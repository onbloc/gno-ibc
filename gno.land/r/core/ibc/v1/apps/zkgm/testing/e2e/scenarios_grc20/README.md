# GRC20 Filetest Scenarios

This directory contains packet-level filetests for local GRC20 ZKGM flows that
can run through the shared `testing/loader` bootstrap.

The scenarios intentionally stay in this directory when they can use the normal
test loader and remain stable under package-by-package CI execution. This keeps
them aligned with the existing `testing/e2e/scenarios_*` layout.

Some class-change cases need to bootstrap the implementation directly so they
can call `impl.Send` with explicit native `SentCoins`. Those tests are better
kept as unit coverage for now: placing them beside these loader-backed
filetests makes multi-package `gno test` runs sensitive to bootstrap order and
can trip `impl.GetInstance`'s post-bootstrap guard.
