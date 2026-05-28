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

`CallEnv` carries the relayer as `Caller`, the predicted proxy account, path,
source and destination channel strings, sender bytes, calldata, relayer bytes,
and relayer message bytes. `IntentCallEnv` uses market-maker fields for the
intent receive path.
