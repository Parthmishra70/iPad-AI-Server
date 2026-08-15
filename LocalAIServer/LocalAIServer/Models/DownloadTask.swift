//
//  DownloadTask.swift
//  LocalAIServer
//
//  Manages model download tasks with progress tracking and resume capability
//

import Foundation

/// Tracks the state of a model download
class DownloadTask: ObservableObject, Identifiable {
    let id: String
    let modelId: String
    let url: URL
    let destinationURL: URL
    
    @Published var state: DownloadState = .pending
    @Published var progress: Double = 0.0
    @Published var downloadedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var speed: Double = 0.0 // bytes per second
    @Published var estimatedTimeRemaining: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var canResume: Bool = false
    
    var downloadTask: URLSessionDownloadTask?
    
    enum DownloadState: String {
        case pending = "Pending"
        case downloading = "Downloading"
        case paused = "Paused"
        case completed = "Completed"
        case failed = "Failed"
        case cancelled = "Cancelled"
    }
    
    init(modelId: String, url: URL, destinationURL: URL) {
        self.id = UUID().uuidString
        self.modelId = modelId
        self.url = url
        self.destinationURL = destinationURL
    }
    
    /// Formatted progress percentage
    var progressPercentage: String {
        return String(format: "%.1f%%", progress * 100)
    }
    
    /// Formatted downloaded size
    var formattedDownloadedSize: String {
        return ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
    }
    
    /// Formatted total size
    var formattedTotalSize: String {
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
    
    /// Formatted speed
    var formattedSpeed: String {
        if speed > 0 {
            return "\(ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file))/s"
        }
        return "--"
    }
    
    /// Formatted estimated time remaining
    var formattedETARemaining: String {
        if estimatedTimeRemaining > 0 {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.minute, .second]
            formatter.unitsStyle = .abbreviated
            return formatter.string(from: estimatedTimeRemaining) ?? "--"
        }
        return "--"
    }
}

/// Manager for active download tasks
class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    
    private var tasks: [String: DownloadTask] = [:]
    private var urlSession: URLSession?
    
    override init() {
        super.init()
        setupURLSession()
    }
    
    private func setupURLSession() {
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.localaiserver.background")
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
    
    func getTask(for modelId: String) -> DownloadTask? {
        return tasks[modelId]
    }
    
    func startDownload(for model: AIModel, to destination: URL) async -> DownloadTask? {
        guard let url = model.sourceURL else { return nil }
        
        let task = DownloadTask(modelId: model.id, url: url, destinationURL: destination)
        await MainActor.run {
            tasks[model.id] = task
        }
        
        guard let session = urlSession else { return nil }
        
        let downloadTask = session.downloadTask(with: url)
        task.downloadTask = downloadTask
        downloadTask.resume()
        
        return task
    }
    
    func pauseDownload(for modelId: String) {
        guard let task = tasks[modelId]?.downloadTask else { return }
        task.cancel { [weak self] (_) in
            guard let self else { return }
            self.tasks[modelId]?.state = .paused
            self.tasks[modelId]?.canResume = true
        }
    }
    
    func resumeDownload(for modelId: String) {
        guard let task = tasks[modelId], task.canResume else { return }
        task.state = .downloading
    }
    
    func cancelDownload(for modelId: String) {
        tasks[modelId]?.downloadTask?.cancel()
        tasks[modelId]?.state = .cancelled
    }
    
    func removeTask(for modelId: String) {
        tasks.removeValue(forKey: modelId)
    }
}

// MARK: - URLSessionDownloadDelegate
extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, 
                                 didFinishDownloadingTo location: URL) {
        Task {
            await handleDownloadCompletion(location: location, task: downloadTask)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, 
                                 didWriteData bytesWritten: Int64, totalBytesWritten: Int64, 
                                 totalBytesExpectedToWrite: Int64) {
        Task {
            await updateProgress(task: downloadTask, written: totalBytesWritten, total: totalBytesExpectedToWrite)
        }
    }
    
    private func handleDownloadCompletion(location: URL, task: URLSessionDownloadTask) async {
        // Find the corresponding DownloadTask
        // Move file from temporary location to final destination
    }
    
    private func updateProgress(task: URLSessionDownloadTask, written: Int64, total: Int64) async {
        // Update progress on the corresponding DownloadTask
    }
}
