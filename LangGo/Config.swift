//
//  Config.swift
//  LangGo
//
//  Created by James Tang on 2025/6/27.
//

import Foundation

struct Config {
    static var strapiBaseUrl: String {
        if let environmentOverride = ProcessInfo.processInfo.environment["STRAPI_BASE_URL"],
           !environmentOverride.isEmpty {
            return environmentOverride
        }

        #if DEBUG
            #if targetEnvironment(simulator)
                return "http://localhost:1338"
            #elseif USE_LOCAL_IP
                return "http://192.168.1.72:1338" // Use your actual LAN IP on a physical device.
            #else
                return "http://localhost:1338"
            #endif
        #else
            return "https://langgo-en-strapi.geniusparentingai.ca"
        #endif
    }
    static let keychainService = "com.langGo.swift"
    
    // Define the target language for learning based on Xcode Build Settings (Preprocessor Macros)
    static let learningTargetLanguageCode: String = {
        #if LEARNING_ENGLISH
            return "en"
        #elseif LEARNING_FRENCH
            return "fr"
        #else
            // Default fallback if no specific learning language macro is defined
            return "en"
        #endif
    }()
}
