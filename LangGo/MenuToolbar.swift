//
//  MenuToolbar.swift
//  LangGo
//
//  Created by James Tang on 2025/8/9.
//


import SwiftUI

struct MenuToolbar: ToolbarContent {
    @Binding var isSideMenuShowing: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: {
                withAnimation(.easeInOut) {
                    isSideMenuShowing.toggle()
                }
            }) {
                Image(systemName: "line.3.horizontal")
                    .font(.title3)
                    .foregroundColor(.primary)
            }
        }
    }
}