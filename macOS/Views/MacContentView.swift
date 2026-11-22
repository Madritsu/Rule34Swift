import AppKit
import AVKit
import ImageIO
import Metal
import MetalKit
import QuartzCore
import SwiftUI
import WebKit

struct MacContentView: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var gallery: GalleryViewModel
    @StateObject private var savedGallery: GalleryViewModel
    @FocusState private var searchIsFocused: Bool
    @State private var selectedSection: MacSection = .discover
    @State private var sidebarExpanded = true
    @State private var compactSearchPresented = false
    @State private var showingAgeVerificationHelp = false
    @State private var showingCaptchaWindow = false
    @State private var suppressNextCaptchaSheet = false
    @State private var previousCompactLayout: Bool?
    @State private var selectedPost: Rule34Post?
    @State private var selectedPostOrigin: CGRect?
    @State private var selectedPostThumbnailURL: URL?
    @State private var postViewerWindow: MacFullscreenViewerWindow?
    @State private var postViewerOriginFrame: NSRect?
    @StateObject private var viewerTransition = MacViewerTransitionState()
    @State private var mouseScrollMonitor: Any?

    init(settings: AppSettings) {
        self.settings = settings
        _gallery = StateObject(wrappedValue: GalleryViewModel(settings: settings, mode: .search))
        _savedGallery = StateObject(wrappedValue: GalleryViewModel(settings: settings, mode: .favorites))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.055, green: 0.065, blue: 0.095), Color(red: 0.025, green: 0.03, blue: 0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                HStack(spacing: 0) {
                    sidebar
                        .frame(width: sidebarExpanded ? 310 : 76)
                        .zIndex(2)
                    mainPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .zIndex(0)
                }
                .animation(.spring(response: 0.46, dampingFraction: 0.9), value: sidebarExpanded)
                .padding(14)
            }
            .background(Color.black)
            .background(MacWindowCornerStyle().frame(width: 0, height: 0))
            .onAppear {
                applyResponsiveSidebarLayout(width: geometry.size.width)
                installSmoothMouseScrolling()
                if gallery.posts.isEmpty { gallery.search() }
            }
            .onChange(of: geometry.size.width) { width in
                applyResponsiveSidebarLayout(width: width)
            }
            .onDisappear {
                removeSmoothMouseScrolling()
                dismissPostViewer()
            }
            .onChange(of: selectedPost) { post in
                if let post {
                    presentPostViewer(post, thumbnailURL: selectedPostThumbnailURL, origin: selectedPostOrigin)
                } else {
                    dismissPostViewer()
                }
            }
            .onChange(of: gallery.query) { _ in
                gallery.updateSuggestions()
            }
            .onChange(of: selectedSection) { section in
                gallery.errorMessage = nil
                if section == .favorites {
                    savedGallery.reloadFavorites()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .favoritesDidChange)) { _ in
                gallery.reloadFavorites()
                savedGallery.reloadFavorites()
            }
            .onChange(of: settings.searchSourceMode) { _ in
                if selectedSection == .discover { gallery.search() }
            }
            .onChange(of: settings.hideAI) { _ in
                if selectedSection == .discover { gallery.search() }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: selectedSection)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: refreshCurrentSection) {
                    Image(systemName: "arrow.clockwise")
                }
                .help(selectedSection == .favorites ? "Refresh saved posts" : "Reload results")
            }
        }
        .toolbarBackground(
            LinearGradient(
                colors: [Color(red: 0.055, green: 0.065, blue: 0.095), Color(red: 0.025, green: 0.03, blue: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            for: .windowToolbar
        )
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarColorScheme(.dark, for: .windowToolbar)
        .onChange(of: gallery.captchaDetected) { detected in
            if detected {
                if suppressNextCaptchaSheet { suppressNextCaptchaSheet = false }
                else { showingCaptchaWindow = true }
            }
        }
        .onChange(of: gallery.isLoading) { loading in
            if !loading, suppressNextCaptchaSheet { suppressNextCaptchaSheet = false }
        }
        .sheet(isPresented: $showingCaptchaWindow) {
            Rule34CaptchaWindow(html: gallery.captchaHTML ?? "") {
                suppressNextCaptchaSheet = true
                showingCaptchaWindow = false
                gallery.search()
            }
            .frame(minWidth: 700, idealWidth: 820, minHeight: 520, idealHeight: 620)
        }
    }

    private func applyResponsiveSidebarLayout(width: CGFloat) {
        let isCompact = width < 1120
        guard previousCompactLayout != isCompact else { return }
        if previousCompactLayout == nil {
            sidebarExpanded = !isCompact
        } else {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.9)) {
                sidebarExpanded = !isCompact
            }
        }
        previousCompactLayout = isCompact
    }

    private func presentPostViewer(_ post: Rule34Post, thumbnailURL: URL?, origin: CGRect?) {
        dismissPostViewer()
        guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main else { return }

        let originFrame = origin.flatMap { screenFrame(for: $0, in: NSApp.keyWindow, screen: screen) }
            ?? centeredOriginFrame(on: screen)
        postViewerOriginFrame = originFrame
        viewerTransition.progress = 0

        let window = MacFullscreenViewerWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isReleasedWhenClosed = false

        let viewer = MacPostViewer(
            post: post,
            thumbnailURL: thumbnailURL,
            originFrame: originFrame,
            screenFrame: screen.frame,
            gallery: gallery,
            transition: viewerTransition,
            onFavorite: {
                gallery.toggleFavorite(post)
                savedGallery.reloadFavorites()
            },
            settings: settings,
            onSearchTag: { tag in
                selectedPost = nil
                selectedSection = .discover
                gallery.query = tag
                gallery.search()
            },
            onClose: { selectedPost = nil }
        )
        let hostingView = NSHostingView(rootView: viewer)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        let containerView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        containerView.autoresizingMask = [.width, .height]
        hostingView.frame = containerView.bounds
        hostingView.autoresizingMask = [.width, .height]
        let dimmingView = NSView(frame: containerView.bounds)
        dimmingView.autoresizingMask = [.width, .height]
        dimmingView.wantsLayer = true
        dimmingView.layer?.backgroundColor = NSColor.black.cgColor
        dimmingView.layer?.opacity = 0
        containerView.addSubview(dimmingView)
        containerView.addSubview(hostingView)
        window.contentView = containerView
        postViewerWindow = window
        window.makeKeyAndOrderFront(nil)
        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
            viewerTransition.progress = 1
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            dimmingView.animator().alphaValue = 0.9
        }
    }

    private func dismissPostViewer() {
        guard let window = postViewerWindow else { return }
        postViewerWindow = nil
        guard postViewerOriginFrame != nil,
              let _ = window.screen ?? NSScreen.main else {
            window.orderOut(nil)
            window.close()
            return
        }
        withAnimation(.easeIn(duration: 0.28)) {
            viewerTransition.progress = 0
        }
        if let dimmingView = window.contentView?.subviews.first(where: { $0.layer?.backgroundColor != nil }) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                dimmingView.animator().alphaValue = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            window.orderOut(nil)
            window.close()
        }
        postViewerOriginFrame = nil
    }

    private func screenFrame(for frame: CGRect, in window: NSWindow?, screen: NSScreen) -> NSRect? {
        guard let window, let contentView = window.contentView else { return nil }
        let contentRect = NSRect(
            x: frame.minX,
            // GeometryProxy reports the frame in the flipped SwiftUI view space.
            // Let AppKit convert it to window coordinates instead of flipping Y here,
            // which mirrored the animation's origin vertically.
            y: frame.minY,
            width: frame.width,
            height: frame.height
        )
        return window.convertToScreen(contentView.convert(contentRect, to: nil))
    }

    private func centeredOriginFrame(on screen: NSScreen) -> NSRect {
        let size = NSSize(width: 220, height: 220)
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private var sidebar: some View {
        ZStack(alignment: .leading) {
            if sidebarExpanded {
                expandedSidebar
                    .frame(width: 310)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity.animation(.easeOut(duration: 0.16)))
                    ))
            } else {
                compactSidebar
                    .frame(width: 76)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity
                    ))
            }
        }
        .frame(maxHeight: .infinity, alignment: .leading)
    }

    private var expandedSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("RULE 34")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .tracking(1.1)
                    Text("DESKTOP EXPLORER")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.42))
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.46, dampingFraction: 0.9)) { sidebarExpanded = false }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Collapse sidebar")
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("LIBRARY")
                sidebarButton(.discover, title: "Discover", symbol: "safari")
                sidebarButton(.favorites, title: "Saved posts", symbol: "heart")
            }
            .padding(.top, 30)
            .padding(.horizontal, 12)

            sectionLabel("GLOBAL TAG SEARCH")
                .padding(.top, 32)
                .padding(.horizontal, 17)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.52))
                TextField("Search tags…", text: $gallery.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .help("Rule34 search: spaces = AND, -tag = exclude, * = wildcard, ( tag1 ~ tag2 ) = OR, tag~ = fuzzy match")
                    .focused($searchIsFocused)
                    .onSubmit(runSearch)
                if !gallery.query.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            gallery.query = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.36))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 44)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(searchIsFocused ? 0.2 : 0.075), lineWidth: 1))
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .overlay(alignment: .topLeading) {
                if shouldShowSuggestions {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 5) {
                            ForEach(gallery.suggestions.prefix(20)) { item in
                                suggestionRow(item)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(7)
                    }
                    .frame(maxHeight: 250)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.42), radius: 18, y: 8)
                    .padding(.horizontal, 14)
                    .offset(y: 52)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(20)
                }
            }
            .zIndex(5)

            Button(action: runSidebarAction) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right")
                    Text(selectedSection == .favorites ? "Refresh saved posts" : "Explore posts")
                }
                .font(.system(size: 12, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(LinearGradient(colors: [.white, .white.opacity(0.78)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [.command])
            .padding(.horizontal, 14)
            .padding(.top, 10)

            Spacer(minLength: 14)

            Text("⌘ ↵ TO SEARCH")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.30))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
        }
        .macPanelSurface(cornerRadius: 26)
        .padding(.trailing, 12)
    }

    private var compactSidebar: some View {
        VStack(spacing: 12) {
            Button {
                compactSearchPresented = false
                withAnimation(.spring(response: 0.46, dampingFraction: 0.9)) { sidebarExpanded = true }
            } label: {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Expand sidebar")
            .padding(.top, 14)

            Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(.horizontal, 8)

            compactSidebarButton(.discover, symbol: "safari", help: "Discover")
            compactSidebarButton(.favorites, symbol: "heart", help: "Saved posts")

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { compactSearchPresented.toggle() }
                selectedSection = .discover
                if compactSearchPresented {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { searchIsFocused = true }
                } else {
                    searchIsFocused = false
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(compactSearchPresented ? .white : .white.opacity(0.62))
                    .frame(width: 42, height: 42)
                    .background(compactSearchPresented ? .white.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Search tags")

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .macPanelSurface(cornerRadius: 24)
        .padding(.trailing, 12)
        .overlay(alignment: .topLeading) {
            if compactSearchPresented {
                compactSearchPopover
                    .fixedSize()
                    .offset(x: 58, y: 184)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topLeading)))
                    .zIndex(10)
            }
        }
    }

    private var compactSearchPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                TextField("Search tags…", text: $gallery.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .help("Rule34 search: spaces = AND, -tag = exclude, * = wildcard, ( tag1 ~ tag2 ) = OR, tag~ = fuzzy match")
                    .focused($searchIsFocused)
                    .onSubmit {
                        runSearch()
                        compactSearchPresented = false
                    }
                if !gallery.query.isEmpty {
                    Button {
                        gallery.query = ""
                        searchIsFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.42))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            if shouldShowSuggestions {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 5) {
                        ForEach(gallery.suggestions.prefix(20)) { item in
                            suggestionRow(item)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(5)
                }
                .frame(maxHeight: 250)
            }
        }
        .padding(9)
        .frame(width: 286, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.13), lineWidth: 1))
        .shadow(color: .black.opacity(0.48), radius: 20, y: 9)
    }

    private func compactSidebarButton(_ section: MacSection, symbol: String, help: String) -> some View {
        let active = selectedSection == section
        return Button {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) { selectedSection = section }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? .white : .white.opacity(0.58))
                .frame(width: 42, height: 42)
                .background(active ? .white.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .leading) {
                    if active { Capsule().fill(.white.opacity(0.9)).frame(width: 3, height: 20) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if section == .favorites && !savedGallery.favorites.isEmpty {
                        Circle().fill(Color.white.opacity(0.9)).frame(width: 8, height: 8).overlay(Circle().stroke(Color.black.opacity(0.7), lineWidth: 1))
                    }
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedSection == .discover ? "Explore" : "Your collection")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(selectedSection == .discover ? subtitle : "Posts you have kept for later")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }
                Spacer()
                if gallery.isLoading || (selectedSection == .favorites && savedGallery.isLoading) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 19)
            .padding(.bottom, 18)

            HStack(spacing: 8) {
                statusPill(symbol: selectedSection == .discover ? "square.grid.2x2.fill" : "heart.fill", text: "\(displayedPosts.count) POSTS", color: .white)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            Rectangle().fill(.white.opacity(0.06)).frame(height: 1)

            if gallery.ageVerificationDetected && selectedSection == .discover {
                ageVerificationNotice
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else if let error = currentError, !error.isEmpty {
                emptyState(title: "Couldn’t load posts", symbol: "wifi.exclamationmark", detail: error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if displayedPosts.isEmpty && !isCurrentSearchLoading {
                emptyState(
                    title: selectedSection == .discover ? "Nothing here yet" : "No saved posts",
                    symbol: selectedSection == .discover ? "sparkle.magnifyingglass" : "heart",
                    detail: selectedSection == .discover ? "Search for a tag from the panel on the left." : "Save posts from the gallery and they will appear here."
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 15)], spacing: 15) {
                        ForEach(Array(displayedPosts.enumerated()), id: \.element.id) { index, post in
                            MacPostCard(post: post, thumbnailURL: galleryThumbnailURL(for: post), preferOriginal: isTallComicPost(post), isFavorite: gallery.isFavorite(post), onFavorite: { gallery.toggleFavorite(post) }, onOpen: { origin in
                                selectedPostOrigin = origin
                                selectedPostThumbnailURL = galleryThumbnailURL(for: post)
                                selectedPost = post
                            })
                                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.94)).combined(with: .offset(y: 12)), removal: .opacity))
                                .animation(.spring(response: 0.42, dampingFraction: 0.82).delay(Double(min(index % 12, 8)) * 0.025), value: displayedPosts)
                        }
                    }
                    .padding(20)
                    .animation(.spring(response: 0.4, dampingFraction: 0.82), value: displayedPosts)
                }
                .scrollIndicators(.hidden)
                .overlay(alignment: .bottom) {
                    if selectedSection == .discover { pagingControls }
                }
            }
        }
        .macPanelSurface(cornerRadius: 26)
    }

    private var pagingControls: some View {
        HStack(spacing: 12) {
            Button { gallery.movePage(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(!gallery.canGoBack)
            Text("PAGE \(gallery.page + 1)")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.6))
            Button { gallery.movePage(1) } label: { Image(systemName: "chevron.right") }
                .disabled(!gallery.canGoForward)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .bold))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
        .padding(.bottom, 16)
    }

    private var displayedPosts: [Rule34Post] {
        selectedSection == .favorites ? savedGallery.favorites : gallery.posts
    }

    private var shouldShowSuggestions: Bool {
        searchIsFocused &&
        !gallery.suggestions.isEmpty &&
        gallery.query.last?.isWhitespace != true
    }

    private var isCurrentSearchLoading: Bool {
        selectedSection == .discover && gallery.isLoading
    }

    private var currentError: String? {
        selectedSection == .discover ? gallery.errorMessage : nil
    }

    private var ageVerificationNotice: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
                .padding(16)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("Age verification required")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text("Rule34 returned an age verification page. Check your VPN location or network.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button { showingAgeVerificationHelp = true } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Regions reported as restricted")
            .popover(isPresented: $showingAgeVerificationHelp, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Reported restrictions")
                        .font(.headline)
                    Text("United Kingdom")
                        .font(.subheadline.weight(.semibold))
                    Text("Certain U.S. states. Rule34 has not published a complete state list.")
                        .font(.callout)
                    Text("The list can change. A detected page only confirms that age verification was returned for this connection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(width: 300, alignment: .leading)
            }
        }
        .padding(32)
    }

    private var subtitle: String {
        guard selectedSection == .discover else { return "Posts you have kept for later" }
        let tagQuery = gallery.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return tagQuery.isEmpty ? "Search the booru, one tag at a time or combine them." : "Showing results for “\(tagQuery)”"
    }

    private func galleryThumbnailURL(for post: Rule34Post) -> URL? {
        let quality: MediaQuality = isTallComicPost(post) ? .high : settings.galleryQuality
        return post.urlForQuality(quality)
    }

    private func isTallComicPost(_ post: Rule34Post) -> Bool {
        guard let width = Double(post.width ?? ""),
              let height = Double(post.height ?? ""), width > 0 else { return false }
        return height / width >= 2.5
    }

    private func emptyState(title: String, symbol: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.82))
                .padding(16)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.48))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(32)
    }

    private var suggestionPlaceholder: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: gallery.query.count < 2 ? "character.cursor.ibeam" : "ellipsis")
                    .foregroundStyle(.white.opacity(0.7))
                Text(gallery.query.count < 2 ? "Type at least 2 letters" : "Looking for matching tags")
                    .foregroundStyle(.white.opacity(0.48))
            }
            .font(.system(size: 11, weight: .medium))

            if gallery.query.isEmpty {
                Text("Suggestions from the global Rule34 tag index will appear here while you type.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 4)
        .animation(.easeInOut(duration: 0.22), value: gallery.query.count < 2)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .tracking(1.15)
            .foregroundStyle(.white.opacity(0.38))
    }

    private func sidebarButton(_ section: MacSection, title: String, symbol: String) -> some View {
        let active = selectedSection == section
        return Button {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(active ? .white : .white.opacity(0.55))
                Text(title)
                    .font(.system(size: 12, weight: active ? .bold : .medium))
                    .foregroundStyle(active ? .white : .white.opacity(0.62))
                Spacer()
                if section == .favorites && !savedGallery.favorites.isEmpty {
                    Text("\(savedGallery.favorites.count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(active ? 0.8 : 0.4))
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 39)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.white.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.9)).frame(width: 3).padding(.vertical, 8)
                        }
                        .matchedGeometryEffect(id: "active-section", in: sectionAnimation)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: active)
    }

    @Namespace private var sectionAnimation

    private func suggestionRow(_ item: AutocompleteItem) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                gallery.applySuggestion(item)
                searchIsFocused = true
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: iconForTagType(item.type))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(colorForTagType(item.type))
                    .frame(width: 22, height: 22)
                    .background(colorForTagType(item.type).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.value.replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                    if let label = item.label, !label.isEmpty {
                        Text(label)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.38))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let type = item.type, !type.isEmpty {
                    Text(type.uppercased())
                        .font(.system(size: 7, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(colorForTagType(type).opacity(0.8))
                }
            }
            .padding(.horizontal, 9)
            .frame(minHeight: 52)
            .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("Use tag \(item.value)")
    }

    private func statusPill(symbol: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).foregroundStyle(.white.opacity(0.56))
        }
        .font(.system(size: 9, weight: .heavy, design: .rounded))
        .tracking(0.55)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.045), in: Capsule())
    }

    private func iconForTagType(_ type: String?) -> String {
        switch type?.lowercased() {
        case "artist": "paintpalette.fill"
        case "character": "person.fill"
        case "copyright": "c.circle.fill"
        case "metadata": "info.circle.fill"
        default: "number"
        }
    }

    private func colorForTagType(_ type: String?) -> Color {
        switch type?.lowercased() {
        case "artist": .white
        case "character": .white.opacity(0.82)
        case "copyright": .white.opacity(0.72)
        case "metadata": .white.opacity(0.62)
        default: .white.opacity(0.78)
        }
    }

    private func runSearch() {
        searchIsFocused = false
        selectedSection = .discover
        gallery.search()
    }

    private func refreshCurrentSection() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.75)) {
            if selectedSection == .favorites {
                savedGallery.refreshFavorites()
            } else {
                gallery.search()
            }
        }
    }

    private func runSidebarAction() {
        if selectedSection == .favorites {
            savedGallery.refreshFavorites()
        } else {
            runSearch()
        }
    }

    private func installSmoothMouseScrolling() {
        guard mouseScrollMonitor == nil else { return }
        mouseScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let window = event.window, let contentView = window.contentView else { return event }
            let point = contentView.convert(event.locationInWindow, from: nil)
            guard !event.hasPreciseScrollingDeltas,
                  !event.modifierFlags.contains(.command),
                  let scrollView = Self.scrollView(under: point, in: contentView) else { return event }

            let clipView = scrollView.contentView
            let current = clipView.bounds.origin
            let maxY = max(0, (scrollView.documentView?.bounds.height ?? 0) - clipView.bounds.height)
            let direction: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
            let targetY = min(maxY, max(0, current.y + CGFloat(event.scrollingDeltaY) * direction * 34))
            guard abs(targetY - current.y) > 0.5 else { return nil }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                clipView.animator().setBoundsOrigin(NSPoint(x: current.x, y: targetY))
            }
            return nil
        }
    }

    private func removeSmoothMouseScrolling() {
        if let mouseScrollMonitor {
            NSEvent.removeMonitor(mouseScrollMonitor)
            self.mouseScrollMonitor = nil
        }
    }

    private static func scrollView(under point: NSPoint, in view: NSView) -> NSScrollView? {
        guard let hit = view.hitTest(point) else { return nil }
        var current: NSView? = hit
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView { return scrollView }
            current = candidate.superview
        }
        return nil
    }
}

