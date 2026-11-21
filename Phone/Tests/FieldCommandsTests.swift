import XCTest
import SyncKit
@testable import YabPhone

/// The menu actions the field finds by name (AGENTS.md: a menu action is
/// discoverable in the command field), keys or not, Private included.
@MainActor
final class FieldCommandsTests: XCTestCase {
    private var app: AppModel!
    private var oldMotion = false
    private let page = URL(string: "https://example.com/a")!

    override func setUpWithError() throws {
        oldMotion = Motion.disabled
        Motion.disabled = true
        app = AppModel(world: try World.load(named: "mira"), fixturesEnabled: false, privateLockEnabled: { false })
    }

    override func tearDown() {
        app = nil
        Motion.disabled = oldMotion
    }

    private func openPage(privately: Bool = false) {
        app.browser.open(PageFixtures.liveTab(for: page, isPrivate: privately), deduplicate: false)
        app.surfaces.openField(.address)
    }

    /// The command rows the field shows for the words.
    private func commands(_ words: String) -> [WordRow] {
        app.field.typed(words)
        return app.fieldRows.filter { if case .command = $0.action { true } else { false } }
    }

    private func until(_ done: () -> Bool) async throws {
        let end = Date().addingTimeInterval(3)
        while !done(), Date() < end { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(done())
    }

    private func widen() {
        app.workspace.resize(expanded: true)
        app.workspace.windowSize = CGSize(width: 1376, height: 1032)
    }

    func testActionsWithoutAKeyAreFoundByTheirNames() {
        widen()
        openPage()
        for name in ["Save as PDF", "Duplicate Tab", "Open in Split View"] {
            let rows = commands(name.lowercased())
            XCTAssertEqual(app.fieldRows.first?.action, rows.first?.action, "\(name) typed whole leads the rows")
            XCTAssertFalse(rows.isEmpty, name)
        }
    }

    func testActionsWithoutAKeyAreOfferedOnlyWhenTheyCanRun() {
        app.workspace.windowSize = CGSize(width: 800, height: 1100)
        openPage()
        XCTAssertTrue(commands("open in split view").isEmpty, "no split in a narrow window")
        let mail = Tab(id: "mail-tab", title: "Mail", site: "Mail", icon: "mail", url: "https://mail.example.com/")
        app.field.close()
        app.browser.open(mail, deduplicate: false)
        app.surfaces.openField(.address)
        XCTAssertTrue(commands("duplicate tab").isEmpty, "Mail has no page to copy")
    }

    func testDuplicateTabFromTheFieldOpensACopy() async throws {
        openPage()
        let before = app.browser.space.allTabs.count
        let row = try XCTUnwrap(commands("duplicate tab").first)
        app.choose(row)
        try await until { app.browser.space.allTabs.count == before + 1 }
        XCTAssertEqual(app.browser.tab?.navigationURL, page)
    }

    func testPrivateOffersOnlyWhatItCanRunAndRunsIt() async throws {
        widen()
        openPage(privately: true)
        XCTAssertTrue(app.field.place.isPrivate)
        for name in ["open in split view", "reopen closed tab", "show all tabs", "new tab"] {
            XCTAssertFalse(commands(name).contains { $0.title.lowercased() == name }, "\(name) leaves Private")
        }
        XCTAssertFalse(commands("reload page").isEmpty)
        let row = try XCTUnwrap(commands("duplicate tab").first)
        let before = app.browser.allTabs.filter(\.isPrivate).count
        app.choose(row)
        try await until { app.browser.allTabs.filter(\.isPrivate).count == before + 1 }
        XCTAssertEqual(app.browser.tab?.isPrivate, true, "the copy stays private")
        XCTAssertEqual(app.browser.tab?.navigationURL, page)
    }

    func testAPrivateFieldOverAnOrdinaryPageLeavesThatPageAlone() {
        openPage()
        app.field.setPrivate(true)
        XCTAssertTrue(app.field.place.isPrivate)
        for name in ["reload page", "duplicate tab", "close tab", "copy link"] {
            XCTAssertTrue(commands(name).isEmpty, "\(name) would act on the ordinary page")
        }
    }

    func testDuplicateTabOnAMacTabOpensACopyInThatRowsSpace() throws {
        let space = try XCTUnwrap(app.browser.spaces.first { !$0.isPrivate && $0.id != app.browser.spaceID }?.id)
        let synced = SyncTab(id: "AAAAAAAA-0000-4000-8000-0000000000aa", space: "mac-space",
                             url: "https://example.com/on-mac", title: "On the Mac")
        let before = app.browser.space(space)?.allTabs.count ?? 0
        app.duplicateFromMac(synced, in: space)
        XCTAssertEqual(app.browser.spaceID, space)
        XCTAssertEqual(app.browser.space(space)?.allTabs.count, before + 1)
        XCTAssertEqual(app.browser.tab?.navigationURL?.absoluteString, "https://example.com/on-mac")
        XCTAssertNotEqual(app.browser.tab?.id, synced.id, "a local copy, not the Mac's tab")
    }
}
