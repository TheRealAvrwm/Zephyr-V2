local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer
local unpackArgs = (type(table) == "table" and table.unpack) or unpack
if type(unpackArgs) ~= "function" then
    unpackArgs = function(t)
        return t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10]
    end
end

local existing = game:GetService("CoreGui"):FindFirstChild("ZephyrStratRecorder")
if existing then
    existing:Destroy()
end
local existingPG = LocalPlayer:FindFirstChild("PlayerGui")
    and LocalPlayer.PlayerGui:FindFirstChild("ZephyrStratRecorder")
if existingPG then
    existingPG:Destroy()
end

local Network = nil
local TroopsChannel = nil
local VotingChannel = nil
local TicketsChannel = nil
local ConsumablesChannel = nil
local oldTroopsInvoke = nil
local oldVotingInvoke = nil
local oldTicketsInvoke = nil
local oldTicketsFire = nil
local oldConsumablesFire = nil
local GameState = nil
local startupWarnings = {}
local logQueue = {}
local addLog
local recordTimeScaleValue
local getGameTimeScale
local macroClockConnection = nil
local RECORDER_BASE_W = 400
local RECORDER_BASE_H = 420
local RecorderScale = 1
local RecorderLogTextSize = 11

local function getRecorderViewport()
    local camera = workspace.CurrentCamera
    local size = camera and camera.ViewportSize
    if size and size.X > 0 and size.Y > 0 then
        return size
    end
    return Vector2.new(1280, 720)
end

local function computeRecorderScale()
    local viewport = getRecorderViewport()
    local scale = math.min(1, viewport.X / 470, viewport.Y / 500)
    if UserInputService.TouchEnabled then
        scale = math.min(scale, 0.48)
        if viewport.X < 900 or viewport.Y < 500 then
            scale = math.min(scale, 0.44)
        end
        if viewport.X < 700 or viewport.Y < 380 then
            scale = math.min(scale, 0.40)
        end
        return math.clamp(scale, 0.35, 1)
    end
    return math.clamp(scale, 0.58, 1)
end

local function rpx(value)
    return math.max(1, math.floor((tonumber(value) or 0) * RecorderScale + 0.5))
end

local function clampRecorderPosition(frame)
    if not frame then
        return
    end
    local viewport = getRecorderViewport()
    local width = frame.AbsoluteSize.X
    local height = frame.AbsoluteSize.Y
    if width <= 0 then
        width = rpx(RECORDER_BASE_W)
    end
    if height <= 0 then
        height = rpx(RECORDER_BASE_H)
    end
    local keepVisible = UserInputService.TouchEnabled and math.max(28, rpx(52)) or math.max(40, rpx(70))
    local x = frame.Position.X.Offset
    local y = frame.Position.Y.Offset
    if frame.Position.X.Scale ~= 0 then
        x = (viewport.X * frame.Position.X.Scale) + x
    end
    if frame.Position.Y.Scale ~= 0 then
        y = (viewport.Y * frame.Position.Y.Scale) + y
    end
    x = math.clamp(x, -width + keepVisible, viewport.X - keepVisible)
    y = math.clamp(y, -height + keepVisible, viewport.Y - keepVisible)
    frame.Position = UDim2.new(0, x, 0, y)
end

do
    local ok, result = pcall(function()
        local shared = ReplicatedStorage:FindFirstChild("Shared") or ReplicatedStorage:WaitForChild("Shared", 5)
        local modules = shared and (shared:FindFirstChild("Modules") or shared:WaitForChild("Modules", 5))
        local networkModule = modules and (modules:FindFirstChild("Network") or modules:WaitForChild("Network", 5))
        if not networkModule then
            error("Network module not found")
        end
        return require(networkModule)
    end)

    local channelOk, channelFn = false, nil
    if ok and type(result) == "table" then
        channelOk, channelFn = pcall(function()
            return result.Channel
        end)
    end

    if channelOk and type(channelFn) == "function" then
        Network = result
        local troopsOk, troops = pcall(function()
            return channelFn("Troops")
        end)
        local votingOk, voting = pcall(function()
            return channelFn("Voting")
        end)
        local ticketsOk, tickets = pcall(function()
            return channelFn("TicketsManager")
        end)
        local consumablesOk, consumables = pcall(function()
            return channelFn("Consumables")
        end)
        if troopsOk and troops then
            TroopsChannel = troops
            local invokeOk, invokeFn = pcall(function()
                return TroopsChannel.InvokeServer
            end)
            if invokeOk and type(invokeFn) == "function" then
                oldTroopsInvoke = invokeFn
            else
                TroopsChannel = nil
            end
        end
        if votingOk and voting then
            VotingChannel = voting
            local invokeOk, invokeFn = pcall(function()
                return VotingChannel.InvokeServer
            end)
            if invokeOk and type(invokeFn) == "function" then
                oldVotingInvoke = invokeFn
            else
                VotingChannel = nil
            end
        end
        if ticketsOk and tickets then
            TicketsChannel = tickets
            local invokeOk, invokeFn = pcall(function()
                return TicketsChannel.InvokeServer
            end)
            local fireOk, fireFn = pcall(function()
                return TicketsChannel.FireServer
            end)
            if invokeOk and type(invokeFn) == "function" then
                oldTicketsInvoke = invokeFn
            end
            if fireOk and type(fireFn) == "function" then
                oldTicketsFire = fireFn
            end
            if type(oldTicketsInvoke) ~= "function" and type(oldTicketsFire) ~= "function" then
                TicketsChannel = nil
            end
        end
        if consumablesOk and consumables then
            ConsumablesChannel = consumables
            local fireOk, fireFn = pcall(function()
                return ConsumablesChannel.FireServer
            end)
            if fireOk and type(fireFn) == "function" then
                oldConsumablesFire = fireFn
            else
                ConsumablesChannel = nil
            end
        end
    else
        table.insert(startupWarnings, "Network require unavailable; recording hooks may not work.")
    end
end

do
    local ok, result = pcall(function()
        local shared = ReplicatedStorage:FindFirstChild("Shared") or ReplicatedStorage:WaitForChild("Shared", 5)
        local modules = shared and (shared:FindFirstChild("Modules") or shared:WaitForChild("Modules", 5))
        local gameStateModule = modules
            and (modules:FindFirstChild("GameState") or modules:WaitForChild("GameState", 5))
        if not gameStateModule then
            error("GameState module not found")
        end
        return require(gameStateModule)
    end)
    if ok and type(result) == "table" then
        GameState = result
    else
        table.insert(startupWarnings, "GameState unavailable; recorder timing will use real time.")
    end
end

local function invokeRemoteFunction(...)
    local args = { ... }
    local remote = ReplicatedStorage:FindFirstChild("RemoteFunction")
        or ReplicatedStorage:WaitForChild("RemoteFunction", 2)
    if not remote then
        return false
    end
    local ok, result = pcall(function()
        return remote:InvokeServer(unpackArgs(args))
    end)
    return ok, result
end

local function fireRemoteEvent(...)
    local args = { ... }
    local remote = ReplicatedStorage:FindFirstChild("RemoteEvent") or ReplicatedStorage:WaitForChild("RemoteEvent", 2)
    if not remote then
        return false
    end
    local ok, result = pcall(function()
        return remote:FireServer(unpackArgs(args))
    end)
    return ok, result
end

local function invokeTroops(...)
    local args = { ... }
    if type(oldTroopsInvoke) == "function" and TroopsChannel then
        local ok, result = pcall(function()
            return oldTroopsInvoke(TroopsChannel, unpackArgs(args))
        end)
        if ok then
            return true, result
        end
    end
    return invokeRemoteFunction("Troops", unpackArgs(args))
end

local lastTroopsActionAt = 0
local TROOPS_ACTION_INTERVAL = 0.04
local troopsActionBusy = false

local function invokeTroopsThrottled(...)
    while troopsActionBusy do
        task.wait(0.01)
    end
    troopsActionBusy = true
    local elapsed = tick() - lastTroopsActionAt
    if elapsed < TROOPS_ACTION_INTERVAL then
        task.wait(TROOPS_ACTION_INTERVAL - elapsed)
    end
    lastTroopsActionAt = tick()
    local callOk, ok, result = pcall(invokeTroops, ...)
    troopsActionBusy = false
    if not callOk then
        return false, ok
    end
    return ok, result
end

local function voteSkip()
    if type(oldVotingInvoke) == "function" and VotingChannel then
        local ok, result = pcall(function()
            return oldVotingInvoke(VotingChannel, "Skip")
        end)
        if ok then
            return true, result
        end
    end
    return invokeRemoteFunction("Voting", "Skip")
end

local function fireConsumable(...)
    local args = { ... }
    if type(oldConsumablesFire) == "function" and ConsumablesChannel then
        local ok, result = pcall(function()
            return oldConsumablesFire(ConsumablesChannel, unpackArgs(args))
        end)
        if ok then
            return true, result
        end
    end
    return fireRemoteEvent("Consumables", unpackArgs(args))
end

local function isTimeScaleLocked()
    if not GameState then
        return false
    end
    local locked = false
    pcall(function()
        local state = GameState.State
        local value = state and state.TimeScaleLocked or GameState.TimeScaleLocked
        locked = value == true
    end)
    return locked
end

local function unlockTimeScale()
    if type(oldTicketsInvoke) == "function" and TicketsChannel then
        local ok, result = pcall(function()
            return oldTicketsInvoke(TicketsChannel, "UnlockTimeScale")
        end)
        if ok then
            return true, result
        end
    end
    return false, "TicketsManager unlock unavailable"
end

local function cycleTimeScale()
    if type(oldTicketsFire) == "function" and TicketsChannel then
        local ok, result = pcall(function()
            return oldTicketsFire(TicketsChannel, "CycleTimeScale")
        end)
        if ok then
            return true, result
        end
    end
    return false, "TicketsManager cycle unavailable"
end

local lastUnsafeTimeScaleWarnAt = 0
local function normalizePlaybackTimeScale(scale)
    scale = tonumber(scale) or 1
    if scale <= 0.05 then
        if tick() - lastUnsafeTimeScaleWarnAt > 2 then
            lastUnsafeTimeScaleWarnAt = tick()
            addLog("Timescale x0 ignored during playback so timing cannot freeze.", Color3.fromRGB(255, 180, 80))
        end
        return nil
    end
    if scale < 0.5 then
        return 0.5
    end
    if scale > 2 then
        return 2
    end
    return scale
end

local function doTimeScaleUnlock()
    if not isTimeScaleLocked() then
        return true
    end
    local ok, result = unlockTimeScale()
    if not ok then
        addLog("Timescale unlock failed: " .. tostring(result), Color3.fromRGB(255, 120, 90))
        return false
    end
    local start = tick()
    while tick() - start < 4 do
        if not isTimeScaleLocked() then
            return true
        end
        task.wait(0.1)
    end
    return not isTimeScaleLocked()
end

local function doTimeScale(action)
    local target = normalizePlaybackTimeScale(action and action.data and action.data.scale)
    if not target then
        return true
    end
    if isTimeScaleLocked() and not doTimeScaleUnlock() then
        return false
    end
    if math.abs(getGameTimeScale() - target) <= 0.05 then
        return true
    end
    for _ = 1, 6 do
        local ok, result = cycleTimeScale()
        if not ok then
            addLog("Timescale cycle failed: " .. tostring(result), Color3.fromRGB(255, 120, 90))
            return false
        end
        local start = tick()
        while tick() - start < 1.25 do
            if math.abs(getGameTimeScale() - target) <= 0.05 then
                return true
            end
            task.wait(0.05)
        end
    end
    addLog("Timescale target not reached: x" .. tostring(target), Color3.fromRGB(255, 120, 90))
    return false
end

local Macro = {}
Macro.recording = false
Macro.playing = false
Macro.actions = {}
Macro.startTime = nil
Macro.clockElapsed = 0
Macro.clockRunning = false
Macro.lastTimeScale = 1
Macro.timingMode = "wall"
Macro.createdAt = nil

