-- Defines two globals used by farint50_02.lua / farint_restore.lua.
-- CrowdFarInterval(meters, seconds): on every skeletal mesh of remote avatars farther than <meters> from the local
--   character, set the component tick interval to <seconds> (the mesh keeps animating, but only that often).
-- CrowdFarIntervalRestore(): puts every changed interval back. Client-local, nothing is sent anywhere.
local function log(s) print("[CrowdDiag] " .. s .. "\n") end
local function try(f) local ok, v = pcall(f); if ok then return v end; return nil end
local function addr(o) local ok, a = pcall(function() return o:GetAddress() end); return ok and a or tostring(o) end
CrowdFarIntervalSaved = CrowdFarIntervalSaved or {}

function CrowdFarInterval(meters, seconds)
    local me = FindFirstOf("BP_Biped_Player_C")
    if not (me and me:IsValid()) then log("farint: no local player"); return end
    local p, far, lim = me:K2_GetActorLocation(), {}, meters * 100
    local nAv = 0
    for _, av in ipairs(FindAllOf("BP_RemoteAvatarCCC_C") or {}) do
        if av:IsValid() then
            local l = av:K2_GetActorLocation()
            if math.sqrt((l.X - p.X) ^ 2 + (l.Y - p.Y) ^ 2 + (l.Z - p.Z) ^ 2) > lim then far[addr(av)] = true; nAv = nAv + 1 end
        end
    end
    local set, readback, err = 0, {}, nil
    for _, cls in ipairs({ "SkeletalMeshComponent", "SkeletalMeshComponentBudgeted" }) do
        for _, c in ipairs(FindAllOf(cls) or {}) do
            local o = try(function() return c:GetOwner() end)
            if o and far[addr(o)] and try(function() return c:IsComponentTickEnabled() end) == true then
                local k = addr(c)
                if CrowdFarIntervalSaved[k] == nil then CrowdFarIntervalSaved[k] = { c = c, v = try(function() return c:GetComponentTickInterval() end) or 0 } end
                local ok, e = pcall(function() c:SetComponentTickInterval(seconds) end)
                if ok then set = set + 1 else err = e end
                local r = string.format("%.2f", try(function() return c:GetComponentTickInterval() end) or -1)
                readback[r] = (readback[r] or 0) + 1
            end
        end
    end
    local rb = {}; for k, v in pairs(readback) do table.insert(rb, k .. "s x" .. v) end
    log(string.format("farint >%dm interval %.2fs: %d avatars, %d ticking meshes set, readback %s%s", meters, seconds, nAv, set, table.concat(rb, " "), err and (" ERR " .. tostring(err)) or ""))
end

function CrowdFarIntervalRestore()
    local n = 0
    for _, r in pairs(CrowdFarIntervalSaved) do
        if try(function() return r.c:IsValid() end) and pcall(function() r.c:SetComponentTickInterval(r.v) end) then n = n + 1 end
    end
    CrowdFarIntervalSaved = {}
    log("farint restore: " .. n .. " meshes back to their own interval")
end
