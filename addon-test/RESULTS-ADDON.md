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

## Test 9: ablation of one persistent crowd (local, 200 standing, compact, LODBias=2, 2026-11-23 23:20-00:00)
The experiment the review asked for. One cohort stays spawned for the whole run; a diagnostic UE4SS mod
(CrowdDiag) flips one switch at a time on every remote avatar, reads the state back, and each step is
15 s settle + 60 s measure with a baseline between or around the steps. Numbers are CPU ms per frame per
thread (thread CPU share x frame time), so they stay valid when the 75 FPS cap is reached.

What a remote avatar runs (read from the live objects): 8 skeletal meshes. Four tick every frame: the body
(CharacterMesh0: main AnimBP + post-process AnimBP), Hair (no master pose, no anim instance), Arms (master
pose = body, plus a post-process AnimBP) and Robe (no master pose, its own AnimBP). Upper, Lower, Socks and
Shoes follow the body's pose and do not tick. Every mesh has VisibilityBasedAnimTickOption = 0 (always tick
the pose and refresh bones, on screen or not) and update-rate optimisation off.

| Step (read back on all 200 avatars) | FPS | Game thread | Render | RHI |
|---|---|---|---|---|
| Baseline (11 runs) | 36.1-40.9 | 21.4-23.3 ms | 17.0-21.2 ms | 19.9-22.2 ms |
| Tick off: Hair + Arms + Robe (600 meshes) | 49.1 | 16.1 | 14.7 | 16.5 |
| Tick off: body (200 meshes) | 58.8 | 16.4 | 10.3 | 11.4 |
| Tick off: all 8 meshes | 75 (cap) | 10.9 | 4.4 | 6.8 |
| bNoSkeletonUpdate on all 8 | 75 (cap) | 11.3 | 6.0 | 7.8 |
| Tick off: all 8 + actor + movement, capsule overlaps off | 75 (cap) | 7.1 | 6.5 | 7.5 |
| Actor tick off only | 37.9 | 22.1 | 19.2 | 21.7 |
| Movement component tick off only | 38.7 | 21.5 | 18.9 | 20.9 |
| Ability + managed-character component ticks off | 38.2 | 22.3 | 19.0 | 21.5 |
| Capsule overlap events off only | 37.7 | 22.8 | 20.0 | 21.7 |
| URO on all 8, ForceAnimRate 2, interpolation on | 40.3 | 19.4 | 18.6 | 20.2 |
| VisibilityBasedAnimTickOption = 1 (tick pose, refresh bones only when rendered) | 50.6 | 19.1 | 8.0 | 10.0 |
| VisibilityBasedAnimTickOption = 3 (tick pose only when rendered), two runs; fails visually, see below | 58.8 / 63.9 | 15.8 / 15.0 | 12.5 / 10.6 | 12.6 / 11.7 |
| Option 3 + URO on all 8, ForceAnimRate 2, interpolation off | 70.2 | 13.5 | 8.8 | 9.8 |
| Option 3 + capsule overlaps off | 66.0 | 14.5 | 10.1 | 11.2 |

- The per-frame pose update of the four ticking meshes is about half of the game thread (-10.7 ms of 21.4)
  and about three quarters of the render and RHI threads (-13.3 and -13.4 ms). A character whose pose is not
  updated is cheap to draw. This corrects Test 8's reading: animation is the main per-player cost.
