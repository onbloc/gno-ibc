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
ABI_VECTORS      := gno.land/p/core/encoding/abi/testdata/vectors.json
ABI_VECTORS_GNO  := gno.land/p/core/ibc/zkgm/vectors_fixture_test.gno

# Third-party packages mirrored from sparse-checkout submodules into their
# gno.land/p/<org>/<pkg>/ workspace paths. The submodule pin is the source of
# truth; the mirrors are .gitignored and rebuilt by `make vendor`.
VENDOR_GNOSWAP_SRC := third_party/gnoswap/contract/p/gnoswap/uint256
VENDOR_GNOSWAP_DST := gno.land/p/gnoswap/uint256
VENDOR_ONBLOC_SRC  := third_party/gnolang-gno/examples/gno.land/p/onbloc/json
VENDOR_ONBLOC_DST  := gno.land/p/onbloc/json
VENDOR_NT_AVL_SRC  := third_party/gnolang-gno/examples/gno.land/p/nt/avl/v0
VENDOR_NT_AVL_DST  := gno.land/p/nt/avl/v0
VENDOR_BPTREE_SRC  := third_party/gnolang-gno/examples/gno.land/p/nt/bptree/v0
VENDOR_BPTREE_DST  := gno.land/p/nt/bptree/v0
VENDOR_NT_CFORD32_SRC := third_party/gnolang-gno/examples/gno.land/p/nt/cford32/v0
VENDOR_NT_CFORD32_DST := gno.land/p/nt/cford32/v0
VENDOR_NT_MUX_SRC  := third_party/gnolang-gno/examples/gno.land/p/nt/mux/v0
VENDOR_NT_MUX_DST  := gno.land/p/nt/mux/v0
VENDOR_NT_SEQID_SRC := third_party/gnolang-gno/examples/gno.land/p/nt/seqid/v0
VENDOR_NT_SEQID_DST := gno.land/p/nt/seqid/v0
VENDOR_NT_UASSERT_SRC := third_party/gnolang-gno/examples/gno.land/p/nt/uassert/v0
VENDOR_NT_UASSERT_DST := gno.land/p/nt/uassert/v0
VENDOR_NT_UFMT_SRC := third_party/gnolang-gno/examples/gno.land/p/nt/ufmt/v0
VENDOR_NT_UFMT_DST := gno.land/p/nt/ufmt/v0
VENDOR_AIB_ENCODING_SRC := third_party/gno-realms/gno.land/p/aib/encoding
VENDOR_AIB_ENCODING_DST := gno.land/p/aib/encoding
VENDOR_AIB_PROTO_SRC    := third_party/gno-realms/gno.land/p/aib/encoding/proto
VENDOR_AIB_PROTO_DST    := gno.land/p/aib/encoding/proto
VENDOR_AIB_ICS23_SRC    := third_party/gno-realms/gno.land/p/aib/ics23
VENDOR_AIB_ICS23_DST    := gno.land/p/aib/ics23
VENDOR_AIB_JSONPAGE_SRC := third_party/gno-realms/gno.land/p/aib/jsonpage
VENDOR_AIB_JSONPAGE_DST := gno.land/p/aib/jsonpage
VENDOR_AIB_MERKLE_SRC   := third_party/gno-realms/gno.land/p/aib/merkle
VENDOR_AIB_MERKLE_DST   := gno.land/p/aib/merkle
VENDOR_AIB_APP_SRC      := third_party/gno-realms/gno.land/p/aib/ibc/app
VENDOR_AIB_APP_DST      := gno.land/p/aib/ibc/app
VENDOR_AIB_HOST_SRC     := third_party/gno-realms/gno.land/p/aib/ibc/host
VENDOR_AIB_HOST_DST     := gno.land/p/aib/ibc/host
VENDOR_AIB_LIGHTCLIENT_SRC := third_party/gno-realms/gno.land/p/aib/ibc/lightclient
VENDOR_AIB_LIGHTCLIENT_DST := gno.land/p/aib/ibc/lightclient
VENDOR_AIB_TM_SRC       := third_party/gno-realms/gno.land/p/aib/ibc/lightclient/tendermint
VENDOR_AIB_TM_DST       := gno.land/p/aib/ibc/lightclient/tendermint
VENDOR_AIB_TYPES_SRC    := third_party/gno-realms/gno.land/p/aib/ibc/types
VENDOR_AIB_TYPES_DST    := gno.land/p/aib/ibc/types
VENDOR_AIB_CORE_SRC     := third_party/gno-realms/gno.land/r/aib/ibc/core
VENDOR_AIB_CORE_DST     := gno.land/r/aib/ibc/core

