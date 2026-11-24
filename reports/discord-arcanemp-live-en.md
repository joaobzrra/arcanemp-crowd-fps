**Follow-up 2: live measurements on a public server (what remote players cost, and why)**

My own client on CHRONIX, 19-38 players loaded. The switches are client-local and restored after each step. CPU ms per frame per thread.
```
                                       FPS    game   render  RHI
baseline, ~33 players                  54     16.5   17.0    14.0
every per-player tick off              73.6   -5.1   -6.6    -4.0
players >50 m: mesh tick every 0.2 s   63.4   -2.2   -5.2    -3.2
```
**Findings**
- Remote players are fully built and animated every frame at any distance. One scan: of 24 players, 13 were 200-500 m away and 2 beyond 500 m, all ticking, most behind walls.
- The cost is per-player ticks: about 0.16 ms game + 0.20 ms render + 0.12 ms RHI per player per frame. Skeletal mesh ticks are the render/RHI part. Actor, ability, facial and wand ticks: nothing measurable.
- Half of the ticking meshes on players (53 of 107, including 18 of 20 body meshes) are cosmetic-mod assets with a single LOD, so LODBias and distance never reduce them.
- CPU trace: the client's own code is about 5% of the game thread, engine code 77%. Your code is not slow; the engine work each avatar creates is the cost.

**What would fix it in the client**
1. Do not animate far or unseen avatars every frame (a tick interval or the animation budget, decided per avatar for all its meshes together; flipping `VisibilityBasedAnimTickOption` per mesh broke clothes and faces in my tests).
2. A shorter streaming range, or a cheap stand-in beyond ~100 m.
3. Render the in-game UI on the GPU with a 60 FPS cap. Not measurable on my PC; a tester with a weak PC reports a gain.

My add-on does (1) for players beyond 50 m: 57 -> 66 FPS (+15%) with 30-38 players. Limits: one PC, single runs, not yet repeated on a full server; I will post that when I have it.
Data and scripts (Tests 11-13): https://github.com/joaobzrra/arcanemp-crowd-fps/blob/main/addon-test/RESULTS-ADDON.md
