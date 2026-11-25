# ArcaneMP crowd FPS

Hogwarts Legacy with the ArcaneMP multiplayer mod loses FPS as more players are nearby.
This repository holds the measurements, a one-click workaround for players, and the test harness for modders.

Not affiliated with ArcaneMP, MafiaHub, Avalanche Software or WB Games.

## For players

1. Download `arcanemp-crowd-fix.zip` from Releases and unzip it anywhere (the game folder is fine).
2. Close the game.
3. Double-click `install.bat` (strong) or `install-mild.bat` (mild).
4. Play as usual. Works with the Forge launcher and the ArcaneMP launcher (both use the same settings folder).

Undo: close the game, double-click `uninstall.bat`.

| Setting | FPS with 100 players nearby | Change |
|---|---|---|
| none | 39.3 | |
| `install-mild.bat` (`r.SkeletalMeshLODBias=1`) | 45.0 | +15% |
| `install.bat` (`r.SkeletalMeshLODBias=2`) | 57.3 | +46% |

Side effect: character models (including your own) are slightly simpler up close.

The installer edits one line in `%LOCALAPPDATA%\Hogwarts Legacy\ArcaneMP\Saved\Config\WindowsNoEditor\Engine.ini`
under `[SystemSettings]` and keeps a copy as `Engine.ini.before-crowdfix`. It refuses to run while the game is open.

Do **not** add `p.ClothPhysics=0`: it crashes the client on teleport.

## Settings on servers that lock the menu

ArcaneMP has its own settings, separate from the normal game, and some servers lock the in-game settings menu.
[settings-copy/](settings-copy/) copies the normal game's settings into ArcaneMP with one double-click, with
frame generation switched off, and can undo it. It ships in the same `arcanemp-crowd-fix.zip`
(`copy-settings.bat`, `restore-settings.bat`).

## Add-on test (CrowdFix, UE4SS)

**Unstable test build, not approved by ArcaneMP yet. Use at your own risk.**

The config fix above only helps the render thread. Outside a class the game also loads every player on the
server, including those hundreds of metres away. A separate add-on lowers the cost of those far players on
your PC only: nothing is sent to the server and nobody else sees a difference.

