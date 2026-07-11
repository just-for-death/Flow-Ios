import XCTest
@testable import Flow

final class NavTabManagerTests: XCTestCase {

    func testDefaultOrderHasSevenTabs() {
        XCTAssertEqual(NavTabManager.defaultOrder.count, 7)
    }

    func testExploreTabIndexMatchesAndroid() {
        XCTAssertEqual(NavTab.explore.rawValue, 6)
    }

    func testMoveTabReorders() {
        let nav = NavTabManager.shared
        let original = nav.tabOrder
        let savedShorts = nav.shortsNavigationEnabled
        defer {
            nav.tabOrder = original
            nav.shortsNavigationEnabled = savedShorts
        }
        nav.tabOrder = [0, 1, 2, 3, 4, 5, 6]
        nav.shortsNavigationEnabled = false
        nav.moveTab(.music, direction: -1)
        XCTAssertEqual(nav.enabledTabs().first, .music)
        XCTAssertEqual(nav.enabledTabs()[1], .home)
    }

    func testDefaultTabFallsBackWhenDisabled() {
        let nav = NavTabManager.shared
        let savedDefault = nav.defaultTabIndex
        let savedShorts = nav.shortsNavigationEnabled
        defer {
            nav.defaultTabIndex = savedDefault
            nav.shortsNavigationEnabled = savedShorts
        }
        nav.defaultTabIndex = NavTab.shorts.rawValue
        nav.shortsNavigationEnabled = false
        XCTAssertNotEqual(nav.defaultTab(), .shorts)
    }

    func testOverflowWhenManyTabsEnabled() {
        let nav = NavTabManager.shared
        let savedShorts = nav.shortsNavigationEnabled
        let savedMusic = nav.musicNavigationEnabled
        let savedSearch = nav.searchNavTabEnabled
        let savedExplore = nav.categoriesNavigationEnabled
        defer {
            nav.shortsNavigationEnabled = savedShorts
            nav.musicNavigationEnabled = savedMusic
            nav.searchNavTabEnabled = savedSearch
            nav.categoriesNavigationEnabled = savedExplore
        }
        nav.shortsNavigationEnabled = true
        nav.musicNavigationEnabled = true
        nav.searchNavTabEnabled = true
        nav.categoriesNavigationEnabled = true
        XCTAssertGreaterThan(nav.enabledTabs().count, NavTabManager.maxVisibleTabs)
        XCTAssertFalse(nav.overflowTabs().isEmpty)
    }
}

final class FlowDatabasePlaylistTests: XCTestCase {

    func testCreateRenameDeletePlaylist() {
        let db = FlowDatabase.shared
        let pl = db.createPlaylist(title: "Test List")
        XCTAssertEqual(db.userPlaylists().first(where: { $0.syncId == pl.syncId })?.title, "Test List")
        db.renamePlaylist(syncId: pl.syncId, title: "Renamed")
        XCTAssertEqual(db.playlists[pl.syncId]?.title, "Renamed")
        db.deletePlaylist(syncId: pl.syncId)
        XCTAssertTrue(db.playlists[pl.syncId]?.deleted == true)
    }

    func testAddAndRemovePlaylistItem() {
        let db = FlowDatabase.shared
        let pl = db.createPlaylist(title: "Items")
        let item = CanonicalPlaylistItem(videoId: "abc", title: "Vid", hlc: "1")
        db.addToPlaylist(syncId: pl.syncId, item: item)
        XCTAssertEqual(db.playlists[pl.syncId]?.items.filter { !$0.deleted }.count, 1)
        db.removeFromPlaylist(syncId: pl.syncId, videoId: "abc")
        XCTAssertEqual(db.playlists[pl.syncId]?.items.filter { !$0.deleted }.count, 0)
        XCTAssertEqual(db.playlists[pl.syncId]?.items.count, 1) // soft-deleted tombstone retained
        db.deletePlaylist(syncId: pl.syncId)
    }
}

final class FlowAppIconTests: XCTestCase {

    func testAndroidSuffixMapping() {
        XCTAssertEqual(FlowAppIcon.flowLight.androidSuffix, ".IconFlowLight")
        XCTAssertEqual(FlowAppIcon.fromStored(".IconAmoled"), .amoled)
    }

    func testSyncQueueAutoplaySeparateKey() {
        let entry = SyncSettingsMapper.whitelist.first { $0.canonical == "queue_autoplay" }
        XCTAssertEqual(entry?.iosKey, "queue_autoplay_enabled")
        let autoplay = SyncSettingsMapper.whitelist.first { $0.canonical == "autoplay" }
        XCTAssertEqual(autoplay?.iosKey, "autoplay_enabled")
        XCTAssertNotEqual(entry?.iosKey, autoplay?.iosKey)
    }

    func testSyncWhitelistIncludesSponsorActions() {
        XCTAssertNotNil(SyncSettingsMapper.whitelist.first { $0.canonical == "sponsorblock_action_sponsor" })
        XCTAssertNotNil(SyncSettingsMapper.whitelist.first { $0.canonical == "subscriptions_show_shorts" })
    }
}
