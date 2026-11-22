import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import Photos

struct PostDetailView: View {
    let post: Rule34Post
    let isFavorite: Bool
    let fullViewQuality: MediaQuality
    let sourceMode: Rule34SourceMode
    let onSearchTag: (String) -> Void
    let onToggleFavorite: (Rule34Post) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var favoriteState: Bool
    @State private var showsInfo = false
    @State private var enrichedPost: Rule34Post?
    @State private var isLoadingDetails = false
    @State private var isDownloading = false
    @State private var showDownloadAlert = false
    @State private var downloadMessage = ""
    @State private var isObscured = false

    @EnvironmentObject var settings: AppSettings

    private let apiClient = Rule34APIClient()

    init(post: Rule34Post, isFavorite: Bool, fullViewQuality: MediaQuality, sourceMode: Rule34SourceMode = .api, onSearchTag: @escaping (String) -> Void, onToggleFavorite: @escaping (Rule34Post) -> Void) {
        self.post = post
        self.isFavorite = isFavorite
        self.fullViewQuality = fullViewQuality
        self.sourceMode = sourceMode
        self.onSearchTag = onSearchTag
        self.onToggleFavorite = onToggleFavorite
        _favoriteState = State(initialValue: isFavorite)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoadingDetails {
                ProgressView()
                    .tint(.orange)
            } else {
                mediaView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !currentPost.isVideo {
                    VStack {
                        overlayBar
                            .padding(.horizontal, 14)
                            .zIndex(1000)
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                } else {
                    VStack {
                        Spacer()
                    }
                }
            }
        }
        .sheet(isPresented: $showsInfo) {
            PostInfoView(post: currentPost, sourceMode: sourceMode, onSearchTag: onSearchTag)
                .environmentObject(settings)
                #if !os(macOS)
                .presentationDetents([.large])
                #endif
        }
        .alert("Download", isPresented: $showDownloadAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloadMessage)
        }
        .task {
            await loadPostDetails()
        }
        .onChange(of: post.id) { _ in
            // SwiftUI keeps @State alive when the sheet content is reused for another post.
            // Always derive the heart from the newly selected post.
            favoriteState = isFavorite
        }
        .onChange(of: isFavorite) { newValue in
            favoriteState = newValue
        }
        .overlay {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("Hidden")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .allowsHitTesting(false)
                .opacity(settings.privacyBlurEnabled && isObscured ? 1 : 0)
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                withAnimation(.easeOut(duration: 0.25)) {
                    isObscured = false
                }
            } else if newPhase == .inactive || newPhase == .background {
                withAnimation(.easeIn(duration: 0.2)) {
                isObscured = true
                }
            }
        }
    }

    private var currentPost: Rule34Post {
        enrichedPost ?? post
    }

    private func loadPostDetails() async {
        guard sourceMode == .booru, enrichedPost == nil else { return }
        // Search-result entries use a placeholder URL for video detection.
        // Always resolve the post page before creating a player so it receives the real media URL.
        isLoadingDetails = true
        defer { isLoadingDetails = false }

        do {
            if let fullPost = try await apiClient.fetchBooruPost(id: post.id) {
                enrichedPost = fullPost
            }
        } catch {
        }
    }

    @ViewBuilder
    private var mediaView: some View {
        if currentPost.isVideo, let url = currentPost.fileURL {
            R34VideoPlayerView(
                url: url,
                topLeading: AnyView(EmptyView()),
                topTrailing: AnyView(overlayBar)
            )
            .id(url)
        } else if let url = currentPost.urlForQuality(fullViewQuality) {
            R34ZoomableImage(url: url)
        } else {
            R34EmptyStateView(title: "No media URL", systemImage: "link.badge.plus")
        }
    }

    private func downloadMedia() async {
        guard !isDownloading else { return }

        guard let url = currentPost.urlForQuality(fullViewQuality) else {
            downloadMessage = NSLocalizedString("No media URL available", comment: "Download error")
            showDownloadAlert = true
            return
        }

        isDownloading = true
        defer { isDownloading = false }

        do {
            let (downloadURL, _) = try await URLSession.shared.download(for: Rule34APIClient.mediaRequest(for: url))
            let localURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension.isEmpty ? "mp4" : url.pathExtension)
            try FileManager.default.copyItem(at: downloadURL, to: localURL)

            #if os(macOS)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = url.lastPathComponent
            panel.begin { response in
                guard response == .OK, let fileURL = panel.url else {
                    try? FileManager.default.removeItem(at: localURL)
                    return
                }
                try? FileManager.default.removeItem(at: fileURL)
                do {
                    try FileManager.default.moveItem(at: localURL, to: fileURL)
                } catch {
                    try? FileManager.default.removeItem(at: localURL)
                }
                DispatchQueue.main.async {
                    downloadMessage = NSLocalizedString("Saved to disk", comment: "Download status")
                    showDownloadAlert = true
                }
            }
            #else
            defer { try? FileManager.default.removeItem(at: localURL) }
            let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            if status == .notDetermined {
                let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard newStatus == .authorized || newStatus == .limited else {
                    downloadMessage = NSLocalizedString("Photo library access denied", comment: "Download error")
                    showDownloadAlert = true
                    return
                }
            } else if status != .authorized && status != .limited {
                downloadMessage = NSLocalizedString("Photo library access denied", comment: "Download error")
                showDownloadAlert = true
                return
            }

            if currentPost.isVideo {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: localURL)
                }
                await MainActor.run {
                    downloadMessage = NSLocalizedString("Video saved to Photos", comment: "Download status")
                    showDownloadAlert = true
                }
            } else {
                let data = try Data(contentsOf: localURL)
                guard let image = UIImage(data: data) else {
                    downloadMessage = NSLocalizedString("Failed to process image", comment: "Download error")
                    showDownloadAlert = true
                    return
                }
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                await MainActor.run {
                    downloadMessage = NSLocalizedString("Image saved to Photos", comment: "Download status")
                    showDownloadAlert = true
                }
            }
            #endif
        } catch {
            downloadMessage = String(format: NSLocalizedString("Download failed: %@", comment: "Download error"), error.localizedDescription)
            showDownloadAlert = true
        }
    }

    private var overlayBar: some View {
        HStack(spacing: 10) {
            overlayTapButton(system: "safari", active: false) {
                openURL(rule34PostURL)
            }

            overlayTapButton(system: "info.circle", active: showsInfo) {
                showsInfo.toggle()
            }

            overlayTapButton(system: isDownloading ? "arrow.down.circle.fill" : "arrow.down.circle", active: isDownloading) {
                Task {
                    await downloadMedia()
                }
            }

            overlayTapButton(system: favoriteState ? "heart.fill" : "heart", active: favoriteState) {
                favoriteState.toggle()
                onToggleFavorite(post)
            }

            Spacer()

            overlayTapButton(system: "xmark", active: false) {
                dismiss()
            }
        }
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.001))
        .contentShape(Rectangle())
    }

    private func overlayTapButton(system: String, active: Bool, action: @escaping () -> Void) -> some View {
        Image(systemName: system)
            .r34OverlayButton(active: active)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    private var rule34PostURL: URL {
        var components = URLComponents(string: "https://rule34.xxx/index.php")!
        components.queryItems = [
            URLQueryItem(name: "page", value: "post"),
            URLQueryItem(name: "s", value: "view"),
            URLQueryItem(name: "id", value: currentPost.id)
        ]
        return components.url!
    }
}

