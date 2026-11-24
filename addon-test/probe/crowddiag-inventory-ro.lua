-- READ-ONLY inventory of remote avatars. Writes nothing to the game: it only reads objects and prints to UE4SS.log.
-- Output tag: [CrowdInv]. Run inside the game thread (CrowdDiag `lua inventory_ro.lua`, or the CrowdInv mod).
-- Answers: what is one remote player made of? Per avatar: components by class, skeletal meshes (ticking, anim
-- instance, post-process instance, master pose, bones, materials), static meshes, and actors attached to it.
local TAG = "[CrowdInv] "
local function log(s) print(TAG .. s .. "\n") end
local function try(f) local ok, v = pcall(f); if ok then return v end; return nil end
local function addr(o) local ok, a = pcall(function() return o:GetAddress() end); return ok and a or tostring(o) end
local function full(o) return try(function() return o:GetFullName() end) or "?" end
local function cls(o) return (full(o):match("^(%S+)")) or "?" end
local function leaf(name) return (name:match("([%w_]+)$")) or name end
local function bump(t, k, n) t[k] = (t[k] or 0) + (n or 1) end
local function top(t, n)
    local a = {}; for k, v in pairs(t) do table.insert(a, { k = k, v = v }) end
    table.sort(a, function(x, y) if x.v == y.v then return x.k < y.k end; return x.v > y.v end)
    local out = {}; for i = 1, math.min(n, #a) do table.insert(out, a[i].k .. "=" .. a[i].v) end
    return table.concat(out, " "), #a
end

local t0 = os.clock()
local avs, isAv = {}, {}
for _, av in ipairs(FindAllOf("BP_RemoteAvatarCCC_C") or {}) do
    if av:IsValid() then table.insert(avs, av); isAv[addr(av)] = true end
end
log(string.format("BEGIN avatars=%d", #avs))
if #avs == 0 then log("END (no remote avatars)"); return end

-- Pass 1: every component owned by a remote avatar.
local compClass, compTick = {}, {}
local per = {}   -- avatar addr -> counters
local function P(k) per[k] = per[k] or { comps = 0, ticking = 0, sk = 0, skTick = 0, anim = 0, post = 0, master = 0, bones = 0, mats = 0, st = 0, widgets = 0 }; return per[k] end
local animClass, postClass, meshAsset, slotName = {}, {}, {}, {}
local nComp = 0
for _, c in ipairs(FindAllOf("ActorComponent") or {}) do
    nComp = nComp + 1
    local o = try(function() return c:GetOwner() end)
    if o and try(function() return o:IsValid() end) then
        local ok = addr(o)
        if isAv[ok] then
            local p, cn = P(ok), cls(c)
            local ticking = try(function() return c:IsComponentTickEnabled() end) == true
            p.comps = p.comps + 1; bump(compClass, cn)
            if ticking then p.ticking = p.ticking + 1; bump(compTick, cn) end
            if cn:find("^SkeletalMeshComponent") then
                p.sk = p.sk + 1; if ticking then p.skTick = p.skTick + 1 end
                bump(slotName, leaf(full(c)) .. (ticking and "(tick)" or ""))
                local ai = try(function() return c:GetAnimInstance() end)
                if ai and try(function() return ai:IsValid() end) then p.anim = p.anim + 1; bump(animClass, cls(ai)) end
                local pi = try(function() return c:GetPostProcessInstance() end)
                if pi and try(function() return pi:IsValid() end) then p.post = p.post + 1; bump(postClass, cls(pi)) end
                local m = try(function() return c.MasterPoseComponent:Get() end)
                if m and try(function() return m:IsValid() end) then p.master = p.master + 1 end
                p.bones = p.bones + (try(function() return c:GetNumBones() end) or 0)
                p.mats = p.mats + (try(function() return c:GetNumMaterials() end) or 0)
                local sm = try(function() return c.SkeletalMesh end)
                if sm and try(function() return sm:IsValid() end) then bump(meshAsset, leaf(full(sm))) end
            elseif cn:find("StaticMeshComponent") then p.st = p.st + 1
            elseif cn:find("Widget") then p.widgets = p.widgets + 1 end
        end
    end
end
local t1 = os.clock()

-- Pass 2: actors attached to a remote avatar (wands, brooms, pets, props, name plates).
local attClass, attTick, nAct, nAtt = {}, {}, 0, 0
for _, a in ipairs(FindAllOf("Actor") or {}) do
    nAct = nAct + 1
    local par = try(function() return a:GetAttachParentActor() end)
    if par and try(function() return par:IsValid() end) and isAv[addr(par)] then
        nAtt = nAtt + 1
        local cn = cls(a); bump(attClass, cn)
        if try(function() return a:IsActorTickEnabled() end) == true then bump(attTick, cn) end
    end
end
local t2 = os.clock()

-- Totals and distribution per avatar.
local sum = { comps = 0, ticking = 0, sk = 0, skTick = 0, anim = 0, post = 0, master = 0, bones = 0, mats = 0, st = 0, widgets = 0 }
local skDist, tickDist = {}, {}
for _, p in pairs(per) do
    for k, v in pairs(p) do sum[k] = sum[k] + v end
    bump(skDist, string.format("%02d", p.sk)); bump(tickDist, string.format("%02d", p.skTick))
end
local n = #avs
log(string.format("per avatar (mean of %d): components %.1f (ticking %.1f) | skeletal meshes %.1f (ticking %.1f, anim instance %.1f, post-process %.1f, master-pose follower %.1f) | bones %.0f | materials %.1f | static meshes %.1f | widgets %.1f | attached actors %.2f",
    n, sum.comps / n, sum.ticking / n, sum.sk / n, sum.skTick / n, sum.anim / n, sum.post / n, sum.master / n, sum.bones / n, sum.mats / n, sum.st / n, sum.widgets / n, nAtt / n))
log("skeletal meshes per avatar (count=avatars): " .. top(skDist, 20))
log("ticking skeletal meshes per avatar: " .. top(tickDist, 20))
log("component classes: " .. top(compClass, 40))
log("ticking component classes: " .. top(compTick, 40))
log("mesh slots: " .. top(slotName, 40))
log("anim instance classes: " .. top(animClass, 20))
log("post-process classes: " .. top(postClass, 20))
local assets, nAssets = top(meshAsset, 40)
log(string.format("distinct skeletal mesh assets: %d; most used: %s", nAssets, assets))
log("attached actor classes: " .. top(attClass, 30))
log("ticking attached actor classes: " .. top(attTick, 30))
log(string.format("END scanned components=%d actors=%d; time components %.2fs actors %.2fs", nComp, nAct, t1 - t0, t2 - t1))
