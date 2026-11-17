import ArgumentParser
import Foundation
import ZestCore

@main
struct Zest: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "zest",
        abstract: "Autocomplete popup for zsh on macOS.",
        discussion: "The popup itself runs in Zest.app. This tool helps you write and check specs.",
        version: ZestVersion.current,
        subcommands: [Complete.self, Validate.self, Gen.self, BuildSpecs.self, Init.self, Doctor.self, Serve.self, ThemeCommand.self]
    )
}

struct SpecOptions: ParsableArguments {
    @ArgumentParser.Option(name: .customLong("specs"), help: "Extra spec folder, searched first. Can be repeated.")
    var specDirs: [String] = []

    func store() -> SpecStore {
        var dirs = specDirs.map { URL(fileURLWithPath: $0, isDirectory: true) }
        dirs += SpecStore.defaultDirectories(builtIn: Paths.builtInSpecs)
        return SpecStore(directories: dirs)
    }
}

// MARK: - complete

struct Complete: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print the suggestions for a command line.",
        discussion: "Example: zest complete 'git checkout '")

    @Argument(help: "The command line, as typed.")
    var buffer: String

    @ArgumentParser.Option(help: "Cursor position. Default: end of the line.")
    var cursor: Int?

    @ArgumentParser.Option(help: "Working directory. Default: the current one.")
    var cwd: String = FileManager.default.currentDirectoryPath

    @ArgumentParser.Option(help: "How many suggestions to print.")
    var limit = 20

    @OptionGroup var specs: SpecOptions

    func run() throws {
        let runner = GeneratorRunner()
        runner.synchronous = true
        let engine = Engine(store: specs.store(), generators: runner)
        let result = engine.complete(CompletionRequest(buffer: buffer, cursor: cursor, cwd: cwd))
        if result.items.isEmpty {
            print("(no suggestions)")
            return
        }
        let width = min(40, result.items.prefix(limit).map(\.name.count).max() ?? 0)
        for item in result.items.prefix(limit) {
            let name = item.name.padding(toLength: max(width, item.name.count), withPad: " ", startingAt: 0)
            let kind = item.kind.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)
            print("\(kind) \(name)  \(item.description ?? "")")
        }
        if result.items.count > limit { print("… \(result.items.count - limit) more") }
    }
}

// MARK: - validate

struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check that spec files load, and report mistakes.",
        discussion: "With no paths, checks your own specs in ~/.config/zest/specs.")

    @Argument(help: "Spec files or folders.")
    var paths: [String] = []

    @Flag(help: "Only print problems.")
    var quiet = false

    @Flag(help: "Also type typical command lines for each spec and check the suggestions (no scripts are run).")
    var deep = false

    func run() throws {
        let targets = paths.isEmpty ? [SpecStore.userSpecsDirectory.path] : paths
        var files: [URL] = []
        for path in targets {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
                throw ValidationError("\(path): no such file or folder")
            }
            if isDir.boolValue {
                let root = URL(fileURLWithPath: path, isDirectory: true)
                let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
                while let url = e?.nextObject() as? URL {
                    if ["yaml", "yml"].contains(url.pathExtension) { files.append(url) }
                }
            } else {
                files.append(URL(fileURLWithPath: path))
            }
        }
        files.sort { $0.path < $1.path }
        var problems = 0
        for url in files {
            let issues = SpecLinter.lint(url: url)
            if issues.isEmpty {
                if !quiet { print("ok    \(url.path)") }
            } else {
                problems += issues.count
                for issue in issues { print("error \(url.path): \(issue)") }
            }
        }
        if deep { problems += runDeep(files) }
        print("\(files.count) spec files checked, \(problems) problems.")
        if problems > 0 { throw ExitCode.failure }
    }
}

extension Validate {
    /// Simulates typing for every top-level spec. Nested files are reached through `loadSpec`.
    func runDeep(_ files: [URL]) -> Int {
        var byRoot: [URL: [String]] = [:]
        for path in paths.isEmpty ? [SpecStore.userSpecsDirectory.path] : paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            let root = isDir.boolValue ? url : url.deletingLastPathComponent()
            let names: [String]
            if isDir.boolValue {
                names = ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
                    .filter { ["yaml", "yml"].contains(($0 as NSString).pathExtension) }
                    .map { ($0 as NSString).deletingPathExtension }
            } else {
                names = [url.deletingPathExtension().lastPathComponent]
            }
            byRoot[root, default: []] += names
        }
        var count = 0
        for (root, names) in byRoot {
            let simulator = SpecSimulator(directories: [root])
            for name in names.sorted() {
                let problems = simulator.check(name)
                for problem in problems { print("deep  \(problem)") }
                count += problems.count
            }
        }
        return count
    }
}

// MARK: - gen

