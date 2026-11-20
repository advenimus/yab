import AppKit
import Testing
@testable import Fast

@MainActor
@Suite(.serialized)
struct BenchPaceTests {
    // Held for the whole suite: a released object's address, and so its
    // identifier, can come back for the next one.
    private static let keys = (0..<4).map { _ in Key() }
    private final class Key {}
    private func key(_ index: Int) -> ObjectIdentifier { ObjectIdentifier(Self.keys[index]) }

    @Test func aPageNamedByACallDrawsFullyUntilTheCallEnds() {
        var pace = BenchPace()
        let page = key(0)
        pace.began(); pace.names(page); pace.woke(page)
        #expect(pace.awake(page))
        pace.ended(naming: page)
        #expect(!pace.awake(page))
    }

    @Test func aPageNamedByTwoCallsRestsOnlyAfterBoth() {
        var pace = BenchPace()
        let page = key(0)
        pace.began(); pace.names(page)
        pace.began(); pace.names(page)
        pace.ended(naming: page)
        #expect(pace.awake(page))
        pace.ended(naming: page)
        #expect(!pace.awake(page) && pace.calls == 0)
    }

    @Test func aPageOpenedByACallThatNamedNoneDrawsFullyUntilNoCallIsInFlight() {
        var pace = BenchPace()
        let opened = key(0), other = key(1)
        pace.began()
        pace.woke(opened)
        pace.began(); pace.names(other)
        #expect(pace.awake(opened) && pace.awake(other))
        pace.ended(naming: nil)
        #expect(pace.awake(opened), "another call is still in flight")
        pace.ended(naming: other)
        #expect(!pace.awake(opened) && !pace.awake(other))
        pace.began(); pace.names(other)
        #expect(!pace.awake(opened), "a later call about another page does not wake it")
    }

    @Test func aPageWokenWithNoCallInFlightRestsAtOnce() {
        var pace = BenchPace()
        let page = key(0)
        pace.woke(page)
        #expect(!pace.awake(page))
        pace.began()
        #expect(!pace.awake(page))
    }

    @Test func aCallAboutOnePageLeavesTheOthersResting() {
        var pace = BenchPace()
        let a = key(0), b = key(1)
        pace.woke(b)
        pace.began(); pace.names(a); pace.woke(a)
        #expect(pace.awake(a) && !pace.awake(b))
    }

    @Test func aRestedPageIsForgotten() {
        var pace = BenchPace()
        let page = key(0)
        pace.began(); pace.woke(page)
        pace.forget(page)
        #expect(!pace.awake(page))
    }

    @Test func aHelperWithoutThePatchIsSentNothing() {
        let helper = UUID()
        for interval in [0, ChromiumPage.restingInterval] {
            #expect(ChromiumFrames.next(interval: interval, capable: false, remote: "tab-1", helper: helper, sent: nil) == nil)
        }
    }

    @Test func aPageIsToldOnlyWhatChanges() {
        let helper = UUID(), slow = ChromiumPage.restingInterval
        #expect(ChromiumFrames.next(interval: 0, capable: true, remote: "tab-1", helper: helper, sent: nil) == nil,
                "a new page draws at the display's rate already")
        let rested = ChromiumFrames.next(interval: slow, capable: true, remote: "tab-1", helper: helper, sent: nil)
        #expect(rested?.interval == slow)
        #expect(ChromiumFrames.next(interval: slow, capable: true, remote: "tab-1", helper: helper, sent: rested) == nil)
        #expect(ChromiumFrames.next(interval: 0, capable: true, remote: "tab-1", helper: helper, sent: rested)?.interval == 0)
    }

    @Test func aRestartedHelpersPageWithTheSameNameIsToldAgain() {
        let slow = ChromiumPage.restingInterval
        let old = ChromiumFrames.Sent(remote: "tab-1", helper: UUID(), interval: slow)
        #expect(ChromiumFrames.next(interval: slow, capable: true, remote: "tab-1", helper: UUID(), sent: old)?.interval == slow)
    }

    @Test func onlyARestingPageInTheRoomIsPaced() {
        #expect(ChromiumPage.frameInterval(resting: true, inRoom: true) == ChromiumPage.restingInterval)
        #expect(ChromiumPage.frameInterval(resting: true, inRoom: false) == 0)
        #expect(ChromiumPage.frameInterval(resting: false, inRoom: true) == 0)
        #expect(ChromiumPage.restingInterval > 0 && ChromiumPage.restingInterval <= 1000)
    }
}
