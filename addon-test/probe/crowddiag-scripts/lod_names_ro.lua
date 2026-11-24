-- READ-ONLY. Lists the real property and function names that mention LOD on the skeletal mesh component
-- classes and on the skeletal mesh asset class, so later scripts use names read from the game, not guessed.
local TAG = "[CrowdLod] "
local function log(s) print(TAG .. s .. "\n") end
local function try(f) local ok, v = pcall(f); if ok then return v end; return nil end

local function names(struct, label)
    local depth = 0
    while struct and try(function() return struct:IsValid() end) and depth < 12 do
        local sn = try(function() return struct:GetFName():ToString() end) or "?"
        local props, funcs = {}, {}
        local okP, eP = pcall(function()
            struct:ForEachProperty(function(p)
                local n = p:GetFName():ToString()
                if n:find("LOD") or n:find("Lod") then table.insert(props, n) end
            end)
        end)
        local okF, eF = pcall(function()
            struct:ForEachFunction(function(f)
                local n = f:GetFName():ToString()
                if n:find("LOD") or n:find("Lod") then table.insert(funcs, n) end
            end)
        end)
        log(string.format("%s > %s | props: %s%s | funcs: %s%s", label, sn, table.concat(props, " "), okP and "" or (" ERR " .. tostring(eP)),
            table.concat(funcs, " "), okF and "" or (" ERR " .. tostring(eF))))
        struct = try(function() return struct:GetSuperStruct() end)
        depth = depth + 1
    end
end

local c = FindFirstOf("SkeletalMeshComponentBudgeted") or FindFirstOf("SkeletalMeshComponent")
if not (c and c:IsValid()) then log("no skeletal mesh component found"); return end
names(try(function() return c:GetClass() end), "component")
local mesh = try(function() return c.SkeletalMesh end)
if mesh and try(function() return mesh:IsValid() end) then
    names(try(function() return mesh:GetClass() end), "asset")
    log("asset LODInfo read: type " .. type(try(function() return mesh.LODInfo end)) .. ", length " .. tostring(try(function() return #mesh.LODInfo end)))
else
    log("component has no SkeletalMesh asset")
end
log("END")
