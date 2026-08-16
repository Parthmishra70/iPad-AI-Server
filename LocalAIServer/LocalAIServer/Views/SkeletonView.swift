import SwiftUI

struct SkeletonCard: View {
    var height: CGFloat? = nil
    var cornerRadius: CGFloat = 16
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemGray5))
            .frame(height: height ?? 200)
            .redacted(reason: .placeholder)
            .shimmering()
    }
}

struct SkeletonModelCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 56, height: 56)
                
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 120, height: 20)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 80, height: 14)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 160, height: 14)
                }
                
                Spacer()
            }
            .padding(20)
            
            Divider()
                .padding(.horizontal, 20)
            
            HStack(spacing: 12) {
                ForEach(0..<4) { _ in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray5))
                        .frame(height: 28)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray5))
                .frame(height: 50)
                .padding(20)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
        )
        .redacted(reason: .placeholder)
        .shimmering()
    }
}

struct SkeletonSection: View {
    var height: CGFloat = 100
    var cornerRadius: CGFloat = 16
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemGray5))
            .frame(height: height)
            .redacted(reason: .placeholder)
            .shimmering()
    }
}

struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 36, height: 36)
            
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 100, height: 16)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 140, height: 12)
            }
            
            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
        )
        .redacted(reason: .placeholder)
        .shimmering()
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.3),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.6)
                    .offset(x: phase * geometry.size.width * 1.5 - geometry.size.width * 0.75)
                    .animation(
                        .linear(duration: 1.5)
                        .repeatForever(autoreverses: false),
                        value: phase
                    )
                    .onAppear { phase = 1 }
                }
                .mask(content)
            )
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

#Preview {
    VStack(spacing: 20) {
        SkeletonModelCard()
        SkeletonRow()
        SkeletonSection(height: 150)
        SkeletonCard(height: 180)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}