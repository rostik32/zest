import Foundation

/// Builds a spec draft from a command's `--help` output. Used by `zest gen`.
///
/// Help output has no standard format, so this is a best effort: it recognises the
/// common layouts (GNU, cobra, clap, yargs, click) and produces a starting point you
/// then edit by hand.
public enum HelpParser {
    /// Subcommands that are listed but never run with `--help`, in case a CLI ignores
    /// `--help` and does something.
    public static let doNotIntrospect: Set<String> = [
        "help", "update", "upgrade", "install", "uninstall", "purge", "rm", "remove",
        "delete", "stop", "kill", "respawn", "setup-token", "gateway", "attach", "logs",
        "import", "login", "logout", "reset", "destroy", "deploy", "publish", "push",
    ]

    public struct Result: Equatable {
        public var options: [Option]
        public var subcommands: [Subcommand]
    }

    /// Runs `argv --help` and parses it, recursing into subcommands up to `depth` levels.
    public static func generate(
        command: String, depth: Int, run: (_ argv: [String]) -> String
    ) -> Spec? {
        let result = build([command], depth: depth, run: run)
        guard !result.options.isEmpty || !result.subcommands.isEmpty else { return nil }
        var spec = Spec(name: Names(command))
        spec.options = result.options.isEmpty ? nil : result.options
        spec.subcommands = result.subcommands.isEmpty ? nil : result.subcommands
        if spec.subcommands == nil {
            spec.args = OneOrMany(Arg(name: "args", isOptional: true, isVariadic: true, template: OneOrMany(.filepaths)))
        }
        return spec
    }

    private static func build(_ argv: [String], depth: Int, run: ([String]) -> String) -> Result {
        let text = run(argv + ["--help"])
        var result = parse(text, programWords: Set(argv.map { ($0 as NSString).lastPathComponent }))
        guard depth > 0 else { return result }
        for i in result.subcommands.indices {
            let name = result.subcommands[i].name.first
            if doNotIntrospect.contains(name) { continue }
            let sub = build(argv + [name], depth: depth - 1, run: run)
            if !sub.options.isEmpty { result.subcommands[i].options = sub.options }
            if !sub.subcommands.isEmpty { result.subcommands[i].subcommands = sub.subcommands }
        }
        return result
    }

    // MARK: - Parsing

