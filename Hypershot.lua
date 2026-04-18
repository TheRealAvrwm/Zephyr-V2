-- Zephyr-V2 Loader
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer

local queueTeleport = (syn and syn.queue_on_teleport) or queue_on_teleport

local LOADER_URL = "https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/hypershotloader.lua"
local SCRIPT_URL = "https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/Games/hypershot.lua"
loadstring(game:HttpGet(SCRIPT_URL))()

local function queueLoader()
    if not queueTeleport then return end
    pcall(function()
        queueTeleport('loadstring(game:HttpGet("' .. LOADER_URL .. '"))()')
    end)
end

LocalPlayer.OnTeleport:Connect(function()
    queueLoader()
end)

TeleportService.TeleportInitFailed:Connect(function(player)
    if player == LocalPlayer then
        queueLoader()
    end
end)
