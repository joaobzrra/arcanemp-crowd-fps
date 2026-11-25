-- CrowdDiag (UE4SS Lua, TEST CLIENT ONLY): inventory + ablation switches for remote avatars.
-- Commands: write lines to Mods\CrowdDiag\cmd.txt (read every second, then deleted). Output: UE4SS.log, tag [CrowdDiag].
--   inventory                     list every component of the nearest remote avatar with tick/anim/bounds/collision state
--   tick <followers|body|all8|actor|movement> <off|on>   SetComponentTickEnabled / SetActorTickEnabled on ALL avatars
--   noskel <followers|body|all8> <on|off>                bNoSkeletonUpdate on the meshes
--   overlap <off|on>              capsule SetGenerateOverlapEvents
--   restore                       put back every original value this mod changed
--   count                         read back how many meshes have tick enabled / bNoSkeletonUpdate (proves a switch took)
--   cvar <name>                   read a console variable (int and float) via KismetSystemLibrary
--   console <command...>          run a console command
--   vistick <followers|body|all8> <0-3>   VisibilityBasedAnimTickOption (0 always tick+refresh bones, 3 only when rendered)
--   uro <followers|body|all8> <on|off>    bEnableUpdateRateOptimizations
--   hidden <followers|body|all8> <on|off> SetHiddenInGame (render-side ablation: nothing of that group is drawn)
--   comptick <ClassName> <off|on>         SetComponentTickEnabled on every component of that class owned by a remote avatar
--   lua <file>                            run Scripts\<file> (dofile) in the game thread: new experiments without a restart
--   tickfar <meters> <off|on>             mesh ticks of avatars farther than <meters> from the local character
--   attachtick <off|on>                   mesh ticks of wands held by avatars and of mounts carrying avatars
-- "followers" = the avatar's skeletal meshes other than avatar.Mesh (the body, CharacterMesh0).
-- Untested as of 2026-11-23: every call is wrapped in pcall and logs its error, so a missing function shows up as ERR.
local TAG = "[CrowdDiag] "
local DIR = debug.getinfo(1, "S").source:match("@?(.*[\\/])Scripts[\\/]") or ""
local function log(s) print(TAG .. s .. "\n") end
local function key(o) local ok, a = pcall(function() return o:GetAddress() end); return ok and a or tostring(o) end
local function try(f) local ok, v = pcall(f); if ok then return v end; return "ERR " .. tostring(v) end
local function s(v) if v == nil then return "nil" end; if type(v) == "userdata" then return try(function() return v:IsValid() and v:GetFullName() or "invalid" end) end; return tostring(v) end

local orig = {}   -- "addr|what" -> { obj, what, value }
local function remember(obj, what, value) local k = key(obj) .. "|" .. what; if orig[k] == nil then orig[k] = { obj = obj, what = what, value = value } end end

local function avatars() return FindAllOf("BP_RemoteAvatarCCC_C") or {} end
local function meshesByOwner()
    local by, seen = {}, {}
    for _, cls in ipairs({ "SkeletalMeshComponent", "SkeletalMeshComponentBudgeted" }) do
        for _, c in ipairs(FindAllOf(cls) or {}) do
            local ck = key(c)
            if not seen[ck] and c:IsValid() then
                seen[ck] = true
                local ok, o = pcall(function() return c:GetOwner() end)
                if ok and o and o:IsValid() then local k = key(o); by[k] = by[k] or {}; table.insert(by[k], c) end
            end
        end
    end
    return by
end
local function groupMeshes(av, by, group)
    local out, body = {}, av.Mesh
    local bk = (body and body:IsValid()) and key(body) or nil
    for _, c in ipairs(by[key(av)] or {}) do
        local isBody = key(c) == bk
        if group == "all8" or (group == "body" and isBody) or (group == "followers" and not isBody) then table.insert(out, c) end
    end
    return out
end

