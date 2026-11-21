import XCTest
@testable import YabPhone

/// A whole document opens in the system's viewer only over the tab it was
/// asked for, in front, in use, and of the same privacy as the page in front.
@MainActor
final class DocumentViewerTests: XCTestCase {
    private var app: AppModel!

    override func setUp() {
        let tab = { (id: String) in Tab(id: id, title: id, site: id, icon: "globe", url: "about:blank") }
        let world = World(name: "document-viewer", space: "public", spaces: [
            Space(id: "public", name: "Public", emoji: "", tint: RGB(238, 233, 226),
                  today: [tab("page"), tab("other")], current: "page"),
            Space(id: "private", name: "Private", emoji: "", tint: RGB(31, 31, 34),
                  today: [tab("secret"), tab("secret.other")], current: "secret", isPrivate: true)
        ], mac: World.Mac(joined: false))
        app = AppModel(world: world, fixturesEnabled: false, privateLockEnabled: { false })
    }

    override func tearDown() { app = nil }

    private func file(isPrivate: Bool = false) -> DownloadEntry {
        DownloadEntry(id: UUID(), name: "doc.pdf", host: "127.0.0.1", size: 1, date: Date(), state: .done, isPrivate: isPrivate)
    }

    func testTheSourceInFrontOfTheSamePrivacyShowsIt() {
        XCTAssertEqual(app.browser.tab?.id, "page")
        XCTAssertTrue(app.showsDocument(file(), for: "page", appActive: true))
    }

    func testAClosedSourceTabsDocumentOnlyLands() {
        app.browser.close("other")
        XCTAssertNil(app.browser.tab("other"))
        XCTAssertFalse(app.showsDocument(file(), for: "other", appActive: true), "a gone tab's file never opens over another page")
    }

    func testAPrivateDocumentNeverOpensOverAPublicPage() {
        app.browser.close("secret")
        XCTAssertNotNil(app.browser.tab("secret.other"), "another private tab remains")
        XCTAssertFalse(app.showsDocument(file(isPrivate: true), for: "secret", appActive: true))
        XCTAssertFalse(app.showsDocument(file(isPrivate: true), for: "page", appActive: true),
                       "a private file never shows over a public page, whatever tab it names")
    }

    func testNothingOpensWhileTheAppIsAway() {
        XCTAssertFalse(app.showsDocument(file(), for: "page", appActive: false))
    }
}
