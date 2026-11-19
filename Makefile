# Install copies this bundle to <share>/langs/awk, where `x -l` looks: a lang
# is installed when its files are there. No registry, no database.

X ?= x

# The version is derived from git describe, never committed: lang.xon declares
# what this lang requires; the installed artifact carries what it is.
LANG_VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
SHARE := $(if $(PREFIX),$(PREFIX)/share/x,$(shell $(X) --share-dir))
DEST  := $(SHARE)/langs/awk

# What a consumer needs to RUN the lang: the declaration, the entry, the
# modules.  Not the suite, not the tooling, not CI.
PAYLOAD := lang.xon run.x awk

.PHONY: install
install: ## Install into <share>/langs/awk
	@test -n "$(SHARE)" || { echo "x-awk: cannot find an x tree -- set PREFIX or X" >&2; exit 1; }
	@test -d "$(SHARE)" || { echo "x-awk: no x tree at $(SHARE)" >&2; exit 1; }
	rm -rf "$(DEST)"
	mkdir -p "$(DEST)"
	cp -R $(PAYLOAD) "$(DEST)/"
	printf '%s\n' '$(LANG_VERSION)' > "$(DEST)/version"
	@# THE BOOT, SAVED: the state image `x -l awk` loads instead of booting
	@# from source -- 0.5s against 6 (docs/state-images.md in x-lang).  The
	@# wrapper writes it here, once, into the installed bundle's .images/,
	@# because a bundle's image is its installer's to write; a platform
	@# whose wrapper predates --image, or has no writer, boots from source.
	"$(X)" --image -l awk || true
	@echo "x-awk: installed to $(DEST)"
	@echo "x-awk: try  x -l awk"

.PHONY: uninstall
uninstall: ## Remove it again
	rm -rf "$(DEST)"
	@echo "x-awk: removed $(DEST)"

.PHONY: test
test: ## Run the spec suite (every failure is loud)
	X="$(X)" sh tests/spec-runner.sh

.PHONY: check
check: ## Run the suite against tests/contract/known-failures.txt -- what CI gates on
	X="$(X)" sh tests/spec-gate.sh

# The rows run `x -l awk`, so x has to find THIS tree: X_LANG_DIR is the
# directory holding it.  An installed x is needed; a checkout's wrapper
# only runs from its own root.
.PHONY: card
card: ## Hold docs/card.md to the card format and run its rows
	X_LANG_DIR="$${X_LANG_DIR:-$(CURDIR)/..}" BUNDLE=. X="$(X)" \
		sh "$$("$(X)" --share-dir)/tools/lang-kit/card.sh"

.PHONY: help
help: ## Show targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[32m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
