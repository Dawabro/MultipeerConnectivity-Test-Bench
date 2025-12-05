//
//  PeerCommunicatorBasic.swift
//  MultipeerBench
//
//  Created by David Brown on 4/12/25.
//

import Foundation
import MultipeerConnectivity

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

protocol PeerCommunication: Observable {
    var connectedPeers: [ConnectedPeer] { get }
    var logs: [LogEntry] { get }
    var isBrowsing: Bool { get }
    var isAdvertising: Bool { get }
    
    func startBrowsing()
    func stopBrowsing()
    func startAdvertising()
    func stopAdvertising()
    func sendData(_ data: Data)
    func clearLogs()
    func disconnectPeer(_ peer: ConnectedPeer)
    func disconnectSession()
}

@Observable
final class PeerCommunicatorBasic: NSObject, MCNearbyServiceAdvertiserDelegate, PeerCommunication {
    var connectedPeers: [ConnectedPeer] = []
    var logs: [LogEntry] = []
    var isBrowsing: Bool = false
    var isAdvertising: Bool = false
    private let peerID = MCPeerID(displayName: PeerIDDisplayNameAssistant.validDisplayName(from: UIDevice.current.name))
    private let session: MCSession
    private let serviceBrowser: MCNearbyServiceBrowser
    private var serviceAdvertiser: MCNearbyServiceAdvertiser
    private let serviceType = "dwb-mpbench"
    private var peerFoundTimestamp = [MCPeerID: Date]()
    
    override init() {
        self.session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        self.serviceBrowser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        self.serviceAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        super.init()
        self.session.delegate = self
        self.serviceBrowser.delegate = self
        self.serviceAdvertiser.delegate = self
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func startBrowsing() {
        guard !isBrowsing else { fatalError("Already browsing! Calling startBrowsing() again is not supported.") }
        serviceBrowser.startBrowsingForPeers()
        log(message: "🟢 Browsing started")
        isBrowsing = true
    }
    
    func stopBrowsing() {
        serviceBrowser.stopBrowsingForPeers()
        log(message: "🔴 Browsing stopped")
        isBrowsing = false
    }
    
    func startAdvertising() {
        guard !isAdvertising else { fatalError("Already advertising! Calling startAdvertisingPeer() again is not supported.") }
        serviceAdvertiser.startAdvertisingPeer()
        log(message: "🟢 Advertising started")
        isAdvertising = true
    }
    
    func stopAdvertising() {
        serviceAdvertiser.stopAdvertisingPeer()
        log(message: "🔴 Advertising stopped")
        isAdvertising = false
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        log(message: "📬 Received invitation from: \(peerID.displayName)")
        
        invitationHandler(true, session)
        logPeerFound(peerID)
        log(message: "🤝 Accepted invitation from: \(peerID.displayName)")
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        isAdvertising = false
        log(message: "⛔️ \(peerID.displayName) did not start advertising peer, error: \(error.localizedDescription)")
    }
    
    func sendData(_ data: Data) {
        let selectedPeers = connectedPeers.filter({ $0.isSelected }).map({ $0.mcPeerID })
        
        do {
            try session.send(data, toPeers: selectedPeers, with: .reliable)
            log(message: "📦 Sent \(data.count) bytes to \(session.connectedPeers.count) connected peers")
        } catch {
            log(message: "⛔️ Error sending data: \(error.localizedDescription)")
        }
    }
    
    private func sendAcknowledgment(to peerID: MCPeerID) {
        guard let acknowledgement = "ACK".data(using: .utf8) else { return }
        
        do {
            try session.send(acknowledgement, toPeers: [peerID], with: .reliable)
            log(message: "📦 Sent acknowledgment to \(peerID.displayName)")
        } catch {
            log(message: "⛔️ Error sending acknowledgement: \(error.localizedDescription)")
        }
    }
    
    func disconnectPeer(_ peer: ConnectedPeer) {
        session.cancelConnectPeer(peer.mcPeerID)
        log(message: "🔴 Canceled connection with \(peer.mcPeerID.displayName)")
    }
    
    func disconnectSession() {
        session.disconnect()
        connectedPeers.removeAll()
        peerFoundTimestamp.removeAll()
        log(message: "🔴 Session disconnected")
    }
    
    func clearLogs() {
        logs.removeAll()
    }
    
    private func logPeerFound(_ peerID: MCPeerID) {
        guard peerFoundTimestamp[peerID] == nil else { return }
        peerFoundTimestamp[peerID] = Date()
    }
    
    private func addConnectedPeer(_ peerID: MCPeerID) {
        let newConnectedPeer = ConnectedPeer(peerID: peerID)
        connectedPeers.append(newConnectedPeer)
    }
    
    private func removeConnectedPeer(_ peerID: MCPeerID) {
        if connectedPeers.contains(where: { $0.mcPeerID == peerID }) {
            peerFoundTimestamp.removeValue(forKey: peerID)
            connectedPeers.removeAll { $0.mcPeerID == peerID }
            print("⚠️ removed \(peerID.displayName) from connectedPeers")
        } else {
            print("⚠️ \(peerID.displayName) not found in connectedPeers")
        }
    }
    
    private func log(message: String) {
        logs.append(LogEntry(message))
        print("PeerCommunicator Log: \(message)")
    }
}

extension PeerCommunicatorBasic: MCNearbyServiceBrowserDelegate {
    
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        log(message: "👋 Found \(peerID.displayName)")
        logPeerFound(peerID)
        
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
        log(message: "✉️ Invited \(peerID.displayName) to join session")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        log(message: "⚠️ Lost \(peerID.displayName)")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        isBrowsing = false
        log(message: "⛔️ Did not start browsing for peers, error: \(error.localizedDescription)")
    }
}

