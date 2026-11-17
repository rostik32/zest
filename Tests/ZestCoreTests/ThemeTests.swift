import Testing
@testable import ZestCore

@Suite struct ThemeTests {
    @Test func parsesColors() {
        #expect(RGBA(hex: "#1E2227") == RGBA(red: 30.0 / 255, green: 34.0 / 255, blue: 39.0 / 255))
        #expect(RGBA(hex: "#fff")?.hex == "#FFFFFF")
        #expect(RGBA(hex: "#00000080")?.alpha == 128.0 / 255)
        #expect(RGBA(hex: "1E2227") == nil)
        #expect(RGBA(hex: "#12345") == nil)
    }

    @Test func blendsTransparentColors() {
        let half = RGBA(hex: "#FFFFFF80")!.over(RGBA(hex: "#000000")!)
        #expect(half.hex == "#808080")
        #expect(RGBA(hex: "#000000")!.contrast(with: RGBA(hex: "#FFFFFF")!) > 20)
    }

    @Test func themeFilesRoundTrip() throws {
        let theme = ZestTheme.oneDarkProDarker
        let read = try ZestTheme(yaml: theme.yaml, id: theme.id)
        #expect(read == theme)
        #expect(throws: ThemeError.self) { try ZestTheme(yaml: "name: x\ncolors:\n  nope: \"#000000\"\n", id: "x") }
        #expect(throws: ThemeError.self) { try ZestTheme(yaml: "name: x\ncolors:\n  text: red\n", id: "x") }
    }

    @Test func missingColorsComeFromTheDefaults() throws {
        let theme = try ZestTheme(yaml: "name: Partial\nappearance: light\ncolors:\n  background: \"#FFFFFF\"\n", id: "p")
        #expect(theme[.background].hex == "#FFFFFF")
        #expect(theme[.text] == ZestTheme.defaultLight[.text])
    }

    @Test func slugs() {
        #expect(ZestTheme.slug("Tokyo Night Storm") == "tokyo-night-storm")
        #expect(ZestTheme.slug("Rosé Pine Dawn") == "rose-pine-dawn")
        #expect(ZestTheme.slug("SynthWave '84") == "synthwave-84")
    }

    @Test func convertsAVSCodeTheme() throws {
        let json = """
        {
          // VS Code allows comments
          "name": "Sample",
          "type": "dark",
          "colors": {
            "editor.background": "#101010",
            "editorSuggestWidget.background": "#202020",
            "editorSuggestWidget.foreground": "#DDDDDD",
            "editorSuggestWidget.selectedBackground": "#FFFFFF20",
            "editorSuggestWidget.highlightForeground": "#55AAFF",
            "terminal.ansiGreen": "#33CC33",
            "terminal.ansiBlue": "#3355FF",
            "terminal.ansiMagenta": "#202022", /* too dark on the background */
            "terminal.ansiBrightMagenta": "#EE77EE",
          },
        }
        """
        let theme = try VSCodeTheme.convert(json: json)
        #expect(theme.name == "Sample")
        #expect(theme.appearance == .dark)
        #expect(theme[.background].hex == "#202020")
        #expect(theme[.text].hex == "#DDDDDD")
        #expect(theme[.selection].hex == "#3C3C3C")      // 12.5% white over the background
        #expect(theme[.match].hex == "#55AAFF")
        #expect(theme[.command].hex == "#33CC33")
        #expect(theme[.subcommand].hex == "#EE77EE")     // the dim magenta falls back to bright
        #expect(theme[.argument].hex == "#E5E510")       // not set: VS Code's default yellow
        #expect(theme[.description].contrast(with: theme[.background]) >= 2.5)
    }

    @Test func followsIncludes() throws {
        let base = ##"{ "type": "light", "colors": { "editor.background": "#FAFAFA", "editor.foreground": "#222222" } }"##
        let child = ##"{ "name": "Child", "include": "./base.json", "colors": { "editor.foreground": "#111111" } }"##
        let theme = try VSCodeTheme.convert(json: child) { path in
            #expect(path == "./base.json")
            return base
        }
        #expect(theme.appearance == .light)
        #expect(theme[.background].hex == "#FAFAFA")
        #expect(theme[.text].hex == "#111111")
    }

    @Test func readsExtensionFolders() throws {
        let folder = TempFiles.folder([
            "package.json": ##"{ "contributes": { "themes": [ { "label": "%dark%", "uiTheme": "vs-dark", "path": "./themes/dark.json" }, { "label": "Paper", "uiTheme": "vs", "path": "./themes/light.json" } ] } }"##,
            "package.nls.json": ##"{ "dark": "Midnight" }"##,
            "themes/dark.json": ##"{ "colors": { "editor.background": "#000000" } }"##,
            "themes/light.json": ##"{ "colors": { "editor.background": "#FFFFFF" } }"##,
        ])
        let themes = VSCodeExtension.themes(in: folder)
        #expect(themes.map(\.label) == ["Midnight", "Paper"])
        let paper = try VSCodeExtension.convert(themes[1])
        #expect(paper.appearance == .light)
        #expect(paper.id == "paper")
    }

    @Test func yourThemesReplaceBuiltInOnes() throws {
        let builtIn = TempFiles.folder(["calm.yaml": "name: Calm\ncolors:\n  background: \"#111111\"\n"])
        let yours = TempFiles.folder(["calm.yaml": "name: My Calm\ncolors:\n  background: \"#222222\"\n"])
        let store = ThemeStore(directories: [yours, builtIn])
        #expect(store.theme(id: "calm")?.name == "My Calm")
        #expect(store.all().filter { $0.id == "calm" }.count == 1)
        #expect(store.theme(id: ZestTheme.oneDarkProDarker.id) != nil)  // always there
    }

    @Test func bundledThemesAreComplete() throws {
        let store = ThemeStore(directories: [TempFiles.bundledThemes])
        let themes = store.all()
        #expect(themes.count > 50)
        #expect(themes.contains { $0.appearance == .light })
        for theme in themes {
            for token in ZestTheme.Token.allCases {
                #expect(theme.colors[token] != nil, "\(theme.id) has no \(token.rawValue)")
            }
            #expect(theme[.text].contrast(with: theme[.background]) >= 3, "\(theme.id): text is hard to read")
            // A few themes (Solarized Dark, Monokai Dimmed) have low-contrast selections in VS Code
            // too; zest keeps their look.
            #expect(theme[.selectedText].contrast(with: theme[.selection]) >= 2.3, "\(theme.id): selected text is hard to read")
        }
    }
}
