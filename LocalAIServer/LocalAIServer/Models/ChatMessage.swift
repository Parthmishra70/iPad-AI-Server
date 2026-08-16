import Foundation

/// Represents a chat message in the conversation
struct ChatMessage: Codable, Equatable, Hashable {
    let role: String
    let content: String
    
    init(role: String, content: String) {
        self.role = role
        self.content = content
    }
    
    /// Create a system message
    static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: "system", content: content)
    }
    
    /// Create a user message
    static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: "user", content: content)
    }
    
    /// Create an assistant message
    static func assistant(_ content: String) -> ChatMessage {
        ChatMessage(role: "assistant", content: content)
    }
    
    /// Check if this is a system message
    var isSystem: Bool { role == "system" }
    
    /// Check if this is a user message
    var isUser: Bool { role == "user" }
    
    /// Check if this is an assistant message
    var isAssistant: Bool { role == "assistant" }
}

/// Request body for chat completions API
struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double?
    let maxTokens: Int?
    let stream: Bool?
    
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

/// Response from chat completions API
struct ChatCompletionResponse: Codable {
    let id: String
    let object: String
    let choices: [Choice]
}

/// A single choice in the completion response
struct Choice: Codable {
    let index: Int
    let message: ChatMessage
    let finishReason: String
    
    enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }
}

/// Streaming response chunk
struct StreamChunk: Codable {
    let choices: [StreamChoice]
}

/// A single choice in a streaming chunk
struct StreamChoice: Codable {
    let delta: Delta
}

/// Delta content for streaming
struct Delta: Codable {
    let content: String?
}