//
//  Tokenizer.swift
//  LocalAIServer
//

import Foundation

/// Simple tokenizer for Gemma models
/// In production, use the official SentencePiece or similar library
class Tokenizer {
    static let shared = Tokenizer()
    
    let eosTokenId: Int32 = 1
    let bosTokenId: Int32 = 2
    
    private var vocab: [String: Int32] = [:]
    private var reverseVocab: [Int32: String] = [:]
    
    init() {
        // Load vocabulary from model or embedded file
        // This is a simplified example
        loadDefaultVocab()
    }
    
    func encode(text: String) throws -> [Int32] {
        // Simple whitespace tokenization (replace with proper tokenization)
        let tokens = text.components(separatedBy: .whitespaces)
        var tokenIds: [Int32] = [bosTokenId]
        
        for token in tokens {
            if let id = vocab[token] {
                tokenIds.append(id)
            } else {
                // Handle unknown tokens (character-level fallback)
                let charIds = token.unicodeScalars.compactMap { vocab[String($0)] }
                tokenIds.append(contentsOf: charIds)
            }
        }
        
        return tokenIds
    }
    
    func decode(tokens: [Int32]) throws -> String {
        var textParts: [String] = []
        
        for tokenId in tokens {
            if let token = reverseVocab[tokenId] {
                textParts.append(token)
            }
        }
        
        return textParts.joined()
    }
    
    private func loadDefaultVocab() {
        // Load from embedded vocab file or model metadata
        // This is a placeholder - implement proper vocab loading
        vocab = [:]
        reverseVocab = [:]
    }
}