private struct R34ZoomableImage: View {
    let url: URL

    @StateObject private var loader = R34ImageLoader()

    var body: some View {
        Group {
            switch loader.phase {
            case .idle, .loading:
                ProgressView()
                    .tint(.orange)
            case .success(let image):
                #if canImport(UIKit) && !os(macOS)
                ZoomableScrollImage(image: image)
                #else
                if let nsImage = image as? NSImage {
                    ZoomableNSImage(image: nsImage)
                }
                #endif
            case .failed:
                R34EmptyStateView(title: "Media failed to load", systemImage: "photo.badge.exclamationmark")
            }
        }
        .padding(.horizontal, 8)
        .task(id: url) {
            await loader.load(url: url)
        }
    }
}

#if canImport(UIKit) && !os(macOS)
private struct ZoomableScrollImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 5.0
        scrollView.minimumZoomScale = 1.0
        scrollView.zoomScale = 1.0
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        if image.images != nil {
            imageView.startAnimating()
        }

        scrollView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            let next: CGFloat = scrollView.zoomScale > 1.01 ? 1.0 : 2.0
            scrollView.setZoomScale(next, animated: true)
        }
    }
}
#elseif os(macOS)
private struct ZoomableNSImage: View {
    let image: NSImage

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = lastScale * value
                        }
                        .onEnded { value in
                            lastScale = scale
                            if scale < 1.0 {
                                withAnimation {
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { value in
                            lastOffset = offset
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation {
                        if scale > 1.01 {
                            scale = 1.0
                            lastScale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2.5
                            lastScale = 2.5
                        }
                    }
                }
        }
    }
}
#endif

private extension View {
    func r34OverlayButton(active: Bool = false) -> some View {
        self
            .font(.title3.weight(.semibold))
            .foregroundStyle(active ? .orange : .white)
            .frame(width: 44, height: 44)
            .r34Glass(cornerRadius: 22, interactive: true)
    }
}
