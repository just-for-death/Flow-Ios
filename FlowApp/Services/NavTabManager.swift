import Foundation
import Observation

// MARK: - NavTab
/// Bottom-nav destinations — indices align with Android `nav_tab_order` (0…6).
enum NavTab: Int, CaseIterable, Identifiable, Hashable {
    case home = 0
    case shorts = 1
    case music = 2
    case subscriptions = 3
    case library = 4
    case search = 5
    case explore = 6

    var id: Int { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .shorts: return "play.rectangle.on.rectangle"
        case .music: return "music.note"
        case .subscriptions: return "person.2.fill"
        case .library: return "folder.fill"
        case .search: return "magnifyingglass"
        case .explore: return "square.grid.2x2.fill"
        }
    }

    var label: String {
        switch self {
        case .home: return "Home"
        case .shorts: return "Shorts"
        case .music: return "Music"
        case .subscriptions: return "Subscriptions"
        case .library: return "Library"
        case .search: return "Search"
        case .explore: return "Explore"
        }
    }

    /// Tabs that can be hidden via settings.
    var isOptional: Bool {
        switch self {
        case .shorts, .music, .search, .explore: return true
        default: return false
        }
    }
}

// MARK: - NavTabManager
@Observable
final class NavTabManager {
    static let shared = NavTabManager()
    static let defaultOrder: [Int] = [0, 1, 2, 3, 4, 5, 6]
    static let maxVisibleTabs = 5

    private let defaults = UserDefaults.standard

    /// Bumped when nav prefs change (including sync/import writing UserDefaults directly).
    private(set) var settingsRevision = 0

    private init() {}

    func refreshFromStorage() {
        settingsRevision += 1
    }

    private func touch() {
        settingsRevision += 1
    }

    var tabOrder: [Int] {
        get {
            guard let raw = defaults.string(forKey: "nav_tab_order"), !raw.isEmpty else {
                return Self.defaultOrder
            }
            let parsed = raw.split(separator: ",").compactMap { Int($0) }
            return parsed.isEmpty ? Self.defaultOrder : parsed
        }
        set {
            let clean = newValue.filter { (0...6).contains($0) }
            defaults.set(clean.map(String.init).joined(separator: ","), forKey: "nav_tab_order")
            touch()
        }
    }

    var defaultTabIndex: Int {
        get { defaults.object(forKey: "default_nav_tab_index") as? Int ?? 0 }
        set { defaults.set(max(0, min(6, newValue)), forKey: "default_nav_tab_index"); touch() }
    }

    var shortsNavigationEnabled: Bool {
        get { defaults.object(forKey: "shorts_navigation_enabled") as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: "shorts_navigation_enabled")
            reconcileDefaultTab()
            touch()
        }
    }

    var musicNavigationEnabled: Bool {
        get { defaults.object(forKey: "music_navigation_enabled") as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: "music_navigation_enabled")
            reconcileDefaultTab()
            touch()
        }
    }

    var searchNavTabEnabled: Bool {
        get { defaults.object(forKey: "search_nav_tab_enabled") as? Bool ?? false }
        set {
            defaults.set(newValue, forKey: "search_nav_tab_enabled")
            reconcileDefaultTab()
            touch()
        }
    }

    var categoriesNavigationEnabled: Bool {
        get { defaults.object(forKey: "categories_nav_tab_enabled") as? Bool ?? false }
        set {
            defaults.set(newValue, forKey: "categories_nav_tab_enabled")
            reconcileDefaultTab()
            touch()
        }
    }

    private func reconcileDefaultTab() {
        if let tab = NavTab(rawValue: defaultTabIndex), !isEnabled(tab) {
            defaultTabIndex = (enabledTabs().first ?? .home).rawValue
        }
    }

    func isEnabled(_ tab: NavTab) -> Bool {
        switch tab {
        case .shorts: return shortsNavigationEnabled
        case .music: return musicNavigationEnabled
        case .search: return searchNavTabEnabled
        case .explore: return categoriesNavigationEnabled
        default: return true
        }
    }

    /// All enabled tabs sorted by user order.
    func enabledTabs() -> [NavTab] {
        let enabled = NavTab.allCases.filter(isEnabled)
        let orderMap = Dictionary(uniqueKeysWithValues: tabOrder.enumerated().map { ($1, $0) })
        return enabled.sorted { (orderMap[$0.rawValue] ?? Int.max) < (orderMap[$1.rawValue] ?? Int.max) }
    }

    func visibleTabs() -> [NavTab] {
        let all = enabledTabs()
        if all.count <= Self.maxVisibleTabs { return all }
        return Array(all.prefix(Self.maxVisibleTabs - 1))
    }

    func overflowTabs() -> [NavTab] {
        let all = enabledTabs()
        guard all.count > Self.maxVisibleTabs else { return [] }
        return Array(all.dropFirst(Self.maxVisibleTabs - 1))
    }

    func defaultTab() -> NavTab {
        let idx = defaultTabIndex
        if let tab = NavTab(rawValue: idx), isEnabled(tab) { return tab }
        return enabledTabs().first ?? .home
    }

    /// Reorder among enabled tabs only — disabled tabs stay in place.
    func moveTab(_ tab: NavTab, direction: Int) {
        var ordered = enabledTabs()
        guard let idx = ordered.firstIndex(of: tab) else { return }
        let targetIdx = idx + direction
        guard ordered.indices.contains(targetIdx) else { return }
        ordered.swapAt(idx, targetIdx)

        var iter = ordered.makeIterator()
        var newOrder: [Int] = []
        for raw in tabOrder {
            guard let t = NavTab(rawValue: raw) else {
                newOrder.append(raw)
                continue
            }
            if isEnabled(t) {
                newOrder.append(iter.next()?.rawValue ?? raw)
            } else {
                newOrder.append(raw)
            }
        }
        let inOrder = Set(newOrder)
        for t in ordered where !inOrder.contains(t.rawValue) {
            newOrder.append(t.rawValue)
        }
        tabOrder = newOrder
    }

    func tab(for index: Int) -> NavTab? {
        NavTab(rawValue: index)
    }
}
