-- CrowdFix (UE4SS Lua mod) for ArcaneMP / Hogwarts Legacy.
-- Lowers the game-thread cost of distant remote players: their body mesh gets Unreal's animation
-- update-rate optimisation (URO) beyond a distance; nearby players are never touched.
-- Settings: Mods\CrowdFix\settings.txt (re-read every sweep).
--   enabled=1        0 turns the mod off (restores every player it changed)
--   distance=2500    cm; players farther than this get URO
--   interpolate=1    a.URO.ForceInterpolation (smooth between skipped frames)
--   animrate=2       a.URO.ForceAnimRate (URO players update every N frames; 0 = engine default)
--   shadows=0        cm; players farther than this stop casting shadows (all their meshes). 0 = keep all shadows
--   cloth=0          cm; players farther than this get cloth simulation paused (all their meshes). 0 = never
--   fardistance=5000 cm; players farther than this have their meshes animate only every `farinterval` seconds
--   farinterval=0.2  seconds between animation updates of those far players (0.2 = 5 per second). 0 = feature off
-- Measured on ArcaneMP 1.15.1 (100 test characters, 15-50 m): see the repository README.
local MOD_DIR = debug.getinfo(1, "S").source:match("@?(.*[\\/])Scripts[\\/]") or ""
local TAG = "[CrowdFix] "
local BATCH, STEP_MS, RESCAN_S = 10, 250, 10

local function readSettings()
    local s = { enabled = 1, distance = 2500, interpolate = 1, animrate = 2, shadows = 0, cloth = 0, fardistance = 5000, farinterval = 0.2 }
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
local me, lastLine, loggedShadow = nil, "", false
local stats = { far = 0, near = 0, noShadow = 0, noCloth = 0, uroOn = 0, slow = 0, maxStepMs = 0 }
local farSlow, farGen = {}, {}   -- avatar address -> true while its meshes run at the far interval / mesh-scan number it was applied at
local origInterval = {}          -- mesh address -> tick interval before CrowdFix touched it
local scanGen, loggedFar = 0, false

local function key(o) local ok, a = pcall(function() return o:GetAddress() end); return ok and a or tostring(o) end

-- Groups every skeletal mesh by the actor that owns it (a remote player has 8).
local function mapMeshes()
    meshesOf = {}
    local seen = {}
    for _, cls in ipairs({ "SkeletalMeshComponent", "SkeletalMeshComponentBudgeted" }) do
        for _, c in ipairs(FindAllOf(cls) or {}) do
            local ck = key(c)
            if not seen[ck] and c:IsValid() then
                seen[ck] = true
                local ok, owner = pcall(function() return c:GetOwner() end)
                if ok and owner and owner:IsValid() then
                    -- Grouped for every owner; only remote avatars (from the sweep list) are ever looked up.
                    local k = key(owner)
                    meshesOf[k] = meshesOf[k] or {}
                    table.insert(meshesOf[k], c)
                end
            end
        end
    end
    for ck in pairs(origInterval) do if not seen[ck] then origInterval[ck] = nil end end
    scanGen = scanGen + 1
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
    if full then
        list = FindAllOf("BP_RemoteAvatarCCC_C") or {}; lastScan = os.clock()
        -- Forget players that despawned, so their old entries do not keep the mesh scan running.
        local live = {}
        for _, av in ipairs(list) do live[key(av)] = true end
        for _, t in ipairs({ applied, shadowOff, clothOff, farSlow, farGen }) do
            for k in pairs(t) do if not live[k] then t[k] = nil end end
        end
        if cfg.shadows > 0 or cfg.cloth > 0 or cfg.farinterval > 0 or next(shadowOff) or next(clothOff) or next(farSlow) then mapMeshes() end
    end
    local p = FindFirstOf("BP_Biped_Player_C")
    me = (p and p:IsValid()) and p:K2_GetActorLocation() or nil
    cfg = readSettings()
    applyCvars()
    idx = 1
    stats.far, stats.near, stats.noShadow, stats.noCloth, stats.uroOn, stats.slow = 0, 0, 0, 0, 0, 0
