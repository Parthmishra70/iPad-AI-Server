# Local AI Server for iPad

A SwiftUI iPad application that turns your iPad into a **local AI inference server**, exposing an OpenAI-compatible API endpoint for other devices on your network.

## ⚠️ Important: Implementation Status

This project provides a **complete architectural foundation** with all UI, networking, model management, and API server infrastructure. However, to enable **real AI inference**, you must complete the following integration steps:

### ✅ Completed Components

1. **Full SwiftUI Application**
   - Dashboard with server status
   - Model management screen (browse, download, install, load, delete)
   - API Server configuration screen
   - API Documentation viewer
   - Settings panel
   - QR Code generation for easy connection sharing

2. **HTTP Server Infrastructure**
   - Complete Network.framework-based HTTP server
   - OpenAI-compatible endpoints:
     - `GET /health` - Health check
     - `GET /v1/models` - List available models
     - `POST /v1/chat/completions` - Chat completion (standard & streaming)
   - API key authentication via Keychain
   - SSE streaming support

3. **Model Management**
   - Download manager with progress tracking
   - Model lifecycle: download → install → load → unload → delete
   - Support for Gemma 2B, Gemma 3B, Phi-3 Mini models
   - Local storage in app's Documents directory

4. **Security Features**
   - API key stored in iOS Keychain
   - Local network only access by default
   - Authorization header validation

5. **UI/UX**
   - Professional SwiftUI interface
   - Real-time download progress
   - Server status indicators
   - Request counter and uptime tracking
   - Copy endpoint functionality

### 🔧 Required Integration Steps

#### 1. Add Google AI Edge LiteRT Swift Package

The inference engine currently uses placeholder implementations. To enable real inference:

1. Open the project in Xcode
2. Go to **File → Add Package Dependencies**
3. Add the Google AI Edge LiteRT package:
   ```
   https://github.com/google-ai-edge/mediapipe.git
   ```
   Or use the dedicated LiteRT package when available.

4. Alternatively, add this to your `Package.swift`:
   ```swift
   .package(url: "https://github.com/google-ai-edge/litert-objc", from: "1.0.0")
   ```

#### 2. Implement Real Inference in `InferenceEngine.swift`

Replace the placeholder code in `LiteRTInferenceEngine` with actual LiteRT integration:

```swift
import LiteRT // or appropriate import

class LiteRTInferenceEngine: InferenceEngineProtocol {
    private var interpreter: Interpreter?
    private var tokenizer: Tokenizer?
    
    func loadModel(at path: URL) async throws {
        let modelData = try Data(contentsOf: path)
        let options = Interpreter.Options()
        options.addDelegate(CoreMLDelegate()) // For hardware acceleration
        
        interpreter = try Interpreter(modelData: modelData, options: options)
        try interpreter!.allocateTensors()
        
        // Initialize tokenizer for the specific model
        tokenizer = try await Tokenizer(modelName: "gemma")
    }
    
    func generate(prompt: String, temperature: Double, maxTokens: Int) async throws -> String {
        guard let interpreter = interpreter, let tokenizer = tokenizer else {
            throw InferenceError.modelNotLoaded
        }
        
        // Tokenize input
        let inputTokens = try tokenizer.encode(text: prompt)
        
        // Set input tensor
        try interpreter.copy(inputTokens, toInputAt: 0)
        
        // Run inference
        try interpreter.invoke()
        
        // Get output
        let outputTensor = try interpreter.output(at: 0)
        let outputTokens = outputTensor.data.toArray()
        
        // Decode tokens to text
        let response = try tokenizer.decode(tokens: outputTokens)
        
        return response
    }
    
    // Implement streaming similarly with incremental token generation
}
```

#### 3. Update Model URLs

The current model URLs point to HuggingFace but may need updating:

- Verify the latest LiteRT model formats from Google AI Edge documentation
- Check supported model formats for your target iPadOS version
- Consider providing pre-converted CoreML models as alternatives

#### 4. Add Info.plist Entries

Add required permissions to `Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>This app creates a local server to allow other devices on your network to access AI inference.</string>

<key>NSBonjourServices</key>
<array>
    <string>_http._tcp</string>
</array>

<key>UIBackgroundModes</key>
<array>
    <string>local-network</string>
</array>
```

#### 5. Handle iPadOS Constraints

Implement proper handling for:

- **Background execution**: The server will pause when app goes to background
- **Memory pressure**: Monitor and unload models when memory is constrained
- **Thermal throttling**: Reduce inference speed or pause during thermal events
- **App lifecycle**: Save state and gracefully shutdown server

Example:
```swift
import UIKit

extension LocalAIServerApp: UIApplicationDelegate {
    func applicationWillResignActive(_ application: UIApplication) {
        // Optionally warn user or pause server
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Server will stop accepting new connections
        // Consider showing local notification
    }
    
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        // Unload model to free memory
        Task {
            await ModelManager.shared.unloadModel()
        }
    }
}
```

## Architecture

```
┌─────────────────────────────────────────┐
│              iPad App                    │
│                                          │
│  ┌──────────────┐  ┌──────────────────┐ │
│  │   SwiftUI    │  │  Model Manager   │ │
│  │   Views      │  │                  │ │
│  └──────────────┘  └──────────────────┘ │
│           │                │             │
│  ┌──────────────┐  ┌──────────────────┐ │
│  │  API Key     │  │ Inference Engine │ │
│  │  Service     │  │ (LiteRT/CoreML)  │ │
│  └──────────────┘  └──────────────────┘ │
│                          │               │
│  ┌────────────────────────────────────┐ │
│  │       HTTP Server (Network)        │ │
│  │  /health, /v1/models, /v1/chat    │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
              │ Wi-Fi/LAN
              ▼
┌─────────────────────────────────────────┐
│  Client Devices (Mac, PC, Android)      │
│  curl, Python requests, OpenAI SDK      │
└─────────────────────────────────────────┘
```

