-- CrowdProbe v4: distance-tiered throttling of ArcaneMP remote-player bodies, spread over frames.
-- Settings file Mods\CrowdProbe\tiers.txt (re-read every sweep):
--   mode=tiered | off      near=<cm>      far=<cm>      interval=<s, 0 = URO only>
-- Near: untouched. Mid: URO on the body mesh. Far: URO + tick interval on the body mesh.
-- Only the body mesh (the character's Mesh, CharacterMesh0) is changed; clothing/hair meshes follow its pose.
-- Work per 250 ms step: at most BATCH avatars, and a setting is written only when an avatar's tier changes.
local MOD_DIR = debug.getinfo(1, "S").source:match("@?(.*[\\/])Scripts[\\/]") or ""
local TAG = "[CrowdProbe] "
local BATCH, STEP_MS, RESCAN_S = 10, 250, 10

local function exists(name)
    local f = io.open(MOD_DIR .. name, "r")
    if f then f:close() return true end
    return false
end

local function readSettings()
    local cfg = { mode = "off", near = 500, far = 1000, interval = 0 }
    local f = io.open(MOD_DIR .. "tiers.txt", "r")
    if not f then return cfg end
    for line in f:lines() do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*([^%s;]+)")
        if k then cfg[k] = tonumber(v) or v end
    end
    f:close()
    return cfg
end

local cfg = readSettings()
local list, idx, lastScan = {}, 1, -1e9
local tierOf = {}            -- avatar address -> applied tier
local counts = { [0] = 0, [1] = 0, [2] = 0 }
local stats = { scanMs = 0, maxStepMs = 0, writes = 0 }
local lastLine = ""
local me = nil

local function key(o) local ok, a = pcall(function() return o:GetAddress() end); return ok and a or tostring(o) end

local function applyTier(body, tier)
    body.bEnableUpdateRateOptimizations = tier >= 1
    body:SetComponentTickInterval(tier == 2 and cfg.interval or 0.0)
end

local function rescan()
    local t0 = os.clock()
    list = FindAllOf("BP_RemoteAvatarCCC_C") or {}
    local p = FindFirstOf("BP_Biped_Player_C")
    me = (p and p:IsValid()) and p:K2_GetActorLocation() or nil
    cfg = readSettings()
    stats.scanMs = (os.clock() - t0) * 1000
    idx, lastScan = 1, os.clock()
    counts = { [0] = 0, [1] = 0, [2] = 0 }
end

LoopAsync(STEP_MS, function()
    ExecuteInGameThread(function()
        local ok, e = pcall(function()
            if exists("diag.flag") then
                os.remove(MOD_DIR .. "diag.flag")
                pcall(function() dofile(MOD_DIR .. "Scripts\\diag.lua")() end)
            end
            local t0 = os.clock()
            if idx > #list then
                if os.clock() - lastScan >= RESCAN_S or #list == 0 then rescan() else
                    -- refresh our own position and settings each sweep without a full object scan
                    local p = FindFirstOf("BP_Biped_Player_C")
                    me = (p and p:IsValid()) and p:K2_GetActorLocation() or nil
                    cfg = readSettings()
                    idx = 1
                    counts = { [0] = 0, [1] = 0, [2] = 0 }
                end
            end
            local stop = math.min(#list, idx + BATCH - 1)
            for i = idx, stop do
                local av = list[i]
                if av and av:IsValid() then
                    local tier = 0
                    if cfg.mode == "tiered" and me then
                        local l = av:K2_GetActorLocation()
                        local dx, dy, dz = l.X - me.X, l.Y - me.Y, l.Z - me.Z
                        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
                        if d >= cfg.far then tier = 2 elseif d >= cfg.near then tier = 1 end
                    end
                    counts[tier] = counts[tier] + 1
                    local k = key(av)
                    if tierOf[k] ~= tier then
                        local body = av.Mesh
                        if body and body:IsValid() then applyTier(body, tier); stats.writes = stats.writes + 1 end
                        tierOf[k] = tier
                    end
                end
            end
            idx = stop + 1
            local stepMs = (os.clock() - t0) * 1000
            if stepMs > stats.maxStepMs then stats.maxStepMs = stepMs end
            if idx > #list then
                local line = string.format("mode=%s near=%s far=%s interval=%s avatars=%d near=%d mid=%d far=%d writes=%d scanMs=%.2f maxStepMs=%.2f",
                    tostring(cfg.mode), tostring(cfg.near), tostring(cfg.far), tostring(cfg.interval), #list,
                    counts[0], counts[1], counts[2], stats.writes, stats.scanMs, stats.maxStepMs)
                if line ~= lastLine then print(TAG .. line .. "\n"); lastLine = line end
                stats.maxStepMs = 0
            end
        end)
        if not ok then print(TAG .. "step error: " .. tostring(e) .. "\n") end
    end)
    return false
end)

print(TAG .. "v4 loaded from " .. MOD_DIR .. "\n")
