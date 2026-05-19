# protogen

Generates `_pb_gen.gno` protobuf encode/decode helpers for Gno structs
annotated with `//gno:protobuf` and `pb:"..."` field tags.

## Why

Gno has no `go generate`, but Gno is a syntactic subset of Go, so the standard
`go/parser` can read `.gno` files. This tool walks the package, finds tagged
structs, and emits the formulaic `pbAppend*` / `pbDecode*` boilerplate that
otherwise gets hand-written in every light client.

## Usage

From the repo root:

```sh
make generate          # regenerate everything in PROTOGEN_PKGS
make generate-check    # CI: regenerate and assert no diff
```

To run the tool directly against an arbitrary package:

```sh
cd tools/protogen
go run . /abs/path/to/pkg [/abs/path/to/pkg ...]
```

## Tag format

```gno
//gno:protobuf
type ClientState struct {
    ChainID         string `pb:"1,bytes"`
    TrustingPeriod  uint64 `pb:"2,varint"`
    FrozenHeight    Height `pb:"5,message,enc=pbEncodeHeight,dec=pbDecodeHeight"`
    ContractAddress H256   `pb:"16,bytes32"`
}
```

Kinds:

| Kind      | Go type                         | Wire           |
|-----------|---------------------------------|----------------|
| `bytes`   | `string`, `[]byte`              | length-delim   |
| `varint`  | `uint64`                        | varint         |
| `int64`   | `int64`                         | varint         |
| `int32`   | `int32`                         | varint         |
| `bytes32` | `[32]byte` or named alias       | length-delim   |
| `message` | nested struct (requires enc/dec) | length-delim   |

For `message`, both `enc=<fn>` and `dec=<fn>` are required. `enc` must be
`func(T) []byte`; `dec` must be `func([]byte) (T, error)`.

## Output contract

For struct `Foo`, the tool writes `foo_pb_gen.gno` next to the source with two
functions: `EncodeFoo(m Foo) []byte` and `DecodeFoo(buf []byte) (Foo, error)`.

The generated code calls into `pbAppend*` / `pbDecode*` / `pbSkipField` /
`toBytes32` helpers that must already exist in the same package — see
`gno.land/p/core/ibc/lightclients/cometbls/misbehaviour.gno` for a reference
implementation.

## Scope

MVP only covers cometbls (`ClientState`, `Misbehaviour`). Adding new packages
to `PROTOGEN_PKGS` in the root Makefile is the way to extend coverage.
Features intentionally out of scope right now: `oneof`, `repeated`, packed
fields, the inline `Timestamp` shape in `LightHeader`, and `Height`'s "skip
field 1" rule (those stay hand-written in `misbehaviour.gno`).
