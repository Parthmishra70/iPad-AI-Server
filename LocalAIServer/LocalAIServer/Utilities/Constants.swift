//
//  Constants.swift
//  LocalAIServer
//
//  App-wide constants and configuration
//

import Foundation

/// Application-wide constants
enum AppConstants {
    /// Default server port
    static let defaultPort = 8080
    
    /// Minimum allowed port
    static let minPort = 1024
    
    /// Maximum allowed port
    static let maxPort = 65535
    
    /// Recommended port range to avoid conflicts
    static let recommendedPortRange = 8000...9000
    
    /// Maximum concurrent connections
    static let maxConnections = 10
    
    /// Request timeout in seconds
    static let requestTimeout: TimeInterval = 30
    
    /// Maximum tokens for generation
    static let maxTokens = 2048
    
    /// Default temperature for inference
    static let defaultTemperature: Double = 0.7
    
    /// Temperature range
    static let temperatureRange: ClosedRange<Double> = 0.0...2.0
    
    /// Models directory name
    static let modelsDirectoryName = "Models"
    
    /// API key prefix
    static let apiKeyPrefix = "sk-local-"
    
    /// App group identifier (for shared data)
    static let appGroupIdentifier = "group.com.localaiserver.app"
    
    /// User defaults keys
    enum UserDefaultsKeys {
        static let serverPort = "serverPort"
        static let activeModelId = "activeModelId"
        static let showAdvancedSettings = "showAdvancedSettings"
        static let enableLogging = "enableLogging"
        static let apiKey = "apiKey"
        /// Persisted dictionary of `[modelId: encoded AIModel]` for models
        /// the user added from HuggingFace search. Built-in models live in
        /// `AIModel.availableModels` and are NOT re-serialized here.
        static let customModels = "customModels"
    }
    
    /// Notification names
    enum Notifications {
        static let serverDidStart = Notification.Name("serverDidStart")
        static let serverDidStop = Notification.Name("serverDidStop")
        static let modelDidLoad = Notification.Name("modelDidLoad")
        static let modelDidUnload = Notification.Name("modelDidUnload")
    }
}

/// API endpoint paths
enum APIEndpoints {
    static let health = "/health"
    static let v1Models = "/v1/models"
    static let v1ChatCompletions = "/v1/chat/completions"
}

/// Model identifiers
enum ModelIdentifiers {
    static let gemma2B = "gemma-2b"
    static let gemma3B = "gemma-3b"
    static let phi3Mini = "phi-3-mini"
}

/// Error messages
enum ErrorMessages {
    static let noModelLoaded = "No model is currently loaded. Please download and load a model first."
    static let serverNotRunning = "Server is not running. Please start the server first."
    static let invalidAPIKey = "Invalid or missing API key."
    static let networkError = "Network error. Please check your connection."
    static let modelDownloadFailed = "Failed to download model. Please try again."
    static let insufficientStorage = "Insufficient storage space for this model."
    static let insufficientMemory = "Device may not have enough RAM for this model."
}
