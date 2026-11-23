-- CrowdFix (UE4SS Lua mod) for ArcaneMP / Hogwarts Legacy.
-- Lowers the game-thread cost of distant remote players: their body mesh gets Unreal's animation
-- update-rate optimisation (URO) beyond a distance; nearby players are never touched.
-- Settings: Mods\CrowdFix\settings.txt (re-read every sweep).
--   enabled=1        0 turns the mod off (restores every player it changed)
--   distance=2500    cm; players farther than this get URO
--   interpolate=1    a.URO.ForceInterpolation (smooth between skipped frames)
--   animrate=2       a.URO.ForceAnimRate (URO players update every N frames; 0 = engine default)
-- Measured on ArcaneMP 1.15.1 (100 test characters, 15-50 m): see the repository README.
local MOD_DIR = debug.getinfo(1, "S").source:match("@?(.*[\\/])Scripts[\\/]") or ""
local TAG = "[CrowdFix] "
local BATCH, STEP_MS, RESCAN_S = 10, 250, 10

local function readSettings()
    local s = { enabled = 1, distance = 2500, interpolate = 1, animrate = 2 }
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
    local want = string.format("%d/%d", cfg.interpolate, cfg.animrate)
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
local me, lastLine = nil, ""
local stats = { far = 0, near = 0, maxStepMs = 0 }

local function key(o) local ok, a = pcall(function() return o:GetAddress() end); return ok and a or tostring(o) end

local function startSweep(full)
    if full then list = FindAllOf("BP_RemoteAvatarCCC_C") or {}; lastScan = os.clock() end
    local p = FindFirstOf("BP_Biped_Player_C")
    me = (p and p:IsValid()) and p:K2_GetActorLocation() or nil
    cfg = readSettings()
    applyCvars()
    idx = 1
    stats.far, stats.near = 0, 0
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
                    local far = false
                    if cfg.enabled == 1 and me then
                        local l = av:K2_GetActorLocation()
                        local dx, dy, dz = l.X - me.X, l.Y - me.Y, l.Z - me.Z
                        far = (dx * dx + dy * dy + dz * dz) >= cfg.distance * cfg.distance
                    end
                    if far then stats.far = stats.far + 1 else stats.near = stats.near + 1 end
                    local k = key(av)
                    if (applied[k] or false) ~= far then
                        local body = av.Mesh
                        if body and body:IsValid() then body.bEnableUpdateRateOptimizations = far end
                        applied[k] = far or nil
                    end
                end
            end
            idx = stop + 1
            local ms = (os.clock() - t0) * 1000
            if ms > stats.maxStepMs then stats.maxStepMs = ms end
            if idx > #list and #list > 0 then
                local line = string.format("enabled=%d distance=%dcm players near=%d far(URO)=%d slowestStep=%.1fms",
                    cfg.enabled, cfg.distance, stats.near, stats.far, stats.maxStepMs)
                if line ~= lastLine then print(TAG .. line .. "\n"); lastLine = line end
                stats.maxStepMs = 0
            end
        end)
        if not ok then print(TAG .. "error: " .. tostring(e) .. "\n") end
    end)
    return false
end)

print(TAG .. "loaded\n")
