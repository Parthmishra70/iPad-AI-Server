//
//  AppRouter.swift
//  LocalAIServer
//
//  Shared app-level navigation state. Allows views anywhere in the hierarchy
//  to request a switch of the primary tab in the root NavigationSplitView
//  without pushing a duplicate destination onto a local navigation stack.
//

import Foundation
import SwiftUI

/// Primary tabs in the root sidebar.
enum AppTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case chat = "Chat"
    case models = "Models"
    case server = "API Server"
    case docs = "API Docs"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "gauge"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .models: return "brain.head.profile"
        case .server: return "server.rack"
        case .docs: return "doc.text"
        case .settings: return "gear"
        }
    }
}

/// App-wide router. Holds the currently selected primary tab.
/// Observed by the root ContentView sidebar/detail and writable by any
/// descendant view (e.g. ChatView requesting a switch to Models).
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var selectedTab: AppTab = .dashboard

    /// Bump whenever a deep-link style "go to tab" request is issued.
    /// Observers can react via `onChange(of: token)`.
    @Published var pendingRequest: PendingRequest?

    struct PendingRequest: Equatable {
        let tab: AppTab
        let token: UUID
    }

    private init() {}

    func requestSwitch(to tab: AppTab) {
        selectedTab = tab
        pendingRequest = PendingRequest(tab: tab, token: UUID())
    }
}
