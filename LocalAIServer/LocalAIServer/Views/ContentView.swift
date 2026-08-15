//
//  ContentView.swift
//  LocalAIServer
//
//  Main navigation view - uses NavigationSplitView on iPad for responsive layout
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var serverManager: ServerManager
    
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var selectedTab: Tab = .dashboard
    
    enum Tab: String, CaseIterable, Identifiable {
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
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar - Navigation
            List {
                ForEach(Tab.allCases) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.rawValue, systemImage: tab.icon)
                            .foregroundColor(selectedTab == tab ? .accentColor : .primary)
                    }
                    .listRowBackground(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                }
            }
            .navigationTitle("Local AI Server")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ServerStatusBadge()
                }
            }
        } detail: {
            // Detail View - must declare navigationDestination for sidebar links
            DetailColumn(selectedTab: $selectedTab)
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selectedTab) { _ in
            // Navigation handled by NavigationLink
        }
    }
    
    @ViewBuilder
    private func detailView(for tab: Tab) -> some View {
        switch tab {
        case .dashboard:
            DashboardView()
        case .chat:
            ChatView()
        case .models:
            ModelsView()
        case .server:
            ServerView()
        case .docs:
            APIDocsView()
        case .settings:
            SettingsView()
        }
    }
}

// Detail column that handles navigation from sidebar
private struct DetailColumn: View {
    @Binding var selectedTab: ContentView.Tab
    
    var body: some View {
        NavigationStack {
            detailView(for: selectedTab)
        }
        .navigationDestination(for: ContentView.Tab.self) { tab in
            detailView(for: tab)
        }
    }
    
    @ViewBuilder
    private func detailView(for tab: ContentView.Tab) -> some View {
        switch tab {
        case .dashboard:
            DashboardView()
        case .chat:
            ChatView()
        case .models:
            ModelsView()
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
                .fill(serverManager.isRunning ? Color.green : Color.red)
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
                .fill(serverManager.isRunning ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(ModelManager.shared)
        .environmentObject(ServerManager.shared)
        .environmentObject(APIKeyService.shared)
}