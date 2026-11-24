-- Run with CrowdDiag: `lua diag_rendered.lua`. For the 6 remote avatars nearest to the local player, logs the
-- engine's "recently rendered" answer for the actor and for each of its skeletal meshes, plus each mesh's
-- VisibilityBasedAnimTickOption. Shows which meshes of a visible character the engine treats as not rendered.
local TAG = "[CrowdDiag] rendered: "
local function log(s) print(TAG .. s .. "\n") end
local function try(f) local ok, v = pcall(f); if ok then return v end; return "ERR" end
local function addr(o) local ok, a = pcall(function() return o:GetAddress() end); return ok and a or tostring(o) end

local me = FindFirstOf("BP_Biped_Player_C")
if not (me and me:IsValid()) then log("no local player"); return end
local p = me:K2_GetActorLocation()

local list = {}
for _, av in ipairs(FindAllOf("BP_RemoteAvatarCCC_C") or {}) do
    if av:IsValid() then
        local l = av:K2_GetActorLocation()
        table.insert(list, { av = av, d = math.sqrt((l.X - p.X) ^ 2 + (l.Y - p.Y) ^ 2 + (l.Z - p.Z) ^ 2) })
    end
end
table.sort(list, function(a, b) return a.d < b.d end)

local byOwner = {}
for _, cls in ipairs({ "SkeletalMeshComponent", "SkeletalMeshComponentBudgeted" }) do
    for _, c in ipairs(FindAllOf(cls) or {}) do
        if c:IsValid() then
            local ok, o = pcall(function() return c:GetOwner() end)
            if ok and o and o:IsValid() then local k = addr(o); byOwner[k] = byOwner[k] or {}; byOwner[k][addr(c)] = c end
        end
    end
end

local totals = { avatars = 0, actorRendered = 0, meshes = 0, meshRendered = 0 }
for i, e in ipairs(list) do
    local av = e.av
    local actorR = try(function() return av:WasRecentlyRendered(0.2) end)
    totals.avatars = totals.avatars + 1
    if actorR == true then totals.actorRendered = totals.actorRendered + 1 end
    local parts = {}
    for _, c in pairs(byOwner[addr(av)] or {}) do
        local name = try(function() return c:GetFullName() end)
        name = type(name) == "string" and (name:match("%.([%w_]+)$") or name) or "?"
        local r = try(function() return c:WasRecentlyRendered(0.2) end)
        totals.meshes = totals.meshes + 1
        if r == true then totals.meshRendered = totals.meshRendered + 1 end
        if i <= 6 then
            table.insert(parts, string.format("%s=%s(vis%s,hidden=%s)", name, tostring(r),
                tostring(try(function() return c.VisibilityBasedAnimTickOption end)),
                tostring(try(function() return c.bHiddenInGame end))))
        end
    end
    if i <= 6 then
        table.sort(parts)
        log(string.format("#%d at %.0f cm actor=%s | %s", i, e.d, tostring(actorR), table.concat(parts, " ")))
    end
end
log(string.format("totals: avatars=%d actorRendered=%d meshes=%d meshRendered=%d",
    totals.avatars, totals.actorRendered, totals.meshes, totals.meshRendered))