    private static let optionPattern = try! NSRegularExpression(pattern: #"^(-{1,2}[\w?#][\w?#.-]*)(?:[= ]([A-Z][A-Z0-9_-]*)\b)?"#)
    private static let argPattern = try! NSRegularExpression(pattern: #"([<\[])([^>\]]+)[>\]]"#)
    private static let commandPattern = try! NSRegularExpression(pattern: #"^[a-z][\w:|.-]*"#)

    private enum Mode { case options, commands }

    private final class Entry {
        var names: [String]
        var args: [Arg]
        var description: String?
        let isOption: Bool

        init(names: [String], args: [Arg], description: String?, isOption: Bool) {
            self.names = names
            self.args = args
            self.description = description
            self.isOption = isOption
        }
    }

    public static func parse(_ text: String, programWords: Set<String> = []) -> Result {
        var options: [Entry] = []
        var commands: [Entry] = []
        var mode: Mode?
        var entryIndent: Int?
        var last: Entry?
        var lastIndent = 0

        for rawLine in text.replacingOccurrences(of: "\t", with: "    ").components(separatedBy: .newlines) {
            let line = stripANSI(rawLine)
            let stripped = line.trimmingCharacters(in: .whitespaces)
            guard !stripped.isEmpty else { continue }
            let indent = line.prefix(while: { $0 == " " }).count

            if isHeader(stripped, indent: indent) {
                // "HELP TOPICS" (gh, go) are not commands you can run.
                let isCommands = stripped.range(of: "command", options: .caseInsensitive) != nil
                    && stripped.range(of: "topic", options: .caseInsensitive) == nil
                mode = isCommands ? .commands : .options
                entryIndent = nil
                last = nil
                continue
            }
            let parts = splitColumns(stripped)
            let head = parts.head
            let desc = parts.description

            // Options are recognised anywhere: many CLIs list them without a header.
            if indent <= 10, head.range(of: #"^-{1,2}[\w?#]"#, options: .regularExpression) != nil,
               let entry = parseOption(head) {
                entry.description = desc.isEmpty ? nil : desc
                options.append(entry)
                last = entry
                lastIndent = indent
                continue
            }
            if let previous = last, indent > lastIndent {
                // A wrapped description of the previous entry.
                append(previous, stripped, replaceOnly: indent - lastIndent < 10)
                continue
            }
            last = nil
            guard mode == .commands, indent > 0 else {
                if indent == 0 { mode = nil }
                continue
            }
            if entryIndent == nil { entryIndent = indent }

            // npm lists its commands as a paragraph: "access, adduser, audit, bugs, …".
            if parts.description.isEmpty, stripped.contains(", "),
               stripped.range(of: #"^[a-z][\w-]*(, [a-z][\w-]*)*,?$"#, options: .regularExpression) != nil {
                for name in stripped.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !name.isEmpty {
                    commands.append(Entry(names: [name], args: [], description: nil, isOption: false))
                }
                continue
            }

            // yargs prints `gemini mcp  Manage MCP servers`: drop the program path.
            var words = head.split(separator: " ").map(String.init)
            while words.count > 1, programWords.contains(words[0]) { words.removeFirst() }
            let commandHead = words.joined(separator: " ")
            guard indent == entryIndent, matches(commandPattern, commandHead) else { continue }

            // gh writes "auth:", docker marks plugins with "compose*".
            let word = words[0].trimmingCharacters(in: CharacterSet(charactersIn: ":*"))
            let rest = words.dropFirst().joined(separator: " ")
            let names = word.split(separator: "|").map(String.init).filter { !$0.isEmpty }
            guard !names.isEmpty else { continue }
            let args = parseArgs(rest).filter {
                !["options", "command", "flags"].contains(($0.name ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "-")))
            }
            let entry = Entry(names: names, args: args, description: desc.isEmpty ? nil : desc, isOption: false)
            commands.append(entry)
            last = entry
            lastIndent = indent
        }

        return Result(
            options: options.map {
                var o = Option(name: Names($0.names), description: $0.description)
                if !$0.args.isEmpty { o.args = OneOrMany($0.args) }
                return o
            },
            subcommands: commands.map {
                var s = Subcommand(name: Names($0.names), description: $0.description)
                if !$0.args.isEmpty { s.args = OneOrMany($0.args) }
                return s
            })
    }

    private static func isHeader(_ s: String, indent: Int) -> Bool {
        if indent > 4 || s.contains("  ") || s.hasPrefix("-") { return false }
        let words = s.split(separator: " ")
        if s.hasSuffix(":") { return words.count <= 5 }
        // "Available Commands", "Subcommands" without a colon (cobra, VS Code).
        if words.count <= 3, words.allSatisfy({ $0.first?.isUppercase == true }), s.last?.isLetter == true {
            return true
        }
        return s == s.uppercased() && s.contains(where: \.isLetter) && words.count <= 4
    }

    private static func splitColumns(_ s: String) -> (head: String, description: String) {
        guard let range = s.range(of: #"\s{2,}"#, options: .regularExpression) else { return (s, "") }
        return (String(s[..<range.lowerBound]), s[range.upperBound...].trimmingCharacters(in: .whitespaces))
    }

    private static func parseOption(_ head: String) -> Entry? {
        var names: [String] = []
        var args = parseArgs(head)
        for part in head.split(separator: ",") {
            let token = part.trimmingCharacters(in: .whitespaces)
            let ns = token as NSString
            guard let m = optionPattern.firstMatch(in: token, range: NSRange(location: 0, length: ns.length)) else { continue }
            names.append(ns.substring(with: m.range(at: 1)))
            // GNU style: `--threads=NUM`, `-o FILE`.
            if m.range(at: 2).location != NSNotFound, args.isEmpty {
                args.append(Arg(name: ns.substring(with: m.range(at: 2))))
            }
        }
        guard !names.isEmpty else { return nil }
        return Entry(names: names, args: args, description: nil, isOption: true)
    }

    private static func parseArgs(_ text: String) -> [Arg] {
        let ns = text as NSString
        return argPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            let bracket = ns.substring(with: m.range(at: 1))
            let name = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            var arg = Arg(name: name.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
            if bracket == "[" { arg.isOptional = true }
            if name.hasSuffix("...") { arg.isVariadic = true }
            return arg
        }
    }

    private static func append(_ entry: Entry, _ text: String, replaceOnly: Bool) {
        if entry.description?.isEmpty ?? true {
            entry.description = text
        } else if !replaceOnly, let d = entry.description, d.count < 200 {
            entry.description = d + " " + text
        }
    }

    private static func matches(_ regex: NSRegularExpression, _ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    static func stripANSI(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1b}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
    }
}
