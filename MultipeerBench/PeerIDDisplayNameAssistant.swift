//
//  PeerIDDisplayNameAssistant.swift
//  MultipeerBench
//
//  Created by David Brown on 4/16/25.
//

import UIKit
import MultipeerConnectivity

@MainActor
struct PeerIDDisplayNameAssistant {
    private static let maxNameByteSize = 63
    private static let peerIDKey = "persistedPeerIDKey"
    
    static var deviceName: String {
        validDisplayName(from: UIDevice.current.name)
    }
    
    static func validDisplayName(from input: String) -> String {
        guard !displayNameIsValid(input) else { return input }
        var trimmedInput = String(input.prefix(maxNameByteSize))
        var trimCountLimit = 100
        
        while !displayNameIsValid(trimmedInput) {
            trimmedInput.removeLast()
            trimCountLimit -= 1
            guard trimCountLimit > 0 else { break }
        }
        
        return trimmedInput
    }
        
    static func persistentPeerID(displayName: String) -> MCPeerID {
        if let data = UserDefaults.standard.data(forKey: peerIDKey),
           let peerID = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data) {
            return peerID
        }
        
        let peerID = MCPeerID(displayName: validDisplayName(from: displayName))
        
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: peerID, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: peerIDKey)
        }
        
        return peerID
    }
    
    private static func displayNameIsValid(_ proposedDisplayName: String) -> Bool {
        guard let data = proposedDisplayName.data(using: .utf8) else { return false }
        return data.count <= maxNameByteSize
    }
}
