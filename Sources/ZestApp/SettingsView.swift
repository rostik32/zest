import AppKit
import SwiftUI
import ZestCore
import ZestUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: Updater

    var body: some View {
        TabView {
            GeneralTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            BehaviorTab()
                .tabItem { Label("Behavior", systemImage: "keyboard") }
            AppearanceTab(model: model)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            SpecsTab(model: model)
                .tabItem { Label("Specs", systemImage: "doc.text") }
            UpdatesTab(updater: updater)
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
        // Resizable; starts large enough that the theme list and preview fit.
        .frame(minWidth: 640, idealWidth: 760, maxWidth: .infinity,
               minHeight: 560, idealHeight: 820, maxHeight: .infinity)
        .padding(.vertical, 8)
        .background(ResizableWindow())
    }
}

/// SwiftUI's Settings window has a fixed size; this lets you resize it.
private struct ResizableWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.insert(.resizable)
            window.minSize = NSSize(width: 640, height: 560)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct StatusRow: View {
    let ok: Bool
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct GeneralTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Show suggestions", isOn: $model.enabled)
                Toggle("Start zest at login", isOn: Binding(
                    get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            }
            Section("Setup") {
                HStack {
                    StatusRow(
                        ok: model.accessibilityGranted, title: "Accessibility access",
                        detail: "Needed to place the popup under the cursor.")
                    Spacer()
                    if !model.accessibilityGranted {
                        Button("Open System Settings") { model.requestAccessibility() }
                    }
                }
                HStack {
                    StatusRow(
                        ok: model.shellInstalled, title: "zsh integration",
                        detail: "Three lines at the end of ~/.zshrc. Only zsh is supported.")
                    Spacer()
                    if model.shellInstalled {
                        Button("Remove") { model.uninstallShellIntegration() }
                    } else {
                        Button("Add to ~/.zshrc") { model.installShellIntegration() }
                    }
                }
                if let error = model.serverError {
                    StatusRow(ok: false, title: "zest could not start", detail: error)
                }
            }
            Section {
                Text("Open a new terminal window after changing the zsh integration.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct BehaviorTab: View {
    @AppStorage(Pref.enter) private var enter = CompletionController.EnterBehavior.smart.rawValue
    @AppStorage(Pref.fuzzy) private var fuzzy = true
    @AppStorage(Pref.history) private var history = true
    @AppStorage(Pref.ghostText) private var ghostText = true
    @AppStorage(Pref.pathCommands) private var pathCommands = true

    var body: some View {
        Form {
            Section("Keys") {
                Picker("Enter", selection: $enter) {
                    Text("Insert while typing a word, otherwise run").tag(CompletionController.EnterBehavior.smart.rawValue)
                    Text("Always insert the suggestion").tag(CompletionController.EnterBehavior.insert.rawValue)
                    Text("Always run the command").tag(CompletionController.EnterBehavior.run.rawValue)
                }
                LabeledContent("Tab", value: "Insert the suggestion")
                LabeledContent("↑ ↓", value: "Choose a suggestion")
                LabeledContent("Esc", value: "Close the popup")
                LabeledContent("→", value: "Accept the grey ghost text")
            }
            Section("Suggestions") {
                Toggle("Fuzzy matching (\"gco\" finds \"git-checkout\")", isOn: $fuzzy)
                Toggle("Suggest commands from history", isOn: $history)
                Toggle("Suggest every program on $PATH", isOn: $pathCommands)
                Toggle("Ghost text from history (new terminals)", isOn: $ghostText)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceTab: View {
    @ObservedObject var model: AppModel
    @AppStorage(Pref.fontSize) private var fontSize = 13.0
    @AppStorage(Pref.fontName) private var fontName = "Menlo"
    @AppStorage(Pref.rows) private var rows = 8
    @AppStorage(Pref.width) private var width = 440.0
    @AppStorage(Pref.descriptions) private var descriptions = true
    @AppStorage(Pref.themeDark) private var darkTheme = ZestTheme.oneDarkProDarker.id
    @AppStorage(Pref.themeLight) private var lightTheme = "github-light-default"
    @AppStorage(Pref.themeFollowsAppearance) private var followsAppearance = false
    @AppStorage(Pref.themeMatchesEditor) private var matchesEditor = true
    @State private var editingLight = false
    @State private var search = ""
    @State private var fonts: [String] = []

    var body: some View {
        let themes = model.themes.all()
        let _ = model.themesVersion  // reload the list after an import
        Form {
            Section("Theme") {
                Toggle("Use a light theme when macOS is in Light mode", isOn: $followsAppearance)
                let appearance: ZestTheme.Appearance? = followsAppearance ? (editingLight ? .light : .dark) : nil
                let shown = ThemeList.filter(themes, search: search, appearance: appearance)
                HStack(spacing: 12) {
                    if followsAppearance {
                        Picker("Editing", selection: $editingLight) {
                            Text("Dark theme").tag(false)
                            Text("Light theme").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    Spacer()
                    if !search.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("\(shown.count) found").font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Search themes", text: $search, prompt: Text("Search \(themes.count) themes"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(width: 240)
                }
                ThemeList(themes: shown, search: search, slot: editingLight && followsAppearance,
                          selection: editingLight && followsAppearance ? $lightTheme : $darkTheme)
                Toggle("In VS Code and Cursor, use the editor's theme", isOn: $matchesEditor)
                if matchesEditor {
                    Text(editorThemes)
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Import VS Code Theme…") { importTheme() }
                    Button("Open Themes Folder") { model.openThemesFolder() }
                }
            }
            Section("Text") {
                Picker("Font", selection: $fontName) {
                    ForEach(fonts.contains(fontName) ? fonts : [fontName] + fonts, id: \.self) { name in
                        Text(name == PopupFont.system ? "SF Mono (system)" : name).tag(name)
                    }
                }
                Stepper("Font size: \(Int(fontSize))", value: $fontSize, in: 10...20)
                Stepper("Visible rows: \(rows)", value: $rows, in: 3...20)
                Slider(value: $width, in: 300...800, step: 20) { Text("Width: \(Int(width))") }
                Toggle("Show descriptions", isOn: $descriptions)
            }
            Section("Preview") {
                let theme = previewTheme(themes)
                PreviewPopup(theme: theme, fontName: fontName, fontSize: fontSize, rows: rows, descriptions: descriptions)
                    .frame(maxWidth: CGFloat(width))
                    .frame(maxWidth: .infinity)
                Text("\(theme.name)\(theme.source.map { " · " + $0 } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { if fonts.isEmpty { fonts = PopupFont.families() } }
    }

    /// The theme being edited, so picking one shows it right away.
    private func previewTheme(_ themes: [ZestTheme]) -> ZestTheme {
        let id = followsAppearance && editingLight ? lightTheme : darkTheme
        return themes.first { $0.id == id } ?? .oneDarkProDarker
    }

    private var editorThemes: String {
        let dark = AppModel.systemIsDark
        return EditorTheme.Editor.allCases.map { editor in
            "\(editor == .vscode ? "VS Code" : "Cursor"): \(EditorTheme.name(for: editor, darkMode: dark))"
        }.joined(separator: " · ")
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.title = "Import VS Code Themes"
        panel.message = "Choose a theme's .json file, or an extension folder (with package.json)."
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK else { return }
        let imported = model.importThemes(from: panel.urls)
        if let first = imported.first {
            search = ""
            if followsAppearance && first.appearance == .light { lightTheme = first.id; editingLight = true }
            else { darkTheme = first.id; editingLight = false }
        }
    }
}

/// The list of themes, with a color swatch for each.
private struct ThemeList: View {
    /// Already filtered with `filter`.
    let themes: [ZestTheme]
    let search: String
    /// Changes when you switch between the dark and the light theme.
    let slot: Bool
    @Binding var selection: String

    static func filter(_ themes: [ZestTheme], search: String, appearance: ZestTheme.Appearance?) -> [ZestTheme] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return themes.filter { theme in
            (appearance == nil || theme.appearance == appearance)
                && (query.isEmpty || theme.name.lowercased().contains(query) || (theme.source ?? "").lowercased().contains(query))
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(themes) { theme in
                        ThemeRow(theme: theme, selected: theme.id == selection)
                            .id(theme.id)
                            .contentShape(Rectangle())
                            .onTapGesture { selection = theme.id }
                    }
                    if themes.isEmpty {
                        Text("No themes match “\(search)”.").foregroundStyle(.secondary).padding(.vertical, 20)
                    }
                }
                .padding(4)
            }
            .frame(height: 260)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: slot) { _, _ in proxy.scrollTo(selection, anchor: .center) }
        }
    }
}

private struct ThemeRow: View {
    let theme: ZestTheme
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Swatch(theme: theme)
            VStack(alignment: .leading, spacing: 1) {
                Text(theme.name)
                Text(theme.appearance == .dark ? "Dark" : "Light")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Color.accentColor.opacity(0.15) : .clear))
    }
}

/// The theme's background with its text and kind colors.
private struct Swatch: View {
    let theme: ZestTheme

    var body: some View {
        HStack(spacing: 3) {
            Text("Aa").font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(theme[.text]))
            ForEach([ZestTheme.Token.command, .subcommand, .option, .argument], id: \.self) { token in
                Circle().fill(Color(theme[token])).frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 6)
        .frame(width: 66, height: 24)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color(theme[.background])))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(theme[.border]), lineWidth: 1))
    }
}

/// A popup with sample items, drawn with the settings as they are being changed.
private struct PreviewPopup: View {
    let theme: ZestTheme
    let fontName: String
    let fontSize: Double
    let rows: Int
    let descriptions: Bool

    private static let icons = IconResolver(
        indexURL: Paths.icons?.appendingPathComponent("material.json"),
        iconsDirectory: Paths.icons?.appendingPathComponent("material"))

    var body: some View {
        let model = sample()
        PopupView(model: model, icons: Self.icons)
            .frame(height: model.height(itemCount: model.items.count))
    }

    @MainActor
    private func sample() -> PopupModel {
        let preview = PopupModel()
        preview.fontSize = CGFloat(fontSize)
        preview.fontName = fontName
        preview.visibleRows = min(rows, 10)
        preview.showDescriptions = descriptions
        preview.palette = Palette(theme)
        func item(_ kind: CompletionKind, _ name: String, _ description: String?, _ matched: [Int]) -> Completion {
            Completion(kind: kind, name: name, insertText: name, description: description, icon: nil,
                       matchedIndices: matched, score: 0, appendSpace: true, replaceStart: 0, replaceEnd: 0,
                       deprecated: false, usageKey: "")
        }
        preview.items = [
            item(.subcommand, "checkout", "Switch branches or restore working tree files", [0, 1]),
            item(.subcommand, "cherry-pick", "Apply the changes introduced by some commits", [0, 1]),
            item(.option, "--force", "Throw away local changes", []),
            item(.argument, "main", "Branch", []),
            item(.folder, "src/", nil, []),
            item(.file, "Package.swift", nil, []),
            item(.history, "git checkout -b feature", "From history", []),
            item(.command, "git", "The stupid content tracker", []),
            item(.subcommand, "clone", "Clone a repository into a new directory", []),
            item(.subcommand, "commit", "Record changes to the repository", []),
        ]
        return preview
    }
}

private struct SpecsTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Built-in specs", value: "\(model.store.commands().count) commands")
                LabeledContent("Your specs", value: SpecStore.userSpecsDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                HStack {
                    Button("Open My Specs Folder") { model.openSpecsFolder() }
                    Button("Reload Specs") { model.reloadSpecs() }
                }
            }
            Section("Add a command") {
                Text("""
                Put a YAML file named after the command in your specs folder, e.g. mytool.yaml. \
                A spec in your folder replaces the built-in one with the same name.

                To start from the command's --help output, run:
                    zest gen mytool
                Then check it with:
                    zest validate
                """)
                .font(.callout)
                .textSelection(.enabled)
                Link("Spec format reference", destination: URL(string: "https://github.com/rostik32/zest/blob/main/docs/spec-format.md")!)
            }
        }
        .formStyle(.grouped)
    }
}

private struct UpdatesTab: View {
    @ObservedObject var updater: Updater
    @AppStorage(Pref.autoCheckUpdates) private var autoCheck = true
    @AppStorage(Pref.autoInstallUpdates) private var autoInstall = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: ZestVersion.current)
                Toggle("Check for updates automatically", isOn: $autoCheck)
                Toggle("Install updates without asking", isOn: $autoInstall)
                    .disabled(!autoCheck)
                HStack {
                    Button("Check Now") { Task { await updater.check(userInitiated: true) } }
                        .disabled(updater.status == .checking || updater.status == .installing)
                    Text(statusText).foregroundStyle(.secondary)
                }
            }
            Section {
                Text("Updates come from GitHub Releases of rostik32/zest. Each update is checked against its checksum and must be signed with the same certificate as this app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        switch updater.status {
        case .idle: return ""
        case .checking: return "Checking…"
        case .upToDate: return "Up to date"
        case .available(let v): return "Version \(v) is available"
        case .installing: return "Installing…"
        case .failed(let e): return "Failed: \(e)"
        }
    }
}
