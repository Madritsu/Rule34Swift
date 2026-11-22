import Foundation

actor Rule34TagMetadataStore {
    static let shared = Rule34TagMetadataStore()

    private let api = Rule34APIClient()
    private var cache: [String: Rule34TagInfo] = [:]

    func info(for tag: String) async -> Rule34TagInfo? {
        let key = normalize(tag)
        guard !key.isEmpty else { return nil }

        if let cached = cache[key] {
            return cached
        }

        do {
            let suggestions = try await api.autocomplete(query: key)
            let match = suggestions.first { normalize($0.value) == key } ?? suggestions.first
            guard let match else { return nil }

            let info = Rule34TagInfo(
                id: normalize(match.value),
                name: match.value,
                count: nil,
                type: match.type
            )
            cache[key] = info
            return info
        } catch {
            return nil
        }
    }

    func warm(tags: [String]) async -> [Rule34TagInfo] {
        var results: [Rule34TagInfo] = []
        results.reserveCapacity(tags.count)

        await withTaskGroup(of: Rule34TagInfo?.self) { group in
            for tag in tags {
                group.addTask {
                    await self.info(for: tag)
                }
            }

            for await item in group {
                if let item {
                    results.append(item)
                }
            }
        }

        return results
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