local MACRO_START_WAVE = 1
local ROUND_RESET_WAVE = 0
local WAVE_DETECT_POLL = 0.05
local MACRO_START_TIMEOUT = 600
local PLACE_RETRY_TIMEOUT = 25
local UPGRADE_RETRY_TIMEOUT = 25
local SELL_RETRY_TIMEOUT = 8
local TARGET_RETRY_TIMEOUT = 8
local ABILITY_RETRY_TIMEOUT = 8
local OPTION_RETRY_TIMEOUT = 8
local TOWER_MATCH_RADIUS = 5
local PLACE_VERIFY_RADIUS = 5
local PLACE_ALREADY_RADIUS = 1.25
local SELL_MATCH_RADIUS = 6
local PLACE_SLOT_WAIT_TIMEOUT = 120
local UPGRADE_TARGET_FIND_TIMEOUT = 10
local PLAYBACK_RETRY_FOREVER = 1000000000
local AUTO_SAVE_FILE = "zephyr_tds_recorder_autosave.txt"

getGameTimeScale = function()
    if not GameState then
        return 1
    end
    local scale = 1
    pcall(function()
        local state = GameState.State
        local value = state and state.TimeScale or GameState.TimeScale
        scale = tonumber(value) or 1
    end)
    if scale ~= scale or scale < 0 then
        return 1
    end
    return scale
end

local function stopMacroClock()
    Macro.clockRunning = false
    if macroClockConnection then
        pcall(function()
            macroClockConnection:Disconnect()
        end)
        macroClockConnection = nil
    end
end

local function startMacroClock()
    stopMacroClock()
    Macro.startTime = tick()
    Macro.clockElapsed = 0
    Macro.clockRunning = true
    Macro.lastTimeScale = getGameTimeScale()
    macroClockConnection = RunService.Heartbeat:Connect(function(dt)
        if not Macro.clockRunning then
            return
        end
        local scale = getGameTimeScale()
        Macro.clockElapsed = (Macro.clockElapsed or 0) + math.max(0, dt or 0) * scale
        if math.abs(scale - (Macro.lastTimeScale or scale)) >= 0.01 then
            Macro.lastTimeScale = scale
            if Macro.recording and type(recordTimeScaleValue) == "function" then
                recordTimeScaleValue(scale)
            elseif Macro.recording or Macro.playing then
                addLog(("Timescale detected: x%.2f"):format(scale), Color3.fromRGB(120, 220, 255))
            end
        end
    end)
end

local function getMacroElapsed()
    return Macro.clockElapsed or 0
end

local function getCurrentWave()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local topDisplay = gui and gui:FindFirstChild("ReactGameTopGameDisplay")
    local frame = topDisplay and topDisplay:FindFirstChild("Frame")
    local wave = frame and frame:FindFirstChild("wave")
    local container = wave and wave:FindFirstChild("container")
    local label = container and container:FindFirstChild("value")
    local text = label and label.Text
    return type(text) == "string" and tonumber(text:match("^(%d+)") or text:match("(%d+)")) or nil
end

local function getCash()
    local cash = LocalPlayer:FindFirstChild("Cash")
    if cash and cash:IsA("IntValue") then
        return cash.Value
    end
    return 0
end

local function waitForCash(amount, timeout, shouldStop)
    if not amount or type(amount) ~= "number" or amount <= 0 then
        return true
    end
    timeout = timeout or 300
    local start = tick()
    while tick() - start < timeout do
        if shouldStop and shouldStop() then
            return false
        end
        if getCash() >= amount then
            return true
        end
        task.wait(0.15)
    end
    return false
end

local function waitForWave(targetWave, timeout, shouldStop)
    timeout = timeout or 600
    local start = tick()
    while tick() - start < timeout do
        if shouldStop and shouldStop() then
            return false
        end
        local current = getCurrentWave()
        if current and current >= targetWave then
            return true
        end
        task.wait(WAVE_DETECT_POLL)
    end
    return false
end

local function waitForMacroTime(targetTime, shouldStop, wallStart, useGameTiming)
    targetTime = tonumber(targetTime) or 0
    local elapsed = useGameTiming and getMacroElapsed() or (tick() - (wallStart or tick()))
    while Macro.playing and elapsed < targetTime do
        if shouldStop and shouldStop() then
            return false
        end
        task.wait(math.min(WAVE_DETECT_POLL, targetTime - elapsed))
        elapsed = useGameTiming and getMacroElapsed() or (tick() - (wallStart or tick()))
    end
    return Macro.playing
end

local function getTowerRoot(tower)
    if not tower then
        return nil
    end
    return tower:FindFirstChild("HumanoidRootPart")
        or tower:FindFirstChild("RootPart")
        or tower.PrimaryPart
        or tower:FindFirstChildWhichIsA("BasePart")
        or tower:FindFirstChildWhichIsA("BasePart", true)
end

local function isOwnTower(tower)
    local owner = tower and tower:FindFirstChild("Owner")
    if not owner then
        return true
    end
    local ok, value = pcall(function()
        return owner.Value
    end)
    if not ok then
        return true
    end
    return value == LocalPlayer
        or value == LocalPlayer.UserId
        or value == LocalPlayer.Name
        or tostring(value) == tostring(LocalPlayer.UserId)
end

local function xzDistance(a, b)
    local dx = a.X - b.X
    local dz = a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

local function waitForTowerAt(pos, timeout)
    if not pos then
        return nil
    end
    timeout = timeout or 2
    local start = tick()
    while tick() - start < timeout do
        local towers = workspace:FindFirstChild("Towers")
        if towers then
            for _, tower in ipairs(towers:GetChildren()) do
                if tower:IsA("Model") and isOwnTower(tower) then
                    local root = getTowerRoot(tower)
                    if root and xzDistance(root.Position, pos) < 5 then
                        return tower
                    end
                end
            end
        end
        task.wait(0.05)
    end
    return nil
end

local function waitForUpgrade(troop, previousLevel, timeout)
    timeout = timeout or 2
    local start = tick()
    while tick() - start < timeout do
        if not troop or not troop.Parent then
            return false
        end
        local rep = troop:FindFirstChild("TowerReplicator")
        if rep then
            local current = rep:GetAttribute("Upgrade")
            if current and current > previousLevel then
                return true
            end
        end
        task.wait(0.05)
    end
    return false
end

local function getHealthText()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local topDisplay = gui and gui:FindFirstChild("ReactGameTopGameDisplay")
    local frame = topDisplay and topDisplay:FindFirstChild("Frame")
    local healthbar = frame and frame:FindFirstChild("healthbar")
    local progress = healthbar and healthbar:FindFirstChild("progress")
    return progress and progress.Text or nil
end

local function isBaseDown()
    local text = getHealthText()
    if not text then
        return false
    end
    return tonumber(text:match("^(%d+)")) == 0
end

-- Interface
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ZephyrStratRecorder"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
local ok = pcall(function()
    ScreenGui.Parent = game:GetService("CoreGui")
end)
if not ok then
    ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local Main = Instance.new("Frame")
Main.Name = "Main"
RecorderScale = computeRecorderScale()
local initialViewport = getRecorderViewport()
local initialW = rpx(RECORDER_BASE_W)
local initialH = rpx(RECORDER_BASE_H)
Main.Size = UDim2.new(0, initialW, 0, initialH)
Main.Position =
    UDim2.new(0, math.floor((initialViewport.X - initialW) / 2), 0, math.floor((initialViewport.Y - initialH) / 2))
Main.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
Main.BorderSizePixel = 0
Main.ZIndex = 10
Main.Active = true
Main.Parent = ScreenGui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 12)
local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(30, 30, 40)
MainStroke.Thickness = 1
MainStroke.Parent = Main

local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, rpx(48))
TitleBar.BackgroundColor3 = Color3.fromRGB(13, 13, 18)
TitleBar.BorderSizePixel = 0
TitleBar.ZIndex = 11
TitleBar.Parent = Main
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 12)
local TitleBarFix = Instance.new("Frame")
TitleBarFix.Size = UDim2.new(1, 0, 0, rpx(12))
TitleBarFix.Position = UDim2.new(0, 0, 1, -rpx(12))
TitleBarFix.BackgroundColor3 = Color3.fromRGB(13, 13, 18)
TitleBarFix.BorderSizePixel = 0
TitleBarFix.ZIndex = 11
TitleBarFix.Parent = TitleBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -rpx(16), 0, rpx(20))
TitleLabel.Position = UDim2.new(0, rpx(14), 0, rpx(8))
TitleLabel.BackgroundTransparency = 1
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.Text = "Strat Recorder"
TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleLabel.TextSize = rpx(15)
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.ZIndex = 12
TitleLabel.Parent = TitleBar

local SubLabel = Instance.new("TextLabel")
SubLabel.Size = UDim2.new(0, rpx(120), 0, rpx(14))
SubLabel.Position = UDim2.new(0, rpx(14), 0, rpx(28))
SubLabel.BackgroundTransparency = 1
SubLabel.Font = Enum.Font.Gotham
SubLabel.Text = "FREE · KEYLESS"
SubLabel.TextColor3 = Color3.fromRGB(130, 80, 255)
SubLabel.TextSize = rpx(10)
SubLabel.TextXAlignment = Enum.TextXAlignment.Left
SubLabel.ZIndex = 12
SubLabel.Parent = Main

local DiscordLabel = Instance.new("TextLabel")
DiscordLabel.Size = UDim2.new(0, rpx(180), 0, rpx(14))
DiscordLabel.Position = UDim2.new(1, -rpx(190), 0, rpx(17))
DiscordLabel.BackgroundTransparency = 1
DiscordLabel.Font = Enum.Font.Gotham
DiscordLabel.Text = "discord.gg/zephyrmvsd"
DiscordLabel.TextColor3 = Color3.fromRGB(80, 80, 100)
DiscordLabel.TextSize = rpx(10)
DiscordLabel.TextXAlignment = Enum.TextXAlignment.Right
DiscordLabel.ZIndex = 12
DiscordLabel.Parent = Main

local LogBox = Instance.new("Frame")
LogBox.Size = UDim2.new(1, -rpx(24), 0, rpx(220))
LogBox.Position = UDim2.new(0, rpx(12), 0, rpx(58))
LogBox.BackgroundColor3 = Color3.fromRGB(6, 6, 10)
LogBox.BorderSizePixel = 0
LogBox.ZIndex = 11
LogBox.Parent = Main
Instance.new("UICorner", LogBox).CornerRadius = UDim.new(0, 8)
local LogStroke = Instance.new("UIStroke")
LogStroke.Color = Color3.fromRGB(22, 22, 32)
LogStroke.Thickness = 1
LogStroke.Parent = LogBox

local LogScroll = Instance.new("ScrollingFrame")
LogScroll.Size = UDim2.new(1, -rpx(8), 1, -rpx(8))
LogScroll.Position = UDim2.new(0, rpx(4), 0, rpx(4))
LogScroll.BackgroundTransparency = 1
LogScroll.BorderSizePixel = 0
LogScroll.ScrollBarThickness = rpx(3)
LogScroll.ScrollBarImageColor3 = Color3.fromRGB(100, 60, 255)
LogScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
LogScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
LogScroll.ZIndex = 12
LogScroll.Parent = LogBox
local LogLayout = Instance.new("UIListLayout")
LogLayout.Padding = UDim.new(0, 1)
LogLayout.Parent = LogScroll
local LogPad = Instance.new("UIPadding")
LogPad.PaddingLeft = UDim.new(0, rpx(4))
LogPad.PaddingTop = UDim.new(0, rpx(4))
LogPad.Parent = LogScroll

local LOG_DUPLICATE_WINDOW = 0.5
local MAX_VISIBLE_LOG_LINES = 160
local lastLogText = nil
local lastLogAt = 0
local visibleLogLines = {}

addLog = function(text, color)
    text = tostring(text or "")
    local now = tick()
    if text == lastLogText and now - lastLogAt < LOG_DUPLICATE_WINDOW then
        lastLogAt = now
        return
    end
    lastLogText = text
    lastLogAt = now
    table.insert(logQueue, { text = text, color = color or Color3.fromRGB(180, 180, 200) })
end

