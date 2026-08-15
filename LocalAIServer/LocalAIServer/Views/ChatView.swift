//
 //  ChatView.swift
 //  LocalAIServer
 //
 //  Chat interface for testing local AI models
 //

import SwiftUI

// Local message type with timestamp for chat UI
struct LocalChatMessage: Identifiable {
    let id = UUID()
    let role: String
    let content: String
    let timestamp: Date
    
    init(role: String, content: String, timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
    
    init(from message: ChatMessage) {
        self.role = message.role
        self.content = message.content
        self.timestamp = Date()
    }
}

struct ChatView: View {
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var serverManager: ServerManager
    
    @State private var messages: [LocalChatMessage] = []
    @State private var inputText: String = ""
    @State private var isStreaming = false
    @State private var currentResponse: String = ""
    @State private var showModelNotLoadedAlert = false
    @State private var temperature: Double = 0.7
    @State private var maxTokens: Int = 512
    @State private var showSettings = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Model indicator header
                if let activeModel = modelManager.activeModel {
                    ActiveModelHeader(model: activeModel, isStreaming: isStreaming)
                } else {
                    NoModelHeader()
                }
                
                Divider()
                
                // Messages area
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if messages.isEmpty && !isStreaming {
                                EmptyStateView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 60)
                            }
                            
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            
                            if isStreaming {
                                StreamingResponseView(text: currentResponse)
                                    .id("streaming")
                            }
                        }
                        .padding(20)
                    }
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isStreaming) { _ in
                        if isStreaming {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("streaming", anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Input area
                ChatInputView(
                    inputText: $inputText,
                    isStreaming: isStreaming,
                    temperature: $temperature,
                    maxTokens: $maxTokens,
                    showSettings: $showSettings,
                    onSend: sendMessage
                )
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: clearChat) {
                        Image(systemName: "trash")
                            .foregroundColor(messages.isEmpty ? .secondary : .red)
                    }
                    .disabled(messages.isEmpty)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if let model = modelManager.activeModel {
                            Text("Model: \(model.displayName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Divider()
                        }
                        
                        Button(action: { showSettings = true }) {
                            Label("Settings", systemImage: "slider.horizontal.3")
                        }
                        
                        Button(role: .destructive, action: clearChat) {
                            Label("Clear Chat", systemImage: "trash")
                        }
                        .disabled(messages.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                ChatSettingsView(
                    temperature: $temperature,
                    maxTokens: $maxTokens
                )
            }
            .alert("No Model Loaded", isPresented: $showModelNotLoadedAlert) {
                Button("Load Model") {
                    // Navigate to models view would require more complex navigation
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please load a model from the Models tab before chatting.")
            }
        }
    }
    
    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard modelManager.activeModel != nil else {
            showModelNotLoadedAlert = true
            return
        }
        
        let userMessage = LocalChatMessage(role: "user", content: inputText)
        messages.append(userMessage)
        inputText = ""
        isStreaming = true
        currentResponse = ""
        
        Task {
            do {
                // Convert LocalChatMessage to ChatMessage for the API
                let chatMessages = messages.map { ChatMessage(role: $0.role, content: $0.content) }
                
                for try await token in modelManager.streamResponse(
                    messages: chatMessages,
                    temperature: temperature,
                    maxTokens: maxTokens
                ) {
                    await MainActor.run {
                        currentResponse += token
                    }
                }
                
                await MainActor.run {
                    let assistantMessage = LocalChatMessage(role: "assistant", content: currentResponse)
                    messages.append(assistantMessage)
                    currentResponse = ""
                    isStreaming = false
                }
            } catch {
                await MainActor.run {
                    let errorMessage = LocalChatMessage(
                        role: "assistant",
                        content: "Error: \(error.localizedDescription)"
                    )
                    messages.append(errorMessage)
                    currentResponse = ""
                    isStreaming = false
                }
            }
        }
    }
    
    private func clearChat() {
        messages.removeAll()
        currentResponse = ""
    }
}

// MARK: - Active Model Header

struct ActiveModelHeader: View {
    let model: AIModel
    let isStreaming: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(modelColor)
                    .frame(width: 36, height: 36)
                
