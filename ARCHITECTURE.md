# Local AI Model Server for iPad - Architecture Document

## Technology Stack Analysis

### On-Device Inference Options for iPadOS

1. **Google AI Edge / LiteRT (formerly TensorFlow Lite)**
   - Supports iOS/iPadOS via Swift Package Manager or CocoaPods
   - LiteRT-LM provides optimized LLM inference
   - Supports Gemma models in .tflite format
   - Hardware acceleration via Core ML delegation

2. **Apple Core ML**
   - Native Apple framework for on-device ML
   - Excellent hardware acceleration (GPU, Neural Engine)
   - Supports transformed models from various formats
   - Can convert Hugging Face models to Core ML format

3. **MLX (Apple's framework)**
   - Apple Silicon optimized
   - Primarily for macOS currently
   - iOS support emerging

### Recommended Approach

For this implementation, we'll use a hybrid approach:
- **Primary**: Google LiteRT-LM for LLM inference (Gemma support)
- **Fallback**: Core ML for compatible models
- **Architecture**: Abstraction layer to support multiple backends

## Project Structure

```
LocalAIServer/
├── LocalAIServerApp.swift          # App entry point
├── Models/
│   ├── AIModel.swift               # Model data structures
│   ├── DownloadTask.swift          # Download management
│   └── ServerConfig.swift          # Server configuration
├── Managers/
│   ├── ModelManager.swift          # Model lifecycle management
│   ├── InferenceEngine.swift       # On-device inference
│   ├── HTTPServer.swift            # Local HTTP server
│   └── NetworkManager.swift        # Network utilities
├── Views/
│   ├── DashboardView.swift         # Main dashboard
│   ├── ModelsView.swift            # Model management
│   ├── ServerView.swift            # Server controls
│   ├── APIDocsView.swift           # API documentation
│   └── SettingsView.swift          # App settings
├── Services/
│   ├── APIKeyService.swift         # API key management
│   └── RequestLogger.swift         # Request tracking
├── Utilities/
│   ├── QRCodeGenerator.swift       # QR code generation
│   └── Constants.swift             # App constants
└── Resources/
    └── Assets.xcassets             # App assets
```

## API Endpoints

| Endpoint | Method | Description | Auth Required |
|----------|--------|-------------|---------------|
| /health | GET | Health check | No |
| /v1/models | GET | List available models | Yes |
| /v1/chat/completions | POST | Chat completion | Yes |
| /v1/chat/completions (stream) | POST | Streaming chat | Yes |

## Security Model

- API Key stored in Keychain
- Bearer token authentication
- Local network only by default
- User-configurable port
- Warning system for external exposure

## Model Storage

- Models stored in app's documents directory
- Support for .tflite and .mlmodel formats
- Download progress tracking
- Resume capability for interrupted downloads
