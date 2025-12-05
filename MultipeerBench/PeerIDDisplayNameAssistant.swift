//
//  PeerIDDisplayNameAssistant.swift
//  MultipeerBench
//
//  Created by David Brown on 4/16/25.
//

import UIKit

struct PeerIDDisplayNameAssistant {
    private static let maxNameByteSize = 63
    
    static var deviceName: String {
        validDisplayName(from: UIDevice.current.name)
    }
    
    static func validDisplayName(from input: String) -> String {
        guard !displayNameIsValid(input) else { return input }
        var trimmedInput = String(input.prefix(maxNameByteSize))
        var trimCountLimit = 100
        
        while !displayNameIsValid(trimmedInput) {
            trimmedInput.removeLast()
            trimCountLimit -= 1
            guard trimCountLimit > 0 else { break }
        }
        
        return trimmedInput
    }
    
    private static func displayNameIsValid(_ proposedDisplayName: String) -> Bool {
        guard let data = proposedDisplayName.data(using: .utf8) else { return false }
        return data.count <= maxNameByteSize
    }
}
