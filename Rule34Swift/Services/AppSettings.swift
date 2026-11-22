import Foundation
import Combine

enum MediaQuality: String, CaseIterable, Codable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var displayName: String {
        NSLocalizedString(rawValue, comment: "Media quality")
    }
}

enum Rule34SourceMode: String, CaseIterable, Codable {
    case api = "API"
    case booru = "rule34.xxx"

    var displayName: String {
        rawValue
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var userID: String {
        didSet { KeychainStore.set(userID, for: Keys.userID) }
    }

    @Published var apiKey: String {
        didSet { KeychainStore.set(apiKey, for: Keys.apiKey) }
    }

    @Published var blacklist: String {
        didSet { UserDefaults.standard.set(blacklist, forKey: Keys.blacklist) }
    }

    @Published var hideAI: Bool {
        didSet { UserDefaults.standard.set(hideAI, forKey: Keys.hideAI) }
    }

    @Published var galleryQuality: MediaQuality {
        didSet {
            UserDefaults.standard.set(galleryQuality.rawValue, forKey: Keys.galleryQuality)
        }
    }

    @Published var fullViewQuality: MediaQuality {
        didSet {
            UserDefaults.standard.set(fullViewQuality.rawValue, forKey: Keys.fullViewQuality)
        }
    }

    @Published var privacyBlurEnabled: Bool {
        didSet { UserDefaults.standard.set(privacyBlurEnabled, forKey: Keys.privacyBlurEnabled) }
    }

    @Published var appLockEnabled: Bool {
        didSet { UserDefaults.standard.set(appLockEnabled, forKey: Keys.appLockEnabled) }
    }

    @Published var searchSourceMode: Rule34SourceMode {
        didSet { UserDefaults.standard.set(searchSourceMode.rawValue, forKey: Keys.searchSourceMode) }
    }

    @Published var accountUsername: String? {
        didSet {
            UserDefaults.standard.set(accountUsername, forKey: Keys.accountUsername)
        }
    }

    var hasCredentials: Bool {
        !userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        userID = Self.loadCredential(keychainKey: Keys.userID, legacyDefaultsKey: Keys.userID)
        apiKey = Self.loadCredential(keychainKey: Keys.apiKey, legacyDefaultsKey: Keys.apiKey)
        blacklist = UserDefaults.standard.string(forKey: Keys.blacklist) ?? ""
        hideAI = UserDefaults.standard.object(forKey: Keys.hideAI) as? Bool ?? true

        if let galleryRaw = UserDefaults.standard.string(forKey: Keys.galleryQuality),
           let quality = MediaQuality(rawValue: galleryRaw) {
            galleryQuality = quality
        } else {
            galleryQuality = .medium
        }

        if let fullViewRaw = UserDefaults.standard.string(forKey: Keys.fullViewQuality),
           let quality = MediaQuality(rawValue: fullViewRaw) {
            fullViewQuality = quality
        } else {
            fullViewQuality = .high
        }

        privacyBlurEnabled = UserDefaults.standard.object(forKey: Keys.privacyBlurEnabled) as? Bool ?? false
        appLockEnabled = UserDefaults.standard.object(forKey: Keys.appLockEnabled) as? Bool ?? false
        if let sourceRaw = UserDefaults.standard.string(forKey: Keys.searchSourceMode),
           let source = Rule34SourceMode(rawValue: sourceRaw) {
            searchSourceMode = source
        } else {
            searchSourceMode = .booru
        }
        accountUsername = UserDefaults.standard.string(forKey: Keys.accountUsername)
    }

    func clearCredentials() {
        userID = ""
        apiKey = ""
        KeychainStore.delete(Keys.userID)
        KeychainStore.delete(Keys.apiKey)
        UserDefaults.standard.removeObject(forKey: Keys.userID)
        UserDefaults.standard.removeObject(forKey: Keys.apiKey)
    }

    private static func loadCredential(keychainKey: String, legacyDefaultsKey: String) -> String {
        let stored = KeychainStore.string(for: keychainKey)
        if !stored.isEmpty {
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
            return stored
        }

        guard let legacy = UserDefaults.standard.string(forKey: legacyDefaultsKey), !legacy.isEmpty else { return "" }
        if KeychainStore.set(legacy, for: keychainKey) {
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        }
        return legacy
    }

    func clearAccountSession() {
        accountUsername = nil
        UserDefaults.standard.removeObject(forKey: Keys.accountUsername)
    }
}

private enum Keys {
    static let userID = "rule34.userID"
    static let apiKey = "rule34.apiKey"
    static let blacklist = "rule34.blacklist"
    static let hideAI = "rule34.hideAI"
    static let galleryQuality = "rule34.galleryQuality"
    static let fullViewQuality = "rule34.fullViewQuality"
    static let privacyBlurEnabled = "rule34.privacyBlurEnabled"
    static let appLockEnabled = "rule34.appLockEnabled"
    static let searchSourceMode = "rule34.searchSourceMode"
    static let accountUsername = "rule34.accountUsername"
}