private struct Rule34CaptchaWindow: View {
    let html: String
    let onVerificationAttempt: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Complete Rule34 verification")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("The search will retry after verification")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            Rule34CaptchaWebView(html: html, onVerificationAttempt: onVerificationAttempt)
        }
    }
}

private struct Rule34CaptchaWebView: NSViewRepresentable {
    let html: String
    let onVerificationAttempt: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onVerificationAttempt: onVerificationAttempt) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.webView = webView
        webView.loadHTMLString(html, baseURL: URL(string: "https://rule34.xxx/"))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onVerificationAttempt: () -> Void
        weak var webView: WKWebView?
        private var lastSuccessfulURL: URL?
        private var initialChallengeLoaded = false

        init(onVerificationAttempt: @escaping () -> Void) {
            self.onVerificationAttempt = onVerificationAttempt
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard initialChallengeLoaded else {
                initialChallengeLoaded = true
                return
            }
            webView.evaluateJavaScript("({title: document.title, text: document.body?.innerText || '', userAgent: navigator.userAgent})") { [weak self] result, _ in
                guard let self, let page = result as? [String: String] else { return }
                let content = "\(page["title"] ?? "") \(page["text"] ?? "")".lowercased()
                guard !content.contains("captcha") else { return }
                guard let url = webView.url, url.host?.hasSuffix("rule34.xxx") == true,
                      self.lastSuccessfulURL != url else { return }
                self.lastSuccessfulURL = url
                Rule34CaptchaCookieStore.sync(from: webView.configuration.websiteDataStore.httpCookieStore, userAgent: page["userAgent"]) {
                    self.onVerificationAttempt()
                }
            }
        }
    }
}

