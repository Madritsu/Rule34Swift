import Foundation

final class FavoritesStore {
    struct Snapshot: Codable {
        var items: [Rule34Post]
    }

    struct LegacySnapshot: Codable {
        var items: [LegacyFavorite]
    }

    struct LegacyFavorite: Codable {
        var id: String?
        var file_url: String?
        var preview_url: String?
        var sample_url: String?
        var tags: String?
        var score: String?
        var width: String?
        var height: String?

        func toPost() -> Rule34Post? {
            let idValue = (id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let file = URL(string: file_url ?? "")
            let preview = URL(string: preview_url ?? "")
            let sample = URL(string: sample_url ?? "")
            let tagsValue = tags ?? ""
            if idValue.isEmpty && file == nil { return nil }
            return Rule34Post(
                id: idValue.isEmpty ? (file?.absoluteString ?? UUID().uuidString) : idValue,
                fileURL: file,
                previewURL: preview,
                sampleURL: sample,
                tags: tagsValue,
                score: score,
                width: width,
                height: height,
                sourceMode: .api  // Legacy favorites were saved through API
            )
        }
    }

    enum ImportError: LocalizedError {
        case fileNotReadable
        case unreadableFile

        var errorDescription: String? {
            switch self {
            case .fileNotReadable:
                return "The selected file could not be read."
            case .unreadableFile:
                return "favorites.json could not be read."
            }
        }
    }

    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("Rule34Swift", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("favorites.json")
    }

    func load() -> [Rule34Post] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }

        if let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            let validPosts = snapshot.items.filter { isValidPost($0) }
            return migrateSourceMode(validPosts)
        }
        if let items = try? JSONDecoder().decode([Rule34Post].self, from: data) {
            let validPosts = items.filter { isValidPost($0) }
            return migrateSourceMode(validPosts)
        }
        if let legacy = try? JSONDecoder().decode(LegacySnapshot.self, from: data) {
            let posts = legacy.items.compactMap { $0.toPost() }.filter { isValidPost($0) }
            save(posts)
            return posts
        }
        if let legacyItems = try? JSONDecoder().decode([LegacyFavorite].self, from: data) {
            let posts = legacyItems.compactMap { $0.toPost() }.filter { isValidPost($0) }
            save(posts)
            return posts
        }

        return []
    }

    private func migrateSourceMode(_ posts: [Rule34Post]) -> [Rule34Post] {
        var needsMigration = false
        let migrated = posts.map { post -> Rule34Post in
            if post.sourceMode == nil {
                needsMigration = true
                return Rule34Post(
                    id: post.id,
                    fileURL: post.fileURL,
                    previewURL: post.previewURL,
                    sampleURL: post.sampleURL,
                    tags: post.tags,
                    score: post.score,
                    width: post.width,
                    height: post.height,
                    createdAt: post.createdAt,
                    tagTypes: post.tagTypes,
                    sourceMode: .api  // Old favorites without sourceMode are from API
                )
            }
            return post
        }

        if needsMigration {
            save(migrated)  // Save migrated posts back to file
        }

        return migrated
    }

    private func isValidPost(_ post: Rule34Post) -> Bool {
        // Validate that post has at least an ID or a valid URL
        return !post.id.isEmpty || post.fileURL != nil || post.previewURL != nil
    }

    func save(_ items: [Rule34Post]) {
        let snapshot = Snapshot(items: items)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
        NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
    }

    func importFavorites(from data: Data) throws -> Int {
        let imported = try decodeFavorites(from: data)
        guard !imported.isEmpty else { throw ImportError.unreadableFile }

        var existing = load()
        let existingKeys = Set(existing.map(favoriteKey))
        let newItems = imported.filter { !existingKeys.contains(favoriteKey($0)) }
        if !newItems.isEmpty {
            // Keep existing items, just prepend new unique ones.
            existing.insert(contentsOf: newItems, at: 0)
            save(existing)
        } else {
            // Still notify so UI can refresh message/state.
            NotificationCenter.default.post(name: .favoritesDidChange, object: nil)
        }
        return newItems.count
    }

    private func decodeFavorites(from data: Data) throws -> [Rule34Post] {
        if let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            return snapshot.items
        }
        if let items = try? JSONDecoder().decode([Rule34Post].self, from: data) {
            return items
        }
        if let legacy = try? JSONDecoder().decode(LegacySnapshot.self, from: data) {
            return legacy.items.compactMap { $0.toPost() }
        }
        if let legacyItems = try? JSONDecoder().decode([LegacyFavorite].self, from: data) {
            return legacyItems.compactMap { $0.toPost() }
        }
        throw ImportError.unreadableFile
    }

    private func favoriteKey(_ post: Rule34Post) -> String {
        post.id.isEmpty ? (post.fileURL?.absoluteString ?? "") : post.id
    }

    func exportFavoritesData() -> Data {
        let snapshot = Snapshot(items: load())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(snapshot)) ?? Data("{\"items\":[]}".utf8)
    }

    func syncFavorites(userID: String, apiKey: String) async -> (updated: Int, failed: Int) {
        let api = Rule34APIClient()
        var items = load()
        var updatedCount = 0
        var failedCount = 0

        for (index, post) in items.enumerated() {
            guard !post.id.isEmpty else { continue }

            do {
                if let freshPost = try await api.fetchPost(id: post.id, userID: userID, apiKey: apiKey) {
                    let needsUpdate = post.score != freshPost.score ||
                                     post.width != freshPost.width ||
                                     post.height != freshPost.height

                    if needsUpdate {
                        items[index] = Rule34Post(
                            id: post.id,
                            fileURL: post.fileURL,
                            previewURL: post.previewURL,
                            sampleURL: post.sampleURL,
                            tags: post.tags,
                            score: freshPost.score,
                            width: freshPost.width,
                            height: freshPost.height,
                            createdAt: post.createdAt,
                            tagTypes: post.tagTypes,
                            sourceMode: post.sourceMode
                        )
                        updatedCount += 1
                    }
                }
            } catch {
                failedCount += 1
            }
        }

        if updatedCount > 0 {
            save(items)
        }

        return (updatedCount, failedCount)
    }
}

extension Notification.Name {
    static let favoritesDidChange = Notification.Name("Rule34Swift.favoritesDidChange")
}
