import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct Rule34MacApp: App {
    @StateObject private var settings = AppSettings()
    @State private var cacheSize = "Calculating…"

    var body: some Scene {
        WindowGroup {
            MacContentView(settings: settings)
                .preferredColorScheme(.dark)
                .frame(minWidth: 760, minHeight: 620)
                .task { updateCacheSize() }
        }
        .defaultSize(width: 1440, height: 920)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandMenu("Cache") {
                Text("Cache: \(cacheSize)")
                    .onAppear { updateCacheSize() }
                Button("Refresh cache size") { updateCacheSize() }
                Button("Clear Cache") { Task { await ImageCacheStore.shared.clear(); updateCacheSize() } }
            }
        }
        Settings {
            MacSettingsView(settings: settings, importFavorites: importFavorites, exportFavorites: exportFavorites)
                .frame(width: 620, height: 740)
                .preferredColorScheme(.dark)
        }
    }

    private func updateCacheSize() {
        Task {
            let bytes = await ImageCacheStore.shared.folderSizeBytes()
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            cacheSize = formatter.string(fromByteCount: bytes)
        }
    }

    private func importFavorites() {
        let panel = NSOpenPanel()
        panel.title = "Import favorites"
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let count = try FavoritesStore().importFavorites(from: Data(contentsOf: url))
            showTransferResult(
                title: "Import complete",
                message: count == 0 ? "All favorites from this file are already in your collection." : "Imported \(count) favorites."
            )
        } catch {
            showTransferResult(title: "Import failed", message: error.localizedDescription)
        }
    }

    private func exportFavorites() {
        let panel = NSSavePanel()
        panel.title = "Export favorites"
        panel.nameFieldStringValue = "Rule34Swift_favorites.json"
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try FavoritesStore().exportFavoritesData().write(to: url, options: .atomic)
            showTransferResult(title: "Export complete", message: "Favorites were saved to the selected JSON file.")
        } catch {
            showTransferResult(title: "Export failed", message: error.localizedDescription)
        }
    }

    private func showTransferResult(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private struct MacSettingsView: View {
    @ObservedObject var settings: AppSettings
    let importFavorites: () -> Void
    let exportFavorites: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.055, green: 0.065, blue: 0.095), Color(red: 0.025, green: 0.03, blue: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 13) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Settings").font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            Text("Personalize your Rule34Swift client")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.48))
                        }
                        Spacer()
                    }
                    .padding(.bottom, 2)

                    MacSettingsCard(title: "Rule34 connection", subtitle: "Choose the search source and API credentials.", symbol: "network") {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 7) {
                                settingsLabel("Search source")
                                Picker("Search source", selection: $settings.searchSourceMode) {
                                    ForEach(Rule34SourceMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                                }
                                .pickerStyle(.segmented)
                            }
                            HStack(spacing: 12) {
                                settingsInputLabel("User ID")
                                TextField("Enter your user ID", text: $settings.userID)
                                    .textFieldStyle(.plain)
                                    .settingsInputSurface()
                            }
                            VStack(alignment: .leading, spacing: 7) {
                                settingsLabel("API key")
                                SecureField("Enter your API key", text: $settings.apiKey)
                                    .textFieldStyle(.plain)
                                    .settingsInputSurface()
                                Label("Stored securely in the system Keychain", systemImage: "key.horizontal")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.42))
                            }
                            VStack(alignment: .leading, spacing: 7) {
                                settingsLabel("Blacklist tags")
                                TextEditor(text: $settings.blacklist)
                                    .font(.system(size: 12))
                                    .scrollContentBackground(.hidden)
                                    .frame(height: 66)
                                    .settingsInputSurface()
                                Text("Separate tags with spaces or commas.")
                                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                            }
                            settingsToggle("Hide AI posts", detail: "Apply the site’s AI filter to gallery results.", isOn: $settings.hideAI)
                        }
                    }

                    MacSettingsCard(title: "Image quality", subtitle: "Set the quality separately for thumbnails and the viewer.", symbol: "photo") {
                        VStack(spacing: 12) {
                            qualityPickerRow("Gallery", detail: "Preview images", selection: $settings.galleryQuality)
                            Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
                            qualityPickerRow("Viewer", detail: "Opened posts", selection: $settings.fullViewQuality)
                        }
                    }

                    MacSettingsCard(title: "Saved posts", subtitle: "Move your collection between app installs.", symbol: "heart") {
                        HStack(spacing: 10) {
                            Button(action: importFavorites) {
                                Label("Import JSON…", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            Button(action: exportFavorites) {
                                Label("Export JSON…", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.white.opacity(0.2))
                        }
                    }
                }
                .padding(24)
                .padding(.top, 18)
                .padding(.bottom, 24)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
                .background(SettingsScrollWheelMonitor())
            }
        }
        .tint(.white)
    }

    private func settingsLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(1.05)
            .foregroundStyle(.white.opacity(0.44))
    }

    private func settingsInputLabel(_ title: String) -> some View {
        settingsLabel(title).frame(width: 76, alignment: .leading)
    }

    private func qualityPickerRow(_ title: String, detail: String, selection: Binding<MediaQuality>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.88))
                Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.42))
            }
            Spacer()
            Picker(title, selection: selection) {
                ForEach(MediaQuality.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 250)
        }
    }

    private func settingsToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.88))
                Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.42))
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn).labelsHidden()
        }
    }
}

