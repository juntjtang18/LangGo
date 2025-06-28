//
//  Config.swift
//  LangGo
//
//  Created by James Tang on 2025/6/27.
//

import Foundation

struct Config {
    static var strapiBaseUrl: String {
        #if DEBUG
            #if USE_LOCAL_IP
                return "http://192.168.1.66:8080" // Use your actual IP
            #else
                return "http://localhost:8080"
            #endif
        #else
            return "https://langgoens.geniusparentingai.ca"
        #endif
    }
    static let keychainService = "com.langGo.swift"
}
