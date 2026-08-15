//
//  AIModel.swift
//  LocalAIServer
//
//  Model data structures for AI models
//

import Foundation

/// Represents the state of a model
enum ModelState: String, Codable {
    case notDownloaded = "Not Downloaded"
    case downloading = "Downloading"
    case downloaded = "Downloaded"
    case installing = "Installing"
    case installed = "Installed"
    case loading = "Loading"
    case loaded = "Loaded"
    case error = "Error"
    case unavailable = "Unavailable"
}

/// Represents a compatible AI model that can be downloaded and used
struct AIModel: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let displayName: String
    let description: String
    let fileSizeGB: Double
    let requiredRAM: Double // in GB
    let format: ModelFormat
    let sourceURL: URL?
    var state: ModelState
    var localPath: String?
    var downloadProgress: Double // 0.0 to 1.0
    var errorMessage: String?
    
    enum ModelFormat: String, Codable {
        case tflite = "TFLite"
        case mlmodel = "CoreML"
        case safetensors = "SafeTensors"
    }
    
    init(id: String, name: String, displayName: String, description: String, 
         fileSizeGB: Double, requiredRAM: Double, format: ModelFormat, 
         sourceURL: URL? = nil) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.fileSizeGB = fileSizeGB
        self.requiredRAM = requiredRAM
        self.format = format
        self.sourceURL = sourceURL
        self.state = .notDownloaded
        self.localPath = nil
        self.downloadProgress = 0.0
        self.errorMessage = nil
    }
    
    /// Check if model can be loaded for inference
    var isReadyForInference: Bool {
        return state == .loaded
    }
    
    /// Check if model is available locally
    var isDownloaded: Bool {
        return state == .downloaded || state == .installed || state == .loading || state == .loaded
    }
    
    /// Formatted file size string
    var formattedFileSize: String {
        if fileSizeGB >= 1 {
            return String(format: "%.1f GB", fileSizeGB)
        } else {
            return String(format: "%.0f MB", fileSizeGB * 1024)
        }
    }
    
    /// Formatted RAM requirement string
    var formattedRAMRequirement: String {
        return String(format: "%.1f GB", requiredRAM)
    }
    
    /// Formatted progress percentage string
    var progressPercentage: String {
        return String(format: "%.1f%%", downloadProgress * 100)
    }
    
    /// Formatted downloaded size string
    var formattedDownloadedSize: String {
        let bytes = Int64(downloadProgress * Double(fileSizeGB) * 1024 * 1024 * 1024)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    /// Formatted total size string
    var formattedTotalSize: String {
        let bytes = Int64(fileSizeGB * 1024 * 1024 * 1024)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Extension for predefined models
extension AIModel {
    /// Gemma 2B - Small, fast model suitable for most iPads
    static let gemma2B = AIModel(
        id: "gemma-2b",
        name: "gemma",
        displayName: "Gemma 2B",
        description: "Google's lightweight 2B parameter model. Good balance of speed and quality.",
        fileSizeGB: 1.5,
        requiredRAM: 4.0,
        format: .tflite,
        sourceURL: URL(string: "https://huggingface.co/google/gemma-2b-it-litert/resolve/main/gemma-2b-it-litert.litert-model")
    )
    
    /// Gemma 3B - Medium sized model
    static let gemma3B = AIModel(
        id: "gemma-3b",
        name: "gemma-3b",
        displayName: "Gemma 3B",
        description: "Enhanced 3B parameter model with better reasoning capabilities.",
        fileSizeGB: 2.5,
        requiredRAM: 6.0,
        format: .tflite,
        sourceURL: URL(string: "https://huggingface.co/google/gemma-3b-it-litert/resolve/main/gemma-3b-it-litert.litert-model")
    )
    
    /// Phi-3 Mini - Microsoft's efficient small model
    static let phi3Mini = AIModel(
        id: "phi-3-mini",
        name: "phi-3-mini",
        displayName: "Phi-3 Mini (3.8B)",
        description: "Microsoft's compact model with strong performance for its size.",
        fileSizeGB: 2.3,
        requiredRAM: 6.0,
        format: .tflite,
        sourceURL: URL(string: "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-liteRT/resolve/main/Phi-3-mini-4k-instruct-liteRT.litert-model")
    )
    
    /// List of all available models
    static let availableModels: [AIModel] = [
        .gemma2B,
        .gemma3B,
        .phi3Mini
    ]
}
