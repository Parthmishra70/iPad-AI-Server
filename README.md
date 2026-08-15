# Local AI Server for iPad

A SwiftUI iPad application that turns your iPad into a **local AI inference server**. Download GGUF models, run them completely on-device using llama.cpp with Metal GPU acceleration, and expose an OpenAI-compatible API endpoint for other devices on your network.

## Features

- **On-Device Inference**: Run GGUF models locally using llama.cpp with Metal GPU acceleration (M-series iPads)
- **OpenAI-Compatible API**: Expose `/v1/chat/completions`, `/v1/models`, `/health` endpoints
- **Model Management**: Browse, download, validate (GGUF magic + SHA256), install, load/unload models
- **Local Network Server**: HTTP server accessible from Mac, PC, Android, or other devices on the same network
- **API Key Authentication**: Secure your server with Bearer token authentication (stored in Keychain)
- **Streaming Support**: Server-Sent Events (SSE) for real-time token streaming
- **Chat Interface**: Built-in ChatGPT-style UI for testing models directly on iPad
- **Responsive iPad UI**: NavigationSplitView with adaptive grids, modern SwiftUI design

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                      iPad                             │
│  ┌────────────────────────────────────────────────┐  │
│  │              Model Manager                      │  │
│  │  Download / Validate / Install / Load / Delete  │  │
│  └─────────────────────────┬──────────────────────┘  │
│                            │                          │
│  ┌─────────────────────────▼──────────────────────┐  │
│  │            llama.cpp Engine (Metal)             │  │
│  │  Model Load / Tokenize / Sample / Decode Loop   │  │
│  └─────────────────────────┬──────────────────────┘  │
│                            │                          │
│                  GGUF Model (Q4_K_M)                  │
│                            │                          │
│  ┌─────────────────────────▼──────────────────────┐  │
│  │              Local HTTP Server                  │  │
│  │  POST /v1/chat/completions (stream + non-stream)│  │
│  │  GET  /v1/models                                │  │
│  │  GET  /health                                   │  │
│  └─────────────────────────┬──────────────────────┘  │
└────────────────────────────┼──────────────────────────┘
                             │ LAN / Wi-Fi
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
          Mac/PC         Android        iPad/iPhone
         (OpenAI SDK)  (requests)     (any client)
```

## Supported Models (Default)

| Model | Size | Quantization | Context | RAM Required | Notes |
|-------|------|-------------|---------|--------------|-------|
| **Qwen2.5-1.5B-Instruct** | 1.2 GB | Q4_K_M | 4096 | ~3 GB | Default, excellent for iPad Air M2 |
| Qwen2.5-3B-Instruct | 2.0 GB | Q4_K_M | 4096 | ~5 GB | Better quality, M-series only |
| Llama-3.2-3B-Instruct | 2.0 GB | Q4_K_M | 4096 | ~5 GB | Llama family alternative |

All models download from Hugging Face with integrity validation.

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

### Chat Completions (Non-Streaming)
```http
POST /v1/chat/completions
Content-Type: application/json
Authorization: Bearer YOUR_API_KEY

{
  "model": "qwen2.5-1.5b-instruct-q4_k_m",
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
  "model": "qwen2.5-1.5b-instruct-q4_k_m",
  "messages": [...],
  "stream": true
}
```
Returns Server-Sent Events (SSE) with `data: {...}` chunks ending with `data: [DONE]`.

## Usage Example (Python)

```python
import requests

url = "http://192.168.1.20:8080/v1/chat/completions"

payload = {
    "model": "qwen2.5-1.5b-instruct-q4_k_m",
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
    model="qwen2.5-1.5b-instruct-q4_k_m",
    messages=[{"role": "user", "content": "Hello!"}]
)

print(response.choices[0].message.content)
```

### Streaming with OpenAI SDK

```python
stream = client.chat.completions.create(
    model="qwen2.5-1.5b-instruct-q4_k_m",
    messages=[{"role": "user", "content": "Write a poem"}],
    stream=True
)

