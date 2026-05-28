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
place of `Relayer` and `RelayerMsg`. It is the parameter passed to
`OnIntentZkgm` on the intent-settlement path.

## Minimal receiver example

```go
import (
    "std"
    z "gno.land/p/gnoswap/ibc/zkgm"
    "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

type echoReceiver struct{}

func (r *echoReceiver) OnZkgm(cur realm, env z.CallEnv) error {
    // env.Calldata carries the bytes the source side packed into Call.ContractCalldata.
    return nil
}

func (r *echoReceiver) OnIntentZkgm(cur realm, env z.IntentCallEnv) error {
    return nil
}

func init() {
    zkgm.RegisterReceiver(cross(cur), &echoReceiver{})
}
```
