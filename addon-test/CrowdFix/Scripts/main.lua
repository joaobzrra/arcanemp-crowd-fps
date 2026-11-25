-- CrowdFix (UE4SS Lua mod) for ArcaneMP / Hogwarts Legacy.
-- Lowers the cost of distant remote players on this client only; nearby players are never touched and nothing is
-- sent to the server. Three steps by distance:
--   beyond `distance`       the body mesh gets Unreal's animation update-rate optimisation (URO)
--   beyond `fardistance`    every mesh animates only every `farinterval` seconds
--   beyond `sleepdistance`  the player is put to sleep: hidden, no animation, no movement or ability updates.
--                           The position keeps following the real player, who wakes up when coming closer.
-- Settings: Mods\CrowdFix\settings.txt (re-read every sweep).
--   enabled=1        0 turns the mod off (restores every player it changed)
--   distance=2500    cm; players farther than this get URO
--   interpolate=1    a.URO.ForceInterpolation (smooth between skipped frames)
--   animrate=2       a.URO.ForceAnimRate (URO players update every N frames; 0 = engine default)
--   shadows=0        cm; players farther than this stop casting shadows (all their meshes). 0 = keep all shadows
--   cloth=0          cm; players farther than this get cloth simulation paused (all their meshes). 0 = never
--   fardistance=5000 cm; players farther than this have their meshes animate only every `farinterval` seconds
--   farinterval=0.2  seconds between animation updates of those far players (0.2 = 5 per second). 0 = feature off
--   sleepdistance=0  cm; players farther than this are asleep and not drawn (10000 = 100 m). 0 = feature off
-- Measured on ArcaneMP 1.15.1: see the repository README and addon-test/RESULTS-ADDON.md.
local MOD_DIR = debug.getinfo(1, "S").source:match("@?(.*[\\/])Scripts[\\/]") or ""
local TAG = "[CrowdFix] "
local BATCH, STEP_MS, RESCAN_S = 10, 250, 10
local SCAN_BUDGET_S = 0.002   -- seconds of component-map work per step (the map is built over several steps)
local WAKE_FACTOR = 0.9       -- a sleeping player wakes inside 90% of sleepdistance, so nobody flickers at the edge

