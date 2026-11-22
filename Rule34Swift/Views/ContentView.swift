import SwiftUI
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

struct ContentView: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var coordinator = AppCoordinator()
    @AppStorage("rule34.ageConfirmed") private var ageConfirmed = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isObscured = false
    @State private var isAppLocked = false
    @State private var isAuthenticating = false
    @State private var lockError: String?
    @State private var hasUnlockedOnMacThisLaunch = false
    @State private var shouldAutoAuthenticate = true
    @State private var externalImportMessage: String?
    private let showsProfileTab = false

    var body: some View {
        ZStack {
            if ageConfirmed {
                #if os(macOS)
                macOSContent
                #else
                iOSContent
                #endif
            } else {
                AgeGateView {
                    ageConfirmed = true
                }
            }
        }
        .blur(radius: isAppLocked ? 22 : 0)
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
        .overlay {
            if isAppLocked {
                appLockOverlay
            }
        }
        .task(id: ageConfirmed) {
            guard ageConfirmed else { return }
            await requestUnlockIfNeeded()
        }
        .onChange(of: settings.appLockEnabled) { enabled in
            if enabled && ageConfirmed {
                shouldAutoAuthenticate = true
                #if targetEnvironment(macCatalyst) || os(macOS)
                hasUnlockedOnMacThisLaunch = false
                #endif
                Task { await requestUnlockIfNeeded() }
            } else {
                isAppLocked = false
                lockError = nil
                hasUnlockedOnMacThisLaunch = false
                shouldAutoAuthenticate = true
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                withAnimation(.easeOut(duration: 0.25)) {
                    isObscured = false
                }
                if ageConfirmed {
                    // Re-authenticate only after the app was locked again.
                    // A successful Face ID request sets isAppLocked to false.
                    if isAppLocked && !isAuthenticating && shouldAutoAuthenticate {
                        Task { await requestUnlockIfNeeded() }
                    }
                }
            } else if newPhase == .inactive || newPhase == .background {
                withAnimation(.easeIn(duration: 0.2)) {
                    isObscured = true
                }
                #if os(iOS)
                if settings.appLockEnabled {
                    isAppLocked = true
                    shouldAutoAuthenticate = true
                }
                #endif
            }
        }
        .onOpenURL { url in
            importFavorites(from: url)
        }
        .alert("Favorites import", isPresented: Binding(
            get: { externalImportMessage != nil },
            set: { if !$0 { externalImportMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(externalImportMessage ?? "")
        }
    }

    private func importFavorites(from url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            let count = try FavoritesStore().importFavorites(from: data)
            externalImportMessage = count == 0
                ? NSLocalizedString("Favorites are already imported.", comment: "Import result")
                : String(format: NSLocalizedString("Imported %lld favorites.", comment: "Import result"), count)
        } catch {
            externalImportMessage = error.localizedDescription
        }
    }

    private var appLockOverlay: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                #if targetEnvironment(macCatalyst) || os(macOS)
                Image(systemName: "lock.laptopcomputer")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.orange)
                #else
                Image(systemName: "faceid")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.orange)
                #endif
                Text("Locked")
                    .font(.title2.bold())
                #if targetEnvironment(macCatalyst) || os(macOS)
                Text(lockError ?? NSLocalizedString("Enter your Mac password to continue", comment: "App lock"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                #else
                Text(lockError ?? NSLocalizedString("Confirm Face ID to continue", comment: "App lock"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                #endif

                if isAuthenticating {
                    ProgressView()
                        .tint(.orange)
                } else {
                    Button("Unlock") {
                        shouldAutoAuthenticate = true
                        Task { await requestUnlockIfNeeded() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
            .padding(28)
            .r34Glass(cornerRadius: 24, interactive: true)
            .padding(24)
        }
        .transition(.opacity)
    }

    @MainActor
    private func requestUnlockIfNeeded() async {
        guard settings.appLockEnabled else {
            isAppLocked = false
            return
        }
        #if targetEnvironment(macCatalyst) || os(macOS)
        guard !hasUnlockedOnMacThisLaunch else {
            isAppLocked = false
            return
        }
        #endif
        guard !isAuthenticating else { return }

        isAppLocked = true
        lockError = nil
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        #if targetEnvironment(macCatalyst) || os(macOS)
        context.localizedFallbackTitle = NSLocalizedString("Use Password", comment: "Mac authentication fallback")
        let policy = LAPolicy.deviceOwnerAuthentication
        let unavailableMessage = NSLocalizedString("macOS authentication is unavailable", comment: "App lock")
        let reason = NSLocalizedString("Unlock Rule34Swift with your Mac password", comment: "Mac authentication prompt")
        #else
        let policy = LAPolicy.deviceOwnerAuthenticationWithBiometrics
        let unavailableMessage = NSLocalizedString("Face ID is unavailable on this device", comment: "App lock")
        let reason = NSLocalizedString("Unlock your private viewer", comment: "Face ID prompt")
        #endif

        var error: NSError?
        guard context.canEvaluatePolicy(policy, error: &error) else {
            lockError = error?.localizedDescription ?? unavailableMessage
            shouldAutoAuthenticate = false
            return
        }

        do {
            let granted = try await context.evaluatePolicy(
                policy,
                localizedReason: reason
            )
            if granted {
                #if targetEnvironment(macCatalyst) || os(macOS)
                hasUnlockedOnMacThisLaunch = true
                #endif
                withAnimation(.easeOut(duration: 0.2)) {
                    isAppLocked = false
                }
            }
        } catch {
            lockError = error.localizedDescription
            shouldAutoAuthenticate = false
        }
    }

    #if os(macOS)
    private var macOSContent: some View {
        NavigationSplitView {
            List(selection: $coordinator.selectedTab) {
                Section("Browse") {
                    Label("Search", systemImage: "magnifyingglass")
                        .tag(AppCoordinator.Tab.search)
                    Label("Favorites", systemImage: "heart.fill")
                        .tag(AppCoordinator.Tab.favorites)
                }

                if showsProfileTab {
                    Section("Account") {
                        Label("Profile", systemImage: "person.crop.circle.fill")
                            .tag(AppCoordinator.Tab.profile)
                    }
                }

                Section("App") {
                    Label("Settings", systemImage: "gearshape.fill")
                        .tag(AppCoordinator.Tab.settings)
                }
            }
            .navigationTitle("Rule34Swift")
        } detail: {
            switch coordinator.selectedTab {
            case .search:
                GalleryScreen(settings: settings, coordinator: coordinator, mode: .search)
            case .favorites:
                GalleryScreen(settings: settings, coordinator: coordinator, mode: .favorites)
            case .profile:
                ProfileView(settings: settings, coordinator: coordinator)
            case .settings:
                SettingsView(settings: settings)
            }
        }
        .tint(.orange)
    }
    #endif

    private var iOSContent: some View {
        TabView(selection: $coordinator.selectedTab) {
            GalleryScreen(settings: settings, coordinator: coordinator, mode: .search)
                .tag(AppCoordinator.Tab.search)
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            GalleryScreen(settings: settings, coordinator: coordinator, mode: .favorites)
                .tag(AppCoordinator.Tab.favorites)
                .tabItem {
                    Label("Favorites", systemImage: "heart.fill")
                }

            if showsProfileTab {
                ProfileView(settings: settings, coordinator: coordinator)
                    .tag(AppCoordinator.Tab.profile)
                    .tabItem {
                        Label("Profile", systemImage: "person.crop.circle.fill")
                    }
            }

            SettingsView(settings: settings)
                .tag(AppCoordinator.Tab.settings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(.orange)
    }
}

private struct AgeGateView: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, .gray.opacity(0.45), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.orange)

                Text("Private Viewer")
                    .font(.largeTitle.bold())

                Text("This app is intended for a private local build. Continue only if you are allowed to view this content in your region.")
                    .foregroundStyle(.secondary)

                Button(action: onContinue) {
                    Label("Continue", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.orange)
            }
            .padding(22)
            .r34Glass(cornerRadius: 24, interactive: true)
            .padding(24)
        }
    }
}
