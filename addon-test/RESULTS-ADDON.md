# CrowdFix add-on tests (UE4SS)

Date: 2026-11-23. Same machine and method as [../results/RESULTS.md](../results/RESULTS.md):
local ArcaneMP 1.15.1 server, `test-harness/crowd-test` spawns 100 characters around one client,
120 s per phase, FPS = client probe (timer ticks/s), "worst frame" = median of the per-5 s worst frame.
Uncapped unless noted. Visual verdicts come from a person watching the screen live.

## Why an add-on
- With `r.SkeletalMeshLODBias=2` the render thread drops from 81% to 62% busy, but the game thread
  stays at 95-97% (thread probe), and no cvar lowers it: URO cvars only affect components that opt in,
  and ArcaneMP's remote characters do not.
- UE4SS can reach the remote characters through engine reflection without touching ArcaneMP code.

## Loading UE4SS next to ArcaneMP
| Method | Result |
|---|---|
| `dwmapi.dll` proxy next to `ArcaneMPLauncher.exe` | Fails. UE4SS starts before the launcher maps `HogwartsLegacy.exe` and scans the 6.4 MB launcher image: 475 failed signature scans. |
| Load `UE4SS.dll` after the main menu appears (late injection) | Works. `game executable: ...HogwartsLegacy.exe (383492096 bytes)`, `Found GUObjectArray`, Lua mods start. |

## What a remote player is
`BP_RemoteAvatarCCC_C` actor with 8 `SkeletalMeshComponent`s: Lower, Upper, Robe, Arms, Hair, Socks,
Shoes, and `CharacterMesh0` (head/body root, class `SkeletalMeshComponentBudgeted`). 5 LODs each.
100 players = 800 animated meshes.

## Test 1: what each lever does (compact crowd, all within ~14 m)
| Applied to remote players | FPS | Notes |
|---|---|---|
| nothing (UE4SS loaded) | 40.1 | UE4SS itself costs nothing measurable (39.3 without it) |
| `SetForcedLOD(3)` on all 8 meshes | 38.7 | no gain |
| + tick interval 0.1 s + URO on all 8 meshes | 78.0 | +95% |

## Test 2: bisect (compact crowd)
| Applied to all 8 meshes | FPS |
|---|---|
| tick interval 0.1 s only | 60.3 |
| URO only | 55.5 |
| both | 71.6 |

Visual (live): hair detaches from the body (each mesh ticks on its own schedule), and the walk looks
like ~20 FPS. Rejected.

## Test 3: body mesh only, distance tiers
Only the body mesh (`avatar.Mesh`) is changed; the other 7 meshes follow its pose, so nothing detaches.
| Run | FPS | Worst frame | Visual |
|---|---|---|---|
| tiers 5/10 m, URO + 15 Hz beyond 10 m (probe v3) | 48.5 | 49 ms | models fine |
| tiers 5/10 m, URO only (probe v3) | 47.3 | 51 ms | models "perfect", pacing bad |
| off, same session | 39.5 | 44 ms | |
| tiers 5/10 m, URO only (v4: batched, writes on change) | 49.7 | 33 ms | "no bugs whatsoever" |
| off, same session | 38.2 | 34 ms | |

Probe v3 re-applied settings to 800 meshes every 5 s in one frame, which caused a regular hitch.
v4 handles 10 players per 250 ms and writes only when a player changes tier: slowest step 2 ms.

## Test 4: stacked with the LOD config fix
| Run (LODBias=2 in Engine.ini) | FPS | Worst frame | Visual |
|---|---|---|---|
| compact crowd, add-on tiers 5/10 m | 67.0 | 24 ms | stutter on characters ~10 m away |
| compact crowd, LOD fix only | 54.0 | 28 ms | clean |

## Test 5: realistic spread and tuning (crowd 15-50 m)
| Run (LODBias=2 in Engine.ini) | FPS | Worst frame | Visual |
|---|---|---|---|
| LOD fix only | 56.8 | 27 ms | smooth, 57-60 FPS on screen |
| + add-on: URO beyond 25 m | 63.9 | 25 ms | farthest characters flicker |
| + `a.URO.ForceInterpolation 1` | 61.4 | 25 ms | slow stutter on the two farthest rings |
| + `a.URO.ForceAnimRate 2` | 61.1 | 26 ms | no visible stutter, stable 60 |

The two cvars were set live from Lua with `UKismetSystemLibrary::ExecuteConsoleCommand`.

## Result
Recipe: `r.SkeletalMeshLODBias=2` (Engine.ini) + URO on the remote body mesh beyond 25 m +
`a.URO.ForceInterpolation 1` + `a.URO.ForceAnimRate 2`. Nearby players are untouched.
For the mod team: the same can be done inside the client (opt remote avatars' body mesh into URO
beyond ~25 m with interpolation and a rate cap), with no add-on.

## Known limits
- `a.URO.ForceAnimRate 2` is global: game NPCs that already use URO also update every second frame.
- No untouched-game number for the spread crowd; the ~38-40 FPS baseline is from the compact crowd.
- Tested on one PC (Ryzen 9 5900XT, RTX 5060 Ti) and on a local server only, never on a public server.
- Not approved by ArcaneMP yet; it needs UE4SS loaded after the menu (late injection).

## Files
- `CrowdFix/`: the Lua mod (`Scripts/main.lua`, `settings.txt`).
- `start-crowdfix.bat`, `tools/start-crowdfix.ps1`: loader (waits for the game, loads UE4SS once).
- `LEIA-ME_README.txt`: player instructions (PT/EN).
- Release asset `arcanemp-crowdfix-addon-test.zip` = these files + UE4SS v4.0.0 (MIT licence).
