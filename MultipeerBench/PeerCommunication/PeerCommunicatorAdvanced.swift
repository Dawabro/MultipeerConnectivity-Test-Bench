//
//  PeerCommunicatorAdvanced.swift
//  MultipeerBench
//
//  Created by David Brown on 12/5/25.
//

import Foundation
@preconcurrency import MultipeerConnectivity
import Network

@MainActor
protocol PeerCommunicationAdvanced {
    var state: PeerCommunicatorAdvancedState { get }
    
    func startBroadcasting()
    func stopBroadcasting()
    func sendData(_ data: Data)
    func disconnectSession()
}

@Observable
@MainActor
final class PeerCommunicatorAdvancedState {
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
    
    func addPeer(_ peerID: MCPeerID) {
        let newConnectedPeer = ConnectedPeer(peerID: peerID)
        connectedPeers.append(newConnectedPeer)
    }
    
    func setPeerAsConnected(_ peerID: MCPeerID) {
        guard let connectedPeer = connectedPeers.first(where: { $0.mcPeerID == peerID }) else { return }
        connectedPeer.isConnected = true
        connectedPeer.isSelected = true
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
final class PeerCommunicatorAdvanced: NSObject, PeerCommunicationAdvanced {
    let state = PeerCommunicatorAdvancedState()
    private nonisolated let peerID: MCPeerID
    private let session: MCSession
    private var serviceBrowser: MCNearbyServiceBrowser
    private var serviceAdvertiser: MCNearbyServiceAdvertiser
    private let serviceType = "dwb-mpbench"
    private var peerFoundTimestamp = [MCPeerID: Date]()
    
    private let browserEventStream: AsyncStream<BrowserEvent>
    private nonisolated let browserEventContinuation: AsyncStream<BrowserEvent>.Continuation
    
    private let advertiserEventStream: AsyncStream<AdvertiserEvent>
    private nonisolated let advertiserEventContinuation: AsyncStream<AdvertiserEvent>.Continuation
    
    private let sessionStateStream: AsyncStream<(MCPeerID, MCSessionState)>
    private nonisolated let sessionStateContinuation: AsyncStream<(MCPeerID, MCSessionState)>.Continuation
    
    private let receivedDataStream: AsyncStream<(Data, MCPeerID)>
    private nonisolated let receivedDataContinuation: AsyncStream<(Data, MCPeerID)>.Continuation
    
    private var restartTask: Task<Void, Error>?
    private var reconnectTask: Task<Void, Error>?
        
    init(displayNameInput: String? = nil) {
        var myPeerDisplayName: String
        
        if let displayNameInput {
            myPeerDisplayName = PeerIDDisplayNameAssistant.validDisplayName(from: displayNameInput)
        } else {
            myPeerDisplayName = PeerIDDisplayNameAssistant.deviceName
        }
        
        let peerID = MCPeerID(displayName: myPeerDisplayName)
        self.peerID = peerID
        self.session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        self.serviceBrowser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        self.serviceAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        
        (browserEventStream, browserEventContinuation) = AsyncStream.makeStream()
        (advertiserEventStream, advertiserEventContinuation) = AsyncStream.makeStream()
        (sessionStateStream, sessionStateContinuation) = AsyncStream.makeStream()
        (receivedDataStream, receivedDataContinuation) = AsyncStream.makeStream()
        
        super.init()
        
        // Single consumer for browser events
        Task { [weak self] in
            guard let stream = self?.browserEventStream else { return }
            for await event in stream {
                guard let self else { return }
                self.handleBrowserEvent(event)
            }
        }
        
        // Single consumer for advertiser events
        Task { [weak self] in
            guard let stream = self?.advertiserEventStream else { return }
            for await event in stream {
                guard let self else { return }
                self.handleAdvertiserEvent(event)
            }
        }
        
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
        
        self.session.delegate = self
        self.serviceBrowser.delegate = self
        self.serviceAdvertiser.delegate = self
        
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.state.log(message: "⚠️ App will go to background)")
                
                self.reconnectTask?.cancel()
                self.restartTask?.cancel()
                
                self.stopBroadcasting()
            }
        }
        
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.state.log(message: "🟢 App did become active)")
                
                self.restartTask?.cancel()
                
                self.restartTask = Task { @MainActor [weak self] in
                    try await Task.sleep(for: .seconds(2))
                    guard let self, !Task.isCancelled else { return }
                    
                    self.state.log(message: "🔄 Restarting browsing and advertising")
                    try await self.recreateBrowserAndAdvertiser()
                }
            }
        }
    }
    
    deinit {
        browserEventContinuation.finish()
        advertiserEventContinuation.finish()
        sessionStateContinuation.finish()
        receivedDataContinuation.finish()
    }
    
    func startBroadcasting() {
        startBrowsing()
        startAdvertising()
    }
    
    func stopBroadcasting() {
        stopBrowsing()
        stopAdvertising()
    }
    
    private func startBrowsing() {
        assert(state.isBrowsing == false, "Calling startBrowsingForPeers() again is not supported, will cause crashes.")
        guard state.isBrowsing == false else { return }
        serviceBrowser.startBrowsingForPeers()
        state.log(message: "🟢 Browsing started")
        state.setIsBrowsing(true)
    }
    
    private func stopBrowsing() {
        serviceBrowser.stopBrowsingForPeers()
        state.log(message: "🔴 Browsing stopped")
        state.setIsBrowsing(false)
    }
    
    private func startAdvertising() {
        assert(state.isAdvertising == false, "Calling startAdvertisingPeer() again is not supported, will cause crashes.")
        guard state.isAdvertising == false else { return }
        serviceAdvertiser.startAdvertisingPeer()
        state.log(message: "🟢 Advertising started")
        state.setIsAdvertising(true)
    }
    
    private func stopAdvertising() {
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
    
    func disconnectSession() {
        session.disconnect()
        state.removeAllConnectedPeers()
        peerFoundTimestamp.removeAll()
        state.log(message: "🔴 Session disconnected")
    }
}

