//
//  NetworkManager.swift
//  LocalAIServer
//
//  Network utilities for IP address discovery and connectivity checks
//

import Foundation
import Network

/// Utility class for network-related operations
class NetworkManager {
    static let shared = NetworkManager()
    
    /// Get the local Wi-Fi IP address
    func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            let interface = ptr!.pointee

            guard let ifaAddr = interface.ifa_addr else { continue }

            let addrFamily = ifaAddr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                // en0 is typically Wi-Fi on iPad
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(ifaAddr, socklen_t(ifaAddr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        
        return address
    }
    
    /// Check if device is connected to a network
    func isConnectedToNetwork() -> Bool {
        let monitor = NWPathMonitor()
        var isConnected = false
        
        let semaphore = DispatchSemaphore(value: 0)
        
        monitor.pathUpdateHandler = { path in
            isConnected = path.status == .satisfied
            semaphore.signal()
        }
        
        monitor.start(queue: DispatchQueue.global(qos: .background))
        _ = semaphore.wait(timeout: .now() + 2.0)
        monitor.cancel()
        
        return isConnected
    }
    
    /// Get network interface information
    func getNetworkInterfaces() -> [NetworkInterface] {
        var interfaces: [NetworkInterface] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else { return [] }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            let interface = ptr!.pointee
            let name = String(cString: interface.ifa_name)

            guard let ifaAddr = interface.ifa_addr else { continue }

            let addrFamily = ifaAddr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(ifaAddr, socklen_t(ifaAddr.pointee.sa_len),
                           &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                let address = String(cString: hostname)

                interfaces.append(NetworkInterface(name: name, address: address))
            }
        }
        
        return interfaces
    }
}

/// Represents a network interface
struct NetworkInterface {
    let name: String
    let address: String
    
    var displayName: String {
        switch name {
        case "en0": return "Wi-Fi"
        case "en1": return "Ethernet"
        case "pdp_ip0": return "Cellular"
        default: return name
        }
    }
}
