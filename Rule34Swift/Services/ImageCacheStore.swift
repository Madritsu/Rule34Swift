import CryptoKit
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

actor ImageCacheStore {
    static let shared = ImageCacheStore()

    private let fm = FileManager.default
    private let folderURL: URL

    init() {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
        folderURL = base.appendingPathComponent("Rule34Swift", isDirectory: true)
            .appendingPathComponent("ImageCache", isDirectory: true)
        try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    #if canImport(UIKit)
    func cachedImage(for url: URL) -> UIImage? {
        let path = fileURL(for: url)
        guard let data = try? Data(contentsOf: path) else { return nil }
        return UIImage(data: data)
    }
    #elseif canImport(AppKit)
    func cachedImage(for url: URL) -> NSImage? {
        let path = fileURL(for: url)
        guard let data = try? Data(contentsOf: path) else { return nil }
        return NSImage(data: data)
    }
    #endif

    func store(_ data: Data, for url: URL) {
        let path = fileURL(for: url)
        try? data.write(to: path, options: .atomic)
    }

    func cachedData(for url: URL) -> Data? {
        try? Data(contentsOf: fileURL(for: url), options: .mappedIfSafe)
    }

    func clear() {
        try? fm.removeItem(at: folderURL)
        try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        URLCache.shared.removeAllCachedResponses()
    }

    func folderSizeBytes() -> Int64 {
        guard let enumerator = fm.enumerator(at: folderURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    private func fileURL(for url: URL) -> URL {
        let key = url.absoluteString
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return folderURL.appendingPathComponent(hex).appendingPathExtension("img")
    }
}
