//
//  ModelsView.swift
//  LocalAIServer
//
//  Model management screen for browsing, downloading, and managing AI models
//

import SwiftUI

struct ModelsView: View {
    @EnvironmentObject var modelManager: ModelManager
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 350, maximum: 450), spacing: 16)], spacing: 16) {
                ForEach(modelManager.models) { model in
                    ModelCard(model: model)
                }
            }
            .padding(24)
            
            // Info Section
            ModelInfoSection()
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .navigationTitle("Models")
        .background(Color(.systemGroupedBackground))
        .refreshable {
            modelManager.loadSavedModels()
        }
    }
}

// MARK: - Model Card

struct ModelCard: View {
    @EnvironmentObject var modelManager: ModelManager
    @State private var showDeleteConfirmation = false
    @State private var isDownloading = false
    
    let model: AIModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with icon and status
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(modelColor)
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: modelIcon)
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.displayName)
                            .font(.headline)
                            .lineLimit(1)
                        
                        if modelManager.activeModel?.id == model.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                        }
                    }
                    
                    Text(model.provider)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
            }
            .padding(20)
            
            Divider()
                .padding(.horizontal, 20)
            
            // Specs
            HStack(spacing: 12) {
                SpecBadge(icon: "externaldrive.fill", text: model.formattedFileSize)
                SpecBadge(icon: "memorychip", text: model.formattedRAMRequirement)
                SpecBadge(icon: "number", text: model.quantization)
                SpecBadge(icon: "text.bubble", text: "\(model.contextLength) ctx")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            // Progress/State
            if model.state == .downloading {
                DownloadProgressView(model: model)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            } else if model.state == .validating {
                ValidatingProgressView()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            } else if model.state == .invalid {
                InvalidStateView()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
            
            // Action Button
            ActionButton(model: model, isDownloading: $isDownloading, showDeleteConfirmation: $showDeleteConfirmation)
                .padding(20)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
        )
        .confirmationDialog("Delete Model?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await modelManager.deleteModel(model)
                }
            }
        } message: {
            Text("This will remove \"\(model.displayName)\" from your device. You can download it again later.")
        }
    }
    
    private var modelColor: Color {
        switch model.provider.lowercased() {
        case "qwen": return .orange
        case "meta": return .blue
        default: return .gray
        }
    }
    
    private var modelIcon: String {
        switch model.provider.lowercased() {
        case "qwen": return "brain.head.profile"
        case "meta": return "sparkles"
        default: return "doc"
        }
    }
}

struct SpecBadge: View {
    let icon: String
    let text: String
    
    var body: some View {
        Label {
            Text(text)
                .font(.caption2.weight(.medium))
        } icon: {
            Image(systemName: icon)
                .font(.caption2)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(.systemGray6))
        .cornerRadius(6)
    }
}

struct DownloadProgressView: View {
    let model: AIModel
    
    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: model.downloadProgress)
                .progressViewStyle(.linear)
                .frame(height: 6)
                .tint(.blue)
            
            HStack {
                Text("\(model.progressPercentage)")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.blue)
                
                Spacer()
                
                Text("\(model.formattedDownloadedSize) / \(model.formattedTotalSize)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct ValidatingProgressView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.8)
            
            Text("Validating download...")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(12)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
}

struct InvalidStateView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            
            Text("Invalid model file")
                .font(.caption)
                .foregroundColor(.red)
            
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Action Button

struct ActionButton: View {
    @EnvironmentObject var modelManager: ModelManager
    @State private var isLoading = false
    
    let model: AIModel
    @Binding var isDownloading: Bool
    @Binding var showDeleteConfirmation: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            switch model.state {
            case .notDownloaded:
                Button(action: startDownload) {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isLoading)
                
            case .downloading:
                ProgressView()
                    .scaleEffect(0.9)
                    .frame(maxWidth: .infinity)
                
            case .validating:
                ProgressView()
                    .scaleEffect(0.9)
                    .frame(maxWidth: .infinity)
                
            case .invalid:
                Button(action: retry) {
                    Label("Retry Validation", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .foregroundColor(.red)
                
            case .downloaded, .installed:
                if modelManager.activeModel?.id == model.id {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Loaded & Active")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.green)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(10)
                } else {
                    Button(action: loadModel) {
                        Label("Load Model", systemImage: "arrow.up.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isLoading || modelManager.isLoadingModel)
                }
                
            case .loading:
                ProgressView()
                    .scaleEffect(0.9)
                    .frame(maxWidth: .infinity)
                
            case .loaded:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Loaded & Active")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.green.opacity(0.1))
                .cornerRadius(10)
                
            case .error:
                Button(action: retry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
            default:
                EmptyView()
            }
            
            // Delete button for downloaded models
            if model.isDownloaded && modelManager.activeModel?.id != model.id {
                Button(action: { showDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }
    
    private func startDownload() {
        isLoading = true
        Task {
            do {
                try await modelManager.downloadModel(model)
            } catch {
                print("Download error: \(error)")
            }
            isLoading = false
        }
    }
    
    private func loadModel() {
        isLoading = true
        Task {
            await modelManager.loadModel(model)
            isLoading = false
        }
    }
    
    private func retry() {
        if model.state == .invalid {
            Task {
                try? await modelManager.installModel(model)
            }
        } else if model.state == .error {
            Task {
                await modelManager.loadModel(model)
            }
        }
    }
}

// MARK: - Model Info Section

struct ModelInfoSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Model Information")
                .font(.headline)
            
            VStack(spacing: 12) {
                ModelsInfoRow(icon: "externaldrive.fill", title: "Storage Location", detail: "App Documents/Models", color: .blue)
                ModelsInfoRow(icon: "memorychip", title: "Hardware Acceleration", detail: "Metal GPU (M-series iPads)", color: .orange)
                ModelsInfoRow(icon: "wifi.slash", title: "Offline Inference", detail: "No internet required after download", color: .green)
                ModelsInfoRow(icon: "lock.shield", title: "Privacy", detail: "All inference happens locally on device", color: .purple)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
        )
    }
}

struct ModelsInfoRow: View {
    let icon: String
    let title: String
    let detail: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    ModelsView()
        .environmentObject(ModelManager.shared)
}