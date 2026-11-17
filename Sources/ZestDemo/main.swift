// Renders the README demo (docs/images/demo.gif and docs/images/hero.png), and with
// `appearance` the themes demo (docs/images/appearance.gif).
//
// This is not a screen recording: it types a script into the real completion engine
// (CompletionController + built-in specs) inside a throwaway sample project, runs the real
// commands for their output, and draws each state with the app's real popup view on a
// clean terminal window. Run it again whenever the popup changes:
//
//   make demo        (needs ffmpeg: brew install ffmpeg)

import AppKit
import SwiftUI
import ZestCore
import ZestUI

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let output = root.appendingPathComponent("docs/images")

// MARK: - Sample project

func run(_ args: [String], in dir: URL) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = args
    p.currentDirectoryURL = dir
    var env = ProcessInfo.processInfo.environment
    env["GIT_AUTHOR_NAME"] = "demo"; env["GIT_AUTHOR_EMAIL"] = "demo@example.com"
    env["GIT_COMMITTER_NAME"] = "demo"; env["GIT_COMMITTER_EMAIL"] = "demo@example.com"
    p.environment = env
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    try? p.run()
    p.waitUntilExit()
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
}

let work = FileManager.default.temporaryDirectory.appendingPathComponent("zest-demo-\(UUID().uuidString)")
let project = work.appendingPathComponent("zest")
for dir in ["src/components", "src/pages", "src/hooks", "public", "tests", "docs"] {
    try FileManager.default.createDirectory(at: project.appendingPathComponent(dir), withIntermediateDirectories: true)
}
for file in ["README.md", "Dockerfile", "tsconfig.json", "vite.config.ts", "src/main.tsx", "src/App.tsx"] {
    FileManager.default.createFile(atPath: project.appendingPathComponent(file).path, contents: Data())
}
try """
{ "name": "zest", "private": true,
  "scripts": { "dev": "vite", "build": "tsc && vite build", "test": "vitest run", "lint": "eslint src" } }
""".write(to: project.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
_ = run(["git", "init", "-q", "-b", "main"], in: project)
_ = run(["git", "add", "-A"], in: project)
_ = run(["git", "commit", "-qm", "Initial commit"], in: project)
for branch in ["feature/login", "fix/header-layout", "release/1.2"] { _ = run(["git", "branch", branch], in: project) }
defer { try? FileManager.default.removeItem(at: work) }

// MARK: - Engine

let runner = GeneratorRunner()
runner.synchronous = true
var engineSettings = EngineSettings()
engineSettings.pathCommands = false
engineSettings.historySuggestions = false
// The compiled specs of the app bundle (with the command index), like the real app uses.
let compiledSpecs = root.appendingPathComponent("dist/Zest.app/Contents/Resources/specs")
guard FileManager.default.fileExists(atPath: compiledSpecs.path) else {
    print("Build the app first: make app")
    exit(1)
}
let engine = Engine(store: SpecStore(directories: [compiledSpecs]), generators: runner, settings: engineSettings)
let controller = CompletionController(engine: engine)
let iconsDir = root.appendingPathComponent("assets/icons")
let icons = IconResolver(indexURL: iconsDir.appendingPathComponent("material.json"), iconsDirectory: iconsDir.appendingPathComponent("material"))

// MARK: - Terminal model and view

let fontSize: CGFloat = 14
let termLine: CGFloat = 21
let font = NSFont(name: "Menlo", size: fontSize)!
let cell = ("M" as NSString).size(withAttributes: [.font: font]).width
let windowSize = CGSize(width: 880, height: 400)
let inset: CGFloat = 18
let titleHeight: CGFloat = 32

struct Line {
    var prompt: String?   // folder shown in the prompt, nil for output lines
    var text: String
}

@MainActor
final class Terminal: ObservableObject {
    @Published var lines: [Line] = []
    @Published var folder = "zest"
    @Published var buffer = ""
    @Published var cursor = 0
    @Published var popupVisible = false
    @Published var replaceColumn = 0
    /// A label in the corner, e.g. ("Theme", "Dracula"), for the appearance demo.
    @Published var caption: (label: String, value: String)?
    /// 0 = macOS in Dark mode, 1 = Light mode (the window and terminal colors follow it).
    @Published var lightness = 0.0
    let popup = PopupModel()
    var cwd = project

    var promptLength: Int { folder.count + 3 }  // "<folder> ❯ "
}

/// A terminal color between its dark-mode and light-mode value.
func mix(_ dark: UInt32, _ light: UInt32, _ t: Double) -> Color {
    func c(_ v: UInt32, _ shift: UInt32) -> Double { Double((v >> shift) & 0xFF) / 255 }
    func m(_ shift: UInt32) -> Double { c(dark, shift) + (c(light, shift) - c(dark, shift)) * t }
    return Color(.sRGB, red: m(16), green: m(8), blue: m(0))
}

struct PromptText: View {
    let folder: String
    let text: String
    var lightness = 0.0

    var body: some View {
        Text(folder).foregroundColor(mix(0x4AA5F0, 0x0969DA, lightness))
            + Text(" ❯ ").foregroundColor(mix(0x8CC265, 0x1A7F37, lightness))
            + Text(text).foregroundColor(mix(0xABB2BF, 0x24292F, lightness))
    }
}

struct TerminalView: View {
    @ObservedObject var term: Terminal

    var body: some View {
        ZStack(alignment: .topLeading) {
            mix(0x15171B, 0xDADDE3, term.lightness)
            window.padding(28).shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        }
        .frame(width: windowSize.width + 56, height: windowSize.height + 56)
    }

    var window: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 8) {
                    ForEach([0xFF5F57, 0xFEBC2E, 0x28C840], id: \.self) { Circle().fill(Color(hex: UInt32($0))).frame(width: 12, height: 12) }
                    Spacer()
                }
                Text("zsh — \(term.folder)").font(.system(size: 13, weight: .medium)).foregroundColor(mix(0x7F848E, 0x6E7781, term.lightness))
            }
            .padding(.horizontal, 14)
            .frame(height: titleHeight)
            .background(mix(0x1E2227, 0xECECEC, term.lightness))
            ZStack(alignment: .topLeading) {
                mix(0x23272E, 0xFFFFFF, term.lightness)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(term.lines.enumerated()), id: \.offset) { _, line in
                        Group {
                            if let folder = line.prompt { PromptText(folder: folder, text: line.text, lightness: term.lightness) } else { Text(line.text).foregroundColor(mix(0xABB2BF, 0x24292F, term.lightness)) }
                        }
                        .frame(height: termLine, alignment: .leading)
                    }
                    ZStack(alignment: .topLeading) {
                        PromptText(folder: term.folder, text: term.buffer, lightness: term.lightness)
                        Rectangle().fill(mix(0x528BFF, 0x0969DA, term.lightness)).frame(width: cell, height: termLine - 3)
                            .offset(x: CGFloat(term.promptLength + term.cursor) * cell, y: 1)
                            .opacity(0.85)
                    }
                    .frame(height: termLine, alignment: .leading)
                }
                .font(.custom("Menlo", size: fontSize))
                .padding(inset)
                if term.popupVisible {
                    PopupView(model: term.popup, icons: icons)
                        .frame(width: 440, height: term.popup.height(itemCount: term.popup.items.count))
                        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
                        .offset(x: popupX, y: inset + CGFloat(term.lines.count + 1) * termLine + 4)
                }
                if let caption = term.caption {
                    HStack(spacing: 8) {
                        Text(caption.label).foregroundColor(mix(0x7F848E, 0x6E7781, term.lightness))
                        Text(caption.value).foregroundColor(mix(0xD7DAE0, 0x24292F, term.lightness)).fontWeight(.semibold)
                    }
                    .font(.system(size: 14))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(mix(0x2C313A, 0xF0F1F4, term.lightness)))
                    .overlay(Capsule().stroke(mix(0x3A3F47, 0xD0D4DA, term.lightness), lineWidth: 1))
                    .frame(width: windowSize.width - 2 * inset, alignment: .trailing)
                    .offset(x: inset, y: windowSize.height - titleHeight - inset - 32)
                }
            }
        }
        .frame(width: windowSize.width, height: windowSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    var popupX: CGFloat {
        // Same alignment as the app: the suggestion text lines up with the word.
        let column = CGFloat(term.promptLength + term.replaceColumn)
        return inset + column * cell - (term.popup.iconSize + 20)
    }
}

