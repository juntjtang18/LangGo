// LangGo/Vocabook/ScanWordToVocabookFlowView.swift
import SwiftUI
import AVFoundation
import UIKit
import Vision

struct ScanWordToVocabookFlowView: View {
    @State private var stage: ScanWordStage = .processing
    @State private var isShowingCamera = true
    @State private var scannedText = ""

    let onCancel: () -> Void
    let onSaved: () -> Void

    var body: some View {
        Group {
            switch stage {
            case .processing:
                ScanWordOCRProcessingView()
            case .picker:
                ScanWordPickerView(
                    text: scannedText,
                    onClose: onCancel,
                    onSaved: onSaved
                )
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            isShowingCamera = true
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            ScanWordCameraCaptureView { image in
                isShowingCamera = false
                beginOCRProcessing(for: image)
            } onCancel: {
                onCancel()
            }
        }
    }

    private func beginOCRProcessing(for image: UIImage) {
        stage = .processing

        Task {
            let extractedText = await WordScanOCRService.recognizeText(from: image)
            await MainActor.run {
                scannedText = extractedText
                stage = .picker
            }
        }
    }
}

private enum ScanWordStage {
    case processing
    case picker
}

private struct ScanWordCameraCaptureView: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImagePicked: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImagePicked: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImagePicked = onImagePicked
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            } else {
                onCancel()
            }
        }
    }
}

private struct ScanWordOCRProcessingView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color(red: 0.10, green: 0.45, blue: 0.98))

                Text("Processing OCR...")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.14, green: 0.16, blue: 0.22))

                Text("Extracting words from your photo.")
                    .font(.system(size: 19, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.50, green: 0.52, blue: 0.58))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }
    }
}

private struct ScanWordPickerView: View {
    @StateObject private var viewModel = ScannedWordPickerViewModel()
    @State private var selectedWord = ""
    @State private var selectedParagraphIndex: Int?
    @State private var selectedWordRange: NSRange?
    @State private var wordFrame: CGRect = .zero
    @State private var showTranslationPopover = false

    let text: String
    let onClose: () -> Void
    let onSaved: () -> Void

    private var paragraphs: [String] {
        text.components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    topBar

                    if paragraphs.isEmpty {
                        emptyState
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 18) {
                                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                                    SelectableTextView(
                                        text: paragraph,
                                        fontSize: 20,
                                        selectedWordRange: selectedParagraphIndex == index ? selectedWordRange : nil,
                                        spokenSentenceRange: nil
                                    ) { word, sentence, frame, range in
                                        selectedWord = word
                                        selectedParagraphIndex = index
                                        selectedWordRange = range
                                        wordFrame = frame
                                        showTranslationPopover = true
                                        Task {
                                            await viewModel.translate(word: word, sentence: sentence)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 44)
                        }
                    }
                }
                .background(Color.white)

                feedbackToast
            }
            .overlay {
                translationPopoverOverlay(screenGeometry: proxy)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .alert("Scan Word", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                onClose()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                    Text("Close")
                }
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color(red: 0.35, green: 0.38, blue: 0.46))
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Pick a Word")
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.14, green: 0.16, blue: 0.22))

            Spacer()

            Color.clear
                .frame(width: 72, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Color(red: 0.52, green: 0.54, blue: 0.60))

            Text("No text found")
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.14, green: 0.16, blue: 0.22))

            Text("Close and scan another photo.")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.50, green: 0.52, blue: 0.58))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    private func translationPopoverOverlay(screenGeometry: GeometryProxy) -> some View {
        ZStack {
            if showTranslationPopover {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showTranslationPopover = false
                        selectedParagraphIndex = nil
                        selectedWordRange = nil
                    }

                TranslationPopover(
                    originalWord: selectedWord,
                    translationData: viewModel.contextualTranslation,
                    isLoading: viewModel.isTranslating || viewModel.isSavingWord,
                    onSave: {
                        Task {
                            await viewModel.saveWordToVocab(word: selectedWord)
                            if viewModel.errorMessage == nil {
                                onSaved()
                            }
                        }
                    },
                    onPlayAudio: {
                        let utterance = AVSpeechUtterance(string: selectedWord)
                        utterance.voice = AVSpeechSynthesisVoice(language: Config.learningTargetLanguageCode)
                        AVSpeechSynthesizer().speak(utterance)
                    }
                )
                .modifier(PopoverPositioner(wordFrame: wordFrame))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: screenGeometry.size.width, height: screenGeometry.size.height)
        .allowsHitTesting(showTranslationPopover)
    }

    @ViewBuilder
    private var feedbackToast: some View {
        if let feedbackMessage = viewModel.feedbackMessage {
            Text(feedbackMessage)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
                .shadow(radius: 5)
                .padding(.bottom, 32)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )
    }
}

@MainActor
private final class ScannedWordPickerViewModel: ObservableObject {
    @Published var contextualTranslation: StoryViewModel.ContextualTranslation?
    @Published var isTranslating = false
    @Published var isSavingWord = false
    @Published var errorMessage: String?
    @Published var feedbackMessage: String?

    private let wordService = DataServices.shared.wordService

    func translate(word: String, sentence: String) async {
        let baseLanguage = UserSessionManager.shared.currentUser?.user_profile?.baseLanguage ?? "en"
        let learningLanguage = Config.learningTargetLanguageCode

        guard learningLanguage != baseLanguage else {
            contextualTranslation = .init(
                translatedWord: word,
                translatedSentence: sentence,
                partOfSpeech: ""
            )
            return
        }

        isTranslating = true
        defer { isTranslating = false }

        do {
            let response = try await wordService.translateWordInContext(
                word: word,
                sentence: sentence,
                sourceLang: learningLanguage,
                targetLang: baseLanguage
            )
            contextualTranslation = .init(
                translatedWord: response.translation,
                translatedSentence: response.sentence,
                partOfSpeech: response.partOfSpeech
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveWordToVocab(word: String) async {
        guard let translation = contextualTranslation else { return }

        let baseLanguage = UserSessionManager.shared.currentUser?.user_profile?.baseLanguage ?? "en"
        isSavingWord = true
        defer { isSavingWord = false }

        do {
            _ = try await wordService.saveNewWord(
                targetText: word,
                baseText: translation.translatedWord,
                partOfSpeech: translation.partOfSpeech,
                locale: baseLanguage
            )
            feedbackMessage = "Saved to Vocabook"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum WordScanOCRService {
    static func recognizeText(from image: UIImage) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { request, _ in
                    let text = (request.results as? [VNRecognizedTextObservation])?
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: "\n\n") ?? ""
                    continuation.resume(returning: text)
                }

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                do {
                    let handler = try makeImageHandler(from: image)
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    private static func makeImageHandler(from image: UIImage) throws -> VNImageRequestHandler {
        if let cgImage = image.cgImage {
            return VNImageRequestHandler(
                cgImage: cgImage,
                orientation: CGImagePropertyOrientation(image.imageOrientation),
                options: [:]
            )
        }

        if let ciImage = image.ciImage {
            return VNImageRequestHandler(
                ciImage: ciImage,
                orientation: CGImagePropertyOrientation(image.imageOrientation),
                options: [:]
            )
        }

        throw WordScanOCRFailure.invalidImage
    }
}

private enum WordScanOCRFailure: Error {
    case invalidImage
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
