# Local AI Server for iPad

A SwiftUI iPad application that turns your iPad into a **local AI inference server**. Download AI models, run them completely on-device, and expose an OpenAI-compatible API endpoint for other devices on your network.

## Features

- **On-Device Inference**: Run AI models locally using Google's LiteRT (formerly TensorFlow Lite) or Apple Core ML
- **OpenAI-Compatible API**: Expose `/v1/chat/completions` endpoint compatible with OpenAI SDK clients
- **Model Management**: Browse, download, install, and manage multiple AI models
- **Local Network Server**: HTTP server accessible from Mac, PC, Android, or other devices on the same Wi-Fi
- **API Key Authentication**: Secure your local server with Bearer token authentication
- **Streaming Support**: Server-Sent Events (SSE) for streaming responses
- **Clean SwiftUI Interface**: Professional UI with Dashboard, Models, Server, API Docs, and Settings screens

## Architecture

```
┌──────────────────────────────────┐
│            iPad                  │
│  ┌────────────────────────────┐  │
│  │      Model Manager          │  │
│  │  Download / Install / Load  │  │
│  └─────────────┬──────────────┘  │
│                │                  │
│  ┌─────────────▼──────────────┐  │
│  │   On-Device Runtime         │  │
│  │  LiteRT / Core ML           │  │
│  └─────────────┬──────────────┘  │
│                │                  │
│       AI Model (Gemma, etc.)     │
│                │                  │
│  ┌─────────────▼──────────────┐  │
│  │    Local HTTP Server        │  │
│  │  POST /v1/chat/completions  │  │
│  │  GET  /v1/models            │  │
│  │  GET  /health               │  │
│  └─────────────┬──────────────┘  │
└────────────────┼─────────────────┘
                 │ Wi-Fi / LAN
     ┌───────────┴───────────┐
     │                       │
   Mac/PC              Android/iPad
```

## Supported Models

- **Gemma 2B** - Google's lightweight 2B parameter model
- **Gemma 3B** - Enhanced 3B parameter model
- **Phi-3 Mini** - Microsoft's efficient 3.8B model

## API Endpoints

### Health Check
```http
GET /health
```

### List Models
```http
GET /v1/models
Authorization: Bearer YOUR_API_KEY
```

### Chat Completions
```http
POST /v1/chat/completions
Content-Type: application/json
Authorization: Bearer YOUR_API_KEY

{
  "model": "gemma",
  "messages": [
    {"role": "user", "content": "Explain machine learning"}
  ],
  "temperature": 0.7,
  "max_tokens": 512
}
```

### Streaming Chat Completions
```http
POST /v1/chat/completions
Content-Type: application/json
Authorization: Bearer YOUR_API_KEY

{
  "model": "gemma",
  "messages": [...],
  "stream": true
}
```

## Usage Example (Python)

```python
import requests

url = "http://192.168.1.20:8080/v1/chat/completions"

payload = {
    "model": "gemma",
    "messages": [
        {"role": "user", "content": "What is computer vision?"}
    ]
}

headers = {
    "Authorization": "Bearer YOUR_API_KEY",
    "Content-Type": "application/json"
}

response = requests.post(url, json=payload, headers=headers)
print(response.json())
```

### Using OpenAI SDK

```python
from openai import OpenAI

client = OpenAI(
    api_key="YOUR_API_KEY",
    base_url="http://192.168.1.20:8080/v1"
)

response = client.chat.completions.create(
    model="gemma",
    messages=[{"role": "user", "content": "Hello!"}]
)

print(response.choices[0].message.content)
```

## Requirements

- iPadOS 17.0+
- Xcode 15.0+
- Wi-Fi network connection
- Sufficient storage for models (1.5-3 GB per model)
- Recommended: iPad with 6GB+ RAM for larger models

## Installation

1. Open `LocalAIServer.xcodeproj` in Xcode
2. Select your development team in project settings
3. Connect your iPad via USB or use wireless deployment
4. Build and run on iPad

## Security Notes

- **Local Network Only**: By default, the server only accepts connections from your local network
- **API Key Required**: All endpoints except `/health` require Bearer token authentication
- **No Cloud Processing**: All inference happens entirely on-device; no data leaves your iPad
- **Background Limitations**: Due to iPadOS restrictions, the server may stop when the app is backgrounded

## Important Limitations

### iPadOS Constraints

1. **Background Execution**: The server requires the app to remain active. Background execution is limited by iPadOS.

2. **Thermal Management**: Extended inference sessions may cause device warming. Performance will throttle automatically.

3. **Memory Pressure**: Large models require significant RAM. The app will handle memory pressure gracefully.

4. **Network Permissions**: Local network access permission is required and must be granted by the user.

### Inference Performance

- Actual inference speed depends on iPad model and chip
- M-series iPads provide the best performance
- Hardware acceleration via GPU and Neural Engine is utilized where supported

## Project Structure

```
LocalAIServer/
├── LocalAIServerApp.swift      # App entry point
├── Models/
│   ├── AIModel.swift           # Model data structures
│   ├── DownloadTask.swift      # Download management
│   └── ServerConfig.swift      # Server configuration
├── Managers/
│   ├── ModelManager.swift      # Model lifecycle
│   ├── InferenceEngine.swift   # On-device inference
│   ├── HTTPServer.swift        # Local HTTP server
│   └── NetworkManager.swift    # Network utilities
├── Views/
│   ├── ContentView.swift       # Main tab navigation
│   ├── DashboardView.swift     # Dashboard screen
│   ├── ModelsView.swift        # Model management
│   ├── ServerView.swift        # Server controls
│   ├── APIDocsView.swift       # API documentation
│   └── SettingsView.swift      # App settings
├── Services/
│   └── APIKeyService.swift     # API key management
└── Utilities/
    └── Constants.swift         # App constants
```

## Adding Real Inference

To enable actual model inference:

1. Add Google AI Edge LiteRT Swift package to the project
2. Download compatible `.litert-model` files
3. Implement tokenization in `InferenceEngine.swift`
4. Configure Core ML delegation for hardware acceleration

See `InferenceEngine.swift` for detailed integration notes.

## License

MIT License - See LICENSE file for details

## Disclaimer

This application runs AI models locally on your device. Model licenses (Gemma, Phi-3, etc.) are subject to their respective terms. Ensure compliance with model provider licenses when downloading and using models.
