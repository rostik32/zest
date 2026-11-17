import AppKit
import OSLog
import SwiftUI
import ZestCore
import ZestUI

/// A borderless panel that floats above the terminal without taking focus, so every
/// key still goes to the shell.
final class PopupPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        level = .popUpMenu
        isFloatingPanel = true
        hidesOnDeactivate = false
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows, moves and hides the popup.
@MainActor
final class PopupController {
    let model = PopupModel()
    private let panel = PopupPanel()
    private let icons: IconResolver

    init(icons: IconResolver) {
        self.icons = icons
        let host = NSHostingView(rootView: PopupView(model: model, icons: icons))
        host.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = host
    }

    /// Called when the popup closed by itself: the terminal window closed or changed, or
    /// it changed size in a terminal whose cursor position comes from the shell. The
    /// popup stays closed until the next key, when the shell reports where it is.
    var onDismiss: (() -> Void)?

    /// The chosen theme's colors, used everywhere except in VS Code and Cursor when
    /// `matchEditor` is on.
    var basePalette = Palette.default
    var matchEditor = true
    private let editorThemes = EditorThemeCache()
    private var lastFront: NSRunningApplication?

    /// Picks the palette for the app in front: the editor's theme in VS Code and Cursor.
    func refreshPalette(for front: NSRunningApplication? = nil) {
        let app = front ?? lastFront
        var palette = basePalette
        if matchEditor, let app, let editor = EditorThemeCache.editor(for: app),
           let theme = editorThemes.theme(for: editor, onUpdate: { [weak self] in
               guard let self else { return }
               self.refreshPalette()
           }) {
            palette = Palette(theme)
        }
        if model.palette != palette { model.palette = palette }
    }

    // Follow the terminal window while the popup is open.
    private var followTimer: Timer?
    private var missedTicks = 0
    private var shown: (state: CompletionController.State, width: CGFloat, window: CaretLocator.Window)?

    func hide() {
        stopFollowing()
        if panel.isVisible {
            panel.orderOut(nil)
            Log.popup.debug("closed")
        }
    }

    private func stopFollowing() {
        missedTicks = 0
        followTimer?.invalidate()
        followTimer = nil
        shown = nil
    }

    private func startFollowing(_ state: CompletionController.State, width: CGFloat, front: NSRunningApplication) {
        guard let window = CaretLocator.focusedWindow(of: front) else {
            stopFollowing()
            return
        }
        shown = (state, width, window)
        guard followTimer == nil else { return }
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
    }

    /// Moves the popup with the terminal window (dragging, resizing), and closes it when
    /// that window closes or another window comes to the front.
    private func follow() {
        guard let shown, panel.isVisible else { return }
        let window = NSWorkspace.shared.frontmostApplication.flatMap(CaretLocator.focusedWindow(of:))
        // Electron apps sometimes miss an Accessibility request; give a closed window a
        // few ticks before closing the popup.
        guard let window,
              CFEqual(window.element, shown.window.element) || window.frame == shown.window.frame
        else {
            missedTicks += 1
            if missedTicks >= 3 {
                Log.popup.debug("hidden: the terminal window closed or another one is in front")
                hide()
                onDismiss?()
            }
            return
        }
        missedTicks = 0
        guard window.frame != shown.window.frame else { return }
        if shown.state.start != nil, window.frame.size != shown.window.frame.size {
            Log.popup.debug("hidden: terminal window resized; waiting for the shell to report the cursor again")
            hide()
            onDismiss?()
            return
        }
        show(shown.state, width: shown.width)
    }

