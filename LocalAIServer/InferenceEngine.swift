import Foundation
#if canImport(LiteRT)
import LiteRT
#endif
#if canImport(CoreML)
import CoreML
#endif

/// Production-ready LiteRT inference engine
class LiteRTInferenceEngine: InferenceEngineProtocol {
    private var interpreter: Interpreter?
    private var tokenizer: Tokenizer?
    private var modelPath: URL?
    private var isLoaded: Bool = false
    
    // Configuration
    private let maxContextLength = 2048
    private let temperature: Float = 0.7
    
    func loadModel(at path: URL) async throws {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw InferenceError.modelNotFound
        }
        
        print("Loading model from: \(path.path)")
        
        do {
            // Load model data
            let modelData = try Data(contentsOf: path)
            
            // Configure interpreter with hardware acceleration
            let options = Interpreter.Options()
            
            // Add CoreML delegate for GPU/Neural Engine acceleration
            #if canImport(CoreML)
            if let coreMLDelegate = CoreMLDelegate() {
                options.add(coreMLDelegate)
                print("CoreML delegate added for hardware acceleration")
            }
            #endif
            
            // Create interpreter
            #if canImport(LiteRT)
            interpreter = try Interpreter(modelData: modelData, options: options)
            try interpreter!.allocateTensors()
            #else
            throw InferenceError.inferenceFailed
            #endif
            
            // Initialize tokenizer (model-specific)
            tokenizer = Tokenizer.shared
            
            modelPath = path
            isLoaded = true
            
            print("Model loaded successfully")
            
        } catch {
            print("Failed to load model: \(error)")
            throw error
        }
    }
    
    func generate(prompt: String, temperature: Double, maxTokens: Int) async throws -> String {
        guard isLoaded else {
            throw InferenceError.modelNotLoaded
        }
        
        guard let interpreter = interpreter, let tokenizer = tokenizer else {
            throw InferenceError.modelNotLoaded
        }
        
        do {
            // Format prompt for chat model
            let formattedPrompt = formatChatPrompt(prompt)
            
            // Tokenize input
            let inputTokens = try tokenizer.encode(text: formattedPrompt)
            
            // Prepare input tensor
            let inputShape = [1, inputTokens.count]
            try interpreter.resizeInputTensor(
                at: 0, 
                shape: inputShape.map { NSNumber(value: $0) }
            )
            try interpreter.allocateTensors()
            
            // Copy input data
            try interpreter.copy(inputTokens, toInputAt: 0)
            
            // Run inference loop
            var generatedTokens: [Int32] = []
            var currentTokens = inputTokens
            
            for _ in 0..<maxTokens {
                try interpreter.invoke()
                
                // Get output logits
                let outputTensor = try interpreter.output(at: 0)
                let logits = try extractLogits(from: outputTensor)
                
                // Sample next token with temperature
                let nextToken = sampleToken(logits: logits, temperature: Float(temperature))
                
                guard nextToken != tokenizer.eosTokenId else {
                    break // End of sequence
                }
                
                generatedTokens.append(nextToken)
                currentTokens.append(nextToken)
                
                // Update input for next iteration
                try interpreter.resizeInputTensor(
                    at: 0,
                    shape: [1, currentTokens.count].map { NSNumber(value: $0) }
                )
                try interpreter.copy(currentTokens, toInputAt: 0)
            }
            
            // Decode generated tokens
            let response = try tokenizer.decode(tokens: generatedTokens)
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch {
            print("Inference failed: \(error)")
            throw InferenceError.inferenceFailed
        }
    }
    
    func streamGenerate(prompt: String, temperature: Double, maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        guard isLoaded else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: InferenceError.modelNotLoaded)
            }
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let formattedPrompt = formatChatPrompt(prompt)
                    
                    guard let tokenizer = self.tokenizer else {
                        throw InferenceError.modelNotLoaded
                    }
                    
                    var inputTokens = try tokenizer.encode(text: formattedPrompt)
                    var generatedCount = 0
                    
                    for _ in 0..<maxTokens {
                        try Task.checkCancellation()
                        
                        guard let interpreter = self.interpreter else {
                            throw InferenceError.modelNotLoaded
                        }
                        
                        // Resize and allocate
                        try interpreter.resizeInputTensor(
                            at: 0,
                            shape: [1, inputTokens.count].map { NSNumber(value: $0) }
                        )
                        try interpreter.allocateTensors()
                        try interpreter.copy(inputTokens, toInputAt: 0)
                        
                        // Run inference
                        try interpreter.invoke()
                        
                        // Get output
                        let outputTensor = try interpreter.output(at: 0)
                        let logits = try extractLogits(from: outputTensor)
                        
                        // Sample token
                        let nextToken = sampleToken(logits: logits, temperature: Float(temperature))
                        
                        guard nextToken != tokenizer.eosTokenId else {
                            break
                        }
                        
                        // Decode single token
                        let tokenText = try tokenizer.decode(tokens: [nextToken])
                        
                        // Stream the token
                        continuation.yield(tokenText)
                        
                        inputTokens.append(nextToken)
                        generatedCount += 1
                        
                        // Small delay for realistic streaming
                        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    }
                    
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func unload() async {
        interpreter = nil
        tokenizer = nil
        modelPath = nil
        isLoaded = false
        print("Model unloaded")
    }
    
    // MARK: - Helper Methods
    
    private func formatChatPrompt(_ prompt: String) -> String {
        // Format for Gemma-style chat models
        return "<bos><start_of_turn>user\n\(prompt)<end_of_turn>\n<start_of_turn>model\n"
    }
    
    private func extractLogits(from tensor: Tensor) throws -> [Float] {
        // Extract logits from output tensor
        // Implementation depends on tensor structure
        guard let data = tensor.data as? [Float] else {
            throw InferenceError.decodingFailed
        }
        return data
    }
    
    private func sampleToken(logits: [Float], temperature: Float) -> Int32 {
        // Apply temperature scaling
        let scaledLogits = logits.map { $0 / temperature }
        
        // Softmax
        let maxLogit = scaledLogits.max() ?? 0
        let expLogits = scaledLogits.map { exp($0 - maxLogit) }
        let sumExp = expLogits.reduce(0, +)
        let probabilities = expLogits.map { $0 / sumExp }
        
        // Sample from distribution
        let randomValue = Float.random(in: 0..<1)
        var cumulativeProb: Float = 0
        
        for (index, prob) in probabilities.enumerated() {
            cumulativeProb += prob
            if cumulativeProb >= randomValue {
                return Int32(index)
            }
        }
        
        return Int32(probabilities.count - 1)
    }
}
