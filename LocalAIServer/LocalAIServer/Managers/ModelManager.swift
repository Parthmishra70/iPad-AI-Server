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
    /// IDs of built-in models from `AIModel.availableModels`. Persisted
    /// custom HF models use these to distinguish from built-ins.
    private let builtInIds = Set(AIModel.availableModels.map { $0.id })
    
    /// Directory where models are stored
    private var modelsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("Models", isDirectory: true)
    }
    
    init() {
        createModelsDirectoryIfNeeded()
    }
    
    // MARK: - Initialization
    
    func loadSavedModels() async {
        isLoadingModels = true

        // Body is async — no inner Task wrapper. Callers can `await` and
        // actually wait for the catalog to be rehydrated (used by
        // Dashboard refreshable + app startup TaskGroup).
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

        // Rehydrate custom (HF-sourced) models. Their metadata lives in
        // UserDefaults; their on-disk file presence + savedStates drive
        // the visible state, same as built-ins.
        for var customModel in loadCustomModels() {
            let modelPath = getModelPath(for: customModel)

            if let savedState = savedStates[customModel.id] {
                customModel.state = savedState
                customModel.downloadProgress = savedState == .downloaded || savedState == .installed ? 1.0 : 0.0
            }

            if fileManager.fileExists(atPath: modelPath.path) {
                if customModel.state == .notDownloaded {
                    customModel.state = .downloaded
                }
                customModel.localPath = modelPath.path
            } else if customModel.state != .downloading {
                // File is gone but the entry is persisted — reset.
                customModel.state = .notDownloaded
                customModel.downloadProgress = 0.0
                customModel.localPath = nil
            }

            loadedModels.append(customModel)
        }

        self.models = loadedModels
        self.isLoadingModels = false

        if let savedModelId = UserDefaults.standard.string(forKey: "activeModelId") {
            let model = loadedModels.first { $0.id == savedModelId && $0.isDownloaded }
            if let model {
                await loadModel(model)
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

    // MARK: - Custom HF Model Persistence

    /// Load all custom (non-built-in) models the user previously added via
    /// HuggingFace search. Returns them in their persisted state; the caller
    /// merges in downloaded-file checks before displaying.
    private func loadCustomModels() -> [AIModel] {
        guard let data = userDefaults.data(forKey: AppConstants.UserDefaultsKeys.customModels) else {
            return []
        }
        guard let dict = try? JSONDecoder().decode([String: Data].self, from: data) else {
            return []
        }
        var result: [AIModel] = []
        for (_, modelData) in dict {
            if let model = try? JSONDecoder().decode(AIModel.self, from: modelData) {
                result.append(model)
            }
        }
        return result
    }

    /// Re-encode the full set of custom models back to UserDefaults. Called
    /// after `addCustomModel`, `deleteModel`, or `updateModelState` when a
    /// custom model's metadata (e.g. contextLength discovered at load time)
    /// has changed.
    private func saveCustomModels() {
        var dict: [String: Data] = [:]
        for model in models where !builtInIds.contains(model.id) {
            if let data = try? JSONEncoder().encode(model) {
                dict[model.id] = data
            }
        }
        if let data = try? JSONEncoder().encode(dict) {
            userDefaults.set(data, forKey: AppConstants.UserDefaultsKeys.customModels)
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

    /// On-disk location for resume data produced by a cancelled download.
    /// Stored as a hidden file `<Models>/.<id>.resume` so partial download
    /// state survives app crashes/relaunches. Deleted on successful
    /// completion or explicit cancel.
    private func resumeDataPath(for modelId: String) -> URL {
        modelsDirectory.appendingPathComponent(".\(modelId).resume")
    }

    /// Persist resume data to disk so it survives app restarts.
    private func saveResumeData(_ data: Data, for modelId: String) {
        do {
            try data.write(to: resumeDataPath(for: modelId), options: .atomic)
        } catch {
            print("Failed to persist resume data for \(modelId): \(error)")
        }
    }

    /// Read any on-disk resume data for `modelId`. Returns nil if none
    /// exists or the file can't be read.
    private func loadResumeData(for modelId: String) -> Data? {
        let url = resumeDataPath(for: modelId)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Persist the in-memory resumeData dict to disk for ALL models that
    /// currently have resume data. Called from receiveCancel.
    private func flushAllResumeData() {
        for (modelId, data) in resumeData {
            saveResumeData(data, for: modelId)
        }
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
        // Prefer in-memory resume data; fall back to disk-persisted data
        // left over from a prior session (app crashed, force-quit, etc.).
        let data = resumeData.removeValue(forKey: model.id) ?? loadResumeData(for: model.id)
        if let data {
            task = downloadSession.downloadTask(withResumeData: data)
            // Once we've handed the bytes to URLSession, the on-disk copy
            // is redundant — remove it. If this download fails/cancels
            // again we'll write a fresh file.
            let resumeFile = resumeDataPath(for: model.id)
            if fileManager.fileExists(atPath: resumeFile.path) {
                try? fileManager.removeItem(at: resumeFile)
            }
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
        // Download is done — discard any stale resume data, on-disk or in-memory.
        resumeData.removeValue(forKey: modelId)
        let resumeFile = resumeDataPath(for: modelId)
        if fileManager.fileExists(atPath: resumeFile.path) {
            try? fileManager.removeItem(at: resumeFile)
        }

        // Move file to destination and validate
        Task { [weak self] in
            guard let self else { return }
            do {
                // Remove any prior file so move doesn't fail
                try? FileManager.default.removeItem(at: destinationURL)
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                try await self.validateDownload(model, at: destinationURL, expectedBytes: expectedBytes)
                await self.updateModelState(modelId, state: .installed, progress: 1.0, localPath: destinationURL)

                // Surface a toast so the user knows the download finished
                // even if they've wandered off to another tab. The toast
                // is sticky (no auto-dismiss) since it carries an action
                // the user may want to invoke later.
                ToastCenter.shared.show(
                    ToastMessage(
                        title: "Download complete",
                        detail: "\(model.displayName) is ready to load.",
                        systemImage: "checkmark.circle.fill",
                        tint: .green,
                        actionLabel: "Load & Chat",
                        action: { [weak self] in
                            guard let self else { return }
                            Task {
                                await self.loadModel(model)
                                await MainActor.run {
                                    ToastCenter.shared.dismiss()
                                    AppRouter.shared.requestSwitch(to: .chat)
                                }
                            }
                        }
                    ),
                    sticky: true
                )

                continuation.resume(returning: ())
            } catch {
                await self.updateModelState(modelId, state: .notDownloaded, errorMessage: error.localizedDescription)

                ToastCenter.shared.show(
                    ToastMessage(
                        title: "Download failed",
                        detail: error.localizedDescription,
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .red,
                        actionLabel: nil,
                        action: nil
                    )
                )

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
            // Persist to memory AND disk so resume survives app relaunch.
            resumeData[modelId] = resumeBytes
            saveResumeData(resumeBytes, for: modelId)
            Task { [weak self] in
                await self?.updateModelState(modelId, state: .downloading, progress: nil)
            }
        } else {
            // No resume data — clean up any stale on-disk file too.
            resumeData.removeValue(forKey: modelId)
            let resumeFile = resumeDataPath(for: modelId)
            if fileManager.fileExists(atPath: resumeFile.path) {
                try? fileManager.removeItem(at: resumeFile)
            }
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
        // Also remove the on-disk resume file so a relaunch doesn't try to
        // resume a model the user explicitly cancelled.
        let resumeFile = resumeDataPath(for: model.id)
        if fileManager.fileExists(atPath: resumeFile.path) {
            try? fileManager.removeItem(at: resumeFile)
        }
        activeDownloads[model.id]?.cancel()
        activeDownloads.removeValue(forKey: model.id)
        Task { [weak self] in
            await self?.updateModelState(model.id, state: .notDownloaded)
        }
    }
    
    /// Insert a model (e.g., from a HuggingFace search) into the catalog
    /// and persist it across launches via UserDefaults.
    func addCustomModel(_ model: AIModel) {
        if !models.contains(where: { $0.id == model.id }) {
            models.append(model)
        } else if let idx = models.firstIndex(where: { $0.id == model.id }) {
            // Already present — refresh metadata in case the user re-added it.
            models[idx] = model
        }
        saveCustomModels()
        saveModelStates()
    }
    
    // MARK: - Download Validation

    /// Compute total bytes in the Models directory and the device's free
    /// disk space. Used by the storage usage card on the Dashboard.
    struct StorageUsage {
        let usedBytes: Int64
        let freeBytes: Int64
        var usedGB: Double { Double(usedBytes) / 1_073_741_824 }
        var freeGB: Double { Double(freeBytes) / 1_073_741_824 }
        var totalGB: Double { usedGB + freeGB }
        /// 0.0..1.0 — fraction of total disk used by downloaded models.
        var pressure: Double {
            guard totalGB > 0 else { return 0 }
            return min(1.0, usedGB / totalGB)
        }
    }

    func storageUsage() -> StorageUsage {
        var used: Int64 = 0
        if let contents = try? fileManager.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for url in contents where url.pathExtension == "gguf" {
                if let attrs = try? url.resourceValues(forKeys: [.fileSizeKey]),
                   let size = attrs.fileSize {
                    used += Int64(size)
                }
            }
        }
        let free: Int64
        if let attrs = try? modelsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let freeFromVolume = attrs.volumeAvailableCapacityForImportantUsage {
            free = Int64(freeFromVolume)
        } else {
            free = 0
        }
        return StorageUsage(usedBytes: used, freeBytes: free)
    }

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

        // Don't kick off a second concurrent load of the same model
        // (e.g. user taps "Load Model" in the sticky sheet AND taps
        // "Load & Chat" on the post-download toast). The class is
        // @MainActor so these property reads are already isolated.
        if isLoadingModel, currentLoadingModelId == model.id {
            return
        }

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
            // Load the model and read the real trained context length back
            // from the GGUF metadata. We use it to update AIModel.contextLength
            // (which may have been a guess of 4096 at add time) and persist
            // the corrected value for custom HF models.
            let trainedNCtx = try await engine.loadModel(at: getModelPath(for: model))

            await MainActor.run {
                // Patch the catalog entry with the real context length.
                if let idx = self.models.firstIndex(where: { $0.id == model.id }),
                   self.models[idx].contextLength != trainedNCtx,
                   trainedNCtx > 0 {
                    self.models[idx].contextLength = trainedNCtx
                    // If it's a custom (HF-added) model, the corrected value
                    // is persisted to UserDefaults so the next launch sees it.
                    if !self.builtInIds.contains(model.id) {
                        self.saveCustomModels()
                    }
                }

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

        // Clean up any leftover resume data for this model too.
        resumeData.removeValue(forKey: model.id)
        let resumeFile = resumeDataPath(for: model.id)
        if fileManager.fileExists(atPath: resumeFile.path) {
            try? fileManager.removeItem(at: resumeFile)
        }

        // For custom (non-built-in) models, remove the persisted entry too
        // so it doesn't reappear on next launch as an orphan row.
        if !builtInIds.contains(model.id) {
            models.removeAll { $0.id == model.id }
            saveCustomModels()
        } else {
            await updateModelState(model.id, state: .notDownloaded, progress: 0.0, localPath: nil)
        }

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

    /// The most recently completed model that is downloaded but NOT
    /// currently loaded. Used by ChatView's idle card to suggest
    /// "Load & Chat with this" when the user has at least one model
    /// installed but no model is currently active.
    var recentlyDownloadedModel: AIModel? {
        // Prefer models whose state is .installed or .loaded-but-not-active.
        // We sort by id reversely since HF-sourced models are appended to
        // the catalog and built-ins come first; later additions = more recent.
        let candidates = models.filter { m in
            (m.state == .installed || m.state == .downloaded) && m.id != activeModelId
        }
        return candidates.last
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