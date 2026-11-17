import Testing
@testable import ZestCore

@Suite struct CompletionControllerTests {
    let controller = CompletionController(engine: Fixtures.engine())

    func line(_ buffer: String, cursor: Int? = nil) -> ShellProtocol.Line {
        .init(session: "s", cwd: "/work", cursor: cursor ?? buffer.unicodeScalars.count, buffer: buffer)
    }

    func type(_ buffer: String) {
        controller.handle(.line(line(buffer)))
    }

    func press(_ key: ShellProtocol.Key, _ buffer: String) -> ShellProtocol.Reply? {
        controller.handle(.key(sequence: "1", key: key, line(buffer)))
    }

    @Test func showsPopupWhileTyping() {
        type("git ch")
        #expect(controller.current.visible)
        #expect(controller.current.selectedItem?.name == "checkout")
    }

    @Test func hiddenForEmptyLine() {
        type("")
        #expect(!controller.current.visible)
        #expect(press(.tab, "") == .pass)
    }

    @Test func tabInsertsSelection() {
        type("git ch")
        #expect(press(.tab, "git ch") == .set(cursor: 13, buffer: "git checkout "))
    }

    @Test func clickedItemIsInsertedByTheNextTab() throws {
        type("git c")
        let items = controller.current.items
        let index = try #require(items.firstIndex { $0.name == "clone" })
        #expect(index != 0)
        #expect(controller.select(index: index))
        #expect(controller.current.selected == index)
        #expect(press(.tab, "git c") == .set(cursor: 10, buffer: "git clone "))
        #expect(!controller.select(index: 99))
    }

    @Test func arrowsMoveSelection() {
        type("git c")
        #expect(press(.down, "git c") == .consumed)
        let second = controller.current.selectedItem?.name
        #expect(press(.up, "git c") == .consumed)
        #expect(controller.current.selected == 0)
        #expect(second != controller.current.items.first?.name)
    }

    @Test func escapeHidesUntilTheLineChanges() {
        type("git c")
        #expect(press(.escape, "git c") == .consumed)
        #expect(!controller.current.visible)
        #expect(press(.tab, "git c") == .pass)
        type("git co")
        #expect(controller.current.visible)
    }

    @Test func positionTravelsWithTheLine() {
        controller.handle(.hello(session: "s", pid: 1, app: "ghostty", historyFile: "/dev/null"))
        let start = ShellProtocol.GridPosition(row: 5, column: 17, rows: 35, columns: 99)
        controller.handle(.position(session: "s", start))
        type("git ch")
        #expect(controller.current.start == start)
    }

    @Test func disconnectHidesThatSessionsPopup() {
        controller.handle(.hello(session: "s", pid: 1, app: "x", historyFile: "/dev/null"))
        type("git ch")
        #expect(controller.current.visible)
        controller.handle(.disconnected(session: "other"))
        #expect(controller.current.visible)
        controller.handle(.disconnected(session: "s"))
        #expect(!controller.current.visible)
        #expect(controller.current.line == nil)
    }

    @Test func hiddenPopupLetsKeysThroughUntilTheLineChanges() {
        type("git ch")
        controller.hide()
        #expect(!controller.current.visible)
        #expect(press(.tab, "git ch") == .pass)
        // Results computed again for the same line (e.g. a generator finished) keep it closed.
        type("git ch")
        #expect(!controller.current.visible)
        type("git che")
        #expect(controller.current.visible)
    }

    @Test func enterAfterSpaceRunsTheCommand() {
        type("git ")
        #expect(controller.current.visible)
        #expect(press(.enter, "git ") == .pass)
    }

    @Test func enterWhileTypingInserts() {
        type("git chec")
        #expect(press(.enter, "git chec") == .set(cursor: 13, buffer: "git checkout "))
    }

    @Test func enterAfterArrowsInserts() {
        type("git ")
        _ = press(.down, "git ")
        #expect(press(.enter, "git ") == .set(cursor: 11, buffer: "git commit "))
    }

    @Test func enterRunsWhenTypedWordIsComplete() {
        type("git -C Desktop/ ")
        type("git commit --amend")
        #expect(press(.enter, "git commit --amend") == .pass)
    }

    @Test func enterBehaviorSettings() {
        controller.settings.enter = .run
        type("git chec")
        #expect(press(.enter, "git chec") == .pass)
        controller.settings.enter = .insert
        type("git ")
        #expect(press(.enter, "git ") == .set(cursor: 13, buffer: "git checkout "))
    }

    @Test func endOfLineHides() {
        type("git c")
        controller.handle(.end(session: "s"))
        #expect(!controller.current.visible)
    }

    @Test func aliasesPerSession() {
        controller.handle(.aliases(session: "s", ["g": "git"]))
        type("g ch")
        #expect(controller.current.selectedItem?.name == "checkout")
    }

    @Test func executedCommandsBecomeHistory() {
        controller.handle(.exec(session: "s", command: "git clone https://example.com/repo"))
        type("git cl")
        #expect(controller.current.items.last?.name == "git clone https://example.com/repo")
    }

    @Test func disabled() {
        controller.settings.enabled = false
        type("git ch")
        #expect(!controller.current.visible)
    }

    @Test func metafiedHistory() throws {
        // How zsh writes "cd Прив": every byte of a non-ASCII character becomes 0x83, byte ^ 0x20.
        var bytes: [UInt8] = Array("cd ".utf8)
        for byte in "Прив".utf8 {
            bytes += byte >= 0x83 ? [0x83, byte ^ 0x20] : [byte]
        }
        let path = try temporaryFile(bytes: bytes + [0x0A])
        var store = HistoryStore()
        store.load(path: path)
        #expect(store.entries == ["cd Прив"])
    }

    @Test func historyFileFormats() throws {
        let path = try temporaryFile(": 1700000000:0;ls -la\n: 1700000001:0;echo one\\\ntwo\nplain command\nls -la\n")
        var store = HistoryStore()
        store.load(path: path)
        #expect(store.entries == ["ls -la", "plain command", "echo one\ntwo"])
    }
}