task.spawn(function()
    while true do
        task.wait(0.08)
        local madeLabel = false
        while #logQueue > 0 do
            local entry = table.remove(logQueue, 1)
            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, -rpx(8), 0, rpx(16))
            label.AutomaticSize = Enum.AutomaticSize.Y
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.Code
            label.Text = entry.text
            label.TextColor3 = entry.color
            label.TextSize = RecorderLogTextSize
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.TextWrapped = true
            label.ZIndex = 13
            label.Parent = LogScroll
            table.insert(visibleLogLines, label)
            if #visibleLogLines > MAX_VISIBLE_LOG_LINES then
                local old = table.remove(visibleLogLines, 1)
                if old and old.Parent then
                    old:Destroy()
                end
            end
            madeLabel = true
        end
        if madeLabel then
            task.defer(function()
                LogScroll.CanvasPosition = Vector2.new(0, math.huge)
            end)
        end
    end
end)

addLog("Logging stopped.", Color3.fromRGB(80, 80, 100))
for _, warning in ipairs(startupWarnings) do
    addLog(warning, Color3.fromRGB(255, 180, 80))
end

local ImportLabel = Instance.new("TextLabel")
ImportLabel.Size = UDim2.new(1, -rpx(24), 0, rpx(14))
ImportLabel.Position = UDim2.new(0, rpx(12), 0, rpx(288))
ImportLabel.BackgroundTransparency = 1
ImportLabel.Font = Enum.Font.GothamSemibold
ImportLabel.Text = "IMPORT STRAT"
ImportLabel.TextColor3 = Color3.fromRGB(60, 60, 80)
ImportLabel.TextSize = rpx(9)
ImportLabel.TextXAlignment = Enum.TextXAlignment.Left
ImportLabel.ZIndex = 11
ImportLabel.Parent = Main

local ImportBox = Instance.new("Frame")
ImportBox.Size = UDim2.new(1, -rpx(24), 0, rpx(44))
ImportBox.Position = UDim2.new(0, rpx(12), 0, rpx(304))
ImportBox.BackgroundColor3 = Color3.fromRGB(6, 6, 10)
ImportBox.BorderSizePixel = 0
ImportBox.ClipsDescendants = true
ImportBox.ZIndex = 11
ImportBox.Parent = Main
Instance.new("UICorner", ImportBox).CornerRadius = UDim.new(0, 8)
local ImportStroke = Instance.new("UIStroke")
ImportStroke.Color = Color3.fromRGB(22, 22, 32)
ImportStroke.Thickness = 1
ImportStroke.Parent = ImportBox

local ImportInput = Instance.new("TextBox")
ImportInput.Size = UDim2.new(1, -rpx(16), 1, 0)
ImportInput.Position = UDim2.new(0, rpx(8), 0, 0)
ImportInput.BackgroundTransparency = 1
ImportInput.Font = Enum.Font.Code
ImportInput.PlaceholderText = "Paste strat code or one-line raw..."
ImportInput.PlaceholderColor3 = Color3.fromRGB(50, 50, 65)
ImportInput.Text = ""
ImportInput.TextColor3 = Color3.fromRGB(200, 200, 220)
ImportInput.TextSize = rpx(10)
ImportInput.TextXAlignment = Enum.TextXAlignment.Left
ImportInput.TextYAlignment = Enum.TextYAlignment.Center
ImportInput.ClearTextOnFocus = false
ImportInput.MultiLine = false
ImportInput.TextTruncate = Enum.TextTruncate.AtEnd
ImportInput.ZIndex = 12
ImportInput.Parent = ImportBox

ImportInput.Focused:Connect(function()
    TweenService:Create(ImportStroke, TweenInfo.new(0.15), {
        Color = Color3.fromRGB(100, 60, 255),
        Thickness = 1.5,
    }):Play()
end)
ImportInput.FocusLost:Connect(function()
    TweenService:Create(ImportStroke, TweenInfo.new(0.15), {
        Color = Color3.fromRGB(22, 22, 32),
        Thickness = 1,
    }):Play()
end)

local btnY = rpx(362)
local btns = {}

local function makeBtn(text, color, x, w)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, w, 0, rpx(38))
    btn.Position = UDim2.new(0, x, 0, btnY)
    btn.BackgroundColor3 = color
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.GothamBold
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = rpx(12)
    btn.AutoButtonColor = false
    btn.ZIndex = 11
    btn.Parent = Main
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
    local orig = color
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), {
            BackgroundColor3 = orig:Lerp(Color3.fromRGB(255, 255, 255), 0.12),
        }):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundColor3 = orig }):Play()
    end)
    table.insert(btns, btn)
    return btn
end

local btnW = rpx(88)
local gap = rpx(12)
local StartBtn = makeBtn("Start", Color3.fromRGB(50, 200, 100), gap, btnW)
local ClearBtn = makeBtn("Clear", Color3.fromRGB(200, 50, 60), gap + btnW + gap, btnW)
local CopyBtn = makeBtn("Copy", Color3.fromRGB(60, 80, 200), gap + (btnW + gap) * 2, btnW)
local PlayBtn = makeBtn("Play", Color3.fromRGB(140, 50, 255), gap + (btnW + gap) * 3, btnW)

local function layoutRecorder(keepPosition)
    local oldScale = RecorderScale
    local oldSize = Main.AbsoluteSize
    RecorderScale = computeRecorderScale()
    RecorderLogTextSize = math.max(8, rpx(11))

    local width = rpx(RECORDER_BASE_W)
    local height = rpx(RECORDER_BASE_H)
    local viewport = getRecorderViewport()
    Main.Size = UDim2.new(0, width, 0, height)
    if not keepPosition then
        Main.Position = UDim2.new(0, math.floor((viewport.X - width) / 2), 0, math.floor((viewport.Y - height) / 2))
    elseif oldScale ~= RecorderScale and oldSize.X > 0 and oldSize.Y > 0 then
        local centerX = Main.AbsolutePosition.X + (oldSize.X / 2)
        local centerY = Main.AbsolutePosition.Y + (oldSize.Y / 2)
        Main.Position = UDim2.new(0, math.floor(centerX - width / 2), 0, math.floor(centerY - height / 2))
    end

    TitleBar.Size = UDim2.new(1, 0, 0, rpx(48))
    TitleBarFix.Size = UDim2.new(1, 0, 0, rpx(12))
    TitleBarFix.Position = UDim2.new(0, 0, 1, -rpx(12))
    TitleLabel.Size = UDim2.new(1, -rpx(16), 0, rpx(20))
    TitleLabel.Position = UDim2.new(0, rpx(14), 0, rpx(8))
    TitleLabel.TextSize = math.max(10, rpx(15))
    SubLabel.Size = UDim2.new(0, rpx(120), 0, rpx(14))
    SubLabel.Position = UDim2.new(0, rpx(14), 0, rpx(28))
    SubLabel.TextSize = math.max(7, rpx(10))
    DiscordLabel.Size = UDim2.new(0, rpx(180), 0, rpx(14))
    DiscordLabel.Position = UDim2.new(1, -rpx(190), 0, rpx(17))
    DiscordLabel.TextSize = math.max(7, rpx(10))
    DiscordLabel.Visible = width >= 300

    LogBox.Size = UDim2.new(1, -rpx(24), 0, rpx(220))
    LogBox.Position = UDim2.new(0, rpx(12), 0, rpx(58))
    LogScroll.Size = UDim2.new(1, -rpx(8), 1, -rpx(8))
    LogScroll.Position = UDim2.new(0, rpx(4), 0, rpx(4))
    LogScroll.ScrollBarThickness = math.max(2, rpx(3))
    LogLayout.Padding = UDim.new(0, math.max(1, rpx(1)))
    LogPad.PaddingLeft = UDim.new(0, rpx(4))
    LogPad.PaddingTop = UDim.new(0, rpx(4))
    for _, label in ipairs(visibleLogLines) do
        if label and label.Parent then
            label.Size = UDim2.new(1, -rpx(8), 0, rpx(16))
            label.TextSize = RecorderLogTextSize
        end
    end

    ImportLabel.Size = UDim2.new(1, -rpx(24), 0, rpx(14))
    ImportLabel.Position = UDim2.new(0, rpx(12), 0, rpx(288))
    ImportLabel.TextSize = math.max(7, rpx(9))
    ImportBox.Size = UDim2.new(1, -rpx(24), 0, rpx(44))
    ImportBox.Position = UDim2.new(0, rpx(12), 0, rpx(304))
    ImportInput.Size = UDim2.new(1, -rpx(16), 1, 0)
    ImportInput.Position = UDim2.new(0, rpx(8), 0, 0)
    ImportInput.TextSize = math.max(8, rpx(10))

    local buttonGap = rpx(12)
    local buttonW = math.floor((width - buttonGap * 5) / 4)
    local buttonY = rpx(362)
    local buttons = { StartBtn, ClearBtn, CopyBtn, PlayBtn }
    for i, btn in ipairs(buttons) do
        btn.Size = UDim2.new(0, buttonW, 0, rpx(38))
        btn.Position = UDim2.new(0, buttonGap + (buttonW + buttonGap) * (i - 1), 0, buttonY)
        btn.TextSize = math.max(8, rpx(12))
    end

    clampRecorderPosition(Main)
end

layoutRecorder(false)
if workspace.CurrentCamera then
    workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
        task.defer(function()
            layoutRecorder(true)
        end)
    end)
end

-- Strategy format
local function asVector3(value)
    if not value then
        return nil
    end
    local ok, valueType = pcall(function()
        return typeof(value)
    end)
    if ok and valueType == "Vector3" then
        return value
    end
    if ok and valueType == "vector" then
        local readOk, x, y, z = pcall(function()
            return value.X or value.x, value.Y or value.y, value.Z or value.z
        end)
        if readOk then
            return Vector3.new(x or 0, y or 0, z or 0)
        end
    end
    if type(value) == "table" then
        return Vector3.new(value.X or value.x or 0, value.Y or value.y or 0, value.Z or value.z or 0)
    end
    return nil
end

local function tableHasAnyValue(value)
    return type(value) == "table" and next(value) ~= nil
end

local function encodeAbilityDataForLine(value)
    if not tableHasAnyValue(value) then
        return nil
    end
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(value)
    end)
    if not ok or type(encoded) ~= "string" or encoded == "" then
        return nil
    end
    return encoded:gsub("%]%]", "] ]"):gsub("\r", ""):gsub("\n", " ")
end

local function decodeAbilityDataFromLine(value)
    if type(value) ~= "string" or value == "" then
        return {}
    end
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(value)
    end)
    if ok and type(decoded) == "table" then
        return decoded
    end
    return {}
end

