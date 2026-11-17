import AppKit
import Combine
import ServiceManagement
import ZestCore
import ZestUI

/// Owns the services: specs, engine, socket server and popup.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var accessibilityGranted = CaretLocator.isTrusted
    @Published private(set) var shellInstalled = ShellIntegration.isInstalled
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var serverError: String?
    @Published var enabled: Bool {
        didSet { Pref.defaults.set(enabled, forKey: Pref.enabled) }
    }

    let resources = Paths.resources
    let store: SpecStore
    let engine: Engine
    let controller: CompletionController
    let popup: PopupController
    let updater = Updater()
    let themes = ThemeStore()
    /// Bumped when the theme files change (an import), so the theme list reloads.
    @Published private(set) var themesVersion = 0
    private var server: SocketServer?
    private var appearanceObservation: NSKeyValueObservation?
    private var observers: [Any] = []
    private var permissionTimer: Timer?

    private init() {
        Pref.register()
        enabled = Pref.defaults.bool(forKey: Pref.enabled)
        store = SpecStore(directories: SpecStore.defaultDirectories(builtIn: Paths.builtInSpecs))
        engine = Engine(store: store, usage: UsageStore(url: Paths.usage))
        controller = CompletionController(engine: engine)
        let icons = IconResolver(
            indexURL: Paths.icons?.appendingPathComponent("material.json"),
            iconsDirectory: Paths.icons?.appendingPathComponent("material"))
        IconCache.shared.configure(icons: Paths.icons)
        popup = PopupController(icons: icons)
        popup.onDismiss = { [controller] in controller.hide() }
        popup.model.onSelect = { [weak self] index in self?.select(index) }
    }

    func start() {
        applyPreferences()
        ShellIntegration.copyScript()

        controller.onChange = { [weak self] state in
            DispatchQueue.main.async { self?.render(state) }
        }
        let server = SocketServer(path: Paths.socket.path) { [controller] message in
            controller.handle(message)
        }
        do {
            try server.start()
            self.server = server
        } catch {
            serverError = String(describing: error)
        }

        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyPreferences() }
        })
        // Light and dark themes follow the macOS appearance.
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.applyPreferences() }
        }
        // Hide the popup as soon as another app comes to the front.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.popup.hide() }
        })

        // The Accessibility switch can change at any time in System Settings.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
        updater.startSchedule()
        if !Pref.defaults.bool(forKey: Pref.onboarded) {
            Onboarding.run(model: self)
        }
    }

    func stop() {
        server?.stop()
    }

    private func render(_ state: CompletionController.State) {
        guard enabled, accessibilityGranted else {
            popup.hide()
            return
        }
        popup.show(state, width: CGFloat(Pref.defaults.double(forKey: Pref.width)))
    }

    func refreshStatus() {
        // Assign only on change: every assignment re-renders the menu and settings.
        let trusted = CaretLocator.isTrusted
        if trusted != accessibilityGranted { accessibilityGranted = trusted }
        let installed = ShellIntegration.isInstalled
        if installed != shellInstalled { shellInstalled = installed }
        let login = SMAppService.mainApp.status == .enabled
        if login != launchAtLogin { launchAtLogin = login }
    }

    private var lastGhostText: Bool?

    private func applyPreferences() {
        let d = Pref.defaults
        let isEnabled = d.bool(forKey: Pref.enabled)
        if isEnabled != enabled { enabled = isEnabled }
        var engineSettings = EngineSettings()
        engineSettings.fuzzy = d.bool(forKey: Pref.fuzzy)
        engineSettings.historySuggestions = d.bool(forKey: Pref.history)
        engineSettings.pathCommands = d.bool(forKey: Pref.pathCommands)
        engine.settings = engineSettings

        var controllerSettings = CompletionController.Settings()
        controllerSettings.enabled = enabled
        controllerSettings.enter = CompletionController.EnterBehavior(rawValue: d.string(forKey: Pref.enter) ?? "") ?? .smart
        controller.settings = controllerSettings

        let model = popup.model
        let fontSize = CGFloat(d.double(forKey: Pref.fontSize))
        if model.fontSize != fontSize { model.fontSize = fontSize }
        let rows = max(3, d.integer(forKey: Pref.rows))
        if model.visibleRows != rows { model.visibleRows = rows }
        let descriptions = d.bool(forKey: Pref.descriptions)
        if model.showDescriptions != descriptions { model.showDescriptions = descriptions }
        let fontName = d.string(forKey: Pref.fontName) ?? "Menlo"
        if model.fontName != fontName { model.fontName = fontName }
        popup.basePalette = Palette(currentTheme)
        popup.matchEditor = d.bool(forKey: Pref.themeMatchesEditor)
        popup.refreshPalette()
        let ghost = d.bool(forKey: Pref.ghostText)
        if ghost != lastGhostText {
            lastGhostText = ghost
            ShellIntegration.writeSettings(ghostText: ghost)
        }
        if !enabled { popup.hide() }
    }

    /// A click on a suggestion: select it and press Tab in the terminal, so the shell
    /// inserts it exactly as if you had chosen it with the keyboard. The terminal keeps
    /// the keyboard focus (the popup never takes it).
    private func select(_ index: Int) {
        guard controller.select(index: index) else { return }
        let tab: CGKeyCode = 48
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: tab, keyDown: down)
            else { return }
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Themes

    static var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// The theme for the current macOS appearance (outside VS Code and Cursor).
    var currentTheme: ZestTheme {
        let d = Pref.defaults
        let light = d.bool(forKey: Pref.themeFollowsAppearance) && !Self.systemIsDark
        let id = d.string(forKey: light ? Pref.themeLight : Pref.themeDark) ?? ZestTheme.oneDarkProDarker.id
        return themes.theme(id: id) ?? .oneDarkProDarker
    }

    /// Imports VS Code themes (.json files or extension folders) into your themes folder.
    /// Returns the imported themes.
    @discardableResult
    func importThemes(from urls: [URL]) -> [ZestTheme] {
        var imported: [ZestTheme] = []
        for url in urls {
            do {
                var themes: [ZestTheme] = []
                if url.pathExtension.lowercased() == "json" {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    let base = url.deletingLastPathComponent()
                    themes = [try VSCodeTheme.convert(json: text) { try String(contentsOf: base.appendingPathComponent($0), encoding: .utf8) }]
                } else {
                    themes = try VSCodeExtension.themes(in: url).map { try VSCodeExtension.convert($0) }
                }
                if themes.isEmpty { throw ThemeError.notFound("No color themes in \(url.lastPathComponent).") }
                for theme in themes { try ThemeStore.save(theme) }
                imported += themes
            } catch {
                show(error: "Could not import \(url.lastPathComponent)", error)
            }
        }
        themesVersion += 1
        return imported
    }

    func openThemesFolder() {
        try? FileManager.default.createDirectory(at: ThemeStore.userDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(ThemeStore.userDirectory)
    }

    // MARK: - Actions

    func requestAccessibility() {
        CaretLocator.requestTrust()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func installShellIntegration() {
        do {
            try ShellIntegration.install()
        } catch {
            show(error: "Could not change ~/.zshrc", error)
        }
        refreshStatus()
    }

    func uninstallShellIntegration() {
        do {
            try ShellIntegration.uninstall()
        } catch {
            show(error: "Could not change ~/.zshrc", error)
        }
        refreshStatus()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            show(error: "Could not change the login item", error)
        }
        refreshStatus()
    }

    func reloadSpecs() {
        store.reload()
        engine.generators.clearCache()
    }

    func openSpecsFolder() {
        let dir = SpecStore.userSpecsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    func show(error title: String, _ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

/// First launch: ask for the permissions and setup zest needs, one step at a time.
@MainActor
enum Onboarding {
    static func run(model: AppModel) {
        NSApp.activate(ignoringOtherApps: true)

        if !model.accessibilityGranted {
            let alert = NSAlert()
            alert.messageText = "Allow zest to see where the cursor is"
            alert.informativeText = """
            zest shows its popup right under the text cursor in your terminal. To find the \
            cursor it needs Accessibility access. zest only reads the cursor position; it does \
            not read or send what you type anywhere.

            In System Settings, turn on zest under Privacy & Security → Accessibility.
            """
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn { model.requestAccessibility() }
        }

        if !model.shellInstalled {
            let alert = NSAlert()
            alert.messageText = "Add zest to zsh?"
            alert.informativeText = """
            zest adds three lines to the end of ~/.zshrc so new terminal windows connect to it. \
            A backup is saved as ~/.zshrc.zest-backup. You can remove the lines any time in Settings.

            zest works with zsh only.
            """
            alert.addButton(withTitle: "Add to ~/.zshrc")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn { model.installShellIntegration() }
        }

        if !model.launchAtLogin {
            let alert = NSAlert()
            alert.messageText = "Start zest when you log in?"
            alert.informativeText = "zest runs in the menu bar. You can change this in Settings."
            alert.addButton(withTitle: "Start at Login")
            alert.addButton(withTitle: "No")
            if alert.runModal() == .alertFirstButtonReturn { model.setLaunchAtLogin(true) }
        }

        Pref.defaults.set(true, forKey: Pref.onboarded)
    }
}