local function inventory()
    local me = FindFirstOf("BP_Biped_Player_C")
    if not (me and me:IsValid()) then log("no local player"); return end
    local p = me:K2_GetActorLocation()
    local best, bd = nil, math.huge
    for _, av in ipairs(avatars()) do
        if av:IsValid() then
            local l = av:K2_GetActorLocation(); local d = (l.X - p.X) ^ 2 + (l.Y - p.Y) ^ 2 + (l.Z - p.Z) ^ 2
            if d < bd then best, bd = av, d end
        end
    end
    if not best then log("no remote avatars"); return end
    log(string.format("inventory of %s at %.0f cm; actor tick=%s", s(best), math.sqrt(bd), s(try(function() return best:IsActorTickEnabled() end))))
    local bk = key(best)
    local n = 0
    for _, c in ipairs(FindAllOf("ActorComponent") or {}) do
        local ok, o = pcall(function() return c:GetOwner() end)
        if ok and o and o:IsValid() and key(o) == bk then
            n = n + 1
            log(string.format("  %s | tick=%s interval=%s", s(c), s(try(function() return c:IsComponentTickEnabled() end)),
                s(try(function() return c:GetComponentTickInterval() end))))
            local isMesh = s(c):find("^SkeletalMeshComponent") ~= nil
            if isMesh then
                log(string.format("    master=%s anim=%s postAnim=%s disablePost=%s uro=%s visTick=%s noSkel=%s pause=%s",
                    s(try(function() local m = c.MasterPoseComponent; local ok, o = pcall(function() return m:Get() end); if ok then return o end; return "weakptr type " .. type(m) .. " (no Get)" end)), s(try(function() return c:GetAnimInstance() end)),
                    s(try(function() return c:GetPostProcessInstance() end)), s(try(function() return c.bDisablePostProcessBlueprint end)),
                    s(try(function() return c.bEnableUpdateRateOptimizations end)), s(try(function() return c.VisibilityBasedAnimTickOption end)),
                    s(try(function() return c.bNoSkeletonUpdate end)), s(try(function() return c.bPauseAnims end))))
                log(string.format("    fixedBounds=%s boundsFromMaster=%s kinematic=%s overlaps=%s collision=%s castShadow=%s forcedLOD=%s minLOD=%s budgetAuto=%s",
                    s(try(function() return c.bComponentUseFixedSkelBounds end)), s(try(function() return c.bUseBoundsFromMasterPoseComponent end)),
                    s(try(function() return c.KinematicBonesUpdateType end)), s(try(function() return c:GetGenerateOverlapEvents() end)),
                    s(try(function() return c:GetCollisionEnabled() end)), s(try(function() return c.CastShadow end)),
                    s(try(function() return c.ForcedLodModel end)), s(try(function() return c.MinLodModel end)),
                    s(try(function() return c.bAutoRegisterWithBudgetAllocator end))))
            end
        end
    end
    log("inventory done: " .. n .. " components")
end

local function setTick(group, on)
    local by = (group == "followers" or group == "body" or group == "all8") and meshesByOwner() or nil
    local n, err = 0, nil
    for _, av in ipairs(avatars()) do
        if av:IsValid() then
            local targets = {}
            if by then targets = groupMeshes(av, by, group)
            elseif group == "movement" then local m = av.CharacterMovement; if m and m:IsValid() then targets = { m } end end
            if group == "actor" then
                remember(av, "actortick", try(function() return av:IsActorTickEnabled() end))
                local ok, e = pcall(function() av:SetActorTickEnabled(on) end); if ok then n = n + 1 else err = e end
            end
            for _, c in ipairs(targets) do
                remember(c, "tick", try(function() return c:IsComponentTickEnabled() end))
                local ok, e = pcall(function() c:SetComponentTickEnabled(on) end); if ok then n = n + 1 else err = e end
            end
        end
    end
    log(string.format("tick %s %s: %d objects%s", group, on and "on" or "off", n, err and (" ERR " .. tostring(err)) or ""))
end

