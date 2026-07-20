# gno-ibc Makefile.
#
# `make install-gno` clones the pinned gno toolchain into a per-user cache
# and installs `gno`, `gnoland`, `gnodev`, and `gnokey` from it. The IBC
# crypto stdlibs (bn254, cometbls, cometblszk, keccak256, merkle, modexp)
# ship in the upstream pin, so this repo no longer vendors them locally.
#
# Bump GNO_COMMIT in .gno-version to roll the upstream toolchain.

include .gno-version

# Use bash with pipefail so failures inside `cmd | tee` (e.g. test-cover)
# bubble out instead of being masked by tee's exit code.
SHELL       := /bin/bash
.SHELLFLAGS := -o pipefail -c

# Exported so `make install-gno GNO_COMMIT=...` overrides the pin from the
# command line without editing .gno-version.
export GNO_COMMIT GNO_REPO

GNO_CACHE  := $(HOME)/.cache/gno-ibc/gno
GO_BIN_DIR := $(shell go env GOPATH)/bin
GNO_BIN    := $(GO_BIN_DIR)/gno
GNO_SHORT  := $(shell echo $(GNO_COMMIT) | cut -c1-7)

ZKGM_FIXTURES_DIR     := tools/zkgm-fixtures
ZKGM_SCENARIOS        := gno.land/p/onbloc/ibc/zkgm/testdata/scenarios.json
ZKGM_SCENARIOS_GNO    := gno.land/p/onbloc/ibc/zkgm/scenarios_fixture_test.gno

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
	p/nt/markdown/sanitize/v0 \
	p/nt/mux/v0 \
	p/nt/seqid/v0 \
	p/nt/testutils/v0 \
	p/nt/uassert/v0 \
	p/nt/ufmt/v0 \
	r/demo/defi/grc20reg

VENDOR_GNOSWAP_REPO := third_party/gnoswap
VENDOR_GNOSWAP_SUB  := contract
VENDOR_GNOSWAP_RELS := \
	p/gnoswap/uint256 \
	p/gnoswap/int256

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

FLAGS_p_gnoswap_uint256 := $(STD_EXCLUDES)
FLAGS_p_onbloc_json     :=
FLAGS_p_nt_avl_v0       := $(STD_EXCLUDES) --exclude='filetests/' --exclude='list/' --exclude='pager/' --exclude='rolist/'
FLAGS_p_nt_bptree_v0    := --delete-excluded --exclude='list/' --exclude='pager/' --exclude='rolist/' --exclude='rotree/'
FLAGS_p_aib_ibc_lightclient            := $(STD_EXCLUDES) --exclude='testing/'
FLAGS_p_aib_ibc_lightclient_tendermint := $(STD_EXCLUDES) --exclude='testing/'
FLAGS_r_aib_ibc_core    := $(STD_EXCLUDES) --exclude='README.md' --exclude='recover-client.md'

vendor-flags = $(if $(filter undefined,$(origin FLAGS_$(subst /,_,$(1)))),$(STD_EXCLUDES),$(FLAGS_$(subst /,_,$(1))))

# rsync only auto-creates the leaf dest dir, so mkdir -p covers intermediates.
vendor-cmd = mkdir -p $(dir gno.land/$(2)) && rsync $(RSYNC_BASE) $(call vendor-flags,$(2)) $(1)/$(2)/ gno.land/$(2)/

.PHONY: help install-gno verify-gno vendor fmt test test-cover test-smoke test-gnokey-query-smoke test-gnokey-qeval-smoke test-zkgm-native-refund-smoke clean-gno-cache refresh-zkgm-scenarios derive-sender-salt-vectors generate generate-check

PROTOGEN_PKGS := gno.land/p/onbloc/ibc/union/lightclient/cometbls

COVERAGE_DIR := coverage