- Tick off and bNoSkeletonUpdate give the same result, so the cost is the skeleton update itself.
- Option 3 (off-screen characters skip the pose update) gave +52% and +66% FPS in the two runs, but it FAILS
  the visual check: with it set on all 8 meshes, characters in plain view have displaced clothes and wrong
  faces for as long as it is on (tester's report and a steady-camera screenshot), and they return to normal
  within seconds of restoring option 0. A per-mesh read showed all 8 meshes of every avatar agreeing on
  "recently rendered", so the cause is not known. Part of the gain therefore comes from visible meshes not
  updating: the number overstates a correct implementation, and the property flip is not usable as is.
- Half-rate updates with interpolation save little, because interpolation still refreshes bones every frame.
- Actor tick, movement, the two extra components and capsule overlaps cost nothing measurable on their own.
  The extra 3.8 ms of the combined step is unexplained.
- Visual: with only Hair + Arms + Robe ticks off, clothes separate from the body up close; the tester found
  it acceptable at 30-40 m.
- Not a clean test, excluded: hiding all meshes (game and render thread got slower while RHI fell to 9.6 ms).
- Limits: one compact standing crowd; 75 FPS cap reached in three steps; the tester could move the camera
  during the run; no CPU sampling by module yet.

## Test 10: the classroom of Test 6, rebuilt locally (2026-11-24 00:15-00:28)
Same room and seat as the live classroom blocks of Test 6, same camera angle (placed by the tester), 65
scripted characters filling the benches in front of and around the seat (35 idle, 12 seated clips, 9 pacing,
9 casting). These bodies have 324 skeletal meshes in total, 184 of them ticking. LODBias=2, cap 75.

| Step | FPS | Game thread | Render | RHI |
|---|---|---|---|---|
| Empty room | 75 (cap) | 5.6 ms | 2.7 ms | 5.4 ms |
| 65 characters, baseline (2 runs) | 73.3 / 74.3 | 10.0 / 10.8 | 8.9 / 6.7 | 10.4 / 9.9 |
| Tick off: all meshes | 75 (cap) | 7.6 | 6.3 | 7.6 |
| URO on all meshes, ForceAnimRate 2, interpolation off | 74.9 | 9.1 | 7.1 | 8.7 |
| URO on all meshes, ForceAnimRate 2, interpolation on | 75 (cap) | 10.1 | 6.3 | 9.6 |

- 65 scripted characters add about 4.4-5.2 ms of game thread and 4-6 ms of render thread to the empty room,
  and the scene stays at the frame cap. The live lesson in this room (Test 6, 60-66 real players) ran at
  37-46 FPS with the game thread at 75-94% and the render thread at 80-82% of a 22-27 ms frame. A real player
  therefore costs roughly three times a scripted character on both threads. The local harness does not
  reproduce the live load, and what a real player carries beyond these bodies has not been identified.
- Animation is still about half of the scripted characters' game-thread cost here (-2.4 to -3.2 ms with all
  mesh ticks off). Half-rate URO saves 1-2 ms without interpolation and nothing measurable with it.
- Limits: the two baselines differ by 2 ms on the render thread (pacing and casting characters, and the
  on-screen count moved between 46 and 65); differences under about 1 ms are not meaningful. The comparison
  with Test 6 is across two client installs and two sessions a few hours apart.

## Test 11: what real players are made of, and a CPU sampling trace (live, 2026-11-24 00:45-01:06)
Read-only: a Lua inventory (`probe/crowddiag-inventory-ro.lua`, `probe/crowddiag-scripts/inventory_world_ro.lua`) plus a 63.5 s
`wpr -start CPU` trace of the tester's own client on the public server. Nothing in the game was changed.

- With 71-76 remote players loaded, 70 of them more than 50 m from the tester's character and 0-2 on screen:
  38-39 FPS, game thread 95% (24-25 ms per frame), render thread 81% (21 ms), RHI 63% (16.5 ms), GPU 36-39%.
- A later scan with finer buckets (24 players): 6 within 25 m, 1 at 50-100 m, 2 at 100-200 m, 13 at 200-500 m,
  2 beyond 500 m. Players hundreds of metres away are fully built and update every frame.
- A real player (mean of 72 with a body): 8.2 skeletal meshes, 3.6 of them ticking, about 970 bones,
  18.8 materials; 219 distinct mesh assets across the crowd. The scripted mix of Test 10: 5.0 meshes, 2.8
  ticking, 525 bones, 23 assets.
- Levels of detail (`probe/crowddiag-scripts/lod_scan_ro.lua`, 23 players): of 226 skeletal mesh components on players,
  141 have 5 LODs and 85 have ONE. Of the 107 that tick, 54 have 5 and 53 have one; the one-LOD meshes hold 48%
  of the bones. The one-LOD assets are player-installed cosmetics (custom heads, hair, accessories). A one-LOD
  mesh cannot drop detail with distance and `r.SkeletalMeshLODBias` has no effect on it.
