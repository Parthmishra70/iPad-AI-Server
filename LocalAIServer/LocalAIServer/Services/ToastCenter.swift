//
//  ToastCenter.swift
//  LocalAIServer
//
//  Lightweight transient-message bus for non-blocking UI events like
//  "Download complete" or "Model loaded". Used by ModelManager to
//  surface completion events when the user is NOT on the Models tab
//  (where in-row UI already shows state changes).
//

import Foundation
import SwiftUI

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String?
    let systemImage: String
    let tint: Color
    /// Optional action — when non-nil, the banner shows a tappable button.
    let actionLabel: String?
    let action: (() -> Void)?

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    /// Currently-presented toast. Setting this to a new value dismisses
    /// the previous one. Auto-clears after `displayDuration` seconds
    /// unless the user taps it first.
    @Published var current: ToastMessage?

    /// How long the toast remains onscreen before auto-dismissing.
    /// Set to nil to keep it sticky until the user dismisses it.
    var displayDuration: TimeInterval? = 4.0

    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// Present a toast. If `displayDuration` is set, it auto-dismisses
    /// after that interval. Calling show() while a toast is already up
    /// replaces it (cancelling the prior dismiss timer).
    func show(
        _ message: ToastMessage,
        sticky: Bool = false
    ) {
        dismissTask?.cancel()
        current = message

        if sticky { return }

        guard let displayDuration else { return }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(displayDuration * 1_000_000_000))
            if Task.isCancelled { return }
            await MainActor.run { self?.current = nil }
        }
    }

    /// Manually dismiss the current toast (e.g. on tap).
    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }
}
