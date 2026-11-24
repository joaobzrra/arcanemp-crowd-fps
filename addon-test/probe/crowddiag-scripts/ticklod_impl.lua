-- Defines two globals used by ticklod1_off.lua / ticklod5_off.lua / ticklod_restore.lua.
-- CrowdTickLodOff(n): component tick OFF on every remote-avatar skeletal mesh whose GetNumLODs() == n.
-- CrowdTickLodRestore(): puts back every tick state CrowdTickLodOff changed. Client-local, nothing is sent anywhere.
local function log(s) print("[CrowdDiag] " .. s .. "\n") end
local function try(f) local ok, v = pcall(f); if ok then return v end; return nil end
local function addr(o) local ok, a = pcall(function() return o:GetAddress() end); return ok and a or tostring(o) end
CrowdTickLodSaved = CrowdTickLodSaved or {}

function CrowdTickLodOff(n)
    local isAv = {}
    for _, av in ipairs(FindAllOf("BP_RemoteAvatarCCC_C") or {}) do if av:IsValid() then isAv[addr(av)] = true end end
    local total, was, set = 0, 0, 0
    for _, cls in ipairs({ "SkeletalMeshComponent", "SkeletalMeshComponentBudgeted" }) do
        for _, c in ipairs(FindAllOf(cls) or {}) do
            local o = try(function() return c:GetOwner() end)
            if o and isAv[addr(o)] and try(function() return c:GetNumLODs() end) == n then
                total = total + 1
                local ticking = try(function() return c:IsComponentTickEnabled() end)
                if ticking == true then
                    was = was + 1
                    local k = addr(c)
                    if CrowdTickLodSaved[k] == nil then CrowdTickLodSaved[k] = c end
                    if pcall(function() c:SetComponentTickEnabled(false) end) then set = set + 1 end
                end
            end
        end
    end
    log(string.format("ticklod %d off: %d meshes with %d LODs, %d were ticking, %d switched off", n, total, n, was, set))
end

function CrowdTickLodRestore()
    local n = 0
    for _, c in pairs(CrowdTickLodSaved) do
        if try(function() return c:IsValid() end) and pcall(function() c:SetComponentTickEnabled(true) end) then n = n + 1 end
    end
    CrowdTickLodSaved = {}
    log("ticklod restore: " .. n .. " meshes ticking again")
end