local function formatAction(action)
    if not action or not action.type then
        return nil
    end
    if not action.data then
        return nil
    end
    local function fv(v)
        local vec = asVector3(v)
        if vec then
            return vec.X, vec.Y, vec.Z
        end
        return 0, 0, 0
    end
    local function safeText(value)
        return tostring(value or ""):gsub('"', "'")
    end
    if action.type == "Place" then
        local x, y, z = fv(action.data.position)
        return string.format(
            'place(%.1f, %.1f, %.1f, "%s", %d, %.2f)',
            x,
            y,
            z,
            tostring(action.data.tower or "Unknown"),
            action.data.cashBefore or 0,
            action.time or 0
        )
    elseif action.type == "Upgrade" then
        if not action.data.troopPos then
            return nil
        end
        local x, _, z = fv(action.data.troopPos)
        return string.format(
            "upgrade(%.1f, %.1f, %d, %d, %.2f)",
            x,
            z,
            action.data.path or 1,
            action.data.cashBefore or 0,
            action.time or 0
        )
    elseif action.type == "Sell" then
        if not action.data.troopPos then
            return nil
        end
        local x, _, z = fv(action.data.troopPos)
        return string.format("sell(%.1f, %.1f, %.2f)", x, z, action.time or 0)
    elseif action.type == "Target" then
        if not action.data.troopPos then
            return nil
        end
        local x, _, z = fv(action.data.troopPos)
        return string.format(
            'target(%.1f, %.1f, "%s", %.2f)',
            x,
            z,
            tostring(action.data.target or "First"),
            action.time or 0
        )
    elseif action.type == "Ability" then
        if not action.data.troopPos then
            return nil
        end
        local x, _, z = fv(action.data.troopPos)
        local encoded = encodeAbilityDataForLine(action.data.abilityData)
        if encoded then
            return string.format(
                'abilitydata(%.1f, %.1f, "%s", [[%s]], %.2f)',
                x,
                z,
                safeText(action.data.name),
                encoded,
                action.time or 0
            )
        end
        return string.format(
            'ability(%.1f, %.1f, "%s", %.2f)',
            x,
            z,
            tostring(action.data.name or ""),
            action.time or 0
        )
    elseif action.type == "Option" then
        if not action.data.troopPos then
            return nil
        end
        local x, _, z = fv(action.data.troopPos)
        local name = action.data.name
        local value = action.data.value
        if name == nil then
            name = ""
        end
        if value == nil then
            value = ""
        end
        return string.format(
            'option(%.1f, %.1f, "%s", "%s", %.2f)',
            x,
            z,
            tostring(name),
            tostring(value),
            action.time or 0
        )
    elseif action.type == "Consumable" then
        local x, y, z = fv(action.data.position)
        local dx, dy, dz = fv(action.data.direction)
        return string.format(
            'consumable(%.1f, %.1f, %.1f, "%s", "%s", %.2f, %.3f, %.3f, %.3f, %.2f)',
            x,
            y,
            z,
            safeText(action.data.name),
            safeText(action.data.pathName),
            tonumber(action.data.pathToEnd) or 0,
            dx,
            dy,
            dz,
            action.time or 0
        )
    elseif action.type == "Skip" then
        return string.format("skip(%d, %.2f)", action.data.wave or 0, action.time or 0)
    elseif action.type == "TimeScaleUnlock" then
        return string.format("timescaleunlock(%.2f)", action.time or 0)
    elseif action.type == "TimeScale" then
        return string.format("timescale(%.2f, %.2f)", tonumber(action.data.scale) or 1, action.time or 0)
    end
    return nil
end

local function getActionColor(t)
    if t == "Place" then
        return Color3.fromRGB(100, 220, 120)
    end
    if t == "Upgrade" then
        return Color3.fromRGB(100, 160, 255)
    end
    if t == "Sell" then
        return Color3.fromRGB(255, 100, 100)
    end
    if t == "Target" then
        return Color3.fromRGB(255, 200, 80)
    end
    if t == "Ability" then
        return Color3.fromRGB(200, 100, 255)
    end
    if t == "Option" then
        return Color3.fromRGB(120, 220, 255)
    end
    if t == "Consumable" then
        return Color3.fromRGB(255, 120, 210)
    end
    if t == "Skip" then
        return Color3.fromRGB(255, 160, 60)
    end
    if t == "TimeScale" or t == "TimeScaleUnlock" then
        return Color3.fromRGB(120, 220, 255)
    end
    return Color3.fromRGB(180, 180, 200)
end

local function getIsoNow()
    local ok, value = pcall(function()
        return DateTime.now():ToIsoDate()
    end)
    if ok and type(value) == "string" and value ~= "" then
        return value
    end
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function getExportText()
    local lines = {}
    for _, action in ipairs(Macro.actions) do
        local line = formatAction(action)
        if line then
            table.insert(lines, line)
        end
    end
    if #lines > 0 then
        local now = getIsoNow()
        Macro.createdAt = Macro.createdAt or now
        local ok, encoded = pcall(function()
            return HttpService:JSONEncode({
                createdAt = Macro.createdAt,
                updatedAt = now,
                recorder = "ZephyrTDS",
            })
        end)
        if ok and type(encoded) == "string" then
            table.insert(lines, 1, "-- ZEPHYR_META: " .. encoded)
        end
        if Macro.timingMode == "game" then
            table.insert(lines, 1, "-- ZEPHYR_TIMING: game")
        end
    end
    return table.concat(lines, "\n")
end

local lastAutoSaveAt = 0
local autoSavePending = false
local lastAutoSaveText = ""

local function saveDraft(force)
    if type(writefile) ~= "function" then
        return false
    end
    local text = getExportText()
    if text == "" then
        return false
    end
    if text == lastAutoSaveText and not force then
        return false
    end
    if not force and tick() - lastAutoSaveAt < 2 then
        if not autoSavePending then
            autoSavePending = true
            task.delay(2, function()
                autoSavePending = false
                saveDraft(true)
            end)
        end
        return false
    end
    local ok = pcall(function()
        writefile(AUTO_SAVE_FILE, text)
    end)
    if ok then
        lastAutoSaveAt = tick()
        lastAutoSaveText = text
    end
    return ok
end

local function clearDraft()
    if type(writefile) ~= "function" then
        return false
    end
    local ok = pcall(function()
        writefile(AUTO_SAVE_FILE, "")
    end)
    if ok then
        lastAutoSaveText = ""
    end
    return ok
end

local function loadDraft()
    if type(readfile) ~= "function" then
        return false
    end
    local ok, text = pcall(function()
        if type(isfile) == "function" and not isfile(AUTO_SAVE_FILE) then
            return nil
        end
        return readfile(AUTO_SAVE_FILE)
    end)
    if ok and type(text) == "string" and text ~= "" then
        ImportInput.Text = text
        addLog("Loaded autosaved draft into import box.", Color3.fromRGB(120, 220, 255))
        return true
    end
    return false
end