- Trace (mean 33.6 FPS, 57 players loaded): the game thread used 97% of one core. Where the CPU was: the game's
  own code 77%, Windows kernel 10%, the multiplayer client's own code 5%. The game-code time is flat: half of it
  is spread over 97 functions. Render thread: 86% game code. RHI thread: 46% game code, 28% GPU driver.
  Limits: the launcher maps the game image in a way that defeats Windows stack walking, so only "where the CPU
  was" is known, not "who asked for it"; and the trace itself cost about 15% of the frame rate, so the shares
  are the result, not the absolute milliseconds.

## Test 12: switching per-player updates off on real players (live, 2026-11-24 02:05-02:32)
The diagnostic mod on the tester's own client, public server, 19-36 remote players loaded and drifting.
Client-local switches only (other players freeze on the tester's screen, nobody else is affected), every step
followed by a restore and a new baseline. 10 s settle + 40 s measure; FPS from the engine frame counter; ms =
thread CPU per frame. Delta = step minus the mean of the two baselines around it.

| Step | Players | FPS | Delta game | Delta render | Delta RHI |
|---|---|---|---|---|---|
| Baselines, round 1 | 19-25 | 58-67 | | | |
| Mesh ticks off, all players | 22 | 72.5 | -1.5 | -3.2 | -2.5 |
| Mesh ticks off, players beyond 50 m only | 21 | 70.4 | -0.85 | -2.5 | -1.5 |
| Mesh ticks off, one-LOD meshes only (34 meshes; 18 of 20 body meshes) | 20 | 72.2 | -0.6 | -2.0 | -1.3 |
| Mesh ticks off, five-LOD meshes only (46 meshes) | 20 | 66.4 | -1.2 | -0.55 | -0.4 |
| Wand and mount mesh ticks off (22 meshes) | 20 | 61.7 | inside baseline drift | | |
| Baselines, round 2 | 30-36 | 52-56 | | | |
| Players beyond 50 m: mesh tick interval 0.2 s (138 meshes) | 35 | 63.4 | -2.2 | -5.2 | -3.2 |
| Players beyond 100 m: mesh ticks off (229 meshes) | 34 | 66.6 | -3.0 | -4.5 | -3.3 |
| Every per-player tick off (meshes, actor, movement, ability, managed, facial, overlap, wands) | 33 | 73.6 | -5.1 | -6.6 | -4.0 |
| Baselines, round 3 | 20-33 | 51-67 | | | |
| Mesh ticks off, all players | 26 | 71.4 | -1.0 | -4.1 | -2.3 |
| Non-mesh ticks off (actor, movement, ability, managed, facial, overlap) | 20 | 70.1 | -1.4 | -1.3 | -0.4 |
| Actor tick off | 24 | 65.8 | none | none | none |
| Ability + managed character + facial ticks off | 33 | 52.1 | none | none | none |

- The per-player cost is per-player updates. With every one of them off, 33 players cost 5.1 ms of game thread,
  6.6 ms of render thread and 4.0 ms of RHI less: about 0.155 / 0.20 / 0.12 ms per player per frame.
- Mesh updates are the render and RHI cost. On the game thread they share the cost with the non-mesh group;
  actor, ability, managed-character and facial ticks show nothing, which leaves the movement component (its own
  step was spoiled by a scene change and is not reported).
- Players beyond 50 m carry most of the mesh cost, and they are not visible as individuals at that distance.
  Updating their meshes 5 times a second instead of every frame recovers nearly as much as stopping them.
- One-LOD meshes: switching them off gives nearly the whole render saving, the five-LOD meshes give little. Not
  separated yet from the fact that most of them are the body mesh, which also drives the master-pose followers.
- Limits: one measurement per step; the crowd changed between steps (the Players column is the count at each
  step); game-thread deltas for the same switch varied between 1 and 3 ms across rounds. The client had an
  experimental UI change applied during this test and Test 13 (lower UI frame rate), not during Test 11.

## Test 13: CrowdFix with the far-player interval (live, 2026-11-24 02:33-02:37)
New settings: `fardistance=5000` (cm) and `farinterval=0.2` (s). Every ticking skeletal mesh of a player beyond
`fardistance` gets that component tick interval; it is put back when the player comes closer or the mod is
switched off. Same session as Test 12, 30-38 players, 15 s settle + 40 s measure.

| State | FPS | Game | Render | RHI | Read-back |
|---|---|---|---|---|---|
| Off | 54.2 | 16.42 | 17.60 | 14.06 | |
| Far interval only (URO distance out of range) | 58.4 | 15.41 | 15.27 | 12.57 | 23 players slowed |
| Off | 56.1 | 15.87 | 16.64 | 13.98 | |
| Shipped defaults (URO beyond 25 m + far interval beyond 50 m) | 66.1 | 12.98 | 12.86 | 11.66 | 27 on URO, 26 slowed |
| Off | 58.6 | 14.73 | 15.76 | 13.56 | |

- Shipped defaults: +8.8 FPS (+15%), game -2.3 ms, render -3.3 ms, RHI -2.1 ms. Far interval alone: +3.3 FPS
  with 23 far players (Test 12 measured +10.6 FPS when 34 were far): the gain follows the number of far players.
- The mod logged no errors and read the interval back from the game (0.20 s).
- Limits: one measurement per state, on one PC, with at most 38 players loaded; not yet repeated in a full
  server. The visual effect on far players was accepted by the tester without a line of sight to them.

## Test 14: CrowdFix v3, sleep beyond a distance (local and live, 2026-11-24 19:44-21:02)
Outside a class the client loads the whole server: on a roof with 2 players on screen, 77 of 82 loaded avatars
were farther than 100 m. New setting `sleepdistance` (cm, 0 = off). A player beyond it is put to sleep on this PC
only: every skeletal mesh of the avatar, of what it holds (wand) and of its mount is hidden with
`SetHiddenInGame(true, false)`, and the ticks of those meshes, of the movement, ability, managed-character and
facial components and of the actor are switched off. The mod restores only what it changed, when the player comes
inside 90% of the distance, when the mod is switched off, or when the player despawns. A sleeping avatar's position
still follows the real player, so waking by distance works. Presets in the loader: Ultra Performance (sleep beyond
100 m, URO beyond 10 m), Performance (200 m, 15 m), Balanced and Quality (nobody sleeps).

Also changed in v3:
- Timer: `LoopInGameThreadWithDelay` instead of `LoopAsync` (kept as a fallback). A game crash with two copies of
  the script loaded in one game was traced to this. Read in the UE4SS v4.0.0 source (`LuaMod.cpp`): `LoopAsync`
  callbacks run on the mod's own thread, on a Lua thread of the same Lua state the mod's other callbacks use.
  That this caused the crash is inferred, not proven.
- The map of meshes per player is built a little per step (2 ms budget per 250 ms step, one class per step).
  The earlier build walked every skeletal mesh in one callback: up to 31 ms measured live.
- Hiding per mesh: `SetActorHiddenInGame(true)` succeeds on these avatars but `bHidden` reads false before and
  after; per mesh, `bHiddenInGame` and `IsVisible()` read back.
- After a player leaves, the client keeps the avatar as an empty shell until the next garbage collection (about
  30 s): parked at the world origin, actor tick off, body mesh still valid but no longer owned by the avatar
  (`probe/crowddiag-scripts/shell_probe.lua`). v3 does not count or handle shells. Player counts in the status
  lines of earlier tests, and their ">500 m" group, included shells.
- Offline test against a fake engine: `tests/crowdfix_mock_test.lua`, 25 checks, both timer modes.

Local server, 100 scripted players at 1-104 m, one copy of the mod, read back from outside the mod
(`probe/crowddiag-scripts/sleep_readback_ro.lua`, driver `test-harness/scripts/local-sleep-states.ps1`):

| State | Asleep (mod) | Read-back | FPS (5 s samples, cap 75) |
|---|---|---|---|
| Off | 0 | `hidden=0 actorTickOff=0 meshesTicking=381` | 45-55 |
| Sleep beyond 50 m | 25 | `hidden=26 ... hidden inside 90%=0, visible beyond=0`, `meshesTicking=290` | 62-66 |
| Sleep beyond 10 m (run before the shell change) | 75 | `hidden=75 ... hidden inside 90%=0, visible beyond=0`, `meshesTicking=92` | 71-75 |
| Off | 0 | `hidden=0 actorTickOff=0 meshesTicking=381`, `intervals: 0.000s=381` | 46-58 |

- Slowest mod step 3-8 ms in every state, 10 ms while players were recreated (440 and 590 recreates in two
  runs). No error line. Screenshots with the 10 m limit: no leftover shadow, wand or frozen body.

Live (CHRONIX), roof of a house, 65-88 players loaded, 1-3 on screen, 15 s settle + 40 s measure, frame cap 75
(driver `test-harness/scripts/live-crowdfix-v3-ab.ps1`). CPU ms per frame:

| State | FPS | Game | Render | RHI | Read-back |
|---|---|---|---|---|---|
| Off | 41.1 | 23.30 | 20.44 | 16.98 | |
| Performance (sleep beyond 200 m) | 63.1 | 15.22 | 9.79 | 9.81 | 21 asleep, 63 slowed |
| Off | 47.7 | 19.83 | 18.03 | 14.63 | |
| Ultra Performance (sleep beyond 100 m) | 74.0 | 12.44 | 8.18 | 8.92 | 64 asleep |
| Off | 44.2 | 21.23 | 18.50 | 15.33 | |

- Against the baselines on both sides: Performance +18.7 FPS (+42%), game -6.3 ms, render -9.4 ms, RHI -6.0 ms.
  Ultra Performance +28 FPS (+61%, at the cap), game -8.1 ms, render -10.1 ms, RHI -6.1 ms.
- Slowest mod step 3-7 ms. No error line. The client built 15-23 player bodies per step in every state, on or
  off: sleeping does not make it rebuild players.
- After the run: `hidden=0`, `intervals: 0.000s=317`, body ticking on all 66 players that had a body.
- Visual: the tester noticed no difference during either preset, and saw one far player (estimated 50-100 m)
  running with no animation. Cause not determined: the 0.2 s interval beyond 50 m, or a sleeping player whose
  clothes the client re-applied (new meshes of a sleeping player stay visible until the next map, up to about 13 s).
- Limits: one run per state on one PC; a sleeping player on a broom was only tested offline; the loader (`.bat`)
  was not yet run with this build when this was written.

## Test 15: a crowd close by and on screen (live, 2026-11-24 21:11-21:17)
A dinner: 92-98 players loaded, 55-66 on screen, all within 30 m. 12 s settle + 40 s measure
(driver `test-harness/scripts/live-settings-ab.ps1`). CPU ms per frame:

| State | FPS | Game | Render | RHI | Read-back |
|---|---|---|---|---|---|
| Off | 29.7 | 23.99 | 26.62 | 23.31 | |
| 0.05 s mesh tick interval beyond 3 m | 30.4 | 25.11 | 27.49 | 23.14 | 87 players slowed |
| Off | 29.0 | 23.96 | 27.24 | 23.88 | |
| No shadows beyond 5 m (`SetCastShadow(false)`) | 31.3 | 22.58 | 24.06 | 20.51 | 75 players |
| Off | 31.6 | 23.25 | 25.60 | 21.70 | |

- The interval gave no gain. It was applied and stayed applied: read back every 8 s for 40 s, 404 of 434 ticking
  avatar meshes at 0.050 s (`probe/crowddiag-scripts/interval_readback_ro.lua`), FPS 30-34. Not explained.
- No shadows: about -2.4 ms render, -2.3 ms RHI, +1 FPS, inside the drift between the baselines.
- No thread is saturated in this state (game 69-76%, render 75-86%, GPU 32-38%).
- Conclusion: the add-on's distance steps do not reach a crowd that stands this close. No player-side setting
  was found for it; it needs work inside the client.

## Result
Recipe: `r.SkeletalMeshLODBias=2` (Engine.ini) + URO on the remote body mesh beyond 25 m +
`a.URO.ForceInterpolation 1` + `a.URO.ForceAnimRate 2` + a 0.2 s mesh tick interval for players beyond 50 m +
sleep (hidden, no ticks) for players beyond 100 m or 200 m (Test 14).
Nearby players are untouched.
For the mod team: the same can be done inside the client with no add-on. The larger fix is on the same line:
remote players that are far away or not visible should not be animated every frame (Tests 11-13), and players
hundreds of metres away are currently fully built.

## Known limits
- `a.URO.ForceAnimRate 2` is global: game NPCs that already use URO also update every second frame.
- No untouched-game number for the spread crowd; the ~38-40 FPS baseline is from the compact crowd.
- Tested on one PC (Ryzen 9 5900XT, RTX 5060 Ti), on a local server and in two live sessions on one public
  server (Test 6); single runs per setting, phase noise about +-3 FPS.
- The 56.8 -> 61.1 "recipe" gain (Test 5) is a single run near the noise level and did not repeat in rooms.
- Not an official ArcaneMP feature; it needs UE4SS loaded after the menu (late injection).
- Only one copy of the mod may run in a game: loading a second copy of the script into a running game crashed it.
- A crowd close by and on screen is not helped (Test 15).
- "A real player costs three times a scripted one" (Test 10) is not established: the scripted figure came from
  a mixed cohort and the live figure from two different places. Test 12 measures the live per-player cost directly.

## Files
- `CrowdFix/`: the Lua mod (`Scripts/main.lua`, `settings.txt`).
- `start-crowdfix.bat`, `tools/start-crowdfix.ps1`: loader (waits for the game, loads UE4SS once).
- `LEIA-ME_README.txt`: player instructions (PT/EN).
- `probe/crowddiag-main.lua`: the diagnostic mod of Tests 9-10 (switches with read-back; test client only).
  `probe/crowddiag-rendered.lua`, `probe/crowddiag-where.lua`: helper reads it runs with its `lua` command.
  `probe/crowddiag-inventory-ro.lua`: read-only inventory of what a remote avatar is made of.
- `../test-harness/scripts/ablate.ps1`: the step driver of Tests 9-10 (commands, settle, FPS and thread CPU).
- `probe/crowddiag-scripts/`: scripts the diagnostic mod runs with its `lua` command, under the file names they
  need in its `Scripts` folder. `inventory_world_ro.lua`, `lod_names_ro.lua`, `lod_scan_ro.lua`: the read-only
  scans of Test 11. `ticklod*.lua`, `farint*.lua`: the per-LOD and far-interval switches of Test 12.
- `probe/crowdinv-main.lua`: the read-only mod of Test 11 (runs the two inventories on request and prints the
  frame counter every 5 s, which the live drivers read).
- `../test-harness/scripts/live-ablate.ps1`: the step driver of Test 12 (no local server needed; FPS from the
  frame counter the scan mod prints). `../test-harness/scripts/live-crowdfix-ab.ps1`: the on/off run of Test 13.
- `tests/crowdfix_mock_test.lua`: offline test of the mod against a fake engine (Lua 5.4):
  `lua tests/crowdfix_mock_test.lua CrowdFix/Scripts/main.lua <empty scratch folder> [async]`.
- `../test-harness/scripts/local-sleep-states.ps1`, `live-crowdfix-v3-ab.ps1`: the local state check and the live
  preset run of Test 14. `live-settings-ab.ps1`: the off / setting / off run of Test 15.
- `probe/crowddiag-scripts/sleep_readback_ro.lua`, `shell_probe.lua`, `interval_readback_ro.lua`: the read-only
  read-backs of Tests 14-15.
- Not in the repository: the trace reader used for Test 11's sampling numbers.
- Release asset `arcanemp-crowdfix-addon-test.zip` = these files + UE4SS v4.0.0 (MIT licence).
