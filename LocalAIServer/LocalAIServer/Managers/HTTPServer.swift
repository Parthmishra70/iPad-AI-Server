//
//  HTTPServer.swift
//  LocalAIServer
//
//  Local HTTP server exposing OpenAI-compatible API endpoints
//

import Foundation
import Network

/// Local HTTP server that exposes AI model inference via REST API
@MainActor
class ServerManager: ObservableObject {
    static let shared = ServerManager()
    
    @Published var isRunning: Bool = false
    @Published var ipAddress: String?
    @Published var port: Int = 8080
    @Published var requestCount: Int64 = 0
    @Published var lastRequestTime: Date?
    @Published var apiKey: String?
    @Published var errorMessage: String?
    
    private var listener: NWListener?
    private var connections: Set<NWConnectionWrapper> = []
    private var startTime: Date?
    
    // MARK: - Configuration
    
    func loadConfiguration() {
        port = UserDefaults.standard.integer(forKey: "serverPort")
        if port == 0 { port = 8080 }
        
        apiKey = KeychainHelper.load(key: "apiKey")
        
        getLocalIPAddress()
    }
    
    func saveConfiguration() {
        UserDefaults.standard.set(port, forKey: "serverPort")
    }
    
    // MARK: - Server Control
    
    func startServer() async {
        guard !isRunning else { return }
        
        do {
            try await setupListener()
            isRunning = true
            startTime = Date()
            errorMessage = nil
            
            print("Server started on port \(port)")
        } catch {
            errorMessage = error.localizedDescription
            isRunning = false
        }
    }
    
    func stopServer() {
        listener?.cancel()
        for connection in connections {
            connection.connection.cancel()
        }
        connections.removeAll()
        isRunning = false
        startTime = nil
        
        print("Server stopped")
    }
    
    // MARK: - Network Setup
    
