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

## Test 6: live public server (CHRONIX, 2026-11-23 20:40-20:50)
Busy event, ~70 players seated at tables, mostly within 25 m. Read-only watcher every 5 s; FPS from the
Steam overlay counter (crops every 15 s). LODBias=2 installed; frame cap 75. CrowdFix loaded at 20:43:31.
| Period | Players near / far (URO) | Game thread | Render | GPU | FPS (Steam) |
|---|---|---|---|---|---|
| no CrowdFix (n=33) | not counted | 89% | 75-80% | 39% | 45 |
| CrowdFix, Quality 25 m | 70 / 0-5 | 90% | 77-80% | 40% | 47, 47, 48 |
| CrowdFix, player moved away | 18-44 / 24-50 | 89% | 80-85% | 40-45% | 41, 45, 46, 46 |

- CrowdFix finds real players on a public server (`BP_RemoteAvatarCCC_C`, 71 found).
- No measurable FPS change in this scene. (An earlier reading, "seated players barely animate", is not supported:
  standing costs the same as walking, 36.0 vs 36.3 FPS in results/RESULTS.md. URO here touched only the body
  mesh, with ForceAnimRate 2, so it was a weak treatment; see "Review" below.)
- In a packed hub almost everyone is within 25 m. The loader now offers presets: 10 / 15 / 20 / 25 m.

Classroom A/B, 20:57-21:07, ~60 players, alternating presets every 150 s (camera moved once at 21:03):
| Block | Players near / far (URO) | Game thread | GPU | FPS (Steam, every 15 s) | Avg |
|---|---|---|---|---|---|
| A1 Quality 25 m | 57 / 0 | 94% | 46% | 43 47 50 48 44 45 45 46 46 45 | 45.9 |
| B1 Ultra 10 m | 52 / 7 | 90% | 44% | 45 46 45 46 45 47 47 47 48 | 46.2 |
| A2 Quality 25 m | 60 / 1 | 89% | 41% | 43 45 44 43 46 42 45 43 44 41 | 43.6 |
| B2 Ultra 10 m | 56 / 6 | 82% | 42% | 41 43 40 40 37 40 40 39 38 | 39.8 |

- Even at 10 m only 5-7 of ~60 players were throttled: in a classroom nearly everyone is within 10 m.
- No preset effect beyond noise; FPS drifted down over the 10 minutes in both presets (scene activity).
- Conclusion: a distance rule cannot help in rooms; the cost of nearby players has to be cut in the client.

Same classroom, 21:10-21:16, URO on almost everyone (distance 2 m), 120 s blocks:
| Block | Players near / far (URO) | Game thread | Render thread | GPU | FPS (Steam) | Avg |
|---|---|---|---|---|---|---|
| C1 2 m | 4 / 62 | 75% | 82% | 43% | 37 39 33 38 40 39 40 37 | 37.9 |
| A 25 m | 66 / 0 | 77% | 80% | 40% | 37 40 37 39 39 40 39 39 | 38.8 |
| C2 2 m | 4 / 62 | 74% | 80% | 39% | 39 39 39 38 35 33 37 | 37.1 |

- Throttling animation on 62 of 66 players changed nothing: in this scene the render thread (80-82%) is
  the busiest thread, not the game thread, and URO only removes game-thread animation work.
- Next lever to test is render-side: per-player shadow casting or draw cost for remote avatars.
- Memory: game working set 5.7 -> 7.3 GB when UE4SS loads; private bytes 15.55 -> 15.78 GB;
  system RAM in use 67-68% -> 70-72% (32 GB PC).

## Test 7: shadows and cloth per player (local, 100 standing, compact, LODBias=2)
URO distance 25 m in all phases (nobody throttled), so only shadows/cloth change. 120 s phases.
| Phase | Change | FPS | Worst frame p50 |
|---|---|---|---|
| P0 | none | 60.4 | 23 ms |
| P1 | `SetCastShadow(false)` on all 8 meshes of players beyond 5 m (71/100) | 62.5 | 30 ms |
| P2 | same on all 100 | 55.9 | 33 ms (one 2 s hitch) |
| P3 | game shadows lowest: `sg.ShadowQuality 0`, `sg.RaytracingShadowsQuality 0` | 58.6 | 31 ms |
| P4 | `SuspendClothingSimulation()` on all 8 meshes of all 100 (call succeeded) | 60.0 | 31 ms |
- Shadow switch verified: `shadow check: avatar has 8 meshes, first CastShadow now false`.
- Neither shadows nor cloth are a meaningful cost in this scene. Phase noise is about +-3 FPS.
- The add-on's 10 s mesh-mapping scan cost 17-25 ms per run (worse worst-frames in P1-P4); fixed afterwards.

