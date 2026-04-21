import Foundation

final class MemoryCacheStore {
    private let cache = NSCache<NSString, NSData>()

    func data(for key: String) -> Data? {
        cache.object(forKey: key as NSString) as Data?
    }

    func setData(_ data: Data, for key: String) {
        cache.setObject(data as NSData, forKey: key as NSString)
    }

    func removeData(for key: String) {
        cache.removeObject(forKey: key as NSString)
    }
}
