//
//  LanguageSelectionView.swift
//  LangGo
//
//  Created by James Tang on 2025/8/13.
//


import SwiftUI

struct LanguageSelectionView: View {
    var onContinue: () -> Void
    @EnvironmentObject var languageSettings: LanguageSettings
    
    var body: some View {
        VStack {
            Text("What is your native language?")
                .font(.largeTitle)
                .padding()

            Picker("Select a language", selection: $languageSettings.selectedLanguageCode) {
                ForEach(LanguageSettings.availableLanguages) { language in
                    Text(language.name).tag(language.id)
                }
            }
            .pickerStyle(WheelPickerStyle())


            Button("Continue") {
                UserDefaults.standard.set(languageSettings.selectedLanguageCode, forKey: "selectedLanguage") // 👈 persist for ProficiencyViewModel
                onContinue()
            }
            .padding()
        }
    }
}