private struct MacSettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.92))
                    Text(subtitle).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.42))
                }
                Spacer()
            }
            content
        }
        .padding(17)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(.white.opacity(0.075), lineWidth: 1))
    }
}

private extension View {
    func settingsInputSurface() -> some View {
        self
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.09), lineWidth: 1))
    }
}

private struct SettingsScrollWheelMonitor: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SettingsPassthroughView {
        let view = SettingsPassthroughView()
        view.onWindowChange = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            coordinator?.attach(to: view)
        }
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: SettingsPassthroughView, context: Context) {
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: SettingsPassthroughView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        private weak var view: SettingsPassthroughView?
        private weak var window: NSWindow?
        private weak var scrollView: NSScrollView?
        private var eventMonitor: Any?
        private var windowObservers: [NSObjectProtocol] = []

        func attach(to view: SettingsPassthroughView) {
            self.view = view
            if window !== view.window {
                removeWindowObservers()
                window = view.window
                observeWindow(view.window)
            }
            scrollView = view.enclosingScrollView
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.route(event) ?? event
            }
        }

        func detach() {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            eventMonitor = nil
            removeWindowObservers()
            scrollView = nil
            window = nil
            view = nil
        }

        private func observeWindow(_ window: NSWindow?) {
            guard let window else { return }
            window.initialFirstResponder = view
            let center = NotificationCenter.default
            windowObservers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self, weak window] _ in
                guard let self, let window, let view = self.view else { return }
                window.initialFirstResponder = view
                window.makeFirstResponder(view)
            })
            windowObservers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self, weak window] _ in
                guard let self, let window, let view = self.view else { return }
                window.initialFirstResponder = view
                window.makeFirstResponder(view)
            })
        }

        private func removeWindowObservers() {
            for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
            windowObservers.removeAll()
        }

        private func route(_ event: NSEvent) -> NSEvent? {
            guard let view, let window = view.window, event.window === window,
                  let scrollView = view.enclosingScrollView,
                  let documentView = scrollView.documentView else { return event }

            let verticalDelta = event.scrollingDeltaY
            guard abs(verticalDelta) >= abs(event.scrollingDeltaX), verticalDelta != 0 else { return event }

            let clipView = scrollView.contentView
            var origin = clipView.bounds.origin
            let delta = event.hasPreciseScrollingDeltas ? verticalDelta : event.deltaY * 10
            origin.y += documentView.isFlipped ? -delta : delta
            let maximumY = max(0, documentView.bounds.height - clipView.bounds.height)
            origin.y = min(max(origin.y, 0), maximumY)
            clipView.scroll(to: origin)
            scrollView.reflectScrolledClipView(clipView)
            return nil
        }
    }
}

private final class SettingsPassthroughView: NSView {
    var onWindowChange: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

