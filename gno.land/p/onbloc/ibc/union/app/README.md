# IBC Union App Interface Package

Pure interface package for IBC Union application callbacks invoked by the
[core realm](../../../../../r/onbloc/ibc/union/core/).

This module exists so application realms can implement the callback contracts
without importing the core realm. Core stores applications behind these
interfaces and dispatches channel, packet, acknowledgement, timeout, and intent
receive callbacks through them.

## Files

- [app.gno](app.gno) defines `IApp` for ordinary IBC Union callbacks.
- [app.gno](app.gno) also defines `IIntentApp` for apps that opt into proofless
  intent receive handling.