1. Download `arcanemp-crowdfix-addon-v3-unstable.zip` from the release
   [CrowdFix add-on v3 (unstable)](https://github.com/joaobzrra/arcanemp-crowd-fps/releases/tag/addon-v3-unstable)
   and unzip it anywhere.
2. Double-click `start-crowdfix.bat` (before or after starting the game) and pick a preset.
3. Start the game as usual. The window prints "CrowdFix loaded" about 30 s after the game opens.

To stop: close the game. Nothing stays installed. Run the `.bat` again while the game is open to switch preset.

| Preset | Players that sleep (not drawn, not animated) | Fewer animation updates beyond |
|---|---|---|
| 1 Ultra Performance | farther than 100 m | 10 m |
| 2 Performance | farther than 200 m | 15 m |
| 3 Balanced | nobody | 20 m |
| 4 Quality | nobody | 25 m |

In every preset, players farther than 50 m animate 5 times a second. Sleeping players wake up by themselves
when they come closer.

| Live server, 65-88 players loaded, almost all farther than 100 m | FPS | Change |
|---|---|---|
| Add-on off | 44-46 | |
| Performance (200 m) | 63 | +42% |
| Ultra Performance (100 m) | 74 (75 cap) | +61% |

Limits: one PC, one run per state. A crowd standing close to you (everybody within 30 m) is not helped.
All tests, numbers and visual verdicts: [addon-test/RESULTS-ADDON.md](addon-test/RESULTS-ADDON.md).

## Frame generation

ArcaneMP 1.15.1 turns frame generation off at every start. Every test run with it kept selected (NVIDIA
DLSS, AMD FSR 3, Intel XeSS and the driver-level NVIDIA Smooth Motion) fails, and the Direct3D 12 debug
layer names the call that removes the graphics device.
Results, errors, logs and crash report extracts: [frame-generation/](frame-generation/).

## For modders

Full data: [results/RESULTS.md](results/RESULTS.md). Posts sent to the mod team and a server staff:
[reports/](reports/).

### Method
- Local ArcaneMP 1.15.1 server; resource `test-harness/crowd-test` spawns N `Character`s
  (client side: `BP_RemoteAvatarCCC`, the same path as remote players) around one client on the Quidditch pitch.
- 60 s settle, then 120 s per crowd size. FPS = client-script 1 ms timer ticks per second
  (checked against the Steam overlay counter: 33 vs 36, 60 vs 60).
- Ryzen 9 5900XT, RTX 5060 Ti 16 GB, 1080p, DLSS Quality, ray tracing on, uncapped, Crowd detail = Medium.

### Results
| Nearby characters | 0 | 25 | 50 | 100 | 150 | 200 |
|---|---|---|---|---|---|---|
| FPS | 118.6 | 79.6 | 60.1 | 36.3 | 28.9 | 23.6 |
| GPU load | 90% | | | 48% | | 28% |

- About 0.17 ms of frame time per character. CPU-bound.
- Behaviour barely matters: walk, stand, sprint, cast with FX, sit, outfit churn, labels all within ±15% at 100
  (identical repeats: 36.3 / 38.6 / 38.4).
- Threads at 100 characters (% of one core): render 81.5, game 74.5, RHI 64.6.
  With `r.SkeletalMeshLODBias=2`: game 97.1, RHI 71.8, render 61.8. The game thread becomes the only limit.
- Limiting the game to 4 physical cores costs at most 26% (at 50 characters).
- The first spawn of a group causes one 290-330 ms frame.

### Config tested (ArcaneMP `Engine.ini`, `[SystemSettings]`)
| cvar | Result at 100 characters |
|---|---|
| `r.SkeletalMeshLODBias=2` | 39.3 → 57.3 FPS |
| `r.SkeletalMeshLODBias=1` | 45.0 FPS |
| `r.RayTracing.Geometry.SkeletalMeshes=0`, `r.EnableMorphTargets=0` | no gain on top of LOD bias 2 |
| `a.URO.Enable=1`, `a.URO.ForceAnimRate=4`, `a.URO.ForceInterpolation=1`, `a.ForceParallelAnimUpdate=1`, `p.ClothPhysics.WaitForParallelClothTask=0` | no gain (55.3 vs 56.3) |
| `p.ClothPhysics=0` | crash on teleport: `0xC0000005 at HogwartsLegacy.exe+0x29BB453`, read of 0x50, game thread (2/2) |

The ini is read: setting `PhoenixSigMgr.LOD.TriangleBudget=3000000` changes the mod's own startup log line to
`TriangleBudget 3000000 -> 4000000`.

### What only the mod can fix
1. Force LOD 2+ on remote players beyond the nearest N. Crowd detail already resolves `CustomizableCharacterComponent::SetForcedLOD`.
2. Reconsider raising `PhoenixSigMgr.LOD.TriangleBudget` from 2,000,000 to 4,000,000 at startup.
3. Reduce game-thread work for distant remote players: component tick interval, animation update rate
   (the URO cvars only affect components that opt in), cloth off.
4. Fix the cloth-off teleport crash.
5. Spread remote-player spawns over several frames.
6. Server option: per-player stream range or a cap on fully simulated nearby players.
7. Do not draw or animate remote players that are far away: outside a class the client fully builds players
   hundreds of metres away. Doing it from an add-on gave +42% to +61% FPS
   ([addon-test/RESULTS-ADDON.md](addon-test/RESULTS-ADDON.md), Test 14).
8. A crowd close by and on screen (about 95 players within 30 m, about 30 FPS): no player-side setting helps
   (Test 15 of the same file).

### Reproduce
- `test-harness/crowd-test`: server resource. Server console: `crowdrun <walk|walknamed|stand|players|churn|fxall|labels> [n,n,...]`, `crowdstop`.
  Results are logged as `PHASE END ... client timer ticks/s mean ...`.
- `test-harness/scripts/crowd-monitor.ps1`: CPU, per-thread load, GPU, memory every 5 s during a run.
- `test-harness/scripts/thread-probe.ps1`: names the busiest game threads (Windows thread descriptions).
- `test-harness/scripts/summarize-run.js`, `count-window.js`: summaries.

## Author
João Bezerra. MIT licence (see `LICENSE`).
