# Changelog

## 0.1.7 — 2026-11-17

- The popup works with the mouse: scroll the list, and click a suggestion to insert it, as Tab
  does. The keyboard stays with the terminal.
- The row under the pointer is highlighted.

## 0.1.6 — 2026-11-17

- Themes: pick one of 74 VS Code themes in Settings → Appearance, with search and a live preview.
  One Dark Pro, Dracula, Catppuccin, Tokyo Night, GitHub, Nord, Gruvbox, Solarized, Rosé Pine,
  Ayu and more.
- In VS Code and Cursor the popup uses the editor's own theme. You can turn this off.
- A light and a dark theme can follow the macOS appearance.
- Choose the font: any installed monospaced font.
- Import any VS Code theme from Settings or with `zest theme import`; `zest theme list` shows
  them all. See docs/themes.md.
- The Settings preview changes as you change the theme, font, size, rows or descriptions.
- New shells start faster: zest reads the existing key bindings without starting a subshell per
  key. `scripts/bench.zsh` measures what zest costs, and the README has the numbers.

## 0.1.5 — 2026-11-16

- Ghostty is supported: the shell asks Ghostty where the cursor is, so the popup opens right under
  it.
- The popup follows its terminal window when you move or resize it.
- The popup closes when its terminal window closes or its shell exits.

## 0.1.4 — 2026-11-16

- iTerm2 is supported: the popup opens under the cursor and lines up with the word being completed.
- zest logs where it found the text cursor, which helps with bug reports about other terminals. To
  watch: `/usr/bin/log stream --level debug --predicate 'subsystem == "io.github.rostik32.zest"'`.
- Ghostty is not supported yet: it doesn't report where the text cursor is.

## 0.1.3 — 2026-11-16

- The update window shows a short summary of what's new; the full notes open with Release Notes.

## 0.1.2 — 2026-11-16

- New spec: `tofu` (OpenTofu), with workspace and resource address suggestions. Thanks to
  @chen-xiao-yuan for the first community contribution! (#4)
- The `composer`, `drush` and `magento` specs work on every supported macOS version (their
  generators use awk instead of sed to separate names and descriptions).

## 0.1.1 — 2026-11-15

- Specs that only load another spec now work (`speedtest` → `speedtest-cli`).
- Options without a dash are suggested (`dd bs=`, `dig +short`, `launchctl limit cpu`).
- Subcommands that start with a dash work (`dscacheutil -q`).
- `command`, `exec` and `builtin` use their own specs.
- Restored `rails` (with app commands), `kamal`, `task` and `z`; new specs for `composer`, `drush`,
  `magento`, `mask` and `php`. They were empty because Fig built them at runtime.
- Generators can return descriptions: `descriptionSeparator`.
- Non-ASCII history (e.g. Cyrillic) is decoded correctly; history entries whose command does not
  exist are skipped; a word typed in a Cyrillic keyboard layout suggests the command (`св` → `cd`).
- Commands you run often come first at the start of the line.
- `zest validate --deep` simulates typing for every spec; CI runs it on all 1,504 specs.

## 0.1.0 — 2026-11-15

First release.

- Autocomplete popup for zsh in Terminal.app, VS Code and Cursor, placed under the text cursor.
- 1,504 command specs imported from withfig/autocomplete, plus files, folders and history.
- Specs in YAML; `zest gen` drafts a spec from `--help`, `zest validate` checks specs.
- Fuzzy matching, ranking by how often you pick items, ghost text from history.
- One Dark Pro Darker colors, Material Icon Theme and Codicons icons.
- Menu bar app with settings, launch at login and automatic updates from GitHub Releases.