// MARK: - Recording

@MainActor
final class Recorder {
    let term = Terminal()
    let frames: URL
    var list = ""
    var index = 0
    let window: NSWindow
    let host: NSHostingView<TerminalView>

    init(frames: URL) {
        self.frames = frames
        host = NSHostingView(rootView: TerminalView(term: term))
        let size = CGSize(width: windowSize.width + 56, height: windowSize.height + 56)
        host.frame = CGRect(origin: .zero, size: size)
        window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        term.popup.visibleRows = 7
    }

    /// Captures the current state and shows it for `seconds`.
    func frame(_ seconds: Double) {
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        let name = String(format: "%05d.png", index)
        try? rep.representation(using: .png, properties: [:])?.write(to: frames.appendingPathComponent(name))
        list += "file '\(name)'\nduration \(seconds)\n"
        index += 1
    }

    private func line() -> ShellProtocol.Line {
        .init(session: "demo", cwd: term.cwd.path, cursor: term.cursor, buffer: term.buffer)
    }

    private func sync() {
        let state = controller.current
        term.popupVisible = state.visible
        term.popup.items = state.items
        term.popup.selected = state.selected
        term.replaceColumn = state.items.first?.replaceStart ?? 0
    }

    func type(_ text: String, each: Double = 0.11) {
        for ch in text {
            term.buffer.append(ch)
            term.cursor = term.buffer.count
            controller.handle(.line(line()))
            sync()
            frame(each)
        }
    }

