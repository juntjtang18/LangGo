// BadgePositionPreferenceKey.swift

import SwiftUI

struct BadgePositionPreferenceKey: PreferenceKey {
    typealias Value = Anchor<CGPoint>?
    
    static var defaultValue: Value = nil
    
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value = value ?? nextValue()
    }
}
