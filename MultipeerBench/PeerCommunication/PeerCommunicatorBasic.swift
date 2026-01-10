//
//  PeerCommunicatorBasic.swift
//  MultipeerBench
//
//  Created by David Brown on 4/12/25.
//

import Foundation
@preconcurrency import MultipeerConnectivity

//
//  MARK: - MultipeerConnectivity Setup Instructions
//
//  1. Info.plist Updates
//     - Add a key `NSLocalNetworkUsageDescription` (String) explaining why you need local network access.
//       For example: "We need access to find and connect to nearby devices."
//     - Add a key `NSBonjourServices` (Array) and include your service type as `_yourServiceType._tcp`.
//       Example array entry: `<string>_my-mc-service._tcp</string>`
//
//  2. Requirements for serviceType String
//     - Must be at most 15 characters long.
//     - Must contain only lowercase letters, digits, and hyphens (no spaces or underscores).
//       (The leading underscore and ._tcp suffix are automatically added in Info.plist.)
//     - Must match exactly between all peers in the network.
//
//  Example Service Setup
//     let serviceType = "my-mc-service" // in Swift code
//     // Corresponds to "_my-mc-service._tcp" in Info.plist
//
//  These changes are required on iOS 14+ for local network permissions and Bonjour discovery.
//

@MainActor
protocol PeerCommunication {
    func startBrowsing()
    func stopBrowsing()
    func startAdvertising()
    func stopAdvertising()
    func sendData(_ data: Data)
    func disconnectPeer(_ peer: ConnectedPeer)
    func disconnectSession()
}

@Observable
@MainActor
final class PeerCommunicatorState {
    private(set) var connectedPeers: [ConnectedPeer] = []
    private(set) var logs: [LogEntry] = []
    private(set) var isBrowsing: Bool = false
    private(set) var isAdvertising: Bool = false
    
    nonisolated init() { }
    
    func setIsBrowsing(_ isBrowsing: Bool) {
        self.isBrowsing = isBrowsing
    }
    
    func setIsAdvertising(_ isAdvertising: Bool) {
        self.isAdvertising = isAdvertising
    }
    
    func log(message: String) {
        logs.append(LogEntry(message))
        print("PeerCommunicator Log: \(message)")
    }
    
    func clearLogs() {
        logs.removeAll()
    }
    
    func addConnectedPeer(_ peerID: MCPeerID) {
        let newConnectedPeer = ConnectedPeer(peerID: peerID)
        connectedPeers.append(newConnectedPeer)
    }
    
    func removeConnectedPeer(_ peerID: MCPeerID) {
        if connectedPeers.contains(where: { $0.mcPeerID == peerID }) {
            connectedPeers.removeAll { $0.mcPeerID == peerID }
            log(message: "⚠️ removed \(peerID.displayName) from connectedPeers")
        } else {
            log(message: "⚠️ attempted to remove peer that wasn't connected")
        }
    }
    
    func removeAllConnectedPeers() {
        connectedPeers.removeAll(keepingCapacity: true)
    }
}

@MainActor
final class PeerCommunicatorBasic: NSObject, PeerCommunication {
    let state = PeerCommunicatorState()
    private nonisolated let peerID: MCPeerID
    private let session: MCSession
    private nonisolated let syncSession: MCSession
    private let serviceBrowser: MCNearbyServiceBrowser
    private var serviceAdvertiser: MCNearbyServiceAdvertiser
    private let serviceType = "dwb-mpbench"
    private var peerFoundTimestamp = [MCPeerID: Date]()
    
    private let sessionStateStream: AsyncStream<(MCPeerID, MCSessionState)>
    private nonisolated let sessionStateContinuation: AsyncStream<(MCPeerID, MCSessionState)>.Continuation
    
    private let receivedDataStream: AsyncStream<(Data, MCPeerID)>
    private nonisolated let receivedDataContinuation: AsyncStream<(Data, MCPeerID)>.Continuation
        
