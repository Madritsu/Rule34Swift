import SwiftUI

struct GalleryScreen: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var coordinator: AppCoordinator
    @StateObject private var model: GalleryViewModel
    @State private var selectedPost: Rule34Post?
    @State private var showingCaptcha = false
    @State private var showingAgeInfo = false
    @FocusState private var isSearchFocused: Bool

    init(settings: AppSettings, coordinator: AppCoordinator, mode: GalleryViewModel.Mode) {
        self.settings = settings
        self.coordinator = coordinator
        _model = StateObject(wrappedValue: GalleryViewModel(settings: settings, mode: mode))
    }

#if os(macOS)
    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)
    ]
#elseif targetEnvironment(macCatalyst)
    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)
    ]
#else
    private let columns = [
        // На iPhone 8 ширина контента позволяет разместить три плитки.
        // Минимум 100 pt оставляет достаточно места даже с отступами и зазорами.
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 8)
    ]
#endif

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        if model.mode == .search {
                            searchPanel
                        }

                        statusRow

                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(model.visiblePosts) { post in
                                PostTile(post: post, isFavorite: model.isFavorite(post), galleryQuality: settings.galleryQuality)
                                    .onTapGesture {
                                        selectedPost = post
                                    }
                            }
                        }
                        .id(model.page)
                    }
                    .padding(12)
                    .padding(.bottom, 96)
                }
                .refreshable {
                    await model.load()
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 40)
                        .onEnded(handlePageSwipe)
                )
            }
            .navigationTitle(model.title)
            .toolbar {
                #if os(macOS)
                ToolbarItemGroup(placement: .automatic) {
                    Button {
                        model.movePage(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!model.canGoBack)

                    Button {
                        model.movePage(1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!model.canGoForward)
                }
                #else
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        model.movePage(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!model.canGoBack)

                    Button {
                        model.movePage(1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!model.canGoForward)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    if isSearchFocused {
                        Button {
                            isSearchFocused = false
                            dismissKeyboard()
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.title3)
                        }
                        .tint(.orange)
                    }
                }
                #endif
            }
            .task {
                await model.load()
            }
            .onChange(of: coordinator.pendingSearchTag) { newValue in
                guard model.mode == .search, let newValue, !newValue.isEmpty else { return }
                model.query = newValue
                model.search()
                coordinator.pendingSearchTag = nil
            }
            .onChange(of: settings.hideAI) { _ in model.search() }
            .onChange(of: settings.blacklist) { _ in model.search() }
            .onReceive(NotificationCenter.default.publisher(for: .favoritesDidChange)) { _ in
                model.reloadFavorites()
            }
#if os(macOS)
            .sheet(item: $selectedPost) { post in
                detailView(for: post)
            }
#elseif targetEnvironment(macCatalyst)
            .fullScreenCover(item: $selectedPost) { post in
                detailView(for: post)
            }
#else
            .sheet(item: $selectedPost) { post in
                detailView(for: post)
            }
#endif
            .onChange(of: model.captchaDetected) { detected in
                if detected { showingCaptcha = true }
            }
            .sheet(isPresented: $showingCaptcha) {
                VStack(spacing: 12) {
                    Text("Complete Rule34 verification")
                        .font(.headline)
                    Rule34CaptchaWebView(html: model.captchaHTML ?? "") {
                        showingCaptcha = false
                        model.search()
                    }
                }
                .padding()
                .presentationDetents([.large])
            }
            .alert("Age verification", isPresented: $showingAgeInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Reported restrictions: United Kingdom and certain U.S. states. Rule34 has not published a complete state list. Check your VPN location or network.")
            }
        }
    }

    @ViewBuilder
    private func detailView(for post: Rule34Post) -> some View {
        PostDetailView(
            post: post,
            isFavorite: model.isFavorite(post),
            fullViewQuality: settings.fullViewQuality,
            sourceMode: post.sourceMode ?? settings.searchSourceMode,
            onSearchTag: { tag in
                coordinator.openSearch(tag: tag)
                selectedPost = nil
            },
            onToggleFavorite: { updatedPost in
                model.toggleFavorite(updatedPost)
            }
        )
        .environmentObject(settings)
    }

    private var searchPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "number")
                    .foregroundStyle(.orange)

                TextField("tags, e.g. neko highres", text: $model.query)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                    .onSubmit { model.search() }
                    .onChange(of: model.query) { _ in model.updateSuggestions() }

                Button {
                    model.search()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(settings.searchSourceMode == .api && !settings.hasCredentials)
            }

            if !model.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(model.suggestions.prefix(10)) { item in
                            Button(item.value) {
                                model.applySuggestion(item)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        }
                    }
                }
            }
        }
        .padding(12)
        .r34Glass(cornerRadius: 20, interactive: true)
    }

    private var statusRow: some View {
        HStack {
            if model.isLoading {
                ProgressView()
                    .tint(.orange)
                Text("Loading")
            } else if model.ageVerificationDetected {
                HStack {
                    Label("Age verification required. Check VPN location.", systemImage: "checkmark.shield")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button { showingAgeInfo = true } label: { Image(systemName: "questionmark.circle") }
                        .buttonStyle(.plain)
                }
            } else if model.captchaDetected {
                Button { showingCaptcha = true } label: {
                    Label("CAPTCHA required. Tap to verify.", systemImage: "exclamationmark.shield")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            } else if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if model.mode == .search {
                Text("Page \(model.page + 1)")
                Spacer()
                if settings.searchSourceMode == .booru {
                    // rule34.xxx HTML doesn't provide total count
                    Text("Browsing")
                } else {
                    Text("Results \(model.total)")
                }
            } else {
                Text("\(model.visiblePosts.count) saved")
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handlePageSwipe(_ value: DragGesture.Value) {
        guard model.mode == .search, !model.isLoading else { return }
        let horizontal = value.translation.width
        let vertical = value.translation.height
        guard abs(horizontal) > abs(vertical), abs(horizontal) >= 70 else { return }

        if horizontal < 0, model.canGoForward {
            model.movePage(1)
        } else if horizontal > 0, model.canGoBack {
            model.movePage(-1)
        }
    }
}