private struct MacWindowCornerStyle: NSViewRepresentable {
    private let trafficLightsInset = NSPoint(x: 9, y: -8)
    private static var trafficLightsOffsetKey = 0

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view) }
    }

    private func configure(_ view: NSView) {
        guard let window = view.window else { return }
        window.titleVisibility = .hidden

        guard objc_getAssociatedObject(window, &Self.trafficLightsOffsetKey) as? Bool != true else { return }
        for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(buttonType) else { continue }
            button.setFrameOrigin(NSPoint(
                x: button.frame.origin.x + trafficLightsInset.x,
                y: button.frame.origin.y + trafficLightsInset.y
            ))
        }
        objc_setAssociatedObject(window, &Self.trafficLightsOffsetKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

private extension View {
    func macPanelSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(.white.opacity(0.022), in: shape)
            .clipShape(shape)
            .overlay(shape.stroke(.white.opacity(0.06), lineWidth: 1))
    }
}

private final class MacFullscreenViewerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private final class MacViewerTransitionState: ObservableObject {
    @Published var progress: CGFloat = 0
}

private enum MacSection: Hashable {
    case discover
    case favorites
}

private struct MacPostCard: View {
    let post: Rule34Post
    let thumbnailURL: URL?
    let preferOriginal: Bool
    let isFavorite: Bool
    let onFavorite: () -> Void
    let onOpen: (CGRect) -> Void
    @State private var isHovered = false

    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width
            ZStack(alignment: .topTrailing) {
                MacPostImage(url: thumbnailURL, post: post, preferOriginal: preferOriginal)
                    .frame(width: side, height: side)
                    .clipped()

                LinearGradient(colors: [.black.opacity(0.32), .clear, .black.opacity(0.18)], startPoint: .top, endPoint: .bottom)

                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.black.opacity(0.58), in: Circle())
                        .scaleEffect(isFavorite ? 1.04 : 1)
                }
                .buttonStyle(.plain)
                .help(isFavorite ? "Remove from saved posts" : "Save post")
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if post.isVideo {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.gray.opacity(0.72), lineWidth: 1.5)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.width)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture { onOpen(geometry.frame(in: .global)) }
        }
        .aspectRatio(1, contentMode: .fit)
        .shadow(color: isHovered ? .white.opacity(0.08) : .black.opacity(0.12), radius: isHovered ? 18 : 8, y: isHovered ? 8 : 3)
        .scaleEffect(isHovered ? 1.018 : 1)
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { isHovered = hovering }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MacPostImage: View {
    let url: URL?
    let post: Rule34Post
    let preferOriginal: Bool
    @State private var image: NSImage?
    @State private var loading = false

    var body: some View {
        ZStack {
            Rectangle().fill(LinearGradient(colors: [.white.opacity(0.045), .white.opacity(0.015)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .transition(.opacity)
                    .drawingGroup(opaque: false, colorMode: .linear)
            } else if loading {
                ProgressView().controlSize(.small).tint(.white.opacity(0.5))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(.white.opacity(0.22))
            }
        }
        .task(id: "\(post.id)-\(url?.absoluteString ?? "none")-\(preferOriginal)") { await loadImage() }
    }

    @MainActor
    private func loadImage() async {
        guard let previewURL = url else { return }
        loading = true
        defer { loading = false }
        // A post can expose only one of preview/sample/original URLs, and an
        // advertised URL can still return 404. Try every available rendition
        // in order before giving up on the thumbnail.
        let candidates = [previewURL, post.previewURL, post.sampleURL, post.fileURL]
            .compactMap { $0 }
            .reduce(into: [URL]()) { result, candidate in
                if !result.contains(candidate) { result.append(candidate) }
            }
        guard let preview = await firstAvailableImage(from: candidates) else { return }
        image = preview

        let previewIsTall = preview.size.width > 0 && preview.size.height / preview.size.width >= 2.5
        guard (preferOriginal || previewIsTall), post.needsBooruMediaResolution,
              let details = try? await Rule34APIClient().fetchBooruPost(id: post.id),
              let originalURL = details.fileURL,
              originalURL != previewURL,
              let original = await image(for: originalURL) else { return }
        withAnimation(.easeOut(duration: 0.25)) { image = original }
    }

    @MainActor
    private func firstAvailableImage(from urls: [URL]) async -> NSImage? {
        for candidate in urls {
            if let image = await image(for: candidate) {
                return image
            }
        }
        return nil
    }

    @MainActor
    private func image(for url: URL) async -> NSImage? {
        if let cached = MacThumbnailMemoryCache.shared.image(for: url) { return cached }
        let data: Data
        if let cachedData = await ImageCacheStore.shared.cachedData(for: url) {
            data = cachedData
        } else {
            do {
                let (downloaded, _) = try await URLSession.shared.data(for: Rule34APIClient.mediaRequest(for: url))
                data = downloaded
                await ImageCacheStore.shared.store(downloaded, for: url)
            } catch {
                return nil
            }
        }
        let thumbnail = await Task.detached(priority: .utility) {
            downsampleMacImage(data, maximumPixelSize: 720)
        }.value
        if let thumbnail {
            MacThumbnailMemoryCache.shared.insert(thumbnail, for: url)
        }
        return thumbnail
    }
}

private func downsampleMacImage(_ data: Data, maximumPixelSize: CGFloat) -> NSImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
          ] as CFDictionary) else { return nil }
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}

