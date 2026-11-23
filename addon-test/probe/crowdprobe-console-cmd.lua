-- Runs console commands live through UKismetSystemLibrary::ExecuteConsoleCommand (triggered by diag.flag).
local TAG = "[CrowdCmd] "
local COMMANDS = { "a.URO.ForceInterpolation 1" }

return function()
    local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local pc = FindFirstOf("PlayerController")
    if not (ksl and ksl:IsValid()) then print(TAG .. "KismetSystemLibrary not found\n") return end
    if not (pc and pc:IsValid()) then print(TAG .. "PlayerController not found\n") return end
    for _, c in ipairs(COMMANDS) do
        local ok, e = pcall(function() ksl:ExecuteConsoleCommand(pc, c, pc) end)
        print(TAG .. c .. " -> " .. (ok and "ok" or ("ERR " .. tostring(e))) .. "\n")
    end
end