// MARK: Advertiser Delegate
extension PeerCommunicatorAdvanced: MCNearbyServiceAdvertiserDelegate {
    
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        advertiserEventContinuation.yield(.receivedInvitation(peerID, context, invitationHandler))
    }
    
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        advertiserEventContinuation.yield(.failed(error))
    }
    
    private func handleAdvertiserEvent(_ event: AdvertiserEvent) {
        switch event {
        case .receivedInvitation(let peerID, _, let invitation):
            state.log(message: "📬 Received invitation from: \(peerID.displayName)")
            
            if peerFoundTimestamp[peerID] == nil {
                peerFoundTimestamp[peerID] = Date()
            }
            
            invitation(true, session)
            state.log(message: "🤝 Accepted invitation from: \(peerID.displayName)")
            
        case .failed(let error):
            state.setIsAdvertising(false)
            state.log(message: "⛔️ Did not start advertising peer, error: \(error.localizedDescription)")
        }
    }
}

// MARK: Browser Delegate
extension PeerCommunicatorAdvanced: MCNearbyServiceBrowserDelegate {
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        browserEventContinuation.yield(.foundPeer(peerID, info))
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        browserEventContinuation.yield(.lostPeer(peerID))
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        browserEventContinuation.yield(.failed(error))
    }
    
    private func handleBrowserEvent(_ event: BrowserEvent) {
        switch event {
        case .foundPeer(let peerID, let discoveryInfo):
            state.log(message: "👋 Found \(peerID.displayName)")
            
            if peerFoundTimestamp[peerID] == nil {
                peerFoundTimestamp[peerID] = Date()
            }
            
            guard session.connectedPeers.doesNotContain(peerID) else { return }
            serviceBrowser.invitePeer(peerID, to: session, withContext: nil, timeout: 45)
            state.log(message: "✉️ Invited \(peerID.displayName) to join session")
            
        case .lostPeer(let peerID):
            state.log(message: "⚠️ Lost \(peerID.displayName)")
            
        case .failed(let error):
            state.setIsBrowsing(false)
            state.log(message: "⛔️ Did not start browsing for peers, error: \(error.localizedDescription)")
        }
    }
}

