-- READ-ONLY world scan. Writes nothing to the game: it reads objects and prints to UE4SS.log, tag [CrowdWorld].
-- Answers: besides remote avatars, what else is alive and ticking? Actor classes (count, ticking), component
-- classes (count, ticking), who owns the ticking skeletal meshes, and anything broom / mount / creature / pet.
local TAG = "[CrowdWorld] "
local function log(s) print(TAG .. s .. "\n") end
local function try(f) local ok, v = pcall(f); if ok then return v end; return nil end
local function addr(o) local ok, a = pcall(function() return o:GetAddress() end); return ok and a or tostring(o) end
local function full(o) return try(function() return o:GetFullName() end) or "?" end
local function cls(o) return (full(o):match("^(%S+)")) or "?" end
local function bump(t, k, n) t[k] = (t[k] or 0) + (n or 1) end
local function top(t, n, other)
    local a = {}; for k, v in pairs(t) do table.insert(a, { k = k, v = v }) end
    table.sort(a, function(x, y) if x.v == y.v then return x.k < y.k end; return x.v > y.v end)
    local out = {}
    for i = 1, math.min(n, #a) do
        local s = a[i].k .. "=" .. a[i].v
        if other and other[a[i].k] then s = s .. "(" .. other[a[i].k] .. ")" end
        table.insert(out, s)
    end
    return table.concat(out, " "), #a
end
local KEY = { "Broom", "Mount", "Creature", "Beast", "Pet", "Owl", "Cat", "Familiar", "Wand", "Avatar", "Proxy", "Player",
              "Label", "Nameplate", "Widget", "Voice", "Emote", "Prop", "Fx", "Niagara", "Particle" }

local t0 = os.clock()
local me = FindFirstOf("BP_Biped_Player_C")
local mp = me and me:IsValid() and me:K2_GetActorLocation() or nil

-- Actors: class histogram, ticking, keyword classes, and what remote avatars are attached to (mounted?).
local actClass, actTick, keyClass, keyTick, classOf = {}, {}, {}, {}, {}
local EDGES_M = { 10, 25, 50, 100, 200, 500 }  -- distance from the local character, metres; last bucket is "beyond"
local nAct, nActTick, avatars, avNear, avMounted, avRendered = 0, 0, 0, { 0, 0, 0, 0, 0, 0, 0 }, {}, 0
for _, a in ipairs(FindAllOf("Actor") or {}) do
    if try(function() return a:IsValid() end) then
        nAct = nAct + 1
        local cn = cls(a); classOf[addr(a)] = cn
        bump(actClass, cn)
        local ticking = try(function() return a:IsActorTickEnabled() end) == true
        if ticking then nActTick = nActTick + 1; bump(actTick, cn) end
        for _, k in ipairs(KEY) do if cn:find(k) then bump(keyClass, cn); if ticking then bump(keyTick, cn) end; break end end
        if cn == "BP_RemoteAvatarCCC_C" then
            avatars = avatars + 1
            if mp then
                local l = a:K2_GetActorLocation(); local d = math.sqrt((l.X - mp.X) ^ 2 + (l.Y - mp.Y) ^ 2 + (l.Z - mp.Z) ^ 2)
                local b = #EDGES_M + 1
                for i, m in ipairs(EDGES_M) do if d <= m * 100 then b = i; break end end
                avNear[b] = avNear[b] + 1
            end
            if try(function() return a:WasRecentlyRendered(0.2) end) == true then avRendered = avRendered + 1 end
            local par = try(function() return a:GetAttachParentActor() end)
            if par and try(function() return par:IsValid() end) then bump(avMounted, cls(par)) end
        end
    end
end
local t1 = os.clock()

-- Components: class histogram, ticking, and the owners of ticking skeletal meshes.
local compClass, compTick, skOwner, skOwnerTick = {}, {}, {}, {}
local nComp, nCompTick, nSk, nSkTick = 0, 0, 0, 0
for _, c in ipairs(FindAllOf("ActorComponent") or {}) do
    nComp = nComp + 1
    local cn = cls(c); bump(compClass, cn)
    local ticking = try(function() return c:IsComponentTickEnabled() end) == true
    if ticking then nCompTick = nCompTick + 1; bump(compTick, cn) end
    if cn:find("^SkeletalMeshComponent") then
        nSk = nSk + 1
        local o = try(function() return c:GetOwner() end)
        local on = o and classOf[addr(o)] or "?"
        bump(skOwner, on)
        if ticking then nSkTick = nSkTick + 1; bump(skOwnerTick, on) end
    end
end
local t2 = os.clock()

log(string.format("BEGIN actors=%d (ticking %d) components=%d (ticking %d) skeletal meshes=%d (ticking %d)", nAct, nActTick, nComp, nCompTick, nSk, nSkTick))
local dist, lo = {}, 0
for i, m in ipairs(EDGES_M) do table.insert(dist, string.format("%d-%dm %d", lo, m, avNear[i])); lo = m end
table.insert(dist, string.format(">%dm %d", lo, avNear[#EDGES_M + 1]))
log(string.format("remote avatars=%d rendered=%d | by distance from the local character: %s", avatars, avRendered, table.concat(dist, ", ")))
log("remote avatars attached to (parent actor class): " .. top(avMounted, 20))
log("ticking actor classes, count: " .. top(actTick, 60))
log("actor classes, count(ticking): " .. top(actClass, 60, actTick))
log("keyword actor classes, count(ticking): " .. top(keyClass, 60, keyTick))
log("ticking component classes, count: " .. top(compTick, 60))
log("component classes, count(ticking): " .. top(compClass, 50, compTick))
log("skeletal mesh owners, count(ticking): " .. top(skOwner, 40, skOwnerTick))
log(string.format("END time actors %.2fs components %.2fs", t1 - t0, t2 - t1))
