//
//  BasicPeerCommunicationView.swift
//  MultipeerBench
//
//  Created by David Brown on 12/5/25.
//

import SwiftUI

struct BasicPeerCommunicationView: View {
    var peerCommunicator: PeerCommunication
    var commState: PeerCommunicatorState
    @State private var showClearLogsAlert = false
    @State private var showSessionDisconnectAlert = false
    
    private var dataSendingDisabled: Bool {
        commState.connectedPeers.isEmpty ||  commState.connectedPeers.allSatisfy { $0.isSelected == false }
    }
    
    init(peerCommunicator: PeerCommunication, commState: PeerCommunicatorState) {
        self.peerCommunicator = peerCommunicator
        self.commState = commState
    }
    
    private var browsingState: Binding<Bool> {
        Binding<Bool>(
            get: {
                return commState.isBrowsing
            }, set: { startBrowsing in
                if startBrowsing {
                    Task {
                        peerCommunicator.startBrowsing()
                    }
                } else {
                    Task {
                        peerCommunicator.stopBrowsing()
                    }
                }
            })
    }
    
    private var advertisingState: Binding<Bool> {
        Binding<Bool>(
            get: {
                return commState.isAdvertising
            }, set: { startBrowsing in
                if startBrowsing {
                    Task {
                        peerCommunicator.startAdvertising()
                    }
                } else {
                    Task {
                        peerCommunicator.stopAdvertising()
                    }
                }
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
                            .swipeActions {
                                Button("Disconnect") {
                                    Task {
                                        peerCommunicator.disconnectPeer(peer)
                                    }
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
                        ForEach(commState.logs.sorted(by: { $0.timeStamp > $1.timeStamp })) { log in
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
                commState.clearLogs()
            } label: {
                Text("Clear")
            }
        }
        .alert("Disconnect Current Session?", isPresented: $showSessionDisconnectAlert) {
            Button(role: .destructive) {
                Task {
                    peerCommunicator.disconnectSession()
                }
            } label: {
                Text("Disconnect")
            }
        }
    }
    
    private func sendData() {
        Task {
            let testData = Data([1, 2, 3, 4, 5])
            peerCommunicator.sendData(testData)
        }
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
    BasicPeerCommunicationView(peerCommunicator: MockPeerCommunicator(), commState: PeerCommunicatorState())
}
