//
//  AdvancedPeerCommunicationView.swift
//  MultipeerBench
//
//  Created by David Brown on 12/5/25.
//

import SwiftUI

struct AdvancedPeerCommunicationView: View {
    var peerCommunicator: PeerCommunicationAdvanced
    var commState: PeerCommunicatorAdvancedState
    @State private var showClearLogsAlert = false
    @State private var showSessionDisconnectAlert = false
    @State private var highlightedLogIDs: Set<UUID> = []
    
    private var dataSendingDisabled: Bool {
        commState.connectedPeers.isEmpty ||  commState.connectedPeers.allSatisfy { $0.isSelected == false }
    }
    
    init(peerCommunicator: PeerCommunicationAdvanced, commState: PeerCommunicatorAdvancedState) {
        self.peerCommunicator = peerCommunicator
        self.commState = commState
    }
    
    private var commsEnabled: Binding<Bool> {
        Binding<Bool>(
            get: {
                return commState.isBrowsing && commState.isAdvertising
            }, set: { startComms in
                if startComms {
                    peerCommunicator.startBroadcasting()
                } else {
                    peerCommunicator.stopBroadcasting()
                }
            })
    }
    
    var body: some View {
        VStack(spacing: 20) {
            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 20) {
                        Toggle("Comms Enabled", isOn: commsEnabled)
                    }
                    .frame(maxWidth: 200)
                    .padding()
                    .padding(.trailing)
                }
                
                
                Divider()
            }
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Connected Peers:")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .underline()
                    
                    Spacer()
                    
                    Button(role: .destructive) {
                        showSessionDisconnectAlert = true
                    } label: {
                        Text("Disconnect Session")
                            .font(.caption)
                    }
                }
                
                List(commState.connectedPeers) { peer in
                    VStack(alignment: .leading, spacing: 4) {
                        ConnectedPeerRow(peer: peer)
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: 160)
            }
            .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Logs:")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .underline()
                    Spacer()
                    Button("", systemImage: "eraser", action: { showClearLogsAlert = true })
                        .font(.title3)
                }
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(commState.logs.sorted(by: { $0.timeStamp > $1.timeStamp })) { log in
                            LogEntryRow(logEntry: log, isHighlighted: highlightedLogIDs.contains(log.id))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .foregroundStyle(Color.gray.opacity(0.15))
            }
            .padding(.horizontal)
            .onChange(of: commState.logs.count) { oldCount, newCount in
                if newCount > oldCount {
                    highlightNewLogs()
                }
            }
            
            Spacer()
            
            Button("Send Data", action: sendData)
                .buttonStyle(.borderedProminent)
                .disabled(dataSendingDisabled)
        }
        .fontDesign(.monospaced)
        .alert("Clear Logs?", isPresented: $showClearLogsAlert) {
            Button(role: .destructive) {
                commState.clearLogs()
            } label: {
                Text("Clear")
            }
        }
        .alert("Disconnect Current Session?", isPresented: $showSessionDisconnectAlert) {
            Button(role: .destructive) {
                peerCommunicator.disconnectSession()
            } label: {
                Text("Disconnect")
            }
        }
    }
    
    private func highlightNewLogs() {
        let sortedLogs = commState.logs.sorted(by: { $0.timeStamp > $1.timeStamp })
        guard let newestLog = sortedLogs.first else { return }
        
        highlightedLogIDs.insert(newestLog.id)
        
        Task {
            try? await Task.sleep(for: .seconds(1))
            highlightedLogIDs.remove(newestLog.id)
        }
    }
    
    private func sendData() {
        let testData = Data([1, 2, 3, 4, 5])
        peerCommunicator.sendData(testData)
    }
}

fileprivate struct ConnectedPeerRow: View {
    var peer: ConnectedPeer
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            ProgressView()
                .opacity(peer.isConnected ? 0 : 1)
            
            Button {
                peer.isSelected.toggle()
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(peer.displayName)
                        
                        Text("\(peer.mcPeerID.hash)")
                            .font(.footnote)
                    }
                    .foregroundStyle(colorScheme.isLight ? .black : .white)
                    
                    Spacer()
                    Image(systemName: peer.isSelected ? "antenna.radiowaves.left.and.right.circle" : "antenna.radiowaves.left.and.right.slash.circle")
                        .font(.title)
                        .foregroundStyle(peer.isSelected ? .blue : .gray)
                }
            }
            .opacity(peer.isConnected ? 1 : 0.2)
            .disabled(!peer.isConnected)
        }
    }
}

fileprivate struct LogEntryRow: View {
    var logEntry: LogEntry
    var isHighlighted: Bool
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(logEntry.message)
                .font(.caption)
            
            Text(logEntry.timeStamp.description)
                .font(.caption2)
                .padding(.leading, 25)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHighlighted ? Color.yellow.opacity(0.3) : Color.clear)
        )
        .animation(.easeOut(duration: 0.7), value: isHighlighted)
    }
}

#Preview {
    AdvancedPeerCommunicationView(peerCommunicator: MockPeerCommunicatorAdvanced(), commState: PeerCommunicatorAdvancedState())
}
