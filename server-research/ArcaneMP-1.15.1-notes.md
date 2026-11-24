# ArcaneMP 1.15.1 server: reverse engineering notes

Method: static analysis only (PE headers, imports/exports, strings, MSVC RTTI demangled with `llvm-undname`, and `objdump -d` disassembly). Nothing was executed or profiled. Sections 1 to 11 come from strings and type names in `server/ArcaneMPServer.exe`; sections 12 to 13 from its disassembly; section 14 from `client/ArcaneMPClient.dll`. Items marked (inferred) are conclusions, not read directly from code. Build analysed: ArcaneMP 1.15.1. Addresses change with every build.

## 1. What it is

- Multiplayer mod server for Hogwarts Legacy ("HogwartsMP", id `hogwarts-mp`, name `arcanemp-server`, version string `1.15.1`, release channel `stable`).
- Built on the MafiaHub Framework 44.1.1 (built by CI at `C:\actions-runner-hogwarts\...\Framework-44.1.1-windows`). The framework supplies networking, replication, HTTP, voice, scripting and crash reporting. ArcaneMP code lives in the `ArcaneMP::` namespaces.
- Native x64 C++ (MSVC 14.51), console subsystem. Imports `libnode.dll` (Node.js with V8) and `WINHTTP`, `WS2_32`, `IPHLPAPI`, `CRYPT32`. `server-linux/` is the same product (251 `ArcaneMP` strings), linked against `libnode.so.147`.
- Sentry/Crashpad crash reporting is built in (`crashpad_handler`, `session.json`, `/cache/sentry`, `/envelope/`). It can be disabled ("Crash reporting disabled: {}").

## 2. Process architecture

Startup log: `Host / Port / Max Players / Password / Threads: N cores: tick, network, packet, N replication, N background, N script platform, N web`.

| Thread | Role |
|---|---|
| tick | Game loop. Warns "Server tick took X ms against a Y ms budget". |
| network | MafiaNet (RakNet fork) peer: connection requests, build check, ticket and account proof. |
| packet | Dispatches RPC handlers keyed by a 64-bit hash (`{:016x}`). Warns on slow handlers (`slow-packet-handler-ms`). |
| replication (N) | Entity replication pass shared with the tick thread. |
| background (N) | Blocking work taken off the tick thread. |
| script platform | Node.js/V8 platform. Warns on slow scripts (`slow-script-ms`). |
| web | httplib HTTP server (asset file server). |

## 3. CLI options (cxxopts)

| Flag | Meaning |
|---|---|
| `-p, --port` | Networking port to bind |
| `-h, --host` | Networking host to bind |
| `-c, --config` | JSON config file (default `server.json`; a default is written if missing) |
| `-t, --server-token` | Masterlist push token. The server is announced only when this is set. |
| `--password` | Join password (max 255 bytes; empty = open) |
| `--maxplayers` | Capped by a hard limit compiled into the build |
| `--download-url` | http(s) base URLs clients fetch resource files from before the game port |
| `--max-downloading` | Extra connections admitted while they download (0 = downloads use player slots) |
| `--package-secret` | Secret for the resource package key (defaults to the server token) |
| `--replication-threads`, `--background-threads` | -1 = size to host, 0 = none |
| `--slow-script-ms`, `--slow-packet-handler-ms` | Warning thresholds |
| `--log-file`, `--log-level`, `--no-rate-limit` | Logging and rate limiting |

Config validation messages: `bindHost is required`, `bindPort must be in the range 1-65535`, `maxPlayers must be greater than 0`, `download-url entries must start with http(s)://`. Defaults seen: host `0.0.0.0`; masterlist `https://masterlist.mafiahub.dev`; API `https://api.mafiahub.dev`.

`server.json` has top-level keys such as `resources`, `description`, `tickRate`, and a `mod` block. Unknown `mod.*` keys log "not a key this build understands; keeping it". Known `mod` keys, published to clients as "replicated config":

- `mod.autoRespawn`
- `mod.broomUpgradeTier` (0-3)
- `mod.broomSpeedMultiplier` (0.25-3)
- `mod.gearStatMultiplier` (0-1)
- `mod.gearTraits`
- `mod.curseforge` (CurseForge project ids every client installs before joining)

## 4. Console commands

