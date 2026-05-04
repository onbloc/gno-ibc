# gno-ibc Makefile.
#
# `make install-gno` runs tools/setup-stdlibs.py, which clones the pinned gno
# repo into a per-user cache, symlinks every package under stdlibs/ into
# <cache>/gnovm/stdlibs/<module>/, regenerates the native-binding dispatch
# table (`go generate`), and installs the resulting `gno` binary.
#
# Bump GNO_COMMIT in .gno-version to roll the upstream toolchain.

include .gno-version

GNO_CACHE  := $(HOME)/.cache/gno-ibc/gno
GO_BIN_DIR := $(shell go env GOPATH)/bin
GNO_BIN    := $(GO_BIN_DIR)/gno
GNO_SHORT  := $(shell echo $(GNO_COMMIT) | cut -c1-7)

ABI_FIXTURES_DIR := tools/abi-fixtures
ABI_VECTORS      := gno.land/p/aib/encoding/abi/testdata/vectors.json

.PHONY: help install-gno verify-gno test test-stdlibs test-smoke clean-gno-cache refresh-abi-vectors

# Vendored stdlib import paths, derived from stdlibs/<path>/gnomod.toml presence.
STDLIB_PKGS   := $(patsubst stdlibs/%/gnomod.toml,%,$(wildcard stdlibs/*/*/gnomod.toml))
# Subset that ships a Go-side native binding (vs pure-gno). Detected via .go presence.
STDLIB_NATIVE := $(foreach p,$(STDLIB_PKGS),$(if $(wildcard stdlibs/$(p)/*.go),$(p)))

help:
	@echo "Targets:"
	@echo "  install-gno           — vendor stdlibs/, regenerate, build+install gno"
	@echo "  verify-gno            — assert the gno binary is on PATH"
	@echo "  test                  — verify-gno, then run user-package gno tests"
	@echo "  test-stdlibs          — run the vendored stdlib's own .gno and .go tests"
	@echo "  test-smoke            — run only the env-prep smoke tests"
	@echo "  clean-gno-cache       — remove the cloned gno repo (forces re-clone next install)"
	@echo "  refresh-abi-vectors   — regenerate ABI ground-truth vectors via the Rust harness"
	@echo
	@echo "Pinned: $(GNO_REPO)@$(GNO_SHORT)  (.gno-version)"

install-gno:
	@python3 tools/setup-stdlibs.py

verify-gno:
	@command -v gno >/dev/null 2>&1 || { \
		echo "ERROR: 'gno' not found on PATH. Make sure $(GO_BIN_DIR) is on PATH and run 'make install-gno'."; exit 1; }
	@gno version 2>&1 | grep -q $(GNO_SHORT) || { \
		gno version; \
		echo "ERROR: 'gno' on PATH does not match pinned commit $(GNO_SHORT)."; \
		echo "       Run 'make install-gno' to rebuild against the current pin + stdlibs/."; \
		exit 1; }
	@echo "ok: gno binary matches pinned commit $(GNO_SHORT)"

test: verify-gno
	@gno test -v ./gno.land/...

# Stdlib sources live under stdlibs/ but their gnomod.toml declares stdlib
# paths, so `gno test ./stdlibs/...` would reject them as user mempackages.
# Test them by import path (gno) and via the cache (go).
test-stdlibs: verify-gno
	@for pkg in $(STDLIB_PKGS); do \
		echo ">> gno test $$pkg"; \
		gno test -v $$pkg || exit 1; \
	done
	@echo ">> go test (native bindings)"
	@cd $(GNO_CACHE)/gnovm && go test $(addprefix ./stdlibs/,$(STDLIB_NATIVE))

test-smoke: verify-gno
	@gno test ./gno.land/p/aib/_smoke/ -v

clean-gno-cache:
	@rm -rf $(GNO_CACHE)
	@echo "removed $(GNO_CACHE)"

# Regenerates ABI test vectors against Union's `sol!` macro definitions.
# Single canonical fixture lives next to the gno tests that consume it.
# CI re-runs this and asserts the committed bytes match.
refresh-abi-vectors:
	@command -v cargo >/dev/null 2>&1 || { \
		echo "ERROR: 'cargo' not found on PATH. Install Rust toolchain (rustup) to refresh ABI vectors."; exit 1; }
	@echo ">> regenerating $(ABI_VECTORS)"
	@cargo run --release --quiet -p abi-fixtures > $(ABI_VECTORS)
	@echo "ok: vectors written to $(ABI_VECTORS) ($$(grep -c '"name":' $(ABI_VECTORS)) scenarios)"
