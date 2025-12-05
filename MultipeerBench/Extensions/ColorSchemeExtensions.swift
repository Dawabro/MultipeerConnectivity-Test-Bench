//
//  ColorSchemeExtensions.swift
//  MultipeerBench
//
//  Created by David Brown on 12/5/25.
//

import SwiftUI

extension ColorScheme {
    
    var isLight: Bool {
        self == .light
    }
    
    var isDark: Bool {
        !isLight
    }
}
