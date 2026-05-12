# gno-ibc Makefile.
#
# `make install-gno` runs tools/setup-stdlibs.py, which clones the pinned gno
# repo into a per-user cache, symlinks every package under stdlibs/ into
# <cache>/gnovm/stdlibs/<module>/, regenerates the native-binding dispatch
# table (`go generate`), and installs the resulting `gno` and `gnodev` binaries.
#
# Bump GNO_COMMIT in .gno-version to roll the upstream toolchain.

include .gno-version

# Use bash with pipefail so failures inside `cmd | tee` (e.g. test-cover)
# bubble out instead of being masked by tee's exit code.
SHELL       := /bin/bash
.SHELLFLAGS := -o pipefail -c

# Exported so `make install-gno GNO_COMMIT=...` propagates the override into
# tools/setup-stdlibs.py, which otherwise reads .gno-version directly.
export GNO_COMMIT GNO_REPO

GNO_CACHE  := $(HOME)/.cache/gno-ibc/gno
GO_BIN_DIR := $(shell go env GOPATH)/bin
GNO_BIN    := $(GO_BIN_DIR)/gno
GNO_SHORT  := $(shell echo $(GNO_COMMIT) | cut -c1-7)

ABI_FIXTURES_DIR := tools/abi-fixtures
ABI_VECTORS      := gno.land/p/core/encoding/abi/testdata/vectors.json
ABI_VECTORS_GNO  := gno.land/p/core/ibc/zkgm/vectors_fixture_test.gno

# Submodule pins (.gitmodules + tree gitlinks) are the source of truth; the
# gno.land/<rel>/ mirrors built by `make vendor` are .gitignored.

VENDOR_GNOLANG_REPO := third_party/gnolang-gno
VENDOR_GNOLANG_SUB  := examples/gno.land
VENDOR_GNOLANG_RELS := \
	p/demo/tokens/grc20 \
	p/moul/md \
	p/onbloc/diff \
	p/onbloc/json \
	p/nt/avl/v0 \
	p/nt/bptree/v0 \
	p/nt/cford32/v0 \
	p/nt/fqname/v0 \
	p/nt/mux/v0 \
	p/nt/seqid/v0 \
	p/nt/testutils/v0 \
	p/nt/uassert/v0 \
	p/nt/ufmt/v0 \
	r/demo/defi/grc20reg

VENDOR_GNOSWAP_REPO := third_party/gnoswap
VENDOR_GNOSWAP_SUB  := contract
VENDOR_GNOSWAP_RELS := p/gnoswap/uint256

VENDOR_GNOREALMS_REPO := third_party/gno-realms
VENDOR_GNOREALMS_SUB  := gno.land
VENDOR_GNOREALMS_RELS := \
	p/aib/encoding \
	p/aib/ics23 \
	p/aib/jsonpage \
	p/aib/merkle \
	p/aib/ibc/app \
	p/aib/ibc/host \
	p/aib/ibc/lightclient \
	p/aib/ibc/lightclient/tendermint \
	p/aib/ibc/lightclient/tendermint/testing \
	p/aib/ibc/types \
	r/aib/ibc/core

RSYNC_BASE   := -a --delete
STD_EXCLUDES := --delete-excluded --exclude='*_test.gno' --exclude='*_filetest.gno'

FLAGS_p_gnoswap_uint256 :=
FLAGS_p_onbloc_json     :=
FLAGS_p_nt_avl_v0       := $(STD_EXCLUDES) --exclude='filetests/' --exclude='list/' --exclude='pager/' --exclude='rolist/'
FLAGS_p_nt_bptree_v0    := --delete-excluded --exclude='list/' --exclude='pager/' --exclude='rolist/' --exclude='rotree/'
FLAGS_p_aib_ibc_lightclient            := $(STD_EXCLUDES) --exclude='testing/'
FLAGS_p_aib_ibc_lightclient_tendermint := $(STD_EXCLUDES) --exclude='testing/'
FLAGS_r_aib_ibc_core    := $(STD_EXCLUDES) --exclude='README.md' --exclude='recover-client.md'

