import Foundation

struct CacheEntry<T: Codable>: Codable {
    let key: String
    let createdAt: Date
    let expiresAt: Date?
    let payload: T
}
