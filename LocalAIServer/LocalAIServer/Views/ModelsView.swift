//
//  ModelsView.swift
//  LocalAIServer
//
//  Model management screen for browsing, downloading, and managing AI models
//

import SwiftUI

struct ModelsView: View {
    @EnvironmentObject var modelManager: ModelManager
    @State private var searchText: String = ""
    
    private var filteredModels: [AIModel] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return modelManager.models }
        return modelManager.models.filter { model in
            model.displayName.localizedCaseInsensitiveContains(trimmed) ||
            model.name.localizedCaseInsensitiveContains(trimmed) ||
            model.provider.localizedCaseInsensitiveContains(trimmed) ||
            model.quantization.localizedCaseInsensitiveContains(trimmed) ||
            model.description.localizedCaseInsensitiveContains(trimmed) ||
            model.hfRepo.localizedCaseInsensitiveContains(trimmed)
        }
    }
    
    var body: some View {
        ScrollView {
            if modelManager.isLoadingModels {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 350, maximum: 450), spacing: 16)], spacing: 16) {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonModelCard()
                    }
                }
                .padding(24)
                
                SkeletonSection(height: 180)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            } else {
                if filteredModels.isEmpty && !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    // No local matches — show empty state for the catalog and surface the HF live search below.
                    EmptySearchResultsView(query: searchText)
                        .padding(.vertical, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 350, maximum: 450), spacing: 16)], spacing: 16) {
                        ForEach(filteredModels) { model in
                            ModelCard(model: model)
                        }
                    }
                    .padding(24)
                }
                
                // Live HuggingFace search: appears whenever the user has typed a query.
                HuggingFaceSearchSection(query: searchText)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                
                // Info Section (only when not searching)
                if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    ModelInfoSection()
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Models")
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await modelManager.loadSavedModels()
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search models by name, provider, or quantization")
    }
}

struct EmptySearchResultsView: View {
    let query: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundColor(.secondary.opacity(0.6))
            
            VStack(spacing: 6) {
                Text("No local models match \u{201C}\(query)\u{201D}")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Try a broader query, or browse HuggingFace below.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct EmptyModelsView: View {
    @EnvironmentObject var modelManager: ModelManager
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundColor(.blue)
            }
            
            VStack(spacing: 12) {
                Text("No Models Downloaded")
                    .font(.title2.bold())
                
                Text("Download a model from the available list to start running AI inference locally on your iPad.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            VStack(spacing: 12) {
                ForEach(AIModel.availableModels) { model in
                    AvailableModelRow(model: model)
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 40)
    }
}

struct AvailableModelRow: View {
    @EnvironmentObject var modelManager: ModelManager
    let model: AIModel
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 12) {
                    Label(model.formattedFileSize, systemImage: "externaldrive.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Label(model.formattedRAMRequirement, systemImage: "memorychip")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Label(model.quantization, systemImage: "number")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if model.state == .downloading || model.state == .validating {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button(action: startDownload) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .disabled(model.state == .downloading || model.state == .validating)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private func startDownload() {
        Task {
            try? await modelManager.downloadModel(model)
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
                .tint(Color(.systemBlue))
            
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
        .background(Color(.systemBlue).opacity(0.15))
        .cornerRadius(8)
    }
}

struct InvalidStateView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(.systemRed))
            
            Text("Invalid model file")
                .font(.caption)
                .foregroundColor(Color(.systemRed))
            
            Spacer()
        }
        .padding(12)
        .background(Color(.systemRed).opacity(0.15))
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
                            .foregroundColor(Color(.systemGreen))
                        Text("Loaded & Active")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(Color(.systemGreen))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemGreen).opacity(0.15))
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
                        .foregroundColor(Color(.systemGreen))
                    Text("Loaded & Active")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Color(.systemGreen))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemGreen).opacity(0.15))
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

// MARK: - HuggingFace Live Search

struct HuggingFaceSearchSection: View {
    @EnvironmentObject var modelManager: ModelManager
    let query: String
    
