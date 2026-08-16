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
    case validating = "Validating"
    case invalid = "Invalid"
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
    
    // New fields for GGUF/HuggingFace models
    let provider: String
    let hfRepo: String
    let ggufFilename: String
    let quantization: String
    /// Trained context length from the GGUF metadata. Initialized to the
    /// catalog value (e.g. 4096) but replaced at load time with the real
    /// value read via `llama_model_n_ctx_train`.
    var contextLength: Int
    let sha256: String?
    
    enum ModelFormat: String, Codable {
        case gguf = "GGUF"
    }
    
    init(id: String, name: String, displayName: String, description: String,
         fileSizeGB: Double, requiredRAM: Double, format: ModelFormat,
         sourceURL: URL? = nil,
         provider: String = "", hfRepo: String = "", ggufFilename: String = "",
         quantization: String = "", contextLength: Int = 2048, sha256: String? = nil) {
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
        self.provider = provider
        self.hfRepo = hfRepo
        self.ggufFilename = ggufFilename
        self.quantization = quantization
        self.contextLength = contextLength
        self.sha256 = sha256
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
    /// Qwen2.5-1.5B-Instruct Q4_K_M - Default model for iPad
    static let qwen2_5_1_5B = AIModel(
        id: "qwen2.5-1.5b-instruct-q4_k_m",
        name: "qwen2.5-1.5b-instruct",
        displayName: "Qwen2.5-1.5B-Instruct (Q4_K_M)",
        description: "Qwen2.5 1.5B parameter instruction-tuned model. Excellent balance of speed and quality for iPad. Q4_K_M quantization fits in ~3GB RAM.",
        fileSizeGB: 1.1,
        requiredRAM: 3.0,
        format: .gguf,
        sourceURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"),
        provider: "Qwen",
        hfRepo: "Qwen/Qwen2.5-1.5B-Instruct-GGUF",
        ggufFilename: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
        quantization: "Q4_K_M",
        contextLength: 4096,
        sha256: "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
    )
    
    /// Qwen2.5-3B-Instruct Q4_K_M - Higher quality, needs M-series iPad
    static let qwen2_5_3B = AIModel(
        id: "qwen2.5-3b-instruct-q4_k_m",
        name: "qwen2.5-3b-instruct",
        displayName: "Qwen2.5-3B-Instruct (Q4_K_M)",
        description: "Qwen2.5 3B parameter model. Better reasoning, requires iPad with 6GB+ RAM (M-series).",
        fileSizeGB: 2.0,
        requiredRAM: 5.0,
        format: .gguf,
        sourceURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf"),
        provider: "Qwen",
        hfRepo: "Qwen/Qwen2.5-3B-Instruct-GGUF",
        ggufFilename: "qwen2.5-3b-instruct-q4_k_m.gguf",
        quantization: "Q4_K_M",
        contextLength: 4096,
        sha256: nil
    )
    
    /// Llama-3.2-3B-Instruct Q4_K_M - Llama family alternative
    static let llama3_2_3B = AIModel(
        id: "llama-3.2-3b-instruct-q4_k_m",
        name: "llama-3.2-3b-instruct",
        displayName: "Llama-3.2-3B-Instruct (Q4_K_M)",
        description: "Meta's Llama 3.2 3B instruction-tuned model. Strong general capabilities, requires 6GB+ RAM.",
        fileSizeGB: 2.0,
        requiredRAM: 5.0,
        format: .gguf,
        sourceURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"),
        provider: "Meta",
        hfRepo: "bartowski/Llama-3.2-3B-Instruct-GGUF",
        ggufFilename: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
        quantization: "Q4_K_M",
        contextLength: 4096,
        sha256: nil
    )
    
    /// List of all available models
    static let availableModels: [AIModel] = [
        .qwen2_5_1_5B,
        .qwen2_5_3B,
        .llama3_2_3B
    ]

    /// Build an AIModel from a HuggingFace repo + a chosen GGUF file.
    /// Used by the live search in ModelsView when the user picks a custom model.
    static func fromHuggingFace(repoId: String, file: HuggingFaceFile) -> AIModel {
        let sizeGB = file.sizeGB ?? 0
        // RAM heuristic: GGUF Q4 ≈ file size * 1.5 for weights + KV cache.
        let requiredRAM = max(2.0, (sizeGB * 1.5).rounded(.up))
        let sanitizedId = "\(repoId.replacingOccurrences(of: "/", with: "_"))__\(file.filename)"
            .replacingOccurrences(of: ".gguf", with: "")
        let author = repoId.split(separator: "/").first.map(String.init) ?? ""
        let description = "\(file.filename) (\(file.quantization)) — \(String(format: "%.2f GB", sizeGB)) from \(repoId)"
        return AIModel(
            id: sanitizedId,
            name: file.filename,
            displayName: "\(repoId.split(separator: "/").last.map(String.init) ?? repoId) (\(file.quantization))",
            description: description,
            fileSizeGB: sizeGB,
            requiredRAM: requiredRAM,
            format: .gguf,
            sourceURL: HuggingFaceService.shared.resolveDownload(repoId: repoId, filename: file.filename),
            provider: author,
            hfRepo: repoId,
            ggufFilename: file.filename,
            quantization: file.quantization,
            contextLength: 4096,
            sha256: nil
        )
    }
}