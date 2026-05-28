# IBC Native Function Gas Table

Calibrated gas costs for the IBC / CometBLS native bindings registered
in `gnovm/stdlibs/native_gas.go`.

Gas model: `gas = Base + Slope × N / 1024` (1 gas = 1 ns on reference
hardware). The slope axis (e.g. `len(data)`) is read from the indicated
parameter at runtime.

Calibrated on Apple M5 ARM64. Both calibration sets (these rows and the
pre-existing sha256/ed25519/etc. rows on M2) must be re-run on the reference
Xeon 8168 before any consensus-relevant deployment.

Calibrated rows are stored in
[`stdlibs/native_gas_calibration.txt`](../stdlibs/native_gas_calibration.txt)
and injected into the pinned Gno cache by `make install-gno`. See
[docs/README.md](README.md#local-development) for the toolchain setup that
performs the injection.

## Gas table

| Pkg.Fn | Shape | Base (gas) | Slope (gas / 1024 N) | Slope axis | R² |
|---|---|---:|---:|---|---:|
| `crypto/keccak256.sum256` | linear | 344 | 6,729 | `len(data)` bytes | 0.999 |
| `crypto/bn254.g1Add` | flat | 2,405 | — | — | — |
| `crypto/bn254.g1Mul` | flat | 24,831 | — | — | — |
| `crypto/bn254.pairingCheck` | linear | 360 | 1,056,325 | `len(input)` bytes (192 B / pair) | 0.935 |
| `crypto/cometbls.verifyZKP` | flat | 1,320,088 | — | — | — |
| `crypto/merkle.leafHash` | linear | 399 | 5,740 | `len(leaf)` bytes | 1.000 |
| `crypto/merkle.innerHash` | flat | 829 | — | — | — |
| `crypto/merkle.hashFromByteSlices` | linear | 645 | 9,546 | `len(encoded)` bytes | 1.000 |
| `crypto/merkle.verifySimpleProof` | linear | 939 | 9,122 | `len(aunts)` bytes (= depth × 32) | 0.893 |
| `crypto/modexp.modExp` | linear | 22,405 | 7,573,342 | `len(exp)` bytes (modulus held at 256 B) | 0.978 |

## Representative call costs

| Call | Computation | Gas |
|---|---|---:|
| `keccak256(32 B)` | 344 + 6729·32/1024 | ~554 |
| `keccak256(1 KB)` | 344 + 6729·1024/1024 | ~7,073 |
| `bn254.g1Add` | flat | 2,405 |
| `bn254.g1Mul` | flat | 24,831 |
| `bn254.pairingCheck` (1 pair, 192 B) | 360 + 1056325·192/1024 | ~198,421 |
| `bn254.pairingCheck` (2 pairs, 384 B) | 360 + 1056325·384/1024 | ~396,482 |
| `cometbls.verifyZKP` | flat (Groth16 verify) | 1,320,088 |
| `merkle.leafHash(32 B)` | 399 + 5740·32/1024 | ~578 |
| `merkle.innerHash` | flat | 829 |
| `merkle.hashFromByteSlices` (256 × 32 B leaves = 9,220 B) | 645 + 9546·9220/1024 | ~86,597 |
| `merkle.verifySimpleProof` (depth=10, aunts=320 B) | 939 + 9122·320/1024 | ~3,790 |
| `modexp` (RSA-2048, exp=256 B) | 22405 + 7573342·256/1024 | ~1,915,740 |
| `modexp` (exp=32 B) | 22405 + 7573342·32/1024 | ~259,072 |

## Notes

- **`crypto/cometblszk`**: pure-Gno package — no native entries. Its call
  cost is the sum of the underlying natives it invokes (`bn254.*`,
  `keccak256.sum256`, etc.).
- **`modexp` limitation**: the model holds the modulus at 256 B and slopes
  on `len(exp)`. Callers with smaller modulus are overcharged (safe);
  callers with modulus larger than 256 B would be undercharged (DoS
  vector). Current IBC clients do not exercise the latter, but a custom
  charger should replace this single-slope shape before any non-IBC
  consumer ships.
- **`bn254.pairingCheck`** has the lowest R² (0.935) — still acceptably
  linear, matches EIP-197 cost shape.
- All numbers are nanoseconds (since `1 gas = 1 ns`). Xeon 8168 is
  typically 1.5–2× slower than M5, so re-calibration on the reference
  hardware is mandatory before mainnet.
