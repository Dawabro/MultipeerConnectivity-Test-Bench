//
//  MultipeerBenchApp.swift
//  MultipeerBench
//
//  Created by David Brown on 4/12/25.
//

import SwiftUI

@main
struct MultipeerBenchApp: App {
//    let peerCommunicator = PeerCommunicatorBasic()
    let peerCommunicator = PeerCommunicatorAdvanced()
    
    var body: some Scene {
        WindowGroup {
//            BasicPeerCommunicationView(peerCommunicator: peerCommunicator, commState: peerCommunicator.state)
            
            AdvancedPeerCommunicationView(peerCommunicator: peerCommunicator, commState: peerCommunicator.state)
        }
    }
}
