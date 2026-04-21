import Foundation

final class CacheIndexStore {
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "com.langGo.swift.CacheIndexStore.queue")
    private let fileName = "cache_tag_index.json"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func replaceTags(for key: String, with tags: [CacheTagValue]) {
        queue.sync {
            var index = loadIndex()

            for existingTag in index.keys {
                index[existingTag]?.removeAll { $0 == key }
                if index[existingTag]?.isEmpty == true {
                    index.removeValue(forKey: existingTag)
                }
            }

            for tag in Set(tags) {
                var keys = index[tag.rawValue] ?? []
                if !keys.contains(key) {
                    keys.append(key)
                }
                index[tag.rawValue] = keys
            }

            persist(index)
        }
    }

    func removeKey(_ key: String) {
        queue.sync {
            var index = loadIndex()
            var needsPersist = false

            for existingTag in index.keys {
                let originalCount = index[existingTag]?.count ?? 0
                index[existingTag]?.removeAll { $0 == key }
                if index[existingTag]?.isEmpty == true {
                    index.removeValue(forKey: existingTag)
                }
                if (index[existingTag]?.count ?? 0) != originalCount {
                    needsPersist = true
                }
            }

            if needsPersist {
                persist(index)
            }
        }
    }

    func keys(for tag: CacheTagValue) -> [String] {
        queue.sync {
            loadIndex()[tag.rawValue] ?? []
        }
    }

    private func loadIndex() -> [String: [String]] {
        guard let url = indexURL(), fileManager.fileExists(atPath: url.path) else {
            return [:]
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: [String]].self, from: data)
        } catch {
            return [:]
        }
    }

    private func persist(_ index: [String: [String]]) {
        guard let url = indexURL() else { return }
        do {
            let data = try JSONEncoder().encode(index)
            try data.write(to: url)
        } catch {
        }
    }

    private func indexURL() -> URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName)
    }
}
