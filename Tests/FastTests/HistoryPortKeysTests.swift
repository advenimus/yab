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

    /// Visits in each space are shared out as the counts are: each port's
    /// row gets its pages' visits in that space, the row the servers shared
    /// keeps what is left, and nothing is lost when a row folds into one
    /// already there.
    @Test func aSpacesVisitsAreSharedOutToo() throws {
        let a = UUID().uuidString, b = UUID().uuidString
        func here(_ count: Int) -> SpaceVisits { SpaceVisits(count: count, last: now) }
        var visits: [String: Visit] = [
            "localhost": Visit(url: "http://localhost:3105/", key: "localhost", title: "Blog home", count: 20, last: now,
                               spaces: [a: here(12), b: here(3)]),
            "localhost/a": Visit(url: "http://localhost:3000/a", key: "localhost/a", title: "A", count: 10, last: now, spaces: [a: here(8)]),
            "localhost/b": Visit(url: "http://localhost:4000/b", key: "localhost/b", title: "B", count: 4, last: now, spaces: [a: here(2), b: here(1)]),
        ]
        #expect(History.keyPorts(&visits))
        #expect(visits["localhost:3000"]?.spaces?[a]?.count == 8)
        #expect(visits["localhost:4000"]?.spaces?[a]?.count == 2)
        #expect(visits["localhost:4000"]?.spaces?[b]?.count == 1)
        #expect(visits["localhost:3105"]?.spaces?[a]?.count == 2)
        #expect(visits["localhost:3105"]?.spaces?[b]?.count == 2)
        #expect(visits["localhost:3000/a"]?.spaces?[a]?.count == 8)
    }

    /// The shared row and a page on the same server: the row folds into the
    /// one its page made, its visits in each space with it.
    @Test func aRowFoldedIntoItsServerKeepsItsSpaces() throws {
        let a = UUID().uuidString
        var visits: [String: Visit] = [
            "localhost": Visit(url: "http://localhost:3000/", key: "localhost", title: "Pika", count: 15, last: now,
                               spaces: [a: SpaceVisits(count: 15, last: now)]),
            "localhost/a": Visit(url: "http://localhost:3000/a", key: "localhost/a", title: "A", count: 10, last: now,
                                 spaces: [a: SpaceVisits(count: 10, last: now)]),
        ]
        #expect(History.keyPorts(&visits))
        #expect(visits["localhost:3000"]?.count == 15)
        #expect(visits["localhost:3000"]?.spaces?[a]?.count == 15)
        #expect(visits["localhost:3000"]?.title == "Pika")
    }

    /// Two IPv6 hosts are two hosts, colons and all: the first's own six
    /// visits to its front page stay with it, none go to the second.
    @Test func ipv6HostsDontShareVisits() throws {
        var visits: [String: Visit] = [
            "[fd00::1]": Visit(url: "http://[fd00::1]:3000/", key: "[fd00::1]", title: "", count: 10, last: now),
            "[fd00::1]/a": Visit(url: "http://[fd00::1]:3000/a", key: "[fd00::1]/a", title: "A", count: 4, last: now),
            "[fd00::2]": Visit(url: "http://[fd00::2]:4000/", key: "[fd00::2]", title: "", count: 2, last: now),
            "[fd00::2]/b": Visit(url: "http://[fd00::2]:4000/b", key: "[fd00::2]/b", title: "B", count: 2, last: now),
        ]
        #expect(History.keyPorts(&visits))
        #expect(visits["[fd00::1]:3000"]?.count == 10)
        #expect(visits["[fd00::2]:4000"]?.count == 2)
        #expect(History.bareHost("[fd00::1]:3000") == "[fd00::1]")
        #expect(History.bareHost("localhost:3000") == "localhost")
    }

    /// "Been here in this space" asks for the site's row, port and all.
    @Test func beenAtAServerOnAPort() throws {
        let space = UUID()
        let history = History([])
        history.record(URL(string: "https://example.com:8443/dashboard")!, title: "Dashboard", space: space)
        #expect(history.been(at: URL(string: "https://example.com:8443/")!, in: space))
        #expect(!history.been(at: URL(string: "https://example.com/")!, in: space))
        #expect(!history.been(at: URL(string: "https://example.com:8443/")!, in: UUID()))
    }

    /// Keeping a site out of Frequent keeps out that server only.
    @Test func keepingOneServerOutOfFrequentLeavesTheOthers() throws {
        let history = History([
            Visit(url: "https://example.com/", key: "example.com", title: "Example", count: 9, last: now),
            Visit(url: "https://example.com:8443/", key: "example.com:8443", title: "Console", count: 9, last: now),
        ])
        history.forgetFrequent("example.com")
        let keys = history.frequent(10, now: now).map(\.key)
        #expect(keys.contains("example.com:8443"))
        #expect(!keys.contains("example.com"))
    }

    /// One kept out before a port was part of a place was every server on
    /// its host: when the history is given its ports, each server's row
    /// is kept out too, by its own key.
    @Test func aSiteKeptOutBeforeKeepsItsServersOut() throws {
        let spread = History.hiddenPorts(["localhost", "news.example"],
                                         sites: ["localhost:3000", "localhost:3000/a", "localhost:4000", "github.com", "[::1]:5173"])
        #expect(spread == ["localhost", "news.example", "localhost:3000", "localhost:4000"])
        #expect(History.hiddenPorts([], sites: ["localhost:3000"]).isEmpty)
        // A server with pages and no row of its own is kept out too.
        #expect(History.hiddenPorts(["localhost"], sites: ["localhost:5000/app"]) == ["localhost", "localhost:5000"])
    }

    /// Through a load: a shared row of 1 visit and imported pages of 900
    /// and 100 on two other ports gives neither port a row, and a host kept
    /// out before still keeps both servers' pages out of Frequent.
    @Test func serversWithoutARowStayKeptOut() throws {
        var visits: [String: Visit] = [
            "localhost": Visit(url: "http://localhost:3105/", key: "localhost", title: "", count: 1, last: now),
            "localhost/a": Visit(url: "http://localhost:3000/a", key: "localhost/a", title: "A", count: 900, last: now),
            "localhost/b": Visit(url: "http://localhost:4000/b", key: "localhost/b", title: "B", count: 100, last: now),
        ]
        #expect(History.keyPorts(&visits))
        #expect(visits["localhost:4000"] == nil)
        let spread = History.hiddenPorts(["localhost"], sites: visits.keys)
        #expect(spread.isSuperset(of: ["localhost:3000", "localhost:4000", "localhost:3105"]))
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
