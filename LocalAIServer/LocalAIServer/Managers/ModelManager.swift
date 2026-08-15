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
    
    private let fileManager = FileManager.default
    private var inferenceEngine: InferenceEngineProtocol?
    
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
        models = AIModel.availableModels
        
        for i in 0..<models.count {
            let modelPath = getModelPath(for: models[i])
            if fileManager.fileExists(atPath: modelPath.path) {
                models[i].state = .downloaded
                models[i].localPath = modelPath.path
            }
        }
        
        if let savedModelId = UserDefaults.standard.string(forKey: "activeModelId") {
            let model = models.first { $0.id == savedModelId && $0.isDownloaded }
            if let model {
                Task {
                    await loadModel(model)
                }
            }
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
    
    func downloadModel(_ model: AIModel) async throws {
        guard let url = model.sourceURL else {
            throw ModelError.invalidSourceURL
        }
        
        DispatchQueue.main.async {
            if let index = self.models.firstIndex(where: { $0.id == model.id }) {
                self.models[index].state = .downloading
                self.models[index].downloadProgress = 0.0
                self.models[index].errorMessage = nil
            }
        }
        
        let destinationURL = getModelPath(for: model)
        
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        
        if let httpResponse = response as? HTTPURLResponse {
            guard httpResponse.statusCode == 200 else {
                throw ModelError.downloadFailed
            }
        }
        
        try fileManager.moveItem(at: tempURL, to: destinationURL)
        
        // Validate the downloaded file
        try await validateDownload(model, at: destinationURL)
        
        DispatchQueue.main.async {
            if let index = self.models.firstIndex(where: { $0.id == model.id }) {
                self.models[index].state = .downloaded
                self.models[index].downloadProgress = 1.0
                self.models[index].localPath = destinationURL.path
            }
        }
    }
    
    func pauseDownload(for model: AIModel) {
    }
    
    func resumeDownload(for model: AIModel) async throws {
        try await downloadModel(model)
    }
    
    func cancelDownload(for model: AIModel) {
    }
    
    // MARK: - Download Validation
    
    private func validateDownload(_ model: AIModel, at url: URL) async throws {
        DispatchQueue.main.async {
            if let index = self.models.firstIndex(where: { $0.id == model.id }) {
                self.models[index].state = .validating
            }
        }
        
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let attrs = try fileManager.attributesOfItem(atPath: url.path)
            let fileSize = attrs[.size] as? UInt64 ?? 0
            let expectedSize = UInt64(model.fileSizeGB * 1024 * 1024 * 1024)
            
            if expectedSize > 0 {
                let ratio = Double(fileSize) / Double(expectedSize)
                if ratio < 0.98 || ratio > 1.02 {
                    throw ModelError.installationFailed
                }
            }
            
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            
            let magic = try handle.read(upToCount: 4) ?? Data()
            guard magic == Data([0x47, 0x47, 0x55, 0x46]) else {
                throw ModelError.installationFailed
            }
            
            if let sha256 = model.sha256 {
                let data = try Data(contentsOf: url)
                let computed = data.sha256()
                if computed.lowercased() != sha256.lowercased() {
                    throw ModelError.installationFailed
                }
            }
        }.value
        
        DispatchQueue.main.async {
            if let index = self.models.firstIndex(where: { $0.id == model.id }) {
                self.models[index].state = .installed
            }
        }
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
        
        DispatchQueue.main.async {
            if let index = self.models.firstIndex(where: { $0.id == model.id }) {
                self.models[index].state = .installing
            }
        }
        
        try await validateDownload(model, at: modelPath)
    }
    
    // MARK: - Model Loading/Unloading
    
    func loadModel(_ model: AIModel) async {
        guard model.isDownloaded else { return }
        
        DispatchQueue.main.async {
            self.isLoadingModel = true
            self.currentLoadingModelId = model.id
            if let index = self.models.firstIndex(where: { $0.id == model.id }) {
                self.models[index].state = .loading
            }
        }
        
        do {
            let engine = LlamaCppInferenceEngine()
            try await engine.loadModel(at: getModelPath(for: model))
            
            DispatchQueue.main.async {
                self.inferenceEngine = engine
                self.activeModelId = model.id
                self.isLoadingModel = false
                self.currentLoadingModelId = nil
                
                if let index = self.models.firstIndex(where: { $0.id == model.id }) {
                    self.models[index].state = .loaded
                }
                
                UserDefaults.standard.set(model.id, forKey: "activeModelId")
            }
        } catch {
            DispatchQueue.main.async {
                self.isLoadingModel = false
                self.currentLoadingModelId = nil
                if let index = self.models.firstIndex(where: { $0.id == model.id }) {
                    self.models[index].state = .error
                    self.models[index].errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func unloadModel() async {
        await inferenceEngine?.unload()
        
        DispatchQueue.main.async {
            if let index = self.models.firstIndex(where: { $0.id == self.activeModelId }) {
                self.models[index].state = .installed
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
        
        DispatchQueue.main.async {
            if let index = self.models.firstIndex(where: { $0.id == model.id }) {
                self.models[index].state = .notDownloaded
                self.models[index].localPath = nil
                self.models[index].downloadProgress = 0.0
            }
            
            if self.activeModelId == model.id {
                Task {
                    await self.unloadModel()
                }
            }
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
              let modelPtr = await getModelPointer(for: model) else {
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
    
    private func getModelPointer(for model: AIModel) async -> OpaquePointer? {
        guard let engine = inferenceEngine as? LlamaCppInferenceEngine else { return nil }
        return await engine.getModelPointer()
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