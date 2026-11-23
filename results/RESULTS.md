# ArcaneMP crowd-size client performance tests

Date: 2026-11-23 (GMT-3). Build: ArcaneMP 1.15.1, 118 CurseForge cosmetic mods required by the test server.

Hardware: Ryzen 9 5900XT (16C/32T), RTX 5060 Ti 16 GB, 32 GB RAM, 1920x1080, DLSS Quality, ray tracing on.

## Method

A local test server spawned N server-side "Characters" (same body as remote players) in a ring around one real player on the Quidditch pitch (323482,-465966,-85353.9). A run teleports the player there, settles 60 s, then holds each crowd size for one 120 s "phase". The probe is a client script timer: ticks/s is the FPS figure, sampled over the phase (n=24 samples, 5 s each); "worst gap" is the longest gap between ticks in a sample (ms), reported as p50/p90/max over the samples. The probe was validated against the Steam overlay FPS counter: probe 33 vs overlay 36 at 13:49:13-15, and probe 59-60 vs overlay 60 at 14:14. CPU/GPU come from a separate monitor sampling every 5 s (n = number of monitor samples in that phase; low n = weak figure). Process CPU: 100 = one core. Walk mode = characters walk; other modes are named in each section.

Run settings: Run 1 = in-game Framerate 60 + VSync ON (capped at 60 FPS). Runs 2 onward = VSync OFF, Framerate 360, Frame Generation Off.

## Run 1: walk, capped at 60 FPS (13:43-13:57)

| Crowd | FPS mean | p10 | Worst frame p50/p90/max ms | Proc CPU % | GPU % | GPU W | Private GB | n |
|---|---|---|---|---|---|---|---|---|
| 0 | 60.0 | 60 | 18/19/32 | 227 | 37 | 81 | 16.97 | 12 |
| 25 | 59.8 | 60 | 19/24/333 | 407 | 51 | 88 | 17.26 | 11 |
| 50 | 58.4 | 57 | 22/25/30 | 613 | 56 | 93 | 17.49 | 11 |
| 100 | 37.6 | 35 | 34/42/51 | 588 | 37 | 69 | 18.05 | 11 |
| 150 | 27.3 | 24 | 51/63/70 | 571 | 34 | 59 | 18.63 | 12 |
| 200 | 22.8 | 22 | 73/87/96 | 584 | 26 | 49 | 19.53 | 11 |
| 0 (end) | 59.3 | 60 | 18/24/102 | 208 | 43 | 86 | 17.39 | 12 |

## Run 2: walk, uncapped (14:09-14:23)

| Crowd | FPS mean | p10 | Worst frame p50/p90/max ms | Proc CPU % | GPU % | GPU W | Private GB | n |
|---|---|---|---|---|---|---|---|---|
| 0 | 118.6 | 109 | 13/14/18 | 475 | 90 | 141 | 16.62 | 12 |
| 25 | 79.6 | 78 | 18/21/292 | 610 | 81 | 119 | 16.99 | 11 |
| 50 | 60.1 | 59 | 22/25/26 | 569 | 63 | 94 | 17.27 | 12 |
| 100 | 36.3 | 34 | 35/39/44 | 584 | 48 | 77 | 17.80 | 11 |
| 150 | 28.9 | 28 | 58/66/78 | 619 | 38 | 68 | 18.66 | 12 |
| 200 | 23.6 | 22 | 77/89/96 | 603 | 28 | 49 | 19.35 | 11 |
| 0 (end) | 126.3 | 124 | 13/15/121 | 415 | 81 | 136 | 17.19 | 12 |

## Run 3: walk, uncapped, game limited to 4 physical cores (14:24-14:38, affinity 0x55)

| Crowd | FPS mean | p10 | Worst frame p50/p90/max ms | Proc CPU % | GPU % | GPU W | Private GB | n |
|---|---|---|---|---|---|---|---|---|
| 0 | 113.1 | 108 | 13/15/21 | 252 | 71 | 120 | 17.15 | 12 |
| 25 | 80.2 | 67 | 18/21/33 | 311 | 57 | 94 | 17.38 | 12 |
| 50 | 44.5 | 43 | 27/34/38 | 293 | 43 | 76 | 17.67 | 11 |
| 100 | 33.2 | 32 | 38/44/49 | 321 | 34 | 62 | 18.25 | 12 |
| 150 | 27.2 | 26 | 58/68/82 | 336 | 30 | 54 | 18.94 | 12 |
| 200 | 21.5 | 20 | 78/88/90 | 327 | 26 | 45 | 19.67 | 11 |
| 0 (end) | 94.3 | 87 | 14/22/120 | 263 | 67 | 111 | 17.36 | 12 |

