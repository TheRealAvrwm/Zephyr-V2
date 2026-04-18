-- Zephyr-V2 Loader
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer

local queueTeleport = (syn and syn.queue_on_teleport) or queue_on_teleport

local LOADER_URL = "https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/hypershotloader.lua"
local SCRIPT_URL = "https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/Games/hypershot.lua"

local UI_NAME = "ZephyrUI"
local function uiAlreadyLoaded()
    if CoreGui:FindFirstChild(UI_NAME) then return true end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if pg and pg:FindFirstChild(UI_NAME) then return true end
    return false
end

if uiAlreadyLoaded() then return end
if _G.ZephyrLoaded then return end
_G.ZephyrLoaded = true
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