for chunk in stream:
    if chunk.choices[0].delta.content:
        print(chunk.choices[0].delta.content, end="", flush=True)
```

## Requirements

- iPadOS 17.0+
- Xcode 15.0+
- Local network connection
- Sufficient storage (1.2–2.5 GB per model)
- **Recommended**: iPad with M-series chip (Metal GPU) and 4GB+ RAM

## Installation

1. Open `LocalAIServer/LocalAIServer.xcodeproj` in Xcode
2. Select your development team in project settings
3. Connect your iPad via USB or use wireless deployment
4. Build and run on iPad (Debug/Release)

## First Run

1. **Generate API Key** — Server tab → "Generate API Key" (copy it)
2. **Download Model** — Models tab → "Download" on Qwen2.5-1.5B-Instruct
3. **Validate & Install** — Automatic after download (GGUF magic + SHA256)
4. **Load Model** — Tap "Load" → status changes to "Loaded & Active"
5. **Start Server** — Server tab → Toggle "Start Server"
6. **Test** — Chat tab or any OpenAI client pointing to `http://<iPad-IP>:8080/v1`

## Security

- **Local Network Only**: Server binds to all interfaces but firewall rules limit to LAN
- **API Key Required**: All endpoints except `/health` require Bearer token
- **No Cloud Processing**: All inference happens entirely on-device
- **Keychain Storage**: API keys stored securely in iOS Keychain

## iPadOS Limitations

| Limitation | Impact | Workaround |
|------------|--------|------------|
| Background execution | Server stops when app backgrounded | Keep app in foreground; use Stage Manager |
| Thermal throttling | Extended inference warms device | Plug in; shorter sessions |
| Memory pressure | Large models need RAM | Q4_K_M fits in 3–4 GB |
| Local Network permission | Required at first launch | Grant in system prompt |

## Performance (iPad Air M2, Qwen2.5-1.5B Q4_K_M)

| Metric | Value |
|--------|-------|
| Model load time | ~2–3 seconds |
| First token latency | ~100–200 ms |
| Throughput (Metal) | ~15–25 tokens/sec |
| RAM usage | ~2.5 GB (weights + KV cache) |
| Context window | 4096 tokens |

## Project Structure

```
LocalAIServer/
├── LocalAIServerApp.swift           # App entry point
├── Models/
│   ├── AIModel.swift                # Model definitions + Qwen/Llama presets
│   ├── DownloadTask.swift           # Background download + validation
│   └── ServerConfig.swift           # Server config
├── Managers/
│   ├── ModelManager.swift           # Lifecycle + chat templating
│   ├── InferenceEngine.swift        # LlamaCppInferenceEngine (llama.cpp)
│   ├── HTTPServer.swift             # NWListener HTTP server (NWConnection)
│   └── NetworkManager.swift         # IP discovery
├── Views/
│   ├── ContentView.swift            # NavigationSplitView (sidebar + detail)
│   ├── ChatView.swift               # ChatGPT-style interface
│   ├── DashboardView.swift          # Status + quick stats
│   ├── ModelsView.swift             # Model grid with actions
│   ├── ServerView.swift             # Server config + API key
│   ├── APIDocsView.swift            # Dynamic API docs + examples
│   └── SettingsView.swift           # Device info + privacy notes
├── Services/
│   └── APIKeyService.swift          # Keychain Bearer token
└── Utilities/
    └── Constants.swift              # Endpoints, ports, keys
```

## Dependencies

- **llama.swift** (SPM) — `https://github.com/mattt/llama.swift` v2.10442.0
  - Wraps llama.cpp b10442 XCFramework with Metal support
- Swift Package Manager for dependency resolution

## License

MIT License — See LICENSE file for details

## Disclaimer

This application runs AI models locally on your device. Model licenses (Qwen, Llama, etc.) are subject to their respective terms. Ensure compliance with model provider licenses when downloading and using models.