#!/usr/bin/env python3
"""Generate genesis_txs.jsonl for gnoland with all IBC packages.

Packages are emitted in topological dependency order so gnoland can replay
them without forward-reference errors. Package paths are read from gnomod.toml
module fields; dependency order is derived from imports in .gno source files.
Packages already present in the gnoland genesis (discovered from
$GNOROOT/examples/) are excluded automatically.
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


def scan_modules(root: str) -> dict[str, str]:
    """Walk root for gnomod.toml files. Returns {pkgpath: dirpath}."""
    packages: dict[str, str] = {}
    for dirpath, _, filenames in os.walk(root):
        if "gnomod.toml" not in filenames:
            continue
        with open(os.path.join(dirpath, "gnomod.toml"), encoding="utf-8") as f:
            content = f.read()
        m = re.search(r'^module\s*=\s*"([^"]+)"', content, re.MULTILINE)
        if m:
            packages[m.group(1)] = dirpath
    return packages


def local_imports(dirpath: str) -> list[str]:
    """Return gno.land/* import paths declared in import blocks of non-test .gno files."""
    imports: set[str] = set()
    import_block = re.compile(r'\bimport\s*\(([^)]*)\)', re.DOTALL)
    import_single = re.compile(r'\bimport\s+"(gno\.land/[^"]+)"')
    quoted = re.compile(r'"(gno\.land/[^"]+)"')
    for fname in os.listdir(dirpath):
        if not fname.endswith(".gno"):
            continue
        if fname.endswith("_test.gno") or fname.endswith("_filetest.gno"):
            continue
        with open(os.path.join(dirpath, fname), encoding="utf-8") as f:
            content = f.read()
        for block in import_block.findall(content):
            imports.update(quoted.findall(block))
        imports.update(import_single.findall(content))
    return list(imports)


def topological_sort(
    packages: dict[str, str],
    emit: set[str],
) -> list[tuple[str, str]]:
    """Kahn's algorithm over emit, using .gno import blocks as edges."""
    in_degree = {pkg: 0 for pkg in emit}
    dependents: dict[str, list[str]] = {pkg: [] for pkg in emit}

    for pkg in emit:
        for imp in local_imports(packages[pkg]):
            if imp in emit and imp != pkg:
                in_degree[pkg] += 1
                dependents[imp].append(pkg)

    queue = sorted(pkg for pkg, deg in in_degree.items() if deg == 0)
    result: list[tuple[str, str]] = []

    while queue:
        pkg = queue.pop(0)
        result.append((pkg, packages[pkg]))
        for dep in sorted(dependents[pkg]):
            in_degree[dep] -= 1
            if in_degree[dep] == 0:
                queue.append(dep)

    if len(result) != len(emit):
        cycle = emit - {pkg for pkg, _ in result}
        raise RuntimeError(f"cycle detected among packages: {cycle}")

    return result


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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ibc-root", required=True, help="path to gno-ibc repo root")
    parser.add_argument("--gno-root", required=True, help="path to gnoland repo root (used to discover genesis packages)")
    parser.add_argument("--output", required=True, help="output .jsonl file path")
    args = parser.parse_args()

    genesis_pkgs = set(scan_modules(os.path.join(args.gno_root, "examples")))
    all_packages = scan_modules(os.path.join(args.ibc_root, "gno.land"))
    emit = {pkg for pkg in all_packages if pkg not in genesis_pkgs}
    ordered = topological_sort(all_packages, emit)

    written = 0
    with open(args.output, "w", encoding="utf-8") as out:
        for pkgpath, dirpath in ordered:
            tx = make_addpkg_tx(pkgpath, dirpath)
            out.write(json.dumps(tx, ensure_ascii=False) + "\n")
            written += 1

    print(f"wrote {written} addpkg transactions → {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
