//
//  InferenceEngine.swift
//  LocalAIServer
//
//  Protocol and implementation for on-device AI inference using llama.cpp
//

import Foundation
import LlamaSwift

/// Protocol for inference engines - allows multiple backend implementations
protocol InferenceEngineProtocol: AnyObject {
    func loadModel(at path: URL) async throws
    func generate(prompt: String, temperature: Double, maxTokens: Int) async throws -> String
    func streamGenerate(prompt: String, temperature: Double, maxTokens: Int) -> AsyncThrowingStream<String, Error>
    func unload() async
}

/// llama.cpp based inference engine using mattt/llama.swift
/// This is the primary engine for running GGUF models on iPad with Metal acceleration
final class LlamaCppInferenceEngine: InferenceEngineProtocol {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var modelPath: URL?
    private let nCtx: UInt32 = 2048
    private var isLoaded: Bool = false
    
    private let queue = DispatchQueue(label: "com.localaiserver.llama", qos: .userInitiated)
    
    // MARK: - InferenceEngineProtocol
    
    func loadModel(at path: URL) async throws {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw InferenceError.modelNotFound
        }
        
        self.modelPath = path
        
        try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            llama_backend_init()
            
            var modelParams = llama_model_default_params()
            modelParams.n_gpu_layers = -1
            
            let cPath = path.path.cString(using: .utf8)!
            let loadedModel = llama_model_load_from_file(cPath, modelParams)
            
            guard let loadedModel = loadedModel else {
                throw InferenceError.inferenceFailed
            }
            
            guard let loadedVocab = llama_model_get_vocab(loadedModel) else {
                llama_model_free(loadedModel)
                throw InferenceError.inferenceFailed
            }
            
            var ctxParams = llama_context_default_params()
            ctxParams.n_ctx = self.nCtx
            ctxParams.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
            ctxParams.n_threads_batch = ctxParams.n_threads
            ctxParams.n_batch = 512
            
            guard let loadedContext = llama_init_from_model(loadedModel, ctxParams) else {
                llama_model_free(loadedModel)
                throw InferenceError.inferenceFailed
            }
            
