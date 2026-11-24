# Server research

Research notes on the ArcaneMP server and client, kept apart from the crowd FPS measurements.

| File | Contents |
|---|---|
| [ArcaneMP-1.15.1-notes.md](ArcaneMP-1.15.1-notes.md) | Static analysis of the 1.15.1 server and client binaries: architecture, CLI and config, join flow, scripting API, RPC framing, and the client's CEF settings that affect FPS. |

Method: static analysis only (strings, RTTI, disassembly). Nothing was run or profiled, so findings that concern performance are hypotheses until measured. Addresses and offsets apply to build 1.15.1 only.