## Run 4a: players mode (14:39-14:50)

Characters act like players: runs, spell casts, effects, sits. Action counts are per phase.

| Crowd | FPS mean | p10 | Worst frame p50/p90/max ms | Proc CPU % | GPU % | GPU W | Private GB | n | Actions (runs/casts/fx/sits) |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 115.0 | 111 | 13/14/16 | 431 | 75 | 128 | 17.30 | 12 | 0/0/0/0 |
| 50 | 68.0 | 62 | 22/38/47 | 587 | 68 | 113 | 18.82 | 11 | 617/270/270/237 |
| 100 | 41.2 | 37 | 31/37/43 | 557 | 46 | 85 | 19.56 | 7 | 1280/562/562/434 |
| 200 | 24.0 | 22 | 67/75/89 | 558 | 36 | 61 | 21.01 | 2 | 2528/1148/1148/854 |
| 0 (end) | 108.1 | 109 | 14/17/99 | 431 | 96 | 148 | 18.14 | 12 | 0/0/0/0 |

## Single-phase runs at 100 characters

| Run | Mode | Window | FPS mean | p10 | Worst frame p50/p90/max ms | Proc CPU % | GPU % | GPU W | Private GB | n | Actions (runs/casts/fx/sits/recreates) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 4b | churn | 14:51-14:53 | 36.8 | 33 | 36/45/52 | 528 | 49 | 78 | 19.26 | 2 | 1252/559/559/463/690 |
| 4c | fxall | 14:54-14:56 | 39.9 | 37 | 33/40/43 | 590 | 38 | 76 | 19.52 | 9 | 1278/493/493/477/0 |
| 4d | labels | 14:57-14:59 | 42.8 | 40 | 31/36/39 | 575 | 41 | 79 | 19.51 | 6 | 1202/608/608/464/0 |

## Outfit test: walknamed (15:01-15:07)

Walk mode, characters wear game NPC outfits (named) instead of modded outfits. No player actions.

| Crowd | FPS mean | p10 | Worst frame p50/p90/max ms | Proc CPU % | GPU % | GPU W | Private GB | n |
|---|---|---|---|---|---|---|---|---|
| 50 | 55.4 | 50 | 23/26/27 | 413 | 42 | 81 | 18.27 | 12 |
| 100 | 32.0 | 28 | 37/43/50 | 409 | 34 | 62 | 18.69 | 11 |
| 200 | 35.5 | 34 | 39/44/53 | 515 | 34 | 74 | 18.99 | 12 |

## Stand test (15:08-15:11)

Characters stand still at 100.

| Crowd | FPS mean | p10 | Worst frame p50/p90/max ms | Proc CPU % | GPU % | GPU W | Private GB | n |
|---|---|---|---|---|---|---|---|---|
| 100 | 36.0 | 34 | 37/40/45 | 539 | 38 | 71 | 18.50 | 11 |

## Comparison at 100 characters

| Test | FPS mean | p10 | Worst frame p50/p90/max ms | Proc CPU % | GPU % | GPU W | Private GB | n |
|---|---|---|---|---|---|---|---|---|
| Run 1 walk (capped 60) | 37.6 | 35 | 34/42/51 | 588 | 37 | 69 | 18.05 | 11 |
| Run 2 walk | 36.3 | 34 | 35/39/44 | 584 | 48 | 77 | 17.80 | 11 |
| Run 3 walk, 4 cores | 33.2 | 32 | 38/44/49 | 321 | 34 | 62 | 18.25 | 12 |
| 4a players | 41.2 | 37 | 31/37/43 | 557 | 46 | 85 | 19.56 | 7 |
| 4b churn | 36.8 | 33 | 36/45/52 | 528 | 49 | 78 | 19.26 | 2 |
| 4c fxall | 39.9 | 37 | 33/40/43 | 590 | 38 | 76 | 19.52 | 9 |
| 4d labels | 42.8 | 40 | 31/36/39 | 575 | 41 | 79 | 19.51 | 6 |
| walknamed | 32.0 | 28 | 37/43/50 | 409 | 34 | 62 | 18.69 | 11 |
| stand | 36.0 | 34 | 37/40/45 | 539 | 38 | 71 | 18.50 | 11 |

## Client log activity: 4a@100 vs 4b churn@100

`count-window.js` over `ArcaneMP.log`, 118 s windows.

| Window | Log lines | SpawnCccProxy | LoadLookFromArrays | Cloth rebuild |
|---|---|---|---|---|
| 4a@100 (14:43:46-14:45:44) | 925 | 40 | 20 | 50 |
| 4b churn (14:51:15-14:53:13) | 9379 | 747 | 373 | 666 |

