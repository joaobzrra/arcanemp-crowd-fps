-- Offline test of CrowdFix's logic against a fake Unreal / UE4SS API (no game needed).
-- Run: lua crowdfix_mock_test.lua <path to CrowdFix\Scripts\main.lua> <empty scratch folder> [async]
-- ("async" = pretend the engine lacks LoopInGameThreadWithDelay, to test the LoopAsync fallback)
-- It checks the sleep step (sleepdistance): who sleeps, what is switched off, waking with the 90% edge,
-- switching the mod off, and a player that despawns while asleep.
local MAIN, TMP = arg[1], arg[2]
assert(MAIN and TMP, "usage: lua crowdfix_mock_test.lua <main.lua> <scratch folder>")
local SEP = package.config:sub(1, 1)

-- ---- fake engine ---------------------------------------------------------------------------------------------
local now = 0
os.clock = function() now = now + 0.0005; return now end   -- every call costs half a millisecond of fake time
local nextAddr = 1000
local Obj = {}
Obj.__index = Obj
local function new(cls, fields)
    nextAddr = nextAddr + 8
    local o = setmetatable({ cls = cls, addr = nextAddr, valid = true, tick = false, interval = 0, bHiddenInGame = false }, Obj)
    for k, v in pairs(fields or {}) do o[k] = v end
    return o
end
function Obj:IsValid() return self.valid end
function Obj:GetAddress() return self.addr end
function Obj:GetOwner() return self.owner end
function Obj:GetAttachParentActor() return self.parent end
function Obj:K2_GetActorLocation() return { X = self.x or 0, Y = 0, Z = 0 } end
function Obj:IsActorTickEnabled() return self.tick end
function Obj:SetActorTickEnabled(v) self.tick = v end
function Obj:SetHiddenInGame(v) self.bHiddenInGame = v end
function Obj:IsComponentTickEnabled() return self.tick end
function Obj:SetComponentTickEnabled(v) self.tick = v end
function Obj:GetComponentTickInterval() return self.interval end
function Obj:SetComponentTickInterval(v) self.interval = v end
function Obj:SetCastShadow(v) self.CastShadow = v end
function Obj:ExecuteConsoleCommand() end

local world = { BP_RemoteAvatarCCC_C = {}, SkeletalMeshComponent = {}, SkeletalMeshComponentBudgeted = {},
                Biped_MovementComponent = {}, AblAbilityComponent = {}, PhoenixManagedCharacter = {}, FacialComponent = {} }
local player = new("BP_Biped_Player_C", { x = 0 })
local function comp(cls, owner, ticking)
    local c = new(cls, { owner = owner, tick = ticking })
    table.insert(world[cls], c)
    return c
end
local function avatar(meters, mounted)
    local av = new("BP_RemoteAvatarCCC_C", { x = meters * 100, tick = true })
    av.Mesh = comp("SkeletalMeshComponentBudgeted", av, true)          -- body
    av.Mesh.bEnableUpdateRateOptimizations = false
    av.robe = comp("SkeletalMeshComponent", av, true)                  -- a follower that ticks
    av.shoes = comp("SkeletalMeshComponent", av, false)                -- a follower that never ticks
    av.move = comp("Biped_MovementComponent", av, true)
    av.ability = comp("AblAbilityComponent", av, true)
    av.wand = new("BP_CustomizableWand_C", { parent = av })
    av.wandMesh = comp("SkeletalMeshComponent", av.wand, true)
    if mounted then
        av.broom = new("BP_FlyingBroomCapsule_House_C", {}); av.parent = av.broom
        av.broomMesh = comp("SkeletalMeshComponent", av.broom, true)
    end
    table.insert(world.BP_RemoteAvatarCCC_C, av)
    return av
end
local A, B, C, D = avatar(10), avatar(60), avatar(150), avatar(250, true)
local E = avatar(80)   -- loses every mesh later while it stays loaded
local F = avatar(70)   -- becomes a shell later: its components stay valid but no longer belong to it
local npcMesh = comp("SkeletalMeshComponent", new("BP_Student_C", {}), true)   -- not a player: must never change
local gameHidden = comp("SkeletalMeshComponent", C, false); gameHidden.bHiddenInGame = true   -- hidden by the game, not by the mod

