//
//  BadgePositionPreferenceKey.swift
//  LangGo
//
//  Created by James Tang on 2025/8/22.
//


// BadgePositionPreferenceKey.swift

import SwiftUI

struct BadgePositionPreferenceKey: PreferenceKey {
    typealias Value = Anchor<CGPoint>?
    
    static var defaultValue: Value = nil
    
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value = value ?? nextValue()
    }
}