// LangGo/Vocabook/ExamView.swift
import SwiftUI
import SPConfetti

struct ExamView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = ExamViewModel()
    @State private var showFireworks = false
    @State private var showBadge = false

    var body: some View {
        ZStack {
            NavigationStack {
                VStack {
                    if viewModel.flashcards.isEmpty && viewModel.isLoading {
                        ProgressView("Loading Exam...")
                    } else if viewModel.flashcards.isEmpty, let errorMessage = viewModel.errorMessage {
                        Text("Error: \(errorMessage)")
                            .foregroundColor(.red)
                            .padding()
                    } else if viewModel.flashcards.isEmpty {
                        Text("No cards available for an exam at this time.")
                            .font(.title)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    } else {
                        examContent
                    }
                }
                .opacity(viewModel.isSessionComplete ? 0 : 1)
                .navigationTitle("Exam")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { dismiss() }) {
                            //    Button("Close") { dismiss() }
                            
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            
                        }
                    }
                }
                .task {
                    await viewModel.loadExamCards()
                }
            }
            
            if viewModel.isSessionComplete {
                ExamCelebrationView(showBadge: $showBadge) {
                    dismiss()
                }
                .confetti(isPresented: $showFireworks,
                          animation: .fullWidthToUp,
                          particles: [.star, .arc, .circle],
                          duration: 3.0)
            }
        }
        .onChange(of: viewModel.isSessionComplete) { completed in
            guard completed else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showFireworks = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    showBadge = true
                }
            }
        }
    }

    private var examContent: some View {
        VStack {
            VStack(spacing: 6) {
                ProgressView(value: progressValue, total: progressTotal)
                HStack(spacing: 8) {
                    Text(progressCountString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if let errorMessage = viewModel.errorMessage {
                Text("Could not load more cards: \(errorMessage)")
                    .font(.footnote)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

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
                .disabled(!viewModel.canGoNext)
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

private struct ExamCelebrationView: View {
    @Binding var showBadge: Bool
    var onClose: () -> Void

    var body: some View {
        VStack {
            Spacer()

            if showBadge {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 150, height: 150)
                            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)

                        Image(systemName: "star.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.white)
                    }

                    Text("Session Complete!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Button("Done") { onClose() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.top, 2)
                }
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}
