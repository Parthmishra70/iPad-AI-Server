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
    @EnvironmentObject var modelManager: ModelManager
    
    @State private var portText: String = "8080"
    @State private var showAPIKey = false
    @State private var generatedKey: String = ""
    @State private var showPortError = false
    @State private var portDebounceTask: Task<Void, Never>?
    
    var body: some View {
        Form {
            // Server Status Section
            Section {
                ServerStatusHeader()
            }
            
            // Network Configuration Section
            Section(header: SectionHeader(title: "Network Configuration", icon: "wifi", color: .blue)) {
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("Port", text: $portText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: portText) { _, newValue in
                            updatePort(newValue)
                        }
                        .onSubmit {
                            validatePort()
                        }
                }
                
                if let ip = serverManager.ipAddress {
                    LabeledContent("IP Address", value: ip)
                    
                    if let endpoint = serverManager.apiEndpoint {
                        LabeledContent("API Endpoint") {
                            Text(endpoint)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        HStack(spacing: 12) {
                            Button(action: { copyEndpoint(endpoint) }) {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            
                            NavigationLink(destination: QRCodeView(endpoint: endpoint)) {
                                Label("QR Code", systemImage: "qrcode")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }
                    }
                } else {
                    LabeledContent("IP Address") {
                        Label("Not connected", systemImage: "wifi.slash")
                            .foregroundColor(.secondary)
                    }
                }
                
                Toggle("Local Network Only", isOn: .constant(true))
                    .disabled(true)
                
                Text("For security, the server only accepts connections from your local network.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // API Key Section
            Section(header: SectionHeader(title: "API Authentication", icon: "key.fill", color: .orange)) {
                if apiKeyService.hasAPIKey {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label("API Key Configured", systemImage: "checkmark.shield.fill")
                                .foregroundColor(.green)
                            Spacer()
                        }
                        
                        if showAPIKey, let key = apiKeyService.getKey() {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(key)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .padding(12)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                                
                                Button(action: { copyAPIKey(key) }) {
                                    Label("Copy API Key", systemImage: "doc.on.doc")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        
                        HStack(spacing: 12) {
                            Button(action: { withAnimation(.spring()) { showAPIKey.toggle() } }) {
                                Label(showAPIKey ? "Hide" : "Show", systemImage: showAPIKey ? "eye.slash" : "eye")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            
                            Button(action: regenerateAPIKey) {
                                Label("Regenerate", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }
                        
                        Button(role: .destructive) {
                            deleteAPIKey()
                        } label: {
                            Label("Remove API Key", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("No API key configured. Generate one to enable authentication.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Button(action: generateAPIKey) {
                            Label("Generate API Key", systemImage: "key.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
            }
            
            // Active Model Section
            Section(header: SectionHeader(title: "Active Model", icon: "brain.head.profile", color: .purple)) {
                if let model = modelManager.activeModel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.displayName)
                            .font(.headline)
                        
                        HStack(spacing: 16) {
                            ModelInfoBadge(icon: "externaldrive.fill", text: model.formattedFileSize)
                            ModelInfoBadge(icon: "number", text: model.quantization)
                            ModelInfoBadge(icon: "text.bubble", text: "\(model.contextLength) ctx")
                        }
                        
                        Button {
                            AppRouter.shared.requestSwitch(to: .models)
                        } label: {
                            Label("Manage Models", systemImage: "arrow.right")
                        }
                    }
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.5))
                        
                        Text("No model loaded")
                            .foregroundColor(.secondary)
                        
                        Button {
                            AppRouter.shared.requestSwitch(to: .models)
                        } label: {
                            Label("Browse Models", systemImage: "arrow.right")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }
            
            // Usage Instructions
            Section(header: SectionHeader(title: "Usage Instructions", icon: "doc.text.fill", color: .green)) {
                VStack(alignment: .leading, spacing: 10) {
                    InstructionStep(number: 1, text: "Start the server using the toggle above")
                    InstructionStep(number: 2, text: "Note the IP address and port")
                    InstructionStep(number: 3, text: "Use any OpenAI-compatible client to connect")
                    InstructionStep(number: 4, text: "Include the API key in the Authorization header")
                }
                .padding(.vertical, 8)
                
                NavigationLink(destination: APIDocsView()) {
                    Label("View API Documentation", systemImage: "doc.text.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .navigationTitle("API Server")
        .onAppear {
            portText = "\(serverManager.port)"
        }
        .alert("Invalid Port", isPresented: $showPortError) {
            Button("OK") { }
        } message: {
            Text("Please enter a valid port number between 1 and 65535")
        }
    }
    
    // MARK: - Actions
    
    private func toggleServer() {
        Task {
            if serverManager.isRunning {
                await serverManager.stopServer()
            } else {
                await serverManager.startServer()
            }
        }
    }
    
    private func updatePort(_ value: String) {
        guard let port = Int(value), port > 0 && port < 65536 else {
            if !value.isEmpty { showPortError = true }
            return
        }

        // Debounce server restart so rapid typing doesn't flap the listener.
        portDebounceTask?.cancel()
        portDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }

            serverManager.port = port
            serverManager.saveConfiguration()

            if serverManager.isRunning {
                await serverManager.stopServer()
                try? await Task.sleep(nanoseconds: 500_000_000)
                await serverManager.startServer()
            }
        }
    }
    
    private func validatePort() {
        guard let port = Int(portText), port > 0 && port < 65536 else {
            showPortError = true
            portText = "\(serverManager.port)"
            return
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
    
    private func copyEndpoint(_ endpoint: String) {
        UIPasteboard.general.string = endpoint
    }
    
    private func copyAPIKey(_ key: String) {
        UIPasteboard.general.string = key
    }
    
    private func formatUptime() -> String {
        guard let uptime = serverManager.uptime else { return "—" }
        
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

// MARK: - Helper Views

struct ServerStatusHeader: View {
    @EnvironmentObject var serverManager: ServerManager
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Circle()
                    .fill(serverManager.isRunning ? Color(.systemGreen) : Color(.systemRed))
                    .frame(width: 16, height: 16)
                    .animation(.easeInOut(duration: 0.2), value: serverManager.isRunning)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(serverManager.isRunning ? "Server Running" : "Server Stopped")
                        .font(.headline)
                    
                    if let ip = serverManager.ipAddress {
                        Text("Accessible at \(ip):\(serverManager.port)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { serverManager.isRunning },
                    set: { _ in 
                        Task {
                            if serverManager.isRunning {
                                await serverManager.stopServer()
                            } else {
                                await serverManager.startServer()
                            }
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            
            if serverManager.isRunning {
                HStack(spacing: 24) {
                    StatPill(title: "Uptime", value: formatUptimeStatic(), icon: "clock", color: .blue)
                    StatPill(title: "Requests", value: "\(serverManager.requestCount)", icon: "network", color: .green)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func formatUptimeStatic() -> String {
        guard let uptime = serverManager.uptime else { return "—" }
        
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        let seconds = Int(uptime) % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(title)
                .font(.headline)
        }
    }
}

struct InstructionStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 24, height: 24)
                
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundColor(.accentColor)
            }
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

struct StatPill: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

struct ModelInfoBadge: View {
    let icon: String
    let text: String
    
    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon)
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

#Preview {
    ServerView()
        .environmentObject(ServerManager.shared)
        .environmentObject(APIKeyService.shared)
        .environmentObject(ModelManager.shared)
}