struct Gen: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Draft a spec from a command's --help output.",
        discussion: """
        Writes ~/.config/zest/specs/<command>.yaml (or --out). The draft is a starting point:
        check it, fix descriptions and add generators by hand. Subcommands that might
        do something (install, delete, ...) are listed but never run.
        """)

    @Argument(help: "Commands to generate specs for.")
    var commands: [String]

    @ArgumentParser.Option(help: "How many levels of subcommands to read.")
    var depth = 2

    @ArgumentParser.Option(help: "Output folder.")
    var out: String = SpecStore.userSpecsDirectory.path

    @Flag(help: "Overwrite existing files.")
    var force = false

    func run() throws {
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let shell = ProcessShellRunner()
        for command in commands {
            let target = URL(fileURLWithPath: out).appendingPathComponent(command + ".yaml")
            if FileManager.default.fileExists(atPath: target.path) && !force {
                print("\(target.path) exists; use --force to overwrite")
                continue
            }
            let spec = HelpParser.generate(command: command, depth: depth) { argv in
                let result = shell.run(.argv(argv), cwd: NSHomeDirectory(), timeout: 15)
                return result.stdout.isEmpty ? result.stderr : result.stdout
            }
            guard let spec else {
                print("\(command): could not read its --help output, skipped")
                continue
            }
            let yaml = try SpecStore.encodeYAML(spec)
            try ("# Generated by `zest gen \(command)`. Review and edit it.\n# yaml-language-server: $schema=https://raw.githubusercontent.com/rostik32/zest/main/schema/spec.schema.json\n" + yaml)
                .write(to: target, atomically: true, encoding: .utf8)
            print("\(target.path): \(spec.subcommands?.count ?? 0) subcommands, \(spec.options?.count ?? 0) options")
        }
    }
}

// MARK: - build-specs

struct BuildSpecs: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build-specs",
        abstract: "Compile YAML specs to JSON for the app bundle (used by the build).")

    @ArgumentParser.Option(help: "Folder with YAML specs.")
    var from: String

    @ArgumentParser.Option(help: "Output folder.")
    var to: String

    func run() throws {
        let source = URL(fileURLWithPath: from, isDirectory: true).standardizedFileURL
        let target = URL(fileURLWithPath: to, isDirectory: true)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        var index: [SpecStore.CommandInfo] = []
        var count = 0
        var failures: [String] = []
        let e = FileManager.default.enumerator(at: source, includingPropertiesForKeys: nil)
        while let url = e?.nextObject() as? URL {
            let relative = String(url.standardizedFileURL.path.dropFirst(source.path.count + 1))
            let name = (relative as NSString).deletingPathExtension
            let out = target.appendingPathComponent(name)
            switch url.pathExtension {
            case "yaml", "yml":
                do {
                    let spec = try SpecStore.load(url: url)
                    try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try SpecStore.encodeJSON(spec).write(to: out.appendingPathExtension("json"))
                    if !name.contains("/") {
                        index.append(SpecStore.CommandInfo(name: name, description: spec.description, icon: spec.icon))
                    }
                    count += 1
                } catch {
                    failures.append("\(relative): \(SpecStore.describe(error))")
                }
            case "js":
                try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: url, to: out.appendingPathExtension("js"))
            default:
                break
            }
        }
        index.sort { $0.name < $1.name }
        try JSONEncoder().encode(index).write(to: target.appendingPathComponent("index.json"))
        print("Compiled \(count) specs to \(target.path)")
        if !failures.isEmpty {
            failures.forEach { print("error \($0)") }
            throw ExitCode.failure
        }
    }
}

// MARK: - init

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print the zsh integration script.",
        discussion: "Add `source <(zest init zsh)` to ~/.zshrc, or let Zest.app set it up for you.")

    @Argument(help: "Shell. Only zsh is supported.")
    var shell: String

    func run() throws {
        guard shell == "zsh" else { throw ValidationError("only zsh is supported") }
        guard let url = Paths.zshScript else { throw ValidationError("zest.zsh not found; reinstall Zest.app") }
        print(try String(contentsOf: url, encoding: .utf8), terminator: "")
    }
}

// MARK: - doctor

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check that zest is set up correctly.")

    func run() throws {
        func line(_ ok: Bool, _ text: String) { print((ok ? "✓ " : "✗ ") + text) }
        let specs = Paths.builtInSpecs
        line(specs != nil, "Built-in specs: \(specs?.path ?? "not found")")
        line(true, "Your specs: \(SpecStore.userSpecsDirectory.path)")
        let zshrc = (try? String(contentsOfFile: NSHomeDirectory() + "/.zshrc", encoding: .utf8)) ?? ""
        line(zshrc.contains("zest"), "~/.zshrc loads zest")
        line(FileManager.default.fileExists(atPath: Paths.socket.path), "Zest.app is running (\(Paths.socket.path))")
        line(ProcessInfo.processInfo.environment["ZEST_SESSION"] != nil, "This shell is connected to zest")
    }
}

