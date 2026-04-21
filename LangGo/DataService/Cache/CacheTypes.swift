import Foundation

struct CacheTagValue: RawRepresentable, Hashable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

enum CacheTTLValue {
    case seconds(TimeInterval)

    var timeInterval: TimeInterval {
        switch self {
        case .seconds(let seconds):
            return seconds
        }
    }
}
