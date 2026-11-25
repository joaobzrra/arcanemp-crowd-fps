-- READ-ONLY probe: which cheap read tells an empty avatar shell (a player that left) from a live avatar?
-- Totals per signal over every BP_RemoteAvatarCCC_C. Tag [ShellProbe].
local function tally(t, k) t[k] = (t[k] or 0) + 1 end
local function show(t) local p = {}; for k, n in pairs(t) do table.insert(p, tostring(k) .. "=" .. n) end; table.sort(p); return table.concat(p, " ") end
local n, destroying, bodyValid, atOrigin, tickOn, rootValid, hiddenBody = 0, {}, {}, {}, {}, {}, {}
for _, av in ipairs(FindAllOf("BP_RemoteAvatarCCC_C") or {}) do
    if av:IsValid() then
        n = n + 1
        local ok, v = pcall(function() return av:IsActorBeingDestroyed() end); tally(destroying, ok and tostring(v) or "ERR")
        local body = av.Mesh
        tally(bodyValid, tostring(body ~= nil and body:IsValid()))
        local l = av:K2_GetActorLocation()
        tally(atOrigin, tostring(math.abs(l.X) < 1 and math.abs(l.Y) < 1 and math.abs(l.Z) < 1))
        local okT, t = pcall(function() return av:IsActorTickEnabled() end); tally(tickOn, okT and tostring(t) or "ERR")
        local okR, r = pcall(function() local c = av.RootComponent; return c ~= nil and c:IsValid() end); tally(rootValid, okR and tostring(r) or "ERR")
        local okO, o = pcall(function() return body:GetOwner():GetAddress() == av:GetAddress() end); tally(hiddenBody, okO and tostring(o) or "ERR")
    end
end
print(string.format("[ShellProbe] avatars=%d | IsActorBeingDestroyed: %s | body valid: %s | at world origin: %s | actor tick: %s | root valid: %s | body owned by this avatar: %s\n",
    n, show(destroying), show(bodyValid), show(atOrigin), show(tickOn), show(rootValid), show(hiddenBody)))
