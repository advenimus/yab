import AppKit
import Foundation
import SyncKit
import Testing
@testable import Fast

/// History kept a place without its port, so every server on localhost was
/// one place: "local" offered one row going to whichever server made it
/// first (localhost:3005, 8 pages), not localhost:3000 (707). Arc lists a
/// row for each port and finishes "local" as localhost:3000. A port that
/// isn't the scheme's own is now part of the key.
@MainActor @Suite(.serialized)
struct HistoryPortKeysTests {
    private let now = Date()

    @Test(arguments: [
        ("http://localhost:3000/", "localhost:3000"),
        ("http://localhost:3000/workspace/pika?x=1#y", "localhost:3000/workspace/pika"),
        ("http://LocalHost:4000/Dashboard", "localhost:4000/dashboard"),
        ("http://localhost/", "localhost"),
        ("http://localhost:80/a", "localhost/a"),
        ("https://www.example.com:443/", "example.com"),
        ("https://example.com:8443/", "example.com:8443"),
        ("http://example.com:443/", "example.com:443"),
        ("http://[::1]:5173/app", "[::1]:5173/app"),
        ("http://192.168.1.5:8080/", "192.168.1.5:8080"),
        ("https://github.com/notifications", "github.com/notifications"),
    ])
    func theKeyKeepsAPortOfItsOwn(_ address: String, _ key: String) throws {
        let url = try #require(URL(string: address))
        #expect(History.key(for: url) == key)
        // Sync's key, the iPhone's too, is the same.
        #expect(SyncVisit.key(url) == key)
    }

    @Test func eachServerIsAPlaceOfItsOwn() throws {
        let history = History([])
        for _ in 0..<5 { history.record(URL(string: "http://localhost:3000/workspace/pika")!, title: "Pika") }
        history.record(URL(string: "http://localhost:4000/dashboard")!, title: "Muzekit")
        history.record(URL(string: "http://localhost:3005/blog")!, title: "Blog")
        let rows = history.suggestions(for: "local", limit: 10, now: now)
        let roots = rows.filter { !$0.key.contains("/") }
        #expect(roots.first?.key == "localhost:3000")
        #expect(roots.first?.url == URL(string: "http://localhost:3000/"))
        #expect(Set(roots.map(\.key)) == ["localhost:3000", "localhost:4000", "localhost:3005"])
        // Finished as Arc finishes it, port and all.
        #expect(history.completion(for: "local", among: rows) == "host:3000")
        // Its port typed picks the server.
        #expect(history.suggestions(for: "localhost:4", now: now).first?.key == "localhost:4000")
    }

