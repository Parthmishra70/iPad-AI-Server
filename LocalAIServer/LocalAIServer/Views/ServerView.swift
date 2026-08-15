//
//  ServerView.swift
//  LocalAIServer
//
//  API Server configuration and status screen
//

import SwiftUI

struct ServerView: View {
    @EnvironmentObject var serverManager: ServerManager
    @EnvironmentObject var apiKeyService: APIKeyService
    
    @State private var portText: String = "8080"
    @State private var showAPIKey = false
    @State private var generatedKey: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                // Server Status Section
                Section(header: Text("Server Status")) {
                    HStack {
                        Circle()
                            .fill(serverManager.isRunning ? Color.green : Color.red)
                            .frame(width: 12, height: 12)
                        
                        Text(serverManager.isRunning ? "Running" : "Stopped")
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { serverManager.isRunning },
                            set: { _ in toggleServer() }
                        ))
                        .toggleStyle(.switch)
                    }
                    
                    if serverManager.isRunning {
                        LabeledContent("Uptime", value: formatUptime())
                        LabeledContent("Requests", value: "\(serverManager.requestCount)")
                    }
                }
                
                // Network Configuration Section
                Section(header: Text("Network Configuration")) {
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("Port", text: $portText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .onChange(of: portText) { newValue in
                                updatePort(newValue)
                            }
                    }
                    
                    LabeledContent("IP Address", value: serverManager.ipAddress ?? "Not connected")
                    
                    if let endpoint = serverManager.apiEndpoint {
                        LabeledContent("API Endpoint", value: endpoint)
                        
                        HStack {
                            Button(action: copyEndpoint(endpoint)) {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            
                            NavigationLink(destination: QRCodeView(endpoint: endpoint)) {
                                Label("QR Code", systemImage: "qrcode")
                            }
                        }
                    }
                    
                    Toggle("Local Network Only", isOn: .constant(true))
                        .disabled(true)
                    
                    Text("For security, the server only accepts connections from your local network by default.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // API Key Section
                Section(header: Text("API Authentication")) {
                    if apiKeyService.hasAPIKey {
                        HStack {
                            Text("API Key Status")
                            Spacer()
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)
                        }
                        
                        if showAPIKey, let key = apiKeyService.getKey() {
                            Text(key)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            
                            Button(action: copyAPIKey(key)) {
                                Label("Copy API Key", systemImage: "doc.on.doc")
                            }
                        }
                        
                        Button(action: regenerateAPIKey) {
                            Label("Regenerate API Key", systemImage: "arrow.clockwise")
                        }
                        
                        Button(role: .destructive) {
                            deleteAPIKey()
                        } label: {
                            Label("Remove API Key", systemImage: "trash")
                        }
                    } else {
                        Text("No API key configured. Generate one to enable authentication.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button(action: generateAPIKey) {
                            Label("Generate API Key", systemImage: "key.fill")
                        }
                    }
                }
                
                // Model Information Section
                Section(header: Text("Active Model")) {
                    if let model = ModelManager.shared.activeModel {
                        LabeledContent("Model", value: model.displayName)
                        LabeledContent("Format", value: model.format.rawValue)
                        LabeledContent("Size", value: model.formattedFileSize)
                    } else {
                        Text("No model loaded")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        NavigationLink(destination: ModelsView()) {
                            Label("Browse Models", systemImage: "arrow.right")
                        }
                    }
                }
                
                // Usage Instructions
                Section(header: Text("Usage Instructions")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Start the server using the toggle above")
                        Text("2. Note the IP address and port")
                        Text("3. Use any OpenAI-compatible client to connect")
                        Text("4. Include the API key in the Authorization header")
                    }
                    .font(.caption)
                    
                    NavigationLink(destination: APIDocsView()) {
                        Label("View API Documentation", systemImage: "doc.text.fill")
                    }
                }
            }
            .navigationTitle("API Server")
            .onAppear {
                portText = "\(serverManager.port)"
            }
        }
    }
    
    // MARK: - Actions
    
    private func toggleServer() {
        Task {
            if serverManager.isRunning {
                serverManager.stopServer()
            } else {
                await serverManager.startServer()
            }
        }
    }
    
    private func updatePort(_ value: String) {
        guard let port = Int(value), port > 0 && port < 65536 else { return }
        serverManager.port = port
        serverManager.saveConfiguration()
        
        // Restart server if running
        if serverManager.isRunning {
            Task {
                serverManager.stopServer()
                try? await Task.sleep(nanoseconds: 500_000_000)
                await serverManager.startServer()
            }
        }
    }
    
    private func generateAPIKey() {
        generatedKey = apiKeyService.generateNewKey()
        showAPIKey = true
    }
    
    private func regenerateAPIKey() {
        generatedKey = apiKeyService.generateNewKey()
        showAPIKey = true
    }
    
    private func deleteAPIKey() {
        apiKeyService.deleteKey()
        showAPIKey = false
    }
    
    private func copyEndpoint(_ endpoint: String) -> () -> Void {
        return {
            UIPasteboard.general.string = endpoint
        }
    }
    
    private func copyAPIKey(_ key: String) -> () -> Void {
        return {
            UIPasteboard.general.string = key
        }
    }
    
    private func formatUptime() -> String {
        guard let uptime = serverManager.uptime else { return "-" }
        
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        let seconds = Int(uptime) % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

#Preview {
    ServerView()
        .environmentObject(ServerManager.shared)
        .environmentObject(APIKeyService.shared)
}
