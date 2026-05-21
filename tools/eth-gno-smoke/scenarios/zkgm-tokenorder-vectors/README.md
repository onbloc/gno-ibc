# ZKGM TokenOrder vectors

These fixtures preserve TokenOrderV2 payloads captured while testing Gno to
Union Sepolia integration.

They are offline regression inputs. The checker validates the ABI field layout,
amounts, token bytes, order kind, and INITIALIZE metadata without calling Union,
Sepolia, or a relayer.

```sh
tools/eth-gno-smoke/fixture.sh zkgm-tokenorder-vectors --check
```
