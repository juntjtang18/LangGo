//
//  RecordModalView.swift
//  Fix: keep your working TTS playback and add a safe speech-activity waveform for the TOP row.
//  - Top-left plays with AVSpeechSynthesizer.speak(...) exactly as before (no engine, no disk I/O).
//  - The top waveform is driven by AVSpeechSynthesizer delegate callbacks + a timer (activity proxy).
//  - Recording + user playback still use real audio metering.
//  - MODIFIED: Both rows now save a reference waveform and overlay a live one on playback/rerecording.
//  - MODIFIED: Waveform animation now draws from left to right.
//  - MODIFIED: Waveform has a thin baseline for silence and leading horizontal padding.
//  - MODIFIED: Right-side button plays both native TTS and user recording simultaneously.
//

import SwiftUI
import AVFoundation

// MARK: - Simple audio recorder (unchanged)
final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var permissionDenied = false
    @Published var errorMessage: String?
    @Published var lastFileURL: URL?
    @Published var levels: [Float] = []

    private var recorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private let levelCapacity = 100

    func toggle() { isRecording ? stop() : start() }

    func start() {
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else { self.permissionDenied = true; return }
                do {
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
                    try session.setActive(true)
                    try self.beginRecording()
                    self.isRecording = true
                } catch {
                    self.errorMessage = error.localizedDescription
                    self.isRecording = false
                }
            }
        }
    }

    private func beginRecording() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.delegate = self
        recorder?.isMeteringEnabled = true

        guard recorder?.record() == true else {
            throw NSError(domain: "AudioRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start recording"])
        }

        lastFileURL = url
        levels.removeAll()
        startMetering()
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        stopMetering()
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch { /* ignore */ }
    }

    private func startMetering() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { [weak self] _ in
            guard let self = self, let rec = self.recorder else { return }
            rec.updateMeters()
            let dB = rec.averagePower(forChannel: 0)
            let clampedDB = max(-50, dB)
            let linear = pow(10.0, clampedDB / 20.0)
            let gain: Float = 2.6
            let shaped = min(1.0, pow(Float(linear) * gain, 0.7))
            DispatchQueue.main.async {
                self.levels.append(shaped)
                if self.levels.count > self.levelCapacity {
                    self.levels.removeFirst(self.levels.count - self.levelCapacity)
                }
            }
        }
    }
    private func stopMetering() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        DispatchQueue.main.async { self.errorMessage = error?.localizedDescription; self.stop() }
    }

    deinit { if isRecording { stop() } }
}

// MARK: - AVSpeechSynthesizer delegate proxy (unchanged)
final class SynthDelegateProxy: NSObject, AVSpeechSynthesizerDelegate {
    var onStart: (() -> Void)?
    var onWillSpeakRange: ((NSRange) -> Void)?
    var onFinish: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) { onStart?() }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) { onWillSpeakRange?(characterRange) }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { onFinish?() }
}

// MARK: - UI
struct RecordModalView: View {
    let phrase: String
    let onClose: () -> Void

    @StateObject private var recorder = AudioRecorder()

    // Playback (user recording)
    @State private var player: AVAudioPlayer?
    @State private var playerTimer: Timer?
    @State private var playbackLevels: [Float] = []
    @State private var userReferenceLevels: [Float] = []

    // Playback (native TTS)
    private let synthesizer = AVSpeechSynthesizer()
    private let synthProxy = SynthDelegateProxy()
    @State private var nativeIsSpeaking = false
    @State private var referenceNativeLevels: [Float] = []
    @State private var liveNativeLevels: [Float] = []
    @State private var nativeTimer: Timer?
    @State private var nativeLastLevel: Float = 0