`help`, `stop` (stops a resource if given one, otherwise the server), `status`, `resmon` (per-resource script time, heap and GC over the last minute; `resmon heap` for memory), `start <res>`, `restart <res>`, `ensure <res>`, `refresh`, `refreshall`. Console input also raises a `consoleCommand` script event.

## 5. Networking and join flow

Transport: MafiaNet over UDP on `bindPort`, with a reliable event channel and delta-tracked variable lists. Rate limits apply per address and per client script event.

Order of events (from log strings):

1. **Connection request.** Refused if it has no identity, if the address asks too often, if the server is full, or if the account proof fails ("Your client could not prove its account. Update it and try again.").
2. **Account proof.** The request is signed with the account key (domain tag `mafiahub-account-key-v1`). `accountId` is a 32-hex-character id that is the same across servers and sessions. The docs say to key bans, whitelists and saved data on `accountId` only.
3. **Unverified identifiers.** Steam, Epic, Discord and the framework hardware id are client-reported and "a modified client can send anyone's". The docs say never to key ownership, bans or permissions on them.
4. **Launch ticket.** The `ticket` from the client's launch link is passed to scripts untouched. Checking it is the server owner's job.
5. **Build verification.** `Build verified for player guid` / `Build mismatch ... dropping peer`. Verification can be turned off ("Build token verification DISABLED; accepting any client version").
6. **`playerConnecting`.** A script event where a resource can hold or reject the join, followed by the resource list, asset download and `OnPlayerReady`, `OnPlayerConnect`.
7. **Password.** Applied to the networking peer itself. Max 255 bytes.

Replication: `ReplicationManager` with a `World` and per-player interest streaming. Players only see each other when they share a virtual world and the same game map. Entity types in `ArcaneMP::Shared`: Human, Character, Npc, Beast, Door, Gate, Arena, BrewingSite, HerbPlot, Lootable, LevelObjects, Collider, Fx, Light, WandLink, WorldObject. `World` and `TextLabel` come from the framework.

## 6. Client-to-server RPCs (`ArcaneMP::Shared::RPC`)

Authoritative checks are done by the server where it has the data; most of these are client reports (the docs call them "client-reported: validate before acting").

- Combat and world: `ReportPvpHit`, `ReportNpcDamage`, `ReportColliderSpellHit`, `HazardState`
- Beasts: `ReportBeastCaptureCommitted`, `ReportBeastCare`, `ReportBeastReleased`
- Doors and progression: `ReportDoorUnlockRequest`, `ReportDoorUnlocked`, `ReportHousePointsRequest`
- Map and travel: `ReportPlayerMapDiscovery`, `ReportPlayerFlooFlames`, `RequestPlayerFastTravel`, `StreamedTeleportRequest/Result`, `MapTravelResult`
- NPCs: `RequestNpcAdoption`
- Inventory: `InventoryEntry`

Server-side handler groups (`ArcaneMP::Core::Handlers`): Creature, Door, HousePoints, Inventory, MapFog, Npc, Teleport.

## 7. Game services (`ArcaneMP::Core::Modules`)

`HoldService`, `HousePointsService`, `MoveService`, `NpcService` (with `NpcRewardPolicy`), `SanctuaryService` (creature sanctuary), `VivariumService` (breeding, births, byproducts), `Encounters` (`ArenaService`, `EncounterArea`, enemy camps and waves, `World.setEncounterPolicy("server")`), `Train`, and `Zones` (volumes that report entity crossings 10 times a second).

## 8. Scripting

