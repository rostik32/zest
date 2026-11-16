# Changelog

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
