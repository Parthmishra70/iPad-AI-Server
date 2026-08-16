import SwiftUI

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void
    var isRetryable: Bool = false
    var onRetry: (() -> Void)? = nil
    
    @State private var isVisible = true
    
    var body: some View {
        if isVisible {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(.systemRed))
                    .font(.title3)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                if isRetryable, let onRetry = onRetry {
                    Button("Retry") {
                        onRetry()
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemRed))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                Button(action: {
                    withAnimation(.spring()) {
                        isVisible = false
                    }
                    onDismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemRed).opacity(0.15))
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isVisible)
        }
    }
}

struct InlineErrorBanner: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(Color(.systemRed))
            
            Text(message)
                .font(.caption)
                .foregroundColor(Color(.systemRed))
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.medium))
                    .foregroundColor(Color(.systemRed))
            }
        }
        .padding(12)
        .background(Color(.systemRed).opacity(0.1))
        .cornerRadius(8)
    }
}

struct ToastBanner: View {
    let message: String
    let type: ToastType
    let onDismiss: () -> Void
    
    @State private var isVisible = true
    
    enum ToastType {
        case success
        case error
        case warning
        case info
        
        var color: Color {
            switch self {
            case .success: return Color(.systemGreen)
            case .error: return Color(.systemRed)
            case .warning: return Color(.systemOrange)
            case .info: return Color(.systemBlue)
            }
        }
        
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }
    
    var body: some View {
        if isVisible {
            HStack(spacing: 12) {
                Image(systemName: type.icon)
                    .foregroundColor(type.color)
                    .font(.title3)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring()) {
                        isVisible = false
                    }
                    onDismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(type.color.opacity(0.15))
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isVisible)
        }
    }
}

struct ToastContainer<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(spacing: 8) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

#Preview {
    VStack(spacing: 20) {
        ErrorBanner(message: "Failed to load model. Please check your internet connection and try again.", onDismiss: {})
        
        InlineErrorBanner(message: "Invalid API key", onDismiss: {})
        
        ToastBanner(message: "Model loaded successfully!", type: .success, onDismiss: {})
        ToastBanner(message: "Failed to connect to server", type: .error, onDismiss: {})
        ToastBanner(message: "Server will stop in 5 minutes", type: .warning, onDismiss: {})
        ToastBanner(message: "New version available", type: .info, onDismiss: {})
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}