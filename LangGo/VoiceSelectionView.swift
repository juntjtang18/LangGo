//
//  VoiceSelectionView.swift
//  LangGo
//
//  Created by James Tang on 2025/8/18.
//


// VoiceSelectionView.swift

import SwiftUI
import AVFoundation

struct VoiceSelectionView: View {
    // This view will observe the same ViewModel
    @EnvironmentObject var voiceService: VoiceSelectionService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                // --- Section for Standard Apple Voices ---
                Section(header: Text("Standard Voices")) {
                    // Loop through the voices provided by the ViewModel
                    ForEach(voiceService.availableStandardVoices, id: \.identifier) { voice in
                        voiceRow(for: voice)
                    }
                }

                // --- Section for Premium Subscription Voices ---
                Section(
                    header: Text("Premium Voices"),
                    footer: Text("Unlock higher quality, more natural voices with a Premium Subscription.")
                ) {
                    // Mockup of a premium voice option
                    premiumVoiceRow(name: "Google WaveNet Voice 1", isLocked: true)
                    premiumVoiceRow(name: "Google WaveNet Voice 2", isLocked: true)

                    // The call-to-action for your subscription
                    Button(action: {
                        // TODO: Trigger your paywall/subscription view
                        print("Presenting subscription view...")
                    }) {
                        HStack {
                            Spacer()
                            Image(systemName: "star.fill")
                            Text("Unlock with Premium")
                            Spacer()
                        }
                        .padding()
                        .foregroundColor(.white)
                        .background(Color.accentColor)
                        .cornerRadius(10)
                    }
                }
            }
            .navigationTitle("Select a Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                // Tell the ViewModel to load the voices when the view appears
                voiceService.fetchAvailableVoices()
            }
        }
    }

    // A reusable view for a single voice row
    private func voiceRow(for voice: AVSpeechSynthesisVoice) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(voice.name)
                Text("\(voice.language), \(voice.gender.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Button to sample the voice
            Button(action: {
                voiceService.sampleVoice(text: "Hello, you can select my voice.", identifier: voice.identifier)
            }) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)

            // Show a checkmark for the selected voice
            if voiceService.selectedVoiceIdentifier == voice.identifier {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.title2)
            }
        }
        .contentShape(Rectangle()) // Makes the whole row tappable
        .onTapGesture {
            voiceService.selectVoice(identifier: voice.identifier)
        }
    }
    
    // A simple view for a locked premium voice
    private func premiumVoiceRow(name: String, isLocked: Bool) -> some View {
        HStack {
            Text(name)
                .foregroundColor(.secondary)
            Spacer()
            Image(systemName: "lock.fill")
                .foregroundColor(.secondary)
        }
    }
}

// A helper extension for the voice's gender
extension AVSpeechSynthesisVoiceGender {
    var name: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        default: return "Unspecified"
        }
    }
}