private final class MacThumbnailMemoryCache {
    static let shared = MacThumbnailMemoryCache()
    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 180
        cache.totalCostLimit = 128 * 1024 * 1024
    }

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: NSImage, for url: URL) {
        let pixels = Int(image.size.width * image.size.height)
        cache.setObject(image, forKey: url as NSURL, cost: max(1, pixels * 4))
    }
}

private struct MacPostViewer: View {
    let post: Rule34Post
    let thumbnailURL: URL?
    let originFrame: NSRect
    let screenFrame: NSRect
    @ObservedObject var gallery: GalleryViewModel
    @ObservedObject var transition: MacViewerTransitionState
    let onFavorite: () -> Void
    let settings: AppSettings
    let onSearchTag: (String) -> Void
    let onClose: () -> Void

    @State private var showInfo = false
    @State private var image: NSImage?
    @State private var isLoadingOriginal = true
    @State private var didLoadOriginal = false
    @State private var downloadMessage: String?
    @State private var isDownloading = false
    @State private var resolvedPost: Rule34Post?
    @State private var zoomScale: CGFloat = 1
    @State private var mediaReveal: CGFloat = 0
    @State private var toolbarReveal: CGFloat = 0
    @State private var imageOffset = CGSize.zero
    @State private var dragOrigin = CGSize.zero
    @State private var viewerSize = CGSize.zero
    @State private var scrollMonitor: Any?
    @State private var keyboardMonitor: Any?
    @State private var infoTagsByCategory: [Rule34TagInfo.Category: [Rule34TagInfo]] = [:]
    @State private var infoComments: [Rule34Comment] = []
    @State private var isLoadingInfo = false

