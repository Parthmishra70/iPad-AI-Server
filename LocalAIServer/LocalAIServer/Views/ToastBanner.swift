//
//  ToastBanner.swift
//  LocalAIServer
//
//  Overlay banner that renders the current ToastCenter message.
//  Designed to sit at the top of the app's root ZStack so it can
//  appear over any tab. Tap to dismiss; tap action button to invoke
//  the toast's action closure (which also dismisses).
//

import SwiftUI

struct ToastOverlay: View {
    @EnvironmentObject var toastCenter: ToastCenter

    var body: some View {
        VStack {
            if let toast = toastCenter.current {
                ToastOverlayCard(message: toast) {
                    toastCenter.dismiss()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
                .zIndex(100)
            }
            Spacer()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toastCenter.current)
        .allowsHitTesting(toastCenter.current != nil)
    }
}

private struct ToastOverlayCard: View {
    let message: ToastMessage
    let onTapDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: message.systemImage)
                .font(.title3)
                .foregroundColor(message.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(message.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if let detail = message.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if let actionLabel = message.actionLabel, let action = message.action {
                Button {
                    action()
                    onTapDismiss()
                } label: {
                    Text(actionLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(message.tint)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                onTapDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(message.tint.opacity(0.25), lineWidth: 1)
        )
        .onTapGesture {
            // Tap anywhere on the card (but not on a button) dismisses.
            onTapDismiss()
        }
    }
}