    override init() {
        let peerID = MCPeerID(displayName: PeerIDDisplayNameAssistant.validDisplayName(from: UIDevice.current.name))
        self.peerID = peerID
        self.session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        self.syncSession = session
        self.serviceBrowser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        self.serviceAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        (sessionStateStream, sessionStateContinuation) = AsyncStream.makeStream()
        (receivedDataStream, receivedDataContinuation) = AsyncStream.makeStream()
        super.init()
        
        self.session.delegate = self
        self.serviceBrowser.delegate = self
        self.serviceAdvertiser.delegate = self
        
        // Synchronizes session state changes
        Task { @MainActor [weak self] in
            guard let stream = self?.sessionStateStream else { return }
            
            for await (peerID, state) in stream {
                guard let self else { return }
                self.handleSessionStateChange(peerID: peerID, state: state)
            }
        }
        
        // Synchronizes data stream
        Task { @MainActor [weak self] in
            guard let stream = self?.receivedDataStream else { return }
            
            for await (data, peerID) in stream {
                guard let self else { return }
                self.handleReceivedData(data: data, fromPeer: peerID)
            }
        }
    }
    
    deinit {
        sessionStateContinuation.finish()
        receivedDataContinuation.finish()
    }
    
    func startBrowsing() {
        assert(state.isBrowsing == false, "Calling startBrowsingForPeers() again is not supported, will cause crashes.")
        guard state.isBrowsing == false else { return }
        serviceBrowser.startBrowsingForPeers()
        state.log(message: "🟢 Browsing started")
        state.setIsBrowsing(true)
    }
    
    func stopBrowsing() {
        serviceBrowser.stopBrowsingForPeers()
        state.log(message: "🔴 Browsing stopped")
        state.setIsBrowsing(false)
    }
    
    func startAdvertising() {
        assert(state.isAdvertising == false, "Calling startAdvertisingPeer() again is not supported, will cause crashes.")
        guard state.isAdvertising == false else { return }
        serviceAdvertiser.startAdvertisingPeer()
        state.log(message: "🟢 Advertising started")
        state.setIsAdvertising(true)
    }
    
    func stopAdvertising() {
        serviceAdvertiser.stopAdvertisingPeer()
        state.log(message: "🔴 Advertising stopped")
        state.setIsAdvertising(false)
    }
    
    func sendData(_ data: Data) {
        let selectedPeers = state.connectedPeers.filter { $0.isSelected }.map { $0.mcPeerID }
        
        do {
            try session.send(data, toPeers: selectedPeers, with: .reliable)
            state.log(message: "📦 Sent \(data.count) bytes to \(selectedPeers.count) connected peers")
        } catch {
            state.log(message: "⛔️ Error sending data: \(error.localizedDescription)")
        }
    }
    
    private func sendAcknowledgment(to peerID: MCPeerID) {
        guard let acknowledgement = "ACK".data(using: .utf8) else { return }
        
        do {
            try session.send(acknowledgement, toPeers: [peerID], with: .reliable)
            state.log(message: "📦 Sent acknowledgment to \(peerID.displayName)")
        } catch {
            state.log(message: "⛔️ Error sending acknowledgement: \(error.localizedDescription)")
        }
    }
    
    func disconnectPeer(_ peer: ConnectedPeer) {
        session.cancelConnectPeer(peer.mcPeerID)
        state.log(message: "🔴 Canceled connection with \(peer.mcPeerID.displayName)")
    }
    
    func disconnectSession() {
        session.disconnect()
        state.removeAllConnectedPeers()
        peerFoundTimestamp.removeAll()
        state.log(message: "🔴 Session disconnected")
    }
}

extension PeerCommunicatorBasic: MCNearbyServiceAdvertiserDelegate {
    
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, syncSession)
        
        Task { @MainActor in
            if peerFoundTimestamp[peerID] == nil {
                peerFoundTimestamp[peerID] = Date()
            }
            
            self.state.log(message: "📬 Received invitation from: \(peerID.displayName)")
            self.state.log(message: "🤝 Accepted invitation from: \(peerID.displayName)")
        }
    }
    
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        Task { @MainActor in
            self.state.setIsAdvertising(false)
            self.state.log(message: "⛔️ \(self.peerID.displayName) did not start advertising peer, error: \(error.localizedDescription)")
        }
    }
}

extension PeerCommunicatorBasic: MCNearbyServiceBrowserDelegate {
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        browser.invitePeer(peerID, to: syncSession, withContext: nil, timeout: 15)
        