    init(
        post: Rule34Post,
        thumbnailURL: URL?,
        originFrame: NSRect,
        screenFrame: NSRect,
        gallery: GalleryViewModel,
        transition: MacViewerTransitionState,
        onFavorite: @escaping () -> Void,
        settings: AppSettings,
        onSearchTag: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.post = post
        self.thumbnailURL = thumbnailURL
        self.originFrame = originFrame
        self.screenFrame = screenFrame
        self.gallery = gallery
        self.transition = transition
        self.onFavorite = onFavorite
        self.settings = settings
        self.onSearchTag = onSearchTag
        self.onClose = onClose
        let cachedCover = [post.previewURL, post.sampleURL, thumbnailURL, post.fileURL]
            .compactMap { $0 }
            .compactMap { MacThumbnailMemoryCache.shared.image(for: $0) }
            .first
        _image = State(initialValue: cachedCover)
    }

    private var activePost: Rule34Post { resolvedPost ?? post }
    private var isTallComic: Bool {
        guard let width = Double(activePost.width ?? ""),
              let height = Double(activePost.height ?? ""), width > 0 else { return false }
        return height / width >= 2.5
    }
    private var mediaQuality: MediaQuality {
        isTallComic ? .high : settings.fullViewQuality
    }
    private var mediaURL: URL? { activePost.urlForQuality(mediaQuality) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            mediaViewer
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            HStack(spacing: 9) {
                if let downloadMessage {
                    Text(downloadMessage)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(.black.opacity(0.72), in: Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                viewerButton("info.circle", help: "Post information") {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { showInfo.toggle() }
                }
                let isFavorite = gallery.isFavorite(post)
                viewerButton(isFavorite ? "heart.fill" : "heart", help: isFavorite ? "Remove from saved posts" : "Save post", action: onFavorite)
                viewerButton(isDownloading ? "arrow.down.circle" : "arrow.down.to.line", help: "Download original") {
                    Task { await downloadMedia() }
                }
                viewerButton("arrow.up.right.square", help: "Open on Rule34") {
                    if let url = URL(string: "https://rule34.xxx/index.php?page=post&s=view&id=\(post.id)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                viewerButton("xmark", help: "Close", action: onClose)
            }
            .padding(.trailing, 36)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .opacity(transition.progress)
            .offset(y: 42 * (1 - toolbarReveal))
            .zIndex(2)

            if showInfo {
                infoPanel
                    .frame(width: 280)
                    .padding(.top, 70)
                    .padding(.trailing, 18)
                    .padding(.bottom, 18)
                    .opacity(transition.progress)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .preferredColorScheme(.dark)
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { viewerSize = geometry.size }
                .onChange(of: geometry.size) { viewerSize = $0 }
        })
        .ignoresSafeArea()
        .onAppear(perform: installScrollZoomMonitor)
        .onDisappear(perform: removeScrollZoomMonitor)
        .onAppear {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    mediaReveal = 1
                    toolbarReveal = 1
                }
            }
        }
        .onChange(of: transition.progress) { progress in
            if progress == 0 {
                // Return to the neutral media state before the window disappears.
                withAnimation(.linear(duration: 0.07)) {
                    zoomScale = 1
                    imageOffset = .zero
                    dragOrigin = .zero
                }
            }
            withAnimation(.easeInOut(duration: progress > 0 ? 0.26 : 0.20)) {
                mediaReveal = progress
            }
        }
        .task(id: post.id) { await loadPostMedia() }
        .task(id: showInfo ? post.id : "") {
            guard showInfo else { return }
            await loadInfo()
        }
    }

    @ViewBuilder
    private var mediaViewer: some View {
        ZStack(alignment: .topLeading) {
            if activePost.isVideo, let mediaURL {
                MacNativeVideoPlayer(url: mediaURL)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .scaleEffect(revealScale + ((1 - revealScale) * mediaReveal))
                    .offset(revealOffset)
            } else if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(zoomScale)
                    .offset(imageOffset)
                    .scaleEffect((revealScale + ((1 - revealScale) * mediaReveal)) * zoomScale)
                    .offset(x: revealOffset.width + imageOffset.width, y: revealOffset.height + imageOffset.height)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard zoomScale > 1 else { return }
                                let dragSensitivity: CGFloat = 0.68
                                imageOffset = CGSize(
                                    width: dragOrigin.width + value.translation.width * dragSensitivity,
                                    height: dragOrigin.height + value.translation.height * dragSensitivity
                                )
                            }
                            .onEnded { _ in dragOrigin = imageOffset }
                    )
                    .animation(.easeOut(duration: 0.12), value: zoomScale)
            } else {
                Color.clear
            }