local function readSettings()
    local s = { enabled = 1, distance = 2500, interpolate = 1, animrate = 2, shadows = 0, cloth = 0, fardistance = 5000, farinterval = 0.2, sleepdistance = 0 }
    local f = io.open(MOD_DIR .. "settings.txt", "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("^%s*([%w_]+)%s*=%s*([^%s;]+)")
            if k and tonumber(v) then s[k] = tonumber(v) end
        end
        f:close()
    end
    return s
end

local cfg = readSettings()
local appliedCvars = nil
local function applyCvars()
    -- `enabled` is part of the key, so switching CrowdFix on/off re-applies (or resets) the cvars.
    local want = string.format("%d/%d/%d", cfg.enabled, cfg.interpolate, cfg.animrate)
    if want == appliedCvars then return end
    local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local pc = FindFirstOf("PlayerController")
    if not (ksl and ksl:IsValid() and pc and pc:IsValid()) then return end
    local on = cfg.enabled == 1
    for _, c in ipairs({ "a.URO.ForceInterpolation " .. (on and cfg.interpolate or 0),
                         "a.URO.ForceAnimRate " .. (on and cfg.animrate or 0) }) do
        local ok, e = pcall(function() ksl:ExecuteConsoleCommand(pc, c, pc) end)
        print(TAG .. c .. (ok and " ok" or (" failed: " .. tostring(e))) .. "\n")
    end
    appliedCvars = want
end

local list, idx, lastScan = {}, 1, -1e9
local applied = {}          -- avatar address -> true when URO is on
local shadowOff = {}        -- avatar address -> true when its meshes do not cast shadows
local origShadow = {}       -- mesh address -> CastShadow value before CrowdFix touched it
local meshesOf = {}         -- avatar address -> its skeletal mesh components
local othersOf = {}         -- avatar address -> its movement / ability / managed-character / facial components
local heldOf = {}           -- avatar address -> skeletal meshes of actors attached to it (wand)
local ownerMeshes = {}      -- any other actor's address -> its skeletal meshes (used for the broom or beast a player rides)
local me, lastLine, loggedShadow = nil, "", false
local stats = { far = 0, near = 0, noShadow = 0, noCloth = 0, uroOn = 0, slow = 0, asleep = 0, maxStepMs = 0 }
local farSlow, farGen = {}, {}   -- avatar address -> true while its meshes run at the far interval / map number it was applied at
local origInterval = {}          -- mesh address -> tick interval before CrowdFix touched it
local asleep, sleepGen = {}, {}  -- avatar address -> what CrowdFix changed to put it to sleep / map number it was applied at
local scanGen, loggedFar, loggedSleep = 0, false, false

local function key(o) local ok, a = pcall(function() return o:GetAddress() end); return ok and a or tostring(o) end

-- The component map (which meshes and tickable components belong to which remote player) is rebuilt every
-- RESCAN_S seconds. Walking every skeletal mesh of the world in one go froze the game for up to 31 ms in the open
-- castle, so the walk is spread over steps of SCAN_BUDGET_S each and the finished map is swapped in at the end.
local MESH_CLASSES = { "SkeletalMeshComponent", "SkeletalMeshComponentBudgeted" }
local OTHER_CLASSES = { "Biped_MovementComponent", "AblAbilityComponent", "PhoenixManagedCharacter", "FacialComponent" }
local scan = nil

local function scanWanted()
    if cfg.enabled == 1 and (cfg.shadows > 0 or cfg.cloth > 0 or (cfg.farinterval > 0 and cfg.fardistance > 0) or cfg.sleepdistance > 0) then return true end
    return next(shadowOff) ~= nil or next(farSlow) ~= nil or next(asleep) ~= nil
end

local function beginScan()
    local isAv = {}
    for _, av in ipairs(list) do if av:IsValid() then isAv[key(av)] = true end end
    local withSleep = cfg.sleepdistance > 0 or next(asleep) ~= nil
    scan = { classes = {}, ci = 1, items = {}, i = 1, isAv = isAv, withSleep = withSleep,
             seen = {}, meshes = {}, others = {}, held = {}, byOwner = {}, parentOf = {} }
    for _, c in ipairs(MESH_CLASSES) do table.insert(scan.classes, { name = c, mesh = true }) end
    if withSleep then for _, c in ipairs(OTHER_CLASSES) do table.insert(scan.classes, { name = c, mesh = false }) end end
end

local function stepScan(t0)
    local sc = scan
    if sc.ci <= #sc.classes then
        -- One class per step: FindAllOf returns the whole list at once.
        local cl = sc.classes[sc.ci]
        for _, c in ipairs(FindAllOf(cl.name) or {}) do table.insert(sc.items, { c = c, mesh = cl.mesh }) end
        sc.ci = sc.ci + 1
        return
    end
    while sc.i <= #sc.items do
        local it = sc.items[sc.i]; sc.i = sc.i + 1
        local c = it.c
        if c:IsValid() then
            local ck = key(c)
            if not sc.seen[ck] then
                sc.seen[ck] = true
                local ok, owner = pcall(function() return c:GetOwner() end)
                if ok and owner and owner:IsValid() then
                    local okey = key(owner)
                    if sc.isAv[okey] then
                        local t = it.mesh and sc.meshes or sc.others
                        t[okey] = t[okey] or {}
                        table.insert(t[okey], c)
                    elseif it.mesh and sc.withSleep then
                        sc.byOwner[okey] = sc.byOwner[okey] or {}
                        table.insert(sc.byOwner[okey], c)
                        -- A skeletal mesh of something a remote player holds (wand): found through its attach parent.
                        local pk = sc.parentOf[okey]
                        if pk == nil then
                            local okP, k2 = pcall(function()
                                local par = owner:GetAttachParentActor()
                                if par and par:IsValid() then return key(par) end
                                return nil
                            end)
                            pk = (okP and k2 and sc.isAv[k2]) and k2 or false
                            sc.parentOf[okey] = pk
                        end
                        if pk then sc.held[pk] = sc.held[pk] or {}; table.insert(sc.held[pk], c) end
                    end
                end
            end
        end
        if os.clock() - t0 >= SCAN_BUDGET_S then return end
    end
    meshesOf, othersOf, heldOf, ownerMeshes = sc.meshes, sc.others, sc.held, sc.byOwner
    for ck in pairs(origInterval) do if not sc.seen[ck] then origInterval[ck] = nil end end
    scanGen = scanGen + 1
    scan = nil
end

-- Far players: each of their ticking skeletal meshes updates its animation only every cfg.farinterval seconds.
-- Coming back inside the distance (or switching the mod off) puts every mesh back to its own interval.
local function setFarInterval(avKey, on)
    local n, first = 0, nil
    for _, c in ipairs(meshesOf[avKey] or {}) do
        if c:IsValid() then
            local ck = key(c)
            if on then
                local okT, ticking = pcall(function() return c:IsComponentTickEnabled() end)
                if okT and ticking then
                    if origInterval[ck] == nil then
                        local okI, v = pcall(function() return c:GetComponentTickInterval() end)
                        origInterval[ck] = okI and v or 0
                    end
                    if pcall(function() c:SetComponentTickInterval(cfg.farinterval) end) then n = n + 1; first = first or c end
                end
            elseif origInterval[ck] ~= nil then
                pcall(function() c:SetComponentTickInterval(origInterval[ck]) end)
                origInterval[ck] = nil
            end
        end
    end
    if on and first and not loggedFar then
        loggedFar = true
        print(string.format("%sfar check: %d meshes of one far player set, first interval now %.2fs\n", TAG, n, first:GetComponentTickInterval()))
    end
end

-- Sleep: every mesh of the player is hidden and every tick CrowdFix found on it is switched off. The ArcaneMP
-- client keeps moving the sleeping actor to the real player's position (measured live), so the distance check still
-- sees it coming. Called again after every new component map: it catches clothes, a wand or a broom that appeared
-- meanwhile. Hiding is done per mesh (SetHiddenInGame, read back through bHiddenInGame): the actor-level
-- SetActorHiddenInGame gave no readable result on this game (bHidden stayed false), so it is not relied on.
local function quiet(c, s, list, hide)
    if not c:IsValid() then return 0 end
    local n = 0
    local okT, ticking = pcall(function() return c:IsComponentTickEnabled() end)
    if okT and ticking and pcall(function() c:SetComponentTickEnabled(false) end) then
        table.insert(s[list .. "Ticks"], c); n = 1
    end
    if hide then
        local okH, hidden = pcall(function() return c.bHiddenInGame end)
        if okH and hidden == false and pcall(function() c:SetHiddenInGame(true, false) end) then table.insert(s[list .. "Hidden"], c) end
    end
    return n
end

local function sleepAvatar(av, k)
    local s = asleep[k]
    if not s then
        s = { av = av, ownTicks = {}, ownHidden = {}, mountTicks = {}, mountHidden = {} }
        -- Unknown (a failed read) counts as "was ticking": waking restores the normal state.
        local okT, t = pcall(function() return av:IsActorTickEnabled() end); s.actorTick = (not okT) or t ~= false
        asleep[k] = s
    end
    pcall(function() av:SetActorTickEnabled(false) end)
    local n = 0
    for _, c in ipairs(meshesOf[k] or {}) do n = n + quiet(c, s, "own", true) end
    for _, c in ipairs(heldOf[k] or {}) do n = n + quiet(c, s, "own", true) end
    for _, c in ipairs(othersOf[k] or {}) do n = n + quiet(c, s, "own", false) end
    -- A broom or beast the player rides is its own actor: its meshes sleep too, or it would fly on without a rider.
    local okM, mk = pcall(function()
        local p = av:GetAttachParentActor()
        if p and p:IsValid() then return key(p) end
        return nil
    end)
    if okM and mk then
        for _, c in ipairs(ownerMeshes[mk] or {}) do n = n + quiet(c, s, "mount", true) end
    end
    sleepGen[k] = scanGen
    if not loggedSleep then
        loggedSleep = true
        local body = av.Mesh
        local okH, h = pcall(function() return body.bHiddenInGame end)
        local okA, a = pcall(function() return av:IsActorTickEnabled() end)
        print(string.format("%ssleep check: one far player asleep, %d ticks switched off, %d meshes hidden, body hidden now %s, actor tick now %s\n",
            TAG, n, #s.ownHidden, okH and tostring(h) or "unreadable", okA and tostring(a) or "unreadable"))
    end
end

-- Puts back what `quiet` changed for one group ("own" or "mount").
local function restore(s, list)
    for _, c in ipairs(s[list .. "Ticks"]) do
        if c:IsValid() then pcall(function() c:SetComponentTickEnabled(true) end) end
    end
    for _, c in ipairs(s[list .. "Hidden"]) do
        if c:IsValid() then pcall(function() c:SetHiddenInGame(false, false) end) end
    end
end

local function wakeAvatar(k)
    local s = asleep[k]
    if not s then return end
    restore(s, "own")
    restore(s, "mount")
    local av = s.av
    if av and av:IsValid() and s.actorTick then pcall(function() av:SetActorTickEnabled(true) end) end
    asleep[k], sleepGen[k] = nil, nil
end

local function setShadows(avKey, off)
    for _, c in ipairs(meshesOf[avKey] or {}) do
        if c:IsValid() then
            local ck = key(c)
            if origShadow[ck] == nil then origShadow[ck] = c.CastShadow end
            local want = (not off) and origShadow[ck] or false
            pcall(function() c:SetCastShadow(want) end)
        end
    end
end

local clothOff, loggedCloth = {}, false   -- avatar address -> true when its cloth is paused
local function setCloth(avKey, off)
    local okAll, err = true, nil
    for _, c in ipairs(meshesOf[avKey] or {}) do
        if c:IsValid() then
            local ok, e = pcall(function()
                if off then c:SuspendClothingSimulation() else c:ResumeClothingSimulation() end
            end)
            if not ok then okAll, err = false, e end
        end
    end
    if not loggedCloth then
        loggedCloth = true
        print(string.format("%scloth check: %s on %d meshes -> %s\n", TAG, off and "Suspend" or "Resume",
            #(meshesOf[avKey] or {}), okAll and "ok" or ("ERR " .. tostring(err))))
    end
end

local function startSweep(full)
    cfg = readSettings()
    applyCvars()
    if full then
        list = FindAllOf("BP_RemoteAvatarCCC_C") or {}; lastScan = os.clock()
        -- Forget players that despawned, so their old entries do not keep the component map running.
        local live = {}
        for _, av in ipairs(list) do live[key(av)] = true end
        -- A player that despawned while asleep must not leave its broom asleep and hidden.
        for k, s in pairs(asleep) do if not live[k] then restore(s, "mount") end end
        for _, t in ipairs({ applied, shadowOff, clothOff, farSlow, farGen, asleep, sleepGen }) do
            for k in pairs(t) do if not live[k] then t[k] = nil end end
        end
        if not scan and (scanWanted() or next(clothOff) ~= nil) then beginScan() end
    end
    local p = FindFirstOf("BP_Biped_Player_C")
    me = (p and p:IsValid()) and p:K2_GetActorLocation() or nil
    idx = 1
    stats.far, stats.near, stats.noShadow, stats.noCloth, stats.uroOn, stats.slow, stats.asleep = 0, 0, 0, 0, 0, 0, 0
end

-- One step of work, always on the game thread.
local function step()
    local ok, e = pcall(function()
        local t0 = os.clock()
        if scan then stepScan(t0) end
        if idx > #list then startSweep(os.clock() - lastScan >= RESCAN_S or #list == 0) end
        local stop = math.min(#list, idx + BATCH - 1)
        for i = idx, stop do
            local av = list[i]
            if av and av:IsValid() then
                local k = key(av)
                local d2 = nil   -- squared distance to the local character; nil while CrowdFix is off
                if cfg.enabled == 1 and me then
                    local l = av:K2_GetActorLocation()
                    local dx, dy, dz = l.X - me.X, l.Y - me.Y, l.Z - me.Z
                    d2 = dx * dx + dy * dy + dz * dz
                end
                local far = d2 ~= nil and d2 >= cfg.distance * cfg.distance
                local noShadow = d2 ~= nil and cfg.shadows > 0 and d2 >= cfg.shadows * cfg.shadows
                local slow = d2 ~= nil and cfg.farinterval > 0 and cfg.fardistance > 0 and d2 >= cfg.fardistance * cfg.fardistance
                local noCloth = d2 ~= nil and cfg.cloth > 0 and d2 >= cfg.cloth * cfg.cloth
                local sleep = false
                if d2 ~= nil and cfg.sleepdistance > 0 then
                    local lim = cfg.sleepdistance * (asleep[k] and WAKE_FACTOR or 1)
                    sleep = d2 >= lim * lim
                end
                local body = av.Mesh
                -- After a player leaves, the client keeps an empty shell of the avatar until the engine's next garbage
                -- collection (seen parked at the world origin). Its body mesh still reads as valid but no longer names
                -- the avatar as its owner. A shell is not counted and not handled, only released if it was asleep.
                local hasBody = false
                if body ~= nil and body:IsValid() then
                    local okO, owned = pcall(function()
                        local o = body:GetOwner()
                        return o ~= nil and o:IsValid() and o:GetAddress() == k
                    end)
                    hasBody = okO and owned == true
                end
                if not hasBody then
                    if asleep[k] then restore(asleep[k], "mount"); asleep[k], sleepGen[k] = nil, nil end
                    applied[k], shadowOff[k], clothOff[k], farSlow[k], farGen[k] = nil, nil, nil, nil, nil
                elseif far then stats.far = stats.far + 1 else stats.near = stats.near + 1 end
                if hasBody then
                    if (applied[k] or false) ~= far then
                        body.bEnableUpdateRateOptimizations = far
                        applied[k] = far or nil
                    end
                    -- Read-back: count only players whose body mesh really has URO on.
                    if body.bEnableUpdateRateOptimizations then stats.uroOn = stats.uroOn + 1 end
                end
                -- Recorded only once the avatar's meshes are mapped, so a new player is handled after the next map.
                local mapped = meshesOf[k] ~= nil and #meshesOf[k] > 0
                if not mapped then
                    -- A player whose meshes are gone has nothing left to restore: drop the flags, or they
                    -- would keep the component map running after CrowdFix is switched off.
                    if not noShadow then shadowOff[k] = nil end
                    if not noCloth then clothOff[k] = nil end
                    if not slow then farSlow[k], farGen[k] = nil, nil end
                end
                if (shadowOff[k] or false) ~= noShadow and mapped then
                    setShadows(k, noShadow)
                    shadowOff[k] = noShadow or nil
                    if not loggedShadow then
                        loggedShadow = true
                        local m = meshesOf[k][1]
                        print(string.format("%sshadow check: avatar has %d meshes, first CastShadow now %s\n",
                            TAG, #meshesOf[k], tostring(m.CastShadow)))
                    end
                end
                if shadowOff[k] then stats.noShadow = stats.noShadow + 1 end
                if (clothOff[k] or false) ~= noCloth and mapped then
                    setCloth(k, noCloth)
                    clothOff[k] = noCloth or nil
                end
                if clothOff[k] then stats.noCloth = stats.noCloth + 1 end
                -- Re-applied after every new map, so clothes a far player put on later are covered too.
                if mapped and ((farSlow[k] or false) ~= slow or (slow and farGen[k] ~= scanGen)) then
                    setFarInterval(k, slow)
                    farSlow[k] = slow or nil
                    farGen[k] = slow and scanGen or nil
                end
                if farSlow[k] then stats.slow = stats.slow + 1 end
                if sleep then
                    if mapped and sleepGen[k] ~= scanGen then sleepAvatar(av, k) end
                elseif asleep[k] then
                    wakeAvatar(k)
                end
                if asleep[k] then stats.asleep = stats.asleep + 1 end
            end
        end
        idx = stop + 1
        local ms = (os.clock() - t0) * 1000
        if ms > stats.maxStepMs then stats.maxStepMs = ms end
        if idx > #list and #list > 0 then
            local line = string.format("enabled=%d distance=%dcm shadows=%dcm cloth=%dcm fardistance=%dcm farinterval=%.2fs sleepdistance=%dcm players near=%d far=%d uroOn(readback)=%d noShadow=%d noCloth=%d slowAnim=%d asleep=%d slowestStep=%.1fms",
                cfg.enabled, cfg.distance, cfg.shadows, cfg.cloth, cfg.fardistance, cfg.farinterval, cfg.sleepdistance, stats.near, stats.far, stats.uroOn, stats.noShadow, stats.noCloth, stats.slow, stats.asleep, stats.maxStepMs)
            if line ~= lastLine then print(TAG .. line .. "\n"); lastLine = line end
            stats.maxStepMs = 0
        end
    end)
    if not ok then print(TAG .. "error: " .. tostring(e) .. "\n") end
end

-- The timer must fire on the game thread. LoopAsync runs its callback on UE4SS's async thread, and that thread
-- shares one Lua state with the game-thread callbacks: two scripts of one mod running at the same moment corrupt it
-- (seen as a crash in UE4SS, 2026-11-24). LoopInGameThreadWithDelay (UE4SS v4) never leaves the game thread.
if LoopInGameThreadWithDelay then
    LoopInGameThreadWithDelay(STEP_MS, step)
    print(TAG .. "loaded (v3, game-thread timer)\n")
else
    LoopAsync(STEP_MS, function() ExecuteInGameThread(step); return false end)
    print(TAG .. "loaded (v3, async timer: this UE4SS has no LoopInGameThreadWithDelay)\n")
end