local function setNoSkel(group, on)
    local by, n = meshesByOwner(), 0
    for _, av in ipairs(avatars()) do
        if av:IsValid() then
            for _, c in ipairs(groupMeshes(av, by, group)) do
                remember(c, "noskel", try(function() return c.bNoSkeletonUpdate end))
                if pcall(function() c.bNoSkeletonUpdate = on end) then n = n + 1 end
            end
        end
    end
    log(string.format("noskel %s %s: %d meshes", group, on and "on" or "off", n))
end

local function setOverlap(on)
    local n = 0
    for _, av in ipairs(avatars()) do
        local cap = av:IsValid() and av.CapsuleComponent or nil
        if cap and cap:IsValid() then
            remember(cap, "overlap", try(function() return cap:GetGenerateOverlapEvents() end))
            if pcall(function() cap:SetGenerateOverlapEvents(on) end) then n = n + 1 end
        end
    end
    log(string.format("overlap %s: %d capsules", on and "on" or "off", n))
end

local function setProp(group, prop, value)
    local by, n, err = meshesByOwner(), 0, nil
    for _, av in ipairs(avatars()) do
        if av:IsValid() then
            for _, c in ipairs(groupMeshes(av, by, group)) do
                remember(c, "prop:" .. prop, try(function() return c[prop] end))
                local ok, e = pcall(function() c[prop] = value end); if ok then n = n + 1 else err = e end
            end
        end
    end
    log(string.format("%s %s = %s: %d meshes%s", prop, group, tostring(value), n, err and (" ERR " .. tostring(err)) or ""))
end

local function setHidden(group, on)
    local by, n, err = meshesByOwner(), 0, nil
    for _, av in ipairs(avatars()) do
        if av:IsValid() then
            for _, c in ipairs(groupMeshes(av, by, group)) do
                remember(c, "hidden", try(function() return c.bHiddenInGame end))
                local ok, e = pcall(function() c:SetHiddenInGame(on, false) end); if ok then n = n + 1 else err = e end
            end
        end
    end
    log(string.format("hidden %s %s: %d meshes%s", group, on and "on" or "off", n, err and (" ERR " .. tostring(err)) or ""))
end

local function setCompTick(cls, on)
    local n, total, err = 0, 0, nil
    for _, c in ipairs(FindAllOf(cls) or {}) do
        local ok, o = pcall(function() return c:GetOwner() end)
        if ok and o and o:IsValid() and s(o):find("^BP_RemoteAvatarCCC_C") then
            total = total + 1
            remember(c, "tick", try(function() return c:IsComponentTickEnabled() end))
            local ok2, e = pcall(function() c:SetComponentTickEnabled(on) end); if ok2 then n = n + 1 else err = e end
        end
    end
    local still = 0
    for _, c in ipairs(FindAllOf(cls) or {}) do
        local ok, o = pcall(function() return c:GetOwner() end)
        if ok and o and o:IsValid() and s(o):find("^BP_RemoteAvatarCCC_C") and try(function() return c:IsComponentTickEnabled() end) == true then still = still + 1 end
    end
    log(string.format("comptick %s %s: %d of %d set, readback ticking=%d%s", cls, on and "on" or "off", n, total, still, err and (" ERR " .. tostring(err)) or ""))
end

-- Mesh ticks off only for avatars farther than <meters> from the local character (near ones keep animating).
local function setTickFar(meters, on)
    local me = FindFirstOf("BP_Biped_Player_C")
    if not (me and me:IsValid()) then log("tickfar: no local player"); return end
    local p, by, nAv, n, lim = me:K2_GetActorLocation(), meshesByOwner(), 0, 0, meters * 100
    for _, av in ipairs(avatars()) do
        if av:IsValid() then
            local l = av:K2_GetActorLocation()
            if math.sqrt((l.X - p.X) ^ 2 + (l.Y - p.Y) ^ 2 + (l.Z - p.Z) ^ 2) > lim then
                nAv = nAv + 1
                for _, c in ipairs(groupMeshes(av, by, "all8")) do
                    remember(c, "tick", try(function() return c:IsComponentTickEnabled() end))
                    if pcall(function() c:SetComponentTickEnabled(on) end) then n = n + 1 end
                end
            end
        end
    end
    log(string.format("tickfar >%dm %s: %d avatars, %d meshes", meters, on and "on" or "off", nAv, n))