            if isLoadingOriginal {
                ProgressView()
                    .controlSize(.regular)
                    .tint(.white)
                    .padding(9)
                    .background(.black.opacity(0.52), in: Circle())
                    .padding(.top, 28)
                    .padding(.leading, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var infoPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .center) {
                    Text("POST INFORMATION")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer(minLength: 6)
                    Text((activePost.sourceMode ?? settings.searchSourceMode) == .api ? "API" : "BOORU")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.1), in: Capsule())
                }
                infoRow("Post", value: activePost.id)
                infoRow("Score", value: activePost.score ?? "—")
                infoRow("Size", value: activePost.pixelSizeText)
                infoRow("Type", value: activePost.mediaKind)

                sectionDivider

                ForEach(Rule34TagInfo.Category.allCases, id: \.self) { category in
                    if let items = infoTagsByCategory[category], !items.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(category.displayName.uppercased())
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .tracking(0.9)
                                .foregroundStyle(.white.opacity(0.52))
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
                                ForEach(items) { tag in
                                    Button { onSearchTag(tag.name) } label: {
                                        Text(tag.name.replacingOccurrences(of: "_", with: " "))
                                            .font(.system(size: 10, weight: .semibold))
                                            .lineLimit(1)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 6)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Search for \(tag.name)")
                                }
                            }
                        }
                    }
                }

                sectionDivider

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("COMMENTS")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(0.9)
                            .foregroundStyle(.white.opacity(0.52))
                        Spacer()
                        if isLoadingInfo { ProgressView().controlSize(.mini).tint(.white.opacity(0.7)) }
                    }
                    if isLoadingInfo && infoComments.isEmpty {
                        Text("Loading comments…")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                    } else if infoComments.isEmpty {
                        Text("No comments found.")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                    } else {
                        ForEach(infoComments) { comment in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Button {
                                        onSearchTag(comment.creator.isEmpty ? "Anonymous" : comment.creator)
                                    } label: {
                                        Text(comment.creator.isEmpty ? "Anonymous" : comment.creator)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.9))
                                    }
                                    .buttonStyle(.plain)
                                    Spacer(minLength: 4)
                                    if let date = comment.createdAt {
                                        Text(date)
                                            .font(.system(size: 8))
                                            .foregroundStyle(.white.opacity(0.4))
                                    }
                                }
                                Text(comment.body.decodingHTMLEntities())
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .textSelection(.enabled)
                            }
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 20, x: -6, y: 8)
    }

    private var sectionDivider: some View {
        Capsule().fill(.white.opacity(0.09)).frame(height: 1)
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.45))
            Spacer()
            Text(value).foregroundStyle(.white.opacity(0.82))
        }
        .font(.system(size: 11, weight: .medium))
    }

    private func loadInfo() async {
        isLoadingInfo = true
        defer { isLoadingInfo = false }

        async let loadedComments = fetchComments()
        async let loadedTags = buildGroupedTags()
        infoComments = await loadedComments
        infoTagsByCategory = await loadedTags
    }

    private func fetchComments() async -> [Rule34Comment] {
        let mode = activePost.sourceMode ?? settings.searchSourceMode
        switch mode {
        case .api:
            return (try? await Rule34APIClient().fetchComments(
                postID: activePost.id,
                userID: settings.userID,
                apiKey: settings.apiKey
            )) ?? []
        case .booru:
            if let comments = try? await Rule34APIClient().fetchBooruComments(postID: activePost.id), !comments.isEmpty {
                return comments
            }
            return (try? await Rule34APIClient().fetchComments(
                postID: activePost.id,
                userID: settings.userID,
                apiKey: settings.apiKey
            )) ?? []
        }
    }

    private func buildGroupedTags() async -> [Rule34TagInfo.Category: [Rule34TagInfo]] {
        let names = activePost.tagList
        let orderedNames = Array(NSOrderedSet(array: names)) as? [String] ?? names
        var grouped: [Rule34TagInfo.Category: [Rule34TagInfo]] = [:]

        for name in orderedNames {
            if let type = activePost.tagTypes?[name] {
                grouped[Rule34TagInfo(id: name, name: name, count: nil, type: type).category, default: []]
                    .append(Rule34TagInfo(id: name, name: name, count: nil, type: type))
            }
        }

        let unresolved = orderedNames.filter { activePost.tagTypes?[$0] == nil }
        let fetched = await Rule34TagMetadataStore.shared.warm(tags: Array(unresolved.prefix(12)))
        for item in fetched where !item.name.isEmpty {
            grouped[item.category, default: []].append(item)
        }

        let categorized = Set(grouped.values.flatMap { $0.map(\.name) })
        let remaining = orderedNames.filter { !categorized.contains($0) }
        if !remaining.isEmpty {
            grouped[.general, default: []].append(contentsOf: remaining.map {
                Rule34TagInfo(id: $0, name: $0, count: nil, type: nil)
            })
        }

        for category in grouped.keys {
            grouped[category]?.sort { lhs, rhs in
                guard let lhsIndex = orderedNames.firstIndex(of: lhs.name),
                      let rhsIndex = orderedNames.firstIndex(of: rhs.name) else { return lhs.name < rhs.name }
                return lhsIndex < rhsIndex
            }
        }
        return grouped
    }

    private func viewerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(isDownloading && help == "Download original")
    }

    @MainActor
    private func loadPostMedia() async {
        isLoadingOriginal = true
        didLoadOriginal = false
        defer { isLoadingOriginal = false }

        if image == nil {
            Task { @MainActor in await loadThumbnailIfNeeded() }
        }

        if post.needsBooruMediaResolution,
           let details = try? await Rule34APIClient().fetchBooruPost(id: post.id) {
            resolvedPost = Rule34Post(
                id: post.id,
                fileURL: details.fileURL ?? post.fileURL,
                previewURL: post.previewURL ?? details.previewURL,
                sampleURL: details.sampleURL ?? post.sampleURL,
                tags: details.tags.isEmpty ? post.tags : details.tags,
                score: details.score ?? post.score,
                width: details.width ?? post.width,
                height: details.height ?? post.height,
                createdAt: details.createdAt ?? post.createdAt,
                tagTypes: details.tagTypes ?? post.tagTypes,
                sourceMode: .booru
            )
        }
        if isTallComic { zoomScale = 1.12 }
        guard !activePost.isVideo, let mediaURL else { return }
        if let cached = await ImageCacheStore.shared.cachedImage(for: mediaURL) {
            image = cached
            didLoadOriginal = true
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(for: Rule34APIClient.mediaRequest(for: mediaURL))
            guard let loaded = NSImage(data: data) else { return }
            await ImageCacheStore.shared.store(data, for: mediaURL)
            image = loaded
            didLoadOriginal = true
        } catch {
            downloadMessage = "Preview failed to load"
        }
    }

    @MainActor
    private func loadThumbnailIfNeeded() async {
        let candidates = [post.previewURL, post.sampleURL, thumbnailURL]
            .compactMap { $0 }
            .reduce(into: [URL]()) { result, candidate in
                if !result.contains(candidate) { result.append(candidate) }
            }

        for url in candidates {
            if let cached = MacThumbnailMemoryCache.shared.image(for: url) {
                guard !didLoadOriginal else { return }
                image = cached
                return
            }

            let data: Data
            if let cachedData = await ImageCacheStore.shared.cachedData(for: url) {
                data = cachedData
            } else {
                do {
                    let (downloaded, _) = try await URLSession.shared.data(for: Rule34APIClient.mediaRequest(for: url))
                    data = downloaded
                    await ImageCacheStore.shared.store(downloaded, for: url)
                } catch {
                    continue
                }
            }

            guard let cover = NSImage(data: data) else { continue }
            MacThumbnailMemoryCache.shared.insert(cover, for: url)
            guard !didLoadOriginal else { return }
            image = cover
            return
        }
    }

    @MainActor
    private func downloadMedia() async {
        guard let mediaURL = activePost.urlForQuality(.high) else {
            downloadMessage = "Media URL unavailable"
            return
        }
        isDownloading = true
        defer { isDownloading = false }
        do {
            let (data, _) = try await URLSession.shared.data(for: Rule34APIClient.mediaRequest(for: mediaURL))
            let panel = NSSavePanel()
            panel.nameFieldStringValue = mediaURL.lastPathComponent.isEmpty ? "Rule34_\(post.id)" : mediaURL.lastPathComponent
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            try data.write(to: destination, options: .atomic)
            downloadMessage = "Saved to \(destination.lastPathComponent)"
        } catch {
            downloadMessage = "Download failed: \(error.localizedDescription)"
        }
    }

    private func installScrollZoomMonitor() {
        if scrollMonitor == nil {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                guard event.modifierFlags.contains(.command), !activePost.isVideo else { return event }
                // Trackpad and high-resolution wheels can report large deltas;
                // keep each gesture gradual instead of jumping several zoom levels.
                let multiplier = pow(1.08, Double(event.scrollingDeltaY))
                DispatchQueue.main.async {
                    let nextScale = min(8, max(1, zoomScale * CGFloat(multiplier)))
                    let scaleRatio = nextScale / zoomScale
                    let size = viewerSize == .zero ? (event.window?.contentView?.bounds.size ?? .zero) : viewerSize
                    let cursorX = event.locationInWindow.x
                    let cursorY = size.height - event.locationInWindow.y
                    let fittedImageSize = self.fittedImageSize(image?.size ?? size, in: size)
                    let visibleImage = CGRect(
                        x: (size.width - fittedImageSize.width * zoomScale) / 2 + imageOffset.width,
                        y: (size.height - fittedImageSize.height * zoomScale) / 2 + imageOffset.height,
                        width: fittedImageSize.width * zoomScale,
                        height: fittedImageSize.height * zoomScale
                    )
                    let cursorIsOverImage = visibleImage.contains(CGPoint(x: cursorX, y: cursorY))
                    let anchorX = cursorIsOverImage ? cursorX - size.width / 2 : 0
                    let anchorY = cursorIsOverImage ? cursorY - size.height / 2 : 0
                    let proposed = CGSize(
                        width: anchorX - (anchorX - imageOffset.width) * scaleRatio,
                        height: anchorY - (anchorY - imageOffset.height) * scaleRatio
                    )
                    imageOffset = self.constrainedImageOffset(proposed, imageSize: fittedImageSize, viewerSize: size, scale: nextScale)
                    zoomScale = nextScale
                    dragOrigin = imageOffset
                    if nextScale == 1 {
                        imageOffset = .zero
                        dragOrigin = .zero
                    }
                }
                return nil
            }
        }

        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            DispatchQueue.main.async { onClose() }
            return nil
        }

    }

    private func fittedImageSize(_ imageSize: CGSize, in bounds: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private var revealScale: CGFloat {
        guard viewerSize.width > 0 else { return 0.82 }
        let fitted = fittedImageSize(image?.size ?? viewerSize, in: viewerSize)
        return min(1, max(0.08, originFrame.width / max(1, fitted.width)))
    }

    private var revealOffset: CGSize {
        guard viewerSize.width > 0 else { return .zero }
        let originCenterX = originFrame.midX - screenFrame.minX
        let originCenterY = screenFrame.height - (originFrame.midY - screenFrame.minY)
        return CGSize(
            width: (originCenterX - viewerSize.width / 2) * (1 - mediaReveal),
            height: (originCenterY - viewerSize.height / 2) * (1 - mediaReveal)
        )
    }

    private func constrainedImageOffset(_ offset: CGSize, imageSize: CGSize, viewerSize: CGSize, scale: CGFloat) -> CGSize {
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let limitX = max(0, (scaledWidth - viewerSize.width) / 2)
        let limitY = max(0, (scaledHeight - viewerSize.height) / 2)
        return CGSize(
            width: min(limitX, max(-limitX, offset.width)),
            height: min(limitY, max(-limitY, offset.height))
        )
    }

    private func removeScrollZoomMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
    }
}