    func show(_ state: CompletionController.State, width: CGFloat) {
        guard state.visible, !state.items.isEmpty, let front = NSWorkspace.shared.frontmostApplication else {
            hide()
            return
        }
        let bundle = front.bundleIdentifier ?? "?"
        guard Self.belongs(session: state.app, to: front) else {
            Log.popup.debug("hidden: shell from \(state.app, privacy: .public) is not in front (\(bundle, privacy: .public))")
            hide()
            return
        }
        guard let caret = CaretLocator.caret(for: front, start: state.start, cursor: state.line?.cursor) else {
            Log.popup.debug("hidden: no text cursor found in \(bundle, privacy: .public)")
            hide()
            return
        }
        Log.popup.debug("shown in \(bundle, privacy: .public) at \(caret.rect.debugDescription, privacy: .public)")

        lastFront = front
        refreshPalette(for: front)
        if model.items != state.items { model.items = state.items }
        if model.selected != state.selected { model.selected = state.selected }
        if model.isLoading != state.isLoading { model.isLoading = state.isLoading }

        let height = model.height(itemCount: state.items.count)
        // Line up the suggestion text with the start of the word being completed.
        var x = caret.rect.minX
        if let cell = caret.cellWidth, let line = state.line, let first = state.items.first {
            let typed = max(0, line.cursor - first.replaceStart)
            x -= CGFloat(typed) * cell
        }
        x -= model.iconSize + 20  // row padding (4 + 8) + icon + spacing (8)

        let screen = NSScreen.screens.first { $0.frame.contains(caret.rect.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var y = caret.rect.minY - 4 - height
        if y < visible.minY { y = caret.rect.maxY + 4 }  // Not enough room below: open upwards.
        x = min(max(x, visible.minX + 4), visible.maxX - width - 4)

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
        startFollowing(state, width: width, front: front)
    }

    /// The popup is only shown while the terminal that sent the line is in front.
    static func belongs(session app: String, to front: NSRunningApplication) -> Bool {
        guard !app.isEmpty, let bundle = front.bundleIdentifier else { return true }
        if app == bundle { return true }
        // $TERM_PROGRAM values, when the shell did not inherit __CFBundleIdentifier.
        switch app {
        case "Apple_Terminal": return bundle == "com.apple.Terminal"
        case "iTerm.app": return bundle == "com.googlecode.iterm2"
        case "vscode": return bundle == "com.microsoft.VSCode" || bundle.hasPrefix("com.todesktop.")
            || bundle == "com.vscodium" || bundle == "com.microsoft.VSCodeInsiders"
        default: return false
        }
    }
}


/// The themes VS Code and Cursor are using, read in the background and kept until the
/// editor's settings or the macOS appearance change.
@MainActor
final class EditorThemeCache {
    private struct Entry {
        var settingsDate: Date?
        var dark: Bool
        var theme: ZestTheme?
    }

    private var entries: [EditorTheme.Editor: Entry] = [:]
    private var loading: Set<EditorTheme.Editor> = []

    static func editor(for app: NSRunningApplication) -> EditorTheme.Editor? {
        guard let bundle = app.bundleIdentifier else { return nil }
        if bundle == "com.microsoft.VSCode" || bundle == "com.microsoft.VSCodeInsiders" || bundle == "com.vscodium" {
            return .vscode
        }
        return bundle.hasPrefix("com.todesktop.") ? .cursor : nil
    }

    /// The cached theme (possibly a little stale); starts a refresh when needed and calls
    /// `onUpdate` when it has a new one.
    func theme(for editor: EditorTheme.Editor, onUpdate: @escaping @MainActor () -> Void) -> ZestTheme? {
        let date = EditorTheme.settingsDate(for: editor)
        let dark = AppModel.systemIsDark
        let entry = entries[editor]
        if entry == nil || entry?.settingsDate != date || entry?.dark != dark, !loading.contains(editor) {
            loading.insert(editor)
            Task.detached(priority: .utility) {
                let theme = EditorTheme.current(for: editor, darkMode: dark)
                await MainActor.run {
                    self.entries[editor] = Entry(settingsDate: date, dark: dark, theme: theme)
                    self.loading.remove(editor)
                    Log.popup.debug("editor theme for \(editor.rawValue, privacy: .public): \(theme?.name ?? "not found", privacy: .public)")
                    onUpdate()
                }
            }
        }
        return entry?.theme
    }
}
