#!/usr/bin/env python3
"""Generate genesis_txs.jsonl for gnoland with all IBC packages.

Packages are emitted in topological dependency order so gnoland can replay
them without forward-reference errors.  The module path (from gnomod.toml)
is used as the on-chain pkgpath, which allows directory paths and module
names to diverge (e.g. gno.land/r/core/... stored as gno.land/r/gnoswap/...).
"""
import argparse
import json
import os
import re
import sys

CREATOR = "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
GAS_WANTED = "100000000"
GAS_FEE = "1000000ugnot"


def read_gno_files(dirpath: str) -> list[dict]:
    files = []
    for fname in sorted(os.listdir(dirpath)):
        is_gno = fname.endswith(".gno")
        is_mod = fname == "gnomod.toml"
        if not is_gno and not is_mod:
            continue
        if fname.endswith("_test.gno") or fname.endswith("_filetest.gno"):
            continue
        with open(os.path.join(dirpath, fname), encoding="utf-8") as f:
            files.append({"name": fname, "body": f.read()})
    return files


def pkg_name_from_files(files: list[dict]) -> str:
    for f in files:
        m = re.search(r"^\s*package\s+(\w+)", f["body"], re.MULTILINE)
        if m:
            return m.group(1)
    return ""


def make_addpkg_tx(pkgpath: str, dirpath: str) -> dict:
    files = read_gno_files(dirpath)
    if not files:
        raise RuntimeError(f"no .gno files found in {dirpath} for {pkgpath}")
    name = pkg_name_from_files(files)
    if not name:
        raise RuntimeError(f"no package declaration found in {dirpath} for {pkgpath}")
    return {
        "tx": {
            "msg": [
                {
                    "@type": "/vm.m_addpkg",
                    "creator": CREATOR,
                    "package": {"name": name, "path": pkgpath, "files": files},
                }
            ],
            "fee": {"gas_wanted": GAS_WANTED, "gas_fee": GAS_FEE},
            "signatures": [{"pub_key": None, "signature": None}],
            "memo": "",
        }
    }


def packages_in_order(ibc_root: str) -> list[tuple[str, str]]:
    """(pkgpath, dirpath) in topological dependency order.

    Omits packages that are already bundled in the default gnoland genesis
    (i.e. present under $GNOROOT/examples/): p/nt/*, p/moul/md, p/onbloc/diff,
    p/onbloc/json, p/demo/tokens/grc20, r/demo/defi/grc20reg.
    """
    g = ibc_root + "/gno.land"
    return [
        # layer 0 — no local deps
        ("gno.land/p/gnoswap/uint256",                                 f"{g}/p/gnoswap/uint256"),
        ("gno.land/p/core/encoding/rlp",                               f"{g}/p/core/encoding/rlp"),
        ("gno.land/p/aib/encoding",                                    f"{g}/p/aib/encoding"),
        # layer 1 — single dependency on layer 0
        ("gno.land/p/aib/encoding/proto",                              f"{g}/p/aib/encoding/proto"),
        ("gno.land/p/aib/ics23",                                       f"{g}/p/aib/ics23"),
        ("gno.land/p/aib/ibc/host",                                    f"{g}/p/aib/ibc/host"),
        ("gno.land/p/core/encoding/abi",                               f"{g}/p/core/encoding/abi"),
        ("gno.land/p/core/ethereum/mpt",                               f"{g}/p/core/ethereum/mpt"),
        # layer 2
        ("gno.land/p/aib/merkle",                                      f"{g}/p/aib/merkle"),
        ("gno.land/p/aib/jsonpage",                                    f"{g}/p/aib/jsonpage"),
        ("gno.land/p/aib/ibc/types",                                   f"{g}/p/aib/ibc/types"),
        ("gno.land/p/core/ethereum/storage",                           f"{g}/p/core/ethereum/storage"),
        ("gno.land/p/core/ibc/lightclients/cometbls",                  f"{g}/p/core/ibc/lightclients/cometbls"),
        ("gno.land/p/core/ibc/lightclients/statelensics23mpt",         f"{g}/p/core/ibc/lightclients/statelensics23mpt"),
        ("gno.land/p/gnoswap/ibc/zkgm",                                f"{g}/p/core/ibc/zkgm"),
        ("gno.land/p/gnoswap/tokenbucket",                             f"{g}/p/core/tokenbucket"),
        # layer 3
        ("gno.land/p/aib/ibc/app",                                     f"{g}/p/aib/ibc/app"),
        ("gno.land/p/aib/ibc/lightclient",                             f"{g}/p/aib/ibc/lightclient"),
        # layer 4
        ("gno.land/p/aib/ibc/lightclient/tendermint",                  f"{g}/p/aib/ibc/lightclient/tendermint"),
        # layer 5
        ("gno.land/p/aib/ibc/lightclient/tendermint/testing",          f"{g}/p/aib/ibc/lightclient/tendermint/testing"),
        # layer 3 — realms, no realm deps
        ("gno.land/r/aib/ibc/core",                                    f"{g}/r/aib/ibc/core"),
        ("gno.land/r/core/ibc/v1/core",                                f"{g}/r/core/ibc/v1/core"),
        # layer 4
        ("gno.land/r/core/ibc/v1/lightclients/cometbls",              f"{g}/r/core/ibc/v1/lightclients/cometbls"),
        ("gno.land/r/core/ibc/v1/lightclients/statelensics23mpt",      f"{g}/r/core/ibc/v1/lightclients/statelensics23mpt"),
        ("gno.land/r/gnoswap/ibc/v1/apps/zkgm",                       f"{g}/r/core/ibc/v1/apps/zkgm"),
        # layer 5
        ("gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/mock",          f"{g}/r/core/ibc/v1/apps/zkgm/testing/mock"),
        ("gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/impl",               f"{g}/r/core/ibc/v1/apps/zkgm/v0/impl"),
        # layer 6
        ("gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader",             f"{g}/r/core/ibc/v1/apps/zkgm/v0/loader"),
        # layer 7
        ("gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e",           f"{g}/r/core/ibc/v1/apps/zkgm/testing/e2e"),
        # layer 8
        ("gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e/scenarios", f"{g}/r/core/ibc/v1/apps/zkgm/testing/e2e/scenarios"),
        ("gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls",  f"{g}/r/core/ibc/v1/apps/zkgm/testing/realcometbls"),
        # layer 9
        ("gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls/scenarios", f"{g}/r/core/ibc/v1/apps/zkgm/testing/realcometbls/scenarios"),
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ibc-root", required=True, help="path to gno-ibc repo root")
    parser.add_argument("--output", required=True, help="output .jsonl file path")
    args = parser.parse_args()

    written = 0
    skipped = []
    with open(args.output, "w", encoding="utf-8") as out:
        for pkgpath, dirpath in packages_in_order(args.ibc_root):
            if not os.path.isdir(dirpath):
                skipped.append((pkgpath, dirpath))
                continue
            tx = make_addpkg_tx(pkgpath, dirpath)
            out.write(json.dumps(tx, ensure_ascii=False) + "\n")
            written += 1

    print(f"wrote {written} addpkg transactions → {args.output}", file=sys.stderr)
    if skipped:
        print("skipped (no .gno files or missing dir):", file=sys.stderr)
        for p, d in skipped:
            print(f"  {p}  ({d})", file=sys.stderr)


if __name__ == "__main__":
    main()
