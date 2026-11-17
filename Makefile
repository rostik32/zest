# Common tasks. Run `make help` to list them.
SHELL := /bin/bash

# With only the Command Line Tools installed (no Xcode), Swift Testing lives in a
# folder the compiler does not search by default.
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
CLT_LIBS := /Library/Developer/CommandLineTools/Library/Developer/usr/lib
ifeq ($(shell xcode-select -p),/Library/Developer/CommandLineTools)
TEST_FLAGS := -Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) -Xlinker -F -Xlinker $(CLT_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS) -Xlinker -rpath -Xlinker $(CLT_LIBS)
endif

BIN_DIR ?= $(HOME)/.local/bin

.PHONY: help build test specs zsh-test check app install icons themes demo
help: ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-10s %s\n", $$1, $$2}'

build: ## Build everything (debug)
	swift build

test: ## Run the unit tests
	swift test $(TEST_FLAGS)

specs: ## Check every spec, including simulated typing (no scripts are run)
	swift build -c release --product zest
	.build/release/zest validate --quiet --deep specs

zsh-test: ## Run the zsh end-to-end test
	scripts/test-zsh.sh

check: test specs zsh-test ## Everything CI checks, except the schema check (needs Node)

app: ## Build dist/Zest.app and dist/Zest.zip
	scripts/build-app.sh

install: app ## Build, install to /Applications and link the zest command
	-osascript -e 'tell application id "io.github.rostik32.zest" to quit' 2>/dev/null; sleep 1
	ditto dist/Zest.app /Applications/Zest.app
	mkdir -p $(BIN_DIR)
	ln -sf /Applications/Zest.app/Contents/Helpers/zest $(BIN_DIR)/zest
	open /Applications/Zest.app

icons: ## Download the icon sets again (Material Icon Theme, Codicons)
	scripts/update-icons.sh

themes: ## Download the bundled VS Code themes again and convert them (themes/)
	scripts/update-themes.sh

demo: app ## Render docs/images/demo.gif, hero.png and appearance.gif (needs ffmpeg)
	swift run -c release ZestDemo
	swift run -c release ZestDemo appearance