// MARK: - serve

struct Serve: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run the completion server without the popup and print what it would show.",
        discussion: """
        For debugging specs and the zsh integration: start this, then in another terminal run
        `ZEST_SOCKET=<path> zsh` and type. Used by scripts/test-zsh.sh.
        """)

    @ArgumentParser.Option(help: "Socket path.")
    var socket: String = Paths.socket.path + ".debug"

    @OptionGroup var specs: SpecOptions

    func run() throws {
        let engine = Engine(store: specs.store())
        let controller = CompletionController(engine: engine)
        controller.onChange = { state in
            let line = state.line.map { "\($0.buffer)|" } ?? ""
            if state.visible {
                let items = state.items.prefix(5).enumerated()
                    .map { ($0.offset == state.selected ? ">" : " ") + $0.element.name }
                print("popup [\(line)] " + items.joined(separator: " "))
            } else {
                print("hidden [\(line)]")
            }
            fflush(stdout)
        }
        let server = SocketServer(path: socket) { message in
            switch message {
            case .position(_, let p):
                print("position \(p.row);\(p.column) at \(p.cursor) of \(p.rows)x\(p.columns)")
                fflush(stdout)
            case .disconnected:
                print("disconnected")
                fflush(stdout)
            default:
                break
            }
            return controller.handle(message)
        }
        try server.start()
        print("listening on \(socket)")
        fflush(stdout)
        signal(SIGINT) { _ in Foundation.exit(0) }
        signal(SIGTERM) { _ in Foundation.exit(0) }
        dispatchMain()
    }
}

// MARK: - theme

struct ThemeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "theme",
        abstract: "List themes, or import VS Code themes.",
        subcommands: [List.self, Import.self, Editor.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List the themes zest can use.")

        @ArgumentParser.Option(help: "Theme folder to read instead of the usual ones. Can be repeated.")
        var from: [String] = []

        func run() {
            let store = from.isEmpty ? ThemeStore() : ThemeStore(directories: from.map { URL(fileURLWithPath: $0) })
            for theme in store.all() {
                print("\(theme.id.padding(toLength: 34, withPad: " ", startingAt: 0)) \(theme.appearance.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0)) \(theme.name)")
            }
        }
    }

    struct Import: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Convert VS Code color themes into zest themes.",
            discussion: """
            Give a theme's .json file, or an extension folder (with package.json) to import every \
            theme it contributes. Themes are written to ~/.config/zest/themes, where zest finds them.
            """)

        @Argument(help: "Theme .json files or extension folders.")
        var paths: [String]

        @ArgumentParser.Option(help: "Name for the theme (only with a single .json file).")
        var name: String?

        @ArgumentParser.Option(help: "Output folder.")
        var out: String = ThemeStore.userDirectory.path

        @ArgumentParser.Option(help: "Where the themes come from, saved in each file, e.g. \"Dracula (MIT)\".")
        var source: String?

        @ArgumentParser.Option(help: "Text added to each theme's name, e.g. \" (VS Code)\".")
        var suffix: String = ""

        func run() throws {
            let outURL = URL(fileURLWithPath: out, isDirectory: true)
            for path in paths {
                let url = URL(fileURLWithPath: path)
                var themes: [ZestTheme] = []
                if url.pathExtension == "json" {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    let base = url.deletingLastPathComponent()
                    themes.append(try VSCodeTheme.convert(json: text, name: name, source: source) { include in
                        try String(contentsOf: base.appendingPathComponent(include).standardizedFileURL, encoding: .utf8)
                    })
                } else {
                    let contributed = VSCodeExtension.themes(in: url)
                    if contributed.isEmpty { throw ValidationError("\(path): no themes found (expected a .json file or an extension folder with package.json)") }
                    for theme in contributed { themes.append(try VSCodeExtension.convert(theme, source: source)) }
                }
                for var theme in themes {
                    if !suffix.isEmpty {
                        theme.name += suffix
                        theme.id = ZestTheme.slug(theme.name)
                    }
                    let file = try ThemeStore.save(theme, to: outURL)
                    print("\(theme.appearance.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0)) \(theme.name) -> \(file.path)")
                }
            }
        }
    }

    struct Editor: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show the theme VS Code or Cursor is using, as zest sees it.")

        @Argument(help: "vscode or cursor.")
        var editor: String = "vscode"

        @Flag(help: "Assume macOS is in Light mode.")
        var light = false

        func run() throws {
            guard let which = EditorTheme.Editor(rawValue: editor) else { throw ValidationError("editor must be vscode or cursor") }
            let name = EditorTheme.name(for: which, darkMode: !light)
            print("\(editor) uses \"\(name)\"")
            guard let theme = EditorTheme.current(for: which, darkMode: !light) else {
                print("Theme files not found in the editor's extension folders.")
                throw ExitCode(1)
            }
            print(theme.yaml, terminator: "")
        }
    }
}
