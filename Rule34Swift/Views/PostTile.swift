import SwiftUI
#if canImport(UIKit)
import UIKit
import ImageIO
#endif

struct PostTile: View {
    let post: Rule34Post
    let isFavorite: Bool
    let galleryQuality: MediaQuality

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    R34RemoteImage(url: post.urlForQuality(galleryQuality), contentMode: .fill, shouldAnimate: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
        }
        .contentShape(Rectangle())
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder((post.isVideo || post.isAnimatedImage) ? .orange.opacity(0.9) : .white.opacity(0.08), lineWidth: 1)
        }
    }
}

struct R34RemoteImage: View {
    let url: URL?
    let contentMode: ContentMode
    let shouldAnimate: Bool

    @StateObject private var loader = R34ImageLoader()

    init(url: URL?, contentMode: ContentMode = .fit, shouldAnimate: Bool = true) {
        self.url = url
        self.contentMode = contentMode
        self.shouldAnimate = shouldAnimate
    }

    var body: some View {
        Group {
            switch loader.phase {
            case .idle, .loading:
                ZStack {
                    Color.gray.opacity(0.18)
                    ProgressView()
                        .tint(.orange)
                }
            case .success(let image):
                #if canImport(UIKit)
                if image.images != nil {
                    AnimatedUIImageView(image: image, contentMode: contentMode, shouldAnimate: shouldAnimate)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                }
                #else
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                #endif
            case .failed:
                ZStack {
                    Color.gray.opacity(0.18)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            await loader.load(url: url, shouldDecodeAnimation: shouldAnimate)
        }
    }
}

#if canImport(UIKit) && !os(macOS)
private struct AnimatedUIImageView: UIViewRepresentable {
    let image: UIImage
    let contentMode: ContentMode
    let shouldAnimate: Bool

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        view.contentMode = contentMode == .fill ? .scaleAspectFill : .scaleAspectFit
        view.image = image
        if shouldAnimate {
            view.startAnimating()
        }
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.contentMode = contentMode == .fill ? .scaleAspectFill : .scaleAspectFit
        uiView.image = image
        if image.images != nil && shouldAnimate {
            uiView.startAnimating()
        } else {
            uiView.stopAnimating()
        }
    }
}
#endif

final class R34ImageLoader: ObservableObject {
    enum Phase {
        case idle
        case loading
        #if canImport(UIKit)
        case success(UIImage)
        #else
        case success(NSImage)
        #endif
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    #if canImport(UIKit)
    private static let cache = NSCache<NSURL, UIImage>()
    #else
    private static let cache = NSCache<NSURL, NSImage>()
    #endif

    static func clearMemoryCache() {
        cache.removeAllObjects()
    }

    func load(url: URL?, shouldDecodeAnimation: Bool = true) async {
        guard let url else {
            await MainActor.run { self.phase = .failed }
            return
        }

        if let cached = Self.cache.object(forKey: url as NSURL) {
            await MainActor.run { self.phase = .success(cached) }
            return
        }

        if let disk = await ImageCacheStore.shared.cachedImage(for: url) {
            Self.cache.setObject(disk, forKey: url as NSURL)
            await MainActor.run { self.phase = .success(disk) }
            return
        }

        await MainActor.run { self.phase = .loading }
        let request = Rule34APIClient.mediaRequest(for: url)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                await MainActor.run { self.phase = .failed }
                return
            }
            let isGIF = (http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("image/gif") == true) || url.path.lowercased().hasSuffix(".gif")
            let image = await Task.detached(priority: .userInitiated) {
                #if canImport(UIKit) && !os(macOS)
                return (isGIF && shouldDecodeAnimation) ? (Self.decodeGIF(data: data) as? UIImage) : UIImage(data: data)
                #else
                return (Self.decodeGIF(data: data) as? NSImage) ?? NSImage(data: data)
                #endif
            }.value
            guard let image else {
                await MainActor.run { self.phase = .failed }
                return
            }
            Self.cache.setObject(image, forKey: url as NSURL)
            await ImageCacheStore.shared.store(data, for: url)
            await MainActor.run { self.phase = .success(image) }
        } catch {
            await MainActor.run { self.phase = .failed }
        }
    }

    private static func decodeGIF(data: Data) -> Any? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: true]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else {
            #if canImport(UIKit) && !os(macOS)
            return UIImage(data: data)
            #else
            return NSImage(data: data)
            #endif
        }

        var images: [Any] = []
        images.reserveCapacity(count)
        var total: Double = 0

        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, options as CFDictionary) else { continue }
            let frameDuration = gifFrameDuration(source: source, index: i)
            total += frameDuration
            #if canImport(UIKit) && !os(macOS)
            images.append(UIImage(cgImage: cg))
            #else
            images.append(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
            #endif
        }

        if images.isEmpty { return nil }
        if total <= 0 { total = Double(images.count) * 0.1 }
        #if canImport(UIKit) && !os(macOS)
        return UIImage.animatedImage(with: images as! [UIImage], duration: total)
        #else
        return images.first as? NSImage
        #endif
    }

    private static func gifFrameDuration(source: CGImageSource, index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }
        if let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, unclamped > 0 {
            return max(unclamped, 0.02)
        }
        if let delay = gif[kCGImagePropertyGIFDelayTime] as? Double, delay > 0 {
            return max(delay, 0.02)
        }
        return 0.1
    }
}
