-- CrowdInv (UE4SS Lua): READ-ONLY. It never sets a property, calls a setter or runs a console command.
-- Commands, one word per line in Mods\CrowdInv\cmd.txt (read every second, then deleted):
--   inventory -> Scripts\inventory_ro.lua        (what each remote avatar is made of; tag [CrowdInv])
--   world     -> Scripts\inventory_world_ro.lua  (everything alive and ticking in the world; tag [CrowdWorld])
-- It also logs the frame rate every 5 s (tag [CrowdFps]) from the engine's frame counter.
local TAG = "[CrowdInv] "
local DIR = debug.getinfo(1, "S").source:match("@?(.*[\\/])Scripts[\\/]") or ""
local function log(s) print(TAG .. s .. "\n") end
local SCRIPTS = { inventory = "inventory_ro.lua", world = "inventory_world_ro.lua" }

-- The timers fire on the game thread. LoopAsync runs its callback on UE4SS's async thread, which shares this Lua
-- state with the game-thread callbacks; two of them running at the same moment crashed the game on 2026-11-24.
local function everyMs(ms, fn)
    if LoopInGameThreadWithDelay then LoopInGameThreadWithDelay(ms, fn)
    else LoopAsync(ms, function() ExecuteInGameThread(fn); return false end) end
end

everyMs(1000, function()
    local f = io.open(DIR .. "cmd.txt", "r")
    if f then
        local lines = {}
        for l in f:lines() do l = l:gsub("%s+", ""); if l ~= "" then table.insert(lines, l) end end
        f:close(); os.remove(DIR .. "cmd.txt")
        for _, l in ipairs(lines) do
            local file = SCRIPTS[l]
            if file then
                local ok, e = pcall(dofile, DIR .. "Scripts\\" .. file)
                if not ok then log(l .. " failed: " .. tostring(e)) end
            else
                log("unknown command: " .. l)
            end
        end
    end
end)

-- Frame rate: frames counted by the engine between two reads, over the wall-clock time between them.
local lastFrames, lastClock, fpsBroken = nil, nil, false
everyMs(5000, function()
    if fpsBroken then return end
    local ok, frames = pcall(function()
        return StaticFindObject("/Script/Engine.Default__KismetSystemLibrary"):GetFrameCount()
    end)
    if not ok or type(frames) ~= "number" then
        fpsBroken = true; print("[CrowdFps] frame counter not available: " .. tostring(frames) .. "\n"); return
    end
    local now = os.clock()
    if lastFrames and now > lastClock then
        print(string.format("[CrowdFps] fps %.1f frames %d dt %.2f\n", (frames - lastFrames) / (now - lastClock), frames - lastFrames, now - lastClock))
    end
    lastFrames, lastClock = frames, now
end)
log("loaded (read-only, " .. (LoopInGameThreadWithDelay and "game-thread timer" or "async timer") .. ")")