end

-- Skeletal mesh ticks of actors attached to a remote avatar (wand) and of actors a remote avatar is attached to (mount).
local function setAttachTick(on)
    local isAv = {}
    for _, av in ipairs(avatars()) do if av:IsValid() then isAv[key(av)] = true end end
    local owners, nHeld, nMount = {}, 0, 0
    for _, a in ipairs(FindAllOf("Actor") or {}) do
        if try(function() return a:IsValid() end) == true then
            local par = try(function() return a:GetAttachParentActor() end)
            if type(par) == "userdata" and try(function() return par:IsValid() end) == true then
                if isAv[key(par)] then
                    if not owners[key(a)] then owners[key(a)] = true; nHeld = nHeld + 1 end
                elseif isAv[key(a)] then
                    if not owners[key(par)] then owners[key(par)] = true; nMount = nMount + 1 end
                end
            end
        end
    end
    local by, n = meshesByOwner(), 0
    for k in pairs(owners) do
        for _, c in ipairs(by[k] or {}) do
            remember(c, "tick", try(function() return c:IsComponentTickEnabled() end))
            if pcall(function() c:SetComponentTickEnabled(on) end) then n = n + 1 end
        end
    end
    log(string.format("attachtick %s: %d held actors, %d mounts, %d meshes", on and "on" or "off", nHeld, nMount, n))
end

local function restore()
    local n = 0
    for _, r in pairs(orig) do
        local o, v = r.obj, r.value
        if o and o:IsValid() and r.what:sub(1, 5) == "prop:" and type(v) ~= "string" then
            if pcall(function() o[r.what:sub(6)] = v end) then n = n + 1 end
        elseif o and o:IsValid() and type(v) == "boolean" then
            local ok = pcall(function()
                if r.what == "tick" then o:SetComponentTickEnabled(v)
                elseif r.what == "actortick" then o:SetActorTickEnabled(v)
                elseif r.what == "noskel" then o.bNoSkeletonUpdate = v
                elseif r.what == "hidden" then o:SetHiddenInGame(v, false)
                elseif r.what == "overlap" then o:SetGenerateOverlapEvents(v) end
            end)
            if ok then n = n + 1 end
        end
    end
    orig = {}
    log("restored " .. n .. " values")
end

local function count()
    local by = meshesByOwner()
    local c = { body = 0, bodyTick = 0, fol = 0, folTick = 0, noskel = 0, actorTick = 0, avatars = 0 }
    for _, av in ipairs(avatars()) do
        if av:IsValid() then
            c.avatars = c.avatars + 1
            if try(function() return av:IsActorTickEnabled() end) == true then c.actorTick = c.actorTick + 1 end
            for _, m in ipairs(groupMeshes(av, by, "body")) do c.body = c.body + 1; if try(function() return m:IsComponentTickEnabled() end) == true then c.bodyTick = c.bodyTick + 1 end; if try(function() return m.bNoSkeletonUpdate end) == true then c.noskel = c.noskel + 1 end end
            for _, m in ipairs(groupMeshes(av, by, "followers")) do c.fol = c.fol + 1; if try(function() return m:IsComponentTickEnabled() end) == true then c.folTick = c.folTick + 1 end; if try(function() return m.bNoSkeletonUpdate end) == true then c.noskel = c.noskel + 1 end end
        end
    end
    local uro, hid, vis, rendered = 0, 0, {}, 0
    for _, av in ipairs(avatars()) do
        if av:IsValid() then
            if try(function() return av:WasRecentlyRendered(0.2) end) == true then rendered = rendered + 1 end
            for _, m in ipairs(groupMeshes(av, by, "all8")) do
                if try(function() return m.bEnableUpdateRateOptimizations end) == true then uro = uro + 1 end
                if try(function() return m.bHiddenInGame end) == true then hid = hid + 1 end
                local v = tostring(try(function() return m.VisibilityBasedAnimTickOption end)); vis[v] = (vis[v] or 0) + 1
            end
        end
    end
    local vs = {}; for k, v in pairs(vis) do table.insert(vs, k .. "x" .. v) end; table.sort(vs)
    log(string.format("count: avatars=%d actorTick=%d body=%d bodyTick=%d followers=%d followersTick=%d noSkel=%d uro=%d hidden=%d rendered=%d visTick=%s",
        c.avatars, c.actorTick, c.body, c.bodyTick, c.fol, c.folTick, c.noskel, uro, hid, rendered, table.concat(vs, " ")))
