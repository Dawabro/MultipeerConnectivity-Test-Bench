//
//  ConnectedPeer.swift
//  MultipeerBench
//
//  Created by David Brown on 12/5/25.
//

import Foundation
import MultipeerConnectivity

@Observable
final class ConnectedPeer: Identifiable {
    let id: UUID
    var isSelected: Bool = false
    let mcPeerID: MCPeerID
    var isConnected: Bool = false
    
    var displayName: String {
        mcPeerID.displayName
    }
    
    init(peerID: MCPeerID) {
        self.id = UUID()
        self.mcPeerID = peerID
    }
}