local function parseAndLoad(text)
    local actions = {}
    actions.timingMode = "wall"
    local zeroFallbackPos = nil
    local function isZeroPair(x, z)
        return math.abs((tonumber(x) or 0)) < 0.01 and math.abs((tonumber(z) or 0)) < 0.01
    end
    local function troopPosFrom(x, z)
        if isZeroPair(x, z) and zeroFallbackPos then
            return zeroFallbackPos
        end
        return Vector3.new(tonumber(x), 4.04, tonumber(z))
    end
    text = tostring(text or ""):gsub("%)%s+(%a)", ")\n%1")
    for line in text:gmatch("[^\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line == "" then
            continue
        end
        if line:sub(1, 2) == "--" then
            local lower = line:lower()
            if lower:find("zephyr_timing:%s*game") or lower:find("timing:%s*game") then
                actions.timingMode = "game"
            elseif lower:find("zephyr_timing:%s*wall") or lower:find("timing:%s*wall") then
                actions.timingMode = "wall"
            end
            continue
        end
        do
            local px, py, pz, tower, cash, t = line:match(
                'place%(([%-%.%d]+),%s*([%-%.%d]+),%s*([%-%.%d]+),%s*"([^"]+)",%s*([%-%.%d]+),%s*([%.%d]+)%)'
            )
            if px then
                local pos = Vector3.new(tonumber(px), tonumber(py), tonumber(pz))
                zeroFallbackPos = Vector3.new(pos.X, 4.04, pos.Z)
                table.insert(actions, {
                    time = tonumber(t) or 0,
                    type = "Place",
                    data = {
                        position = pos,
                        rotation = CFrame.new(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1),
                        tower = tower,
                        cashBefore = tonumber(cash) or 0,
                    },
                })
                continue
            end
        end
        do
            local ux, uz, path, ucash, ut =
                line:match("upgrade%(([%-%.%d]+),%s*([%-%.%d]+),%s*([%-%.%d]+),%s*([%-%.%d]+),%s*([%-%.%d]+)%)")
            if ux then
                table.insert(actions, {
                    time = tonumber(ut) or 0,
                    type = "Upgrade",
                    data = {
                        troopPos = troopPosFrom(ux, uz),
                        troopName = "Default",
                        path = tonumber(path) or 1,
                        cashBefore = tonumber(ucash) or 0,
                    },
                })
                continue
            end
        end
        do
            local sx, sz, st = line:match("sell%(([%-%.%d]+),%s*([%-%.%d]+),%s*([%.%d]+)%)")
            if sx then
                table.insert(actions, {
                    time = tonumber(st) or 0,
                    type = "Sell",
                    data = {
                        troopPos = troopPosFrom(sx, sz),
                        troopName = "Default",
                    },
                })
                continue
            end
        end
        do
            local tx, tz, tmode, tt = line:match('target%(([%-%.%d]+),%s*([%-%.%d]+),%s*"([^"]+)",%s*([%.%d]+)%)')
            if tx then
                table.insert(actions, {
                    time = tonumber(tt) or 0,
                    type = "Target",
                    data = {
                        troopPos = troopPosFrom(tx, tz),
                        troopName = "Default",
                        target = tmode,
                    },
                })
                continue
            end
        end
        do
            local ax, az, aname, encoded, at =
                line:match('abilitydata%(([%-%.%d]+),%s*([%-%.%d]+),%s*"([^"]+)",%s*%[%[(.-)%]%],%s*([%.%d]+)%)')
            if ax then
                table.insert(actions, {
                    time = tonumber(at) or 0,
                    type = "Ability",
                    data = {
                        troopPos = troopPosFrom(ax, az),
                        troopName = "Default",
                        name = aname,
                        abilityData = decodeAbilityDataFromLine(encoded),
                    },
                })
                continue
            end
        end
        do
            local ax, az, aname, at = line:match('ability%(([%-%.%d]+),%s*([%-%.%d]+),%s*"([^"]+)",%s*([%.%d]+)%)')
            if ax then
                table.insert(actions, {
                    time = tonumber(at) or 0,
                    type = "Ability",
                    data = {
                        troopPos = troopPosFrom(ax, az),
                        troopName = "Default",
                        name = aname,
                        abilityData = {},
                    },
                })
                continue
            end
        end
        do
            local ox, oz, oname, ovalue, ot =
                line:match('option%(([%-%.%d]+),%s*([%-%.%d]+),%s*"([^"]+)",%s*"([^"]+)",%s*([%.%d]+)%)')
            if ox then
                table.insert(actions, {
                    time = tonumber(ot) or 0,
                    type = "Option",
                    data = {
                        troopPos = troopPosFrom(ox, oz),
                        troopName = "Default",
                        name = oname,
                        value = ovalue,
                    },
                })
                continue
            end
        end
        do
            local cx, cy, cz, cname, pathName, pathToEnd, dx, dy, dz, ct = line:match(
                'consumable%(([%-%.%d]+),%s*([%-%.%d]+),%s*([%-%.%d]+),%s*"([^"]+)",%s*"([^"]*)",%s*([%-%.%d]+),%s*([%-%.%d]+),%s*([%-%.%d]+),%s*([%-%.%d]+),%s*([%.%d]+)%)'
            )
            if cx then
                local pos = Vector3.new(tonumber(cx) or 0, tonumber(cy) or 0, tonumber(cz) or 0)
                local direction = Vector3.new(tonumber(dx) or 0, tonumber(dy) or 0, tonumber(dz) or 0)
                local hasPlacement = tostring(pathName or "") ~= ""
                    or math.abs(pos.X) > 0.01
                    or math.abs(pos.Y) > 0.01
                    or math.abs(pos.Z) > 0.01
                table.insert(actions, {
                    time = tonumber(ct) or 0,
                    type = "Consumable",
                    data = {
                        name = cname,
                        position = pos,
                        pathName = pathName,
                        pathToEnd = tonumber(pathToEnd) or 0,
                        direction = direction,
                        hasPlacement = hasPlacement,
                    },
                })
                continue
            end
        end
        do
            local wave, skt = line:match("skip%((%d+),%s*([%.%d]+)%)")
            if wave then
                table.insert(actions, {
                    time = tonumber(skt) or 0,
                    type = "Skip",
                    data = { wave = tonumber(wave) or 0 },
                })
                continue
            end
        end
        do
            local ts = line:match("timescaleunlock%(%s*([%.%d]+)%s*%)")
            if ts then
                table.insert(actions, {
                    time = tonumber(ts) or 0,
                    type = "TimeScaleUnlock",
                    data = {},
                })
                continue
            end
        end
        do
            local scale, ts = line:match("timescale%(%s*([%.%d]+)%s*,%s*([%.%d]+)%s*%)")
            if scale then
                actions.timingMode = "game"
                table.insert(actions, {
                    time = tonumber(ts) or 0,
                    type = "TimeScale",
                    data = { scale = tonumber(scale) or 1 },
                })
            end
        end
    end
    return actions
end

task.defer(loadDraft)

-- Recording hooks
local lastRecordSignature = nil
local lastRecordAt = 0
local lastRecordBySignature = {}
local RECORD_DUPLICATE_WINDOW = {
    Place = 0.12,
    Upgrade = 0.35,
    Sell = 0.6,
    Target = 0.45,
    Ability = 0.75,
    Option = 0.75,
    Consumable = 0.35,
    Skip = 1.25,
    TimeScale = 1.25,
    TimeScaleUnlock = 2,
}

local function positionSignature(pos)
    local vec = asVector3(pos)
    if not vec then
        return "nil"
    end
    return string.format("%.1f,%.1f,%.1f", vec.X, vec.Y, vec.Z)
end

local function canCommitRecord(signature, actionType, window)
    if type(signature) ~= "string" or signature == "" then
        return true
    end
    local now = tick()
    local minWindow = tonumber(window) or RECORD_DUPLICATE_WINDOW[actionType] or 0.35
    local previous = lastRecordBySignature[signature]
    if previous and now - previous < minWindow then
        return false
    end
    lastRecordBySignature[signature] = now
    lastRecordSignature = signature
    lastRecordAt = now
    return true
end

local function getTowerModelFromInstance(value)
    local ok, valueType = pcall(function()
        return typeof(value)
    end)
    if not ok or valueType ~= "Instance" or not value then
        return nil
    end
    local towers = workspace:FindFirstChild("Towers")
    if not towers then
        return nil
    end
    local current = value
    while current and current ~= towers do
        if current.Parent == towers and current:IsA("Model") then
            return current
        end
        current = current.Parent
    end
    return nil
end

local function copyAbilityDataValue(value, depth)
    depth = tonumber(depth) or 0
    if depth > 5 then
        return nil
    end
    local valueType = type(value)
    if valueType == "string" or valueType == "number" or valueType == "boolean" then
        return value
    end

    local okType, luauType = pcall(function()
        return typeof(value)
    end)
    if okType then
        if luauType == "Vector3" then
            return { __zephyrType = "Vector3", X = value.X, Y = value.Y, Z = value.Z }
        elseif luauType == "Vector2" then
            return { __zephyrType = "Vector2", X = value.X, Y = value.Y }
        elseif luauType == "CFrame" then
            return { __zephyrType = "CFrame", components = { value:GetComponents() } }
        elseif luauType == "Instance" then
            local tower = getTowerModelFromInstance(value)
            if tower then
                local root = getTowerRoot(tower)
                return {
                    __zephyrType = "TowerRef",
                    name = tower.Name,
                    position = root and copyAbilityDataValue(root.Position, depth + 1) or nil,
                }
            elseif value:IsA("BasePart") then
                return {
                    __zephyrType = "InstancePosition",
                    name = value.Name,
                    position = copyAbilityDataValue(value.Position, depth + 1),
                }
            end
            return nil
        end
    end

    if valueType ~= "table" then
        return nil
    end
    local out = {}
    for k, v in pairs(value) do
        if type(k) == "string" or type(k) == "number" then
            local copied = copyAbilityDataValue(v, depth + 1)
            if copied ~= nil then
                out[k] = copied
            end
        end
    end
    if next(out) == nil then
        return nil
    end
    return out
end

local function copyPrimitiveMap(value)
    return copyAbilityDataValue(value, 0) or {}
end

local commitPreparedAction

local function prepareTroopActionBeforeRemote(action, args)
    if not Macro.recording or not Macro.startTime then
        return nil
    end
    args = args or {}
    local timestamp = getMacroElapsed()
    local cashBefore = getCash()

    if action == "Place" then
        local data = args[1]
        local position = asVector3(data and data.Position)
        if not position then
            addLog("Place not recorded: position unavailable.", Color3.fromRGB(255, 120, 90))
            return nil
        end
        return {
            signature = "Place|" .. tostring(args[2]) .. "|" .. positionSignature(position),
            duplicateWindow = RECORD_DUPLICATE_WINDOW.Place,
            action = {
                time = timestamp,
                type = "Place",
                data = {
                    position = position,
                    rotation = data and data.Rotation,
                    tower = args[2],
                    cashBefore = cashBefore,
                },
            },
        }
    elseif action == "Upgrade" then
        local data = args[2]
        local troop = data and data.Troop
        local root = getTowerRoot(troop)
        if not root then
            addLog("Upgrade not recorded: tower position unavailable.", Color3.fromRGB(255, 120, 90))
            return nil
        end
        local path = tonumber(data and data.Path) or 1
        local pos = root.Position
        return {
            signature = "Upgrade|" .. tostring(troop) .. "|" .. positionSignature(pos) .. "|" .. tostring(path),
            duplicateWindow = RECORD_DUPLICATE_WINDOW.Upgrade,
            action = {
                time = timestamp,
                type = "Upgrade",
                data = {
                    troopName = troop and troop.Name or "Default",
                    troopPos = pos,
                    path = path,
                    cashBefore = cashBefore,
                },
            },
        }
    elseif action == "Sell" then
        local data = args[1]
        local troop = data and data.Troop
        local root = getTowerRoot(troop)
        if not root then
            addLog("Sell not recorded: tower position unavailable before server call.", Color3.fromRGB(255, 120, 90))
            return nil
        end
        local pos = root.Position
        return {
            signature = "Sell|" .. tostring(troop) .. "|" .. positionSignature(pos),
            duplicateWindow = RECORD_DUPLICATE_WINDOW.Sell,
            action = {
                time = timestamp,
                type = "Sell",
                data = {
                    troopName = troop and troop.Name or "Default",
                    troopPos = pos,
                },
            },
        }
    elseif action == "Target" then
        local data = args[2]
        local troop = data and data.Troop
        local root = getTowerRoot(troop)
        if not root then
            addLog("Target not recorded: tower position unavailable.", Color3.fromRGB(255, 120, 90))
            return nil
        end
        local pos = root.Position
        local target = data and data.Target
        return {
            signature = "Target|" .. tostring(troop) .. "|" .. positionSignature(pos) .. "|" .. tostring(target),
            duplicateWindow = RECORD_DUPLICATE_WINDOW.Target,
            action = {
                time = timestamp,
                type = "Target",
                data = {
                    troopName = troop and troop.Name or "Default",
                    troopPos = pos,
                    target = target,
                },
            },
        }
    elseif action == "Abilities" then
        local data = args[2]
        local troop = data and data.Troop
        local root = getTowerRoot(troop)
        if not root then
            addLog("Ability not recorded: tower position unavailable.", Color3.fromRGB(255, 120, 90))
            return nil
        end
        local pos = root.Position
        local name = data and data.Name
        return {
            signature = "Ability|" .. tostring(troop) .. "|" .. positionSignature(pos) .. "|" .. tostring(name),
            duplicateWindow = RECORD_DUPLICATE_WINDOW.Ability,
            action = {
                time = timestamp,
                type = "Ability",
                data = {
                    troopName = troop and troop.Name or "Default",
                    troopPos = pos,
                    name = name,
                    abilityData = copyPrimitiveMap(data and data.Data),
                },
            },
        }
    elseif action == "Option" then
        local mode = args[1]
        local data = args[2] or args[3]
        if mode ~= "Set" or type(data) ~= "table" then
            return nil
        end
        local troop = data.Troop
        local root = getTowerRoot(troop)
        if not root then
            addLog("Option not recorded: tower position unavailable.", Color3.fromRGB(255, 120, 90))
            return nil
        end
        local pos = root.Position
        return {
            signature = "Option|"
                .. tostring(troop)
                .. "|"
                .. positionSignature(pos)
                .. "|"
                .. tostring(data.Name)
                .. "|"
                .. tostring(data.Value),
            duplicateWindow = RECORD_DUPLICATE_WINDOW.Option,
            action = {
                time = timestamp,
                type = "Option",
                data = {
                    troopName = troop and troop.Name or "Default",
                    troopPos = pos,
                    name = data.Name,
                    value = data.Value,
                },
            },
        }
    end
    return nil
end

local function recordTroopAction(action, args)
    return commitPreparedAction(prepareTroopActionBeforeRemote(action, args))
end

local function prepareConsumableActionBeforeRemote(action, args)
    if action ~= "Consume" or not Macro.recording or not Macro.startTime then
        return nil
    end
    args = args or {}
    local name = tostring(args[1] or "")
    if name == "" then
        return nil
    end
    local payload = type(args[2]) == "table" and args[2] or {}
    local position = asVector3(payload.position)
    local direction = asVector3(payload.direction)
    local pathName = tostring(payload.pathName or "")
    local pathToEnd = tonumber(payload.pathToEnd) or 0
    local hasPlacement = position ~= nil or direction ~= nil or pathName ~= "" or payload.pathToEnd ~= nil
    position = position or Vector3.new(0, 0, 0)
    direction = direction or Vector3.new(0, 0, 0)
    return {
        signature = "Consumable|" .. name .. "|" .. pathName .. "|" .. positionSignature(position),
        duplicateWindow = RECORD_DUPLICATE_WINDOW.Consumable,
        action = {
            time = getMacroElapsed(),
            type = "Consumable",
            data = {
                name = name,
                position = position,
                pathName = pathName,
                pathToEnd = pathToEnd,
                direction = direction,
                hasPlacement = hasPlacement,
            },
        },
    }
end

commitPreparedAction = function(prepared)
    if not prepared or not prepared.action then
        return false
    end
    if not canCommitRecord(prepared.signature, prepared.action.type, prepared.duplicateWindow) then
        return true
    end
    table.insert(Macro.actions, prepared.action)
    local line = formatAction(prepared.action)
    if line then
        addLog(line, getActionColor(prepared.action.type))
    end
    saveDraft(false)
    return true
end

local function recordSkipAction()
    if not Macro.recording or not Macro.startTime then
        return false
    end
    local wave = getCurrentWave() or 0
    if not canCommitRecord("Skip|" .. tostring(wave), "Skip") then
        return true
    end
    local a = {
        time = getMacroElapsed(),
        type = "Skip",
        data = { wave = wave },
    }
    table.insert(Macro.actions, a)
    local line = formatAction(a)
    if line then
        addLog(line, getActionColor("Skip"))
    end
    saveDraft(false)
    return true
end

local lastRecordedTimeScale = nil
local lastRecordedTimeScaleAt = 0

local function readTimescaleTickets()
    local ok, value = pcall(function()
        local cacheModule = require(ReplicatedStorage.Client.Modules.Cache)
        local cache = cacheModule and cacheModule("Values.TimescaleTickets")
        if cache then
            return cache:GetValue()
        end
    end)
    if ok then
        return tonumber(value)
    end
    return nil
end

local function recordTimeScaleUnlock()
    if not Macro.recording or not Macro.startTime then
        return false
    end
    if not canCommitRecord("TimeScaleUnlock", "TimeScaleUnlock") then
        return true
    end
    local a = {
        time = getMacroElapsed(),
        type = "TimeScaleUnlock",
        data = { ticketsBefore = readTimescaleTickets() },
    }
    table.insert(Macro.actions, a)
    local line = formatAction(a)
    if line then
        addLog(line, getActionColor("TimeScaleUnlock"))
    end
    saveDraft(false)
    return true
end

recordTimeScaleValue = function(scale)
    if not Macro.recording or not Macro.startTime then
        return false
    end
    scale = tonumber(scale) or getGameTimeScale()
    if not scale or scale ~= scale or scale < 0 then
        return false
    end
    if
        lastRecordedTimeScale
        and math.abs(scale - lastRecordedTimeScale) < 0.01
        and tick() - lastRecordedTimeScaleAt < 1.5
    then
        return true
    end
    if not canCommitRecord(("TimeScale|%.2f"):format(scale), "TimeScale") then
        return true
    end
    lastRecordedTimeScale = scale
    lastRecordedTimeScaleAt = tick()
    local a = {
        time = getMacroElapsed(),
        type = "TimeScale",
        data = { scale = scale },
    }
    table.insert(Macro.actions, a)
    local line = formatAction(a)
    if line then
        addLog(line, getActionColor("TimeScale"))
    end
    saveDraft(false)
    return true
end

local unpackResults = (type(table) == "table" and type(table.unpack) == "function") and table.unpack or unpack
local function packResults(...)
    return { n = select("#", ...), ... }
end

local function resultFailureText(value, depth, treatFalseAsFailure)
    depth = depth or 0
    if depth > 4 then
        return nil
    end
    local valueType = type(value)
    if valueType == "boolean" and value == false and treatFalseAsFailure then
        return "server returned false"
    end
    if valueType == "string" then
        local text = value:lower()
        if
            text:find("not enough", 1, true)
            or text:find("insufficient", 1, true)
            or text:find("can't afford", 1, true)
            or text:find("can't ", 1, true)
            or text:find("cannot afford", 1, true)
            or text:find("cannot", 1, true)
            or text:find("need $", 1, true)
            or text:find("more to", 1, true)
            or text:find("must be", 1, true)
            or text:find("too close", 1, true)
            or text:find("occupied", 1, true)
            or text:find("blocked", 1, true)
            or text:find("invalid", 1, true)
            or text:find("limit", 1, true)
            or text:find("max", 1, true)
            or text:find("cooldown", 1, true)
            or text:find("denied", 1, true)
            or text:find("unable", 1, true)
            or text:find("rejected", 1, true)
            or text:find("reject", 1, true)
            or text:find("failed", 1, true)
            or text:find("failure", 1, true)
            or text:find("error", 1, true)
        then
            return value
        end
    elseif valueType == "table" then
        for k, v in pairs(value) do
            local nested = resultFailureText(v, depth + 1, treatFalseAsFailure)
            if nested then
                return nested
            end
            if type(k) == "string" then
                local key = k:lower()
                if (key == "error" or key == "err") and v ~= nil and v ~= false then
                    return tostring(v)
                end
            end
        end
    end
    return nil
end

local function shouldRecordServerResult(results, treatFalseAsFailure)
    if not results then
        return true
    end
    for i = 1, results.n or #results do
        local failure = resultFailureText(results[i], nil, treatFalseAsFailure)
        if failure then
            return false, failure
        end
    end
    return true
end

local function isInstance(value)
    local ok, result = pcall(function()
        return typeof(value) == "Instance"
    end)
    return ok and result == true
end

local function isPlacedTowerInstance(value)
    if not isInstance(value) then
        return false
    end
    local towers = workspace:FindFirstChild("Towers")
    if not towers then
        return false
    end
    local ok, result = pcall(function()
        return value:IsDescendantOf(towers)
    end)
    return ok and result == true
end

local function resultContainsPlacedTower(value, depth)
    depth = depth or 0
    if depth > 4 then
        return false
    end
    if isPlacedTowerInstance(value) then
        return true
    end
    if type(value) == "table" then
        for _, v in pairs(value) do
            if resultContainsPlacedTower(v, depth + 1) then
                return true
            end
        end
    end
    return false
end

local function shouldRecordTroopServerResult(action, results)
    if action == "Place" and results then
        for i = 1, results.n or #results do
            if resultContainsPlacedTower(results[i]) then
                return true
            end
        end
        local accepted, failure = shouldRecordServerResult(results, true)
        if not accepted then
            return false, failure
        end
        if (results.n or #results) > 0 then
            return false, "placement did not return a tower"
        end
    end
    return shouldRecordServerResult(results, false)
end

local function recordTroopActionIfAccepted(action, args, results, preparedAction)
    local accepted, failure = shouldRecordTroopServerResult(action, results)
    if accepted then
        if preparedAction then
            return commitPreparedAction(preparedAction)
        end
        return recordTroopAction(action, args)
    end
    if Macro.recording and Macro.startTime then
        addLog("Skipped rejected " .. tostring(action) .. ": " .. tostring(failure), Color3.fromRGB(255, 120, 90))
    end
    return false
end

local function recordSkipActionIfAccepted(results)
    local accepted, failure = shouldRecordServerResult(results)
    if accepted then
        return recordSkipAction()
    end
    if Macro.recording and Macro.startTime then
        addLog("Skipped rejected Skip: " .. tostring(failure), Color3.fromRGB(255, 120, 90))
    end
    return false
end

local function recordTroopsInvoke(self, action, ...)
    local args = { ... }
    local preparedAction = prepareTroopActionBeforeRemote(action, args)
    local results = packResults(oldTroopsInvoke(self, action, ...))
    recordTroopActionIfAccepted(action, args, results, preparedAction)
    return unpackResults(results, 1, results.n)
end

local troopsHookInstalled = false
if type(oldTroopsInvoke) == "function" and TroopsChannel then
    troopsHookInstalled = pcall(function()
        TroopsChannel.InvokeServer = recordTroopsInvoke
    end)
end
if not troopsHookInstalled then
    addLog("Troops recording hook unavailable; import/playback can still work.", Color3.fromRGB(255, 180, 80))
end

local function recordVotingInvoke(self, action, ...)
    local results = packResults(oldVotingInvoke(self, action, ...))
    if action == "Skip" then
        recordSkipActionIfAccepted(results)
    end
    return unpackResults(results, 1, results.n)
end

local votingHookInstalled = false
if type(oldVotingInvoke) == "function" and VotingChannel then
    votingHookInstalled = pcall(function()
        VotingChannel.InvokeServer = recordVotingInvoke
    end)
end
if not votingHookInstalled then
    addLog("Skip recording hook unavailable; import/playback can still work.", Color3.fromRGB(255, 180, 80))
end

local function recordTicketsInvoke(self, action, ...)
    local results = packResults(oldTicketsInvoke(self, action, ...))
    if action == "UnlockTimeScale" then
        local accepted, failure = shouldRecordServerResult(results, true)
        if accepted then
            recordTimeScaleUnlock()
        elseif Macro.recording and Macro.startTime then
            addLog("Skipped rejected timescale unlock: " .. tostring(failure), Color3.fromRGB(255, 120, 90))
        end
    end
    return unpackResults(results, 1, results.n)
end

local ticketsInvokeHookInstalled = false
if type(oldTicketsInvoke) == "function" and TicketsChannel then
    ticketsInvokeHookInstalled = pcall(function()
        TicketsChannel.InvokeServer = recordTicketsInvoke
    end)
end

local function recordTicketsFire(self, action, ...)
    local beforeScale = getGameTimeScale()
    local results = packResults(oldTicketsFire(self, action, ...))
    if action == "CycleTimeScale" then
        task.spawn(function()
            local scale = beforeScale
            local start = tick()
            while tick() - start < 1.5 do
                task.wait(0.08)
                scale = getGameTimeScale()
                if math.abs(scale - beforeScale) > 0.01 then
                    break
                end
            end
            recordTimeScaleValue(scale)
        end)
    end
    return unpackResults(results, 1, results.n)
end

local ticketsFireHookInstalled = false
if type(oldTicketsFire) == "function" and TicketsChannel then
    ticketsFireHookInstalled = pcall(function()
        TicketsChannel.FireServer = recordTicketsFire
    end)
end

local function recordConsumablesFire(self, action, ...)
    local args = { ... }
    local preparedAction = prepareConsumableActionBeforeRemote(action, args)
    local results = packResults(oldConsumablesFire(self, action, ...))
    if preparedAction then
        commitPreparedAction(preparedAction)
    end
    return unpackResults(results, 1, results.n)
end

local consumablesFireHookInstalled = false
if type(oldConsumablesFire) == "function" and ConsumablesChannel then
    consumablesFireHookInstalled = pcall(function()
        ConsumablesChannel.FireServer = recordConsumablesFire
    end)
end

if ticketsInvokeHookInstalled or ticketsFireHookInstalled then
    addLog("Timescale recorder hook active.", Color3.fromRGB(100, 220, 120))
else
    addLog(
        "Timescale hook unavailable; scale changes are still detected when GameState updates.",
        Color3.fromRGB(255, 180, 80)
    )
end
if consumablesFireHookInstalled then
    addLog("Consumable recorder hook active.", Color3.fromRGB(100, 220, 120))
else
    addLog(
        "Consumable recorder hook unavailable; direct RemoteEvent support may be needed.",
        Color3.fromRGB(255, 180, 80)
    )
end

local remoteFunctionHookInstalled = false
if type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
    local wrap = type(newcclosure) == "function" and newcclosure or function(fn)
        return fn
    end
    local oldNamecall = nil
    remoteFunctionHookInstalled = pcall(function()
        oldNamecall = hookmetamethod(
            game,
            "__namecall",
            wrap(function(self, ...)
                local args = { ... }
                local method = getnamecallmethod()
                if method == "InvokeServer" then
                    local isRemoteFunction = false
                    pcall(function()
                        isRemoteFunction = self:IsA("RemoteFunction") and self.Name == "RemoteFunction"
                    end)
                    if isRemoteFunction then
                        local preparedSell = nil
                        local troopArgs = nil
                        if args[1] == "Troops" then
                            troopArgs = {}
                            for i = 3, #args do
                                troopArgs[i - 2] = args[i]
                            end
                            preparedSell = prepareTroopActionBeforeRemote(args[2], troopArgs)
                        end
                        local results = packResults(oldNamecall(self, ...))
                        if args[1] == "Troops" then
                            recordTroopActionIfAccepted(args[2], troopArgs, results, preparedSell)
                        elseif args[1] == "Voting" and args[2] == "Skip" then
                            recordSkipActionIfAccepted(results)
                        end
                        return unpackResults(results, 1, results.n)
                    end
                elseif method == "FireServer" then
                    local isRemoteEvent = false
                    pcall(function()
                        isRemoteEvent = self:IsA("RemoteEvent") and self.Name == "RemoteEvent"
                    end)
                    if isRemoteEvent and args[1] == "Consumables" and not consumablesFireHookInstalled then
                        local consumableArgs = {}
                        for i = 3, #args do
                            consumableArgs[i - 2] = args[i]
                        end
                        local preparedAction = prepareConsumableActionBeforeRemote(args[2], consumableArgs)
                        local results = packResults(oldNamecall(self, ...))
                        if preparedAction then
                            commitPreparedAction(preparedAction)
                        end
                        return unpackResults(results, 1, results.n)
                    end
                end
                return oldNamecall(self, ...)
            end)
        )
    end)
end
if remoteFunctionHookInstalled then
    addLog("RemoteFunction recorder hook active.", Color3.fromRGB(100, 220, 120))
else
    addLog(
        "RemoteFunction recorder hook unavailable; direct remote calls may need a supported executor.",
        Color3.fromRGB(255, 180, 80)
    )
end

-- Playback
local function countTowersNearPos(pos, radius)
    local towers = workspace:FindFirstChild("Towers")
    if not towers or not pos then
        return 0
    end
    local count = 0
    for _, tower in ipairs(towers:GetChildren()) do
        if tower:IsA("Model") and isOwnTower(tower) then
            local root = getTowerRoot(tower)
            if root and xzDistance(root.Position, pos) <= (radius or PLACE_VERIFY_RADIUS) then
                count += 1
            end
        end
    end
    return count
end

local function countOwnTowers()
    local towers = workspace:FindFirstChild("Towers")
    if not towers then
        return 0
    end
    local count = 0
    for _, tower in ipairs(towers:GetChildren()) do
        if tower:IsA("Model") and isOwnTower(tower) then
            count += 1
        end
    end
    return count
end

local towerLimitCacheValue = nil
local towerLimitCacheAt = 0
local function getDisplayedTowerLimit()
    if tick() - towerLimitCacheAt < 2 then
        return towerLimitCacheValue
    end
    towerLimitCacheAt = tick()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if not gui then
        return nil
    end
    for _, obj in ipairs(gui:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            local text = tostring(obj.Text or "")
            local lower = (text .. " " .. tostring(obj.Name)):lower()
            if
                (lower:find("tower", 1, true) or lower:find("troop", 1, true) or lower:find("unit", 1, true))
                and lower:find("limit", 1, true)
            then
                local _, limit = text:match("(%d+)%s*/%s*(%d+)")
                limit = tonumber(limit)
                if limit and limit >= 10 and limit <= 60 then
                    towerLimitCacheValue = limit
                    return limit
                end
            end
        end
    end
    towerLimitCacheValue = nil
    return nil
end

local function getEstimatedTowerLimit()
    local playerCount = math.max(1, #Players:GetPlayers())
    if playerCount <= 1 then
        return 40
    end
    if playerCount == 2 then
        return 30
    end
    if playerCount == 3 then
        return 25
    end
    return 20
end

local function getTowerLimitState()
    return countOwnTowers(), getDisplayedTowerLimit() or getEstimatedTowerLimit()
end

local function isRobloxInstance(value)
    local ok, result = pcall(function()
        return typeof(value) == "Instance"
    end)
    return ok and result == true
end

local function isPlacedTowerInstance(value)
    if not isRobloxInstance(value) then
        return false
    end
    local towers = workspace:FindFirstChild("Towers")
    if not towers then
        return false
    end
    local ok, result = pcall(function()
        return value:IsDescendantOf(towers)
    end)
    return ok and result == true
end

local function resultContainsPlacedTower(value, depth)
    depth = depth or 0
    if depth > 4 then
        return false
    end
    if isPlacedTowerInstance(value) then
        return true
    end
    if type(value) == "table" then
        for _, v in pairs(value) do
            if resultContainsPlacedTower(v, depth + 1) then
                return true
            end
        end
    end
    return false
end

local function resultFailureText(value, depth)
    depth = depth or 0
    if depth > 4 then
        return nil
    end
    local valueType = type(value)
    if valueType == "boolean" and value == false then
        return "server returned false"
    end
    if valueType == "string" then
        local text = value:lower()
        if
            text:find("not enough", 1, true)
            or text:find("insufficient", 1, true)
            or text:find("can't afford", 1, true)
            or text:find("can't ", 1, true)
            or text:find("cannot", 1, true)
            or text:find("need $", 1, true)
            or text:find("more to", 1, true)
            or text:find("too close", 1, true)
            or text:find("occupied", 1, true)
            or text:find("blocked", 1, true)
            or text:find("invalid", 1, true)
            or text:find("limit", 1, true)
            or text:find("max", 1, true)
            or text:find("denied", 1, true)
            or text:find("unable", 1, true)
            or text:find("rejected", 1, true)
            or text:find("failed", 1, true)
            or text:find("failure", 1, true)
            or text:find("error", 1, true)
        then
            return value
        end
    elseif valueType == "table" then
        for k, v in pairs(value) do
            local nested = resultFailureText(v, depth + 1)
            if nested then
                return nested
            end
            if type(k) == "string" then
                local key = k:lower()
                if (key == "error" or key == "err") and v ~= nil and v ~= false then
                    return tostring(v)
                end
            end
        end
    end
    return nil
end

local function getPlaceResultStatus(ok, result)
    if not ok then
        return false, "remote", tostring(result)
    end
    if resultContainsPlacedTower(result) then
        return true, "placed", nil
    end
    local failure = resultFailureText(result)
    if not failure then
        return nil, "unknown", nil
    end
    local text = failure:lower()
    if
        text:find("not enough", 1, true)
        or text:find("insufficient", 1, true)
        or text:find("can't afford", 1, true)
        or text:find("cannot afford", 1, true)
        or text:find("need $", 1, true)
        or text:find("more to place", 1, true)
    then
        return false, "cash", failure
    end
    if text:find("limit", 1, true) or text:find("max", 1, true) then
        return false, "slot", failure
    end
    if
        text:find("too close", 1, true)
        or text:find("occupied", 1, true)
        or text:find("blocked", 1, true)
        or text:find("invalid", 1, true)
        or text:find("cannot place", 1, true)
        or text:find("can't place", 1, true)
        or text:find("cannot", 1, true)
    then
        return false, "blocked", failure
    end
    return false, "retry", failure
end

local function waitForTowerCountIncrease(pos, beforeCount, timeout, shouldStop)
    timeout = timeout or 1
    local start = tick()
    while tick() - start < timeout do
        if shouldStop and shouldStop() then
            return false
        end
        if countTowersNearPos(pos, PLACE_VERIFY_RADIUS) > beforeCount then
            return true
        end
        task.wait(0.05)
    end
    return false
end

local function findTowerNearPos(pos, radius)
    if not pos then
        return nil
    end
    local towers = workspace:FindFirstChild("Towers")
    if not towers then
        return nil
    end
    local matchRadius = tonumber(radius) or TOWER_MATCH_RADIUS
    local best, bestDist = nil, math.huge
    for _, tower in ipairs(towers:GetChildren()) do
        if tower:IsA("Model") and isOwnTower(tower) then
            local root = getTowerRoot(tower)
            if root then
                local dist = xzDistance(root.Position, pos)
                if dist < bestDist and dist <= matchRadius then
                    best = tower
                    bestDist = dist
                end
            end
        end
    end
    return best
end

local function resolveAbilityDataValue(value, depth)
    depth = tonumber(depth) or 0
    if depth > 5 then
        return nil
    end
    if type(value) ~= "table" then
        return value
    end

    local marker = tostring(value.__zephyrType or value.__type or "")
    if marker == "Vector3" then
        return Vector3.new(
            tonumber(value.X or value.x) or 0,
            tonumber(value.Y or value.y) or 0,
            tonumber(value.Z or value.z) or 0
        )
    elseif marker == "Vector2" then
        return Vector2.new(tonumber(value.X or value.x) or 0, tonumber(value.Y or value.y) or 0)
    elseif marker == "CFrame" then
        local components = value.components or value.Components
        if type(components) == "table" and #components >= 12 then
            return CFrame.new(
                components[1],
                components[2],
                components[3],
                components[4],
                components[5],
                components[6],
                components[7],
                components[8],
                components[9],
                components[10],
                components[11],
                components[12]
            )
        end
        local pos = resolveAbilityDataValue(value.position or value.Position, depth + 1)
        if typeof(pos) == "Vector3" then
            return CFrame.new(pos)
        end
        return nil
    elseif marker == "TowerRef" then
        local pos = resolveAbilityDataValue(value.position or value.Position, depth + 1)
        if typeof(pos) == "Vector3" then
            return findTowerNearPos(pos, math.max(TOWER_MATCH_RADIUS, SELL_MATCH_RADIUS))
        end
        return nil
    elseif marker == "InstancePosition" then
        return resolveAbilityDataValue(value.position or value.Position, depth + 1)
    end

    local out = {}
    for k, v in pairs(value) do
        if k ~= "__zephyrType" and k ~= "__type" and (type(k) == "string" or type(k) == "number") then
            local resolved = resolveAbilityDataValue(v, depth + 1)
            if resolved ~= nil then
                out[k] = resolved
            end
        end
    end
    return out
end

local function resolveAbilityData(data)
    return resolveAbilityDataValue(data or {}, 0) or {}
end

local function doPlace(action, shouldStop, retryForever)
    local posVec = asVector3(action.data.position)
    if not posVec then
        addLog("Place skipped: position missing.", Color3.fromRGB(255, 120, 90))
        return false
    end
    if findTowerNearPos(posVec, PLACE_ALREADY_RADIUS) then
        return true
    end
    local start = tick()
    local timeout = retryForever and PLAYBACK_RETRY_FOREVER or PLACE_RETRY_TIMEOUT
    local waitingForSlot = false
    local lastReject = nil
    local lastCashLog = 0
    local function waitForSlot(count, limit)
        if not waitingForSlot then
            waitingForSlot = true
            addLog(
                ("Waiting for tower slot: %s (%s/%s)"):format(
                    tostring(action.data.tower),
                    tostring(count),
                    tostring(limit or "?")
                ),
                Color3.fromRGB(255, 200, 80)
            )
        end
        task.wait(0.5)
    end
    while Macro.playing and tick() - start < timeout do
        if shouldStop and shouldStop() then
            return false
        end
        if findTowerNearPos(posVec, PLACE_ALREADY_RADIUS) then
            return true
        end
        local towerCount, towerLimit = getTowerLimitState()
        if towerLimit and towerCount >= towerLimit then
            waitForSlot(towerCount, towerLimit)
            continue
        end
        local beforeCount = countTowersNearPos(posVec, PLACE_VERIFY_RADIUS)
        local remoteOk, result = invokeTroopsThrottled("Place", {
            Rotation = action.data.rotation,
            Position = posVec,
        }, action.data.tower)
        local placed, status, reason = getPlaceResultStatus(remoteOk, result)
        if
            placed
            or waitForTowerCountIncrease(posVec, beforeCount, 1.1, shouldStop)
            or findTowerNearPos(posVec, PLACE_ALREADY_RADIUS)
        then
            return true
        end
        if status == "blocked" then
            addLog(
                "Place blocked: " .. tostring(action.data.tower) .. " at recorded spot.",
                Color3.fromRGB(255, 120, 90)
            )
            return false
        elseif status == "slot" then
            towerCount, towerLimit = getTowerLimitState()
            waitForSlot(towerCount, towerLimit)
        elseif status == "cash" then
            if tick() - lastCashLog >= 6 then
                lastCashLog = tick()
                addLog(
                    "Waiting for cash: " .. tostring(action.data.tower) .. " ($" .. tostring(getCash()) .. ")",
                    Color3.fromRGB(255, 200, 80)
                )
            end
            task.wait(0.35)
        else
            local message = tostring(status or "retry") .. "|" .. tostring(reason or "")
            if message ~= lastReject and reason then
                lastReject = message
                addLog("Place retry: " .. tostring(reason), Color3.fromRGB(255, 180, 80))
            end
            task.wait(0.12)
        end
    end
    addLog("Place timed out: " .. tostring(action.data.tower), Color3.fromRGB(255, 120, 90))
    return false
end

local function doUpgrade(action, shouldStop, retryForever)
    local start = tick()
    local timeout = retryForever and PLAYBACK_RETRY_FOREVER or UPGRADE_RETRY_TIMEOUT
    local missingDeadline = start + UPGRADE_TARGET_FIND_TIMEOUT
    local lastMissingLog = 0
    local lastWaitLog = 0
    while Macro.playing and tick() - start < timeout do
        if shouldStop and shouldStop() then
            return false
        end
        local troop = findTowerNearPos(action.data.troopPos)
        if not troop then
            if tick() >= missingDeadline then
                addLog("Upgrade target missing; stopped at recorded position.", Color3.fromRGB(255, 120, 90))
                return false
            end
            if tick() - lastMissingLog >= 3 then
                lastMissingLog = tick()
                addLog("Waiting for upgrade target...", Color3.fromRGB(255, 200, 80))
            end
            task.wait(0.1)
            continue
        end
        local rep = troop:FindFirstChild("TowerReplicator")
        local levelBefore = rep and rep:GetAttribute("Upgrade") or 0
        invokeTroopsThrottled("Upgrade", "Set", {
            Troop = troop,
            Path = tonumber(action.data.path),
        })
        if waitForUpgrade(troop, levelBefore, 0.75) then
            return true
        end
        if retryForever and tick() - lastWaitLog >= 6 then
            lastWaitLog = tick()
            addLog("Waiting to upgrade ($" .. tostring(getCash()) .. ")", Color3.fromRGB(255, 200, 80))
        end
        task.wait(retryForever and 0.25 or 0.1)
    end
    addLog("Upgrade timed out.", Color3.fromRGB(255, 120, 90))
    return false
end

local function doSell(action, shouldStop)
    local start = tick()
    while Macro.playing and tick() - start < SELL_RETRY_TIMEOUT do
        if shouldStop and shouldStop() then
            return false
        end
        local troop = findTowerNearPos(action.data.troopPos, SELL_MATCH_RADIUS)
        if not troop then
            task.wait(0.1)
            continue
        end
        invokeTroopsThrottled("Sell", { Troop = troop })
        local s = tick()
        while tick() - s < 2 do
            if not troop.Parent then
                return true
            end
            if shouldStop and shouldStop() then
                return false
            end
            task.wait(0.1)
        end
    end
    addLog("Sell timed out", Color3.fromRGB(255, 120, 90))
    return false
end

local function doTarget(action, shouldStop)
    local start = tick()
    while Macro.playing and tick() - start < TARGET_RETRY_TIMEOUT do
        if shouldStop and shouldStop() then
            return false
        end
        local troop = findTowerNearPos(action.data.troopPos)
        if troop then
            invokeTroopsThrottled("Target", "Set", {
                Troop = troop,
                Target = action.data.target,
            })
            return true
        end
        task.wait(0.1)
    end
    addLog("Target timed out.", Color3.fromRGB(255, 120, 90))
    return false
end

local function doAbility(action, shouldStop)
    local start = tick()
    while Macro.playing and tick() - start < ABILITY_RETRY_TIMEOUT do
        if shouldStop and shouldStop() then
            return false
        end
        local troop = findTowerNearPos(action.data.troopPos)
        if troop then
            invokeTroopsThrottled("Abilities", "Activate", {
                Troop = troop,
                Name = action.data.name,
                Data = resolveAbilityData(action.data.abilityData),
            })
            return true
        end
        task.wait(0.1)
    end
    addLog("Ability timed out: " .. tostring(action.data.name), Color3.fromRGB(255, 120, 90))
    return false
end

local function doOption(action, shouldStop)
    local start = tick()
    while Macro.playing and tick() - start < OPTION_RETRY_TIMEOUT do
        if shouldStop and shouldStop() then
            return false
        end
        local troop = findTowerNearPos(action.data.troopPos)
        if troop then
            invokeTroopsThrottled("Option", "Set", {
                Troop = troop,
                Name = action.data.name,
                Value = action.data.value,
            })
            return true
        end
        task.wait(0.1)
    end
    addLog("Option timed out: " .. tostring(action.data.name), Color3.fromRGB(255, 120, 90))
    return false
end

local function doConsumable(action, shouldStop)
    if shouldStop and shouldStop() then
        return false
    end
    local data = action and action.data or {}
    local name = tostring(data.name or "")
    if name == "" then
        addLog("Consumable skipped: name missing.", Color3.fromRGB(255, 120, 90))
        return false
    end
    local payload = {}
    local hasPlacement
    if data.hasPlacement ~= nil then
        hasPlacement = data.hasPlacement == true
    else
        local pos = asVector3(data.position)
        hasPlacement = tostring(data.pathName or "") ~= ""
            or (pos and (math.abs(pos.X) > 0.01 or math.abs(pos.Y) > 0.01 or math.abs(pos.Z) > 0.01))
    end
    if hasPlacement then
        payload.pathName = tostring(data.pathName or "")
        payload.position = asVector3(data.position) or Vector3.new(0, 0, 0)
        payload.pathToEnd = tonumber(data.pathToEnd) or 0
        payload.direction = asVector3(data.direction) or Vector3.new(0, 0, 0)
    end
    local ok, result = fireConsumable("Consume", name, payload)
    if not ok then
        addLog("Consumable failed: " .. name .. " " .. tostring(result), Color3.fromRGB(255, 120, 90))
        return false
    end
    return true
end

local function playMacro(actions)
    if Macro.playing then
        Macro.playing = false
        return
    end
    if not actions or #actions == 0 then
        return
    end
    if Macro.recording then
        Macro.recording = false
        saveDraft(true)
        stopMacroClock()
        StartBtn.Text = "Start"
        StartBtn.BackgroundColor3 = Color3.fromRGB(50, 200, 100)
        addLog("Logging stopped before playback.", Color3.fromRGB(80, 80, 100))
    end
    local timingMode = actions.timingMode or Macro.timingMode or "wall"
    local useGameTiming = timingMode == "game"
    Macro.playing = true
    PlayBtn.Text = "Stop"
    PlayBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 60)

    local currentBeforeStart = getCurrentWave()
    if currentBeforeStart and currentBeforeStart > MACRO_START_WAVE then
        Macro.playing = false
        PlayBtn.Text = "Play"
        PlayBtn.BackgroundColor3 = Color3.fromRGB(140, 50, 255)
        addLog("Playback cancelled: start before or on Wave 1.", Color3.fromRGB(255, 100, 100))
        return
    end

    addLog("Waiting for Wave 1...", Color3.fromRGB(255, 200, 80))
    local started = waitForWave(MACRO_START_WAVE, MACRO_START_TIMEOUT, function()
        return not Macro.playing
    end)
    if not Macro.playing then
        PlayBtn.Text = "Play"
        PlayBtn.BackgroundColor3 = Color3.fromRGB(140, 50, 255)
        return
    end
    if not started then
        Macro.playing = false
        PlayBtn.Text = "Play"
        PlayBtn.BackgroundColor3 = Color3.fromRGB(140, 50, 255)
        addLog("Playback cancelled: Wave 1 not detected.", Color3.fromRGB(255, 100, 100))
        return
    end
    local waveAtStart = getCurrentWave()
    if waveAtStart and waveAtStart > MACRO_START_WAVE then
        Macro.playing = false
        PlayBtn.Text = "Play"
        PlayBtn.BackgroundColor3 = Color3.fromRGB(140, 50, 255)
        addLog("Playback cancelled: Wave 1 was missed.", Color3.fromRGB(255, 100, 100))
        return
    end

    local wallStart = tick()
    if useGameTiming then
        startMacroClock()
        addLog(("Playback timing: game-time x%.2f"):format(getGameTimeScale()), Color3.fromRGB(120, 220, 255))
    else
        addLog("Playback timing: legacy real-time.", Color3.fromRGB(120, 220, 255))
    end
    local highestWaveSeen = getCurrentWave() or MACRO_START_WAVE
    local function shouldStopPlayback()
        if isBaseDown() then
            return true
        end
        local current = getCurrentWave()
        if current and current > highestWaveSeen then
            highestWaveSeen = current
        end
        return current == ROUND_RESET_WAVE or (current == MACRO_START_WAVE and highestWaveSeen > MACRO_START_WAVE)
    end

    for _, action in ipairs(actions) do
        if not Macro.playing then
            break
        end
        if shouldStopPlayback() then
            break
        end
        if action.type == "Skip" and action.data.wave and action.data.wave > 0 then
            local current = getCurrentWave()
            if current and current < action.data.wave then
                local waveStart = tick()
                while Macro.playing and tick() - waveStart < MACRO_START_TIMEOUT do
                    if shouldStopPlayback() then
                        break
                    end
                    current = getCurrentWave()
                    if current and current >= action.data.wave then
                        break
                    end
                    task.wait(WAVE_DETECT_POLL)
                end
            end
        else
            if not waitForMacroTime(action.time, shouldStopPlayback, wallStart, useGameTiming) then
                break
            end
        end
        if not Macro.playing then
            break
        end
        if shouldStopPlayback() then
            break
        end
        local actionOk = true
        if action.type == "Place" then
            actionOk = doPlace(action, shouldStopPlayback, true)
        elseif action.type == "Upgrade" then
            actionOk = doUpgrade(action, shouldStopPlayback, true)
        elseif action.type == "Sell" then
            actionOk = doSell(action, shouldStopPlayback)
        elseif action.type == "Target" then
            actionOk = doTarget(action, shouldStopPlayback)
        elseif action.type == "Ability" then
            actionOk = doAbility(action, shouldStopPlayback)
        elseif action.type == "Option" then
            actionOk = doOption(action, shouldStopPlayback)
        elseif action.type == "Consumable" then
            actionOk = doConsumable(action, shouldStopPlayback)
        elseif action.type == "TimeScaleUnlock" then
            actionOk = doTimeScaleUnlock()
        elseif action.type == "TimeScale" then
            actionOk = doTimeScale(action)
        elseif action.type == "Skip" then
            voteSkip()
            actionOk = true
        end
        if actionOk == false then
            if shouldStopPlayback() then
                break
            end
            addLog(
                "Playback stopped: " .. tostring(action.type) .. " failed instead of skipping.",
                Color3.fromRGB(255, 100, 100)
            )
            break
        end
    end

    Macro.playing = false
    stopMacroClock()
    PlayBtn.Text = "Play"
    PlayBtn.BackgroundColor3 = Color3.fromRGB(140, 50, 255)
end

task.spawn(function()
    while true do
        task.wait(0.5)
        if Macro.playing and isBaseDown() then
            while Macro.playing and isBaseDown() do
                voteSkip()
                task.wait(0.3)
            end
        end
    end
end)

StartBtn.MouseButton1Click:Connect(function()
    if Macro.recording then
        Macro.recording = false
        Macro.startTime = nil
        stopMacroClock()
        saveDraft(true)
        StartBtn.Text = "Start"
        StartBtn.BackgroundColor3 = Color3.fromRGB(50, 200, 100)
        addLog("Logging stopped.", Color3.fromRGB(80, 80, 100))
    else
        Macro.playing = false
        Macro.recording = true
        Macro.actions = {}
        Macro.actions.timingMode = "game"
        Macro.timingMode = "game"
        Macro.createdAt = getIsoNow()
        Macro.startTime = nil
        lastRecordedTimeScale = nil
        lastRecordedTimeScaleAt = 0
        lastRecordSignature = nil
        lastRecordAt = 0
        lastRecordBySignature = {}
        stopMacroClock()
        clearDraft()
        PlayBtn.Text = "Play"
        PlayBtn.BackgroundColor3 = Color3.fromRGB(140, 50, 255)
        StartBtn.Text = "Stop Logging"
        StartBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 60)
        for _, child in ipairs(LogScroll:GetChildren()) do
            if child:IsA("TextLabel") then
                child:Destroy()
            end
        end
        visibleLogLines = {}
        lastLogText = nil
        lastLogAt = 0
        addLog("Waiting for Wave 1...", Color3.fromRGB(255, 200, 80))
        task.spawn(function()
            local started = waitForWave(MACRO_START_WAVE, MACRO_START_TIMEOUT, function()
                return not Macro.recording
            end)
            if not Macro.recording then
                return
            end
            if started then
                startMacroClock()
                addLog(
                    ("Logging started. Game-time timing x%.2f."):format(getGameTimeScale()),
                    Color3.fromRGB(100, 220, 120)
                )
            else
                Macro.recording = false
                StartBtn.Text = "Start"
                StartBtn.BackgroundColor3 = Color3.fromRGB(50, 200, 100)
                addLog("Logging cancelled: Wave 1 not detected.", Color3.fromRGB(255, 100, 100))
            end
        end)
    end
end)

ClearBtn.MouseButton1Click:Connect(function()
    Macro.actions = {}
    Macro.recording = false
    Macro.playing = false
    Macro.startTime = nil
    Macro.timingMode = "wall"
    Macro.createdAt = nil
    lastRecordSignature = nil
    lastRecordAt = 0
    lastRecordBySignature = {}
    stopMacroClock()
    StartBtn.Text = "Start"
    StartBtn.BackgroundColor3 = Color3.fromRGB(50, 200, 100)
    PlayBtn.Text = "Play"
    PlayBtn.BackgroundColor3 = Color3.fromRGB(140, 50, 255)
    for _, child in ipairs(LogScroll:GetChildren()) do
        if child:IsA("TextLabel") then
            child:Destroy()
        end
    end
    visibleLogLines = {}
    lastLogText = nil
    lastLogAt = 0
    ImportInput.Text = ""
    clearDraft()
    addLog("Logging stopped.", Color3.fromRGB(80, 80, 100))
end)

CopyBtn.MouseButton1Click:Connect(function()
    local text = getExportText()
    saveDraft(true)
    local copied = false
    if type(setclipboard) == "function" then
        copied = pcall(function()
            setclipboard(text)
        end)
    end
    if not copied and type(writefile) == "function" then
        copied = pcall(function()
            writefile("zephyr_tds_strat.txt", text)
        end)
    end
    CopyBtn.Text = copied and "Copied!" or "Copy Failed"
    task.delay(1.5, function()
        if CopyBtn and CopyBtn.Parent then
            CopyBtn.Text = "Copy"
        end
    end)
end)

PlayBtn.MouseButton1Click:Connect(function()
    if Macro.playing then
        Macro.playing = false
        stopMacroClock()
        PlayBtn.Text = "Play"
        PlayBtn.BackgroundColor3 = Color3.fromRGB(140, 50, 255)
        return
    end
    local actions = Macro.actions
    if ImportInput.Text ~= "" then
        local parsed = parseAndLoad(ImportInput.Text)
        if parsed and #parsed > 0 then
            actions = parsed
        end
    end
    task.spawn(playMacro, actions)
end)

local dragging, dragStart, startPos

TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if
        dragging
        and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch)
    then
        local delta = input.Position - dragStart
        Main.Position =
            UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        clampRecorderPosition(Main)
    end
end)
