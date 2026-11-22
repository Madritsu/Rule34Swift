import Foundation
import Combine

@MainActor
final class GalleryViewModel: ObservableObject {
    enum Mode {
        case search
        case favorites
    }

    @Published var query = ""
    @Published private(set) var posts: [Rule34Post] = []
    @Published private(set) var favorites: [Rule34Post] = []
    @Published private(set) var suggestions: [AutocompleteItem] = []
    @Published private(set) var page = 0
    @Published private(set) var total = 0
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var ageVerificationDetected = false
    @Published private(set) var captchaDetected = false
    @Published private(set) var captchaHTML: String?

    let mode: Mode
    private let api = Rule34APIClient()
    private let favoritesStore = FavoritesStore()
    private let settings: AppSettings
    private var suggestionsTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var activeSearchID = UUID()
    private var favoriteEnrichmentTasks = Set<String>()

    init(settings: AppSettings, mode: Mode) {
        self.settings = settings
        self.mode = mode
        reloadFavorites()
    }

    var title: String {
        NSLocalizedString(mode == .favorites ? "Favorites" : "Search", comment: "Gallery title")
    }

    var visiblePosts: [Rule34Post] {
        mode == .favorites ? favorites : posts
    }

    var canGoBack: Bool {
        page > 0 && mode == .search
    }

    var canGoForward: Bool {
        guard mode == .search, !posts.isEmpty else { return false }
        switch settings.searchSourceMode {
        case .api:
            return posts.count >= 51
        case .booru:
            return posts.count >= 40
        }
    }

    func load() async {
        if mode == .favorites {
            reloadFavorites()
            await syncFavoritesMetadata()
            return
        }

        let requestID = UUID()
        activeSearchID = requestID
        isLoading = true
        errorMessage = nil
        ageVerificationDetected = false
        captchaDetected = false
        captchaHTML = nil
        defer {
            if activeSearchID == requestID { isLoading = false }
        }

        do {
            let result: Rule34SearchResult
            switch settings.searchSourceMode {
            case .api:
                result = try await api.search(
                    tags: query,
                    page: page,
                    userID: settings.userID,
                    apiKey: settings.apiKey,
                    blacklist: settings.blacklist,
                    hideAI: settings.hideAI
                )
            case .booru:
                result = try await api.searchBooru(
                    tags: query,
                    page: page,
                    blacklist: settings.blacklist,
                    hideAI: settings.hideAI
                )
            }
            guard activeSearchID == requestID, !Task.isCancelled else { return }
            posts = result.posts
            total = result.total
        } catch {
            guard activeSearchID == requestID, !Task.isCancelled else { return }
            posts = []
            total = 0
            errorMessage = error.localizedDescription
            if case Rule34APIError.ageVerification = error {
                ageVerificationDetected = true
            }
            if case let Rule34APIError.captcha(html) = error {
                captchaDetected = true
                captchaHTML = html
            }
        }
    }

    func search() {
        page = 0
        searchTask?.cancel()
        searchTask = Task { await load() }
    }

    func movePage(_ delta: Int) {
        guard mode == .search else { return }
        page = max(0, page + delta)
        searchTask?.cancel()
        searchTask = Task { await load() }
    }

