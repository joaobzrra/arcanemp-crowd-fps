-- READ-ONLY. How many levels of detail (LODs) do the skeletal meshes of remote avatars have?
-- Names used here were read from the game with lod_names_ro.lua: SkinnedMeshComponent:GetNumLODs(),
-- SkinnedMeshComponent.ForcedLodModel / MinLodModel, SkeletalMesh.LODInfo (array).
local TAG = "[CrowdLod] "
local function log(s) print(TAG .. s .. "\n") end
local function try(f) local ok, v = pcall(f); if ok then return v end; return nil end
local function addr(o) local ok, a = pcall(function() return o:GetAddress() end); return ok and a or tostring(o) end
local function bump(t, k, n) t[k] = (t[k] or 0) + (n or 1) end
local function top(t, n)
    local a = {}; for k, v in pairs(t) do table.insert(a, { k = k, v = v }) end
    table.sort(a, function(x, y) if x.v == y.v then return tostring(x.k) < tostring(y.k) end; return x.v > y.v end)
    local out = {}; for i = 1, math.min(n, #a) do table.insert(out, tostring(a[i].k) .. "=" .. a[i].v) end
    return table.concat(out, " ")
end

local isAv = {}
for _, av in ipairs(FindAllOf("BP_RemoteAvatarCCC_C") or {}) do if av:IsValid() then isAv[addr(av)] = true end end
local t0 = os.clock()
local nComp, byLods, byLodsTick, bonesByLods, forced, minLod = 0, {}, {}, {}, {}, {}
local oneLod, twoLod, assets = {}, {}, {}
for _, cls in ipairs({ "SkeletalMeshComponent", "SkeletalMeshComponentBudgeted" }) do
    for _, c in ipairs(FindAllOf(cls) or {}) do
        local o = try(function() return c:GetOwner() end)
        if o and isAv[addr(o)] then
            nComp = nComp + 1
            local mesh = try(function() return c.SkeletalMesh end)
            local name = mesh and try(function() return mesh:GetFName():ToString() end) or "(none)"
            local lods = try(function() return c:GetNumLODs() end)
            local assetLods = mesh and try(function() return #mesh.LODInfo end) or nil
            local key = tostring(lods) .. (assetLods ~= lods and ("/asset" .. tostring(assetLods)) or "")
            local bones = try(function() return c:GetNumBones() end) or 0
            local ticking = try(function() return c:IsComponentTickEnabled() end) == true
            bump(byLods, key); bump(bonesByLods, key, bones)
            if ticking then bump(byLodsTick, key) end
            bump(forced, tostring(try(function() return c.ForcedLodModel end)))
            bump(minLod, tostring(try(function() return c.MinLodModel end)))
            if lods == 1 then bump(oneLod, name) elseif lods == 2 then bump(twoLod, name) end
            assets[name] = lods
        end
    end
end
local nAssets, assetsByLods = 0, {}
for _, l in pairs(assets) do nAssets = nAssets + 1; bump(assetsByLods, tostring(l)) end
log(string.format("BEGIN avatar skeletal mesh components=%d distinct assets=%d scan %.2fs", nComp, nAssets, os.clock() - t0))
log("components by number of LODs (count): " .. top(byLods, 12))
log("ticking components by number of LODs: " .. top(byLodsTick, 12))
log("bones summed by number of LODs: " .. top(bonesByLods, 12))
log("distinct assets by number of LODs: " .. top(assetsByLods, 12))
log("ForcedLodModel values: " .. top(forced, 6) .. " | MinLodModel values: " .. top(minLod, 6))
log("assets with ONE LOD, by use: " .. top(oneLod, 40))
log("assets with TWO LODs, by use: " .. top(twoLod, 25))
log("END")
