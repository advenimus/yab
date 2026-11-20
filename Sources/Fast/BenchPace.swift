import Foundation

/// Which pages in the bench's room draw at their display's rate. A page there
/// is drawn as if someone looked at it, so that it behaves for its agent as a
/// page in front of someone does, but no one does: between its agent's calls
/// it can draw slowly (Bench.paceRoom). It draws at the display's rate while a
/// call that names it is in flight, and so does a page woken by a call that
/// named none (`open`), until no call at all is in flight.
struct BenchPace {
    private(set) var calls = 0
    private var named: [ObjectIdentifier: Int] = [:]
    private var loose: Set<ObjectIdentifier> = []

    mutating func began() { calls += 1 }

    mutating func names(_ page: ObjectIdentifier) { named[page, default: 0] += 1 }

    mutating func ended(naming page: ObjectIdentifier?) {
        calls = max(calls - 1, 0)
        if let page, let count = named[page] { named[page] = count > 1 ? count - 1 : nil }
        if calls == 0 { loose.removeAll() }
    }

    /// The bench took the page into its room. Woken by Yab itself, with no
    /// call in flight, it is not kept awake for the next unrelated one.
    mutating func woke(_ page: ObjectIdentifier) {
        if named[page] == nil, calls > 0 { loose.insert(page) }
    }

    mutating func forget(_ page: ObjectIdentifier) { loose.remove(page) }

    func awake(_ page: ObjectIdentifier) -> Bool {
        named[page] != nil || (calls > 0 && loose.contains(page))
    }
}
