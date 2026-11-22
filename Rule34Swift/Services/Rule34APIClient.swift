import Foundation
import Darwin
import WebKit

struct Rule34SearchResult {
    let posts: [Rule34Post]
    let total: Int
}

enum Rule34APIError: LocalizedError {
    case missingCredentials
    case badResponse
    case ageVerification
    case captcha(String)
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return NSLocalizedString("Add user ID and API key in Settings first.", comment: "API error")
        case .badResponse:
            return NSLocalizedString("The API returned an unexpected response.", comment: "API error")
        case .ageVerification:
            return NSLocalizedString("Rule34 requires age verification in this region.", comment: "Age verification error")
        case .captcha:
            return NSLocalizedString("Rule34 requires CAPTCHA verification.", comment: "CAPTCHA error")
        case .invalidPayload(let preview):
            return String(format: NSLocalizedString("The API response could not be read. Preview: %@", comment: "API error"), preview)
        }
    }
}

final class Rule34APIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Builds a request for media hosts that require the same headers as the API.
    /// Keeping this in one place prevents the player and downloads from behaving differently.
    static func mediaRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("https://rule34.xxx/", forHTTPHeaderField: "Referer")
        let userAgent = Rule34CaptchaCookieStore.userAgent ?? "Rule34Swift/1.0"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .useProtocolCachePolicy
        return request
    }

    func search(tags rawTags: String, page: Int, userID: String, apiKey: String, blacklist: String, hideAI: Bool) async throws -> Rule34SearchResult {
        let cleanUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanUserID.isEmpty, !cleanAPIKey.isEmpty else {
            throw Rule34APIError.missingCredentials
        }

        let tags = normalizedTags(rawTags, blacklist: blacklist, hideAI: hideAI)
        async let posts = fetchPosts(tags: tags, page: page, userID: cleanUserID, apiKey: cleanAPIKey)
        async let total = fetchTotal(tags: tags, userID: cleanUserID, apiKey: cleanAPIKey)
        let loadedPosts = try await posts
        let loadedTotal = (try? await total) ?? loadedPosts.count
        return Rule34SearchResult(posts: loadedPosts, total: max(loadedTotal, loadedPosts.count))
    }

    func searchPublic(tags rawTags: String, page: Int) async throws -> [Rule34Post] {
        let tags = normalizeTagQuery(rawTags)
        return try await fetchPosts(tags: tags, page: page, userID: nil, apiKey: nil)
    }

    func searchBooru(tags rawTags: String, page: Int, blacklist: String, hideAI: Bool) async throws -> Rule34SearchResult {
        // The website applies its AI filter through the `filter_ai` cookie,
        // not through a `-ai_generated` search tag. Keep the query unchanged
        // and mirror the website behavior in the booru request itself.
        var tags = normalizeBooruTagQuery(rawTags)
        let blocked = blacklist
            .split { $0.isWhitespace || $0 == "," }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#- ")) }
            .filter { !$0.isEmpty }
        for tag in blocked { tags += " -\(tag)" }
        tags = tags.trimmingCharacters(in: .whitespacesAndNewlines)
        let posts = try await fetchBooruPosts(tags: tags, page: page, hideAI: hideAI)
        return Rule34SearchResult(posts: posts, total: posts.count)
    }

    func fetchBooruPost(id: String) async throws -> Rule34Post? {
        let html = try await booruPostHTML(id: id)
        let post = parseBooruPostDetail(from: html, id: id, baseURL: URL(string: "https://rule34.xxx")!)
        return post
    }

    func fetchBooruComments(postID: String) async throws -> [Rule34Comment] {
        let html = try await booruPostHTML(id: postID)
        return parseBooruComments(from: html, postID: postID)
    }

    func autocomplete(query: String) async throws -> [AutocompleteItem] {
        guard query.count >= 2 else { return [] }
        var components = URLComponents(string: "https://api.rule34.xxx/autocomplete.php")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        let data = try await data(from: components.url!)
        return (try? JSONDecoder().decode([AutocompleteItem].self, from: data)) ?? []
    }

    func fetchPost(id: String, userID: String, apiKey: String) async throws -> Rule34Post? {
        let cleanUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanUserID.isEmpty, !cleanAPIKey.isEmpty else {
            throw Rule34APIError.missingCredentials
        }

        let posts = try await fetchPosts(tags: "id:\(id)", page: 0, userID: cleanUserID, apiKey: cleanAPIKey)
        return posts.first
    }

    func fetchPostsForDownload(tags: String, page: Int, userID: String, apiKey: String) async throws -> [Rule34Post] {
        let cleanUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUserID.isEmpty, !cleanAPIKey.isEmpty else {
            throw Rule34APIError.missingCredentials
        }
        return try await fetchPosts(tags: normalizeTagQuery(tags), page: page, userID: cleanUserID, apiKey: cleanAPIKey)
    }

    func fetchComments(postID: String, userID: String? = nil, apiKey: String? = nil) async throws -> [Rule34Comment] {
        var components = URLComponents(string: "https://api.rule34.xxx/index.php")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "dapi"),
            URLQueryItem(name: "s", value: "comment"),
            URLQueryItem(name: "q", value: "index"),
            URLQueryItem(name: "post_id", value: postID)
        ]

        if let userID, !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "user_id", value: userID))
            items.append(URLQueryItem(name: "api_key", value: apiKey))
        }

        components.queryItems = items

        let data = try await data(from: components.url!)
        if let comments = parseXMLComments(from: data) {
            return comments
        }
        if let comments = try? JSONDecoder().decode([Rule34CommentJSON].self, from: data) {
            return comments.map { $0.toComment() }
        }
        return []
    }

    func fetchTagInfo(name: String) async throws -> Rule34TagInfo? {
        for parameter in ["name", "tags"] {
            var components = URLComponents(string: "https://api.rule34.xxx/index.php")!
            components.queryItems = [
                URLQueryItem(name: "page", value: "dapi"),
                URLQueryItem(name: "s", value: "tag"),
                URLQueryItem(name: "q", value: "index"),
                URLQueryItem(name: parameter, value: name)
            ]

            let data = try await data(from: components.url!)
            if let item = try? JSONDecoder().decode(Rule34TagInfo.self, from: data) {
                return item
            }
            if let items = try? JSONDecoder().decode([Rule34TagInfo].self, from: data), let item = items.first {
                return item
            }
            if let wrapped = try? JSONDecoder().decode(WrappedTagInfo.self, from: data), let item = wrapped.items.first {
                return item
            }
            if let item = parseXMLTag(from: data) {
                return item
            }
        }
        return nil
    }

    private func fetchPosts(tags: String, page: Int, userID: String?, apiKey: String?) async throws -> [Rule34Post] {
        var components = URLComponents(string: "https://api.rule34.xxx/index.php")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "dapi"),
            URLQueryItem(name: "s", value: "post"),
            URLQueryItem(name: "q", value: "index"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "tags", value: tags),
            URLQueryItem(name: "pid", value: String(max(0, page))),
            URLQueryItem(name: "limit", value: "51")
        ]

        if let userID, !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "user_id", value: userID))
            items.append(URLQueryItem(name: "api_key", value: apiKey))
        }

        components.queryItems = items

        let data = try await data(from: components.url!)
        if let posts = try? JSONDecoder().decode([Rule34Post].self, from: data) {
            parserLog("DAPI JSON array parsed posts=\(posts.count)")
            return posts
        }
        if let wrapped = try? JSONDecoder().decode(WrappedPosts.self, from: data) {
            parserLog("DAPI wrapped JSON parsed posts=\(wrapped.items.count)")
            return wrapped.items
        }
        if let posts = parseXMLPosts(from: data), !posts.isEmpty {
            parserLog("DAPI XML fallback parsed posts=\(posts.count)")
            return posts
        }
        if isEmptyJSON(data) {
            parserLog("DAPI response parsed as empty result")
            return []
        }
        parserLog("DAPI parser failed; response prefix: \(textPrefix(data))")
        throw Rule34APIError.invalidPayload(payloadPreview(from: data))
    }

    private func fetchBooruPosts(tags: String, page: Int, hideAI: Bool) async throws -> [Rule34Post] {
        var components = URLComponents(string: "https://rule34.xxx/index.php")!
        components.queryItems = [
            URLQueryItem(name: "page", value: "post"),
            URLQueryItem(name: "s", value: "list"),
            URLQueryItem(name: "tags", value: tags),
            URLQueryItem(name: "pid", value: String(max(0, page * 42)))
        ]

        let data = try await data(
            from: components.url!,
            cookie: "filter_ai=\(hideAI ? "1" : "0")"
        )
        guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            return []
        }

        let posts = parseBooruPosts(from: html, baseURL: URL(string: "https://rule34.xxx")!)
        parserLog("Booru HTML parser found posts=\(posts.count)")
        if !posts.isEmpty {
            return posts
        }

        if html.lowercased().contains("no results") || html.lowercased().contains("no posts") {
            return []
        }

        throw Rule34APIError.invalidPayload(payloadPreview(from: data))
    }

    private func booruPostHTML(id: String) async throws -> String {
        var components = URLComponents(string: "https://rule34.xxx/index.php")!
        components.queryItems = [
            URLQueryItem(name: "page", value: "post"),
            URLQueryItem(name: "s", value: "view"),
            URLQueryItem(name: "id", value: id)
        ]
        let data = try await data(from: components.url!)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func fetchTotal(tags: String, userID: String, apiKey: String) async throws -> Int {
        var components = URLComponents(string: "https://api.rule34.xxx/index.php")!
        components.queryItems = [
            URLQueryItem(name: "page", value: "dapi"),
            URLQueryItem(name: "s", value: "post"),
            URLQueryItem(name: "q", value: "index"),
            URLQueryItem(name: "tags", value: tags),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "user_id", value: userID),
            URLQueryItem(name: "api_key", value: apiKey)
        ]

        let data = try await data(from: components.url!)
        guard let xml = String(data: data, encoding: .utf8) else { return 0 }
        return parseCount(from: xml)
    }

    private func data(from url: URL, cookie: String? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("https://rule34.xxx/", forHTTPHeaderField: "Referer")
        let userAgent = Rule34CaptchaCookieStore.userAgent ?? "Rule34Swift/1.0"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let savedCookies = Rule34CaptchaCookieStore.header(for: url)
        let cookieHeader = [savedCookies, cookie].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "; ")
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        if url.host == "rule34.xxx" {
            parserLog("Booru session cookiesSent=\(!cookieHeader.isEmpty) cookieNames=\(Rule34CaptchaCookieStore.cookieNames) userAgent=\(userAgent == "Rule34Swift/1.0" ? "default" : "webView")")
        }

        for attempt in 0...1 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw Rule34APIError.badResponse
                }
                parserLog("HTTP \(request.httpMethod ?? "GET") \(redactedURL(url)) status=\(http.statusCode) bytes=\(data.count) type=\(http.value(forHTTPHeaderField: "Content-Type") ?? "unknown") prefix=\(textPrefix(data))")
                if url.host == "rule34.xxx", isAgeVerificationPage(data) {
                    throw Rule34APIError.ageVerification
                }
                if url.host == "rule34.xxx", isCaptchaPage(data) {
                    parserLog("CAPTCHA page detected; opening interactive verification")
                    throw Rule34APIError.captcha(String(data: data, encoding: .utf8) ?? "")
                }
                if 200..<300 ~= http.statusCode {
                    return data
                }
                let isTemporaryStatus = http.statusCode == 403 || http.statusCode == 408 || http.statusCode == 425 || http.statusCode == 429 || http.statusCode >= 500
                if attempt == 0 && isTemporaryStatus {
                    try await Task.sleep(nanoseconds: 450_000_000)
                    continue
                }
                throw Rule34APIError.badResponse
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError {
                let temporaryCodes: Set<URLError.Code> = [
                    .timedOut, .cannotFindHost, .cannotConnectToHost,
                    .networkConnectionLost, .dnsLookupFailed, .notConnectedToInternet
                ]
                guard attempt == 0, temporaryCodes.contains(error.code) else { throw error }
                try await Task.sleep(nanoseconds: 450_000_000)
            }
        }
        throw Rule34APIError.badResponse
    }

    private func isAgeVerificationPage(_ data: Data) -> Bool {
        guard let html = String(data: data, encoding: .utf8)?.lowercased() else { return false }
        return html.contains("age verification") || html.contains("age-verification") ||
            html.contains("verify your age") || html.contains("age check required")
    }

    private func isCaptchaPage(_ data: Data) -> Bool {
        guard let html = String(data: data, encoding: .utf8)?.lowercased() else { return false }
        let title = html.firstCapture(of: #"<title[^>]*>([\s\S]*?)</title>"#)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.contains("captcha") || html.contains("class=\"captcha-box\"") ||
            html.contains("class='captcha-box'") || html.contains("id=\"challenge-form\"") ||
            html.contains("id='challenge-form'") || html.contains("cf-chl-")
    }

    private func parserLog(_ message: String) {
        guard ProcessInfo.processInfo.environment["RULE34_DEBUG_LOGS"] == "1",
              isatty(STDOUT_FILENO) == 1 else { return }
        print("[Rule34Swift][Parser] \(message)")
    }

    private func redactedURL(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.host ?? "unknown" }
        parts.queryItems = parts.queryItems?.map { item in
            ["api_key", "user_id"].contains(item.name.lowercased())
                ? URLQueryItem(name: item.name, value: "REDACTED")
                : item
        }
        return parts.string ?? url.host ?? "unknown"
    }

    private func textPrefix(_ data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) else { return "<non-UTF8 body>" }
        let compact = text.prefix(500).replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "\\r", with: " ")
        return String(compact).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    }

    private func normalizedTags(_ value: String, blacklist: String, hideAI: Bool) -> String {
        var tags = normalizeTagQuery(value)
        let blocked = blacklist
            .split { $0.isWhitespace || $0 == "," }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#- ")) }
            .filter { !$0.isEmpty }

        for tag in blocked {
            tags.append(" -\(tag)")
        }
        if hideAI {
            tags.append(" -ai_generated")
        }
        return tags.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeTagQuery(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Preserve Rule34.xxx operators (wildcards, exclusions, fuzzy tags and
    /// parenthesized OR groups) while trimming only optional hashtag prefixes.
    private func normalizeBooruTagQuery(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func parseCount(from xml: String) -> Int {
        guard let range = xml.range(of: #"count=['"](\d+)['"]"#, options: .regularExpression) else { return 0 }
        let match = String(xml[range])
        let digits = match.filter(\.isNumber)
        return Int(digits) ?? 0
    }

    private func isEmptyJSON(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return text == "[]" || text == "{}" || text.isEmpty
    }

    private func payloadPreview(from data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? "<binary data>"
        return String(text.prefix(180))
    }

    private func parseXMLPosts(from data: Data) -> [Rule34Post]? {
        let parser = XMLParser(data: data)
        let delegate = Rule34XMLPostParser()
        parser.delegate = delegate
        return parser.parse() ? delegate.posts : nil
    }

    private func parseXMLComments(from data: Data) -> [Rule34Comment]? {
        let parser = XMLParser(data: data)
        let delegate = Rule34XMLCommentParser()
        parser.delegate = delegate
        return parser.parse() ? delegate.comments : nil
    }

    private func parseXMLTag(from data: Data) -> Rule34TagInfo? {
        let parser = XMLParser(data: data)
        let delegate = Rule34XMLTagParser()
        parser.delegate = delegate
        return parser.parse() ? delegate.tag : nil
    }

    private func parseBooruPosts(from html: String, baseURL: URL) -> [Rule34Post] {
        // Pattern to capture entire thumb span block to check for video/gif indicators
        let pattern = #"<span[^>]*class=["'][^"']*thumb[^"']*["'][^>]*>([\s\S]*?)</span>"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex?.matches(in: html, options: [], range: range) ?? []

        return matches.compactMap { match in
            guard match.numberOfRanges >= 2,
                  let blockRange = Range(match.range(at: 1), in: html) else {
                return nil
            }

            let block = String(html[blockRange])

            // Extract ID
            guard let idMatch = block.firstCapture(of: #"page=post&s=view&id=(\d+)"#) else {
                return nil
            }

            // Extract image src
            guard let src = block.firstCapture(of: #"<img[^>]+(?:src|data-src)=["']([^"']+)["']"#) else {
                return nil
            }

            let previewURL = URL(string: src.decodingHTMLEntities(), relativeTo: baseURL)?.absoluteURL ?? URL(string: src.decodingHTMLEntities())

            // Detect media type from thumbnail indicators
            var fileURL: URL? = nil
            if block.contains("Video") || block.contains("video") || block.contains("mp4") || block.contains("webm") {
                // Mark as video by creating a fake .mp4 URL that will trigger isVideo
                fileURL = URL(string: "video.mp4", relativeTo: previewURL)
            } else if block.contains("GIF") || block.contains("gif") || block.contains("animated") {
                // Mark as GIF
                fileURL = URL(string: "animated.gif", relativeTo: previewURL)
            }

            return Rule34Post(id: idMatch, fileURL: fileURL, previewURL: previewURL, sampleURL: previewURL, tags: "", sourceMode: .booru)
        }
    }

    private func parseBooruPostDetail(from html: String, id: String, baseURL: URL) -> Rule34Post? {
        // The displayed #image is frequently a sample. Keep the original link
        // separate and prefer it for `.high` downloads.
        let originalURL = firstURL(
            in: html,
            baseURL: baseURL,
            patterns: [
                #"<a[^>]+href=["']([^"']+)["'][^>]*>\s*Original\s+(?:image|video)\s*</a>"#,
                #"<a[^>]+href=["']([^"']+)["'][^>]*>\s*Download\s*</a>"#
            ]
        )

        let displayedMediaURL = firstURL(
            in: html,
            baseURL: baseURL,
            patterns: [
                #"<source[^>]+src=["']([^"']+)["']"#,
                #"<video[^>]+src=["']([^"']+)["']"#,
                #"<img[^>]+id=["']image["'][^>]+src=["']([^"']+)["']"#
            ]
        )

        let previewURL = firstURL(
            in: html,
            baseURL: baseURL,
            patterns: [
                #"<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']"#,
                #"<img[^>]+id=["']image["'][^>]+src=["']([^"']+)["']"#
            ]
        )

        let tagTypes = parseBooruTagTypes(from: html)
        let tags = parseBooruTags(from: html).joined(separator: " ")
        let createdAt = html.firstCapture(of: #"Posted:\s*(?:</[^>]+>\s*)*([0-9]{4}-[0-9]{2}-[0-9]{2}\s+[0-9:]{8})"#)
            ?? html.firstCapture(of: #"([0-9]{4}-[0-9]{2}-[0-9]{2}\s+[0-9:]{8})"#)

        // Try multiple patterns for score - improved to match actual HTML structure
        let score = html.firstCapture(of: #"<span\s+id=["']psc\d+["']>([+-]?\d+)</span>"#)
            ?? html.firstCapture(of: #"Score:\s*</b>\s*([+-]?\d+)"#)
            ?? html.firstCapture(of: #"Score:\s*([+-]?\d+)"#)
            ?? html.firstCapture(of: #"<b>Score:</b>\s*([+-]?\d+)"#)
            ?? html.firstCapture(of: #"score["']?\s*[:=]\s*["']?([+-]?\d+)"#)

        // Try multiple patterns for size - more comprehensive
        var width: String?
        var height: String?

        // Pattern 1: "Size: 1920x1080" or "Size: </b> 1920x1080"
        if let sizeMatch = html.firstCapture(of: #"Size:\s*(?:</b>\s*)?(\d+)\s*x\s*(\d+)"#) {
            let parts = sizeMatch.split(separator: "x")
            if parts.count == 2 {
                width = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                height = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Pattern 2: Look for image dimensions in stats section
        if width == nil || height == nil {
            if let dimMatch = html.firstCapture(of: #"(?:width|dimensions?).*?(\d{3,5})\s*[x×]\s*(\d{3,5})"#) {
                let parts = dimMatch.split(whereSeparator: { $0 == "x" || $0 == "×" })
                if parts.count == 2 {
                    width = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                    height = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        // Pattern 3: meta tag dimensions
        if width == nil || height == nil {
            if let metaWidth = html.firstCapture(of: #"<meta[^>]+(?:property|name)=["'](?:og:image:width|width)["'][^>]+content=["'](\d+)["']"#),
               let metaHeight = html.firstCapture(of: #"<meta[^>]+(?:property|name)=["'](?:og:image:height|height)["'][^>]+content=["'](\d+)["']"#) {
                width = metaWidth
                height = metaHeight
            }
        }

        let fileURL = originalURL ?? displayedMediaURL ?? previewURL
        guard fileURL != nil || previewURL != nil || !tags.isEmpty else { return nil }
        return Rule34Post(
            id: id,
            fileURL: fileURL,
            previewURL: previewURL,
            sampleURL: displayedMediaURL ?? previewURL,
            tags: tags,
            score: score,
            width: width,
            height: height,
            createdAt: createdAt,
            tagTypes: tagTypes,
            sourceMode: .booru
        )
    }

    /// Reads category directly from tag-sidebar classes such as `tag-type-character`.
    /// This keeps the post information screen useful when the public API is unavailable.
    private func parseBooruTagTypes(from html: String) -> [String: String] {
        let pattern = #"<li[^>]+class=["'][^"']*tag-type-([a-z_]+)[^"']*["'][^>]*>[\s\S]*?<a[^>]*>[^<]*</a>[\s\S]*?<a[^>]+href=["'][^"']*tags=([^"'&]+)[^"']*["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [:]
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var result: [String: String] = [:]

        for match in regex.matches(in: html, options: [], range: range) {
            guard match.numberOfRanges >= 3,
                  let typeRange = Range(match.range(at: 1), in: html),
                  let tagRange = Range(match.range(at: 2), in: html) else {
                continue
            }

            let tag = String(html[tagRange])
                .replacingOccurrences(of: "+", with: " ")
                .removingPercentEncoding?
                .decodingHTMLEntities()
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let type = String(html[typeRange]).lowercased()

            if !tag.isEmpty {
                result[tag] = type
            }
        }

        return result
    }

    private func parseBooruTags(from html: String) -> [String] {
        var seen = Set<String>()
        var tags: [String] = []

        // Pattern 1: Tags in sidebar <li class="tag-type-{TYPE} tag">
        // HTML structure: <li class="tag-type-X tag"><a>?</a><a href="...tags=TAG">TAG_TEXT</a></li>
        // We need the SECOND <a> tag (the first one is the "?" wiki link)
        let sidebarPattern = #"<li[^>]+class=["'][^"']*tag-type-[^"']*["'][^>]*>[\s\S]*?<a[^>]*>[^<]*</a>[\s\S]*?<a[^>]+href=["'][^"']*tags=([^"'&]+)["'][^>]*>([^<]+)</a>"#
        if let regex1 = try? NSRegularExpression(pattern: sidebarPattern, options: [.caseInsensitive]) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            let matches = regex1.matches(in: html, options: [], range: range)

            for match in matches {
                if match.numberOfRanges >= 3,
                   let tagRange = Range(match.range(at: 1), in: html) {
                    let encodedTag = String(html[tagRange]).replacingOccurrences(of: "+", with: " ")
                    let tag = (encodedTag.removingPercentEncoding ?? encodedTag)
                        .decodingHTMLEntities()
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if !tag.isEmpty && !seen.contains(tag) {
                        seen.insert(tag)
                        tags.append(tag)
                    }
                }
            }
        }

        // Pattern 2: Tags from textarea in edit form - ALWAYS try this as additional source
        if let textareaContent = html.firstCapture(of: #"<textarea[^>]+id=["']tags["'][^>]*>([\s\S]*?)</textarea>"#) {
            let textareaTags = textareaContent
                .split(whereSeparator: { $0.isWhitespace })
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            for tag in textareaTags where !seen.contains(tag) {
                seen.insert(tag)
                tags.append(tag)
            }
        }

        // Pattern 3: Fallback - any tag links (only if we still have no tags)
        if tags.isEmpty {
            let pattern2 = #"href=["'][^"']*page=post&s=list&tags=([^"'&]+)[^"']*["']"#
            if let regex2 = try? NSRegularExpression(pattern: pattern2, options: [.caseInsensitive]) {
                let range = NSRange(html.startIndex..<html.endIndex, in: html)
                let matches = regex2.matches(in: html, options: [], range: range)

                for match in matches {
                    guard match.numberOfRanges >= 2,
                          let tagRange = Range(match.range(at: 1), in: html) else { continue }
                    let encoded = String(html[tagRange])
                        .replacingOccurrences(of: "+", with: " ")
                    let raw = (encoded.removingPercentEncoding ?? encoded).decodingHTMLEntities()
                    let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "_", with: " ")

                    if !tag.isEmpty && !seen.contains(tag) {
                        seen.insert(tag)
                        tags.append(tag)
                    }
                }
            }
        }

        return tags
    }

    private func parseBooruComments(from html: String, postID: String) -> [Rule34Comment] {
        // Pattern for rule34.xxx comment structure: <div id="c{ID}">...</div>
        let pattern = #"<div[^>]+id=["']c(\d+)["'][^>]*>([\s\S]*?)(?=<hr[^>]*>|<div[^>]+id=["']c\d+["']|<div[^>]+id=["']paginator["']|$)"#

        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex?.matches(in: html, options: [], range: range) ?? []

        return matches.compactMap { match in
            guard match.numberOfRanges >= 3,
                  let idRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else {
                return nil
            }

            let id = String(html[idRange])
            let bodyHTML = String(html[bodyRange])

            // Extract username from <a href="...&uname={USERNAME}">{USERNAME}</a>
            let creator = bodyHTML.firstCapture(of: #"<a[^>]+href=["'][^"']*uname=([^"'&]+)[^"']*["'][^>]*>([^<]+)</a>"#)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Current booru markup uses a `span.date`; older pages used "Posted on".
            let createdAt = (bodyHTML.firstCapture(of: #"<span[^>]+class=["'][^"']*date[^"']*["'][^>]*>\s*([0-9]{4}-[0-9]{2}-[0-9]{2}\s+[0-9:]{8})"#)
                ?? bodyHTML.firstCapture(of: #"Posted on ([0-9\-: ]+)"#))?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Current booru markup: <div class="content"><div class="body">…</div>.
            // Keep the old col2 alternative for cached/older pages.
            let body = (bodyHTML.firstCapture(of: #"<div[^>]+class=["'][^"']*body[^"']*["'][^>]*>([\s\S]*?)</div>"#)
                ?? bodyHTML.firstCapture(of: #"<div\s+class=["']col2["'][^>]*>([\s\S]*?)</div>"#)
                ?? "")
                .strippingHTML
                .replacingOccurrences(of: "&rsquo;", with: "'")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&#039;", with: "'")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !body.isEmpty else { return nil }
            return Rule34Comment(
                id: id,
                postID: postID,
                creator: creator,
                creatorID: nil,
                createdAt: createdAt,
                body: body
            )
        }
    }

    private func firstURL(in html: String, baseURL: URL, patterns: [String]) -> URL? {
        for pattern in patterns {
            guard let raw = html.firstCapture(of: pattern)?.decodingHTMLEntities(), !raw.isEmpty else { continue }
            if raw.hasPrefix("//") {
                return URL(string: "https:\(raw)")
            }
            if let url = URL(string: raw, relativeTo: baseURL)?.absoluteURL {
                return url
            }
        }
        return nil
    }
}

enum Rule34CaptchaCookieStore {
    private static let storageKey = "rule34.booru.sessionCookies"

    static var userAgent: String? {
        UserDefaults.standard.string(forKey: "rule34.booru.webViewUserAgent")
    }

    static var cookieNames: String {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let properties = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[HTTPCookiePropertyKey: Any]] else { return "none" }
        let names = properties.compactMap { $0[.name] as? String }.sorted()
        return names.isEmpty ? "none" : names.joined(separator: ",")
    }

    static func save(_ cookies: [HTTPCookie], userAgent: String?) {
        let siteCookies = cookies.filter { $0.domain.contains("rule34.xxx") }
        let properties = siteCookies.compactMap(\.properties)
        guard let data = try? PropertyListSerialization.data(fromPropertyList: properties, format: .binary, options: 0) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        if let userAgent, !userAgent.isEmpty {
            UserDefaults.standard.set(userAgent, forKey: "rule34.booru.webViewUserAgent")
        }
        if ProcessInfo.processInfo.environment["RULE34_DEBUG_LOGS"] == "1",
           isatty(STDOUT_FILENO) == 1 {
            print("[Rule34Swift][Parser] WebView session saved cookies=\(siteCookies.count) names=\(siteCookies.map(\.name).sorted().joined(separator: ",")) userAgent=\(userAgent == nil ? "missing" : "captured")")
        }
        siteCookies.forEach(HTTPCookieStorage.shared.setCookie)
    }

    static func header(for url: URL) -> String? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let properties = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[HTTPCookiePropertyKey: Any]] else { return nil }
        let cookies = properties.compactMap(HTTPCookie.init(properties:)).filter { cookie in
            cookie.domain.contains("rule34.xxx") && (cookie.expiresDate.map { $0 > Date() } ?? true)
        }
        guard !cookies.isEmpty else { return nil }
        return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
    }

    static func sync(from store: WKHTTPCookieStore, userAgent: String?, completion: @escaping () -> Void) {
        store.getAllCookies { cookies in
            save(cookies, userAgent: userAgent)
            DispatchQueue.main.async(execute: completion)
        }
    }
}

private struct WrappedPosts: Decodable {
    let posts: [Rule34Post]?
    let post: [Rule34Post]?

    var items: [Rule34Post] {
        posts ?? post ?? []
    }
}

private struct WrappedTagInfo: Decodable {
    let tags: [Rule34TagInfo]?
    let tag: [Rule34TagInfo]?

    var items: [Rule34TagInfo] {
        tags ?? tag ?? []
    }
}

private struct Rule34CommentJSON: Decodable {
    let id: String?
    let postID: String?
    let creator: String?
    let creatorID: String?
    let createdAt: String?
    let body: String?

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case creator
        case creatorID = "creator_id"
        case createdAt = "created_at"
        case body
    }

    func toComment() -> Rule34Comment {
        Rule34Comment(
            id: id ?? UUID().uuidString,
            postID: postID,
            creator: creator ?? "",
            creatorID: creatorID,
            createdAt: createdAt,
            body: body ?? ""
        )
    }
}

private final class Rule34XMLPostParser: NSObject, XMLParserDelegate {
    private(set) var posts: [Rule34Post] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "post" else { return }

        posts.append(
            Rule34Post(
                id: attributeDict["id"] ?? UUID().uuidString,
                fileURL: URL(string: attributeDict["file_url"] ?? ""),
                previewURL: URL(string: attributeDict["preview_url"] ?? ""),
                sampleURL: URL(string: attributeDict["sample_url"] ?? ""),
                tags: attributeDict["tags"] ?? "",
                score: attributeDict["score"],
                width: attributeDict["width"],
                height: attributeDict["height"],
                createdAt: attributeDict["created_at"]
            )
        )
    }
}

private final class Rule34XMLCommentParser: NSObject, XMLParserDelegate {
    private(set) var comments: [Rule34Comment] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "comment" else { return }

        comments.append(
            Rule34Comment(
                id: attributeDict["id"] ?? UUID().uuidString,
                postID: attributeDict["post_id"],
                creator: attributeDict["creator"] ?? "",
                creatorID: attributeDict["creator_id"],
                createdAt: attributeDict["created_at"],
                body: attributeDict["body"] ?? ""
            )
        )
    }
}

private final class Rule34XMLTagParser: NSObject, XMLParserDelegate {
    private(set) var tag: Rule34TagInfo?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard tag == nil else { return }
        guard elementName == "tag" else { return }

        let name = attributeDict["name"] ?? attributeDict["tag"] ?? ""
        tag = Rule34TagInfo(
            id: attributeDict["id"] ?? name,
            name: name,
            count: attributeDict["count"],
            type: attributeDict["type"]
        )
    }
}
