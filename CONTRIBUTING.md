# Contributing to zest

Thanks for helping! There are three common kinds of contribution:

| You want to… | Read |
| --- | --- |
| Add or fix suggestions for a command | [Adding a command](docs/adding-a-command.md): usually one YAML file, no Swift needed |
| Fix a bug or add a feature | This page and [Architecture](docs/architecture.md) |
| Report a problem or ask for a command | [Open an issue](https://github.com/rostik32/zest/issues/new/choose) |
| Add a theme | [Themes](docs/themes.md): add the VS Code extension to `scripts/update-themes.sh` |
| Ask a question or suggest an idea | [Discussions](https://github.com/rostik32/zest/discussions) |

New here? The [good first issues](https://github.com/rostik32/zest/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
are small, self-contained tasks, most of them a single spec file.

## Setup

You need macOS 14+ on Apple silicon and Xcode or the Command Line Tools
(`xcode-select --install`). Node.js is only needed for the Fig importer and the schema check.

```bash
git clone https://github.com/rostik32/zest.git
cd zest
make test         # unit tests
make check        # unit tests, spec checks and the zsh end-to-end test (what CI runs)
make app          # builds dist/Zest.app
make install      # builds and installs to /Applications, links the zest command
```

Run `make help` for all targets. VS Code and Cursor users: open the folder and install the
recommended extensions; YAML specs are then checked against the schema as you type.

## Project layout

```
Sources/ZestCore/   the engine: parsing, specs, matching, generators, protocol (no UI, fully tested)
Sources/ZestApp/    the menu bar app: popup, settings, socket server, updater
Sources/zest/       the `zest` command: complete, validate, gen, serve, …
shell/zest.zsh      the zsh integration
specs/              built-in specs (YAML)
schema/             JSON Schema for specs
Tests/              unit tests (Swift Testing) and the zsh end-to-end test
tools/import-fig/   converts Fig specs to YAML
scripts/            build, release, icons
docs/               documentation
```

## Working on the engine

Most logic lives in `ZestCore` and can be tried without the app:

```bash
swift run zest complete 'git checkout -'        # what the popup would show
swift run zest serve                            # run the server without UI and print the popup
ZEST_SOCKET=~/Library/Application\ Support/zest/zest.sock.debug zsh   # a shell that talks to it
```

Add a test next to the code you change. `Tests/ZestCoreTests/Fixtures/specs` holds small specs for
engine tests; prefer those over the big built-in specs, so tests don't break when specs change.

> With only the Command Line Tools, a test file must not `import Foundation` together with
> `import Testing` (the cross-import module ships with Xcode only). Put file helpers in
> `Tests/ZestCoreTests/Support.swift`.

## Working on the app

```bash
make install && open /Applications/Zest.app
```

macOS ties the Accessibility permission to the app's signature, and local builds are signed ad hoc,
so you will be asked to grant it again after each rebuild: remove the old zest entry in System
Settings → Privacy & Security → Accessibility and add the new one. Maintainers can avoid this with
`scripts/setup-local-signing.sh` (see [Releasing](docs/releasing.md)).

For changes to `shell/zest.zsh` or anything on the path of a key press, compare
`zsh scripts/bench.zsh` before and after: it measures shell startup, the cost of each key and the
wait for Tab, ↑ and ↓.

If the popup doesn't open in some terminal, watch the app's debug messages while you type there. They
say whether the terminal was in front and what it reported as the text cursor:

```bash
/usr/bin/log stream --level debug --predicate 'subsystem == "io.github.rostik32.zest"'
```

## The README demo

`docs/images/demo.gif` and `hero.png` are rendered by `make demo` (needs `ffmpeg`): it types a script
into the real engine in a throwaway project, runs the commands for their output and draws each step
with the app's popup view. Run it again when the popup's look changes.

## Pull requests

- Keep each pull request to one change, and describe what it fixes or adds and how you tested it.
- Run `make check` before pushing; CI runs the same checks. `make specs` simulates typing for
  every spec (`zest validate --deep`): it catches broken `loadSpec` references, JavaScript that does
  not load, subcommands that suggest nothing and slow specs, without running any scripts.
- Code style: follow the surrounding code. Comments explain *why*, not *what*.
- Spec changes: descriptions are short sentences without a final period, and generators must be
  fast and read-only.

By contributing you agree that your work is released under the [MIT license](LICENSE).
Please be kind and constructive; see the [Code of Conduct](CODE_OF_CONDUCT.md).
