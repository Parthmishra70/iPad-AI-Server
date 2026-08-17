//
//  ModelsView.swift
//  LocalAIServer
//
//  Model management screen for browsing, downloading, and managing AI models
//

import SwiftUI

struct ModelsView: View {
    @EnvironmentObject var modelManager: ModelManager
    @ObservedObject private var appRouter = AppRouter.shared
    @Binding var selectedTab: Tab
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
                            ModelCard(model: model, selectedTab: $selectedTab)
                        }
                    }
                    .padding(24)
                }
                
                // Live HuggingFace search: appears whenever the user has typed a query.
                HuggingFaceSearchSection(query: searchText, selectedTab: $selectedTab)
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
        .onChange(of: appRouter.pendingHFSearchQuery) { _, newValue in
            if let query = newValue {
                searchText = query
                appRouter.pendingHFSearchQuery = nil
            }
        }
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
    let selectedTab: Binding<Tab>
    
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
            ActionButton(
                model: model,
                isDownloading: $isDownloading,
                showDeleteConfirmation: $showDeleteConfirmation,
                selectedTab: selectedTab
            )
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
    let selectedTab: Binding<Tab>
    
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
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(.systemGreen))
                        Text("Loaded")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(Color(.systemGreen))
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .background(Color(.systemGreen).opacity(0.15))
                    .cornerRadius(10)

                    Button {
                        selectedTab.wrappedValue = .chat
                    } label: {
                        Label("Chat", systemImage: "bubble.left.fill")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color(.systemGreen))
                }
                
            case .error:
                VStack(spacing: 8) {
                    Button(action: retry) {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    if isOOMError && !model.hfRepo.isEmpty {
                        Button {
                            AppRouter.shared.requestHFSearch(repoId: model.hfRepo)
                        } label: {
                            Label("Browse smaller variants", systemImage: "arrow.down.right.and.arrow.up.left")
                                .font(.caption.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(.orange)
                    }
                }
                
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

    /// True when the model's error is specifically a context-allocation
    /// OOM (the model's trained n_ctx exceeded available RAM on the
    /// iPad). Drives the "Browse smaller variants" deep-link to a
    /// lower-quantization alternative in the same repo.
    private var isOOMError: Bool {
        guard let msg = model.errorMessage else { return false }
        return msg.localizedCaseInsensitiveContains("context window") ||
               msg.localizedCaseInsensitiveContains("OOM") ||
               msg.localizedCaseInsensitiveContains("allocate")
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
    @Binding var selectedTab: Tab
    
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
                HuggingFaceFilesView(repoId: id, selectedTab: $selectedTab)
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
            errorMessage = HuggingFaceError.wrap(error).errorDescription
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
    @Binding var selectedTab: Tab

    @State private var files: [HuggingFaceFile] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var errorIsGated = false
    @State private var pickingFile: HuggingFaceFile?
    @State private var excludeBaseModels = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // If a model from THIS repo is currently downloading (e.g.
                // the user tapped "Hide" in the sheet), surface a compact
                // banner with progress and a hop-back-to-catalog button.
                if let downloading = activeDownloadFromThisRepo {
                    DownloadingFromRepoBanner(model: downloading, selectedTab: $selectedTab)
                        .padding(.bottom, 4)
                }

                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.1)
                        Text("Loading files from \(repoId)…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
                } else if let errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: errorIsGated ? "lock.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(errorIsGated ? .orange : .red)
                            Text(errorIsGated ? "Gated repository" : "Couldn't load files")
                                .font(.headline)
                        }
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if errorIsGated {
                            Text("Tip: try a public repo like Qwen/Qwen2.5-1.5B-Instruct-GGUF or bartowski/Llama-3.2-3B-Instruct-GGUF.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if files.isEmpty {
                    VStack(spacing: 10) {
                        Text("No \(excludeBaseModels ? "instruct-tuned " : "")GGUF files found.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if excludeBaseModels {
                            Text("This repo may only contain base models. Toggle 'Show base models' below to list every GGUF verbatim.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding(.vertical, 30)
                    .frame(maxWidth: .infinity)
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

                if !isLoading && errorMessage == nil {
                    Toggle("Show base models", isOn: $excludeBaseModels)
                        .padding(.top, 10)
                        .onChange(of: excludeBaseModels) { _, _ in
                            Task { await load() }
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
            AddCustomModelSheet(
                repoId: repoId,
                file: file,
                selectedTab: $selectedTab,
                onAdd: { model in
                    modelManager.addCustomModel(model)
                    pickingFile = nil
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        errorIsGated = false
        defer { isLoading = false }
        do {
            files = try await HuggingFaceService.shared.listFiles(
                repoId: repoId,
                excludeBaseModels: excludeBaseModels
            )
        } catch let hf as HuggingFaceError {
            errorIsGated = (hf == .gatedRepo)
            errorMessage = hf.errorDescription
        } catch {
            errorMessage = HuggingFaceError.wrap(error).errorDescription
        }
    }

    /// If a model sourced from THIS repo is mid-download, return it so the
    /// banner shows progress + a Go-to-Models short-cut.
    private var activeDownloadFromThisRepo: AIModel? {
        modelManager.models.first { model in
            (model.state == .downloading || model.state == .validating) &&
            model.hfRepo == repoId
        }
    }
}

private struct DownloadingFromRepoBanner: View {
    let model: AIModel
    @Binding var selectedTab: Tab
    @EnvironmentObject var modelManager: ModelManager

    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: model.downloadProgress)
                .tint(.blue)
                .frame(width: 80)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("\(Int(model.downloadProgress * 100))% · \(model.formattedDownloadedSize) / \(model.formattedTotalSize)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                selectedTab = .models
            } label: {
                Label("Go to Models", systemImage: "arrow.right.circle")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBlue).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
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
                    if !file.looksLikeInstruct {
                        Label("base", systemImage: "exclamationmark.triangle")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.orange)
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
    @EnvironmentObject var modelManager: ModelManager
    let repoId: String
    let file: HuggingFaceFile
    @Binding var selectedTab: Tab
    let onAdd: (AIModel) -> Void

    @AppStorage(AppConstants.UserDefaultsKeys.autoNavigateToCatalog) private var autoNavigateToCatalog = false

    @State private var phase: Phase = .confirm
    @State private var addedModel: AIModel?
    @State private var loadError: String?

    /// Drives the 4 phases of the sheet's state machine.
    enum Phase: Equatable {
        case confirm
        case downloading
        case readyToLoad
        case loaded
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    fileHeader

                    ramWarning

                    if autoNavigateToCatalog && phase == .confirm {
                        autoNavNote
                    }

                    Spacer(minLength: 8)

                    phaseView
                }
                .padding(20)
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .disabled(phase == .downloading)
                }
            }
        }
        .onChange(of: phase) { _, new in
            if new == .loaded {
                // After successful load, give it a moment to render,
                // then auto-switch to the Chat tab so the user can
                // actually use the model they just downloaded.
                Task {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    await MainActor.run {
                        // Dismiss the toast that fired when the download
                        // finished — the user is already on the success
                        // path through the sheet.
                        ToastCenter.shared.dismiss()
                        dismiss()
                        selectedTab = .chat
                    }
                }
            }
        }
    }

    // MARK: - Phase UI

    @ViewBuilder
    private var phaseView: some View {
        switch phase {
        case .confirm:
            Button {
                startDownloadAndAdd()
            } label: {
                Label("Download & Add", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        case .downloading:
            downloadingCard

        case .readyToLoad:
            loadingHint
            Button {
                loadAddedModel()
            } label: {
                Label("Load Model", systemImage: "arrow.up.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(modelManager.isLoadingModel)

            Button {
                // Keep the model installed; just leave the sheet.
                dismiss()
            } label: {
                Text("Load from Models tab later")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

        case .loaded:
            VStack(spacing: 12) {
                Label("Loaded & Active", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundColor(.green)

                Text("Opening Chat…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var downloadingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView(value: currentProgress)
                .tint(.blue)
            HStack {
                Text("\(Int(currentProgress * 100))%")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(progressSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text("Downloading from \(repoId)…")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button {
                    if let m = addedModel {
                        modelManager.cancelDownload(for: m)
                    }
                    dismiss()
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .foregroundColor(.red)

                Button {
                    dismiss()
                } label: {
                    Label("Hide", systemImage: "eye.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }

    @ViewBuilder
    private var loadingHint: some View {
        if let m = addedModel {
            VStack(alignment: .leading, spacing: 4) {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.green)
                Text("\(file.filename) (\(String(format: "%.2f", m.fileSizeGB)) GB) is ready to load.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 4)
        }
        if let err = loadError {
            Text(err)
                .font(.caption)
                .foregroundColor(.red)
                .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private var fileHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(file.filename)
                .font(.headline)
            if let size = file.sizeGB {
                Text(String(format: "%.2f GB · %@", size, file.quantization))
                    .foregroundColor(.secondary)
            }
            if !file.looksLikeInstruct {
                Label("Base model — may not chat well", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    @ViewBuilder
    private var ramWarning: some View {
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
    }

    @ViewBuilder
    private var autoNavNote: some View {
        Label("Auto-navigate to catalog is ON — the sheet will dismiss after you tap Download & Add.", systemImage: "info.circle")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.vertical, 4)
    }

    // MARK: - State

    private var currentProgress: Double {
        guard let m = addedModel,
              let idx = modelManager.models.firstIndex(where: { $0.id == m.id }) else {
            return 0
        }
        return modelManager.models[idx].downloadProgress
    }

    private var progressSize: String {
        guard let m = addedModel else { return "" }
        let downloaded = Int64(currentProgress * m.fileSizeGB * 1024 * 1024 * 1024)
        return "\(ByteCountFormatter.string(fromByteCount: max(0, downloaded), countStyle: .file)) / \(m.formattedTotalSize)"
    }

    private var navigationTitle: String {
        switch phase {
        case .confirm: return "Add Custom Model"
        case .downloading: return "Downloading"
        case .readyToLoad: return "Ready to Load"
        case .loaded: return "Ready to Chat"
        }
    }

    private func startDownloadAndAdd() {
        let model = AIModel.fromHuggingFace(repoId: repoId, file: file)
        addedModel = model
        onAdd(model)

        // Always kick off the download. The setting only changes whether
        // the sheet stays mounted as a download companion or dismisses
        // and routes the user back to the catalog row.
        let downloadTask = Task {
            do {
                try await modelManager.downloadModel(model)
                await MainActor.run {
                    if !autoNavigateToCatalog {
                        phase = .readyToLoad
                    }
                }
            } catch {
                await MainActor.run {
                    if !autoNavigateToCatalog {
                        if (error as? URLError)?.code == .cancelled {
                            phase = .confirm
                        } else {
                            loadError = error.localizedDescription
                            phase = .confirm
                        }
                    }
                }
            }
        }

        if autoNavigateToCatalog {
            // Dismiss the sheet AND pop back to the catalog so the user
            // can see the new model's row with live progress. The download
            // continues in the background; ModelManager emits a toast on
            // completion so the user can also act from anywhere.
            selectedTab = .models
            dismiss()
            return
        }

        phase = .downloading
        _ = downloadTask
    }

    private func loadAddedModel() {
        guard let m = addedModel else { return }
        loadError = nil
        Task {
            await modelManager.loadModel(m)
            await MainActor.run {
                // Check that load actually succeeded before transitioning
                if modelManager.activeModelId == m.id {
                    phase = .loaded
                } else if let idx = modelManager.models.firstIndex(where: { $0.id == m.id }),
                          case .error = modelManager.models[idx].state {
                    loadError = modelManager.models[idx].errorMessage
                    phase = .readyToLoad
                }
            }
        }
    }
}

#Preview {
    ModelsView(selectedTab: .constant(.models))
        .environmentObject(ModelManager.shared)
}