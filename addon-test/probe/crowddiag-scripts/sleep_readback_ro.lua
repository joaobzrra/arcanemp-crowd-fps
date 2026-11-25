-- READ-ONLY: what state every remote avatar is in, as totals, plus the distance range from the local character.
-- Used to verify CrowdFix's sleep step from outside the mod.
local me = FindFirstOf("BP_Biped_Player_C")
if not (me and me:IsValid()) then print("[CrowdSleep] no local player\n"); return end
local p = me:K2_GetActorLocation()
local n, hidden, actorOff, bodyTick, moveTick, dmin, dmax = 0, 0, 0, 0, 0, math.huge, 0
local hiddenNear, shownFar = 0, 0   -- relative to the limit passed in the global CrowdSleepLimitM (metres), if set
local owners = {}
for _, av in ipairs(FindAllOf("BP_RemoteAvatarCCC_C") or {}) do
    if av:IsValid() then
        n = n + 1
        local l = av:K2_GetActorLocation()
        local d = math.sqrt((l.X - p.X) ^ 2 + (l.Y - p.Y) ^ 2 + (l.Z - p.Z) ^ 2) / 100
        if d < dmin then dmin = d end
        if d > dmax then dmax = d end
        -- "hidden" = the body mesh is hidden (bHiddenInGame). The actor-level bHidden is not readable on this game.
        local okH, h = pcall(function() return av.Mesh.bHiddenInGame end)
        local isHidden = okH and h == true
        if isHidden then hidden = hidden + 1 end
        if CrowdSleepLimitM then
            if isHidden and d < CrowdSleepLimitM * 0.9 then hiddenNear = hiddenNear + 1 end
            if (not isHidden) and d >= CrowdSleepLimitM then shownFar = shownFar + 1 end
        end
        local okT, t = pcall(function() return av:IsActorTickEnabled() end)
        if okT and t == false then actorOff = actorOff + 1 end
        local body = av.Mesh
        if body and body:IsValid() then
            local okB, b = pcall(function() return body:IsComponentTickEnabled() end)
            if okB and b then bodyTick = bodyTick + 1 end
        end
        local mv = av.CharacterMovement
        if mv and mv:IsValid() then
            local okM, m = pcall(function() return mv:IsComponentTickEnabled() end)
            if okM and m then moveTick = moveTick + 1 end
        end
        owners[av:GetAddress()] = true
    end
end
local meshes, meshTick = 0, 0
for _, cls in ipairs({ "SkeletalMeshComponent", "SkeletalMeshComponentBudgeted" }) do
    for _, c in ipairs(FindAllOf(cls) or {}) do
        if c:IsValid() then
            local ok, o = pcall(function() return c:GetOwner() end)
            if ok and o and o:IsValid() and owners[o:GetAddress()] then
                meshes = meshes + 1
                local okT, t = pcall(function() return c:IsComponentTickEnabled() end)
                if okT and t then meshTick = meshTick + 1 end
            end
        end
    end
end
print(string.format("[CrowdSleep] avatars=%d hidden=%d actorTickOff=%d bodyTicking=%d movementTicking=%d meshes=%d meshesTicking=%d distance %.0f-%.0f m%s\n",
    n, hidden, actorOff, bodyTick, moveTick, meshes, meshTick, n > 0 and dmin or 0, dmax,
    CrowdSleepLimitM and string.format(" | limit %d m: hidden inside 90%%=%d, visible beyond=%d", CrowdSleepLimitM, hiddenNear, shownFar) or ""))