            self.setLoaded(model: loadedModel, context: loadedContext, vocab: loadedVocab)
            print("Model loaded from: \(path.path)")
        }.value
    }
    
    func generate(prompt: String, temperature: Double, maxTokens: Int) async throws -> String {
        let (context, vocab) = try getContextAndVocab()
        
        return try await Task.detached(priority: .userInitiated) { [prompt, temperature, maxTokens, context, vocab] in
            var fullResponse = ""
            
            // Tokenize the prompt
            var tokens = self.tokenize(prompt, vocab: vocab)
            guard !tokens.isEmpty else {
                throw InferenceError.tokenizationFailed
            }
            
            // Create batch for prefill
            var batch = llama_batch_get_one(&tokens, Int32(tokens.count))
            
            if llama_decode(context, batch) != 0 {
                throw InferenceError.inferenceFailed
            }
            
            // Initialize sampler chain
            let sparams = llama_sampler_chain_default_params()
            let sampler = llama_sampler_chain_init(sparams)
            llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
            llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.95, 1))
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(Float(temperature)))
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32(Date().timeIntervalSince1970)))
            
            var nGenerated = 0
            let eosToken = llama_vocab_eos(vocab)
            
            while nGenerated < maxTokens {
// Sample from the context
            let token = llama_sampler_sample(sampler, context, -1)
                
                if token == eosToken {
                    break
                }
                
                llama_sampler_accept(sampler, token)
                
                var pieceBytes = [CChar](repeating: 0, count: 32)
                let nChars = llama_token_to_piece(vocab, token, &pieceBytes, Int32(pieceBytes.count), 0, false)
                if nChars > 0 {
                    let piece = String(cString: pieceBytes)
                    fullResponse += piece
                }
                
                // Create batch for next token
                var nextTokens = [token]
                batch = llama_batch_get_one(&nextTokens, 1)
                
                if llama_decode(context, batch) != 0 {
                    break
                }
                
                nGenerated += 1
            }
            
            llama_sampler_free(sampler)
            return fullResponse
        }.value
    }
    
    func streamGenerate(prompt: String, temperature: Double, maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    guard let self = self else {
                        continuation.finish(throwing: InferenceError.modelNotLoaded)
                        return
                    }
                    
                    let (context, vocab) = try self.getContextAndVocab()
                    
                    var tokens = self.tokenize(prompt, vocab: vocab)
                    guard !tokens.isEmpty else {
                        continuation.finish(throwing: InferenceError.tokenizationFailed)
                        return
                    }
                    
                    var batch = llama_batch_get_one(&tokens, Int32(tokens.count))
                    
                    if llama_decode(context, batch) != 0 {
                        continuation.finish(throwing: InferenceError.inferenceFailed)
                        return
                    }
                    
let sparams = llama_sampler_chain_default_params()
                    let sampler = llama_sampler_chain_init(sparams)
                    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
                    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.95, 1))
                    llama_sampler_chain_add(sampler, llama_sampler_init_temp(Float(temperature)))
                    llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32(Date().timeIntervalSince1970)))
                    
                    var nGenerated = 0
                    let eosToken = llama_vocab_eos(vocab)
                    
                    while nGenerated < maxTokens {
                        try Task.checkCancellation()
                        
                        let token = llama_sampler_sample(sampler, context, -1)
                        
                        if token == eosToken {
                            break
                        }
                        
                        llama_sampler_accept(sampler, token)
                        
                        var pieceBytes = [CChar](repeating: 0, count: 32)
                        let nChars = llama_token_to_piece(vocab, token, &pieceBytes, Int32(pieceBytes.count), 0, false)
                        if nChars > 0 {
                            let piece = String(cString: pieceBytes)
                            continuation.yield(piece)
                        }
                        
                        var nextTokens = [token]
                        batch = llama_batch_get_one(&nextTokens, 1)
                        
                        if llama_decode(context, batch) != 0 {
                            break
                        }
                        
                        nGenerated += 1
                    }
                    
                    llama_sampler_free(sampler)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func unload() async {
        let (model, context) = getModelAndContext()
        
        if let context = context {
            llama_free(context)
        }
        if let model = model {
            llama_model_free(model)
        }
        
        setUnloaded()
        llama_backend_free()
        print("Model unloaded")
    }
    
    func getModelPointer() -> OpaquePointer? {
        return queue.sync { model }
    }
    
    // MARK: - Private helpers
    
    private func tokenize(_ text: String, vocab: OpaquePointer) -> [llama_token] {
        let textLen = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(textLen) * 2 + 10)
        let nTokens = llama_tokenize(vocab, text, textLen, &tokens, Int32(tokens.count), true, false)
        return Array(tokens.prefix(Int(nTokens)))
    }
    
    private func setLoaded(model: OpaquePointer, context: OpaquePointer, vocab: OpaquePointer) {
        queue.sync {
            self.model = model
            self.context = context
            self.vocab = vocab
            self.isLoaded = true
        }
    }
    
    private func setUnloaded() {
        queue.sync {
            self.model = nil
            self.context = nil
            self.vocab = nil
            self.isLoaded = false
        }
    }
    
    private func getContextAndVocab() throws -> (OpaquePointer, OpaquePointer) {
        let (context, vocab, loaded) = queue.sync {
            (self.context, self.vocab, self.isLoaded)
        }
        guard loaded, let context = context, let vocab = vocab else {
            throw InferenceError.modelNotLoaded
        }
        return (context, vocab)
    }
    
    private func getModelAndContext() -> (OpaquePointer?, OpaquePointer?) {
        queue.sync { (self.model, self.context) }
    }
}

// MARK: - Errors

enum InferenceError: LocalizedError {
    case modelNotFound
    case modelNotLoaded
    case inferenceFailed
    case tokenizationFailed
    case decodingFailed
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound: return "Model file not found at specified path"
        case .modelNotLoaded: return "No model is currently loaded"
        case .inferenceFailed: return "Inference execution failed"
        case .tokenizationFailed: return "Failed to tokenize input"
        case .decodingFailed: return "Failed to decode output tokens"
        }
    }
}