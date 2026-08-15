//
//  DashboardView.swift
//  LocalAIServer
//
//  Main dashboard showing server status and quick actions
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var serverManager: ServerManager
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Server Status Card
                    ServerStatusCard()
                    
                    // Active Model Card
                    ActiveModelCard()
                    
                    // Network Info Card
                    NetworkInfoCard()
                    
                    // Quick Stats
                    QuickStatsCard()
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .refreshable {
                await serverManager.startServer()
            }
        }
    }
}

// MARK: - Server Status Card

struct ServerStatusCard: View {
    @EnvironmentObject var serverManager: ServerManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("Local AI Server")
                    .font(.title2.bold())
                
                Spacer()
                
                StatusIndicator(isRunning: serverManager.isRunning)
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(serverManager.isRunning ? "Running" : "Stopped")
                            .fontWeight(.medium)
                    } icon: {
                        Circle()
                            .fill(serverManager.isRunning ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                    }
                    
                    if let ip = serverManager.ipAddress {
                        Text("IP: \(ip)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: toggleServer) {
                    Label(
                        serverManager.isRunning ? "Stop" : "Start",
                        systemImage: serverManager.isRunning ? "stop.fill" : "play.fill"
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(serverManager.isRunning ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(serverManager.errorMessage != nil)
            }
            
            if let error = serverManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4)
    }
    
    private func toggleServer() {
        Task {
            if serverManager.isRunning {
                serverManager.stopServer()
            } else {
                await serverManager.startServer()
            }
        }
    }
}

// MARK: - Active Model Card

struct ActiveModelCard: View {
    @EnvironmentObject var modelManager: ModelManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Active Model")
                    .font(.headline)
            } icon: {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.purple)
            }
            
            Divider()
            
            if let model = modelManager.activeModel {
                Text(model.displayName)
                    .font(.title2.bold())
                
                HStack(spacing: 16) {
                    Label {
                        Text(model.formattedFileSize)
                    } icon: {
                        Image(systemName: "externaldrive.fill")
                    }
                    
                    Label {
                        Text(model.format.rawValue)
                    } icon: {
                        Image(systemName: "doc.badge.gearshape")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                if modelManager.isLoadingModel {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading model...")
                            .font(.caption)
                    }
                }
            } else {
                Text("No model loaded")
                    .foregroundColor(.secondary)
                
                NavigationLink(destination: ModelsView()) {
                    Text("Browse Models")
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4)
    }
}

// MARK: - Network Info Card

struct NetworkInfoCard: View {
    @EnvironmentObject var serverManager: ServerManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Network Information")
                    .font(.headline)
            } icon: {
                Image(systemName: "wifi")
                    .foregroundColor(.orange)
            }
            
            Divider()
            
            if let ip = serverManager.ipAddress {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: "IP Address", value: ip)
                    InfoRow(label: "Port", value: "\(serverManager.port)")
                    InfoRow(label: "API Endpoint", value: serverManager.apiEndpoint ?? "Unknown")
                }
                
                HStack(spacing: 12) {
                    Button(action: copyEndpoint) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
                    NavigationLink(destination: QRCodeView(endpoint: serverManager.apiEndpoint ?? "")) {
                        Label("QR Code", systemImage: "qrcode")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("Not connected to network")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4)
    }
    
    private func copyEndpoint() {
        if let endpoint = serverManager.apiEndpoint {
            UIPasteboard.general.string = endpoint
        }
    }
}

// MARK: - Quick Stats Card

struct QuickStatsCard: View {
    @EnvironmentObject var serverManager: ServerManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Statistics")
                    .font(.headline)
            } icon: {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.green)
            }
            
            Divider()
            
            HStack(spacing: 24) {
                StatBox(title: "Requests", value: "\(serverManager.requestCount)")
                StatBox(title: "Last Request", value: formatLastRequest())
                StatBox(title: "Uptime", value: formatUptime())
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4)
    }
    
    private func formatLastRequest() -> String {
        guard let last = serverManager.lastRequestTime else { return "-" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: last, relativeTo: Date())
    }
    
    private func formatUptime() -> String {
        guard let uptime = serverManager.uptime else { return "-" }
        
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

// MARK: - Helper Views

struct StatusIndicator: View {
    let isRunning: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Text(isRunning ? "Running" : "Stopped")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption.monospaced())
                .fontWeight(.medium)
        }
    }
}

struct StatBox: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack {
            Text(value)
                .font(.title3.bold())
                .minimumScaleFactor(0.5)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct QRCodeView: View {
    let endpoint: String
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Scan to Connect")
                .font(.title2.bold())
            
            // Placeholder for QR code
            // In production, use a QR code generation library
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .frame(width: 200, height: 200)
                
                VStack {
                    Image(systemName: "qrcode")
                        .font(.system(size: 60))
                        .foregroundColor(.black)
                    
                    Text(endpoint)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
            }
            
            Text(endpoint)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
        .padding()
    }
}

#Preview {
    DashboardView()
        .environmentObject(ModelManager.shared)
        .environmentObject(ServerManager.shared)
}
