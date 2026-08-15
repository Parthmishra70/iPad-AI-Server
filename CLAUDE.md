# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Local AI Server for iPad** — A SwiftUI iPad application that runs AI models (Gemma 2B/3B, Phi-3 Mini) entirely on-device using Google's LiteRT-LM framework, then exposes them via an OpenAI-compatible HTTP API on the local network. Target: iPadOS 17+, built with Xcode 15+.

## Build, Run, and Test

This is a standard Xcode iOS project — there is no `Makefile`, `Package.swift`, or CLI test runner.

- **Open**: `LocalAIServer/LocalAIServer.xcodeproj` in Xcode 15+
- **Build & Run**: select an iPad target (M-series iPads recommended), press ⌘R. The app requires Local Network permission at runtime.
- **Clean build**: ⇧⌘K
- **Dependencies**: `LocalAIServer/LocalAIServer/LiteRTLM/CLiteRTLM.xcframework` is vendored (pre-built binary framework). The Swift wrapper files in `LiteRTLM/` (Engine, Conversation, Message, Config, etc.) wrap this xcframework. No SPM or CocoaPods — the framework is added directly via the .pbxproj.
- **Tests**: no test target exists in the project. Verification is manual via the API endpoints.

## High-Level Architecture

The app has three coordinated singletons wired into the SwiftUI environment in `LocalAIServerApp.swift`:

- **`ModelManager.shared`** — Model lifecycle (download/install/load/unload/delete). Owns the active `InferenceEngineProtocol` instance. Stores model files at `<Documents>/Models/<id>.litertlm`.
- **`ServerManager.shared`** — Raw `Network.framework` TCP listener (NOT Swifter/NWHTTP). Owns port binding, request parsing, auth, and SSE streaming. Lives in `Managers/HTTPServer.swift` despite the filename.
- **`APIKeyService.shared`** — Keychain-backed Bearer token storage; mirrors the key into `ServerManager.apiKey`.

### Request Flow

Client → `ServerManager` (NWListener, parses HTTP manually from `\r\n`-split string) → auth check → `ModelManager.generateResponse/streamResponse` → `InferenceEngineProtocol.generate/streamGenerate` (LiteRT-LM `Engine`/`Conversation`) → response serialized as JSON or SSE chunks.

### Key Files

- `Managers/InferenceEngine.swift` — `InferenceEngineProtocol` + two implementations: `LiteRTInferenceEngine` (real, wraps `LiteRTLM/Engine.swift`) and `CoreMLInferenceEngine` (stub). `ModelManager.loadModel` always instantiates `LiteRTInferenceEngine`.
- `Managers/HTTPServer.swift` — `ServerManager` class with hand-rolled HTTP parsing. Routes: `GET /health` (no auth), `GET /v1/models`, `POST /v1/chat/completions` (with `stream` SSE).
- `LiteRTLM/` — Swift wrapper around the vendored `CLiteRTLM.xcframework`. The runtime entry points are `Engine(engineConfig:).initialize()`, `engine.createConversation(with:)`, and `conversation.sendMessageStream(_:)`.
- `Models/AIModel.swift` — Defines `AIModel.availableModels` (gemma2B/3B, phi3Mini). Model state machine: `notDownloaded → downloading → downloaded → installed → loading → loaded`. `isDownloaded` is true for any post-download state.
- `Models/DownloadTask.swift` — `DownloadManager` uses a background `URLSession` (identifier `com.localaiserver.background`). Note: `handleDownloadCompletion` and `updateProgress` are stubs — file movement and progress wiring are not yet implemented.
- `Tokenizer.swift` (project root, not inside the app target) — Placeholder whitespace tokenizer with empty vocab. Not currently referenced by `InferenceEngine`; LiteRT-LM handles tokenization internally via `Conversation`.
- `Services/APIKeyService.swift` — Keychain via `SecItemAdd`/`SecItemUpdate` (note: `save` calls update then add unconditionally, ignoring the update status).
- `Utilities/Constants.swift` — Single source of truth for port range (8000–9000 recommended), `UserDefaultsKeys`, `APIEndpoints`, `Notifications`. Use these instead of hardcoding.

### Current State of the Build

The app builds, but the inference layer has known gaps documented in `IMPLEMENTATION_GUIDE.md` and `ARCHITECTURE.md`:

- `InferenceEngine.swift` instantiates `EngineConfig(modelPath:backend:.gpu:...)` — the `backend` enum case `.gpu` and the `EngineConfig` initializer signature must match the vendored `LiteRTLM/Config.swift`. If the xcframework API drifts, `loadModel` throws.
- `DownloadManager` progress callbacks (`updateProgress`, `handleDownloadCompletion`) are empty — downloads started via `ModelManager.downloadModel` work (it uses `URLSession.shared.download(from:)` directly), but `DownloadManager.startDownload` is a parallel path that does not finish moving the file.
- `ModelManager.formatMessages` produces a plain `"role: content"` string; LiteRT-LM `Conversation` expects a chat-template-formatted prompt. End-to-end chat quality depends on whether `Conversation.sendMessage` applies its own template internally.

### Conventions

- All managers are `@MainActor` `ObservableObject` singletons accessed via `.shared`.
- HTTP responses set `Access-Control-Allow-Origin: *` on every reply (CORS open for any origin).
- Models and config are persisted via `UserDefaults` (port, active model ID) and `Keychain` (API key only).
- Local-network binding is enforced via `NWParameters.requiredInterfaceType = .wifi` in `setupListener`.
- The project deliberately does NOT use SwiftPM — adding a new dependency means dropping a `.xcframework` into `LiteRTLM/` and editing `project.pbxproj`.
