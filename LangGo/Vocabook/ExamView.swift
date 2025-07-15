import SwiftUI

struct ExamView: View {
    @Environment(\.dismiss) var dismiss
    @State var viewModel: ExamViewModel

    init(flashcards: [Flashcard], strapiService: StrapiService) {
        _viewModel = State(initialValue: ExamViewModel(flashcards: flashcards, strapiService: strapiService))
    }

    var body: some View {
        NavigationStack {
            VStack {
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
                                        if option.isCorrect {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.headline)
                                        } else if option.text == viewModel.selectedOption?.text {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .font(.headline)
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
                            .transition(.opacity.animation(.easeInOut))
                        }
                    }
                    .padding()
                } else {
                    Text("No exam questions available.")
                        .font(.title)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack {
                    Button(action: {
                        viewModel.goToPreviousCard()
                    }) {
                        Image(systemName: "arrow.left.circle.fill")
                            .font(.largeTitle)
                    }
                    .disabled(viewModel.currentCardIndex == 0)

                    Spacer()
                    
                    Button(action: {
                        viewModel.swapDirection()
                    }) {
                        Image(systemName: "arrow.2.squarepath")
                            .font(.largeTitle)
                    }

                    Spacer()

                    Button(action: {
                        viewModel.goToNextCard()
                    }) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.largeTitle)
                    }
                    .disabled(viewModel.currentCardIndex >= viewModel.flashcards.count - 1)
                }
                .padding()
            }
            .navigationTitle("Exam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
