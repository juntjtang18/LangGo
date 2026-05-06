// LangGo/Conversation/SpeechRecognizer.swift
import AVFoundation
import Speech
import SwiftUI

class SpeechRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published var isListening = false
    @Published var error: String?

    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer: SFSpeechRecognizer?

    init() {
        recognizer = SFSpeechRecognizer()
    }

    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                if authStatus != .authorized {
                    self.error = "Speech recognition permission was not granted."
                }
            }
        }

        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if !granted {
                        self.error = "Microphone access was not granted."
                    }
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if !granted {
                        self.error = "Microphone access was not granted."
                    }
                }
            }
        }
    }

    // UPDATED: This method no longer manages the AVAudioSession.
    func start() {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            self.error = "Speech recognizer is not available for the current locale."
            return
        }

        audioEngine = AVAudioEngine()
        request = SFSpeechAudioBufferRecognitionRequest()

        guard let request = request, let audioEngine = audioEngine else {
            self.error = "Could not create audio engine or recognition request."
            return
        }

        let inputNode = audioEngine.inputNode
        
        var recordingFormat = inputNode.outputFormat(forBus: 0)
        if recordingFormat.sampleRate == 0 || recordingFormat.channelCount == 0 {
            recordingFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 44100,
                channels: 1,
                interleaved: false
            )!
        }

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            self.error = "Invalid audio format: sample rate or channel count is zero."
            return
        }

        do {
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, _) in
                request.append(buffer)
            }

            audioEngine.prepare()
            
            // The audio session is now managed by the ViewModel. We just start the engine.
            try audioEngine.start()
            isListening = true

            task = recognizer.recognitionTask(with: request) { (result, error) in
                if let result = result {
                    self.transcript = result.bestTranscription.formattedString
                } else if error != nil {
                    self.error = "Recognition task error: \(error?.localizedDescription ?? "Unknown error")"
                    self.stop()
                }
            }
        } catch {
            self.error = "Could not start audio engine: \(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        task?.cancel()
        task?.finish()
        request?.endAudio()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)

        request = nil
        task = nil
        audioEngine = nil
        isListening = false
    }
}