    private var hasRecording: Bool { recorder.lastFileURL != nil }
    private var isPlayingUser: Bool { (player?.isPlaying ?? false) }
    private var isPlayingNative: Bool { synthesizer.isSpeaking }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(8)
                        .background(Circle().fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            Text(phrase)
                .font(.title2).bold()
                .multilineTextAlignment(.center)

            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 16) {
                    // TOP: Native playback row
                    GeometryReader { proxy in
                        HStack(spacing: 12) {
                            Button(action: playNative) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .imageScale(.large)
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(Color.black))
                            }
                            .buttonStyle(.plain)

                            CombinedWaveformView(
                                referenceLevels: referenceNativeLevels,
                                liveLevels: liveNativeLevels
                            )
                            .frame(height: 56)
                        }
                        .padding(.leading, proxy.size.width * 0.10)
                        .padding(.trailing, proxy.size.width * 0.03)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 72)

                    // BOTTOM: User recording/playback row
                    GeometryReader { proxy in
                        HStack(spacing: 12) {
                            Button(action: playUserRecording) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .imageScale(.large)
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Circle().fill(hasRecording ? Color.black : Color.gray.opacity(0.5)))
                            }
                            .buttonStyle(.plain)
                            .disabled(!hasRecording)

                            CombinedWaveformView(
                                referenceLevels: userReferenceLevels,
                                liveLevels: recorder.isRecording ? recorder.levels : (isPlayingUser ? playbackLevels : [])
                            )
                            .frame(height: 56)
                        }
                        .padding(.leading, proxy.size.width * 0.10)
                        .padding(.trailing, proxy.size.width * 0.03)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 72)
                }
                .frame(maxWidth: .infinity)

                // ** MODIFIED: Right-side button action points to playBoth() **
                SideIconWithBracketButton(
                    systemName: "speaker.wave.2.fill",
                    fill: Color(red: 0.32, green: 0.33, blue: 0.39),
                    enabled: hasRecording,
                    action: playBoth
                )
                .frame(width: 92, height: 160)
            }
            .padding(.horizontal, 8)

            Button {
                recorder.toggle()
            } label: {
                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(recorder.isRecording ? .red : .black))
                    .shadow(radius: 6, y: 3)
                    .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            
            Text("The top row plays the standard voice; the bottom and right buttons play your recording. Both save a reference waveform.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: 520, maxHeight: 520)
        .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThickMaterial))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.secondary.opacity(0.15)))
        .padding(.horizontal, 20)
        .onAppear {
            synthesizer.delegate = synthProxy
            synthProxy.onStart = { nativeIsSpeaking = true; startNativeActivityTimer() }
            synthProxy.onWillSpeakRange = { _ in bumpNativeActivity() }
            synthProxy.onFinish = {
                nativeIsSpeaking = false
                if referenceNativeLevels.isEmpty {
                    referenceNativeLevels = liveNativeLevels
                }
            }
        }
        .onChange(of: recorder.isRecording) { isRecordingNow in
            if !isRecordingNow && hasRecording {
                userReferenceLevels = recorder.levels
            }
        }
        .onDisappear {
            if recorder.isRecording { recorder.stop() }
            stopUserPlaybackMetering()
            stopNativeActivityTimer()
        }
        .alert("Microphone Access Needed", isPresented: $recorder.permissionDenied) {
            Button("OK", role: .cancel) {}
        } message: { Text("Please allow microphone access in Settings to record your voice.") }
        .alert("Playback Error", isPresented: Binding(get: { playbackErrorMessage != nil }, set: { _ in playbackErrorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(playbackErrorMessage ?? "") }
        .alert("Recording Error", isPresented: Binding(get: { recorder.errorMessage != nil }, set: { _ in recorder.errorMessage = nil })) {
            Button("OK", role: .cancel) {}
        } message: { Text(recorder.errorMessage ?? "") }
    }

    @State private var playbackErrorMessage: String?

    // ** NEW: Function to play both audio sources simultaneously **
    private func playBoth() {
        guard hasRecording else { return }
        playNative()
        playUserRecording()
    }

    private func playUserRecording() {
        guard !isPlayingUser, let url = recorder.lastFileURL else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // ** MODIFIED: Added .mixWithOthers to allow simultaneous playback **
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try session.setActive(true)
            
            player = try AVAudioPlayer(contentsOf: url)
            player?.isMeteringEnabled = true
            player?.prepareToPlay()
            player?.play()
            startUserPlaybackMetering()
        } catch {
            playbackErrorMessage = error.localizedDescription
        }
    }

    private func startUserPlaybackMetering() {
        stopUserPlaybackMetering()
        playbackLevels.removeAll()
        playerTimer = Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { _ in
            guard let p = player, p.isPlaying else { stopUserPlaybackMetering(); return }
            p.updateMeters()
            let dB = p.averagePower(forChannel: 0)
            let clampedDB = max(-50, dB)
            let linear = pow(10.0, clampedDB / 20.0)
            let gain: Float = 2.6
            let shaped = min(1.0, pow(Float(linear) * gain, 0.7))
            playbackLevels.append(shaped)
            if playbackLevels.count > 100 {
                playbackLevels.removeFirst(playbackLevels.count - 100)
            }
        }
    }

    private func stopUserPlaybackMetering() {
        playerTimer?.invalidate()
        playerTimer = nil
    }

    private func playNative() {
        if isPlayingNative { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        synthesizer.speak(utterance)
    }

    private func bumpNativeActivity() {
        nativeLastLevel = min(1.0, nativeLastLevel + 0.35 + Float.random(in: 0...0.25))
    }

    private func startNativeActivityTimer() {
        stopNativeActivityTimer()
        liveNativeLevels.removeAll()
        nativeLastLevel = 0.0
        nativeTimer = Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { _ in
            let decay: Float = 0.90
            nativeLastLevel *= decay
            let floor: Float = isPlayingNative ? 0.08 : 0.0
            let value = max(floor, nativeLastLevel)
            liveNativeLevels.append(value)
            if liveNativeLevels.count > 100 {
                liveNativeLevels.removeFirst(liveNativeLevels.count - 100)
            }
            if !isPlayingNative && value < 0.01 {
                stopNativeActivityTimer()
            }
        }
    }

    private func stopNativeActivityTimer() {
        nativeTimer?.invalidate()
        nativeTimer = nil
        nativeLastLevel = 0
    }
}

