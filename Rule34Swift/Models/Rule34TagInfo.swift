import Foundation

struct Rule34TagInfo: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let count: String?
    let type: String?

    enum Category: String, CaseIterable {
        case search = "Search"
        case copyright = "Copyright"
        case character = "Character"
        case artist = "Artist"
        case general = "General"
        case meta = "Meta"
        case other = "Other"

        var displayName: String {
            NSLocalizedString(rawValue, comment: "Tag category")
        }
    }

    var category: Category {
        switch type?.lowercased() {
        case "search":
            return .search
        case "copyright":
            return .copyright
        case "character":
            return .character
        case "artist":
            return .artist
        case "general", "gen":
            return .general
        case "meta", "metadata":
            return .meta
        default:
            return .other
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case count
        case type
        case tag
    }

    init(id: String, name: String, count: String?, type: String?) {
        self.id = id
        self.name = name
        self.count = count
        self.type = type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawName = container.decodeFlexibleValue(forKey: .name) ?? container.decodeFlexibleValue(forKey: .tag) ?? ""
        name = rawName
        id = container.decodeFlexibleValue(forKey: .id) ?? rawName
        count = container.decodeFlexibleValue(forKey: .count)
        type = container.decodeFlexibleValue(forKey: .type)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(count, forKey: .count)
        try container.encodeIfPresent(type, forKey: .type)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleValue(forKey key: Key) -> String? {
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
