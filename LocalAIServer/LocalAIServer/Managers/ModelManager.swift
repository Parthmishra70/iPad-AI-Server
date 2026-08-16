//
//  ModelManager.swift
//  LocalAIServer
//
//  Manages AI model lifecycle: download, install, load, unload, delete
//

import Foundation
import Combine
import LlamaSwift
import CryptoKit

/// Manager for AI model lifecycle operations
@MainActor
class ModelManager: ObservableObject {
    static let shared = ModelManager()
    
    @Published var models: [AIModel] = []
    @Published var activeModelId: String?
    @Published var isLoadingModel: Bool = false
    @Published var currentLoadingModelId: String?
    @Published var isLoadingModels: Bool = false
    
    private let fileManager = FileManager.default
    private var inferenceEngine: InferenceEngineProtocol?
    
    private let userDefaults = UserDefaults.standard
    private let modelStateKey = "savedModelStates"
    
    /// Directory where models are stored
    private var modelsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("Models", isDirectory: true)
    }
    
    init() {
        createModelsDirectoryIfNeeded()
    }
    
    // MARK: - Initialization
    
    func loadSavedModels() {
        isLoadingModels = true
        
        Task {
            let availableModels = AIModel.availableModels
            var loadedModels: [AIModel] = []
            let savedStates = loadModelStates()
            
            for model in availableModels {
                var modelCopy = model
                let modelPath = getModelPath(for: modelCopy)
                
                // Restore saved state if available
                if let savedState = savedStates[model.id] {
                    modelCopy.state = savedState
                    modelCopy.downloadProgress = savedState == .downloaded || savedState == .installed ? 1.0 : 0.0
                }
                
                // Check if file actually exists
                if fileManager.fileExists(atPath: modelPath.path) {
                    if modelCopy.state == .notDownloaded {
                        modelCopy.state = .downloaded
                    }
                    modelCopy.localPath = modelPath.path
                }
                
                loadedModels.append(modelCopy)
            }
            
            await MainActor.run {
                self.models = loadedModels
                self.isLoadingModels = false
            }
            
            if let savedModelId = UserDefaults.standard.string(forKey: "activeModelId") {
                let model = loadedModels.first { $0.id == savedModelId && $0.isDownloaded }
                if let model {
                    await loadModel(model)
                }
            }
        }
    }
    
    private func loadModelStates() -> [String: ModelState] {
        guard let data = userDefaults.data(forKey: modelStateKey),
              let states = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        var result: [String: ModelState] = [:]
        for (id, stateStr) in states {
            if let state = ModelState(rawValue: stateStr) {
                result[id] = state
            }
        }
        return result
    }
    
    private func saveModelStates() {
        var states: [String: String] = [:]
        for model in models {
            if model.state != .notDownloaded {
                states[model.id] = model.state.rawValue
            }
        }
        if let data = try? JSONEncoder().encode(states) {
            userDefaults.set(data, forKey: modelStateKey)
        }
    }
    
    private func createModelsDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: modelsDirectory.path) {
            try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Model Path Management
    
    func getModelPath(for model: AIModel) -> URL {
        return modelsDirectory.appendingPathComponent("\(model.id).gguf")
    }
    
    // MARK: - Download Operations
    
    /// Active download tasks keyed by model id, so pause/cancel can find them.
    private var activeDownloads: [String: URLSessionDownloadTask] = [:]
    /// Resume data produced by cancelled tasks (for true resume support).
    private var resumeData: [String: Data] = [:]
    /// Background URLSession used for downloads (kept alive across cancels).
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = true
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: ModelDownloadDelegate.shared, delegateQueue: nil)
    }()
    
    func downloadModel(_ model: AIModel) async throws {
        guard let url = model.sourceURL else {
            throw ModelError.invalidSourceURL
        }
        
        // Reset error state if re-attempting
        await updateModelState(model.id, state: .downloading, progress: 0.0)
        
        let destinationURL = getModelPath(for: model)
        
        // Track the task so pause/cancel can address it
        let task: URLSessionDownloadTask
        if let data = resumeData.removeValue(forKey: model.id) {
            task = downloadSession.downloadTask(withResumeData: data)
        } else {
            task = downloadSession.downloadTask(with: url)
        }
        task.taskDescription = model.id
        activeDownloads[model.id] = task
        ModelDownloadDelegate.shared.register(modelId: model.id, manager: self)
        task.resume()
        
        // Await completion via a continuation that the delegate resumes
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                ModelDownloadDelegate.shared.attachContinuation(modelId: model.id, continuation: cont, destinationURL: destinationURL, model: model)
            }
        } onCancel: {
            task.cancel()
        }
    }
    
    private func updateModelState(_ modelId: String, state: ModelState, progress: Double? = nil, localPath: URL? = nil, errorMessage: String? = nil) {
        if let index = models.firstIndex(where: { $0.id == modelId }) {
            models[index].state = state
            if let progress = progress {
                models[index].downloadProgress = progress
            }
            if let localPath = localPath {
                models[index].localPath = localPath.path
            }
            if let errorMessage = errorMessage {
                models[index].errorMessage = errorMessage
            }
        }
        saveModelStates()
    }
    
    /// Throttled progress updates from delegate — called every ~50ms during a download.
    func receiveProgress(modelId: String, bytesWritten: Int64, totalBytes: Int64) {
        let progress = totalBytes > 0 ? Double(bytesWritten) / Double(totalBytes) : 0
        if let index = models.firstIndex(where: { $0.id == modelId }) {
            models[index].downloadProgress = progress
        }
    }
    
    /// Called by delegate when a download finishes successfully.
    func receiveCompletion(modelId: String, model: AIModel, tempURL: URL, destinationURL: URL, expectedBytes: Int64, continuation: CheckedContinuation<Void, Error>) {
        activeDownloads.removeValue(forKey: modelId)
        
        // Move file to destination and validate
        Task { [weak self] in
            guard let self else { return }
            do {
                // Remove any prior file so move doesn't fail
                try? FileManager.default.removeItem(at: destinationURL)
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                try await self.validateDownload(model, at: destinationURL, expectedBytes: expectedBytes)
                await self.updateModelState(modelId, state: .installed, progress: 1.0, localPath: destinationURL)
                continuation.resume(returning: ())
            } catch {
                await self.updateModelState(modelId, state: .notDownloaded, errorMessage: error.localizedDescription)
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Called by delegate when a download fails (non-resumable).
    func receiveFailure(modelId: String, error: Error, continuation: CheckedContinuation<Void, Error>) {
        activeDownloads.removeValue(forKey: modelId)
        Task { [weak self] in
            await self?.updateModelState(modelId, state: .notDownloaded, errorMessage: error.localizedDescription)
        }
        continuation.resume(throwing: error)
    }
    
    /// Called by delegate when a download was cancelled and produced resume data.
    func receiveCancel(modelId: String, resumeBytes: Data?, continuation: CheckedContinuation<Void, Error>) {
        activeDownloads.removeValue(forKey: modelId)
        if let resumeBytes {
            resumeData[modelId] = resumeBytes
            Task { [weak self] in
                await self?.updateModelState(modelId, state: .downloading, progress: nil)
            }
        } else {
            Task { [weak self] in
                await self?.updateModelState(modelId, state: .notDownloaded)
            }
        }
        let err = URLError(.cancelled)
        continuation.resume(throwing: err)
    }
    
    func pauseDownload(for model: AIModel) {
        guard let task = activeDownloads[model.id] else { return }
        // cancel(byProducingResumeData:) keeps partial bytes available
        task.cancel(byProducingResumeData: { _ in })
    }
    
    func resumeDownload(for model: AIModel) async throws {
        // If resume data exists, downloadModel will pick it up
        try await downloadModel(model)
    }
    
    func cancelDownload(for model: AIModel) {
        resumeData.removeValue(forKey: model.id)
        activeDownloads[model.id]?.cancel()
        activeDownloads.removeValue(forKey: model.id)
        Task { [weak self] in
            await self?.updateModelState(model.id, state: .notDownloaded)
        }
    }
    
    /// Insert a model (e.g., from a HuggingFace search) into the catalog.
    func addCustomModel(_ model: AIModel) {
        if !models.contains(where: { $0.id == model.id }) {
            models.append(model)
            saveModelStates()
        }
    }
    
    // MARK: - Download Validation
    
    private func validateDownload(_ model: AIModel, at url: URL, expectedBytes: Int64) async throws {
        await updateModelState(model.id, state: .validating)
        
        try await Task.detached(priority: .userInitiated) { [fileSizeGB = model.fileSizeGB, sha256 = model.sha256] in
            let fileManager = FileManager.default
            let attrs = try fileManager.attributesOfItem(atPath: url.path)
            let fileSize = attrs[.size] as? UInt64 ?? 0
            
            // Size check: prefer Content-Length from the HTTP response; fall back to fileSizeGB hint.
            // Tolerance widened to ±10% (HF rounding and a few KiB overhead are normal).
            if expectedBytes > 0 {
                let ratio = Double(fileSize) / Double(expectedBytes)
                if ratio < 0.90 || ratio > 1.10 {
                    throw ModelError.installationFailed
                }
            } else if fileSizeGB > 0 {
                let expectedSize = UInt64(fileSizeGB * 1024 * 1024 * 1024)
                let ratio = Double(fileSize) / Double(expectedSize)
                if ratio < 0.85 || ratio > 1.15 {
                    throw ModelError.installationFailed
                }
            }
            
            // GGUF magic check
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            
            let magic = try handle.read(upToCount: 4) ?? Data()
            guard magic == Data([0x47, 0x47, 0x55, 0x46]) else {
                throw ModelError.installationFailed
            }
            
            // Streaming SHA256 (no full-file load into RAM)
            if let sha256 {
                try handle.seek(toOffset: 0)
                var hasher = SHA256()
                let chunkSize = 4 * 1024 * 1024 // 4 MB
                while true {
                    let data = try handle.read(upToCount: chunkSize) ?? Data()
                    if data.isEmpty { break }
                    hasher.update(data: data)
                }
                let computed = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                if computed.lowercased() != sha256.lowercased() {
                    throw ModelError.installationFailed
                }
            }
        }.value
    }
    
    // MARK: - Model Installation
    
    func installModel(_ model: AIModel) async throws {
        guard model.state == .downloaded else {
            throw ModelError.modelNotDownloaded
        }
        
        let modelPath = getModelPath(for: model)
        guard fileManager.fileExists(atPath: modelPath.path) else {
            throw ModelError.downloadFailed
        }
        
        await updateModelState(model.id, state: .installing)
        
        try await validateDownload(model, at: modelPath, expectedBytes: -1)
    }
    
    // MARK: - Model Loading/Unloading
    
    func loadModel(_ model: AIModel) async {
        guard model.isDownloaded else { return }
        
        await updateModelState(model.id, state: .loading)
        
        await MainActor.run {
            self.isLoadingModel = true
            self.currentLoadingModelId = model.id
        }
        
        do {
            // Unload any previously-loaded engine so its model memory is
            // released before we allocate a new one.
            if let existing = inferenceEngine {
                await existing.unload()
                await MainActor.run { self.inferenceEngine = nil }
            }

            let engine = LlamaCppInferenceEngine()
            try await engine.loadModel(at: getModelPath(for: model))
            
            await MainActor.run {
                self.inferenceEngine = engine
                self.activeModelId = model.id
                self.isLoadingModel = false
                self.currentLoadingModelId = nil
            }
            
            await updateModelState(model.id, state: .loaded)
            
            UserDefaults.standard.set(model.id, forKey: "activeModelId")
        } catch {
            await MainActor.run {
                self.isLoadingModel = false
                self.currentLoadingModelId = nil
            }
            
            await updateModelState(model.id, state: .error, errorMessage: error.localizedDescription)
        }
    }
    
    func unloadModel() async {
        await inferenceEngine?.unload()
        
        await MainActor.run {
            if let activeId = self.activeModelId {
                self.updateModelState(activeId, state: .installed)
            }
            self.activeModelId = nil
            self.inferenceEngine = nil
        }
    }
    
    // MARK: - Model Deletion
    
    func deleteModel(_ model: AIModel) async throws {
        let modelPath = getModelPath(for: model)
        
        if fileManager.fileExists(atPath: modelPath.path) {
            try fileManager.removeItem(at: modelPath)
        }
        
        await updateModelState(model.id, state: .notDownloaded, progress: 0.0, localPath: nil)
        
        if self.activeModelId == model.id {
            await unloadModel()
        }
    }
    
    // MARK: - Inference
    
    func generateResponse(messages: [ChatMessage], temperature: Double, maxTokens: Int) async throws -> String {
        guard let engine = inferenceEngine else {
            throw ModelError.noModelLoaded
        }
        
        let prompt = await formatMessagesForModel(messages, model: activeModel)
        return try await engine.generate(prompt: prompt, temperature: temperature, maxTokens: maxTokens)
    }
    
    func streamResponse(messages: [ChatMessage], temperature: Double, maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        guard let engine = inferenceEngine else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: ModelError.noModelLoaded)
            }
        }
        
        let model = activeModel
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let prompt = await self.formatMessagesForModel(messages, model: model)
                    for try await token in engine.streamGenerate(prompt: prompt, temperature: temperature, maxTokens: maxTokens) {
                        try Task.checkCancellation()
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func formatMessagesForModel(_ messages: [ChatMessage], model: AIModel?) async -> String {
        guard let model = model,
              let modelPtr = getModelPointer(for: model) else {
            return messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
        }
        
        return await Task.detached(priority: .userInitiated) {
            var llamaMessages = [llama_chat_message]()
            for msg in messages {
                var cm = llama_chat_message()
                cm.role = UnsafePointer<CChar>(strdup(msg.role))
                cm.content = UnsafePointer<CChar>(strdup(msg.content))
                llamaMessages.append(cm)
            }
            
            // Get the chat template from the model
            let template = llama_model_chat_template(modelPtr, nil)
            guard template != nil else {
                for m in llamaMessages { free(UnsafeMutableRawPointer(mutating: m.role)); free(UnsafeMutableRawPointer(mutating: m.content)) }
                return messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
            }
            
            // First call to get the required buffer size
            let formattedSize = llama_chat_apply_template(
                template,
                llamaMessages,
                llamaMessages.count,
                true,
                nil,
                0
            )
            
            guard formattedSize >= 0 else {
                for m in llamaMessages { free(UnsafeMutableRawPointer(mutating: m.role)); free(UnsafeMutableRawPointer(mutating: m.content)) }
                return messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
            }
            
            // Allocate buffer and apply template
            var buffer = [CChar](repeating: 0, count: Int(formattedSize) + 1)
            let nWritten = llama_chat_apply_template(
                template,
                llamaMessages,
                llamaMessages.count,
                true,
                &buffer,
                Int32(buffer.count)
            )
            
            for m in llamaMessages { free(UnsafeMutableRawPointer(mutating: m.role)); free(UnsafeMutableRawPointer(mutating: m.content)) }
            
            if nWritten >= 0 {
                return String(cString: buffer)
            }
            
            return messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
        }.value
    }
    
    private func getModelPointer(for model: AIModel) -> OpaquePointer? {
        guard let engine = inferenceEngine as? LlamaCppInferenceEngine else { return nil }
        return engine.getModelPointer()
    }
    
    // MARK: - Active Model
    
    var activeModel: AIModel? {
        guard let id = activeModelId else { return nil }
        return models.first { $0.id == id }
    }
}

// MARK: - Errors

enum ModelError: LocalizedError {
    case invalidSourceURL
    case modelNotDownloaded
    case modelNotInstalled
    case noModelLoaded
    case downloadFailed
    case installationFailed
    case loadingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidSourceURL: return "Invalid model source URL"
        case .modelNotDownloaded: return "Model must be downloaded first"
        case .modelNotInstalled: return "Model must be installed first"
        case .noModelLoaded: return "No model is currently loaded"
        case .downloadFailed: return "Download failed"
        case .installationFailed: return "Installation failed (validation failed)"
        case .loadingFailed: return "Failed to load model"
        }
    }
}

// MARK: - Data Extension for SHA256

extension Data {
    func sha256() -> String {
        let hash = SHA256.hash(data: self)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}