vendor-flags = $(if $(filter undefined,$(origin FLAGS_$(subst /,_,$(1)))),$(STD_EXCLUDES),$(FLAGS_$(subst /,_,$(1))))

# rsync only auto-creates the leaf dest dir, so mkdir -p covers intermediates.
vendor-cmd = mkdir -p $(dir gno.land/$(2)) && rsync $(RSYNC_BASE) $(call vendor-flags,$(2)) $(1)/$(2)/ gno.land/$(2)/

.PHONY: help install-gno link-stdlibs verify-gno vendor fmt test test-cover test-stdlibs test-smoke clean-gno-cache refresh-abi-vectors

COVERAGE_DIR := coverage

# Vendored stdlib import paths, derived from stdlibs/<path>/gnomod.toml presence.
STDLIB_PKGS   := $(patsubst stdlibs/%/gnomod.toml,%,$(wildcard stdlibs/*/*/gnomod.toml))
# Subset that ships a Go-side native binding (vs pure-gno). Detected via .go presence.
STDLIB_NATIVE := $(foreach p,$(STDLIB_PKGS),$(if $(wildcard stdlibs/$(p)/*.go),$(p)))
# First-party gno packages. Third-party mirrors under gno.land/p/{aib,gnoswap,nt,onbloc}
# and gno.land/r/aib are dependency inputs only, so local and CI tests skip them.
USER_GNO_PKGS := $(patsubst %/gnomod.toml,./%/,$(shell find gno.land/p/core gno.land/r/core -name gnomod.toml | sort))

help:
	@echo "Targets:"
	@echo "  install-gno           — vendor stdlibs/, regenerate, build+install gno + gnodev"
	@echo "  link-stdlibs          — refresh stdlib symlinks only (no rebuild)"
	@echo "  verify-gno            — assert the gno binary is on PATH"
	@echo "  vendor                — mirror sparse third_party package sub-paths into gno.land/"
	@echo "  fmt                   — gofumpt -w on uncommitted .go/.gno files (modified, staged, untracked)"
	@echo "  test                  — verify-gno + vendor, then run first-party gno tests"
	@echo "  test-cover            — same as test, plus -cover (needs gno PR #4241; override GNO_COMMIT)"
	@echo "  test-stdlibs          — run the vendored stdlib's own .gno and .go tests"
	@echo "  test-smoke            — run only the env-prep smoke tests"
	@echo "  clean-gno-cache       — remove the cloned gno repo (forces re-clone next install)"
	@echo "  refresh-abi-vectors   — regenerate ABI ground-truth vectors via the Rust harness"
	@echo
	@echo "Pinned: $(GNO_REPO)@$(GNO_SHORT)  (.gno-version)"

install-gno:
	@python3 tools/setup-stdlibs.py

# Refresh stdlib symlinks under the cached gno checkout without rebuilding
# the binary. Used in CI when the binary cache hits but .gno files in
# stdlibs/ may have been added/removed (edits to existing files are picked
# up automatically since symlinks resolve to the working-tree path).
link-stdlibs:
	@python3 tools/setup-stdlibs.py --link-only

# Initialise/update the third_party submodules, ensure sparse-checkout is set,
# and rsync the relevant subdirectories into the gno.land workspace paths.
# Idempotent — safe to run on every test invocation.
vendor:
	@git submodule update --init --recursive --quiet
	@git -C $(VENDOR_GNOLANG_REPO) sparse-checkout init --cone >/dev/null
	@git -C $(VENDOR_GNOLANG_REPO) sparse-checkout set $(addprefix $(VENDOR_GNOLANG_SUB)/,$(VENDOR_GNOLANG_RELS)) >/dev/null
	@git -C $(VENDOR_GNOSWAP_REPO) sparse-checkout init --cone >/dev/null
	@git -C $(VENDOR_GNOSWAP_REPO) sparse-checkout set $(addprefix $(VENDOR_GNOSWAP_SUB)/,$(VENDOR_GNOSWAP_RELS)) >/dev/null
	@git -C $(VENDOR_GNOREALMS_REPO) sparse-checkout init --cone >/dev/null
	@git -C $(VENDOR_GNOREALMS_REPO) sparse-checkout set $(addprefix $(VENDOR_GNOREALMS_SUB)/,$(VENDOR_GNOREALMS_RELS)) >/dev/null
	@$(foreach r,$(VENDOR_GNOLANG_RELS),$(call vendor-cmd,$(VENDOR_GNOLANG_REPO)/$(VENDOR_GNOLANG_SUB),$(r)) && )true
	@$(foreach r,$(VENDOR_GNOSWAP_RELS),$(call vendor-cmd,$(VENDOR_GNOSWAP_REPO)/$(VENDOR_GNOSWAP_SUB),$(r)) && )true
	@$(foreach r,$(VENDOR_GNOREALMS_RELS),$(call vendor-cmd,$(VENDOR_GNOREALMS_REPO)/$(VENDOR_GNOREALMS_SUB),$(r)) && )true
	@echo "ok: vendored third_party package mirrors into gno.land/"

verify-gno:
	@command -v gno >/dev/null 2>&1 || { \
		echo "ERROR: 'gno' not found on PATH. Make sure $(GO_BIN_DIR) is on PATH and run 'make install-gno'."; exit 1; }
	@gno version 2>&1 | grep -q $(GNO_SHORT) || { \
		gno version; \
		echo "ERROR: 'gno' on PATH does not match pinned commit $(GNO_SHORT)."; \
		echo "       Run 'make install-gno' to rebuild against the current pin + stdlibs/."; \
		exit 1; }
	@echo "ok: gno binary matches pinned commit $(GNO_SHORT)"

fmt:
	@command -v gofumpt >/dev/null 2>&1 || { \
		echo "ERROR: 'gofumpt' not found on PATH. Install with: go install mvdan.cc/gofumpt@latest"; exit 1; }
	@files=$$( { \
		git diff --name-only --diff-filter=ACMR; \
		git diff --cached --name-only --diff-filter=ACMR; \
		git ls-files --others --exclude-standard; \
	} | sort -u | grep -E '\.(go|gno)$$' || true); \
	if [ -z "$$files" ]; then \
		echo "fmt: no uncommitted .go/.gno files"; \
		exit 0; \
	fi; \
	echo "$$files" | xargs gofumpt -w; \
	echo "ok: formatted $$(echo "$$files" | wc -l | tr -d ' ') file(s)"

test: verify-gno vendor
	@gno test -v $(USER_GNO_PKGS)

# Coverage requires a gno toolchain that includes gnolang/gno#4241
# (`-cover` / `-coverprofile`). Override GNO_COMMIT on the make command line
# to point at a build that has those flags, e.g.
#   make test-cover GNO_COMMIT=57ad9a4a35daf50bdca5617fc89725a666a9c94b
# The .github/workflows/gno-coverage.yml workflow does this automatically.
test-cover: verify-gno vendor
	@mkdir -p $(COVERAGE_DIR)
	@gno test -cover -coverprofile=$(COVERAGE_DIR)/profile.txt -v $(USER_GNO_PKGS) 2>&1 \
		| tee $(COVERAGE_DIR)/output.log

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
	@gno test ./gno.land/p/core/_smoke/ -v

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
	@python3 -c 'from pathlib import Path; src = Path("$(ABI_VECTORS)").read_text(); assert "\x60" not in src, "vectors.json contains a backtick; cannot embed in Gno raw string"; Path("$(ABI_VECTORS_GNO)").write_text("package zkgm\n\nconst fixtureVectorsJSON = `" + src + "`\n")'
	@echo "ok: vectors written to $(ABI_VECTORS) and $(ABI_VECTORS_GNO) ($$(grep -c '"name":' $(ABI_VECTORS)) scenarios)"
