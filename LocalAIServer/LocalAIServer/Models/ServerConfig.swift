//
//  ServerConfig.swift
//  LocalAIServer
//
//  Server configuration and settings
//

import Foundation

/// Configuration for the local HTTP server
struct ServerConfig: Codable {
    var port: Int
    var isRunning: Bool
    var apiKey: String?
    var allowLocalNetworkOnly: Bool
    var requestCount: Int64
    
    static let `default` = ServerConfig(
        port: 8080,
        isRunning: false,
        apiKey: nil,
        allowLocalNetworkOnly: true,
        requestCount: 0
    )
    
    /// API endpoint URL when server is running
    func apiEndpoint(ipAddress: String) -> String {
        return "http://\(ipAddress):\(port)/v1"
    }
    
    /// Health endpoint URL
    func healthEndpoint(ipAddress: String) -> String {
        return "http://\(ipAddress):\(port)/health"
    }
}

/// Information about the current server status
struct ServerStatus {
    let isRunning: Bool
    let ipAddress: String?
    let port: Int
    let activeModel: String?
    let requestCount: Int64
    let uptime: TimeInterval?
    
    var displayAddress: String {
        guard let ip = ipAddress else { return "Unknown" }
        return "\(ip):\(port)"
    }
    
    var fullAPIEndpoint: String {
        guard let ip = ipAddress else { return "Unknown" }
        return "http://\(ip):\(port)/v1"
    }
}
