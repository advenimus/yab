import AppKit
import Foundation
import Testing
@testable import Fast

/// The cookie step's pace from a live bridge: quick while a host is open on
/// both engines or someone looks at a Chromium page, slow otherwise, and a
/// slow wait under way cut short as soon as either becomes true.
@MainActor @Suite(.serialized)
struct CookieStepPaceTests {
    private let factory = PageEngineFactory(kinds: [.chromium]) { tab, _ in ChromiumPage(tab: tab) }

    private func host(_ name: String) -> URL { URL(string: "https://\(name)-\(UUID().uuidString.prefix(8).lowercased()).test/")! }

    private func window() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    /// A registered window holding a WebKit tab on screen and a Chromium tab behind it.
    private func browser(_ window: NSWindow) -> (browser: Browser, chromium: Tab, page: ChromiumPage)? {
        _ = NSApplication.shared
        let browser = Browser(windowID: UUID())
        let web = Tab(shy: true)
        web.restore(url: URL(string: "https://shown.test/")!, title: "Shown")
        let chromium = Tab(shy: true, engine: .chromium, factory: factory)
        chromium.restore(url: URL(string: "https://behind.test/")!, title: "Behind")
        browser.prepare(web)
        browser.prepare(chromium)
        browser.lay([web, chromium])
        browser.activeID = web.id
        BrowserWindows.shared.register(window, for: browser)
        guard let page = chromium.page as? ChromiumPage else { return nil }
        return (browser, chromium, page)
    }

    private func letGo(_ browser: Browser, _ window: NSWindow) {
        for tab in browser.pagesHeld { (tab.builtPage as? ChromiumPage)?.retire(call: false, pictureInPicture: false); tab.close() }
        window.close()
        BrowserWindows.shared.forgetForTests(browser)
        browser.letGo()
        browser.dozing?.invalidate(); browser.stuck.timer?.invalidate(); browser.pressure?.cancel()
    }

    private func sight(active: Bool, windows: Bool) -> () -> Void {
        let (wasActive, wasInSight) = (ChromiumDRMCookies.appActive, ChromiumDRMCookies.windowInSight)
        ChromiumDRMCookies.appActive = { active }
        ChromiumDRMCookies.windowInSight = { _ in windows }
        return { ChromiumDRMCookies.appActive = wasActive; ChromiumDRMCookies.windowInSight = wasInSight }
    }

    /// The step's next wait once it is worked out (a restart works it out in its own turn).
    private func due(_ bridge: ChromiumDRMCookies) async throws -> TimeInterval {
        for _ in 0..<200 where bridge.stepDue == nil { try await Task.sleep(for: .milliseconds(5)) }
        return try #require(bridge.stepDue).timeIntervalSinceNow
    }

    @Test func onlyAChromiumPageOnScreenIsSeen() throws {
        let window = window()
        let made = try #require(browser(window))
        defer { letGo(made.browser, window) }
        let restore = sight(active: true, windows: true)
        defer { restore() }
        let store = made.chromium.pageStore
        func seen() -> Bool { ChromiumDRMCookies.seen(in: [made.browser], holds: { $0 === store }) }
        // Behind the WebKit tab on screen: held, not seen.
        #expect(!seen())
        // Switched to: on the stage, in the window.
        window.contentView?.addSubview(made.page)
        #expect(seen())
        made.page.isHidden = true
        #expect(!seen())
        made.page.isHidden = false
        // In a window nobody can see.
        ChromiumDRMCookies.windowInSight = { _ in false }
        #expect(!seen())
        ChromiumDRMCookies.windowInSight = { _ in true }
        // Taken off the stage again, then shown in a small window of its own.
        made.page.removeFromSuperview()
        #expect(!seen())
        let small = self.window()
        defer { small.close() }
        small.contentView?.addSubview(made.page)
        #expect(seen())
    }

    @Test func aFrameOpeningAHostOnBothEnginesCutsASlowWaitShort() async throws {
        let restore = sight(active: false, windows: false)
        defer { restore() }
        let tab = Tab(shy: true)
        let bridge = try ChromiumDRMCookies.of(tab)
        defer { ChromiumDRMCookies.retirePrivate(bridge.profile); tab.close() }
        let frame = host("frame")
        bridge.touched(frame, mainFrame: false, by: .chromium)
        bridge.keepInStep()
        #expect(try await due(bridge) > 20)
        // A WebKit page puts the same site in a frame: now open on both.
        bridge.touched(frame, mainFrame: false, by: .webKit)
        #expect(try await due(bridge) <= 3.5)
    }

    @Test func aRedirectLandingOnAHostTheOtherEngineHasCutsASlowWaitShort() async throws {
        let restore = sight(active: false, windows: false)
        defer { restore() }
        let tab = Tab(shy: true)
        let bridge = try ChromiumDRMCookies.of(tab)
        defer { ChromiumDRMCookies.retirePrivate(bridge.profile); tab.close() }
        let site = host("redirect")
        bridge.touched(site, mainFrame: false, by: .chromium)
        bridge.keepInStep()
        #expect(try await due(bridge) > 20)
        // A WebKit page's server redirect lands there: its page has no address yet.
        bridge.touched(site, by: .webKit)
        #expect(try await due(bridge) <= 3.5)
    }

    @Test func aChromiumTabSwitchedToCutsASlowWaitShort() async throws {
        let window = window()
        let made = try #require(browser(window))
        defer { letGo(made.browser, window) }
        let restore = sight(active: true, windows: true)
        defer { restore() }
        let bridge = try ChromiumDRMCookies.of(made.chromium)
        defer { ChromiumDRMCookies.retirePrivate(bridge.profile) }
        bridge.keepInStep()
        // Yab in front, its window in sight, the Chromium tab behind: slow.
        #expect(try await due(bridge) > 20)
        // The tab switched to: the stage puts its page in the window.
        window.contentView?.addSubview(made.page)
        #expect(try await due(bridge) <= 3.5)
    }
}