// MARK: - Subviews
private struct SideIconWithBracketButton: View {
    let systemName: String
    var fill: Color = Color.black
    let enabled: Bool
    let action: () -> Void

    private let tick: CGFloat = 14
    private let gapToIcon: CGFloat = 8
    private let lineWidth: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let diameter: CGFloat = 48
            let centerY = proxy.size.height / 2
            let iconCenterX = proxy.size.width - diameter / 2
            let radius = diameter / 2
            let bracketX = iconCenterX - radius - gapToIcon

            ZStack {
                Path { p in
                    let topY: CGFloat = 6
                    let bottomY: CGFloat = proxy.size.height - 6
                    p.move(to: CGPoint(x: bracketX, y: topY)); p.addLine(to: CGPoint(x: bracketX - tick, y: topY))
                    p.move(to: CGPoint(x: bracketX, y: topY)); p.addLine(to: CGPoint(x: bracketX, y: bottomY))
                    p.move(to: CGPoint(x: bracketX, y: bottomY)); p.addLine(to: CGPoint(x: bracketX - tick, y: bottomY))
                }
                .stroke(Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                Button(action: action) {
                    Image(systemName: systemName).font(.title2).foregroundColor(.white).frame(width: diameter, height: diameter)
                        .background(Circle().fill(enabled ? fill : Color.gray.opacity(0.5))).shadow(radius: 4, y: 2)
                }
                .buttonStyle(.plain).position(x: iconCenterX, y: centerY).opacity(enabled ? 1.0 : 0.5).allowsHitTesting(enabled)
            }
        }
    }
}

private struct CombinedWaveformView: View {
    var referenceLevels: [Float]
    var liveLevels: [Float]

    var body: some View {
        ZStack {
            LiveWaveform(levels: referenceLevels, barColor: .secondary.opacity(0.4))
            LiveWaveform(levels: liveLevels, barColor: .accentColor.opacity(0.8))
        }
        .background(Color.secondary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Live waveform rendering
private struct LiveWaveform: View {
    var levels: [Float]
    var barColor: Color = .secondary.opacity(0.7)

    var body: some View {
        GeometryReader { proxy in
            let barCount = 56
            let slice = Array(levels.suffix(barCount))
            let padded = slice + Array(repeating: Float(0), count: max(0, barCount - slice.count))
            let height = proxy.size.height
            let horizontalPadding: CGFloat = 5
            let availableWidth = proxy.size.width - (horizontalPadding * 2)
            let barSlot = availableWidth / CGFloat(barCount)
            let barWidth = barSlot * 0.7
            let spacing = barSlot * 0.3

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    let v = padded[i]
                    let isSilent = v < 0.02
                    let barHeight = isSilent ? 2.0 : max(6, CGFloat(v) * height)
                    
                    Capsule()
                        .frame(width: barWidth, height: barHeight)
                        .foregroundStyle(barColor)
                        .animation(.linear(duration: 0.035), value: levels)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, horizontalPadding)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
