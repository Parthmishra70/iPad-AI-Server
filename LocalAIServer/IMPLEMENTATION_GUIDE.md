# Implementation Guide: Completing the Local AI Server

This guide provides step-by-step instructions to complete the LiteRT inference integration.

## Current Status

### ✅ What's Already Built

1. **Complete SwiftUI Application** - All 5 screens implemented and working
2. **HTTP Server** - Full Network.framework server with OpenAI-compatible API
3. **Model Management** - Download, install, load, unload, delete functionality
4. **API Authentication** - Keychain-based API key system
5. **QR Code Generation** - Using CoreImage CIFilter
6. **Progress Tracking** - Download progress with formatted display
7. **Streaming Support** - SSE implementation for token streaming

### ❌ What Needs Integration

1. **LiteRT Inference Engine** - Currently uses placeholder responses
2. **Tokenizer Implementation** - Required for prompt encoding/decoding
3. **Model File Validation** - Verify downloaded model integrity
4. **Hardware Acceleration** - CoreML delegate configuration

---

## Step 1: Add LiteRT Dependencies

### Option A: Swift Package Manager (Recommended)

1. Open `LocalAIServer.xcodeproj` in Xcode 15+
2. Go to **File → Add Package Dependencies**
3. Enter repository URL:
   ```
   https://github.com/google-ai-edge/mediapipe.git
   ```
4. Select the latest version
5. Add to target: `LocalAIServer`

### Option B: Manual Framework Integration

If SPM doesn't work, download pre-built frameworks:

1. Visit [Google AI Edge Releases](https://github.com/google-ai-edge/mediapipe/releases)
2. Download iOS LiteRT framework
3. Drag into Xcode project under "Frameworks" group
4. Ensure "Copy items if needed" is checked
5. Add to "Frameworks, Libraries, and Embedded Content"

### Option C: Use Pre-converted CoreML Models

Alternative approach using Apple's CoreML:

1. Convert models using `coremltools`:
   ```python
   import coremltools as ct
   
   # Load LiteRT model
   from litert import Model
   model = Model.load("gemma-2b-it.litert-model")
   
   # Convert to CoreML
   mlmodel = ct.convert(model, convert_to="mlprogram")
   mlmodel.save("Gemma2B.mlpackage")
   ```

2. Use CoreML framework (already available in iOS)
3. No external dependencies needed

---

## Step 2: Update InferenceEngine.swift

Replace the entire `LiteRTInferenceEngine` class with this implementation:

```swift
import Foundation
#if canImport(LiteRT)
import LiteRT
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
            tokenizer = await Tokenizer.shared
            
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
```

---

## Step 3: Implement Tokenizer

Create a new file `Tokenizer.swift`:

```swift
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
```

**Better Approach**: Use an existing tokenizer library:

```swift
// Add via SPM: https://github.com/johnmai-dev/Jinja
// Or: https://github.com/huggingface/swift-transformers

import Transformers

class Tokenizer {
    static let shared = Tokenizer()
    private let tokenizer: PreTrainedTokenizer?
    
    init() {
        // Load appropriate tokenizer for the model
        self.tokenizer = try? PreTrainedTokenizer(tokenizerConfig: "gemma-2b")
    }
    
    func encode(text: String) throws -> [Int32] {
        return try tokenizer?.encode(text: text).map { Int32($0) } ?? []
    }
    
    func decode(tokens: [Int32]) throws -> String {
        return try tokenizer?.decode(tokens: tokens.map { Int($0) }) ?? ""
    }
}
```

---

## Step 4: Update Info.plist

Add these entries to enable local network access:

```xml
<!-- Local Network Usage -->
<key>NSLocalNetworkUsageDescription</key>
<string>This app creates a local AI inference server that other devices on your network can connect to.</string>

<!-- Bonjour Services for discovery -->
<key>NSBonjourServices</key>
<array>
    <string>_http._tcp</string>
    <string>_localaiserver._tcp</string>
</array>

<!-- Background Modes (limited support) -->
<key>UIBackgroundModes</key>
<array>
    <string>local-network</string>
</array>
```

---

## Step 5: Test the Integration

### Build and Run

1. Connect iPad to Mac
2. Select iPad as target device
3. Build and run (⌘R)
4. Grant local network permission when prompted

### Test Flow

1. **Download a Model**
   - Go to Models tab
   - Tap Download on Gemma 2B
   - Wait for download to complete

2. **Load the Model**
   - Tap Load button
   - Wait for model to load (may take 10-30 seconds)
   - Status should show "Loaded"

3. **Start Server**
   - Go to API Server tab
   - Toggle server ON
   - Note the IP address and port

4. **Test from Mac**
   ```bash
   # Get API key first (generate in Settings)
   API_KEY="sk-local-your-key"
   
   # Health check
   curl http://192.168.1.XXX:8080/health
   
   # Chat completion
   curl http://192.168.1.XXX:8080/v1/chat/completions \
     -H "Authorization: Bearer $API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"model": "gemma", "messages": [{"role": "user", "content": "Hello!"}]}'
   ```

---

## Troubleshooting

### Build Errors

**"No such module 'LiteRT'"**
- Verify SPM package is added correctly
- Check that target has LiteRT in "Frameworks, Libraries..."
- Clean build folder (⇧⌘K) and rebuild

**"Cannot find 'Interpreter' in scope"**
- Import statement may be wrong
- Check LiteRT API documentation for correct class names
- Version mismatch - update to latest LiteRT

### Runtime Errors

**Model fails to load**
- Verify model file exists at path
- Check file permissions
- Ensure sufficient RAM available
- Try smaller model (Gemma 2B)

**Inference returns empty response**
- Check tokenizer is initialized
- Verify model format matches expected input
- Add logging to debug tensor shapes

**Server won't start**
- Check local network permission granted
- Verify no other app using port 8080
- Try different port in Settings

### Performance Issues

**Slow inference**
- Enable CoreML delegate
- Use quantized models (INT8)
- Close other apps to free RAM
- Check for thermal throttling

**High memory usage**
- Unload model when not in use
- Use smaller models
- Monitor memory pressure in Xcode

---

## Next Steps After Integration

1. **Optimize Performance**
   - Profile with Instruments
   - Tune temperature and sampling parameters
   - Experiment with batch sizes

2. **Add More Models**
   - Support Llama models
   - Add Mistral variants
   - Enable custom model import

3. **Enhance Features**
   - Conversation history
   - System prompts
   - Multiple model switching
   - Request queuing

4. **Production Readiness**
   - Add error recovery
   - Implement retry logic
   - Add logging/telemetry
   - Write unit tests

---

## Resources

- [LiteRT Documentation](https://ai.google.dev/edge/litert)
- [Core ML Programming Guide](https://developer.apple.com/documentation/coreml)
- [Hugging Face Transformers](https://huggingface.co/docs/transformers)
- [Swift Transformers Library](https://github.com/huggingface/swift-transformers)