## Test 8: realistic RP scene, 250 characters (local)
65 within 10 m (35 idle with wands/props, 12 seated clips, 9 pacing 2-3 m, 9 casting with FX every 10-25 s),
185 walking 30-100 m away. The local server streamed all 250 to the client (CHRONIX streamed at most 71).
| Phase | CrowdFix | FPS | Game thread | Render | RHI | GPU |
|---|---|---|---|---|---|---|
| P0 | off | 29.9 | 98% | 43% | 48% | 26% |
| P1 | URO beyond 25 m (184 throttled) | 29.7 | 97% | 43% | 48% | 25% |
| P2 | URO beyond 10 m | 28.7 | 97% | 44% | 47% | 23% |
| P3 | off | 28.7 | 97% | 44% | 49% | 24% |
- The game thread is saturated, and body-mesh URO (with ForceAnimRate 2 + interpolation) on 184 players
  changes nothing. This does NOT show that animation is cheap: the other 7 meshes per player were untouched,
  and in Tests 1-2 throttling all 8 meshes gave 40 -> 60-78 FPS. "184 throttled" counts players by distance;
  the property was not read back.

## Review (2026-11-23, three independent reviews of this file and the code)
Points all three agreed on, checked against the files:
- Test 8's "not animation" conclusion was too strong (see above).
- Render-side levers (shadows, ray-traced skeletal meshes) were tested only where the game thread limits FPS,
  so a render saving cannot show as FPS. The live classroom is render-thread heavy; retest there, and report
  CPU ms per frame per thread, not only FPS.
- No phase settles after respawning its crowd (one 60 s settle before the first phase only).
- Missing read-backs: CrowdFix counts players by distance, caches by actor address, and does not re-apply the
  URO cvars when `enabled` toggles; the scan in Test 7 ran only in P1/P2/P4.
- Untested and promising: the 7 follower meshes (do they use MasterPoseComponent, their own AnimInstance, a
  post-process AnimInstance?), the animation budget allocator (`a.Budget.*`, the body mesh is
  SkeletalMeshComponentBudgeted), `VisibilityBasedAnimTickOption`, bounds/kinematic-update flags, movement
  component and capsule overlaps, and a sampled CPU profile (Windows `wpr`) of the game thread by module.

## Result
Recipe: `r.SkeletalMeshLODBias=2` (Engine.ini) + URO on the remote body mesh beyond 25 m +
`a.URO.ForceInterpolation 1` + `a.URO.ForceAnimRate 2`. Nearby players are untouched.
For the mod team: the same can be done inside the client (opt remote avatars' body mesh into URO
beyond ~25 m with interpolation and a rate cap), with no add-on.

## Known limits
- `a.URO.ForceAnimRate 2` is global: game NPCs that already use URO also update every second frame.
- No untouched-game number for the spread crowd; the ~38-40 FPS baseline is from the compact crowd.
- Tested on one PC (Ryzen 9 5900XT, RTX 5060 Ti), on a local server and in two live sessions on one public
  server (Test 6); single runs per setting, phase noise about +-3 FPS.
- The 56.8 -> 61.1 "recipe" gain (Test 5) is a single run near the noise level and did not repeat in rooms.
- Not approved by ArcaneMP yet; it needs UE4SS loaded after the menu (late injection).

## Files
- `CrowdFix/`: the Lua mod (`Scripts/main.lua`, `settings.txt`).
- `start-crowdfix.bat`, `tools/start-crowdfix.ps1`: loader (waits for the game, loads UE4SS once).
- `LEIA-ME_README.txt`: player instructions (PT/EN).
- Release asset `arcanemp-crowdfix-addon-test.zip` = these files + UE4SS v4.0.0 (MIT licence).