                Image(systemName: modelIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(model.quantization)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .cornerRadius(4)
                    
                    Text("\(model.contextLength) ctx")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isStreaming {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Generating...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
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

// MARK: - No Model Header

struct NoModelHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("No Model Loaded")
                    .font(.subheadline.weight(.semibold))
                
                Text("Select a model from the Models tab")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            NavigationLink(destination: ModelsView()) {
                Text("Browse Models")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.accentColor)
            }
            
            VStack(spacing: 8) {
                Text("Start a Conversation")
                    .font(.title2.bold())
                
                Text("Type a message below to chat with your local AI model. All inference runs on-device.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: LocalChatMessage
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if message.role == "user" {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                assistantHeader
                
                messageContent
                    .background(bubbleBackground)
                    .foregroundColor(bubbleForeground)
                    .cornerRadius(18, corners: bubbleCorners)
                
                if message.role == "user" {
                    Text(formatTime(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.trailing, 4)
                }
            }
            
            if message.role == "assistant" {
                Spacer(minLength: 60)
            }
        }
    }
    
    @ViewBuilder
    private var assistantHeader: some View {
        if message.role == "assistant" {
            HStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 20, height: 20)
                    
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                Text("Assistant")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var messageContent: some View {
        Text(message.content)
            .font(.body)
            .textSelection(.enabled)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }
    
    private var bubbleBackground: Color {
        message.role == "user" ? Color.accentColor : Color(.systemGray5)
    }
    
    private var bubbleForeground: Color {
        message.role == "user" ? .white : .primary
    }
    
    private var bubbleCorners: UIRectCorner {
        message.role == "user" 
            ? [.topLeft, .topRight, .bottomLeft]
            : [.topLeft, .topRight, .bottomRight]
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Streaming Response View

struct StreamingResponseView: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 20, height: 20)
                        
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.accentColor)
                    }
                    Text("Assistant")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                }
                
                Text(text.isEmpty ? " " : text)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray5))
                    .cornerRadius(18, corners: [.topLeft, .topRight, .bottomRight])
                
                // Typing indicator
                TypingIndicator()
            }
            
            Spacer(minLength: 60)
        }
    }
}

struct TypingIndicator: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 6, height: 6)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .padding(.leading, 16)
        .padding(.top, 4)
        .onAppear { animating = true }
    }
}

// MARK: - Chat Input View

struct ChatInputView: View {
    @Binding var inputText: String
    let isStreaming: Bool
    @Binding var temperature: Double
    @Binding var maxTokens: Int
    @Binding var showSettings: Bool
    let onSend: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 10) {
            // Settings chips
            HStack(spacing: 8) {
                Label("Temp: \(temperature, specifier: "%.1f")", systemImage: "thermometer")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .cornerRadius(6)
                
                Label("Max: \(maxTokens)", systemImage: "text.badge.plus")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .cornerRadius(6)
                
                Spacer()
                
                Button(action: { showSettings = true }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            
            // Input field and send button
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message...", text: $inputText, axis: .vertical)
                    .focused($isFocused)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    .lineLimit(1...5)
                    .disabled(isStreaming)
                    .onSubmit {
                        if !isStreaming { onSend() }
                    }
                
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(canSend ? .accentColor : .secondary)
                }
                .disabled(!canSend)
                .scaleEffect(canSend ? 1.0 : 0.9)
                .animation(.spring(response: 0.3), value: canSend)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
    }
    
    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }
}

// MARK: - Chat Settings

struct ChatSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var temperature: Double
    @Binding var maxTokens: Int
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Generation Parameters")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(temperature, format: .number.precision(.fractionLength(1)))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $temperature, in: 0.0...2.0, step: 0.1)
                        
                        Text("Higher = more creative, Lower = more focused")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Max Tokens")
                            Spacer()
                            Text("\(maxTokens)")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(maxTokens) },
                            set: { maxTokens = Int($0) }
                        ), in: 64...4096, step: 64)
                        
                        Text("Maximum response length")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button("Reset to Defaults") {
                        temperature = 0.7
                        maxTokens = 512
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Chat Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Rounded Corner Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    ChatView()
        .environmentObject(ModelManager.shared)
        .environmentObject(ServerManager.shared)
}