//
//  FlashcardReviewView.swift
//  LangGo
//
//  Created by James Tang on 2025/6/27.
//

import Foundation
import SwiftUI

struct FlashcardReviewView: View {
    @Environment(\.dismiss) var dismiss
    var viewModel: FlashcardViewModel
    
    @State private var currentIndex = 0
    
    // Used for the flip animation
    @State private var isFlipped = false
    
    var body: some View {
        VStack {
            if viewModel.reviewCards.isEmpty {
                Text("No cards to review!")
                    .font(.largeTitle)
                    .onAppear {
                        // Dismiss if there are no cards
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            dismiss()
                        }
                    }
            } else {
                // --- Progress Bar ---
                ProgressView(value: Double(currentIndex), total: Double(viewModel.reviewCards.count))
                    .padding()
                
                Spacer()

                // --- Card View ---
                Text(viewModel.reviewCards[currentIndex].content)
                    .font(.system(size: 48, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding()
                
                Spacer()
                
                // --- Action Buttons ---
                HStack(spacing: 20) {
                    Button(action: { markCard(.wrong) }) {
                        Text("Wrong")
                            .font(.title2)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                    Button(action: { markCard(.correct) }) {
                        Text("Correct")
                             .font(.title2)
                             .fontWeight(.bold)
                             .frame(maxWidth: .infinity)
                             .padding()
                             .background(Color.green.opacity(0.8))
                             .foregroundColor(.white)
                             .cornerRadius(12)
                    }
                }
                .padding()
            }
        }
    }
    
    private enum Answer {
        case correct, wrong
    }
    
    private func markCard(_ answer: Answer) {
        let currentCard = viewModel.reviewCards[currentIndex]
        
        switch answer {
        case .correct:
            viewModel.markCorrect(for: currentCard)
        case .wrong:
            viewModel.markWrong(for: currentCard)
        }
        
        // Advance to the next card or finish
        if currentIndex < viewModel.reviewCards.count - 1 {
            currentIndex += 1
        } else {
            // Review is finished, dismiss the view
            dismiss()
        }
    }
}