    func resolvedPostForViewing(_ post: Rule34Post) async -> Rule34Post {
        do {
            switch settings.searchSourceMode {
            case .api:
                if post.fileURL == nil,
                   settings.hasCredentials,
                   let resolved = try await api.fetchPost(id: post.id, userID: settings.userID, apiKey: settings.apiKey) {
                    return resolved
                }
            case .booru:
                if post.fileURL == nil,
                   let resolved = try await api.fetchBooruPost(id: post.id) {
                    return resolved
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        return post
    }

    func updateSuggestions() {
        guard query.last?.isWhitespace != true else {
            suggestions = []
            suggestionsTask?.cancel()
            return
        }

        let lastWord = query.split(separator: " ").last.map(String.init) ?? ""
        let clean = lastWord.trimmingCharacters(in: CharacterSet(charactersIn: "#-*()~, "))
        guard clean.count >= 2 else {
            suggestions = []
            suggestionsTask?.cancel()
            return
        }

        suggestionsTask?.cancel()
        let request = clean
        suggestionsTask = Task {
            let results = (try? await api.autocomplete(query: request)) ?? []
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.query.last?.isWhitespace != true else { return }
                let current = self.query.split(separator: " ").last.map(String.init) ?? ""
                let currentClean = current.trimmingCharacters(in: CharacterSet(charactersIn: "#-*()~, "))
                guard request == currentClean else { return }
                self.suggestions = results
            }
        }
    }

    func applySuggestion(_ item: AutocompleteItem) {
        guard let tokenRange = query.range(of: #"\S+$"#, options: .regularExpression) else {
            query = item.value + " "
            suggestions = []
            return
        }

        let token = String(query[tokenRange])
        let prefix = String(token.prefix { "-(".contains($0) || $0 == "*" })
        let suffix = String(token.reversed().prefix { "*~),".contains($0) }.reversed())
        query.replaceSubrange(tokenRange, with: prefix + item.value + suffix + " ")
        suggestions = []
    }

    func isFavorite(_ post: Rule34Post) -> Bool {
        favorites.contains(where: { $0.hasSameIdentity(as: post) })
    }

    func toggleFavorite(_ post: Rule34Post) {
        if let index = favorites.firstIndex(where: { $0.hasSameIdentity(as: post) }) {
            favorites.remove(at: index)
        } else {
            // Save post with current source mode
            let postWithSource = Rule34Post(
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
                sourceMode: post.sourceMode ?? settings.searchSourceMode
            )
            favorites.insert(postWithSource, at: 0)
            resolveFavoriteMediaIfNeeded(postWithSource)
        }
        favoritesStore.save(favorites)
        if mode == .favorites {
            posts = favorites
        }
    }

    func reloadFavorites() {
        favorites = favoritesStore.load()
        favorites.forEach(resolveFavoriteMediaIfNeeded)
        if mode == .favorites {
            posts = favorites
            total = favorites.count
        }
    }

    func refreshFavorites() {
        guard mode == .favorites, !isLoading else { return }
        Task { await refreshSavedFavorites() }
    }

    private func refreshSavedFavorites() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var refreshed = favorites
        for index in refreshed.indices {
            let saved = refreshed[index]
            do {
                let latest: Rule34Post?
                switch saved.sourceMode ?? settings.searchSourceMode {
                case .booru:
                    latest = try await api.fetchBooruPost(id: saved.id)
                case .api:
                    guard settings.hasCredentials else { continue }
                    latest = try await api.fetchPost(id: saved.id, userID: settings.userID, apiKey: settings.apiKey)
                }
                guard let latest else { continue }
                refreshed[index] = Rule34Post(
                    id: saved.id,
                    fileURL: latest.fileURL ?? saved.fileURL,
                    previewURL: latest.previewURL ?? saved.previewURL,
                    sampleURL: latest.sampleURL ?? saved.sampleURL,
                    tags: latest.tags.isEmpty ? saved.tags : latest.tags,
                    score: latest.score ?? saved.score,
                    width: latest.width ?? saved.width,
                    height: latest.height ?? saved.height,
                    createdAt: latest.createdAt ?? saved.createdAt,
                    tagTypes: latest.tagTypes ?? saved.tagTypes,
                    sourceMode: saved.sourceMode ?? settings.searchSourceMode
                )
            } catch {
                // Retain the saved snapshot when a post cannot be refreshed.
            }
        }

        favorites = refreshed
        posts = refreshed
        total = refreshed.count
        favoritesStore.save(refreshed)
    }

    private func syncFavoritesMetadata() async {
        let result = await favoritesStore.syncFavorites(userID: settings.userID, apiKey: settings.apiKey)
        if result.updated > 0 {
            reloadFavorites()
        }
    }

    private func resolveFavoriteMediaIfNeeded(_ post: Rule34Post) {
        guard (post.previewURL == nil || post.needsBooruMediaResolution),
              !post.id.isEmpty,
              favoriteEnrichmentTasks.insert(post.id).inserted else { return }

        Task { [weak self] in
            guard let self else { return }
            defer { favoriteEnrichmentTasks.remove(post.id) }
            do {
                let details: Rule34Post?
                switch post.sourceMode ?? settings.searchSourceMode {
                case .booru:
                    details = try await api.fetchBooruPost(id: post.id)
                case .api:
                    guard settings.hasCredentials else { return }
                    details = try await api.fetchPost(id: post.id, userID: settings.userID, apiKey: settings.apiKey)
                }
                guard let details,
                      let index = favorites.firstIndex(where: { $0.id == post.id }) else { return }
                let current = favorites[index]
                let enriched = Rule34Post(
                    id: current.id,
                    fileURL: details.fileURL ?? current.fileURL,
                    previewURL: current.previewURL ?? details.previewURL,
                    sampleURL: details.sampleURL ?? current.sampleURL,
                    tags: details.tags.isEmpty ? current.tags : details.tags,
                    score: details.score ?? current.score,
                    width: details.width ?? current.width,
                    height: details.height ?? current.height,
                    createdAt: details.createdAt ?? current.createdAt,
                    tagTypes: details.tagTypes ?? current.tagTypes,
                    sourceMode: .booru
                )
                favorites[index] = enriched
                favoritesStore.save(favorites)
                if mode == .favorites { posts = favorites }
            } catch {
                // Keep the preview favorite; a later reload can retry enrichment.
            }
        }
    }
}
