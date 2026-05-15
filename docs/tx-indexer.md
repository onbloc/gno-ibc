# TX Indexer Guide

This guide covers how to use the [tx-indexer](https://github.com/gnolang/tx-indexer) deployed in the gno-ibc test environment for querying IBC transactions and events.

## Connection Info

| Item | Value |
|------|-------|
| GraphQL Playground | http://23.20.153.250:8546/graphql |
| GraphQL Query Endpoint | http://23.20.153.250:8546/graphql/query |
| DB path | /node/indexer-db |

## Management Commands

```bash
# Reset indexer after chain re-initialization
bash ~/reset-indexer.sh

# Check logs
sudo docker logs tx-indexer
```

## GraphQL Query Examples

### Query by Transaction Hash

```graphql
query getTransaction {
  getTransactions(
    where: {
      hash: { eq: "TXHASH_HERE" }
    }
  ) {
    hash
    index
    success
    block_height
    messages {
      typeUrl
      route
      value {
        ...on MsgCall {
          caller
          send
          pkg_path
          func
          args
        }
        ...on MsgRun {
          caller
          send
          package {
            name
            path
            files { name body }
          }
        }
      }
    }
    response {
      events {
        ...on GnoEvent {
          type
          pkg_path
          attrs { key value }
        }
      }
    }
  }
}
```

### Query by Event

```graphql
query getTransactionsByEvent {
  getTransactions(
    where: {
      success: { eq: true },
      response: {
        events: {
          _or: [
            {
              GnoEvent: {
                pkg_path: { eq: "gno.land/p/demo/tokens/grc20" }
                type: { eq: "Transfer" }
                attrs: {
                  key: { eq: "to" }
                  value: { eq: "g1rp7cmetn27eqlpjpc4vuusf8kaj746tysc0qgh" }
                }
              }
            }
          ]
        }
      }
    }
    order: { heightAndIndex: DESC }
  ) {
    hash
    index
    success
    block_height
    messages {
      typeUrl
      route
      value {
        ...on MsgCall {
          caller
          send
          pkg_path
          func
          args
        }
        ...on MsgRun {
          caller
          send
          package {
            name
            path
            files { name body }
          }
        }
      }
    }
    response {
      events {
        ...on GnoEvent {
          type
          pkg_path
          attrs { key value }
        }
      }
    }
  }
}
```

## IBC Event Query Patterns

Common IBC event types to filter on:

| IBC Action | Event Type | pkg_path |
|------------|------------|----------|
| Create client | `create_client` | `gno.land/r/core/ibc/v1` |
| Update client | `update_client` | `gno.land/r/core/ibc/v1` |
| Send packet | `send_packet` | `gno.land/r/core/ibc/v1` |
| Acknowledge packet | `write_acknowledgement` | `gno.land/r/core/ibc/v1` |
| Timeout packet | `timeout_packet` | `gno.land/r/core/ibc/v1` |

To narrow results by a specific client or connection, add an `attrs` filter:

```graphql
attrs: {
  key: { eq: "client_id" }
  value: { eq: "08-cometbls-0" }
}
```

## Tips

- Use the GraphQL Playground at http://23.20.153.250:8546/graphql for interactive exploration and schema introspection.
- `order: { heightAndIndex: DESC }` returns the most recent transactions first.
- Run `bash ~/reset-indexer.sh` any time the chain is restarted from genesis to clear stale index data.
