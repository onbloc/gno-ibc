# IBC Union ZKGM Types Package

Pure package for UCS03-ZKGM wire types, ABI codecs, path helpers, salts,
prediction helpers, and receiver interfaces.

The proxy and v1 implementation realms use this package for packet envelopes,
instructions, token orders, acknowledgements, call environments, channel paths,
wrapped-token predictions, and salt derivation.

## Files

- [types.gno](types.gno) defines packet, instruction, token order, metadata,
  and ack structures.
- [abi.gno](abi.gno) encodes and decodes ZKGM packets and operands.
- [interfaces.gno](interfaces.gno) defines `Zkgmable` receiver callbacks and
  call environments.
- [path.gno](path.gno) updates and reads multi-hop channel paths.
- [predict.gno](predict.gno) derives wrapped-token denoms and call proxy
  accounts.
- [salt.gno](salt.gno) derives sender, batch, and forward salts.
- [constants.gno](constants.gno) holds protocol constants and opcode/tag
  values.

## Subpackages

- [tokenbucket/](tokenbucket/) implements the rate-limit bucket used by the ZKGM
  app realm.
