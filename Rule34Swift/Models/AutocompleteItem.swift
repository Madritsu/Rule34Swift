import Foundation

struct AutocompleteItem: Codable, Identifiable, Hashable {
    let value: String
    let label: String?
    let type: String?

    var id: String { value }

    enum CodingKeys: String, CodingKey {
        case value
        case label
        case type
    }

    init(value: String, label: String? = nil, type: String? = nil) {
        self.value = value.decodingHTMLEntities()
        self.label = label?.decodingHTMLEntities()
        self.type = type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawValue = try container.decode(String.self, forKey: .value)
        let rawLabel = try container.decodeIfPresent(String.self, forKey: .label)

        self.value = rawValue.decodingHTMLEntities()
        self.label = rawLabel?.decodingHTMLEntities()
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
    }
}
