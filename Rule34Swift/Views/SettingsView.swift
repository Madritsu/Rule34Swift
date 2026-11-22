import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @FocusState private var focusedField: Field?
    @State private var importMessage = ""
    @State private var showsImporter = false
    @State private var isExporting = false
    @State private var cacheSizeText = "—"
    @State private var isComputingCacheSize = false
    private let favoritesStore = FavoritesStore()

    private enum Field: Hashable {
        case userID
        case apiKey
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("API") {
                    #if os(macOS)
                    TextField("User ID", text: $settings.userID)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focusedField, equals: .userID)
                    #else
                    TextField("User ID", text: $settings.userID)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.numberPad)
                        .submitLabel(.done)
                        .focused($focusedField, equals: .userID)
                    #endif

                    SecureField("API key", text: $settings.apiKey)
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focusedField, equals: .apiKey)

                    Text("Credentials are stored in the system Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        settings.clearCredentials()
                    } label: {
                        Label("Clear saved credentials", systemImage: "key.slash")
                    }
                }

                Section("Search") {
                    Toggle("Hide AI generated", isOn: $settings.hideAI)
                }

                Section("Image Quality") {
                    Picker("Gallery preview quality", selection: $settings.galleryQuality) {
                        ForEach(MediaQuality.allCases, id: \.self) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }

                    Picker("Full view quality", selection: $settings.fullViewQuality) {
                        ForEach(MediaQuality.allCases, id: \.self) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }

                    Text("Low uses preview images, Medium uses compressed versions, High loads originals")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Privacy") {
                    Toggle("Blur in app switcher", isOn: $settings.privacyBlurEnabled)

                    #if targetEnvironment(macCatalyst) || os(macOS)
                    Toggle("Require Mac password when opening", isOn: $settings.appLockEnabled)

                    Text("The app stays locked until macOS verifies the current user with Touch ID or their password.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    #else
                    Toggle("Require Face ID when opening", isOn: $settings.appLockEnabled)

                    Text("The app stays blurred until Face ID confirms access. If Face ID is unavailable in LiveContainer, leave this turned off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    #endif
                }

                Section("Source") {
                    Picker("Search source", selection: $settings.searchSourceMode) {
                        ForEach(Rule34SourceMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("API is faster and richer. rule34.xxx uses the site itself for browsing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Favorites") {
                    Button {
                        showsImporter = true
                    } label: {
                        Label("Import favorites.json", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        exportFavorites()
                    } label: {
                        Label("Export favorites.json", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isExporting)

                    if !importMessage.isEmpty {
                        Text(importMessage)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Cache") {
                    HStack {
                        Text("Image cache")
                        Spacer()
                        if isComputingCacheSize {
                            ProgressView()
                        } else {
                            Text(cacheSizeText)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(role: .destructive) {
                        clearImageCache()
                    } label: {
                        Label("Clear image cache", systemImage: "trash")
                    }
                }

            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    if focusedField != nil {
                        Button {
                            focusedField = nil
                            dismissKeyboard()
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.title3)
                        }
                        .tint(.orange)
                    }
                }
            }
        }
        #if os(macOS) || targetEnvironment(macCatalyst)
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [UTType.json, UTType.data],
            allowsMultipleSelection: false
        ) { result in
            importFavorites(result)
        }
        #else
        .sheet(isPresented: $showsImporter) {
            FavoritesDocumentPicker { result in
                showsImporter = false
                importFavorites(result)
            }
        }
        #endif
        .onAppear {
            refreshCacheSize()
        }
    }

    private func importFavorites(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }

            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart { url.stopAccessingSecurityScopedResource() }
            }

            let data = try Data(contentsOf: url)
            let count = try favoritesStore.importFavorites(from: data)
            importMessage = count == 0
                ? NSLocalizedString("Favorites are already imported.", comment: "Import result")
                : String(format: NSLocalizedString("Imported %lld favorites.", comment: "Import result"), count)
        } catch {
            importMessage = error.localizedDescription
        }
    }

    private func exportFavorites() {
        isExporting = true
        importMessage = NSLocalizedString("Preparing export...", comment: "Export status")
        let data = favoritesStore.exportFavoritesData()

        let temp = FileManager.default.temporaryDirectory
        let fileName = "Rule34Swift_favorites.json"
        let url = temp.appendingPathComponent(fileName)

        do {
            try data.write(to: url, options: .atomic)
            importMessage = NSLocalizedString("Ready to share.", comment: "Export status")
            presentShareSheet(for: url)
        } catch {
            importMessage = error.localizedDescription
        }
        isExporting = false
    }

    private func presentShareSheet(for url: URL) {
        #if os(macOS)
        let panel = NSSharingServicePicker(items: [url])
        panel.show(relativeTo: .zero, of: NSApp.keyWindow?.contentView ?? NSView(), preferredEdge: .minY)
        #else
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return
        }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = rootViewController.view
            popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        rootViewController.present(activityVC, animated: true)
        #endif
    }

    private func refreshCacheSize() {
        guard !isComputingCacheSize else { return }
        isComputingCacheSize = true
        Task {
            let bytes = await ImageCacheStore.shared.folderSizeBytes()
            let formatted = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            await MainActor.run {
                cacheSizeText = formatted
                isComputingCacheSize = false
            }
        }
    }

    private func clearImageCache() {
        isComputingCacheSize = true
        cacheSizeText = "—"
        Task {
            await ImageCacheStore.shared.clear()
            R34ImageLoader.clearMemoryCache()
            await MainActor.run {
                isComputingCacheSize = false
            }
            refreshCacheSize()
        }
    }

}

#if canImport(UIKit) && !os(macOS)
private struct FavoritesDocumentPicker: UIViewControllerRepresentable {
    let onResult: (Result<[URL], Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.json, .data],
            asCopy: true
        )
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onResult: (Result<[URL], Error>) -> Void

        init(onResult: @escaping (Result<[URL], Error>) -> Void) {
            self.onResult = onResult
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onResult(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onResult(.success([]))
        }
    }
}
#endif
