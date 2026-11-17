import Foundation
import Yams

/// Finds and loads specs. Specs are read lazily, the first time a command is typed.
///
/// Directories are searched in order, so a spec in the user's folder
/// (`~/.config/zest/specs`) overrides a built-in spec with the same name.
public final class SpecStore: @unchecked Sendable {
    public struct CommandInfo: Codable, Sendable, Equatable {
        public var name: String
        public var description: String?
        public var icon: String?

        public init(name: String, description: String?, icon: String?) {
            self.name = name
            self.description = description
            self.icon = icon
        }
    }

    public let directories: [URL]
    private let lock = NSLock()
    private struct Cached {
        var spec: Spec
        var url: URL
        var modified: Date?
    }

    private var cache: [String: Cached] = [:]
    private var indexStamp: [Date?] = []
    private var commandIndex: [String: CommandInfo]?
    private var errors: [String: String] = [:]

    public static let extensions = ["yaml", "yml", "json"]

    public init(directories: [URL]) {
        self.directories = directories
    }

    /// The default search path: user specs first, then the specs shipped with zest.
    public static func defaultDirectories(builtIn: URL?) -> [URL] {
        var dirs = [userSpecsDirectory]
        if let builtIn { dirs.append(builtIn) }
        return dirs
    }

    public static var userSpecsDirectory: URL {
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        return base.appendingPathComponent("zest/specs")
    }

    public func reload() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
        commandIndex = nil
        errors.removeAll()
    }

    /// The last load error for a spec, if any. Shown by `zest validate` and in the app.
    public func loadError(for name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return errors[name]
    }

    /// Loads a spec by name. `name` may contain `/` for specs split into files, e.g. `aws/s3`.
    public func spec(named name: String) -> Spec? {
        guard Self.isValidName(name) else { return nil }
        let url = file(for: name)
        let modified = url.flatMap(Self.modificationDate)
        lock.lock()
        // Reuse the parsed spec while its file is unchanged, so edits apply right away.
        if let cached = cache[name], cached.url == url, cached.modified == modified {
            lock.unlock()
            return cached.spec
        }
        lock.unlock()
        guard let url else { return nil }

        var result: Spec?
        var error: String?
        do {
            result = try Self.load(url: url)
        } catch let loadError {
            error = Self.describe(loadError)
        }

        lock.lock()
        defer { lock.unlock() }
        if let result {
            cache[name] = Cached(spec: result, url: url, modified: modified)
            errors[name] = nil
        } else {
            cache[name] = nil
        }
        if let error { errors[name] = error }
        return result
    }

    /// The JavaScript companion of a spec, used by specs imported from Fig.
    public func companionScript(for name: String) -> URL? {
        for dir in directories {
            let url = dir.appendingPathComponent(name + ".js")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// The file a spec is loaded from.
    public func file(for name: String) -> URL? {
        for dir in directories {
            for ext in Self.extensions {
                let url = dir.appendingPathComponent(name + "." + ext)
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    /// All top-level commands that have a spec, with descriptions for the popup.
    public func commands() -> [String: CommandInfo] {
        // Rebuild when a spec folder changed (a file was added, removed or renamed).
        let stamp = directories.map(Self.modificationDate)
        lock.lock()
        if let index = commandIndex, stamp == indexStamp { lock.unlock(); return index }
        lock.unlock()

        var index: [String: CommandInfo] = [:]
        // Later directories have lower priority, so read them first and overwrite.
        for dir in directories.reversed() {
            let indexFile = dir.appendingPathComponent("index.json")
            if let data = try? Data(contentsOf: indexFile),
               let entries = try? JSONDecoder().decode([CommandInfo].self, from: data) {
                for entry in entries { index[entry.name] = entry }
                continue
            }
            let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
                .filter { Self.extensions.contains(($0 as NSString).pathExtension) && $0 != "index.json" }
            // Without an index, read descriptions only from small folders (your own specs);
            // parsing a thousand YAML files would freeze the popup.
            let readDescriptions = files.count <= 200
            for file in files {
                let url = dir.appendingPathComponent(file)
                let name = url.deletingPathExtension().lastPathComponent
                let spec = readDescriptions ? try? Self.load(url: url) : nil
                index[name] = CommandInfo(name: name, description: spec?.description, icon: spec?.icon)
            }
        }

        lock.lock()
        commandIndex = index
        indexStamp = stamp
        lock.unlock()
        return index
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    // MARK: - Decoding

    public static func load(url: URL) throws -> Spec {
        let data = try Data(contentsOf: url)
        return try decode(data, isJSON: url.pathExtension == "json")
    }

    public static func decode(_ data: Data, isJSON: Bool) throws -> Spec {
        if isJSON {
            return try JSONDecoder().decode(Spec.self, from: data)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw SpecError.invalidEncoding
        }
        return try YAMLDecoder().decode(Spec.self, from: text)
    }

    public static func encodeYAML(_ spec: Spec) throws -> String {
        let encoder = YAMLEncoder()
        encoder.options.width = -1
        encoder.options.sortKeys = false
        // YAML 1.1 readers (editors, the schema check) take a bare y, n, yes, no, on or off
        // as a boolean: quote them, e.g. the argument of `-j n`.
        return try encoder.encode(spec).replacingOccurrences(
            of: #"(?m)^(\s*(?:- )?(?:[\w-]+: )?)(y|Y|n|N|yes|Yes|YES|no|No|NO|on|On|ON|off|Off|OFF)$"#,
            with: "$1'$2'", options: .regularExpression)
    }

    public static func encodeJSON(_ spec: Spec) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(spec)
    }

    static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("/") && !name.contains("..") && !name.contains("\0")
    }

    public static func describe(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx), .dataCorrupted(let ctx):
                return "\(path(ctx.codingPath)): \(ctx.debugDescription)"
            case .keyNotFound(let key, let ctx):
                return "\(path(ctx.codingPath + [key])): missing required field"
            @unknown default:
                return String(describing: error)
            }
        }
        return String(describing: error)
    }

    private static func path(_ keys: [CodingKey]) -> String {
        let parts = keys.map { $0.intValue.map { "[\($0)]" } ?? "." + $0.stringValue }
        let joined = parts.joined()
        return joined.isEmpty ? "(root)" : String(joined.drop(while: { $0 == "." }))
    }
}

public enum SpecError: Error, CustomStringConvertible {
    case invalidEncoding

    public var description: String {
        switch self {
        case .invalidEncoding: return "the file is not valid UTF-8"
        }
    }
}
