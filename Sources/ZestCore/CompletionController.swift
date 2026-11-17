import Foundation

/// The popup's state machine: turns shell messages into suggestions and answers key
/// presses. It knows nothing about windows, so it can be tested without AppKit.
/// Thread-safe: every call runs on one serial queue.
public final class CompletionController: @unchecked Sendable {
    public enum EnterBehavior: String, Sendable, CaseIterable {
        /// Enter inserts the selection only after you moved it with ↑/↓ or while you type
        /// a word; after a space it runs the command.
        case smart
        /// Enter always inserts the selection while the popup is open.
        case insert
        /// Enter always runs the command; use Tab to insert.
        case run
    }

    public struct Settings: Sendable, Equatable {
        public var enter: EnterBehavior = .smart
        public var enabled = true
        public init() {}
    }

    /// What the popup should show.
    public struct State: Sendable, Equatable {
        public var visible: Bool
        public var items: [Completion]
        public var selected: Int
        public var isLoading: Bool
        public var session: String
        /// The terminal app of the session (bundle id or $TERM_PROGRAM).
        public var app: String
        public var shellPID: Int32
        public var line: ShellProtocol.Line?
        /// Where the command line starts, for terminals that report it themselves.
        public var start: ShellProtocol.GridPosition?

        public static let hidden = State(visible: false, items: [], selected: 0, isLoading: false, session: "", app: "", shellPID: 0, line: nil, start: nil)

        public var selectedItem: Completion? { items.indices.contains(selected) ? items[selected] : nil }
    }

    private struct Session {
        var app = ""
        var pid: Int32 = 0
        var aliases: [String: String] = [:]
        var historyFile: String?
        var start: ShellProtocol.GridPosition?
    }

    public let engine: Engine
    public var settings = Settings()
    /// Called on the controller's queue whenever the state changes.
    public var onChange: (@Sendable (State) -> Void)?

    private let queue = DispatchQueue(label: "zest.controller")
    private var sessions: [String: Session] = [:]
    private var history = HistoryStore()
    private var state = State.hidden
    private var result = CompletionResult.empty
    private var navigated = false
    /// Esc hides the popup until the line changes.
    private var dismissedLine: String?

    public init(engine: Engine) {
        self.engine = engine
        engine.generators.onUpdate = { [weak self] in
            guard let self else { return }
            self.queue.async { self.refresh() }
        }
    }

    public var current: State { queue.sync { state } }

    /// Handles a message. Returns the reply for `.key` messages.
    @discardableResult
    public func handle(_ message: ShellProtocol.Message) -> ShellProtocol.Reply? {
        queue.sync { process(message) }
    }

    /// Hides the popup until the command line changes, like Esc; e.g. when the
    /// terminal window closed or changed size.
    public func hide() {
        queue.async {
            self.dismissedLine = self.state.line?.buffer
            self.publish(visible: false)
        }
    }

    /// Makes `index` the selected item, e.g. after a mouse click; the next Tab inserts it.
    /// Returns false when the popup is closed or the index is out of range.
    @discardableResult
    public func select(index: Int) -> Bool {
        queue.sync {
            guard state.visible, state.items.indices.contains(index) else { return false }
            state.selected = index
            navigated = true
            publish(visible: true)
            return true
        }
    }

    /// Accepts an item, e.g. after a mouse click. Returns the new line.
    public func accept(index: Int) -> ShellProtocol.Line? {
        queue.sync {
            guard state.visible, state.items.indices.contains(index), let line = state.line else { return nil }
            state.selected = index
            guard case .set(let cursor, let buffer) = acceptSelected(line) else { return nil }
            return ShellProtocol.Line(session: line.session, cwd: line.cwd, cursor: cursor, buffer: buffer)
        }
    }

    // MARK: - Messages

    private func process(_ message: ShellProtocol.Message) -> ShellProtocol.Reply? {
        switch message {
        case .hello(let session, let pid, let app, let historyFile):
            sessions[session] = Session(app: app, pid: pid, historyFile: historyFile)
            history.load(path: historyFile)
            return nil
        case .aliases(let session, let aliases):
            sessions[session, default: Session()].aliases = aliases
            return nil
        case .line(let line):
            update(line)
            return nil
        case .key(_, let key, let line):
            if line != state.line { update(line) }
            return press(key, line: line)
        case .end(let session):
            if session == state.session {
                dismissedLine = nil
                state.line = nil
                publish(visible: false)
            }
            return nil
        case .exec(_, let command):
            history.add(command)
            return nil
        case .position(let session, let start):
            sessions[session, default: Session()].start = start
            return nil
        case .disconnected(let session):
            sessions[session] = nil
            if session == state.session {
                dismissedLine = nil
                state.line = nil
                publish(visible: false)
            }
            return nil
        }
    }

    private func update(_ line: ShellProtocol.Line) {
        let previous = state.line
        let session = sessions[line.session] ?? Session()
        state.session = line.session
        state.app = session.app
        state.shellPID = session.pid
        state.start = session.start
        state.line = line
        if let dismissed = dismissedLine, dismissed != line.buffer { dismissedLine = nil }
        // A new word starts a new selection.
        if previous?.buffer != line.buffer { navigated = false }
        compute(keepSelection: previous?.buffer == line.buffer)
    }