.PHONY: help install-gno verify-gno vendor test test-stdlibs test-smoke clean-gno-cache refresh-abi-vectors

# Vendored stdlib import paths, derived from stdlibs/<path>/gnomod.toml presence.
STDLIB_PKGS   := $(patsubst stdlibs/%/gnomod.toml,%,$(wildcard stdlibs/*/*/gnomod.toml))
# Subset that ships a Go-side native binding (vs pure-gno). Detected via .go presence.
STDLIB_NATIVE := $(foreach p,$(STDLIB_PKGS),$(if $(wildcard stdlibs/$(p)/*.go),$(p)))
# First-party gno packages. Third-party mirrors under gno.land/p/{aib,gnoswap,nt,onbloc}
# and gno.land/r/aib are dependency inputs only, so local and CI tests skip them.
USER_GNO_PKGS := $(patsubst %/gnomod.toml,./%/,$(shell find gno.land/p/core gno.land/r/core -name gnomod.toml 2>/dev/null | sort))

help:
	@echo "Targets:"
	@echo "  install-gno           — vendor stdlibs/, regenerate, build+install gno"
	@echo "  verify-gno            — assert the gno binary is on PATH"
	@echo "  vendor                — mirror sparse third_party package sub-paths into gno.land/"
	@echo "  test                  — verify-gno + vendor, then run first-party gno tests"
	@echo "  test-stdlibs          — run the vendored stdlib's own .gno and .go tests"
	@echo "  test-smoke            — run only the env-prep smoke tests"
	@echo "  clean-gno-cache       — remove the cloned gno repo (forces re-clone next install)"
	@echo "  refresh-abi-vectors   — regenerate ABI ground-truth vectors via the Rust harness"
	@echo
	@echo "Pinned: $(GNO_REPO)@$(GNO_SHORT)  (.gno-version)"

install-gno:
	@python3 tools/setup-stdlibs.py

# Initialise/update the third_party submodules, ensure sparse-checkout is set,
# and rsync the relevant subdirectories into the gno.land workspace paths.
# Idempotent — safe to run on every test invocation.
vendor:
	@git submodule update --init --recursive --quiet
	@git -C third_party/gnolang-gno sparse-checkout init --cone >/dev/null
	@git -C third_party/gnolang-gno sparse-checkout set examples/gno.land/p/onbloc/json examples/gno.land/p/nt/avl/v0 examples/gno.land/p/nt/bptree/v0 examples/gno.land/p/nt/cford32/v0 examples/gno.land/p/nt/mux/v0 examples/gno.land/p/nt/seqid/v0 examples/gno.land/p/nt/uassert/v0 examples/gno.land/p/nt/ufmt/v0 >/dev/null
	@git -C third_party/gnoswap sparse-checkout init --cone >/dev/null
	@git -C third_party/gnoswap sparse-checkout set contract/p/gnoswap/uint256 >/dev/null
	@git -C third_party/gno-realms sparse-checkout init --cone >/dev/null
	@git -C third_party/gno-realms sparse-checkout set gno.land/p/aib/encoding gno.land/p/aib/encoding/proto gno.land/p/aib/ics23 gno.land/p/aib/jsonpage gno.land/p/aib/merkle gno.land/p/aib/ibc/app gno.land/p/aib/ibc/host gno.land/p/aib/ibc/lightclient gno.land/p/aib/ibc/lightclient/tendermint gno.land/p/aib/ibc/types gno.land/r/aib/ibc/core >/dev/null
	@mkdir -p $(VENDOR_GNOSWAP_DST) $(VENDOR_ONBLOC_DST) $(VENDOR_NT_AVL_DST) $(VENDOR_BPTREE_DST) $(VENDOR_NT_CFORD32_DST) $(VENDOR_NT_MUX_DST) $(VENDOR_NT_SEQID_DST) $(VENDOR_NT_UASSERT_DST) $(VENDOR_NT_UFMT_DST) $(VENDOR_AIB_ENCODING_DST) $(VENDOR_AIB_PROTO_DST) $(VENDOR_AIB_ICS23_DST) $(VENDOR_AIB_JSONPAGE_DST) $(VENDOR_AIB_MERKLE_DST) $(VENDOR_AIB_APP_DST) $(VENDOR_AIB_HOST_DST) $(VENDOR_AIB_LIGHTCLIENT_DST) $(VENDOR_AIB_TM_DST) $(VENDOR_AIB_TYPES_DST) $(VENDOR_AIB_CORE_DST)
	@rsync -a --delete $(VENDOR_GNOSWAP_SRC)/ $(VENDOR_GNOSWAP_DST)/
	@rsync -a --delete $(VENDOR_ONBLOC_SRC)/ $(VENDOR_ONBLOC_DST)/
	@rsync -a --delete --delete-excluded --exclude='filetests/' --exclude='list/' --exclude='pager/' --exclude='rolist/' --exclude='rotree/' --exclude='*_test.gno' --exclude='*_filetest.gno' $(VENDOR_NT_AVL_SRC)/ $(VENDOR_NT_AVL_DST)/
	@rsync -a --delete --delete-excluded --exclude='list/' --exclude='pager/' --exclude='rolist/' --exclude='rotree/' $(VENDOR_BPTREE_SRC)/ $(VENDOR_BPTREE_DST)/
	@rsync -a --delete --delete-excluded --exclude='*_test.gno' --exclude='*_filetest.gno' $(VENDOR_NT_CFORD32_SRC)/ $(VENDOR_NT_CFORD32_DST)/
	@rsync -a --delete --delete-excluded --exclude='*_test.gno' --exclude='*_filetest.gno' $(VENDOR_NT_MUX_SRC)/ $(VENDOR_NT_MUX_DST)/
	@rsync -a --delete --delete-excluded --exclude='*_test.gno' --exclude='*_filetest.gno' $(VENDOR_NT_SEQID_SRC)/ $(VENDOR_NT_SEQID_DST)/
	@rsync -a --delete --delete-excluded --exclude='*_test.gno' --exclude='*_filetest.gno' $(VENDOR_NT_UASSERT_SRC)/ $(VENDOR_NT_UASSERT_DST)/
	@rsync -a --delete --delete-excluded --exclude='*_test.gno' --exclude='*_filetest.gno' $(VENDOR_NT_UFMT_SRC)/ $(VENDOR_NT_UFMT_DST)/
	@rsync -a --delete --delete-excluded --exclude='*_test.gno' --exclude='*_filetest.gno' $(VENDOR_AIB_ENCODING_SRC)/ $(VENDOR_AIB_ENCODING_DST)/
	@rsync -a --delete --delete-excluded --exclude='*_test.gno' --exclude='*_filetest.gno' $(VENDOR_AIB_PROTO_SRC)/ $(VENDOR_AIB_PROTO_DST)/
	@rsync -a --delete --delete-excluded --exclude='*_test.gno' --exclude='*_filetest.gno' $(VENDOR_AIB_ICS23_SRC)/ $(VENDOR_AIB_ICS23_DST)/
	@rsync -a --delete --delete-excluded --exclude='*_test.gno' --exclude='*_filetest.gno' $(VENDOR_AIB_JSONPAGE_SRC)/ $(VENDOR_AIB_JSONPAGE_DST)/
	@rsync -a --delete --delete-excluded --exclude='*_test.gno' --exclude='*_filetest.gno' $(VENDOR_AIB_MERKLE_SRC)/ $(VENDOR_AIB_MERKLE_DST)/
	@rsync -a --delete --delete-excluded --exclude='*_test.gno' --exclude='*_filetest.gno' $(VENDOR_AIB_APP_SRC)/ $(VENDOR_AIB_APP_DST)/
	@rsync -a --delete --delete-excluded --exclude='*_test.gno' --exclude='*_filetest.gno' $(VENDOR_AIB_HOST_SRC)/ $(VENDOR_AIB_HOST_DST)/
	@rsync -a --delete --delete-excluded --exclude='testing/' --exclude='*_test.gno' --exclude='*_filetest.gno' $(VENDOR_AIB_LIGHTCLIENT_SRC)/ $(VENDOR_AIB_LIGHTCLIENT_DST)/
	@rsync -a --delete --delete-excluded --exclude='testing/' --exclude='*_test.gno' --exclude='*_filetest.gno' $(VENDOR_AIB_TM_SRC)/ $(VENDOR_AIB_TM_DST)/
	@rsync -a --delete --delete-excluded --exclude='*_test.gno' --exclude='*_filetest.gno' $(VENDOR_AIB_TYPES_SRC)/ $(VENDOR_AIB_TYPES_DST)/
	@rsync -a --delete --delete-excluded --exclude='*_test.gno' --exclude='*_filetest.gno' --exclude='README.md' --exclude='recover-client.md' $(VENDOR_AIB_CORE_SRC)/ $(VENDOR_AIB_CORE_DST)/
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

test: verify-gno vendor
	@gno test -v $(USER_GNO_PKGS)

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
