import Photos
import SwiftUI

private enum BulkMediaFilter: String, CaseIterable, Identifiable {
    case images = "Images"
    case videos = "Videos"
    case both = "Images and videos"

    var id: String { rawValue }
    var displayName: String { NSLocalizedString(rawValue, comment: "Bulk download media filter") }
}

private struct PhotoAlbum: Identifiable {
    let id: String
    let title: String
}

@MainActor
private final class BulkDownloadModel: ObservableObject {
    @Published var tags = ""
    @Published var mediaFilter: BulkMediaFilter = .both
    @Published var quality: MediaQuality = .high
    @Published var limit = 30
    @Published var useDateRange = false
    @Published var startDate = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @Published var endDate = Date.now
    @Published var albums: [PhotoAlbum] = [PhotoAlbum(id: "library", title: "Recents")]
    @Published var selectedAlbumID = "library"
    @Published private(set) var isRunning = false
    @Published private(set) var isPaused = false
    @Published private(set) var completed = 0
    @Published private(set) var failed = 0
    @Published private(set) var total = 0
    @Published var message: String?

    private let api = Rule34APIClient()
    private var task: Task<Void, Never>?
    private var isCancellationRequested = false

    func refreshAlbums() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let granted: PHAuthorizationStatus
        if status == .notDetermined {
            granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        } else {
            granted = status
        }
        guard granted == .authorized || granted == .limited else {
            message = NSLocalizedString("Photo library access is required to choose an album.", comment: "Bulk download error")
            return
        }

        var loaded = [PhotoAlbum(id: "library", title: "Recents")]
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        collections.enumerateObjects { collection, _, _ in
            loaded.append(PhotoAlbum(id: collection.localIdentifier, title: collection.localizedTitle ?? "Album"))
        }
        albums = loaded.sorted { $0.id == "library" || $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func start(settings: AppSettings) {
        guard !isRunning else { return }
        guard !tags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = NSLocalizedString("Enter at least one tag.", comment: "Bulk download error")
            return
        }
        completed = 0
        failed = 0
        total = 0
        message = nil
        isCancellationRequested = false
        isRunning = true
        isPaused = false
        let request = Request(tags: tags, filter: mediaFilter, quality: quality, limit: limit, useDateRange: useDateRange, startDate: startDate, endDate: endDate, albumID: selectedAlbumID)
        task = Task { [weak self] in
            await self?.run(request: request, settings: settings)
        }
    }

    func togglePause() { isPaused.toggle() }

    func cancel() {
        isCancellationRequested = true
        task?.cancel()
        task = nil
        isRunning = false
        isPaused = false
        message = NSLocalizedString("Download cancelled.", comment: "Bulk download status")
    }

    private func run(request: Request, settings: AppSettings) async {
        defer {
            isRunning = false
            isPaused = false
            task = nil
        }

        do {
            let posts = try await findPosts(request: request, settings: settings)
            guard !shouldStop else { return }
            total = posts.count
            guard !posts.isEmpty else {
                message = NSLocalizedString("No posts matched these filters.", comment: "Bulk download status")
                return
            }

            for post in posts {
                while isPaused && !shouldStop {
                    try await Task.sleep(for: .milliseconds(300))
                }
                guard !shouldStop else { return }
                do {
                    try await download(post: post, request: request)
                    guard !shouldStop else { return }
                    completed += 1
                } catch is CancellationError {
                    return
                } catch {
                    guard !shouldStop else { return }
                    failed += 1
                }
            }
            message = shouldStop
                ? NSLocalizedString("Download cancelled.", comment: "Bulk download status")
                : String(format: NSLocalizedString("Finished: %lld saved, %lld failed.", comment: "Bulk download status"), completed, failed)
        } catch {
            message = error.localizedDescription
        }
    }

    private func findPosts(request: Request, settings: AppSettings) async throws -> [Rule34Post] {
        var results: [Rule34Post] = []
        var page = 0
        while results.count < request.limit && page < 20 && !shouldStop {
            let searchResult = try await api.searchBooru(
                tags: request.tags,
                page: page,
                blacklist: settings.blacklist,
                hideAI: settings.hideAI
            )
            let pagePosts = searchResult.posts
            guard !pagePosts.isEmpty else { break }
            var index = 0
            while index < pagePosts.count && results.count < request.limit {
                guard !shouldStop else { return results }
                let batchEnd = min(index + 4, pagePosts.count)
                let batch = Array(pagePosts[index..<batchEnd])
                let resolvedBatch = await withTaskGroup(of: (Int, Rule34Post?).self) { group in
                    for (offset, post) in batch.enumerated() {
                        group.addTask { [api] in
                            (offset, try? await api.fetchBooruPost(id: post.id))
                        }
                    }

                    var resolved = Array<Rule34Post?>(repeating: nil, count: batch.count)
                    for await (offset, post) in group {
                        resolved[offset] = post
                    }
                    return resolved
                }

                guard !shouldStop else { return results }
                for post in resolvedBatch.compactMap({ $0 }) where results.count < request.limit {
                    if request.matches(post) {
                        results.append(post)
                    }
                }

                index = batchEnd
                try await Task.sleep(for: .milliseconds(60))
            }
            page += 1
        }
        return Array(results.prefix(request.limit))
    }