extension PeerCommunicatorBasic: MCSessionDelegate {
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case MCSessionState.connecting:
            log(message: "📡 Connecting to \(peerID.displayName)")
        case MCSessionState.connected:
            let peerFoundTime = peerFoundTimestamp.removeValue(forKey: peerID) ?? Date()
            let connectionTimeInterval = Date().timeIntervalSince(peerFoundTime).formatted(.number.precision(.fractionLength(2)))
            log(message: "📳 Connected to \(peerID.displayName) in \(connectionTimeInterval) seconds")
            addConnectedPeer(peerID)
        case MCSessionState.notConnected:
            let isAConnectedPeer = connectedPeers.contains(where: { $0.mcPeerID == peerID })
            
            if isAConnectedPeer {
                log(message: "📵 Not connected to \(peerID.displayName)")
                removeConnectedPeer(peerID)
            } else {
                log(message: "📵 Not connected to \(peerID.displayName) (Ignored, not a connected peer)")
            }
        default:
            print("\(peerID.displayName) has unknown MCSessionState \(state)")
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let acknowledgedMessage = String(data: data, encoding: .utf8)
        
        if acknowledgedMessage == "ACK" {
            log(message: "✅ Received acknowledgment from \(peerID.displayName)")
        } else {
            log(message: "📡 Received \(data.count) bytes from \(peerID.displayName)")
            sendAcknowledgment(to: peerID)
        }
    }
    
    // Unused MCSessionDelegate methods:
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // empty
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // empty
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // empty
    }
}

@Observable
final class MockPeerCommunicator: PeerCommunication {
    var connectedPeers = [ConnectedPeer]()
    var logs: [LogEntry] = []
    var isBrowsing: Bool = false
    var isAdvertising: Bool = false
    
    init(withConnectedPeers: Bool = true) {
        self.connectedPeers = [
            ConnectedPeer(peerID: MCPeerID(displayName: "Ashley iPhone")),
            ConnectedPeer(peerID: MCPeerID(displayName: "Pierson iPad")),
            ConnectedPeer(peerID: MCPeerID(displayName: "Liam Mac"))
        ]
    }
    
    func startBrowsing() {
        print(#function)
        isBrowsing = true
        
        logs.append(LogEntry("🟢 Browsing started"))
        logs.append(LogEntry("👋 Found Ashley iPhone"))
        logs.append(LogEntry("✉️ Invited Ashley iPhone to join session"))
        
    }
    
    func stopBrowsing() {
        print(#function)
        isBrowsing = false
    }
    
    func startAdvertising() {
        print(#function)
        isAdvertising = true
    }
    
    func stopAdvertising() {
        print(#function)
        isAdvertising = false
    }
    
    func sendData(_ data: Data) {
        print("sent data: \(data.count) bytes")
    }
    
    func clearLogs() {
        logs.removeAll()
    }
    
    func disconnectPeer(_ peer: ConnectedPeer) {
        connectedPeers.removeAll { $0.id == peer.id }
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
