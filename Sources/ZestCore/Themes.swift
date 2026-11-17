import Foundation
import Yams

// MARK: - Colors

/// An sRGB color with alpha, written as `#RRGGBB` or `#RRGGBBAA` in theme files.
public struct RGBA: Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parses `#RGB`, `#RGBA`, `#RRGGBB` and `#RRGGBBAA`.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 || s.count == 4 { s = String(s.flatMap { [$0, $0] }) }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let v = s.count == 6 ? value << 8 | 0xFF : value
        red = Double((v >> 24) & 0xFF) / 255
        green = Double((v >> 16) & 0xFF) / 255
        blue = Double((v >> 8) & 0xFF) / 255
        alpha = Double(v & 0xFF) / 255
    }

    public var hex: String {
        func byte(_ x: Double) -> String { String(format: "%02X", Int((max(0, min(1, x)) * 255).rounded())) }
        return "#" + byte(red) + byte(green) + byte(blue) + (alpha < 1 ? byte(alpha) : "")
    }

    /// This color painted over `background`, as an opaque color.
    public func over(_ background: RGBA) -> RGBA {
        guard alpha < 1 else { return self }
        func mix(_ a: Double, _ b: Double) -> Double { a * alpha + b * (1 - alpha) }
        return RGBA(red: mix(red, background.red), green: mix(green, background.green), blue: mix(blue, background.blue))
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio, from 1 (none) to 21.
    public func contrast(with other: RGBA) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

// MARK: - Theme

/// The colors of the popup.
public struct ZestTheme: Equatable, Sendable, Identifiable {
    public enum Appearance: String, Sendable, CaseIterable { case dark, light }

    /// Every color a theme sets. The raw values are the keys in theme files.
    public enum Token: String, CaseIterable, Sendable {
        case background, border, selection, text, selectedText, match, description
        case command, subcommand, option, argument
    }

    /// The file name without `.yaml`; stable, used in settings.
    public var id: String
    public var name: String
    public var appearance: Appearance
    public var colors: [Token: RGBA]
    /// Where the colors come from, e.g. "Dracula Theme by Dracula Theme (MIT)".
    public var source: String?

    public init(id: String, name: String, appearance: Appearance, colors: [Token: RGBA], source: String? = nil) {
        self.id = id
        self.name = name
        self.appearance = appearance
        self.colors = colors
        self.source = source
    }

    public subscript(token: Token) -> RGBA {
        colors[token] ?? ZestTheme.fallback(appearance)[token]
    }

    /// The colors used before themes existed: One Dark Pro Darker's suggest widget.
    public static let oneDarkProDarker = ZestTheme(
        id: "one-dark-pro-darker", name: "One Dark Pro Darker", appearance: .dark,
        colors: [
            .background: RGBA(hex: "#1E2227")!, .border: RGBA(hex: "#181A1F")!,
            .selection: RGBA(hex: "#2C313A")!, .text: RGBA(hex: "#ABB2BF")!,
            .selectedText: RGBA(hex: "#D7DAE0")!, .match: RGBA(hex: "#ECEBEB")!,
            .description: RGBA(hex: "#7F848E")!, .command: RGBA(hex: "#8CC265")!,
            .subcommand: RGBA(hex: "#C162DE")!, .option: RGBA(hex: "#4AA5F0")!,
            .argument: RGBA(hex: "#D18F52")!,
        ],
        source: "One Dark Pro by binaryify (MIT)")

    static let defaultLight = ZestTheme(
        id: "light", name: "Light", appearance: .light,
        colors: [
            .background: RGBA(hex: "#F3F3F3")!, .border: RGBA(hex: "#C8C8C8")!,
            .selection: RGBA(hex: "#D6EBFF")!, .text: RGBA(hex: "#333333")!,
            .selectedText: RGBA(hex: "#000000")!, .match: RGBA(hex: "#0066BF")!,
            .description: RGBA(hex: "#717171")!, .command: RGBA(hex: "#00BC00")!,
            .subcommand: RGBA(hex: "#BC05BC")!, .option: RGBA(hex: "#0451A5")!,
            .argument: RGBA(hex: "#949800")!,
        ])

    static func fallback(_ appearance: Appearance) -> ZestTheme {
        appearance == .dark ? oneDarkProDarker : defaultLight
    }
}

// MARK: - Theme files

extension ZestTheme {
    /// Reads a theme file:
    ///
    ///     name: Dracula
    ///     appearance: dark
    ///     colors:
    ///       background: "#21222C"
    ///       ...
    public init(yaml: String, id: String) throws {
        guard let root = try Yams.load(yaml: yaml) as? [String: Any] else { throw ThemeError.invalid("not a mapping") }
        let appearance = (root["appearance"] as? String).flatMap(Appearance.init(rawValue:)) ?? .dark
        var colors: [Token: RGBA] = [:]
        for (key, value) in root["colors"] as? [String: Any] ?? [:] {
            guard let token = Token(rawValue: key) else { throw ThemeError.invalid("unknown color \"\(key)\"") }
            guard let text = value as? String, let color = RGBA(hex: text) else {
                throw ThemeError.invalid("\(key): \"\(value)\" is not a color like #RRGGBB")
            }
            colors[token] = color
        }
        self.init(id: id, name: root["name"] as? String ?? id, appearance: appearance, colors: colors,
                  source: root["source"] as? String)
    }

    public var yaml: String {
        var lines = ["name: \(Self.quote(name))", "appearance: \(appearance.rawValue)"]
        if let source { lines.append("source: \(Self.quote(source))") }
        lines.append("colors:")
        for token in Token.allCases {
            if let color = colors[token] { lines.append("  \(token.rawValue): \"\(color.hex)\"") }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// A file name for a theme name: "Tokyo Night Storm" -> "tokyo-night-storm".
    public static func slug(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        let parts = folded.split { !($0.isLetter || $0.isNumber) }
        return parts.isEmpty ? "theme" : parts.joined(separator: "-")
    }
}

public enum ThemeError: Error, CustomStringConvertible {
    case invalid(String)
    case notFound(String)

    public var description: String {
        switch self {
        case .invalid(let s): return "invalid theme: \(s)"
        case .notFound(let s): return s
        }
    }
}

// MARK: - Store

/// Built-in themes (`Resources/themes`, `themes/` in a checkout) and your own
/// (`~/.config/zest/themes`). Yours replace built-in ones with the same file name.
public final class ThemeStore: @unchecked Sendable {
    public let directories: [URL]

    public init(directories: [URL] = ThemeStore.defaultDirectories) {
        self.directories = directories
    }

    public static var userDirectory: URL {
        SpecStore.userSpecsDirectory.deletingLastPathComponent().appendingPathComponent("themes", isDirectory: true)
    }

    public static var builtInDirectory: URL? {
        guard let resources = Paths.resources else { return nil }
        let url = resources.appendingPathComponent("themes", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public static var defaultDirectories: [URL] {
        [userDirectory] + (builtInDirectory.map { [$0] } ?? [])
    }

    /// All themes, sorted by name. Files that don't parse are skipped.
    public func all() -> [ZestTheme] {
        var byID: [String: ZestTheme] = [:]
        for directory in directories.reversed() {  // later ones (yours) win
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "yaml" || file.pathExtension == "yml" {
                let id = file.deletingPathExtension().lastPathComponent
                if let text = try? String(contentsOf: file, encoding: .utf8), let theme = try? ZestTheme(yaml: text, id: id) {
                    byID[id] = theme
                }
            }
        }
        if byID[ZestTheme.oneDarkProDarker.id] == nil { byID[ZestTheme.oneDarkProDarker.id] = .oneDarkProDarker }
        return byID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func theme(id: String) -> ZestTheme? {
        for directory in directories {
            let file = directory.appendingPathComponent(id + ".yaml")
            if let text = try? String(contentsOf: file, encoding: .utf8), let theme = try? ZestTheme(yaml: text, id: id) {
                return theme
            }
        }
        return id == ZestTheme.oneDarkProDarker.id ? .oneDarkProDarker : nil
    }

    /// Saves a theme into `directory` (your themes folder by default). Returns the file.
    @discardableResult
    public static func save(_ theme: ZestTheme, to directory: URL = userDirectory) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(theme.id + ".yaml")
        try theme.yaml.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}

// MARK: - VS Code themes

/// Turns a VS Code color theme into a zest theme. It uses the colors of VS Code's own
/// suggest widget (`editorSuggestWidget.*`), which is what the popup looks like, and
/// falls back to the general editor colors and to VS Code's defaults.
public enum VSCodeTheme {
    /// Converts one theme file. `include` chains are followed with `read`, which gets a
    /// path relative to the theme file and returns its contents.
    public static func convert(
        json: String, name: String? = nil, uiTheme: String? = nil, source: String? = nil,
        read: (String) throws -> String = { _ in throw ThemeError.notFound("include not supported") }
    ) throws -> ZestTheme {
        var colors: [String: String] = [:]
        var type = uiTheme.map(Self.type(uiTheme:))
        var themeName = name
        try collect(json: json, into: &colors, type: &type, name: &themeName, read: read, depth: 0)
        let appearance: ZestTheme.Appearance = (type ?? "dark") == "light" ? .light : .dark
        let finalName = themeName ?? "Imported Theme"
        return ZestTheme(
            id: ZestTheme.slug(finalName), name: finalName, appearance: appearance,
            colors: map(colors, appearance: appearance), source: source)
    }

    /// "vs" -> light, "vs-dark" -> dark, "hc-black" -> dark, "hc-light" -> light.
    static func type(uiTheme: String) -> String {
        switch uiTheme {
        case "vs", "hc-light": return "light"
        default: return "dark"
        }
    }

    private static func collect(
        json: String, into colors: inout [String: String], type: inout String?, name: inout String?,
        read: (String) throws -> String, depth: Int
    ) throws {
        guard depth < 8 else { throw ThemeError.invalid("include chain is too long") }
        guard let object = try JSONSerialization.jsonObject(with: Data(JSONC.strip(json).utf8)) as? [String: Any] else {
            throw ThemeError.invalid("not a JSON object")
        }
        // Included themes come first; this file's colors override them.
        if let include = object["include"] as? String {
            try collect(json: read(include), into: &colors, type: &type, name: &name, read: read, depth: depth + 1)
        }
        if depth == 0, name == nil { name = object["name"] as? String }
        if let t = object["type"] as? String, type == nil || depth == 0 {
            type = t.hasPrefix("hc") ? (t == "hcLight" ? "light" : "dark") : t
        }
        for (key, value) in object["colors"] as? [String: Any] ?? [:] {
            if let value = value as? String { colors[key] = value }
        }
    }

    static func map(_ c: [String: String], appearance: ZestTheme.Appearance) -> [ZestTheme.Token: RGBA] {
        let defaults = appearance == .dark ? darkDefaults : lightDefaults
        func color(_ keys: [String]) -> RGBA? {
            for key in keys { if let value = c[key], let color = RGBA(hex: value), color.alpha > 0 { return color } }
            return nil
        }
        func pick(_ keys: [String], _ fallback: String) -> RGBA {
            color(keys) ?? color([fallback]) ?? RGBA(hex: defaults[fallback]!)!
        }
        let editor = color(["editor.background"]) ?? RGBA(hex: defaults["editor.background"]!)!
        let background = color(["editorSuggestWidget.background", "editorWidget.background", "editorHoverWidget.background"])?
            .over(editor) ?? editor
        let text = pick(["editorSuggestWidget.foreground", "editor.foreground", "foreground"], "editor.foreground").over(background)
        let selection = pick(["editorSuggestWidget.selectedBackground", "quickInputList.focusBackground",
                              "list.activeSelectionBackground", "list.focusBackground"], "list.activeSelectionBackground")
            .over(background)
        var selectedText = (color(["editorSuggestWidget.selectedForeground", "quickInputList.focusForeground",
                                   "list.activeSelectionForeground"]) ?? text).over(selection)
        if selectedText.contrast(with: selection) < 3 { selectedText = text }
        var match = pick(["editorSuggestWidget.highlightForeground", "list.highlightForeground", "focusBorder"],
                         "list.highlightForeground").over(background)
        if match.contrast(with: background) < 2 { match = selectedText }
        let border = (color(["editorSuggestWidget.border", "editorWidget.border", "widget.border", "contrastBorder",
                             "editorGroup.border", "panel.border"]) ?? RGBA(hex: defaults["editorWidget.border"]!)!)
            .over(background)
        // VS Code draws the details of a suggestion in the text color at 70% opacity.
        var description = RGBA(red: text.red, green: text.green, blue: text.blue, alpha: 0.7).over(background)
        if description.contrast(with: background) < 2.5 { description = text }

        // Kinds use the terminal's colors, which every theme sets; dim ones fall back to
        // their bright variants, then to the text color.
        func kind(_ name: String) -> RGBA {
            for key in ["terminal.ansi\(name)", "terminal.ansiBright\(name)"] {
                if let value = color([key])?.over(background), value.contrast(with: background) >= 2.5 { return value }
            }
            let fallback = RGBA(hex: defaults["terminal.ansi\(name)"]!)!
            return fallback.contrast(with: background) >= 2.5 ? fallback : text
        }
        return [
            .background: background, .border: border, .selection: selection, .text: text,
            .selectedText: selectedText, .match: match, .description: description,
            .command: kind("Green"), .subcommand: kind("Magenta"), .option: kind("Blue"), .argument: kind("Yellow"),
        ]
    }

    // VS Code's built-in defaults for the keys above.
    static let darkDefaults: [String: String] = [
        "editor.background": "#1E1E1E", "editor.foreground": "#D4D4D4",
        "list.activeSelectionBackground": "#04395E", "list.highlightForeground": "#2AAAFF",
        "editorWidget.border": "#454545",
        "terminal.ansiGreen": "#0DBC79", "terminal.ansiMagenta": "#BC3FBC",
        "terminal.ansiBlue": "#2472C8", "terminal.ansiYellow": "#E5E510",
    ]
    static let lightDefaults: [String: String] = [
        "editor.background": "#FFFFFF", "editor.foreground": "#000000",
        "list.activeSelectionBackground": "#D6EBFF", "list.highlightForeground": "#0066BF",
        "editorWidget.border": "#C8C8C8",
        "terminal.ansiGreen": "#00BC00", "terminal.ansiMagenta": "#BC05BC",
        "terminal.ansiBlue": "#0451A5", "terminal.ansiYellow": "#949800",
    ]
}

// MARK: - VS Code extensions

/// A theme an extension contributes (`contributes.themes` in its package.json).
public struct ContributedTheme: Sendable {
    public var label: String
    public var id: String?
    public var uiTheme: String
    public var file: URL
}

public enum VSCodeExtension {
    /// The themes an extension folder contributes, with `%placeholder%` labels resolved
    /// from package.nls.json.
    public static func themes(in folder: URL) -> [ContributedTheme] {
        let package = folder.appendingPathComponent("package.json")
        guard let text = try? String(contentsOf: package, encoding: .utf8),
              let object = try? JSONSerialization.jsonObject(with: Data(JSONC.strip(text).utf8)) as? [String: Any],
              let contributes = object["contributes"] as? [String: Any],
              let themes = contributes["themes"] as? [[String: Any]]
        else { return [] }
        var nls: [String: Any] = [:]
        if let text = try? String(contentsOf: folder.appendingPathComponent("package.nls.json"), encoding: .utf8),
           let object = try? JSONSerialization.jsonObject(with: Data(JSONC.strip(text).utf8)) as? [String: Any] {
            nls = object
        }
        return themes.compactMap { theme in
            guard let path = theme["path"] as? String else { return nil }
            var label = theme["label"] as? String ?? theme["id"] as? String ?? path
            if label.hasPrefix("%"), label.hasSuffix("%") {
                let key = String(label.dropFirst().dropLast())
                label = (nls[key] as? String) ?? ((nls[key] as? [String: Any])?["message"] as? String) ?? label
            }
            return ContributedTheme(label: label, id: theme["id"] as? String, uiTheme: theme["uiTheme"] as? String ?? "vs-dark",
                                    file: folder.appendingPathComponent(path).standardizedFileURL)
        }
    }

    /// Converts a contributed theme, following its `include` chain.
    public static func convert(_ theme: ContributedTheme, source: String? = nil) throws -> ZestTheme {
        let text = try String(contentsOf: theme.file, encoding: .utf8)
        let base = theme.file.deletingLastPathComponent()
        return try VSCodeTheme.convert(json: text, name: theme.label, uiTheme: theme.uiTheme, source: source) { path in
            try String(contentsOf: base.appendingPathComponent(path).standardizedFileURL, encoding: .utf8)
        }
    }
}

// MARK: - The editor's current theme

/// Finds the color theme VS Code or Cursor is using right now.
public enum EditorTheme {
    public enum Editor: String, Sendable, CaseIterable {
        case vscode, cursor

        var settings: URL {
            let folder = self == .vscode ? "Code" : "Cursor"
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/\(folder)/User/settings.json")
        }

        var extensionFolders: [URL] {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let app = self == .vscode ? "Visual Studio Code" : "Cursor"
            return [
                home.appendingPathComponent(self == .vscode ? ".vscode/extensions" : ".cursor/extensions"),
                URL(fileURLWithPath: "/Applications/\(app).app/Contents/Resources/app/extensions"),
                home.appendingPathComponent("Applications/\(app).app/Contents/Resources/app/extensions"),
            ]
        }

        var defaultTheme: String { self == .vscode ? "Default Dark Modern" : "Cursor Dark" }
    }

    /// The theme name from the editor's settings. With `window.autoDetectColorScheme`
    /// it is the preferred dark or light theme for the current macOS appearance.
    public static func name(for editor: Editor, darkMode: Bool) -> String {
        guard let text = try? String(contentsOf: editor.settings, encoding: .utf8),
              let settings = try? JSONSerialization.jsonObject(with: Data(JSONC.strip(text).utf8)) as? [String: Any]
        else { return editor.defaultTheme }
        if settings["window.autoDetectColorScheme"] as? Bool == true {
            let key = darkMode ? "workbench.preferredDarkColorTheme" : "workbench.preferredLightColorTheme"
            return settings[key] as? String ?? (darkMode ? editor.defaultTheme : "Default Light Modern")
        }
        return settings["workbench.colorTheme"] as? String ?? editor.defaultTheme
    }

    /// The editor's current theme, converted. Nil if it can't be found.
    public static func current(for editor: Editor, darkMode: Bool) -> ZestTheme? {
        let name = name(for: editor, darkMode: darkMode)
        for folder in editor.extensionFolders {
            let extensions = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for ext in extensions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {  // newest version first
                for theme in VSCodeExtension.themes(in: ext) where theme.label == name || theme.id == name {
                    if var converted = try? VSCodeExtension.convert(theme) {
                        converted.id = "editor-" + editor.rawValue
                        return converted
                    }
                }
            }
        }
        return nil
    }

    /// When the editor's settings last changed, to know when to look again.
    public static func settingsDate(for editor: Editor) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: editor.settings.path))?[.modificationDate] as? Date
    }
}

// MARK: - JSON with comments

/// VS Code's JSON allows comments and trailing commas.
enum JSONC {
    static func strip(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        var chars = Array(text.unicodeScalars)[...]
        var inString = false
        while let c = chars.popFirst() {
            if inString {
                out.unicodeScalars.append(c)
                if c == "\\", let next = chars.popFirst() { out.unicodeScalars.append(next) }
                else if c == "\"" { inString = false }
                continue
            }
            if c == "\"" { inString = true; out.unicodeScalars.append(c); continue }
            if c == "/", chars.first == "/" {
                while let n = chars.first, n != "\n" { chars.removeFirst() }
                continue
            }
            if c == "/", chars.first == "*" {
                chars.removeFirst()
                while let n = chars.popFirst() { if n == "*", chars.first == "/" { chars.removeFirst(); break } }
                continue
            }
            out.unicodeScalars.append(c)
        }
        // Trailing commas: `,` followed by whitespace and `}` or `]`.
        return out.replacingOccurrences(of: #",(\s*[}\]])"#, with: "$1", options: .regularExpression)
    }
}
