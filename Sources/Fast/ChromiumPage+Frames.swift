import AppKit
import YabCoreClient

/// What a page in the bench's room was last told to draw at.
@MainActor
final class ChromiumFrames {
    var resting = false
    var sent: (remote: String, interval: Int)?
    var sending: Task<Void, Never>?
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

    nonisolated static func frameInterval(resting: Bool, inRoom: Bool) -> Int {
        resting && inRoom ? restingInterval : 0
    }

    var restsFrames: Bool {
        get { frames.resting }
        set {
            guard newValue != frames.resting else { return }
            frames.resting = newValue
            paceFrames()
        }
    }

    /// A new page in the helper draws at the display's rate until told
    /// otherwise; one told nothing yet is told only to slow down.
    func paceFrames() {
        guard let remote = remoteID, !retired, ChromiumProcess.shared.pacesFrames,
              let core = ChromiumProcess.shared.connectedClient else { return }
        let interval = Self.frameInterval(resting: frames.resting, inRoom: window?.identifier == Bench.roomID)
        let before = frames.sent?.remote == remote ? frames.sent : nil
        guard interval != before?.interval ?? 0 else { return }
        frames.sent = (remote, interval)
        // In order: a slow-down sent after the wake-up would keep a working page slow.
        let previous = frames.sending
        frames.sending = Task { @MainActor [weak self] in
            await previous?.value
            guard ChromiumProcess.shared.isCurrent(core) else { return }
            do {
                _ = try await core.request("tab.frames", params: ["tab": .string(remote), "interval": .number(Double(interval))])
            } catch {
                DebugLog.note("chromium.frames", ["error": error.localizedDescription, "interval": interval])
                if let self, self.frames.sent?.remote == remote, self.frames.sent?.interval == interval { self.frames.sent = before }
            }
        }
    }
}
