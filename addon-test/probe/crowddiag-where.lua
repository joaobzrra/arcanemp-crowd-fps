-- Run with CrowdDiag: `lua diag_where.lua`. Logs the local player's position and facing (actor yaw) and the
-- camera's position and yaw, so a test crowd can be placed relative to where the tester stands and looks.
local function log(s) print("[CrowdDiag] where: " .. s .. "\n") end
local me = FindFirstOf("BP_Biped_Player_C")
if not (me and me:IsValid()) then log("no local player"); return end
local p, r = me:K2_GetActorLocation(), me:K2_GetActorRotation()
log(string.format("player pos %.1f %.1f %.1f yaw %.1f", p.X, p.Y, p.Z, r.Yaw))
local ok, err = pcall(function()
    local pc = FindFirstOf("PlayerController")
    local cam = pc.PlayerCameraManager
    local cp, cr = cam:GetCameraLocation(), cam:GetCameraRotation()
    log(string.format("camera pos %.1f %.1f %.1f yaw %.1f pitch %.1f", cp.X, cp.Y, cp.Z, cr.Yaw, cr.Pitch))
end)
if not ok then log("camera read failed: " .. tostring(err)) end