- Resources are JavaScript packages in `resources/`, each with a `package.json`. The server discovers them, orders them by dependency (cycle detection, optional dependencies) and starts each in its own Node.js runtime. Duplicate names are rejected.
- Exports must be declared in the `package.json` `exports` array, otherwise "Registering undeclared export" is logged. `Imports` gives access to another resource's exports.
- Client assets: a resource can ship client files and Unreal asset paks ("lanes", lowercase `[a-z0-9_-]` names). The server encrypts them into `.fwpak` packages under `.packages`, with `.chunks` lists and sha256 fingerprints. Hot reload is broadcast to clients (`Broadcasting hot-reload of resource`).
- Sandbox (embedded JS): `require` blocks `fs`, `net`, `dgram`, `tls`, `http(s)`, `http2`, `dns`, `child_process`, `worker_threads`, `cluster`, `vm`, `v8`, `perf_hooks`, `async_hooks`, `module`, `wasi`, `sqlite`, `inspector` and others. `process.env` is frozen empty. `process.exit`, `abort`, `kill`, `chdir`, `dlopen`, `binding` are disabled. String-based code generation is disabled at the C++ level. The sandbox is a denylist, so a package that re-exports a blocked module is only partly covered (the code itself comments on this).
- Exposed objects (v8pp bindings): `Player` (large surface: health, visibility, collision, ragdoll, animal forms, perches, teleport, map travel, PvP flags and teams, broom and gear tuning, UI via CEF `showUI/sendUI`), `NPC`, `Character`, `Beast`, `Fx`, `Light`, `WandLink`, `WorldObject`, `Zone`, `World`, `Pvp`, `Events`, `Creator`, plus math types `Vector2/3/4`, `Quaternion`, `Color`, `Entity`.
- Typed event map (`EventMap`) with game events such as `playerConnecting`, `playerDied`, `playerDownedEnd`, `playerInventoryChanged`, `playerTeleportComplete`, `playerMapTravelComplete`, `playerLocationChanged`, `playerFastTravelUnlocked`, `playerVoiceStart/Stop/TierChange`, and many audio events. Chat lines not starting a command go to resources if any listens; otherwise the server relays them.

## 9. HTTP surface

A single httplib server, TCP, for asset delivery: `GET /files/<token-or-path>` with `X-Download-Token`, `X-Queue-Position`, `Retry-After`, `.chunks` range lists. Download tokens are issued per peer from a random source. If neither `--package-secret` nor `--server-token` is set, the package key is derived from the mod slug alone and "anyone can recompute it" (the server logs this itself). Package nonce derivation uses HMAC with the tag `FWPK-nonce-v1`.

## 10. Voice

`VoiceServer` relay (`gUVoice`) with tier events. If the relay cannot start: "Voice relay unavailable; voice chat disabled".

## 11. Findings worth acting on if you run it

- Set `--server-token` or `--package-secret`. Without one, resource package keys are derivable by anyone.
- Key bans and permissions on `player.accountId`, never on Steam/Epic/Discord ids or the hardware id.
- Treat all `Report*` RPCs and client-reported events as untrusted input.
- The scripting sandbox is a denylist; review third-party resources before installing them.
- Disabling build verification accepts any client version.

## 12. Wire protocol (disassembly pass)

Method: `objdump -d` of the whole `.text`, then following cross-references from log strings and RTTI vtables. Addresses are virtual addresses in `ArcaneMPServer.exe` 1.15.1 (image base `0x140000000`); they change with every build.

**Transport primitives (confirmed in code)**
- Messages are MafiaNet `BitStream`s (RakNet lineage; the binary also contains `RPC4` and `ReplicaManager3`/`Connection_RM3` types, so entity replication uses RM3 and the game RPCs sit on top).
- Bit writer/reader helpers: `0x140565950` (write N bits), `0x140564e90` (read N bits), `0x140565740` (write aligned bytes), `0x1405648e0` (reports whether the host needs an endian swap), `0x1405653f0` (byte-reverse helper, used only when the swap flag says so). Fixed-width integers are written as 8/16/32/64 bits, not variable-length.
- **RPC framing:** the receive function at `0x140403ae0` reads a **64-bit id** (`ReadBits(…, 0x40)`), then the payload. The same id is what the log prints as `{:016x}`. The handler map lookup and the "payload was cut short" drop are at `0x1404045d0` to `0x140404700`; the slow-handler timer is at `0x1404055b0`.
- **Registration:** `0x140408230` registers a handler for an id (and logs "registered after the packet thread started" if called too late). It is called from **67 sites**, each with the id passed as a 64-bit immediate, so ids are compile-time constants. The list of site addresses and ids was extracted to a scratch file and is reproduced in section 13.
- **Named-string message (confirmed layout):** the function at `0x140407d00` sends `u32`, then `u16` length, then that many bytes, as a reliable message (reliability argument 3). This is a generic "named payload" send, probably the resource/client-event message.
- Each typed handler is a `std::function` wrapper. Its `_Do_call` copies the decoded struct and hands it to the script thread. For `RequestNpcAdoption` the in-memory struct is `{ u32; std::string; std::string }` (a number followed by two strings), taken from the wrapper at `0x1402a9d60` (found through its RTTI complete-object locator at `0x14110ca10`).