// MARK: Session Delegate
extension PeerCommunicatorAdvanced: MCSessionDelegate {
    
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        sessionStateContinuation.yield((peerID, state))
    }
    
    private func handleSessionStateChange(peerID: MCPeerID, state: MCSessionState) {
        switch state {
        case MCSessionState.connecting:
            self.state.addPeer(peerID)
            self.state.log(message: "📡 Connecting to \(peerID.displayName)")
            
        case MCSessionState.connected:
            let peerFoundTime = peerFoundTimestamp.removeValue(forKey: peerID) ?? Date()
            let connectionTimeInterval = Date().timeIntervalSince(peerFoundTime).formatted(.number.precision(.fractionLength(2)))
            self.state.log(message: "📳 Connected to \(peerID.displayName) in \(connectionTimeInterval) seconds")
            self.state.setPeerAsConnected(peerID)
            
        case MCSessionState.notConnected:
            let isAConnectedPeer = self.state.connectedPeers.contains(where: { $0.mcPeerID == peerID })
            
            if isAConnectedPeer {
                self.state.log(message: "📵 Not connected to \(peerID.displayName) \(peerID.hash)")
                self.state.removeConnectedPeer(peerID)
                self.peerFoundTimestamp.removeValue(forKey: peerID)
                self.scheduleBrowsingAdvertisingRestart()
            } else {
                peerFoundTimestamp.removeValue(forKey: peerID)
                self.state.log(message: "📵 Not connected to \(peerID.displayName) \(peerID.hash) (Ignored, not a connected peer)")
            }
            
        @unknown default:
            print("\(peerID.displayName) has unknown MCSessionState \(state)")
        }
    }
    
    private func scheduleBrowsingAdvertisingRestart() {
        guard UIApplication.shared.applicationState == .active else {
            state.log(message: "⏸️ Skipping restart, app not active")
            return
        }
        
        reconnectTask?.cancel()
        
        reconnectTask = Task { @MainActor [weak self] in
            try await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            
            self.state.log(message: "🔄 Recreating browser and advertiser")
            try await self.recreateBrowserAndAdvertiser()
        }
    }
    
    private func recreateBrowserAndAdvertiser() async throws {
        // Stop and detach old instances
        stopBroadcasting()
        serviceBrowser.delegate = nil
        serviceAdvertiser.delegate = nil
        
        // Create fresh instances
        serviceBrowser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        serviceAdvertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        
        // Reconnect delegates
        serviceBrowser.delegate = self
        serviceAdvertiser.delegate = self
        
        // Start fresh
        startBrowsing()
        try await Task.sleep(for: .seconds(1))
        startAdvertising()
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

private enum BrowserEvent {
    case foundPeer(MCPeerID, [String: String]?)
    case lostPeer(MCPeerID)
    case failed(Error)
}

private enum AdvertiserEvent {
    case receivedInvitation(MCPeerID, Data?, (Bool, MCSession?) -> Void)
    case failed(Error)
}

// MARK: Mock
@MainActor
final class MockPeerCommunicatorAdvanced: PeerCommunicationAdvanced {
    let state = PeerCommunicatorAdvancedState()
    
    init(withConnectedPeers: Bool = true) {
        if withConnectedPeers {
            state.addPeer(MCPeerID(displayName: "Ashley iPhone"))
            state.addPeer(MCPeerID(displayName: "Pierson iPad"))
            state.addPeer(MCPeerID(displayName: "Liam Mac"))
        }
    }
    
    func startBroadcasting() {
        startBrowsing()
        startAdvertising()
    }
    
    func stopBroadcasting() {
        state.setIsBrowsing(false)
        state.setIsAdvertising(false)
    }
    
    private func startBrowsing() {
        print(#function)
        state.setIsBrowsing(true)
        
        state.log(message: "🟢 Browsing started")
        state.log(message: "👋 Found Ashley iPhone")
        state.log(message: "✉️ Invited Ashley iPhone to join session")
    }
    
    private func startAdvertising() {
        print(#function)
        state.setIsAdvertising(true)
        
        state.log(message: "🟢 Advertising started")
    }
    
    func sendData(_ data: Data) {
        print("sent data: \(data.count) bytes")
    }
    
    func disconnectSession() {
        print("session disconnected")
        state.removeAllConnectedPeers()
    }
}
