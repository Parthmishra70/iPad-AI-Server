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
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 20) {
                // Server Status Card
                ServerStatusCard()
                    .gridCellColumns(gridColumns.count == 1 ? 1 : 2)
                
                // Active Model Card
                ActiveModelCard()
                
                // Network Info Card
                NetworkInfoCard()
                
                // Quick Stats
                QuickStatsCard()
                    .gridCellColumns(gridColumns.count == 1 ? 1 : 2)
            }
            .padding(24)
            .animation(.easeInOut(duration: 0.3), value: gridColumns.count)
        }
        .navigationTitle("Dashboard")
        .refreshable {
            await serverManager.startServer()
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private var gridColumns: [GridItem] {
        // This will be determined by the geometry reader in practice
        // For now using adaptive columns that work well on iPad
        [GridItem(.adaptive(minimum: 380, maximum: 500), spacing: 20)]
    }
}

// MARK: - Server Status Card

struct ServerStatusCard: View {
    @EnvironmentObject var serverManager: ServerManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .symbolRenderingMode(.hierarchical)
                
                Text("Local AI Server")
                    .font(.title2.bold())
                
                Spacer()
                
                StatusIndicator(isRunning: serverManager.isRunning)
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 12) {
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
                    
                    if serverManager.isRunning {
                        Label("Ready for requests", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                Spacer()
                
                Button(action: toggleServer) {
                    Label(
                        serverManager.isRunning ? "Stop Server" : "Start Server",
                        systemImage: serverManager.isRunning ? "stop.fill" : "play.fill"
                    )
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(serverManager.isRunning ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .font(.headline)
                }
                .disabled(serverManager.errorMessage != nil)
                .buttonStyle(.plain)
            }
            
            if let error = serverManager.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
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
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Active Model")
                    .font(.headline)
            } icon: {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.purple)
                    .symbolRenderingMode(.hierarchical)
            }
            
            Divider()
            
            if let model = modelManager.activeModel {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.displayName)
                        .font(.title2.bold())
                        .lineLimit(1)
                    
                    HStack(spacing: 16) {
                        DashboardModelInfoBadge(icon: "externaldrive.fill", text: model.formattedFileSize)
                        DashboardModelInfoBadge(icon: "number", text: model.quantization)
                        DashboardModelInfoBadge(icon: "text.bubble", text: "\(model.contextLength) ctx")
                    }
                    
                    if modelManager.isLoadingModel {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading model...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                    
                    HStack {
                        Spacer()
                        NavigationLink(destination: ModelsView()) {
                            Label("Manage Models", systemImage: "arrow.right")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("No model loaded")
                        .foregroundColor(.secondary)
                        .font(.headline)
                    
                    NavigationLink(destination: ModelsView()) {
                        Label("Browse Models", systemImage: "arrow.right")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
    }
}

struct DashboardModelInfoBadge: View {
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

// MARK: - Network Info Card

struct NetworkInfoCard: View {
    @EnvironmentObject var serverManager: ServerManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Network Information")
                    .font(.headline)
            } icon: {
                Image(systemName: "wifi")
                    .foregroundColor(.orange)
                    .symbolRenderingMode(.hierarchical)
            }
            
            Divider()
            
            if let ip = serverManager.ipAddress {
                VStack(alignment: .leading, spacing: 12) {
                    DashboardInfoRow(label: "IP Address", value: ip)
                    DashboardInfoRow(label: "Port", value: "\(serverManager.port)")
                    DashboardInfoRow(label: "API Endpoint", value: serverManager.apiEndpoint ?? "Unknown")
                }
                
                HStack(spacing: 12) {
                    Button(action: copyEndpoint) {
                        Label("Copy Endpoint", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    
                    NavigationLink(destination: QRCodeView(endpoint: serverManager.apiEndpoint ?? "")) {
                        Label("QR Code", systemImage: "qrcode")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("Not connected to network")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    
                    Text("Connect to Wi-Fi to enable network access")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
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
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Statistics")
                    .font(.headline)
            } icon: {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.green)
                    .symbolRenderingMode(.hierarchical)
            }
            
            Divider()
            
            HStack(spacing: 0) {
                StatBox(title: "Total Requests", value: "\(serverManager.requestCount)")
                
                Divider()
                    .padding(.vertical, 16)
                
                StatBox(title: "Last Request", value: formatLastRequest())
                
                Divider()
                    .padding(.vertical, 16)
                
                StatBox(title: "Uptime", value: formatUptime())
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
    }
    
    private func formatLastRequest() -> String {
        guard let last = serverManager.lastRequestTime else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: last, relativeTo: Date())
    }
    
    private func formatUptime() -> String {
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

// MARK: - Helper Views

struct StatusIndicator: View {
    let isRunning: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)
                .animation(.easeInOut(duration: 0.2), value: isRunning)
            
            Text(isRunning ? "Running" : "Stopped")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(isRunning ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
        )
    }
}

struct DashboardInfoRow: View {
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
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct StatBox: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.title2.bold())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    DashboardView()
        .environmentObject(ModelManager.shared)
        .environmentObject(ServerManager.shared)
}