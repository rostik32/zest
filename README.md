<p align="center">
  <img src="assets/icon.png" width="112" alt="zest icon">
</p>

<h1 align="center">zest</h1>

<p align="center">
  An autocomplete popup for zsh on macOS: subcommands, options, files and git branches,<br>
  with descriptions, right under your cursor in Terminal, iTerm2, Ghostty, VS Code and Cursor.<br>
  A free, open-source alternative to the Fig, Amazon Q and Kiro CLI autocomplete.
</p>

<p align="center">
  <a href="https://github.com/rostik32/zest/actions/workflows/ci.yml"><img src="https://github.com/rostik32/zest/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/rostik32/zest/releases/latest"><img src="https://img.shields.io/github/v/release/rostik32/zest" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B%20·%20Apple%20silicon-1e2227" alt="macOS 14+, Apple silicon">
  <img src="https://img.shields.io/badge/shell-zsh-8cc265" alt="zsh">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-4aa5f0" alt="MIT license"></a>
</p>

<p align="center">
  <img src="docs/images/demo.gif" width="760" alt="zest suggesting git branches, npm scripts, docker options and folders while typing">
</p>

## Why

zest does the one thing Fig, and later Amazon Q and Kiro CLI, did best: the completion popup. It is a
small native app instead of a web view with a terminal proxy in front of every shell:

- **Native and light.** Written in Swift. About 20–30 MB of memory, a ~3 MB app binary, no
  Electron and no web view. zsh talks to it over a local socket; nothing sits between your
  terminal and your shell.
