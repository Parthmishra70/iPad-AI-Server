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
    /// When true, tapping "Download & Add" in the HuggingFace file picker
    /// dismisses the sheet and routes the user to the catalog row showing
    /// progress. When false (default), the sheet stays mounted as a sticky
    /// download companion that transitions through Download -> Load -> Chat.
    @AppStorage(AppConstants.UserDefaultsKeys.autoNavigateToCatalog) private var autoNavigateToCatalog = false
    
    var body: some View {
        Form {
            // About Section
            Section {
                AboutCard()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            
            // Server Settings Section
            Section(header: SettingsSectionHeader(title: "Server Settings", icon: "server.rack", color: .blue)) {
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

            // HuggingFace Section
            Section(header: SettingsSectionHeader(title: "HuggingFace", icon: "globe", color: .orange)) {
                Toggle("Auto-navigate to catalog after add", isOn: $autoNavigateToCatalog)
                    .accessibilityHint("When on, tapping 'Download & Add' dismisses the sheet and routes you to the new model's catalog row. When off, the sheet stays mounted showing download progress, then transitions to Load and Start Chatting.")
            }
            
            // Storage Section
            Section(header: SettingsSectionHeader(title: "Storage", icon: "externaldrive.fill", color: .orange)) {
                StorageRow(title: "Models Directory", value: "Documents/Models")
                StorageRow(title: "Downloaded Models", value: "\(downloadedModelsCount)")
                StorageRow(title: "Total Size", value: totalModelsSize)
                
                Button(role: .destructive) {
                    clearCache()
                } label: {
                    Label("Clear Cache", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            
            // Device Info Section
            Section(header: SettingsSectionHeader(title: "Device Information", icon: "iphone.gen3.radiowaves.left.and.right", color: .purple)) {
                DeviceInfoRow(label: "Device Name", value: UIDevice.current.name, icon: "iphone", color: .blue)
                DeviceInfoRow(label: "Model", value: deviceModel, icon: "cpu", color: .orange)
                DeviceInfoRow(label: "iOS Version", value: UIDevice.current.systemVersion, icon: "gearshape", color: .green)
                DeviceInfoRow(label: "Available Memory", value: deviceMemory, icon: "memorychip", color: .purple)
                DeviceInfoRow(label: "Processor", value: "Apple M2", icon: "bolt", color: .red)
            }
            
            // Privacy & Security Section
            Section(header: SettingsSectionHeader(title: "Privacy & Security", icon: "lock.shield.fill", color: .green)) {
                PrivacyCard(
                    icon: "lock.shield.fill",
                    iconColor: .green,
                    title: "Local-Only Access",
                    description: "The server only accepts connections from your local network by default. API key authentication provides an additional layer of security."
                )
                
                PrivacyCard(
                    icon: "eye.slash.fill",
                    iconColor: .blue,
                    title: "No Cloud Processing",
                    description: "All AI inference happens entirely on your device. No prompts or responses are sent to external servers."
                )
                
                PrivacyCard(
                    icon: "key.fill",
                    iconColor: .orange,
                    title: "API Key Authentication",
                    description: "Every request (except /health) requires a valid Bearer token. Keys are stored securely in the iOS Keychain."
                )
            }
            
            // iPadOS Limitations Section
            Section(header: SettingsSectionHeader(title: "Important Notes", icon: "exclamationmark.triangle", color: .red)) {
                LimitationCard(
                    icon: "clock.fill",
                    iconColor: .orange,
                    title: "Background Execution Limited",
                    description: "The server may stop when the app is in the background due to iPadOS restrictions. Keep the app active for continuous availability."
                )
                
                LimitationCard(
                    icon: "thermometer.medium.fill",
                    iconColor: .red,
                    title: "Thermal Management",
                    description: "Extended inference sessions may cause device warming. The app will automatically throttle performance if needed."
                )
                
                LimitationCard(
                    icon: "battery.50",
                    iconColor: .green,
                    title: "Battery Impact",
                    description: "Running AI inference consumes significant power. Consider keeping your iPad plugged in during extended use."
                )
            }
            
            // Version Info
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("Local AI Server")
                            .font(.headline)
                        Text("Version 1.0.0 (Build 1)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Powered by llama.cpp & Metal")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
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
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let gb = Double(physicalMemory) / (1024 * 1024 * 1024)
        return String(format: "%.0f GB", gb)
    }
    
    // MARK: - Actions
    
    private func clearCache() {
        // Implement cache clearing logic
    }
}

// MARK: - Helper Views

struct SettingsSectionHeader: View {
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

struct AboutCard: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: .blue.opacity(0.3), radius: 12, x: 0, y: 6)
                
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 6) {
                Text("Local AI Server")
                    .font(.title2.bold())
                
                Text("Run AI models locally on your iPad with an OpenAI-compatible API")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            HStack(spacing: 16) {
                FeatureBadge(icon: "server.rack", text: "Local API")
                FeatureBadge(icon: "lock.shield", text: "Private")
                FeatureBadge(icon: "wifi.slash", text: "Offline")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
}

struct FeatureBadge: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct StorageRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
        }
    }
}

struct DeviceInfoRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(color)
            }
            
            Text(label)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

struct PrivacyCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }
}

struct LimitationCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(iconColor)
                }
                
                Text(title)
                    .font(.subheadline.bold())
            }
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 42)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    SettingsView()
        .environmentObject(ModelManager.shared)
        .environmentObject(ServerManager.shared)
}