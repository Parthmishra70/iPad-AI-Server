//
//  APIKeyService.swift
//  LocalAIServer
//
//  Manages API key for server authentication
//

import Foundation
import Security

/// Service for managing API key storage in Keychain
@MainActor
class APIKeyService: ObservableObject {
    static let shared = APIKeyService()
    
    @Published var hasAPIKey: Bool = false
    
    init() {
        checkForKey()
    }
    
    // MARK: - API Key Management
    
    func generateNewKey() -> String {
        let uuid = UUID().uuidString
        let key = "sk-local-\(uuid.replacingOccurrences(of: "-", with: ""))"
        
        saveKey(key)
        return key
    }
    
    func saveKey(_ key: String) {
        KeychainHelper.save(key: key, forKey: "apiKey")
        hasAPIKey = true
        
        // Update ServerManager
        ServerManager.shared.apiKey = key
    }
    
    func deleteKey() {
        KeychainHelper.delete(forKey: "apiKey")
        hasAPIKey = false
        ServerManager.shared.apiKey = nil
    }
    
    func getKey() -> String? {
        return KeychainHelper.load(key: "apiKey")
    }
    
    private func checkForKey() {
        hasAPIKey = KeychainHelper.load(key: "apiKey") != nil
    }
}

/// Helper for Keychain operations
struct KeychainHelper {
    static let shared = KeychainHelper()
    
    enum KeychainError: Error {
        case duplicateItem
        case itemNotFound
        case unknown(OSStatus)
    }
    
    func save(key: String, forKey: String) {
        guard let data = key.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: forKey,
            kSecValueData as String: data
        ]
        
        // Try to update existing item first
        let attributes: [String: Any] = [kSecValueData as String: data]
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        // If update fails (item doesn't exist), add new item
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let keyString = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return keyString
    }
    
    func delete(forKey: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: forKey
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Static convenience methods

extension KeychainHelper {
    static func save(key: String, forKey: String) {
        shared.save(key: key, forKey: forKey)
    }
    
    static func load(key: String) -> String? {
        return shared.load(key: key)
    }
    
    static func delete(forKey: String) {
        shared.delete(forKey: forKey)
    }
}
