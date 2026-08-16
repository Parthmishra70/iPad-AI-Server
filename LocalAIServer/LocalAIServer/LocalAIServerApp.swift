//
//  LocalAIServerApp.swift
//  LocalAIServer
//
//  Main entry point for the Local AI Server iPad application
//

import SwiftUI

@main
struct LocalAIServerApp: App {
    @StateObject private var modelManager = ModelManager.shared
    @StateObject private var serverManager = ServerManager.shared
    @StateObject private var apiKeyService = APIKeyService.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(modelManager)
                .environmentObject(serverManager)
                .environmentObject(apiKeyService)
                .onAppear {
                    // Initialize app state on launch
                    Task {
                        await withTaskGroup(of: Void.self) { group in
                            group.addTask { await modelManager.loadSavedModels() }
                            group.addTask { await serverManager.refreshIPAddress() }
                            group.addTask { await serverManager.loadConfiguration() }
                        }
                    }
                }
        }
    }
}