    private func download(post: Rule34Post, request: Request) async throws {
        try Task.checkCancellation()
        guard let url = post.urlForQuality(request.quality) else { throw Rule34APIError.badResponse }
        let (fileURL, response) = try await URLSession.shared.download(for: Rule34APIClient.mediaRequest(for: url))
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw Rule34APIError.badResponse }
        guard !isCancellationRequested else { throw CancellationError() }

        // URLSession uses an extension-less temporary file. Photos relies on the
        // extension for some image/video formats, so stage it under the real one.
        let fileExtension = url.pathExtension.isEmpty ? (post.isVideo ? "mp4" : "jpg") : url.pathExtension
        let stagedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try FileManager.default.copyItem(at: fileURL, to: stagedURL)
        defer { try? FileManager.default.removeItem(at: stagedURL) }

        try await PHPhotoLibrary.shared().performChanges {
            // Add the downloaded resource itself instead of decoding it into UIImage.
            // This preserves the original pixels, format, and video stream.
            let assetRequest = PHAssetCreationRequest.forAsset()
            if post.isVideo {
                assetRequest.addResource(with: .video, fileURL: stagedURL, options: nil)
            } else {
                assetRequest.addResource(with: .photo, fileURL: stagedURL, options: nil)
            }
            guard request.albumID != "library",
                  let placeholder = assetRequest.placeholderForCreatedAsset,
                  let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [request.albumID], options: nil).firstObject,
                  let change = PHAssetCollectionChangeRequest(for: album) else { return }
            change.addAssets([placeholder] as NSArray)
        }
    }

    private var shouldStop: Bool {
        isCancellationRequested || Task.isCancelled
    }

    private struct Request {
        let tags: String
        let filter: BulkMediaFilter
        let quality: MediaQuality
        let limit: Int
        let useDateRange: Bool
        let startDate: Date
        let endDate: Date
        let albumID: String

        func matches(_ post: Rule34Post) -> Bool {
            if filter == .images && post.isVideo { return false }
            if filter == .videos && !post.isVideo { return false }
            guard useDateRange else { return true }
            guard let rawDate = post.createdAt, let date = Self.dateFormatter.date(from: rawDate) else { return false }
            let calendar = Calendar.current
            let firstDay = calendar.startOfDay(for: startDate)
            let dayAfterLast = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate
            return date >= firstDay && date < dayAfterLast
        }

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter
        }()
    }
}

struct BulkDownloadView: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var model = BulkDownloadModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Search") {
                    TextField("Tags", text: $model.tags)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Media", selection: $model.mediaFilter) {
                        ForEach(BulkMediaFilter.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Quality", selection: $model.quality) {
                        ForEach(MediaQuality.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Stepper("Posts limit: \(model.limit)", value: $model.limit, in: 1...100, step: 5)
                }

                Section("Date") {
                    Toggle("Filter by date", isOn: $model.useDateRange)
                    if model.useDateRange {
                        #if targetEnvironment(macCatalyst) || os(macOS)
                        HStack(alignment: .top, spacing: 24) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("From")
                                    .font(.headline)
                                DatePicker(
                                    "From",
                                    selection: $model.startDate,
                                    in: ...model.endDate,
                                    displayedComponents: .date
                                )
                                .labelsHidden()
                                .datePickerStyle(.graphical)
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("To")
                                    .font(.headline)
                                DatePicker(
                                    "To",
                                    selection: $model.endDate,
                                    in: model.startDate...,
                                    displayedComponents: .date
                                )
                                .labelsHidden()
                                .datePickerStyle(.graphical)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        #else
                        DatePicker("From", selection: $model.startDate, displayedComponents: .date)
                        DatePicker("To", selection: $model.endDate, in: model.startDate..., displayedComponents: .date)
                        #endif
                    }
                }

                Section("Save to Photos") {
                    Picker("Album", selection: $model.selectedAlbumID) {
                        ForEach(model.albums) { album in
                            Text(album.title).tag(album.id)
                        }
                    }
                    Button("Refresh albums") { Task { await model.refreshAlbums() } }
                }

                Section("Queue") {
                    ProgressView(value: Double(model.completed + model.failed), total: Double(max(model.total, 1)))
                    Text("Saved: \(model.completed)   Failed: \(model.failed)   Total: \(model.total)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let message = model.message { Text(message).foregroundStyle(.secondary) }

                    if model.isRunning {
                        Button(model.isPaused ? "Resume" : "Pause") { model.togglePause() }
                        Button("Cancel", role: .destructive) { model.cancel() }
                    } else {
                        Button("Start download") { model.start(settings: settings) }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                    }
                }
            }
            .navigationTitle("Downloads")
            .task { await model.refreshAlbums() }
        }
    }
}