    @State private var results: [HuggingFaceModel] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var debounceTask: Task<Void, Never>?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundColor(.orange)
                Text("HuggingFace")
                    .font(.headline)
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Spacer()
            }
            
            if query.trimmingCharacters(in: .whitespaces).count < 2 {
                Text("Type at least 2 characters to search the HuggingFace Hub for GGUF models.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .font(.caption)
                }
            } else if results.isEmpty && !isLoading {
                Text("No GGUF models found for \u{201C}\(query)\u{201D}.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(results) { model in
                        NavigationLink(value: HFSearchRoute.repo(model.id)) {
                            HuggingFaceModelRow(model: model)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
        )
        .onChange(of: query) { _, newValue in
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000) // 350ms debounce
                if Task.isCancelled { return }
                await runSearch(query: newValue)
            }
        }
        .navigationDestination(for: HFSearchRoute.self) { route in
            switch route {
            case .repo(let id):
                HuggingFaceFilesView(repoId: id)
            }
        }
    }
    
    private func runSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            errorMessage = nil
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let r = try await HuggingFaceService.shared.searchModels(query: trimmed)
            results = r
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
    }
}

enum HFSearchRoute: Hashable {
    case repo(String)
}

struct HuggingFaceModelRow: View {
    let model: HuggingFaceModel
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.orange)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(model.id)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 10) {
                    if let author = model.author, !author.isEmpty {
                        Label(author, systemImage: "person.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let downloads = model.downloads {
                        Label(formatCount(downloads), systemImage: "arrow.down.circle")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if model.hasGGUFTag {
                        Label("GGUF", systemImage: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

struct HuggingFaceFilesView: View {
    @EnvironmentObject var modelManager: ModelManager
    let repoId: String
    
    @State private var files: [HuggingFaceFile] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pickingFile: HuggingFaceFile?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading files from \(repoId)…")
                    }
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                } else if files.isEmpty {
                    Text("No .gguf files found in this repository.")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(files) { file in
                        Button {
                            pickingFile = file
                        } label: {
                            HuggingFaceFileRow(file: file)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle(repoId)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .sheet(item: $pickingFile) { file in
            AddCustomModelSheet(repoId: repoId, file: file) { model in
                modelManager.addCustomModel(model)
                pickingFile = nil
            }
            .presentationDetents([.medium, .large])
        }
    }
    
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            files = try await HuggingFaceService.shared.listFiles(repoId: repoId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct HuggingFaceFileRow: View {
    let file: HuggingFaceFile
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.fill")
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(file.filename)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Label(file.quantization, systemImage: "number")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let size = file.sizeGB {
                        Label(String(format: "%.2f GB", size), systemImage: "externaldrive")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

struct AddCustomModelSheet: View {
    @Environment(\.dismiss) private var dismiss
    let repoId: String
    let file: HuggingFaceFile
    let onAdd: (AIModel) -> Void
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(file.filename)
                        .font(.headline)
                    if let size = file.sizeGB {
                        Text(String(format: "%.2f GB · %@", size, file.quantization))
                            .foregroundColor(.secondary)
                    }
                }
                
                if let sizeGB = file.sizeGB {
                    let physicalRAM = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
                    let requiredRAM = max(2.0, (sizeGB * 1.5).rounded(.up))
                    if requiredRAM > physicalRAM {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("May not fit on this device", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.orange)
                            Text("This file likely needs ~\(Int(requiredRAM)) GB of RAM. Your iPad reports ~\(String(format: "%.1f", physicalRAM)) GB. You can still download, but loading may fail.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(10)
                    }
                }
                
                Spacer()
                
                Button {
                    let model = AIModel.fromHuggingFace(repoId: repoId, file: file)
                    onAdd(model)
                    Task {
                        try? await ModelManager.shared.downloadModel(model)
                    }
                    dismiss()
                } label: {
                    Label("Download & Add", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(20)
            .navigationTitle("Add Custom Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ModelsView()
        .environmentObject(ModelManager.shared)
}