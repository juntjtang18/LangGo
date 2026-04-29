import CryptoKit
import Foundation

final class DiskCacheStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func data(for key: String) throws -> Data? {
        guard let url = cacheURL(for: key), fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    func write(_ data: Data, for key: String) throws {
        guard let url = cacheURL(for: key) else { return }
        try data.write(to: url)
    }

    func removeData(for key: String) throws {
        guard let url = cacheURL(for: key), fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    private func cacheURL(for key: String) -> URL? {
        let fileName = "\(hashedFileName(for: key)).json"
        return fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName)
    }

    private func hashedFileName(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
