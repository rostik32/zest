import Foundation
@testable import ZestCore

struct FakeFileSystem: FileSystem {
    var tree: [String: [FileEntry]]
    var homeDirectory = "/Users/me"

    func list(_ path: String) -> [FileEntry] {
        var key = path
        while key.count > 1 && key.hasSuffix("/") { key.removeLast() }
        return tree[key] ?? []
    }
}

struct FakeShell: ShellRunner {
    var outputs: [String: String]

    func run(_ script: Script, cwd: String, timeout: TimeInterval) -> ShellResult {
        let key: String
        switch script {
        case .shell(let s): key = s
        case .argv(let a): key = a.joined(separator: " ")
        }
        return ShellResult(stdout: outputs[key] ?? "")
    }
}

enum Fixtures {
    static var specs: URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures/specs")
    }

    /// The real icon assets in the repository.
    static var iconDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../assets/icons/material").standardized
    }

    static var iconIndex: URL {
        iconDirectory.deletingLastPathComponent().appendingPathComponent("material.json")
    }

    static let fileSystem = FakeFileSystem(tree: [
        "/work": [
            FileEntry(name: "Desktop", isDirectory: true),
            FileEntry(name: "Documents", isDirectory: true),
            FileEntry(name: "My Doc.txt", isDirectory: false),
            FileEntry(name: ".hidden", isDirectory: false),
            FileEntry(name: "notes.md", isDirectory: false),
        ],
        "/work/Desktop": [
            FileEntry(name: "graphio", isDirectory: true),
            FileEntry(name: "client", isDirectory: true),
            FileEntry(name: "todo.txt", isDirectory: false),
        ],
        "/Users/me": [FileEntry(name: "Projects", isDirectory: true)],
    ])

    static func engine(
        shell: [String: String] = ["git branch": "main\nfeature/x\n", "list-items": "a,b", "other-items": "x,y"],
        usage: UsageStore? = nil
    ) -> Engine {
        let runner = GeneratorRunner(shell: FakeShell(outputs: shell))
        runner.synchronous = true
        var settings = EngineSettings()
        settings.pathCommands = false
        return Engine(
            store: SpecStore(directories: [specs]), generators: runner,
            fileSystem: fileSystem, settings: settings, usage: usage)
    }
}

extension Engine {
    func names(_ buffer: String, aliases: [String: String] = [:], history: [String] = []) -> [String] {
        complete(CompletionRequest(buffer: buffer, cwd: "/work", aliases: aliases, history: history)).items.map(\.name)
    }

    func first(_ buffer: String) -> Completion? {
        complete(CompletionRequest(buffer: buffer, cwd: "/work")).items.first
    }
}

/// Writes `contents` to a new temporary file and returns its path.
/// (Test files that import both Testing and Foundation need Xcode, so file helpers live here.)
func temporaryFile(_ contents: String) throws -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zest-test-\(UUID().uuidString)")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url.path
}

func temporaryDirectory() throws -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zest-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.path
}

/// Writes a file. `modified` moves its modification date into the future by that many
/// seconds, so a change is visible even within the same second.
func write(_ text: String, to path: String, modified: TimeInterval = 0) throws {
    try text.write(toFile: path, atomically: true, encoding: .utf8)
    if modified != 0 { try touch(path, modified: modified) }
}

func touch(_ path: String, modified: TimeInterval) throws {
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(modified)], ofItemAtPath: path)
}

func specStore(_ dir: String) -> SpecStore {
    SpecStore(directories: [URL(fileURLWithPath: dir)])
}

func temporaryFile(bytes: [UInt8]) throws -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("zest-test-\(UUID().uuidString)")
    try Data(bytes).write(to: url)
    return url.path
}

enum TempFiles {
    /// A new folder with the given files (relative path -> contents).
    static func folder(_ files: [String: String]) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zest-test-\(UUID().uuidString)")
        for (path, text) in files {
            let url = dir.appendingPathComponent(path)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
        return dir
    }

    /// The themes that ship with zest (themes/ in the repository).
    static var bundledThemes: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../themes").standardized
    }
}