    func press(_ key: ShellProtocol.Key, hold: Double = 0.5) {
        let reply = controller.handle(.key(sequence: "1", key: key, line()))
        if case .set(let cursor, let buffer) = reply {
            term.buffer = buffer
            term.cursor = cursor
            controller.handle(.line(line()))
        }
        sync()
        frame(hold)
    }

    /// Enter: runs the command for real in the sample project and shows its output.
    func execute(hold: Double = 0.8) {
        let command = term.buffer.trimmingCharacters(in: .whitespaces)
        term.lines.append(Line(prompt: term.folder, text: command))
        if command.hasPrefix("cd ") {
            let target = String(command.dropFirst(3)).trimmingCharacters(in: CharacterSet(charactersIn: " /"))
            term.cwd = term.cwd.appendingPathComponent(target)
            term.folder += "/" + target
        } else {
            let out = run(["zsh", "-f", "-c", command], in: term.cwd)
            for text in out.split(separator: "\n").prefix(3) { term.lines.append(Line(prompt: nil, text: String(text))) }
        }
        clear()
        frame(hold)
    }

    func clear() {
        term.buffer = ""
        term.cursor = 0
        controller.handle(.end(session: "demo"))
        sync()
    }
}

// MARK: - Script

@MainActor
func render() throws {
    let frames = work.appendingPathComponent("frames")
    try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
    let r = Recorder(frames: frames)
    var heroIndex = 0

    // A developer's usual history, so frequent commands rank first (as they would for you).
    for command in ["git status", "git pull", "git add -A", "git commit -m wip", "npm install", "npm run dev",
                    "npm test", "docker compose up", "docker ps", "docker run --rm -it node:22", "cd ..", "ls -la"] {
        controller.handle(.exec(session: "demo", command: command))
    }

    r.frame(0.8)
    // git: subcommands, then branches.
    r.type("git ch")
    r.frame(0.9)
    r.press(.tab, hold: 1.0)
    r.press(.down, hold: 0.6)
    heroIndex = r.index
    r.press(.down, hold: 0.8)
    r.press(.up, hold: 0.7)
    r.press(.tab, hold: 0.7)
    r.execute()
    // npm scripts from package.json.
    r.type("npm run ")
    r.frame(1.1)
    r.press(.down, hold: 0.6)
    r.press(.tab, hold: 0.9)
    r.clear()
    r.frame(0.3)
    // docker options with descriptions.
    r.type("docker run --")
    r.frame(1.0)
    r.type("me", each: 0.15)
    r.frame(1.4)
    r.clear()
    r.frame(0.3)
    // folders.
    r.type("cd s")
    r.frame(1.0)
    r.press(.tab, hold: 1.2)
    r.execute(hold: 0.6)
    r.type("ls -")
    r.frame(1.6)
    r.clear()
    r.frame(1.0)

    try r.list.write(to: frames.appendingPathComponent("list.txt"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    // Hero image: the branch list.
    let hero = output.appendingPathComponent("hero.png")
    try? FileManager.default.removeItem(at: hero)
    try FileManager.default.copyItem(at: frames.appendingPathComponent(String(format: "%05d.png", heroIndex)), to: hero)

    // GIF with a palette made for these frames; only changed areas are stored per frame.
    let gif = output.appendingPathComponent("demo.gif").path
    let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.fileExists(atPath: $0) } ?? "ffmpeg"
    let filter = "scale=936:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff:max_colors=128[p];[b][p]paletteuse=dither=none:diff_mode=rectangle"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: ffmpeg)
    p.arguments = ["-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", "list.txt", "-vf", filter, "-loop", "0", gif]
    p.currentDirectoryURL = frames
    try p.run()
    p.waitUntilExit()
    print("Wrote \(gif) (\(r.index) frames) and \(hero.path)")
}

// MARK: - Appearance demo