    /// A history written before: each port's pages under its own key, and
    /// the one row they all shared split by its pages' visits, the visits
    /// to the row itself staying with the server it went to.
    @Test func anOlderHistoryGetsItsPorts() throws {
        let old = Date(timeIntervalSinceNow: -3_600)
        let list = [
            Visit(url: "http://localhost:3005/", key: "localhost", title: "Rishi", count: 40, last: old, typed: 3),
            Visit(url: "http://localhost:3000/workspace/pika", key: "localhost/workspace/pika", title: "Pika", count: 25, last: old),
            Visit(url: "http://localhost:3000/get-started", key: "localhost/get-started", title: "Start", count: 5, last: old),
            Visit(url: "http://localhost:4000/dashboard", key: "localhost/dashboard", title: "Muzekit", count: 6, last: old),
            Visit(url: "http://localhost:3005/blog", key: "localhost/blog", title: "Blog", count: 2, last: old),
            Visit(url: "https://github.com/", key: "github.com", title: "GitHub", count: 9, last: old),
        ]
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("history-ports-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try JSONEncoder().encode(list).write(to: file)
        let history = History(file: file)
        let places = history.places
        #expect(places["localhost"] == nil)
        #expect(places["localhost/workspace/pika"] == nil)
        #expect(places["localhost:3000/workspace/pika"]?.count == 25)
        #expect(places["localhost:4000/dashboard"]?.count == 6)
        // 40 on the shared row: 30 + 6 + 2 were its pages', 2 its own.
        #expect(places["localhost:3000"]?.count == 30)
        #expect(places["localhost:4000"]?.count == 6)
        #expect(places["localhost:3005"]?.count == 4)
        #expect(places["localhost:3005"]?.typed == 3)
        #expect(places["localhost:3005"]?.title == "Rishi")
        #expect(places["localhost:3000"]?.url == "http://localhost:3000/")
        // Nothing without a port moves.
        #expect(places["github.com"]?.count == 9)
        #expect(places.values.allSatisfy { $0.key == History.key(for: URL(string: $0.url)!) })
        #expect(history.suggestions(for: "local", now: now).first?.key == "localhost:3000")
    }

    /// The shared row went to the scheme's own port (http://localhost/):
    /// it stays, less the visits its pages on other ports made.
    @Test func aSharedRowOnTheSchemesPortStays() throws {
        var visits: [String: Visit] = [
            "localhost": Visit(url: "http://localhost/", key: "localhost", title: "", count: 12, last: now),
            "localhost/app": Visit(url: "http://localhost:5173/app", key: "localhost/app", title: "App", count: 10, last: now),
        ]
        #expect(History.keyPorts(&visits))
        #expect(visits["localhost"]?.count == 2)
        #expect(visits["localhost:5173"]?.count == 10)
        #expect(visits["localhost:5173/app"]?.count == 10)
        // Run again, nothing is left to move.
        #expect(!History.keyPorts(&visits))
    }

    /// Pages brought in from another browser count more than the row
    /// they never reached: the row's visits are shared out by them, and
    /// the host counts for no more than it did, beside other sites.
    @Test func aRowCountsForNoMoreThanItDid() throws {
        var visits: [String: Visit] = [
            "localhost": Visit(url: "http://localhost:3005/", key: "localhost", title: "", count: 100, last: now),
            "localhost/a": Visit(url: "http://localhost:3000/a", key: "localhost/a", title: "A", count: 900, last: now),
            "localhost/b": Visit(url: "http://localhost:4000/b", key: "localhost/b", title: "B", count: 100, last: now),
        ]
        #expect(History.keyPorts(&visits))
        #expect(visits["localhost:3000"]?.count == 90)
        #expect(visits["localhost:4000"]?.count == 10)
        #expect(visits["localhost:3005"]?.count == 0)
        let rows = ["localhost:3000", "localhost:4000", "localhost:3005"].compactMap { visits[$0]?.count }
        #expect(rows.reduce(0, +) == 100)
    }

    /// In the field: "local" leads with the busiest server, finished with
    /// its port, and Return's row goes there.
    @Test func theFieldFinishesThePort() throws {
        _ = NSApplication.shared
        let browser = Browser(windowID: UUID())
        let tab = Tab(later: .nonPersistent())
        tab.restore(url: URL(string: "https://fixture.example/")!, title: "Fixture")
        browser.lay([tab])
        browser.activeID = nil
        let suggest = browser.prefs.searchSuggest
        browser.prefs.searchSuggest = false
        let history = History([])
        for _ in 0..<5 { history.record(URL(string: "http://localhost:3000/workspace/pika")!, title: "Pika") }
        history.record(URL(string: "http://localhost:3005/blog")!, title: "Blog")
        browser.history = history
        browser.openFresh()
        defer {
            tab.close(); browser.dismiss(); browser.letGo()
            browser.prefs.searchSuggest = suggest
            if let id = browser.windowID { try? FileManager.default.removeItem(at: Store.file("session-window-\(id.uuidString).json")) }
        }
        browser.replaceTyped("local")
        #expect(browser.ending == "host:3000")
        #expect(browser.query.lead == 0)
        #expect(browser.offers.first?.url == URL(string: "http://localhost:3000/"))
        #expect(Address.url(from: "local" + (browser.ending ?? "")) == URL(string: "http://localhost:3000"))
    }
}
