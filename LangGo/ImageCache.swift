// GeniusParentingAISwift/ImageCache.swift
import SwiftUI

// MARK: - Image Caching System
class ImageCache {
    static let shared = NSCache<NSURL, UIImage>()
    private init() {}
}

@MainActor
class ImageLoader: ObservableObject {
    @Published var image: UIImage?
    private let url: URL
    init(url: URL) { self.url = url }
    func load() {
        if let cachedImage = ImageCache.shared.object(forKey: url as NSURL) {
            self.image = cachedImage
            return
        }
        // Capture url locally to avoid accessing self.url in the closure
        let requestUrl = self.url
        URLSession.shared.dataTask(with: requestUrl) { data, response, error in
            guard let data = data, let loadedImage = UIImage(data: data), error == nil else { return }
            ImageCache.shared.setObject(loadedImage, forKey: requestUrl as NSURL)
            DispatchQueue.main.async {
                self.image = loadedImage
            }
        }.resume()
    }
}

struct CachedAsyncImage: View {
    @StateObject private var loader: ImageLoader
    init(url: URL) { _loader = StateObject(wrappedValue: ImageLoader(url: url)) }
    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color(UIColor.secondarySystemBackground)
            }
        }.onAppear { loader.load() }
    }
}