/// `a` and `b` mixed, `t` from 0 (a) to 1 (b).
func blend(_ a: ZestTheme, _ b: ZestTheme, _ t: Double) -> ZestTheme {
    var colors: [ZestTheme.Token: RGBA] = [:]
    for token in ZestTheme.Token.allCases {
        let x = a[token], y = b[token]
        colors[token] = RGBA(red: x.red + (y.red - x.red) * t, green: x.green + (y.green - x.green) * t,
                             blue: x.blue + (y.blue - x.blue) * t)
    }
    return ZestTheme(id: "blend", name: "", appearance: t < 0.5 ? a.appearance : b.appearance, colors: colors)
}

/// docs/images/appearance.gif: the popup changing theme, font, size and rows in place.
@MainActor
func renderAppearance() throws {
    let frames = work.appendingPathComponent("frames")
    try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
    let r = Recorder(frames: frames)
    let term = r.term
    let store = ThemeStore(directories: [root.appendingPathComponent("themes")])
    let ids = ["one-dark-pro-darker", "dracula-theme", "catppuccin-mocha", "tokyo-night", "github-light-default",
               "rose-pine-dawn", "gruvbox-dark-medium", "nord", "one-dark-pro-darker"]
    let themes = ids.compactMap { store.theme(id: $0) }
    term.popup.visibleRows = 6
    term.popup.palette = Palette(themes[0])

    r.frame(0.5)
    r.type("git c", each: 0.09)
    term.caption = ("Theme", themes[0].name)
    r.frame(1.2)

    // Themes, each fading into the next.
    for (i, next) in themes.enumerated().dropFirst() {
        let previous = themes[i - 1]
        for step in 1...8 {
            term.popup.palette = Palette(blend(previous, next, Double(step) / 8))
            r.frame(0.035)
        }
        term.popup.palette = Palette(next)
        term.caption = ("Theme", next.name)
        r.frame(0.55)
        if i < themes.count - 1 { r.press(i % 3 == 2 ? .up : .down, hold: 0.55) } else { r.frame(0.6) }
    }

    // Fonts.
    for name in ["SF Mono", "Monaco", "PT Mono", "Menlo"] {
        term.popup.fontName = name == "SF Mono" ? PopupFont.system : name
        term.caption = ("Font", name)
        r.frame(0.9)
    }

    // Size: grows, then shrinks back.
    term.caption = ("Size", "13")
    for size in Array(stride(from: 13.0, through: 16.0, by: 0.5)) + Array(stride(from: 15.5, through: 13.0, by: -0.5)) {
        term.popup.fontSize = size
        term.caption = ("Size", "\(Int(size.rounded()))")
        r.frame(size == 16 ? 0.8 : 0.06)
    }
    r.frame(0.4)

    // Rows.
    for rows in [3, 4, 5, 6, 7, 8] {
        term.popup.visibleRows = rows
        term.caption = ("Visible rows", "\(rows)")
        r.frame(rows == 3 || rows == 8 ? 0.7 : 0.12)
    }

    // Descriptions off and on.
    term.popup.showDescriptions = false
    term.caption = ("Descriptions", "Off")
    r.frame(1.0)
    term.popup.showDescriptions = true
    term.caption = ("Descriptions", "On")
    r.frame(1.2)

    // macOS switches to Light mode and back: the popup follows with its light theme.
    if let dark = store.theme(id: "one-dark-pro-darker"), let light = store.theme(id: "github-light-default") {
        term.caption = ("macOS Dark mode", "\(dark.name)")
        r.frame(1.0)
        for (from, to, goingLight) in [(dark, light, true), (light, dark, false)] {
            term.caption = goingLight ? ("macOS Light mode", "\(light.name)") : ("macOS Dark mode", "\(dark.name)")
            for step in 1...12 {
                let t = Double(step) / 12
                term.lightness = goingLight ? t : 1 - t
                term.popup.palette = Palette(blend(from, to, t))
                r.frame(0.04)
            }
            term.popup.palette = Palette(to)
            r.frame(goingLight ? 1.8 : 1.4)
        }
    }

    try r.list.write(to: frames.appendingPathComponent("list.txt"), atomically: true, encoding: .utf8)
    let gif = output.appendingPathComponent("appearance.gif").path
    let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.fileExists(atPath: $0) } ?? "ffmpeg"
    let filter = "scale=936:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=full:max_colors=192[p];[b][p]paletteuse=dither=none:diff_mode=rectangle"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: ffmpeg)
    p.arguments = ["-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", "list.txt", "-vf", filter, "-loop", "0", gif]
    p.currentDirectoryURL = frames
    try p.run()
    p.waitUntilExit()
    print("Wrote \(gif) (\(r.index) frames)")
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    IconCache.shared.configure(icons: iconsDir)
    do {
        if CommandLine.arguments.contains("appearance") { try renderAppearance() }
        else { try render() }
    } catch { print("error: \(error)"); exit(1) }
}