# First-party gno packages. Third-party mirrors under gno.land/p/{aib,gnoswap,nt,onbloc}
# and gno.land/r/aib are dependency inputs only, so local and CI tests skip them.
# Packages under any ignore/ directory are excluded too (scratch/scenario realms
# that are not part of the first-party test suite).
USER_GNO_PKGS := $(patsubst %/gnomod.toml,./%/,$(shell find gno.land/p/onbloc gno.land/r/onbloc -name gnomod.toml | grep -v '/ignore/' | sort))
TEST_GNO_PKGS := $(if $(PKG),$(addprefix ./,$(patsubst ./%,%,$(PKG))),$(USER_GNO_PKGS))
SCENARIO_GNO_PKGS := $(patsubst %/gnomod.toml,./%/,$(shell find gno.land/r/onbloc/ibc/scenario -name gnomod.toml | grep -v '/ignore/' | sort))
SCENARIO_TEST_GNO_PKGS := $(if $(PKG),$(addprefix ./,$(patsubst ./%,%,$(PKG))),$(SCENARIO_GNO_PKGS))
GNO_TEST_FLAGS := -v$(if $(RUN), -run "$(RUN)")

help:
	@echo "Targets:"
	@echo "  install-gno           — clone pinned gno and install gno + gnoland + gnodev + gnokey"
	@echo "  verify-gno            — assert the gno binary is on PATH"
	@echo "  vendor                — mirror sparse third_party package sub-paths into gno.land/"
	@echo "  fmt                   — gofumpt -w on uncommitted .go/.gno files (modified, staged, untracked)"
	@echo "  test                  — verify-gno + vendor, then run first-party gno tests"
	@echo "    PKG=<path>          — run only one or more packages/realms (for example, PKG=gno.land/r/onbloc/ibc/union/core)"
	@echo "    RUN=<name>          — pass a test-name regex to gno test -run"
	@echo "  test-cover            — same as test, plus -cover (needs gno PR #4241; override GNO_COMMIT)"
	@echo "  test-smoke            — run only the env-prep smoke tests"
	@echo "  test-gnokey-query-smoke — run the full gnokey smoke suite"
	@echo "  test-gnokey-qeval-smoke — run only the gnokey maketx/qeval core smoke suite"
	@echo "  test-zkgm-native-refund-smoke — run only the ZKGM native refund gnokey smoke suite"
	@echo "  clean-gno-cache       — remove the cloned gno repo (forces re-clone next install)"
	@echo "  refresh-zkgm-scenarios — regenerate handler/dispatch end-to-end ZKGM scenarios via the Rust harness"
	@echo "  derive-sender-salt-vectors — print DeriveSenderSalt bootstrap vectors via the Rust harness"
	@echo "  generate              — regenerate _pb_gen.gno codecs from //gno:protobuf-tagged structs"
	@echo "  generate-check        — assert generated _pb_gen.gno files are up to date (CI)"
	@echo
	@echo "Pinned: $(GNO_REPO)@$(GNO_SHORT)  (.gno-version)"

# Clean the cached checkout before switching pins because older setup flows
# left local stdlib symlink files under paths now tracked by upstream gno.
install-gno:
	@if [ ! -d $(GNO_CACHE)/.git ]; then \
		mkdir -p $(dir $(GNO_CACHE)); \
		echo ">> cloning $(GNO_REPO) into $(GNO_CACHE)"; \
		git clone --quiet --filter=blob:none $(GNO_REPO) $(GNO_CACHE); \
	fi
	@cd $(GNO_CACHE) && \
		git cat-file -e $(GNO_COMMIT)^{commit} 2>/dev/null || git fetch --quiet origin; \
		git reset --quiet --hard; \
		git clean --quiet -ffdx; \
		git checkout --quiet $(GNO_COMMIT)
	@echo ">> installing gno @ $(GNO_SHORT)"
	@$(MAKE) -C $(GNO_CACHE)/gnovm install
	@$(MAKE) -C $(GNO_CACHE)/gno.land install.gnoland install.gnokey
	@$(MAKE) -C $(GNO_CACHE) install.gnodev

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
		echo "       Run 'make install-gno' to rebuild against the current pin."; \
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
	@for pkg in $(TEST_GNO_PKGS); do \
		echo "==> gno test $(GNO_TEST_FLAGS) $$pkg"; \
		gno test $(GNO_TEST_FLAGS) "$$pkg" || exit $$?; \
	done

