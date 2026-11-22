import Foundation
import WebKit

@MainActor
final class Rule34AccountService: ObservableObject {
    @Published var username: String?
    @Published var favorites: [Rule34Post] = []
    @Published var uploads: [Rule34Post] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasActiveSession = false

    private let api = Rule34APIClient()
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: config)
        username = UserDefaults.standard.string(forKey: "rule34.accountUsername")
    }

    var isLoggedIn: Bool {
        hasActiveSession
    }

    func adoptCookies(from webView: WKWebView) async {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = await getCookies(from: store)
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    func markAuthenticated(username: String? = nil) {
        hasActiveSession = true
        if let username = username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty {
            self.username = username
            UserDefaults.standard.set(username, forKey: "rule34.accountUsername")
        } else if let stored = UserDefaults.standard.string(forKey: "rule34.accountUsername")?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty, self.username == nil {
            self.username = stored
        }
    }

    func detectUsername(from html: String) -> String? {
        let patterns = [
            #"page=account&s=profile&uname=([^"'<>&\s]+)"#,
            #"page=account&s=profile&uname=([^"']+)"#,
            #"My Profile.*?uname=([^"'<>&\s]+)"#
        ]

        for pattern in patterns {
            if let match = html.firstCapture(of: pattern), !match.isEmpty {
                return match.decodingHTMLEntities()
            }
        }
        return nil
    }

    func refreshSession(username fallbackUsername: String? = nil) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let knownUsername = (fallbackUsername ?? username ?? UserDefaults.standard.string(forKey: "rule34.accountUsername") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !knownUsername.isEmpty {
            username = knownUsername
            UserDefaults.standard.set(knownUsername, forKey: "rule34.accountUsername")
        }

        do {
            favorites = try await loadFavorites()
            if knownUsername.isEmpty {
                uploads = []
            } else {
                uploads = try await loadUploads(username: knownUsername)
            }
            hasActiveSession = true
            if knownUsername.isEmpty {
                errorMessage = "Signed in, but username was not detected yet."
            } else {
                errorMessage = nil
            }
        } catch {
            favorites = []
            uploads = []
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        username = nil
        favorites = []
        uploads = []
        errorMessage = nil
        hasActiveSession = false
        UserDefaults.standard.removeObject(forKey: "rule34.accountUsername")
    }

    private func loadFavorites() async throws -> [Rule34Post] {
        let html = try await html(from: URL(string: "https://rule34.xxx/index.php?page=favorites&s=list")!)
        return parsePostPreviews(from: html, baseURL: URL(string: "https://rule34.xxx")!)
    }

    private func loadUploads(username: String) async throws -> [Rule34Post] {
        return try await api.searchPublic(tags: "user:\(username)", page: 0)
    }

    private func html(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("https://rule34.xxx/", forHTTPHeaderField: "Referer")
        request.setValue("Rule34Swift/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func parsePostPreviews(from html: String, baseURL: URL) -> [Rule34Post] {
        let pattern = #"<a[^>]+href=["'][^"']*page=post&s=view&id=(\d+)[^"']*["'][^>]*>.*?<img[^>]+src=["']([^"']+)["']"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex?.matches(in: html, options: [], range: range) ?? []

        return matches.compactMap { match in
            guard match.numberOfRanges >= 3,
                  let idRange = Range(match.range(at: 1), in: html),
                  let srcRange = Range(match.range(at: 2), in: html) else { return nil }
            let id = String(html[idRange])
            let src = String(html[srcRange]).decodingHTMLEntities()
            let previewURL = URL(string: src, relativeTo: baseURL)?.absoluteURL ?? URL(string: src)
            return Rule34Post(id: id, fileURL: nil, previewURL: previewURL, sampleURL: previewURL, tags: "")
        }
    }

    private func getCookies(from store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
}