private struct MetalImageView: NSViewRepresentable {
    let image: NSImage
    let zoomScale: CGFloat
    let imageOffset: CGSize
    let revealScale: CGFloat
    let revealOffset: CGSize

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        context.coordinator.configure(view)
        guard context.coordinator.isReady else {
            let fallback = NSImageView(frame: .zero)
            fallback.image = image
            fallback.imageScaling = .scaleProportionallyUpOrDown
            fallback.wantsLayer = true
            return fallback
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let view = view as? MTKView else {
            (view as? NSImageView)?.image = image
            return
        }
        context.coordinator.update(image: image, zoom: zoomScale * revealScale,
                                   offset: CGSize(width: imageOffset.width + revealOffset.width,
                                                  height: imageOffset.height + revealOffset.height),
                                   in: view)
        view.setNeedsDisplay(view.bounds)
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        private var pipeline: MTLRenderPipelineState?
        private var commandQueue: MTLCommandQueue?
        private var texture: MTLTexture?
        private var imageIdentity: ObjectIdentifier?
        private var zoom: Float = 1
        private var offset = SIMD2<Float>(0, 0)
        private var imageAspect: Float = 1
        var isReady: Bool { pipeline != nil }

        func configure(_ view: MTKView) {
            guard let device = view.device else { return }
            commandQueue = device.makeCommandQueue()
            guard commandQueue != nil else { return }
            let source = """
            #include <metal_stdlib>
            using namespace metal;
            struct VOut { float4 position [[position]]; float2 uv; };
            struct Params { float2 scale; float2 offset; };
            vertex VOut imageVertex(uint id [[vertex_id]], constant Params &p [[buffer(0)]]) {
                float2 pos[6] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(-1,1),float2(1,-1),float2(1,1)};
                float2 uv[6] = {float2(0,1),float2(1,1),float2(0,0),float2(0,0),float2(1,1),float2(1,0)};
                VOut o; o.position=float4(pos[id]*p.scale+p.offset,0,1); o.uv=uv[id]; return o;
            }
            fragment float4 imageFragment(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
                constexpr sampler s(address::clamp_to_edge, filter::linear);
                return tex.sample(s,in.uv);
            }
            """
            do {
                let library = try device.makeLibrary(source: source, options: nil)
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "imageVertex")
                descriptor.fragmentFunction = library.makeFunction(name: "imageFragment")
                descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
                pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
                view.delegate = self
            } catch { pipeline = nil }
        }

