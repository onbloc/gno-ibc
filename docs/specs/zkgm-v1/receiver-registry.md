# Receiver Registry

Receivers implement `z.Zkgmable`:

```go
type Zkgmable interface {
    OnZkgm(cur realm, env CallEnv) error
    OnIntentZkgm(cur realm, env IntentCallEnv) error
}
```

A receiver registers itself by calling `RegisterReceiver(cross(cur), receiver)`
from its own realm. The proxy keys the registry by `cur.Previous().PkgPath()`,
so each receiver realm can register one receiver. Duplicate registration
panics. `GetReceiver(path)` returns nil when the path is not registered.

## CallEnv

`CallEnv` is what the implementation hands to `OnZkgm` during a `PacketRecv`
dispatch:

```go
type CallEnv struct {
    Caller             string      // relayer that submitted PacketRecv
    ProxyAccount       string      // PredictCallProxyAccount(path, destChannel, sender)
    Path               *u256.Uint  // packed channel-id path
    SourceChannel      string      // source channel id as decimal string
    DestinationChannel string      // destination channel id as decimal string
    Sender             []byte      // ZKGM sender bytes from the source side
    Calldata           []byte      // bytes copied from Call.ContractCalldata
    Relayer            []byte      // raw relayer bytes from the source side
    RelayerMsg         []byte      // raw relayer message bytes
}
```

`IntentCallEnv` has the same shape with `MarketMaker` and `MarketMakerMsg` in
place of `Relayer` and `RelayerMsg`.

## Example

A runnable receiver lives at
[`gno.land/r/gnoswap/ibc/examples/echo`](../../../gno.land/r/core/ibc/examples/echo)
(on disk under `gno.land/r/core/...`; published under the `gnoswap` namespace,
see [Architecture](../architecture.md#realm-topology)). The interesting
contract is:

```go
func init(cur realm) {
    zkgm.RegisterReceiver(cross(cur), receiver)
}

func (r *echoReceiver) OnZkgm(cur realm, env z.CallEnv) error {
    r.calls++
    r.lastCalldata = append([]byte(nil), env.Calldata...)
    return nil
}

func (r *echoReceiver) OnIntentZkgm(cur realm, env z.IntentCallEnv) error {
    return errors.New("echo: intent settlement not implemented")
}
```

Run it end-to-end against an in-memory gnodev chain:

```sh
./tools/gnokey-smoke/run-echo-example.sh
```

The script boots gnodev, invokes the registered receiver with a sample
`CallEnv` via `gnokey maketx run`, and reads back the captured state through
`vm/qeval`. It exits 0 and prints `PASS: echo-receiver example end-to-end`
when the receiver behaves as expected.
