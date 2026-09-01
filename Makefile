# x-awk -- the AWK lang for x-lang
#
# INSTALL PUTS THIS BUNDLE WHERE `-l` LOOKS: an installed x searches
# <share>/langs/*/lang.xon, so a lang is "installed" when its files are there.
#
#   make install                  into the x on PATH
#   PREFIX=$HOME/.local make install    into a particular prefix

X ?= x

# THE VERSION IS DERIVED, NEVER COMMITTED -- lang.xon declares what this lang
# REQUIRES, and the installed artifact carries what it IS (git describe).
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

.PHONY: bundle
bundle: ## Roll a release tarball and print its pin
	sh tools/bundle.sh

.PHONY: help
help: ## Show targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[32m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