## Frame time and per-character cost (run 2)

Frame time = 1000 / FPS mean.

| Crowd | FPS mean | Frame time ms | Delta vs 0 ms | ms per character vs 0 |
|---|---|---|---|---|
| 0 | 118.6 | 8.43 | 0 | - |
| 25 | 79.6 | 12.56 | 4.13 | 0.165 |
| 50 | 60.1 | 16.64 | 8.21 | 0.164 |
| 100 | 36.3 | 27.55 | 19.12 | 0.191 |
| 150 | 28.9 | 34.60 | 26.17 | 0.174 |
| 200 | 23.6 | 42.37 | 33.94 | 0.170 |

Overall slope: (42.37 - 8.43) ms / 200 characters = 0.170 ms per character. Between steps: 0-25 = 0.165, 25-50 = 0.163, 50-100 = 0.218, 100-150 = 0.141, 150-200 = 0.155 ms per character. The end-of-run 0 phase (126.3 FPS = 7.92 ms) is 0.5 ms below the starting 0 phase.

## Observations

- FPS falls with crowd size in every walk run: run 2 goes 118.6 (0) to 36.3 (100) to 23.6 (200).
- Cost is close to linear: about 0.17 ms of frame time per character (run 2, arithmetic above).
- GPU load falls as crowd grows (run 2: 90% at 0, 48% at 100, 28% at 200) while process CPU stays about 570-620% from 25 characters up. Inferred: the client is CPU-bound, not GPU-bound, at these crowd sizes.
- Run 1 (capped 60) holds 58.4 at 50 and falls to 37.6 at 100; at 100 and above it matches the uncapped run 2 within 1.3 FPS (37.6 vs 36.3, 27.3 vs 28.9, 22.8 vs 23.6).
- Run 3 (4 cores) process CPU is 252-336% against 415-619% in run 2, and FPS is lower at every size from 25 up: 44.5 vs 60.1 at 50 (-26%), 33.2 vs 36.3 at 100 (-9%), 27.2 vs 28.9 at 150, 21.5 vs 23.6 at 200. Largest loss is at 50. Inferred: the main cost sits mostly on a few threads (busiest-thread % is 61-70 in run 3 and 73-85 in run 2 at 25-100).
- First appearance of a crowd causes one long frame: worst-gap max 292 ms (run 2, 25), 333 ms (run 1, 25). Later phases and run 3 show max 33-96 ms.
- The 4b churn window shows 747 SpawnCccProxy and 666 cloth rebuilds in 118 s against 40 and 50 in 4a@100. FPS 36.8 vs 41.2, worst frame max 52 vs 43 ms (churn n=2 CPU/GPU samples).
- Spell effects on all characters (4c, 39.9) and labels (4d, 42.8) are not slower than plain walk at 100 (36.3). Inferred: effects and labels are not the main cost.
- Players mode (4a, 41.2 at 100) is not slower than walk (36.3 at 100) although it adds runs, casts, effects and sits. Inferred: the extra actions cost little compared with the base per-character cost.
- Private memory grows with crowd: run 2 16.62 GB at 0 to 19.35 GB at 200 (about 13.7 MB per character); it does not return to baseline at the end-of-run 0 (17.19). 4a reaches 21.01 GB at 200.
- Walknamed (game NPC outfits) is not faster than modded outfits at 100 (32.0 vs 36.3) and 50 (55.4 vs 60.1). Inferred: modded outfits are not the extra cost.
- Unexplained: walknamed 200 (35.5 FPS, p10 34, worst p50 39 ms) is faster than walknamed 100 (32.0 FPS, p10 28, worst p50 37 ms). Process CPU is higher at 200 (515 vs 409). No cause found in these data.
- Stand at 100 (36.0 FPS, no animation or actions) equals walk at 100 (36.3, run 2) within 0.3 FPS. Inferred: the per-character cost does not come from walking or actions; it is present for characters that merely exist and stand.
- Low-n phases (4a@200 n=2, 4b n=2, 4a@100 n=7, 4d n=6, stand n=6) have weak CPU/GPU figures. FPS figures always come from the server log (n=24).

## Repeatability (run-to-run noise)

`crowdrun walk 100,100` at 15:11 (same setup as run 2 walk@100), server log PHASE END lines:

| Run | FPS mean | p10 | worst frame p50/p90/max ms |
|---|---|---|---|
| Run 2 walk@100 (14:15-14:17) | 36.3 | 34 | 35/39/44 |
| Repeat 1 (15:12-15:14) | 38.6 | 35 | 34/38/41 |
| Repeat 2 (15:14-15:16) | 38.4 | 38 | 30/35/53 |

