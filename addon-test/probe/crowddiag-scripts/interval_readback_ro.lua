-- READ-ONLY: tick interval of every ticking skeletal mesh owned by a remote avatar, as a histogram.
local TAG = "[CrowdIvl] "
local av = {}
for _, a in ipairs(FindAllOf("BP_RemoteAvatarCCC_C") or {}) do
    if a:IsValid() then av[a:GetAddress()] = true end
end
local hist, ticking, total = {}, 0, 0
for _, cls in ipairs({ "SkeletalMeshComponent", "SkeletalMeshComponentBudgeted" }) do
    for _, c in ipairs(FindAllOf(cls) or {}) do
        if c:IsValid() then
            local ok, owner = pcall(function() return c:GetOwner() end)
            if ok and owner and owner:IsValid() and av[owner:GetAddress()] then
                total = total + 1
                local okT, t = pcall(function() return c:IsComponentTickEnabled() end)
                if okT and t then
                    ticking = ticking + 1
                    local okI, v = pcall(function() return c:GetComponentTickInterval() end)
                    local k = okI and string.format("%.3f", v) or "ERR"
                    hist[k] = (hist[k] or 0) + 1
                end
            end
        end
    end
end
local parts = {}
for k, n in pairs(hist) do table.insert(parts, k .. "s=" .. n) end
table.sort(parts)
print(string.format("%savatar skeletal meshes=%d ticking=%d intervals: %s\n", TAG, total, ticking, table.concat(parts, " ")))
