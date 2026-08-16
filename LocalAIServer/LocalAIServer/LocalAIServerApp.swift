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
    @StateObject private var toastCenter = ToastCenter.shared

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(modelManager)
                    .environmentObject(serverManager)
                    .environmentObject(apiKeyService)
                    .environmentObject(toastCenter)

                // Top-of-screen toast overlay. Sits above every tab so
                // ModelManager's download-complete / load-failed events
                // are visible without the user having to be on the
                // Models tab.
                ToastOverlay()
                    .environmentObject(toastCenter)
                    .ignoresSafeArea(.keyboard)
            }
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