Identical setups vary by up to about 6% (36.3 to 38.6). Against that noise, at 100 characters:
walk, stand, churn (36.8), fxall (39.9) and labels (42.8) are within or near noise; players (41.2)
is at the edge of noise; walknamed (32.0) is about 15% below the walk mean (37.8) and is the only
clear difference. Inferred: crowd size sets the frame rate; what the characters do moves it by at most ~15%.

## Phase 2: config fixes (15:27-16:05)

Method: cvars in `%LOCALAPPDATA%\Hogwarts Legacy\ArcaneMP\Saved\Config\WindowsNoEditor\Engine.ini` under
`[SystemSettings]`, one game launch per set, `crowdrun walk 100` (some with a 0 phase first), uncapped, crowdDetail 4
(the user's `preferences.json` value; all earlier runs also used 4). Proof the ini is read: sentinel
`PhoenixSigMgr.LOD.TriangleBudget=3000000` made the mod log print `TriangleBudget 3000000 -> 4000000` (normally `2000000 -> 4000000`).

| Set | 0 chars FPS | 100 chars FPS | worst frame p50/p90 ms | Result |
|---|---|---|---|---|
| L1 none (baseline, 15:27) | 117.0 | 39.3 | 35/40 | |
| L2 all 8 below + cloth off (15:33) | - | - | - | CRASH at pitch teleport |
| L2b SkeletalMeshLODBias=2, RayTracing.Geometry.SkeletalMeshes=0, EnableMorphTargets=0 (15:36) | 140.3 | 56.3 | 26/29 | +43% |
| L3 L2b + p.ClothPhysics=0 (15:42) | - | - | - | CRASH at pitch teleport (same address) |
| L4 L2b + a.URO.Enable=1, a.URO.ForceAnimRate=4, a.URO.ForceInterpolation=1, a.ForceParallelAnimUpdate=1, p.ClothPhysics.WaitForParallelClothTask=0 (15:52) | - | 55.3 | 27/31 | no gain over L2b |
| L5 r.SkeletalMeshLODBias=2 only (15:56) | - | 57.3 | 27/29 | +46%, the whole gain |
| L6 r.SkeletalMeshLODBias=1 only (16:01) | - | 45.0 | 29/31 | +15% |

Crash (L2, L3): client log `Unhandled exception 0xC0000005 at HogwartsLegacy.exe+0x29BB453 on thread 'CrBrowserMain'`,
`Faulting read of 0x50`, right after `[DestinationTeleport] request N holding the player until the floor under the destination loads`.
Only `p.ClothPhysics=0` is common to both crashing sets and absent from the non-crashing ones.

Thread split (`thread-probe.ps1`, % of one core over 15 s; game thread = process main thread, renamed `CrBrowserMain` by CEF,
verified by start time equal to process start):

| State | Game thread | Render thread | RHI thread |
|---|---|---|---|
| L1, 0 chars | 50.5% | 64.5% | 78.0% |
| L1, 100 chars | 74.5% | 81.5% | 64.6% |
| L2b, 100 chars | 97.1% | 61.8% | 71.8% |
| L4, 100 chars | 95.2% | 61.1% | 70.0% |

Inferred: at baseline each character adds ~0.16 ms to both the game and the render thread. LOD bias 2 removes most
of the render-thread cost; the game thread then saturates and no tested cvar reduces it (animation update-rate cvars
apply only to components that opt in; the mod's remote characters evidently do not).

Mod facts (client log): sets `PhoenixSigMgr.LOD.TriangleBudget 2000000 -> 4000000` and `r.SkinCache.SceneMemoryLimitInMB 128 -> 512`
at startup; resolves `CustomizableCharacterComponent::SetForcedLOD` (its crowd-detail LOD tool); none of its 1,110
resolved functions is a tick-interval / update-rate / animation-budget function.

## Not reproduced by these tests

- Body-scale reconcile ([Scale] path): not reproducible through the API.
- Voice lip-sync.
- Brooms.
- Real spell replays (casts here are scripted actions, not recorded player spells).

## Sources

- FPS, worst frame and action counts: the test server's log (`<server>\logs\hogwarts-mp.log`, lines "PHASE END" and "schedule armed"), written by `test-harness/crowd-test`.
- CPU/GPU per phase: `test-harness/scripts/crowd-monitor.ps1` CSVs, summarized with `test-harness/scripts/summarize-run.js <dir>\samples.csv`.
- Client log counts: `test-harness/scripts/count-window.js <client>\logs\ArcaneMP.log "label=HH:MM:SS-HH:MM:SS"`.
- Thread split: `test-harness/scripts/thread-probe.ps1`.
- Raw logs are not published (they contain account and machine details).
