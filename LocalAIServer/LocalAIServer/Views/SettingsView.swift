//
//  SettingsView.swift
//  LocalAIServer
//
//  App settings and configuration screen
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var serverManager: ServerManager
    
    @AppStorage("showAdvancedSettings") private var showAdvancedSettings = false
    @AppStorage("enableLogging") private var enableLogging = false
    
    var body: some View {
        NavigationView {
            Form {
                // App Information Section
                Section(header: Text("About")) {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Build", value: "1")
                    
                    Link(destination: URL(string: "https://github.com")!) {
                        HStack {
                            Text("Source Code")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Server Settings Section
                Section(header: Text("Server Settings")) {
                    Toggle("Enable Request Logging", isOn: $enableLogging)
                    
                    if showAdvancedSettings {
                        Picker("Max Connections", selection: .constant(10)) {
                            Text("5").tag(5)
                            Text("10").tag(10)
                            Text("20").tag(20)
                            Text("50").tag(50)
                        }
                        
                        Toggle("Verbose Logging", isOn: .constant(false))
                    }
                    
                    Toggle("Show Advanced Settings", isOn: $showAdvancedSettings)
                }
                
                // Storage Section
                Section(header: Text("Storage")) {
                    StorageInfoRow(title: "Models Directory", value: "Documents/Models")
                    StorageInfoRow(title: "Downloaded Models", value: "\(downloadedModelsCount)")
                    StorageInfoRow(title: "Total Size", value: totalModelsSize)
                    
                    Button(role: .destructive) {
                        clearCache()
                    } label: {
                        Label("Clear Cache", systemImage: "trash")
                    }
                }
                
                // Device Info Section
                Section(header: Text("Device Information")) {
                    DeviceInfoRow(label: "Device Name", value: UIDevice.current.name)
                    DeviceInfoRow(label: "Model", value: deviceModel)
                    DeviceInfoRow(label: "iOS Version", value: UIDevice.current.systemVersion)
                    DeviceInfoRow(label: "Memory", value: deviceMemory)
                }
                
                // Privacy & Security Section
                Section(header: Text("Privacy & Security")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.green)
                            Text("Local-Only Access")
                                .font(.headline)
                        }
                        
                        Text("The server only accepts connections from your local network by default. API key authentication provides an additional layer of security.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "eye.slash.fill")
                                .foregroundColor(.blue)
                            Text("No Cloud Processing")
                                .font(.headline)
                        }
                        
                        Text("All AI inference happens entirely on your device. No prompts or responses are sent to external servers.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                // iPadOS Limitations Section
                Section(header: Text("Important Notes")) {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoNote(icon: "clock.fill", iconColor: .orange, text: "Background Execution Limited")
                        Text("The server may stop when the app is in the background due to iPadOS restrictions. Keep the app active for continuous availability.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        InfoNote(icon: "thermometer.medium.fill", iconColor: .red, text: "Thermal Management")
                        Text("Extended inference sessions may cause device warming. The app will automatically throttle performance if needed.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        InfoNote(icon: "battery.50", iconColor: .green, text: "Battery Impact")
                        Text("Running AI inference consumes significant power. Consider keeping your iPad plugged in during extended use.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Settings")
        }
    }
    
    // MARK: - Computed Properties
    
    private var downloadedModelsCount: Int {
        modelManager.models.filter { $0.isDownloaded }.count
    }
    
    private var totalModelsSize: String {
        let totalGB = modelManager.models
            .filter { $0.isDownloaded }
            .reduce(0.0) { $0 + $1.fileSizeGB }
        
        if totalGB >= 1 {
            return String(format: "%.1f GB", totalGB)
        } else {
            return String(format: "%.0f MB", totalGB * 1024)
        }
    }
    
    private var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? UInt8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(value))
        }
        return identifier
    }
    
    private var deviceMemory: String {
        // This is an approximation since iOS doesn't expose exact RAM
        return "4-16 GB (varies by model)"
    }
    
    // MARK: - Actions
    
    private func clearCache() {
        // Implement cache clearing logic
    }
}

// MARK: - Helper Views

struct StorageInfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

struct DeviceInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        LabeledContent(label, value: value)
    }
}

struct InfoNote: View {
    let icon: String
    let iconColor: Color
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
            Text(text)
                .font(.subheadline.bold())
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(ModelManager.shared)
        .environmentObject(ServerManager.shared)
}