end

LoopAsync(STEP_MS, function()
    ExecuteInGameThread(function()
        local ok, e = pcall(function()
            local t0 = os.clock()
            if idx > #list then startSweep(os.clock() - lastScan >= RESCAN_S or #list == 0) end
            local stop = math.min(#list, idx + BATCH - 1)
            for i = idx, stop do
                local av = list[i]
                if av and av:IsValid() then
                    local far, noShadow, slow = false, false, false
                    if cfg.enabled == 1 and me then
                        local l = av:K2_GetActorLocation()
                        local dx, dy, dz = l.X - me.X, l.Y - me.Y, l.Z - me.Z
                        local d2 = dx * dx + dy * dy + dz * dz
                        far = d2 >= cfg.distance * cfg.distance
                        noShadow = cfg.shadows > 0 and d2 >= cfg.shadows * cfg.shadows
                        slow = cfg.farinterval > 0 and cfg.fardistance > 0 and d2 >= cfg.fardistance * cfg.fardistance
                    end
                    if far then stats.far = stats.far + 1 else stats.near = stats.near + 1 end
                    local k = key(av)
                    local body = av.Mesh
                    if body and body:IsValid() then
                        if (applied[k] or false) ~= far then
                            body.bEnableUpdateRateOptimizations = far
                            applied[k] = far or nil
                        end
                        -- Read-back: count only players whose body mesh really has URO on.
                        if body.bEnableUpdateRateOptimizations then stats.uroOn = stats.uroOn + 1 end
                    end
                    -- Recorded only once the avatar's meshes are mapped, so a new player is handled after the next rescan.
                    if (shadowOff[k] or false) ~= noShadow and meshesOf[k] and #meshesOf[k] > 0 then
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
                    local noCloth = false
                    if cfg.enabled == 1 and me and cfg.cloth > 0 then
                        local l = av:K2_GetActorLocation()
                        local dx, dy, dz = l.X - me.X, l.Y - me.Y, l.Z - me.Z
                        noCloth = (dx * dx + dy * dy + dz * dz) >= cfg.cloth * cfg.cloth
                    end
                    if (clothOff[k] or false) ~= noCloth and meshesOf[k] and #meshesOf[k] > 0 then
                        setCloth(k, noCloth)
                        clothOff[k] = noCloth or nil
                    end
                    if clothOff[k] then stats.noCloth = stats.noCloth + 1 end
                    -- Re-applied after every mesh scan, so clothes a far player put on later are covered too.
                    if meshesOf[k] and #meshesOf[k] > 0 and ((farSlow[k] or false) ~= slow or (slow and farGen[k] ~= scanGen)) then
                        setFarInterval(k, slow)
                        farSlow[k] = slow or nil
                        farGen[k] = slow and scanGen or nil
                    end
                    if farSlow[k] then stats.slow = stats.slow + 1 end
                end
            end
            idx = stop + 1
            local ms = (os.clock() - t0) * 1000
            if ms > stats.maxStepMs then stats.maxStepMs = ms end
            if idx > #list and #list > 0 then
                local line = string.format("enabled=%d distance=%dcm shadows=%dcm cloth=%dcm fardistance=%dcm farinterval=%.2fs players near=%d far=%d uroOn(readback)=%d noShadow=%d noCloth=%d slowAnim=%d slowestStep=%.1fms",
                    cfg.enabled, cfg.distance, cfg.shadows, cfg.cloth, cfg.fardistance, cfg.farinterval, stats.near, stats.far, stats.uroOn, stats.noShadow, stats.noCloth, stats.slow, stats.maxStepMs)
                if line ~= lastLine then print(TAG .. line .. "\n"); lastLine = line end
                stats.maxStepMs = 0
            end
        end)
        if not ok then print(TAG .. "error: " .. tostring(e) .. "\n") end
    end)
    return false
end)

print(TAG .. "loaded\n")
