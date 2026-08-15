//
//  ContentView.swift
//  LocalAIServer
//
//  Main tab-based navigation view
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var serverManager: ServerManager
    
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "gauge")
                }
            
            ModelsView()
                .tabItem {
                    Label("Models", systemImage: "brain.head.profile")
                }
            
            ServerView()
                .tabItem {
                    Label("API Server", systemImage: "server.rack")
                }
            
            APIDocsView()
                .tabItem {
                    Label("API Docs", systemImage: "doc.text")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ModelManager.shared)
        .environmentObject(ServerManager.shared)
        .environmentObject(APIKeyService.shared)
}
