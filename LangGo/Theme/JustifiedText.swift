//
//  JustifiedText.swift
//  LangGo
//
//  Created by James Tang on 2025/7/21.
//


import SwiftUI
import UIKit

struct JustifiedText: UIViewRepresentable {
    private let text: String
    private let font: UIFont

    init(_ text: String, font: UIFont = .systemFont(ofSize: 17, weight: .regular)) {
        self.text = text
        self.font = font
    }

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.textAlignment = .justified
        label.numberOfLines = 0 // Allow multiple lines
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ uiView: UILabel, context: Context) {
        let attributedString = NSAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .justified
                paragraphStyle.lineSpacing = 5 // Match your previous line spacing
                return paragraphStyle
            }()
        ])
        uiView.attributedText = attributedString
    }
}