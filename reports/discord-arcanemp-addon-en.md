**Follow-up: crowd FPS, what fixed the game thread (test add-on)**

The config workaround (`r.SkeletalMeshLODBias=2`) only fixes the render thread. The game thread stays at 95-97%, and no cvar reaches it because remote players never opt into URO.

So I tested an add-on (UE4SS Lua, loaded next to the official client, no ArcaneMP code touched):
- Each `BP_RemoteAvatarCCC_C` has 8 skeletal meshes (Lower, Upper, Robe, Arms, Hair, Socks, Shoes, `CharacterMesh0`).
- The add-on sets `bEnableUpdateRateOptimizations` on the body mesh (`avatar.Mesh`) for players beyond 25 m only. Followers keep following its pose.
- Plus `a.URO.ForceInterpolation 1` and `a.URO.ForceAnimRate 2`.
- Spread over frames (10 avatars per 250 ms, writes only on change; slowest step 2 ms).
```
100 chars spread 15-50 m          FPS    worst frame p50
LODBias=2 only                    56.8   27 ms
+ add-on (URO beyond 25 m)        63.9   25 ms   far ones flicker
+ ForceInterpolation + AnimRate 2 61.1   26 ms   no visible stutter
```
**What did NOT work**
- Tick interval 0.1 s on all 8 meshes: +50% FPS (40 -> 60); with URO on all 8 as well, +95% (78). But hair detaches and the walk looks like ~20 FPS.
- URO starting at 5-10 m: visible stutter. 25 m is the comfortable distance.
- `SetForcedLOD` per mesh: no gain (something overrides it).

**Suggested change in the client**
Opt remote avatars' body mesh into URO beyond ~25 m, with interpolation and a rate cap. Same result, no add-on needed. (Correction: an earlier version said ~39 to ~61 FPS; that mixed a compact-crowd baseline with a spread-crowd result. The measured add-on gain on top of LOD bias was 56.8 to 61.1 in one spread run, and none in rooms.)

Add-on source, test data and loader: https://github.com/joaobzrra/arcanemp-crowd-fps/tree/main/addon-test
The add-on needs UE4SS loaded after the menu (late injection). Is that acceptable to you, or would you rather add this to the client?
— João Bezerra
