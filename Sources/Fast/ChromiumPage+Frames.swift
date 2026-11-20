import AppKit
import YabCoreClient

/// What a page in the bench's room was last told to draw at, by which
/// helper: a helper started again names its tabs from tab-1 again.
@MainActor
final class ChromiumFrames {
    struct Sent: Equatable { let remote: String; let helper: UUID; let interval: Int }
    var resting = false
    var sent: Sent?

    /// What to send now, or nothing. A helper without CEF 0137 is never sent
    /// anything, and a page it has just made draws at the display's rate.
    nonisolated static func next(interval: Int, capable: Bool, remote: String, helper: UUID, sent: Sent?) -> Sent? {
        guard capable else { return nil }
        let before = sent.flatMap { $0.remote == remote && $0.helper == helper ? $0 : nil }
        guard interval != before?.interval ?? 0 else { return nil }
        return Sent(remote: remote, helper: helper, interval: interval)
    }
}

/// An agent's page in the bench's room, between its agent's calls, draws at
/// most 30 times a second, the rate Chrome's Energy Saver gives every page,
/// and is still shown to itself: animation frames, timers and observers go on,
/// fewer frames are drawn. The room lies on no screen, so Chrome paced it by
/// the main display: 240 a second on a 240 Hz monitor, where an animated page
/// there cost its GPU process 37% of a core, its renderer 18% and the window
/// server 14% (2026-11-19). A call that names the page, or the stage taking
/// it, brings it back to the display's rate before anything else is sent.
extension ChromiumPage: PageFramePace {
    nonisolated static let restingInterval = 33

    /// A video of the page in picture in picture is someone's to watch, and
    /// its frame sink is the page's child: slowing the page would slow it.
    nonisolated static func frameInterval(resting: Bool, inRoom: Bool, pictureInPicture: Bool = false) -> Int {
        resting && inRoom && !pictureInPicture ? restingInterval : 0
    }

    var restsFrames: Bool {
        get { frames.resting }
        // Sent only when it changes (ChromiumFrames.next), so asking each time
        // the bench looks again also sends what a failed request didn't.
        set {
            frames.resting = newValue
            paceFrames()
        }
    }

    /// A new page in the helper draws at the display's rate until told
    /// otherwise; one told nothing yet is told only to slow down. A request
    /// that fails leaves what was sent before, and the bench's next call,
    /// or a change of stage or room, sends again.
    func paceFrames() {
        guard let remote = remoteID, !retired, ChromiumProcess.shared.connectedClient != nil else { return }
        let interval = Self.frameInterval(resting: frames.resting, inRoom: window?.identifier == Bench.roomID,
                                          pictureInPicture: videoPiP != nil)
        guard let sent = ChromiumFrames.next(interval: interval, capable: ChromiumProcess.shared.pacesFrames, remote: remote,
                                             helper: ChromiumProcess.shared.connectionGeneration, sent: frames.sent) else { return }
        let before = frames.sent
        frames.sent = sent
        queueFrames { [weak self] core, id in
            guard id == remote else { return }
            do {
                _ = try await core.request("tab.frames", params: ["tab": .string(id), "interval": .number(Double(interval))])
            } catch {
                DebugLog.note("chromium.frames", ["error": error.localizedDescription, "interval": interval])
                if let self, self.frames.sent == sent { self.frames.sent = before }
            }
        }
    }
}
