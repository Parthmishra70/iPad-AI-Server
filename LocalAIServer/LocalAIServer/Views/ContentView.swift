//
//  ContentView.swift
//  LocalAIServer
//
//  Main navigation view - uses NavigationSplitView on iPad for responsive layout
//

import SwiftUI

/// Primary tabs in the root sidebar. Aliased to `AppRouter`'s `AppTab`
/// so any view can switch tabs via either:
///   - a `@Binding<Tab>` passed down (used by ChatView/ModelsView), OR
///   - `AppRouter.shared.requestSwitch(to: .chat)` (used by non-view
///     code like `ModelManager`'s toast action).
typealias Tab = AppTab

struct ContentView: View {
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var serverManager: ServerManager
    @ObservedObject private var appRouter = AppRouter.shared

    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar - Navigation
            List {
                ForEach(AppTab.allCases) { tab in
                    Button {
                        appRouter.selectedTab = tab
                    } label: {
                        Label(tab.rawValue, systemImage: tab.icon)
                            .foregroundColor(appRouter.selectedTab == tab ? .accentColor : .primary)
                    }
                    .listRowBackground(appRouter.selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                }
            }
            .navigationTitle("Local AI Server")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ServerStatusBadge()
                }
            }
        } detail: {
            detailView(for: appRouter.selectedTab)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func detailView(for tab: AppTab) -> some View {
        switch tab {
        case .dashboard:
            DashboardView()
        case .chat:
            ChatView(selectedTab: $appRouter.selectedTab)
        case .models:
            ModelsView(selectedTab: $appRouter.selectedTab)
        case .server:
            ServerView()
        case .docs:
            APIDocsView()
        case .settings:
            SettingsView()
        }
    }
}

struct ServerStatusBadge: View {
    @EnvironmentObject var serverManager: ServerManager
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(serverManager.isRunning ? Color(.systemGreen) : Color(.systemRed))
                .frame(width: 8, height: 8)
                .animation(.easeInOut(duration: 0.2), value: serverManager.isRunning)
            
            Text(serverManager.isRunning ? "Running" : "Stopped")
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(serverManager.isRunning ? Color(.systemGreen).opacity(0.15) : Color(.systemRed).opacity(0.15))
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(ModelManager.shared)
        .environmentObject(ServerManager.shared)
        .environmentObject(APIKeyService.shared)
}