- **1,500 commands out of the box.** git, docker, kubectl, npm, brew, aws, gcloud, … imported
  from the open-source [Fig spec collection](https://github.com/withfig/autocomplete), plus files,
  folders and command history.
- **Adding a command is one YAML file.** Run `zest gen mytool` to draft it from `--help`.
- **Looks like your editor.** One Dark Pro Darker colors, Material Icon Theme file icons and
  Codicons, as in VS Code and Cursor.
- **Private.** Everything runs on your Mac. zest makes no network requests except checking
  GitHub for updates, which you can turn off.

## Requirements

- macOS 14 Sonoma or later, on Apple silicon (M1 or newer)
- **zsh**, the default macOS shell. bash and fish are not supported.
- Terminal.app, iTerm2, Ghostty, VS Code or Cursor. Other terminals work if they report the text
  cursor through macOS Accessibility.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/rostik32/zest/main/install.sh | sh
```

The script downloads the latest release, checks its checksum, puts **Zest.app** in
`/Applications` and the `zest` command in `~/.local/bin`, then starts the app. On first launch zest
asks for three things:

1. **Accessibility access**, to find the text cursor so the popup opens right under it.
2. **Three lines in `~/.zshrc`**, so new shells connect to zest. A backup is saved as
   `~/.zshrc.zest-backup`.
3. Whether to **start at login**.

Then open a new terminal window and start typing.

<details>
<summary>Install with Homebrew</summary>

```bash
brew tap rostik32/tap
brew trust rostik32/tap      # recent Homebrew versions ask you to trust third-party taps
brew install --cask zest
```

Then open zest from Applications. The cask always installs the latest release; zest updates itself.
</details>

<details>
<summary>Install by hand, or build from source</summary>

Download `Zest.zip` from the [latest release](https://github.com/rostik32/zest/releases/latest),
unzip it and move `Zest.app` to `/Applications`. zest is free and not signed by Apple, so the first
time macOS may say it cannot check the app: open **System Settings → Privacy & Security** and
click **Open Anyway**. The install script avoids this step.

To build it yourself you need the Xcode Command Line Tools (`xcode-select --install`):

```bash
git clone https://github.com/rostik32/zest.git
cd zest
make install    # builds dist/Zest.app, copies it to /Applications, links the zest command
```
</details>

<details>
<summary>Uninstall</summary>

```bash
curl -fsSL https://raw.githubusercontent.com/rostik32/zest/main/install.sh | sh -s -- --uninstall
```

This removes the app, the lines in `~/.zshrc` and zest's data. Your own specs in
`~/.config/zest` stay.
</details>

## Use it

Type a command. The popup appears while you type and disappears when there is nothing to suggest.

| Key | What it does |
| --- | --- |
| <kbd>Tab</kbd> | Insert the selected suggestion |
| <kbd>↑</kbd> <kbd>↓</kbd> | Choose a suggestion |
| <kbd>Enter</kbd> | Insert while you are typing a word; after a space it runs the command. You can change this in Settings. |
| <kbd>Esc</kbd> | Close the popup for this line |
| <kbd>→</kbd> | Accept the grey ghost text from your history |

When the popup is closed, every key does exactly what it did before, including your own key
bindings and zsh's own completion.

The menu bar icon lets you turn suggestions on and off (<kbd>⌘P</kbd>), open **Settings**, check for
updates, reload specs or quit. In Settings you can change the Enter key behavior, fuzzy matching,
history suggestions, font size, popup width and the number of visible rows.

<p align="center">
  <img src="docs/images/hero.png" width="720" alt="zest listing git branches for git checkout">
</p>

## Add a command

zest looks for specs in `~/.config/zest/specs` first, then in the ones that ship with it. A spec is
a YAML file named after the command:

```yaml
# ~/.config/zest/specs/deploy.yaml
name: deploy
description: Deploy the app
subcommands:
  - name: staging
    description: Deploy to staging
  - name: production
    description: Deploy to production
    options:
      - name: [-f, --force]
        description: Skip the confirmation
options:
  - name: --branch
    description: Branch to deploy
    args:
      name: branch
      generators:
        script: git branch --format='%(refname:short)'
```

Changes are picked up right away. You can also start from the command's help text:

```bash
zest gen deploy        # writes ~/.config/zest/specs/deploy.yaml from `deploy --help`
zest validate          # checks your specs for mistakes
zest complete 'deploy production -'   # shows what the popup would suggest
```

To share a spec with everyone, add it to [`specs/`](specs) and open a pull request.
[Adding a command](docs/adding-a-command.md) walks through it, and the
[spec format reference](docs/spec-format.md) lists every field.

## How it works

```
 Terminal / iTerm2 / Ghostty / VS Code / Cursor
 └─ zsh ── shell/zest.zsh ──── Unix socket ────► Zest.app (menu bar)
            sends the line on every key           ├─ parses the line, loads the spec
            asks what Tab, ↑, ↓, Enter, Esc do     ├─ fuzzy-ranks suggestions
            while the popup is open               ├─ runs generators (git branches…)
                                                  └─ draws the popup under the cursor
                                                     (found with the Accessibility API)
```

See [architecture](docs/architecture.md) for the details and the socket protocol.

## FAQ

### Can zest replace Fig, Amazon Q or Kiro CLI?

For the autocomplete popup, yes. zest uses the same open-source command specs Fig used, so the
suggestions will look familiar. It does only completion: there is no AI chat, no account and no
cloud service, and it does not wrap your terminal in a proxy.

### Which terminals does it work in?

Terminal.app, iTerm2, Ghostty, VS Code and Cursor are tested. Other terminals work if they report
the position of the text cursor through macOS Accessibility. For one that doesn't, add
`export ZEST_ASK_POSITION=1` before the zest lines in `~/.zshrc`: the shell then asks the terminal
where the cursor is, as it does in Ghostty.
Reports for other terminals are welcome in [issues](https://github.com/rostik32/zest/issues).

### Does it support bash or fish, or Intel Macs?

Not yet. zest needs zsh (the default shell on macOS), macOS 14 or later and an Apple silicon Mac.

### How is it different from zsh-autocomplete or zsh-autosuggestions?

Those are zsh plugins that draw inside the terminal: zsh-autosuggestions shows grey text from your
history, zsh-autocomplete lists zsh's own completions under the prompt. zest is a separate app that
shows a floating popup with a description and an icon for every suggestion, from specs for
1,500 commands, and it also has its own grey history suggestion.

### Does zest send my commands anywhere?

No. Everything runs on your Mac. The only network request is the update check on GitHub, which you
can turn off in Settings.

### Is it free?

Yes, under the MIT license. Because it is free, it is not notarized by Apple; the install script and
the Homebrew cask take care of the warning macOS shows for such apps.

## Roadmap

Ideas, not promises. Help is welcome with any of them; for something big, say hi in
[Discussions](https://github.com/rostik32/zest/discussions/categories/ideas) first.

- **More commands.** Popular tools that still have no spec are listed as
  [good first issues](https://github.com/rostik32/zest/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22).
- **More terminals.** WezTerm, kitty, Alacritty and others haven't been tried yet
  ([#18](https://github.com/rostik32/zest/issues/18)).
- **bash and fish.** The app doesn't depend on zsh: each shell needs its own small script like
  [`shell/zest.zsh`](shell/zest.zsh) that sends the command line and asks about keys.

## Contributing

Specs, bug fixes and ideas are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) explains how to set up the
project, run the tests and send a pull request. Most contributions are a single YAML file; the
[good first issues](https://github.com/rostik32/zest/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
are a good place to start. Questions go to [Discussions](https://github.com/rostik32/zest/discussions).

## Credits

- Command specs: [withfig/autocomplete](https://github.com/withfig/autocomplete), MIT license.
- File and folder icons: [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme), MIT license.
- Symbol icons: [Codicons](https://github.com/microsoft/vscode-codicons), CC BY 4.0.
- Colors: [One Dark Pro](https://github.com/Binaryify/OneDark-Pro), MIT license.
- [Yams](https://github.com/jpsim/Yams) and [Swift Argument Parser](https://github.com/apple/swift-argument-parser).

zest is not affiliated with Fig, Amazon or Kiro.

## License

[MIT](LICENSE)