**Not recovered**
- **The id hash.** I tested FNV-1a/FNV-1, djb2, sdbm and XXH64 over about 25 spellings of each RPC name (bare, `ArcaneMP::Shared::RPC::X`, MSVC `struct ` prefix, RTTI raw name `.?AUX@RPC@Shared@ArcaneMP@@`, with and without a NUL). None matched any of the 67 ids. The hash is probably seeded, salted, or computed over a string I have not seen (for example a framework-side type key). It needs the `constexpr` hash function itself, which the optimizer folded away, so the way forward is the client DLL or the Framework source.
- **Per-field layouts of the 18 named structs.** The serializer for each struct is inlined into its handler registration site, so each needs its own read-through. Only `RequestNpcAdoption` is partly known (above).
- **MafiaNet connection-level message ids** (the first byte of each datagram), and the RM3 construction payload layouts for each entity type.

## 13. Registered RPC ids (67 sites)

Handler registration site -> 64-bit id (hex), as extracted from the `movabs` immediate before each call to `0x140408230`. The id-to-name mapping is not recovered, so these are anonymous. Matching an id to a struct needs the wrapper that the same site installs.

```
14016598e 1c1860b349580159   140165b0a f00b85294a253de5   140169283 fb401503303e0b0a
14019bf53 a919c0ff82a6ed57   1401cb2c4 31a5670b158d8ab2   1401cb493 64bbd62b4f3fee28
1401cb65f 9a707d759ff60438   1401cb7cd e71f03591aabf959   1401cb8f1 0ef175388d01c10f
1401cba18 045f5019f6d82a5c   1401cbb3a 427dc679567ec228   1401cbc61 78adcb6cfec82861
1401cbd83 b370cba66e3069db   1401e9bd6 728780f555ed0e46   1401e9dab 44f68f762c5098b2
1402023b3 8c9626c36f6f20e1   140222283 159d5d319377fcb7   1402273b3 d977f20d23989697
14023568f e830aab7fc185bb6   14023585c 9eacf5d63421b9c9   1402359d7 ebbde84a979c0066
140235b46 5cbfa70b943cbd02   140235c62 b2b6991c03ca3ef1   140235d84 a46347be996b272f
140235ea1 e15b460d6621cc6d   1402789c3 f0ddf87258dbcb5c   140280d23 638641ad967b5d12
1402a869e 93d45ec870bc513c   1402a8870 7476326c6b6d2cfe   1402a8a3f 4a477e233801397e
1402a8bb2 896980c8aafd7f60   1402a8cd1 4cbefb7474b92966   1402a8df8 d1d2c023ebfe274c
1402a8f1f d8d1c6397d511dac   1402a9041 8c89e8ba5fe1585d   1402a9163 8d61a9859aeee18d
1402a9285 1987ffeae5930de9   1402a93a7 128ebebf6061400d   1402a94c9 104e85687523025a
1402f49ca 17dcada88453d2aa   (+ 27 more sites, not listed here)
```

**Correction after checking the client DLL:** all 67 constants also appear in `ArcaneMPClient.dll`, in `.rdata` tables that sit next to unrelated strings (for example creature names such as "Hippogriff" and "Graphorn"). The constants are therefore not confirmed to be RPC ids. They are 64-bit keys passed to the same registration function, and what they hash is still unknown. About 67,000 strings from both binaries were hashed with FNV-1a and FNV-1 with no match, so the hash is seeded, salted or a different algorithm.

## 14. Client-side findings relevant to low FPS (static analysis only, nothing measured)

Client = `ArcaneMPClient.dll` (injected into the game). It imports `libcef.dll`, `libnode.dll`, `d3d11/d3d12/dxgi`, and Discord and voice code.