        Task { @MainActor in
            if peerFoundTimestamp[peerID] == nil {
                peerFoundTimestamp[peerID] = Date()
            }
            
            self.state.log(message: "👋 Found \(peerID.displayName)")
            self.state.log(message: "✉️ Invited \(peerID.displayName) to join session")
        }
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.state.log(message: "⚠️ Lost \(peerID.displayName)")
        }
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            self.state.setIsBrowsing(false)
            self.state.log(message: "⛔️ Did not start browsing for peers, error: \(error.localizedDescription)")
        }
    }
}

extension PeerCommunicatorBasic: MCSessionDelegate {
    
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        sessionStateContinuation.yield((peerID, state))
    }
    
    private func handleSessionStateChange(peerID: MCPeerID, state: MCSessionState) {
        switch state {
        case MCSessionState.connecting:
            self.state.log(message: "📡 Connecting to \(peerID.displayName)")
            
        case MCSessionState.connected:
            let peerFoundTime = peerFoundTimestamp.removeValue(forKey: peerID) ?? Date()
            let connectionTimeInterval = Date().timeIntervalSince(peerFoundTime).formatted(.number.precision(.fractionLength(2)))
            self.state.log(message: "📳 Connected to \(peerID.displayName) in \(connectionTimeInterval) seconds")
            self.state.addConnectedPeer(peerID)
            
        case MCSessionState.notConnected:
            let isAConnectedPeer = self.state.connectedPeers.contains(where: { $0.mcPeerID == peerID })
            
            if isAConnectedPeer {
                self.state.log(message: "📵 Not connected to \(peerID.displayName)")
                self.state.removeConnectedPeer(peerID)
                self.peerFoundTimestamp.removeValue(forKey: peerID)
            } else {
                self.state.log(message: "📵 Not connected to \(peerID.displayName) (Ignored, not a connected peer)")
            }
            
        @unknown default:
            print("\(peerID.displayName) has unknown MCSessionState \(state)")
        }
    }
    
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        receivedDataContinuation.yield((data, peerID))
    }
    
    private func handleReceivedData(data: Data, fromPeer peerID: MCPeerID) {
        let acknowledgedMessage = String(data: data, encoding: .utf8)
        
        if acknowledgedMessage == "ACK" {
            state.log(message: "✅ Received acknowledgment from \(peerID.displayName)")
        } else {
            state.log(message: "📡 Received \(data.count) bytes from \(peerID.displayName)")
            sendAcknowledgment(to: peerID)
        }
    }
    
    // Unused MCSessionDelegate methods:
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // empty
    }
    
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // empty
    }
    
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // empty
    }
}

@MainActor
final class MockPeerCommunicator: PeerCommunication {
    let state = PeerCommunicatorState()
    
    init(withConnectedPeers: Bool = true) {
        if withConnectedPeers {
            state.addConnectedPeer(MCPeerID(displayName: "Ashley iPhone"))
            state.addConnectedPeer(MCPeerID(displayName: "Pierson iPad"))
            state.addConnectedPeer(MCPeerID(displayName: "Liam Mac"))
        }
    }
    
    func startBrowsing() {
        print(#function)
        state.setIsBrowsing(true)
        
        state.log(message: "🟢 Browsing started")
        state.log(message: "👋 Found Ashley iPhone")
        state.log(message: "✉️ Invited Ashley iPhone to join session")
    }
    
    func stopBrowsing() {
        print(#function)
        state.setIsBrowsing(false)
    }
    
    func startAdvertising() {
        print(#function)
        state.setIsAdvertising(true)
    }
    
    func stopAdvertising() {
        print(#function)
        state.setIsAdvertising(false)
    }
    
    func sendData(_ data: Data) {
        print("sent data: \(data.count) bytes")
    }
    
    func disconnectPeer(_ peer: ConnectedPeer) {
        state.removeConnectedPeer(peer.mcPeerID)
    }
    
    func disconnectSession() {
        print("session disconnected")
    }
}

struct LogEntry: Identifiable {
    let message: String
    let timeStamp: Date
    let id: UUID = UUID()
    
    init(_ message: String, timeStamp: Date = Date()) {
        self.message = message
        self.timeStamp = timeStamp
    }
}
