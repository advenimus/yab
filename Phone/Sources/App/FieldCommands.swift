import Foundation

/// What the field runs by name (Words.commandRows): a key of the menu, or a
/// menu action that has no key, as the Mac's field finds both.
enum FieldCommand: Hashable, Sendable {
    case key(BrowserKey)
    case savePDF, duplicateTab, splitView, download

    static let all: [FieldCommand] = BrowserKey.all.filter(\.commandable).map { .key($0) }
        + [.savePDF, .duplicateTab, .splitView, .download]

    var token: String {
        switch self {
        case let .key(key): key.token
        default: "\(self)"
        }
    }

    init?(token: String) {
        guard let command = Self.all.first(where: { $0.token == token }) else { return nil }
        self = command
    }

    var title: String {
        switch self {
        case let .key(key): key.title
        case .savePDF: "Save as PDF"
        case .duplicateTab: "Duplicate Tab"
        case .splitView: "Split View"
        case .download: "Download"
        }
    }

    var aliases: [String] {
        switch self {
        case let .key(key): key.aliases
        case .savePDF: ["pdf", "export pdf"]
        case .duplicateTab: ["copy tab", "clone tab"]
        case .splitView: ["open in split view", "side by side"]
        case .download: ["save file", "download file"]
        }
    }

    var shortcut: String {
        if case let .key(key) = self { return key.shortcut }
        return ""
    }

    var candidate: CommandCandidate {
        CommandCandidate(token: token, title: title, aliases: aliases, shortcut: shortcut)
    }
}

extension AppModel {
    /// The menu actions the field offers now (Words.commandRows).
    var commandCandidates: [CommandCandidate] {
        let isPrivate = field.place.isPrivate
        return FieldCommand.all.filter { offers($0) && (!isPrivate || runsInPrivate($0)) }.map(\.candidate)
    }

    func offers(_ command: FieldCommand) -> Bool {
        let tab = browser.tab
        switch command {
        case let .key(key): return offers(key)
        case .savePDF: return tab != nil
        case .duplicateTab: return tab.map { !$0.isMail && $0.navigationURL != nil } ?? false
        case .splitView: return workspace.canSplit && tab.map { !$0.isMail } == true && !pageIsPrivate
        case .download: return pageDownloadable
        }
    }

    /// A private field runs nothing that leaves Private or shows what it
    /// keeps out (history, the other tabs, Split View), and acts on a page
    /// only when that page is private: with the eyes shut over an ordinary
    /// tab, that tab is not the field's.
    func runsInPrivate(_ command: FieldCommand) -> Bool {
        let page = browser.tab?.isPrivate == true
        switch command {
        case .savePDF, .duplicateTab, .download: return page
        case .splitView: return false
        case let .key(key):
            switch key {
            case .newPrivateTab, .toggleSidebar: return true
            case .newTab, .reopenTab, .allTabs, .settings, .openLocation, .nextTab, .previousTab, .tab: return false
            case .closeTab, .reload, .back, .forward, .find, .stop, .zoomIn, .zoomOut, .actualSize,
                 .reader, .copyLink, .print: return page
            }
        }
    }

    /// A command chosen in the field, once the field is gone: nothing runs
    /// from under a lock or a cover.
    func run(_ command: FieldCommand) {
        if case let .key(key) = command { return use(key) }
        guard !privateContentBlocked, !privateLock.presentsPrompt, !surfaces.settings, !surfaces.join,
              surfaces.chat == nil, !surfaces.coversChrome, offers(command), let tab = browser.tab else { return }
        switch command {
        case .key: return
        case .savePDF: savePageAsPDF()
        case .duplicateTab: duplicate(tab)
        case .splitView: newTabBeside()
        case .download: downloadPage()
        }
    }
}
