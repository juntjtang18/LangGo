// LangGo/Vocabook/ExamView.swift
import SwiftUI

struct ExamView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = ExamViewModel()

    var body: some View {
        NavigationStack {
            VStack {
                // MODIFIED: The view now handles loading, error, and content states.
                if viewModel.isLoading {
                    ProgressView("Loading Exam...")
                } else if let errorMessage = viewModel.errorMessage {
                    Text("Error: \(errorMessage)")
                        .foregroundColor(.red)
                        .padding()
                } else if viewModel.flashcards.isEmpty {
                    Text("No cards available for an exam at this time.")
                        .font(.title)
                        .foregroundColor(.secondary)
                } else {
                    // This is the main exam content, shown only when data is ready.
                    examContent
                }
            }
            .navigationTitle("Exam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            // The .task modifier triggers the data load when the view appears.
            .task {
                await viewModel.loadExamCards()
            }
        }
    }
    
    // The main UI for the exam, extracted into a computed property for clarity.
    private var examContent: some View {
        VStack {
            VStack {
                ProgressView(value: progressValue, total: progressTotal)
                Text(progressCountString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            if let question = viewModel.questionText, let options = viewModel.examOptions {
                VStack(alignment: .leading, spacing: 20) {
                    Text(question)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 20)

                    ForEach(options, id: \.text) { option in
                        Button(action: {
                            viewModel.selectOption(option)
                        }) {
                            HStack {
                                Text(option.text)
                                    .foregroundColor(Color(UIColor.label))
                                Spacer()
                                if viewModel.isAnswerSubmitted {
                                    if option.isCorrect == true {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                    } else if option.text == viewModel.selectedOption?.text {
                                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                                    }
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(viewModel.selectedOption?.text == option.text ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                        }
                        .disabled(viewModel.isAnswerSubmitted)
                    }

                    if viewModel.isAnswerSubmitted && viewModel.selectedOption?.isCorrect == false {
                        HStack(alignment: .top) {
                            Image(systemName: "info.circle.fill").foregroundColor(.blue)
                            Text("The correct answer is: **\(viewModel.correctAnswer ?? "N/A")**")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 10)
                    }
                }
                .padding()
            }
            
            Spacer()
            
            HStack {
                Button(action: viewModel.goToPreviousCard) {
                    Image(systemName: "arrow.left.circle.fill")
                }
                .disabled(viewModel.currentCardIndex == 0)
                .font(.largeTitle)

                Spacer()
                
                Button(action: viewModel.swapDirection) {
                    Image(systemName: "arrow.2.squarepath")
                }
                .font(.largeTitle)

                Spacer()
                
                Button(action: viewModel.goToNextCard) {
                    Image(systemName: "arrow.right.circle.fill")
                }
                .disabled(viewModel.currentCardIndex >= viewModel.flashcards.count - 1)
                .font(.largeTitle)
            }
            .padding()
        }
    }
    
    private var progressValue: Double {
        guard viewModel.flashcards.count > 0 else { return 0 }
        return Double(viewModel.currentCardIndex + 1)
    }
    private var progressTotal: Double {
        Double(max(1, viewModel.flashcards.count))
    }
    private var progressCountString: String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        let format = NSLocalizedString("%lld of %lld", comment: "Progress count format (e.g., 1 of 10)")
        return String(format: format, viewModel.currentCardIndex + 1, viewModel.flashcards.count)
    }


}
