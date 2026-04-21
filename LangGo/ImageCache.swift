// GeniusParentingAISwift/ImageCache.swift
import SwiftUI

extension Notification.Name {
    static let imageCacheDidInvalidate = Notification.Name("ImageCacheDidInvalidate")
}

// MARK: - Image Caching System
class ImageCache {
    static let shared = NSCache<NSURL, UIImage>()
    private init() {}

    static func removeImage(for url: URL) {
        shared.removeObject(forKey: url as NSURL)
        NotificationCenter.default.post(name: .imageCacheDidInvalidate, object: url)
    }

    static func removeAllImages() {
        shared.removeAllObjects()
        NotificationCenter.default.post(name: .imageCacheDidInvalidate, object: nil)
    }
}

@MainActor
class ImageLoader: ObservableObject {
    @Published var image: UIImage?
    private var currentURL: URL?
    private var currentTask: Task<Void, Never>?

    deinit {
        currentTask?.cancel()
    }

    func load(from url: URL, forceReload: Bool = false) {
        currentTask?.cancel()
        currentURL = url

        if !forceReload, let cachedImage = ImageCache.shared.object(forKey: url as NSURL) {
            self.image = cachedImage
            return
        }

        image = nil
        let requestURL = url
        currentTask = Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: requestURL)
                guard !Task.isCancelled, let loadedImage = UIImage(data: data) else { return }
                ImageCache.shared.setObject(loadedImage, forKey: requestURL as NSURL)
                if currentURL == requestURL {
                    image = loadedImage
                }
            } catch {
                if !Task.isCancelled, currentURL == requestURL {
                    image = nil
                }
            }
        }
    }

    func handleInvalidation(for invalidatedURL: URL?, currentViewURL: URL) {
        guard invalidatedURL == nil || invalidatedURL == currentViewURL else { return }
        load(from: currentViewURL, forceReload: true)
    }
}

struct CachedAsyncImage: View {
    @StateObject private var loader = ImageLoader()
    let url: URL
    let contentMode: ContentMode

    init(url: URL, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
    }
    
    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            loader.load(from: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .imageCacheDidInvalidate)) { notification in
            loader.handleInvalidation(for: notification.object as? URL, currentViewURL: url)
        }
    }
}