## API Usage Examples

### Using curl

```bash
# Health check
curl http://192.168.1.100:8080/health

# List models
curl http://192.168.1.100:8080/v1/models \
  -H "Authorization: Bearer sk-local-your-api-key"

# Chat completion
curl http://192.168.1.100:8080/v1/chat/completions \
  -H "Authorization: Bearer sk-local-your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'

# Streaming
curl http://192.168.1.100:8080/v1/chat/completions \
  -H "Authorization: Bearer sk-local-your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma",
    "messages": [{"role": "user", "content": "Tell me a story"}],
    "stream": true
  }'
```

### Using Python Requests

```python
import requests

url = "http://192.168.1.100:8080/v1/chat/completions"
headers = {
    "Authorization": "Bearer sk-local-your-api-key",
    "Content-Type": "application/json"
}
payload = {
    "model": "gemma",
    "messages": [
        {"role": "user", "content": "Explain machine learning"}
    ],
    "temperature": 0.7,
    "max_tokens": 512
}

response = requests.post(url, json=payload, headers=headers)
print(response.json())
```

### Using OpenAI SDK

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://192.168.1.100:8080/v1",
    api_key="sk-local-your-api-key"  # Required even though it's local
)

response = client.chat.completions.create(
    model="gemma",
    messages=[
        {"role": "user", "content": "What is computer vision?"}
    ]
)

print(response.choices[0].message.content)
```

## Project Structure

```
LocalAIServer/
├── LocalAIServerApp.swift       # App entry point
├── Views/
│   ├── ContentView.swift        # Main tab navigation
│   ├── DashboardView.swift      # Server status overview
│   ├── ModelsView.swift         # Model management
│   ├── ServerView.swift         # Server configuration
│   ├── APIDocsView.swift        # API documentation
│   ├── SettingsView.swift       # App settings
│   └── QRCodeView.swift         # QR code for endpoint
├── Managers/
│   ├── ModelManager.swift       # Model lifecycle
│   ├── InferenceEngine.swift    # AI inference (TO INTEGRATE)
│   ├── HTTPServer.swift         # REST API server
│   └── NetworkManager.swift     # Network utilities
├── Services/
│   └── APIKeyService.swift      # Keychain API key storage
├── Models/
│   ├── AIModel.swift            # Model data structures
│   ├── DownloadTask.swift       # Download management
│   └── ServerConfig.swift       # Server configuration
└── Utilities/
    └── Constants.swift          # App constants
```

## Supported Models

| Model | Size | RAM Required | Format | Status |
|-------|------|--------------|--------|--------|
| Gemma 2B | 1.5 GB | 4 GB | LiteRT | Ready (needs inference impl) |
| Gemma 3B | 2.5 GB | 6 GB | LiteRT | Ready (needs inference impl) |
| Phi-3 Mini | 2.3 GB | 6 GB | LiteRT | Ready (needs inference impl) |

## Security Considerations

1. **Local Network Only**: By default, the server only accepts connections from your local Wi-Fi network
2. **API Key Required**: All endpoints except `/health` require Bearer token authentication
3. **No Cloud Dependency**: Once models are downloaded, all inference happens on-device
4. **Keychain Storage**: API keys are securely stored in iOS Keychain

## Troubleshooting

### Server Won't Start
- Check that iPad is on Wi-Fi
- Ensure local network permission is granted in Settings
- Try a different port (default: 8080)

### Can't Connect from Other Devices
- Verify both devices are on the same Wi-Fi network
- Check the IP address shown in the Server screen
- Ensure firewall isn't blocking the port
- Verify API key is correct

### Model Download Fails
- Check internet connection
- Verify model URL is accessible
- Ensure sufficient storage space

### Inference Returns Placeholder Text
- **This is expected until LiteRT is integrated**
- Follow the integration steps above
- Verify LiteRT package is added correctly

## Performance Optimization Tips

1. **Start with smaller models** (Gemma 2B) for faster inference
2. **Use newer iPads** with M-series chips for best performance
3. **Monitor thermal conditions** - inference may slow down if device heats up
4. **Close other apps** to maximize available RAM
5. **Keep iPad plugged in** during extended inference sessions

## Roadmap

- [x] Complete UI implementation
- [x] HTTP server with OpenAI-compatible API
- [x] Model management system
- [x] API key authentication
- [x] QR code sharing
- [ ] **LiteRT integration** (requires developer action)
- [ ] Core ML model support
- [ ] Background server mode (with limitations)
- [ ] Multiple concurrent request handling
- [ ] Model quantization options
- [ ] Custom model import

## License

MIT License - See LICENSE file for details

## Contributing

Contributions welcome! Areas needing help:
- LiteRT/CoreML integration expertise
- Model conversion tools
- Performance optimization
- Additional model support

## Resources

- [Google AI Edge LiteRT Documentation](https://ai.google.dev/edge/litert)
- [Apple Core ML Documentation](https://developer.apple.com/documentation/coreml)
- [OpenAI API Reference](https://platform.openai.com/docs/api-reference)
- [iPadOS Networking Guidelines](https://developer.apple.com/documentation/network)
