//
//  MultipeerBenchApp.swift
//  MultipeerBench
//
//  Created by David Brown on 4/12/25.
//

import SwiftUI

@main
struct MultipeerBenchApp: App {
    let peerCommunicator = PeerCommunicatorBasic()
    
    var body: some Scene {
        WindowGroup {
            BasicPeerCommunicationView(peerCommunicator: peerCommunicator)
        }
    }
}
