import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    enum Tab: Hashable {
        case search
        case favorites
        case downloads
        case profile
        case settings
    }

    @Published var selectedTab: Tab = .search
    @Published var pendingSearchTag: String?

    func openSearch(tag: String) {
        pendingSearchTag = tag
        selectedTab = .search
    }
}