local meshWalks = 0   -- how often the mod asked for every skeletal mesh of the world
function FindAllOf(cls)
    if cls == "SkeletalMeshComponent" then meshWalks = meshWalks + 1 end
    local out = {}; for _, o in ipairs(world[cls] or {}) do if o.valid then table.insert(out, o) end end; return out
end
function FindFirstOf(cls) if cls == "BP_Biped_Player_C" then return player end; return new(cls, {}) end
function StaticFindObject() return new("KismetSystemLibrary", {}) end
-- The mod must take the game-thread timer when the engine offers it (arg 3 = "async" hides it, to test the fallback).
local step, timerUsed
function ExecuteInGameThread(f) f() end
function LoopAsync(_, f) step, timerUsed = f, "LoopAsync" end
if arg[3] ~= "async" then function LoopInGameThreadWithDelay(_, f) step, timerUsed = f, "LoopInGameThreadWithDelay" end end
local realPrint, logLines = print, {}
print = function(s) table.insert(logLines, (s:gsub("\n$", ""))) end

-- ---- the mod under test ----------------------------------------------------------------------------------------
local modDir = TMP .. SEP .. "CrowdFix"
os.execute((SEP == "\\" and 'mkdir "' or 'mkdir -p "') .. modDir .. SEP .. 'Scripts" 2>' .. (SEP == "\\" and "nul" or "/dev/null"))
local src = assert(io.open(MAIN, "rb")):read("a")
local f = assert(io.open(modDir .. SEP .. "Scripts" .. SEP .. "main.lua", "wb")); f:write(src); f:close()
local function settings(t)
    local s = assert(io.open(modDir .. SEP .. "settings.txt", "w"))
    for k, v in pairs(t) do s:write(k .. "=" .. v .. "\n") end
    s:close()
end
local function run(seconds) for _ = 1, seconds * 4 do now = now + 0.25; step() end end

local failed = 0
local function check(name, cond)
    if not cond then failed = failed + 1 end
    realPrint((cond and "ok   " or "FAIL ") .. name)
end
local function shown(av) return not (av.Mesh.bHiddenInGame or av.robe.bHiddenInGame or av.shoes.bHiddenInGame or av.wandMesh.bHiddenInGame) end
local function hidden(av) return av.Mesh.bHiddenInGame and av.robe.bHiddenInGame and av.shoes.bHiddenInGame and av.wandMesh.bHiddenInGame end
local function awake(av) return av.tick and shown(av) and av.Mesh.tick and av.robe.tick and av.move.tick and av.ability.tick and av.wandMesh.tick end
local function sleeping(av) return (not av.tick) and hidden(av) and not av.Mesh.tick and not av.robe.tick and not av.move.tick and not av.ability.tick and not av.wandMesh.tick end

settings({ enabled = 1, distance = 2500, interpolate = 1, animrate = 2, fardistance = 5000, farinterval = 0.2, sleepdistance = 20000 })
dofile(modDir .. SEP .. "Scripts" .. SEP .. "main.lua")
assert(step, "the mod did not register its loop")
check("timer: " .. timerUsed, timerUsed == (arg[3] == "async" and "LoopAsync" or "LoopInGameThreadWithDelay"))

run(30)
check("200 m: the 250 m player sleeps (every mesh hidden, every tick off, wand too)", sleeping(D))
check("200 m: its broom is hidden and not ticking", D.broomMesh.bHiddenInGame == true and D.broomMesh.tick == false)
check("200 m: a mesh that never ticked stays off and is not touched", D.shoes.tick == false)
check("200 m: the 150 m player is awake", awake(C))
check("200 m: the 150 m player animates at the far interval", C.Mesh.interval == 0.2 and C.robe.interval == 0.2)
check("200 m: the 60 m player is awake with URO and the far interval", awake(B) and B.Mesh.bEnableUpdateRateOptimizations == true and B.robe.interval == 0.2)
check("200 m: the 10 m player is untouched", awake(A) and A.Mesh.interval == 0 and A.Mesh.bEnableUpdateRateOptimizations == false)
check("an NPC mesh is untouched", npcMesh.tick == true and npcMesh.interval == 0 and npcMesh.bHiddenInGame == false)

