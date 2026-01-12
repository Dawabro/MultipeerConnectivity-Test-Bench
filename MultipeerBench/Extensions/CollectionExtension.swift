//
//  CollectionExtension.swift
//  MultipeerBench
//
//  Created by David Brown on 1/11/26.
//

import Foundation

extension Collection where Element: Equatable {
    
    func doesNotContain(_ element: Element) -> Bool {
        contains(element) == false
    }
}

extension Collection where Element: Hashable {
    
    func doesNotContain(_ element: Element) -> Bool {
        contains(element) == false
    }
}