        func update(image: NSImage, zoom: CGFloat, offset: CGSize, in view: MTKView) {
            self.zoom = Float(zoom)
            self.offset = SIMD2(Float(offset.width / max(1, view.bounds.width) * 2), Float(-offset.height / max(1, view.bounds.height) * 2))
            guard imageIdentity != ObjectIdentifier(image) else { return }
            imageIdentity = ObjectIdentifier(image)
            guard let device = view.device,
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { texture = nil; return }
            imageAspect = Float(cg.width) / Float(max(1, cg.height))
            let loader = MTKTextureLoader(device: device)
            texture = try? loader.newTexture(cgImage: cg, options: [.SRGB: false, .textureUsage: MTLTextureUsage.shaderRead.rawValue])
        }

        func draw(in view: MTKView) {
            guard let pipeline, let texture, let pass = view.currentRenderPassDescriptor,
                  let buffer = view.device?.makeBuffer(length: MemoryLayout<SIMD4<Float>>.stride, options: []) else { return }
            let aspect = Float(view.drawableSize.width / max(1, view.drawableSize.height))
            let fit: SIMD2<Float> = imageAspect > aspect ? SIMD2(1, aspect / imageAspect) : SIMD2(imageAspect / aspect, 1)
            var params = SIMD4<Float>(fit.x * zoom, fit.y * zoom, offset.x, offset.y)
            memcpy(buffer.contents(), &params, MemoryLayout<SIMD4<Float>>.stride)
            guard let queue = commandQueue, let command = queue.makeCommandBuffer(),
                  let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
            encoder.setRenderPipelineState(pipeline); encoder.setVertexBuffer(buffer, offset: 0, index: 0); encoder.setFragmentTexture(texture, index: 0); encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6); encoder.endEncoding()
            if let drawable = view.currentDrawable { command.present(drawable) }
            command.commit()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    }
}

/// Uses AppKit's native AVPlayerView instead of AVKit's SwiftUI VideoPlayer.
/// The latter crashes during SwiftUI metadata/layout setup on some Intel Hackintosh systems.
private struct MacNativeVideoPlayer: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.player = context.coordinator.player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        context.coordinator.player.replaceCurrentItem(with: AVPlayerItem(url: url))
        view.player = context.coordinator.player
    }

    final class Coordinator {
        private static let volumeKey = "macVideoPlayer.volume"
        private static let mutedKey = "macVideoPlayer.muted"

        var url: URL
        let player: AVPlayer
        private var volumeObservation: NSKeyValueObservation?
        private var mutedObservation: NSKeyValueObservation?

        init(url: URL) {
            self.url = url
            self.player = AVPlayer(url: url)
            let defaults = UserDefaults.standard
            let savedVolume = defaults.object(forKey: Self.volumeKey) as? NSNumber
            player.volume = savedVolume.map { min(1, max(0, $0.floatValue)) } ?? 1
            player.isMuted = defaults.object(forKey: Self.mutedKey) as? Bool ?? false

            // Observe the AVPlayer itself so changes made through AVPlayerView's
            // native volume and mute controls are persisted immediately.
            volumeObservation = player.observe(\.volume, options: [.new]) { player, _ in
                defaults.set(player.volume, forKey: Self.volumeKey)
            }
            mutedObservation = player.observe(\.isMuted, options: [.new]) { player, _ in
                defaults.set(player.isMuted, forKey: Self.mutedKey)
            }
        }
    }
}
