//
//  ModelManager.swift
//  LocalAIServer
//
//  Manages AI model lifecycle: download, install, load, unload, delete
//

import Foundation
import Combine

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
        // Load model states from disk
        // For now, initialize with available models
        models = AIModel.availableModels
        
        // Check which models are already downloaded
        for i in 0..<models.count {
            let modelPath = getModelPath(for: models[i])
            if fileManager.fileExists(atPath: modelPath.path) {
                models[i].state = .downloaded
                models[i].localPath = modelPath.path
            }
        }
        
        // Try to load the last active model
        if let savedModelId = UserDefaults.standard.string(forKey: "activeModelId") {
            if let model = models.first(where: { $0.id == savedModelId && model.isDownloaded }) {
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
        return modelsDirectory.appendingPathComponent("\(model.id).litert-model")
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
            }
        }
        
        let destinationURL = getModelPath(for: model)
        
        // Use URLSession for downloading with progress tracking
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        
        // Move to final destination
        try fileManager.moveItem(at: tempURL, to: destinationURL)
        
        DispatchQueue.main.async {
            if let index = self.models.firstIndex(where: { $0.id == model.id }) {
                self.models[index].state = .downloaded
                self.models[index].downloadProgress = 1.0
                self.models[index].localPath = destinationURL.path
            }
        }
    }
    
    func pauseDownload(for model: AIModel) {
        // Implement pause functionality
    }
    
    func resumeDownload(for model: AIModel) async throws {
        try await downloadModel(model)
    }
    
    func cancelDownload(for model: AIModel) {
        // Implement cancel functionality
    }
    
    // MARK: - Model Installation
    
    func installModel(_ model: AIModel) async throws {
        guard model.state == .downloaded else {
            throw ModelError.modelNotDownloaded
        }
        
        DispatchQueue.main.async {
            if let index = self.models.firstIndex(where: { $0.id == model.id }) {
                self.models[index].state = .installing
            }
        }
        
        // For LiteRT models, installation may involve validation
        // This is a placeholder for actual installation logic
        try await Task.sleep(nanoseconds: 1_000_000_000) // Simulate installation
        
        DispatchQueue.main.async {
            if let index = self.models.firstIndex(where: { $0.id == model.id }) {
                self.models[index].state = .installed
            }
        }
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
            // Initialize inference engine with the model
            let engine = LiteRTInferenceEngine()
            try await engine.loadModel(at: getModelPath(for: model))
            
            DispatchQueue.main.async {
                self.inferenceEngine = engine
                self.activeModelId = model.id
                self.isLoadingModel = false
                self.currentLoadingModelId = nil
                
                if let index = self.models.firstIndex(where: { $0.id == model.id }) {
                    self.models[index].state = .loaded
                }
                
                // Save active model preference
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
            
            // If this was the active model, unload it
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
        
        return try await engine.generate(prompt: formatMessages(messages), 
                                         temperature: temperature, 
                                         maxTokens: maxTokens)
    }
    
    func streamResponse(messages: [ChatMessage], temperature: Double, maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        guard let engine = inferenceEngine else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: ModelError.noModelLoaded)
            }
        }
        
        return engine.streamGenerate(prompt: formatMessages(messages),
                                     temperature: temperature,
                                     maxTokens: maxTokens)
    }
    
    private func formatMessages(_ messages: [ChatMessage]) -> String {
        // Format chat messages into a prompt string
        // This depends on the model's expected format
        return messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
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
        case .installationFailed: return "Installation failed"
        case .loadingFailed: return "Failed to load model"
        }
    }
}
