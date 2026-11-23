**ArcaneMP 1.15.1: client FPS vs. nearby players (test data + config workaround)**

Setup: local server spawning N Characters (same `BP_RemoteAvatarCCC` path as remote players) around one client, 120 s per step. Ryzen 9 5900XT, RTX 5060 Ti, 1080p, uncapped, Crowd detail = Medium.
```
Nearby chars   0      25    50    100   150   200
FPS            118.6  79.6  60.1  36.3  28.9  23.6
GPU load       90%  ->  28%   (CPU-bound, ~0.17 ms per character)
```
**Findings**
- Body count drives the cost. Walking, standing, casting, sitting, outfit changes, FX, labels: all within ±15% at 100 (run-to-run noise ~6%).
- Game thread AND render thread each grow ~0.16 ms per character.
- First spawn of a group = one 290-330 ms freeze.
- 4 cores instead of 32 costs ≤26%: per-thread speed is the limit.

**Workaround** — `r.SkeletalMeshLODBias=2` under `[SystemSettings]` in `%LOCALAPPDATA%\Hogwarts Legacy\ArcaneMP\Saved\Config\WindowsNoEditor\Engine.ini`
100 chars: **39.3 → 57.3 FPS (+46%)**. Bias 1: 45.0. Render thread 81% → 62% busy; game thread then saturates (97%).

**Bug** — `p.ClothPhysics=0` crashes the client on teleport: `0xC0000005 at HogwartsLegacy.exe+0x29BB453`, read of 0x50, game thread. Reproduced 2/2.
No effect on remote characters: `a.URO.*`, `a.ForceParallelAnimUpdate`, `p.ClothPhysics.WaitForParallelClothTask`.

**Requests**
1. Force LOD 2+ on remote players beyond the nearest N (Crowd detail already uses `SetForcedLOD`). Same +46%, local player keeps full detail.
2. Reconsider raising `PhoenixSigMgr.LOD.TriangleBudget` 2M → 4M by default.
3. Throttle distant remote players on the game thread: tick interval, anim update rate (URO opt-in), cloth off.
4. Fix the cloth-off teleport crash.
5. Spread proxy spawns over several frames.
6. Server option: per-player stream range or visible-player cap.

Data, test scripts, installer: https://github.com/joaobzrra/arcanemp-crowd-fps
— João Bezerra
