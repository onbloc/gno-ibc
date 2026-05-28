# Client Lifecycle

`CreateClient` allocates a client identifier for the requested client type,
delegates initialization to the registered light-client adapter, stores the
client state and initial consensus state, and emits `CreateClient`.

Example emission:

```json
{
  "type": "CreateClient",
  "attrs": [
    {
      "key": "client_id",
      "value": "1"
    },
    {
      "key": "client_type",
      "value": "cometbls"
    }
  ],
  "pkg_path": "gno.land/r/core/ibc/v1/core"
}
```

`UpdateClient` loads the registered adapter, delegates header verification and
state transition, persists the returned client state and consensus state, and
emits `UpdateClient`.

Example emission:

```json
{
  "type": "UpdateClient",
  "attrs": [
    {
      "key": "client_type",
      "value": "cometbls"
    },
    {
      "key": "client_id",
      "value": "1"
    },
    {
      "key": "height",
      "value": "123"
    }
  ],
  "pkg_path": "gno.land/r/core/ibc/v1/core"
}
```

`ForceUpdateClient` is a deployer-only operational path. It requires an origin
call, requires the target adapter to support the force-update interface, and
then persists the adapter-provided state update. It emits the same
`UpdateClient` event shape as a normal client update.

Status-sensitive proof verification is delegated to registered light-client
adapters. V1 adapters must reject inactive clients before membership or
non-membership proof decoding.