D.x = 18500; run(15)
check("edge: at 185 m a sleeping player stays asleep (wakes only inside 180 m)", sleeping(D))
D.x = 17000; run(15)
check("wake: at 170 m the player is awake and visible again", awake(D))
check("wake: the broom is visible and ticking again", D.broomMesh.bHiddenInGame == false and D.broomMesh.tick == true)
check("wake: the never-ticking mesh was not switched on", D.shoes.tick == false)
D.x = 19000; run(15)
check("edge: at 190 m an awake player stays awake", awake(D))
D.x = 25000

settings({ enabled = 1, distance = 2500, interpolate = 1, animrate = 2, fardistance = 5000, farinterval = 0.2, sleepdistance = 10000 })
run(30)
check("100 m: the 150 m and 250 m players sleep", sleeping(C) and sleeping(D))
check("100 m: the 60 m player is awake", awake(B))

-- A player that changes clothes while asleep: the new mesh ticks until the next map, then it is switched off too.
local newHat = comp("SkeletalMeshComponent", C, true)
run(30)
check("asleep: a mesh added later is switched off and hidden after the next map", newHat.tick == false and newHat.bHiddenInGame == true)

-- A player that despawns while asleep must not leave its broom hidden.
D.valid = false; D.Mesh.valid = false; D.robe.valid = false; D.shoes.valid = false; D.move.valid = false; D.ability.valid = false
run(30)
check("despawn while asleep: the broom is visible and ticking again", D.broomMesh.bHiddenInGame == false and D.broomMesh.tick == true)

-- A far player whose meshes all vanish while it stays loaded (seen live: avatars without a body).
check("80 m: the player animates at the far interval before losing its meshes", E.robe.interval == 0.2)
for _, c in ipairs({ E.Mesh, E.robe, E.shoes, E.move, E.ability, E.wandMesh }) do c.valid = false end
for _, c in ipairs({ F.Mesh, F.robe, F.shoes, F.move, F.ability }) do c.owner = nil end
run(30)
-- Seen on the test server: the client keeps bodiless avatar shells of players that left. They must not be counted.
local lastStatus
for _, l in ipairs(logLines) do if l:find("players near=", 1, true) then lastStatus = l end end
local nNear, nFar = lastStatus:match("players near=(%d+) far=(%d+)")
check("player shells (no body, or a body that no longer belongs to them) are not counted (near + far = 3)", tonumber(nNear) + tonumber(nFar) == 3)

settings({ enabled = 0, distance = 2500, interpolate = 1, animrate = 2, fardistance = 5000, farinterval = 0.2, sleepdistance = 10000 })
run(30)
check("off: everybody is awake and visible", awake(A) and awake(B) and awake(C) and newHat.tick == true and newHat.bHiddenInGame == false)
check("off: a mesh the game itself had hidden stays hidden", gameHidden.bHiddenInGame == true)
check("off: intervals and URO are back", B.robe.interval == 0 and C.Mesh.interval == 0 and B.Mesh.bEnableUpdateRateOptimizations == false)
local walks = meshWalks
run(60)
check("off: the mod stops walking the world's meshes", meshWalks == walks)

local errors = 0
for _, l in ipairs(logLines) do if l:find("error", 1, true) then errors = errors + 1; realPrint("LOG " .. l) end end
check("the mod logged no error", errors == 0)
local slowest = 0
for _, l in ipairs(logLines) do local ms = l:match("slowestStep=([%d.]+)ms"); if ms and tonumber(ms) > slowest then slowest = tonumber(ms) end end
realPrint(string.format("slowest step in fake time: %.1f ms (every engine call costs 0.5 ms here)", slowest))
realPrint(failed == 0 and "ALL PASSED" or (failed .. " FAILED"))
os.exit(failed == 0 and 0 or 1)
