# gno-ibc Makefile.
#
# `make install-gno` clones the pinned gno fork into a per-user cache, builds
# the `gno` CLI, and installs it under $GOPATH/bin. The pinned commit lives in
# .gno-version. Bump it there to roll the toolchain.

include .gno-version

GNO_CACHE  := $(HOME)/.cache/gno-ibc/gno
GO_BIN_DIR := $(shell go env GOPATH)/bin
GNO_BIN    := $(GO_BIN_DIR)/gno
GNO_SHORT  := $(shell echo $(GNO_COMMIT) | cut -c1-7)

.PHONY: help install-gno verify-gno test test-smoke clean-gno-cache

help:
	@echo "Targets:"
	@echo "  install-gno       — clone+build+install the pinned gno binary"
	@echo "  verify-gno        — assert the gno on PATH matches the pin"
	@echo "  test              — verify-gno, then run all gno tests"
	@echo "  test-smoke        — run only the env-prep smoke tests"
	@echo "  clean-gno-cache   — remove the cloned gno fork (forces re-clone next install)"
	@echo
	@echo "Pinned: $(GNO_REPO)@$(GNO_SHORT)  (.gno-version)"

install-gno:
	@mkdir -p $(dir $(GNO_CACHE))
	@if [ ! -d "$(GNO_CACHE)/.git" ]; then \
		echo ">> cloning $(GNO_REPO) into $(GNO_CACHE)"; \
		git clone --quiet $(GNO_REPO) $(GNO_CACHE); \
	fi
	@cd $(GNO_CACHE) && git fetch --quiet origin
	@cd $(GNO_CACHE) && git checkout --quiet $(GNO_COMMIT)
	@echo ">> building gno from $(GNO_SHORT)"
	@# Delegate to upstream gnovm/Makefile's install target. It bakes in:
	@#  - version.Version  (so `gno version` contains the commit hash)
	@#  - gnoenv._GNOROOT  (so the binary finds its stdlibs at runtime)
	@$(MAKE) --no-print-directory -C $(GNO_CACHE)/gnovm install
	@$(MAKE) --no-print-directory verify-gno

verify-gno:
	@command -v gno >/dev/null 2>&1 || { \
		echo "ERROR: 'gno' not found on PATH. Make sure $(GO_BIN_DIR) is on PATH and run 'make install-gno'."; exit 1; }
	@gno version 2>&1 | grep -q $(GNO_SHORT) || { \
		gno version; \
		echo "ERROR: 'gno' on PATH does not match pinned commit $(GNO_SHORT)."; \
		echo "       Run 'make install-gno' to build the pinned toolchain."; \
		exit 1; }
	@echo "ok: gno binary matches pinned commit $(GNO_SHORT)"

test: verify-gno
	@gno test ./...

test-smoke: verify-gno
	@gno test ./gno.land/p/aib/_smoke/ -v

clean-gno-cache:
	@rm -rf $(GNO_CACHE)
	@echo "removed $(GNO_CACHE)"
