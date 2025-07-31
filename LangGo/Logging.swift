/Users/James/develop/apple/GeniusParentingAISwift/GeniusParentingAISwift/Logging.plist// Logging.swift

import Foundation
import os

// MARK: - LogLevel Enum
/// Defines the different levels of logging, similar to other logging frameworks.
/// Conforming to `Comparable` allows for easy filtering (e.g., show `info` and above).
enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    /// Creates a LogLevel from a string value (case-insensitive). This is used for parsing the .plist file.
    init?(string: String) {
        switch string.lowercased() {
        case "debug": self = .debug
        case "info": self = .info
        case "warning": self = .warning
        case "error": self = .error
        default: return nil
        }
    }

    /// Allows for comparing log levels, e.g., `level >= .info`.
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Logging Configuration Manager
/// A singleton class that reads the `Logging.plist` file and provides the configuration to the rest of the app.
class LoggingConfig {
    static let shared = LoggingConfig()

    /// The default log level to use if a specific category is not defined in the plist. Defaults to `.info`.
    private(set) var defaultLevel: LogLevel = .info
    
    /// A dictionary holding the specific log levels for each category defined in the plist.
    private(set) var levels: [String: LogLevel] = [:]

    private init() {
        // Load the configuration from Logging.plist upon initialization.
        loadConfiguration()
    }

    /// Reads the Logging.plist file from the app's main bundle and populates the configuration.
    private func loadConfiguration() {
        guard let url = Bundle.main.url(forResource: "Logging", withExtension: "plist"),
              let data = try? Data(contentsOf: url) else {
            print("⚠️ Logging.plist not found. Using default log levels.")
            return
        }

        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            print("⚠️ Could not read Logging.plist. Using default log levels.")
            return
        }

        // Parse the default level from the plist.
        if let defaultLevelString = plist["DefaultLevel"] as? String,
           let level = LogLevel(string: defaultLevelString) {
            self.defaultLevel = level
        }

        // Parse the category-specific levels from the plist.
        if let levelsDict = plist["Levels"] as? [String: String] {
            // .compactMapValues safely converts the [String: String] dict to [String: LogLevel], ignoring any invalid values.
            self.levels = levelsDict.compactMapValues { LogLevel(string: $0) }
        }
        
        print("✅ Logging configuration loaded from Logging.plist. Default level: \(self.defaultLevel).")
    }

    /// Returns the configured log level for a given category, or the default level if none is set.
    func level(for category: String) -> LogLevel {
        return levels[category] ?? defaultLevel
    }
}


// MARK: - Custom Logger Wrapper
/// A custom logger struct that wraps Apple's `os.Logger` to add level-checking functionality.
struct AppLogger {
    private let logger: os.Logger
    private let category: String

    /// Creates a new logger for a specific category.
    /// - Parameters:
    ///   - category: The name of the category (e.g., "NetworkManager", "ProfileViewModel"). This should match the keys in Logging.plist.
    ///   - subsystem: The bundle identifier of the app.
    init(category: String, subsystem: String = "com.geniusparentingai.GeniusParentingAISwift") {
        self.logger = Logger(subsystem: subsystem, category: category)
        self.category = category
    }

    /// Checks if a message at a given level should be logged based on the configuration.
    private func shouldLog(level: LogLevel) -> Bool {
        // The core logic: only log if the message's level is >= the configured level for its category.
        return level >= LoggingConfig.shared.level(for: category)
    }

    /// Logs a message at the `debug` level.
    /// The `@autoclosure` optimization prevents the string from being computed if the log level is too low.
    func debug(_ message: @autoclosure @escaping () -> String) {
        if shouldLog(level: .debug) {
            logger.debug("\(message())")
        }
    }

    /// Logs a message at the `info` level.
    func info(_ message: @autoclosure @escaping () -> String) {
        if shouldLog(level: .info) {
            logger.info("\(message())")
        }
    }

    /// Logs a message at the `warning` level.
    func warning(_ message: @autoclosure @escaping () -> String) {
        if shouldLog(level: .warning) {
            logger.warning("\(message())")
        }
    }

    /// Logs a message at the `error` level.
    func error(_ message: @autoclosure @escaping () -> String) {
        if shouldLog(level: .error) {
            logger.error("\(message())")
        }
    }
}
