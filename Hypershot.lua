local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")

local TeleportCheck = false
local queueTeleport = syn and syn.queue_on_teleport or queue_on_teleport
local function executeScript()
    if UserInputService.TouchEnabled then
        loadstring(game:HttpGet('https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/Games/HyperShotMobiles.lua'))()
    else
        loadstring(game:HttpGet('https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/Games/HypershotPc.lua'))()
    end
end

executeScript()

LocalPlayer.OnTeleport:Connect(function(State)
    if not TeleportCheck and queueTeleport then
        TeleportCheck = true
        if UserInputService.TouchEnabled then
            queueTeleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/Games/HyperShotMobiles.lua'))()")
        else
            queueTeleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/Games/HypershotPc.lua'))()")
        end
    end
end)

TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage)
    if player == LocalPlayer and queueTeleport then
        if UserInputService.TouchEnabled then
            queueTeleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/Games/HyperShotMobile.lua'))()")
        else
            queueTeleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/Games/HypershotPc.lua'))()")
        end
    end
end)