    private func setupListener() async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: UInt16(port))!)
        
        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    print("Listener ready")
                case .failed(let error):
                    self?.errorMessage = error.localizedDescription
                    self?.isRunning = false
                case .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }
        
        listener?.start(queue: .global(qos: .userInitiated))
    }
    
    private func handleConnection(_ connection: NWConnection) {
        let wrapper = NWConnectionWrapper(connection: connection)
        connections.insert(wrapper)
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Connection established, start reading
                Task { @MainActor in
                    self?.readData(from: connection)
                }
            case .failed, .cancelled:
                Task { @MainActor in
                    self?.connections.remove(wrapper)
                }
            default:
                break
            }
        }
        
        connection.start(queue: .global(qos: .userInitiated))
    }
    
    private func readData(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data {
                Task { @MainActor in
                    await self?.processRequest(data: data, connection: connection)
                }
            }
            
            if isComplete || error != nil {
                Task { @MainActor in
                    let wrapper = self?.connections.first { $0.connection === connection }
                    if let wrapper = wrapper {
                        self?.connections.remove(wrapper)
                    }
                }
            }
        }
    }
    
    // MARK: - Request Processing
    
    private func processRequest(data: Data, connection: NWConnection) async {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: .badRequest, body: "Invalid request")
            return
        }
        
        let lines = requestString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }
        
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return }
        
        let method = parts[0]
        let path = parts[1]
        
        // Extract headers and body
        var headers: [String: String] = [:]
        var bodyStartIndex = 0
        for (index, line) in lines.enumerated() {
            if line.isEmpty {
                bodyStartIndex = index + 1
                break
            }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key.lowercased()] = value
            }
        }
        
        let body = bodyStartIndex > 0 && bodyStartIndex < lines.count 
            ? lines[bodyStartIndex...].joined(separator: "\n") 
            : ""
        
        // Increment request counter
        requestCount += 1
        lastRequestTime = Date()
        
        // Check API key authentication (except for /health)
        if path != "/health" {
            guard let authHeader = headers["authorization"] else {
                sendResponse(connection: connection, status: .unauthorized, body: "Missing authorization header")
                return
            }
            
            if let expectedKey = apiKey, !authHeader.contains(expectedKey) {
                sendResponse(connection: connection, status: .unauthorized, body: "Invalid API key")
                return
            }
        }
        
        // Route request
        await handleRoute(method: method, path: path, headers: headers, body: body, connection: connection)
    }
    
    private func handleRoute(method: String, path: String, headers: [String: String], 
                            body: String, connection: NWConnection) async {
        
        switch (method, path) {
        case ("GET", "/health"):
            await handleHealth(connection: connection)
            
        case ("GET", "/v1/models"):
            await handleListModels(connection: connection)
            
        case ("POST", "/v1/chat/completions"):
            await handleChatCompletions(headers: headers, body: body, connection: connection)
            
        default:
            sendResponse(connection: connection, status: .notFound, body: "Endpoint not found")
        }
    }
    
    // MARK: - Endpoint Handlers
    
    private func handleHealth(connection: NWConnection) async {
        let modelManager = ModelManager.shared
        let response = HealthResponse(
            status: "ok",
            model: modelManager.activeModel?.name ?? "none",
            device: "iPad",
            inference: "local"
        )
        
        sendJSON(connection: connection, status: .ok, object: response)
    }
    
    private func handleListModels(connection: NWConnection) async {
        let modelManager = ModelManager.shared
        let models = modelManager.models.filter { $0.isDownloaded }.map { model in
            ModelInfo(id: model.name, object: "model", ownedBy: "local")
        }
        
        let response = ModelsListResponse(object: "list", data: models)
        sendJSON(connection: connection, status: .ok, object: response)
    }
    
    private func handleChatCompletions(headers: [String: String], body: String, 
                                       connection: NWConnection) async {
        guard let requestData = body.data(using: .utf8),
              let request = try? JSONDecoder().decode(ChatCompletionRequest.self, from: requestData) else {
            sendResponse(connection: connection, status: .badRequest, body: "Invalid request body")
            return
        }
        
        let modelManager = ModelManager.shared
        
        guard modelManager.activeModel != nil else {
            sendResponse(connection: connection, status: .serviceUnavailable, 
                        body: "No model loaded")
            return
        }
        
        if request.stream ?? false {
            await handleStreamingChat(request: request, connection: connection)
        } else {
            await handleStandardChat(request: request, connection: connection)
        }
    }
    
    private func handleStandardChat(request: ChatCompletionRequest, connection: NWConnection) async {
        let modelManager = ModelManager.shared
        
        do {
            let content = try await modelManager.generateResponse(
                messages: request.messages.map { ChatMessage(role: $0.role, content: $0.content) },
                temperature: request.temperature ?? 0.7,
                maxTokens: request.maxTokens ?? 512
            )
            
            let response = ChatCompletionResponse(
                id: "chatcmpl-\(UUID().uuidString.prefix(8))",
                object: "chat.completion",
                choices: [
                    Choice(
                        index: 0,
                        message: ChatMessage(role: "assistant", content: content),
                        finishReason: "stop"
                    )
                ]
            )
            
            sendJSON(connection: connection, status: .ok, object: response)
        } catch {
            sendResponse(connection: connection, status: .internalServerError, 
                        body: error.localizedDescription)
        }
    }
    
    private func handleStreamingChat(request: ChatCompletionRequest, connection: NWConnection) async {
        let modelManager = ModelManager.shared
        
        let stream = modelManager.streamResponse(
            messages: request.messages.map { ChatMessage(role: $0.role, content: $0.content) },
            temperature: request.temperature ?? 0.7,
            maxTokens: request.maxTokens ?? 512
        )
        
        // Send SSE headers
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
        sendData(connection: connection, data: headers.data(using: .utf8)!)
        
        do {
            for try await token in stream {
                let chunk = StreamChunk(choices: [StreamChoice(delta: Delta(content: token))])
                let jsonData = try JSONEncoder().encode(chunk)
                let sseData = "data: \(String(data: jsonData, encoding: .utf8)!)\n\n".data(using: .utf8)!
                sendData(connection: connection, data: sseData)
            }
            
            // Send DONE
            let doneData = "data: [DONE]\n\n".data(using: .utf8)!
            sendData(connection: connection, data: doneData)
        } catch {
            print("Streaming error: \(error)")
        }
    }
    
    // MARK: - Response Helpers
    
    private func sendResponse(connection: NWConnection, status: HTTPStatus, body: String) {
        let httpResponse = """
        HTTP/1.1 \(status.code) \(status.reason)\r
        Content-Type: text/plain\r
        Content-Length: \(body.count)\r
        Access-Control-Allow-Origin: *\r
        \r
        \(body)
        """
        
        sendData(connection: connection, data: httpResponse.data(using: .utf8)!)
    }
    
    private func sendJSON<T: Encodable>(connection: NWConnection, status: HTTPStatus, object: T) {
        guard let jsonData = try? JSONEncoder().encode(object),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            sendResponse(connection: connection, status: .internalServerError, body: "Encoding failed")
            return
        }
        
        let httpResponse = """
        HTTP/1.1 \(status.code) \(status.reason)\r
        Content-Type: application/json\r
        Content-Length: \(jsonString.count)\r
        Access-Control-Allow-Origin: *\r
        \r
        \(jsonString)
        """
        
        sendData(connection: connection, data: httpResponse.data(using: .utf8)!)
    }
    
    private func sendData(connection: NWConnection, data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in })
    }
    
    // MARK: - Network Info
    
    private func getLocalIPAddress() {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else { return }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            let interface = ptr!.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" { // Wi-Fi interface
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        
        ipAddress = address
    }
    
    // MARK: - Server Status
    
    var uptime: TimeInterval? {
        guard let start = startTime else { return nil }
        return Date().timeIntervalSince(start)
    }
    
    var apiEndpoint: String? {
        guard let ip = ipAddress else { return nil }
        return "http://\(ip):\(port)/v1"
    }
}

