//
//  NearbyPeer.swift
//  MultipeerBench
//
//  Created by David Brown on 12/5/25.
//

import Foundation
import MultipeerConnectivity

@Observable
final class NearbyPeer: Identifiable, Equatable {
    let id: UUID
    let mcPeerID: MCPeerID
    var isSelected: Bool = false
    var isConnected: Bool = false
    
    var displayName: String {
        mcPeerID.displayName
    }
    
    init(peerID: MCPeerID) {
        self.mcPeerID = peerID
        self.id = UUID()
    }
    
    static func == (lhs: NearbyPeer, rhs: NearbyPeer) -> Bool {
        lhs.mcPeerID == rhs.mcPeerID
    }
}