| Area | Evidence | Reading |
|---|---|---|
| In-game UI | CEF in windowless (off-screen) mode. Each paint is copied from a shared GPU texture into the game's D3D11/D3D12 pipeline. Log strings: "shared texture copy timed out", "paint dropped, frame fence never reached", "falling back to CPU path", "accelerated paint does not support a deferred context, using the CPU path". CEF flags include `disable-gpu`, `disable-gpu-compositing`, `force-high-performance-gpu`. The UI is a React bundle. `vk_swiftshader.dll` (software renderer) ships with the client. | The CPU path copies full frames through system memory every paint. A shared-texture copy that waits on a GPU fence stalls on a busy GPU. CEF's GPU and renderer processes also compete with the game for the same GPU and cores. |
| Game hook | `ProcessEvent` is detoured through MinHook. The detour (`0x180242fa0` in this build) runs on every Unreal function call: two hash-map lookups (FNV-1a over an 8-byte key), then about a dozen flag checks and compares before calling the original. | This executes on the game thread, and Unreal calls `ProcessEvent` many thousands of times per frame. The per-call work is small and mostly early-outs, but the total is unmeasured. The client's own docs say a per-frame reflected call "is not free". |
| Render hooks | DX12 `Present` and `ExecuteCommandLists` hooks, ImGui overlay. | Each adds work on the render thread every frame. |
| Client scripting | "Client scripting module initialized with standalone V8 engine". Log text "its arguments cannot be copied to the script thread". | Client scripts run on their own thread, not the game thread. V8 is a CPU competitor, not a per-frame blocker. |
| Server scripting | Node.js runs only in the server process (and the client ships `libnode.dll` for V8). | Server-side Node cannot lower a client's frame rate. It can cause rubber-banding and delayed events. |

### CEF configuration (read from the client code)

- **Browser creation** (function around `0x18072d8dc`, build 1.15.1): `cef_browser_settings_t` is zeroed (`size = 0x108`) and then `windowless_frame_rate` (offset 8) is set to **`0xf0` = 240**. It is a hard-coded immediate, not read from a config. The window info requests windowless rendering and shared-texture paint. Bundled CEF is `156.0.14` (Chromium 156). I could not confirm from the binary whether this CEF build caps the rate below 240, so the effective paint rate is unverified.
- **Command-line switches** (function around `0x18075bf90`): when a boolean on the app object (`this+0x41`) is **false**, it appends `disable-gpu`, `disable-gpu-compositing` and `disable-gpu-process-crash-limit`. When it is true, it skips those three. In both cases it appends `force-high-performance-gpu`, `disable-extensions`, `disable-pdf-extension`, `disable-spell-checking`, `disable-component-update`, plus `disable-features=WebUSB,WebHID,NetworkServiceInProcess2` and `autoplay-policy=no-user-gesture-required`. **Traced:** the boolean is the sixth parameter of the CEF initializer at `0x180726170`. That function has exactly one caller, at `0x1801d1626`, and the caller passes a constant `0` (`mov BYTE PTR [rsp+0x28], 0` just before the call). The initializer copies it into the App object (`App+0x41`, at `0x1807275e4`) and into its own state (`this+0xc8`). The App constructor (`0x180723d30`) also zeroes it. No other write to it was found in the CEF code region. So in this build CEF always starts with `disable-gpu`, `disable-gpu-compositing` and `disable-gpu-process-crash-limit`, and the GPU is never enabled for the UI. The remaining switches are appended either way. Caveat: this is read from machine code without running it, and I did not check whether libcef or the game overrides these switches elsewhere.
- **`disable_web`:** the client checks a `disable_web` setting and, if present, logs "disable_web flag present, skipping web manager init" and does not start CEF at all. I did not confirm where it is read from (launcher argument, config file or environment).
- **Paint path:** shared-texture copy with fence wait, with a CPU fallback and a "paint dropped" path (see table above).

## 15. Not done

- Nothing was run, profiled or timed in this analysis, so section 14 is a ranked hypothesis, not a diagnosis. A local test of a client copy with the GPU switch enabled reported some FPS improvement; no numbers were recorded.
- No dynamic analysis: no packet capture, no full decompilation of handler bodies.
- RPC id to name mapping and per-struct field layouts are not recovered (see section 12).
- `libnode.dll` / `libnode.so.147` are stock Node.js builds and were not examined.
- Only the CEF and `ProcessEvent` parts of `ArcaneMPClient.dll` were read; the pattern files and the rest of the client were not.