test-scenario: verify-gno vendor
	@for pkg in $(SCENARIO_TEST_GNO_PKGS); do \
		echo "==> gno test $(GNO_TEST_FLAGS) $$pkg"; \
		gno test $(GNO_TEST_FLAGS) "$$pkg" || exit $$?; \
	done

test-smoke: verify-gno
	@gno test ./gno.land/p/core/_smoke/ -v

test-gnokey-query-smoke: verify-gno vendor
	@./tools/gnokey-query-smoke.sh

test-gnokey-qeval-smoke: verify-gno vendor
	@./tools/gnokey-smoke/run-query-smoke.sh

test-zkgm-native-refund-smoke: verify-gno vendor
	@./tools/gnokey-smoke/run-zkgm-native-refund.sh

clean-gno-cache:
	@rm -rf $(GNO_CACHE)
	@echo "removed $(GNO_CACHE)"

# Regenerates handler/dispatch end-to-end ZKGM scenarios (full ZkgmPacket
# envelopes + matching Ack pairs) against Union's `sol!` macro definitions.
# Output lands next to the gno tests that consume it. CI re-runs this and
# asserts the committed bytes match.
refresh-zkgm-scenarios:
	@command -v cargo >/dev/null 2>&1 || { \
		echo "ERROR: 'cargo' not found on PATH. Install Rust toolchain (rustup) to refresh ZKGM scenarios."; exit 1; }
	@mkdir -p $(dir $(ZKGM_SCENARIOS))
	@echo ">> regenerating $(ZKGM_SCENARIOS)"
	@cargo run --release --quiet -p zkgm-fixtures > $(ZKGM_SCENARIOS)
	@python3 -c 'from pathlib import Path; src = Path("$(ZKGM_SCENARIOS)").read_text(); assert "\x60" not in src, "scenarios.json contains a backtick; cannot embed in Gno raw string"; Path("$(ZKGM_SCENARIOS_GNO)").write_text("package zkgm\n\nconst fixtureScenariosJSON = `" + src + "`\n")'
	@echo "ok: scenarios written to $(ZKGM_SCENARIOS) and $(ZKGM_SCENARIOS_GNO) ($$(grep -c '"name":' $(ZKGM_SCENARIOS)) scenarios)"

derive-sender-salt-vectors:
	@command -v cargo >/dev/null 2>&1 || { \
		echo "ERROR: 'cargo' not found on PATH. Install Rust toolchain (rustup) to derive sender salt vectors."; exit 1; }
	@cargo run --release --quiet -p zkgm-fixtures --bin derive_sender_salt

generate:
	@echo ">> regenerating _pb_gen.gno in $(PROTOGEN_PKGS)"
	@cd tools/protogen && go run . $(addprefix $(CURDIR)/,$(PROTOGEN_PKGS))
	@echo "ok: regenerated"

# `git diff` misses new files, so check untracked too (adding a new
# //gno:protobuf struct produces a new _pb_gen.gno).
generate-check: generate
	@modified=$$(git diff --name-only -- '*_pb_gen.gno'); \
	untracked=$$(git ls-files --others --exclude-standard -- '*_pb_gen.gno'); \
	if [ -n "$$modified$$untracked" ]; then \
		echo "ERROR: generated _pb_gen.gno files are out of date. Run 'make generate' and commit."; \
		[ -n "$$modified" ]  && { echo "modified:";  echo "$$modified";  }; \
		[ -n "$$untracked" ] && { echo "untracked:"; echo "$$untracked"; }; \
		git --no-pager diff -- '*_pb_gen.gno'; \
		exit 1; \
	fi
	@echo "ok: generated files up to date"
