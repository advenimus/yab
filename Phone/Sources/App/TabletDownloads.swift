import SwiftUI

/// The Mac's downloads button (Hoard) for the iPad: in the sidebar's foot
/// always, in the toolbar while the sidebar is away and there is something
/// to show. Its popover holds the first file's question, then the list.
/// The phone keeps these in its plate (ChromeLayer), which the iPad's
/// toolbar layout never mounts.
struct TabletDownloadsButton: View {
    @Environment(AppModel.self) private var app
    /// Only the button on screen presents, so two never stand at once.
    let active: Bool
    let id: String
    @State private var open = false

    private typealias M = Metrics.Tablet
    private var question: DownloadAsk? { app.downloads.asking(isPrivate: app.pageIsPrivate) }
    private var busy: Bool { question != nil || app.downloads.list(isPrivate: app.pageIsPrivate).contains(where: \.isRunning) }

    var body: some View {
        Button { open.toggle() } label: {
            Glyph(mac: .yabDownload, size: M.downloadIdleMark)
                .frame(width: Metrics.touch, height: Metrics.touch)
                .overlay(alignment: .topTrailing) {
                    if busy {
                        Circle().fill(Ink.unread)
                            .frame(width: M.downloadDot, height: M.downloadDot)
                            .offset(x: -M.downloadDotInset, y: M.downloadDotInset)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Downloads")
        .accessibilityValue(question != nil ? "Asking" : busy ? "Downloading" : "")
        .accessibilityIdentifier(id)
        .modifier(TabletDownloadsHost(active: active, id: id, open: $open))
    }
}

/// What makes a control the downloads' place: the list's popover and the
/// first file's question at once. The button wears it, and so does the
/// band's folded + menu in a narrow pane.
struct TabletDownloadsHost: ViewModifier {
    @Environment(AppModel.self) private var app
    /// Only the control on screen presents, so two never stand at once.
    let active: Bool
    let id: String
    @Binding var open: Bool

    private var question: DownloadAsk? { app.downloads.asking(isPrivate: app.pageIsPrivate) }

    func body(content: Content) -> some View {
        content
            .popover(isPresented: Binding(get: { active && open }, set: { open = $0 }), arrowEdge: .bottom) {
                TabletDownloadsPanel().environment(app).presentationCompactAdaptation(.popover)
            }
            // A site's first file asks at once, from wherever the button is.
            .onChange(of: question?.id, initial: true) { _, id in if id != nil { open = true } }
            .onChange(of: active) { _, shown in open = shown && question != nil }
            .onChange(of: open) { _, shown in if shown { app.downloads.seen() } }
            .onChange(of: app.workspace.downloadsShown) { _, _ in if active { open = true } }
    }
}

/// The popover's body: the question while one waits, else every file.
struct TabletDownloadsPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let isPrivate = app.pageIsPrivate
        Group {
            if let question = app.downloads.asking(isPrivate: isPrivate) {
                DownloadAskCard(ask: question)
                    .id(question.id)
                    .frame(height: Metrics.DownloadAsk.height)
                    .padding(Metrics.Tablet.downloadsInset)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Downloads").font(.system(size: Metrics.Tablet.downloadsTitleFont, weight: .semibold))
                            .padding(.horizontal, Metrics.PageMenu.inset + Metrics.Tablet.downloadsTitleInset)
                            .padding(.vertical, Metrics.Tablet.downloadsTitleVertical)
                        DownloadsBody(ink: PageMenuInk(dark: isPrivate || scheme == .dark), host: nil, isPrivate: isPrivate)
                    }
                    .padding(.top, Metrics.Tablet.downloadsInset)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: Metrics.Tablet.downloadsHeight)
            }
        }
        .frame(width: Metrics.Tablet.downloadsWidth)
        .animation(Motion.downloadAsk.current, value: app.downloads.asking(isPrivate: isPrivate)?.id)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tablet.downloads")
    }
}
