//
//  AdvancedPeerCommunicationView.swift
//  MultipeerBench
//
//  Created by David Brown on 12/5/25.
//

import SwiftUI

struct AdvancedPeerCommunicationView: View {
    var peerCommunicator: PeerCommunicationAdvanced
    private let browsingState: Binding<Bool>
    private let advertisingState: Binding<Bool>
    private let disconnectInBackgroundState: Binding<Bool>
    @State private var showClearLogsAlert = false
    @State private var showSessionDisconnectAlert = false
    
    private var dataSendingDisabled: Bool {
        peerCommunicator.connectedPeers.isEmpty ||  peerCommunicator.connectedPeers.allSatisfy { $0.isSelected == false }
    }
    
    init(peerCommunicator: PeerCommunicationAdvanced) {
        self.peerCommunicator = peerCommunicator
        
        self.browsingState = Binding<Bool>(
            get: {
                return peerCommunicator.isBrowsing
            }, set: { startBrowsing in
                if startBrowsing {
                    peerCommunicator.startBrowsing()
                } else {
                    peerCommunicator.stopBrowsing()
                }
            })
        
        self.advertisingState = Binding<Bool>(
            get: {
                return peerCommunicator.isAdvertising
            }, set: { startBrowsing in
                if startBrowsing {
                    peerCommunicator.startAdvertising()
                } else {
                    peerCommunicator.stopAdvertising()
                }
            })
        
        self.disconnectInBackgroundState = Binding<Bool>(
            get: {
                return peerCommunicator.disconnectInBackground
            }, set: { shouldDisconnectInBackground in
                peerCommunicator.setDisconnectInBackground(shouldDisconnectInBackground)
            })
    }
    
    var body: some View {
        VStack(spacing: 20) {
            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 20) {
                        Toggle("Browsing", isOn: browsingState)
                        Toggle("Advertising", isOn: advertisingState)
                        Toggle("Disconnect in Background", isOn: disconnectInBackgroundState)
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
                
                List(peerCommunicator.connectedPeers) { peer in
                    VStack(alignment: .leading, spacing: 4) {
                        ConnectedPeerRow(peer: peer)
                            .swipeActions {
                                Button("Disconnect") {
                                    peerCommunicator.disconnectPeer(peer)
                                }
                                .tint(.red)
                            }
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
                        ForEach(peerCommunicator.logs.sorted(by: { $0.timeStamp > $1.timeStamp })) { log in
                            LogEntryRow(logEntry: log)
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
            
            Spacer()
            
            Button("Send Data", action: sendData)
                .buttonStyle(.borderedProminent)
                .disabled(dataSendingDisabled)
        }
        .fontDesign(.monospaced)
        .alert("Clear Logs?", isPresented: $showClearLogsAlert) {
            Button(role: .destructive) {
                peerCommunicator.clearLogs()
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
    
    private func sendData() {
        let testData = Data([1, 2, 3, 4, 5])
        peerCommunicator.sendData(testData)
    }
}

fileprivate struct ConnectedPeerRow: View {
    var peer: ConnectedPeer
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button {
            peer.isSelected.toggle()
        } label: {
            HStack {
                Text(peer.displayName)
                    .foregroundStyle(colorScheme.isLight ? .black : .white)
                
                Spacer()
                Image(systemName: peer.isSelected ? "antenna.radiowaves.left.and.right.circle" : "antenna.radiowaves.left.and.right.slash.circle")
                    .font(.title)
                    .foregroundStyle(peer.isSelected ? .blue : .gray)
            }
        }
    }
}

fileprivate struct LogEntryRow: View {
    var logEntry: LogEntry
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(logEntry.message)
                .font(.caption)
            
            Text(logEntry.timeStamp.description)
                .font(.caption2)
                .padding(.leading, 25)
        }
    }
}

#Preview {
    AdvancedPeerCommunicationView(peerCommunicator: MockPeerCommunicatorAdvanced())
}
