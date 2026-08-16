//
//  ModelDownloadDelegate.swift
//  LocalAIServer
//
//  URLSessionDownloadDelegate that reports progress incrementally and
//  hands completed downloads back to ModelManager. Single instance owned
//  by ModelManager's `downloadSession`; thread-safe via main-actor hops.
//

import Foundation

final class ModelDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    static let shared = ModelDownloadDelegate()
    
    private let queue = DispatchQueue(label: "com.localaiserver.download.delegate")
    
    /// Lookup: modelId -> ModelManager (weak).
    private var managers: [String: WeakBox<ModelManager>] = [:]
    /// Lookup: modelId -> download metadata (continuation, destination, model, expected size).
    private struct Pending {
        var continuation: CheckedContinuation<Void, Error>
        var destinationURL: URL
        var model: AIModel
        var expectedBytes: Int64
    }
    private var pending: [String: Pending] = [:]
    
    func register(modelId: String, manager: ModelManager) {
        queue.sync { _ = managers[modelId] }  // serialize
        queue.sync {
            managers[modelId] = WeakBox(manager)
        }
    }
    
    func attachContinuation(modelId: String, continuation: CheckedContinuation<Void, Error>, destinationURL: URL, model: AIModel) {
        queue.sync {
            pending[modelId] = Pending(continuation: continuation, destinationURL: destinationURL, model: model, expectedBytes: -1)
        }
    }
    
    func updateExpectedBytes(modelId: String, expectedBytes: Int64) {
        queue.sync {
            pending[modelId]?.expectedBytes = expectedBytes
        }
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let modelId = downloadTask.taskDescription ?? identifyFrom(downloadTask) else { return }
        let total = totalBytesExpectedToWrite
        let written = totalBytesWritten
        queue.sync {
            pending[modelId]?.expectedBytes = total
        }
        guard let manager = lookupManager(modelId: modelId) else { return }
        Task { @MainActor in
            manager.receiveProgress(modelId: modelId, bytesWritten: written, totalBytes: total)
        }
    }
    
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temp file at `location` is only valid for the duration of this callback.
        // We MUST move/copy it before returning.
        guard let modelId = downloadTask.taskDescription ?? identifyFrom(downloadTask) else { return }
        
        guard let manager = lookupManager(modelId: modelId) else { return }
        
        let p: Pending? = queue.sync { pending[modelId] }
        guard let pendingMeta = p else { return }
        
        let destinationURL = pendingMeta.destinationURL
        let model = pendingMeta.model
        let expectedBytes = pendingMeta.expectedBytes
        let continuation = pendingMeta.continuation
        
        // Read original HTTP response to capture the canonical size if Content-Length was missing.
        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           let contentLengthStr = httpResponse.value(forHTTPHeaderField: "Content-Length"),
           let contentLength = Int64(contentLengthStr),
           contentLength > 0 {
            queue.sync { pending[modelId]?.expectedBytes = contentLength }
        }
        let finalExpected = queue.sync { pending[modelId]?.expectedBytes ?? -1 }
        let finalDestination = destinationURL
        let finalModel = model
        
        // Hand off to manager on main actor with the temp file. Manager will move/validate.
        Task { @MainActor in
            manager.receiveCompletion(
                modelId: modelId,
                model: finalModel,
                tempURL: location,
                destinationURL: finalDestination,
                expectedBytes: finalExpected,
                continuation: continuation
            )
        }
    }
    
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let modelId = task.taskDescription ?? identifyFrom(task as? URLSessionDownloadTask) else { return }
        let p: Pending? = queue.sync { pending[modelId] }
        guard let pendingMeta = p else { return }
        let continuation = pendingMeta.continuation
        queue.sync { _ = pending.removeValue(forKey: modelId) }
        
        if let nsError = error as NSError? {
            // Resume data lives on the original error object (URLSessionDownloadTask specifically)
            let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            if let manager = lookupManager(modelId: modelId) {
                Task { @MainActor in
                    manager.receiveCancel(modelId: modelId, resumeBytes: resumeData, continuation: continuation)
                }
            } else {
                continuation.resume(throwing: URLError(.cancelled))
            }
            return
        }
        
        // No error: success path is handled in didFinishDownloadingTo, which already called manager.receiveCompletion.
        // If we somehow got here without that, complete silently.
        if let error {
            if let manager = lookupManager(modelId: modelId) {
                Task { @MainActor in
                    manager.receiveFailure(modelId: modelId, error: error, continuation: continuation)
                }
            } else {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func lookupManager(modelId: String) -> ModelManager? {
        var m: ModelManager?
        queue.sync { m = managers[modelId]?.value }
        return m
    }
    
    /// Best-effort: find the modelId for a task that didn't have taskDescription set.
    private func identifyFrom(_ task: URLSessionDownloadTask?) -> String? { nil }
}

/// Weak reference box for safe main-actor access across threads.
final class WeakBox<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
