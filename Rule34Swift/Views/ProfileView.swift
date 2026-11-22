import SwiftUI

struct ProfileView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var coordinator: AppCoordinator
    @StateObject private var account = Rule34AccountService()

    @State private var showsAuth = false
    @State private var selectedPost: Rule34Post?
    @State private var localFavorites: [Rule34Post] = []

    private let api = Rule34APIClient()
    private let favoritesStore = FavoritesStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    headerCard

                    if account.isLoggedIn {
                        accountSection
                    } else {
                        guestCard
                    }

                    if account.isLoggedIn {
                        feedSection(
                            title: "Favorites from account",
                            subtitle: "Pulled from the logged-in session",
                            posts: account.favorites
                        )

                        feedSection(
                            title: "Published from account",
                            subtitle: "Loaded from the user uploads search",
                            posts: account.uploads
                        )
                    }
                }
                .padding(12)
                .padding(.bottom, 96)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Profile")
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .automatic) {
                    if account.isLoggedIn {
                        Button {
                            Task {
                                await account.refreshSession(username: settings.accountUsername)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                #else
                ToolbarItem(placement: .topBarTrailing) {
                    if account.isLoggedIn {
                        Button {
                            Task {
                                await account.refreshSession(username: settings.accountUsername)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                #endif
            }
            .sheet(item: $selectedPost) { post in
                PostDetailView(
                    post: post,
                    isFavorite: isFavorite(post),
                    fullViewQuality: settings.fullViewQuality,
                    sourceMode: post.sourceMode ?? settings.searchSourceMode,
                    onSearchTag: { tag in
                        coordinator.openSearch(tag: tag)
                    },
                    onToggleFavorite: { updatedPost in
                        toggleFavorite(updatedPost)
                    }
                )
                .environmentObject(settings)
            }
            #if os(macOS)
            .sheet(isPresented: $showsAuth) {
                authView
            }
            #else
            .fullScreenCover(isPresented: $showsAuth) {
                authView
            }
            #endif
            .task {
                localFavorites = favoritesStore.load()
                let savedUsername = settings.accountUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !savedUsername.isEmpty || account.isLoggedIn {
                    await account.refreshSession(username: savedUsername.isEmpty ? nil : savedUsername)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .favoritesDidChange)) { _ in
                localFavorites = favoritesStore.load()
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString(account.isLoggedIn ? "Logged in" : "Account", comment: "Account status"))
                        .font(.headline)
                    Text(NSLocalizedString(account.isLoggedIn ? "Your site session is active." : "Sign in to load favorites and uploads from the account.", comment: "Account status"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let username = account.username, !username.isEmpty {
                    Text(username)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.orange.opacity(0.18))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 10) {
                Button {
                    showsAuth = true
                } label: {
                    Label(NSLocalizedString(account.isLoggedIn ? "Reconnect" : "Register / Login", comment: "Account action"), systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                if account.isLoggedIn {
                    Button(role: .destructive) {
                        settings.clearAccountSession()
                        account.signOut()
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .r34Glass(cornerRadius: 20, interactive: true)
    }

    private var guestCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Login / Register")
                .font(.headline)
            Text("Open the site, sign in or register there, and the app will capture the session cookies automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                showsAuth = true
            } label: {
                Label("Login / Register", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding(14)
        .r34Glass(cornerRadius: 20, interactive: true)
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Account data")
                    .font(.headline)
                Spacer()
                if account.isLoading {
                    ProgressView()
                        .tint(.orange)
                }
            }

            if let error = account.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .r34Glass(cornerRadius: 20, interactive: true)
    }

    private func feedSection(title: String, subtitle: String, posts: [Rule34Post]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if posts.isEmpty {
                R34EmptyStateView(title: "Nothing here yet", systemImage: "photo.on.rectangle.angled", message: "This section will fill after the session is loaded.")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116, maximum: 150), spacing: 8)], spacing: 8) {
                    ForEach(posts.prefix(18)) { post in
                        PostTile(post: post, isFavorite: isFavorite(post), galleryQuality: .medium)
                            .onTapGesture {
                                openDetail(for: post)
                            }
                    }
                }
            }
        }
        .padding(14)
        .r34Glass(cornerRadius: 20, interactive: true)
    }

    private var authView: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Rule34AuthWebView(startURL: URL(string: "https://rule34.xxx/index.php?page=account&s=home")!) { username in
                    let clean = username?.trimmingCharacters(in: .whitespacesAndNewlines)
                    account.markAuthenticated(username: clean)
                    if let clean, !clean.isEmpty {
                        settings.accountUsername = clean
                    }
                    Task {
                        await account.refreshSession(username: clean)
                    }
                    showsAuth = false
                }
                .ignoresSafeArea()
            }
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .automatic) {
                    Button {
                        showsAuth = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                #else
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsAuth = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                #endif
            }
        }
    }

    private func openDetail(for post: Rule34Post) {
        Task {
            var fullPost = post
            if post.fileURL == nil,
               let userID = cleanedUserID,
               let apiKey = cleanedAPIKey,
               !userID.isEmpty,
               !apiKey.isEmpty,
               let resolved = try? await api.fetchPost(id: post.id, userID: userID, apiKey: apiKey) {
                fullPost = resolved
            }
            await MainActor.run {
                selectedPost = fullPost
            }
        }
    }

    private func isFavorite(_ post: Rule34Post) -> Bool {
        localFavorites.contains(where: { $0.hasSameIdentity(as: post) })
    }

    private func toggleFavorite(_ post: Rule34Post) {
        if let index = localFavorites.firstIndex(where: { $0.hasSameIdentity(as: post) }) {
            localFavorites.remove(at: index)
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
                sourceMode: settings.searchSourceMode
            )
            localFavorites.insert(postWithSource, at: 0)
        }
        favoritesStore.save(localFavorites)
    }

    private var cleanedUserID: String? {
        let value = settings.userID.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var cleanedAPIKey: String? {
        let value = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
