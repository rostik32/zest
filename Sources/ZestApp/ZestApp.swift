import AppKit
import SwiftUI
import ZestCore
import ZestUI

@main
struct ZestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model, updater: model.updater)
        } label: {
            Image(systemName: model.enabled ? "text.cursor" : "pause.circle")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model, updater: model.updater)
        }
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in AppModel.shared.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.stop() }
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: Updater
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if !model.accessibilityGranted {
            Button("⚠︎ Allow Accessibility Access…") { model.requestAccessibility() }
        }
        if !model.shellInstalled {
            Button("⚠︎ Add zest to ~/.zshrc") { model.installShellIntegration() }
        }
        if let error = model.serverError {
            Text("⚠︎ \(error)")
        }
        Toggle("Suggestions On", isOn: $model.enabled)
            .keyboardShortcut("p")
        Divider()
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
        Button(updateTitle) {
            Task { await updater.check(userInitiated: true) }
        }
        .disabled(updater.status == .checking || updater.status == .installing)
        Divider()
        Button("Open My Specs Folder") { model.openSpecsFolder() }
        Button("Reload Specs") { model.reloadSpecs() }
        Divider()
        Text("zest \(ZestVersion.current)")
        Button("Quit zest") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var updateTitle: String {
        switch updater.status {
        case .checking: return "Checking for Updates…"
        case .installing: return "Installing Update…"
        case .available(let version): return "Install zest \(version)…"
        default: return "Check for Updates…"
        }
    }
}
