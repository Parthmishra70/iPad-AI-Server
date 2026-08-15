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
        NavigationView {
            List {
                Section(header: Text("Available Models")) {
                    ForEach(modelManager.models) { model in
                        ModelRow(model: model)
                    }
                }
                
                Section(header: Text("Model Information")) {
                    VStack(alignment: .leading, spacing: 12) {
                        InfoItem(icon: "externaldrive.fill", 
                                title: "Storage Location", 
                                detail: "App Documents/Models")
                        
                        InfoItem(icon: "memorychip", 
                                title: "Hardware Acceleration", 
                                detail: "GPU & Neural Engine")
                        
                        InfoItem(icon: "wifi.slash", 
                                title: "Offline Inference", 
                                detail: "No internet required after download")
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Models")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refreshModels) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }
    
    private func refreshModels() {
        modelManager.loadSavedModels()
    }
}

// MARK: - Model Row

struct ModelRow: View {
    @EnvironmentObject var modelManager: ModelManager
    @State private var showDeleteConfirmation = false
    @State private var isDownloading = false
    
    let model: AIModel
    
    var body: some View {
        HStack(spacing: 16) {
            // Model Icon
            ZStack {
                Circle()
                    .fill(modelColor)
                    .frame(width: 50, height: 50)
                
                Image(systemName: modelIcon)
                    .font(.title3)
                    .foregroundColor(.white)
            }
            
            // Model Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.displayName)
                        .font(.headline)
                    
                    if modelManager.activeModel?.id == model.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack(spacing: 12) {
                    Label(model.formattedFileSize, systemImage: "externaldrive.fill")
                    Label(model.formattedRAMRequirement, systemImage: "memorychip")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                
                // Progress bar for downloads
                if model.state == .downloading {
                    ProgressView(value: model.downloadProgress)
                        .progressViewStyle(.linear)
                        .frame(height: 4)
                    
                    Text("\(model.progressPercentage) • \(model.formattedDownloadedSize) / \(model.formattedTotalSize)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Action Button
            ActionButton(model: model, isDownloading: $isDownloading, showDeleteConfirmation: $showDeleteConfirmation)
        }
        .padding(.vertical, 4)
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
        switch model.name {
        case "gemma": return .purple
        case "gemma-3b": return .indigo
        case "phi-3-mini": return .blue
        default: return .gray
        }
    }
    
    private var modelIcon: String {
        switch model.name {
        case "gemma": return "sparkles"
        case "gemma-3b": return "brain.head.profile"
        case "phi-3-mini": return "cpu"
        default: return "doc"
        }
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
        Group {
            switch model.state {
            case .notDownloaded:
                Button(action: startDownload) {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .disabled(isLoading)
                
            case .downloading:
                ProgressView()
                    .scaleEffect(0.8)
                
            case .downloaded, .installed:
                if modelManager.activeModel?.id == model.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Button(action: loadModel) {
                        Label("Load", systemImage: "arrow.up.circle.fill")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(isLoading || modelManager.isLoadingModel)
                }
                
            case .loading:
                ProgressView()
                    .scaleEffect(0.8)
                
            case .loaded:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                
            case .error:
                Button(action: retry) {
                    Image(systemName: "arrow.clockwise")
                }
                
            default:
                EmptyView()
            }
        }
        .buttonStyle(.bordered)
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
        // Reset state and retry
    }
}

// MARK: - Info Item

struct InfoItem: View {
    let icon: String
    let title: String
    let detail: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    ModelsView()
        .environmentObject(ModelManager.shared)
}