end

local function ksl() local k = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary"); local pc = FindFirstOf("PlayerController"); return k, pc end
local function cvar(name)
    local k, pc = ksl()
    log(string.format("cvar %s int=%s float=%s", name, s(try(function() return k:GetConsoleVariableIntValue(name) end)),
        s(try(function() return k:GetConsoleVariableFloatValue(name) end))))
end
local function console(cmd)
    local k, pc = ksl()
    local ok, e = pcall(function() k:ExecuteConsoleCommand(pc, cmd, pc) end)
    log("console " .. cmd .. " -> " .. (ok and "ok" or ("ERR " .. tostring(e))))
end

local function run(line)
    local w = {}; for t in line:gmatch("%S+") do table.insert(w, t) end
    local c = w[1]
    if c == "inventory" then inventory()
    elseif c == "tick" then setTick(w[2], w[3] == "on")
    elseif c == "noskel" then setNoSkel(w[2], w[3] == "on")
    elseif c == "overlap" then setOverlap(w[2] == "on")
    elseif c == "restore" then restore()
    elseif c == "count" then count()
    elseif c == "cvar" then cvar(w[2])
    elseif c == "console" then console(line:sub(9))
    elseif c == "vistick" then setProp(w[2], "VisibilityBasedAnimTickOption", tonumber(w[3]))
    elseif c == "uro" then setProp(w[2], "bEnableUpdateRateOptimizations", w[3] == "on")
    elseif c == "hidden" then setHidden(w[2], w[3] == "on")
    elseif c == "comptick" then setCompTick(w[2], w[3] == "on")
    elseif c == "tickfar" then setTickFar(tonumber(w[2]) or 50, w[3] == "on")
    elseif c == "attachtick" then setAttachTick(w[2] == "on")
    elseif c == "lua" then local ok, e = pcall(dofile, DIR .. "Scripts\\" .. w[2]); log("lua " .. w[2] .. " -> " .. (ok and "ok" or ("ERR " .. tostring(e))))
    else log("unknown command: " .. line) end
end

-- The timer fires on the game thread. LoopAsync runs its callback on UE4SS's async thread, which shares this Lua
-- state with the game-thread callbacks; two of them running at the same moment crashed the game on 2026-11-24.
local function everyMs(ms, fn)
    if LoopInGameThreadWithDelay then LoopInGameThreadWithDelay(ms, fn)
    else LoopAsync(ms, function() ExecuteInGameThread(fn); return false end) end
end
everyMs(1000, function()
    local f = io.open(DIR .. "cmd.txt", "r")
    if f then
        local lines = {}; for l in f:lines() do l = l:gsub("^%s+", ""):gsub("%s+$", ""); if l ~= "" then table.insert(lines, l) end end
        f:close(); os.remove(DIR .. "cmd.txt")
        for _, l in ipairs(lines) do local ok, e = pcall(run, l); if not ok then log("error in '" .. l .. "': " .. tostring(e)) end end
    end
end)
log("loaded (" .. (LoopInGameThreadWithDelay and "game-thread timer" or "async timer") .. ")")