// MARK: - NWConnection Wrapper

/// Wrapper for NWConnection to conform to Hashable
class NWConnectionWrapper: Hashable {
    let connection: NWConnection
    private let id = UUID()
    
    init(connection: NWConnection) {
        self.connection = connection
    }
    
    static func == (lhs: NWConnectionWrapper, rhs: NWConnectionWrapper) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - HTTP Status Codes

enum HTTPStatus {
    case ok
    case badRequest
    case unauthorized
    case notFound
    case serviceUnavailable
    case internalServerError
    
    var code: Int {
        switch self {
        case .ok: return 200
        case .badRequest: return 400
        case .unauthorized: return 401
        case .notFound: return 404
        case .serviceUnavailable: return 503
        case .internalServerError: return 500
        }
    }
    
    var reason: String {
        switch self {
        case .ok: return "OK"
        case .badRequest: return "Bad Request"
        case .unauthorized: return "Unauthorized"
        case .notFound: return "Not Found"
        case .serviceUnavailable: return "Service Unavailable"
        case .internalServerError: return "Internal Server Error"
        }
    }
}

// MARK: - API Response Models

struct HealthResponse: Codable {
    let status: String
    let model: String
    let device: String
    let inference: String
}

struct ModelInfo: Codable {
    let id: String
    let object: String
    let ownedBy: String
}

struct ModelsListResponse: Codable {
    let object: String
    let data: [ModelInfo]
}

struct ChatMessageRequest: Codable {
    let role: String
    let content: String
}

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessageRequest]
    let temperature: Double?
    let maxTokens: Int?
    let stream: Bool?
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

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

struct ChatCompletionResponse: Codable {
    let id: String
    let object: String
    let choices: [Choice]
}

struct Delta: Codable {
    let content: String?
}

struct StreamChoice: Codable {
    let delta: Delta
}

struct StreamChunk: Codable {
    let choices: [StreamChoice]
}
