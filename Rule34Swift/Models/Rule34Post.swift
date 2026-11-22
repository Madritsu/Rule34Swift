import Foundation

struct Rule34Post: Codable, Hashable, Identifiable {
    let id: String
    let fileURL: URL?
    let previewURL: URL?
    let sampleURL: URL?
    let tags: String
    let score: String?
    let width: String?
    let height: String?
    let createdAt: String?
    /// Categories parsed from the booru post page (for example, character or copyright).
    /// The API does not reliably expose this metadata without credentials.
    let tagTypes: [String: String]?
    let sourceMode: Rule34SourceMode?

    enum CodingKeys: String, CodingKey {
        case id
        case fileURL = "file_url"
        case previewURL = "preview_url"
        case sampleURL = "sample_url"
        case tags
        case score
        case width
        case height
        case createdAt = "created_at"
        case tagTypes = "tag_types"
        case sourceMode = "source_mode"
    }

    init(id: String, fileURL: URL?, previewURL: URL?, sampleURL: URL?, tags: String, score: String? = nil, width: String? = nil, height: String? = nil, createdAt: String? = nil, tagTypes: [String: String]? = nil, sourceMode: Rule34SourceMode? = nil) {
        self.id = id
        self.fileURL = fileURL
        self.previewURL = previewURL
        self.sampleURL = sampleURL
        self.tags = tags.decodingHTMLEntities()
        self.score = score
        self.width = width
        self.height = height
        self.createdAt = createdAt
        self.tagTypes = tagTypes
        self.sourceMode = sourceMode
    }

    /// Compares posts without treating missing or empty URLs as a shared identity.
    /// The booru post ID is the authoritative identity whenever both posts have one.
    func hasSameIdentity(as other: Rule34Post) -> Bool {
        let lhsID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsID = other.id.trimmingCharacters(in: .whitespacesAndNewlines)

        if !lhsID.isEmpty && !rhsID.isEmpty {
            return lhsID == rhsID
        }

        guard let lhsURL = fileURL,
              let rhsURL = other.fileURL,
              !lhsURL.absoluteString.isEmpty,
              !rhsURL.absoluteString.isEmpty else {
            return false
        }
        return lhsURL == rhsURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(forKey: .id) ?? UUID().uuidString
        fileURL = try container.decodeURL(forKey: .fileURL)
        previewURL = try container.decodeURL(forKey: .previewURL)
        sampleURL = try container.decodeURL(forKey: .sampleURL)
        let rawTags = try container.decodeFlexibleString(forKey: .tags) ?? ""
        tags = rawTags.decodingHTMLEntities()
        score = try container.decodeFlexibleString(forKey: .score)
        width = try container.decodeFlexibleString(forKey: .width)
        height = try container.decodeFlexibleString(forKey: .height)
        createdAt = try container.decodeFlexibleString(forKey: .createdAt)
        tagTypes = try? container.decodeIfPresent([String: String].self, forKey: .tagTypes)
        sourceMode = try? container.decodeIfPresent(Rule34SourceMode.self, forKey: .sourceMode)
    }

    var thumbnailURL: URL? {
        previewURL ?? sampleURL ?? fileURL
    }

    var mediumPreviewURL: URL? {
        sampleURL ?? previewURL ?? fileURL
    }

    var displayURL: URL? {
        fileURL ?? sampleURL ?? previewURL
    }

    /// Booru search cards use placeholder filenames to retain video/GIF classification.
    /// Favorites need the detail-page URL before they can be exported or opened at full quality.
    var needsBooruMediaResolution: Bool {
        guard sourceMode == .booru else { return false }
        guard let fileURL else { return true }
        let name = fileURL.lastPathComponent.lowercased()
        return name == "video.mp4" || name == "animated.gif"
    }

    func urlForQuality(_ quality: MediaQuality) -> URL? {
        let usableFileURL = needsBooruMediaResolution ? nil : fileURL
        switch quality {
        case .low:
            return previewURL ?? sampleURL ?? usableFileURL
        case .medium:
            return sampleURL ?? previewURL ?? usableFileURL
        case .high:
            return usableFileURL ?? sampleURL ?? previewURL
        }
    }

    var mediaKind: String {
        if isVideo { return NSLocalizedString("Video", comment: "Media type") }
        if isAnimatedImage { return "GIF" }
        return NSLocalizedString("Image", comment: "Media type")
    }

    var pixelSizeText: String {
        guard let width, let height, !width.isEmpty, !height.isEmpty else {
            return NSLocalizedString("Unknown", comment: "Unknown value")
        }
        return "\(width)x\(height)"
    }

    var tagList: [String] {
        tags.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    var isVideo: Bool {
        let url = fileURL ?? sampleURL ?? previewURL
        guard let path = url?.path.lowercased() else { return false }
        return path.hasSuffix(".mp4") || path.hasSuffix(".webm")
    }

    var isAnimatedImage: Bool {
        let url = fileURL ?? sampleURL ?? previewURL
        return url?.path.lowercased().hasSuffix(".gif") == true
    }
}

private extension KeyedDecodingContainer {
    func decodeURL(forKey key: Key) throws -> URL? {
        guard let value = try decodeFlexibleString(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return URL(string: value)
    }

    func decodeFlexibleString(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}