    private func refresh() {
        guard state.line != nil else { return }
        compute(keepSelection: true)
    }

    private func compute(keepSelection: Bool) {
        guard let line = state.line else { return }
        let session = sessions[line.session] ?? Session()
        guard settings.enabled, !line.buffer.trimmingCharacters(in: .whitespaces).isEmpty,
              !line.buffer.contains("\n") else {
            result = .empty
            publish(visible: false)
            return
        }
        let request = CompletionRequest(
            buffer: line.buffer, cursor: line.cursor, cwd: line.cwd,
            aliases: session.aliases, history: history.entries)
        result = engine.complete(request)
        // Keep the selection only once you moved it; otherwise new results (e.g. from a
        // generator that just finished) start at the top.
        let selectedName = keepSelection && navigated ? state.selectedItem?.name : nil
        state.items = result.items
        state.isLoading = result.isLoading
        state.selected = selectedName.flatMap { name in result.items.firstIndex { $0.name == name } } ?? 0
        publish(visible: shouldShow(line))
    }

    private func shouldShow(_ line: ShellProtocol.Line) -> Bool {
        guard !result.items.isEmpty, dismissedLine == nil else { return false }
        // Nothing to add when the only suggestion is exactly what was typed.
        if result.items.allSatisfy({ $0.insertText == result.query && !result.query.isEmpty }) { return false }
        return true
    }

    private func publish(visible: Bool) {
        state.visible = visible
        onChange?(state)
    }

    // MARK: - Keys

    private func press(_ key: ShellProtocol.Key, line: ShellProtocol.Line) -> ShellProtocol.Reply {
        guard state.visible, !state.items.isEmpty else { return .pass }
        switch key {
        case .up:
            if state.selected > 0 { state.selected -= 1 }
            navigated = true
            publish(visible: true)
            return .consumed
        case .down:
            if state.selected < state.items.count - 1 { state.selected += 1 }
            navigated = true
            publish(visible: true)
            return .consumed
        case .escape:
            dismissedLine = line.buffer
            publish(visible: false)
            return .consumed
        case .tab:
            return acceptSelected(line)
        case .enter:
            switch settings.enter {
            case .run:
                publish(visible: false)
                return .pass
            case .insert:
                return acceptSelected(line)
            case .smart:
                // After a space nothing is being typed: Enter runs the command,
                // unless you picked something with the arrows.
                if navigated || !result.query.isEmpty {
                    if state.selectedItem?.insertText == result.query && !navigated {
                        publish(visible: false)
                        return .pass
                    }
                    return acceptSelected(line)
                }
                publish(visible: false)
                return .pass
            }
        }
    }

    private func acceptSelected(_ line: ShellProtocol.Line) -> ShellProtocol.Reply {
        guard let item = state.selectedItem else { return .pass }
        let applied = Engine.apply(item, buffer: line.buffer, cursor: line.cursor)
        engine.usage?.record(item.usageKey)
        navigated = false
        publish(visible: false)
        return .set(cursor: applied.cursor, buffer: applied.buffer)
    }
}

/// Commands from the zsh history file plus the ones run since the app started.
struct HistoryStore {
    private(set) var entries: [String] = []
    private var loaded: Set<String> = []
    static let limit = 5000

    mutating func load(path: String) {
        guard !path.isEmpty, loaded.insert(path).inserted,
              let data = FileManager.default.contents(atPath: path) else { return }
        let text = String(decoding: Self.unmetafy(data), as: UTF8.self)
        var commands: [String] = []
        var pending = ""
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            if pending.isEmpty, line.hasPrefix(": "), let semicolon = line.firstIndex(of: ";") {
                // Extended history: ": 1700000000:0;command".
                line = String(line[line.index(after: semicolon)...])
            }
            if line.hasSuffix("\\") {
                pending += line.dropLast() + "\n"
                continue
            }
            let command = pending + line
            pending = ""
            if !command.isEmpty { commands.append(command) }
        }
        var seen = Set(entries)
        var merged = entries
        for command in commands.reversed() where seen.insert(command).inserted {
            merged.append(command)
            if merged.count >= Self.limit { break }
        }
        entries = merged
    }

    /// zsh stores history "metafied": a byte that has a special meaning to zsh
    /// (0x83–0xFF and a few others, so every byte of non-ASCII UTF-8 such as Cyrillic)
    /// is written as 0x83 followed by the byte XOR 0x20.
    static func unmetafy(_ data: Data) -> Data {
        guard data.contains(0x83) else { return data }
        var out = Data(capacity: data.count)
        var meta = false
        for byte in data {
            if meta {
                out.append(byte ^ 0x20)
                meta = false
            } else if byte == 0x83 {
                meta = true
            } else {
                out.append(byte)
            }
        }
        return out
    }

    mutating func add(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.removeAll { $0 == trimmed }
        entries.insert(trimmed, at: 0)
        if entries.count > Self.limit { entries.removeLast() }
    }
}
