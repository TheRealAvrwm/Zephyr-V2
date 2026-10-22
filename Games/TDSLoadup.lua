spawn(function()
local VirtualUser = game:GetService('VirtualUser')
 
game:GetService('Players').LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)
end)
repeat
    task.wait()
until game:IsLoaded()
ZephyrExecutorName = "Unknown"
ZephyrLowCompatExecutor = false
pcall(function()
    if type(identifyexecutor) == "function" then
        local name = identifyexecutor()
        ZephyrExecutorName = tostring(name or "Unknown")
    end
end)
do
    local lower = ZephyrExecutorName:lower()
    ZephyrLowCompatExecutor = lower:find("solara", 1, true) ~= nil or lower:find("xeno", 1, true) ~= nil
end

function zephyrGlobalFunction(name)
    name = tostring(name or "")
    if
        ZephyrLowCompatExecutor
        and (name == "getgenv" or name == "firesignal" or name == "getconnections" or name == "debug.traceback")
    then
        return nil
    end

    local ok, value = pcall(function()
        local env = _G
        if type(getfenv) == "function" then
            local envOk, got = pcall(getfenv, 0)
            if envOk and type(got) == "table" then
                env = got
            end
        end
        return env and env[name] or _G[name]
    end)

    if ok and type(value) == "function" then
        return value
    end
    return nil
end

function zephyrGetRuntimeEnv()
    local getgenvFn = zephyrGlobalFunction("getgenv")
    if getgenvFn then
        local ok, genv = pcall(getgenvFn)
        if ok and type(genv) == "table" then
            return genv
        end
    end
    return _G
end

function zephyrTraceback(err)
    if ZephyrLowCompatExecutor then
        return tostring(err)
    end
    local dbg = nil
    pcall(function()
        dbg = debug
    end)
    if type(dbg) == "table" and type(dbg.traceback) == "function" then
        local ok, trace = pcall(dbg.traceback, tostring(err), 2)
        if ok and type(trace) == "string" then
            return trace
        end
    end
    return tostring(err)
end

function zephyrWaitForLocalPlayer(timeout)
    timeout = tonumber(timeout) or 20
    local start = tick()
    while tick() - start < timeout do
        local loaded = true
        pcall(function()
            loaded = game:IsLoaded()
        end)
        if loaded then
            break
        end
        task.wait(0.05)
    end
    local PlayersService = game:GetService("Players")
    local player = PlayersService.LocalPlayer
    while not player and tick() - start < timeout do
        task.wait(0.05)
        player = PlayersService.LocalPlayer
    end
    return player
end

ZephyrRuntimeEnv = zephyrGetRuntimeEnv()
ZephyrRuntimeEnv.__ZephyrTdsRuntimeState = ZephyrRuntimeEnv.__ZephyrTdsRuntimeState or {}

do
    local oldCleanup = ZephyrRuntimeEnv.__ZEPHYR_TDS_CLEANUP
    if type(oldCleanup) == "function" then
        pcall(oldCleanup)
    end
end

pcall(function()
    local player = game:GetService("Players").LocalPlayer
    local playerGui = player and player:FindFirstChild("PlayerGui")
    if not playerGui then
        return
    end
    for _, child in ipairs(playerGui:GetChildren()) do
        if child.Name == "ZephyrTDS" then
            child:Destroy()
        end
    end
end)

local runtimeAlive = true
local runtimeCleanupCallbacks = {}
function registerRuntimeCleanup(fn)
    if type(fn) ~= "function" then
        return
    end
    if not runtimeAlive then
        pcall(fn)
        return
    end
    table.insert(runtimeCleanupCallbacks, fn)
end

ZephyrRuntimeEnv.__ZEPHYR_TDS_CLEANUP = function()
    if not runtimeAlive then
        return
    end
    runtimeAlive = false
    for i = #runtimeCleanupCallbacks, 1, -1 do
        pcall(runtimeCleanupCallbacks[i])
    end
end

function clearTable(t)
    if type(table) == "table" and type(table.clear) == "function" then
        table.clear(t)
        return
    end
    for k in pairs(t) do
        t[k] = nil
    end
end

-- Pickups
pickupFarmRunning = false
pickupFarmThread = nil
pickupSession = 0
pickupAttemptAt = setmetatable({}, { __mode = "k" })
PICKUP_NAMES = { ["Bunz"] = true, ["Lorebook"] = true }
PICKUP_CONTAINERS = { "Pickups", "ForcedPickups" }
PICKUP_SCAN_INTERVAL = 0.3
PICKUP_EMPTY_SCAN_INTERVAL = 0.7
PICKUP_RETRY_DELAY = 0.45
PICKUP_HOLD_TIME = 0.4
PICKUP_TOUCH_HEIGHT = 2.75
PICKUP_MAX_PER_SWEEP = 80

function getPickupHRP()
    local player = game:GetService("Players").LocalPlayer
    if not player then
        return nil
    end
    local character = player.Character
    if not character then
        return nil
    end
    return character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
end

function waitForPickupHRP()
    local player = game:GetService("Players").LocalPlayer
    if not player then
        return nil
    end
    local character = player.Character or player.CharacterAdded:Wait()
    return character:FindFirstChild("HumanoidRootPart")
        or character:WaitForChild("HumanoidRootPart", 4)
        or character.PrimaryPart
end

function hasPickupName(obj)
    local current = obj
    while current and current ~= workspace do
        if PICKUP_NAMES[current.Name] then
            return true
        end
        if current.Name == "Pickups" or current.Name == "ForcedPickups" then
            return false
        end
        current = current.Parent
    end
    return false
end

function isValidPickupPart(part)
    if not part or not part.Parent or not part:IsA("BasePart") then
        return false
    end
    if not hasPickupName(part) then
        return false
    end
    local ok, alive = pcall(function()
        return part:IsDescendantOf(workspace)
    end)
    if not ok or not alive then
        return false
    end
    local pos = part.Position
    if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then
        return false
    end
    if pos.Y < -500 or pos.Y > 5000 then
        return false
    end
    return true
end

function getPickupContainers()
    local containers = {}
    for _, name in ipairs(PICKUP_CONTAINERS) do
        local container = workspace:FindFirstChild(name)
        if container then
            table.insert(containers, container)
        end
    end
    return containers
end

function findNearestPickup()
    local hrp = getPickupHRP()
    if not hrp then
        return nil
    end

    local bestPart, bestDistance
    local scanned = 0
    for _, container in ipairs(getPickupContainers()) do
        for _, obj in ipairs(container:GetDescendants()) do
            if obj:IsA("BasePart") then
                scanned += 1
                if scanned > PICKUP_MAX_PER_SWEEP then
                    break
                end
                if isValidPickupPart(obj) then
                    local lastAttempt = pickupAttemptAt[obj]
                    if not lastAttempt or tick() - lastAttempt >= PICKUP_RETRY_DELAY then
                        local distance = (obj.Position - hrp.Position).Magnitude
                        if not bestDistance or distance < bestDistance then
                            bestPart = obj
                            bestDistance = distance
                        end
                    end
                end
            end
        end
    end
    return bestPart
end

function setPickupRootCFrame(hrp, cframe)
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
    hrp.CFrame = cframe
end

function collectPickupPart(part, session)
    if not isValidPickupPart(part) then
        return false
    end
    pickupAttemptAt[part] = tick()

    local hrp = getPickupHRP() or waitForPickupHRP()
    if not hrp or not hrp.Parent then
        return false
    end

    local savedCFrame = hrp.CFrame
    local savedVelocity = hrp.AssemblyLinearVelocity
    local savedAngularVelocity = hrp.AssemblyAngularVelocity
    local lookVector = savedCFrame.LookVector
    local ok = pcall(function()
        local started = tick()
        while pickupFarmRunning and pickupSession == session and tick() - started < PICKUP_HOLD_TIME do
            if not isValidPickupPart(part) then
                break
            end
            local target = part.Position + Vector3.new(0, PICKUP_TOUCH_HEIGHT, 0)
            setPickupRootCFrame(hrp, CFrame.new(target, target + lookVector))
            task.wait(0.035)
        end
    end)

    if pickupFarmRunning and pickupSession == session and hrp and hrp.Parent then
        pcall(function()
            hrp.CFrame = savedCFrame
            hrp.AssemblyLinearVelocity = savedVelocity
            hrp.AssemblyAngularVelocity = savedAngularVelocity
        end)
    end

    if not ok then
        return false
    end
    return not isValidPickupPart(part)
end

function startPickupFarm()
    if pickupFarmRunning then
        return true
    end
    pickupFarmRunning = true
    pickupSession += 1
    local session = pickupSession
    pickupFarmThread = task.spawn(function()
        while pickupFarmRunning and pickupSession == session do
            local part = findNearestPickup()
            if part then
                collectPickupPart(part, session)
                task.wait(PICKUP_SCAN_INTERVAL)
            else
                task.wait(PICKUP_EMPTY_SCAN_INTERVAL)
            end
        end
        if pickupSession == session then
            pickupFarmThread = nil
        end
    end)
    return true
end

function stopPickupFarm()
    pickupFarmRunning = false
    pickupSession += 1
    clearTable(pickupAttemptAt)
    if pickupFarmThread then
        task.cancel(pickupFarmThread)
        pickupFarmThread = nil
    end
end

-- Services
TweenService = game:GetService("TweenService")
Players = game:GetService("Players")
UserInputService = game:GetService("UserInputService")
RunService = game:GetService("RunService")
ReplicatedStorage = game:GetService("ReplicatedStorage")
CollectionService = game:GetService("CollectionService")
Lighting = game:GetService("Lighting")
SoundService = game:GetService("SoundService")
MarketplaceService = game:GetService("MarketplaceService")
ZephyrTdsStartedAt = tick()
LocalPlayer = zephyrWaitForLocalPlayer(90) or Players.LocalPlayer
while not LocalPlayer do
    warn("[Zephyr] Waiting for LocalPlayer before booting TDS UI...")
    task.wait(0.25)
    LocalPlayer = Players.LocalPlayer
end
function zephyrWaitForPlayerGui(player, timeout)
    timeout = tonumber(timeout) or 90
    local start = tick()
    local gui = player and player:FindFirstChildOfClass("PlayerGui")
    while not gui and tick() - start < timeout do
        if player then
            local ok, result = pcall(function()
                return player:WaitForChild("PlayerGui", 0.5)
            end)
            if ok and result then
                gui = result
            end
            if not gui then
                gui = player:FindFirstChildOfClass("PlayerGui")
            end
        end
        if not gui then
            task.wait(0.1)
        end
    end
    return gui
end
PlayerGui = zephyrWaitForPlayerGui(LocalPlayer, UserInputService.TouchEnabled and 120 or 90)
while not PlayerGui do
    warn("[Zephyr] Waiting for PlayerGui before booting TDS UI...")
    task.wait(0.5)
    PlayerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
end
HttpService = game:GetService("HttpService")
requireBlockedReason = nil

function safeRequire(module, label)
    if not module then
        return nil, "missing module"
    end
    if type(require) ~= "function" then
        requireBlockedReason = requireBlockedReason or "require unavailable"
        return nil, requireBlockedReason
    end

    local ok, result = pcall(require, module)
    if ok then
        return result, nil
    end

    local reason = tostring(result)
    if reason:lower():find("cannot require", 1, true) then
        requireBlockedReason = requireBlockedReason or reason
    end
    return nil, label and (tostring(label) .. ": " .. reason) or reason
end

function findPath(root, ...)
    local current = root
    for i = 1, select("#", ...) do
        if not current then
            return nil
        end
        local name = select(i, ...)
        current = current:FindFirstChild(name)
    end
    return current
end

function safeRequirePath(label, root, ...)
    return safeRequire(findPath(root, ...), label)
end

AUTOEXEC_UI_READY_TIMEOUT = UserInputService.TouchEnabled and 45 or 25
AUTOEXEC_FEATURE_START_DELAY = 1.5
MOBILE_TDS_REQUIRE_GRACE = 25

function isTdsInterfaceScreenName(name)
    name = tostring(name or "")
    if name == "GameGui" or name == "LobbyGui" or name == "SharedGui" or name == "Interface" then
        return true
    end
    return name:sub(1, 9) == "ReactGame"
        or name:sub(1, 14) == "ReactUniversal"
        or name:sub(1, 14) == "ReactOverrides"
        or name == "ReactUpgrades"
        or name == "ReactOldUpgrades"
        or name == "SoundGui"
end

function getWorkspaceType()
    local typeValue = workspace:FindFirstChild("Type")
    if typeValue then
        local ok, value = pcall(function()
            return typeValue.Value
        end)
        if ok and type(value) == "string" then
            return value
        end
    end
    return ""
end

function getTdsInterfaceCounts()
    local counts = { total = 0, universal = 0, game = 0 }
    if not PlayerGui then
        return counts
    end
    for _, child in ipairs(PlayerGui:GetChildren()) do
        if child:IsA("ScreenGui") and isTdsInterfaceScreenName(child.Name) then
            counts.total += 1
            if child.Name:sub(1, 14) == "ReactUniversal" or child.Name:sub(1, 14) == "ReactOverrides" then
                counts.universal += 1
            elseif
                child.Name:sub(1, 9) == "ReactGame"
                or child.Name == "ReactUpgrades"
                or child.Name == "ReactOldUpgrades"
            then
                counts.game += 1
            end
        end
    end
    return counts
end

function tdsUiLooksMounted()
    local counts = getTdsInterfaceCounts()
    local workspaceType = getWorkspaceType()

    if workspaceType == "Game" then
        return PlayerGui:FindFirstChild("GameGui") ~= nil
            or PlayerGui:FindFirstChild("ReactGameTopGameDisplay") ~= nil
            or PlayerGui:FindFirstChild("ReactGameHotbar") ~= nil
            or counts.game >= 3
    end

    if workspaceType == "Lobby" then
        return PlayerGui:FindFirstChild("LobbyGui") ~= nil
            or PlayerGui:FindFirstChild("SharedGui") ~= nil
            or PlayerGui:FindFirstChild("ReactUniversalTopbar") ~= nil
            or counts.universal >= 2
    end

    return counts.game > 0
        or counts.universal > 0
        or PlayerGui:FindFirstChild("GameGui") ~= nil
        or PlayerGui:FindFirstChild("LobbyGui") ~= nil
end

function tdsBackendLooksReady()
    if getWorkspaceType() ~= "" then
        return true
    end

    local network = ReplicatedStorage:FindFirstChild("Network")
    if network then
        local children = network:GetChildren()
        if
            #children > 0
            or network:FindFirstChild("LobbyVoting")
            or network:FindFirstChild("Elevators")
            or network:FindFirstChild("Modifiers")
        then
            return true
        end
    end

    if ReplicatedStorage:FindFirstChild("RemoteEvent") and ReplicatedStorage:FindFirstChild("RemoteFunction") then
        return true
    end

    local shared = ReplicatedStorage:FindFirstChild("Shared")
    local client = ReplicatedStorage:FindFirstChild("Client")
    return shared ~= nil and client ~= nil
end

function repairTdsInterfaceScreens()
    if not PlayerGui then
        return 0
    end
    local repaired = 0
    for _, child in ipairs(PlayerGui:GetChildren()) do
        if child:IsA("ScreenGui") and isTdsInterfaceScreenName(child.Name) then
            local okEnabled, enabled = pcall(function()
                return child.Enabled
            end)
            local shouldBeEnabled = child.Name == "GameGui"
                or child.Name == "LobbyGui"
                or child.Name == "SharedGui"
                or child.Name == "Interface"
                or child.Name == "ReactGameTopGameDisplay"
                or child.Name == "ReactGameHotbar"
                or child.Name == "ReactUniversalTopbar"
                or child.Name == "ReactUniversalHotbar"
            if shouldBeEnabled and okEnabled and enabled == false then
                pcall(function()
                    child.Enabled = true
                end)
                repaired += 1
            end
            if child.Name:sub(1, 5) == "React" or child.Name == "SoundGui" then
                pcall(function()
                    child.ResetOnSpawn = false
                end)
            end
        end
    end
    return repaired
end

function canSafelyRequireTdsModules()
    -- Requiring modules before TDS does can break its startup on mobile.
    if UserInputService.TouchEnabled and tick() - ZephyrTdsStartedAt < MOBILE_TDS_REQUIRE_GRACE then
        return false
    end
    return tdsUiLooksMounted()
end

function tryInitTdsInterfaces()
    -- Leave interface initialization to TDS.
    return false
end

function waitForTdsUiReady(timeout)
    timeout = tonumber(timeout) or AUTOEXEC_UI_READY_TIMEOUT
    if not game:IsLoaded() then
        pcall(function()
            game.Loaded:Wait()
        end)
    end

    local start = tick()
    while tick() - start < timeout do
        repairTdsInterfaceScreens()
        if tdsUiLooksMounted() and tdsBackendLooksReady() then
            task.wait(UserInputService.TouchEnabled and 1.25 or 0.35)
            return true
        end
        task.wait(0.25)
    end

    local settleStart = tick()
    while tick() - settleStart < 2 do
        repairTdsInterfaceScreens()
        if tdsUiLooksMounted() and tdsBackendLooksReady() then
            return true
        end
        task.wait(0.25)
    end
    return false
end

function startTdsUiRepairWindow(duration)
    duration = tonumber(duration) or 20
    task.spawn(function()
        local start = tick()
        while runtimeAlive ~= false and tick() - start < duration do
            repairTdsInterfaceScreens()
            task.wait(0.5)
        end
    end)
end

GameState = nil
pcall(function()
    if canSafelyRequireTdsModules() then
        local shared = ReplicatedStorage:FindFirstChild("Shared")
        local modules = shared and shared:FindFirstChild("Modules")
        local gameStateModule = modules and modules:FindFirstChild("GameState")
        if gameStateModule then
            GameState = safeRequire(gameStateModule, "Shared.Modules.GameState")
        end
    end
end)

-- Settings
SETTINGS_FOLDER = "ZephyrTDS"
SETTINGS_FILE = SETTINGS_FOLDER .. "/Settings.json"
LEGACY_SETTINGS_FILE = "ZephyrTDSSettings.json"
TDS_FEEDBACK_HOST = "https://zephyr-tds-feedback.avrwmbusiness.workers.dev"
settingsDefaults = {
    autoskipEnabled = false,
    espEnabled = false,
    gatlingEnabled = false,
    pickupFarmEnabled = false,
    autoRestartEnabled = false,
    autoRerunStratsEnabled = false,
    playbackMoneyModeEnabled = false,
    autoReadyEnabled = false,
    modifierVoteEnabled = false,
    streamerModeEnabled = false,
    matchTrackerEnabled = false,
    enemyInspectorEnabled = false,
    abilityManagerEnabled = false,
    autoUpgradeEnabled = false,
    autoUpgradeFarmsEnabled = false,
    resultsTrackerEnabled = false,
    commanderChainEnabled = false,
    supportCaravanEnabled = false,
    unlockTowersClientEnabled = false,
    unlockSkinsClientEnabled = false,
    unlockEmotesClientEnabled = false,
    unlockCosmeticsClientEnabled = false,
    skinChangerEnabled = false,
    skinChangerSelections = {},
    gatlingFireDelay = 0.01,
    gatlingFireRateTicks = 60,
    gatlingMode = "FPS",
    gatlingBurstCount = 12,
    gatlingTargetMode = "First",
    gatlingMaxTargets = 5,
    gatlingBulletLinesEnabled = false,
    gatlingHitsoundsDisabled = false,
    gatlingTargetEsp = "Off",
    autoClaimAllEnabled = false,
    autoAirstrikeEnabled = false,
    autoAirstrikeTarget = "Grouped",
    autoPursuitPositionEnabled = false,
    autoPursuitPositionTarget = "Grouped",
    modifierVoteText = "",
    resultsWebhookUrl = "",
    resultsWebhookIntervalMinutes = 60,
    towerStackName = "",
    autoRejoin = {
        enabled = false,
        map = "",
        mode = "Easy",
        modeUserSet = false,
        modeAutoFilled = false,
    },
    keybinds = {},
    favoriteStrats = {},
    stratVotes = {},
    stratReports = {},
    customStrats = {},
    lastStrat = nil,
}

KNOWN_MODIFIER_ENTRIES = {
    { id = "HiddenEnemies", display = "Hidden Enemies", aliases = { "Hidden Enemies", "Hidden" } },
    { id = "Glass", display = "Glass", aliases = {} },
    { id = "JailedTowers", display = "Jailed", aliases = { "Jailed Towers", "Jailed", "Jail" } },
    { id = "ExplodingEnemies", display = "Exploding Enemies", aliases = { "Exploding Enemies", "Exploding" } },
    { id = "Limitation", display = "Limitation", aliases = { "Limitation Makes Creativity" } },
    { id = "Committed", display = "Committed", aliases = {} },
    { id = "HealthyEnemies", display = "Healthy Enemies", aliases = { "Healthy Enemies", "Healthy" } },
    { id = "SpeedyEnemies", display = "Speedy Enemies", aliases = { "Speedy Enemies", "Speedy" } },
    { id = "Fog", display = "Fog", aliases = {} },
    { id = "FlyingEnemies", display = "Flying Enemies", aliases = { "Flying Enemies", "Flying" } },
    { id = "Broke", display = "Broke", aliases = { "Flying Enemies Broke" } },
    { id = "Quarantine", display = "Quarantine", aliases = {} },
    { id = "Inflation", display = "Inflation", aliases = {} },
}

function settingsText(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

function settingsLookupKey(value)
    return tostring(value or ""):lower():gsub("[^%w]", "")
end

function splitSettingsList(value)
    local out = {}
    for part in tostring(value or ""):gmatch("[^,\r\n]+") do
        local clean = settingsText(part)
        if clean ~= "" then
            table.insert(out, clean)
        end
    end
    return out
end

modifierLookupByKey = {}
legacyBrokenModifierLookupByKey = {}
for _, entry in ipairs(KNOWN_MODIFIER_ENTRIES) do
    entry.display = entry.display or entry.id
    entry.key = settingsLookupKey(entry.id)
    modifierLookupByKey[entry.key] = entry
    modifierLookupByKey[settingsLookupKey(entry.display)] = entry
    legacyBrokenModifierLookupByKey[entry.key:gsub("n", "")] = entry
    legacyBrokenModifierLookupByKey[settingsLookupKey(entry.display):gsub("n", "")] = entry
    for _, alias in ipairs(entry.aliases or {}) do
        local aliasKey = settingsLookupKey(alias)
        modifierLookupByKey[aliasKey] = entry
        legacyBrokenModifierLookupByKey[aliasKey:gsub("n", "")] = entry
    end
end

function cloneSettingsValue(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = cloneSettingsValue(v)
    end
    return out
end

function mergeSettings(defaults, saved)
    local out = cloneSettingsValue(defaults)
    if type(saved) ~= "table" then
        return out
    end
    for k, v in pairs(saved) do
        if type(v) == "table" and type(out[k]) == "table" then
            out[k] = mergeSettings(out[k], v)
        else
            out[k] = v
        end
    end
    return out
end

function ensureSettingsFolder()
    if type(isfolder) == "function" then
        local ok, exists = pcall(function()
            return isfolder(SETTINGS_FOLDER)
        end)
        if ok and exists then
            return true
        end
    end
    if type(makefolder) == "function" then
        local ok = pcall(function()
            makefolder(SETTINGS_FOLDER)
        end)
        if ok then
            return true
        end
    end
    return false
end

function readSettingsFile(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end
    -- isfile can return false here even when readfile works.
    local readOk, raw = pcall(function()
        return readfile(path)
    end)
    if not readOk or type(raw) ~= "string" or raw == "" then
        return nil
    end
    local decodeOk, decoded = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if not decodeOk or type(decoded) ~= "table" then
        return nil
    end
    return decoded
end

function getSettingsFreshness(settings)
    if type(settings) ~= "table" then
        return 0
    end
    local newest = tonumber(settings.settingsSavedAt) or 0
    local saved = settings.lastStrat
    if type(saved) == "table" then
        newest = math.max(newest, tonumber(saved.savedAt) or 0)
    end
    return newest
end

function loadSettings()
    if type(readfile) ~= "function" then
        return cloneSettingsValue(settingsDefaults), nil
    end

    local saved = readSettingsFile(SETTINGS_FILE)
    local legacySaved = readSettingsFile(LEGACY_SETTINGS_FILE)
    if saved and legacySaved then
        if getSettingsFreshness(legacySaved) > getSettingsFreshness(saved) then
            return mergeSettings(settingsDefaults, legacySaved), LEGACY_SETTINGS_FILE
        end
        return mergeSettings(settingsDefaults, saved), SETTINGS_FILE
    end

    if saved then
        return mergeSettings(settingsDefaults, saved), SETTINGS_FILE
    end

    if legacySaved then
        return mergeSettings(settingsDefaults, legacySaved), LEGACY_SETTINGS_FILE
    end

    return cloneSettingsValue(settingsDefaults), nil
end

tdsSettings, loadedSettingsPath = loadSettings()
settingsSaveQueued = false

function saveSettingsNow()
    if type(writefile) ~= "function" then
        return false
    end
    tdsSettings.settingsSavedAt = os.time()
    local encodeOk, encoded = pcall(function()
        return HttpService:JSONEncode(tdsSettings)
    end)
    if not encodeOk or type(encoded) ~= "string" then
        return false
    end

    ensureSettingsFolder()
    local writeOk = pcall(function()
        writefile(SETTINGS_FILE, encoded)
    end)
    local legacyWriteOk = pcall(function()
        writefile(LEGACY_SETTINGS_FILE, encoded)
    end)
    if writeOk then
        loadedSettingsPath = SETTINGS_FILE
        return true
    end

    if legacyWriteOk then
        loadedSettingsPath = LEGACY_SETTINGS_FILE
    end
    return legacyWriteOk
end

function saveSettingsSoon()
    if settingsSaveQueued then
        return
    end
    settingsSaveQueued = true
    task.delay(0.25, function()
        if not runtimeAlive then
            return
        end
        settingsSaveQueued = false
        saveSettingsNow()
    end)
end

function setSetting(key, value)
    tdsSettings[key] = value
    saveSettingsSoon()
end

function setNestedSetting(group, key, value)
    if type(tdsSettings[group]) ~= "table" then
        tdsSettings[group] = {}
    end
    tdsSettings[group][key] = value
    saveSettingsSoon()
end

function ensureSettingsTable(key)
    if type(tdsSettings[key]) ~= "table" then
        tdsSettings[key] = {}
    end
    return tdsSettings[key]
end

function sanitizeLoadedSettings()
    local changed = false

    local selected, seen = {}, {}
    local rawParts = splitSettingsList(tdsSettings.modifierVoteText)
    local index = 1
    while index <= #rawParts do
        local raw = rawParts[index]
        local clean = settingsText(raw)
        local key = settingsLookupKey(clean)
        local entry = modifierLookupByKey[key]
        local endIndex = index
        if not entry and key ~= "" then
            local combinedKey = ""
            for candidateIndex = index, math.min(index + 3, #rawParts) do
                combinedKey = combinedKey .. settingsLookupKey(rawParts[candidateIndex])
                local legacyEntry = legacyBrokenModifierLookupByKey[combinedKey]
                if legacyEntry then
                    entry = legacyEntry
                    endIndex = candidateIndex
                end
            end
        end
        local id = entry and entry.id or clean
        local dedupeKey = entry and entry.key or key
        if id ~= "" and not seen[dedupeKey] then
            seen[dedupeKey] = true
            table.insert(selected, id)
        end
        index = endIndex + 1
    end
    local modifierText = table.concat(selected, ", ")
    if tdsSettings.modifierVoteText ~= modifierText then
        tdsSettings.modifierVoteText = modifierText
        changed = true
    end

    if type(tdsSettings.lastStrat) == "table" and tdsSettings.lastStrat.savedBy ~= "ZephyrTDS" then
        local old = tdsSettings.lastStrat
        local hasContent = type(old.stratContent) == "string" and old.stratContent:match("%S") ~= nil
        local hasUrl = type(old.stratUrl) == "string" and old.stratUrl:match("^%s*https?://") ~= nil
        if hasContent or hasUrl then
            old.savedBy = "ZephyrTDS"
            old.schema = 2
            old.savedAt = tonumber(old.savedAt) or os.time()
        else
            tdsSettings.lastStrat = nil
        end
        changed = true
    end

    if type(tdsSettings.autoRejoin) ~= "table" then
        tdsSettings.autoRejoin = cloneSettingsValue(settingsDefaults.autoRejoin)
        changed = true
    end

    -- Don't restore unlock toggles; they replace the inventory lists.
    if tdsSettings.unlockSkinsClientEnabled == true then
        tdsSettings.unlockSkinsClientEnabled = false
        changed = true
    end
    if tdsSettings.unlockTowersClientEnabled == true then
        tdsSettings.unlockTowersClientEnabled = false
        changed = true
    end
    if tdsSettings.unlockEmotesClientEnabled == true then
        tdsSettings.unlockEmotesClientEnabled = false
        changed = true
    end
    if tdsSettings.unlockCosmeticsClientEnabled == true then
        tdsSettings.unlockCosmeticsClientEnabled = false
        changed = true
    end

    if changed then
        saveSettingsSoon()
    end
end

sanitizeLoadedSettings()
if loadedSettingsPath == LEGACY_SETTINGS_FILE then
    saveSettingsNow()
end

function stratIdentityFromParts(name, mapName, source)
    return tostring(source or "strat") .. ":" .. tostring(mapName or "") .. ":" .. tostring(name or "")
end

function getStratIdentity(macro)
    if type(macro) ~= "table" then
        return "strat:unknown"
    end
    if macro.id then
        return tostring(macro.id)
    end
    if macro.stratUrl and tostring(macro.stratUrl) ~= "" then
        return "url:" .. tostring(macro.stratUrl)
    end
    if macro.customId then
        return "custom:" .. tostring(macro.customId)
    end
    return stratIdentityFromParts(macro.name, macro.map, macro.isCommunity and "community" or "official")
end

function isStratFavorite(stratId)
    return ensureSettingsTable("favoriteStrats")[stratId] == true
end

function setStratFavorite(stratId, enabled)
    ensureSettingsTable("favoriteStrats")[stratId] = enabled == true or nil
    saveSettingsSoon()
end

function getLocalStratVote(stratId)
    return ensureSettingsTable("stratVotes")[stratId]
end

function setLocalStratVote(stratId, vote)
    local votes = ensureSettingsTable("stratVotes")
    vote = tostring(vote or "")
    if vote == "like" or vote == "dislike" then
        votes[stratId] = vote
    else
        votes[stratId] = nil
    end
    saveSettingsSoon()
end

function addLocalStratReport(stratId, report)
    report = tostring(report or ""):match("^%s*(.-)%s*$")
    if report == "" then
        return false
    end
    local reports = ensureSettingsTable("stratReports")
    if type(reports[stratId]) ~= "table" then
        reports[stratId] = {}
    end
    table.insert(reports[stratId], {
        text = report,
        at = os.time(),
    })
    saveSettingsSoon()
    return true
end

-- Strategies
macros = {
    {
        name = "Beginner Pizza Farm",
        subtitle = "Pizza Party Coin Farm",
        color = Color3.fromRGB(34, 197, 94),
        loadout = { "Scout", "Commander" },
        difficulty = "Noob",
        map = "Pizza Party",
        time = 4 + (40 / 60),
        timeLabel = "4m 40s",
        coins = 292,
        xp = 76,
        note = "No Golden Scout needed. Recommended: turn Autoskip on.",
        stratUrl = "https://raw.githubusercontent.com/TheRealAvrwm/TdsCommunityStrats/refs/heads/main/OfficialStartBeginnerPizzaParty",
    },
    {
        name = "Golden Scout Pizza Farm",
        subtitle = "Pizza Party Coin Farm",
        color = Color3.fromRGB(34, 197, 94),
        loadout = { "Golden Scout", "Commander" },
        difficulty = "Noob",
        map = "Pizza Party",
        time = 9 + (51 / 60),
        timeLabel = "9m 51s",
        coins = 438,
        xp = 118,
        note = "Uses Golden Scout and Commander. Recommended: turn Autoskip on.",
        stratUrl = "https://raw.githubusercontent.com/TheRealAvrwm/TdsCommunityStrats/refs/heads/main/strats/OfficialStartNoobGSC",
    },
    {
        name = "Lay By Coin Farm",
        subtitle = "Frost Coin Farm",
        color = Color3.fromRGB(34, 197, 94),
        loadout = { "Trapper", "Minigunner" },
        difficulty = "Pro",
        map = "Lay By",
        modeInfo = { mode = "survival", diff = "Frost", special = false },
        time = 4 + (25 / 60),
        timeLabel = "4m 25s",
        coins = 309,
        xp = 76,
        note = "Requires Trapper + Minigunner.",
        stratUrl = "https://raw.githubusercontent.com/TheRealAvrwm/TdsCommunityStrats/refs/heads/main/coinfarm%20layby",
    },
    {
        name = "Wretched Front Minigunner XP Hardcore",
        subtitle = "Credit: enyucandy",
        color = Color3.fromRGB(139, 92, 246),
        loadout = { "Pyromancer", "Hunter", "Minigunner" },
        difficulty = "Hardcore",
        map = "Wretched Front",
        modeInfo = { mode = "hardcore", diff = "Easy", special = false },
        rewardType = "Gems",
        time = 5 + (33 / 60),
        timeLabel = "5m 33s",
        coins = 77,
        xp = 127,
        note = "Credit: enyucandy. Recommended: turn Autoskip on.",
        stratUrl = "https://raw.githubusercontent.com/TheRealAvrwm/TdsCommunityStrats/refs/heads/main/Wretched%20Front%20Minigunner%20XP%20Hardcore",
    },
    {
        name = "Minigunner farm",
        subtitle = "Credit: enyucandy",
        color = Color3.fromRGB(59, 130, 246),
        loadout = { "Soldier", "Minigunner" },
        difficulty = "Hardcore",
        map = "Wretched Front",
        modeInfo = { mode = "hardcore", diff = "Easy", special = false },
        rewardType = "Gems",
        time = 2 + (53 / 60),
        timeLabel = "2m 53s",
        coins = 43,
        xp = 168,
        note = "Credit: enyucandy. Recommended: turn Autoskip on.",
        stratUrl = "https://raw.githubusercontent.com/TheRealAvrwm/TdsCommunityStrats/refs/heads/main/officialhardcoremniigunner",
    },
}

-- Modes
DIFFICULTY_MAP = {
    ["Easy"] = { mode = "survival", diff = "Easy", special = false },
    ["Casual"] = { mode = "survival", diff = "Casual", special = false },
    ["Intermediate"] = { mode = "survival", diff = "Intermediate", special = false },
    ["Molten"] = { mode = "survival", diff = "Molten", special = false },
    ["Fallen"] = { mode = "survival", diff = "Fallen", special = false },
    ["Frost"] = { mode = "survival", diff = "Frost", special = false },
    ["Hardcore"] = { mode = "hardcore", diff = "Easy", special = false },
    ["Easy Hardcore"] = { mode = "hardcore", diff = "Easy", special = false },
    ["Voidcore"] = { mode = "hardcore", diff = "Hard", special = false },
    ["Hardcore Hard"] = { mode = "hardcore", diff = "Hard", special = false },
    ["Pizza Party"] = { mode = "pizzaparty", diff = nil, special = true },
    ["Polluted Wasteland II"] = { mode = "polluted", diff = nil, special = true },
    ["Badlands II"] = { mode = "badlands", diff = nil, special = true },
}

TDS_MODE_OPTIONS = {
    "Easy",
    "Casual",
    "Intermediate",
    "Molten",
    "Fallen",
    "Frost",
    "Hardcore",
    "Easy Hardcore",
    "Voidcore",
    "Pizza Party",
    "Polluted Wasteland II",
    "Badlands II",
}

TDS_MAP_OPTIONS = {
    "Abandoned City",
    "Area 52",
    "Atlas Colosseum",
    "Autumn Falling",
    "Abyssal Trench",
    "Black Spot Exchange",
    "Candy Valley",
    "Cataclysm",
    "Chess Board",
    "Construction Crazy",
    "Coral Deep",
    "Crash Course",
    "Crossroads",
    "Crystal Cave",
    "Cyber City",
    "Dead Ahead",
    "Derelict Outpost",
    "Desert Oasis",
    "Deserted Village",
    "Distant Shapes",
    "Dusty Bridges",
    "Enchanted Forest",
    "Farm Lands",
    "Forest Camp",
    "Forgetten Docks",
    "Four Seasons",
    "Fungi Island",
    "Gilded Path",
    "Grass Isle",
    "Happy Home of Robloxia",
    "Harbor",
    "Honey Valley",
    "Hot Spot",
    "Iceville",
    "Infernal Abyss",
    "Judging Hall",
    "Laser Stadium",
    "Lay By",
    "Lighthaos",
    "Marshlands",
    "Mason Arch",
    "Medieval Times",
    "Meltdown",
    "Midnight Issue",
    "Moon Base",
    "Musaceae Kingdom",
    "Necropolis",
    "Nether",
    "Night Station",
    "Northern Lights",
    "Opulent Remains",
    "Outskirts Commune",
    "Pier Pressure",
    "Portland",
    "Retro Crossroads",
    "Retro Lighthouse",
    "Retro Rocket Arena",
    "Retro Stained Temple",
    "Retro The Heights",
    "Retro Zone",
    "Rocket Arena",
    "Ruby Escort",
    "Sacred Mountains",
    "Simplicity",
    "Sky Islands",
    "Space City",
    "Spring Fever",
    "Stained Temple",
    "Sugar Rush",
    "Summer Castle",
    "The Heavens",
    "The Heights",
    "Toyboard",
    "Tropical Industries",
    "Tropical Isles",
    "U-Turn",
    "Unknown Garden",
    "Warm Land",
    "Winter Abyss",
    "Winter Bridges",
    "Winter Stronghold",
    "Wrecked Battlefield",
    "Wrecked Battlefield II",
    "Wretched Front",
}

TDS_HARDCORE_MAP_OPTIONS = {
    "Wrecked Battlefield",
    "Outskirts Commune",
    "Wretched Front",
    "Unknown Garden",
}

TDS_MAP_ALIASES = {
    ["lighthouse"] = "Lighthaos",
    ["forgotten docks"] = "Forgetten Docks",
}

TDS_EXTRA_DETECTED_MAP_NAMES = {
    "Badlands II",
    "Cold Ambush",
    "Concrete Carrion",
    "Face to Face Aggression",
    "Foggy Forest",
    "Headache Headquarters",
    "Highlighted Section",
    "Legacy Dusty Bridges",
    "Legacy Gilded Path",
    "Legacy Retro Zone",
    "Legacy Simplicity",
    "Legacy Toyboard",
    "Legacy Unknown Garden",
    "Legacy Winter Abyss",
    "Plastic Cluster",
    "Polluted Wasteland II",
    "Rotfield",
    "Royal Practice",
    "Sk8 P4rk",
    "Totality Tower",
    "Tower Outskirts",
    "Tutorial",
}

TDS_KNOWN_MAP_NAMES = {}
do
    local addedMaps = {}
    local function addKnownMapName(name)
        local clean = tostring(name or ""):match("^%s*(.-)%s*$")
        if clean == "" then
            return
        end
        local key = clean:lower()
        if addedMaps[key] then
            return
        end
        addedMaps[key] = true
        TDS_KNOWN_MAP_NAMES[#TDS_KNOWN_MAP_NAMES + 1] = clean
    end
    for _, name in ipairs(TDS_MAP_OPTIONS) do
        addKnownMapName(name)
    end
    for _, name in ipairs(TDS_EXTRA_DETECTED_MAP_NAMES) do
        addKnownMapName(name)
    end
end

function getMapDefaults(mapName)
    local defaults = {
        ["Crossroads"] = { mode = "survival", diff = "Fallen", special = false },
        ["Maple City"] = { mode = "survival", diff = "Fallen", special = false },
        ["Pizza Party"] = { mode = "pizzaparty", diff = nil, special = true },
        ["Polluted Wasteland II"] = { mode = "polluted", diff = nil, special = true },
        ["Badlands II"] = { mode = "badlands", diff = nil, special = true },
        ["Frozen Peak"] = { mode = "survival", diff = "Frost", special = false },
        ["Lay By"] = { mode = "survival", diff = "Frost", special = false },
        ["Wretched Front"] = { mode = "hardcore", diff = "Easy", special = false },
        ["Hardcore Base"] = { mode = "hardcore", diff = "Easy", special = false },
        ["Voidcore Base"] = { mode = "hardcore", diff = "Hard", special = false },
    }
    if not defaults[mapName] then
        for key, val in pairs(defaults) do
            if key:lower() == (mapName or ""):lower() then
                return val
            end
        end
    end
    return defaults[mapName] or { mode = "survival", diff = "Fallen", special = false }
end

-- Match state
isExecuting = false
autoskipEnabled = false
espEnabled = false
autoskipConnection = nil
espCleanup = nil
extrasOpen = false
gatlingEnabled = false
gatlingPaused = false
gatlingFireDelay = 0.01
GATLING_RATE_MIN = 1
GATLING_RATE_MAX = 120
gatlingLastFire = 0
gatlingConnection = nil
gatlingMiniFrame = nil
gatlingKeybindConn = nil
gatlingSliderUpdateFn = nil
gatlingSyncValue = 0
gatlingMode = "FPS"
gatlingBurstCount = math.clamp(math.floor(tonumber(tdsSettings.gatlingBurstCount) or 12), 1, 64)
gatlingTargetMode = tostring(tdsSettings.gatlingTargetMode or "First")
gatlingFireRateTicks =
    math.clamp(math.floor(tonumber(tdsSettings.gatlingFireRateTicks) or 60), GATLING_RATE_MIN, GATLING_RATE_MAX)
gatlingMaxTargets = math.clamp(math.floor(tonumber(tdsSettings.gatlingMaxTargets) or 5), 1, 10)
gatlingBulletLinesEnabled = tdsSettings.gatlingBulletLinesEnabled == true
gatlingHitsoundsDisabled = tdsSettings.gatlingHitsoundsDisabled == true
gatlingTargetEsp = tostring(tdsSettings.gatlingTargetEsp or "Off")
autoClaimAllEnabled = tdsSettings.autoClaimAllEnabled == true
autoClaimAllThread = nil
autoClaimAchievementIds = nil
autoClaimAchievementCursor = 1
autoClaimLastToastAt = 0
autoClaimQuestAdapter = nil
autoClaimQuestAdapterChecked = false
autoAirstrikeEnabled = tdsSettings.autoAirstrikeEnabled == true
autoAirstrikeTarget = tostring(tdsSettings.autoAirstrikeTarget or "Grouped")
autoAirstrikeThread = nil
stopAutoAirstrike = nil
ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.autoPursuitPositionThread = nil
modifierVoteEnabled = tdsSettings.modifierVoteEnabled == true
modifierVoteBurstThread = nil
modifierVoteBurstSerial = 0
MODIFIER_VOTE_BURST_ATTEMPTS = 100
MODIFIER_VOTE_BURST_DURATION = 30
autoReadyEnabled = false
autoReadyThread = nil
streamerModeEnabled = false
streamerModeRootConnections = {}
streamerModeTextConnections = {}
streamerOriginalTexts = setmetatable({}, { __mode = "k" })
streamerOriginalHumanoids = setmetatable({}, { __mode = "k" })
streamerCharacterConnection = nil
streamerModeScanThread = nil
enemyInspectorEnabled = false
enemyInspectorCleanup = nil
abilityManagerEnabled = false
abilityManagerThread = nil
commanderChainEnabled = false
commanderChainThread = nil
supportCaravanEnabled = false
supportCaravanThread = nil
autoUpgradeEnabled = false
autoUpgradeThread = nil
autoUpgradeFarmsEnabled = false
autoUpgradeFarmsThread = nil
ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.clientTowerUnlockOriginalTroops = nil
unlockSkinsClientEnabled = false
clientSkinUnlockOriginalSkins = nil
unlockEmotesClientEnabled = false
clientEmoteUnlockOriginalEmotes = nil
clientEmoteUnlockOriginalEquipped = nil
unlockCosmeticsClientEnabled = false
clientCosmeticUnlockOriginals = nil
clientCosmeticUnlockOriginalEquipped = nil
clientCosmeticHooksInstalled = false
clientInventoryChannel = nil
oldInventoryFire = nil
oldInventoryInvoke = nil
clientInventoryHookedChannels = setmetatable({}, { __mode = "k" })
clientEmotesChannel = nil
oldEmotesInvoke = nil
clientEmoteHookedChannels = setmetatable({}, { __mode = "k" })
clientPlayerCharacterReplicator = nil
oldCharacterStartEmoting = nil
clientStickerController = nil
oldStickerEquip = nil
oldStickerUnequip = nil
skinChangerEnabled = false
skinChangerThread = nil
skinChangerCacheConn = nil
skinChangerSkinCacheConn = nil
skinChangerSuppressRemember = false
skinChangerSyncQueued = false
skinChangerOriginalTroops = nil
skinContentAssetsTroops = false
skinAssetStreamer = false
skinVisuals = {}
skinVisualFolder = nil
skinChangerHotbarPatched = false
skinChangerHumanoidUtil = false
skinUnitReplicator = false
skinUnitSourceCache = {}
skinUnitSourceCacheAt = {}
skinUnitSourcePending = {}
skinChangerTowerConn = nil
skinChangerUnitConn = nil
skinChangerUnitFolderConn = nil
skinChangerHeartbeatConn = nil
ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.fpsBoosterApplied = false
ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.fpsBoosterWorkspaceConn = nil
ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.fpsBoosterLightingConn = nil
ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.fpsBoosterSoundConn = nil
ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.resultsTrackerThread = nil
ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.resultsTrackerSession = 0
gatlingFireDelay = 1 / math.max(gatlingFireRateTicks, 1)

pcall(function()
    gatlingSyncValue = tonumber(workspace:GetAttribute("Sync")) or 0
    workspace:GetAttributeChangedSignal("Sync"):Connect(function()
        gatlingSyncValue = tonumber(workspace:GetAttribute("Sync")) or 0
    end)
end)

difficultyOrder = { "Noob", "Alright", "Pro", "Hardcore" }
difficultyColors = {
    Noob = Color3.fromRGB(34, 197, 94),
    Alright = Color3.fromRGB(250, 204, 21),
    Pro = Color3.fromRGB(239, 68, 68),
    Hardcore = Color3.fromRGB(139, 92, 246),
    Custom = Color3.fromRGB(20, 184, 166),
    Community = Color3.fromRGB(59, 130, 246),
}
difficultyLabels = {
    Noob = "Beginner",
    Alright = "Intermediate",
    Pro = "Advanced",
    Hardcore = "Hardcore",
    Custom = "My Strats",
    Community = "Community",
}

function organizeMacros()
    local org = { Noob = {}, Alright = {}, Pro = {}, Hardcore = {} }
    for _, m in ipairs(macros) do
        if org[m.difficulty] then
            table.insert(org[m.difficulty], m)
        end
    end
    return org
end

function calcPerHour(val, mins)
    val = tonumber(val) or 0
    mins = tonumber(mins) or 0
    if mins <= 0 then
        return 0
    end
    return math.floor((val / mins) * 60)
end

function fmtNum(n)
    if n >= 1000000 then
        return string.format("%.1fm", n / 1000000)
    end
    if n >= 1000 then
        return string.format("%.1fk", n / 1000)
    end
    return tostring(n)
end

function parseCphValue(str)
    if not str or str == "" then
        return 0
    end
    str = str:match("^%s*(.-)%s*$")
    local numStr, suffix = str:match("^([%d%.]+)([kKmM]?)$")
    if not numStr then
        numStr, suffix = str:match("([%d%.]+)([kKmM]?)")
        if not numStr then
            return 0
        end
    end
    local n = tonumber(numStr) or 0
    suffix = (suffix or ""):lower()
    if suffix == "k" then
        n = n * 1000
    elseif suffix == "m" then
        n = n * 1000000
    end
    return math.floor(n)
end

function detectTowersFromContent(contentStr)
    local towers = {}
    local seen = {}
    for towerName in contentStr:gmatch('place%s*%([^,]+,[^,]+,[^,]+,%s*"([^"]+)"') do
        if not seen[towerName] then
            seen[towerName] = true
            table.insert(towers, towerName)
        end
    end
    return towers
end

function detectNoteFromContent(contentStr)
    if not contentStr or contentStr == "" then
        return nil
    end
    for line in tostring(contentStr):gmatch("[^\r\n]+") do
        local note = line:match("^%s*%-%- NOTE:%s*(.-)%s*$")
        if note and note ~= "" then
            return note
        end
    end
    return nil
end

function detectStratMetadataFromContent(contentStr)
    if not contentStr or contentStr == "" then
        return nil
    end
    local checked = 0
    for line in tostring(contentStr):gmatch("[^\r\n]+") do
        checked += 1
        local raw = line:match("^%s*%-%- ZEPHYR_META:%s*(%b{})")
        if raw then
            local ok, decoded = pcall(function()
                return HttpService:JSONDecode(raw)
            end)
            if ok and type(decoded) == "table" then
                return decoded
            end
        end
        if checked >= 25 then
            break
        end
    end
    return nil
end

function formatStratDate(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    local ok, dt = pcall(function()
        return DateTime.fromIsoDate(value)
    end)
    if ok and dt then
        local utc = dt:ToUniversalTime()
        return string.format("%d/%d/%02d", utc.Month, utc.Day, utc.Year % 100)
    end
    return value:match("^(%d%d%d%d%-%d%d%-%d%d)") or value
end

function stratDateSummary(meta)
    if type(meta) ~= "table" then
        return nil
    end
    local made = formatStratDate(meta.createdAt)
    local updated = formatStratDate(meta.updatedAt)
    if made and updated and made ~= updated then
        return "Published " .. made .. " | Updated " .. updated
    end
    if made then
        return "Published " .. made
    end
    if updated then
        return "Updated " .. updated
    end
    return nil
end

function parseCommunityFilename(filename)
    local name = filename:gsub("%.txt$", "")
    local info = { stratName = name, map = "Crossroads", cph = 0, gph = 0 }
    local parts = {}
    local remaining = name
    while true do
        local s, e = remaining:find(" %- ")
        if not s then
            local trimmed = remaining:match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" then
                table.insert(parts, trimmed)
            end
            break
        end
        local part = remaining:sub(1, s - 1):match("^%s*(.-)%s*$")
        if part and part ~= "" then
            table.insert(parts, part)
        end
        remaining = remaining:sub(e + 1)
    end
    if #parts >= 1 then
        local stratName = parts[1]
        local diffTag = stratName:match("%[([^%]]+)%]")
        if diffTag then
            info.difficulty = diffTag:match("^%s*(.-)%s*$")
            stratName = stratName:gsub("%s*%[.-%]%s*", ""):match("^%s*(.-)%s*$")
        else
            local namePart = (parts[1] or filename):lower()
            if namePart:find("voidcore") then
                info.difficulty = "Voidcore"
            elseif namePart:find("hardcore") then
                info.difficulty = "Hardcore"
            elseif namePart:find("fallen") then
                info.difficulty = "Fallen"
            elseif namePart:find("molten") then
                info.difficulty = "Molten"
            elseif namePart:find("frost") then
                info.difficulty = "Frost"
            elseif namePart:find("pizza party") then
                info.difficulty = "Pizza Party"
            elseif namePart:find("polluted") then
                info.difficulty = "Polluted Wasteland II"
            elseif namePart:find("badlands") then
                info.difficulty = "Badlands II"
            elseif namePart:find("intermediate") then
                info.difficulty = "Intermediate"
            elseif namePart:find("casual") then
                info.difficulty = "Casual"
            elseif namePart:find("easy") then
                info.difficulty = "Easy"
            end
        end
        info.stratName = stratName
    end
    if #parts >= 2 then
        local mapRaw = parts[2]:match("^%s*(.-)%s*$")
        info.map = mapRaw:gsub("(%a)([%w_']*)", function(first, rest)
            return first:upper() .. rest
        end)
    end
    for _, p in ipairs(parts) do
        if info.cph == 0 then
            local numStr = p:match("([%d%.]+[kKmM]?)%s*cph")
            if numStr then
                info.cph = parseCphValue(numStr)
            end
        end
        if info.gph == 0 then
            local numStr = p:match("([%d%.]+[kKmM]?)%s*gph")
            if numStr then
                info.gph = parseCphValue(numStr)
            end
        end
    end
    if info.cph == 0 then
        local numStr = name:match("([%d%.]+[kKmM]?)%s*cph")
        if numStr then
            info.cph = parseCphValue(numStr)
        end
    end
    if info.gph == 0 then
        local numStr = name:match("([%d%.]+[kKmM]?)%s*gph")
        if numStr then
            info.gph = parseCphValue(numStr)
        end
    end
    return info
end

function capitalizeFirst(str)
    if not str or str == "" then
        return str
    end
    return str:sub(1, 1):upper() .. str:sub(2)
end

function asVector3(value)
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
            return value.x or value.X, value.y or value.Y, value.z or value.Z
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

function decodeAbilityDataFromLine(value)
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

-- Playback
function parseAndLoad(text)
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
    local recentPlaceKeys = {}
    local function placeKey(tower, pos)
        return tostring(tower) .. "|" .. string.format("%.1f", pos.X) .. "|" .. string.format("%.1f", pos.Z)
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
                local actionTime = tonumber(t) or 0
                local key = placeKey(tower, pos)
                if recentPlaceKeys[key] and actionTime - recentPlaceKeys[key] <= 5 then
                    continue
                end
                recentPlaceKeys[key] = actionTime
                zeroFallbackPos = Vector3.new(pos.X, 4.04, pos.Z)
                table.insert(actions, {
                    time = actionTime,
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
                    data = { troopPos = troopPosFrom(sx, sz), troopName = "Default" },
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
                    data = { troopPos = troopPosFrom(tx, tz), troopName = "Default", target = tmode },
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
                    data = { troopPos = troopPosFrom(ax, az), troopName = "Default", name = aname, abilityData = {} },
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
                    data = { troopPos = troopPosFrom(ox, oz), troopName = "Default", name = oname, value = ovalue },
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

macroPlaying = false
macroSession = 0
MACRO_START_WAVE = 1
ROUND_RESET_WAVE = 0
MACRO_START_TIMEOUT = 600
AUTO_RERUN_TIMEOUT = 900
WAVE_DETECT_POLL = 0.1
AUTO_RESPAWN_POLL = 0.1
HEALTH_RESTART_RECENT_WINDOW = 20
AUTO_REJOIN_START_RETRY_TIMEOUT = 240
AUTO_REJOIN_START_RETRY_INTERVAL = 2
LOBBY_READY_RETRY_TIMEOUT = 240
LOBBY_READY_RETRY_INTERVAL = 2
AUTO_REJOIN_MAP_SCAN_SETTLE_TIME = 0.62
AUTO_REJOIN_REQUEUE_COOLDOWN = 0.34
AUTO_REJOIN_REQUEUE_NOTIFY_EVERY = 3
AUTO_REJOIN_MAP_TEXT_SCAN_LIMIT = 900
START_WAVE_READY_INTERVAL = 0.5
PLACE_RETRY_TIMEOUT = 25
UPGRADE_RETRY_TIMEOUT = 25
MONEY_PLAYBACK_RETRY_FOREVER = 1000000000
UPGRADE_TARGET_FIND_TIMEOUT = 6
MAX_ACTION_LEAD_TIME = 10
PLACE_SLOT_WAIT_TIMEOUT = 120
ROUND_RESET_CONFIRM_TIME = 2
SELL_RETRY_TIMEOUT = 8
TARGET_RETRY_TIMEOUT = 8
ABILITY_RETRY_TIMEOUT = 8
OPTION_RETRY_TIMEOUT = 8
PLACE_VERIFY_RADIUS = 5.0
TOWER_MATCH_RADIUS = 2.5
SELL_MATCH_RADIUS = 5.0
autoRespawnVoteEnabled = false
autoRespawnVoteThread = nil
autoRerunStratsEnabled = false
autoRerunSerial = 0
autoRejoinStratSerial = 0
autoRejoinEndThread = nil
autoRejoinLaunchAttempted = false
TDS_VIP_GAMEPASS_ID = 10518590
vipOverrideAccessCache = nil
vipOverrideAccessCheckedAt = 0
vipOverrideAccessCheckInFlight = false
VIP_LOBBY_VOTING_PLACE_ID = 5591597781
AUTO_REJOIN_LOBBY_PLACE_IDS = {
    [5591597781] = true,
    [3260590327] = true,
}
baseHealthWasDown = false
baseHealthRestartSerial = 0
lastBaseHealthDownAt = 0
lastBaseHealthRestoredAt = 0
rewardsAutoRejoinWasVisible = false
lastRewardsAutoRejoinAt = 0
uiNotify = nil
voteConfiguredModifiers = nil
startModifierVoteBurst = nil
lobbyVotePreparing = false
lobbyVotePreparingSerial = 0

function beginLobbyVotePreparation(serial)
    lobbyVotePreparing = true
    lobbyVotePreparingSerial = serial
end

function endLobbyVotePreparation(serial)
    if serial == lobbyVotePreparingSerial then
        lobbyVotePreparing = false
    end
end

function notify(msg, color)
    if type(uiNotify) == "function" then
        pcall(uiNotify, msg, color)
    else
        warn("[Zephyr] " .. tostring(msg))
    end
end

function trimText(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

function splitList(value)
    local out = {}
    for part in tostring(value or ""):gmatch("[^,;\r\n]+") do
        local clean = trimText(part)
        if clean ~= "" then
            table.insert(out, clean)
        end
    end
    return out
end

function normalizeLookupText(value)
    return tostring(value or ""):lower():gsub("[^%w]", "")
end

function matchKnownOption(options, value, fallback)
    local text = trimText(value)
    if text == "" then
        return fallback or ""
    end
    local key = normalizeLookupText(text)
    local alias = TDS_MAP_ALIASES and (TDS_MAP_ALIASES[text:lower()] or TDS_MAP_ALIASES[key])
    if alias then
        local aliasKey = normalizeLookupText(alias)
        for _, option in ipairs(options or {}) do
            if normalizeLookupText(option) == aliasKey then
                return option
            end
        end
        return alias
    end
    for _, option in ipairs(options or {}) do
        if normalizeLookupText(option) == key then
            return option
        end
    end
    return fallback ~= nil and fallback or text
end

function getSettingNumber(key, fallback, minValue, maxValue)
    local value = tonumber(tdsSettings[key])
    if not value then
        value = fallback
    end
    if minValue then
        value = math.max(minValue, value)
    end
    if maxValue then
        value = math.min(maxValue, value)
    end
    return value
end

function getNewNetworkRemoteName(kind, actionName)
    local prefix = kind == "event" and "RE:" or kind == "unreliable" and "URE:" or "RF:"
    return prefix .. tostring(actionName), prefix
end

function findNewNetworkRemote(channelName, kind, actionName, timeout)
    timeout = math.max(tonumber(timeout) or 0, 0)
    local remoteName, prefix = getNewNetworkRemoteName(kind, actionName)
    local deadline = tick() + timeout
    repeat
        local network = ReplicatedStorage:FindFirstChild("Network")
        local channel = network and network:FindFirstChild(channelName)
        local remote = channel and channel:FindFirstChild(remoteName)
        if remote then
            return remote, nil
        end
        if timeout <= 0 then
            break
        end
        task.wait(0.05)
    until tick() >= deadline
    local network = ReplicatedStorage:FindFirstChild("Network")
    local channel = network and network:FindFirstChild(channelName)
    if not network then
        return nil, "missing Network"
    end
    if not channel then
        return nil, "missing channel " .. tostring(channelName)
    end
    return nil, "missing remote " .. prefix .. tostring(actionName)
end

function invokeNewNetworkRemote(remote, kind, args)
    local unpacker = (type(table) == "table" and table.unpack) or unpack
    local ok, result = pcall(function()
        if kind == "event" or kind == "unreliable" then
            return remote:FireServer(unpacker(args))
        end
        return remote:InvokeServer(unpacker(args))
    end)
    return ok, result
end

function invokeNewNetwork(channelName, kind, actionName, ...)
    local remote, missing = findNewNetworkRemote(channelName, kind, actionName, 0)
    if not remote then
        return false, missing
    end
    local args = { ... }
    return invokeNewNetworkRemote(remote, kind, args)
end

function invokeNewNetworkWithWait(channelName, kind, actionName, timeout, ...)
    local remote, missing = findNewNetworkRemote(channelName, kind, actionName, timeout)
    if not remote then
        return false, missing
    end
    local args = { ... }
    return invokeNewNetworkRemote(remote, kind, args)
end

function getAutoRejoinConfig()
    if type(tdsSettings.autoRejoin) ~= "table" then
        tdsSettings.autoRejoin = cloneSettingsValue(settingsDefaults.autoRejoin)
    end
    if
        (tdsSettings.autoRejoin.mode == nil or tostring(tdsSettings.autoRejoin.mode) == "")
        and tdsSettings.autoRejoin.difficulty ~= nil
    then
        tdsSettings.autoRejoin.mode = tostring(tdsSettings.autoRejoin.difficulty)
        tdsSettings.autoRejoin.difficulty = nil
        saveSettingsSoon()
    end
    if tdsSettings.autoRejoin.mode == nil or tostring(tdsSettings.autoRejoin.mode) == "" then
        tdsSettings.autoRejoin.mode = settingsDefaults.autoRejoin.mode
    end
    if tdsSettings.autoRejoin.modeUserSet ~= true and tdsSettings.autoRejoin.modeAutoFilled ~= true then
        local savedMode = tostring(tdsSettings.autoRejoin.mode or "")
        if savedMode ~= "" and savedMode:lower() ~= tostring(settingsDefaults.autoRejoin.mode):lower() then
            tdsSettings.autoRejoin.modeUserSet = true
            saveSettingsSoon()
        end
    end
    return tdsSettings.autoRejoin
end

function isAutoRejoinEnabled()
    local config = getAutoRejoinConfig()
    return config.enabled == true
end

function titleCaseWords(value)
    local text = tostring(value or ""):match("^%s*(.-)%s*$")
    text = text:gsub("%s+", " ")
    local exact = {
        vip = "VIP",
        xp = "XP",
        pvp = "PVP",
        dj = "DJ",
        ii = "II",
        iii = "III",
        iv = "IV",
    }
    return (
        text:gsub("%S+", function(word)
            local lower = word:lower()
            return exact[lower] or (lower:sub(1, 1):upper() .. lower:sub(2))
        end)
    )
end

function normalizeAutoRejoinMap(value)
    local text = titleCaseWords(value)
    return matchKnownOption(TDS_MAP_OPTIONS, text, text)
end

function normalizeAutoRejoinMode(value)
    local text = titleCaseWords(value)
    local lower = text:lower()
    if lower == "" then
        return "Easy"
    end
    if lower == "easycore" then
        return "Easy Hardcore"
    end
    if lower == "voidcore" or lower == "hard hardcore" or lower == "hardcore hard" then
        return "Voidcore"
    end
    return matchKnownOption(TDS_MODE_OPTIONS, text, text)
end

function isHardcoreAutoRejoinMode(modeName)
    local normalized = normalizeAutoRejoinMode(modeName)
    local info = DIFFICULTY_MAP[normalized]
    return type(info) == "table" and info.mode == "hardcore"
end

function getAutoRejoinMapOptionsForMode(modeName)
    if isHardcoreAutoRejoinMode(modeName) then
        return TDS_HARDCORE_MAP_OPTIONS
    end
    return TDS_MAP_OPTIONS
end

function normalizeAutoRejoinMapForMode(value, modeName, fallback)
    local mapName = normalizeAutoRejoinMap(value)
    if mapName == "" then
        return fallback or ""
    end
    if not isHardcoreAutoRejoinMode(modeName) then
        return mapName
    end
    local hardcoreMap = matchKnownOption(TDS_HARDCORE_MAP_OPTIONS, mapName, "")
    if hardcoreMap ~= "" then
        return hardcoreMap
    end
    return fallback or ""
end

function getAutoRejoinModeInfo(modeName)
    local normalized = normalizeAutoRejoinMode(modeName)
    return DIFFICULTY_MAP[normalized], normalized
end

function isAutoRejoinModeLockedToMap(modeName)
    local info = getAutoRejoinModeInfo(modeName)
    return type(info) == "table" and info.special == true
end

function hasReplayableSavedStrat(saved)
    if type(saved) ~= "table" then
        return false
    end
    if saved.savedBy ~= "ZephyrTDS" then
        return false
    end
    if type(saved.stratContent) == "string" and saved.stratContent:match("%S") then
        return true
    end
    return type(saved.stratUrl) == "string" and saved.stratUrl:match("^%s*https?://") ~= nil
end

function modeNameFromModeInfo(modeInfo, fallback)
    if type(modeInfo) ~= "table" then
        return normalizeAutoRejoinMode(fallback)
    end
    local mode = tostring(modeInfo.mode or ""):lower()
    local diff = tostring(modeInfo.diff or "")
    local lowerDiff = diff:lower()
    if mode == "hardcore" then
        return lowerDiff == "hard" and "Voidcore" or "Hardcore"
    end
    if mode == "pizzaparty" then
        return "Pizza Party"
    end
    if mode == "polluted" then
        return "Polluted Wasteland II"
    end
    if mode == "badlands" then
        return "Badlands II"
    end
    if diff ~= "" then
        return normalizeAutoRejoinMode(diff)
    end
    return normalizeAutoRejoinMode(fallback)
end

function getModeInfoForAutoRejoin(mapName, modeName, saved)
    if type(saved) == "table" and type(saved.modeInfo) == "table" and type(saved.modeInfo.mode) == "string" then
        return saved.modeInfo
    end
    local normalizedMode = normalizeAutoRejoinMode(modeName)
    if DIFFICULTY_MAP[normalizedMode] then
        return DIFFICULTY_MAP[normalizedMode]
    end
    if type(mapName) == "string" and mapName ~= "" then
        return getMapDefaults(mapName)
    end
    return DIFFICULTY_MAP.Easy
end

function getAutoRejoinTarget(preferSaved)
    local config = getAutoRejoinConfig()
    local saved = tdsSettings.lastStrat
    local configMap = normalizeAutoRejoinMap(config.map)
    local rawConfigMode = config.modeUserSet == true and trimText(config.mode or config.difficulty or "") or ""
    local configMode = normalizeAutoRejoinMode(rawConfigMode)
    local configModeInfo = DIFFICULTY_MAP[configMode]
    if preferSaved ~= false and hasReplayableSavedStrat(saved) then
        local mapName = normalizeAutoRejoinMap(saved.map)
        if mapName ~= "" then
            local modeInfo = type(saved.modeInfo) == "table" and saved.modeInfo or getMapDefaults(mapName)
            local modeName = modeNameFromModeInfo(modeInfo, configMode)
            mapName = normalizeAutoRejoinMapForMode(
                mapName,
                modeName,
                isHardcoreAutoRejoinMode(modeName) and "Wretched Front" or mapName
            )
            return mapName, modeName, modeInfo, saved
        end
    end
    if type(configModeInfo) == "table" and configModeInfo.special == true then
        return configMode, configMode, configModeInfo, nil
    end
    local mapName = configMap
    local modeName = configMode
    local modeInfo = getModeInfoForAutoRejoin(mapName, modeName)
    mapName = normalizeAutoRejoinMapForMode(
        mapName,
        modeName,
        isHardcoreAutoRejoinMode(modeName) and "Wretched Front" or mapName
    )
    return mapName, modeName, modeInfo, nil
end

function buildAutoRejoinStartPayload(preferSaved)
    local _, modeText, modeInfo = getAutoRejoinTarget(preferSaved ~= false)
    if type(modeInfo) ~= "table" then
        modeInfo = DIFFICULTY_MAP[normalizeAutoRejoinMode(modeText)] or DIFFICULTY_MAP.Easy
    end
    local payload = { mode = modeInfo.mode or "survival", count = 1 }
    if not modeInfo.special and modeInfo.diff then
        payload.difficulty = modeInfo.diff
    end
    return payload
end

function buildStartPayloadFromModeInfo(modeInfo)
    if type(modeInfo) ~= "table" then
        modeInfo = DIFFICULTY_MAP.Easy
    end
    local payload = { mode = modeInfo.mode or "survival", count = 1 }
    if not modeInfo.special and modeInfo.diff then
        payload.difficulty = modeInfo.diff
    end
    return payload
end

function getLobbyVotePosition()
    if type(vector) == "table" and type(vector.create) == "function" then
        local ok, value = pcall(function()
            return vector.create(20.591524124145508, 9.357712745666504, 54.93937301635742)
        end)
        if ok then
            return value
        end
    end
    return Vector3.new(20.591524124145508, 9.357712745666504, 54.93937301635742)
end

function isAutoRejoinLobbyPlace()
    return AUTO_REJOIN_LOBBY_PLACE_IDS[game.PlaceId] == true
end

function refreshVipLobbyOverrideAccess(force)
    local now = tick()
    if vipOverrideAccessCheckInFlight then
        return
    end
    if not force and now - vipOverrideAccessCheckedAt < 90 then
        return
    end

    vipOverrideAccessCheckInFlight = true
    vipOverrideAccessCheckedAt = now
    task.spawn(function()
        local ok, owns = pcall(function()
            return MarketplaceService:UserOwnsGamePassAsync(LocalPlayer.UserId, TDS_VIP_GAMEPASS_ID)
        end)
        if ok then
            vipOverrideAccessCache = owns == true
        end
        vipOverrideAccessCheckInFlight = false
    end)
end

function hasVipLobbyOverrideAccess()
    refreshVipLobbyOverrideAccess(false)
    return vipOverrideAccessCache == true
end

task.defer(refreshVipLobbyOverrideAccess, true)

function getCash()
    local cash = LocalPlayer:FindFirstChild("Cash")
    if cash and cash:IsA("ValueBase") then
        return tonumber(cash.Value) or 0
    end
    return 0
end

function findWaveValueLabel()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local topDisplay = gui and gui:FindFirstChild("ReactGameTopGameDisplay")
    local frame = topDisplay and topDisplay:FindFirstChild("Frame")
    local wave = frame and frame:FindFirstChild("wave")
    local container = wave and wave:FindFirstChild("container")
    local exact = container and container:FindFirstChild("value") or nil
    if exact then
        return exact
    end

    if topDisplay then
        for _, obj in ipairs(topDisplay:GetDescendants()) do
            if obj:IsA("TextLabel") or obj:IsA("TextButton") then
                local current = obj
                local waveContext = false
                for _ = 1, 5 do
                    if not current or current == topDisplay then
                        break
                    end
                    if tostring(current.Name):lower():find("wave", 1, true) then
                        waveContext = true
                        break
                    end
                    current = current.Parent
                end
                if waveContext then
                    local ok, text = pcall(function()
                        return obj.Text
                    end)
                    if
                        ok
                        and type(text) == "string"
                        and (text:match("^%s*[Ww]ave%s*%d+") or text:match("^%s*%d+%s*/%s*%d+"))
                    then
                        return obj
                    end
                end
            end
        end
    end

    return nil
end

function parseWaveText(text)
    if type(text) ~= "string" then
        return nil
    end
    text = text:match("^%s*(.-)%s*$")
    if text:match("^%d+%s*:%s*%d+") then
        return nil
    end
    return tonumber(
        text:match("^[Ww]ave%s*(%d+)") or text:match("^(%d+)%s*/") or text:match("^(%d+)$") or text:match("(%d+)")
    )
end

function getCurrentWave()
    -- GameState can still show wave 0 after the HUD reaches wave 1.
    local label = findWaveValueLabel()
    if label then
        local ok, text = pcall(function()
            return label.Text
        end)
        local hudWave = ok and parseWaveText(text) or nil
        if hudWave ~= nil then
            return hudWave
        end
    end

    if GameState then
        local ok, wave = pcall(function()
            return tonumber(GameState.Wave)
        end)
        if ok and wave ~= nil then
            return wave
        end

        ok, wave = pcall(function()
            if type(GameState.Get) == "function" then
                return tonumber(GameState.Get("Wave"))
            end
        end)
        if ok and wave ~= nil then
            return wave
        end
    end

    local state = ReplicatedStorage:FindFirstChild("State")
    local waveValue = state and state:FindFirstChild("Wave")
    if waveValue then
        local ok, wave = pcall(function()
            return tonumber(waveValue.Value)
        end)
        if ok and wave ~= nil then
            return wave
        end
    end

    return nil
end

function waitForCash(amount, timeout)
    if not amount or type(amount) ~= "number" or amount <= 0 then
        return true
    end
    if amount < 0 then
        return true
    end
    timeout = timeout or 300
    local start = tick()
    while tick() - start < timeout do
        if getCash() >= amount then
            return true
        end
        task.wait(0.3)
    end
    return false
end

function waitForWave(targetWave, timeout, stopOnReset)
    timeout = timeout or 600
    targetWave = tonumber(targetWave) or 0
    if targetWave <= 0 then
        return true, getCurrentWave()
    end
    local start = tick()
    while tick() - start < timeout do
        local current = getCurrentWave()
        if stopOnReset and current == ROUND_RESET_WAVE then
            return false, current
        end
        if current and current >= targetWave then
            return true, current
        end
        task.wait(WAVE_DETECT_POLL)
    end
    return false, getCurrentWave()
end

function getGameTimeScale()
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

function isTimeScaleLocked()
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

MIN_PLAYBACK_TIMESCALE = 0.5
MAX_PLAYBACK_TIMESCALE = 2
ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.lastUnsafeTimeScaleWarnAt = 0

function normalizePlaybackTimeScale(scale)
    scale = tonumber(scale) or 1
    if scale <= 0.05 then
        if tick() - (ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.lastUnsafeTimeScaleWarnAt or 0) > 2 then
            ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.lastUnsafeTimeScaleWarnAt = tick()
            warn("[Zephyr] Ignoring timescale 0 during playback so macro timing cannot freeze.")
        end
        return nil
    end
    if scale < MIN_PLAYBACK_TIMESCALE then
        return MIN_PLAYBACK_TIMESCALE
    end
    if scale > MAX_PLAYBACK_TIMESCALE then
        return MAX_PLAYBACK_TIMESCALE
    end
    return scale
end

function makePlaybackClock(useGameTiming)
    local wallStart = tick()
    local last = wallStart
    local gameElapsed = 0
    return function()
        if not useGameTiming then
            return tick() - wallStart
        end
        local now = tick()
        local scale = getGameTimeScale()
        if scale <= 0.05 then
            scale = 1
        end
        gameElapsed += math.max(0, now - last) * scale
        last = now
        return gameElapsed
    end
end

function waitForMacroTime(getElapsed, targetTime, shouldStop)
    targetTime = tonumber(targetTime) or 0
    local elapsed = getElapsed()
    while elapsed < targetTime do
        if shouldStop and shouldStop() then
            return false
        end
        task.wait(math.min(WAVE_DETECT_POLL, targetTime - elapsed))
        elapsed = getElapsed()
    end
    return true
end

function waitForExactWave(targetWave, timeout)
    timeout = timeout or 600
    targetWave = tonumber(targetWave) or 0
    local start = tick()
    while tick() - start < timeout do
        local current = getCurrentWave()
        if current == targetWave then
            return true, current
        end
        task.wait(WAVE_DETECT_POLL)
    end
    return false, getCurrentWave()
end

function isFreshRoundWave(wave)
    return wave == ROUND_RESET_WAVE or wave == MACRO_START_WAVE
end

function waitForFreshRound(timeout)
    timeout = timeout or AUTO_RERUN_TIMEOUT
    local start = tick()
    while tick() - start < timeout do
        local current = getCurrentWave()
        if isFreshRoundWave(current) then
            return true, current
        end
        task.wait(WAVE_DETECT_POLL)
    end
    return false, getCurrentWave()
end

function waitForHealthRestart(timeout)
    timeout = timeout or AUTO_RERUN_TIMEOUT
    if lastBaseHealthRestoredAt > 0 and tick() - lastBaseHealthRestoredAt <= HEALTH_RESTART_RECENT_WINDOW then
        return true, "health-recent"
    end
    local serial = baseHealthRestartSerial
    local start = tick()
    while tick() - start < timeout do
        if baseHealthRestartSerial > serial then
            return true, "health"
        end
        task.wait(AUTO_RESPAWN_POLL)
    end
    return false, "timeout"
end

function getTowerRoot(tower)
    if not tower then
        return nil
    end
    return tower:FindFirstChild("HumanoidRootPart")
        or tower:FindFirstChild("RootPart")
        or tower.PrimaryPart
        or tower:FindFirstChildWhichIsA("BasePart")
        or tower:FindFirstChildWhichIsA("BasePart", true)
end

function isOwnTower(tower)
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

function xzDistance(a, b)
    local dx = a.X - b.X
    local dz = a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

function countTowersNearPos(pos, radius)
    local towers = workspace:FindFirstChild("Towers")
    if not towers then
        return 0
    end
    local count = 0
    for _, tower in ipairs(towers:GetChildren()) do
        if tower:IsA("Model") and isOwnTower(tower) then
            local root = getTowerRoot(tower)
            if root and xzDistance(root.Position, pos) <= radius then
                count += 1
            end
        end
    end
    return count
end

function countOwnTowers()
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

function textObjectHasTowerLimitContext(obj)
    local current = obj
    local blob = tostring(obj.Text or "")
    for _ = 1, 5 do
        if not current then
            break
        end
        blob ..= " " .. tostring(current.Name)
        current = current.Parent
    end
    blob = blob:lower()
    local hasTowerContext = blob:find("tower", 1, true)
        or blob:find("troop", 1, true)
        or blob:find("unit", 1, true)
        or blob:find("placement", 1, true)
    return hasTowerContext and blob:find("limit", 1, true)
end

ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.towerLimitCacheValue = nil
ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.towerLimitCacheAt = 0
function getDisplayedTowerLimit()
    if tick() - (ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.towerLimitCacheAt or 0) < 2 then
        return ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.towerLimitCacheValue
    end
    ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.towerLimitCacheAt = tick()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if not gui then
        return nil
    end
    for _, obj in ipairs(gui:GetDescendants()) do
        if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and textObjectHasTowerLimitContext(obj) then
            local text = tostring(obj.Text or "")
            local _, limit = text:match("(%d+)%s*/%s*(%d+)")
            limit = tonumber(limit)
            if limit and limit >= 10 and limit <= 60 then
                ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.towerLimitCacheValue = limit
                return limit
            end
        end
    end
    ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.towerLimitCacheValue = nil
    return nil
end

function getEstimatedTowerLimit()
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

function getTowerLimitState()
    local count = countOwnTowers()
    return count, getDisplayedTowerLimit() or getEstimatedTowerLimit()
end

function isRobloxInstance(value)
    local ok, result = pcall(function()
        return typeof(value) == "Instance"
    end)
    return ok and result == true
end

function isPlacedTowerInstance(value)
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

function resultContainsPlacedTower(value, depth)
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

function resultFailureText(value, depth)
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

function getPlaceResultStatus(ok, result)
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

function waitForTowerCountIncrease(pos, beforeCount, timeout, shouldStop)
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

function waitForUpgrade(troop, previousLevel, timeout)
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
        task.wait(0.1)
    end
    return false
end

function findTowerNearPos(pos, radius)
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

function resolveAbilityDataValue(value, depth)
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
        local c = value.components or value.Components
        if type(c) == "table" and #c >= 12 then
            return CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
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

function resolveAbilityData(data)
    return resolveAbilityDataValue(data or {}, 0) or {}
end

Network = nil
TroopsChannel = nil
VotingChannel = nil
TicketsChannel = nil
ConsumablesChannel = nil
oldTroopsInvoke = nil
oldVotingInvoke = nil
oldTicketsInvoke = nil
oldTicketsFire = nil
oldConsumablesFire = nil
unpackArgs = (type(table) == "table" and table.unpack) or unpack
if type(unpackArgs) ~= "function" then
    unpackArgs = function(t)
        return t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10]
    end
end

function createLegacyNetworkShim()
    local remoteEvent = ReplicatedStorage:FindFirstChild("RemoteEvent")
        or ReplicatedStorage:WaitForChild("RemoteEvent", 2)
    local remoteFunction = ReplicatedStorage:FindFirstChild("RemoteFunction")
        or ReplicatedStorage:WaitForChild("RemoteFunction", 2)
    local unreliableRemote = ReplicatedStorage:FindFirstChild("UnreliableRemoteEvent")
    if not remoteEvent and not remoteFunction and not unreliableRemote then
        return nil
    end

    local shim = { Channels = {} }
    function shim.Channel(channelName)
        channelName = tostring(channelName or "")
        local cached = shim.Channels[channelName]
        if cached then
            return cached
        end

        local channel = { Channel = channelName }
        function channel:InvokeServer(actionName, ...)
            if not remoteFunction then
                error("RemoteFunction unavailable", 2)
            end
            return remoteFunction:InvokeServer(self.Channel, actionName, ...)
        end
        function channel:FireServer(actionName, ...)
            if not remoteEvent then
                error("RemoteEvent unavailable", 2)
            end
            return remoteEvent:FireServer(self.Channel, actionName, ...)
        end
        function channel:FireUnreliableServer(actionName, ...)
            if not unreliableRemote then
                if not remoteEvent then
                    error("RemoteEvent unavailable", 2)
                end
                return remoteEvent:FireServer(self.Channel, actionName, ...)
            end
            return unreliableRemote:FireServer(self.Channel, actionName, ...)
        end
        function channel:On(actionName, callback)
            if not remoteEvent or type(callback) ~= "function" then
                return function() end
            end
            local connection = remoteEvent.OnClientEvent:Connect(function(eventChannel, eventAction, ...)
                if eventChannel == self.Channel and eventAction == actionName then
                    callback(...)
                end
            end)
            return function()
                if connection and connection.Connected then
                    connection:Disconnect()
                end
            end
        end

        shim.Channels[channelName] = channel
        return channel
    end
    return shim
end

do
    local result, requireError = nil, nil
    if canSafelyRequireTdsModules() then
        local shared = ReplicatedStorage:FindFirstChild("Shared")
        local modules = shared and shared:FindFirstChild("Modules")
        local networkModule = modules and modules:FindFirstChild("Network")
        if networkModule then
            result, requireError = safeRequire(networkModule, "Shared.Modules.Network")
        else
            requireError = "Network module not found"
        end
    else
        requireError = "waiting for TDS client startup"
    end

    local channelOk, channelFn = false, nil
    if type(result) == "table" then
        channelOk, channelFn = pcall(function()
            return result.Channel
        end)
    end

    if not (channelOk and type(channelFn) == "function") then
        local shim = createLegacyNetworkShim()
        if shim then
            result = shim
            channelOk, channelFn = true, shim.Channel
            warn(
                "[Zephyr] Network module unavailable; using direct remote shim:",
                tostring(requireError or requireBlockedReason or "unknown")
            )
        else
            warn(
                "[Zephyr] Network module unavailable; falling back where possible:",
                tostring(requireError or requireBlockedReason or "unknown")
            )
        end
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
    end
end

function invokeRemoteFunction(...)
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

function fireRemoteEvent(...)
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

-- Rewards
AUTO_CLAIM_ALL_INTERVAL = 24
AUTO_CLAIM_FIRST_DELAY = 2
AUTO_CLAIM_PACE = 0.045
AUTO_CLAIM_ACHIEVEMENT_BATCH = 18

function autoClaimTruthy(ok, result)
    if ok ~= true then
        return false
    end
    if result == false then
        return false
    end
    return result ~= nil and result ~= "false"
end

function autoClaimWait()
    task.wait(AUTO_CLAIM_PACE)
end

function autoClaimNewInvoke(channelName, actionName, ...)
    local ok, result = invokeNewNetwork(channelName, "function", actionName, ...)
    if ok then
        return ok, result
    end

    local newNetwork = nil
    if canSafelyRequireTdsModules() then
        newNetwork = safeRequirePath("Shared.Modules.NewNetwork", ReplicatedStorage, "Shared", "Modules", "NewNetwork")
    end
    if type(newNetwork) == "table" and type(newNetwork.Channel) == "function" then
        local args = { ... }
        local channelOk, channel = pcall(function()
            return newNetwork.Channel(channelName)
        end)
        if channelOk and channel and type(channel.invokeServer) == "function" then
            local invokeOk, invokeResult = pcall(function()
                return channel:invokeServer(actionName, unpackArgs(args))
            end)
            return invokeOk, invokeResult
        end
    end

    return false, result
end

function autoClaimGetOldChannel(channelName)
    if Network and type(Network.Channel) == "function" then
        local ok, channel = pcall(function()
            return Network.Channel(channelName)
        end)
        if ok and channel then
            return channel
        end
    end

    local shim = createLegacyNetworkShim()
    if shim and type(shim.Channel) == "function" then
        if not Network then
            Network = shim
        end
        local ok, channel = pcall(function()
            return shim.Channel(channelName)
        end)
        if ok and channel then
            return channel
        end
    end
    return nil
end

function autoClaimOldInvoke(channelName, actionName, ...)
    local args = { ... }
    local channel = autoClaimGetOldChannel(channelName)
    if channel and type(channel.InvokeServer) == "function" then
        local ok, result = pcall(function()
            return channel:InvokeServer(actionName, unpackArgs(args))
        end)
        if ok then
            return ok, result
        end
    end
    return invokeRemoteFunction(channelName, actionName, unpackArgs(args))
end

function autoClaimGetQuestAdapter()
    if autoClaimQuestAdapterChecked then
        return autoClaimQuestAdapter
    end
    if not canSafelyRequireTdsModules() then
        return nil
    end
    autoClaimQuestAdapterChecked = true
    autoClaimQuestAdapter = safeRequirePath(
        "Shared.Data.Quests.ClientAdapter",
        ReplicatedStorage,
        "Shared",
        "Data",
        "Quests",
        "ClientAdapter"
    )
    if autoClaimQuestAdapter == nil then
        autoClaimQuestAdapterChecked = false
    end
    return autoClaimQuestAdapter
end

function autoClaimQuestObjectiveDone(objective)
    if type(objective) ~= "table" then
        return true
    end
    local requirement = tostring(objective.requirement or objective.Requirement or ""):lower()
    if requirement == "optional" then
        return true
    end
    local amount = tonumber(
        objective.amount
            or objective.Amount
            or objective.required
            or objective.Required
            or objective.goal
            or objective.Goal
    ) or 1
    local current = tonumber(
        objective.current
            or objective.Current
            or objective.progress
            or objective.Progress
            or objective.value
            or objective.Value
    ) or 0
    return current >= amount
end

function autoClaimQuestRewardsLeft(record)
    local quest = type(record) == "table" and (record.quest or record.Quest) or nil
    local rewards = type(quest) == "table" and (quest.rewards or quest.Rewards) or record.rewards or record.Rewards
    if type(rewards) ~= "table" then
        return true
    end
    local foundReward = false
    for _, reward in pairs(rewards) do
        foundReward = true
        if type(reward) ~= "table" or reward.claimed ~= true then
            return true
        end
    end
    return foundReward == false
end

function autoClaimQuestRecordClaimable(record)
    if type(record) ~= "table" then
        return false
    end
    local adapter = autoClaimGetQuestAdapter()
    if type(adapter) == "table" and type(adapter.isClaimable) == "function" then
        local ok, claimable = pcall(function()
            return adapter.isClaimable(record)
        end)
        if ok then
            return claimable == true
        end
    end
    return nil
end

function autoClaimQuestComplete(record)
    if type(record) ~= "table" then
        return false
    end
    local quest = record.quest or record.Quest or record
    local state = tostring(record.state or record.State or quest.state or quest.State or ""):lower()
    if state == "completed" or state == "complete" or record.completed == true or record.Completed == true then
        return true
    end

    local objectives = quest.objectives or quest.Objectives or record.objectives or record.Objectives
    if type(objectives) ~= "table" then
        return false
    end
    local sawObjective = false
    for _, objective in pairs(objectives) do
        if type(objective) == "table" then
            sawObjective = true
            if not autoClaimQuestObjectiveDone(objective) then
                return false
            end
        end
    end
    return sawObjective
end

function autoClaimVisitQuestRecords(node, out, seen)
    if type(node) ~= "table" then
        return
    end
    seen = seen or {}
    if seen[node] then
        return
    end
    seen[node] = true

    local id = node.id or node.Id or node.ID
    if
        id ~= nil
        and (
            node.quest ~= nil
            or node.Quest ~= nil
            or node.started ~= nil
            or node.Started ~= nil
            or node.objectives ~= nil
            or node.Objectives ~= nil
        )
    then
        out[#out + 1] = node
    end

    for _, child in pairs(node) do
        if type(child) == "table" then
            autoClaimVisitQuestRecords(child, out, seen)
        end
    end
end

function autoClaimCompletedQuests()
    local claimed = 0
    local ok, state = autoClaimNewInvoke("Quests", "RequestState")
    if not ok or type(state) ~= "table" then
        return claimed
    end

    local records = {}
    autoClaimVisitQuestRecords(state.groups or state.Groups or state, records)
    local tried = {}
    for _, record in ipairs(records) do
        local id = record.id or record.Id or record.ID
        if id ~= nil and not tried[id] then
            tried[id] = true
            local started = record.started == true or record.Started == true
            local adapterClaimable = autoClaimQuestRecordClaimable(record)
            local shouldClaim = adapterClaimable
            if shouldClaim == nil then
                shouldClaim = (started or record.quest or record.Quest)
                    and autoClaimQuestComplete(record)
                    and autoClaimQuestRewardsLeft(record)
            end
            if shouldClaim then
                local claimOk, claimResult = autoClaimNewInvoke("Quests", "ClaimQuest", id)
                if autoClaimTruthy(claimOk, claimResult) then
                    claimed += 1
                end
                autoClaimWait()
            end
        end
    end
    return claimed
end

function autoClaimGetPlaytimeRewardCount()
    local data = canSafelyRequireTdsModules()
            and safeRequirePath(
                "Shared.Modules.PlaytimeRewardData",
                ReplicatedStorage,
                "Shared",
                "Modules",
                "PlaytimeRewardData"
            )
        or nil
    if type(data) == "table" and #data > 0 then
        return math.clamp(#data, 1, 20)
    end
    return 8
end

function autoClaimPlaytimeRewards()
    local claimed = 0
    for index = 1, autoClaimGetPlaytimeRewardCount() do
        local ok, result = autoClaimNewInvoke("PlaytimeRewards", "ClaimReward", index)
        if autoClaimTruthy(ok, result) then
            claimed += 1
        end
        autoClaimWait()
    end
    return claimed
end

function autoClaimGiftbox()
    local claimed = 0
    local ok, gifts = autoClaimOldInvoke("Gifts", "Request")
    if ok and type(gifts) == "table" then
        for _, gift in pairs(gifts) do
            local giftId = type(gift) == "table" and (gift.id or gift.Id or gift.ID)
            if giftId ~= nil then
                local claimOk, claimResult = autoClaimOldInvoke("Gifts", "Claim", giftId)
                if autoClaimTruthy(claimOk, claimResult) then
                    claimed += 1
                end
                autoClaimWait()
            end
        end
    end
    return claimed
end

function autoClaimSeasonRewards()
    local claimed = 0
    local ok, unclaimed = autoClaimOldInvoke("Seasons", "GetUnclaimed")
    if ok and type(unclaimed) == "table" then
        for _, entry in pairs(unclaimed) do
            if type(entry) == "table" and entry.season ~= nil and entry.tier ~= nil then
                local claimOk, claimResult = autoClaimOldInvoke("Seasons", "Claim", entry.season, entry.tier)
                if autoClaimTruthy(claimOk, claimResult) then
                    claimed += 1
                end
                autoClaimWait()
            end
        end
    end
    return claimed
end

function autoClaimGetAchievementIds()
    if autoClaimAchievementIds then
        return autoClaimAchievementIds
    end
    autoClaimAchievementIds = {}
    local content = ReplicatedStorage:FindFirstChild("Content")
    local achievements = content and content:FindFirstChild("Achievement")
    if achievements then
        local seen = {}
        for _, inst in ipairs(achievements:GetDescendants()) do
            if inst:IsA("ModuleScript") and not seen[inst.Name] then
                seen[inst.Name] = true
                autoClaimAchievementIds[#autoClaimAchievementIds + 1] = inst.Name
            end
        end
        table.sort(autoClaimAchievementIds)
    end
    return autoClaimAchievementIds
end

function autoClaimAchievements()
    local claimed = 0
    local ids = autoClaimGetAchievementIds()
    local count = #ids
    if count <= 0 then
        return claimed
    end
    local batch = math.min(AUTO_CLAIM_ACHIEVEMENT_BATCH, count)
    for _ = 1, batch do
        local id = ids[autoClaimAchievementCursor]
        autoClaimAchievementCursor += 1
        if autoClaimAchievementCursor > count then
            autoClaimAchievementCursor = 1
        end
        if id ~= nil then
            local ok, result = autoClaimNewInvoke("Achievements", "Claim", id)
            if autoClaimTruthy(ok, result) then
                claimed += 1
            end
            autoClaimWait()
        end
    end
    return claimed
end

function autoClaimDailyRewards()
    local claimed = 0
    local ok, result = autoClaimNewInvoke("DailySpin", "RedeemReward")
    if autoClaimTruthy(ok, result) then
        claimed += 1
    end
    autoClaimWait()
    ok, result = autoClaimNewInvoke("DailySpin", "RedeemSpin")
    if autoClaimTruthy(ok, result) then
        claimed += 1
    end
    return claimed
end

function autoClaimAllPass()
    local total = 0
    total += autoClaimDailyRewards()
    total += autoClaimPlaytimeRewards()
    total += autoClaimCompletedQuests()
    total += autoClaimGiftbox()
    total += autoClaimSeasonRewards()
    total += autoClaimAchievements()
    return total
end

function startAutoClaimAll(toastFn)
    autoClaimAllEnabled = true
    if autoClaimAllThread then
        return true
    end
    autoClaimAllThread = task.spawn(function()
        task.wait(AUTO_CLAIM_FIRST_DELAY)
        while runtimeAlive and autoClaimAllEnabled do
            local ok, claimed = pcall(autoClaimAllPass)
            if ok and tonumber(claimed) and claimed > 0 and toastFn and tick() - autoClaimLastToastAt > 8 then
                autoClaimLastToastAt = tick()
                toastFn(
                    ("Auto claimed %d reward%s"):format(claimed, claimed == 1 and "" or "s"),
                    Color3.fromRGB(34, 197, 94)
                )
            elseif not ok then
                warn("[Zephyr] Auto Claim All failed:", tostring(claimed))
            end
            task.wait(AUTO_CLAIM_ALL_INTERVAL)
        end
        autoClaimAllThread = nil
    end)
    return true
end

function stopAutoClaimAll()
    autoClaimAllEnabled = false
    if autoClaimAllThread then
        pcall(function()
            task.cancel(autoClaimAllThread)
        end)
        autoClaimAllThread = nil
    end
end

function invokeTroops(...)
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
TROOPS_ACTION_INTERVAL = 0.08
local troopsActionBusy = false

function invokeTroopsThrottled(...)
    while troopsActionBusy and runtimeAlive do
        task.wait(0.01)
    end
    if not runtimeAlive then
        return false, "Runtime stopped"
    end
    troopsActionBusy = true
    local args, result, done = table.pack(...), nil, false
    local timeoutThread
    -- Release the lock in the worker, even if the waiting feature gets cancelled.
    local worker = task.spawn(function()
        result = table.pack(pcall(function()
            local elapsed = tick() - lastTroopsActionAt
            if elapsed < TROOPS_ACTION_INTERVAL then
                task.wait(TROOPS_ACTION_INTERVAL - elapsed)
            end
            if not runtimeAlive then
                return false, "Runtime stopped"
            end
            lastTroopsActionAt = tick()
            return invokeTroops(table.unpack(args, 1, args.n))
        end))
        done, troopsActionBusy = true, false
        if timeoutThread then
            pcall(task.cancel, timeoutThread)
        end
    end)
    if not done then
        timeoutThread = task.delay(12, function()
            if done then
                return
            end
            pcall(task.cancel, worker)
            result = table.pack(true, false, "Tower action timed out")
            done, troopsActionBusy = true, false
        end)
    end
    while not done and runtimeAlive do
        task.wait(0.01)
    end
    if not done then
        return false, "Runtime stopped"
    end
    if not result[1] then
        return false, result[2]
    end
    return result[2], result[3]
end

function voteSkip()
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

function fireConsumable(...)
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

function autoVoteSkipIfEnabled()
    if autoskipEnabled ~= true and tdsSettings.autoskipEnabled ~= true then
        return false
    end
    local callOk, ok = pcall(voteSkip)
    return callOk and ok == true
end

function readTimescaleTickets()
    local ok, value = pcall(function()
        local cacheModule = safeRequirePath("Client.Modules.Cache", ReplicatedStorage, "Client", "Modules", "Cache")
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

function unlockTimeScale()
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

function cycleTimeScale()
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

function waitForTimeScale(targetScale, timeout)
    targetScale = tonumber(targetScale) or 1
    timeout = timeout or 2
    local start = tick()
    while tick() - start < timeout do
        if math.abs(getGameTimeScale() - targetScale) <= 0.05 then
            return true
        end
        task.wait(0.05)
    end
    return false
end

function doTimeScaleUnlock()
    if not isTimeScaleLocked() then
        return true
    end
    local tickets = readTimescaleTickets()
    if tickets and tickets <= 0 then
        warn("[Zephyr] Timescale ticket cache reported 0; trying unlock anyway.")
    end
    local ok, result = unlockTimeScale()
    if not ok then
        warn("[Zephyr] Timescale unlock failed:", tostring(result))
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

function doTimeScale(action)
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
            warn("[Zephyr] Timescale cycle failed:", tostring(result))
            return false
        end
        if waitForTimeScale(target, 1.25) then
            return true
        end
    end
    warn("[Zephyr] Timescale target not reached:", target, "current", getGameTimeScale())
    return false
end

function runSourceScript(source)
    if type(loadstring) ~= "function" then
        return false, "loadstring unavailable"
    end
    local compileOk, fnOrErr, compileErr = pcall(loadstring, source)
    if not compileOk or type(fnOrErr) ~= "function" then
        return false, fnOrErr or compileErr
    end
    return pcall(fnOrErr)
end

function runRemoteScript(url)
    local fetchOk, sourceOrErr = pcall(function()
        return game:HttpGet(url)
    end)
    if not fetchOk or type(sourceOrErr) ~= "string" then
        return false, sourceOrErr
    end
    return runSourceScript(sourceOrErr)
end

function isMacroSessionActive(session)
    return macroPlaying and macroSession == session
end

function stopMacroPlayback()
    macroPlaying = false
    macroSession += 1
end

placeAttemptBusy = false

function doPlace(action, session, shouldStop, extraRetryTime)
    local posVec = action.data.position
    if typeof(posVec) == "vector" then
        posVec = Vector3.new(posVec.x, posVec.y, posVec.z)
    end
    local start = tick()
    local baseTimeout = PLACE_RETRY_TIMEOUT + (tonumber(extraRetryTime) or 0)
    local timeout = baseTimeout
    local failedAttempts = 0
    local waitingForSlot = false
    local lastPlaceReject = nil
    local lastCashWaitLog = 0
    local function waitForTowerSlot(count, limit)
        timeout = math.max(timeout, PLACE_SLOT_WAIT_TIMEOUT + (tonumber(extraRetryTime) or 0))
        if not waitingForSlot then
            waitingForSlot = true
            warn(
                "[Zephyr] Waiting for tower slot:",
                action.data.tower,
                tostring(count) .. "/" .. tostring(limit or "?")
            )
        end
        task.wait(0.5)
    end
    local function notePlaceReject(status, reason)
        if not reason then
            return
        end
        local reasonText = tostring(reason)
        local lowerReason = reasonText:lower()
        local isMoneyWait = lowerReason:find("need $", 1, true)
            or lowerReason:find("more to place", 1, true)
            or lowerReason:find("not enough", 1, true)
            or lowerReason:find("can't afford", 1, true)
            or lowerReason:find("insufficient", 1, true)
        local message = tostring(status) .. "|" .. (isMoneyWait and "cash" or reasonText)
        if message ~= lastPlaceReject then
            lastPlaceReject = message
            warn(
                "[Zephyr] Place rejected:",
                action.data.tower,
                posVec,
                isMoneyWait and "waiting for cash" or reasonText
            )
        end
    end
    while isMacroSessionActive(session) and tick() - start < timeout do
        if shouldStop and shouldStop() then
            return false
        end
        local towerCount, towerLimit = getTowerLimitState()
        if towerLimit and towerCount >= towerLimit then
            waitForTowerSlot(towerCount, towerLimit)
            continue
        end
        while placeAttemptBusy and isMacroSessionActive(session) do
            task.wait(0.02)
        end
        if not isMacroSessionActive(session) then
            return false
        end
        placeAttemptBusy = true
        local attemptOk, placed, placeStatus = pcall(function()
            local beforeCount = countTowersNearPos(posVec, PLACE_VERIFY_RADIUS)
            local remoteOk, placeResult = invokeTroopsThrottled("Place", {
                Rotation = action.data.rotation,
                Position = action.data.position,
            }, action.data.tower)
            local resultPlaced, resultStatus, resultReason = getPlaceResultStatus(remoteOk, placeResult)
            if resultPlaced == true then
                return true
            end
            notePlaceReject(resultStatus, resultReason)
            if resultStatus == "cash" then
                return false, "cash"
            end
            if resultStatus == "slot" then
                return false, "slot"
            end
            if resultStatus == "blocked" then
                if findTowerNearPos(posVec, PLACE_VERIFY_RADIUS) then
                    return true
                end
                return false, "blocked"
            end
            if resultStatus == "retry" or resultStatus == "remote" then
                return false, "retry"
            end
            return waitForTowerCountIncrease(posVec, beforeCount, 1.25, shouldStop)
        end)
        placeAttemptBusy = false
        if not attemptOk then
            error(placed, 0)
        end
        if placed then
            return true
        end
        failedAttempts += 1
        towerCount, towerLimit = getTowerLimitState()
        if placeStatus == "blocked" then
            warn("[Zephyr] Place impossible; skipping:", action.data.tower, posVec)
            return false
        elseif placeStatus == "cash" then
            if tick() - lastCashWaitLog >= 8 then
                lastCashWaitLog = tick()
                warn("[Zephyr] Waiting for cash before placing:", action.data.tower, "cash", getCash())
            end
            task.wait(0.5)
        elseif placeStatus == "slot" then
            waitForTowerSlot(towerCount, towerLimit)
        elseif towerLimit and towerCount >= towerLimit then
            waitForTowerSlot(towerCount, towerLimit)
        else
            task.wait(0.1)
        end
    end
    local towerCount, towerLimit = getTowerLimitState()
    warn(
        "[Zephyr] Place timed out:",
        action.data.tower,
        posVec,
        "cash",
        getCash(),
        "towers",
        tostring(towerCount) .. "/" .. tostring(towerLimit or "?")
    )
    return false
end

function doUpgrade(action, session, shouldStop, extraRetryTime)
    local start = tick()
    local retryForever = (tonumber(extraRetryTime) or 0) >= (MONEY_PLAYBACK_RETRY_FOREVER / 2)
    local timeout = retryForever and MONEY_PLAYBACK_RETRY_FOREVER
        or (UPGRADE_RETRY_TIMEOUT + (tonumber(extraRetryTime) or 0))
    local missingTargetDeadline = retryForever and nil or (start + math.min(timeout, UPGRADE_TARGET_FIND_TIMEOUT))
    local lastMissingLog = 0
    local lastUpgradeWaitLog = 0
    while isMacroSessionActive(session) and tick() - start < timeout do
        if shouldStop and shouldStop() then
            return false
        end
        local troop = findTowerNearPos(action.data.troopPos, retryForever and PLACE_VERIFY_RADIUS or nil)
        if not troop then
            if missingTargetDeadline and tick() >= missingTargetDeadline then
                warn("[Zephyr] Upgrade target missing; skipping:", action.data.troopPos, action.data.path)
                return false
            end
            if retryForever and tick() - lastMissingLog >= 8 then
                lastMissingLog = tick()
                warn("[Zephyr] Waiting for upgrade target:", action.data.troopPos, action.data.path)
            end
            task.wait(retryForever and 0.3 or 0.1)
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
        if retryForever and tick() - lastUpgradeWaitLog >= 8 then
            lastUpgradeWaitLog = tick()
            warn("[Zephyr] Waiting to upgrade:", action.data.troopPos, action.data.path, "cash", getCash())
        end
        task.wait(retryForever and 0.25 or 0.1)
    end
    warn("[Zephyr] Upgrade timed out:", action.data.troopPos, action.data.path)
    return false
end

function doSell(action, session, shouldStop)
    local start = tick()
    while isMacroSessionActive(session) and tick() - start < SELL_RETRY_TIMEOUT do
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
            task.wait(0.1)
        end
    end
    warn("[Zephyr] Sell timed out:", action.data.troopPos)
    return false
end

function doTarget(action, session, shouldStop)
    local start = tick()
    while isMacroSessionActive(session) and tick() - start < TARGET_RETRY_TIMEOUT do
        if shouldStop and shouldStop() then
            return false
        end
        local troop = findTowerNearPos(action.data.troopPos)
        if troop then
            invokeTroopsThrottled("Target", "Set", { Troop = troop, Target = action.data.target })
            return true
        end
        task.wait(0.1)
    end
    return false
end

function doAbility(action, session, shouldStop)
    local start = tick()
    while isMacroSessionActive(session) and tick() - start < ABILITY_RETRY_TIMEOUT do
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
    return false
end

function doOption(action, session, shouldStop)
    local start = tick()
    while isMacroSessionActive(session) and tick() - start < OPTION_RETRY_TIMEOUT do
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
    return false
end

function doConsumable(action, session, shouldStop)
    if not isMacroSessionActive(session) then
        return false
    end
    if shouldStop and shouldStop() then
        return false
    end
    local data = action and action.data or {}
    local name = tostring(data.name or "")
    if name == "" then
        warn("[Zephyr] Consumable skipped: name missing.")
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
        warn("[Zephyr] Consumable failed:", name, tostring(result))
        return false
    end
    return true
end

function getHealthText()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local topDisplay = gui and gui:FindFirstChild("ReactGameTopGameDisplay")
    local frame = topDisplay and topDisplay:FindFirstChild("Frame")
    local healthbar = frame and frame:FindFirstChild("healthbar")
    local progress = healthbar and healthbar:FindFirstChild("progress")
    return progress and progress.Text or nil
end

function getBaseHealth()
    local state = ReplicatedStorage:FindFirstChild("State")
    local health = state and state:FindFirstChild("Health")
    local currentValue = health and health:FindFirstChild("Current")
    local maxValue = health and health:FindFirstChild("Max")

    local current, maximum
    if currentValue then
        pcall(function()
            current = tonumber(currentValue.Value)
        end)
    end
    if maxValue then
        pcall(function()
            maximum = tonumber(maxValue.Value)
        end)
    end

    if current ~= nil then
        return current, maximum, "state"
    end

    local text = getHealthText()
    if type(text) == "string" then
        local currentText, maximumText = text:match("(%d+)%s*/%s*(%d+)")
        if currentText then
            return tonumber(currentText), tonumber(maximumText), "ui"
        end
        local single = tonumber(text:match("(%d+)"))
        if single ~= nil then
            return single, nil, "ui"
        end
    end

    return nil, nil, nil
end

function isBaseDown()
    local current = getBaseHealth()
    return current ~= nil and current <= 0
end

function isNewRewardsGuiEnabled()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local rewards = gui and gui:FindFirstChild("ReactGameNewRewards")
    if not rewards then
        return false
    end
    if rewards:IsA("ScreenGui") and rewards.Enabled == false then
        return false
    end
    if rewards:IsA("GuiObject") and rewards.Visible == false then
        return false
    end

    local function isEffectivelyVisible(obj)
        if not obj:IsA("GuiObject") then
            return false
        end
        local current = obj
        while current and current ~= rewards do
            if current:IsA("GuiObject") and current.Visible == false then
                return false
            end
            current = current.Parent
        end
        local ok, size = pcall(function()
            return obj.AbsoluteSize
        end)
        return not ok or (size.X > 2 and size.Y > 2)
    end

    local function isRewardsText(text)
        text = tostring(text or ""):upper()
        return text:find("TRIUMPH", 1, true)
            or text:find("DEFEAT", 1, true)
            or text:find("PLAY AGAIN", 1, true)
            or text:find("RETURN TO LOBBY", 1, true)
            or text:find("TIME COMPLETED", 1, true)
    end

    for _, desc in ipairs(rewards:GetDescendants()) do
        if
            (desc:IsA("TextLabel") or desc:IsA("TextButton"))
            and isEffectivelyVisible(desc)
            and isRewardsText(desc.Text)
        then
            return true
        end
    end

    return false
end

scheduleAutoRejoinAfterEnd = nil

task.spawn(function()
    while runtimeAlive do
        local health = getBaseHealth()
        if health then
            if health <= 0 then
                if not baseHealthWasDown then
                    lastBaseHealthDownAt = tick()
                end
                baseHealthWasDown = true
                if scheduleAutoRejoinAfterEnd then
                    scheduleAutoRejoinAfterEnd()
                end
            elseif baseHealthWasDown then
                baseHealthWasDown = false
                baseHealthRestartSerial += 1
                lastBaseHealthRestoredAt = tick()
            end
        end
        local rewardsVisible = isNewRewardsGuiEnabled()
        if
            rewardsVisible
            and isAutoRejoinEnabled()
            and not autoRejoinEndThread
            and tick() - lastRewardsAutoRejoinAt > 5
        then
            lastRewardsAutoRejoinAt = tick()
            notify("Rewards detected: auto rejoin strat")
            if scheduleAutoRejoinAfterEnd then
                scheduleAutoRejoinAfterEnd("rewards")
            end
        end
        rewardsAutoRejoinWasVisible = rewardsVisible
        task.wait(AUTO_RESPAWN_POLL)
    end
end)

function startAutoRespawnVote()
    if autoRespawnVoteThread then
        return
    end
    autoRespawnVoteEnabled = true
    autoRespawnVoteThread = task.spawn(function()
        local function shouldRestart()
            local current, maximum = getBaseHealth()
            if current == nil then
                return false
            end
            if current <= 0 then
                return true
            end
            if maximum == nil or maximum > 1 or current > 1 then
                return false
            end

            local managers = CollectionService:GetTagged("VoteManager")
            local manager = managers and managers[1]
            if not manager then
                return false
            end
            local enabled = manager:GetAttribute("Enabled")
            local title = manager:GetAttribute("Title")
            local enabledValue = manager:FindFirstChild("Enabled")
            local titleValue = manager:FindFirstChild("Title")
            if enabledValue then
                pcall(function()
                    enabled = enabledValue.Value
                end)
            end
            if titleValue then
                pcall(function()
                    title = titleValue.Value
                end)
            end
            return enabled == true and tostring(title or ""):upper():find("RESTART", 1, true) ~= nil
        end

        while autoRespawnVoteEnabled do
            if shouldRestart() then
                while autoRespawnVoteEnabled and shouldRestart() do
                    voteSkip()
                    task.wait(AUTO_RESPAWN_POLL)
                end
            else
                task.wait(AUTO_RESPAWN_POLL)
            end
        end
        autoRespawnVoteThread = nil
    end)
end

function stopAutoRespawnVote()
    autoRespawnVoteEnabled = false
    if autoRespawnVoteThread then
        task.cancel(autoRespawnVoteThread)
        autoRespawnVoteThread = nil
    end
end

function scheduleAutoRerunStrat(runAgain, onQueued, onRun)
    if not autoRerunStratsEnabled or type(runAgain) ~= "function" then
        return
    end
    autoRerunSerial += 1
    local serial = autoRerunSerial
    task.spawn(function()
        if onQueued then
            onQueued()
        end
        local restartSeen = waitForHealthRestart(AUTO_RERUN_TIMEOUT)
        if not autoRerunStratsEnabled or serial ~= autoRerunSerial or not restartSeen then
            return
        end
        local start = tick()
        while autoRerunStratsEnabled and serial == autoRerunSerial and tick() - start < 10 do
            if runAgain() then
                if onRun then
                    onRun()
                end
                return
            end
            task.wait(0.1)
        end
    end)
end

function playMacro(actions, onDone, onStarted, options)
    if macroPlaying then
        if onDone then
            onDone(false, "busy")
        end
        return false
    end
    if not actions or #actions == 0 then
        if onDone then
            onDone(false, "empty")
        end
        return false
    end
    macroPlaying = true
    macroSession += 1
    local session = macroSession
    options = type(options) == "table" and options or {}
    local actionLeadTime = math.min(MAX_ACTION_LEAD_TIME, math.max(0, tonumber(options.actionLeadTime) or 0))
    local moneyPlaybackMode = options.moneyPlayback
    if moneyPlaybackMode == nil then
        moneyPlaybackMode = tdsSettings.playbackMoneyModeEnabled == true
    end
    moneyPlaybackMode = moneyPlaybackMode == true
    task.spawn(function()
        local started = waitForWave(MACRO_START_WAVE, MACRO_START_TIMEOUT)
        if not started then
            warn("[Zephyr] Macro playback cancelled: wave 1 was not detected.")
            if macroSession == session then
                macroPlaying = false
            end
            if onDone then
                onDone(false, "wave-timeout")
            end
            return
        end
        if onStarted then
            onStarted()
        end
        do
            local placeActions, sellActions, upgradeActions = 0, 0, 0
            local consumableActions = 0
            for _, action in ipairs(actions) do
                if action.type == "Place" then
                    placeActions += 1
                elseif action.type == "Sell" then
                    sellActions += 1
                end
                if action.type == "Upgrade" then
                    upgradeActions += 1
                end
                if action.type == "Consumable" then
                    consumableActions += 1
                end
            end
            warn(
                "[Zephyr] Macro action summary:",
                tostring(#actions) .. " actions,",
                tostring(placeActions) .. " places,",
                tostring(sellActions) .. " sells,",
                tostring(upgradeActions) .. " upgrades,",
                tostring(consumableActions) .. " consumables"
            )
            local currentTowerCount, towerLimit = getTowerLimitState()
            local possiblePlaces = towerLimit and math.max(0, towerLimit - currentTowerCount) + sellActions or nil
            if possiblePlaces and placeActions > possiblePlaces then
                warn(
                    "[Zephyr] Strat has more place actions than available tower slots:",
                    tostring(placeActions) .. " places,",
                    tostring(sellActions) .. " sells,",
                    "current towers",
                    tostring(currentTowerCount) .. "/" .. tostring(towerLimit)
                )
            end
        end
        local useGameTiming = actions.timingMode == "game"
        local getPlaybackElapsed = makePlaybackClock(useGameTiming)
        warn("[Zephyr] Macro timing mode:", useGameTiming and "game-time" or "real-time")
        local highestWaveSeen = getCurrentWave() or MACRO_START_WAVE
        local resetWaveSeenAt = nil
        local waveResetObserved = false
        local stoppedByBaseDown = false
        local function shouldStopPlayback()
            local current = getCurrentWave()
            if current and current > highestWaveSeen then
                highestWaveSeen = current
            end
            local waveLooksReset = current == ROUND_RESET_WAVE
                or (current == MACRO_START_WAVE and highestWaveSeen > MACRO_START_WAVE)
            if waveLooksReset then
                resetWaveSeenAt = resetWaveSeenAt or tick()
            else
                resetWaveSeenAt = nil
            end
            if waveLooksReset and tick() - resetWaveSeenAt >= ROUND_RESET_CONFIRM_TIME then
                waveResetObserved = true
            end
            stoppedByBaseDown = isBaseDown() or baseHealthWasDown
            return stoppedByBaseDown
        end
        local function waitForActionWave(targetWave)
            local start = tick()
            while tick() - start < MACRO_START_TIMEOUT do
                getPlaybackElapsed()
                if shouldStopPlayback() then
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
        local activeWorkers = 0
        local function spawnActionWorker(fn)
            activeWorkers += 1
            task.spawn(function()
                local ok, err = pcall(fn)
                if not ok then
                    warn("[Zephyr] Macro action error:", tostring(err))
                end
                activeWorkers -= 1
            end)
        end
        local function runActionBlocking(currentAction, earlyBy)
            local retryBonus = moneyPlaybackMode and MONEY_PLAYBACK_RETRY_FOREVER or 0
            local upgradeRetryBonus = moneyPlaybackMode and MONEY_PLAYBACK_RETRY_FOREVER or 0
            local ok, result = pcall(function()
                if currentAction.type == "Place" then
                    return doPlace(currentAction, session, shouldStopPlayback, retryBonus)
                end
                if currentAction.type == "Upgrade" then
                    return doUpgrade(currentAction, session, shouldStopPlayback, upgradeRetryBonus)
                end
                if currentAction.type == "Sell" then
                    return doSell(currentAction, session, shouldStopPlayback)
                end
                if currentAction.type == "Target" then
                    return doTarget(currentAction, session, shouldStopPlayback)
                end
                if currentAction.type == "Ability" then
                    return doAbility(currentAction, session, shouldStopPlayback)
                end
                if currentAction.type == "Option" then
                    return doOption(currentAction, session, shouldStopPlayback)
                end
                if currentAction.type == "Consumable" then
                    return doConsumable(currentAction, session, shouldStopPlayback)
                end
                if currentAction.type == "TimeScaleUnlock" then
                    return doTimeScaleUnlock()
                end
                if currentAction.type == "TimeScale" then
                    return doTimeScale(currentAction)
                end
                if currentAction.type == "Skip" then
                    voteSkip()
                    return true
                end
                return true
            end)
            if not ok then
                warn("[Zephyr] Macro action error:", tostring(result))
                return false
            end
            return result ~= false
        end
        if moneyPlaybackMode then
            warn("[Zephyr] Macro playback mode: cash-based order. Action timestamps will be ignored.")
        end
        for _, action in ipairs(actions) do
            local currentAction = action
            local actionTime = tonumber(currentAction.time) or 0
            local earlyBy = 0
            if not isMacroSessionActive(session) then
                break
            end
            if shouldStopPlayback() then
                break
            end
            if not moneyPlaybackMode then
                local scheduledTime = actionTime
                if actionLeadTime > 0 and currentAction.type == "Place" then
                    scheduledTime = math.max(0, actionTime - actionLeadTime)
                    earlyBy = actionTime - scheduledTime
                end
                if not waitForMacroTime(getPlaybackElapsed, scheduledTime, shouldStopPlayback) then
                    break
                end
            end
            if not isMacroSessionActive(session) then
                break
            end
            if moneyPlaybackMode then
                runActionBlocking(currentAction, earlyBy)
            else
                if currentAction.type == "Place" then
                    spawnActionWorker(function()
                        doPlace(currentAction, session, shouldStopPlayback, earlyBy)
                    end)
                elseif currentAction.type == "Upgrade" then
                    spawnActionWorker(function()
                        doUpgrade(currentAction, session, shouldStopPlayback, earlyBy)
                    end)
                elseif currentAction.type == "Sell" then
                    spawnActionWorker(function()
                        doSell(currentAction, session, shouldStopPlayback)
                    end)
                elseif currentAction.type == "Target" then
                    spawnActionWorker(function()
                        doTarget(currentAction, session, shouldStopPlayback)
                    end)
                elseif currentAction.type == "Ability" then
                    spawnActionWorker(function()
                        doAbility(currentAction, session, shouldStopPlayback)
                    end)
                elseif currentAction.type == "Option" then
                    spawnActionWorker(function()
                        doOption(currentAction, session, shouldStopPlayback)
                    end)
                elseif currentAction.type == "Consumable" then
                    spawnActionWorker(function()
                        doConsumable(currentAction, session, shouldStopPlayback)
                    end)
                elseif currentAction.type == "TimeScaleUnlock" or currentAction.type == "TimeScale" then
                    runActionBlocking(currentAction, earlyBy)
                elseif currentAction.type == "Skip" then
                    voteSkip()
                end
            end
        end
        if stoppedByBaseDown then
            warn("[Zephyr] Macro playback stopped because the base is down. Highest wave seen:", highestWaveSeen)
        elseif waveResetObserved then
            warn("[Zephyr] Ignored wave reset-looking UI during macro playback. Highest wave seen:", highestWaveSeen)
        end
        local drainStart = tick()
        while isMacroSessionActive(session) and activeWorkers > 0 and tick() - drainStart < UPGRADE_RETRY_TIMEOUT do
            if shouldStopPlayback() then
                break
            end
            task.wait(0.1)
        end
        local completedActiveSession = macroSession == session
        if completedActiveSession then
            macroPlaying = false
        end
        if onDone then
            onDone(completedActiveSession)
        end
    end)
    return true
end

function copyModeInfo(modeInfo)
    if type(modeInfo) ~= "table" then
        return nil
    end
    return {
        mode = modeInfo.mode,
        diff = modeInfo.diff,
        special = modeInfo.special == true,
    }
end

function resolveMacroModeInfo(macro)
    if type(macro) ~= "table" then
        return nil
    end
    local modeInfo = copyModeInfo(macro.modeInfo)
    if modeInfo then
        return modeInfo
    end
    local rawDifficulty = trimText(macro.launchDifficulty or macro.modeName or macro.mode or "")
    if rawDifficulty == "" then
        rawDifficulty = trimText(macro.difficulty)
    end
    if rawDifficulty ~= "" then
        local difficulty = normalizeAutoRejoinMode(rawDifficulty)
        if DIFFICULTY_MAP[difficulty] then
            return copyModeInfo(DIFFICULTY_MAP[difficulty])
        end
    end
    local mapName = normalizeAutoRejoinMap(macro.map)
    if mapName ~= "" then
        return copyModeInfo(getMapDefaults(mapName))
    end
    return nil
end

function feedbackFromMetadata(meta)
    if type(meta) ~= "table" then
        return { likes = 0, dislikes = 0, reports = 0 }
    end
    local feedback = type(meta.feedback) == "table" and meta.feedback or meta
    return {
        likes = tonumber(feedback.likes or feedback.upvotes or feedback.up or 0) or 0,
        dislikes = tonumber(feedback.dislikes or feedback.downvotes or feedback.down or 0) or 0,
        reports = tonumber(feedback.reports or feedback.flags or 0) or 0,
    }
end

function buildCustomStratMacro(saved, index)
    if type(saved) ~= "table" then
        return nil
    end
    local content = type(saved.stratContent) == "string" and saved.stratContent or ""
    local url = type(saved.stratUrl) == "string" and saved.stratUrl or ""
    if content:match("%S") == nil and url:match("^%s*https?://") == nil then
        return nil
    end

    local modeName = normalizeAutoRejoinMode(saved.mode or saved.launchDifficulty or "")
    local modeInfo = DIFFICULTY_MAP[modeName] and copyModeInfo(DIFFICULTY_MAP[modeName])
        or copyModeInfo(getMapDefaults(saved.map))
    if modeName == "" then
        modeName = modeNameFromModeInfo(modeInfo, "")
    end
    local loadout = splitList(saved.loadout or "")
    if #loadout == 0 and content ~= "" then
        loadout = detectTowersFromContent(content)
    end
    if #loadout == 0 then
        loadout = { "Custom" }
    end
    local timeMins = tonumber(saved.time) or tonumber(saved.timeMinutes) or 0
    local timeLabel = saved.timeLabel
    if (not timeLabel or timeLabel == "") and timeMins > 0 then
        local mins = math.floor(timeMins)
        local secs = math.floor((timeMins - mins) * 60 + 0.5)
        timeLabel = tostring(mins) .. "m " .. tostring(secs) .. "s"
    end

    return {
        id = "custom:" .. tostring(saved.id or index or saved.name or "local"),
        customId = saved.id,
        customIndex = index,
        isCustom = true,
        category = "Custom",
        name = trimText(saved.name or "Saved Strat"),
        subtitle = trimText(saved.subtitle or "Saved locally"),
        color = Color3.fromRGB(20, 184, 166),
        loadout = loadout,
        difficulty = "Custom",
        launchDifficulty = modeName,
        modeInfo = modeInfo,
        map = trimText(saved.map or "Crossroads"),
        time = timeMins,
        timeLabel = timeLabel,
        coins = tonumber(saved.coins) or tonumber(saved.cph) or 0,
        xp = tonumber(saved.xp) or 0,
        cph = tonumber(saved.cph) or 0,
        gph = tonumber(saved.gph) or 0,
        note = trimText(saved.note or ""),
        stratContent = content ~= "" and content or nil,
        stratUrl = url:match("^%s*https?://") and trimText(url) or nil,
        feedback = { likes = 0, dislikes = 0, reports = 0 },
    }
end

function makeSavedStratDescriptor(macro, contentOverride)
    if type(macro) ~= "table" then
        return nil
    end
    local savedContent = type(contentOverride) == "string" and contentOverride:match("%S") and contentOverride
        or macro.stratContent
    local hasStratContent = type(savedContent) == "string" and savedContent:match("%S") ~= nil
    local hasStratUrl = type(macro.stratUrl) == "string" and macro.stratUrl:match("^%s*https?://") ~= nil
    if not hasStratContent and not hasStratUrl then
        return nil
    end
    return {
        savedBy = "ZephyrTDS",
        schema = 2,
        savedAt = os.time(),
        stratId = getStratIdentity(macro),
        name = tostring(macro.name or "Last Strat"),
        map = normalizeAutoRejoinMap(macro.map),
        stratUrl = hasStratUrl and macro.stratUrl or nil,
        stratContent = hasStratContent and savedContent or nil,
        modeInfo = resolveMacroModeInfo(macro),
        actionLeadTime = tonumber(macro.actionLeadTime) or 0,
    }
end

function rememberLastStrat(macro, contentOverride)
    local descriptor = makeSavedStratDescriptor(macro, contentOverride)
    if not descriptor then
        return nil
    end
    tdsSettings.lastStrat = descriptor
    saveSettingsSoon()
    saveSettingsNow()
    return descriptor
end

function getSavedStratText()
    local saved = tdsSettings.lastStrat
    if type(saved) ~= "table" then
        return false, "No saved strat"
    end
    if saved.savedBy ~= "ZephyrTDS" then
        return false, "Old saved strat ignored. Run a strat once to save it again."
    end
    if type(saved.stratContent) == "string" and saved.stratContent:match("%S") then
        return true, saved.stratContent
    end
    if type(saved.stratUrl) == "string" and saved.stratUrl:match("^%s*https?://") then
        local fetchOk, source = pcall(function()
            return game:HttpGet(saved.stratUrl)
        end)
        if fetchOk and type(source) == "string" and source:match("%S") then
            return true, source
        end
        return false, source or "Strat URL failed"
    end
    return false, "Saved strat has no content"
end

function replaySavedLastStrat(reason)
    local saved = tdsSettings.lastStrat
    if type(saved) ~= "table" then
        notify("No last strat saved yet")
        return false
    end
    if macroPlaying then
        stopMacroPlayback()
        task.wait(0.1)
    end
    local stratOk, stratText = getSavedStratText()
    if not stratOk then
        notify("Saved strat failed: " .. tostring(stratText))
        return false
    end
    local actions = parseAndLoad(stratText)
    if not actions or #actions == 0 then
        notify("Saved strat has no actions")
        return false
    end
    return playMacro(actions, function(ok, failReason)
        if not ok then
            notify("Saved strat stopped: " .. tostring(failReason or "unknown"))
        end
    end, function()
        notify(
            (reason == "lobby" and "Lobby replaying: " or "Auto replaying: ") .. tostring(saved.name or "Last Strat")
        )
    end, { actionLeadTime = tonumber(saved.actionLeadTime) or 0 })
end

function startConfiguredAutoRejoinMatch(preferSaved)
    local payload = buildAutoRejoinStartPayload(preferSaved ~= false)
    return invokeRemoteFunction("Multiplayer", "v2:start", payload)
end

function sendLobbyMapVotePulse(mapName, startPayload, useOverride, includeReadyStart)
    mapName = normalizeAutoRejoinMap(mapName)
    if mapName == "" then
        return false, "map empty"
    end
    local pos = getLobbyVotePosition()
    local sent = false
    local lastResult = nil

    local function mark(ok, result)
        sent = sent or ok == true
        if result ~= nil then
            lastResult = result
        end
    end

    if useOverride ~= false then
        mark(invokeRemoteFunction("LobbyVoting", "Override", mapName))
        mark(invokeNewNetwork("LobbyVoting", "function", "Override", mapName))
        mark(invokeNewNetwork("LobbyVoting", "event", "Override", mapName))
    end

    mark(fireRemoteEvent("LobbyVoting", "Vote", mapName, pos))
    mark(invokeRemoteFunction("LobbyVoting", "Vote", mapName, pos))
    mark(invokeNewNetwork("LobbyVoting", "event", "Vote", mapName, pos))
    mark(invokeNewNetwork("LobbyVoting", "function", "Vote", mapName, pos))

    if includeReadyStart ~= false then
        mark(fireRemoteEvent("LobbyVoting", "Ready"))
        mark(fireRemoteEvent("LobbyVoting", "Ready", true))
        mark(invokeRemoteFunction("LobbyVoting", "Ready"))
        mark(invokeRemoteFunction("LobbyVoting", "Ready", true))
        mark(invokeNewNetwork("LobbyVoting", "event", "Ready"))
        mark(invokeNewNetwork("LobbyVoting", "function", "Ready"))
        mark(invokeNewNetwork("Elevators", "function", "SetReady", true))
        mark(invokeNewNetwork("Elevators", "event", "SetReady", true))

        if type(startPayload) == "table" then
            mark(invokeRemoteFunction("Multiplayer", "v2:start", startPayload))
        end
    end

    return sent, lastResult
end

function isGuiObjectEffectivelyVisible(obj)
    if not obj or not obj:IsA("GuiObject") then
        return false
    end
    local current = obj
    while current do
        if current:IsA("GuiObject") and current.Visible == false then
            return false
        end
        if current:IsA("ScreenGui") and current.Enabled == false then
            return false
        end
        current = current.Parent
    end
    local ok, size = pcall(function()
        return obj.AbsoluteSize
    end)
    return not ok or (size.X > 2 and size.Y > 2)
end

function isZephyrGuiObject(obj)
    local current = obj
    while current do
        if current:IsA("ScreenGui") then
            local name = tostring(current.Name or "")
            return name == "ZephyrTDS" or name == "ZephyrTDSMatchTracker" or name == "ZephyrTDSEnemyInspector"
        end
        current = current.Parent
    end
    return false
end

function getGuiObjectText(obj)
    local parts = {}
    local ok, text = pcall(function()
        return obj.Text
    end)
    if ok and type(text) == "string" then
        table.insert(parts, text)
    end
    for _, desc in ipairs(obj:GetDescendants()) do
        if desc:IsA("TextLabel") or desc:IsA("TextButton") then
            local descOk, descText = pcall(function()
                return desc.Text
            end)
            if descOk and type(descText) == "string" then
                table.insert(parts, descText)
            end
        end
    end
    return table.concat(parts, " "):upper()
end

function getReactOverridesVoteFrame()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local voteGui = gui and gui:FindFirstChild("ReactOverridesVote")
    if not voteGui then
        return nil
    end
    if voteGui:IsA("ScreenGui") and voteGui.Enabled == false then
        return nil
    end
    local frame = voteGui:FindFirstChild("Frame")
    if frame and frame:IsA("GuiObject") then
        return frame
    end
    for _, child in ipairs(voteGui:GetChildren()) do
        if child:IsA("GuiObject") then
            return child
        end
    end
    return nil
end

function isReactOverridesVoteFrameVisible()
    local frame = getReactOverridesVoteFrame()
    return frame ~= nil and isGuiObjectEffectivelyVisible(frame)
end

function getReactOverridesVoteFrameText()
    local frame = getReactOverridesVoteFrame()
    if not frame or not isGuiObjectEffectivelyVisible(frame) then
        return ""
    end
    return getGuiObjectText(frame)
end

function isReactOverridesReadyPromptVisible()
    if not isReactOverridesVoteFrameVisible() then
        return false
    end
    local text = getReactOverridesVoteFrameText()
    if text:find("SKIP WAVE", 1, true) or text:find("RESTART", 1, true) then
        return false
    end
    return text:find("READY?", 1, true) ~= nil or text:match("%f[%a]READY%f[%A]") ~= nil
end

function readyTextMatches(text)
    text = tostring(text or ""):upper()
    if text:find("READY?", 1, true) or text:find("RESTART", 1, true) then
        return false
    end
    return text:match("%f[%a]READY%f[%A]") ~= nil
end

function findClickableGuiAncestor(obj)
    local current = obj
    while current do
        if current:IsA("GuiButton") then
            return current
        end
        current = current.Parent
    end
    return obj
end

readyButtonCache = nil
readyCandidateObjects = setmetatable({}, { __mode = "k" })
readyCandidateConnections = setmetatable({}, { __mode = "k" })
readyWatcherConnections = {}
readyWatcherGui = nil

function clearReadyButtonCache()
    readyButtonCache = nil
end

function getReadyOwnText(obj)
    local parts = { tostring(obj and obj.Name or "") }
    if obj and (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then
        local ok, text = pcall(function()
            return obj.Text
        end)
        if ok and type(text) == "string" then
            parts[#parts + 1] = text
        end
    end
    return table.concat(parts, " "):upper()
end

function updateReadyCandidate(obj)
    if not obj or not obj.Parent or isZephyrGuiObject(obj) then
        return
    end
    local text = getReadyOwnText(obj)
    if text:find("READY", 1, true) or text:find("REQUIRED", 1, true) or text:find("VOTE FOR A MAP", 1, true) then
        readyCandidateObjects[obj] = true
    else
        readyCandidateObjects[obj] = nil
    end
    clearReadyButtonCache()
end

function watchReadyCandidate(obj)
    if not obj or readyCandidateConnections[obj] then
        return
    end
    if not obj:IsA("GuiObject") then
        return
    end
    if not (obj:IsA("GuiButton") or obj:IsA("TextLabel") or obj:IsA("TextBox")) then
        return
    end
    if isZephyrGuiObject(obj) then
        return
    end

    local conns = {}
    local function addConn(conn)
        if conn then
            conns[#conns + 1] = conn
        end
    end
    pcall(function()
        addConn(obj:GetPropertyChangedSignal("Visible"):Connect(clearReadyButtonCache))
    end)
    if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
        pcall(function()
            addConn(obj:GetPropertyChangedSignal("Text"):Connect(function()
                updateReadyCandidate(obj)
            end))
        end)
    end
    pcall(function()
        addConn(obj.AncestryChanged:Connect(function()
            local gui = LocalPlayer:FindFirstChild("PlayerGui")
            if not gui or not obj:IsDescendantOf(gui) then
                readyCandidateObjects[obj] = nil
            else
                updateReadyCandidate(obj)
            end
            clearReadyButtonCache()
        end))
    end)
    readyCandidateConnections[obj] = conns
    updateReadyCandidate(obj)
end

function scanReadyCandidates(root)
    if not root then
        return
    end
    local scanned = 0
    for _, obj in ipairs(root:GetDescendants()) do
        watchReadyCandidate(obj)
        scanned += 1
        if scanned % 160 == 0 then
            task.wait()
        end
    end
end

function stopReadyGuiWatcher()
    for _, conn in ipairs(readyWatcherConnections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    clearTable(readyWatcherConnections)
    for _, conns in pairs(readyCandidateConnections) do
        for _, conn in ipairs(conns) do
            pcall(function()
                conn:Disconnect()
            end)
        end
    end
    readyCandidateConnections = setmetatable({}, { __mode = "k" })
    readyCandidateObjects = setmetatable({}, { __mode = "k" })
    readyWatcherGui = nil
    clearReadyButtonCache()
end

function startReadyGuiWatcher()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if not gui then
        return
    end
    if readyWatcherGui == gui then
        return
    end
    stopReadyGuiWatcher()
    readyWatcherGui = gui
    task.defer(scanReadyCandidates, gui)
    pcall(function()
        readyWatcherConnections[#readyWatcherConnections + 1] = gui.DescendantAdded:Connect(function(obj)
            watchReadyCandidate(obj)
        end)
    end)
    pcall(function()
        readyWatcherConnections[#readyWatcherConnections + 1] = gui.DescendantRemoving:Connect(function(obj)
            readyCandidateObjects[obj] = nil
            clearReadyButtonCache()
        end)
    end)
end

function findVisibleReadyButton()
    startReadyGuiWatcher()
    if
        readyButtonCache
        and readyButtonCache.Parent
        and not isZephyrGuiObject(readyButtonCache)
        and isGuiObjectEffectivelyVisible(readyButtonCache)
        and readyTextMatches(getGuiObjectText(readyButtonCache))
    then
        return readyButtonCache
    end

    for obj in pairs(readyCandidateObjects) do
        if obj and obj.Parent and not isZephyrGuiObject(obj) and isGuiObjectEffectivelyVisible(obj) then
            local text = obj:IsA("GuiButton") and getGuiObjectText(obj) or getReadyOwnText(obj)
            if readyTextMatches(text) then
                local button = findClickableGuiAncestor(obj)
                if button and button.Parent and button:IsA("GuiObject") and isGuiObjectEffectivelyVisible(button) then
                    readyButtonCache = button
                    return button
                end
            end
        else
            readyCandidateObjects[obj] = nil
        end
    end
    return nil
end

function isReadyVoteContextVisible()
    local managers = CollectionService:GetTagged("VoteManager")
    local manager = managers and managers[1]
    if manager then
        local voteEnabled = manager:GetAttribute("Enabled")
        local voteTitle = manager:GetAttribute("Title")
        local enabledValue = manager:FindFirstChild("Enabled")
        local titleValue = manager:FindFirstChild("Title")
        if enabledValue then
            pcall(function()
                voteEnabled = enabledValue.Value
            end)
        end
        if titleValue then
            pcall(function()
                voteTitle = titleValue.Value
            end)
        end
        if voteEnabled == true and tostring(voteTitle or ""):upper():find("READY", 1, true) then
            return true
        end
    end

    startReadyGuiWatcher()
    for obj in pairs(readyCandidateObjects) do
        if obj and obj.Parent and not isZephyrGuiObject(obj) and isGuiObjectEffectivelyVisible(obj) then
            local text = getReadyOwnText(obj)
            if text:find("REQUIRED", 1, true) or text:find("READY?", 1, true) then
                return true
            end
        else
            readyCandidateObjects[obj] = nil
        end
    end
    return false
end

mapVoteGuiScanAt = 0
mapVoteGuiScanValue = false
targetMapGuiScanAt = 0
targetMapGuiScanKey = ""
targetMapGuiScanValue = false
lobbyVoteBoardScanAt = 0
lobbyVoteBoardScanValue = {}

function invalidateLobbyVoteBoardCache()
    lobbyVoteBoardScanAt = 0
    lobbyVoteBoardScanValue = {}
end

function extractKnownVoteMapName(value)
    local raw = trimText(value)
    if raw == "" then
        return ""
    end
    local key = normalizeLookupText(raw)
    if key == "" then
        return ""
    end

    local alias = TDS_MAP_ALIASES and (TDS_MAP_ALIASES[raw:lower()] or TDS_MAP_ALIASES[key])
    if alias then
        return alias
    end

    local knownMaps = TDS_KNOWN_MAP_NAMES or TDS_MAP_OPTIONS or {}
    for _, option in ipairs(knownMaps) do
        if normalizeLookupText(option) == key then
            return option
        end
    end

    for _, option in ipairs(knownMaps) do
        local optionKey = normalizeLookupText(option)
        if #optionKey >= 5 and key:find(optionKey, 1, true) then
            return option
        end
    end

    if TDS_MAP_ALIASES then
        for aliasKey, aliasName in pairs(TDS_MAP_ALIASES) do
            local normalizedAliasKey = normalizeLookupText(aliasKey)
            if #normalizedAliasKey >= 5 and key:find(normalizedAliasKey, 1, true) then
                return aliasName
            end
        end
    end

    return ""
end

function addLobbyVoteBoardCandidate(candidates, seen, obj)
    if not obj or seen[obj] then
        return
    end
    seen[obj] = true
    candidates[#candidates + 1] = obj
end

function scanLobbyVoteBoardText(container, addMap)
    if not container then
        return
    end
    local scanned = 0
    local limit = ZephyrLowCompatExecutor and 260 or 900
    for _, obj in ipairs(container:GetDescendants()) do
        scanned += 1
        if scanned > limit then
            break
        end
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            local text = ""
            pcall(function()
                text = tostring(obj.Name or "") .. " " .. tostring(obj.Text or "")
            end)
            local mapName = extractKnownVoteMapName(text)
            if mapName ~= "" then
                addMap(mapName)
            end
        end
    end
end

function getLobbyVoteBoardMaps()
    local now = tick()
    local scanInterval = ZephyrLowCompatExecutor and 4.5 or 0.85
    if now - lobbyVoteBoardScanAt < scanInterval then
        return lobbyVoteBoardScanValue
    end
    lobbyVoteBoardScanAt = now

    local maps = {}
    local seen = {}
    local function addMap(value)
        local mapName = extractKnownVoteMapName(value)
        if mapName == "" then
            mapName = matchKnownOption(TDS_KNOWN_MAP_NAMES or TDS_MAP_OPTIONS, value, "")
        end
        mapName = trimText(mapName)
        if mapName ~= "" and not seen[mapName] then
            seen[mapName] = true
            maps[#maps + 1] = mapName
        end
    end

    for i = 1, 12 do
        local ok, value = pcall(function()
            return workspace:GetAttribute("Map" .. tostring(i))
        end)
        if ok then
            addMap(value)
        end
    end

    local candidates = {}
    local seenCandidates = {}
    local intermission = workspace:FindFirstChild("IntermissionLobby")
    addLobbyVoteBoardCandidate(candidates, seenCandidates, intermission)

    local boards = intermission and intermission:FindFirstChild("Boards")
    if boards then
        addLobbyVoteBoardCandidate(candidates, seenCandidates, boards)
        for _, board in ipairs(boards:GetChildren()) do
            local index = tostring(board.Name or ""):match("%d+")
            if index then
                local ok, value = pcall(function()
                    return workspace:GetAttribute("Map" .. index)
                end)
                if ok then
                    addMap(value)
                end
            end
            addLobbyVoteBoardCandidate(candidates, seenCandidates, board)
        end
    end

    for _, child in ipairs(workspace:GetChildren()) do
        local name = tostring(child.Name or ""):lower()
        if
            name:find("intermission", 1, true)
            or name:find("lobby", 1, true)
            or name:find("vote", 1, true)
            or name:find("board", 1, true)
            or name:find("map", 1, true)
        then
            addLobbyVoteBoardCandidate(candidates, seenCandidates, child)
            local childBoards = child:FindFirstChild("Boards")
            addLobbyVoteBoardCandidate(candidates, seenCandidates, childBoards)
        end
    end

    if #maps == 0 then
        local scanned = 0
        local limit = ZephyrLowCompatExecutor and 1600 or 5200
        for _, obj in ipairs(workspace:GetDescendants()) do
            scanned += 1
            if scanned > limit then
                break
            end
            local name = tostring(obj.Name or "")
            local lower = name:lower()
            if
                name == "MapDisplay"
                or name == "MapIcon"
                or name == "MapTitle"
                or name == "Boards"
                or lower:find("voteboard", 1, true)
                or lower:find("mapboard", 1, true)
            then
                addLobbyVoteBoardCandidate(candidates, seenCandidates, obj.Parent)
                addLobbyVoteBoardCandidate(candidates, seenCandidates, obj)
            elseif obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                local text = ""
                pcall(function()
                    text = tostring(obj.Name or "") .. " " .. tostring(obj.Text or "")
                end)
                local mapName = extractKnownVoteMapName(text)
                if mapName ~= "" then
                    addMap(mapName)
                end
            end
        end
    end

    for _, candidate in ipairs(candidates) do
        scanLobbyVoteBoardText(candidate, addMap)
    end

    lobbyVoteBoardScanValue = maps
    return maps
end

function hasLobbyVoteBoardMaps()
    return #getLobbyVoteBoardMaps() > 0
end

function isTargetMapInVoteBoards(mapName)
    local targetName = matchKnownOption(TDS_KNOWN_MAP_NAMES or TDS_MAP_OPTIONS, mapName, mapName)
    local targetKey = normalizeLookupText(targetName)
    if targetKey == "" then
        return false
    end
    for _, boardMap in ipairs(getLobbyVoteBoardMaps()) do
        if normalizeLookupText(boardMap) == targetKey then
            return true
        end
    end
    return false
end

function isMapVotingScreenVisible()
    if hasLobbyVoteBoardMaps() then
        return true
    end
    if ZephyrLowCompatExecutor then
        return false
    end

    local now = tick()
    local scanInterval = ZephyrLowCompatExecutor and 3 or 0.75
    if now - mapVoteGuiScanAt < scanInterval then
        return mapVoteGuiScanValue == true
    end
    mapVoteGuiScanAt = now
    mapVoteGuiScanValue = false

    startReadyGuiWatcher()
    for obj in pairs(readyCandidateObjects) do
        if obj and obj.Parent and not isZephyrGuiObject(obj) and isGuiObjectEffectivelyVisible(obj) then
            local text = getReadyOwnText(obj)
            if text:find("VOTE FOR A MAP", 1, true) then
                mapVoteGuiScanValue = true
                return true
            end
        else
            readyCandidateObjects[obj] = nil
        end
    end

    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if gui then
        local scanned = 0
        for _, obj in ipairs(gui:GetDescendants()) do
            if
                not isZephyrGuiObject(obj)
                and obj:IsA("GuiObject")
                and isGuiObjectEffectivelyVisible(obj)
                and (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox"))
            then
                local text = ""
                pcall(function()
                    text = tostring(obj.Text or ""):upper()
                end)
                if text:find("VOTE FOR A MAP", 1, true) then
                    mapVoteGuiScanValue = true
                    return true
                end
                scanned += 1
                if scanned >= (ZephyrLowCompatExecutor and 120 or 700) then
                    break
                end
            end
        end
    end

    return false
end

function isModeLockedVote(modeInfo)
    return type(modeInfo) == "table" and modeInfo.special == true
end

function textContainsVoteMap(text, targetKey)
    local textKey = normalizeLookupText(text)
    if textKey == "" or targetKey == "" then
        return false
    end
    return textKey == targetKey or textKey:find(targetKey, 1, true) ~= nil
end

function isTargetMapVisibleInVoteUi(mapName)
    local targetKey = normalizeLookupText(mapName)
    if targetKey == "" then
        return false
    end
    if isTargetMapInVoteBoards(mapName) then
        return true
    end
    if hasLobbyVoteBoardMaps() then
        return false
    end
    if ZephyrLowCompatExecutor then
        return false
    end

    local now = tick()
    local scanInterval = ZephyrLowCompatExecutor and 3 or 0.75
    if targetMapGuiScanKey == targetKey and now - targetMapGuiScanAt < scanInterval then
        return targetMapGuiScanValue == true
    end
    targetMapGuiScanAt = now
    targetMapGuiScanKey = targetKey
    targetMapGuiScanValue = false

    startReadyGuiWatcher()
    for obj in pairs(readyCandidateObjects) do
        if obj and obj.Parent and not isZephyrGuiObject(obj) and isGuiObjectEffectivelyVisible(obj) then
            if textContainsVoteMap(getReadyOwnText(obj), targetKey) then
                targetMapGuiScanValue = true
                return true
            end
        else
            readyCandidateObjects[obj] = nil
        end
    end

    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if not gui then
        return false
    end

    local scanned = 0
    for _, obj in ipairs(gui:GetDescendants()) do
        if
            not isZephyrGuiObject(obj)
            and obj:IsA("GuiObject")
            and isGuiObjectEffectivelyVisible(obj)
            and (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox"))
        then
            local text = ""
            pcall(function()
                text = tostring(obj.Name or "") .. " " .. tostring(obj.Text or "")
            end)
            if textContainsVoteMap(text, targetKey) then
                targetMapGuiScanValue = true
                return true
            end
            scanned += 1
            if scanned >= (ZephyrLowCompatExecutor and 120 or AUTO_REJOIN_MAP_TEXT_SCAN_LIMIT) then
                break
            end
        end
    end

    return false
end

function waitForTargetMapVote(serial, mapName, modeInfo, timeout)
    if isModeLockedVote(modeInfo) then
        return true, "mode_locked"
    end
    if isTargetMapInVoteBoards(mapName) then
        return true, "board"
    end
    if hasLobbyVoteBoardMaps() then
        return false, "missing"
    end

    local deadline = tick() + math.max(tonumber(timeout) or AUTO_REJOIN_MAP_SCAN_SETTLE_TIME, 0.25)
    local sawVoteScreen = false
    repeat
        if serial ~= autoRejoinStratSerial then
            return false, "interrupted"
        end

        if isTargetMapInVoteBoards(mapName) then
            return true, "board"
        end

        if hasLobbyVoteBoardMaps() then
            return false, "missing"
        end

        if isMapVotingScreenVisible() then
            sawVoteScreen = true
        end

        task.wait(0.25)
    until tick() >= deadline

    return false, sawVoteScreen and "missing" or "not_ready"
end

function isRoundHudVisible()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local topDisplay = gui and gui:FindFirstChild("ReactGameTopGameDisplay")
    if not topDisplay then
        return false
    end
    if topDisplay:IsA("ScreenGui") and topDisplay.Enabled == false then
        return false
    end

    local frame = topDisplay:FindFirstChild("Frame")
    if frame and frame:IsA("GuiObject") and isGuiObjectEffectivelyVisible(frame) then
        local text = getGuiObjectText(frame)
        if text:find("BASE HEALTH", 1, true) or text:find("TIME LEFT", 1, true) or text:match("%f[%a]WAVE%f[%A]") then
            return true
        end
    end

    local waveLabel = findWaveValueLabel()
    if waveLabel and waveLabel:IsA("GuiObject") and isGuiObjectEffectivelyVisible(waveLabel) then
        return true
    end

    for _, child in ipairs(topDisplay:GetDescendants()) do
        if child:IsA("GuiObject") and isGuiObjectEffectivelyVisible(child) then
            local text = ""
            if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
                pcall(function()
                    text = tostring(child.Text or ""):upper()
                end)
            end
            if
                text:find("BASE HEALTH", 1, true)
                or text:find("TIME LEFT", 1, true)
                or text:match("%f[%a]WAVE%f[%A]")
            then
                return true
            end
        end
    end

    return false
end

function getLoadedMatchWave()
    local wave = getCurrentWave()
    if wave and wave >= ROUND_RESET_WAVE and isRoundHudVisible() then
        return wave
    end
    return nil
end

function isLoadedMatchContext()
    local wave = getLoadedMatchWave()
    if wave ~= nil then
        return true, wave
    end

    local currentHealth, maximumHealth = getBaseHealth()
    local stateWave = getCurrentWave()
    if
        getWorkspaceType() == "Game"
        and currentHealth ~= nil
        and maximumHealth ~= nil
        and maximumHealth > 0
        and stateWave ~= nil
        and stateWave >= ROUND_RESET_WAVE
    then
        repairTdsInterfaceScreens()
        return true, stateWave
    end

    if isReactOverridesReadyPromptVisible() or isReadyVoteContextVisible() then
        return true, getCurrentWave()
    end

    if isRoundHudVisible() then
        return true, getCurrentWave()
    end

    return false, nil
end

function clickVisibleReadyButton(button)
    local obj = button or findVisibleReadyButton()
    if not obj then
        return false
    end
    local clicked = false
    pcall(function()
        local fireSignal = zephyrGlobalFunction("firesignal")
        if fireSignal then
            fireSignal(obj.MouseButton1Click)
            fireSignal(obj.Activated)
            clicked = true
        end
    end)
    pcall(function()
        local getConnections = zephyrGlobalFunction("getconnections")
        if getConnections then
            for _, conn in ipairs(getConnections(obj.MouseButton1Click)) do
                if type(conn.Fire) == "function" then
                    conn:Fire()
                end
                if type(conn.Function) == "function" then
                    conn.Function()
                end
                clicked = true
            end
        end
    end)
    if not ZephyrLowCompatExecutor then
        pcall(function()
            local VirtualInputManager = game:GetService("VirtualInputManager")
            local pos = obj.AbsolutePosition + (obj.AbsoluteSize / 2)
            VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
            VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
            clicked = true
        end)
    end
    return clicked
end

function isReadyPromptVisible()
    return isReactOverridesReadyPromptVisible() or findVisibleReadyButton() ~= nil or isReadyVoteContextVisible()
end

function readyStartWave(force)
    if lobbyVotePreparing and not force then
        return false
    end
    local readyOk = false
    if force then
        pcall(function()
            readyOk = select(1, fireRemoteEvent("LobbyVoting", "Ready")) == true or readyOk
        end)
        pcall(function()
            readyOk = select(1, fireRemoteEvent("LobbyVoting", "Ready", true)) == true or readyOk
        end)
        pcall(function()
            readyOk = select(1, invokeRemoteFunction("LobbyVoting", "Ready")) == true or readyOk
        end)
        pcall(function()
            readyOk = select(1, invokeRemoteFunction("LobbyVoting", "Ready", true)) == true or readyOk
        end)
        pcall(function()
            readyOk = select(1, invokeNewNetwork("Elevators", "function", "SetReady", true)) == true or readyOk
        end)
        pcall(function()
            readyOk = select(1, invokeNewNetwork("Elevators", "event", "SetReady", true)) == true or readyOk
        end)
        pcall(function()
            readyOk = select(1, invokeNewNetwork("Ready", "event", "Ready")) == true or readyOk
        end)
        pcall(function()
            readyOk = select(1, invokeNewNetwork("LobbyVoting", "event", "Ready")) == true or readyOk
        end)
        return readyOk
    end
    local readyPromptVisible = isReactOverridesReadyPromptVisible()
    local readyButton = findVisibleReadyButton()
    local readyContextVisible = isReadyVoteContextVisible() or readyButton ~= nil
    if not force and not readyPromptVisible and not readyButton and not readyContextVisible then
        return false
    end
    if readyPromptVisible then
        pcall(function()
            readyOk = select(1, voteSkip()) == true or readyOk
        end)
    end
    if readyButton then
        readyOk = clickVisibleReadyButton(readyButton) == true or readyOk
    end
    if not force and readyContextVisible and not readyOk then
        pcall(function()
            readyOk = select(1, fireRemoteEvent("LobbyVoting", "Ready")) == true or readyOk
        end)
        pcall(function()
            readyOk = select(1, invokeRemoteFunction("LobbyVoting", "Ready")) == true or readyOk
        end)
    end
    if not force then
        return readyOk
    end
    return readyOk
end

runLobbyAutoRejoinVote = nil

function startAutoRejoinMatchAndReplay(reason)
    if not isAutoRejoinEnabled() then
        return false
    end
    if not hasReplayableSavedStrat(tdsSettings.lastStrat) then
        notify("Run a strat once before auto rejoin can replay it")
        return false
    end
    autoRejoinStratSerial += 1
    autoRerunSerial += 1
    local serial = autoRejoinStratSerial
    local fromRewards = reason == "rewards"
    stopMacroPlayback()
    task.spawn(function()
        task.wait(0.35)
        local retryStart = tick()
        local attempts = 0
        local startRetryInterval = ZephyrLowCompatExecutor and 7.5 or AUTO_REJOIN_START_RETRY_INTERVAL
        while tick() - retryStart < AUTO_REJOIN_START_RETRY_TIMEOUT do
            if serial ~= autoRejoinStratSerial or not isAutoRejoinEnabled() then
                return
            end
            attempts += 1
            local startOk, startResult = startConfiguredAutoRejoinMatch(true)
            if not startOk then
                warn("[Zephyr] Auto rejoin v2:start failed:", tostring(startResult))
            elseif fromRewards and (attempts == 1 or attempts % 5 == 0) then
                notify("Auto rejoin start sent (" .. tostring(attempts) .. ")")
            end
            local waitStart = tick()
            local lastStartWaveReadyAt = 0
            while tick() - waitStart < startRetryInterval do
                local currentWave = getLoadedMatchWave() or getCurrentWave()
                if currentWave and currentWave >= MACRO_START_WAVE then
                    autoVoteSkipIfEnabled()
                    task.wait(0.25)
                    if serial == autoRejoinStratSerial and isAutoRejoinEnabled() then
                        replaySavedLastStrat("restart")
                    end
                    return
                end
                if tick() - lastStartWaveReadyAt >= START_WAVE_READY_INTERVAL then
                    lastStartWaveReadyAt = tick()
                    readyStartWave(true)
                end
                task.wait(AUTO_RESPAWN_POLL)
            end
        end
        notify("Auto rejoin start timed out")
    end)
    return true
end

lastAutoRejoinModifierWarnAt = 0
function warnAutoRejoinModifierOnce(message)
    if tick() - lastAutoRejoinModifierWarnAt < 6 then
        return
    end
    lastAutoRejoinModifierWarnAt = tick()
    warn("[Zephyr] Auto rejoin modifier vote skipped:", tostring(message))
end

function voteModifiersForLobbyContext(timeout)
    if tdsSettings.modifierVoteEnabled ~= true and modifierVoteEnabled ~= true then
        return true
    end
    if type(voteConfiguredModifiers) ~= "function" then
        warnAutoRejoinModifierOnce("modifier voting not ready")
        return true, "Modifier voting not ready"
    end

    -- A failed modifier vote shouldn't stop the match from starting.
    if type(startModifierVoteBurst) == "function" then
        pcall(startModifierVoteBurst)
    end

    local done = false
    local voteOk = false
    local voteResult = "Modifier vote queued"
    task.spawn(function()
        local protectedOk, resultOk, result = pcall(voteConfiguredModifiers, true)
        if protectedOk then
            voteOk = resultOk == true or tostring(result or "") == "No modifiers selected"
            voteResult = result
        else
            voteOk = false
            voteResult = resultOk
        end
        done = true
    end)

    local maxWait = math.clamp(tonumber(timeout) or 0.2, 0.05, 0.25)
    local deadline = tick() + maxWait
    while not done and tick() < deadline do
        task.wait(0.03)
    end

    if done and not voteOk and tostring(voteResult or "") ~= "No modifiers selected" then
        warnAutoRejoinModifierOnce(voteResult)
    end
    return true, done and voteResult or "Modifier vote queued"
end

runLobbyAutoRejoinVote = function(allowAnyPlace, preferSavedTarget)
    local preferSaved = preferSavedTarget ~= false
    local mapName, _, _, savedTarget = getAutoRejoinTarget(preferSaved)
    local replaySavedOnWave = preferSaved and type(savedTarget) == "table" and hasReplayableSavedStrat(savedTarget)
    if mapName == "" then
        notify("Auto rejoin map is empty")
        return false
    end
    if preferSaved and hasReplayableSavedStrat(tdsSettings.lastStrat) and not replaySavedOnWave then
        notify("Last strat is missing map info. Run it once again to refresh replay.")
    end
    if not allowAnyPlace and not isAutoRejoinLobbyPlace() then
        return false
    end

    autoRejoinStratSerial += 1
    local serial = autoRejoinStratSerial
    task.spawn(function()
        local retryStart = tick()
        local attempts = 0

        while serial == autoRejoinStratSerial and tick() - retryStart < LOBBY_READY_RETRY_TIMEOUT do
            attempts += 1
            if attempts == 1 or attempts % 5 == 0 then
                notify("Lobby ready attempt " .. tostring(attempts) .. ": " .. mapName)
            end

            beginLobbyVotePreparation(serial)
            local overrideOk, overrideResult = invokeRemoteFunction("LobbyVoting", "Override", mapName)
            if not overrideOk then
                warn("[Zephyr] LobbyVoting Override failed:", tostring(overrideResult))
            end
            task.wait(0.4)

            local voteOk, voteResult = fireRemoteEvent("LobbyVoting", "Vote", mapName, getLobbyVotePosition())
            if not voteOk then
                warn("[Zephyr] LobbyVoting Vote failed:", tostring(voteResult))
            end
            task.wait(0.2)

            if serial ~= autoRejoinStratSerial then
                endLobbyVotePreparation(serial)
                return
            end
            local modifiersOk, modifiersResult = voteModifiersForLobbyContext(4)
            task.wait(0.15)

            if serial ~= autoRejoinStratSerial then
                endLobbyVotePreparation(serial)
                return
            end
            if not modifiersOk then
                endLobbyVotePreparation(serial)
                warn("[Zephyr] Auto rejoin waiting for modifiers:", tostring(modifiersResult))
                task.wait(0.35)
                continue
            end
            local readyOk, readyResult = fireRemoteEvent("LobbyVoting", "Ready")
            if not readyOk then
                warn("[Zephyr] LobbyVoting Ready failed:", tostring(readyResult))
            end
            endLobbyVotePreparation(serial)

            local waitStart = tick()
            local lastStartWaveReadyAt = 0
            while serial == autoRejoinStratSerial and tick() - waitStart < LOBBY_READY_RETRY_INTERVAL do
                if tick() - lastStartWaveReadyAt >= START_WAVE_READY_INTERVAL then
                    lastStartWaveReadyAt = tick()
                    readyStartWave(true)
                end
                local currentWave = getLoadedMatchWave() or getCurrentWave()
                if currentWave and currentWave >= MACRO_START_WAVE then
                    autoVoteSkipIfEnabled()
                    if replaySavedOnWave then
                        replaySavedLastStrat("lobby")
                    end
                    return
                end
                task.wait(WAVE_DETECT_POLL)
            end
        end

        if serial == autoRejoinStratSerial then
            endLobbyVotePreparation(serial)
            notify("Lobby ready timed out")
        end
    end)
    return true
end

function runSelectedStratLobbyVote(descriptor, onWaveOne, onFail)
    if game.PlaceId ~= VIP_LOBBY_VOTING_PLACE_ID then
        return false
    end
    if type(descriptor) ~= "table" then
        return false
    end

    local mapName = normalizeAutoRejoinMap(descriptor.map)
    if mapName == "" then
        return false
    end
    local function isSelectedStratMatchLoaded()
        local matchLoaded, matchWave = isLoadedMatchContext()
        if not matchLoaded or isMapVotingScreenVisible() then
            return false, matchWave
        end
        if isRoundHudVisible() or getWorkspaceType() == "Game" then
            return true, matchWave
        end
        return false, matchWave
    end

    local alreadyInMatch = false
    local loadedWave = nil
    pcall(function()
        alreadyInMatch, loadedWave = isSelectedStratMatchLoaded()
    end)
    if alreadyInMatch then
        task.spawn(function()
            readyStartWave(true)
            autoVoteSkipIfEnabled()
            if type(onWaveOne) == "function" then
                onWaveOne()
            end
        end)
        notify(
            "Match detected; starting strat watcher"
                .. (loadedWave and (" (wave " .. tostring(loadedWave) .. ")") or "")
        )
        return true
    end

    autoRejoinStratSerial += 1
    local serial = autoRejoinStratSerial
    task.spawn(function()
        local retryStart = tick()
        local attempts = 0
        while serial == autoRejoinStratSerial and tick() - retryStart < LOBBY_READY_RETRY_TIMEOUT do
            local matchLoaded, matchWave = isSelectedStratMatchLoaded()
            if matchLoaded then
                readyStartWave(true)
                autoVoteSkipIfEnabled()
                if type(onWaveOne) == "function" then
                    onWaveOne()
                end
                notify(
                    "Match detected; starting strat watcher"
                        .. (matchWave and (" (wave " .. tostring(matchWave) .. ")") or "")
                )
                return
            end

            attempts += 1
            if attempts == 1 or attempts % 5 == 0 then
                notify("Voting selected strat map: " .. mapName)
            end

            beginLobbyVotePreparation(serial)
            local overrideOk, overrideResult = invokeRemoteFunction("LobbyVoting", "Override", mapName)
            if not overrideOk then
                warn("[Zephyr] Selected strat Override failed:", tostring(overrideResult))
            end
            task.wait(0.4)

            local voteOk, voteResult = fireRemoteEvent("LobbyVoting", "Vote", mapName, getLobbyVotePosition())
            if not voteOk then
                warn("[Zephyr] Selected strat Vote failed:", tostring(voteResult))
            end
            task.wait(0.2)

            if serial ~= autoRejoinStratSerial then
                endLobbyVotePreparation(serial)
                if type(onFail) == "function" then
                    onFail("Selected strat vote was interrupted")
                end
                return
            end
            local modifiersOk, modifiersResult = voteModifiersForLobbyContext(4)
            task.wait(0.15)

            if serial ~= autoRejoinStratSerial then
                endLobbyVotePreparation(serial)
                if type(onFail) == "function" then
                    onFail("Selected strat vote was interrupted")
                end
                return
            end
            if not modifiersOk then
                endLobbyVotePreparation(serial)
                warn("[Zephyr] Selected strat waiting for modifiers:", tostring(modifiersResult))
                task.wait(0.35)
                continue
            end
            local readyOk, readyResult = fireRemoteEvent("LobbyVoting", "Ready")
            if not readyOk then
                warn("[Zephyr] Selected strat Ready failed:", tostring(readyResult))
            end
            endLobbyVotePreparation(serial)

            local waitStart = tick()
            local lastReadyAt = 0
            while serial == autoRejoinStratSerial and tick() - waitStart < LOBBY_READY_RETRY_INTERVAL do
                if tick() - lastReadyAt >= START_WAVE_READY_INTERVAL then
                    lastReadyAt = tick()
                    readyStartWave(true)
                end
                local matchLoaded, matchWave = isSelectedStratMatchLoaded()
                if matchLoaded then
                    autoVoteSkipIfEnabled()
                    if type(onWaveOne) == "function" then
                        onWaveOne()
                    end
                    notify(
                        "Match detected; starting strat watcher"
                            .. (matchWave and (" (wave " .. tostring(matchWave) .. ")") or "")
                    )
                    return
                end
                local currentWave = getLoadedMatchWave() or getCurrentWave()
                if currentWave and currentWave >= MACRO_START_WAVE then
                    autoVoteSkipIfEnabled()
                    if type(onWaveOne) == "function" then
                        onWaveOne()
                    end
                    return
                end
                task.wait(WAVE_DETECT_POLL)
            end
        end

        if serial == autoRejoinStratSerial and type(onFail) == "function" then
            endLobbyVotePreparation(serial)
            onFail("Selected strat vote timed out")
        end
    end)
    return true
end

scheduleAutoRejoinAfterEnd = function(reason)
    if not isAutoRejoinEnabled() then
        return
    end
    if autoRejoinEndThread then
        return
    end
    local endReason = reason
    autoRejoinEndThread = task.spawn(function()
        startAutoRejoinMatchAndReplay(endReason)
        local holdStart = tick()
        while
            isAutoRejoinEnabled()
            and ((endReason == "rewards" and isNewRewardsGuiEnabled()) or (endReason ~= "rewards" and isBaseDown()))
            and tick() - holdStart < 20
        do
            task.wait(AUTO_RESPAWN_POLL)
        end
        autoRejoinEndThread = nil
    end)
end

function startLobbyAutoRejoinOnLaunch()
    if autoRejoinLaunchAttempted then
        return false
    end
    if not isAutoRejoinEnabled() then
        return false
    end
    if not isAutoRejoinLobbyPlace() then
        return false
    end
    local config = getAutoRejoinConfig()
    if trimText(config.map or "") == "" and not hasReplayableSavedStrat(tdsSettings.lastStrat) then
        return false
    end
    autoRejoinLaunchAttempted = true
    return runLobbyAutoRejoinVote(false, true)
end

-- Wave skip
function readReplicatedValue(rep, key, fallback)
    if not rep then
        return fallback
    end
    local ok, value = pcall(function()
        return rep:GetAttribute(key)
    end)
    if ok and value ~= nil then
        return value
    end
    local child = rep:FindFirstChild(key)
    if child then
        ok, value = pcall(function()
            return child.Value
        end)
        if ok and value ~= nil then
            return value
        end
    end
    ok, value = pcall(function()
        if type(rep.Get) == "function" then
            return rep:Get(key)
        end
    end)
    if ok and value ~= nil then
        return value
    end
    return fallback
end

function findVoteManager()
    local reps = ReplicatedStorage:FindFirstChild("StateReplicators")
    if reps then
        for _, rep in ipairs(reps:GetChildren()) do
            if rep.Name == "VoteManager" then
                return rep
            end
        end
    end
    local ok, tagged = pcall(function()
        return CollectionService:GetTagged("VoteManager")
    end)
    if ok and type(tagged) == "table" then
        return tagged[1]
    end
    return nil
end

function hasLocalVote(yesVoted)
    if type(yesVoted) == "table" then
        for _, value in pairs(yesVoted) do
            if value == LocalPlayer.UserId or tostring(value) == tostring(LocalPlayer.UserId) then
                return true
            end
        end
    elseif type(yesVoted) == "string" then
        return yesVoted:find(tostring(LocalPlayer.UserId), 1, true) ~= nil
    end
    return false
end

function isSkipVoteOpen()
    local frameVisible = isReactOverridesVoteFrameVisible()
    local frameText = frameVisible and getReactOverridesVoteFrameText() or ""
    local guiLooksLikeSkip = frameVisible
        and (frameText:find("SKIP WAVE", 1, true) ~= nil or frameText:find("SKIP?", 1, true) ~= nil)
    local rep = findVoteManager()
    if rep then
        local enabled = readReplicatedValue(rep, "Enabled", false) == true
        local title = tostring(readReplicatedValue(rep, "Title", "")):lower()
        if enabled and title:find("skip", 1, true) and not title:find("restart", 1, true) then
            if hasLocalVote(readReplicatedValue(rep, "YesVoted", {})) then
                return false
            end
            local maxVotes = tonumber(readReplicatedValue(rep, "MaxVotes", 0)) or 0
            local votes = tonumber(readReplicatedValue(rep, "VoteCount", 0)) or 0
            return guiLooksLikeSkip == true and (maxVotes <= 0 or votes < maxVotes)
        end
    end

    return guiLooksLikeSkip == true
end

function startAutoskip()
    if autoskipConnection then
        pcall(function()
            task.cancel(autoskipConnection)
        end)
    end
    autoskipEnabled = true
    local skipBusy = false
    local lastSkipAt = 0
    local function queueSkip()
        if skipBusy then
            return
        end
        if tick() - lastSkipAt < 0.12 then
            return
        end
        skipBusy = true
        lastSkipAt = tick()
        task.spawn(function()
            pcall(voteSkip)
            skipBusy = false
        end)
    end
    autoskipConnection = task.spawn(function()
        while autoskipEnabled do
            if isSkipVoteOpen() then
                queueSkip()
            end
            task.wait(0.05)
        end
    end)
end

function stopAutoskip()
    autoskipEnabled = false
    if autoskipConnection then
        pcall(function()
            task.cancel(autoskipConnection)
        end)
        autoskipConnection = nil
    end
end

-- ESP
function startESP()
    if espCleanup then
        local cleanup = espCleanup
        espCleanup = nil
        pcall(cleanup)
    end

    espEnabled = true
    local RS = ReplicatedStorage
    local StateReps = RS:FindFirstChild("StateReplicators")
    local NPC_FOLDER = workspace:FindFirstChild("NPCs")

    if not StateReps or not NPC_FOLDER then
        espEnabled = false
        return false
    end

    local npcConns = {}

    local function findRep(npcModel)
        local nm = npcModel.Name
        for _, r in ipairs(StateReps:GetChildren()) do
            if r.Name == "NPCReplicator" then
                local mn = r:GetAttribute("ModelName")
                if mn then
                    if nm == mn or string.match(nm, mn) or string.match(mn, nm) then
                        return r
                    end
                    local base = string.gsub(string.gsub(nm, "Enemy$", ""), "^Enemy", "")
                    if base == mn then
                        return r
                    end
                end
            end
        end
        return nil
    end

    local function bestRep(npcModel)
        local r = findRep(npcModel)
        if r and not r:GetAttribute("_Claimed") then
            r:SetAttribute("_Claimed", true)
            return r
        end
        local root = npcModel.PrimaryPart
            or npcModel:FindFirstChild("HumanoidRootPart")
            or npcModel:FindFirstChildWhichIsA("BasePart")
        if root then
            local pos = root.Position
            local best, bestDist = nil, math.huge
            for _, rep in ipairs(StateReps:GetChildren()) do
                if rep.Name == "NPCReplicator" and not rep:GetAttribute("_Claimed") then
                    local rx = rep:GetAttribute("PositionX") or rep:GetAttribute("X")
                    local ry = rep:GetAttribute("PositionY") or rep:GetAttribute("Y")
                    local rz = rep:GetAttribute("PositionZ") or rep:GetAttribute("Z")
                    if rx and ry and rz then
                        local d = (pos - Vector3.new(rx, ry, rz)).Magnitude
                        if d < bestDist and d < 10 then
                            bestDist = d
                            best = rep
                        end
                    end
                end
            end
            if best then
                best:SetAttribute("_Claimed", true)
                return best
            end
        end
        for _, rep in ipairs(StateReps:GetChildren()) do
            if rep.Name == "NPCReplicator" and not rep:GetAttribute("_Claimed") then
                local mn = rep:GetAttribute("ModelName")
                if mn and string.match(npcModel.Name, mn) then
                    rep:SetAttribute("_Claimed", true)
                    return rep
                end
            end
        end
        return nil
    end

    local function setupNPC(npc)
        if not espEnabled or not npc:IsA("Model") or npcConns[npc] then
            return
        end
        local root = npc.PrimaryPart or npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChildWhichIsA("BasePart")
        if not root then
            return
        end
        local rep = bestRep(npc)
        if not rep then
            return
        end
        local maxHP = rep:GetAttribute("MaxHealth") or rep:GetAttribute("Health") or 100
        local mName = rep:GetAttribute("ModelName") or npc.Name
        local hl = Instance.new("Highlight")
        hl.Name = "ESPCham"
        hl.Adornee = npc
        hl.FillColor = Color3.fromRGB(255, 0, 0)
        hl.FillTransparency = 0.5
        hl.OutlineColor = Color3.fromRGB(255, 0, 0)
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = npc
        local nBB = Instance.new("BillboardGui")
        nBB.Name = "NameBB"
        nBB.Adornee = root
        nBB.Size = UDim2.new(0, 200, 0, 50)
        nBB.StudsOffset = Vector3.new(0, 5, 0)
        nBB.AlwaysOnTop = true
        nBB.Parent = root
        local nL = Instance.new("TextLabel")
        nL.Size = UDim2.new(1, 0, 1, 0)
        nL.BackgroundTransparency = 1
        nL.TextColor3 = Color3.fromRGB(255, 255, 255)
        nL.TextStrokeTransparency = 0
        nL.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        nL.Font = Enum.Font.SourceSansBold
        nL.TextSize = 18
        nL.Text = mName
        nL.Parent = nBB
        local hBB = Instance.new("BillboardGui")
        hBB.Name = "HPBB"
        hBB.Adornee = root
        hBB.Size = UDim2.new(0, 200, 0, 50)
        hBB.StudsOffset = Vector3.new(0, 4, 0)
        hBB.AlwaysOnTop = true
        hBB.Parent = root
        local hL = Instance.new("TextLabel")
        hL.Size = UDim2.new(1, 0, 1, 0)
        hL.BackgroundTransparency = 1
        hL.TextStrokeTransparency = 0
        hL.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        hL.Font = Enum.Font.SourceSansBold
        hL.TextSize = 16
        hL.Parent = hBB
        local function upd()
            local hp = rep:GetAttribute("Health") or 0
            local mhp = rep:GetAttribute("MaxHealth") or maxHP
            local tags = {}
            for _, attr in ipairs({ "Hidden", "Flying", "Lead", "Boss", "Shield" }) do
                if rep:GetAttribute(attr) then
                    table.insert(tags, attr)
                end
            end
            local defense = tonumber(rep:GetAttribute("Defense") or rep:GetAttribute("Armor"))
            if defense and defense > 0 then
                table.insert(tags, tostring(math.floor(defense)) .. "% DEF")
            end
            nL.Text = mName .. (#tags > 0 and (" [" .. table.concat(tags, ", ") .. "]") or "")
            hL.Text = string.format("%d/%d HP", math.floor(hp), math.floor(mhp))
            local pct = mhp > 0 and (hp / mhp) or 0
            hL.TextColor3 = pct > 0.5 and Color3.fromRGB(0, 255, 0)
                or pct > 0.25 and Color3.fromRGB(255, 255, 0)
                or Color3.fromRGB(255, 0, 0)
            hBB.Enabled = hp > 0
            nBB.Enabled = hp > 0
        end
        upd()
        npcConns[npc] = { rep = rep, hBB = hBB, nBB = nBB }
        local hConn = rep:GetAttributeChangedSignal("Health"):Connect(upd)
        local function clean()
            if hBB and hBB.Parent then
                hBB:Destroy()
            end
            if nBB and nBB.Parent then
                nBB:Destroy()
            end
            if hConn then
                hConn:Disconnect()
            end
            if rep then
                rep:SetAttribute("_Claimed", nil)
            end
            npcConns[npc] = nil
            local c = npc:FindFirstChild("ESPCham")
            if c then
                c:Destroy()
            end
        end
        npc.AncestryChanged:Connect(function()
            if not npc.Parent then
                clean()
            end
        end)
        rep.AncestryChanged:Connect(function()
            if not rep.Parent then
                clean()
            end
        end)
    end

    for _, n in ipairs(NPC_FOLDER:GetChildren()) do
        setupNPC(n)
    end
    local espSyncQueued = false
    local function queueEspSync()
        if espSyncQueued then
            return
        end
        espSyncQueued = true
        task.delay(0.25, function()
            espSyncQueued = false
            if not espEnabled then
                return
            end
            for _, n in ipairs(NPC_FOLDER:GetChildren()) do
                if not npcConns[n] then
                    setupNPC(n)
                end
            end
        end)
    end
    local c1 = NPC_FOLDER.ChildAdded:Connect(function(n)
        task.delay(0.25, function()
            if espEnabled then
                setupNPC(n)
            end
        end)
    end)
    local c2 = StateReps.ChildAdded:Connect(function(ch)
        if ch.Name == "NPCReplicator" then
            queueEspSync()
        end
    end)
    espCleanup = function()
        espEnabled = false
        if c1 then
            c1:Disconnect()
        end
        if c2 then
            c2:Disconnect()
        end
        for npc, d in pairs(npcConns) do
            if d.hBB and d.hBB.Parent then
                d.hBB:Destroy()
            end
            if d.nBB and d.nBB.Parent then
                d.nBB:Destroy()
            end
            if d.rep then
                d.rep:SetAttribute("_Claimed", nil)
            end
            local c = npc:FindFirstChild("ESPCham")
            if c then
                c:Destroy()
            end
        end
        clearTable(npcConns)
    end

    return true
end

function stopESP()
    if espCleanup then
        espCleanup()
        espCleanup = nil
    end
end

function setTowerExpCacheLevel(name, wantedLevel)
    name = trimText(name)
    wantedLevel = math.max(1, math.floor(tonumber(wantedLevel) or 5))
    if name == "" then
        return false
    end

    local neededExp = 1000000000

    local cacheModule = safeRequirePath("Client.Modules.Cache", ReplicatedStorage, "Client", "Modules", "Cache")
    if type(cacheModule) ~= "function" then
        return false
    end
    local cache = cacheModule("TowerExp")
    if not cache then
        return false
    end
    local current = {}
    pcall(function()
        local value = cache:GetValue()
        if type(value) == "table" then
            current = cloneSettingsValue(value)
        end
    end)
    if tonumber(current[name]) and tonumber(current[name]) >= neededExp then
        return true
    end
    current[name] = neededExp
    local ok = pcall(function()
        cache:Update(current)
    end)
    return ok == true
end

function equipTower(name)
    name = trimText(name)
    setTowerExpCacheLevel(name, 5)
    local ok, result = invokeRemoteFunction("Inventory", "Equip", "tower", name)
    if ok and result ~= false then
        setTowerExpCacheLevel(name, 5)
    end
    return ok and result ~= false, result
end

function unequipTower(name)
    local ok, result = invokeRemoteFunction("Inventory", "Unequip", "tower", name)
    return ok and result ~= false, result
end

function normalizeLoadoutList(value)
    local raw = type(value) == "table" and value or splitList(value)
    local out, seen = {}, {}
    for _, tower in ipairs(raw) do
        local clean = trimText(tower)
        local key = clean:lower()
        if clean ~= "" and not seen[key] then
            seen[key] = true
            table.insert(out, clean)
        end
    end
    return out
end

function towerNameKey(name)
    return trimText(name):lower()
end

function addEquippedTowerName(out, seen, value)
    local towerName = nil
    if type(value) == "string" then
        towerName = value
    elseif type(value) == "table" then
        towerName = value.Name or value.name or value.TowerName or value.towerName or value.Tower or value.tower
    end
    towerName = trimText(towerName)
    if towerName == "" or towerName == "None" then
        return
    end
    local key = towerNameKey(towerName)
    if seen[key] then
        return
    end
    seen[key] = true
    table.insert(out, towerName)
end

function addEquippedTowerValue(out, seen, value)
    if type(value) == "string" then
        local decoded = nil
        local json = value:match("%[.*%]") or value:match("{.*}")
        if json then
            pcall(function()
                decoded = HttpService:JSONDecode(json)
            end)
        end
        if type(decoded) == "table" then
            addEquippedTowerValue(out, seen, decoded)
        else
            addEquippedTowerName(out, seen, value)
        end
        return
    end
    if type(value) ~= "table" then
        return
    end
    for key, item in pairs(value) do
        addEquippedTowerName(out, seen, item)
        if item == true and type(key) == "string" then
            addEquippedTowerName(out, seen, key)
        end
    end
end

function readEquippedTowerCache()
    local cacheModule = safeRequirePath("Client.Modules.Cache", ReplicatedStorage, "Client", "Modules", "Cache")
    if type(cacheModule) ~= "function" then
        return nil
    end
    local value = nil
    pcall(function()
        local cache = cacheModule("Equipped.Troops")
        value = cache and cache:GetValue()
    end)
    return value
end

function readLocalPlayerReplicatorValue(key)
    local reps = ReplicatedStorage:FindFirstChild("StateReplicators")
    if not reps then
        return nil
    end
    for _, rep in ipairs(reps:GetChildren()) do
        if rep.Name == "PlayerReplicator" then
            local userId = rep:GetAttribute("UserId")
            if tostring(userId) == tostring(LocalPlayer.UserId) then
                local value = rep:GetAttribute(key)
                if value ~= nil then
                    return value
                end
                local child = rep:FindFirstChild(key)
                if child then
                    local ok, childValue = pcall(function()
                        return child.Value
                    end)
                    if ok and childValue ~= nil then
                        return childValue
                    end
                end
                local ok, value = pcall(function()
                    if type(rep.Get) == "function" then
                        return rep:Get(key)
                    end
                end)
                if ok and value ~= nil then
                    return value
                end
            end
        end
    end
    return nil
end

function getEquippedTowerNames()
    local out, seen = {}, {}
    addEquippedTowerValue(out, seen, readEquippedTowerCache())
    if #out == 0 then
        addEquippedTowerValue(out, seen, readLocalPlayerReplicatorValue("EquippedTowers"))
    end
    return out
end

function getMissingLoadoutTowers(loadout, equipped)
    local equippedSet = {}
    for _, tower in ipairs(equipped or {}) do
        equippedSet[towerNameKey(tower)] = true
    end
    local missing = {}
    for _, tower in ipairs(loadout) do
        if not equippedSet[towerNameKey(tower)] then
            table.insert(missing, tower)
        end
    end
    return missing
end

function countLoadoutTowersEquipped(loadout, equipped)
    local equippedSet = {}
    for _, tower in ipairs(equipped or {}) do
        equippedSet[towerNameKey(tower)] = true
    end
    local count = 0
    for _, tower in ipairs(loadout) do
        if equippedSet[towerNameKey(tower)] then
            count += 1
        end
    end
    return count
end

function applyLoadoutList(value)
    local loadout = normalizeLoadoutList(value)
    if #loadout == 0 then
        return false, "No towers entered"
    end

    local requiredSet = {}
    for _, tower in ipairs(loadout) do
        requiredSet[towerNameKey(tower)] = true
    end
    local equippedNow = getEquippedTowerNames()
    local missing = getMissingLoadoutTowers(loadout, equippedNow)
    if #missing == 0 then
        return true, string.format("Loadout already ready (%d/%d)", #loadout, #loadout)
    end

    local unequipped = 0
    local equipped = 0
    for _, tower in ipairs(missing) do
        local ok = equipTower(tower)
        if ok then
            equipped += 1
        end
        task.wait(0.025)
    end

    task.wait(0.08)
    equippedNow = getEquippedTowerNames()
    missing = getMissingLoadoutTowers(loadout, equippedNow)

    if #missing > 0 and #equippedNow > 0 then
        local removable = {}
        for i = #equippedNow, 1, -1 do
            local tower = equippedNow[i]
            if not requiredSet[towerNameKey(tower)] then
                table.insert(removable, tower)
            end
        end
        for i = 1, math.min(#missing, #removable) do
            if unequipTower(removable[i]) then
                unequipped += 1
            end
            task.wait(0.025)
        end
        if unequipped > 0 then
            task.wait(0.08)
        end
        for _, tower in ipairs(missing) do
            local ok = equipTower(tower)
            if ok then
                equipped += 1
            end
            task.wait(0.025)
        end
    end

    task.wait(0.08)
    local ready = countLoadoutTowersEquipped(loadout, getEquippedTowerNames())
    if ready == #loadout then
        return true, string.format("Loadout ready (%d/%d)", ready, #loadout)
    end
    if equipped > 0 then
        return true, string.format("Loadout updated (%d/%d ready, %d replaced)", ready, #loadout, unequipped)
    end
    return false, string.format("Loadout missing %d/%d towers", #loadout - ready, #loadout)
end

modifierCache = nil
modifierCacheAt = 0
MODIFIER_CACHE_TTL = 60
MODIFIER_VOTE_REMOTE_WAIT = 8
modifierReplicatorFolderCache = nil
modifierReplicatorEntityCache = nil
modifierReplicatorReleaseCache = nil

function getModifierInventorySet()
    if not canSafelyRequireTdsModules() then
        return nil
    end
    local ok, value = pcall(function()
        local cacheModule = safeRequirePath("Client.Modules.Cache", ReplicatedStorage, "Client", "Modules", "Cache")
        local cache = cacheModule and cacheModule("Inventory.Modifiers")
        if cache then
            return cache:GetValue()
        end
    end)
    if not ok or type(value) ~= "table" then
        return nil
    end

    local owned = {}
    local count = 0
    local function addOwned(modifierId)
        if type(modifierId) == "string" and modifierId ~= "" then
            owned[modifierId] = true
            owned[settingsLookupKey(modifierId)] = true
            count += 1
        end
    end

    for modifierKey, modifierId in pairs(value) do
        addOwned(modifierId)
        if modifierId == true then
            addOwned(modifierKey)
        end
        if type(modifierId) == "table" then
            addOwned(modifierId.name or modifierId.Name or modifierId.id or modifierId.Id)
        end
    end

    if count <= 0 then
        return nil
    end
    return owned
end

function readModifierReplicatedValue(rep, key, fallback)
    if not rep then
        return fallback
    end
    if type(rep) == "table" then
        local state = rep.State
        if type(state) == "table" and state[key] ~= nil then
            return state[key]
        end
        if rep[key] ~= nil then
            return rep[key]
        end
    end
    local ok, value = pcall(function()
        if type(rep.Get) == "function" then
            return rep:Get(key)
        end
    end)
    if ok and value ~= nil then
        return value
    end
    if typeof(rep) ~= "Instance" then
        return fallback
    end
    ok, value = pcall(function()
        return rep:GetAttribute(key)
    end)
    if ok and value ~= nil then
        return value
    end
    local child = rep:FindFirstChild(key)
    if child then
        ok, value = pcall(function()
            return child.Value
        end)
        if ok and value ~= nil then
            return value
        end
    end
    return fallback
end

function getTrackedReplicatorFromFolder(folder)
    if not folder then
        return nil
    end
    if modifierReplicatorFolderCache == folder and modifierReplicatorEntityCache and folder.Parent then
        return modifierReplicatorEntityCache
    end
    if not canSafelyRequireTdsModules() then
        return folder
    end
    local tagReplicator =
        safeRequirePath("Client.Modules.TagReplicator", ReplicatedStorage, "Client", "Modules", "TagReplicator")
    if type(tagReplicator) ~= "table" then
        return folder
    end

    local trackedOk, tracked = pcall(function()
        if type(tagReplicator.getTrackedReplicator) == "function" then
            return tagReplicator.getTrackedReplicator(folder)
        end
    end)
    if trackedOk and tracked then
        return tracked
    end

    local acquireOk, entity, release = pcall(function()
        if type(tagReplicator.acquireReplicatorEntityFromFolder) == "function" then
            return tagReplicator.acquireReplicatorEntityFromFolder(folder)
        end
    end)
    if acquireOk and entity then
        if type(modifierReplicatorReleaseCache) == "function" and modifierReplicatorFolderCache ~= folder then
            pcall(modifierReplicatorReleaseCache)
        end
        modifierReplicatorFolderCache = folder
        modifierReplicatorEntityCache = entity
        modifierReplicatorReleaseCache = release
        return entity
    end

    return folder
end

function findModifierVoteReplicator()
    local reps = ReplicatedStorage:FindFirstChild("StateReplicators")
    if reps then
        local folder = reps:FindFirstChild("ModifierManager") or reps:FindFirstChild("ModifierReplicator")
        local rep = getTrackedReplicatorFromFolder(folder)
        if rep then
            return rep
        end
        for _, child in ipairs(reps:GetChildren()) do
            if
                CollectionService:HasTag(child, "ModifierReplicator")
                or CollectionService:HasTag(child, "ModifierManager")
            then
                rep = getTrackedReplicatorFromFolder(child)
                if rep then
                    return rep
                end
            end
        end
    end

    for _, tag in ipairs({ "ModifierReplicator", "ModifierManager" }) do
        local ok, tagged = pcall(function()
            return CollectionService:GetTagged(tag)
        end)
        if ok and type(tagged) == "table" then
            for _, folder in ipairs(tagged) do
                local rep = getTrackedReplicatorFromFolder(folder)
                if rep then
                    return rep
                end
            end
        end
    end

    return nil
end

function getLocalModifierVotes()
    local rep = findModifierVoteReplicator()
    local votes = readModifierReplicatedValue(rep, "Votes", {})
    local current = {}
    if type(votes) == "table" then
        for modifierId, users in pairs(votes) do
            local voted = false
            if type(users) == "table" then
                if users[LocalPlayer.UserId] == true or users[tostring(LocalPlayer.UserId)] == true then
                    voted = true
                else
                    for userId, value in pairs(users) do
                        if tostring(userId) == tostring(LocalPlayer.UserId) and value == true then
                            voted = true
                            break
                        end
                        if tostring(value) == tostring(LocalPlayer.UserId) then
                            voted = true
                            break
                        end
                    end
                end
            elseif tostring(users) == tostring(LocalPlayer.UserId) then
                voted = true
            end
            if voted then
                current[tostring(modifierId)] = true
            end
        end
    end
    return current, readModifierReplicatedValue(rep, "Locked", false) == true, rep ~= nil
end

function countMapKeys(map)
    local count = 0
    if type(map) ~= "table" then
        return count
    end
    for _ in pairs(map) do
        count += 1
    end
    return count
end

function getMissingModifierVotes(desired)
    local current, locked, hasReplicator = getLocalModifierVotes()
    if locked then
        return nil, "Voting is currently locked"
    end
    if not hasReplicator then
        return nil, "Vote sent, but TDS vote state was not readable yet"
    end
    local missing = {}
    for modifierId in pairs(desired or {}) do
        if current[modifierId] ~= true then
            table.insert(missing, modifierId)
        end
    end
    for modifierId in pairs(current) do
        if desired[modifierId] ~= true then
            table.insert(missing, "remove " .. modifierId)
        end
    end
    return missing
end

function waitForModifierVotes(desired, timeout)
    timeout = timeout or 1.5
    local start = tick()
    local lastMissing, lastMessage
    while tick() - start < timeout do
        local missing, message = getMissingModifierVotes(desired)
        if message then
            lastMessage = message
        end
        if missing and #missing == 0 then
            return true, "Voted " .. tostring(countMapKeys(desired)) .. " modifier(s)"
        end
        lastMissing = missing
        task.wait(0.15)
    end
    if lastMessage then
        return false, lastMessage
    end
    if lastMissing and #lastMissing > 0 then
        return false, "Not voted: " .. table.concat(lastMissing, ", ")
    end
    return true, "Vote sent"
end

function getAvailableModifiers(forceRefresh)
    if not forceRefresh and modifierCache and tick() - modifierCacheAt < MODIFIER_CACHE_TTL then
        return modifierCache
    end
    local ownedModifiers = getModifierInventorySet()
    local entries = {}
    for i, entry in ipairs(KNOWN_MODIFIER_ENTRIES) do
        local key = entry.key or settingsLookupKey(entry.id)
        table.insert(entries, {
            id = entry.id,
            display = entry.display or entry.id,
            key = key,
            owned = not ownedModifiers or ownedModifiers[entry.id] or ownedModifiers[key] or false,
            inventoryKnown = ownedModifiers ~= nil,
            source = ownedModifiers and "Inventory" or "Known",
            order = i,
        })
    end
    modifierCache = entries
    modifierCacheAt = tick()
    return entries
end

function resolveSelectedModifiers(forceRefresh)
    local available = getAvailableModifiers(forceRefresh)
    local byKey = {}
    for _, entry in ipairs(available) do
        byKey[entry.key] = entry
        byKey[settingsLookupKey(entry.display)] = entry
        local known = modifierLookupByKey[entry.key]
        for _, alias in ipairs((known and known.aliases) or {}) do
            byKey[settingsLookupKey(alias)] = entry
        end
    end

    local resolved = {}
    local seen = {}
    for _, raw in ipairs(splitList(tdsSettings.modifierVoteText)) do
        local key = settingsLookupKey(raw)
        local entry = byKey[key]
        if entry and not seen[entry.key] then
            seen[entry.key] = true
            table.insert(resolved, entry)
        elseif key ~= "" and not seen[key] then
            seen[key] = true
            table.insert(resolved, {
                id = trimText(raw),
                display = trimText(raw),
                key = key,
                owned = true,
                inventoryKnown = false,
                source = "Saved",
                order = 999,
            })
        end
    end

    return resolved, available, true
end

function invokeModifierBulkVote(payload)
    local function tryRemote(remote)
        if not remote then
            return false, nil
        end
        if remote:IsA("RemoteFunction") then
            return invokeNewNetworkRemote(remote, "function", { payload })
        elseif remote:IsA("RemoteEvent") then
            return invokeNewNetworkRemote(remote, "event", { payload })
        elseif remote:IsA("UnreliableRemoteEvent") then
            return invokeNewNetworkRemote(remote, "unreliable", { payload })
        end
        return false, "unsupported remote " .. tostring(remote.ClassName)
    end

    local firstError = "Vote remote unavailable"
    local network = ReplicatedStorage:FindFirstChild("Network")
        or ReplicatedStorage:WaitForChild("Network", MODIFIER_VOTE_REMOTE_WAIT)
    local channel = network
        and (network:FindFirstChild("Modifiers") or network:WaitForChild("Modifiers", MODIFIER_VOTE_REMOTE_WAIT))
    if channel then
        local direct = channel:FindFirstChild("RF:BulkVoteModifiers") or channel:WaitForChild("RF:BulkVoteModifiers", 1)
        if direct then
            local directOk, directResult = tryRemote(direct)
            if directOk then
                return true, directResult
            end
            firstError = tostring(directResult or firstError)
        end
    end

    local ok, result = invokeNewNetworkWithWait("Modifiers", "function", "BulkVoteModifiers", 1, payload)
    if ok then
        return true, result
    end
    firstError = tostring(result or firstError)
    if not network then
        return false, firstError
    end

    if channel then
        for _, remoteName in ipairs({
            "RF:BulkVoteModifiers",
            "RE:BulkVoteModifiers",
            "URE:BulkVoteModifiers",
            "BulkVoteModifiers",
        }) do
            local remote = channel:FindFirstChild(remoteName)
            if remote then
                local fallbackOk, fallbackResult = tryRemote(remote)
                if fallbackOk then
                    return true, fallbackResult
                end
                firstError = tostring(fallbackResult or firstError)
            end
        end
    end

    for _, remote in ipairs(network:GetDescendants()) do
        if tostring(remote.Name or ""):find("BulkVoteModifiers", 1, true) then
            local fallbackOk, fallbackResult = tryRemote(remote)
            if fallbackOk then
                return true, fallbackResult
            end
            firstError = tostring(fallbackResult or firstError)
        end
    end

    return false, firstError
end

voteConfiguredModifiers = function(skipVerify)
    local modifiers, _, hasAvailable = resolveSelectedModifiers(true)
    if not hasAvailable then
        return false, "Modifier list unavailable"
    end
    local currentVotes, locked, hasVoteState = getLocalModifierVotes()
    if locked then
        return false, "Voting is currently locked"
    end

    local desired = {}
    local payload = {}
    for _, modifier in ipairs(modifiers) do
        desired[modifier.id] = true
        payload[modifier.id] = true
    end
    for modifierId in pairs(currentVotes) do
        if not desired[modifierId] then
            payload[modifierId] = false
        end
    end

    if #modifiers == 0 and next(currentVotes) == nil then
        return true, "No modifiers selected"
    end

    local ok, result = invokeModifierBulkVote(payload)
    if not ok then
        return false, result
    end
    if result == false then
        return false, "Modifier vote rejected"
    end
    if skipVerify == true then
        return true, "Vote sent"
    end

    local verified, verifyResult = waitForModifierVotes(desired, hasVoteState and 2 or 1)
    if verified then
        return true, verifyResult
    end
    if tostring(verifyResult or ""):lower():find("locked", 1, true) then
        return false, verifyResult
    end
    if tostring(verifyResult or ""):find("vote state was not readable", 1, true) then
        return true, "Vote sent"
    end
    return true, "Vote sent"
end

startModifierVoteBurst = function()
    modifierVoteBurstSerial += 1
    local serial = modifierVoteBurstSerial
    modifierVoteEnabled = true
    if modifierVoteBurstThread then
        pcall(function()
            task.cancel(modifierVoteBurstThread)
        end)
        modifierVoteBurstThread = nil
    end
    modifierVoteBurstThread = task.spawn(function()
        local interval = MODIFIER_VOTE_BURST_DURATION / math.max(MODIFIER_VOTE_BURST_ATTEMPTS, 1)
        for attempt = 1, MODIFIER_VOTE_BURST_ATTEMPTS do
            if serial ~= modifierVoteBurstSerial or not modifierVoteEnabled or not runtimeAlive then
                break
            end
            if type(voteConfiguredModifiers) == "function" then
                local ok, result = pcall(voteConfiguredModifiers, true)
                if not ok then
                    warn("[Zephyr] Modifier burst failed:", tostring(result))
                elseif result == "No modifiers selected" then
                    break
                end
            end
            task.wait(interval)
        end
        if serial == modifierVoteBurstSerial then
            modifierVoteBurstThread = nil
        end
    end)
end

function startModifierVote()
    modifierVoteEnabled = true
    startModifierVoteBurst()
end

function stopModifierVote()
    modifierVoteEnabled = false
    modifierVoteBurstSerial += 1
    if modifierVoteBurstThread then
        pcall(function()
            task.cancel(modifierVoteBurstThread)
        end)
        modifierVoteBurstThread = nil
    end
end

task.defer(function()
    if tdsSettings.modifierVoteEnabled == true then
        startModifierVote()
    end
end)

function startAutoReady()
    if autoReadyThread then
        return
    end
    autoReadyEnabled = true
    autoReadyThread = task.spawn(function()
        local lastReadyAt = 0
        while autoReadyEnabled do
            local wave = getCurrentWave()
            if not wave or wave < MACRO_START_WAVE then
                local readyVisible = isReadyPromptVisible()
                if readyVisible and tick() - lastReadyAt >= 0.08 then
                    lastReadyAt = tick()
                    readyStartWave(false)
                end
                if readyVisible then
                    task.wait(0.03)
                else
                    task.wait(0.08)
                end
            else
                task.wait(3)
            end
        end
        autoReadyThread = nil
    end)
end

function stopAutoReady()
    autoReadyEnabled = false
    if autoReadyThread then
        task.cancel(autoReadyThread)
        autoReadyThread = nil
    end
end

STREAMER_ALIAS = "Streamer"
streamerNamePatterns = {}

function escapeLuaPattern(value)
    local escaped = tostring(value or ""):gsub("([^%w])", "%%%1")
    return escaped
end

function getStreamerNames()
    local names, seen = {}, {}
    local function add(name)
        name = tostring(name or "")
        if #name < 3 then
            return
        end
        local key = name:lower()
        if seen[key] then
            return
        end
        seen[key] = true
        table.insert(names, name)
    end
    add(LocalPlayer.Name)
    add(LocalPlayer.DisplayName)
    return names
end

function refreshStreamerNamePatterns()
    clearTable(streamerNamePatterns)
    for _, name in ipairs(getStreamerNames()) do
        local pattern = escapeLuaPattern(name)
        table.insert(streamerNamePatterns, pattern)
    end
end

function maskStreamerText(text)
    if type(text) ~= "string" or text == "" then
        return text, false
    end
    local masked = text
    if #streamerNamePatterns == 0 then
        refreshStreamerNamePatterns()
    end
    for _, pattern in ipairs(streamerNamePatterns) do
        masked = masked:gsub(pattern, STREAMER_ALIAS)
    end
    return masked, masked ~= text
end

function isStreamerTextObject(obj)
    return obj and (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox"))
end

function isLikelyStreamerDynamicTextObject(obj)
    local current = obj
    for _ = 1, 6 do
        if not current then
            break
        end
        local name = tostring(current.Name or ""):lower()
        if
            name:find("player", 1, true)
            or name:find("leaderboard", 1, true)
            or name:find("chat", 1, true)
            or name:find("name", 1, true)
        then
            return true
        end
        current = current.Parent
    end
    return false
end

function applyStreamerMaskToTextObject(obj)
    if not streamerModeEnabled or not isStreamerTextObject(obj) then
        return false
    end
    local ok, text = pcall(function()
        return obj.Text
    end)
    if not ok or type(text) ~= "string" then
        return false
    end

    local original = streamerOriginalTexts[obj]
    if original then
        local maskedOriginal = select(1, maskStreamerText(original))
        if text == maskedOriginal then
            return true
        end
        local _, currentContainsName = maskStreamerText(text)
        if not currentContainsName then
            streamerOriginalTexts[obj] = nil
            return false
        end
    end

    local masked, changed = maskStreamerText(text)
    if changed then
        streamerOriginalTexts[obj] = text
        pcall(function()
            obj.Text = masked
        end)
    end
    return changed
end

function watchStreamerTextObject(obj)
    if not streamerModeEnabled or not isStreamerTextObject(obj) then
        return
    end
    local ok, text = pcall(function()
        return obj.Text
    end)
    local _, containsName = maskStreamerText(ok and text or "")
    local shouldTrack = containsName or isLikelyStreamerDynamicTextObject(obj)
    if shouldTrack and not streamerModeTextConnections[obj] then
        local ok, conn = pcall(function()
            return obj:GetPropertyChangedSignal("Text"):Connect(function()
                task.defer(applyStreamerMaskToTextObject, obj)
            end)
        end)
        if ok and conn then
            streamerModeTextConnections[obj] = conn
        end
    end
    applyStreamerMaskToTextObject(obj)
end

function scanStreamerRoot(root)
    if not streamerModeEnabled or not root then
        return
    end
    pcall(function()
        watchStreamerTextObject(root)
        local scanned = 0
        for _, obj in ipairs(root:GetDescendants()) do
            watchStreamerTextObject(obj)
            scanned += 1
            if scanned % 120 == 0 then
                task.wait()
            end
        end
    end)
end

function maskStreamerHumanoid(character)
    if not streamerModeEnabled or not character then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid") or character:FindFirstChild("Humanoid")
    if not humanoid then
        return
    end
    if not streamerOriginalHumanoids[humanoid] then
        streamerOriginalHumanoids[humanoid] = {
            displayName = humanoid.DisplayName,
            displayDistanceType = humanoid.DisplayDistanceType,
        }
    end
    pcall(function()
        humanoid.DisplayName = STREAMER_ALIAS
    end)
end

function restoreStreamerHumanoids()
    for humanoid, original in pairs(streamerOriginalHumanoids) do
        if humanoid and humanoid.Parent and type(original) == "table" then
            pcall(function()
                if original.displayName ~= nil then
                    humanoid.DisplayName = original.displayName
                end
                if original.displayDistanceType ~= nil then
                    humanoid.DisplayDistanceType = original.displayDistanceType
                end
            end)
        end
    end
    streamerOriginalHumanoids = setmetatable({}, { __mode = "k" })
end

function getStreamerRoots()
    local roots = { PlayerGui }
    local ok, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)
    if ok and coreGui then
        table.insert(roots, coreGui)
    end
    return roots
end

function startStreamerMode()
    if streamerModeEnabled then
        return true
    end
    streamerModeEnabled = true
    refreshStreamerNamePatterns()

    for _, root in ipairs(getStreamerRoots()) do
        task.defer(scanStreamerRoot, root)
        local ok, conn = pcall(function()
            return root.DescendantAdded:Connect(function(obj)
                watchStreamerTextObject(obj)
            end)
        end)
        if ok and conn then
            table.insert(streamerModeRootConnections, conn)
        end
    end

    maskStreamerHumanoid(LocalPlayer.Character)
    streamerCharacterConnection = LocalPlayer.CharacterAdded:Connect(function(character)
        task.defer(function()
            maskStreamerHumanoid(character)
        end)
    end)

    return true
end

function stopStreamerMode()
    streamerModeEnabled = false
    if streamerModeScanThread then
        task.cancel(streamerModeScanThread)
        streamerModeScanThread = nil
    end
    if streamerCharacterConnection then
        streamerCharacterConnection:Disconnect()
        streamerCharacterConnection = nil
    end
    for _, conn in ipairs(streamerModeRootConnections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    clearTable(streamerModeRootConnections)
    for _, conn in pairs(streamerModeTextConnections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    clearTable(streamerModeTextConnections)

    for obj, text in pairs(streamerOriginalTexts) do
        if obj and obj.Parent then
            pcall(function()
                obj.Text = text
            end)
        end
    end
    streamerOriginalTexts = setmetatable({}, { __mode = "k" })
    restoreStreamerHumanoids()
end

function getRewardsGuiRoot()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    return gui and gui:FindFirstChild("ReactGameNewRewards") or nil
end

function collectTextLines(root)
    local lines = {}
    if not root then
        return lines
    end
    for _, desc in ipairs(root:GetDescendants()) do
        if desc:IsA("TextLabel") or desc:IsA("TextButton") then
            local ok, text = pcall(function()
                return desc.Text
            end)
            text = ok and trimText(text) or ""
            if text ~= "" then
                table.insert(lines, text)
            end
        end
    end
    return lines
end

function findResultValue(lines, label)
    local needle = label:lower()
    for i, text in ipairs(lines) do
        local lower = text:lower()
        local at = lower:find(needle, 1, true)
        if at then
            local after = trimText(text:sub(at + #label))
            after = after:gsub("^:%s*", "")
            if after ~= "" then
                return after
            end
            for j = i + 1, math.min(#lines, i + 4) do
                local candidate = trimText(lines[j])
                local cLower = candidate:lower()
                if
                    candidate ~= ""
                    and not cLower:find("coins")
                    and not cLower:find("gems")
                    and not cLower:find("xp")
                    and not candidate:find(":")
                then
                    return candidate
                end
            end
        end
    end
    return nil
end

function extractRewardAmount(lines, rewardName)
    local total = 0
    local rewardLower = tostring(rewardName or ""):lower()
    local rewardBase = rewardLower:gsub("s$", "")
    for _, text in ipairs(lines) do
        local lower = trimText(tostring(text or ""):gsub("<[^>]->", "")):lower():gsub("%s+", " ")
        local raw = lower:match("^([%+%-]?%d[%d,]*)%s*" .. rewardBase .. "s?%s*$")
            or lower:match("^" .. rewardBase .. "s?%s*[:%-]?%s*([%+%-]?%d[%d,]*)%s*$")
        if raw then
            total += tonumber((raw:gsub("[+,]", ""))) or 0
        end
    end
    return total
end

function captureRewardsResult()
    local root = getRewardsGuiRoot()
    local lines = collectTextLines(root)
    if #lines == 0 then
        return nil
    end
    local joined = table.concat(lines, " "):upper()
    local outcome = joined:find("TRIUMPH", 1, true) and "Triumph"
        or (joined:find("YOU LOST", 1, true) or joined:find("DEFEAT", 1, true)) and "Defeat"
        or "Result"
    return {
        outcome = outcome,
        map = findResultValue(lines, "Map") or "?",
        wave = tonumber((findResultValue(lines, "Wave") or ""):match("%d+")) or getCurrentWave() or 0,
        mode = findResultValue(lines, "Game Mode") or "?",
        difficulty = findResultValue(lines, "Difficulty") or "?",
        time = findResultValue(lines, "Time Completed") or "?",
        coins = extractRewardAmount(lines, "coins"),
        gems = extractRewardAmount(lines, "gems"),
        xp = extractRewardAmount(lines, "xp"),
    }
end

function readBalanceCacheNumber(...)
    local cacheModule = safeRequirePath("Client.Modules.Cache", ReplicatedStorage, "Client", "Modules", "Cache")
    if type(cacheModule) ~= "function" then
        return nil
    end
    for _, key in ipairs({ ... }) do
        local value = nil
        pcall(function()
            local cache = cacheModule(key)
            value = cache and cache:GetValue()
        end)
        value = tonumber(value)
        if value then
            return value
        end
    end
    return nil
end

function readPlayerNumber(...)
    for _, key in ipairs({ ... }) do
        local value = nil
        pcall(function()
            value = LocalPlayer:GetAttribute(key)
        end)
        value = tonumber(value)
        if value then
            return value
        end
        local child = LocalPlayer:FindFirstChild(key)
        if child and child:IsA("ValueBase") then
            value = tonumber(child.Value)
            if value then
                return value
            end
        end
    end
    return nil
end

function captureCurrentBalances()
    local balances = {
        coins = readBalanceCacheNumber("Values.Coins", "Coins", "Inventory.Coins") or readPlayerNumber("Coins", "Coin"),
        gems = readBalanceCacheNumber("Values.Gems", "Gems", "Inventory.Gems") or readPlayerNumber("Gems", "Gem"),
        xp = readBalanceCacheNumber("Values.Experience", "Values.XP", "Experience", "XP")
            or readPlayerNumber("Experience", "XP", "Exp"),
    }
    balances.available = balances.coins ~= nil or balances.gems ~= nil or balances.xp ~= nil
    return balances.available and balances or nil
end

function cloneBalances(balances)
    if type(balances) ~= "table" then
        return nil
    end
    return {
        coins = balances.coins,
        gems = balances.gems,
        xp = balances.xp,
        available = balances.available == true,
    }
end

function balanceGain(current, started, fallback)
    if type(current) == "number" and type(started) == "number" then
        return current - started
    end
    return fallback
end

function fmtBalance(value)
    return type(value) == "number" and fmtNum(math.floor(value)) or "?"
end

function fmtGain(value)
    if type(value) ~= "number" then
        return "?"
    end
    local prefix = value >= 0 and "+" or "-"
    return prefix .. fmtNum(math.abs(math.floor(value)))
end

function rewardParts(coins, gems, xp, formatter)
    formatter = formatter or function(value)
        return fmtNum(value)
    end
    local parts = {}
    coins = tonumber(coins) or 0
    gems = tonumber(gems) or 0
    xp = tonumber(xp) or 0
    if coins > 0 then
        table.insert(parts, formatter(coins) .. " Coins")
    end
    if gems > 0 then
        table.insert(parts, formatter(gems) .. " Gems")
    end
    if xp > 0 then
        table.insert(parts, formatter(xp) .. " XP")
    end
    return parts
end

function rewardInline(coins, gems, xp, emptyText)
    local parts = rewardParts(coins, gems, xp)
    if #parts == 0 then
        return emptyText or "None"
    end
    return table.concat(parts, " / ")
end

function rewardBlockText(coins, gems, xp, emptyText, formatter)
    local parts = rewardParts(coins, gems, xp, formatter)
    if #parts == 0 then
        return emptyText or "None"
    end
    return table.concat(parts, "\n")
end

resultsStats = {
    runs = 0,
    wins = 0,
    losses = 0,
    coins = 0,
    gems = 0,
    xp = 0,
    pendingRuns = 0,
    pendingCoins = 0,
    pendingGems = 0,
    pendingXp = 0,
    lastVisible = false,
    lastKey = "",
    lastSentAt = tick(),
    startBalances = nil,
    currentBalances = nil,
    sessionStartedAt = tick(),
}

function addTrackedResult(result)
    result.coins = math.max(0, tonumber(result.coins) or 0)
    result.gems = math.max(0, tonumber(result.gems) or 0)
    result.xp = math.max(0, tonumber(result.xp) or 0)
    local key = table.concat({
        tostring(result.outcome),
        tostring(result.map),
        tostring(result.wave),
        tostring(result.time),
        tostring(result.coins),
        tostring(result.gems),
        tostring(result.xp),
    }, "|")
    if key == resultsStats.lastKey then
        return false
    end
    resultsStats.lastKey = key
    resultsStats.runs += 1
    resultsStats.pendingRuns += 1
    if result.outcome == "Triumph" then
        resultsStats.wins += 1
    end
    if result.outcome == "Defeat" then
        resultsStats.losses += 1
    end
    resultsStats.coins += result.coins
    resultsStats.gems += result.gems
    resultsStats.xp += result.xp
    resultsStats.pendingCoins += result.coins
    resultsStats.pendingGems += result.gems
    resultsStats.pendingXp += result.xp
    resultsStats.lastResult = result
    return true
end

function checkForRewardsResult(announce)
    local visible = isNewRewardsGuiEnabled()
    if visible and not resultsStats.lastVisible then
        local result = captureRewardsResult()
        if result and addTrackedResult(result) then
            if announce then
                notify("Result tracked: " .. tostring(result.outcome) .. " wave " .. tostring(result.wave))
            end
            resultsStats.lastRewardAt = tick()
        end
    end
    resultsStats.lastVisible = visible
end

function getHttpRequestFunction()
    local env = zephyrGetRuntimeEnv()
    return env.request
        or env.http_request
        or (type(env.syn) == "table" and env.syn.request)
        or (type(env.http) == "table" and env.http.request)
end

feedbackCache = {}
FEEDBACK_CACHE_TTL = 60

function parseJsonBody(body)
    if type(body) ~= "string" or body == "" then
        return nil
    end
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(body)
    end)
    if ok then
        return decoded
    end
    return nil
end

function normalizeCloudFeedback(data)
    data = type(data) == "table" and data or {}
    local likes = tonumber(data.likes or data.upvotes or 0) or 0
    local dislikes = tonumber(data.dislikes or data.downvotes or 0) or 0
    local reports = tonumber(data.reports or data.flags or 0) or 0
    return {
        likes = likes,
        dislikes = dislikes,
        reports = reports,
        total = tonumber(data.total) or (likes + dislikes),
        positive = data.positive,
        fetchedAt = tick(),
    }
end

function cloudGet(path)
    local ok, responseBody = pcall(function()
        return game:HttpGet(TDS_FEEDBACK_HOST .. path)
    end)
    if not ok then
        return false, responseBody
    end
    return true, parseJsonBody(responseBody)
end

function cloudPost(path, payload)
    local ok, body = pcall(function()
        return HttpService:JSONEncode(payload)
    end)
    if not ok then
        return false, body
    end

    local requestFn = getHttpRequestFunction()
    if type(requestFn) == "function" then
        local requestOk, response = pcall(function()
            return requestFn({
                Url = TDS_FEEDBACK_HOST .. path,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = body,
            })
        end)
        if not requestOk then
            return false, response
        end
        local status = type(response) == "table"
            and tonumber(response.StatusCode or response.status_code or response.status)
        local responseBody = type(response) == "table" and tostring(response.Body or response.body or "") or ""
        local decoded = parseJsonBody(responseBody)
        if status and (status < 200 or status >= 300) then
            return false, (type(decoded) == "table" and decoded.error) or ("HTTP " .. tostring(status))
        end
        return true, decoded or response
    end

    local postOk, responseBody = pcall(function()
        return HttpService:PostAsync(TDS_FEEDBACK_HOST .. path, body, Enum.HttpContentType.ApplicationJson)
    end)
    if not postOk then
        return false, responseBody
    end
    return true, parseJsonBody(responseBody)
end

function fetchCloudFeedback(stratId)
    stratId = tostring(stratId or "")
    if stratId == "" then
        return false, "No strat id"
    end
    local ok, result = cloudGet("/tds/feedback?id=" .. stratId:gsub(" ", "%%20"))
    if not ok then
        return false, result
    end
    if type(result) ~= "table" or result.ok ~= true or type(result.data) ~= "table" then
        return false, "Bad feedback response"
    end
    return true, result.data[stratId]
end

function queueCloudFeedback(stratId, callback)
    stratId = tostring(stratId or "")
    if stratId == "" then
        return
    end
    local cached = feedbackCache[stratId]
    if cached and tick() - (cached.fetchedAt or 0) < FEEDBACK_CACHE_TTL then
        if type(callback) == "function" then
            task.spawn(callback, cached)
        end
        return
    end
    task.spawn(function()
        local ok, data = fetchCloudFeedback(stratId)
        if ok then
            local item = normalizeCloudFeedback(data)
            feedbackCache[stratId] = item
            if type(callback) == "function" then
                callback(item)
            end
        else
            warn("[Zephyr] Feedback fetch failed:", tostring(data))
        end
    end)
end

function submitCloudVote(stratId, vote)
    local payload = {
        strat_id = tostring(stratId or ""),
        user_id = tostring(LocalPlayer and LocalPlayer.UserId or "unknown"),
        vote = vote,
        source = "script",
    }
    return cloudPost("/tds/vote", payload)
end

function submitCloudReport(stratId, reason)
    local payload = {
        strat_id = tostring(stratId or ""),
        user_id = tostring(LocalPlayer and LocalPlayer.UserId or "unknown"),
        reason = tostring(reason or ""),
        source = "script",
    }
    return cloudPost("/tds/report", payload)
end

function sendDiscordWebhook(payload)
    local url = trimText(tdsSettings.resultsWebhookUrl)
    if url == "" then
        return false, "Webhook is empty"
    end
    local body = HttpService:JSONEncode(payload)
    local requestFn = getHttpRequestFunction()
    if type(requestFn) == "function" then
        local ok, response = pcall(function()
            return requestFn({
                Url = url,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = body,
            })
        end)
        if not ok then
            return false, response
        end
        local status = type(response) == "table"
            and tonumber(response.StatusCode or response.status_code or response.status)
        if status and (status < 200 or status >= 300) then
            return false, "Webhook failed (" .. tostring(status) .. ")"
        end
        return true, response
    end
    return pcall(function()
        return HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
    end)
end

function sendResultsSummary()
    local balances = captureCurrentBalances()
    if balances then
        resultsStats.currentBalances = cloneBalances(balances)
        if not resultsStats.startBalances then
            resultsStats.startBalances = cloneBalances(balances)
        end
    else
        balances = resultsStats.currentBalances
    end
    local hasBalances = type(balances) == "table" and balances.available == true
    if resultsStats.pendingRuns <= 0 and not hasBalances then
        return false, "No new runs"
    end

    local last = resultsStats.lastResult or {}
    local started = resultsStats.startBalances or {}
    local sessionSeconds = math.max(1, tick() - (resultsStats.sessionStartedAt or tick()))
    local gainedCoins = balanceGain(balances and balances.coins, started.coins, resultsStats.coins)
    local gainedGems = balanceGain(balances and balances.gems, started.gems, resultsStats.gems)
    local gainedXp = balanceGain(balances and balances.xp, started.xp, resultsStats.xp)
    local function field(name, value, inline)
        return { name = name, value = tostring(value), inline = inline == true }
    end
    local function fmtPlain(value)
        return type(value) == "number" and fmtNum(math.floor(value)) or "Unknown"
    end
    local function fmtPercent(part, total)
        total = tonumber(total) or 0
        if total <= 0 then
            return "0%"
        end
        return tostring(math.floor(((tonumber(part) or 0) / total) * 100 + 0.5)) .. "%"
    end
    local function fmtRate(value)
        if type(value) ~= "number" then
            return "Unknown"
        end
        return fmtNum(math.floor((value / sessionSeconds) * 3600 + 0.5)) .. "/hr"
    end
    local function fmtDuration(seconds)
        seconds = math.max(0, math.floor(tonumber(seconds) or 0))
        local hours = math.floor(seconds / 3600)
        local minutes = math.floor((seconds % 3600) / 60)
        local secs = seconds % 60
        if hours > 0 then
            return string.format("%dh %02dm", hours, minutes)
        end
        return string.format("%dm %02ds", minutes, secs)
    end
    local function rewardBlock(coins, gems, xp, prefix)
        prefix = prefix or ""
        local text = rewardBlockText(coins, gems, xp, "None", function(value)
            return prefix .. fmtPlain(value)
        end)
        return text
    end
    local function gainedBlock(coins, gems, xp)
        return rewardBlockText(coins, gems, xp, "No rewards", fmtGain)
    end
    local function rateBlock(coins, gems, xp)
        return rewardBlockText(coins, gems, xp, "No reward rate yet", fmtRate)
    end
    local function outcomeColor(outcome)
        if outcome == "Triumph" then
            return 2278750
        end
        if outcome == "Defeat" then
            return 15680580
        end
        return 8141549
    end
    local hasLast = type(last.outcome) == "string" and last.outcome ~= ""
    local embeds = {
        {
            author = {
                name = "Zephyr TDS",
            },
            title = "Match Tracker Summary",
            description = table.concat({
                "**" .. tostring(LocalPlayer.Name or "Player") .. "**",
                "Session Time: `" .. fmtDuration(sessionSeconds) .. "`",
            }, "\n"),
            color = outcomeColor(hasLast and last.outcome or nil),
            fields = {
                field(
                    "Session",
                    table.concat({
                        "Runs: **" .. tostring(resultsStats.runs) .. "**",
                        "New Runs: **" .. tostring(resultsStats.pendingRuns) .. "**",
                        "Win Rate: **"
                            .. fmtPercent(resultsStats.wins, resultsStats.wins + resultsStats.losses)
                            .. "**",
                    }, "\n"),
                    true
                ),
                field(
                    "Record",
                    table.concat({
                        "Wins: **" .. tostring(resultsStats.wins) .. "**",
                        "Losses: **" .. tostring(resultsStats.losses) .. "**",
                    }, "\n"),
                    true
                ),
                field("Session Rewards", gainedBlock(resultsStats.coins, resultsStats.gems, resultsStats.xp), true),
                field(
                    "Since Last Webhook",
                    gainedBlock(resultsStats.pendingCoins, resultsStats.pendingGems, resultsStats.pendingXp),
                    true
                ),
                field("Rates", rateBlock(resultsStats.coins, resultsStats.gems, resultsStats.xp), true),
                field(
                    "Account",
                    table.concat({
                        fmtPlain(balances and balances.coins) .. " Coins (" .. fmtGain(gainedCoins) .. ")",
                        fmtPlain(balances and balances.gems) .. " Gems (" .. fmtGain(gainedGems) .. ")",
                        fmtPlain(balances and balances.xp) .. " XP (" .. fmtGain(gainedXp) .. ")",
                    }, "\n"),
                    true
                ),
            },
            footer = {
                text = "Zephyr TDS Match Tracker",
            },
            timestamp = DateTime.now():ToIsoDate(),
        },
    }
    if hasLast then
        local latestLines = {}
        if type(last.map) == "string" and last.map ~= "?" then
            table.insert(latestLines, "**" .. last.map .. "**")
        end
        if tonumber(last.wave) and tonumber(last.wave) > 0 then
            table.insert(latestLines, "Wave " .. tostring(last.wave))
        end
        if type(last.time) == "string" and last.time ~= "?" then
            table.insert(latestLines, last.time)
        end
        local latestDescription = #latestLines > 0 and table.concat(latestLines, " | ") or "Latest tracked match"
        table.insert(embeds, {
            title = "Latest Result: " .. tostring(last.outcome),
            description = latestDescription,
            color = outcomeColor(last.outcome),
            fields = {
                field("Rewards", rewardBlock(last.coins or 0, last.gems or 0, last.xp or 0), true),
            },
            footer = {
                text = tostring(last.difficulty and last.difficulty ~= "?" and last.difficulty or "TDS")
                    .. " | "
                    .. tostring(last.mode and last.mode ~= "?" and last.mode or "Match"),
            },
            timestamp = DateTime.now():ToIsoDate(),
        })
    end
    local payload = {
        username = "Zephyr TDS",
        embeds = embeds,
    }
    local ok, result = sendDiscordWebhook(payload)
    if ok then
        resultsStats.pendingRuns = 0
        resultsStats.pendingCoins = 0
        resultsStats.pendingGems = 0
        resultsStats.pendingXp = 0
        resultsStats.lastSentAt = tick()
    end
    return ok, result
end

function startResultsTracker()
    if ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.resultsTrackerThread then
        return
    end
    tdsSettings.resultsTrackerEnabled = true
    ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.resultsTrackerSession += 1
    local session = ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.resultsTrackerSession
    local startingBalances = captureCurrentBalances()
    if startingBalances then
        resultsStats.startBalances = cloneBalances(startingBalances)
        resultsStats.currentBalances = cloneBalances(startingBalances)
    end
    ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.resultsTrackerThread = task.spawn(function()
        while
            tdsSettings.resultsTrackerEnabled == true
            and session == ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.resultsTrackerSession
        do
            local balances = captureCurrentBalances()
            if balances then
                resultsStats.currentBalances = cloneBalances(balances)
                if not resultsStats.startBalances then
                    resultsStats.startBalances = cloneBalances(balances)
                end
            end
            checkForRewardsResult(true)

            local interval = getSettingNumber("resultsWebhookIntervalMinutes", 60, 1, 1440) * 60
            if
                (resultsStats.pendingRuns > 0 or resultsStats.currentBalances)
                and tick() - resultsStats.lastSentAt >= interval
            then
                local ok, err = sendResultsSummary()
                if not ok then
                    warn("[Zephyr] Results webhook failed:", tostring(err))
                end
            end
            task.wait(2)
        end
        ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.resultsTrackerThread = nil
    end)
end

function stopResultsTracker()
    tdsSettings.resultsTrackerEnabled = false
    ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.resultsTrackerSession += 1
    if ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.resultsTrackerThread then
        task.cancel(ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.resultsTrackerThread)
        ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.resultsTrackerThread = nil
    end
end

matchTrackerGui = nil
matchTrackerThread = nil
matchTrackerEnabled = false

function formatTrackerDuration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    if hours > 0 then
        return string.format("%dh %02dm", hours, minutes)
    end
    return string.format("%dm %02ds", minutes, secs)
end

function stopMatchTracker()
    matchTrackerEnabled = false
    if matchTrackerThread then
        task.cancel(matchTrackerThread)
        matchTrackerThread = nil
    end
    if matchTrackerGui and matchTrackerGui.Parent then
        matchTrackerGui:Destroy()
    end
    matchTrackerGui = nil
end

function startMatchTracker()
    stopMatchTracker()
    matchTrackerEnabled = true

    local existing = PlayerGui:FindFirstChild("ZephyrTDSMatchTracker")
    if existing then
        existing:Destroy()
    end

    local isMobile = UserInputService.TouchEnabled
        and not UserInputService.KeyboardEnabled
        and not UserInputService.MouseEnabled
    local width = isMobile and 276 or 328
    local expandedHeight = isMobile and 184 or 206
    local collapsedHeight = isMobile and 46 or 52
    local headerHeight = isMobile and 36 or 42
    local corner = 10

    local gui = Instance.new("ScreenGui")
    gui.Name = "ZephyrTDSMatchTracker"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = PlayerGui
    matchTrackerGui = gui

    local panel = Instance.new("Frame", gui)
    panel.AnchorPoint = Vector2.new(0.5, 0)
    panel.Size = UDim2.new(0, width, 0, expandedHeight)
    panel.Position = UDim2.new(0.5, 0, 0, isMobile and 72 or 86)
    panel.BackgroundColor3 = Color3.fromRGB(12, 14, 24)
    panel.BorderSizePixel = 0
    panel.ZIndex = 318
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, corner)
    local panelStroke = Instance.new("UIStroke", panel)
    panelStroke.Color = Color3.fromRGB(111, 118, 255)
    panelStroke.Transparency = 0.28
    panelStroke.Thickness = 1
    local panelGradient = Instance.new("UIGradient", panel)
    panelGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(14, 17, 31)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(9, 10, 18)),
    })
    panelGradient.Rotation = 90

    local header = Instance.new("TextButton", panel)
    header.Size = UDim2.new(1, -16, 0, headerHeight)
    header.Position = UDim2.new(0, 8, 0, 8)
    header.BackgroundColor3 = Color3.fromRGB(96, 165, 250)
    header.BorderSizePixel = 0
    header.Text = ""
    header.AutoButtonColor = false
    header.ZIndex = 319
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 9)
    local headerGradient = Instance.new("UIGradient", header)
    headerGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(63, 180, 255)),
        ColorSequenceKeypoint.new(0.48, Color3.fromRGB(93, 101, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 70, 255)),
    })
    headerGradient.Rotation = 0

    local sideSize = headerHeight - 12

    local title = Instance.new("TextLabel", header)
    title.Size = UDim2.new(1, -((sideSize + 14) * 2), 1, 0)
    title.Position = UDim2.new(0, sideSize + 14, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "MATCH TRACKER"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = isMobile and 13 or 16
    title.Font = Enum.Font.GothamBlack
    title.TextXAlignment = Enum.TextXAlignment.Center
    title.ZIndex = 320

    local collapseBtn = Instance.new("TextButton", header)
    collapseBtn.Size = UDim2.new(0, sideSize, 0, sideSize)
    collapseBtn.Position = UDim2.new(1, -(sideSize + 7), 0.5, -(sideSize / 2))
    collapseBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    collapseBtn.BackgroundTransparency = 0.76
    collapseBtn.BorderSizePixel = 0
    collapseBtn.Text = "-"
    collapseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    collapseBtn.TextSize = isMobile and 16 or 18
    collapseBtn.Font = Enum.Font.GothamBlack
    collapseBtn.ZIndex = 320
    Instance.new("UICorner", collapseBtn).CornerRadius = UDim.new(0, 7)

    local body = Instance.new("Frame", panel)
    body.Size = UDim2.new(1, -28, 1, -(headerHeight + 30))
    body.Position = UDim2.new(0, 14, 0, headerHeight + 18)
    body.BackgroundTransparency = 1
    body.ZIndex = 319

    local statRows = {}
    local rowHeight = isMobile and 20 or 23
    local function makeStatRow(order, labelText, color)
        local row = Instance.new("Frame", body)
        row.Size = UDim2.new(1, 0, 0, rowHeight)
        row.Position = UDim2.new(0, 0, 0, (order - 1) * rowHeight)
        row.BackgroundTransparency = 1
        row.ZIndex = 320
        local label = Instance.new("TextLabel", row)
        label.Size = UDim2.new(0.45, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = labelText
        label.TextColor3 = Color3.fromRGB(207, 213, 235)
        label.TextSize = isMobile and 10 or 12
        label.Font = Enum.Font.GothamBlack
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.ZIndex = 321
        local value = Instance.new("TextLabel", row)
        value.Size = UDim2.new(0.55, 0, 1, 0)
        value.Position = UDim2.new(0.45, 0, 0, 0)
        value.BackgroundTransparency = 1
        value.Text = "-"
        value.TextColor3 = color
        value.TextSize = isMobile and 10 or 12
        value.Font = Enum.Font.GothamBlack
        value.TextXAlignment = Enum.TextXAlignment.Right
        value.TextTruncate = Enum.TextTruncate.AtEnd
        value.ZIndex = 321
        statRows[order] = value
        return value
    end
    makeStatRow(1, "Total Rewards", Color3.fromRGB(250, 204, 21))
    makeStatRow(2, "Latest Reward", Color3.fromRGB(250, 204, 21))
    makeStatRow(3, "Total XP", Color3.fromRGB(34, 197, 94))
    makeStatRow(4, "Latest Result", Color3.fromRGB(96, 165, 250))
    makeStatRow(5, "Playtime", Color3.fromRGB(96, 165, 250))

    local divider = Instance.new("Frame", body)
    divider.Size = UDim2.new(1, 0, 0, 1)
    divider.Position = UDim2.new(0, 0, 1, -22)
    divider.BackgroundColor3 = Color3.fromRGB(58, 68, 98)
    divider.BackgroundTransparency = 0.24
    divider.BorderSizePixel = 0
    divider.ZIndex = 320

    local footer = Instance.new("TextLabel", body)
    footer.Size = UDim2.new(1, 0, 0, 18)
    footer.Position = UDim2.new(0, 0, 1, -18)
    footer.BackgroundTransparency = 1
    footer.Text = "Runs: 0 | @" .. tostring(LocalPlayer.Name)
    footer.TextColor3 = Color3.fromRGB(220, 225, 245)
    footer.TextSize = isMobile and 10 or 12
    footer.Font = Enum.Font.GothamBlack
    footer.TextXAlignment = Enum.TextXAlignment.Center
    footer.ZIndex = 320

    local collapsed = false
    local function renderCollapsed()
        panel.Size = UDim2.new(0, width, 0, collapsed and collapsedHeight or expandedHeight)
        body.Visible = not collapsed
        collapseBtn.Text = collapsed and "+" or "-"
    end

    collapseBtn.MouseButton1Click:Connect(function()
        collapsed = not collapsed
        renderCollapsed()
    end)

    do
        local dragging, dragStart, panelStart, dragInput = false, nil, nil, nil
        header.InputBegan:Connect(function(input)
            local t = input.UserInputType
            if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                panelStart = panel.Position
                local conn
                conn = input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                        if conn then
                            conn:Disconnect()
                        end
                    end
                end)
            end
        end)
        header.InputChanged:Connect(function(input)
            local t = input.UserInputType
            if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
                dragInput = input
            end
        end)
        local dragConnection = UserInputService.InputChanged:Connect(function(input)
            if input == dragInput and dragging then
                local delta = input.Position - dragStart
                panel.Position = UDim2.new(
                    panelStart.X.Scale,
                    panelStart.X.Offset + delta.X,
                    panelStart.Y.Scale,
                    panelStart.Y.Offset + delta.Y
                )
            end
        end)
        panel.Destroying:Connect(function()
            dragConnection:Disconnect()
        end)
    end

    local function refreshTrackerText()
        checkForRewardsResult(false)
        local last = resultsStats.lastResult or {}
        local latestResult = "Waiting"
        local hasLatest = type(last.outcome) == "string" and last.outcome ~= ""
        local latestColor = Color3.fromRGB(96, 165, 250)
        if hasLatest then
            local waveText = tonumber(last.wave) and (" W" .. tostring(last.wave)) or ""
            latestResult = tostring(last.outcome) .. waveText
            if last.outcome == "Triumph" then
                latestColor = Color3.fromRGB(34, 197, 94)
            elseif last.outcome == "Defeat" then
                latestColor = Color3.fromRGB(239, 68, 68)
            end
        end
        statRows[1].Text = rewardInline(resultsStats.coins, resultsStats.gems, nil, "No currency")
        statRows[2].Text = hasLatest and rewardInline(last.coins, last.gems, last.xp, "No rewards") or "Waiting"
        statRows[3].Text = fmtNum(resultsStats.xp) .. " XP"
        statRows[4].Text = latestResult
        statRows[4].TextColor3 = latestColor
        statRows[5].Text = formatTrackerDuration(tick() - (resultsStats.sessionStartedAt or tick()))
        footer.Text = "Runs: " .. tostring(resultsStats.runs) .. " | @" .. tostring(LocalPlayer.Name)
    end

    refreshTrackerText()
    matchTrackerThread = task.spawn(function()
        while matchTrackerEnabled and gui.Parent do
            refreshTrackerText()
            task.wait(1)
        end
        matchTrackerThread = nil
    end)

    return true
end

getOwnedTowerEntities = nil
estimateOwnDPS = nil

function getEnemyStatsSnapshot()
    local snapshot = { count = 0, totalHp = 0, highestName = "None", highestHp = 0 }
    local StateReps = ReplicatedStorage:FindFirstChild("StateReplicators")
    if StateReps then
        for _, rep in ipairs(StateReps:GetChildren()) do
            if rep.Name == "NPCReplicator" then
                local hp = tonumber(rep:GetAttribute("Health")) or 0
                if hp > 0 then
                    snapshot.count += 1
                    snapshot.totalHp += hp
                    if hp > snapshot.highestHp then
                        snapshot.highestHp = hp
                        snapshot.highestName = tostring(rep:GetAttribute("ModelName") or "Enemy")
                    end
                end
            end
        end
    else
        local folder = workspace:FindFirstChild("NPCs")
        if folder then
            for _, npc in ipairs(folder:GetChildren()) do
                if npc:IsA("Model") then
                    local hum = npc:FindFirstChildOfClass("Humanoid")
                    local hp = hum and hum.Health or 1
                    if hp > 0 then
                        snapshot.count += 1
                        snapshot.totalHp += hp
                        if hp > snapshot.highestHp then
                            snapshot.highestHp = hp
                            snapshot.highestName = npc.Name
                        end
                    end
                end
            end
        end
    end
    return snapshot
end

function stopEnemyInspector()
    enemyInspectorEnabled = false
    if enemyInspectorCleanup then
        pcall(enemyInspectorCleanup)
        enemyInspectorCleanup = nil
    end
end

function compactNumber(value)
    local n = math.floor((tonumber(value) or 0) + 0.5)
    local abs = math.abs(n)
    if abs >= 1000000000 then
        return string.format("%.1fB", n / 1000000000):gsub("%.0B", "B")
    elseif abs >= 1000000 then
        return string.format("%.1fM", n / 1000000):gsub("%.0M", "M")
    elseif abs >= 1000 then
        return string.format("%.1fK", n / 1000):gsub("%.0K", "K")
    end
    return tostring(n)
end

function startEnemyInspector()
    stopEnemyInspector()
    enemyInspectorEnabled = true
    local gui = Instance.new("ScreenGui")
    gui.Name = "ZephyrTDSEnemyInspector"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = PlayerGui

    local frame = Instance.new("Frame", gui)
    frame.Size = UDim2.new(0, 162, 0, 54)
    frame.Position = UDim2.new(1, -172, 0, 70)
    frame.BackgroundColor3 = Color3.fromRGB(15, 16, 26)
    frame.BackgroundTransparency = 0
    frame.BorderSizePixel = 0
    frame.ZIndex = 300
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = Color3.fromRGB(99, 102, 241)
    stroke.Transparency = 0.3

    local title = Instance.new("TextLabel", frame)
    title.Size = UDim2.new(0.5, -8, 0, 14)
    title.Position = UDim2.new(0, 8, 0, 4)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 10
    title.TextColor3 = Color3.fromRGB(99, 102, 241)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "ENEMIES"
    title.ZIndex = 301

    local dpsLabel = Instance.new("TextLabel", frame)
    dpsLabel.Size = UDim2.new(0.5, -8, 0, 14)
    dpsLabel.Position = UDim2.new(0.5, 0, 0, 4)
    dpsLabel.BackgroundTransparency = 1
    dpsLabel.Font = Enum.Font.GothamBold
    dpsLabel.TextSize = 10
    dpsLabel.TextColor3 = Color3.fromRGB(96, 165, 250)
    dpsLabel.TextXAlignment = Enum.TextXAlignment.Right
    dpsLabel.ZIndex = 301

    local line1 = Instance.new("TextLabel", frame)
    line1.Size = UDim2.new(1, -16, 0, 14)
    line1.Position = UDim2.new(0, 8, 0, 21)
    line1.BackgroundTransparency = 1
    line1.Font = Enum.Font.Gotham
    line1.TextSize = 9
    line1.TextColor3 = Color3.fromRGB(185, 195, 220)
    line1.TextXAlignment = Enum.TextXAlignment.Left
    line1.ZIndex = 301

    local line2 = Instance.new("TextLabel", frame)
    line2.Size = UDim2.new(1, -16, 0, 14)
    line2.Position = UDim2.new(0, 8, 0, 35)
    line2.BackgroundTransparency = 1
    line2.Font = Enum.Font.Gotham
    line2.TextSize = 9
    line2.TextColor3 = Color3.fromRGB(145, 155, 182)
    line2.TextXAlignment = Enum.TextXAlignment.Left
    line2.TextTruncate = Enum.TextTruncate.AtEnd
    line2.ZIndex = 301

    local running = true
    local thread = task.spawn(function()
        while running and enemyInspectorEnabled do
            local s = getEnemyStatsSnapshot()
            local dps = estimateOwnDPS and estimateOwnDPS() or 0
            dpsLabel.Text = "DPS " .. compactNumber(dps)
            line1.Text = string.format("Alive %d  HP %s", s.count, compactNumber(s.totalHp))
            line2.Text = string.format("Top %s  %s", tostring(s.highestName or "None"), compactNumber(s.highestHp))
            task.wait(1.5)
        end
    end)

    enemyInspectorCleanup = function()
        running = false
        if thread then
            task.cancel(thread)
        end
        if gui and gui.Parent then
            gui:Destroy()
        end
    end
    return true
end

towerReplicatorCache = false
OWNED_TOWER_CACHE_TTL = 0.5
ownedTowerCache = nil
ownedTowerCacheAt = 0

function getTowerReplicator()
    if towerReplicatorCache ~= false then
        return towerReplicatorCache
    end
    towerReplicatorCache = nil
    local client = ReplicatedStorage:FindFirstChild("Client")
    local modules = client and client:FindFirstChild("Modules")
    local reps = modules and modules:FindFirstChild("Replicators")
    local mod = reps and reps:FindFirstChild("TowerReplicator")
    local result = mod and safeRequire(mod, "Client.Modules.Replicators.TowerReplicator") or nil
    if type(result) == "table" then
        towerReplicatorCache = result
    end
    return towerReplicatorCache
end

function resolveOwnedTowerName(model, entity)
    local candidates = {}
    local function add(value)
        if type(value) == "string" and value ~= "" and value ~= "Default" then
            table.insert(candidates, value)
        end
    end
    if entity then
        add(entity.TowerName)
        add(entity.Name)
        if type(entity.State) == "table" then
            add(entity.State.Type)
            add(entity.State.Name)
        end
        pcall(function()
            add(entity.Replicator and entity.Replicator:Get("Name"))
        end)
        pcall(function()
            add(entity.Replicator and entity.Replicator:Get("Type"))
        end)
    end
    if model then
        add(model:GetAttribute("TowerName"))
        add(model:GetAttribute("Name"))
        add(model:GetAttribute("Type"))
        add(model:GetAttribute("DisplayName"))
        local nameValue = model:FindFirstChild("Name")
        if nameValue and nameValue:IsA("StringValue") then
            add(nameValue.Value)
        end
        local towerNameValue = model:FindFirstChild("TowerName")
        if towerNameValue and towerNameValue:IsA("StringValue") then
            add(towerNameValue.Value)
        end
        local towerRep = model:FindFirstChild("TowerReplicator")
        if towerRep then
            add(towerRep:GetAttribute("TowerName"))
            add(towerRep:GetAttribute("Name"))
            add(towerRep:GetAttribute("Type"))
            add(towerRep:GetAttribute("DisplayName"))
            local repName = towerRep:FindFirstChild("Name")
                or towerRep:FindFirstChild("TowerName")
                or towerRep:FindFirstChild("Type")
            if repName and repName:IsA("StringValue") then
                add(repName.Value)
            end
        end
        local rep = getTowerReplicator()
        if rep and type(rep.getTowerByModel) == "function" then
            local ok, resolved = pcall(rep.getTowerByModel, model)
            if ok and resolved and resolved ~= entity then
                add(resolved.TowerName)
                add(resolved.Name)
                if type(resolved.State) == "table" then
                    add(resolved.State.Type)
                    add(resolved.State.Name)
                end
                pcall(function()
                    add(resolved.Replicator and resolved.Replicator:Get("Name"))
                end)
            end
        end
    end
    return candidates[1] or tostring(model and model.Name or entity and entity.Name or "")
end

function isLocalTowerOwnerValue(value)
    if value == nil then
        return false
    end
    if value == LocalPlayer or value == LocalPlayer.UserId then
        return true
    end
    if tostring(value) == tostring(LocalPlayer.UserId) or tostring(value) == LocalPlayer.Name then
        return true
    end
    if typeof(value) == "Instance" and value:IsA("Player") then
        return value == LocalPlayer or value.UserId == LocalPlayer.UserId
    end
    if type(value) == "table" then
        return tostring(value.UserId or value.userId or "") == tostring(LocalPlayer.UserId)
    end
    return false
end

function isOwnedTowerEntity(entity)
    if not entity then
        return false
    end
    if isLocalTowerOwnerValue(entity.OwnerId) or isLocalTowerOwnerValue(entity.Owner) then
        return true
    end
    if type(entity.State) == "table" then
        if isLocalTowerOwnerValue(entity.State.OwnerId) or isLocalTowerOwnerValue(entity.State.Owner) then
            return true
        end
    end
    local rep = entity.Replicator
    local ownerValues = { "OwnerId", "Owner", "UserId", "Player" }
    for _, key in ipairs(ownerValues) do
        local ok, value = pcall(function()
            return rep and rep:Get(key)
        end)
        if ok and isLocalTowerOwnerValue(value) then
            return true
        end
    end
    return false
end

function getOwnedTowerEntitiesRaw()
    local out = {}
    local rep = getTowerReplicator()
    if rep and type(rep.getTowers) == "function" then
        local ok, towers = pcall(rep.getTowers)
        if ok and type(towers) == "table" then
            for model, entity in pairs(towers) do
                if isOwnedTowerEntity(entity) then
                    table.insert(out, {
                        model = model,
                        entity = entity,
                        name = resolveOwnedTowerName(model, entity),
                    })
                end
            end
        end
    end
    if #out == 0 then
        local towers = workspace:FindFirstChild("Towers")
        if towers then
            for _, tower in ipairs(towers:GetChildren()) do
                if tower:IsA("Model") and isOwnTower(tower) then
                    table.insert(out, {
                        model = tower,
                        entity = nil,
                        name = resolveOwnedTowerName(tower, nil),
                    })
                end
            end
        end
    end
    return out
end

function getOwnedTowerEntities()
    local now = tick()
    if ownedTowerCache and now - ownedTowerCacheAt < OWNED_TOWER_CACHE_TTL then
        local allAlive = true
        for _, towerInfo in ipairs(ownedTowerCache) do
            local model = towerInfo and towerInfo.model
            if model and typeof(model) == "Instance" and not model.Parent then
                allAlive = false
                break
            end
        end
        if allAlive then
            return ownedTowerCache
        end
    end
    ownedTowerCache = getOwnedTowerEntitiesRaw()
    ownedTowerCacheAt = now
    return ownedTowerCache
end

function getNumericStat(stats, ...)
    if type(stats) ~= "table" then
        return nil
    end
    for _, key in ipairs({ ... }) do
        local value = tonumber(stats[key])
        if value then
            return value
        end
        if type(stats.Attributes) == "table" then
            value = tonumber(stats.Attributes[key])
            if value then
                return value
            end
        end
    end
    return nil
end

function estimateOwnDPS()
    local total = 0
    for _, towerInfo in ipairs(getOwnedTowerEntities()) do
        local stats = towerInfo.entity and towerInfo.entity.Stats
        if type(stats) ~= "table" and towerInfo.model then
            local ok, attrs = pcall(function()
                return towerInfo.model:GetAttributes()
            end)
            if ok and type(attrs) == "table" then
                stats = attrs
            end
        end
        if type(stats) == "table" then
            local damage = getNumericStat(stats, "Damage", "BaseDamage")
            local cooldown = getNumericStat(stats, "Cooldown", "FireRate")
            if damage and cooldown and cooldown > 0 then
                local burst = getNumericStat(stats, "Burst", "BurstCount", "Shots", "Pellets") or 1
                local dps = (damage * burst) / cooldown
                local ammo = getNumericStat(stats, "Ammo", "MaxAmmo")
                local reload = getNumericStat(stats, "ReloadTime")
                if ammo and ammo > 0 and reload and reload > 0 then
                    local activeTime = ammo * cooldown
                    dps = dps * (activeTime / (activeTime + reload))
                end
                local extraDamage = getNumericStat(stats, "ExplosionDamage", "SplashDamage", "ImpactDamage")
                if extraDamage then
                    dps += extraDamage / cooldown
                end
                total += dps
            end
        end
    end
    return total
end

abilityRules = {
    { id = "commander", match = "commander", names = { "Call Of Arms", "Call to Arms" }, interval = 10 },
    { id = "dj", match = "dj booth", names = { "Drop The Beat" }, interval = 30 },
    { id = "mercenary", match = "mercenary base", names = { "Support Caravan" }, interval = 2 },
    { id = "medic", match = "medic", names = { "Cleanse" }, interval = 18 },
    {
        id = "saboteur",
        match = "saboteur",
        names = { "Sabotage", "Detonate", "Remote Detonate", "C4", "Timed Charge", "Explosive Charge" },
        interval = 7,
        discover = true,
    },
    {
        id = "hacker",
        match = "hacker",
        names = { "Hack", "Overclock", "Clone", "Tower Clone", "Replicate" },
        interval = 12,
        discover = true,
    },
    {
        id = "brawler",
        match = "brawler",
        names = { "Uppercut", "Slam", "Knockout", "Rush", "Haymaker" },
        interval = 7,
        discover = true,
    },
}

function addAbilityNameUnique(list, seen, name)
    name = tostring(name or "")
    if name == "" then
        return
    end
    local key = abilityKey(name):lower()
    if key == "" or seen[key] then
        return
    end
    seen[key] = true
    list[#list + 1] = name
end

function abilityMatchesRuleName(rule, name)
    if not rule then
        return false
    end
    if rule.discover == true then
        return true
    end
    local clean = abilityKey(name):lower()
    if clean == "" then
        return false
    end
    for _, candidate in ipairs(rule.names or {}) do
        if abilityKey(candidate):lower() == clean then
            return true
        end
    end
    return false
end

function collectTowerAutoAbilityNames(towerInfo, rule)
    local names = {}
    local seen = {}
    for _, name in ipairs(rule.names or {}) do
        addAbilityNameUnique(names, seen, name)
    end

    local available = towerInfo and towerInfo.entity and towerInfo.entity.AvailableAbilities
    if type(available) == "table" then
        for key, ability in pairs(available) do
            local candidates = { key }
            if type(ability) == "table" then
                candidates[#candidates + 1] = ability.Name
                candidates[#candidates + 1] = ability.Id
                candidates[#candidates + 1] = ability.ID
                candidates[#candidates + 1] = ability.DisplayName
                candidates[#candidates + 1] = ability.Title
            else
                candidates[#candidates + 1] = ability
            end
            for _, candidate in ipairs(candidates) do
                if abilityMatchesRuleName(rule, candidate) then
                    addAbilityNameUnique(names, seen, candidate)
                end
            end
        end
    end

    return names
end

function startAbilityManager()
    if abilityManagerThread then
        return
    end
    abilityManagerEnabled = true
    local lastUsed = {}
    abilityManagerThread = task.spawn(function()
        while abilityManagerEnabled do
            local now = tick()
            for _, towerInfo in ipairs(getOwnedTowerEntities()) do
                local lowerName = towerInfo.name:lower()
                for _, rule in ipairs(abilityRules) do
                    if
                        lowerName:find(rule.match, 1, true)
                        and not (rule.id == "commander" and commanderChainEnabled)
                        and not (rule.id == "mercenary" and supportCaravanEnabled)
                    then
                        for _, abilityName in ipairs(collectTowerAutoAbilityNames(towerInfo, rule)) do
                            local key = tostring(towerInfo.model) .. ":" .. abilityKey(abilityName)
                            local remaining, known = getTowerAbilityCooldownRemaining(towerInfo, abilityName)
                            local localReady = not lastUsed[key] or now - lastUsed[key] >= rule.interval
                            if localReady and (not known or not remaining or remaining <= 0.1) then
                                local ok, result = pcall(function()
                                    return invokeTroopsThrottled("Abilities", "Activate", {
                                        Troop = towerInfo.model,
                                        Name = abilityName,
                                        Data = {},
                                    })
                                end)
                                if ok and result ~= false then
                                    lastUsed[key] = now
                                else
                                    lastUsed[key] = now - (rule.interval * 0.5)
                                end
                            end
                        end
                    end
                end
            end
            task.wait(1.5)
        end
        abilityManagerThread = nil
    end)
end

function stopAbilityManager()
    abilityManagerEnabled = false
    if abilityManagerThread then
        task.cancel(abilityManagerThread)
        abilityManagerThread = nil
    end
end

function upgradeOwnedTower(tower)
    if not tower then
        return false
    end
    local rep = tower:FindFirstChild("TowerReplicator")
    local levelBefore = rep and rep:GetAttribute("Upgrade") or 0
    invokeTroopsThrottled("Upgrade", "Set", {
        Troop = tower,
        Path = 1,
    })
    return waitForUpgrade(tower, levelBefore, 0.45)
end

FARM_UPGRADE_COSTS = { 200, 600, 1250, 2500, 4500 }

function getTowerUpgradeLevelForAuto(towerInfo)
    local level = nil
    local entity = towerInfo and towerInfo.entity
    local model = towerInfo and towerInfo.model
    if entity then
        level = tonumber(entity.Upgrade) or level
        if type(entity.State) == "table" then
            level = tonumber(entity.State.Upgrade) or tonumber(entity.State.Level) or level
        end
        pcall(function()
            level = tonumber(entity.Replicator and entity.Replicator:Get("Upgrade")) or level
        end)
        pcall(function()
            level = tonumber(entity.Replicator and entity.Replicator:Get("Level")) or level
        end)
    end
    if model then
        local rep = model:FindFirstChild("TowerReplicator")
        if rep then
            level = tonumber(rep:GetAttribute("Upgrade")) or tonumber(rep:GetAttribute("Level")) or level
        end
        level = tonumber(model:GetAttribute("Upgrade")) or tonumber(model:GetAttribute("Level")) or level
    end
    return math.max(0, math.floor(tonumber(level) or 0))
end

function isFarmTowerInfo(towerInfo)
    local name = tostring(towerInfo and towerInfo.name or ""):lower()
    if name == "farm" then
        return true
    end
    local model = towerInfo and towerInfo.model
    if model then
        local modelName = tostring(model.Name or ""):lower()
        if modelName == "farm" then
            return true
        end
        local towerName = tostring(model:GetAttribute("TowerName") or model:GetAttribute("Type") or ""):lower()
        if towerName == "farm" then
            return true
        end
    end
    return false
end

function getNextFarmUpgradeCost(towerInfo)
    local level = getTowerUpgradeLevelForAuto(towerInfo)
    if level >= #FARM_UPGRADE_COSTS then
        return nil, true
    end

    local stats = towerInfo and towerInfo.entity and towerInfo.entity.Stats
    local upgrades = type(stats) == "table" and stats.Upgrades or nil
    local liveUpgrade = type(upgrades) == "table" and (upgrades[level + 1] or upgrades[tostring(level + 1)]) or nil
    local liveCost = type(liveUpgrade) == "table" and tonumber(liveUpgrade.Cost) or nil
    return liveCost or FARM_UPGRADE_COSTS[level + 1], false
end

function canUpgradeFarmNow(towerInfo)
    local cost, maxed = getNextFarmUpgradeCost(towerInfo)
    if maxed then
        return false
    end
    if cost and cost > 0 then
        return getCash() >= cost
    end
    return true
end

local sellingOwnedTowers = false
function startAutoUpgradeFarms()
    if autoUpgradeFarmsThread then
        return
    end
    autoUpgradeFarmsEnabled = true
    autoUpgradeFarmsThread = task.spawn(function()
        while runtimeAlive and autoUpgradeFarmsEnabled do
            if macroPlaying or sellingOwnedTowers then
                task.wait(0.3)
                continue
            end
            local upgraded = 0
            for _, towerInfo in ipairs(getOwnedTowerEntities()) do
                if not autoUpgradeFarmsEnabled or macroPlaying or sellingOwnedTowers then
                    break
                end
                if isFarmTowerInfo(towerInfo) and canUpgradeFarmNow(towerInfo) then
                    if upgradeOwnedTower(towerInfo.model) then
                        upgraded += 1
                    end
                    task.wait(0.08)
                end
            end
            task.wait(upgraded > 0 and 0.25 or 0.75)
        end
        autoUpgradeFarmsThread = nil
    end)
end

function stopAutoUpgradeFarms()
    autoUpgradeFarmsEnabled = false
    if autoUpgradeFarmsThread then
        task.cancel(autoUpgradeFarmsThread)
        autoUpgradeFarmsThread = nil
    end
end

function sellOwnedTower(tower)
    if not tower then
        return false
    end
    invokeTroopsThrottled("Sell", {
        Troop = tower,
    })
    local started = tick()
    while tick() - started < 1.5 do
        if not tower.Parent then
            return true
        end
        task.wait(0.05)
    end
    return false
end

function startAutoUpgrade()
    if autoUpgradeThread then
        return
    end
    autoUpgradeEnabled = true
    autoUpgradeThread = task.spawn(function()
        while runtimeAlive and autoUpgradeEnabled do
            if macroPlaying or sellingOwnedTowers then
                task.wait(0.3)
                continue
            end
            local upgraded = 0
            for _, towerInfo in ipairs(getOwnedTowerEntities()) do
                if not autoUpgradeEnabled or macroPlaying or sellingOwnedTowers then
                    break
                end
                if autoUpgradeFarmsEnabled and isFarmTowerInfo(towerInfo) then
                    continue
                end
                if upgradeOwnedTower(towerInfo.model) then
                    upgraded += 1
                end
                task.wait(0.12)
            end
            task.wait(upgraded > 0 and 0.6 or 1.25)
        end
        autoUpgradeThread = nil
    end)
end

function stopAutoUpgrade()
    autoUpgradeEnabled = false
    if autoUpgradeThread then
        task.cancel(autoUpgradeThread)
        autoUpgradeThread = nil
    end
end

function sellAllOwnedTowers()
    if sellingOwnedTowers then
        return 0
    end
    sellingOwnedTowers = true
    local count = 0
    local ok, err = pcall(function()
        local towers = getOwnedTowerEntities()
        for i = #towers, 1, -1 do
            if not runtimeAlive then
                break
            end
            local tower = towers[i].model
            if tower and tower.Parent and sellOwnedTower(tower) then
                count += 1
            end
            task.wait(0.06)
        end
    end)
    sellingOwnedTowers = false
    if not ok then
        warn("[Zephyr] Sell towers failed:", tostring(err))
    end
    return count
end

function getClientCache()
    local cacheModule = safeRequirePath("Client.Modules.Cache", ReplicatedStorage, "Client", "Modules", "Cache")
    if type(cacheModule) == "function" then
        return cacheModule
    end
    return nil
end

function getCacheValue(cacheModule, name, fallback)
    local cache = cacheModule and cacheModule(name)
    if not cache then
        return fallback
    end
    local value
    pcall(function()
        value = cache:GetValue()
    end)
    if value == nil then
        return fallback
    end
    return value
end

function updateCacheValue(cacheModule, name, value)
    local cache = cacheModule and cacheModule(name)
    if not cache then
        return false
    end
    local ok = pcall(function()
        cache:Update(value)
    end)
    return ok == true
end

installClientCosmeticActionHooks = nil

function tableHasValueOrKey(list, name)
    name = tostring(name or "")
    if name == "" or type(list) ~= "table" then
        return false
    end
    if list[name] ~= nil then
        return true
    end
    for _, value in pairs(list) do
        if tostring(value) == name then
            return true
        end
        if type(value) == "table" then
            local valueName = value.Name or value.name or value.Id or value.id
            if valueName and tostring(valueName) == name then
                return true
            end
        end
    end
    return false
end

function removeArrayValue(list, name)
    name = tostring(name or "")
    if type(list) ~= "table" then
        return {}
    end
    for i = #list, 1, -1 do
        if tostring(list[i]) == name then
            table.remove(list, i)
        end
    end
    return list
end

function normalizeClientCosmeticType(itemType)
    local key = tostring(itemType or ""):lower():gsub("%s+", ""):gsub("_", "")
    if key:sub(-1) == "s" then
        key = key:sub(1, -2)
    end
    if key == "emote" then
        return "emote"
    end
    if key == "sticker" then
        return "sticker"
    end
    if key == "tag" or key == "nametag" or key == "nameplate" then
        return "nametag"
    end
    if key == "totem" or key == "charm" then
        return "totem"
    end
    if key == "flair" then
        return "flair"
    end
    return nil
end

function clientVisualUnlockActiveFor(cosmeticType)
    if cosmeticType == "emote" then
        return unlockEmotesClientEnabled == true
    end
    if cosmeticType == "sticker" or cosmeticType == "nametag" or cosmeticType == "totem" or cosmeticType == "flair" then
        return unlockCosmeticsClientEnabled == true
    end
    return false
end

function getClientCosmeticInventory(cacheModule, cosmeticType)
    cacheModule = cacheModule or getClientCache()
    if cosmeticType == "emote" then
        return getCacheValue(cacheModule, "Inventory.Emotes", {}) or {}
    end
    if cosmeticType == "sticker" then
        return getCacheValue(cacheModule, "Inventory.Stickers", {}) or {}
    end
    if cosmeticType == "nametag" then
        return getCacheValue(cacheModule, "Inventory.Nametags", {}) or {}
    end
    if cosmeticType == "totem" then
        return getCacheValue(cacheModule, "Inventory.Totems", {}) or {}
    end
    if cosmeticType == "flair" then
        return getCacheValue(cacheModule, "Inventory.Flairs", {}) or {}
    end
    return {}
end

function isClientVisualCosmeticAvailable(cosmeticType, name)
    if not clientVisualUnlockActiveFor(cosmeticType) then
        return false
    end
    local cacheModule = getClientCache()
    if not cacheModule then
        return false
    end
    return tableHasValueOrKey(getClientCosmeticInventory(cacheModule, cosmeticType), name)
end

function isClientOriginalCosmeticOwned(cosmeticType, name)
    name = tostring(name or "")
    if name == "" then
        return false
    end
    if name == "Default" then
        return true
    end
    if cosmeticType == "emote" then
        return tableHasValueOrKey(clientEmoteUnlockOriginalEmotes, name)
    end
    if type(clientCosmeticUnlockOriginals) ~= "table" then
        return false
    end
    if cosmeticType == "sticker" then
        return tableHasValueOrKey(clientCosmeticUnlockOriginals.stickers, name)
    end
    if cosmeticType == "nametag" then
        return tableHasValueOrKey(clientCosmeticUnlockOriginals.nametags, name)
    end
    if cosmeticType == "totem" then
        return tableHasValueOrKey(clientCosmeticUnlockOriginals.totems, name)
    end
    if cosmeticType == "flair" then
        return tableHasValueOrKey(clientCosmeticUnlockOriginals.flairs, name)
    end
    return false
end

function setLocalPlayerCosmeticValue(cosmeticType, name)
    if not LocalPlayer then
        return
    end
    local valueName = tostring(name or "")
    local candidates
    if cosmeticType == "nametag" then
        candidates = { "Nametag", "NameTag", "Tag" }
        pcall(function()
            LocalPlayer:SetAttribute("Nametag", valueName)
        end)
        pcall(function()
            LocalPlayer:SetAttribute("NameTag", valueName)
        end)
    elseif cosmeticType == "totem" then
        candidates = { "Totem", "Charm" }
        pcall(function()
            LocalPlayer:SetAttribute("Totem", valueName)
        end)
    elseif cosmeticType == "flair" then
        candidates = { "Flair" }
        pcall(function()
            LocalPlayer:SetAttribute("Flair", valueName)
        end)
    else
        return
    end
    for _, childName in ipairs(candidates or {}) do
        local child = LocalPlayer:FindFirstChild(childName)
        if child and child:IsA("StringValue") then
            pcall(function()
                child.Value = valueName
            end)
            pcall(function()
                child:SetAttribute("Enabled", valueName ~= "" and valueName ~= "Default")
            end)
        end
    end
end

function setEquippedClientCosmetic(cosmeticType, name, unequip, slot)
    local cacheModule = getClientCache()
    if not cacheModule then
        return false
    end
    name = tostring(name or "")
    if name == "" then
        return false
    end

    if cosmeticType == "emote" or cosmeticType == "sticker" then
        local cacheName = cosmeticType == "emote" and "Equipped.Emotes" or "Equipped.Stickers"
        local equipped = cloneSettingsValue(getCacheValue(cacheModule, cacheName, {}) or {})
        if type(equipped) ~= "table" then
            equipped = {}
        end
        removeArrayValue(equipped, name)
        if not unequip then
            local slotIndex = tonumber(slot)
            if slotIndex and slotIndex >= 1 and slotIndex <= 8 then
                equipped[math.floor(slotIndex)] = name
            else
                local placed = false
                for i = 1, 8 do
                    if equipped[i] == nil or equipped[i] == "" then
                        equipped[i] = name
                        placed = true
                        break
                    end
                end
                if not placed then
                    table.insert(equipped, name)
                end
            end
        end
        return updateCacheValue(cacheModule, cacheName, equipped)
    end

    if cosmeticType == "nametag" then
        local equippedName = unequip and "Default" or name
        setLocalPlayerCosmeticValue(cosmeticType, equippedName)
        return updateCacheValue(cacheModule, "Equipped.Nametag", equippedName)
    end

    if cosmeticType == "totem" then
        local equippedName = unequip and "Default" or name
        setLocalPlayerCosmeticValue(cosmeticType, equippedName)
        return updateCacheValue(cacheModule, "Equipped.Totem", equippedName)
    end

    if cosmeticType == "flair" then
        local equippedName = unequip and "" or name
        setLocalPlayerCosmeticValue(cosmeticType, equippedName)
        return updateCacheValue(cacheModule, "Equipped.Flair", equippedName)
    end

    return false
end

function reapplyClientCosmeticEquip(cosmeticType, name, unequip, slot)
    task.defer(function()
        setEquippedClientCosmetic(cosmeticType, name, unequip, slot)
    end)
    task.delay(0.2, function()
        setEquippedClientCosmetic(cosmeticType, name, unequip, slot)
    end)
    task.delay(0.75, function()
        setEquippedClientCosmetic(cosmeticType, name, unequip, slot)
    end)
end

function handleClientCosmeticInventoryAction(actionName, itemType, itemName, slot)
    local action = tostring(actionName or ""):lower():gsub("%s+", "")
    local cosmeticType = normalizeClientCosmeticType(itemType)
    local name = itemName

    if action == "equipemote" or action == "unequipemote" then
        cosmeticType = "emote"
        name = itemType
        slot = itemName
    elseif action == "equipsticker" or action == "unequipsticker" then
        cosmeticType = "sticker"
        name = itemType
        slot = itemName
    end

    if
        action ~= "equip"
        and action ~= "unequip"
        and action ~= "equipemote"
        and action ~= "unequipemote"
        and action ~= "equipsticker"
        and action ~= "unequipsticker"
    then
        return false
    end

    name = tostring(name or "")
    if not cosmeticType or name == "" then
        return false
    end
    if not isClientVisualCosmeticAvailable(cosmeticType, name) then
        return false
    end

    local unequip = action:find("unequip", 1, true) ~= nil
    setEquippedClientCosmetic(cosmeticType, name, unequip, slot)
    reapplyClientCosmeticEquip(cosmeticType, name, unequip, slot)

    -- Keep fake unlocks local; the server won't accept them.
    return not isClientOriginalCosmeticOwned(cosmeticType, name)
end

function hookClientInventoryChannel(channel)
    if type(channel) ~= "table" or clientInventoryHookedChannels[channel] then
        return false
    end
    local invokeOk, invokeFn = pcall(function()
        return channel.InvokeServer
    end)
    local fireOk, fireFn = pcall(function()
        return channel.FireServer
    end)
    if not ((invokeOk and type(invokeFn) == "function") or (fireOk and type(fireFn) == "function")) then
        return false
    end

    clientInventoryHookedChannels[channel] = { invoke = invokeFn, fire = fireFn }
    clientInventoryChannel = clientInventoryChannel or channel
    oldInventoryInvoke = oldInventoryInvoke or invokeFn
    oldInventoryFire = oldInventoryFire or fireFn

    local assigned = false
    if fireOk and type(fireFn) == "function" then
        local assignOk = pcall(function()
            channel.FireServer = function(self, actionName, itemType, itemName, slot, ...)
                if handleClientCosmeticInventoryAction(actionName, itemType, itemName, slot) then
                    return true
                end
                return fireFn(self, actionName, itemType, itemName, slot, ...)
            end
        end)
        assigned = assigned or assignOk
    end

    if invokeOk and type(invokeFn) == "function" then
        local assignOk = pcall(function()
            channel.InvokeServer = function(self, actionName, itemType, itemName, slot, ...)
                if handleClientCosmeticInventoryAction(actionName, itemType, itemName, slot) then
                    return true
                end
                return invokeFn(self, actionName, itemType, itemName, slot, ...)
            end
        end)
        assigned = assigned or assignOk
    end

    if not assigned then
        clientInventoryHookedChannels[channel] = nil
        return false
    end

    return true
end

function hookClientEmotesChannel(channel)
    if type(channel) ~= "table" or clientEmoteHookedChannels[channel] then
        return false
    end
    local invokeOk, invokeFn = pcall(function()
        return channel.InvokeServer
    end)
    if not (invokeOk and type(invokeFn) == "function") then
        return false
    end

    clientEmoteHookedChannels[channel] = { invoke = invokeFn }
    clientEmotesChannel = clientEmotesChannel or channel
    oldEmotesInvoke = oldEmotesInvoke or invokeFn

    local assignOk = pcall(function()
        channel.InvokeServer = function(self, actionName, emoteName, ...)
            if
                tostring(actionName or ""):lower() == "play"
                and isClientVisualCosmeticAvailable("emote", emoteName)
                and not isClientOriginalCosmeticOwned("emote", emoteName)
            then
                return true
            end
            return invokeFn(self, actionName, emoteName, ...)
        end
    end)

    if not assignOk then
        clientEmoteHookedChannels[channel] = nil
        return false
    end

    return true
end

function hookClientNetworkChannels(networkModule)
    if type(networkModule) ~= "table" then
        return false
    end
    local channelOk, channelFn = pcall(function()
        return networkModule.Channel
    end)
    if not (channelOk and type(channelFn) == "function") then
        return false
    end

    local hooked = false
    local ok, channel = pcall(channelFn, "Inventory")
    if ok and channel then
        hooked = hookClientInventoryChannel(channel) or hooked
    end
    ok, channel = pcall(channelFn, "Emotes")
    if ok and channel then
        hooked = hookClientEmotesChannel(channel) or hooked
    end
    return hooked
end

function hookClientPlayerEmoteReplicator()
    if oldCharacterStartEmoting then
        return false
    end
    local replicator = safeRequirePath(
        "Client.Modules.Replicators.PlayerCharacterReplicator",
        ReplicatedStorage,
        "Client",
        "Modules",
        "Replicators",
        "PlayerCharacterReplicator"
    )
    if
        type(replicator) ~= "table"
        or type(replicator.StartEmoting) ~= "function"
        or type(replicator.StartEmotingLocally) ~= "function"
    then
        return false
    end

    clientPlayerCharacterReplicator = replicator
    oldCharacterStartEmoting = replicator.StartEmoting
    replicator.StartEmoting = function(self, emoteName, target, state)
        if
            isClientVisualCosmeticAvailable("emote", emoteName)
            and not isClientOriginalCosmeticOwned("emote", emoteName)
        then
            local ok, startedAt = pcall(function()
                return workspace:GetServerTimeNow()
            end)
            if not ok then
                startedAt = tick()
            end
            pcall(function()
                self.EmoteStarted = startedAt
            end)
            local localOk, result = pcall(function()
                return self:StartEmotingLocally(emoteName, startedAt, target, state)
            end)
            if localOk then
                return result ~= false
            end
        end
        return oldCharacterStartEmoting(self, emoteName, target, state)
    end
    return true
end

function makeClientResolvedPromise(...)
    local results = { ... }
    local promise = {}
    function promise:await()
        return unpackArgs(results)
    end
    function promise:andThen(callback)
        if type(callback) == "function" then
            local ok, result = pcall(callback, unpackArgs(results))
            if ok then
                return makeClientResolvedPromise(result)
            end
            return makeClientResolvedPromise(false, result)
        end
        return self
    end
    function promise:catch()
        return self
    end
    function promise:timeout()
        return self
    end
    return promise
end

function getStickerNameFromArg(sticker)
    if type(sticker) == "table" then
        return tostring(sticker.name or sticker.Name or sticker.id or sticker.Id or "")
    end
    return tostring(sticker or "")
end

function hookClientStickerController()
    if oldStickerEquip then
        return false
    end
    local controller = safeRequirePath(
        "Client.Controllers.Shared.StickerController",
        ReplicatedStorage,
        "Client",
        "Controllers",
        "Shared",
        "StickerController"
    )
    if type(controller) ~= "table" then
        return false
    end

    clientStickerController = controller
    oldStickerEquip = type(controller.equipSticker) == "function" and controller.equipSticker or nil
    oldStickerUnequip = type(controller.unequipSticker) == "function" and controller.unequipSticker or nil

    local assigned = false
    if oldStickerEquip then
        local ok = pcall(function()
            controller.equipSticker = function(sticker, slot, ...)
                local name = getStickerNameFromArg(sticker)
                if isClientVisualCosmeticAvailable("sticker", name) then
                    setEquippedClientCosmetic("sticker", name, false, slot)
                    reapplyClientCosmeticEquip("sticker", name, false, slot)
                    if not isClientOriginalCosmeticOwned("sticker", name) then
                        return makeClientResolvedPromise(true)
                    end
                end
                return oldStickerEquip(sticker, slot, ...)
            end
        end)
        assigned = assigned or ok
    end

    if oldStickerUnequip then
        local ok = pcall(function()
            controller.unequipSticker = function(sticker, ...)
                local name = getStickerNameFromArg(sticker)
                if isClientVisualCosmeticAvailable("sticker", name) then
                    setEquippedClientCosmetic("sticker", name, true)
                    reapplyClientCosmeticEquip("sticker", name, true)
                    if not isClientOriginalCosmeticOwned("sticker", name) then
                        return makeClientResolvedPromise(true)
                    end
                end
                return oldStickerUnequip(sticker, ...)
            end
        end)
        assigned = assigned or ok
    end

    if not assigned then
        oldStickerEquip = nil
        oldStickerUnequip = nil
        clientStickerController = nil
        return false
    end

    return true
end

installClientCosmeticActionHooks = function()
    local hooked = false
    hooked = hookClientNetworkChannels(Network) or hooked

    local uiNetwork = safeRequirePath("Shared.UI.Network", ReplicatedStorage, "Shared", "UI", "Network")
    hooked = hookClientNetworkChannels(uiNetwork) or hooked
    hooked = hookClientPlayerEmoteReplicator() or hooked
    hooked = hookClientStickerController() or hooked

    clientCosmeticHooksInstalled = clientCosmeticHooksInstalled or hooked
    return hooked
end

function getSkinSelections()
    if type(tdsSettings.skinChangerSelections) ~= "table" then
        tdsSettings.skinChangerSelections = {}
    end
    return tdsSettings.skinChangerSelections
end

SKIN_CHANGER_BLOCKED_TOWERS = {
    [settingsLookupKey("Gatling Gun")] = true,
}

function skinChangerSupportsTower(towerName)
    return not SKIN_CHANGER_BLOCKED_TOWERS[settingsLookupKey(towerName)]
end

function captureSkinChangerOriginalTroops(cacheModule)
    if type(skinChangerOriginalTroops) == "table" then
        return skinChangerOriginalTroops
    end
    cacheModule = cacheModule or getClientCache()
    local troops = cloneSettingsValue(getCacheValue(cacheModule, "Inventory.Troops", {}) or {})
    if type(troops) == "table" then
        skinChangerOriginalTroops = troops
    else
        skinChangerOriginalTroops = {}
    end
    return skinChangerOriginalTroops
end

function getOriginalPlacementSkin(towerName, fallbackSkin)
    towerName = tostring(towerName or "")
    local originalTroops = captureSkinChangerOriginalTroops()
    local owned = type(originalTroops) == "table" and originalTroops[towerName]
    if type(owned) == "table" and type(owned.Skin) == "string" and owned.Skin ~= "" then
        return owned.Skin
    end
    local cacheModule = getClientCache()
    local liveTroops = getCacheValue(cacheModule, "Inventory.Troops", {}) or {}
    owned = type(liveTroops) == "table" and liveTroops[towerName]
    if type(owned) == "table" and type(owned.Skin) == "string" and owned.Skin ~= "" then
        local saved = getSkinSelections()[towerName]
        if owned.Skin ~= saved then
            return owned.Skin
        end
    end
    fallbackSkin = tostring(fallbackSkin or "Default")
    if fallbackSkin ~= "" and fallbackSkin ~= tostring(getSkinSelections()[towerName] or "") then
        return fallbackSkin
    end
    return "Default"
end

function restoreSkinChangerTroopCache(cacheModule)
    if type(skinChangerOriginalTroops) ~= "table" then
        return false
    end
    cacheModule = cacheModule or getClientCache()
    if not cacheModule then
        return false
    end
    skinChangerSuppressRemember = true
    local ok = updateCacheValue(cacheModule, "Inventory.Troops", cloneSettingsValue(skinChangerOriginalTroops))
    task.defer(function()
        skinChangerSuppressRemember = false
    end)
    return ok
end

function getSavedSkin(towerName)
    if not skinChangerSupportsTower(towerName) then
        return nil
    end
    local selections = getSkinSelections()
    local skin = selections[tostring(towerName or "")]
    if type(skin) == "string" and skin ~= "" then
        return skin
    end
    return nil
end

function setSavedSkin(towerName, skinName)
    towerName = tostring(towerName or "")
    skinName = tostring(skinName or "Default")
    if towerName == "" then
        return
    end
    local selections = getSkinSelections()
    if not skinChangerSupportsTower(towerName) then
        if selections[towerName] ~= nil then
            selections[towerName] = nil
            saveSettingsSoon()
        end
        return
    end
    if selections[towerName] ~= skinName then
        selections[towerName] = skinName
        saveSettingsSoon()
    end
end

towerSkinDataCache = {}
skinSourceCache = {}
skinSourceCacheAt = {}
skinSourcePending = {}

function getTowerSkinData(towerName)
    towerName = tostring(towerName or "")
    if towerName == "" then
        return { Default = true }
    end
    if towerSkinDataCache[towerName] then
        return towerSkinDataCache[towerName]
    end

    local found = { Default = true }
    local content = ReplicatedStorage:FindFirstChild("Content")
    local towerFolder = content and content:FindFirstChild("Tower")
    local tower = towerFolder and towerFolder:FindFirstChild(towerName)
    local statsModule = tower and tower:FindFirstChild("Stats")
    if statsModule then
        local data = safeRequire(statsModule, "Content.Tower.Stats")
        local skinData = data and data.Properties and data.Properties.SkinData
        if type(skinData) == "table" then
            for skinName in pairs(skinData) do
                found[tostring(skinName)] = true
            end
        end
    end

    local troops = ReplicatedStorage:FindFirstChild("Assets")
    troops = troops and troops:FindFirstChild("Troops")
    local assetTower = troops and troops:FindFirstChild(towerName)
    local skins = assetTower and assetTower:FindFirstChild("Skins")
    if skins then
        for _, skin in ipairs(skins:GetChildren()) do
            found[skin.Name] = true
        end
    end

    towerSkinDataCache[towerName] = found
    return found
end

function getSkinChangerPlacementSkin(towerName, troops)
    towerName = tostring(towerName or "")
    if not skinChangerSupportsTower(towerName) then
        local owned = type(troops) == "table" and troops[towerName]
        return type(owned) == "table" and owned.Skin or "Default"
    end
    local saved = getSavedSkin(towerName)
    if saved and saved ~= "Default" then
        local skinData = getTowerSkinData(towerName)
        if skinData[saved] == true then
            return saved
        end
    end
    local owned = type(troops) == "table" and troops[towerName]
    if type(owned) == "table" and type(owned.Skin) == "string" and owned.Skin ~= "" then
        return owned.Skin
    end
    return "Default"
end

function buildAllTowerCache(cacheModule)
    local troops = cloneSettingsValue(getCacheValue(cacheModule, "Inventory.Troops", {}) or {})
    if type(troops) ~= "table" then
        troops = {}
    end
    local towerFolder = ReplicatedStorage:FindFirstChild("Content")
    towerFolder = towerFolder and towerFolder:FindFirstChild("Tower")
    if not towerFolder then
        return nil, 0
    end

    local unlocked = 0
    for _, tower in ipairs(towerFolder:GetChildren()) do
        local towerName = tostring(tower.Name or "")
        if towerName ~= "" then
            local current = type(troops[towerName]) == "table" and cloneSettingsValue(troops[towerName]) or {}
            local selectedSkin = tostring(current.Skin or getSavedSkin(towerName) or "Default")
            if selectedSkin == "" then
                selectedSkin = "Default"
            end
            current.Name = current.Name or towerName
            current.Skin = selectedSkin
            current.Owned = true
            current.Unlocked = true
            current.Purchased = true
            current.Acquired = true
            troops[towerName] = current
            unlocked += 1
        end
    end

    return troops, unlocked
end

function setClientTowerUnlock(enabled)
    local cacheModule = getClientCache()
    if not cacheModule then
        return false, "Cache unavailable"
    end
    if enabled then
        if not ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.clientTowerUnlockOriginalTroops then
            ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.clientTowerUnlockOriginalTroops =
                cloneSettingsValue(getCacheValue(cacheModule, "Inventory.Troops", {}) or {})
        end
        local troops, count = buildAllTowerCache(cacheModule)
        if not troops or count <= 0 then
            return false, "Tower data unavailable"
        end
        skinChangerSuppressRemember = true
        updateCacheValue(cacheModule, "Inventory.Troops", troops)
        task.defer(function()
            skinChangerSuppressRemember = false
        end)
        tdsSettings.unlockTowersClientEnabled = true
        return true, count
    end
    if ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.clientTowerUnlockOriginalTroops then
        skinChangerSuppressRemember = true
        updateCacheValue(
            cacheModule,
            "Inventory.Troops",
            ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.clientTowerUnlockOriginalTroops
        )
        task.defer(function()
            skinChangerSuppressRemember = false
        end)
    end
    ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.clientTowerUnlockOriginalTroops = nil
    tdsSettings.unlockTowersClientEnabled = false
    return true, 0
end

function buildAllSkinCache(cacheModule)
    local skins = cloneSettingsValue(getCacheValue(cacheModule, "Inventory.Skins", {}) or {})
    local troops = cloneSettingsValue(getCacheValue(cacheModule, "Inventory.Troops", {}) or {})
    local towerFolder = ReplicatedStorage:FindFirstChild("Content")
    towerFolder = towerFolder and towerFolder:FindFirstChild("Tower")
    if not towerFolder then
        return nil, 0
    end
    local unlocked = 0
    for _, tower in ipairs(towerFolder:GetChildren()) do
        local statsModule = tower:FindFirstChild("Stats")
        if statsModule then
            local data = safeRequire(statsModule, "Content.Tower.Stats")
            local skinData = data and data.Properties and data.Properties.SkinData
            if type(skinData) == "table" then
                local list = {}
                local selectedSkin = getSavedSkin(tower.Name)
                local sawDefault = false
                for skinName in pairs(skinData) do
                    skinName = tostring(skinName)
                    if skinName == "Default" then
                        sawDefault = true
                    end
                    selectedSkin = selectedSkin
                        or (type(troops[tower.Name]) == "table" and troops[tower.Name].Skin)
                        or "Default"
                    table.insert(list, {
                        Name = skinName,
                        Equipped = selectedSkin == skinName,
                    })
                end
                if not sawDefault then
                    selectedSkin = selectedSkin or "Default"
                    table.insert(list, { Name = "Default", Equipped = selectedSkin == "Default" })
                end
                table.sort(list, function(a, b)
                    return tostring(a.Name) < tostring(b.Name)
                end)
                skins[tower.Name] = list
                unlocked += #list
            end
        end
    end
    return skins, unlocked
end

function setClientSkinUnlock(enabled)
    local cacheModule = getClientCache()
    if not cacheModule then
        return false, "Cache unavailable"
    end
    if enabled then
        if not clientSkinUnlockOriginalSkins then
            clientSkinUnlockOriginalSkins = cloneSettingsValue(getCacheValue(cacheModule, "Inventory.Skins", {}) or {})
        end
        local skins, count = buildAllSkinCache(cacheModule)
        if not skins then
            return false, "Tower data unavailable"
        end
        updateCacheValue(cacheModule, "Inventory.Skins", skins)
        unlockSkinsClientEnabled = true
        return true, count
    end
    if clientSkinUnlockOriginalSkins then
        skinChangerSuppressRemember = true
        updateCacheValue(cacheModule, "Inventory.Skins", clientSkinUnlockOriginalSkins)
        task.defer(function()
            skinChangerSuppressRemember = false
        end)
    end
    clientSkinUnlockOriginalSkins = nil
    unlockSkinsClientEnabled = false
    return true, 0
end

function buildAllEmoteCache(cacheModule)
    local emotes = cloneSettingsValue(getCacheValue(cacheModule, "Inventory.Emotes", {}) or {})
    if type(emotes) ~= "table" then
        emotes = {}
    end
    local count = 0
    local seen = {}
    local function addEmoteName(name)
        name = tostring(name or "")
        if name == "" or seen[name] then
            return
        end
        seen[name] = true
        local current = emotes[name]
        if type(current) ~= "table" then
            current = {}
        end
        current.Equipped = current.Equipped == true
        current.Sorting = tonumber(current.Sorting) or 999
        emotes[name] = current
        count += 1
    end

    local content = ReplicatedStorage:FindFirstChild("Content")
    local contentEmotes = content and content:FindFirstChild("Emote")
    if contentEmotes then
        for _, emote in ipairs(contentEmotes:GetChildren()) do
            addEmoteName(emote.Name)
        end
    end

    local assets = ReplicatedStorage:FindFirstChild("Assets")
    local assetEmotes = assets and assets:FindFirstChild("Emotes")
    if assetEmotes then
        for _, emote in ipairs(assetEmotes:GetChildren()) do
            addEmoteName(emote.Name)
        end
    end

    return emotes, count
end

function setClientEmoteUnlock(enabled)
    local cacheModule = getClientCache()
    if not cacheModule then
        return false, "Cache unavailable"
    end
    if enabled then
        if not clientEmoteUnlockOriginalEmotes then
            clientEmoteUnlockOriginalEmotes =
                cloneSettingsValue(getCacheValue(cacheModule, "Inventory.Emotes", {}) or {})
        end
        if not clientEmoteUnlockOriginalEquipped then
            clientEmoteUnlockOriginalEquipped =
                cloneSettingsValue(getCacheValue(cacheModule, "Equipped.Emotes", {}) or {})
        end
        local emotes, count = buildAllEmoteCache(cacheModule)
        if count <= 0 then
            return false, "Emote data unavailable"
        end
        updateCacheValue(cacheModule, "Inventory.Emotes", emotes)
        unlockEmotesClientEnabled = true
        if installClientCosmeticActionHooks then
            installClientCosmeticActionHooks()
        end
        return true, count
    end
    if clientEmoteUnlockOriginalEmotes then
        updateCacheValue(cacheModule, "Inventory.Emotes", clientEmoteUnlockOriginalEmotes)
    end
    if clientEmoteUnlockOriginalEquipped then
        updateCacheValue(cacheModule, "Equipped.Emotes", clientEmoteUnlockOriginalEquipped)
    end
    clientEmoteUnlockOriginalEmotes = nil
    clientEmoteUnlockOriginalEquipped = nil
    unlockEmotesClientEnabled = false
    return true, 0
end

function collectContentCosmeticNames(folderName, moduleOnly)
    local names = {}
    local seen = {}
    local function add(name)
        name = tostring(name or "")
        if name == "" or seen[name] then
            return
        end
        seen[name] = true
        table.insert(names, name)
    end

    local content = ReplicatedStorage:FindFirstChild("Content")
    local folder = content and content:FindFirstChild(folderName)
    if folder then
        for _, item in ipairs(folder:GetDescendants()) do
            if moduleOnly then
                if item:IsA("ModuleScript") then
                    add(item.Name)
                end
            elseif item:IsA("ModuleScript") or item:IsA("Folder") or item:IsA("Model") then
                add(item.Name)
            end
        end
        for _, item in ipairs(folder:GetChildren()) do
            if not moduleOnly then
                add(item.Name)
            end
        end
    end

    table.sort(names, function(a, b)
        return tostring(a):lower() < tostring(b):lower()
    end)
    return names, #names
end

function buildStickerCache()
    local list, count = collectContentCosmeticNames("Sticker", true)
    local stickers = {}
    for _, name in ipairs(list) do
        stickers[name] = true
    end
    return stickers, count
end

function setClientCosmeticUnlock(enabled)
    local cacheModule = getClientCache()
    if not cacheModule then
        return false, "Cache unavailable"
    end

    if enabled then
        if not clientCosmeticUnlockOriginals then
            clientCosmeticUnlockOriginals = {
                nametags = cloneSettingsValue(getCacheValue(cacheModule, "Inventory.Nametags", {}) or {}),
                totems = cloneSettingsValue(getCacheValue(cacheModule, "Inventory.Totems", {}) or {}),
                flairs = cloneSettingsValue(getCacheValue(cacheModule, "Inventory.Flairs", {}) or {}),
                stickers = cloneSettingsValue(getCacheValue(cacheModule, "Inventory.Stickers", {}) or {}),
            }
        end
        if not clientCosmeticUnlockOriginalEquipped then
            clientCosmeticUnlockOriginalEquipped = {
                nametag = cloneSettingsValue(getCacheValue(cacheModule, "Equipped.Nametag", "Default") or "Default"),
                totem = cloneSettingsValue(getCacheValue(cacheModule, "Equipped.Totem", "Default") or "Default"),
                flair = cloneSettingsValue(getCacheValue(cacheModule, "Equipped.Flair", "") or ""),
                stickers = cloneSettingsValue(getCacheValue(cacheModule, "Equipped.Stickers", {}) or {}),
            }
        end

        local nametags, nametagCount = collectContentCosmeticNames("Nametag", true)
        local totems, totemCount = collectContentCosmeticNames("Totem", true)
        local flairs, flairCount = collectContentCosmeticNames("Flair", true)
        local stickers, stickerCount = buildStickerCache()
        local total = nametagCount + totemCount + flairCount + stickerCount
        if total <= 0 then
            return false, "Cosmetic data unavailable"
        end

        updateCacheValue(cacheModule, "Inventory.Nametags", nametags)
        task.wait()
        updateCacheValue(cacheModule, "Inventory.Totems", totems)
        task.wait()
        updateCacheValue(cacheModule, "Inventory.Flairs", flairs)
        task.wait()
        updateCacheValue(cacheModule, "Inventory.Stickers", stickers)
        unlockCosmeticsClientEnabled = true
        if installClientCosmeticActionHooks then
            installClientCosmeticActionHooks()
        end
        return true, total
    end

    if clientCosmeticUnlockOriginals then
        updateCacheValue(cacheModule, "Inventory.Nametags", clientCosmeticUnlockOriginals.nametags or {})
        task.wait()
        updateCacheValue(cacheModule, "Inventory.Totems", clientCosmeticUnlockOriginals.totems or {})
        task.wait()
        updateCacheValue(cacheModule, "Inventory.Flairs", clientCosmeticUnlockOriginals.flairs or {})
        task.wait()
        updateCacheValue(cacheModule, "Inventory.Stickers", clientCosmeticUnlockOriginals.stickers or {})
    end
    if clientCosmeticUnlockOriginalEquipped then
        updateCacheValue(cacheModule, "Equipped.Nametag", clientCosmeticUnlockOriginalEquipped.nametag or "Default")
        task.wait()
        updateCacheValue(cacheModule, "Equipped.Totem", clientCosmeticUnlockOriginalEquipped.totem or "Default")
        task.wait()
        updateCacheValue(cacheModule, "Equipped.Flair", clientCosmeticUnlockOriginalEquipped.flair or "")
        task.wait()
        updateCacheValue(cacheModule, "Equipped.Stickers", clientCosmeticUnlockOriginalEquipped.stickers or {})
    end
    clientCosmeticUnlockOriginals = nil
    clientCosmeticUnlockOriginalEquipped = nil
    unlockCosmeticsClientEnabled = false
    return true, 0
end

function skinExists(towerName, skinName)
    skinName = tostring(skinName or "Default")
    if skinName == "Default" then
        return true
    end
    if not skinChangerSupportsTower(towerName) then
        return false
    end
    local skinData = getTowerSkinData(towerName)
    return skinData[skinName] == true
end

function getSkinPickerTowers()
    local list = {}
    local seen = {}
    local content = ReplicatedStorage:FindFirstChild("Content")
    local towerFolder = content and content:FindFirstChild("Tower")
    if towerFolder then
        for _, tower in ipairs(towerFolder:GetChildren()) do
            local statsModule = tower:FindFirstChild("Stats")
            if statsModule then
                local data = safeRequire(statsModule, "Content.Tower.Stats")
                local skinData = data and data.Properties and data.Properties.SkinData
                if
                    type(skinData) == "table"
                    and next(skinData)
                    and not seen[tower.Name]
                    and skinChangerSupportsTower(tower.Name)
                then
                    seen[tower.Name] = true
                    table.insert(list, tower.Name)
                end
            end
        end
    end
    local troops = ReplicatedStorage:FindFirstChild("Assets")
    troops = troops and troops:FindFirstChild("Troops")
    if troops then
        for _, tower in ipairs(troops:GetChildren()) do
            local skins = tower:FindFirstChild("Skins")
            if skins and #skins:GetChildren() > 0 and not seen[tower.Name] and skinChangerSupportsTower(tower.Name) then
                seen[tower.Name] = true
                table.insert(list, tower.Name)
            end
        end
    end
    table.sort(list, function(a, b)
        return tostring(a):lower() < tostring(b):lower()
    end)
    return list
end

function getSkinsForTower(towerName)
    local found = cloneSettingsValue(getTowerSkinData(towerName))
    local list = {}
    for name in pairs(found) do
        table.insert(list, name)
    end
    table.sort(list, function(a, b)
        if a == "Default" then
            return true
        end
        if b == "Default" then
            return false
        end
        return tostring(a):lower() < tostring(b):lower()
    end)
    return list
end

function rememberSkinSelectionsFromCache(cacheModule)
    cacheModule = cacheModule or getClientCache()
    if not cacheModule then
        return 0
    end
    local troops = getCacheValue(cacheModule, "Inventory.Troops", {}) or {}
    local skins = getCacheValue(cacheModule, "Inventory.Skins", {}) or {}
    local saved = 0
    local sawTower = {}
    if type(skins) == "table" then
        for towerName, skinList in pairs(skins) do
            if type(skinList) == "table" then
                for _, skinInfo in pairs(skinList) do
                    if
                        type(skinInfo) == "table"
                        and skinInfo.Equipped == true
                        and not getSavedSkin(towerName)
                        and skinExists(towerName, skinInfo.Name)
                    then
                        setSavedSkin(towerName, skinInfo.Name)
                        sawTower[towerName] = true
                        saved += 1
                        break
                    end
                end
            end
        end
    end
    if type(troops) == "table" then
        for towerName, info in pairs(troops) do
            if
                not sawTower[towerName]
                and not getSavedSkin(towerName)
                and type(info) == "table"
                and skinExists(towerName, info.Skin)
            then
                setSavedSkin(towerName, info.Skin)
                saved += 1
            end
        end
    end
    return saved
end

function applySavedSkinsToCache(cacheModule)
    cacheModule = cacheModule or getClientCache()
    if not cacheModule then
        return false
    end
    local originalTroops = captureSkinChangerOriginalTroops(cacheModule)
    local selections = getSkinSelections()
    local troops = cloneSettingsValue(originalTroops or getCacheValue(cacheModule, "Inventory.Troops", {}) or {})
    local skins = cloneSettingsValue(getCacheValue(cacheModule, "Inventory.Skins", {}) or {})
    skinChangerSuppressRemember = true
    for towerName, skinList in pairs(skins) do
        if not skinChangerSupportsTower(towerName) and type(skinList) == "table" then
            local original = type(originalTroops) == "table" and originalTroops[towerName]
            local originalSkin = type(original) == "table" and original.Skin or "Default"
            for _, skinInfo in ipairs(skinList) do
                if type(skinInfo) == "table" then
                    skinInfo.Equipped = skinInfo.Name == originalSkin
                end
            end
        end
    end
    for towerName, skinName in pairs(selections) do
        if skinChangerSupportsTower(towerName) and skinExists(towerName, skinName) then
            if type(troops[towerName]) == "table" then
                troops[towerName].Skin = skinName
            end
            if type(skins[towerName]) == "table" then
                for _, skinInfo in ipairs(skins[towerName]) do
                    if type(skinInfo) == "table" then
                        skinInfo.Equipped = skinInfo.Name == skinName
                    end
                end
            end
        end
    end
    updateCacheValue(cacheModule, "Inventory.Troops", troops)
    updateCacheValue(cacheModule, "Inventory.Skins", skins)
    task.defer(function()
        skinChangerSuppressRemember = false
    end)
    return true
end

function getTowerInfoSkin(towerInfo)
    if not towerInfo then
        return nil
    end
    if towerInfo.forcedSkinName then
        if
            towerInfo.sourceKind ~= "Unit" and not skinChangerSupportsTower(towerInfo.forcedTowerName or towerInfo.name)
        then
            return nil
        end
        return tostring(towerInfo.forcedSkinName),
            tostring(towerInfo.forcedTowerName or towerInfo.sourceName or towerInfo.name or "")
    end
    if not skinChangerSupportsTower(towerInfo.name) then
        return nil
    end
    local candidates, seen = {}, {}
    local function add(value)
        if type(value) ~= "string" or value == "" or value == "Default" then
            return
        end
        if not seen[value] then
            seen[value] = true
            table.insert(candidates, value)
        end
    end
    add(towerInfo.name)
    local entity = towerInfo.entity
    if type(entity) == "table" then
        add(entity.TowerName)
        add(entity.Name)
        if type(entity.State) == "table" then
            add(entity.State.Type)
            add(entity.State.Name)
        end
        pcall(function()
            add(entity.Replicator and entity.Replicator:Get("Name"))
        end)
        pcall(function()
            add(entity.Replicator and entity.Replicator:Get("Type"))
        end)
    end
    local model = towerInfo.model
    if model then
        add(model:GetAttribute("TowerName"))
        add(model:GetAttribute("Type"))
        add(model:GetAttribute("DisplayName"))
        local towerRep = model:FindFirstChild("TowerReplicator")
        if towerRep then
            add(towerRep:GetAttribute("TowerName"))
            add(towerRep:GetAttribute("Name"))
            add(towerRep:GetAttribute("Type"))
        end
    end
    for _, towerName in ipairs(candidates) do
        local saved = getSavedSkin(towerName)
        if saved and skinExists(towerName, saved) then
            return saved, towerName
        end
    end
    local selections = getSkinSelections()
    for selectedTower, saved in pairs(selections) do
        local selectedKey = settingsLookupKey(selectedTower)
        for _, towerName in ipairs(candidates) do
            if selectedKey == settingsLookupKey(towerName) and skinExists(selectedTower, saved) then
                return saved, selectedTower
            end
        end
    end
    return nil
end

getSkinContentAssetsTroops = nil
function findSkinModelInTroopsFolder(troops, towerName, skinName)
    local tower = troops and troops:FindFirstChild(tostring(towerName or ""))
    local skins = tower and tower:FindFirstChild("Skins")
    local source = skins and skins:FindFirstChild(tostring(skinName or "Default"))
    if typeof(source) == "Instance" then
        return source
    end
    return nil
end
function skinModelAvailableNow(towerName, skinName)
    skinName = tostring(skinName or "Default")
    if skinName == "Default" then
        return true
    end
    if findSkinModelInTroopsFolder(getSkinContentAssetsTroops(), towerName, skinName) then
        return true
    end
    local troops = ReplicatedStorage:FindFirstChild("Assets")
    troops = troops and troops:FindFirstChild("Troops")
    return findSkinModelInTroopsFolder(troops, towerName, skinName) ~= nil
end

function getPlacementSafeSkin(towerName, skinName)
    skinName = tostring(skinName or "Default")
    if skinName == "Default" then
        return "Default"
    end
    if skinExists(towerName, skinName) and skinModelAvailableNow(towerName, skinName) then
        return skinName
    end
    return "Default"
end

function getPreviewPlacementSkin(towerName, fallbackSkin)
    towerName = tostring(towerName or "")
    if not skinChangerSupportsTower(towerName) then
        return getOriginalPlacementSkin(towerName, fallbackSkin)
    end
    local saved = getSavedSkin(towerName)
    if
        skinChangerEnabled
        and saved
        and saved ~= "Default"
        and skinExists(towerName, saved)
        and skinModelAvailableNow(towerName, saved)
    then
        return saved
    end
    return getOriginalPlacementSkin(towerName, fallbackSkin)
end

function patchHotbarPlacementSkin()
    if skinChangerHotbarPatched then
        return true
    end
    local hotbar = safeRequirePath(
        "Client.Modules.LegacyInterfaces.Elements.Hotbar",
        ReplicatedStorage,
        "Client",
        "Modules",
        "LegacyInterfaces",
        "Elements",
        "Hotbar"
    )
    local clicked = hotbar and hotbar.Clicked
    if type(clicked) ~= "table" or type(clicked.Fire) ~= "function" then
        return false
    end
    local mt = getmetatable(clicked)
    local originalFire = clicked.ZephyrOriginalFire or (mt and mt.__index and mt.__index.Fire) or clicked.Fire
    clicked.ZephyrOriginalFire = originalFire
    clicked.ZephyrSkinSafePatched = true
    clicked.Fire = function(self, towerName, skinName, goldenPerks, ...)
        local safeSkin = getPreviewPlacementSkin(towerName, skinName)
        return originalFire(self, towerName, safeSkin, goldenPerks, ...)
    end
    skinChangerHotbarPatched = true
    return true
end

function getTowerUpgradeState(towerInfo)
    local level, path = 0, 0
    pcall(function()
        local rep = towerInfo.entity and towerInfo.entity.Replicator
        if rep then
            level = tonumber(rep:Get("Upgrade")) or level
            path = tonumber(rep:Get("Path")) or path
        end
    end)
    local model = towerInfo and towerInfo.model
    if model then
        local rep = model:FindFirstChild("TowerReplicator")
        if rep then
            level = tonumber(rep:GetAttribute("Upgrade")) or level
            path = tonumber(rep:GetAttribute("Path")) or path
        end
    end
    return level, path
end

function getSkinChangerHumanoidUtil()
    if skinChangerHumanoidUtil ~= false then
        return skinChangerHumanoidUtil
    end
    skinChangerHumanoidUtil =
        safeRequirePath("Shared.Modules.HumanoidUtil", ReplicatedStorage, "Shared", "Modules", "HumanoidUtil")
    if type(skinChangerHumanoidUtil) ~= "table" then
        skinChangerHumanoidUtil = nil
    end
    return skinChangerHumanoidUtil
end

function skinModelHasRigBone(model)
    if not model then
        return false
    end
    for _, inst in ipairs(model:GetDescendants()) do
        if inst:IsA("Bone") and not inst:FindFirstAncestor("BoneVFX") then
            return true
        end
    end
    return false
end

function getSkinAnimationAnimator(clone)
    if not clone then
        return nil
    end
    local humanoidUtil = getSkinChangerHumanoidUtil()
    if humanoidUtil and type(humanoidUtil.createAnimationHost) == "function" then
        local ok, _, animator = pcall(function()
            return humanoidUtil.createAnimationHost(clone, skinModelHasRigBone(clone))
        end)
        if ok and animator then
            return animator
        end
    end
    local controller = clone:FindFirstChild("AnimationController")
    if controller and not controller:IsA("AnimationController") then
        local animator = controller:FindFirstChildOfClass("Animator")
        if animator then
            return animator
        end
        pcall(function()
            controller:Destroy()
        end)
        controller = nil
    end
    if not controller then
        controller = Instance.new("AnimationController")
        controller.Name = "AnimationController"
        controller.Parent = clone
    end
    local animator = controller:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Name = "Animator"
        animator.Parent = controller
    end
    return animator
end

function isRenderableSkinPart(inst)
    if not inst:IsA("BasePart") then
        return false
    end
    if inst.Transparency >= 0.98 then
        return false
    end
    local name = string.lower(inst.Name or "")
    if string.find(name, "hitbox", 1, true) or string.find(name, "range", 1, true) then
        return false
    end
    if string.find(name, "placement", 1, true) or string.find(name, "bounds", 1, true) then
        return false
    end
    return true
end

function skinCloneLooksRenderable(clone)
    if not clone then
        return false
    end
    local parts = 0
    for _, inst in ipairs(clone:GetDescendants()) do
        if isRenderableSkinPart(inst) then
            parts += 1
            if parts >= 2 then
                break
            end
        end
    end
    if parts <= 0 then
        return false
    end
    local ok, size = pcall(function()
        return clone:GetExtentsSize()
    end)
    if not ok or not size then
        return parts > 0
    end
    return size.Magnitude > 0.35
end

function findFirstSkinAnimation(inst)
    if not inst then
        return nil
    end
    if inst:IsA("Animation") then
        return inst
    end
    for _, child in ipairs(inst:GetChildren()) do
        if child:IsA("Animation") then
            return child
        end
    end
    for _, desc in ipairs(inst:GetDescendants()) do
        if desc:IsA("Animation") then
            return desc
        end
    end
    return nil
end

function findSkinAnimationForLevel(group, level, path)
    if not group then
        return nil
    end
    if group:IsA("Animation") then
        return group
    end
    level = math.max(0, math.floor(tonumber(level) or 0))
    path = math.max(0, math.floor(tonumber(path) or 0))
    local pathChar = path > 0 and string.char(96 + math.clamp(path, 1, 26)) or nil
    local best = nil
    for i = 0, level do
        local names = { tostring(i) }
        if pathChar then
            table.insert(names, 1, tostring(i) .. pathChar)
            table.insert(names, 2, tostring(i) .. "_" .. tostring(path))
            table.insert(names, 3, tostring(i) .. "-" .. tostring(path))
        end
        for _, name in ipairs(names) do
            local child = group:FindFirstChild(name)
            local anim = findFirstSkinAnimation(child)
            if anim then
                best = anim
            end
        end
    end
    return best or findFirstSkinAnimation(group)
end

function getSkinCloneTrack(state, animationName)
    if not (state and state.clone) then
        return nil
    end
    animationName = tostring(animationName or "")
    if animationName == "" then
        return nil
    end
    state.tracks = state.tracks or {}
    local key = animationName .. "|" .. tostring(state.level or 0) .. "|" .. tostring(state.path or 0)
    local cached = state.tracks[key]
    if cached then
        return cached
    end
    local animations = state.clone:FindFirstChild("Animations")
    if not animations then
        return nil
    end
    local group = animations:FindFirstChild(animationName)
    if not group and animationName == "Idle" then
        group = animations:FindFirstChild("IdleAnimation") or animations:FindFirstChild("IdleAnim")
    end
    local anim = findSkinAnimationForLevel(group, state.level, state.path)
    if not anim then
        return nil
    end
    local animator = state.animator or getSkinAnimationAnimator(state.clone)
    state.animator = animator
    if not animator then
        return nil
    end
    local ok, track = pcall(function()
        return animator:LoadAnimation(anim)
    end)
    if not ok or not track then
        return nil
    end
    state.tracks[key] = track
    return track
end

function playSkinCloneAnimation(state, animationName, props, args)
    local track = getSkinCloneTrack(state, animationName)
    if not track then
        return false
    end
    pcall(function()
        if type(props) == "table" then
            if props.Priority then
                track.Priority = props.Priority
            end
            if props.Looped ~= nil then
                track.Looped = props.Looped == true
            end
        end
        if tostring(animationName) == "Idle" then
            track.Looped = true
            if state.idleTrack and state.idleTrack ~= track then
                pcall(function()
                    state.idleTrack:Stop(0.08)
                end)
            end
            state.idleTrack = track
            if track.IsPlaying then
                return
            end
        end
        local fadeTime = 0.08
        if type(args) == "table" and tonumber(args[1]) then
            fadeTime = tonumber(args[1])
        end
        track:Play(fadeTime)
        if type(props) == "table" and tonumber(props.Speed) then
            track:AdjustSpeed(tonumber(props.Speed))
        end
    end)
    return true
end

function stopSkinCloneAnimations(state)
    for _, track in pairs(state and state.tracks or {}) do
        pcall(function()
            track:Stop(0.05)
            track:Destroy()
        end)
    end
    for _, track in pairs(state and state.mirroredTracks or {}) do
        pcall(function()
            track:Stop(0.05)
            track:Destroy()
        end)
    end
    if state then
        state.tracks = nil
        state.mirroredTracks = nil
        state.idleTrack = nil
        state.animator = nil
    end
end

function getSkinVisualFolder()
    if skinVisualFolder and skinVisualFolder.Parent then
        return skinVisualFolder
    end
    local existing = workspace:FindFirstChild("ZephyrSkinVisuals")
    if existing and existing:IsA("Folder") then
        skinVisualFolder = existing
    else
        skinVisualFolder = Instance.new("Folder")
        skinVisualFolder.Name = "ZephyrSkinVisuals"
        skinVisualFolder.Parent = workspace
    end
    return skinVisualFolder
end

function getSkinRelativePath(root, inst)
    local parts = {}
    local current = inst
    while current and current ~= root do
        table.insert(parts, 1, current.Name)
        current = current.Parent
    end
    return current == root and parts or nil
end

function findSkinCloneDescendant(state, original)
    if not (state and state.clone and original) then
        return nil
    end
    local path = getSkinRelativePath(state.model, original)
    local current = state.clone
    for _, name in ipairs(path or {}) do
        current = current and current:FindFirstChild(name)
    end
    if current and current.ClassName == original.ClassName then
        return current
    end
    for _, desc in ipairs(state.clone:GetDescendants()) do
        if desc.Name == original.Name and desc.ClassName == original.ClassName then
            return desc
        end
    end
    return nil
end

function findSkinAnimationFromTrack(state, originalTrack)
    if not (state and state.clone and originalTrack) then
        return nil
    end
    local originalAnimation
    pcall(function()
        originalAnimation = originalTrack.Animation
    end)
    if originalAnimation then
        local direct = findSkinCloneDescendant(state, originalAnimation)
        if direct and direct:IsA("Animation") then
            return direct
        end
    end
    local trackName = tostring(originalTrack.Name or "")
    local parentName = originalAnimation and originalAnimation.Parent and originalAnimation.Parent.Name or nil
    local best, bestScore = nil, -1
    for _, desc in ipairs(state.clone:GetDescendants()) do
        if desc:IsA("Animation") then
            local score = 0
            if desc.Name == trackName then
                score += 100
            end
            if originalAnimation and desc.Name == originalAnimation.Name then
                score += 120
            end
            if parentName and desc.Parent and desc.Parent.Name == parentName then
                score += 40
            end
            if score > bestScore then
                best, bestScore = desc, score
            end
        end
    end
    if bestScore > 0 and best then
        return best
    end
    if originalAnimation and originalAnimation:IsA("Animation") then
        return originalAnimation
    end
    return nil
end

function findExactSkinCloneDescendant(state, original)
    if not (state and state.clone and original) then
        return nil
    end
    local current = state.clone
    for _, name in ipairs(getSkinRelativePath(state.model, original) or {}) do
        current = current and current:FindFirstChild(name)
    end
    if current and current.ClassName == original.ClassName then
        return current
    end
    return nil
end

function mirrorSkinAnimationTrack(state, originalTrack)
    if state and state.mirroredTracks and state.mirroredTracks[originalTrack] then
        return
    end
    local animation = findSkinAnimationFromTrack(state, originalTrack)
    if not animation then
        return
    end
    local animator = state.animator or getSkinAnimationAnimator(state.clone)
    state.animator = animator
    if not animator then
        return
    end
    local ok, cloneTrack = pcall(function()
        return animator:LoadAnimation(animation)
    end)
    if not ok or not cloneTrack then
        return
    end
    state.mirroredTracks = state.mirroredTracks or {}
    state.mirroredTracks[originalTrack] = cloneTrack
    pcall(function()
        cloneTrack.Priority = originalTrack.Priority
        cloneTrack.Looped = originalTrack.Looped
        cloneTrack:Play(0.05, originalTrack.WeightCurrent, originalTrack.Speed)
        if originalTrack.TimePosition > 0 then
            cloneTrack.TimePosition = originalTrack.TimePosition
        end
    end)
    local stoppedConn
    stoppedConn = originalTrack.Stopped:Connect(function()
        if stoppedConn then
            stoppedConn:Disconnect()
            stoppedConn = nil
        end
        state.mirroredTracks[originalTrack] = nil
        pcall(function()
            cloneTrack:Stop(0.05)
            cloneTrack:Destroy()
        end)
    end)
    state.connections = state.connections or {}
    table.insert(state.connections, stoppedConn)
end

function syncMirroredSkinAnimations(state)
    if not (state and state.clone and state.clone.Parent) then
        return
    end
    local animator = state.originalAnimator
    if not animator then
        return
    end
    local playing = {}
    local ok, tracks = pcall(function()
        return animator:GetPlayingAnimationTracks()
    end)
    if ok and type(tracks) == "table" then
        for _, track in ipairs(tracks) do
            playing[track] = true
            mirrorSkinAnimationTrack(state, track)
            local cloneTrack = state.mirroredTracks and state.mirroredTracks[track]
            if cloneTrack then
                pcall(function()
                    local speed = tonumber(track.Speed) or 1
                    if not cloneTrack.IsPlaying then
                        cloneTrack:Play(0.03, math.max(tonumber(track.WeightCurrent) or 1, 0.01), speed)
                    end
                    if math.abs((cloneTrack.TimePosition or 0) - (track.TimePosition or 0)) > 0.18 then
                        cloneTrack.TimePosition = track.TimePosition
                    end
                    cloneTrack:AdjustSpeed(speed)
                end)
            end
        end
    end
    for originalTrack, cloneTrack in pairs(state.mirroredTracks or {}) do
        if not playing[originalTrack] then
            state.mirroredTracks[originalTrack] = nil
            pcall(function()
                cloneTrack:Stop(0.05)
                cloneTrack:Destroy()
            end)
        end
    end
end

function observeSkinAnimations(towerInfo, state)
    local entity = towerInfo and towerInfo.entity
    local animator = entity and entity.AnimationAnimator
    if not animator then
        local controller = state.model and state.model:FindFirstChild("AnimationController")
        animator = controller and controller:FindFirstChildOfClass("Animator")
    end
    if not animator then
        return
    end
    state.originalAnimator = animator
    local conn = animator.AnimationPlayed:Connect(function(track)
        mirrorSkinAnimationTrack(state, track)
    end)
    state.connections = state.connections or {}
    table.insert(state.connections, conn)
    pcall(function()
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            mirrorSkinAnimationTrack(state, track)
        end
    end)
end

SKIN_SOUND_ROLE_WORDS = {
    fire = { "fire", "shoot", "shot", "gun", "attack", "blast" },
    reload = { "reload", "outro", "mag", "ammo" },
    spin = { "spin", "wind", "start", "slow", "loop" },
    summon = { "summon", "backup", "call", "spawn" },
    hit = { "hit", "impact", "crit" },
    ability = { "ability", "buff", "heal", "stun" },
    placement = { "place", "placement", "deploy" },
    voice = { "voice", "talk", "dialogue", "line" },
}

function skinSoundText(inst)
    local words = {}
    local current = inst
    local depth = 0
    while current and depth < 5 do
        table.insert(words, string.lower(tostring(current.Name or "")))
        current = current.Parent
        depth += 1
    end
    return table.concat(words, " ")
end

function skinSoundRoles(inst)
    local text = skinSoundText(inst)
    local roles = {}
    for role, words in pairs(SKIN_SOUND_ROLE_WORDS) do
        for _, word in ipairs(words) do
            if string.find(text, word, 1, true) then
                roles[role] = true
                break
            end
        end
    end
    return roles
end

function findMatchingSkinSound(state, original)
    if not (state and state.clone and original and original:IsA("Sound")) then
        return nil
    end
    local direct = findExactSkinCloneDescendant(state, original)
    if direct and direct:IsA("Sound") then
        return direct
    end
    local originalRoles = skinSoundRoles(original)
    local originalName = settingsLookupKey(original.Name)
    local originalParent = original.Parent and settingsLookupKey(original.Parent.Name) or ""
    local best, bestScore = nil, -1
    for _, candidate in ipairs(state.clone:GetDescendants()) do
        if candidate:IsA("Sound") and tostring(candidate.SoundId or "") ~= "" then
            local score = 0
            local candidateName = settingsLookupKey(candidate.Name)
            local candidateParent = candidate.Parent and settingsLookupKey(candidate.Parent.Name) or ""
            if candidateName == originalName then
                score += 150
            end
            if candidateParent ~= "" and candidateParent == originalParent then
                score += 45
            end
            local candidateRoles = skinSoundRoles(candidate)
            for role in pairs(originalRoles) do
                if candidateRoles[role] then
                    score += 70
                end
            end
            if score > bestScore then
                best, bestScore = candidate, score
            end
        end
    end
    return bestScore >= 70 and best or nil
end

function observeSkinSound(state, sound)
    if not (state and sound and sound:IsA("Sound")) or state.observedSounds[sound] then
        return
    end
    local cloneSound = findMatchingSkinSound(state, sound)
    if not (cloneSound and cloneSound:IsA("Sound")) then
        return
    end
    state.observedSounds[sound] = true
    state.originals[sound] = state.originals[sound]
        or {
            soundId = sound.SoundId,
            volume = sound.Volume,
            playbackSpeed = sound.PlaybackSpeed,
            rollOffMinDistance = sound.RollOffMinDistance,
            rollOffMaxDistance = sound.RollOffMaxDistance,
            soundGroup = sound.SoundGroup,
            looped = sound.Looped,
            playbackSpeedAttribute = sound:GetAttribute("PlaybackSpeed"),
        }
    sound.SoundId = cloneSound.SoundId
    sound.Volume = cloneSound.Volume
    sound.PlaybackSpeed = cloneSound.PlaybackSpeed
    sound.RollOffMinDistance = cloneSound.RollOffMinDistance
    sound.RollOffMaxDistance = cloneSound.RollOffMaxDistance
    sound.SoundGroup = cloneSound.SoundGroup
    sound.Looped = cloneSound.Looped
    sound:SetAttribute("PlaybackSpeed", cloneSound:GetAttribute("PlaybackSpeed"))
end

function observeSkinSounds(state)
    state.observedSounds = state.observedSounds or {}
    state.addedOriginals = state.addedOriginals or {}
    for _, cloneSound in ipairs(state.clone:GetDescendants()) do
        if cloneSound:IsA("Sound") then
            local parentPath = getSkinRelativePath(state.clone, cloneSound.Parent)
            local originalParent = state.model
            for _, name in ipairs(parentPath or {}) do
                originalParent = originalParent and originalParent:FindFirstChild(name)
            end
            if originalParent and not originalParent:FindFirstChild(cloneSound.Name) then
                local added = cloneSound:Clone()
                added.Parent = originalParent
                table.insert(state.addedOriginals, added)
            end
        end
    end
    for _, inst in ipairs(state.model:GetDescendants()) do
        if inst:IsA("Sound") then
            observeSkinSound(state, inst)
        end
    end
    for _, ref in ipairs(state.model:GetDescendants()) do
        if ref:IsA("ObjectValue") then
            local cloneRef = findExactSkinCloneDescendant(state, ref)
            local cloneSound = cloneRef and cloneRef:IsA("ObjectValue") and cloneRef.Value
            if cloneSound and cloneSound:IsA("Sound") then
                if ref.Value and ref.Value:IsA("Sound") then
                    observeSkinSound(state, ref.Value)
                else
                    local parentPath = getSkinRelativePath(state.clone, cloneSound.Parent)
                    local originalParent = state.model
                    for _, name in ipairs(parentPath or {}) do
                        originalParent = originalParent and originalParent:FindFirstChild(name)
                    end
                    if originalParent then
                        local added = cloneSound:Clone()
                        added.Parent = originalParent
                        state.originals[ref] = { objectValue = ref.Value, hadObjectValue = true }
                        ref.Value = added
                        table.insert(state.addedOriginals, added)
                    end
                end
            end
        end
    end
end

function resetSkinEntitySoundCaches(towerInfo)
    local entity = towerInfo and towerInfo.entity
    if type(entity) ~= "table" then
        return
    end
    for _, key in ipairs({ "_fireSoundPools", "_soundPools" }) do
        local pools = rawget(entity, key)
        if type(pools) == "table" then
            for _, pool in pairs(pools) do
                pcall(function()
                    if type(pool) == "table" and type(pool.destroy) == "function" then
                        pool:destroy()
                    elseif typeof(pool) == "Instance" then
                        pool:Destroy()
                    end
                end)
            end
            table.clear(pools)
        end
    end
end

NARRATOR_BACKUP_SOUND_IDS = {
    "rbxassetid://78101083824737",
    "rbxassetid://131272723702316",
    "rbxassetid://120421924590141",
    "rbxassetid://114209212300693",
    "rbxassetid://95770416886263",
    "rbxassetid://117333368099188",
    "rbxassetid://77491442289804",
    "rbxassetid://129975062609136",
}
NARRATOR_TALKING_SOUND_ID = "rbxassetid://139228198460919"

function isNarratorCrookSkinName(skinName)
    local key = settingsLookupKey(skinName)
    return key == settingsLookupKey("Narrator") or key == settingsLookupKey("Corso")
end

function isGameMasterCrookSkinName(skinName)
    return settingsLookupKey(skinName) == settingsLookupKey("Game Master")
end

function installSkinSpecialAudio(towerInfo, state)
    local entity = towerInfo and towerInfo.entity
    if type(entity) ~= "table" or not state then
        return
    end
    if settingsLookupKey(state.towerName) ~= settingsLookupKey("Crook Boss") then
        return
    end
    local narratorSkin = isNarratorCrookSkinName(state.skin)
    local gameMasterSkin = isGameMasterCrookSkinName(state.skin)
    if not narratorSkin and not gameMasterSkin then
        return
    end
    if rawget(entity, "skinOverride") ~= nil then
        return
    end
    local executables = rawget(entity, "Executables")
    local original = type(executables) == "table" and executables.CallBackup
    if type(original) ~= "function" then
        return
    end
    local wrapped
    wrapped = function(...)
        local result = original(...)
        if skinVisuals[state.model] == state and state.model and state.model.Parent then
            pcall(function()
                local parent = state.model.PrimaryPart or state.model:FindFirstChildWhichIsA("BasePart", true)
                if parent and narratorSkin then
                    local sound = Instance.new("Sound")
                    sound.SoundId = NARRATOR_BACKUP_SOUND_IDS[math.random(1, #NARRATOR_BACKUP_SOUND_IDS)]
                    sound.Volume = 1
                    sound.Parent = parent
                    local towersGroup = game:GetService("SoundService"):FindFirstChild("Towers")
                    if towersGroup then
                        sound.SoundGroup = towersGroup
                    end
                    sound:Play()
                    game:GetService("Debris"):AddItem(sound, 15)
                    local responseDelay = math.max(tonumber(sound.TimeLength) or 0, 1) * 0.93
                    task.delay(responseDelay, function()
                        if math.random() >= 0.43 then
                            return
                        end
                        for otherModel, otherState in pairs(skinVisuals) do
                            if
                                otherState ~= state
                                and otherModel
                                and otherModel.Parent
                                and settingsLookupKey(otherState.towerName) == settingsLookupKey("Crook Boss")
                                and isNarratorCrookSkinName(otherState.skin)
                            then
                                local otherParent = otherModel.PrimaryPart
                                    or otherModel:FindFirstChildWhichIsA("BasePart", true)
                                if otherParent then
                                    local reply = Instance.new("Sound")
                                    reply.SoundId = NARRATOR_TALKING_SOUND_ID
                                    reply.Volume = 1
                                    reply.Parent = otherParent
                                    if towersGroup then
                                        reply.SoundGroup = towersGroup
                                    end
                                    reply:Play()
                                    game:GetService("Debris"):AddItem(reply, 15)
                                end
                                break
                            end
                        end
                    end)
                elseif parent and gameMasterSkin then
                    local level = 0
                    pcall(function()
                        level = tonumber(entity:GetLevel()) or 0
                    end)
                    local source = state.clone:FindFirstChild(level == 4 and "SummonMax" or "Summon", true)
                        or state.clone:FindFirstChild("Summon", true)
                    if source and source:IsA("Sound") then
                        local sound = source:Clone()
                        sound.Parent = parent
                        local towersGroup = game:GetService("SoundService"):FindFirstChild("Towers")
                        if towersGroup then
                            sound.SoundGroup = towersGroup
                        end
                        sound:Play()
                        game:GetService("Debris"):AddItem(sound, 15)
                    end
                end
            end)
        end
        return result
    end
    executables.CallBackup = wrapped
    state.connections = state.connections or {}
    table.insert(state.connections, {
        Disconnect = function()
            if executables and executables.CallBackup == wrapped then
                executables.CallBackup = original
            end
        end,
    })
end

function getSkinModelFloorPoint(model)
    if not model then
        return nil
    end
    local primary = model.PrimaryPart
        or model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChildWhichIsA("BasePart", true)
    local heightOffset = primary and primary:FindFirstChild("HeightOffset")
    if heightOffset and heightOffset:IsA("Attachment") then
        return heightOffset.WorldPosition
    end
    local lowest = math.huge
    local centerX, centerZ, count = 0, 0, 0
    for _, inst in ipairs(model:GetDescendants()) do
        if
            inst:IsA("BasePart")
            and inst.Transparency < 0.98
            and not string.find(string.lower(inst.Name), "hitbox", 1, true)
            and not string.find(string.lower(inst.Name), "range", 1, true)
        then
            lowest = math.min(lowest, inst.Position.Y - (inst.Size.Y * 0.5))
            centerX += inst.Position.X
            centerZ += inst.Position.Z
            count += 1
        end
    end
    if count > 0 and lowest < math.huge then
        return Vector3.new(centerX / count, lowest, centerZ / count)
    end
    if primary then
        return primary.Position
    end
    return nil
end

function shouldFloorAlignSkinClone(clone, model)
    if not clone then
        return true
    end
    local towerKey = settingsLookupKey(clone:GetAttribute("ZephyrTower") or "")
    if towerKey == settingsLookupKey("Pursuit") then
        return false
    end
    if clone:FindFirstChild("FlightPos", true) or (model and model:FindFirstChild("FlightPos", true)) then
        return false
    end
    return true
end

function alignSkinCloneToModel(clone, model, verticalOffset)
    if not (clone and clone.Parent and model and model.Parent) then
        return
    end
    local appliedOffset = tonumber(verticalOffset)
    pcall(function()
        clone:PivotTo(model:GetPivot())
        if appliedOffset == nil and shouldFloorAlignSkinClone(clone, model) then
            local realFloor = getSkinModelFloorPoint(model)
            local cloneFloor = getSkinModelFloorPoint(clone)
            if realFloor and cloneFloor then
                local deltaY = realFloor.Y - cloneFloor.Y
                if math.abs(deltaY) <= 12 then
                    appliedOffset = deltaY
                end
            end
        end
        if appliedOffset and appliedOffset ~= 0 then
            clone:PivotTo(clone:GetPivot() + Vector3.new(0, appliedOffset, 0))
        end
    end)
    return appliedOffset or 0
end

function isSkinDescendantOfBranch(root, inst, branchName)
    if not (root and inst and branchName) then
        return false
    end
    local branch = root:FindFirstChild(branchName)
    return branch ~= nil and (inst == branch or inst:IsDescendantOf(branch))
end

function shouldPreserveOriginalSkinInstance(state, inst)
    if not (state and inst) then
        return false
    end
    if settingsLookupKey(state.towerName or "") == settingsLookupKey("Gatling Gun") then
        return isSkinDescendantOfBranch(state.model, inst, "Character")
    end
    return false
end

function enforceSkinOriginalHidden(state)
    for inst in pairs(state and state.originals or {}) do
        if inst and inst.Parent and not shouldPreserveOriginalSkinInstance(state, inst) then
            pcall(function()
                if inst:IsA("BasePart") then
                    inst.LocalTransparencyModifier = 1
                elseif inst:IsA("Decal") or inst:IsA("Texture") then
                    inst.Transparency = 1
                elseif inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then
                    inst.Enabled = false
                end
            end)
        end
    end
end

function rememberAndHideSkinOriginal(state, inst)
    if not (state and state.originals and inst) or state.originals[inst] then
        return
    end
    if shouldPreserveOriginalSkinInstance(state, inst) then
        return
    end
    pcall(function()
        if inst:IsA("BasePart") then
            state.originals[inst] = { localTransparency = inst.LocalTransparencyModifier }
            inst.LocalTransparencyModifier = 1
        elseif inst:IsA("Decal") or inst:IsA("Texture") then
            state.originals[inst] = { transparency = inst.Transparency }
            inst.Transparency = 1
        elseif inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then
            state.originals[inst] = { enabled = inst.Enabled }
            inst.Enabled = false
        elseif inst:IsA("Sound") then
            observeSkinSound(state, inst)
        end
    end)
end

function restoreSkinVisual(model)
    local state = skinVisuals[model]
    if not state then
        return
    end
    stopSkinCloneAnimations(state)
    if state.descendantConn then
        state.descendantConn:Disconnect()
        state.descendantConn = nil
    end
    for _, conn in ipairs(state.connections or {}) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    state.connections = nil
    if state.clone and state.clone.Parent then
        pcall(function()
            state.clone:Destroy()
        end)
    end

    for _, inst in ipairs(state.addedOriginals or {}) do
        if inst and inst.Parent then
            pcall(function()
                inst:Destroy()
            end)
        end
    end
    state.addedOriginals = nil
    for inst, props in pairs(state.originals or {}) do
        if inst and inst.Parent then
            pcall(function()
                if inst:IsA("BasePart") then
                    inst.LocalTransparencyModifier = props.localTransparency or 0
                elseif inst:IsA("Decal") or inst:IsA("Texture") then
                    inst.Transparency = props.transparency or 0
                elseif inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then
                    inst.Enabled = props.enabled ~= false
                elseif inst:IsA("Sound") then
                    inst.SoundId = props.soundId or ""
                    inst.Volume = props.volume or 0
                    inst.PlaybackSpeed = props.playbackSpeed or 1
                    inst.RollOffMinDistance = props.rollOffMinDistance or 10
                    inst.RollOffMaxDistance = props.rollOffMaxDistance or 10000
                    inst.SoundGroup = props.soundGroup
                    inst.Looped = props.looped == true
                    inst:SetAttribute("PlaybackSpeed", props.playbackSpeedAttribute)
                elseif inst:IsA("ObjectValue") and props.hadObjectValue then
                    inst.Value = props.objectValue
                end
            end)
        end
    end
    skinVisuals[model] = nil
end

function cleanupStaleSkinVisuals()
    local folder = skinVisualFolder or workspace:FindFirstChild("ZephyrSkinVisuals")
    local aliveClones = {}
    local staleModels = {}
    for model, state in pairs(skinVisuals) do
        if not (model and typeof(model) == "Instance" and model.Parent) then
            table.insert(staleModels, model)
        elseif state and state.clone and state.clone.Parent then
            aliveClones[state.clone] = true
        end
    end
    for _, model in ipairs(staleModels) do
        restoreSkinVisual(model)
    end
    if folder then
        for _, child in ipairs(folder:GetChildren()) do
            if child:GetAttribute("ZephyrSkinClone") and not aliveClones[child] then
                pcall(function()
                    child:Destroy()
                end)
            end
        end
    end
end

function hideOriginalForSkin(model, state)
    local originals = {}
    for _, inst in ipairs(model:GetDescendants()) do
        if shouldPreserveOriginalSkinInstance(state, inst) then
            continue
        elseif inst:IsA("BasePart") then
            originals[inst] = { localTransparency = inst.LocalTransparencyModifier }
            inst.LocalTransparencyModifier = 1
        elseif inst:IsA("Decal") or inst:IsA("Texture") then
            originals[inst] = { transparency = inst.Transparency }
            inst.Transparency = 1
        elseif inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then
            originals[inst] = { enabled = inst.Enabled }
            inst.Enabled = false
        end
    end
    return originals
end

function getSkinContentAssetsTroops()
    if skinContentAssetsTroops ~= false then
        return skinContentAssetsTroops
    end
    local found = nil
    local contentAssets =
        safeRequirePath("Shared.Modules.ContentAssets", ReplicatedStorage, "Shared", "Modules", "ContentAssets")
    if type(contentAssets) == "function" then
        local ok, troops = pcall(function()
            return contentAssets("Troops")
        end)
        if ok and typeof(troops) == "Instance" then
            found = troops
        end
    end
    skinContentAssetsTroops = found or false
    return found
end

function getSkinAssetStreamer()
    if skinAssetStreamer ~= false then
        return skinAssetStreamer
    end
    local streamer = safeRequirePath(
        "Client.Controllers.Shared.AssetStreamingController",
        ReplicatedStorage,
        "Client",
        "Controllers",
        "Shared",
        "AssetStreamingController"
    )
    if type(streamer) ~= "table" then
        streamer = nil
    end
    skinAssetStreamer = streamer or false
    return streamer
end

function findSkinSourceInTroopsFolder(troops, towerName, skinName)
    local tower = troops and troops:FindFirstChild(tostring(towerName or ""))
    local skins = tower and tower:FindFirstChild("Skins")
    local source = skins and skins:FindFirstChild(tostring(skinName or "Default"))
    if typeof(source) == "Instance" then
        return source
    end
    return nil
end

function findStreamingSkinSource(path)
    local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local streaming = playerGui and playerGui:FindFirstChild("Streaming")
    local current = streaming
    for part in tostring(path or ""):gmatch("[^/]+") do
        current = current and current:FindFirstChild(part)
    end
    if typeof(current) == "Instance" then
        return current
    end
    return nil
end

function installSkinSourceForPreview(towerName, skinName, source)
    towerName = tostring(towerName or "")
    skinName = tostring(skinName or "Default")
    if towerName == "" or skinName == "" or skinName == "Default" then
        return source
    end
    if not (source and source.Parent) then
        return source
    end
    local troops = getSkinContentAssetsTroops()
    if not troops then
        local assets = ReplicatedStorage:FindFirstChild("Assets")
        troops = assets and assets:FindFirstChild("Troops")
    end
    local tower = troops and troops:FindFirstChild(towerName)
    local skins = tower and tower:FindFirstChild("Skins")
    if not skins then
        return source
    end
    local existing = skins:FindFirstChild(skinName)
    if existing then
        return existing
    end
    local ok, clone = pcall(function()
        return source:Clone()
    end)
    if not ok or not clone then
        return source
    end
    clone.Name = skinName
    clone.Parent = skins
    return clone
end
function requestSkinSourceAsync(towerName, skinName, key)
    if skinSourcePending[key] then
        return
    end
    skinSourcePending[key] = true
    task.delay(8, function()
        if skinSourcePending[key] then
            skinSourcePending[key] = nil
        end
    end)
    task.spawn(function()
        local path = ("Troops/%s/Skins/%s"):format(tostring(towerName), tostring(skinName))
        local source = findStreamingSkinSource(path)
        if not source then
            local streamer = getSkinAssetStreamer()
            if streamer and type(streamer.getAsset) == "function" then
                local ok, streamed = pcall(function()
                    return streamer.getAsset(path, "ZephyrSkinChanger")
                end)
                if ok and typeof(streamed) == "Instance" then
                    source = streamed
                end
            end
        end
        if not source then
            for _ = 1, 50 do
                task.wait(0.1)
                source = findStreamingSkinSource(path)
                if source then
                    break
                end
            end
        end
        if source and source.Parent then
            source = installSkinSourceForPreview(towerName, skinName, source) or source
            skinSourceCache[key] = source
        else
            skinSourceCache[key] = false
            skinSourceCacheAt[key] = tick()
        end
        skinSourcePending[key] = nil
    end)
end

function getSkinSource(towerName, skinName)
    towerName = tostring(towerName or "")
    skinName = tostring(skinName or "Default")
    local key = towerName .. "\0" .. skinName
    local cached = skinSourceCache[key]
    if typeof(cached) == "Instance" and cached.Parent then
        return installSkinSourceForPreview(towerName, skinName, cached) or cached
    end
    if cached == false and skinSourceCacheAt[key] and tick() - skinSourceCacheAt[key] < 3 then
        return nil
    end

    local source = findSkinSourceInTroopsFolder(getSkinContentAssetsTroops(), towerName, skinName)
    if not source then
        local troops = ReplicatedStorage:FindFirstChild("Assets")
        troops = troops and troops:FindFirstChild("Troops")
        source = findSkinSourceInTroopsFolder(troops, towerName, skinName)
    end
    if not source then
        local path = ("Troops/%s/Skins/%s"):format(towerName, skinName)
        source = findStreamingSkinSource(path)
    end

    if source and source.Parent then
        source = installSkinSourceForPreview(towerName, skinName, source) or source
        skinSourceCache[key] = source
        return source
    end
    requestSkinSourceAsync(towerName, skinName, key)
    return nil
end

function addUnitSkinCandidate(list, seen, value)
    value = tostring(value or "")
    if value == "" or value == "Default" then
        return
    end
    local key = settingsLookupKey(value)
    if key == "" or seen[key] then
        return
    end
    seen[key] = true
    table.insert(list, value)
end

function getUnitSkinsFolder(unitName)
    local assets = ReplicatedStorage:FindFirstChild("Assets")
    local units = assets and assets:FindFirstChild("Units")
    local unit = units and units:FindFirstChild(tostring(unitName or ""))
    return unit and unit:FindFirstChild("Skins") or nil
end

function findUnitSkinSourceDirect(unitName, skinName)
    unitName = tostring(unitName or "")
    skinName = tostring(skinName or "")
    if unitName == "" or skinName == "" or skinName == "Default" then
        return nil
    end
    local key = unitName .. "\0" .. skinName
    local cached = skinUnitSourceCache[key]
    if typeof(cached) == "Instance" and cached.Parent then
        return cached
    end
    if cached == false and skinUnitSourceCacheAt[key] and tick() - skinUnitSourceCacheAt[key] < 3 then
        return nil
    end

    local skins = getUnitSkinsFolder(unitName)
    local source = skins and skins:FindFirstChild(skinName)
    if not source and skins then
        local wanted = settingsLookupKey(skinName)
        for _, child in ipairs(skins:GetChildren()) do
            if settingsLookupKey(child.Name) == wanted then
                source = child
                break
            end
        end
    end
    if typeof(source) == "Instance" and source.Parent then
        skinUnitSourceCache[key] = source
        return source
    end
    skinUnitSourceCache[key] = false
    skinUnitSourceCacheAt[key] = tick()
    return nil
end

function findUnitSkinSourceFuzzy(unitName, skinName)
    local skins = getUnitSkinsFolder(unitName)
    if not skins then
        return nil
    end
    local wanted = settingsLookupKey(skinName)
    if wanted == "" then
        return nil
    end
    local best, bestScore = nil, -1
    for _, child in ipairs(skins:GetChildren()) do
        local key = settingsLookupKey(child.Name)
        if key ~= "" and key ~= "default" then
            local score = 0
            if key == wanted then
                score = 100
            end
            if string.find(wanted, key, 1, true) then
                score = math.max(score, 50)
            end
            if string.find(key, wanted, 1, true) then
                score = math.max(score, 45)
            end
            if score > bestScore then
                best, bestScore = child, score
            end
        end
    end
    return bestScore > 0 and best or nil
end

UNIT_SKIN_SOURCE_CONTAINER_KEYS = {
    units = true,
    unit = true,
    goons = true,
    goon = true,
    bodyguards = true,
    bodyguard = true,
    vehicles = true,
    vehicle = true,
    spawnables = true,
    spawns = true,
    summoned = true,
    summons = true,
}

function skinUnitNameScore(unitName, sourceName)
    local wanted = settingsLookupKey(unitName)
    local key = settingsLookupKey(sourceName)
    if wanted == "" or key == "" then
        return 0
    end
    if key == wanted then
        return 220
    end
    if string.find(key, wanted, 1, true) then
        return 120
    end
    if string.find(wanted, key, 1, true) then
        return 95
    end
    if string.find(wanted, "goon", 1, true) and string.find(key, "goon", 1, true) then
        return 85
    end
    if string.find(wanted, "humvee", 1, true) and string.find(key, "humvee", 1, true) then
        return 85
    end
    if string.find(wanted, "tank", 1, true) and string.find(key, "tank", 1, true) then
        return 85
    end
    if string.find(wanted, "sentry", 1, true) and string.find(key, "sentry", 1, true) then
        return 85
    end
    if string.find(wanted, "mark", 1, true) and string.find(key, "mark", 1, true) then
        return 85
    end
    return 0
end

function sourceContainerBonus(inst)
    local score = 0
    local current = inst and inst.Parent
    local depth = 0
    while current and depth < 5 do
        if UNIT_SKIN_SOURCE_CONTAINER_KEYS[settingsLookupKey(current.Name)] then
            score += 45
        end
        current = current.Parent
        depth += 1
    end
    return score
end

function findUnitSkinSourceInOwnerSkin(ownerTowerName, ownerSkinName, unitName)
    ownerTowerName = tostring(ownerTowerName or "")
    ownerSkinName = tostring(ownerSkinName or "Default")
    if ownerTowerName == "" or ownerSkinName == "" or ownerSkinName == "Default" then
        return nil
    end
    local source = getSkinSource(ownerTowerName, ownerSkinName)
    if not (source and source.Parent) then
        return nil
    end
    local best, bestScore = nil, -1
    for _, inst in ipairs(source:GetDescendants()) do
        if inst:IsA("Model") or inst:IsA("Folder") then
            local score = skinUnitNameScore(unitName, inst.Name)
            if score > 0 then
                score += sourceContainerBonus(inst)
                if inst:FindFirstChildWhichIsA("BasePart", true) then
                    score += 25
                end
                if score > bestScore then
                    best, bestScore = inst, score
                end
            end
        end
    end
    return bestScore >= 85 and best or nil
end

function addUnitNameCandidate(list, seen, value)
    value = tostring(value or "")
    if value == "" then
        return
    end
    local key = settingsLookupKey(value)
    if key == "" or seen[key] then
        return
    end
    seen[key] = true
    table.insert(list, value)
end

function collectUnitSourceNameCandidates(unitName, rule)
    local out, seen = {}, {}
    addUnitNameCandidate(out, seen, unitName)
    local key = settingsLookupKey(unitName)
    if string.find(key, "goon", 1, true) then
        addUnitNameCandidate(out, seen, "Goon1")
        addUnitNameCandidate(out, seen, "Goon2")
        addUnitNameCandidate(out, seen, "Goon3")
    end
    if string.find(key, "humvee", 1, true) then
        addUnitNameCandidate(out, seen, "Humvee")
        addUnitNameCandidate(out, seen, "Humvee 2")
        addUnitNameCandidate(out, seen, "Humvee 3")
    end
    if string.find(key, "tank", 1, true) then
        addUnitNameCandidate(out, seen, "Tank")
        addUnitNameCandidate(out, seen, "Railgun Tank")
    end
    for _, value in ipairs(rule and rule.prefetchUnits or {}) do
        addUnitNameCandidate(out, seen, value)
    end
    return out
end

function installUnitSkinSource(unitName, skinName, source)
    if not (source and source.Parent) then
        return source
    end
    local skins = getUnitSkinsFolder(unitName)
    if not skins then
        return source
    end
    local existing = skins:FindFirstChild(skinName)
    if existing then
        return existing
    end
    local ok, clone = pcall(function()
        return source:Clone()
    end)
    if not ok or not clone then
        return source
    end
    clone.Name = skinName
    clone.Parent = skins
    return clone
end

function requestUnitSkinSourceAsync(unitName, skinName)
    local key = tostring(unitName) .. "\0" .. tostring(skinName)
    local cached = skinUnitSourceCache[key]
    if typeof(cached) == "Instance" and cached.Parent then
        return
    end
    if cached == false and skinUnitSourceCacheAt[key] and tick() - skinUnitSourceCacheAt[key] < 3 then
        return
    end
    if skinUnitSourcePending[key] then
        return
    end
    skinUnitSourcePending[key] = true
    task.delay(8, function()
        if skinUnitSourcePending[key] then
            skinUnitSourcePending[key] = nil
        end
    end)
    task.spawn(function()
        local path = ("Units/%s/Skins/%s"):format(tostring(unitName), tostring(skinName))
        local source = findStreamingSkinSource(path)
        if not source then
            local streamer = getSkinAssetStreamer()
            if streamer and type(streamer.getAsset) == "function" then
                local ok, streamed = pcall(function()
                    return streamer.getAsset(path, "ZephyrUnitSkinChanger")
                end)
                if ok and typeof(streamed) == "Instance" then
                    source = streamed
                end
            end
        end
        if not source then
            for _ = 1, 40 do
                task.wait(0.1)
                source = findStreamingSkinSource(path)
                if source then
                    break
                end
            end
        end
        if source and source.Parent then
            source = installUnitSkinSource(unitName, skinName, source) or source
            skinUnitSourceCache[key] = source
        else
            skinUnitSourceCache[key] = false
            skinUnitSourceCacheAt[key] = tick()
        end
        skinUnitSourcePending[key] = nil
    end)
end

function getUnitSkinSource(unitName, skinName, towerInfo)
    unitName = tostring(unitName or "")
    skinName = tostring(skinName or "Default")
    if unitName == "" or skinName == "" or skinName == "Default" then
        return nil
    end
    local candidates, seen = {}, {}
    addUnitSkinCandidate(candidates, seen, skinName)
    if towerInfo and type(towerInfo.unitSkinCandidates) == "table" then
        for _, candidate in ipairs(towerInfo.unitSkinCandidates) do
            addUnitSkinCandidate(candidates, seen, candidate)
        end
    end
    local unitNames, unitSeen = {}, {}
    addUnitNameCandidate(unitNames, unitSeen, unitName)
    if towerInfo and type(towerInfo.unitSourceCandidates) == "table" then
        for _, candidateName in ipairs(towerInfo.unitSourceCandidates) do
            addUnitNameCandidate(unitNames, unitSeen, candidateName)
        end
    end
    for _, sourceUnitName in ipairs(unitNames) do
        for _, candidate in ipairs(candidates) do
            local source = findUnitSkinSourceDirect(sourceUnitName, candidate)
            if source then
                return source
            end
        end
    end
    for _, sourceUnitName in ipairs(unitNames) do
        for _, candidate in ipairs(candidates) do
            local source = findUnitSkinSourceFuzzy(sourceUnitName, candidate)
            if source then
                return source
            end
        end
    end
    if towerInfo and towerInfo.ownerTowerName then
        for _, sourceUnitName in ipairs(unitNames) do
            for _, candidate in ipairs(candidates) do
                local source = findUnitSkinSourceInOwnerSkin(towerInfo.ownerTowerName, candidate, sourceUnitName)
                if source then
                    return source
                end
            end
        end
    end
    for _, sourceUnitName in ipairs(unitNames) do
        for _, candidate in ipairs(candidates) do
            requestUnitSkinSourceAsync(sourceUnitName, candidate)
        end
    end
    return nil
end

function setSkinCloneBranchHidden(state, branchName, hidden)
    local branch = state and state.clone and state.clone:FindFirstChild(branchName)
    if not branch then
        return
    end
    for _, inst in ipairs(branch:GetDescendants()) do
        pcall(function()
            if inst:IsA("BasePart") then
                inst.LocalTransparencyModifier = hidden and 1 or 0
            elseif inst:IsA("Decal") or inst:IsA("Texture") then
                if hidden then
                    inst.Transparency = 1
                end
            elseif inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
                inst.Enabled = not hidden
            end
        end)
    end
end

TRAPPER_WEAPON_GROUPS = { "SingleSpike", "QuadSpike", "Landmine", "C4", "BearTrap" }

function skinBranchHasVisibleRenderable(branch)
    if not branch then
        return false
    end
    for _, inst in ipairs(branch:GetDescendants()) do
        if inst:IsA("BasePart") then
            if inst.Transparency < 0.98 then
                return true
            end
        elseif inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
            if inst.Enabled then
                return true
            end
        elseif inst:IsA("Decal") or inst:IsA("Texture") then
            if inst.Transparency < 0.98 then
                return true
            end
        end
    end
    return false
end

function setSkinCloneModelLocalHidden(model, hidden)
    if not model then
        return
    end
    for _, inst in ipairs(model:GetDescendants()) do
        pcall(function()
            if inst:IsA("BasePart") then
                inst.LocalTransparencyModifier = hidden and 1 or 0
            elseif inst:IsA("Decal") or inst:IsA("Texture") then
                -- Leave decal transparency alone so hiding the model is reversible.
            elseif inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
                inst.Enabled = not hidden
            end
        end)
    end
end

function syncTrapperSkinWeaponVisibility(state)
    if not (state and state.model and state.clone) then
        return
    end
    if settingsLookupKey(state.towerName or "") ~= settingsLookupKey("Trapper") then
        return
    end
    local realWeapon = state.model:FindFirstChild("Weapon")
    local cloneWeapon = state.clone:FindFirstChild("Weapon")
    if not (realWeapon and cloneWeapon) then
        return
    end
    for _, groupName in ipairs(TRAPPER_WEAPON_GROUPS) do
        local realGroup = realWeapon:FindFirstChild(groupName)
        local cloneGroup = cloneWeapon:FindFirstChild(groupName)
        if cloneGroup then
            setSkinCloneModelLocalHidden(cloneGroup, not skinBranchHasVisibleRenderable(realGroup))
        end
    end
end

function getTrapperWeaponGroupName(trapName, level)
    trapName = tostring(trapName or "")
    level = tonumber(level) or 0
    if trapName == "Spike" then
        return level < 2 and "SingleSpike" or "QuadSpike"
    elseif trapName == "Landmine" then
        return level == 4 and "C4" or "Landmine"
    elseif trapName == "BearTrap" then
        return "BearTrap"
    end
    return nil
end

function cloneTrapperSkinTrapModel(state, trapName, level, fbxModel)
    if not (state and state.clone and state.clone.Parent) then
        return nil
    end
    local groupName = getTrapperWeaponGroupName(trapName, level)
    if not groupName then
        return nil
    end
    local weapon = state.clone:FindFirstChild("Weapon")
    local source = weapon and weapon:FindFirstChild(groupName)
    if not source then
        return nil
    end
    local ok, model = pcall(function()
        return source:Clone()
    end)
    if not ok or not model then
        return nil
    end
    local root
    if fbxModel then
        root = model:FindFirstChild("Main")
    else
        root = model.PrimaryPart
    end
    if not (root and root:IsA("BasePart")) then
        root = model:FindFirstChildWhichIsA("BasePart", true)
        if root and root:IsA("BasePart") then
            model.PrimaryPart = root
        end
    end
    if not root then
        pcall(function()
            model:Destroy()
        end)
        return nil
    end
    root.Anchored = true
    local joint
    if fbxModel then
        joint = root:FindFirstChildWhichIsA("RigidConstraint", true) or root:FindFirstChildOfClass("Motor6D")
    else
        joint = root:FindFirstChild("Handle")
    end
    if joint then
        pcall(function()
            joint:Destroy()
        end)
    end
    setSkinCloneModelLocalHidden(model, false)
    return model, root
end

function applyTrapperSkinTrapModel(state, trapObject)
    if not (state and trapObject and trapObject.trapData) then
        return
    end
    local skinModel, skinRoot = cloneTrapperSkinTrapModel(
        state,
        trapObject.trapData.name,
        trapObject.trapData.level,
        trapObject.fbxModel == true
    )
    if not (skinModel and skinRoot) then
        return
    end
    local oldModel = trapObject.model
    local oldRoot = trapObject.root
    if oldModel and oldModel.Parent then
        skinModel.Parent = oldModel.Parent
        pcall(function()
            skinModel:PivotTo(oldModel:GetPivot())
        end)
    end
    trapObject.model = skinModel
    trapObject.root = skinRoot
    trapObject.rootScale = trapObject.fbxModel and skinRoot.Size or 1
    trapObject._originalSize = skinRoot.Size
    if trapObject.rawPosition and skinRoot:FindFirstChild("Floor") then
        pcall(function()
            trapObject.position = trapObject.rawPosition - skinRoot.Floor.Position
        end)
    end
    if oldRoot and oldRoot:IsA("BasePart") then
        pcall(function()
            skinRoot.CFrame = oldRoot.CFrame
            skinRoot.Transparency = oldRoot.Transparency
        end)
    end
    if oldModel and oldModel ~= skinModel then
        pcall(function()
            oldModel:Destroy()
        end)
    end
end

function installTrapperTrapSourcePatch(towerInfo, state)
    local entity = towerInfo and towerInfo.entity
    if type(entity) ~= "table" or not state then
        return
    end
    if settingsLookupKey(state.towerName or "") ~= settingsLookupKey("Trapper") then
        return
    end
    if type(entity._createTrap) ~= "function" then
        return
    end
    local original = rawget(entity, "__zephyrOriginalCreateTrap") or entity._createTrap
    rawset(entity, "__zephyrOriginalCreateTrap", original)
    local wrapped
    wrapped = function(self, ...)
        local ok, result = pcall(original, self, ...)
        if ok and result and skinVisuals[state.model] == state then
            pcall(function()
                applyTrapperSkinTrapModel(state, result)
            end)
        end
        if ok then
            return result
        end
        error(result)
    end
    entity._createTrap = wrapped
    state.connections = state.connections or {}
    table.insert(state.connections, {
        Disconnect = function()
            if entity and entity._createTrap == wrapped then
                entity._createTrap = original
            end
            if entity and rawget(entity, "__zephyrOriginalCreateTrap") == original then
                rawset(entity, "__zephyrOriginalCreateTrap", nil)
            end
        end,
    })
end

function buildSkinCloneSyncMaps(state)
    state.transformPairs = {}
    state.gatlingWeaponPairs = {}
    state.visibilityPairs = {}
    local towerKey = settingsLookupKey(state.towerName or "")
    local isGatling = settingsLookupKey(state.towerName or "") == settingsLookupKey("Gatling Gun")
    local syncVisibility = towerKey == settingsLookupKey("Trapper")
    local modelPivot = state.model:GetPivot()
    local clonePivot = state.clone:GetPivot()
    for _, original in ipairs(state.model:GetDescendants()) do
        local cloneInst = findSkinCloneDescendant(state, original)
        if cloneInst then
            if
                (original:IsA("Motor6D") and cloneInst:IsA("Motor6D"))
                or (original:IsA("Bone") and cloneInst:IsA("Bone"))
            then
                table.insert(state.transformPairs, { original = original, clone = cloneInst })
            elseif
                isGatling
                and original:IsA("BasePart")
                and cloneInst:IsA("BasePart")
                and isSkinDescendantOfBranch(state.model, original, "Weapon")
            then
                table.insert(state.gatlingWeaponPairs, {
                    original = original,
                    clone = cloneInst,
                    originalRelative = modelPivot:ToObjectSpace(original.CFrame),
                    cloneRelative = clonePivot:ToObjectSpace(cloneInst.CFrame),
                })
            end
            if
                syncVisibility
                and (
                    (original:IsA("BasePart") and cloneInst:IsA("BasePart"))
                    or ((original:IsA("Decal") or original:IsA("Texture")) and cloneInst.ClassName == original.ClassName)
                    or (
                        (original:IsA("ParticleEmitter") or original:IsA("Beam") or original:IsA("Trail"))
                        and cloneInst.ClassName == original.ClassName
                    )
                )
            then
                table.insert(state.visibilityPairs, { original = original, clone = cloneInst })
            end
        end
    end
end

function syncSkinCloneModelState(state)
    if not (state and state.model and state.model.Parent and state.clone and state.clone.Parent) then
        return
    end
    local cloneTrackPlaying = false
    for _, track in pairs(state.tracks or {}) do
        local ok, playing = pcall(function()
            return track and track.IsPlaying
        end)
        if ok and playing then
            cloneTrackPlaying = true
            break
        end
    end
    if not cloneTrackPlaying then
        for _, track in pairs(state.mirroredTracks or {}) do
            local ok, playing = pcall(function()
                return track and track.IsPlaying
            end)
            if ok and playing then
                cloneTrackPlaying = true
                break
            end
        end
    end
    if not cloneTrackPlaying then
        for _, pair in ipairs(state.transformPairs or {}) do
            if pair.original.Parent and pair.clone.Parent then
                pcall(function()
                    pair.clone.Transform = pair.original.Transform
                end)
            end
        end
    end
    local towerKey = settingsLookupKey(state.towerName or "")
    for _, pair in ipairs(state.visibilityPairs or {}) do
        local original, cloneInst = pair.original, pair.clone
        if original and original.Parent and cloneInst and cloneInst.Parent then
            pcall(function()
                if original:IsA("BasePart") and cloneInst:IsA("BasePart") then
                    cloneInst.Transparency = original.Transparency
                elseif
                    (original:IsA("Decal") or original:IsA("Texture"))
                    and (cloneInst:IsA("Decal") or cloneInst:IsA("Texture"))
                then
                    cloneInst.Transparency = original.Transparency
                elseif
                    (original:IsA("ParticleEmitter") or original:IsA("Beam") or original:IsA("Trail"))
                    and cloneInst.ClassName == original.ClassName
                then
                    cloneInst.Enabled = original.Enabled
                end
            end)
        end
    end
    if towerKey == settingsLookupKey("Gatling Gun") then
        setSkinCloneBranchHidden(state, "Character", true)
        local modelPivot = state.model:GetPivot()
        local clonePivot = state.clone:GetPivot()
        for _, pair in ipairs(state.gatlingWeaponPairs or {}) do
            if pair.original.Parent and pair.clone.Parent then
                pcall(function()
                    local currentRelative = modelPivot:ToObjectSpace(pair.original.CFrame)
                    local motion = pair.originalRelative:ToObjectSpace(currentRelative)
                    pair.clone.CFrame = clonePivot * pair.cloneRelative * motion
                end)
            end
        end
    end
    syncTrapperSkinWeaponVisibility(state)
end

function getSkinUnitReplicator()
    if skinUnitReplicator ~= false then
        return skinUnitReplicator
    end
    skinUnitReplicator = safeRequirePath(
        "Client.Modules.Replicators.UnitReplicator",
        ReplicatedStorage,
        "Client",
        "Modules",
        "Replicators",
        "UnitReplicator"
    )
    if type(skinUnitReplicator) ~= "table" then
        skinUnitReplicator = nil
    end
    return skinUnitReplicator
end

function prefetchSavedSkinSources()
    local selections = getSkinSelections()
    local streamer = getSkinAssetStreamer()
    local requests, keys = {}, {}
    for towerName, skinName in pairs(selections) do
        towerName = tostring(towerName or "")
        skinName = tostring(skinName or "Default")
        if towerName ~= "" and skinName ~= "" and skinName ~= "Default" and skinExists(towerName, skinName) then
            local key = towerName .. "\0" .. skinName
            local cached = skinSourceCache[key]
            if not skinSourcePending[key] and not (typeof(cached) == "Instance" and cached.Parent) then
                local path = ("Troops/%s/Skins/%s"):format(towerName, skinName)
                skinSourcePending[key] = true
                task.delay(8, function()
                    if skinSourcePending[key] then
                        skinSourcePending[key] = nil
                    end
                end)
                table.insert(keys, key)
                table.insert(requests, { path = path, context = "ZephyrSkinChanger" })
            end
        end
    end
    if #requests == 0 then
        return
    end
    task.spawn(function()
        if streamer and type(streamer.getAssets) == "function" then
            local ok, assets = pcall(function()
                return streamer.getAssets(requests)
            end)
            if ok and type(assets) == "table" then
                for index, source in pairs(assets) do
                    local key = keys[index]
                    if key and typeof(source) == "Instance" and source.Parent then
                        local towerName, skinName = string.match(key, "^([^%z]+)%z(.+)$")
                        source = installSkinSourceForPreview(towerName, skinName, source) or source
                        skinSourceCache[key] = source
                    end
                end
            end
        else
            for index, request in ipairs(requests) do
                local key = keys[index]
                local source = findStreamingSkinSource(request.path)
                if key and source and source.Parent then
                    local towerName, skinName = string.match(key, "^([^%z]+)%z(.+)$")
                    source = installSkinSourceForPreview(towerName, skinName, source) or source
                    skinSourceCache[key] = source
                end
            end
        end
        for _, key in ipairs(keys) do
            local cached = skinSourceCache[key]
            if not (typeof(cached) == "Instance" and cached.Parent) then
                skinSourceCache[key] = false
                skinSourceCacheAt[key] = tick()
            end
            skinSourcePending[key] = nil
        end
    end)
end
function cleanupSkinCloneDuplicateFaces(clone)
    if not clone then
        return
    end
    local heads = {}
    for _, inst in ipairs(clone:GetDescendants()) do
        if (inst:IsA("Decal") or inst:IsA("Texture")) and inst.Transparency < 0.98 then
            local parent = inst.Parent
            local parentKey = settingsLookupKey(parent and parent.Name or "")
            local nameKey = settingsLookupKey(inst.Name)
            local isHeadFace = parentKey == "head" or string.find(parentKey, "head", 1, true) ~= nil
            local isFaceLayer = nameKey == "face"
                or string.find(nameKey, "eye", 1, true) ~= nil
                or string.find(nameKey, "mouth", 1, true) ~= nil
                or string.find(nameKey, "brow", 1, true) ~= nil
                or string.find(nameKey, "expression", 1, true) ~= nil
            if isHeadFace and isFaceLayer then
                heads[parent] = heads[parent] or {}
                table.insert(heads[parent], inst)
            end
        end
    end
    for _, layers in pairs(heads) do
        local customLayers = 0
        local faceLayers = {}
        for _, layer in ipairs(layers) do
            local key = settingsLookupKey(layer.Name)
            if key == "face" then
                table.insert(faceLayers, layer)
            else
                customLayers += 1
            end
        end
        if customLayers > 0 then
            for _, face in ipairs(faceLayers) do
                pcall(function()
                    face.Transparency = 1
                end)
            end
        elseif #faceLayers > 1 then
            local keep = faceLayers[#faceLayers]
            for _, face in ipairs(faceLayers) do
                if face ~= keep then
                    pcall(function()
                        face.Transparency = 1
                    end)
                end
            end
        end
    end
end
function makeSkinClone(towerName, skinName, towerInfo)
    local source
    if towerInfo and towerInfo.sourceKind == "Unit" then
        source = getUnitSkinSource(towerInfo.sourceName or towerName, skinName, towerInfo)
    else
        source = getSkinSource(towerName, skinName)
    end
    if not source then
        return nil
    end

    local clone
    if source:IsA("Model") then
        clone = source:Clone()
    else
        clone = Instance.new("Model")
        clone.Name = source.Name
        for _, child in ipairs(source:GetChildren()) do
            child:Clone().Parent = clone
        end
    end
    clone.Name = tostring(source.Name ~= "" and source.Name or skinName)
    clone:SetAttribute("ZephyrSkinClone", true)
    clone:SetAttribute("ZephyrTower", tostring(towerName))
    clone:SetAttribute("ZephyrSkin", tostring(skinName))
    local primary = clone.PrimaryPart
        or clone:FindFirstChild("HumanoidRootPart")
        or clone:FindFirstChildWhichIsA("BasePart", true)
    if primary and primary:IsA("BasePart") then
        clone.PrimaryPart = primary
    end
    for _, inst in ipairs(clone:GetDescendants()) do
        if inst:IsA("BasePart") then
            inst.CanCollide = false
            inst.CanTouch = false
            inst.CanQuery = false
            inst.Massless = true
        elseif inst:IsA("Script") or inst:IsA("LocalScript") then
            inst.Disabled = true
        end
    end
    cleanupSkinCloneDuplicateFaces(clone)
    return clone
end

function runSkinCloneUpgrades(clone, towerInfo, level, path)
    if towerInfo and towerInfo.sourceKind == "Unit" then
        return
    end
    if not (clone and clone.Parent) then
        return
    end
    if not clone:FindFirstChild("UpgradesModule") then
        return
    end
    local upgrades = safeRequirePath("Shared.Modules.Upgrades", ReplicatedStorage, "Shared", "Modules", "Upgrades")
    if type(upgrades) ~= "table" or type(upgrades.upgrade) ~= "function" then
        return
    end
    local fake = {
        Model = clone,
        Name = tostring(towerInfo.name or ""),
        Path = tonumber(path) or 0,
        OnUpgrade = { Fire = function() end },
        CreateVisualizer = function() end,
    }
    for i = 1, math.max(0, tonumber(level) or 0) do
        pcall(function()
            upgrades.upgrade(fake, i, "tower")
        end)
    end
end

function applySkinVisual(towerInfo)
    local model = towerInfo and towerInfo.model
    if not (model and model.Parent) then
        return
    end
    local skinName, resolvedTowerName = getTowerInfoSkin(towerInfo)
    local towerName = tostring(resolvedTowerName or towerInfo.name or "")
    if not skinName or skinName == "Default" then
        restoreSkinVisual(model)
        return
    end
    local level, path = getTowerUpgradeState(towerInfo)
    local state = skinVisuals[model]
    if state and state.skin == skinName and state.level == level and state.path == path then
        if state.clone and state.clone.Parent then
            alignSkinCloneToModel(state.clone, model, state.alignYOffset)

            enforceSkinOriginalHidden(state)
            return
        end
        restoreSkinVisual(model)
    end
    if skinVisuals[model] then
        restoreSkinVisual(model)
    end
    local clone = makeSkinClone(towerName, skinName, towerInfo)
    if not clone then
        return
    end
    clone.Parent = getSkinVisualFolder()
    runSkinCloneUpgrades(clone, towerInfo, level, path)
    local alignYOffset = alignSkinCloneToModel(clone, model)
    if not skinCloneLooksRenderable(clone) then
        pcall(function()
            clone:Destroy()
        end)
        return
    end

    local newState = {
        model = model,
        towerName = towerName,
        sourceKind = towerInfo and towerInfo.sourceKind,
        skin = skinName,

        level = level,
        path = path,
        clone = clone,
        alignYOffset = alignYOffset,
        originals = {},
        observedSounds = {},
        connections = {},
    }
    newState.originals = hideOriginalForSkin(model, newState)
    skinVisuals[model] = newState
    buildSkinCloneSyncMaps(newState)
    syncSkinCloneModelState(newState)
    newState.descendantConn = model.DescendantAdded:Connect(function(inst)
        rememberAndHideSkinOriginal(newState, inst)
    end)
    observeSkinAnimations(towerInfo, newState)
    observeSkinSounds(newState)
    resetSkinEntitySoundCaches(towerInfo)
    installSkinSpecialAudio(towerInfo, newState)
    installTrapperTrapSourcePatch(towerInfo, newState)
    if not next(newState.mirroredTracks or {}) then
        playSkinCloneAnimation(newState, "Idle", { Priority = Enum.AnimationPriority.Core })
    end
end

SPAWNED_UNIT_SKIN_RULES = {
    {
        owner = "Crook Boss",
        prefetchUnits = { "Goon1", "Goon2", "Goon3" },
        units = { Goon1 = true, Goon2 = true, Goon3 = true, goon1 = true, goon2 = true, goon3 = true },
        aliases = {
            corso = { "Corso", "Narrator", "Narrator Crook Boss", "Corso Crook Boss" },
            narrator = { "Narrator", "Narrator Crook Boss" },
            gamemaster = { "Game Master" },
        },
    },
    {
        owner = "Military Base",
        prefetchUnits = { "Humvee", "Humvee 2", "Humvee 3", "Tank", "Railgun Tank" },
        units = {
            Humvee = true,
            humvee = true,
            ["Humvee 2"] = true,
            humvee2 = true,
            ["Humvee 3"] = true,
            humvee3 = true,
            Tank = true,
            tank = true,
            ["Railgun Tank"] = true,
            railguntank = true,
        },
    },
    {
        owner = "Engineer",
        prefetchUnits = { "Sentry1", "Sentry2", "Sentry3", "Sentry4" },
        units = {
            Sentry1 = true,
            sentry1 = true,
            Sentry2 = true,
            sentry2 = true,
            Sentry3 = true,
            sentry3 = true,
            Sentry4 = true,
            sentry4 = true,
        },
    },
    {
        owner = "Mecha Base",
        prefetchUnits = { "Mark1", "Mark1Rocket", "Mark2", "Mark3", "Mark4", "Mark5" },
        units = {
            Mark1 = true,
            mark1 = true,
            Mark1Rocket = true,
            mark1rocket = true,
            Mark2 = true,
            mark2 = true,
            Mark3 = true,
            mark3 = true,
            Mark4 = true,
            mark4 = true,
            Mark5 = true,
            mark5 = true,
        },
    },
}
CROOK_BOSS_GOON_KEYS = { goon1 = "Goon1", goon2 = "Goon2", goon3 = "Goon3" }

function prefetchSpawnedUnitSkinSources()
    for _, rule in ipairs(SPAWNED_UNIT_SKIN_RULES) do
        local ownerSkin = getSavedSkin(rule.owner)
        if ownerSkin and ownerSkin ~= "Default" then
            local candidates, seen = {}, {}
            addUnitSkinCandidate(candidates, seen, ownerSkin)
            local aliases = rule.aliases and rule.aliases[settingsLookupKey(ownerSkin)]
            if type(aliases) == "table" then
                for _, alias in ipairs(aliases) do
                    addUnitSkinCandidate(candidates, seen, alias)
                end
            end
            for _, unitName in ipairs(rule.prefetchUnits or {}) do
                for _, candidate in ipairs(candidates) do
                    requestUnitSkinSourceAsync(unitName, candidate)
                end
            end
        end
    end
end

function spawnedRuleMatchesUnit(rule, unitName)
    if not (rule and type(rule.units) == "table") then
        return false
    end
    unitName = tostring(unitName or "")
    local key = settingsLookupKey(unitName)
    if rule.units[unitName] == true or rule.units[key] == true then
        return true
    end
    local ownerKey = settingsLookupKey(rule.owner)
    if ownerKey == settingsLookupKey("Crook Boss") then
        return string.find(key, "goon", 1, true) ~= nil
            or string.find(key, "bodyguard", 1, true) ~= nil
            or string.find(key, "crook", 1, true) ~= nil
    elseif ownerKey == settingsLookupKey("Military Base") then
        return string.find(key, "humvee", 1, true) ~= nil
            or string.find(key, "tank", 1, true) ~= nil
            or string.find(key, "railgun", 1, true) ~= nil
            or string.find(key, "apc", 1, true) ~= nil
            or string.find(key, "vehicle", 1, true) ~= nil
    elseif ownerKey == settingsLookupKey("Engineer") then
        return string.find(key, "sentry", 1, true) ~= nil
    elseif ownerKey == settingsLookupKey("Mecha Base") then
        return string.find(key, "mark", 1, true) ~= nil or string.find(key, "mecha", 1, true) ~= nil
    end
    return false
end

function collectSpawnedUnitSkinCandidates(model, entity, ownerSkin, rule)
    local candidates, seen = {}, {}
    addUnitSkinCandidate(candidates, seen, ownerSkin)
    local aliases = rule and rule.aliases and rule.aliases[settingsLookupKey(ownerSkin)]
    if type(aliases) == "table" then
        for _, alias in ipairs(aliases) do
            addUnitSkinCandidate(candidates, seen, alias)
        end
    end
    if type(entity) == "table" then
        pcall(function()
            local rep = entity.Replicator
            if rep then
                addUnitSkinCandidate(candidates, seen, rep:Get("Skin"))
                addUnitSkinCandidate(candidates, seen, rep:Get("SkinName"))
                addUnitSkinCandidate(candidates, seen, rep:Get("UnitSkin"))
                addUnitSkinCandidate(candidates, seen, rep:Get("UnitSkinName"))
            end
        end)
    end
    if model then
        addUnitSkinCandidate(candidates, seen, model:GetAttribute("Skin"))
        addUnitSkinCandidate(candidates, seen, model:GetAttribute("SkinName"))
        addUnitSkinCandidate(candidates, seen, model:GetAttribute("UnitSkin"))
        local pointer = model:FindFirstChild("RootPointer")
        if pointer and pointer:IsA("ObjectValue") and pointer.Value then
            addUnitSkinCandidate(candidates, seen, pointer.Value:GetAttribute("Skin"))
            addUnitSkinCandidate(candidates, seen, pointer.Value:GetAttribute("SkinName"))
            addUnitSkinCandidate(candidates, seen, pointer.Value:GetAttribute("UnitSkin"))
        end
    end
    return candidates
end

function resolveSkinUnitName(model)
    local name = tostring(model and model.Name or "")
    local entity = nil
    local pointer = model and model:FindFirstChild("RootPointer")
    if pointer and pointer:IsA("ObjectValue") and pointer.Value then
        local replicator = getSkinUnitReplicator()
        if replicator and type(replicator.GetNPCFromFolder) == "function" then
            pcall(function()
                entity = replicator.GetNPCFromFolder(pointer.Value)
            end)
        end
    end
    if type(entity) == "table" then
        name = tostring(entity.Name or name)
        pcall(function()
            local rep = entity.Replicator
            local modelName = rep and (rep:Get("ModelName") or rep:Get("DisplayName"))
            if type(modelName) == "string" and modelName ~= "" then
                name = modelName
            end
        end)
    end
    local key = settingsLookupKey(name)
    return CROOK_BOSS_GOON_KEYS[key] or name, entity
end

function getExtraSkinUnitEntities()
    local out = {}
    local unitsFolder = workspace:FindFirstChild("ClientUnits")
    if not unitsFolder then
        return out
    end
    for _, model in ipairs(unitsFolder:GetChildren()) do
        if model:IsA("Model") then
            local unitName, entity = resolveSkinUnitName(model)
            for _, rule in ipairs(SPAWNED_UNIT_SKIN_RULES) do
                if spawnedRuleMatchesUnit(rule, unitName) then
                    local ownerSkin = getSavedSkin(rule.owner)
                    if ownerSkin and ownerSkin ~= "Default" then
                        local towerInfo = {
                            model = model,
                            entity = entity,
                            name = unitName,
                            sourceKind = "Unit",
                            sourceName = unitName,
                            forcedTowerName = unitName,
                            forcedSkinName = ownerSkin,
                            ownerTowerName = rule.owner,
                            ownerSkinName = ownerSkin,
                            unitSkinCandidates = collectSpawnedUnitSkinCandidates(model, entity, ownerSkin, rule),
                            unitSourceCandidates = collectUnitSourceNameCandidates(unitName, rule),
                        }
                        if getUnitSkinSource(unitName, ownerSkin, towerInfo) then
                            table.insert(out, towerInfo)
                            break
                        end
                    end
                end
            end
        end
    end
    return out
end

function refreshSkinVisuals()
    local seen = {}
    for _, towerInfo in ipairs(getOwnedTowerEntities()) do
        if towerInfo.model then
            seen[towerInfo.model] = true
            applySkinVisual(towerInfo)
        end
    end
    for _, towerInfo in ipairs(getExtraSkinUnitEntities()) do
        if towerInfo.model then
            seen[towerInfo.model] = true
            applySkinVisual(towerInfo)
        end
    end
    for model in pairs(skinVisuals) do
        if not seen[model] or not (model and model.Parent) then
            restoreSkinVisual(model)
        end
    end
    cleanupStaleSkinVisuals()
end

function startSkinChanger()
    if skinChangerThread then
        return true
    end
    patchHotbarPlacementSkin()
    local selections = getSkinSelections()
    local removedBlockedSelection = false
    for towerName in pairs(selections) do
        if not skinChangerSupportsTower(towerName) then
            selections[towerName] = nil
            removedBlockedSelection = true
        end
    end
    if removedBlockedSelection then
        saveSettingsSoon()
    end
    local cacheModule = getClientCache()
    if cacheModule then
        captureSkinChangerOriginalTroops(cacheModule)
        rememberSkinSelectionsFromCache(cacheModule)
        applySavedSkinsToCache(cacheModule)
        prefetchSavedSkinSources()
        prefetchSpawnedUnitSkinSources()
        local troopsCache = cacheModule("Inventory.Troops")
        local skinsCache = cacheModule("Inventory.Skins")
        if troopsCache and troopsCache.Updated and type(troopsCache.Updated.Connect) == "function" then
            skinChangerCacheConn = troopsCache.Updated:Connect(function()
                if skinChangerSuppressRemember then
                    return
                end
                skinChangerOriginalTroops = nil
                captureSkinChangerOriginalTroops(cacheModule)
                rememberSkinSelectionsFromCache(cacheModule)
                task.defer(function()
                    if skinChangerEnabled then
                        applySavedSkinsToCache(cacheModule)
                    end
                end)
            end)
        end
        if skinsCache and skinsCache.Updated and type(skinsCache.Updated.Connect) == "function" then
            skinChangerSkinCacheConn = skinsCache.Updated:Connect(function()
                if skinChangerSuppressRemember then
                    return
                end
                rememberSkinSelectionsFromCache(cacheModule)
                task.defer(function()
                    if skinChangerEnabled then
                        applySavedSkinsToCache(cacheModule)
                    end
                end)
            end)
        end
    end
    skinChangerEnabled = true
    cleanupStaleSkinVisuals()
    refreshSkinVisuals()
    local towersFolder = workspace:FindFirstChild("Towers")
    if towersFolder and not skinChangerTowerConn then
        skinChangerTowerConn = towersFolder.ChildAdded:Connect(function()
            task.defer(function()
                if skinChangerEnabled then
                    refreshSkinVisuals()
                end
            end)
            task.delay(0.15, function()
                if skinChangerEnabled then
                    refreshSkinVisuals()
                end
            end)
        end)
    end
    local unitsFolder = workspace:FindFirstChild("ClientUnits")
    if unitsFolder and not skinChangerUnitConn then
        skinChangerUnitConn = unitsFolder.ChildAdded:Connect(function()
            task.defer(function()
                if skinChangerEnabled then
                    refreshSkinVisuals()
                end
            end)
            task.delay(0.15, function()
                if skinChangerEnabled then
                    refreshSkinVisuals()
                end
            end)
        end)
    end
    if not skinChangerUnitFolderConn then
        skinChangerUnitFolderConn = workspace.ChildAdded:Connect(function(child)
            if child.Name ~= "ClientUnits" then
                return
            end
            task.defer(function()
                if not skinChangerEnabled then
                    return
                end
                if skinChangerUnitConn then
                    skinChangerUnitConn:Disconnect()
                    skinChangerUnitConn = nil
                end
                skinChangerUnitConn = child.ChildAdded:Connect(function()
                    task.defer(function()
                        if skinChangerEnabled then
                            refreshSkinVisuals()
                        end
                    end)
                    task.delay(0.15, function()
                        if skinChangerEnabled then
                            refreshSkinVisuals()
                        end
                    end)
                end)
                refreshSkinVisuals()
            end)
        end)
    end
    skinChangerThread = task.spawn(function()
        local nextRefreshAt = 0
        while skinChangerEnabled do
            local now = tick()
            if now >= nextRefreshAt then
                nextRefreshAt = now + 0.5
                refreshSkinVisuals()
            end
            for model, state in pairs(skinVisuals) do
                if state and state.clone and state.clone.Parent and model and model.Parent then
                    local movingUnit = state.sourceKind == "Unit"
                    if not state.nextAlignAt or now >= state.nextAlignAt then
                        state.nextAlignAt = now + (movingUnit and 0.035 or 0.15)
                        alignSkinCloneToModel(state.clone, model, state.alignYOffset)
                    end
                    if not state.nextAnimSyncAt or now >= state.nextAnimSyncAt then
                        state.nextAnimSyncAt = now + 0.08
                        syncMirroredSkinAnimations(state)
                    end
                    if not state.nextModelSyncAt or now >= state.nextModelSyncAt then
                        state.nextModelSyncAt = now + (movingUnit and 0.05 or 0.1)
                        syncSkinCloneModelState(state)
                    end
                    if not state.nextHideAt or now >= state.nextHideAt then
                        state.nextHideAt = now + 0.2
                        enforceSkinOriginalHidden(state)
                    end
                end
            end
            task.wait(0.03)
        end
        skinChangerThread = nil
    end)
    return true
end

function stopSkinChanger()
    skinChangerEnabled = false
    local cacheModule = getClientCache()
    if cacheModule then
        restoreSkinChangerTroopCache(cacheModule)
    end
    skinChangerOriginalTroops = nil
    if skinChangerCacheConn then
        skinChangerCacheConn:Disconnect()
        skinChangerCacheConn = nil
    end
    if skinChangerSkinCacheConn then
        skinChangerSkinCacheConn:Disconnect()
        skinChangerSkinCacheConn = nil
    end
    if skinChangerTowerConn then
        skinChangerTowerConn:Disconnect()
        skinChangerTowerConn = nil
    end
    if skinChangerUnitConn then
        skinChangerUnitConn:Disconnect()
        skinChangerUnitConn = nil
    end
    if skinChangerUnitFolderConn then
        skinChangerUnitFolderConn:Disconnect()
        skinChangerUnitFolderConn = nil
    end
    if skinChangerHeartbeatConn then
        skinChangerHeartbeatConn:Disconnect()
        skinChangerHeartbeatConn = nil
    end
    skinChangerSyncQueued = false
    if skinChangerThread then
        task.cancel(skinChangerThread)
        skinChangerThread = nil
    end
    for model in pairs(skinVisuals) do
        restoreSkinVisual(model)
    end
    cleanupStaleSkinVisuals()
    if skinVisualFolder and skinVisualFolder.Parent and #skinVisualFolder:GetChildren() == 0 then
        pcall(function()
            skinVisualFolder:Destroy()
        end)
    end
    skinVisualFolder = nil
end

abilitiesStoreCache = false
function getAbilitiesStore()
    if abilitiesStoreCache ~= false then
        return abilitiesStoreCache
    end
    abilitiesStoreCache = nil
    local stores = safeRequirePath("Client.Interfaces.Stores", ReplicatedStorage, "Client", "Interfaces", "Stores")
    if
        type(stores) == "table"
        and stores.AbilitiesStore
        and stores.AbilitiesStore.store
        and type(stores.AbilitiesStore.store.getState) == "function"
    then
        abilitiesStoreCache = stores.AbilitiesStore.store
    end
    return abilitiesStoreCache
end

function abilityKey(name)
    return tostring(name or ""):gsub("[^%w]", "")
end

function getServerClock()
    local ok, value = pcall(function()
        return workspace:GetServerTimeNow()
    end)
    return ok and tonumber(value) or tick()
end

function getZephyrRuntimeEnv()
    return zephyrGetRuntimeEnv()
end

function getTowerAbilityCooldownRemaining(towerInfo, abilityName)
    local model = towerInfo and towerInfo.model
    local cleanName = abilityKey(abilityName)
    local store = getAbilitiesStore()
    if model and store then
        local ok, state = pcall(function()
            return store:getState()
        end)
        local modelState = ok and type(state) == "table" and state[model] or nil
        local abilityState = type(modelState) == "table" and (modelState[cleanName] or modelState[abilityName]) or nil
        if type(abilityState) == "table" then
            local endTime = tonumber(abilityState.deltaTime) or 0
            local maxTime = tonumber(abilityState.maxDeltaTime) or 0
            local remaining = math.max(0, endTime - getServerClock())
            return remaining, maxTime > 0 or endTime > 0
        end
    end

    local abilities = towerInfo and towerInfo.entity and towerInfo.entity.Abilities
    if abilities and type(abilities.GetAllStates) == "function" then
        local ok, states = pcall(function()
            return abilities:GetAllStates()
        end)
        if ok and type(states) == "table" then
            for stateName, raw in pairs(states) do
                if abilityKey(stateName) == cleanName and type(raw) == "string" then
                    local endText, maxText = raw:match("^([^,]+),([^,]+)$")
                    local endTime = tonumber(endText) or 0
                    local maxTime = tonumber(maxText) or 0
                    return math.max(0, endTime - getServerClock()), maxTime > 0 or endTime > 0
                end
            end
        end
    end

    return nil, false
end

function towerHasAbility(towerInfo, abilityName, fallbackLevel)
    local cleanName = abilityKey(abilityName)
    local abilities = towerInfo and towerInfo.entity and towerInfo.entity.AvailableAbilities
    if type(abilities) == "table" then
        for key, ability in pairs(abilities) do
            local name = type(ability) == "table" and ability.Name or key
            if abilityKey(name) == cleanName then
                return true
            end
        end
    end
    local level = getTowerUpgradeState(towerInfo)
    return (tonumber(level) or 0) >= (tonumber(fallbackLevel) or 0)
end

function getCommanderAbilityTowers(abilityName, fallbackLevel)
    local commanders = {}
    for _, towerInfo in ipairs(getOwnedTowerEntities()) do
        local lowerName = tostring(towerInfo.name or ""):lower()
        if lowerName:find("commander", 1, true) and towerHasAbility(towerInfo, abilityName, fallbackLevel) then
            table.insert(commanders, towerInfo)
        end
    end
    table.sort(commanders, function(a, b)
        local ap = a.model and getTowerRoot(a.model)
        local bp = b.model and getTowerRoot(b.model)
        local ax = ap and ap.Position.X or 0
        local bx = bp and bp.Position.X or 0
        if ax == bx then
            local az = ap and ap.Position.Z or 0
            local bz = bp and bp.Position.Z or 0
            return az < bz
        end
        return ax < bx
    end)
    return commanders
end

function getCommanderChainTowers()
    return getCommanderAbilityTowers("Call Of Arms", 2)
end

function getSupportCaravanTowers()
    return getCommanderAbilityTowers("Support Caravan", 4)
end

function activateTowerAbility(towerInfo, abilityName)
    if not (towerInfo and towerInfo.model and towerInfo.model.Parent) then
        return false
    end
    local ok, result = invokeTroopsThrottled("Abilities", "Activate", {
        Troop = towerInfo.model,
        Name = abilityName,
        Data = {},
    })
    if ok ~= true then
        return false, result
    end
    if result == false then
        return false, result
    end
    if type(result) == "string" and result ~= "" then
        return false, result
    end
    return true, result
end

COMMANDER_CHAIN_EFFECT_TIME = 10.4
COMMANDER_CHAIN_LOCAL_COOLDOWN = 30
commanderChainStopHook = nil

function installCommanderChainStopHook()
    local env = getZephyrRuntimeEnv()
    local previous = env.__ZEPHYR_TDS_STOP_COMMANDER_CHAIN
    if type(previous) == "function" and previous ~= commanderChainStopHook then
        pcall(previous)
    end
    commanderChainStopHook = function()
        commanderChainEnabled = false
        if commanderChainThread then
            task.cancel(commanderChainThread)
            commanderChainThread = nil
        end
    end
    env.__ZEPHYR_TDS_STOP_COMMANDER_CHAIN = commanderChainStopHook
end

function clearCommanderChainStopHook()
    local env = getZephyrRuntimeEnv()
    if commanderChainStopHook and env.__ZEPHYR_TDS_STOP_COMMANDER_CHAIN == commanderChainStopHook then
        env.__ZEPHYR_TDS_STOP_COMMANDER_CHAIN = nil
    end
    commanderChainStopHook = nil
end

function startCommanderChain()
    if commanderChainThread then
        return true
    end
    installCommanderChainStopHook()
    commanderChainEnabled = true
    local localCooldowns = {}
    commanderChainThread = task.spawn(function()
        local index = 1
        local nextChainAt = 0
        while commanderChainEnabled do
            local commanders = getCommanderChainTowers()
            if #commanders == 0 then
                task.wait(1)
            else
                local now = tick()
                if now >= nextChainAt then
                    local fired = false
                    local soonestReadyAt = now + 1
                    for _ = 1, #commanders do
                        if index > #commanders then
                            index = 1
                        end
                        local towerInfo = commanders[index]
                        index = (index % #commanders) + 1
                        local model = towerInfo and towerInfo.model
                        if model then
                            local remaining, known = getTowerAbilityCooldownRemaining(towerInfo, "Call Of Arms")
                            local localReady = not localCooldowns[model] or now >= localCooldowns[model]
                            if localCooldowns[model] then
                                soonestReadyAt = math.min(soonestReadyAt, localCooldowns[model])
                            end
                            if remaining and remaining > 0.2 then
                                soonestReadyAt = math.min(soonestReadyAt, now + remaining)
                            end
                            if localReady and (not known or not remaining or remaining <= 0.2) then
                                if activateTowerAbility(towerInfo, "Call Of Arms") then
                                    localCooldowns[model] = now + COMMANDER_CHAIN_LOCAL_COOLDOWN
                                    nextChainAt = now + COMMANDER_CHAIN_EFFECT_TIME
                                    fired = true
                                    break
                                else
                                    localCooldowns[model] = now + 1
                                end
                            elseif remaining and remaining > 0.25 then
                                localCooldowns[model] = now + math.min(remaining, COMMANDER_CHAIN_LOCAL_COOLDOWN)
                            end
                        end
                    end
                    if fired then
                        task.wait(0.35)
                    else
                        task.wait(math.clamp(soonestReadyAt - now, 0.25, 0.75))
                    end
                else
                    task.wait(math.clamp(nextChainAt - now, 0.15, 0.75))
                end
            end
        end
        commanderChainThread = nil
        clearCommanderChainStopHook()
    end)
    return true
end

function stopCommanderChain()
    commanderChainEnabled = false
    if commanderChainThread then
        task.cancel(commanderChainThread)
        commanderChainThread = nil
    end
    clearCommanderChainStopHook()
end

function startSupportCaravan()
    if supportCaravanThread then
        return true
    end
    supportCaravanEnabled = true
    local localCooldowns = {}
    supportCaravanThread = task.spawn(function()
        local index = 1
        while supportCaravanEnabled do
            local commanders = getSupportCaravanTowers()
            if #commanders == 0 then
                task.wait(1)
            else
                local now = tick()
                local fired = false
                for _ = 1, #commanders do
                    if index > #commanders then
                        index = 1
                    end
                    local towerInfo = commanders[index]
                    index = (index % #commanders) + 1
                    local model = towerInfo and towerInfo.model
                    if model then
                        local remaining, known = getTowerAbilityCooldownRemaining(towerInfo, "Support Caravan")
                        local localReady = not localCooldowns[model] or now >= localCooldowns[model]
                        if localReady and (not known or not remaining or remaining <= 0.15) then
                            if activateTowerAbility(towerInfo, "Support Caravan") then
                                localCooldowns[model] = now + 59
                                fired = true
                                break
                            else
                                localCooldowns[model] = now + 1.5
                            end
                        elseif remaining and remaining > 0.15 then
                            localCooldowns[model] = now + math.min(remaining, 60)
                        end
                    end
                end
                task.wait(fired and 0.35 or 0.75)
            end
        end
        supportCaravanThread = nil
    end)
    return true
end

function stopSupportCaravan()
    supportCaravanEnabled = false
    if supportCaravanThread then
        task.cancel(supportCaravanThread)
        supportCaravanThread = nil
    end
end

function applyFpsBooster()
    if ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.fpsBoosterApplied then
        return true, "already"
    end
    ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.fpsBoosterApplied = true

    pcall(stopESP)
    pcall(stopEnemyInspector)
    pcall(stopSkinChanger)
    pcall(stopAbilityManager)
    pcall(stopCommanderChain)
    pcall(stopSupportCaravan)
    espEnabled = false
    enemyInspectorEnabled = false
    skinChangerEnabled = false
    abilityManagerEnabled = false
    commanderChainEnabled = false
    supportCaravanEnabled = false

    pcall(function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    end)
    pcall(function()
        local gameSettings = UserSettings():GetService("UserGameSettings")
        gameSettings.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
        gameSettings.MasterVolume = 0
    end)
    if type(setfpscap) == "function" then
        pcall(function()
            setfpscap(240)
        end)
    end

    pcall(function()
        Lighting.GlobalShadows = false
        Lighting.Brightness = 1
        Lighting.EnvironmentDiffuseScale = 0
        Lighting.EnvironmentSpecularScale = 0
        Lighting.FogEnd = 1000000
        Lighting.FogStart = 1000000
        Lighting.ClockTime = 14
    end)
    pcall(function()
        Lighting.Technology = Enum.Technology.Compatibility
    end)

    local terrain = workspace:FindFirstChildOfClass("Terrain")
    if terrain then
        pcall(function()
            terrain.WaterWaveSize = 0
        end)
        pcall(function()
            terrain.WaterWaveSpeed = 0
        end)
        pcall(function()
            terrain.WaterReflectance = 0
        end)
        pcall(function()
            terrain.WaterTransparency = 1
        end)
        pcall(function()
            terrain.Decoration = false
        end)
    end

    local function stripVisual(inst)
        pcall(function()
            if
                inst:IsA("ParticleEmitter")
                or inst:IsA("Trail")
                or inst:IsA("Beam")
                or inst:IsA("Fire")
                or inst:IsA("Smoke")
                or inst:IsA("Sparkles")
            then
                inst.Enabled = false
            elseif inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
                inst.Enabled = false
            elseif inst:IsA("Highlight") then
                inst.Enabled = false
            elseif inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then
                inst.Enabled = false
            elseif inst:IsA("Explosion") then
                inst.Visible = false
            elseif inst:IsA("ForceField") then
                inst.Visible = false
            elseif inst:IsA("PostEffect") then
                inst.Enabled = false
            elseif inst:IsA("Atmosphere") then
                inst.Density = 0
                inst.Haze = 0
                inst.Glare = 0
            elseif inst:IsA("Clouds") then
                inst.Enabled = false
                inst.Cover = 0
                inst.Density = 0
            elseif inst:IsA("Sky") or inst:IsA("SurfaceAppearance") then
                inst:Destroy()
            elseif inst:IsA("Decal") or inst:IsA("Texture") then
                inst.Transparency = 1
            elseif inst:IsA("MeshPart") then
                inst.TextureID = ""
                inst.CastShadow = false
                inst.Material = Enum.Material.SmoothPlastic
                inst.Reflectance = 0
            elseif inst:IsA("BasePart") then
                inst.CastShadow = false
                inst.Material = Enum.Material.SmoothPlastic
                inst.Reflectance = 0
            elseif inst:IsA("SpecialMesh") then
                inst.TextureId = ""
            elseif inst:IsA("Sound") then
                inst.Volume = 0
                inst:Stop()
            end
        end)
    end

    for _, root in ipairs({ workspace, Lighting, SoundService }) do
        for _, inst in ipairs(root:GetDescendants()) do
            stripVisual(inst)
        end
    end

    if ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.fpsBoosterWorkspaceConn then
        ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.fpsBoosterWorkspaceConn:Disconnect()
    end
    ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.fpsBoosterWorkspaceConn = workspace.DescendantAdded:Connect(stripVisual)
    if ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.fpsBoosterLightingConn then
        ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.fpsBoosterLightingConn:Disconnect()
    end
    ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.fpsBoosterLightingConn = Lighting.DescendantAdded:Connect(stripVisual)
    if ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.fpsBoosterSoundConn then
        ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.fpsBoosterSoundConn:Disconnect()
    end
    ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.fpsBoosterSoundConn = SoundService.DescendantAdded:Connect(stripVisual)

    return true, "applied"
end

-- Gatling
gatlingCacheTime = 0
gatlingCacheTargets = nil
gatlingCacheLimit = 0
GATLING_CACHE_TTL = 0.24
GATLING_MEDIUM_CACHE_TTL = 0.6
GATLING_HEAVY_CACHE_TTL = 1.0
GATLING_MEDIUM_ENEMY_COUNT = 24
GATLING_HEAVY_ENEMY_COUNT = 45
GATLING_LOOP_INTERVAL = 1 / 30
GATLING_MOBILE_LOOP_INTERVAL = 1 / 30
GATLING_IDLE_INTERVAL = 0.12
GATLING_UI_UPDATE_INTERVAL = 0.25
GATLING_VISUAL_UPDATE_INTERVAL = 0.18
GATLING_VISUAL_LINE_LIMIT = 6
GATLING_VISUAL_TARGET_LIMIT = 8
GATLING_VISUAL_FIRE_INTERVAL = 0.065
GATLING_MAX_EVENTS_PER_LOOP = 4
GATLING_MEDIUM_EVENTS_PER_LOOP = 3
GATLING_HEAVY_EVENTS_PER_LOOP = 2
GATLING_CATCHUP_TICKS = 14
GATLING_TANK_SHOT_THRESHOLD = 10
GATLING_FAST_DUMP_MIN = 12
GATLING_FAST_DUMP_BURST_MULT = 3
GATLING_RELOAD_POKE_INTERVAL = 0.08
GATLING_FPS_ARM_INTERVAL = 0.12
GATLING_TOWER_CACHE_TTL = 0.5
GATLING_AIM_LEAD_MIN = 0.025
GATLING_AIM_LEAD_MAX = 0.16
GATLING_OVERKILL_SHOTS = 1
GATLING_WEAK_CONFIRM_TTL = 0.095
gatlingLastAimReplicate = 0
gatlingLastReload = 0
gatlingLastStop = 0
gatlingLastFpsArm = 0
gatlingLastVisualAt = 0
gatlingLastLoopAt = 0
gatlingLastUiUpdateAt = 0
gatlingLastTowerScanAt = 0
gatlingLastInvalidateAt = 0
gatlingCachedTowerModel = nil
gatlingCachedTowerEntity = nil
gatlingLastSoundMuteAt = 0
gatlingSentThisSecond = 0
gatlingSentLastSecond = 0
gatlingSentWindowAt = tick()
gatlingLastCandidateCount = 0
gatlingLastTargets = {}
gatlingHiddenFpsArmed = false
gatlingHiddenFpsTower = nil
gatlingVisualFolder = nil
gatlingTargetHighlights = {}
gatlingLineParts = {}
gatlingImpactDots = {}
gatlingMutedSounds = {}
gatlingPatchedFireGunEntities = {}
gatlingLastVisualAim = nil
gatlingRemotesCache = nil
gatlingRemotesCacheAt = 0
gatlingClientAtoms = nil
gatlingClientAtomsChecked = false
gatlingNpcReplicator = nil
gatlingNpcReplicatorChecked = false
gatlingStores = nil
gatlingStoresChecked = false
gatlingUpgradeHandler = nil
gatlingUpgradeHandlerChecked = false
gatlingTargetWatchConns = {}
gatlingZeroAmmoSince = 0
gatlingWaitingForAmmo = false
gatlingLocalFiring = false
gatlingLocalFiringEntity = nil
gatlingReloadFpsActive = false
gatlingReloadFpsEntity = nil
gatlingReloadFpsTower = nil
gatlingReloadFpsStarted = 0
gatlingReloadInputAt = 0
gatlingReloadReleasedAt = 0
gatlingNoTowerToastAt = 0
GATLING_FPS_ICON_ID = "94564306265259"

function setGatlingFireRate(value, save)
    gatlingFireRateTicks =
        math.clamp(math.floor(tonumber(value) or gatlingFireRateTicks or 60), GATLING_RATE_MIN, GATLING_RATE_MAX)
    gatlingFireDelay = 1 / math.max(gatlingFireRateTicks, 1)
    if save ~= false then
        setSetting("gatlingFireRateTicks", gatlingFireRateTicks)
        setSetting("gatlingFireDelay", gatlingFireDelay)
    end
    if gatlingSliderUpdateFn then
        gatlingSliderUpdateFn()
    end
end

function getGatlingRemotes()
    local now = tick()
    if gatlingRemotesCache and now - gatlingRemotesCacheAt < 2 then
        return gatlingRemotesCache
    end
    gatlingRemotesCacheAt = now
    local folder
    pcall(function()
        local network = ReplicatedStorage:FindFirstChild("Network")
        folder = network and network:FindFirstChild("GatlingGun")
    end)
    gatlingRemotesCache = {
        fire = folder and folder:FindFirstChild("RE:Fire") or nil,
        reload = folder and folder:FindFirstChild("RE:Reload") or nil,
        stop = folder and folder:FindFirstChild("RE:StopFiring") or nil,
        fps = folder and folder:FindFirstChild("RE:FpsEnabled") or nil,
        aim = folder and folder:FindFirstChild("URE:ReplicateAimPosition") or nil,
    }
    return gatlingRemotesCache
end

function gatlingInvalidateTargets()
    local now = tick()
    if now - gatlingLastInvalidateAt < 0.18 then
        return
    end
    gatlingLastInvalidateAt = now
    gatlingCacheTime = 0
    gatlingCacheTargets = nil
    gatlingCacheLimit = 0
end

function gatlingDisconnectTargetWatchers()
    for _, conn in ipairs(gatlingTargetWatchConns) do
        if conn then
            pcall(function()
                conn:Disconnect()
            end)
        end
    end
    table.clear(gatlingTargetWatchConns)
end

function gatlingWatchTargetChanges()
    gatlingDisconnectTargetWatchers()
    -- Watch the NPC folder, not every descendant. Large waves flood those events.
    table.insert(
        gatlingTargetWatchConns,
        workspace.ChildAdded:Connect(function(child)
            if child.Name == "NPCs" then
                gatlingWatchTargetChanges()
                gatlingInvalidateTargets()
            end
        end)
    )
    table.insert(
        gatlingTargetWatchConns,
        ReplicatedStorage.ChildAdded:Connect(function(child)
            if child.Name == "StateReplicators" then
                gatlingWatchTargetChanges()
                gatlingInvalidateTargets()
            end
        end)
    )
end

function gatlingGetClientAtoms()
    if gatlingClientAtomsChecked then
        return gatlingClientAtoms
    end
    gatlingClientAtomsChecked = true
    gatlingClientAtoms =
        safeRequirePath("Shared.Modules.ClientAtoms", ReplicatedStorage, "Shared", "Modules", "ClientAtoms")
    return gatlingClientAtoms
end

function gatlingGetNpcReplicatorModule()
    if gatlingNpcReplicatorChecked then
        return gatlingNpcReplicator
    end
    gatlingNpcReplicatorChecked = true
    gatlingNpcReplicator = safeRequirePath(
        "Client.Modules.Replicators.NPCReplicator",
        ReplicatedStorage,
        "Client",
        "Modules",
        "Replicators",
        "NPCReplicator"
    )
    return gatlingNpcReplicator
end

function gatlingGetStores()
    if gatlingStoresChecked then
        return gatlingStores
    end
    gatlingStoresChecked = true
    gatlingStores = safeRequirePath("Client.Interfaces.Stores", ReplicatedStorage, "Client", "Interfaces", "Stores")
    return gatlingStores
end

function gatlingGetUpgradeHandler()
    if gatlingUpgradeHandlerChecked then
        return gatlingUpgradeHandler
    end
    gatlingUpgradeHandlerChecked = true
    gatlingUpgradeHandler = safeRequirePath(
        "Client.Controllers.Game.LegacyGameInterfaceController.Upgrade.upgradeHandler",
        ReplicatedStorage,
        "Client",
        "Controllers",
        "Game",
        "LegacyGameInterfaceController",
        "Upgrade",
        "upgradeHandler"
    )
    return gatlingUpgradeHandler
end

function gatlingUseAbilityEvent(towerModel, abilityName)
    if not towerModel then
        return false
    end
    local stores = gatlingGetStores()
    local event = stores
        and stores.AbilitiesStore
        and stores.AbilitiesStore.events
        and stores.AbilitiesStore.events.UseAbility
    if not event or type(event.Fire) ~= "function" then
        return false
    end
    local ok = pcall(function()
        event:Fire(towerModel, abilityName)
    end)
    return ok == true
end

function gatlingSelectTowerForUi(towerModel)
    if not towerModel then
        return false
    end
    local selected = false
    local stores = gatlingGetStores()
    pcall(function()
        selected = stores and stores.UpgradesStore and stores.UpgradesStore.store:getState().model == towerModel
    end)
    if selected then
        return true
    end

    local handler = gatlingGetUpgradeHandler()
    if handler and type(handler.selectTroop) == "function" then
        local ok = pcall(function()
            handler:selectTroop(towerModel, "Zephyr")
        end)
        if ok then
            return true
        end
    end
    return false
end

function gatlingClickGuiButton(button)
    if not button or not button:IsA("GuiButton") then
        return false
    end
    local clicked = false
    local function fireConnections(signal)
        local getConnections = zephyrGlobalFunction("getconnections")
        if not getConnections then
            return
        end
        for _, conn in ipairs(getConnections(signal)) do
            pcall(function()
                if type(conn.Fire) == "function" then
                    conn:Fire()
                    clicked = true
                elseif type(conn.Function) == "function" then
                    conn.Function()
                    clicked = true
                end
            end)
        end
    end

    pcall(function()
        local fireSignal = zephyrGlobalFunction("firesignal")
        if fireSignal then
            fireSignal(button.MouseButton1Down)
            fireSignal(button.MouseButton1Up)
            fireSignal(button.MouseButton1Click)
            fireSignal(button.Activated)
            clicked = true
        end
    end)
    pcall(function()
        fireConnections(button.MouseButton1Down)
        fireConnections(button.MouseButton1Up)
        fireConnections(button.MouseButton1Click)
        fireConnections(button.Activated)
    end)
    if not clicked and not ZephyrLowCompatExecutor then
        pcall(function()
            local VirtualInputManager = game:GetService("VirtualInputManager")
            local pos = button.AbsolutePosition + (button.AbsoluteSize / 2)
            VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
            VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
            clicked = true
        end)
    end
    return clicked
end

function gatlingButtonScoreForFps(button)
    if not button or not button:IsA("GuiButton") then
        return -1
    end
    if not isGuiObjectEffectivelyVisible(button) then
        return -1
    end
    local zephyrGui = PlayerGui:FindFirstChild("ZephyrTDS")
    if zephyrGui and button:IsDescendantOf(zephyrGui) then
        return -1
    end

    local score = 0
    local blob = getGuiObjectText(button) .. " " .. tostring(button.Name):upper()
    local current = button.Parent
    local depth = 0
    while current and current ~= PlayerGui and depth < 6 do
        blob ..= " " .. tostring(current.Name):upper()
        current = current.Parent
        depth += 1
    end

    if blob:find("FPS", 1, true) then
        score += 12
    end
    if blob:find("GATLING", 1, true) then
        score += 4
    end
    if blob:find("ABILITY", 1, true) then
        score += 2
    end
    if button:IsA("ImageButton") then
        local image = tostring(button.Image or "")
        if image:find(GATLING_FPS_ICON_ID, 1, true) then
            score += 30
        end
    end
    for _, desc in ipairs(button:GetDescendants()) do
        if desc:IsA("ImageLabel") or desc:IsA("ImageButton") then
            local image = tostring(desc.Image or "")
            if image:find(GATLING_FPS_ICON_ID, 1, true) then
                score += 30
            end
        elseif desc:IsA("TextLabel") or desc:IsA("TextButton") then
            local ok, text = pcall(function()
                return desc.Text
            end)
            if ok and tostring(text):upper():find("FPS", 1, true) then
                score += 8
            end
        end
    end

    return score
end

function gatlingClickFpsAbilityButton()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if not gui then
        return false
    end
    local best, bestScore = nil, 0
    for _, obj in ipairs(gui:GetDescendants()) do
        if obj:IsA("GuiButton") then
            local score = gatlingButtonScoreForFps(obj)
            if score > bestScore then
                best = obj
                bestScore = score
            end
        end
    end
    if best and bestScore >= 10 then
        return gatlingClickGuiButton(best)
    end
    return false
end

function gatlingActivateFpsLikeManual(towerModel)
    if gatlingUseAbilityEvent(towerModel, "FPS") then
        return true
    end
    if gatlingSelectTowerForUi(towerModel) then
        task.defer(function()
            task.wait(0.08)
            gatlingClickFpsAbilityButton()
        end)
        return true
    end
    return gatlingClickFpsAbilityButton()
end

function gatlingRepValue(rep, key)
    if not rep then
        return nil
    end
    local ok, value = pcall(function()
        if type(rep.Get) == "function" then
            return rep:Get(key)
        end
        return nil
    end)
    if ok and value ~= nil then
        return value
    end
    ok, value = pcall(function()
        if typeof(rep) == "Instance" then
            return rep:GetAttribute(key)
        end
        return nil
    end)
    if ok and value ~= nil then
        return value
    end
    ok, value = pcall(function()
        if typeof(rep) == "Instance" then
            local child = rep:FindFirstChild(key)
            if child and child:IsA("ValueBase") then
                return child.Value
            end
        end
        return nil
    end)
    if ok and value ~= nil then
        return value
    end
    return nil
end

function gatlingClearVisuals()
    if gatlingVisualFolder and gatlingVisualFolder.Parent then
        gatlingVisualFolder:Destroy()
    end
    gatlingVisualFolder = nil
    for npc, highlight in pairs(gatlingTargetHighlights) do
        if highlight and highlight.Parent then
            highlight:Destroy()
        end
        gatlingTargetHighlights[npc] = nil
    end
    for i, part in pairs(gatlingLineParts) do
        if part and part.Parent then
            part:Destroy()
        end
        gatlingLineParts[i] = nil
    end
    for i, part in pairs(gatlingImpactDots) do
        if part and part.Parent then
            part:Destroy()
        end
        gatlingImpactDots[i] = nil
    end
end

function gatlingRestoreHitsounds()
    for sound, volume in pairs(gatlingMutedSounds) do
        if sound and sound.Parent then
            pcall(function()
                sound.Volume = volume
            end)
        end
        gatlingMutedSounds[sound] = nil
    end
end

function gatlingEnsureVisualFolder()
    if gatlingVisualFolder and gatlingVisualFolder.Parent then
        return gatlingVisualFolder
    end
    gatlingVisualFolder = Instance.new("Folder")
    gatlingVisualFolder.Name = "ZephyrGatlingVisuals"
    gatlingVisualFolder.Parent = workspace
    return gatlingVisualFolder
end

function gatlingGetRoot(npc)
    return npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart or npc:FindFirstChildWhichIsA("BasePart")
end

function gatlingNameMatches(npcName, modelName)
    if npcName == modelName then
        return true
    end
    if pcall(string.match, npcName, modelName) and string.match(npcName, modelName) then
        return true
    end
    if pcall(string.match, modelName, npcName) and string.match(modelName, npcName) then
        return true
    end
    return false
end

function gatlingGetNpcReplicator(npc)
    local StateReplicators = ReplicatedStorage:FindFirstChild("StateReplicators")
    if not StateReplicators or not npc then
        return nil
    end
    local pointer = npc:FindFirstChild("RootPointer")
    if pointer and pointer:IsA("ObjectValue") and pointer.Value then
        return pointer.Value
    end
    local npcModule = gatlingGetNpcReplicatorModule()
    if npcModule and type(npcModule.GetNPCFromModel) == "function" then
        local ok, entity = pcall(function()
            return npcModule.GetNPCFromModel(npc)
        end)
        if ok and entity and entity.Replicator then
            return entity.Replicator
        end
    end
    for _, rep in ipairs(StateReplicators:GetChildren()) do
        if rep.Name ~= "NPCReplicator" then
            continue
        end
        local modelName = rep:GetAttribute("ModelName")
        if modelName and gatlingNameMatches(npc.Name, modelName) then
            return rep
        end
    end
    return nil
end

function gatlingGetHealth(npc)
    local rep = gatlingGetNpcReplicator(npc)
    if rep then
        return gatlingRepValue(rep, "Health") or 0
    end
    local hum = npc:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health or 0
end

function gatlingReadShield(rep, source)
    local shield = 0
    local maxShield = 0
    if type(source) == "table" then
        shield = tonumber(source.Shield) or tonumber(source.HealthShield) or tonumber(source.shield) or shield
        maxShield = tonumber(source.MaxShield) or tonumber(source.maxShield) or tonumber(source.ShieldMax) or maxShield
    end
    if rep then
        shield = tonumber(gatlingRepValue(rep, "Shield"))
            or tonumber(gatlingRepValue(rep, "HealthShield"))
            or tonumber(gatlingRepValue(rep, "shield"))
            or shield
        maxShield = tonumber(gatlingRepValue(rep, "MaxShield"))
            or tonumber(gatlingRepValue(rep, "ShieldMax"))
            or tonumber(gatlingRepValue(rep, "maxShield"))
            or maxShield
    end
    shield = math.max(0, tonumber(shield) or 0)
    maxShield = math.max(shield, tonumber(maxShield) or 0)
    return shield, maxShield
end

gatlingIsTrue = nil

function gatlingIsAlive(npc)
    return gatlingGetHealth(npc) > 0
end

function gatlingGetNPCData(npc)
    local root = gatlingGetRoot(npc)
    local rep = gatlingGetNpcReplicator(npc)
    if rep and gatlingIsTrue(gatlingRepValue(rep, "FakeUnit")) then
        return nil
    end
    local rootHealth = rep and tonumber(gatlingRepValue(rep, "Health")) or gatlingGetHealth(npc)
    rootHealth = tonumber(rootHealth) or 0
    local shield, maxShield = gatlingReadShield(rep)
    if rootHealth <= 0 and shield <= 0 then
        return nil
    end
    local hum = npc:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 and shield <= 0 then
        return nil
    end
    local worldPos = root and root.Position or nil
    if not worldPos and rep then
        local x = gatlingRepValue(rep, "PositionX") or gatlingRepValue(rep, "X")
        local y = gatlingRepValue(rep, "PositionY") or gatlingRepValue(rep, "Y")
        local z = gatlingRepValue(rep, "PositionZ") or gatlingRepValue(rep, "Z")
        if x and y and z then
            worldPos = Vector3.new(x, y, z)
        end
    end
    if not worldPos then
        return nil
    end
    return {
        npc = npc,
        rep = rep,
        pos = worldPos,
        vel = root and root.AssemblyLinearVelocity or Vector3.zero,
        hp = rootHealth + shield,
        health = rootHealth,
        shield = shield,
        maxHp = (rep and tonumber(gatlingRepValue(rep, "MaxHealth")) or rootHealth) + maxShield,
        maxShield = maxShield,
        name = tostring(
            (rep and (gatlingRepValue(rep, "DisplayName") or gatlingRepValue(rep, "ModelName"))) or npc.Name
        ),
        speed = rep
                and tonumber(
                    gatlingRepValue(rep, "Speed")
                        or gatlingRepValue(rep, "ForceSpeed")
                        or gatlingRepValue(rep, "WalkSpeed")
                )
            or nil,
        pathDistance = rep and tonumber(gatlingRepValue(rep, "PathDistance")) or tonumber(
            npc:GetAttribute("PathDistance")
        ) or 0,
        defense = rep and tonumber(gatlingRepValue(rep, "Defense")) or 0,
        pathName = rep and gatlingRepValue(rep, "PathName") or nil,
        pathToEnd = rep and tonumber(gatlingRepValue(rep, "DistanceToEnd")) or nil,
    }
end

function gatlingIsTrue(value)
    if value == true then
        return true
    end
    local kind = type(value)
    if kind == "number" then
        return value ~= 0
    end
    if kind == "string" then
        local lower = value:lower()
        return lower == "true" or lower == "yes" or lower == "1" or lower == "on"
    end
    return false
end

function gatlingInfoLooksLikeTower(towerInfo)
    if not towerInfo then
        return false
    end
    local name = tostring(towerInfo.name or "")
    if name:lower():find("gatling", 1, true) then
        return true
    end

    local model = towerInfo.model
    if not model then
        return false
    end
    local checks = {}
    local function add(value)
        if value ~= nil then
            checks[#checks + 1] = value
        end
    end
    add(model.Name)
    add(model:GetAttribute("TowerName"))
    add(model:GetAttribute("Name"))
    add(model:GetAttribute("Type"))
    add(model:GetAttribute("DisplayName"))
    local towerRep = model:FindFirstChild("TowerReplicator")
    if towerRep then
        add(towerRep:GetAttribute("TowerName"))
        add(towerRep:GetAttribute("Name"))
        add(towerRep:GetAttribute("Type"))
        add(towerRep:GetAttribute("DisplayName"))
    end
    for _, value in ipairs(checks) do
        if tostring(value or ""):lower():find("gatling", 1, true) then
            return true
        end
    end
    local scanned = 0
    for _, inst in ipairs(model:GetDescendants()) do
        scanned += 1
        if scanned > 80 then
            break
        end
        if tostring(inst.Name or ""):lower():find("gatling", 1, true) then
            return true
        end
    end
    return false
end

function gatlingGetEntityTargetData(entity)
    if type(entity) ~= "table" then
        return nil
    end
    local aliveOk, alive = pcall(function()
        if type(entity.IsAlive) == "function" then
            return entity:IsAlive()
        end
        return nil
    end)
    if aliveOk and alive == false then
        return nil
    end

    local model = entity.Model
    local rep = entity.Replicator
    if gatlingIsTrue(entity.FakeUnit) or gatlingIsTrue(gatlingRepValue(rep, "FakeUnit")) then
        return nil
    end
    local root = model and gatlingGetRoot(model) or entity.PrimaryPart or entity.HumanoidRootPart
    local hp = tonumber(entity.Health) or tonumber(gatlingRepValue(rep, "Health")) or 0
    local shield, maxShield = gatlingReadShield(rep, entity)
    if hp <= 0 and shield <= 0 then
        return nil
    end

    local pos = nil
    if root then
        pos = root.Position
    elseif typeof(entity.Position) == "Vector3" then
        pos = entity.Position
    else
        local x = gatlingRepValue(rep, "PositionX") or gatlingRepValue(rep, "X")
        local y = gatlingRepValue(rep, "PositionY") or gatlingRepValue(rep, "Y")
        local z = gatlingRepValue(rep, "PositionZ") or gatlingRepValue(rep, "Z")
        if x and y and z then
            pos = Vector3.new(x, y, z)
        end
    end
    if not pos then
        return nil
    end

    return {
        npc = model or rep or entity,
        entity = entity,
        rep = rep,
        pos = pos,
        vel = root and root.AssemblyLinearVelocity or Vector3.zero,
        hp = hp + shield,
        health = hp,
        shield = shield,
        maxHp = (tonumber(entity.MaxHealth) or tonumber(gatlingRepValue(rep, "MaxHealth")) or hp) + maxShield,
        maxShield = maxShield,
        name = tostring(
            entity.Name
                or gatlingRepValue(rep, "DisplayName")
                or gatlingRepValue(rep, "ModelName")
                or (model and model.Name)
                or "Enemy"
        ),
        speed = tonumber(entity.Speed)
            or tonumber(entity.ForceSpeed)
            or tonumber(
                gatlingRepValue(rep, "Speed") or gatlingRepValue(rep, "ForceSpeed") or gatlingRepValue(rep, "WalkSpeed")
            ),
        pathDistance = tonumber(entity.PathDistance) or tonumber(gatlingRepValue(rep, "PathDistance")) or 0,
        defense = tonumber(entity.Defense) or tonumber(gatlingRepValue(rep, "Defense")) or 0,
        pathName = entity.PathName or gatlingRepValue(rep, "PathName"),
        pathToEnd = tonumber(entity.DistanceToEnd) or tonumber(gatlingRepValue(rep, "DistanceToEnd")),
    }
end

function gatlingGetReplicatorTargetData(rep)
    if not rep then
        return nil
    end
    if gatlingIsTrue(gatlingRepValue(rep, "FakeUnit")) then
        return nil
    end
    local hp = tonumber(gatlingRepValue(rep, "Health")) or 0
    local shield, maxShield = gatlingReadShield(rep)
    if hp <= 0 and shield <= 0 then
        return nil
    end

    local pos = gatlingRepValue(rep, "Position") or gatlingRepValue(rep, "CurrentPosition")
    if typeof(pos) == "CFrame" then
        pos = pos.Position
    end
    if typeof(pos) ~= "Vector3" then
        local x = gatlingRepValue(rep, "PositionX") or gatlingRepValue(rep, "X")
        local y = gatlingRepValue(rep, "PositionY") or gatlingRepValue(rep, "Y")
        local z = gatlingRepValue(rep, "PositionZ") or gatlingRepValue(rep, "Z")
        if x and y and z then
            pos = Vector3.new(x, y, z)
        end
    end
    if typeof(pos) ~= "Vector3" then
        return nil
    end

    return {
        npc = rep,
        rep = rep,
        pos = pos,
        vel = Vector3.zero,
        hp = hp + shield,
        health = hp,
        shield = shield,
        maxHp = (tonumber(gatlingRepValue(rep, "MaxHealth")) or hp) + maxShield,
        maxShield = maxShield,
        name = tostring(gatlingRepValue(rep, "DisplayName") or gatlingRepValue(rep, "ModelName") or "Enemy"),
        speed = tonumber(
            gatlingRepValue(rep, "Speed") or gatlingRepValue(rep, "ForceSpeed") or gatlingRepValue(rep, "WalkSpeed")
        ),
        pathDistance = tonumber(gatlingRepValue(rep, "PathDistance")) or 0,
        defense = tonumber(gatlingRepValue(rep, "Defense")) or 0,
        pathName = gatlingRepValue(rep, "PathName"),
        pathToEnd = tonumber(gatlingRepValue(rep, "DistanceToEnd")),
    }
end

function gatlingRefreshTargetData(target)
    if not target then
        return nil
    end
    local refreshed = nil
    if type(target.entity) == "table" then
        refreshed = gatlingGetEntityTargetData(target.entity)
    end
    if not refreshed and typeof(target.npc) == "Instance" then
        if target.npc:IsA("Model") then
            refreshed = gatlingGetNPCData(target.npc)
        else
            refreshed = gatlingGetReplicatorTargetData(target.npc)
        end
    end
    if not refreshed and target.rep then
        refreshed = gatlingGetReplicatorTargetData(target.rep)
    end
    if refreshed and target.score ~= nil then
        refreshed.score = target.score
    end
    if refreshed and target.screenDist ~= nil then
        refreshed.screenDist = target.screenDist
    end
    if refreshed and target.distance ~= nil then
        refreshed.distance = target.distance
    end
    return refreshed
end

function gatlingFindOwnedTower()
    for _, towerInfo in ipairs(getOwnedTowerEntities()) do
        if gatlingInfoLooksLikeTower(towerInfo) then
            return towerInfo.model, towerInfo.entity
        end
    end
    return nil, nil
end

function gatlingGetOwnedTowerCached()
    local now = tick()
    if now - gatlingLastTowerScanAt < GATLING_TOWER_CACHE_TTL then
        if not gatlingCachedTowerModel or gatlingCachedTowerModel.Parent then
            return gatlingCachedTowerModel, gatlingCachedTowerEntity
        end
    end
    gatlingLastTowerScanAt = now
    gatlingCachedTowerModel, gatlingCachedTowerEntity = gatlingFindOwnedTower()
    return gatlingCachedTowerModel, gatlingCachedTowerEntity
end

function gatlingGetState(entity, key)
    if not entity or not entity.Replicator then
        return nil
    end
    local ok, value = pcall(function()
        return entity.Replicator:Get(key)
    end)
    if ok then
        return value
    end
    return nil
end

function gatlingGetStateFallback(entity, model, key)
    local value = gatlingGetState(entity, key)
    if value ~= nil then
        return value
    end
    if entity and type(entity.State) == "table" and entity.State[key] ~= nil then
        return entity.State[key]
    end
    if entity and type(entity.Data) == "table" and entity.Data[key] ~= nil then
        return entity.Data[key]
    end
    if model then
        local ok, attr = pcall(function()
            return model:GetAttribute(key)
        end)
        if ok and attr ~= nil then
            return attr
        end
        local towerRep = model:FindFirstChild("TowerReplicator")
        if towerRep then
            ok, attr = pcall(function()
                return towerRep:GetAttribute(key)
            end)
            if ok and attr ~= nil then
                return attr
            end
            local child = towerRep:FindFirstChild(key)
            if child and child:IsA("ValueBase") then
                ok, attr = pcall(function()
                    return child.Value
                end)
                if ok and attr ~= nil then
                    return attr
                end
            end
        end
        local child = model:FindFirstChild(key)
        if child and child:IsA("ValueBase") then
            ok, attr = pcall(function()
                return child.Value
            end)
            if ok and attr ~= nil then
                return attr
            end
        end
    end
    return nil
end

function gatlingGetAmmoState(entity, model)
    local ammo = tonumber(gatlingGetStateFallback(entity, model, "Ammo"))
    local maxAmmo = tonumber(gatlingGetStateFallback(entity, model, "MaxAmmo"))
    local reloadingValue = gatlingGetStateFallback(entity, model, "Reloading")
    local reloading = reloadingValue == true or tostring(reloadingValue):lower() == "true"
    return ammo, maxAmmo, reloading
end

function gatlingGetCooldown(entity)
    local cd = tonumber(gatlingGetState(entity, "Cooldown"))
    if cd then
        return cd
    end
    local ok, statsCd = pcall(function()
        return entity and entity.Stats and entity.Stats.Attributes and entity.Stats.Attributes.Cooldown
    end)
    return tonumber(ok and statsCd) or 0.09
end

function gatlingGetDamage(entity, model)
    local damage = tonumber(gatlingGetStateFallback(entity, model, "Damage"))
        or tonumber(gatlingGetStateFallback(entity, model, "BaseDamage"))
    if damage and damage > 0 then
        return damage
    end
    local ok, statsDamage = pcall(function()
        local stats = entity and entity.Stats
        if type(stats) ~= "table" then
            return nil
        end
        return stats.Damage or (stats.Attributes and stats.Attributes.Damage)
    end)
    damage = tonumber(ok and statsDamage)
    if damage and damage > 0 then
        return damage
    end

    local towerName = resolveOwnedTowerName(model, entity)
    local level = tonumber(gatlingGetStateFallback(entity, model, "Upgrade"))
        or tonumber(gatlingGetStateFallback(entity, model, "Level"))
        or 0
    local content = ReplicatedStorage:FindFirstChild("Content")
    local towerFolder = content and content:FindFirstChild("Tower")
    local tower = towerFolder and towerFolder:FindFirstChild(tostring(towerName or ""))
    local statsModule = tower and tower:FindFirstChild("Stats")
    if statsModule then
        local data = safeRequire(statsModule, "Content.Tower.Stats")
        local defaultStats = data and data.Stats and data.Stats.Default
        local upgrades = defaultStats and defaultStats.Upgrades
        local upgradeData = upgrades and upgrades[math.max(0, math.floor(level))]
        local upgradeStats = upgradeData and upgradeData.Stats
        damage = tonumber(upgradeStats and (upgradeStats.Damage or upgradeStats.BaseDamage))
        if damage and damage > 0 then
            return damage
        end
        local defaults = defaultStats and defaultStats.Defaults
        damage = tonumber(defaults and (defaults.Damage or defaults.BaseDamage))
        if damage and damage > 0 then
            return damage
        end
    end

    if tostring(towerName or ""):lower():find("gatling", 1, true) then
        local upgradeDamage = {
            [0] = 5,
            [1] = 8,
            [2] = 12,
            [3] = 13,
            [4] = 20,
            [5] = 36,
            [6] = 67,
        }
        local upgrade = math.clamp(math.floor(level), 0, 6)
        return upgradeDamage[upgrade] or 67
    end

    return 5
end

gatlingPendingShots = {}

function gatlingTargetKey(target)
    return target and (target.rep or target.entity or target.npc)
end

function gatlingGetShotMemory(target, now)
    local key = gatlingTargetKey(target)
    if not key then
        return nil
    end
    if typeof(key) == "Instance" and not key.Parent then
        gatlingPendingShots[key] = nil
        return nil
    end

    local hp = math.max(0, tonumber(target and target.hp) or 0)
    local pending = gatlingPendingShots[key]
    if not pending then
        pending = { shots = 0, lastHp = hp, lastShotAt = 0 }
        gatlingPendingShots[key] = pending
    elseif
        hp < (tonumber(pending.lastHp) or hp) - 0.01
        or now - (tonumber(pending.lastShotAt) or 0) > GATLING_WEAK_CONFIRM_TTL
    then
        pending.shots = 0
        pending.lastHp = hp
    else
        pending.lastHp = hp
    end
    return pending
end

function gatlingRegisterPlannedShot(target, now)
    local pending = gatlingGetShotMemory(target, now)
    if not pending then
        return
    end
    pending.shots += 1
    pending.lastShotAt = now
end

function gatlingEffectiveDamage(target, bulletDamage)
    local defense = math.clamp(tonumber(target and target.defense) or 0, 0, 95)
    return math.max(1, (tonumber(bulletDamage) or 1) * (1 - defense / 100))
end

function gatlingShotsNeeded(target, bulletDamage, now, usePending)
    local hp = math.max(0, tonumber(target and target.hp) or 0)
    local effectiveDamage = gatlingEffectiveDamage(target, bulletDamage)
    if hp <= 0 then
        return 0, 0, effectiveDamage
    end

    local lethalShots = math.max(1, math.ceil(hp / effectiveDamage))
    local buffer = lethalShots > 1 and GATLING_OVERKILL_SHOTS or 0
    local needed = lethalShots + buffer
    if usePending and now then
        local pending = gatlingGetShotMemory(target, now)
        needed = math.max(0, needed - (pending and pending.shots or 0))
    end
    return needed, lethalShots, effectiveDamage
end

function gatlingShouldDumpTarget(target, lethalShots, effectiveDamage)
    if not target then
        return false
    end
    lethalShots = tonumber(lethalShots) or 0
    effectiveDamage = math.max(1, tonumber(effectiveDamage) or 1)
    local hp = math.max(0, tonumber(target.hp) or 0)
    local maxHp = math.max(hp, tonumber(target.maxHp) or 0)
    local shield = math.max(0, tonumber(target.shield) or 0)
    if lethalShots >= GATLING_TANK_SHOT_THRESHOLD then
        return true
    end
    if hp >= effectiveDamage * GATLING_TANK_SHOT_THRESHOLD then
        return true
    end
    if shield >= effectiveDamage * 3 then
        return true
    end
    if maxHp >= effectiveDamage * (GATLING_TANK_SHOT_THRESHOLD * 2) and hp >= effectiveDamage * 4 then
        return true
    end
    local name = tostring(target.name or ""):lower()
    return name:find("boss", 1, true)
        or name:find("tank", 1, true)
        or name:find("breaker", 1, true)
        or name:find("fallen", 1, true)
        or name:find("molten", 1, true)
        or name:find("lead", 1, true)
end

function gatlingTargetAimPosition(target)
    if not target then
        return nil
    end
    local model = nil
    if type(target.entity) == "table" and typeof(target.entity.Model) == "Instance" then
        model = target.entity.Model
    elseif typeof(target.npc) == "Instance" and target.npc:IsA("Model") then
        model = target.npc
    end
    if model then
        local head = model:FindFirstChild("Head")
        if head and head:IsA("BasePart") then
            return head.Position, true
        end
        local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
        if torso and torso:IsA("BasePart") then
            return torso.Position, true
        end
        local root = gatlingGetRoot(model)
        if root then
            local lift = math.clamp(root.Size.Y * 0.45, 0.35, 1.35)
            return root.Position + Vector3.new(0, lift, 0), true
        end
    end
    return target.pos, false
end

function gatlingPredictAim(target, originPos, shotIndex, fireRate)
    if not target or typeof(target.pos) ~= "Vector3" then
        return nil
    end
    local pos, preciseAim = gatlingTargetAimPosition(target)
    pos = pos or target.pos
    local vel = target.vel
    if typeof(vel) ~= "Vector3" then
        vel = Vector3.zero
    end

    local distance = originPos and (pos - originPos).Magnitude or tonumber(target.distance) or 0
    local lead = math.clamp(distance / 450, GATLING_AIM_LEAD_MIN, GATLING_AIM_LEAD_MAX)
    lead += math.min(0.035, (tonumber(shotIndex) or 0) / math.max(tonumber(fireRate) or 60, 1) * 0.15)
    if vel.Magnitude > 0.05 then
        pos += vel * lead
    end
    local lift = preciseAim and 0 or math.clamp(distance / 260, 0.08, 0.45)
    return pos + Vector3.new(0, lift, 0)
end

function gatlingCurrentEventCap()
    if gatlingLastCandidateCount >= GATLING_HEAVY_ENEMY_COUNT then
        return GATLING_HEAVY_EVENTS_PER_LOOP
    elseif gatlingLastCandidateCount >= GATLING_MEDIUM_ENEMY_COUNT then
        return GATLING_MEDIUM_EVENTS_PER_LOOP
    end
    return GATLING_MAX_EVENTS_PER_LOOP
end

function gatlingComputeBudget(now, ammo, firstTarget, bulletDamage)
    local fireRate = math.clamp(tonumber(gatlingFireRateTicks) or 60, GATLING_RATE_MIN, GATLING_RATE_MAX)
    local elapsedTicks = math.floor((now - gatlingLastFire) * fireRate)
    if elapsedTicks <= 0 then
        elapsedTicks = 1
        gatlingLastFire = now
    else
        elapsedTicks = math.min(elapsedTicks, GATLING_CATCHUP_TICKS)
        gatlingLastFire += elapsedTicks / fireRate
    end
    if now - gatlingLastFire > 0.18 then
        gatlingLastFire = now - (1 / fireRate)
    end

    local burst = math.max(1, math.floor(tonumber(gatlingBurstCount) or 1))
    local maxEvents = elapsedTicks * burst
    local _, firstLethalShots, firstEffectiveDamage = gatlingShotsNeeded(firstTarget, bulletDamage)
    local dumpPrimary = gatlingShouldDumpTarget(firstTarget, firstLethalShots, firstEffectiveDamage)
    if dumpPrimary then
        local ammoBudget = ammo and math.max(0, math.floor(ammo)) or GATLING_FAST_DUMP_MIN
        local dumpBudget = math.min(ammoBudget, math.max(GATLING_FAST_DUMP_MIN, burst * GATLING_FAST_DUMP_BURST_MULT))
        maxEvents = math.max(maxEvents, dumpBudget)
    end
    maxEvents = math.min(math.floor(maxEvents), gatlingCurrentEventCap())
    if ammo then
        maxEvents = math.min(maxEvents, math.max(0, math.floor(ammo)))
    end
    return maxEvents, burst, fireRate, dumpPrimary
end

function gatlingBuildShotPlan(targets, bulletDamage, maxEvents, dumpPrimary, now)
    local plan = {}
    local remaining = math.max(0, math.floor(tonumber(maxEvents) or 0))
    if remaining <= 0 then
        return plan
    end

    for index, target in ipairs(targets) do
        if remaining <= 0 then
            break
        end
        local rawNeeded, lethalShots, effectiveDamage = gatlingShotsNeeded(target, bulletDamage)
        if rawNeeded > 0 then
            local shouldDump = (index == 1 and dumpPrimary)
                or gatlingShouldDumpTarget(target, lethalShots, effectiveDamage)
            local needed = shouldDump and rawNeeded or gatlingShotsNeeded(target, bulletDamage, now, true)
            local shots = shouldDump and remaining or math.min(remaining, needed)
            if shots > 0 then
                plan[#plan + 1] = {
                    target = target,
                    shots = shots,
                    lethalShots = lethalShots,
                    effectiveDamage = effectiveDamage,
                    dump = shouldDump,
                }
                remaining -= shots
            end
        end
    end

    if remaining > 0 and plan[1] and plan[1].dump then
        plan[1].shots += remaining
    end
    return plan
end

function gatlingSendStop(remotes)
    if not remotes or not remotes.stop then
        return
    end
    local now = tick()
    if now - gatlingLastStop < 0.25 then
        return
    end
    gatlingLastStop = now
    pcall(function()
        remotes.stop:FireServer()
    end)
end

function gatlingSetHiddenFps(towerModel, enabled, remotes, abilityData)
    if not towerModel then
        return false
    end
    local ok = false
    local payload = type(abilityData) == "table" and abilityData or { enabled = enabled == true }
    if enabled then
        pcall(function()
            local callOk, result = invokeTroops("Abilities", "Activate", {
                Troop = towerModel,
                Name = "FPS",
                Data = payload,
            })
            ok = callOk and result ~= false
        end)
        if not ok then
            pcall(function()
                local callOk, result = invokeTroops("Abilities", "Activate", {
                    Troop = towerModel,
                    Index = "FPS",
                    Data = payload,
                })
                ok = callOk and result ~= false
            end)
        end
        if not ok then
            pcall(function()
                local callOk, result = invokeTroops("Abilities", "Activate", {
                    Troop = towerModel,
                    Index = "FPS",
                })
                ok = callOk and result ~= false
            end)
        end
    end
    if remotes and remotes.fps then
        pcall(function()
            remotes.fps:FireServer(enabled == true)
        end)
        ok = true
    end
    if ok then
        gatlingHiddenFpsArmed = enabled == true
        gatlingHiddenFpsTower = enabled and towerModel or nil
    end
    return ok
end

function gatlingCallLocalFps(entity, enabled)
    if not entity or type(entity.AbilityCallbacks) ~= "table" then
        return false
    end
    local cb = entity.AbilityCallbacks.FPS
    if type(cb) ~= "function" then
        return false
    end
    local ok, data = pcall(function()
        return cb(entity, enabled == true)
    end)
    if not ok then
        ok, data = pcall(function()
            return cb(nil, enabled == true)
        end)
    end
    return ok == true, data
end

function gatlingCallLocalExit(entity, remotes)
    local ok = false
    if entity and type(entity._inputCallbacks) == "table" and type(entity._inputCallbacks.EXIT) == "function" then
        ok = pcall(function()
            entity._inputCallbacks.EXIT(false)
        end)
    end
    if not ok then
        ok = gatlingCallLocalFps(entity, false)
        if remotes and remotes.fps then
            pcall(function()
                remotes.fps:FireServer(false)
            end)
        end
    end
    return ok == true
end

function gatlingSetLocalFiring(entity, enabled)
    enabled = enabled == true
    local targetEntity = entity or gatlingLocalFiringEntity
    if enabled and not targetEntity then
        gatlingLocalFiring = false
        gatlingLocalFiringEntity = nil
        return false
    end
    if gatlingLocalFiring == enabled and gatlingLocalFiringEntity == (enabled and targetEntity or nil) then
        if targetEntity then
            pcall(function()
                targetEntity._firing = enabled
            end)
        end
        return true
    end
    if gatlingLocalFiringEntity and gatlingLocalFiringEntity ~= targetEntity then
        local previous = gatlingLocalFiringEntity
        if type(previous._inputCallbacks) == "table" and type(previous._inputCallbacks.FIRE) == "function" then
            pcall(function()
                previous._inputCallbacks.FIRE(false)
            end)
        end
        pcall(function()
            previous._firing = false
        end)
    end
    local ok = false
    if
        targetEntity
        and type(targetEntity._inputCallbacks) == "table"
        and type(targetEntity._inputCallbacks.FIRE) == "function"
    then
        ok = pcall(function()
            targetEntity._inputCallbacks.FIRE(enabled)
        end)
    end
    if targetEntity then
        pcall(function()
            targetEntity._firing = enabled
        end)
    end
    gatlingLocalFiring = enabled
    gatlingLocalFiringEntity = enabled and targetEntity or nil
    return ok == true
end

function gatlingPatchLocalFireGun(entity)
    if type(entity) ~= "table" or gatlingPatchedFireGunEntities[entity] then
        return gatlingPatchedFireGunEntities[entity] ~= nil
    end
    local original = entity._fireGun
    if type(original) ~= "function" then
        return false
    end
    local hadRaw = rawget(entity, "_fireGun") ~= nil
    gatlingPatchedFireGunEntities[entity] = {
        original = original,
        hadRaw = hadRaw,
    }
    entity._fireGun = function(self, ...)
        if gatlingEnabled and gatlingLocalFiring then
            local aim = gatlingLastVisualAim
            if typeof(aim) == "Vector3" and type(self._fire) == "function" then
                pcall(function()
                    self:_fire(aim)
                end)
            end
            local waitTime = math.clamp(
                tonumber(gatlingFireDelay) or GATLING_VISUAL_FIRE_INTERVAL,
                GATLING_VISUAL_FIRE_INTERVAL,
                0.12
            )
            if type(self.Wait) == "function" then
                self:Wait(waitTime)
            else
                task.wait(waitTime)
            end
            return
        end
        return original(self, ...)
    end
    return true
end

function gatlingRestoreLocalFireGuns()
    for entity, record in pairs(gatlingPatchedFireGunEntities) do
        if type(entity) == "table" and type(record) == "table" then
            pcall(function()
                if record.hadRaw then
                    entity._fireGun = record.original
                else
                    entity._fireGun = nil
                end
            end)
        end
    end
    table.clear(gatlingPatchedFireGunEntities)
    gatlingLastVisualAim = nil
end

function gatlingTapLocalReload(entity, remotes)
    local ok = false
    if remotes and remotes.reload then
        ok = pcall(function()
            remotes.reload:FireServer()
        end) or ok
    end
    if entity and type(entity._inputCallbacks) == "table" and type(entity._inputCallbacks.RELOAD) == "function" then
        ok = pcall(function()
            entity._inputCallbacks.RELOAD(true)
        end)
    end
    return ok == true
end

function gatlingEnterReloadFps(towerModel, entity, remotes)
    if gatlingReloadFpsActive and gatlingReloadFpsTower == towerModel then
        return true
    end
    local alreadyLocalFps = false
    pcall(function()
        alreadyLocalFps = entity and entity._FPSEnabled == true
    end)
    local ok = alreadyLocalFps or gatlingActivateFpsLikeManual(towerModel)
    if not ok then
        local localOk, data = gatlingCallLocalFps(entity, true)
        local remoteOk = gatlingSetHiddenFps(towerModel, true, remotes, data)
        ok = localOk or remoteOk
    end
    if ok then
        gatlingReloadFpsActive = true
        gatlingReloadFpsEntity = entity
        gatlingReloadFpsTower = towerModel
        gatlingReloadFpsStarted = tick()
        gatlingReloadInputAt = tick()
    end
    return ok
end

function gatlingExitReloadFps(entity, remotes)
    if not gatlingReloadFpsActive then
        return
    end
    gatlingCallLocalExit(entity or gatlingReloadFpsEntity, remotes)
    gatlingReloadFpsActive = false
    gatlingReloadFpsEntity = nil
    gatlingReloadFpsTower = nil
    gatlingReloadFpsStarted = 0
    gatlingReloadInputAt = 0
    gatlingHiddenFpsArmed = false
    gatlingHiddenFpsTower = nil
end

function gatlingCurrentCacheTtl()
    if gatlingLastCandidateCount >= GATLING_HEAVY_ENEMY_COUNT then
        return GATLING_HEAVY_CACHE_TTL
    elseif gatlingLastCandidateCount >= GATLING_MEDIUM_ENEMY_COUNT then
        return GATLING_MEDIUM_CACHE_TTL
    end
    return GATLING_CACHE_TTL
end

function gatlingCollectTargets(originPos, limit)
    local now = tick()
    limit = math.clamp(math.floor(tonumber(limit) or 1), 1, 100)
    if gatlingLastCandidateCount >= GATLING_HEAVY_ENEMY_COUNT then
        limit = math.min(limit, 3)
    elseif gatlingLastCandidateCount >= GATLING_MEDIUM_ENEMY_COUNT then
        limit = math.min(limit, 5)
    end
    if now - gatlingCacheTime < gatlingCurrentCacheTtl() and gatlingCacheTargets and gatlingCacheLimit >= limit then
        local cached = {}
        for i = 1, math.min(limit, #gatlingCacheTargets) do
            local target = gatlingCacheTargets[i]
            if target and target.npc and (typeof(target.npc) ~= "Instance" or target.npc.Parent) then
                local refreshed = gatlingRefreshTargetData(target)
                if refreshed then
                    cached[#cached + 1] = refreshed
                    gatlingCacheTargets[i] = refreshed
                end
            end
        end
        if #cached > 0 or #gatlingCacheTargets == 0 then
            return cached
        end
    end

    local mode = tostring(gatlingTargetMode or "Boss"):lower()
    local needsScreenScore = mode:find("screen", 1, true) or mode:find("cross", 1, true)
    local camera = needsScreenScore and workspace.CurrentCamera or nil
    if needsScreenScore and not camera then
        return {}
    end
    local center = camera and Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2) or nil
    local targets = {}
    local targetLimit = math.clamp(math.floor(tonumber(limit) or 1), 1, 100)
    local candidateCount = 0
    local seen = {}
    local gotReplicatorSource = false

    local function targetComesBefore(a, b)
        if not b then
            return true
        end
        if a.score == b.score then
            return (a.pathDistance or 0) > (b.pathDistance or 0)
        end
        return (a.score or 0) < (b.score or 0)
    end

    local function insertTarget(data)
        targets[#targets + 1] = data
        local index = #targets
        while index > 1 and targetComesBefore(targets[index], targets[index - 1]) do
            targets[index], targets[index - 1] = targets[index - 1], targets[index]
            index -= 1
        end
        if #targets > targetLimit then
            targets[#targets] = nil
        end
    end

    local function addCandidate(data)
        if not data or not data.pos then
            return
        end
        local key = data.rep or data.npc or data.entity
        if key and seen[key] then
            return
        end
        if key then
            seen[key] = true
        end
        candidateCount += 1

        local screenDist = math.huge
        if needsScreenScore and camera then
            local screenPos, onScreen = camera:WorldToViewportPoint(data.pos)
            if onScreen and screenPos.Z > 0 then
                screenDist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
            end
        end
        local distance = originPos and (data.pos - originPos).Magnitude or screenDist
        local score
        if needsScreenScore then
            if screenDist == math.huge then
                return
            end
            score = screenDist
        elseif mode:find("close", 1, true) or mode:find("near", 1, true) then
            score = distance
        elseif mode:find("last", 1, true) then
            score = data.pathDistance
        elseif mode:find("weak", 1, true) or mode:find("low", 1, true) then
            score = (tonumber(data.hp) or 0) * 1000 + math.min(distance, 999)
        elseif mode:find("first", 1, true) or mode:find("lead", 1, true) or mode:find("path", 1, true) then
            score = -(tonumber(data.pathDistance) or 0) * 1000 + math.min(distance, 999)
        elseif mode:find("hp", 1, true) or mode:find("boss", 1, true) or mode:find("strong", 1, true) then
            score = -(tonumber(data.hp) or 0) * 1000 - (tonumber(data.pathDistance) or 0) + math.min(distance, 999)
        else
            score = -(tonumber(data.pathDistance) or 0) * 1000 + math.min(distance, 999)
        end
        data.score = score
        data.distance = distance
        data.screenDist = screenDist
        insertTarget(data)
    end

    local atoms = gatlingGetClientAtoms()
    if atoms and type(atoms.enemyReplicators) == "function" then
        local ok, enemyMap = pcall(function()
            return atoms.enemyReplicators()
        end)
        if ok and type(enemyMap) == "table" then
            for _, entity in pairs(enemyMap) do
                addCandidate(gatlingGetEntityTargetData(entity))
            end
            gotReplicatorSource = candidateCount > 0
        end
    end

    if not gotReplicatorSource then
        local folder = workspace:FindFirstChild("NPCs")
        if folder then
            for _, npc in ipairs(folder:GetChildren()) do
                if npc:IsA("Model") then
                    addCandidate(gatlingGetNPCData(npc))
                end
            end
            if candidateCount == 0 then
                for _, npc in ipairs(folder:GetDescendants()) do
                    if npc:IsA("Model") and npc:FindFirstChild("RootPointer") then
                        addCandidate(gatlingGetNPCData(npc))
                    end
                end
            end
        end

        local stateReps = ReplicatedStorage:FindFirstChild("StateReplicators")
        if stateReps then
            for _, rep in ipairs(stateReps:GetChildren()) do
                if rep.Name == "NPCReplicator" then
                    addCandidate(gatlingGetReplicatorTargetData(rep))
                end
            end
        end
    end
    gatlingLastCandidateCount = candidateCount
    gatlingCacheTime = now
    gatlingCacheTargets = targets
    gatlingCacheLimit = targetLimit
    return targets
end

function gatlingFindTarget(originPos)
    local targets = gatlingCollectTargets(originPos, 1)
    local target = targets[1]
    if not target then
        return nil, nil, nil, nil
    end
    return target.pos, target.vel, target.npc, target.hp
end

function gatlingTargetAdornee(target)
    if not target then
        return nil
    end
    local model = nil
    pcall(function()
        if target.entity and target.entity.Model then
            model = target.entity.Model
        end
    end)
    local candidate = model or target.npc
    if typeof(candidate) ~= "Instance" then
        return nil
    end
    if candidate:IsA("Model") or candidate:IsA("BasePart") then
        return candidate
    end
    return nil
end

function gatlingSetLine(folder, startPos, endPos, index, primary)
    local delta = endPos - startPos
    local length = delta.Magnitude
    if length <= 0.05 then
        return
    end
    local part = gatlingLineParts[index]
    if not part or not part.Parent then
        part = Instance.new("Part")
        part.Name = "ShotLine" .. tostring(index or "")
        part.Anchored = true
        part.CanCollide = false
        part.CanQuery = false
        part.CanTouch = false
        part.CastShadow = false
        part.Material = Enum.Material.Neon
        part.Parent = folder
        gatlingLineParts[index] = part
    end
    part.Color = primary and Color3.fromRGB(167, 139, 250) or Color3.fromRGB(56, 189, 248)
    part.Transparency = primary and 0.12 or 0.28
    local width = primary and 0.075 or 0.045
    part.Size = Vector3.new(width, width, length)
    part.CFrame = CFrame.lookAt((startPos + endPos) * 0.5, endPos)

    local dot = gatlingImpactDots[index]
    if not dot or not dot.Parent then
        dot = Instance.new("Part")
        dot.Name = "ImpactDot" .. tostring(index or "")
        dot.Anchored = true
        dot.CanCollide = false
        dot.CanQuery = false
        dot.CanTouch = false
        dot.CastShadow = false
        dot.Shape = Enum.PartType.Ball
        dot.Material = Enum.Material.Neon
        dot.Parent = folder
        gatlingImpactDots[index] = dot
    end
    dot.Color = primary and Color3.fromRGB(236, 72, 153) or Color3.fromRGB(125, 211, 252)
    dot.Transparency = primary and 0.08 or 0.25
    local dotSize = primary and 0.22 or 0.16
    dot.Size = Vector3.new(dotSize, dotSize, dotSize)
    dot.CFrame = CFrame.new(endPos)
end

function gatlingUpdateTargetVisuals(targets, originPos)
    local now = tick()
    if now - gatlingLastVisualAt < GATLING_VISUAL_UPDATE_INTERVAL then
        return
    end
    gatlingLastVisualAt = now
    local wantLines = gatlingBulletLinesEnabled == true
    local wantChams = tostring(gatlingTargetEsp or "Off"):lower() == "chams"
    if not wantLines and not wantChams then
        gatlingClearVisuals()
        return
    end

    local folder = gatlingEnsureVisualFolder()

    local active = {}
    local usedLineIndexes = {}
    local visualTargets = targets or {}
    for i = 1, math.min(#visualTargets, GATLING_VISUAL_TARGET_LIMIT) do
        local target = visualTargets[i]
        local adornee = gatlingTargetAdornee(target)
        if target and (adornee or (target.npc and target.npc.Parent)) then
            local key = adornee or target.npc
            active[key] = true
            if wantLines and originPos and target.pos and i <= GATLING_VISUAL_LINE_LIMIT then
                usedLineIndexes[i] = true
                gatlingSetLine(folder, originPos, target.pos, i, i == 1)
            end
            if wantChams and adornee then
                local highlight = gatlingTargetHighlights[key]
                if not highlight or not highlight.Parent then
                    highlight = Instance.new("Highlight")
                    highlight.Name = "ZephyrGatlingTarget"
                    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    highlight.Parent = folder
                    gatlingTargetHighlights[key] = highlight
                end
                highlight.Adornee = adornee
                highlight.FillColor = i == 1 and Color3.fromRGB(99, 102, 241) or Color3.fromRGB(14, 165, 233)
                highlight.OutlineColor = i == 1 and Color3.fromRGB(244, 114, 182) or Color3.fromRGB(226, 232, 240)
                highlight.FillTransparency = i == 1 and 0.62 or 0.78
                highlight.OutlineTransparency = i == 1 and 0 or 0.18
                highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            end
        end
    end

    if not wantLines then
        table.clear(usedLineIndexes)
    end
    for i, part in pairs(gatlingLineParts) do
        if not usedLineIndexes[i] then
            if part and part.Parent then
                part:Destroy()
            end
            gatlingLineParts[i] = nil
        end
    end
    for i, part in pairs(gatlingImpactDots) do
        if not usedLineIndexes[i] then
            if part and part.Parent then
                part:Destroy()
            end
            gatlingImpactDots[i] = nil
        end
    end

    for npc, highlight in pairs(gatlingTargetHighlights) do
        if not wantChams or not active[npc] or not npc.Parent then
            if highlight and highlight.Parent then
                highlight:Destroy()
            end
            gatlingTargetHighlights[npc] = nil
        end
    end
end

function gatlingUpdateHitsounds()
    if not gatlingHitsoundsDisabled then
        gatlingRestoreHitsounds()
        return
    end
    local now = tick()
    if now - gatlingLastSoundMuteAt < 10 then
        return
    end
    gatlingLastSoundMuteAt = now
    for _, root in ipairs({ SoundService, workspace }) do
        for _, inst in ipairs(root:GetDescendants()) do
            if inst:IsA("Sound") then
                local lname = inst.Name:lower()
                if lname:find("hit", 1, true) or lname:find("gatling", 1, true) then
                    if gatlingMutedSounds[inst] == nil then
                        gatlingMutedSounds[inst] = inst.Volume
                    end
                    pcall(function()
                        inst.Volume = 0
                    end)
                end
            end
        end
    end
end

function startGatling(guiParent, isMobile, C, toastFn)
    local remotes = getGatlingRemotes()
    local gatRemote = remotes and remotes.fire
    if not gatRemote then
        if toastFn then
            toastFn("Gatling waiting for game remotes", Color3.fromRGB(250, 204, 21))
        end
    end
    gatlingRestoreLocalFireGuns()
    gatlingEnabled = true
    gatlingPaused = false
    gatlingLastFire = tick() - 1
    gatlingCacheTime = 0
    gatlingCacheTargets = nil
    gatlingCacheLimit = 0
    gatlingLastAimReplicate = 0
    gatlingLastReload = 0
    gatlingLastFpsArm = 0
    gatlingLastVisualAt = 0
    gatlingLastLoopAt = 0
    gatlingLastUiUpdateAt = 0
    gatlingLastTowerScanAt = 0
    gatlingCachedTowerModel = nil
    gatlingCachedTowerEntity = nil
    gatlingSentThisSecond = 0
    gatlingSentLastSecond = 0
    gatlingSentWindowAt = tick()
    gatlingLastCandidateCount = 0
    gatlingLastTargets = {}
    gatlingHiddenFpsArmed = false
    gatlingHiddenFpsTower = nil
    gatlingZeroAmmoSince = 0
    gatlingWaitingForAmmo = false
    gatlingLocalFiring = false
    gatlingLocalFiringEntity = nil
    gatlingReloadFpsActive = false
    gatlingReloadFpsEntity = nil
    gatlingReloadFpsTower = nil
    gatlingReloadFpsStarted = 0
    gatlingReloadInputAt = 0
    gatlingReloadReleasedAt = 0
    table.clear(gatlingPendingShots)
    gatlingWatchTargetChanges()

    local mf = Instance.new("Frame", guiParent)
    mf.Name = "GatlingMini"
    mf.Size = isMobile and UDim2.new(0, 130, 0, 52) or UDim2.new(0, 175, 0, 52)
    mf.Position = isMobile and UDim2.new(0.5, -65, 0, 6) or UDim2.new(1, -185, 0, 10)
    mf.BackgroundColor3 = Color3.fromRGB(15, 16, 26)
    mf.BorderSizePixel = 0
    mf.ZIndex = 200
    mf.Active = true
    Instance.new("UICorner", mf).CornerRadius = UDim.new(0, 10)
    local mfS = Instance.new("UIStroke", mf)
    mfS.Color = Color3.fromRGB(99, 102, 241)
    mfS.Thickness = 1
    mfS.Transparency = 0.3

    local mfTitle = Instance.new("TextLabel", mf)
    mfTitle.Size = UDim2.new(1, -8, 0, 16)
    mfTitle.Position = UDim2.new(0, 8, 0, 4)
    mfTitle.BackgroundTransparency = 1
    mfTitle.Font = Enum.Font.GothamBold
    mfTitle.TextSize = isMobile and 10 or 11
    mfTitle.TextColor3 = Color3.fromRGB(99, 102, 241)
    mfTitle.TextXAlignment = Enum.TextXAlignment.Left
    mfTitle.Text = "GATLING GUN"
    mfTitle.ZIndex = 201

    local mfStatus = Instance.new("TextLabel", mf)
    mfStatus.Size = UDim2.new(1, -8, 0, 14)
    mfStatus.Position = UDim2.new(0, 8, 0, 20)
    mfStatus.BackgroundTransparency = 1
    mfStatus.Font = Enum.Font.GothamMedium
    mfStatus.TextSize = isMobile and 9 or 10
    mfStatus.TextColor3 = Color3.fromRGB(34, 197, 94)
    mfStatus.TextXAlignment = Enum.TextXAlignment.Left
    mfStatus.Text = "ACTIVE"
    mfStatus.ZIndex = 201
    local mfStatusText = "ACTIVE"
    local mfStatusColor = Color3.fromRGB(34, 197, 94)
    local function setMiniStatus(text, color)
        color = color or mfStatusColor
        if mfStatusText ~= text then
            mfStatusText = text
            mfStatus.Text = text
        end
        if mfStatusColor ~= color then
            mfStatusColor = color
            mfStatus.TextColor3 = color
        end
    end

    local mfRate = Instance.new("TextLabel", mf)
    mfRate.Size = UDim2.new(1, -8, 0, 14)
    mfRate.Position = UDim2.new(0, 8, 0, 34)
    mfRate.BackgroundTransparency = 1
    mfRate.Font = Enum.Font.Gotham
    mfRate.TextSize = isMobile and 8 or 9
    mfRate.TextColor3 = Color3.fromRGB(145, 155, 182)
    mfRate.TextXAlignment = Enum.TextXAlignment.Left
    mfRate.ZIndex = 201

    if isMobile then
        local pauseBtn = Instance.new("TextButton", mf)
        pauseBtn.Size = UDim2.new(0, 28, 0, 28)
        pauseBtn.Position = UDim2.new(1, -34, 0.5, -14)
        pauseBtn.BackgroundColor3 = Color3.fromRGB(30, 33, 50)
        pauseBtn.BorderSizePixel = 0
        pauseBtn.Text = "||"
        pauseBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
        pauseBtn.TextSize = 12
        pauseBtn.Font = Enum.Font.GothamBold
        pauseBtn.ZIndex = 202
        Instance.new("UICorner", pauseBtn).CornerRadius = UDim.new(0, 6)
        pauseBtn.MouseButton1Click:Connect(function()
            gatlingPaused = not gatlingPaused
            pauseBtn.Text = gatlingPaused and ">" or "||"
            setMiniStatus(
                gatlingPaused and "PAUSED" or "ACTIVE",
                gatlingPaused and Color3.fromRGB(250, 204, 21) or Color3.fromRGB(34, 197, 94)
            )
        end)
    else
        mfRate.Text = gatlingMode .. " | 0/s | P pause"
    end

    local function updateMiniRate(force)
        local now = tick()
        if not force and now - gatlingLastUiUpdateAt < GATLING_UI_UPDATE_INTERVAL then
            return
        end
        gatlingLastUiUpdateAt = now
        if isMobile then
            mfRate.Text = string.format("%s | %d/s | %dt", gatlingMode, gatlingSentLastSecond, #gatlingLastTargets)
        else
            mfRate.Text =
                string.format("%s | %d/s | %dt | P pause", gatlingMode, gatlingSentLastSecond, #gatlingLastTargets)
        end
    end

    local mDrag, mDragStart, mStartPos, mDragInp = false, nil, nil, nil
    mf.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
            mDrag = true
            mDragStart = input.Position
            mStartPos = mf.Position
            local ec
            ec = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    mDrag = false
                    if ec then
                        ec:Disconnect()
                    end
                end
            end)
        end
    end)
    mf.InputChanged:Connect(function(input)
        local t = input.UserInputType
        if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
            mDragInp = input
        end
    end)
    local miniDragConnection = UserInputService.InputChanged:Connect(function(input)
        if input == mDragInp and mDrag then
            local d = input.Position - mDragStart
            mf.Position =
                UDim2.new(mStartPos.X.Scale, mStartPos.X.Offset + d.X, mStartPos.Y.Scale, mStartPos.Y.Offset + d.Y)
        end
    end)
    mf.Destroying:Connect(function()
        miniDragConnection:Disconnect()
    end)
    gatlingMiniFrame = mf

    if not isMobile then
        gatlingKeybindConn = UserInputService.InputBegan:Connect(function(input, gp)
            if gp or not gatlingEnabled then
                return
            end
            if input.KeyCode == Enum.KeyCode.P then
                gatlingPaused = not gatlingPaused
                setMiniStatus(
                    gatlingPaused and "PAUSED" or "ACTIVE",
                    gatlingPaused and Color3.fromRGB(250, 204, 21) or Color3.fromRGB(34, 197, 94)
                )
            elseif input.KeyCode == Enum.KeyCode.F1 then
                setGatlingFireRate(gatlingFireRateTicks + 2)
            elseif input.KeyCode == Enum.KeyCode.F2 then
                setGatlingFireRate(gatlingFireRateTicks - 2)
            end
        end)
    end

    gatlingConnection = RunService.Heartbeat:Connect(function()
        if not gatlingEnabled then
            return
        end
        local now = tick()
        local activeLoopInterval = isMobile and GATLING_MOBILE_LOOP_INTERVAL or GATLING_LOOP_INTERVAL
        local loopInterval = gatlingPaused and GATLING_IDLE_INTERVAL or activeLoopInterval
        if now - gatlingLastLoopAt < loopInterval then
            return
        end
        gatlingLastLoopAt = now
        local liveRemotes = getGatlingRemotes()
        if gatlingPaused then
            gatlingSetLocalFiring(gatlingCachedTowerEntity, false)
            gatlingSendStop(liveRemotes)
            gatlingClearVisuals()
            updateMiniRate()
            return
        end
        local char = LocalPlayer.Character
        if not char then
            return
        end
        local myRoot = char:FindFirstChild("HumanoidRootPart")
        if not myRoot then
            return
        end
        now = tick()
        if now - gatlingSentWindowAt >= 1 then
            gatlingSentLastSecond = gatlingSentThisSecond
            gatlingSentThisSecond = 0
            gatlingSentWindowAt = now
        end
        local towerModel, towerEntity = gatlingGetOwnedTowerCached()
        local towerRoot = towerModel and getTowerRoot(towerModel) or nil
        local origin = towerRoot and towerRoot.Position or myRoot.Position
        gatlingUpdateHitsounds()

        if not towerModel then
            gatlingSetLocalFiring(gatlingCachedTowerEntity, false)
            gatlingCachedTowerModel = nil
            gatlingCachedTowerEntity = nil
            gatlingLastTowerScanAt = 0
            ownedTowerCache = nil
            ownedTowerCacheAt = 0
            setMiniStatus("WAIT GATLING", Color3.fromRGB(250, 204, 21))
            gatlingClearVisuals()
            if toastFn and now - gatlingNoTowerToastAt > 8 then
                gatlingNoTowerToastAt = now
                toastFn("Gatling waiting for tower", Color3.fromRGB(250, 204, 21))
            end
            updateMiniRate()
            return
        end

        if not liveRemotes or not liveRemotes.fire then
            setMiniStatus("NO REMOTE", Color3.fromRGB(250, 204, 21))
            gatlingSetLocalFiring(towerEntity, false)
            gatlingClearVisuals()
            updateMiniRate()
            return
        end

        local ammo, maxAmmo, reloading = gatlingGetAmmoState(towerEntity, towerModel)
        local fpsState = gatlingGetStateFallback(towerEntity, towerModel, "FPS")
        local fpsActive = gatlingIsTrue(fpsState) or (gatlingHiddenFpsArmed and gatlingHiddenFpsTower == towerModel)
        if gatlingWaitingForAmmo and ammo == nil then
            gatlingWaitingForAmmo = false
        end

        if not fpsActive then
            if now - gatlingLastFpsArm > GATLING_FPS_ARM_INTERVAL then
                gatlingLastFpsArm = now
                gatlingSetHiddenFps(towerModel, true, liveRemotes)
                fpsActive = gatlingHiddenFpsArmed and gatlingHiddenFpsTower == towerModel
            end
        end

        if not fpsActive and towerEntity then
            setMiniStatus("ARM FPS", Color3.fromRGB(250, 204, 21))
            gatlingLastTargets = {}
            gatlingSetLocalFiring(towerEntity, false)
            gatlingSendStop(liveRemotes)
            gatlingClearVisuals()
            updateMiniRate()
            return
        end

        setMiniStatus("FPS ACTIVE", Color3.fromRGB(34, 197, 94))
        if ammo and ammo <= 0 then
            if gatlingZeroAmmoSince <= 0 then
                gatlingZeroAmmoSince = now
            end
            gatlingWaitingForAmmo = true
            gatlingLastTargets = {}
            gatlingInvalidateTargets()
            gatlingClearVisuals()
            gatlingSetLocalFiring(towerEntity, false)
            gatlingSendStop(liveRemotes)
            if not reloading and now - gatlingLastReload > GATLING_RELOAD_POKE_INTERVAL then
                gatlingLastReload = now
                gatlingTapLocalReload(towerEntity, liveRemotes)
            end
            setMiniStatus(reloading and "RELOADING" or "NO AMMO", Color3.fromRGB(250, 204, 21))
            updateMiniRate()
            return
        else
            if gatlingZeroAmmoSince > 0 then
                gatlingZeroAmmoSince = 0
                gatlingReloadReleasedAt = 0
                gatlingLastFpsArm = 0
                gatlingLastFire = now - (1 / math.max(tonumber(gatlingFireRateTicks) or 60, 1))
            end
            gatlingWaitingForAmmo = false
        end
        if reloading then
            gatlingLastTargets = {}
            gatlingInvalidateTargets()
            gatlingClearVisuals()
            gatlingSetLocalFiring(towerEntity, false)
            gatlingSendStop(liveRemotes)
            setMiniStatus("RELOADING", Color3.fromRGB(250, 204, 21))
            updateMiniRate()
            return
        end

        local targets = gatlingCollectTargets(origin, gatlingMaxTargets)
        gatlingLastTargets = targets
        if
            gatlingBulletLinesEnabled == true
            or tostring(gatlingTargetEsp or "Off"):lower() == "chams"
            or gatlingVisualFolder ~= nil
        then
            gatlingUpdateTargetVisuals(targets, origin)
        end
        if #targets == 0 then
            gatlingSetLocalFiring(towerEntity, false)
            gatlingSendStop(liveRemotes)
            setMiniStatus("NO TARGET", Color3.fromRGB(250, 204, 21))
            updateMiniRate()
            return
        end

        local firstTarget = targets[1]
        local firePos = firstTarget and gatlingPredictAim(firstTarget, origin, 0, gatlingFireRateTicks)
        gatlingLastVisualAim = firePos
        local localVisualsOk = gatlingPatchLocalFireGun(towerEntity)
        gatlingSetLocalFiring(towerEntity, localVisualsOk)
        if liveRemotes and liveRemotes.aim and firePos and now - gatlingLastAimReplicate >= 0.015 then
            gatlingLastAimReplicate = now
            pcall(function()
                liveRemotes.aim:FireServer(firePos)
            end)
        end

        local bulletDamage = gatlingGetDamage(towerEntity, towerModel)
        local maxEvents, _, fireRate, dumpPrimary = gatlingComputeBudget(now, ammo, firstTarget, bulletDamage)
        if maxEvents <= 0 then
            gatlingSetLocalFiring(towerEntity, false)
            updateMiniRate()
            return
        end
        local plan = gatlingBuildShotPlan(targets, bulletDamage, maxEvents, dumpPrimary, now)
        if #plan == 0 then
            gatlingSetLocalFiring(towerEntity, false)
            updateMiniRate()
            return
        end
        local firedThisLoop = 0
        local fireRemote = liveRemotes.fire or gatRemote
        local shotSyncBase = tonumber(workspace:GetAttribute("Sync")) or tonumber(gatlingSyncValue) or 0
        local shotTimeBase = workspace:GetServerTimeNow()
        for _, item in ipairs(plan) do
            local target = item.target
            for _ = 1, item.shots do
                local aimPoint = gatlingPredictAim(target, origin, firedThisLoop, fireRate) or target.pos
                gatlingLastVisualAim = aimPoint
                local shotTime = shotTimeBase + (firedThisLoop * 0.00025)
                local ok = pcall(function()
                    fireRemote:FireServer(aimPoint, shotSyncBase, shotTime)
                end)
                if ok then
                    firedThisLoop += 1
                    gatlingSentThisSecond += 1
                    if not item.dump then
                        gatlingRegisterPlannedShot(target, now)
                    end
                end
            end
        end
        if firedThisLoop > 0 then
            setMiniStatus(
                dumpPrimary and "DUMPING" or (#plan > 1 and "SMART FIRE" or "FIRING"),
                dumpPrimary and Color3.fromRGB(167, 139, 250) or Color3.fromRGB(34, 197, 94)
            )
            if
                ammo
                and firedThisLoop >= math.max(1, math.floor(ammo))
                and now - gatlingLastReload > GATLING_RELOAD_POKE_INTERVAL
            then
                gatlingWaitingForAmmo = true
                gatlingLastReload = now
                gatlingTapLocalReload(towerEntity, liveRemotes)
                setMiniStatus("FAST RELOAD", Color3.fromRGB(250, 204, 21))
            end
        end
        updateMiniRate()
    end)
    return true
end

function stopGatling()
    local remotes = getGatlingRemotes()
    if gatlingReloadFpsActive then
        gatlingExitReloadFps(gatlingReloadFpsEntity, remotes)
    end
    gatlingSetLocalFiring(gatlingCachedTowerEntity or gatlingReloadFpsEntity, false)
    gatlingSendStop(remotes)
    if gatlingHiddenFpsArmed then
        gatlingSetHiddenFps(gatlingHiddenFpsTower, false, remotes)
    end
    gatlingRestoreLocalFireGuns()
    gatlingEnabled = false
    gatlingPaused = false
    gatlingCacheTargets = nil
    gatlingCacheTime = 0
    gatlingCacheLimit = 0
    gatlingLastCandidateCount = 0
    gatlingLastTargets = {}
    gatlingCachedTowerModel = nil
    gatlingCachedTowerEntity = nil
    gatlingLastTowerScanAt = 0
    gatlingHiddenFpsArmed = false
    gatlingHiddenFpsTower = nil
    gatlingZeroAmmoSince = 0
    gatlingWaitingForAmmo = false
    gatlingLocalFiring = false
    gatlingLocalFiringEntity = nil
    gatlingReloadFpsActive = false
    gatlingReloadFpsEntity = nil
    gatlingReloadFpsTower = nil
    gatlingReloadFpsStarted = 0
    gatlingReloadInputAt = 0
    table.clear(gatlingPendingShots)
    if gatlingConnection then
        gatlingConnection:Disconnect()
        gatlingConnection = nil
    end
    if gatlingKeybindConn then
        gatlingKeybindConn:Disconnect()
        gatlingKeybindConn = nil
    end
    gatlingDisconnectTargetWatchers()
    if gatlingMiniFrame and gatlingMiniFrame.Parent then
        gatlingMiniFrame:Destroy()
    end
    gatlingMiniFrame = nil
    gatlingClearVisuals()
    gatlingRestoreHitsounds()
end

-- Airstrike
AIRSTRIKE_RADIUS = 12
AIRSTRIKE_LOCAL_COOLDOWN = 45
AIRSTRIKE_LEAD_SECONDS = 0.55
AIRSTRIKE_LEAD_MIN = 2.5
AIRSTRIKE_LEAD_MAX = 7.5
AIRSTRIKE_LOOP_INTERVAL = 0.35
AIRSTRIKE_BASE_SCAN_INTERVAL = 0.85
airstrikeGameState = nil
airstrikeGameStateChecked = false
airstrikeEnemyFlagCache = {}
airstrikeModifierIds = {
    hidden = 2,
    lead = 5,
    boss = 10,
}

function airstrikeResolvePathAt(pos, fallbackTarget)
    if typeof(pos) ~= "Vector3" then
        return nil, nil, nil
    end
    if not airstrikeGameStateChecked then
        airstrikeGameStateChecked = true
        airstrikeGameState = GameState
            or safeRequirePath("Shared.Modules.GameState", ReplicatedStorage, "Shared", "Modules", "GameState")
    end
    local pathsByTeam = airstrikeGameState and airstrikeGameState.Paths
    if type(pathsByTeam) ~= "table" then
        return fallbackTarget and fallbackTarget.pathName,
            fallbackTarget and fallbackTarget.pathToEnd,
            fallbackTarget and fallbackTarget.path
    end

    local bestName, bestToEnd, bestPath, bestDistance = nil, nil, nil, math.huge
    for _, paths in pairs(pathsByTeam) do
        if type(paths) == "table" then
            for pathName, path in pairs(paths) do
                if tonumber(pathName) and path and type(path.GetClosestPoint) == "function" then
                    local ok, closest, pointToEnd = pcall(function()
                        return path:GetClosestPoint(pos)
                    end)
                    if ok and typeof(closest) == "Vector3" then
                        local distance = (closest - pos).Magnitude
                        if distance < bestDistance then
                            bestName = pathName
                            bestToEnd = pointToEnd
                            bestPath = path
                            bestDistance = distance
                        end
                    end
                end
            end
        end
    end
    return bestName or (fallbackTarget and fallbackTarget.pathName),
        bestToEnd or (fallbackTarget and fallbackTarget.pathToEnd),
        bestPath or (fallbackTarget and fallbackTarget.path)
end

function airstrikeResolvePath(target)
    if not target or typeof(target.pos) ~= "Vector3" then
        return nil, nil, nil
    end
    return airstrikeResolvePathAt(target.pos, target)
end

function airstrikeValueHasFlag(value, flag, depth)
    depth = (tonumber(depth) or 0)
    if depth > 3 then
        return false
    end
    flag = tostring(flag or ""):lower()
    local modifierId = airstrikeModifierIds[flag]
    if value == nil then
        return false
    end
    if modifierId and tonumber(value) == modifierId then
        return true
    end
    if type(value) == "string" then
        return value:lower():find(flag, 1, true) ~= nil
    end
    if type(value) == "table" then
        for key, item in pairs(value) do
            if airstrikeValueHasFlag(key, flag, depth + 1) and item ~= false then
                return true
            end
            if airstrikeValueHasFlag(item, flag, depth + 1) then
                return true
            end
        end
    end
    return false
end

function airstrikeStatsHasFlag(stats, flag)
    if type(stats) ~= "table" then
        return false
    end
    local cap = flag:sub(1, 1):upper() .. flag:sub(2)
    if gatlingIsTrue(stats[flag]) or gatlingIsTrue(stats[cap]) then
        return true
    end
    if airstrikeValueHasFlag(stats.Attributes, flag) then
        return true
    end
    if airstrikeValueHasFlag(stats.Modifiers, flag) then
        return true
    end
    if airstrikeValueHasFlag(stats.ModifiersGiven, flag) then
        return true
    end
    return false
end

function airstrikeFindEnemyStatsModule(enemyName)
    enemyName = tostring(enemyName or "")
    if enemyName == "" then
        return nil
    end
    local content = ReplicatedStorage:FindFirstChild("Content")
    if not content then
        return nil
    end
    local lowerName = enemyName:lower()
    for _, folderName in ipairs({ "NewEnemies", "Enemies" }) do
        local folder = content:FindFirstChild(folderName)
        local enemy = folder and folder:FindFirstChild(enemyName)
        if not enemy and folder then
            for _, child in ipairs(folder:GetChildren()) do
                if child.Name:lower() == lowerName then
                    enemy = child
                    break
                end
            end
        end
        local statsModule = enemy and enemy:FindFirstChild("Stats")
        if statsModule then
            return statsModule
        end
    end
    return nil
end

function airstrikeContentHasFlag(enemyName, flag)
    local key = tostring(enemyName or ""):lower() .. "\0" .. tostring(flag or ""):lower()
    if airstrikeEnemyFlagCache[key] ~= nil then
        return airstrikeEnemyFlagCache[key]
    end
    local statsModule = airstrikeFindEnemyStatsModule(enemyName)
    local hasFlag = false
    if statsModule then
        local stats = safeRequire(statsModule, "EnemyStats." .. tostring(enemyName))
        hasFlag = airstrikeStatsHasFlag(stats, flag)
    end
    airstrikeEnemyFlagCache[key] = hasFlag
    return hasFlag
end

function airstrikeTargetNames(target)
    local names = {}
    local seen = {}
    local function add(value)
        value = tostring(value or "")
        if value ~= "" and not seen[value] then
            seen[value] = true
            names[#names + 1] = value
        end
    end
    add(target and target.name)
    local rep = target and target.rep
    add(rep and gatlingRepValue(rep, "ModelName"))
    add(rep and gatlingRepValue(rep, "DisplayName"))
    add(rep and gatlingRepValue(rep, "Name"))
    local npc = target and target.npc
    if typeof(npc) == "Instance" then
        add(npc.Name)
        add(npc:GetAttribute("ModelName"))
        add(npc:GetAttribute("DisplayName"))
    end
    local entity = target and target.entity
    if type(entity) == "table" then
        add(entity.Name)
        add(entity.ModelName)
        add(entity.DisplayName)
        if entity.Model and typeof(entity.Model) == "Instance" then
            add(entity.Model.Name)
        end
    end
    return names
end

function airstrikeTargetHasFlag(target, flag)
    flag = tostring(flag or ""):lower()
    for _, name in ipairs(airstrikeTargetNames(target)) do
        if name:lower():find(flag, 1, true) then
            return true
        end
        if airstrikeContentHasFlag(name, flag) then
            return true
        end
    end
    local rep = target and target.rep
    local cap = flag:sub(1, 1):upper() .. flag:sub(2)
    if rep then
        for _, key in ipairs({ cap, flag }) do
            local value = gatlingRepValue(rep, key)
            if gatlingIsTrue(value) or airstrikeValueHasFlag(value, flag) then
                return true
            end
        end
        for _, key in ipairs({ "Modifiers", "Attributes", "Modifier", "DetectionModifiers", "Tags" }) do
            if airstrikeValueHasFlag(gatlingRepValue(rep, key), flag) then
                return true
            end
        end
    end
    local npc = target and target.npc
    if typeof(npc) == "Instance" then
        if gatlingIsTrue(npc:GetAttribute(cap)) or gatlingIsTrue(npc:GetAttribute(flag)) then
            return true
        end
        for _, childName in ipairs({ cap, flag, "Modifiers", "Attributes", "Tags" }) do
            local child = npc:FindFirstChild(childName)
            if child then
                if child:IsA("BoolValue") and child.Value == true then
                    return true
                end
                if child:IsA("StringValue") and airstrikeValueHasFlag(child.Value, flag) then
                    return true
                end
                if child:IsA("NumberValue") and airstrikeValueHasFlag(child.Value, flag) then
                    return true
                end
            end
        end
    end
    local entity = target and target.entity
    if type(entity) == "table" then
        if gatlingIsTrue(entity[flag]) or gatlingIsTrue(entity[cap]) then
            return true
        end
        if airstrikeValueHasFlag(entity.Modifiers, flag) then
            return true
        end
        if airstrikeValueHasFlag(entity.Attributes, flag) then
            return true
        end
        if airstrikeValueHasFlag(entity.StatusEffects, flag) then
            return true
        end
    end
    return false
end

function airstrikeGetTarget()
    local rawTargets = gatlingCollectTargets(nil, 100)
    local targets = {}
    for _, target in ipairs(rawTargets) do
        local pathName, pathToEnd, path = airstrikeResolvePath(target)
        if pathName ~= nil and pathToEnd ~= nil then
            target.pathName = pathName
            target.pathToEnd = pathToEnd
            target.path = path
            targets[#targets + 1] = target
        end
    end
    if #targets == 0 then
        return nil
    end
    local mode = tostring(autoAirstrikeTarget or "Grouped"):lower()

    if mode == "grouped" then
        local best, bestCount, bestHp, bestProgress = nil, 0, 0, -math.huge
        for _, center in ipairs(targets) do
            local count, hp = 0, 0
            for _, other in ipairs(targets) do
                if (center.pos - other.pos).Magnitude <= AIRSTRIKE_RADIUS then
                    count += 1
                    hp += tonumber(other.hp) or 0
                end
            end
            local progress = tonumber(center.pathDistance) or 0
            if
                count > bestCount
                or (count == bestCount and hp > bestHp)
                or (count == bestCount and hp == bestHp and progress > bestProgress)
            then
                best, bestCount, bestHp, bestProgress = center, count, hp, progress
            end
        end
        return best
    end

    local flag = mode == "lead" and "lead" or mode == "hidden" and "hidden" or "boss"
    local best = nil
    for _, target in ipairs(targets) do
        if airstrikeTargetHasFlag(target, flag) then
            if
                not best
                or (tonumber(target.hp) or 0) > (tonumber(best.hp) or 0)
                or (
                    (tonumber(target.hp) or 0) == (tonumber(best.hp) or 0)
                    and (tonumber(target.pathDistance) or 0) > (tonumber(best.pathDistance) or 0)
                )
            then
                best = target
            end
        end
    end
    return best
end

function getMilitaryBaseAirstrikeTowers()
    local bases = {}
    for _, towerInfo in ipairs(getOwnedTowerEntities()) do
        local cleanName = abilityKey(towerInfo.name):lower()
        if cleanName:find("militarybase", 1, true) and towerHasAbility(towerInfo, "Airstrike", 4) then
            bases[#bases + 1] = towerInfo
        end
    end
    return bases
end

airstrikePathController = nil
airstrikePathControllerChecked = false

function getAirstrikePathController()
    if airstrikePathControllerChecked then
        return airstrikePathController
    end
    airstrikePathControllerChecked = true
    airstrikePathController = safeRequirePath(
        "Client.Controllers.Game.PathPlacementCursorController",
        ReplicatedStorage,
        "Client",
        "Controllers",
        "Game",
        "PathPlacementCursorController"
    )
    return airstrikePathController
end

function airstrikeCleanupPlacement()
    local pathController = nil
    local okController, controller = pcall(getAirstrikePathController)
    if okController then
        pathController = controller
    end
    if pathController and type(pathController.Stop) == "function" then
        pcall(function()
            pathController:Stop()
        end)
    end
    pcall(function()
        for _, child in ipairs(workspace:GetChildren()) do
            if
                tostring(child.Name):lower():find("airstrike", 1, true)
                and tostring(child.Name):lower():find("crosshair", 1, true)
            then
                pcall(function()
                    child:Destroy()
                end)
            end
        end
    end)
end

function airstrikeScheduleCleanup(delaySeconds)
    task.defer(function()
        task.wait(tonumber(delaySeconds) or 0.08)
        airstrikeCleanupPlacement()
        task.wait(0.25)
        airstrikeCleanupPlacement()
    end)
end

function airstrikeTargetSpeed(target)
    local speed = tonumber(target and target.speed)
    if not speed and target and typeof(target.vel) == "Vector3" and target.vel.Magnitude > 0.1 then
        speed = target.vel.Magnitude
    end
    local rep = target and target.rep
    if not speed and rep then
        speed = tonumber(
            gatlingRepValue(rep, "Speed") or gatlingRepValue(rep, "ForceSpeed") or gatlingRepValue(rep, "WalkSpeed")
        )
    end
    local entity = target and target.entity
    if not speed and type(entity) == "table" then
        speed = tonumber(entity.Speed) or tonumber(entity.ForceSpeed) or tonumber(entity.WalkSpeed)
    end
    return math.clamp(tonumber(speed) or 7, 0, 24)
end

function airstrikeLeadTarget(target)
    local pathName, pathToEnd, path = airstrikeResolvePath(target)
    if pathName == nil or pathToEnd == nil then
        return nil
    end
    local pos = target.pos
    local speed = airstrikeTargetSpeed(target)
    local leadDistance = math.clamp(speed * AIRSTRIKE_LEAD_SECONDS, AIRSTRIKE_LEAD_MIN, AIRSTRIKE_LEAD_MAX)
    if path and type(path.GetScalar) == "function" then
        local pathDistance = tonumber(target.pathDistance)
        local derivedDistance = nil
        if tonumber(pathToEnd) and tonumber(path.PathDistance) then
            derivedDistance = tonumber(path.PathDistance) - tonumber(pathToEnd)
        end
        if
            derivedDistance and (not pathDistance or pathDistance <= 0 or math.abs(pathDistance - derivedDistance) > 12)
        then
            pathDistance = derivedDistance
        end
        if pathDistance then
            local maxPathDistance = tonumber(path.PathDistance) or (pathDistance + leadDistance)
            local wantedDistance = math.clamp(pathDistance + leadDistance, 0, maxPathDistance)
            local ok, aheadPos = pcall(function()
                return path:GetScalar(wantedDistance)
            end)
            if ok and typeof(aheadPos) == "Vector3" then
                pos = aheadPos
                if type(path.GetDistanceToEnd) == "function" then
                    local okToEnd, aheadToEnd = pcall(function()
                        return path:GetDistanceToEnd(wantedDistance)
                    end)
                    if okToEnd and aheadToEnd ~= nil then
                        pathToEnd = aheadToEnd
                    end
                else
                    pathToEnd = math.max(0, (tonumber(path.PathDistance) or wantedDistance) - wantedDistance)
                end
            end
        end
    elseif typeof(target.vel) == "Vector3" and target.vel.Magnitude > 0.1 then
        pos = pos + target.vel.Unit * leadDistance
        local resolvedName, resolvedToEnd, resolvedPath = airstrikeResolvePathAt(pos, target)
        pathName = resolvedName or pathName
        pathToEnd = resolvedToEnd or pathToEnd
        path = resolvedPath or path
    end
    return {
        source = target,
        pos = pos,
        pathName = pathName,
        pathToEnd = pathToEnd,
        path = path,
    }
end

function airstrikeUse(towerInfo, target)
    if not towerInfo or not target or typeof(target.pos) ~= "Vector3" then
        return false
    end
    local aim = airstrikeLeadTarget(target)
    if not aim then
        return false
    end
    local pathName, pathToEnd = aim.pathName, aim.pathToEnd
    if pathName == nil or pathToEnd == nil then
        return false
    end
    local camera = workspace.CurrentCamera
    local cameraPos = camera and camera.CFrame.Position or aim.pos + Vector3.new(0, 20, 0)
    local directionCFrame = CFrame.lookAt(aim.pos, Vector3.new(cameraPos.X, aim.pos.Y, cameraPos.Z))

    -- Military Base's ability callback builds the placement data first.
    local stores = gatlingGetStores()
    local useAbility = stores
        and stores.AbilitiesStore
        and stores.AbilitiesStore.events
        and stores.AbilitiesStore.events.UseAbility
    local pathController = getAirstrikePathController()
    if
        useAbility
        and type(useAbility.Fire) == "function"
        and pathController
        and pathController.OnClicked
        and type(pathController.OnClicked.Fire) == "function"
    then
        local started = pcall(function()
            pathController.CurrentPosition = aim.pos
            pathController.CurrentPathToEnd = pathToEnd
            useAbility:Fire(towerInfo.model, "Airstrike")
        end)
        if started then
            local waitStarted = tick()
            repeat
                task.wait()
            until pathController.active == true or tick() - waitStarted >= 0.3
            if pathController.active == true then
                local completed = pcall(function()
                    pathController.CurrentPosition = aim.pos
                    pathController.CurrentPathToEnd = pathToEnd
                    pathController.OnClicked:Fire(pathName, pathToEnd, aim.pos)
                end)
                airstrikeScheduleCleanup(0.08)
                if completed then
                    return true
                end
            end
            airstrikeCleanupPlacement()
        end
    end

    local ok, result = invokeTroopsThrottled("Abilities", "Activate", {
        Troop = towerInfo.model,
        Name = "Airstrike",
        Data = {
            pathName = pathName,
            pointToEnd = pathToEnd,
            directionCFrame = directionCFrame,
        },
    })
    if ok ~= true or result == false then
        return false
    end
    if type(result) == "string" and result ~= "" then
        return false
    end
    return true
end

function startAutoAirstrike()
    if autoAirstrikeThread then
        pcall(function()
            task.cancel(autoAirstrikeThread)
        end)
    end
    autoAirstrikeEnabled = true
    local localCooldowns = {}
    local bases = {}
    local nextBaseScan = 0
    autoAirstrikeThread = task.spawn(function()
        while autoAirstrikeEnabled do
            local now = tick()
            if now >= nextBaseScan then
                bases = getMilitaryBaseAirstrikeTowers()
                nextBaseScan = now + AIRSTRIKE_BASE_SCAN_INTERVAL
            end
            local readyBases = {}
            for _, towerInfo in ipairs(bases) do
                local model = towerInfo.model
                if model and model.Parent then
                    local remaining, known = getTowerAbilityCooldownRemaining(towerInfo, "Airstrike")
                    local localReady = not localCooldowns[model] or now >= localCooldowns[model]
                    if localReady and (not known or not remaining or remaining <= 0.1) then
                        readyBases[#readyBases + 1] = towerInfo
                    elseif remaining and remaining > 0.1 then
                        localCooldowns[model] = now + math.min(remaining, AIRSTRIKE_LOCAL_COOLDOWN)
                    end
                end
            end
            if #readyBases > 0 then
                local target = airstrikeGetTarget()
                if target then
                    for _, towerInfo in ipairs(readyBases) do
                        local model = towerInfo.model
                        if model and model.Parent then
                            if airstrikeUse(towerInfo, target) then
                                localCooldowns[model] = now + AIRSTRIKE_LOCAL_COOLDOWN
                            else
                                localCooldowns[model] = now + 1.25
                            end
                        end
                    end
                end
            end
            for model in pairs(localCooldowns) do
                if not model.Parent then
                    localCooldowns[model] = nil
                end
            end
            task.wait(AIRSTRIKE_LOOP_INTERVAL)
        end
    end)
end

stopAutoAirstrike = function()
    autoAirstrikeEnabled = false
    local thread = autoAirstrikeThread
    autoAirstrikeThread = nil
    if thread then
        pcall(function()
            task.cancel(thread)
        end)
    end
    pcall(airstrikeCleanupPlacement)
end

PURSUIT_CLUSTER_RADIUS = 18
PURSUIT_LOCAL_COOLDOWN = 2.25
PURSUIT_MIN_REPOSITION_DISTANCE = 10
PURSUIT_POSITION_PAYLOAD_KEYS = { "Position", "position", "Point", "point", "TargetPosition", "targetPosition" }
PURSUIT_FALLBACK_ABILITIES = { "Retarget", "Move", "Patrol", "Pursuit Move", "Reposition" }

function getPursuitTowers()
    local pursuits = {}
    for _, towerInfo in ipairs(getOwnedTowerEntities()) do
        local lowerName = tostring(towerInfo.name or ""):lower()
        if lowerName:find("pursuit", 1, true) or lowerName:find("persuit", 1, true) then
            pursuits[#pursuits + 1] = towerInfo
        end
    end
    return pursuits
end

function getPursuitAbilityNames(towerInfo)
    local names = {}
    local seen = {}
    local function add(name)
        name = tostring(name or "")
        if name == "" then
            return
        end
        local clean = abilityKey(name):lower()
        if clean == "" or seen[clean] then
            return
        end
        if
            clean:find("retarget", 1, true)
            or clean:find("move", 1, true)
            or clean:find("patrol", 1, true)
            or clean:find("position", 1, true)
            or clean:find("reposition", 1, true)
        then
            seen[clean] = true
            names[#names + 1] = name
        end
    end

    local available = towerInfo and towerInfo.entity and towerInfo.entity.AvailableAbilities
    if type(available) == "table" then
        for key, ability in pairs(available) do
            add(key)
            if type(ability) == "table" then
                add(ability.Name)
                add(ability.Id)
                add(ability.ID)
                add(ability.DisplayName)
                add(ability.Title)
            else
                add(ability)
            end
        end
    end
    for _, name in ipairs(PURSUIT_FALLBACK_ABILITIES) do
        add(name)
    end
    return names
end

function getAutoPursuitTarget()
    local targets = gatlingCollectTargets(nil, 100)
    if #targets == 0 then
        return nil
    end
    local mode = tostring(tdsSettings.autoPursuitPositionTarget or "Grouped"):lower()

    if mode == "grouped" then
        local best, bestCount, bestHp, bestProgress = nil, 0, 0, -math.huge
        for _, center in ipairs(targets) do
            local count, hp = 0, 0
            for _, other in ipairs(targets) do
                if center.pos and other.pos and (center.pos - other.pos).Magnitude <= PURSUIT_CLUSTER_RADIUS then
                    count += 1
                    hp += tonumber(other.hp) or 0
                end
            end
            local progress = tonumber(center.pathDistance) or 0
            if
                count > bestCount
                or (count == bestCount and hp > bestHp)
                or (count == bestCount and hp == bestHp and progress > bestProgress)
            then
                best, bestCount, bestHp, bestProgress = center, count, hp, progress
            end
        end
        return best or targets[1]
    end

    local best = nil
    for _, target in ipairs(targets) do
        if target.pos then
            if not best then
                best = target
            elseif mode == "boss" or mode == "strong" then
                if (tonumber(target.hp) or 0) > (tonumber(best.hp) or 0) then
                    best = target
                end
            elseif mode == "closest" then
                local char = LocalPlayer.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                local origin = root and root.Position
                if origin and (target.pos - origin).Magnitude < (best.pos - origin).Magnitude then
                    best = target
                end
            elseif mode == "last" then
                if (tonumber(target.pathDistance) or 0) < (tonumber(best.pathDistance) or 0) then
                    best = target
                end
            else
                if (tonumber(target.pathDistance) or 0) > (tonumber(best.pathDistance) or 0) then
                    best = target
                end
            end
        end
    end
    return best or targets[1]
end

function getAutoPursuitPosition()
    local target = getAutoPursuitTarget()
    if not target or typeof(target.pos) ~= "Vector3" then
        return nil
    end
    local led = airstrikeLeadTarget(target)
    return (led and led.pos) or target.pos
end

function autoPursuitUse(towerInfo, position)
    if not towerInfo or not towerInfo.model or not towerInfo.model.Parent or typeof(position) ~= "Vector3" then
        return false
    end
    for _, abilityName in ipairs(getPursuitAbilityNames(towerInfo)) do
        for _, payloadKey in ipairs(PURSUIT_POSITION_PAYLOAD_KEYS) do
            local payload = { [payloadKey] = position }
            local ok, result = invokeTroopsThrottled("Abilities", "Activate", {
                Troop = towerInfo.model,
                Name = abilityName,
                Data = payload,
            })
            if ok and result ~= false and (type(result) ~= "string" or result == "") then
                return true, abilityName
            end
        end
    end
    return false
end

function startAutoPursuitPosition()
    if ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.autoPursuitPositionThread then
        return
    end
    tdsSettings.autoPursuitPositionEnabled = true
    local lastUsed = {}
    local lastPosition = {}
    ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.autoPursuitPositionThread = task.spawn(function()
        while tdsSettings.autoPursuitPositionEnabled == true do
            local position = getAutoPursuitPosition()
            if position then
                local now = tick()
                for _, towerInfo in ipairs(getPursuitTowers()) do
                    local model = towerInfo.model
                    if model and model.Parent then
                        local previous = lastPosition[model]
                        local movedEnough = not previous
                            or (position - previous).Magnitude >= PURSUIT_MIN_REPOSITION_DISTANCE
                        if movedEnough and (not lastUsed[model] or now - lastUsed[model] >= PURSUIT_LOCAL_COOLDOWN) then
                            if autoPursuitUse(towerInfo, position) then
                                lastUsed[model] = now
                                lastPosition[model] = position
                            else
                                lastUsed[model] = now - (PURSUIT_LOCAL_COOLDOWN * 0.5)
                            end
                            task.wait(0.08)
                        end
                    end
                end
            end
            task.wait(0.35)
        end
        ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.autoPursuitPositionThread = nil
    end)
end

stopAutoPursuitPosition = function()
    tdsSettings.autoPursuitPositionEnabled = false
    local thread = ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.autoPursuitPositionThread
    ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.autoPursuitPositionThread = nil
    if thread then
        pcall(function()
            task.cancel(thread)
        end)
    end
end

function stopAllTdsFeatures()
    pcall(stopMacroPlayback)
    pcall(stopAutoskip)
    pcall(stopESP)
    pcall(stopEnemyInspector)
    pcall(stopGatling)
    pcall(stopAutoClaimAll)
    if stopAutoAirstrike then
        pcall(stopAutoAirstrike)
    end
    if stopAutoPursuitPosition then
        pcall(stopAutoPursuitPosition)
    end
    pcall(stopAutoReady)
    pcall(stopAutoRespawnVote)
    pcall(stopPickupFarm)
    pcall(stopModifierVote)
    pcall(stopResultsTracker)
    pcall(stopMatchTracker)
    pcall(stopAbilityManager)
    pcall(stopCommanderChain)
    pcall(stopSupportCaravan)
    pcall(stopAutoUpgrade)
    pcall(stopAutoUpgradeFarms)
    pcall(stopSkinChanger)
end

function resetAllTdsSettings()
    stopAllTdsFeatures()

    tdsSettings = cloneSettingsValue(settingsDefaults)
    settingsSaveQueued = false

    autoskipEnabled = false
    autoReadyEnabled = false
    modifierVoteEnabled = false
    autoRespawnVoteEnabled = false
    autoRerunStratsEnabled = false
    autoRejoinLaunchAttempted = false
    autoRejoinStratSerial += 1
    autoRerunSerial += 1

    gatlingBurstCount = math.clamp(math.floor(tonumber(tdsSettings.gatlingBurstCount) or 12), 1, 64)
    gatlingTargetMode = tostring(tdsSettings.gatlingTargetMode or "First")
    gatlingFireRateTicks =
        math.clamp(math.floor(tonumber(tdsSettings.gatlingFireRateTicks) or 60), GATLING_RATE_MIN, GATLING_RATE_MAX)
    gatlingFireDelay = tonumber(tdsSettings.gatlingFireDelay) or 0.01
    gatlingMaxTargets = math.clamp(math.floor(tonumber(tdsSettings.gatlingMaxTargets) or 5), 1, 10)
    gatlingBulletLinesEnabled = tdsSettings.gatlingBulletLinesEnabled == true
    gatlingHitsoundsDisabled = tdsSettings.gatlingHitsoundsDisabled == true
    gatlingTargetEsp = tostring(tdsSettings.gatlingTargetEsp or "Off")
    autoClaimAllEnabled = tdsSettings.autoClaimAllEnabled == true
    autoUpgradeFarmsEnabled = tdsSettings.autoUpgradeFarmsEnabled == true
    tdsSettings.unlockTowersClientEnabled = tdsSettings.unlockTowersClientEnabled == true
    ZephyrRuntimeEnv.__ZephyrTdsRuntimeState.clientTowerUnlockOriginalTroops = nil
    unlockSkinsClientEnabled = tdsSettings.unlockSkinsClientEnabled == true
    unlockEmotesClientEnabled = tdsSettings.unlockEmotesClientEnabled == true
    unlockCosmeticsClientEnabled = tdsSettings.unlockCosmeticsClientEnabled == true
    clientEmoteUnlockOriginalEmotes = nil
    clientEmoteUnlockOriginalEquipped = nil
    clientCosmeticUnlockOriginals = nil
    clientCosmeticUnlockOriginalEquipped = nil
    autoAirstrikeEnabled = tdsSettings.autoAirstrikeEnabled == true
    autoAirstrikeTarget = tostring(tdsSettings.autoAirstrikeTarget or "Grouped")
    tdsSettings.autoPursuitPositionEnabled = tdsSettings.autoPursuitPositionEnabled == true
    tdsSettings.autoPursuitPositionTarget = tostring(tdsSettings.autoPursuitPositionTarget or "Grouped")
    if type(gatlingSliderUpdateFn) == "function" then
        pcall(gatlingSliderUpdateFn)
    end

    local saved = saveSettingsNow()
    return saved or type(writefile) ~= "function"
end

-- Interface
function createUI()
    if not runtimeAlive then
        return
    end
    local existing = PlayerGui:FindFirstChild("ZephyrTDS")
    if existing then
        existing:Destroy()
    end

    local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800, 600)
    isMobile = isMobile or vp.X < 600
    local uiConnections = {}
    local function connectUI(signal, callback)
        local connection = signal:Connect(callback)
        uiConnections[#uiConnections + 1] = connection
        return connection
    end

    local C = {
        bg = Color3.fromRGB(18, 21, 24),
        bgLight = Color3.fromRGB(24, 29, 32),
        card = Color3.fromRGB(29, 35, 39),
        cardHover = Color3.fromRGB(37, 45, 49),
        surface = Color3.fromRGB(34, 41, 45),
        surfaceAlt = Color3.fromRGB(45, 54, 58),
        border = Color3.fromRGB(52, 62, 66),
        borderHi = Color3.fromRGB(80, 96, 101),
        text = Color3.fromRGB(237, 243, 245),
        textSec = Color3.fromRGB(180, 195, 201),
        textDim = Color3.fromRGB(143, 161, 169),
        accent = Color3.fromRGB(89, 191, 162),
        accentLit = Color3.fromRGB(130, 220, 190),
        purple = Color3.fromRGB(163, 137, 213),
        purpleLit = Color3.fromRGB(158, 114, 255),
        green = Color3.fromRGB(34, 197, 94),
        yellow = Color3.fromRGB(250, 204, 21),
        red = Color3.fromRGB(239, 68, 68),
        blue = Color3.fromRGB(96, 165, 250),
    }

    local M
    if isMobile then
        M = {
            hdr = 58,
            pad = 8,
            cardH = 80,
            cardExp = 140,
            gap = 7,
            cr = 7,
            title = 14,
            sub = 10,
            cTitle = 13,
            cSub = 10,
            stat = 10,
            pill = 20,
            sec = 11,
            btn = 40,
            tog = 54,
            togW = 42,
            togH = 24,
            knob = 18,
        }
    else
        M = {
            hdr = 64,
            pad = 14,
            cardH = 94,
            cardExp = 158,
            gap = 9,
            cr = 8,
            title = 19,
            sub = 11,
            cTitle = 15,
            cSub = 11,
            stat = 11,
            pill = 22,
            sec = 12,
            btn = 38,
            tog = 46,
            togW = 46,
            togH = 24,
            knob = 18,
        }
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "ZephyrTDS"
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.ResetOnSpawn = false
    gui.Parent = PlayerGui
    gui.Destroying:Connect(function()
        for _, connection in ipairs(uiConnections) do
            connection:Disconnect()
        end
        table.clear(uiConnections)
    end)

    local toggleSize = 46
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Name = "UIToggle"
    toggleBtn.Size = UDim2.new(0, toggleSize, 0, toggleSize)
    toggleBtn.Position = isMobile and UDim2.new(0, 10, 0, 74) or UDim2.new(0, 14, 0, 120)
    toggleBtn.BackgroundColor3 = C.surface
    toggleBtn.BorderSizePixel = 0
    toggleBtn.Text = ""
    toggleBtn.TextColor3 = C.text
    toggleBtn.TextSize = isMobile and 15 or 17
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.AutoButtonColor = false
    toggleBtn.Visible = false
    toggleBtn.ZIndex = 150
    toggleBtn.Parent = gui
    Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 8)
    local logo = Instance.new("ImageLabel", toggleBtn)
    logo.Size = UDim2.fromOffset(34, 34)
    logo.Position = UDim2.fromOffset(6, 6)
    logo.BackgroundColor3 = Color3.fromRGB(230, 239, 235)
    logo.BorderSizePixel = 0
    logo.Image = "rbxthumb://type=Asset&id=89616857457936&w=420&h=420"
    logo.ScaleType = Enum.ScaleType.Fit
    logo.ZIndex = 151
    Instance.new("UICorner", logo).CornerRadius = UDim.new(0, 6)
    local toggleStroke = Instance.new("UIStroke", toggleBtn)
    toggleStroke.Color = C.accent
    toggleStroke.Thickness = 1
    toggleStroke.Transparency = 0.1

    local function toast(msg, col)
        if not runtimeAlive or not gui.Parent then
            return
        end
        local f = Instance.new("Frame")
        f.Size = UDim2.new(0, 0, 0, 24)
        f.AutomaticSize = Enum.AutomaticSize.X
        f.Position = UDim2.new(0.5, 0, 0, -30)
        f.AnchorPoint = Vector2.new(0.5, 0)
        f.BackgroundColor3 = col or C.accent
        f.ZIndex = 100
        f.Parent = gui
        Instance.new("UICorner", f).CornerRadius = UDim.new(0, 6)
        local p = Instance.new("UIPadding", f)
        p.PaddingLeft = UDim.new(0, 10)
        p.PaddingRight = UDim.new(0, 10)
        local t = Instance.new("TextLabel")
        t.Size = UDim2.new(0, 0, 1, 0)
        t.AutomaticSize = Enum.AutomaticSize.X
        t.BackgroundTransparency = 1
        t.Text = msg
        t.TextColor3 = Color3.fromRGB(255, 255, 255)
        t.TextSize = 11
        t.Font = Enum.Font.GothamBold
        t.ZIndex = 101
        t.Parent = f
        TweenService:Create(f, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Position = UDim2.new(0.5, 0, 0, 8),
        }):Play()
        task.delay(2, function()
            if not gui.Parent or not f.Parent then
                return
            end
            local tw = TweenService:Create(f, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
                Position = UDim2.new(0.5, 0, 0, -30),
            })
            tw:Play()
            tw.Completed:Connect(function()
                f:Destroy()
            end)
        end)
    end
    uiNotify = toast

    local function showConfirmPrompt(title, body, confirmText, onConfirm)
        local shade = Instance.new("Frame")
        shade.Name = "ConfirmPrompt"
        shade.Size = UDim2.new(1, 0, 1, 0)
        shade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        shade.BackgroundTransparency = 0.32
        shade.BorderSizePixel = 0
        shade.ZIndex = 300
        shade.Parent = gui

        local box = Instance.new("Frame", shade)
        box.AnchorPoint = Vector2.new(0.5, 0.5)
        box.Position = UDim2.new(0.5, 0, 0.5, 0)
        box.Size = isMobile and UDim2.new(0, 286, 0, 154) or UDim2.new(0, 360, 0, 168)
        box.BackgroundColor3 = C.card
        box.BorderSizePixel = 0
        box.ZIndex = 301
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 8)
        local stroke = Instance.new("UIStroke", box)
        stroke.Color = C.red
        stroke.Thickness = 1
        stroke.Transparency = 0.1

        local titleLabel = Instance.new("TextLabel", box)
        titleLabel.Size = UDim2.new(1, -24, 0, 24)
        titleLabel.Position = UDim2.new(0, 12, 0, 12)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Text = title
        titleLabel.TextColor3 = C.text
        titleLabel.TextSize = isMobile and 13 or 16
        titleLabel.Font = Enum.Font.GothamBold
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left
        titleLabel.ZIndex = 302

        local bodyLabel = Instance.new("TextLabel", box)
        bodyLabel.Size = UDim2.new(1, -24, 0, isMobile and 58 or 64)
        bodyLabel.Position = UDim2.new(0, 12, 0, 42)
        bodyLabel.BackgroundTransparency = 1
        bodyLabel.Text = body
        bodyLabel.TextColor3 = C.textSec
        bodyLabel.TextSize = 11
        bodyLabel.Font = Enum.Font.Gotham
        bodyLabel.TextWrapped = true
        bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
        bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
        bodyLabel.ZIndex = 302

        local cancel = Instance.new("TextButton", box)
        cancel.Size = UDim2.new(0.5, -18, 0, 30)
        cancel.Position = UDim2.new(0, 12, 1, -42)
        cancel.BackgroundColor3 = C.surfaceAlt
        cancel.BorderSizePixel = 0
        cancel.Text = "Cancel"
        cancel.TextColor3 = C.text
        cancel.TextSize = isMobile and 10 or 12
        cancel.Font = Enum.Font.GothamBold
        cancel.ZIndex = 302
        Instance.new("UICorner", cancel).CornerRadius = UDim.new(0, 8)

        local confirm = Instance.new("TextButton", box)
        confirm.Size = UDim2.new(0.5, -18, 0, 30)
        confirm.Position = UDim2.new(0.5, 6, 1, -42)
        confirm.BackgroundColor3 = C.red
        confirm.BorderSizePixel = 0
        confirm.Text = confirmText
        confirm.TextColor3 = Color3.fromRGB(255, 255, 255)
        confirm.TextSize = isMobile and 10 or 12
        confirm.Font = Enum.Font.GothamBold
        confirm.ZIndex = 302
        Instance.new("UICorner", confirm).CornerRadius = UDim.new(0, 8)

        cancel.MouseButton1Click:Connect(function()
            shade:Destroy()
        end)
        confirm.MouseButton1Click:Connect(function()
            shade:Destroy()
            if type(onConfirm) == "function" then
                onConfirm()
            end
        end)
    end

    local targetSize, targetPos
    local function measurePanel()
        local size = gui.AbsoluteSize
        if size.X <= 0 or size.Y <= 0 then
            size = vp
        end
        local width = math.min(isMobile and 430 or 560, math.max(240, size.X - 24))
        local height = math.min(isMobile and 600 or 670, math.max(180, size.Y - 24))
        targetSize = UDim2.fromOffset(width, height)
        targetPos = UDim2.new(0.5, -width / 2, 0.5, -height / 2)
    end
    measurePanel()

    local main = Instance.new("Frame")
    main.Name = "Main"
    main.BackgroundColor3 = C.bg
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.Size = targetSize
    main.Position = targetPos
    main.Parent = gui
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)
    local mStroke = Instance.new("UIStroke", main)
    mStroke.Color = C.border
    mStroke.Thickness = 1
    local shadow = Instance.new("ImageLabel", main)
    shadow.Size = UDim2.new(1, 40, 1, 40)
    shadow.Position = UDim2.new(0.5, 0, 0.5, 0)
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxassetid://5554236805"
    shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    shadow.ImageTransparency = 0.35
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(23, 23, 277, 277)
    shadow.ZIndex = -1

    local topLine = Instance.new("Frame", main)
    topLine.Size = UDim2.new(1, 0, 0, 2)
    topLine.BackgroundColor3 = C.accent
    topLine.BorderSizePixel = 0
    topLine.ZIndex = 30
    local tlGrad = Instance.new("UIGradient", topLine)
    tlGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, C.accent),
        ColorSequenceKeypoint.new(0.5, C.accentLit),
        ColorSequenceKeypoint.new(1, C.blue),
    })

    local hdr = Instance.new("Frame", main)
    hdr.Name = "Header"
    hdr.Size = UDim2.new(1, 0, 0, M.hdr)
    hdr.Position = UDim2.new(0, 0, 0, 2)
    hdr.BackgroundColor3 = C.bgLight
    hdr.BorderSizePixel = 0
    hdr.ZIndex = 10
    local hdrSep = Instance.new("Frame", hdr)
    hdrSep.Size = UDim2.new(1, 0, 0, 1)
    hdrSep.Position = UDim2.new(0, 0, 1, -1)
    hdrSep.BackgroundColor3 = C.border
    hdrSep.BorderSizePixel = 0
    hdrSep.ZIndex = 10

    local brandColor = Instance.new("TextLabel", hdr)
    brandColor.Size = UDim2.new(0, 96, 0, M.title + 2)
    brandColor.BorderSizePixel = 0
    brandColor.Position = UDim2.new(0, M.pad + 42, 0, isMobile and 11 or 12)
    brandColor.BackgroundTransparency = 1
    brandColor.RichText = true
    brandColor.Text = "ZEPHYR"
    brandColor.TextColor3 = C.text
    brandColor.TextSize = M.title
    brandColor.Font = Enum.Font.GothamBold
    brandColor.TextXAlignment = Enum.TextXAlignment.Left
    brandColor.ZIndex = 11

    local subLabel = Instance.new("TextLabel", hdr)
    subLabel.Size = UDim2.new(0, 96, 0, 14)
    subLabel.Position = UDim2.new(0, M.pad + 42, 0, (isMobile and 11 or 12) + M.title + 2)
    subLabel.BackgroundTransparency = 1
    subLabel.Text = "TOWER DEFENSE"
    subLabel.BorderSizePixel = 0
    subLabel.TextColor3 = C.textDim
    subLabel.TextSize = M.sub
    subLabel.Font = Enum.Font.Gotham
    subLabel.TextXAlignment = Enum.TextXAlignment.Left
    subLabel.ZIndex = 11
    local headerLogo = logo:Clone()
    headerLogo.ZIndex = 11
    headerLogo.Position = UDim2.new(0, M.pad, 0.5, -17)
    headerLogo.Parent = hdr

    local hBtnWidth = isMobile and 130 or 188
    local hBtns = Instance.new("Frame", hdr)
    hBtns.Size = UDim2.new(0, hBtnWidth, 0, 42)
    hBtns.Position = UDim2.new(1, -(hBtnWidth + 8), 0.5, -21)
    hBtns.BackgroundTransparency = 1
    hBtns.ZIndex = 12
    local hBtnLay = Instance.new("UIListLayout", hBtns)
    hBtnLay.FillDirection = Enum.FillDirection.Horizontal
    hBtnLay.HorizontalAlignment = Enum.HorizontalAlignment.Right
    hBtnLay.VerticalAlignment = Enum.VerticalAlignment.Center
    hBtnLay.Padding = UDim.new(0, 5)

    local function hdrBtn(text, order, w)
        local b = Instance.new("TextButton", hBtns)
        b.Size = UDim2.new(0, math.max(w or 40, 40), 0, 40)
        b.BackgroundColor3 = C.surface
        b.Text = text
        b.TextColor3 = C.textSec
        b.TextSize = text == "X" and 13 or (isMobile and 10 or 11)
        b.Font = Enum.Font.GothamBold
        b.LayoutOrder = order
        b.ZIndex = 12
        b.BorderSizePixel = 0
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
        local s = Instance.new("UIStroke", b)
        s.Color = C.border
        s.Thickness = 1
        s.Transparency = 0.3
        b.MouseEnter:Connect(function()
            if b:GetAttribute("CustomHover") then
                return
            end
            TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = C.surfaceAlt, TextColor3 = C.text }):Play()
        end)
        b.MouseLeave:Connect(function()
            if b:GetAttribute("CustomHover") then
                return
            end
            TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = C.surface, TextColor3 = C.textSec }):Play()
        end)
        return b
    end

    local keysBtn = (not isMobile) and hdrBtn("Keys", 0, 44) or nil
    if keysBtn then
        keysBtn:SetAttribute("CustomHover", true)
    end
    local miscBtn = hdrBtn("Misc", 1, isMobile and 34 or 44)
    local hideBtn = hdrBtn("-", 2, isMobile and 24 or 26)
    local closeBtn = hdrBtn("X", 3, isMobile and 24 or 26)

    local uiOpen = true
    local panelTween = nil
    local panelRevision = 0
    local function clampPosition(position, width, height)
        local size = gui.AbsoluteSize
        return UDim2.fromOffset(
            math.clamp(position.X.Scale * size.X + position.X.Offset, 0, math.max(0, size.X - width)),
            math.clamp(position.Y.Scale * size.Y + position.Y.Offset, 0, math.max(0, size.Y - height))
        )
    end
    local function setUIOpen(open)
        if uiOpen == open then
            return
        end
        uiOpen = open
        toggleBtn.Visible = not open
        panelRevision += 1
        local revision = panelRevision
        if panelTween then
            panelTween:Cancel()
        end
        toggleBtn.BackgroundColor3 = open and C.surface or C.accent
        if open then
            main.Visible = true
        end
        panelTween = TweenService:Create(main, TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Position = open and targetPos
                or UDim2.new(targetPos.X.Scale, targetPos.X.Offset, targetPos.Y.Scale, targetPos.Y.Offset + 8),
        })
        panelTween.Completed:Once(function()
            if revision == panelRevision and not uiOpen then
                main.Visible = false
            end
        end)
        panelTween:Play()
    end
    local function refreshPanelBounds()
        if not gui.Parent then
            return
        end
        panelRevision += 1
        if panelTween then
            panelTween:Cancel()
        end
        measurePanel()
        main.Size = targetSize
        main.Position = targetPos
        main.Visible = uiOpen
        local compact = targetSize.X.Offset < 420
        if keysBtn then
            keysBtn.Visible = not compact
        end
        local controlsWidth = (keysBtn and not compact) and 188 or 130
        hBtns.Size = UDim2.fromOffset(controlsWidth, 42)
        hBtns.Position = UDim2.new(1, -controlsWidth - 8, 0.5, -21)
        toggleBtn.Position = clampPosition(toggleBtn.Position, toggleSize, toggleSize)
    end
    connectUI(gui:GetPropertyChangedSignal("AbsoluteSize"), refreshPanelBounds)
    local cameraResize
    local function bindPanelCamera()
        if cameraResize then
            cameraResize:Disconnect()
        end
        local camera = workspace.CurrentCamera
        if camera then
            cameraResize = connectUI(camera:GetPropertyChangedSignal("ViewportSize"), function()
                task.defer(refreshPanelBounds)
            end)
        end
        task.defer(refreshPanelBounds)
    end
    connectUI(workspace:GetPropertyChangedSignal("CurrentCamera"), bindPanelCamera)
    bindPanelCamera()

    local toggleWasDragged = false
    do
        local dragging, dragStart, startPos, dragTouch = false, nil, nil, nil
        toggleBtn.InputBegan:Connect(function(input)
            local t = input.UserInputType
            if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
                dragging = true
                toggleWasDragged = false
                dragStart = input.Position
                startPos = toggleBtn.Position
                dragTouch = t == Enum.UserInputType.Touch and input or nil
                local ec
                ec = input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                        if ec then
                            ec:Disconnect()
                        end
                    end
                end)
            end
        end)
        connectUI(UserInputService.InputChanged, function(input)
            if not dragging then
                return
            end
            if dragTouch and input ~= dragTouch then
                return
            end
            local t = input.UserInputType
            if t ~= Enum.UserInputType.MouseMovement and t ~= Enum.UserInputType.Touch then
                return
            end
            local d = input.Position - dragStart
            if math.abs(d.X) > 4 or math.abs(d.Y) > 4 then
                toggleWasDragged = true
            end
            toggleBtn.Position = clampPosition(
                UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y),
                toggleSize,
                toggleSize
            )
        end)
    end

    toggleBtn.Activated:Connect(function()
        if toggleWasDragged then
            toggleWasDragged = false
            return
        end
        setUIOpen(not uiOpen)
    end)
    hideBtn.Activated:Connect(function()
        setUIOpen(false)
    end)
    closeBtn.Activated:Connect(function()
        pcall(saveSettingsNow)
        ZephyrRuntimeEnv.__ZEPHYR_TDS_CLEANUP()
        if gui.Parent then
            gui:Destroy()
        end
    end)

    local keybindEntries = {}
    local keybindPanel = nil
    local keybindList = nil
    local keybindTitle = nil
    local keybindSub = nil
    local keybindConn = nil
    local keybindOpen = false
    local refreshKeybindList = nil

    local function isModifierDown(name)
        if name == "alt" then
            return UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
        elseif name == "ctrl" then
            return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
                or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
        elseif name == "shift" then
            return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
                or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
        end
        return false
    end

    local function keybindPressed(input, binding)
        if not binding or input.KeyCode ~= binding.key then
            return false
        end
        if (binding.alt == true) ~= isModifierDown("alt") then
            return false
        end
        if (binding.ctrl == true) ~= isModifierDown("ctrl") then
            return false
        end
        if (binding.shift == true) ~= isModifierDown("shift") then
            return false
        end
        return true
    end

    local function bindAlt(keyCode, order, id)
        if isMobile then
            return nil
        end
        local keyName = tostring(keyCode):gsub("Enum.KeyCode.", "")
        return {
            key = keyCode,
            alt = true,
            ctrl = false,
            shift = false,
            text = "Alt+" .. keyName,
            order = order or 999,
            id = id,
        }
    end

    local modifierOnlyKeyCodes = {
        [Enum.KeyCode.Unknown] = true,
        [Enum.KeyCode.LeftAlt] = true,
        [Enum.KeyCode.RightAlt] = true,
        [Enum.KeyCode.LeftControl] = true,
        [Enum.KeyCode.RightControl] = true,
        [Enum.KeyCode.LeftShift] = true,
        [Enum.KeyCode.RightShift] = true,
    }
    local reservedKeybindText = "Alt+K"
    local keybindCaptureEntry = nil

    local function keybindIdFromLabel(label)
        local id = tostring(label or "toggle"):lower()
        id = id:gsub("[^%w]+", "_")
        id = id:gsub("^_+", ""):gsub("_+$", "")
        return id ~= "" and id or "toggle"
    end

    local function keyCodeName(keyCode)
        return tostring(keyCode or ""):gsub("^Enum%.KeyCode%.", "")
    end

    local function keyCodeFromName(name)
        local clean = tostring(name or ""):gsub("^Enum%.KeyCode%.", "")
        if clean == "" then
            return nil
        end
        local ok, item = pcall(function()
            return Enum.KeyCode[clean]
        end)
        if ok and typeof(item) == "EnumItem" then
            return item
        end
        local listOk, enumItems = pcall(function()
            return Enum.KeyCode:GetEnumItems()
        end)
        if listOk and type(enumItems) == "table" then
            for _, enumItem in ipairs(enumItems) do
                if tostring(enumItem.Name):lower() == clean:lower() then
                    return enumItem
                end
            end
        end
        return nil
    end

    local function copyKeybind(binding)
        if type(binding) ~= "table" then
            return nil
        end
        return {
            key = binding.key,
            alt = binding.alt == true,
            ctrl = binding.ctrl == true,
            shift = binding.shift == true,
            text = binding.text,
            order = binding.order,
            id = binding.id,
        }
    end

    local function keybindText(binding)
        if type(binding) ~= "table" or not binding.key then
            return "?"
        end
        local parts = {}
        if binding.ctrl then
            parts[#parts + 1] = "Ctrl"
        end
        if binding.alt then
            parts[#parts + 1] = "Alt"
        end
        if binding.shift then
            parts[#parts + 1] = "Shift"
        end
        parts[#parts + 1] = keyCodeName(binding.key)
        return table.concat(parts, "+")
    end

    local function getKeybindStore()
        if type(tdsSettings.keybinds) ~= "table" then
            tdsSettings.keybinds = {}
        end
        return tdsSettings.keybinds
    end

    local function resolveKeybind(id, fallback)
        if type(fallback) ~= "table" or not fallback.key then
            return nil
        end
        local out = copyKeybind(fallback) or {}
        local saved = getKeybindStore()[id]
        if type(saved) == "table" then
            local savedKey = keyCodeFromName(saved.key or saved.keyName or saved.KeyCode)
            if savedKey and not modifierOnlyKeyCodes[savedKey] then
                out.key = savedKey
                out.alt = saved.alt == true
                out.ctrl = saved.ctrl == true
                out.shift = saved.shift == true
            end
        end
        out.id = id
        out.order = tonumber(out.order) or tonumber(fallback.order) or 999
        out.text = keybindText(out)
        return out
    end

    local function saveKeybind(id, binding)
        if tostring(id or "") == "" or type(binding) ~= "table" or not binding.key then
            return
        end
        local store = getKeybindStore()
        store[id] = {
            key = keyCodeName(binding.key),
            alt = binding.alt == true,
            ctrl = binding.ctrl == true,
            shift = binding.shift == true,
        }
        saveSettingsSoon()
        saveSettingsNow()
    end

    local function resetKeybind(id, fallback)
        if tostring(id or "") == "" then
            return resolveKeybind(id, fallback)
        end
        local store = getKeybindStore()
        store[id] = nil
        saveSettingsSoon()
        saveSettingsNow()
        return resolveKeybind(id, fallback)
    end

    local function applyEntryKeybind(entry, binding, persist)
        if type(entry) ~= "table" or type(binding) ~= "table" or not binding.key then
            return
        end
        local nextBinding = copyKeybind(binding) or {}
        nextBinding.id = entry.id
        nextBinding.order = entry.order
        nextBinding.text = keybindText(nextBinding)
        entry.binding = nextBinding
        entry.text = nextBinding.text
        if persist then
            saveKeybind(entry.id, nextBinding)
        end
        if type(entry.onBindingChanged) == "function" then
            pcall(entry.onBindingChanged, nextBinding)
        end
        if type(refreshKeybindList) == "function" then
            task.defer(refreshKeybindList)
        end
    end

    local function beginKeybindCapture(entry)
        if type(entry) ~= "table" or tostring(entry.id or "") == "" then
            return
        end
        keybindCaptureEntry = entry
        if keybindSub then
            keybindSub.Text = "Press a key for "
                .. tostring(entry.label or "toggle")
                .. " / Backspace resets / Esc cancels"
        end
        if type(refreshKeybindList) == "function" then
            task.defer(refreshKeybindList)
        end
    end

    local function setKeybindPanelOpen(open)
        if isMobile or not keybindPanel then
            return
        end
        keybindOpen = open == true
        if keysBtn then
            keysBtn.BackgroundColor3 = keybindOpen and C.accent or C.surface
            keysBtn.TextColor3 = keybindOpen and Color3.fromRGB(255, 255, 255) or C.textSec
        end
        if keybindOpen then
            keybindPanel.Visible = true
            keybindPanel.Position = UDim2.new(1, 18, 0.5, 0)
            TweenService:Create(keybindPanel, TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                Position = UDim2.new(1, -16, 0.5, 0),
            }):Play()
            if type(refreshKeybindList) == "function" then
                refreshKeybindList()
            end
        else
            local tw = TweenService:Create(
                keybindPanel,
                TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
                {
                    Position = UDim2.new(1, 18, 0.5, 0),
                }
            )
            tw:Play()
            tw.Completed:Connect(function()
                if not keybindOpen and keybindPanel then
                    keybindPanel.Visible = false
                end
            end)
        end
    end

    if keysBtn then
        keybindPanel = Instance.new("Frame")
        keybindPanel.Name = "Keybinds"
        keybindPanel.AnchorPoint = Vector2.new(1, 0.5)
        keybindPanel.Position = UDim2.new(1, 18, 0.5, 0)
        keybindPanel.Size = UDim2.new(0, 326, 0, 430)
        keybindPanel.BackgroundColor3 = C.bg
        keybindPanel.BorderSizePixel = 0
        keybindPanel.Visible = false
        keybindPanel.ClipsDescendants = true
        keybindPanel.ZIndex = 210
        keybindPanel.Parent = gui
        Instance.new("UICorner", keybindPanel).CornerRadius = UDim.new(0, 16)
        local kpStroke = Instance.new("UIStroke", keybindPanel)
        kpStroke.Color = C.borderHi
        kpStroke.Thickness = 1
        kpStroke.Transparency = 0.08
        local kpGrad = Instance.new("UIGradient", keybindPanel)
        kpGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 21, 36)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 10, 20)),
        })
        kpGrad.Rotation = 145

        local kpTop = Instance.new("Frame", keybindPanel)
        kpTop.Size = UDim2.new(1, -28, 0, 2)
        kpTop.Position = UDim2.new(0, 14, 0, 0)
        kpTop.BackgroundColor3 = C.accent
        kpTop.BackgroundTransparency = 0.15
        kpTop.BorderSizePixel = 0
        kpTop.ZIndex = 211
        local kpTopGrad = Instance.new("UIGradient", kpTop)
        kpTopGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(96, 165, 250)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(139, 92, 246)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(34, 197, 94)),
        })

        keybindTitle = Instance.new("TextLabel", keybindPanel)
        keybindTitle.Size = UDim2.new(1, -58, 0, 22)
        keybindTitle.Position = UDim2.new(0, 14, 0, 13)
        keybindTitle.BackgroundTransparency = 1
        keybindTitle.RichText = true
        keybindTitle.Text = '<font color="#60a5fa">KEY</font><font color="#eef2ff">BINDS</font>'
        keybindTitle.TextColor3 = C.text
        keybindTitle.TextSize = 17
        keybindTitle.Font = Enum.Font.GothamBold
        keybindTitle.TextXAlignment = Enum.TextXAlignment.Left
        keybindTitle.ZIndex = 212

        keybindSub = Instance.new("TextLabel", keybindPanel)
        keybindSub.Size = UDim2.new(1, -28, 0, 16)
        keybindSub.Position = UDim2.new(0, 14, 0, 36)
        keybindSub.BackgroundTransparency = 1
        keybindSub.Text = "Alt+K opens this. Click any row to toggle."
        keybindSub.TextColor3 = C.textDim
        keybindSub.TextSize = 10
        keybindSub.Font = Enum.Font.Gotham
        keybindSub.TextXAlignment = Enum.TextXAlignment.Left
        keybindSub.ZIndex = 212

        local closeKeys = Instance.new("TextButton", keybindPanel)
        closeKeys.Size = UDim2.new(0, 26, 0, 26)
        closeKeys.Position = UDim2.new(1, -36, 0, 12)
        closeKeys.BackgroundColor3 = C.surface
        closeKeys.BorderSizePixel = 0
        closeKeys.Text = "X"
        closeKeys.TextColor3 = C.textSec
        closeKeys.TextSize = 13
        closeKeys.Font = Enum.Font.GothamBold
        closeKeys.ZIndex = 212
        Instance.new("UICorner", closeKeys).CornerRadius = UDim.new(0, 8)
        closeKeys.MouseButton1Click:Connect(function()
            setKeybindPanelOpen(false)
        end)
        local function paintKeysButton(hover)
            if not keysBtn then
                return
            end
            if keybindOpen then
                keysBtn.BackgroundColor3 = hover and C.accentLit or C.accent
                keysBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            else
                keysBtn.BackgroundColor3 = hover and C.surfaceAlt or C.surface
                keysBtn.TextColor3 = hover and C.text or C.textSec
            end
        end
        keysBtn.MouseEnter:Connect(function()
            paintKeysButton(true)
        end)
        keysBtn.MouseLeave:Connect(function()
            paintKeysButton(false)
        end)

        local hint = Instance.new("Frame", keybindPanel)
        hint.Size = UDim2.new(1, -28, 0, 50)
        hint.Position = UDim2.new(0, 14, 0, 62)
        hint.BackgroundColor3 = Color3.fromRGB(20, 25, 43)
        hint.BorderSizePixel = 0
        hint.ZIndex = 211
        Instance.new("UICorner", hint).CornerRadius = UDim.new(0, 11)
        local hintStroke = Instance.new("UIStroke", hint)
        hintStroke.Color = C.border
        hintStroke.Thickness = 1
        hintStroke.Transparency = 0.55
        local hintText = Instance.new("TextLabel", hint)
        hintText.Size = UDim2.new(1, -18, 1, 0)
        hintText.Position = UDim2.new(0, 9, 0, 0)
        hintText.BackgroundTransparency = 1
        hintText.Text = "Custom keybinds you can change! discord.gg/zephyrmvsd"
        hintText.TextColor3 = C.textSec
        hintText.TextSize = 10
        hintText.TextWrapped = true
        hintText.Font = Enum.Font.GothamMedium
        hintText.TextXAlignment = Enum.TextXAlignment.Left
        hintText.ZIndex = 212

        keybindList = Instance.new("ScrollingFrame", keybindPanel)
        keybindList.Size = UDim2.new(1, -34, 1, -132)
        keybindList.Position = UDim2.new(0, 14, 0, 124)
        keybindList.BackgroundTransparency = 1
        keybindList.BorderSizePixel = 0
        keybindList.ScrollBarThickness = 2
        keybindList.ScrollBarImageColor3 = C.textDim
        keybindList.ScrollBarImageTransparency = 0.62
        keybindList.CanvasSize = UDim2.new(0, 0, 0, 0)
        keybindList.AutomaticCanvasSize = Enum.AutomaticSize.Y
        keybindList.ScrollingDirection = Enum.ScrollingDirection.Y
        keybindList.ZIndex = 211
        local kl = Instance.new("UIListLayout", keybindList)
        kl.SortOrder = Enum.SortOrder.LayoutOrder
        kl.Padding = UDim.new(0, 7)
        local kp = Instance.new("UIPadding", keybindList)
        kp.PaddingBottom = UDim.new(0, 4)

        refreshKeybindList = function()
            if not keybindList then
                return
            end
            local active = 0
            for _, entry in ipairs(keybindEntries) do
                if entry.get and entry.get() then
                    active += 1
                end
            end
            if keybindSub then
                keybindSub.Text = keybindCaptureEntry
                        and ("Listening for " .. tostring(keybindCaptureEntry.label or "toggle") .. "...")
                    or string.format("%d active / %d bound / Alt+K opens this", active, #keybindEntries)
            end
            for _, child in ipairs(keybindList:GetChildren()) do
                if child:IsA("GuiObject") then
                    child:Destroy()
                end
            end
            table.sort(keybindEntries, function(a, b)
                if (a.order or 999) == (b.order or 999) then
                    return tostring(a.label) < tostring(b.label)
                end
                return (a.order or 999) < (b.order or 999)
            end)
            for i, entry in ipairs(keybindEntries) do
                local enabled = entry.get and entry.get() or false
                local row = Instance.new("TextButton", keybindList)
                row.Size = UDim2.new(1, -8, 0, 52)
                row.BackgroundColor3 = enabled and Color3.fromRGB(24, 34, 47) or C.card
                row.BorderSizePixel = 0
                row.Text = ""
                row.AutoButtonColor = false
                row.LayoutOrder = i
                row.ZIndex = 212
                Instance.new("UICorner", row).CornerRadius = UDim.new(0, 11)
                local rs = Instance.new("UIStroke", row)
                rs.Color = enabled and C.green or C.border
                rs.Thickness = 1
                rs.Transparency = enabled and 0.15 or 0.55

                local waitingForKey = keybindCaptureEntry == entry
                local key = Instance.new("TextButton", row)
                key.Size = UDim2.new(0, 84, 0, 28)
                key.Position = UDim2.new(0, 9, 0.5, -14)
                key.BackgroundColor3 = waitingForKey and C.yellow or (enabled and C.accent or C.surfaceAlt)
                key.BorderSizePixel = 0
                key.Text = waitingForKey and "Press..." or tostring(entry.text or "?")
                key.TextColor3 = waitingForKey and Color3.fromRGB(17, 19, 30) or Color3.fromRGB(255, 255, 255)
                key.TextSize = 10
                key.Font = Enum.Font.GothamBold
                key.ZIndex = 213
                key.AutoButtonColor = false
                Instance.new("UICorner", key).CornerRadius = UDim.new(0, 8)
                local ks = Instance.new("UIStroke", key)
                ks.Color = waitingForKey and Color3.fromRGB(255, 238, 160) or C.border
                ks.Thickness = 1
                ks.Transparency = waitingForKey and 0.05 or 0.55

                local name = Instance.new("TextLabel", row)
                name.Size = UDim2.new(1, -158, 0, 15)
                name.Position = UDim2.new(0, 104, 0, 8)
                name.BackgroundTransparency = 1
                name.Text = tostring(entry.label or "Toggle")
                name.TextColor3 = C.text
                name.TextSize = 12
                name.Font = Enum.Font.GothamBold
                name.TextXAlignment = Enum.TextXAlignment.Left
                name.ZIndex = 213

                local state = Instance.new("TextLabel", row)
                state.Size = UDim2.new(1, -158, 0, 13)
                state.Position = UDim2.new(0, 104, 0, 27)
                state.BackgroundTransparency = 1
                state.Text = waitingForKey and "Press any key · Backspace reset · Esc cancel"
                    or (
                        enabled and "Enabled - click row or press key to disable"
                        or "Disabled - click row or press key to enable"
                    )
                state.TextColor3 = waitingForKey and C.yellow or (enabled and C.green or C.textDim)
                state.TextSize = 9
                state.Font = Enum.Font.Gotham
                state.TextXAlignment = Enum.TextXAlignment.Left
                state.ZIndex = 213

                local dot = Instance.new("Frame", row)
                dot.Size = UDim2.new(0, 10, 0, 10)
                dot.Position = UDim2.new(1, -20, 0.5, -5)
                dot.BackgroundColor3 = enabled and C.green or Color3.fromRGB(90, 100, 125)
                dot.BorderSizePixel = 0
                dot.ZIndex = 213
                Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

                row.MouseEnter:Connect(function()
                    TweenService:Create(
                        row,
                        TweenInfo.new(0.12),
                        { BackgroundColor3 = enabled and Color3.fromRGB(28, 42, 57) or C.cardHover }
                    ):Play()
                end)
                row.MouseLeave:Connect(function()
                    TweenService:Create(
                        row,
                        TweenInfo.new(0.12),
                        { BackgroundColor3 = enabled and Color3.fromRGB(24, 34, 47) or C.card }
                    ):Play()
                end)
                local suppressRowClick = false
                key.MouseEnter:Connect(function()
                    if keybindCaptureEntry ~= entry then
                        TweenService
                            :Create(
                                key,
                                TweenInfo.new(0.1),
                                { BackgroundColor3 = enabled and C.accentLit or C.borderHi }
                            )
                            :Play()
                    end
                end)
                key.MouseLeave:Connect(function()
                    if keybindCaptureEntry ~= entry then
                        TweenService
                            :Create(
                                key,
                                TweenInfo.new(0.1),
                                { BackgroundColor3 = enabled and C.accent or C.surfaceAlt }
                            )
                            :Play()
                    end
                end)
                key.MouseButton1Click:Connect(function()
                    suppressRowClick = true
                    beginKeybindCapture(entry)
                    task.delay(0.05, function()
                        suppressRowClick = false
                    end)
                end)
                row.MouseButton1Click:Connect(function()
                    if suppressRowClick or keybindCaptureEntry == entry then
                        return
                    end
                    if entry.set and entry.get then
                        entry.set(not entry.get(), true, true)
                    end
                end)
            end
        end

        keysBtn.MouseButton1Click:Connect(function()
            setKeybindPanelOpen(not keybindOpen)
        end)
        main:GetPropertyChangedSignal("Visible"):Connect(function()
            if not main.Visible then
                setKeybindPanelOpen(false)
            end
        end)

        keybindConn = connectUI(UserInputService.InputBegan, function(input, gp)
            if gp or UserInputService:GetFocusedTextBox() then
                return
            end
            if input.UserInputType ~= Enum.UserInputType.Keyboard then
                return
            end
            if keybindCaptureEntry then
                if modifierOnlyKeyCodes[input.KeyCode] then
                    return
                end
                local entry = keybindCaptureEntry
                if input.KeyCode == Enum.KeyCode.Escape then
                    keybindCaptureEntry = nil
                    if type(refreshKeybindList) == "function" then
                        refreshKeybindList()
                    end
                    return
                end
                if input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
                    keybindCaptureEntry = nil
                    local resetBinding = resetKeybind(entry.id, entry.defaultBinding or entry.binding)
                    applyEntryKeybind(entry, resetBinding, false)
                    toast("Keybind reset: " .. tostring(entry.label or "toggle"), C.green)
                    return
                end
                local nextBinding = {
                    key = input.KeyCode,
                    alt = isModifierDown("alt"),
                    ctrl = isModifierDown("ctrl"),
                    shift = isModifierDown("shift"),
                    order = entry.order,
                }
                nextBinding.text = keybindText(nextBinding)
                if nextBinding.text == reservedKeybindText then
                    toast(reservedKeybindText .. " opens the keybind menu", C.yellow)
                    return
                end
                keybindCaptureEntry = nil
                applyEntryKeybind(entry, nextBinding, true)
                toast(
                    "Keybind saved: " .. tostring(entry.label or "toggle") .. " -> " .. tostring(nextBinding.text),
                    C.green
                )
                return
            end
            if input.KeyCode == Enum.KeyCode.K and isModifierDown("alt") then
                setKeybindPanelOpen(not keybindOpen)
                return
            end
            for _, entry in ipairs(keybindEntries) do
                if keybindPressed(input, entry.binding) and entry.set and entry.get then
                    entry.set(not entry.get(), true, true)
                    return
                end
            end
        end)
        gui.Destroying:Connect(function()
            if keybindConn then
                keybindConn:Disconnect()
                keybindConn = nil
            end
        end)
    end

    local content = Instance.new("ScrollingFrame", main)
    content.Name = "Content"
    content.Size = UDim2.new(1, -(M.pad * 2), 1, -(M.hdr + 6))
    content.Position = UDim2.new(0, M.pad, 0, M.hdr + 4)
    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.ScrollBarThickness = isMobile and 2 or 4
    content.ScrollBarImageColor3 = Color3.fromRGB(60, 70, 100)
    content.ScrollBarImageTransparency = 0.2
    content.CanvasSize = UDim2.new(0, 0, 0, 0)
    content.ScrollingDirection = Enum.ScrollingDirection.Y
    content.ElasticBehavior = Enum.ElasticBehavior.Always
    content.Active = true
    content.Selectable = false
    content.ScrollingEnabled = true

    local cLay = Instance.new("UIListLayout", content)
    cLay.SortOrder = Enum.SortOrder.LayoutOrder
    cLay.Padding = UDim.new(0, M.gap)
    local cPad = Instance.new("UIPadding", content)
    cPad.PaddingTop = UDim.new(0, 2)
    cPad.PaddingBottom = UDim.new(0, 8)

    local cardEntries = {}
    local sectionHeaders = {}
    local searchText = ""
    local sortMode = "Default"
    local viewMode = "All"
    local sortButtons = {}
    local viewButtons = {}
    local rebuildCustomStrats
    local loadCustomEditor

    local filterBar = Instance.new("Frame", content)
    filterBar.Name = "FilterBar"
    filterBar.Size = UDim2.new(1, 0, 0, isMobile and 82 or 104)
    filterBar.BackgroundColor3 = C.card
    filterBar.BorderSizePixel = 0
    filterBar.LayoutOrder = -100
    filterBar.ZIndex = 12
    Instance.new("UICorner", filterBar).CornerRadius = UDim.new(0, M.cr)
    local filterStroke = Instance.new("UIStroke", filterBar)
    filterStroke.Color = C.border
    filterStroke.Thickness = 1
    filterStroke.Transparency = 0.45

    local searchBox = Instance.new("TextBox", filterBar)
    searchBox.Size = UDim2.new(1, -16, 0, isMobile and 24 or 30)
    searchBox.Position = UDim2.new(0, 8, 0, isMobile and 6 or 7)
    searchBox.BackgroundColor3 = C.surface
    searchBox.BorderSizePixel = 0
    searchBox.PlaceholderText = "Search strategies..."
    searchBox.PlaceholderColor3 = C.textDim
    searchBox.Text = ""
    searchBox.TextColor3 = C.text
    searchBox.TextSize = isMobile and 10 or 12
    searchBox.Font = Enum.Font.Gotham
    searchBox.TextXAlignment = Enum.TextXAlignment.Left
    searchBox.ClearTextOnFocus = false
    searchBox.ZIndex = 13
    Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 7)
    local searchStroke = Instance.new("UIStroke", searchBox)
    searchStroke.Color = C.border
    searchStroke.Thickness = 1
    searchStroke.Transparency = 0.55
    local searchPad = Instance.new("UIPadding", searchBox)
    searchPad.PaddingLeft = UDim.new(0, 8)
    searchPad.PaddingRight = UDim.new(0, 8)

    local viewRow = Instance.new("Frame", filterBar)
    viewRow.Size = UDim2.new(1, -16, 0, isMobile and 18 or 24)
    viewRow.Position = UDim2.new(0, 8, 0, isMobile and 33 or 42)
    viewRow.BackgroundTransparency = 1
    viewRow.ZIndex = 13
    local viewLay = Instance.new("UIListLayout", viewRow)
    viewLay.FillDirection = Enum.FillDirection.Horizontal
    viewLay.SortOrder = Enum.SortOrder.LayoutOrder
    viewLay.Padding = UDim.new(0, 6)

    local sortRow = Instance.new("Frame", filterBar)
    sortRow.Size = UDim2.new(1, -16, 0, isMobile and 19 or 24)
    sortRow.Position = UDim2.new(0, 8, 1, isMobile and -23 or -29)
    sortRow.BackgroundTransparency = 1
    sortRow.ZIndex = 13
    local sortLay = Instance.new("UIListLayout", sortRow)
    sortLay.FillDirection = Enum.FillDirection.Horizontal
    sortLay.SortOrder = Enum.SortOrder.LayoutOrder
    sortLay.Padding = UDim.new(0, 6)

    local function refreshSortButtons()
        for mode, btn in pairs(sortButtons) do
            local active = mode == sortMode
            btn.BackgroundColor3 = active and C.accent or C.surface
            btn.TextColor3 = active and Color3.fromRGB(255, 255, 255) or C.textSec
        end
        for mode, btn in pairs(viewButtons) do
            local active = mode == viewMode
            btn.BackgroundColor3 = active and C.purple or C.surface
            btn.TextColor3 = active and Color3.fromRGB(255, 255, 255) or C.textSec
        end
    end

    local function applyCardFilters()
        local needle = tostring(searchText or ""):lower()
        local visibleEntries = {}
        local visibleSections = {}
        for _, entry in ipairs(cardEntries) do
            local matchesSearch = needle == "" or entry.searchText:find(needle, 1, true) ~= nil
            local favoriteNow = type(entry.isFavorite) == "function" and entry.isFavorite() or entry.favorite == true
            local category = entry.category or "Official"
            local matchesView = viewMode == "All"
                or (viewMode == "Favorites" and favoriteNow)
                or (viewMode == "Custom" and category == "Custom")
                or (viewMode == "Community" and category == "Community")
            local visible = matchesSearch and matchesView
            entry.card.Visible = visible
            if visible then
                table.insert(visibleEntries, entry)
                visibleSections[entry.section] = true
            end
        end
        if sortMode == "Default" then
            for _, entry in ipairs(cardEntries) do
                entry.card.LayoutOrder = entry.originalOrder
            end
            for _, header in ipairs(sectionHeaders) do
                header.frame.Visible = visibleSections[header.section] == true
            end
        else
            for _, header in ipairs(sectionHeaders) do
                header.frame.Visible = false
            end
            local sortKey = sortMode == "Gems" and "gemsSort" or "coinsSort"
            table.sort(visibleEntries, function(a, b)
                local av = a[sortKey] or 0
                local bv = b[sortKey] or 0
                if av == bv then
                    return tostring(a.name or "") < tostring(b.name or "")
                end
                return av > bv
            end)
            for i, entry in ipairs(visibleEntries) do
                entry.card.LayoutOrder = i
            end
        end
        refreshSortButtons()
        task.defer(function()
            content.CanvasSize = UDim2.new(0, 0, 0, cLay.AbsoluteContentSize.Y + 16)
        end)
    end

    local function makeSortButton(label, mode, order)
        local b = Instance.new("TextButton", sortRow)
        b.Size = UDim2.new(1 / 3, -4, 1, 0)
        b.BackgroundColor3 = C.surface
        b.BorderSizePixel = 0
        b.Text = label
        b.TextColor3 = C.textSec
        b.TextSize = isMobile and 9 or 11
        b.Font = Enum.Font.GothamBold
        b.AutoButtonColor = false
        b.LayoutOrder = order
        b.ZIndex = 14
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        local s = Instance.new("UIStroke", b)
        s.Color = C.border
        s.Thickness = 1
        s.Transparency = 0.55
        sortButtons[mode] = b
        b.MouseButton1Click:Connect(function()
            sortMode = mode
            applyCardFilters()
        end)
        return b
    end

    local function makeViewButton(label, mode, order)
        local b = Instance.new("TextButton", viewRow)
        b.Size = UDim2.new(1 / 4, -5, 1, 0)
        b.BackgroundColor3 = C.surface
        b.BorderSizePixel = 0
        b.Text = label
        b.TextColor3 = C.textSec
        b.TextSize = isMobile and 8 or 10
        b.Font = Enum.Font.GothamBold
        b.AutoButtonColor = false
        b.LayoutOrder = order
        b.ZIndex = 14
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        local s = Instance.new("UIStroke", b)
        s.Color = C.border
        s.Thickness = 1
        s.Transparency = 0.55
        viewButtons[mode] = b
        b.MouseButton1Click:Connect(function()
            viewMode = mode
            applyCardFilters()
        end)
        return b
    end

    makeViewButton("All", "All", 1)
    makeViewButton("Favorites", "Favorites", 2)
    makeViewButton("My Strats", "Custom", 3)
    makeViewButton("Community", "Community", 4)

    makeSortButton("Default", "Default", 1)
    makeSortButton("Coins/hr", "Coins", 2)
    makeSortButton("Gems/hr", "Gems", 3)
    refreshSortButtons()

    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        searchText = searchBox.Text
        applyCardFilters()
    end)

    local miscPanelOk, miscPanelErr = pcall(function()
        -- Extras
        local extras = Instance.new("Frame", main)
        extras.Name = "Extras"
        extras.Size = UDim2.new(1, 0, 1, -(M.hdr + 2))
        extras.Position = UDim2.new(1, 0, 0, M.hdr + 2)
        extras.BackgroundColor3 = C.bg
        extras.BorderSizePixel = 0
        extras.ZIndex = 20
        extras.Visible = false
        extras.ClipsDescendants = true
        local eGrad = Instance.new("UIGradient", extras)
        eGrad.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 17, 28)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 12, 22)),
        })
        eGrad.Rotation = 160

        local eScroll = Instance.new("ScrollingFrame", extras)
        eScroll.Size = UDim2.new(1, -(M.pad * 2), 1, -(M.pad * 2))
        eScroll.Position = UDim2.new(0, M.pad, 0, M.pad)
        eScroll.BackgroundTransparency = 1
        eScroll.BorderSizePixel = 0
        eScroll.ScrollBarThickness = isMobile and 2 or 3
        eScroll.ScrollBarImageColor3 = Color3.fromRGB(60, 70, 100)
        eScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        eScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        eScroll.ScrollingDirection = Enum.ScrollingDirection.Y
        eScroll.ElasticBehavior = Enum.ElasticBehavior.Always
        eScroll.ZIndex = 21
        eScroll.Active = true
        eScroll.Selectable = false
        eScroll.ScrollingEnabled = true

        local eLay = Instance.new("UIListLayout", eScroll)
        eLay.SortOrder = Enum.SortOrder.LayoutOrder
        eLay.Padding = UDim.new(0, isMobile and 6 or 7)
        local ePad = Instance.new("UIPadding", eScroll)
        ePad.PaddingTop = UDim.new(0, 2)
        ePad.PaddingBottom = UDim.new(0, 12)

        local function syncExtrasCanvas()
            task.defer(function()
                if not (eScroll and eScroll.Parent) then
                    return
                end
                local y = eLay.AbsoluteContentSize.Y + (isMobile and 20 or 28)
                eScroll.CanvasSize = UDim2.new(0, 0, 0, math.max(y, eScroll.AbsoluteSize.Y + 2))
                eScroll.ScrollingEnabled = y > eScroll.AbsoluteSize.Y + 1
            end)
        end
        eLay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(syncExtrasCanvas)
        eScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncExtrasCanvas)

        local backBtn = Instance.new("TextButton", eScroll)
        backBtn.Size = UDim2.new(1, 0, 0, M.btn)
        backBtn.BackgroundColor3 = C.surface
        backBtn.BorderSizePixel = 0
        backBtn.Text = "< Back"
        backBtn.TextColor3 = C.textSec
        backBtn.TextSize = isMobile and 11 or 13
        backBtn.Font = Enum.Font.GothamBold
        backBtn.LayoutOrder = 0
        backBtn.ZIndex = 22
        Instance.new("UICorner", backBtn).CornerRadius = UDim.new(0, M.cr)
        local bkS = Instance.new("UIStroke", backBtn)
        bkS.Color = C.border
        bkS.Thickness = 1
        bkS.Transparency = 0.4
        backBtn.MouseEnter:Connect(function()
            TweenService:Create(backBtn, TweenInfo.new(0.12), { BackgroundColor3 = C.surfaceAlt, TextColor3 = C.text })
                :Play()
        end)
        backBtn.MouseLeave:Connect(function()
            TweenService:Create(backBtn, TweenInfo.new(0.12), { BackgroundColor3 = C.surface, TextColor3 = C.textSec })
                :Play()
        end)

        local function eSectionHdr(text, ord)
            local f = Instance.new("Frame", eScroll)
            f.Size = UDim2.new(1, 0, 0, isMobile and 20 or 24)
            f.BackgroundTransparency = 1
            f.LayoutOrder = ord
            f.ZIndex = 22
            local bar = Instance.new("Frame", f)
            bar.Size = UDim2.new(0, 3, 0, 12)
            bar.Position = UDim2.new(0, 0, 0.5, -6)
            bar.BackgroundColor3 = C.accent
            bar.BorderSizePixel = 0
            bar.ZIndex = 22
            Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
            local l = Instance.new("TextLabel", f)
            l.Size = UDim2.new(1, -10, 1, 0)
            l.Position = UDim2.new(0, 10, 0, 0)
            l.BackgroundTransparency = 1
            l.Text = string.upper(text)
            l.TextColor3 = C.textDim
            l.TextSize = isMobile and 9 or 10
            l.Font = Enum.Font.GothamBold
            l.TextXAlignment = Enum.TextXAlignment.Left
            l.ZIndex = 22
            local line = Instance.new("Frame", f)
            line.Size = UDim2.new(1, 0, 0, 1)
            line.Position = UDim2.new(0, 0, 1, -1)
            line.BackgroundColor3 = C.border
            line.BackgroundTransparency = 0.5
            line.BorderSizePixel = 0
            line.ZIndex = 22
            return f
        end

        eSectionHdr("Farm Setup", 1)

        local function makeToggle(label, desc, ord, cb, initial, keybind)
            local f = Instance.new("Frame", eScroll)
            f.Size = UDim2.new(1, 0, 0, M.tog)
            f.BackgroundColor3 = C.card
            f.BorderSizePixel = 0
            f.LayoutOrder = ord
            f.ZIndex = 22
            Instance.new("UICorner", f).CornerRadius = UDim.new(0, M.cr)
            local fs = Instance.new("UIStroke", f)
            fs.Color = C.border
            fs.Thickness = 1
            fs.Transparency = 0.5
            local keybindId = nil
            local resolvedKeybind = nil
            if (not isMobile) and type(keybind) == "table" and keybind.key then
                keybindId = tostring(keybind.id or keybindIdFromLabel(label))
                local bindOk, bindResult = pcall(resolveKeybind, keybindId, keybind)
                resolvedKeybind = (bindOk and bindResult) or copyKeybind(keybind)
                if type(resolvedKeybind) == "table" then
                    resolvedKeybind.id = keybindId
                    resolvedKeybind.order = tonumber(resolvedKeybind.order) or tonumber(keybind.order) or ord
                    resolvedKeybind.text = keybindText(resolvedKeybind)
                end
            end
            local hasKeybind = type(resolvedKeybind) == "table" and resolvedKeybind.key ~= nil
            local textReserve = hasKeybind and 132 or 60
            local nl = Instance.new("TextLabel", f)
            nl.Size = UDim2.new(1, -textReserve, 0, 14)
            nl.Position = UDim2.new(0, 10, 0, desc and 4 or (M.tog / 2 - 7))
            nl.BackgroundTransparency = 1
            nl.Text = label
            nl.TextColor3 = C.text
            nl.BorderSizePixel = 0
            nl.TextSize = 13
            nl.Font = Enum.Font.GothamBold
            nl.TextTruncate = Enum.TextTruncate.AtEnd
            nl.TextXAlignment = Enum.TextXAlignment.Left
            nl.ZIndex = 23
            if desc then
                local dl = Instance.new("TextLabel", f)
                dl.Size = UDim2.new(1, -textReserve, 0, isMobile and 28 or 24)
                dl.Position = UDim2.new(0, 10, 0, 20)
                dl.BackgroundTransparency = 1
                dl.Text = desc
                dl.TextColor3 = C.textDim
                dl.BorderSizePixel = 0
                dl.TextSize = isMobile and 11 or 10
                dl.Font = Enum.Font.Gotham
                dl.TextWrapped = true
                dl.TextYAlignment = Enum.TextYAlignment.Top
                dl.TextXAlignment = Enum.TextXAlignment.Left
                dl.ZIndex = 23
            end
            local pill = nil
            if hasKeybind then
                pill = Instance.new("TextLabel", f)
                pill.Size = UDim2.new(0, 62, 0, 20)
                pill.Position = UDim2.new(1, -(M.togW + 78), 0.5, -10)
                pill.BackgroundColor3 = C.surfaceAlt
                pill.BorderSizePixel = 0
                pill.Text = tostring(resolvedKeybind.text or "?")
                pill.TextColor3 = C.textSec
                pill.TextSize = 10
                pill.Font = Enum.Font.GothamBold
                pill.ZIndex = 23
                Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 8)
                local ps = Instance.new("UIStroke", pill)
                ps.Color = C.border
                ps.Thickness = 1
                ps.Transparency = 0.5
            end
            local track = Instance.new("TextButton", f)
            track.Size = UDim2.new(0, M.togW, 0, M.togH)
            track.Position = UDim2.new(1, -(M.togW + 8), 0.5, -(M.togH / 2))
            track.BackgroundColor3 = C.surfaceAlt
            track.BorderSizePixel = 0
            track.Text = ""
            track.ZIndex = 23
            Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
            local knob = Instance.new("Frame", track)
            knob.Size = UDim2.new(0, M.knob, 0, M.knob)
            knob.Position = UDim2.new(0, 3, 0.5, -(M.knob / 2))
            knob.BackgroundColor3 = Color3.fromRGB(160, 170, 195)
            knob.BorderSizePixel = 0
            knob.ZIndex = 24
            Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
            local on = false
            local function renderToggle(animated)
                if on then
                    local props = { BackgroundColor3 = C.accent }
                    local knobProps = {
                        Position = UDim2.new(0, M.togW - M.knob - 3, 0.5, -(M.knob / 2)),
                        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                    }
                    if animated then
                        TweenService:Create(track, TweenInfo.new(0.2, Enum.EasingStyle.Quint), props):Play()
                        TweenService:Create(knob, TweenInfo.new(0.2, Enum.EasingStyle.Quint), knobProps):Play()
                    else
                        track.BackgroundColor3 = props.BackgroundColor3
                        knob.Position = knobProps.Position
                        knob.BackgroundColor3 = knobProps.BackgroundColor3
                    end
                else
                    local props = { BackgroundColor3 = C.surfaceAlt }
                    local knobProps = {
                        Position = UDim2.new(0, 3, 0.5, -(M.knob / 2)),
                        BackgroundColor3 = Color3.fromRGB(160, 170, 195),
                    }
                    if animated then
                        TweenService:Create(track, TweenInfo.new(0.2, Enum.EasingStyle.Quint), props):Play()
                        TweenService:Create(knob, TweenInfo.new(0.2, Enum.EasingStyle.Quint), knobProps):Play()
                    else
                        track.BackgroundColor3 = props.BackgroundColor3
                        knob.Position = knobProps.Position
                        knob.BackgroundColor3 = knobProps.BackgroundColor3
                    end
                end
            end
            local function setToggle(nextOn, runCallback, animated)
                local previous = on
                on = nextOn == true
                renderToggle(animated ~= false)
                if runCallback ~= false then
                    local ok, result = pcall(cb, on)
                    if not ok then
                        on = previous
                        renderToggle(false)
                        warn("[Zephyr] Toggle callback failed:", tostring(label), tostring(result))
                        pcall(function()
                            toast(tostring(label) .. " failed in this place", C.red)
                        end)
                    elseif result == false and on then
                        on = false
                        renderToggle(animated ~= false)
                    end
                end
                if type(refreshKeybindList) == "function" then
                    task.defer(refreshKeybindList)
                end
            end
            local hit = Instance.new("TextButton", f)
            hit.Name = "ToggleHitTarget"
            hit.BackgroundTransparency = 1
            hit.Text = ""
            hit.BorderSizePixel = 0
            hit.Size = UDim2.new(0, 56, 1, 0)
            hit.Position = UDim2.new(1, -56, 0, 0)
            hit.ZIndex = 25
            hit.Activated:Connect(function()
                setToggle(not on, true, true)
            end)
            if hasKeybind then
                table.insert(keybindEntries, {
                    id = keybindId,
                    label = label,
                    text = tostring(resolvedKeybind.text or "?"),
                    binding = resolvedKeybind,
                    defaultBinding = copyKeybind(keybind),
                    order = tonumber(resolvedKeybind.order) or ord,
                    get = function()
                        return on
                    end,
                    set = setToggle,
                    onBindingChanged = function(updated)
                        if pill then
                            pill.Text = tostring(updated.text or "?")
                        end
                    end,
                })
                if type(refreshKeybindList) == "function" then
                    task.defer(refreshKeybindList)
                end
            end
            if initial then
                setToggle(true, false, false)
                task.defer(function()
                    waitForTdsUiReady(AUTOEXEC_UI_READY_TIMEOUT)
                    task.wait(AUTOEXEC_FEATURE_START_DELAY)
                    if runtimeAlive and on and track.Parent then
                        setToggle(true, true, false)
                    end
                end)
            end
            return setToggle
        end

        local rejoinConfig = getAutoRejoinConfig()
        local rejoinF = Instance.new("Frame", eScroll)
        rejoinF.Size = UDim2.new(1, 0, 0, isMobile and 206 or 172)
        rejoinF.BackgroundColor3 = C.card
        rejoinF.BorderSizePixel = 0
        rejoinF.LayoutOrder = 2
        rejoinF.ZIndex = 22
        Instance.new("UICorner", rejoinF).CornerRadius = UDim.new(0, M.cr)
        local rejoinS = Instance.new("UIStroke", rejoinF)
        rejoinS.Color = C.border
        rejoinS.Thickness = 1
        rejoinS.Transparency = 0.5

        local rejoinDefaultKeybind = not isMobile
                and { key = Enum.KeyCode.Z, alt = true, ctrl = false, shift = false, text = "Alt+Z", order = 2 }
            or nil
        local rejoinBinding = nil
        if rejoinDefaultKeybind then
            local bindOk, bindResult = pcall(resolveKeybind, "auto_rejoin_strat", rejoinDefaultKeybind)
            rejoinBinding = (bindOk and bindResult) or copyKeybind(rejoinDefaultKeybind)
            if type(rejoinBinding) == "table" then
                rejoinBinding.id = "auto_rejoin_strat"
                rejoinBinding.order = 2
                rejoinBinding.text = keybindText(rejoinBinding)
            end
        end
        local rejoinKey = nil

        local rejoinLabel = Instance.new("TextLabel", rejoinF)
        rejoinLabel.Size = UDim2.new(1, (not isMobile) and -138 or -70, 0, 14)
        rejoinLabel.Position = UDim2.new(0, 10, 0, 6)
        rejoinLabel.BackgroundTransparency = 1
        rejoinLabel.Text = "Auto Rejoin Strat"
        rejoinLabel.TextColor3 = C.text
        rejoinLabel.TextSize = isMobile and 11 or 13
        rejoinLabel.Font = Enum.Font.GothamBold
        rejoinLabel.TextXAlignment = Enum.TextXAlignment.Left
        rejoinLabel.ZIndex = 23
        if not isMobile then
            rejoinKey = Instance.new("TextLabel", rejoinF)
            rejoinKey.Size = UDim2.new(0, 62, 0, 20)
            rejoinKey.Position = UDim2.new(1, -(M.togW + 78), 0, 8)
            rejoinKey.BackgroundColor3 = C.surfaceAlt
            rejoinKey.BorderSizePixel = 0
            rejoinKey.Text = (rejoinBinding and rejoinBinding.text) or "Alt+Z"
            rejoinKey.TextColor3 = C.textSec
            rejoinKey.TextSize = 10
            rejoinKey.Font = Enum.Font.GothamBold
            rejoinKey.ZIndex = 23
            Instance.new("UICorner", rejoinKey).CornerRadius = UDim.new(0, 8)
            local rks = Instance.new("UIStroke", rejoinKey)
            rks.Color = C.border
            rks.Thickness = 1
            rks.Transparency = 0.5
        end

        local rejoinInfo = Instance.new("TextLabel", rejoinF)
        rejoinInfo.Size = UDim2.new(1, -78, 0, 24)
        rejoinInfo.Position = UDim2.new(0, 10, 0, 21)
        rejoinInfo.BackgroundTransparency = 1
        rejoinInfo.Text = "Triumph strats only. After rewards, rejoins and runs the last winning strat."
        rejoinInfo.TextColor3 = C.textDim
        rejoinInfo.TextSize = isMobile and 8 or 9
        rejoinInfo.Font = Enum.Font.Gotham
        rejoinInfo.TextWrapped = true
        rejoinInfo.TextXAlignment = Enum.TextXAlignment.Left
        rejoinInfo.ZIndex = 23

        local rejoinWarn = Instance.new("TextLabel", rejoinF)
        rejoinWarn.Size = UDim2.new(1, -20, 0, 14)
        rejoinWarn.Position = UDim2.new(0, 10, 0, 48)
        rejoinWarn.BackgroundTransparency = 1
        rejoinWarn.Text = "Do not use for loss, XP, or restart-wave farms."
        rejoinWarn.TextColor3 = C.yellow
        rejoinWarn.TextSize = isMobile and 8 or 9
        rejoinWarn.Font = Enum.Font.GothamBold
        rejoinWarn.TextXAlignment = Enum.TextXAlignment.Left
        rejoinWarn.ZIndex = 23

        local rejoinTrack = Instance.new("TextButton", rejoinF)
        rejoinTrack.Size = UDim2.new(0, M.togW, 0, M.togH)
        rejoinTrack.Position = UDim2.new(1, -(M.togW + 8), 0, 8)
        rejoinTrack.BackgroundColor3 = C.surfaceAlt
        rejoinTrack.BorderSizePixel = 0
        rejoinTrack.Text = ""
        rejoinTrack.ZIndex = 23
        Instance.new("UICorner", rejoinTrack).CornerRadius = UDim.new(1, 0)
        local rejoinKnob = Instance.new("Frame", rejoinTrack)
        rejoinKnob.Size = UDim2.new(0, M.knob, 0, M.knob)
        rejoinKnob.Position = UDim2.new(0, 3, 0.5, -(M.knob / 2))
        rejoinKnob.BackgroundColor3 = Color3.fromRGB(160, 170, 195)
        rejoinKnob.BorderSizePixel = 0
        rejoinKnob.ZIndex = 24
        Instance.new("UICorner", rejoinKnob).CornerRadius = UDim.new(1, 0)

        local rejoinInputs = Instance.new("Frame", rejoinF)
        rejoinInputs.Size = UDim2.new(1, -16, 0, isMobile and 68 or 28)
        rejoinInputs.Position = UDim2.new(0, 8, 0, isMobile and 68 or 72)
        rejoinInputs.BackgroundTransparency = 1
        rejoinInputs.ZIndex = 23

        local function makeSettingsInput(parent, placeholder, text, xScale, wScale)
            local bg = Instance.new("Frame", parent)
            bg.Size = UDim2.new(wScale, -4, 0, 28)
            bg.Position = UDim2.new(xScale, 0, 0, 0)
            bg.BackgroundColor3 = C.surface
            bg.BorderSizePixel = 0
            bg.ZIndex = 23
            Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 7)
            local s = Instance.new("UIStroke", bg)
            s.Color = C.border
            s.Thickness = 1
            s.Transparency = 0.5
            local inp = Instance.new("TextBox", bg)
            inp.Size = UDim2.new(1, -10, 1, 0)
            inp.Position = UDim2.new(0, 5, 0, 0)
            inp.BackgroundTransparency = 1
            inp.PlaceholderText = placeholder
            inp.PlaceholderColor3 = C.textDim
            inp.Text = text or ""
            inp.TextColor3 = C.text
            inp.TextSize = isMobile and 9 or 11
            inp.Font = Enum.Font.Gotham
            inp.TextXAlignment = Enum.TextXAlignment.Left
            inp.ClearTextOnFocus = false
            inp.ZIndex = 24
            return inp
        end

        local openSettingsDropdown = nil
        local function makeSettingsDropdown(
            parent,
            options,
            selected,
            xScale,
            wScale,
            onSelect,
            maxVisible,
            yOffset,
            placeholder
        )
            options = type(options) == "table" and options or {}
            placeholder = tostring(placeholder or "Select")
            local function coerceDropdownValue(value)
                local text = trimText(value)
                if text == "" then
                    return ""
                end
                return matchKnownOption(options, text, text)
            end
            local holder = Instance.new("Frame", parent)
            holder.Size = UDim2.new(wScale, -4, 0, isMobile and 32 or 28)
            holder.Position = UDim2.new(xScale, 0, 0, tonumber(yOffset) or 0)
            holder.BackgroundColor3 = C.surface
            holder.BorderSizePixel = 0
            holder.ZIndex = 45
            holder.ClipsDescendants = false
            Instance.new("UICorner", holder).CornerRadius = UDim.new(0, 7)
            local s = Instance.new("UIStroke", holder)
            s.Color = C.border
            s.Thickness = 1
            s.Transparency = 0.5
            local arrowDown = string.char(226, 150, 188)
            local arrowUp = string.char(226, 150, 178)
            local btn = Instance.new("TextButton", holder)
            btn.Size = UDim2.new(1, 0, 1, 0)
            btn.Position = UDim2.new(0, 0, 0, 0)
            btn.BackgroundTransparency = 1
            btn.TextColor3 = C.text
            btn.TextSize = isMobile and 9 or 11
            btn.Font = Enum.Font.GothamMedium
            btn.TextXAlignment = Enum.TextXAlignment.Left
            btn.TextTruncate = Enum.TextTruncate.AtEnd
            btn.ZIndex = 46
            local btnPad = Instance.new("UIPadding", btn)
            btnPad.PaddingLeft = UDim.new(0, 8)
            btnPad.PaddingRight = UDim.new(0, 24)
            local arrow = Instance.new("TextLabel", holder)
            arrow.Size = UDim2.new(0, 20, 1, 0)
            arrow.Position = UDim2.new(1, -22, 0, 0)
            arrow.BackgroundTransparency = 1
            arrow.Text = arrowDown
            arrow.TextColor3 = C.textDim
            arrow.TextSize = isMobile and 8 or 10
            arrow.Font = Enum.Font.GothamBold
            arrow.ZIndex = 47
            local rowH = isMobile and 32 or 25
            local visibleRows = math.max(1, math.min(tonumber(maxVisible) or 6, #options))
            local list = Instance.new("ScrollingFrame", main)
            list.Size = UDim2.new(0, 120, 0, (visibleRows * rowH) + 8)
            list.Position = UDim2.new(0, 0, 0, 0)
            list.BackgroundColor3 = C.surfaceAlt
            list.BorderSizePixel = 0
            list.Visible = false
            list.ScrollBarThickness = 3
            list.CanvasSize = UDim2.new(0, 0, 0, 0)
            list.ZIndex = 95
            list.Active = true
            list.Selectable = false
            Instance.new("UICorner", list).CornerRadius = UDim.new(0, 7)
            local listStroke = Instance.new("UIStroke", list)
            listStroke.Color = C.accent
            listStroke.Thickness = 1
            listStroke.Transparency = 0.35
            local layout = Instance.new("UIListLayout", list)
            layout.SortOrder = Enum.SortOrder.LayoutOrder
            layout.Padding = UDim.new(0, 3)
            local pad = Instance.new("UIPadding", list)
            pad.PaddingTop = UDim.new(0, 4)
            pad.PaddingBottom = UDim.new(0, 4)
            pad.PaddingLeft = UDim.new(0, 4)
            pad.PaddingRight = UDim.new(0, 4)
            local dropdown = { Value = coerceDropdownValue(selected) }
            dropdown.Enabled = true
            local function refreshButton()
                local hasValue = dropdown.Value ~= ""
                btn.Text = hasValue and dropdown.Value or placeholder
                btn.TextColor3 = dropdown.Enabled and (hasValue and C.text or C.textDim)
                    or Color3.fromRGB(105, 112, 132)
                holder.BackgroundColor3 = dropdown.Enabled and C.surface or Color3.fromRGB(18, 20, 30)
                arrow.TextTransparency = dropdown.Enabled and 0 or 0.45
            end
            local function positionList()
                if not (holder and holder.Parent and main and main.Parent) then
                    return
                end
                local mainAbs = main.AbsolutePosition
                local mainSize = main.AbsoluteSize
                local holderAbs = holder.AbsolutePosition
                local holderSize = holder.AbsoluteSize
                local listH = (visibleRows * rowH) + 8
                local x = holderAbs.X - mainAbs.X
                local downY = holderAbs.Y - mainAbs.Y + holderSize.Y + 4
                local upY = holderAbs.Y - mainAbs.Y - listH - 4
                local y = downY
                if downY + listH > mainSize.Y - 6 and upY >= 6 then
                    y = upY
                end
                local maxY = math.max(6, mainSize.Y - listH - 6)
                list.Size = UDim2.new(0, math.max(80, holderSize.X), 0, listH)
                list.Position = UDim2.new(
                    0,
                    math.clamp(x, 6, math.max(6, mainSize.X - holderSize.X - 6)),
                    0,
                    math.clamp(y, 6, maxY)
                )
            end
            local function syncCanvas()
                task.defer(function()
                    local y = layout.AbsoluteContentSize.Y + 8
                    list.CanvasSize = UDim2.new(0, 0, 0, math.max(y, list.AbsoluteSize.Y))
                    list.ScrollingEnabled = y > list.AbsoluteSize.Y
                end)
            end
            layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(syncCanvas)
            local choicesBuilt = false
            local setOpen
            local function clearChoices()
                for _, child in ipairs(list:GetChildren()) do
                    if child:IsA("TextButton") then
                        child:Destroy()
                    end
                end
                choicesBuilt = false
            end
            local function buildChoices()
                if choicesBuilt then
                    return
                end
                choicesBuilt = true
                for i, option in ipairs(options) do
                    local choice = Instance.new("TextButton", list)
                    choice.Size = UDim2.new(1, -2, 0, rowH)
                    choice.LayoutOrder = i
                    choice.BackgroundColor3 = C.surface
                    choice.BorderSizePixel = 0
                    choice.Text = tostring(option)
                    choice.TextColor3 = C.textSec
                    choice.TextSize = isMobile and 10 or 10
                    choice.Font = Enum.Font.GothamMedium
                    choice.TextXAlignment = Enum.TextXAlignment.Left
                    choice.TextTruncate = Enum.TextTruncate.AtEnd
                    choice.ZIndex = 96
                    Instance.new("UICorner", choice).CornerRadius = UDim.new(0, 6)
                    local cp = Instance.new("UIPadding", choice)
                    cp.PaddingLeft = UDim.new(0, 7)
                    cp.PaddingRight = UDim.new(0, 7)
                    choice.MouseButton1Click:Connect(function()
                        dropdown:Set(option)
                        setOpen(false)
                    end)
                end
                syncCanvas()
            end
            setOpen = function(open)
                if openSettingsDropdown and openSettingsDropdown ~= setOpen then
                    pcall(openSettingsDropdown, false)
                end
                if open then
                    buildChoices()
                end
                if open then
                    positionList()
                end
                list.Visible = open == true
                arrow.Text = list.Visible and arrowUp or arrowDown
                s.Color = list.Visible and C.accent or C.border
                openSettingsDropdown = list.Visible and setOpen or nil
            end
            function dropdown:Set(value, silent)
                dropdown.Value = coerceDropdownValue(value)
                refreshButton()
                if not silent and type(onSelect) == "function" then
                    onSelect(dropdown.Value)
                end
            end
            function dropdown:SetEnabled(enabled)
                dropdown.Enabled = enabled ~= false
                if not dropdown.Enabled then
                    setOpen(false)
                end
                refreshButton()
            end
            function dropdown:SetOptions(newOptions, keepValue)
                options = type(newOptions) == "table" and newOptions or {}
                visibleRows = math.max(1, math.min(tonumber(maxVisible) or 6, #options))
                clearChoices()
                if keepValue == false then
                    dropdown.Value = ""
                else
                    dropdown.Value = coerceDropdownValue(dropdown.Value)
                end
                refreshButton()
                syncCanvas()
                if list.Visible then
                    buildChoices()
                    positionList()
                end
            end
            function dropdown:Get()
                return dropdown.Value
            end
            btn.MouseButton1Click:Connect(function()
                if not dropdown.Enabled then
                    return
                end
                setOpen(not list.Visible)
            end)
            holder:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
                if list.Visible then
                    positionList()
                end
            end)
            holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
                if list.Visible then
                    positionList()
                end
            end)
            main:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
                if list.Visible then
                    positionList()
                end
            end)
            main:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
                if list.Visible then
                    positionList()
                end
            end)
            refreshButton()
            syncCanvas()
            return dropdown
        end

        local rejoinInitialMap = trimText(rejoinConfig.map) ~= "" and normalizeAutoRejoinMap(rejoinConfig.map) or ""
        local rejoinInitialMode = (rejoinConfig.modeUserSet == true and trimText(rejoinConfig.mode) ~= "")
                and normalizeAutoRejoinMode(rejoinConfig.mode)
            or ""
        local syncAutoRejoinModeLock
        local rejoinMapDrop
        local rejoinModeDrop
        rejoinMapDrop = makeSettingsDropdown(
            rejoinInputs,
            TDS_MAP_OPTIONS,
            rejoinInitialMap,
            0,
            isMobile and 1 or 0.56,
            function(value)
                if trimText(value) == "" then
                    return
                end
                if isAutoRejoinModeLockedToMap(rejoinInitialMode) then
                    rejoinMapDrop:Set(rejoinInitialMode, true)
                    return
                end
                local normalizedMap = normalizeAutoRejoinMapForMode(value, rejoinInitialMode, "")
                if normalizedMap == "" then
                    toast("That map is not available for " .. tostring(rejoinInitialMode), C.yellow)
                    return
                end
                rejoinMapDrop:Set(normalizedMap, true)
                setNestedSetting("autoRejoin", "map", normalizedMap)
                saveSettingsNow()
                autoRejoinLaunchAttempted = false
                toast("Auto rejoin map saved", C.green)
            end,
            isMobile and 6 or 5,
            isMobile and 0 or nil,
            "Map"
        )
        rejoinModeDrop = makeSettingsDropdown(
            rejoinInputs,
            TDS_MODE_OPTIONS,
            rejoinInitialMode,
            isMobile and 0 or 0.56,
            isMobile and 1 or 0.44,
            function(value)
                if trimText(value) == "" then
                    return
                end
                local modeName = normalizeAutoRejoinMode(value)
                rejoinInitialMode = modeName
                setNestedSetting("autoRejoin", "mode", modeName)
                setNestedSetting("autoRejoin", "modeUserSet", true)
                setNestedSetting("autoRejoin", "modeAutoFilled", false)
                if type(syncAutoRejoinModeLock) == "function" then
                    syncAutoRejoinModeLock(true)
                end
                saveSettingsNow()
                toast("Auto rejoin mode saved", C.green)
            end,
            isMobile and 6 or 5,
            isMobile and 34 or nil,
            "Mode"
        )

        local rejoinRunBtn = Instance.new("TextButton", rejoinF)
        rejoinRunBtn.Size = UDim2.new(1, -16, 0, 26)
        rejoinRunBtn.Position = UDim2.new(0, 8, 0, isMobile and 138 or 112)
        rejoinRunBtn.BackgroundColor3 = C.accent
        rejoinRunBtn.BorderSizePixel = 0
        rejoinRunBtn.Text = "Start Vote Now"
        rejoinRunBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        rejoinRunBtn.TextSize = isMobile and 10 or 12
        rejoinRunBtn.Font = Enum.Font.GothamBold
        rejoinRunBtn.ZIndex = 23
        Instance.new("UICorner", rejoinRunBtn).CornerRadius = UDim.new(0, 7)
        rejoinRunBtn.MouseEnter:Connect(function()
            TweenService:Create(rejoinRunBtn, TweenInfo.new(0.1), { BackgroundColor3 = C.accentLit }):Play()
        end)
        rejoinRunBtn.MouseLeave:Connect(function()
            TweenService:Create(rejoinRunBtn, TweenInfo.new(0.1), { BackgroundColor3 = C.accent }):Play()
        end)

        local rejoinHint = Instance.new("TextLabel", rejoinF)
        rejoinHint.Size = UDim2.new(1, -20, 0, 26)
        rejoinHint.Position = UDim2.new(0, 10, 1, -34)
        rejoinHint.BackgroundTransparency = 1
        rejoinHint.Text = "Pick a map and mode. Special modes lock the map automatically."
        rejoinHint.TextColor3 = C.textDim
        rejoinHint.TextSize = isMobile and 7 or 9
        rejoinHint.Font = Enum.Font.Gotham
        rejoinHint.TextWrapped = true
        rejoinHint.TextXAlignment = Enum.TextXAlignment.Left
        rejoinHint.ZIndex = 23

        syncAutoRejoinModeLock = function(shouldSave)
            local modeName = normalizeAutoRejoinMode(rejoinModeDrop:Get())
            rejoinInitialMode = modeName
            if isAutoRejoinModeLockedToMap(modeName) then
                rejoinMapDrop:SetOptions(TDS_MAP_OPTIONS, true)
                rejoinMapDrop:Set(modeName, true)
                rejoinMapDrop:SetEnabled(false)
                setNestedSetting("autoRejoin", "map", modeName)
                rejoinHint.Text = "This mode picks its own map. Just press Start Vote Now."
            else
                local options = getAutoRejoinMapOptionsForMode(modeName)
                rejoinMapDrop:SetOptions(options, true)
                rejoinMapDrop:SetEnabled(true)
                local currentMap = normalizeAutoRejoinMapForMode(rejoinMapDrop:Get(), modeName, "")
                if currentMap == "" and isHardcoreAutoRejoinMode(modeName) then
                    currentMap = TDS_HARDCORE_MAP_OPTIONS[1] or ""
                end
                if currentMap ~= rejoinMapDrop:Get() then
                    rejoinMapDrop:Set(currentMap, true)
                    setNestedSetting("autoRejoin", "map", currentMap)
                elseif isAutoRejoinModeLockedToMap(rejoinMapDrop:Get()) then
                    rejoinMapDrop:Set("", true)
                    setNestedSetting("autoRejoin", "map", "")
                end
                rejoinHint.Text = isHardcoreAutoRejoinMode(modeName)
                        and "Hardcore only rolls Wrecked Battlefield, Outskirts Commune, Wretched Front, or Unknown Garden."
                    or "Pick a map and mode. No typing needed."
            end
            if shouldSave then
                autoRejoinLaunchAttempted = false
                saveSettingsNow()
            end
        end
        syncAutoRejoinModeLock(false)

        local rejoinOn = rejoinConfig.enabled == true
        local function renderRejoinToggle(animated)
            local bg = rejoinOn and C.accent or C.surfaceAlt
            local knobColor = rejoinOn and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(160, 170, 195)
            local knobPos = rejoinOn and UDim2.new(0, M.togW - M.knob - 3, 0.5, -(M.knob / 2))
                or UDim2.new(0, 3, 0.5, -(M.knob / 2))
            if animated then
                TweenService:Create(rejoinTrack, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { BackgroundColor3 = bg })
                    :Play()
                TweenService:Create(
                    rejoinKnob,
                    TweenInfo.new(0.2, Enum.EasingStyle.Quint),
                    { Position = knobPos, BackgroundColor3 = knobColor }
                ):Play()
            else
                rejoinTrack.BackgroundColor3 = bg
                rejoinKnob.Position = knobPos
                rejoinKnob.BackgroundColor3 = knobColor
            end
        end
        local function setRejoinEnabled(on, animated)
            rejoinOn = on == true
            setNestedSetting("autoRejoin", "enabled", rejoinOn)
            renderRejoinToggle(animated)
            autoRejoinStratSerial += 1
            autoRejoinLaunchAttempted = false
            toast(rejoinOn and "Triumph rejoin enabled" or "Triumph rejoin disabled", rejoinOn and C.green or C.red)
            if rejoinOn then
                task.defer(startLobbyAutoRejoinOnLaunch)
            end
            if type(refreshKeybindList) == "function" then
                task.defer(refreshKeybindList)
            end
        end
        renderRejoinToggle(false)
        rejoinTrack.MouseButton1Click:Connect(function()
            setRejoinEnabled(not rejoinOn, true)
        end)
        if not isMobile then
            table.insert(keybindEntries, {
                id = "auto_rejoin_strat",
                label = "Auto Rejoin Strat",
                text = (rejoinBinding and rejoinBinding.text) or "Alt+Z",
                binding = rejoinBinding,
                defaultBinding = copyKeybind(rejoinDefaultKeybind),
                order = 2,
                get = function()
                    return rejoinOn
                end,
                set = function(nextOn, _, animated)
                    setRejoinEnabled(nextOn, animated)
                end,
                onBindingChanged = function(updated)
                    if rejoinKey then
                        rejoinKey.Text = tostring(updated.text or "?")
                    end
                end,
            })
            if type(refreshKeybindList) == "function" then
                task.defer(refreshKeybindList)
            end
        end
        rejoinRunBtn.MouseButton1Click:Connect(function()
            local modeName = trimText(rejoinModeDrop:Get()) ~= "" and normalizeAutoRejoinMode(rejoinModeDrop:Get())
                or "Easy"
            local mapName
            if isAutoRejoinModeLockedToMap(modeName) then
                mapName = modeName
            else
                local rawMap = trimText(rejoinMapDrop:Get())
                if rawMap == "" then
                    toast("Pick a map first", C.red)
                    return
                end
                mapName = normalizeAutoRejoinMap(rawMap)
            end
            rejoinMapDrop:Set(mapName, true)
            rejoinModeDrop:Set(modeName, true)
            setNestedSetting("autoRejoin", "map", mapName)
            setNestedSetting("autoRejoin", "mode", modeName)
            setNestedSetting("autoRejoin", "modeUserSet", true)
            setNestedSetting("autoRejoin", "modeAutoFilled", false)
            saveSettingsNow()
            autoRejoinLaunchAttempted = false
            if not runLobbyAutoRejoinVote(true, false) then
                toast("Auto rejoin map is empty", C.red)
            end
        end)

        eSectionHdr("Votes & Ready", 10)

        local modF = Instance.new("Frame", eScroll)
        modF.Size = UDim2.new(1, 0, 0, isMobile and 156 or 168)
        modF.BackgroundColor3 = C.card
        modF.BorderSizePixel = 0
        modF.LayoutOrder = 11
        modF.ZIndex = 22
        Instance.new("UICorner", modF).CornerRadius = UDim.new(0, M.cr)
        local modS = Instance.new("UIStroke", modF)
        modS.Color = C.border
        modS.Thickness = 1
        modS.Transparency = 0.5
        local modL = Instance.new("TextLabel", modF)
        modL.Size = UDim2.new(1, -70, 0, 14)
        modL.Position = UDim2.new(0, 10, 0, 6)
        modL.BackgroundTransparency = 1
        modL.Text = "Modifier Picker"
        modL.TextColor3 = C.text
        modL.TextSize = isMobile and 11 or 13
        modL.Font = Enum.Font.GothamBold
        modL.TextXAlignment = Enum.TextXAlignment.Left
        modL.ZIndex = 23
        local selectedModText = Instance.new("TextLabel", modF)
        selectedModText.Size = UDim2.new(1, -20, 0, 14)
        selectedModText.Position = UDim2.new(0, 10, 0, 22)
        selectedModText.BackgroundTransparency = 1
        selectedModText.TextColor3 = C.textDim
        selectedModText.TextSize = isMobile and 8 or 9
        selectedModText.Font = Enum.Font.Gotham
        selectedModText.TextXAlignment = Enum.TextXAlignment.Left
        selectedModText.ZIndex = 23
        local modList = Instance.new("ScrollingFrame", modF)
        modList.Size = UDim2.new(1, -16, 0, isMobile and 72 or 80)
        modList.Position = UDim2.new(0, 8, 0, 42)
        modList.BackgroundColor3 = C.surface
        modList.BorderSizePixel = 0
        modList.ScrollBarThickness = 3
        modList.CanvasSize = UDim2.new(0, 0, 0, 0)
        modList.ZIndex = 23
        modList.Active = true
        modList.Selectable = false
        Instance.new("UICorner", modList).CornerRadius = UDim.new(0, 7)
        local modGrid = Instance.new("UIGridLayout", modList)
        modGrid.CellSize = UDim2.new(0.5, -5, 0, 24)
        modGrid.CellPadding = UDim2.new(0, 5, 0, 5)
        modGrid.SortOrder = Enum.SortOrder.LayoutOrder
        local selectedMods = {}
        local resolvedMods, modifierEntries, hasModifierData = resolveSelectedModifiers(true)
        for _, entry in ipairs(resolvedMods) do
            selectedMods[entry.id] = true
        end
        local knownModifierIds = {}
        for _, entry in ipairs(modifierEntries) do
            knownModifierIds[entry.id] = true
        end
        local function updateSelectedMods(persist)
            if not hasModifierData then
                local savedText = trimText(tdsSettings.modifierVoteText)
                selectedModText.Text = savedText ~= "" and ("Selected: " .. savedText) or "Selected: none"
                return splitList(savedText)
            end
            local list = {}
            local displays = {}
            for _, entry in ipairs(modifierEntries) do
                if selectedMods[entry.id] then
                    list[#list + 1] = entry.id
                    displays[#displays + 1] = entry.display
                end
            end
            for id in pairs(selectedMods) do
                if not knownModifierIds[id] then
                    list[#list + 1] = id
                    displays[#displays + 1] = id
                end
            end
            local modifierText = table.concat(list, ", ")
            if persist == true and tdsSettings.modifierVoteText ~= modifierText then
                tdsSettings.modifierVoteText = modifierText
                saveSettingsSoon()
                saveSettingsNow()
            end
            selectedModText.Text = #displays > 0 and ("Selected: " .. table.concat(displays, ", ")) or "Selected: none"
            return list
        end
        if #modifierEntries == 0 then
            modGrid.CellSize = UDim2.new(1, -6, 0, 44)
            local empty = Instance.new("TextLabel", modList)
            empty.LayoutOrder = 1
            empty.BackgroundTransparency = 1
            empty.Text = "No supported modifiers loaded."
            empty.TextColor3 = C.textDim
            empty.TextSize = isMobile and 8 or 9
            empty.TextWrapped = true
            empty.Font = Enum.Font.Gotham
            empty.ZIndex = 24
        end
        for i, entry in ipairs(modifierEntries) do
            local name = entry.id
            local b = Instance.new("TextButton", modList)
            b.LayoutOrder = i
            b.BackgroundColor3 = selectedMods[name] and C.accent or C.surfaceAlt
            b.BorderSizePixel = 0
            b.Text = entry.display
            b.TextColor3 = C.text
            b.TextSize = isMobile and 8 or 9
            b.TextScaled = true
            b.Font = Enum.Font.GothamMedium
            b.ZIndex = 24
            local bc = Instance.new("UITextSizeConstraint", b)
            bc.MinTextSize = 6
            bc.MaxTextSize = isMobile and 8 or 9
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
            b.MouseButton1Click:Connect(function()
                selectedMods[name] = not selectedMods[name] or nil
                b.BackgroundColor3 = selectedMods[name] and C.accent or C.surfaceAlt
                updateSelectedMods(true)
            end)
        end
        local function updateModifierCanvas()
            local contentY = modGrid.AbsoluteContentSize.Y
            local viewY = modList.AbsoluteSize.Y
            pcall(function()
                viewY = modList.AbsoluteWindowSize.Y
            end)
            if viewY <= 0 then
                viewY = modList.AbsoluteSize.Y
            end
            local canvasY = math.max(contentY, viewY)
            modList.CanvasSize = UDim2.new(0, 0, 0, canvasY)
            modList.ScrollingEnabled = contentY > viewY + 1
            local maxY = math.max(0, contentY - viewY)
            if modList.CanvasPosition.Y > maxY then
                modList.CanvasPosition = Vector2.new(0, maxY)
            end
        end
        task.defer(updateModifierCanvas)
        modGrid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateModifierCanvas)
        modList:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateModifierCanvas)
        updateSelectedMods(false)
        local modBtn = Instance.new("TextButton", modF)
        modBtn.Size = UDim2.new(1, -16, 0, 26)
        modBtn.Position = UDim2.new(0, 8, 1, -34)
        modBtn.BackgroundColor3 = C.accent
        modBtn.BorderSizePixel = 0
        modBtn.Text = "Vote Now"
        modBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        modBtn.TextSize = isMobile and 10 or 12
        modBtn.Font = Enum.Font.GothamBold
        modBtn.ZIndex = 23
        Instance.new("UICorner", modBtn).CornerRadius = UDim.new(0, 7)
        modBtn.MouseButton1Click:Connect(function()
            updateSelectedMods(true)
            local ok, msg = voteConfiguredModifiers()
            toast(tostring(msg or (ok and "Vote sent" or "Vote failed")), ok and C.green or C.red)
        end)

        local resultsF = Instance.new("Frame", eScroll)
        resultsF.Size = UDim2.new(1, 0, 0, isMobile and 116 or 124)
        resultsF.BackgroundColor3 = C.card
        resultsF.BorderSizePixel = 0
        resultsF.LayoutOrder = 21
        resultsF.ZIndex = 22
        Instance.new("UICorner", resultsF).CornerRadius = UDim.new(0, M.cr)
        local resultsS = Instance.new("UIStroke", resultsF)
        resultsS.Color = C.border
        resultsS.Thickness = 1
        resultsS.Transparency = 0.5
        local resultsL = Instance.new("TextLabel", resultsF)
        resultsL.Size = UDim2.new(1, -20, 0, 14)
        resultsL.Position = UDim2.new(0, 10, 0, 6)
        resultsL.BackgroundTransparency = 1
        resultsL.Text = "Discord Results"
        resultsL.TextColor3 = C.text
        resultsL.TextSize = isMobile and 11 or 13
        resultsL.Font = Enum.Font.GothamBold
        resultsL.TextXAlignment = Enum.TextXAlignment.Left
        resultsL.ZIndex = 23
        local resultsRow1 = Instance.new("Frame", resultsF)
        resultsRow1.Size = UDim2.new(1, -16, 0, 28)
        resultsRow1.Position = UDim2.new(0, 8, 0, 28)
        resultsRow1.BackgroundTransparency = 1
        resultsRow1.ZIndex = 23
        local webhookInp =
            makeSettingsInput(resultsRow1, "Discord webhook URL", tostring(tdsSettings.resultsWebhookUrl or ""), 0, 1)
        local resultsRow2 = Instance.new("Frame", resultsF)
        resultsRow2.Size = UDim2.new(1, -16, 0, 28)
        resultsRow2.Position = UDim2.new(0, 8, 0, 62)
        resultsRow2.BackgroundTransparency = 1
        resultsRow2.ZIndex = 23
        local intervalInp = makeSettingsInput(
            resultsRow2,
            "Minutes",
            tostring(tdsSettings.resultsWebhookIntervalMinutes or 60),
            0,
            0.32
        )
        local sendBtn = Instance.new("TextButton", resultsRow2)
        sendBtn.Size = UDim2.new(0.68, -4, 0, 28)
        sendBtn.Position = UDim2.new(0.32, 4, 0, 0)
        sendBtn.BackgroundColor3 = C.accent
        sendBtn.BorderSizePixel = 0
        sendBtn.Text = "Send Summary Now"
        sendBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        sendBtn.TextSize = isMobile and 10 or 12
        sendBtn.Font = Enum.Font.GothamBold
        sendBtn.ZIndex = 23
        Instance.new("UICorner", sendBtn).CornerRadius = UDim.new(0, 7)
        local resultsHint = Instance.new("TextLabel", resultsF)
        resultsHint.Size = UDim2.new(1, -20, 0, 18)
        resultsHint.Position = UDim2.new(0, 10, 1, -22)
        resultsHint.BackgroundTransparency = 1
        resultsHint.Text = "Sends rewards, coins, gems, and XP while you AFK."
        resultsHint.TextColor3 = C.textDim
        resultsHint.TextSize = isMobile and 7 or 9
        resultsHint.Font = Enum.Font.Gotham
        resultsHint.TextXAlignment = Enum.TextXAlignment.Left
        resultsHint.ZIndex = 23
        webhookInp.FocusLost:Connect(function()
            setSetting("resultsWebhookUrl", webhookInp.Text)
        end)
        intervalInp.FocusLost:Connect(function()
            setSetting("resultsWebhookIntervalMinutes", tonumber(intervalInp.Text) or 60)
        end)
        sendBtn.MouseButton1Click:Connect(function()
            setSetting("resultsWebhookUrl", webhookInp.Text)
            setSetting("resultsWebhookIntervalMinutes", tonumber(intervalInp.Text) or 60)
            local ok, msg = sendResultsSummary()
            toast(ok and "Results webhook sent" or tostring(msg), ok and C.green or C.red)
        end)

        local espAvailableNow = workspace:FindFirstChild("NPCs") ~= nil
            and ReplicatedStorage:FindFirstChild("StateReplicators") ~= nil
        if tdsSettings.espEnabled == true and not espAvailableNow then
            tdsSettings.espEnabled = false
            saveSettingsSoon()
        end

        eSectionHdr("Discord Tracking", 20)

        makeToggle(
            "Restart + Ready",
            "Restarts losses and readies after map load",
            12,
            function(on)
                setSetting("autoRestartEnabled", on)
                setSetting("autoReadyEnabled", on)
                autoReadyEnabled = on
                if on then
                    startAutoRespawnVote()
                    startAutoReady()
                    toast("Restart + Ready on", C.green)
                else
                    stopAutoRespawnVote()
                    stopAutoReady()
                    toast("Restart + Ready off", C.red)
                end
            end,
            tdsSettings.autoRestartEnabled == true or tdsSettings.autoReadyEnabled == true,
            bindAlt(Enum.KeyCode.R, 12)
        )
        makeToggle("Vote Modifiers", nil, 13, function(on)
            setSetting("modifierVoteEnabled", on)
            saveSettingsNow()
            modifierVoteEnabled = on
            if on then
                startModifierVote()
                toast("Modifier voting enabled", C.green)
            else
                stopModifierVote()
                toast("Modifier voting off", C.red)
            end
        end, tdsSettings.modifierVoteEnabled == true, bindAlt(Enum.KeyCode.V, 13))
        makeToggle("Results Webhook", "Turns Discord result tracking on", 22, function(on)
            setSetting("resultsTrackerEnabled", on)
            if on then
                startResultsTracker()
                toast("Results webhook on", C.green)
            else
                stopResultsTracker()
                toast("Results webhook off", C.red)
            end
        end, tdsSettings.resultsTrackerEnabled == true, bindAlt(Enum.KeyCode.W, 22))
        makeToggle("Match Tracker", "Shows live session rewards on screen", 23, function(on)
            setSetting("matchTrackerEnabled", on)
            matchTrackerEnabled = on
            if on then
                startMatchTracker()
                toast("Match tracker on", C.green)
            else
                stopMatchTracker()
                toast("Match tracker off", C.red)
            end
        end, tdsSettings.matchTrackerEnabled == true, bindAlt(Enum.KeyCode.M, 23))
        makeToggle("STREAMER MODE", "Hides your username", 24, function(on)
            setSetting("streamerModeEnabled", on)
            if on then
                startStreamerMode()
                toast("Streamer Mode on", C.green)
            else
                stopStreamerMode()
                toast("Streamer Mode off", C.red)
            end
        end, tdsSettings.streamerModeEnabled == true, bindAlt(Enum.KeyCode.H, 24))
        makeToggle("Autoskip", "Votes skip as soon as it can", 14, function(on)
            setSetting("autoskipEnabled", on)
            if on then
                startAutoskip()
                toast("Autoskip enabled", C.green)
            else
                stopAutoskip()
                toast("Autoskip disabled", C.red)
            end
        end, tdsSettings.autoskipEnabled == true, bindAlt(Enum.KeyCode.S, 14))
        eSectionHdr("Match Helpers", 30)

        makeToggle("ESP", "Enemy names and HP", 31, function(on)
            setSetting("espEnabled", on)
            if on then
                if startESP() then
                    toast("ESP enabled", C.green)
                else
                    setSetting("espEnabled", false)
                    stopESP()
                    toast("ESP only runs in-game", C.red)
                    return false
                end
            else
                stopESP()
                toast("ESP disabled", C.red)
            end
        end, tdsSettings.espEnabled == true, bindAlt(Enum.KeyCode.E, 31))
        eSectionHdr("Gatling Gun", 50)

        makeToggle("Gatling", "Auto-fire while Gatling is open", 51, function(on)
            setSetting("gatlingEnabled", on)
            if on then
                local ok = startGatling(gui, isMobile, C, toast)
                if ok then
                    toast("Gatling enabled", C.green)
                else
                    gatlingEnabled = false
                    setSetting("gatlingEnabled", false)
                    return false
                end
            else
                stopGatling()
                toast("Gatling disabled", C.red)
            end
        end, tdsSettings.gatlingEnabled == true, bindAlt(Enum.KeyCode.G, 51))
        local function makeChoiceRow(label, options, selected, ord, onChange)
            local f = Instance.new("Frame", eScroll)
            f.Size = UDim2.new(1, 0, 0, isMobile and 44 or 50)
            f.BackgroundColor3 = C.card
            f.BorderSizePixel = 0
            f.LayoutOrder = ord
            f.ZIndex = 22
            Instance.new("UICorner", f).CornerRadius = UDim.new(0, M.cr)
            local fs = Instance.new("UIStroke", f)
            fs.Color = C.border
            fs.Thickness = 1
            fs.Transparency = 0.5
            local l = Instance.new("TextLabel", f)
            l.Size = UDim2.new(0.3, 0, 0, 16)
            l.Position = UDim2.new(0, 10, 0.5, -8)
            l.BackgroundTransparency = 1
            l.Text = label
            l.TextColor3 = C.textSec
            l.TextSize = isMobile and 9 or 11
            l.Font = Enum.Font.GothamMedium
            l.TextXAlignment = Enum.TextXAlignment.Left
            l.ZIndex = 23
            local row = Instance.new("Frame", f)
            row.Size = UDim2.new(0.7, -16, 0, 26)
            row.Position = UDim2.new(0.3, 8, 0.5, -13)
            row.BackgroundTransparency = 1
            row.ZIndex = 23
            local buttons = {}
            local current = tostring(selected or options[1])
            local function render()
                for opt, btn in pairs(buttons) do
                    local active = opt:lower() == current:lower()
                    btn.BackgroundColor3 = active and C.accent or C.surfaceAlt
                    btn.TextColor3 = active and Color3.fromRGB(255, 255, 255) or C.textSec
                end
            end
            for i, opt in ipairs(options) do
                local btn = Instance.new("TextButton", row)
                btn.Size = UDim2.new(1 / #options, -4, 1, 0)
                btn.Position = UDim2.new((i - 1) / #options, 2, 0, 0)
                btn.BackgroundColor3 = C.surfaceAlt
                btn.BorderSizePixel = 0
                btn.Text = opt
                btn.Font = Enum.Font.GothamBold
                btn.TextSize = isMobile and 8 or 10
                btn.ZIndex = 24
                Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
                buttons[opt] = btn
                btn.MouseButton1Click:Connect(function()
                    current = opt
                    render()
                    onChange(opt)
                end)
            end
            render()
            return f
        end

        makeChoiceRow("Target", { "First", "Last", "Boss", "Closest", "Screen" }, gatlingTargetMode, 52, function(value)
            gatlingTargetMode = value
            setSetting("gatlingTargetMode", value)
            gatlingCacheTime = 0
            toast("Target: " .. value, C.green)
        end)
        makeChoiceRow("Target Glow", { "Off", "Chams" }, gatlingTargetEsp, 53, function(value)
            gatlingTargetEsp = value
            setSetting("gatlingTargetEsp", value)
            if value == "Off" then
                gatlingClearVisuals()
            end
            toast("Target glow: " .. value, C.green)
        end)
        makeChoiceRow("Max Targets", { "1", "2", "3", "5", "8", "10" }, tostring(gatlingMaxTargets), 54, function(value)
            gatlingMaxTargets = math.clamp(tonumber(value) or 5, 1, 10)
            setSetting("gatlingMaxTargets", gatlingMaxTargets)
            gatlingCacheTime = 0
            toast("Max targets: " .. tostring(gatlingMaxTargets), C.green)
        end)
        makeChoiceRow(
            "Burst",
            { "1", "4", "8", "12", "24", "48", "64" },
            tostring(gatlingBurstCount),
            55,
            function(value)
                gatlingBurstCount = math.clamp(tonumber(value) or 12, 1, 64)
                setSetting("gatlingBurstCount", gatlingBurstCount)
                toast("Burst: " .. tostring(gatlingBurstCount), C.green)
            end
        )
        makeToggle("Bullet Lines", "Show Gatling shots", 56, function(on)
            gatlingBulletLinesEnabled = on
            setSetting("gatlingBulletLinesEnabled", on)
            if not on then
                gatlingClearVisuals()
            end
            toast(on and "Bullet lines on" or "Bullet lines off", on and C.green or C.yellow)
        end, tdsSettings.gatlingBulletLinesEnabled == true, bindAlt(Enum.KeyCode.B, 56))
        makeToggle("No Hitsounds", "Mute Gatling hit sounds", 57, function(on)
            gatlingHitsoundsDisabled = on
            setSetting("gatlingHitsoundsDisabled", on)
            if not on then
                gatlingRestoreHitsounds()
            end
            toast(on and "Hitsounds muted" or "Hitsounds restored", on and C.green or C.yellow)
        end, tdsSettings.gatlingHitsoundsDisabled == true, bindAlt(Enum.KeyCode.J, 57))

        eSectionHdr("Airstrike", 60)
        makeToggle("Auto Airstrike", "Uses ready Military Base Airstrikes", 61, function(on)
            autoAirstrikeEnabled = on
            setSetting("autoAirstrikeEnabled", on)
            if on then
                startAutoAirstrike()
                toast("Auto Airstrike on", C.green)
            else
                stopAutoAirstrike()
                toast("Auto Airstrike off", C.red)
            end
        end, tdsSettings.autoAirstrikeEnabled == true, bindAlt(Enum.KeyCode.A, 61))
        makeChoiceRow("Target", { "Boss", "Lead", "Hidden", "Grouped" }, autoAirstrikeTarget, 62, function(value)
            autoAirstrikeTarget = value
            setSetting("autoAirstrikeTarget", value)
            gatlingInvalidateTargets()
            toast("Airstrike target: " .. value, C.green)
        end)

        eSectionHdr("Pursuit", 63)
        makeToggle("Auto Pursuit Position", "Retargets Pursuits onto enemy groups", 64, function(on)
            setSetting("autoPursuitPositionEnabled", on)
            if on then
                startAutoPursuitPosition()
                toast("Auto Pursuit Position on", C.green)
            else
                stopAutoPursuitPosition()
                toast("Auto Pursuit Position off", C.red)
            end
        end, tdsSettings.autoPursuitPositionEnabled == true, bindAlt(Enum.KeyCode.U, 64))
        makeChoiceRow(
            "Target",
            { "Grouped", "First", "Boss", "Closest", "Last" },
            tostring(tdsSettings.autoPursuitPositionTarget or "Grouped"),
            65,
            function(value)
                setSetting("autoPursuitPositionTarget", value)
                gatlingInvalidateTargets()
                toast("Pursuit target: " .. value, C.green)
            end
        )

        makeToggle("Auto Pickups", "Collect Bunz and lorebooks", 35, function(on)
            setSetting("pickupFarmEnabled", on)
            if on then
                if startPickupFarm() then
                    toast("Pickup farm enabled", C.green)
                else
                    setSetting("pickupFarmEnabled", false)
                    stopPickupFarm()
                    toast("Auto pickups only run in-game", C.red)
                    return false
                end
            else
                stopPickupFarm()
                toast("Pickup farm disabled", C.red)
            end
        end, tdsSettings.pickupFarmEnabled == true, bindAlt(Enum.KeyCode.X, 35))
        makeToggle("Auto Claim All", "Daily, time, quests, gifts, seasons", 36, function(on)
            autoClaimAllEnabled = on
            setSetting("autoClaimAllEnabled", on)
            if on then
                startAutoClaimAll(toast)
                toast("Auto claim all enabled", C.green)
            else
                stopAutoClaimAll()
                toast("Auto claim all disabled", C.red)
            end
        end, tdsSettings.autoClaimAllEnabled == true, bindAlt(Enum.KeyCode.C, 36))
        makeToggle("Rerun Last Strat", "Runs the last strat after restart", 4, function(on)
            setSetting("autoRerunStratsEnabled", on)
            autoRerunStratsEnabled = on
            autoRerunSerial += 1
            if on then
                toast("Auto rerun strats enabled", C.green)
            else
                toast("Auto rerun strats disabled", C.red)
            end
        end, tdsSettings.autoRerunStratsEnabled == true, bindAlt(Enum.KeyCode.L, 4))
        makeToggle("Cash Playback", "Ignores times; waits for enough cash", 5, function(on)
            setSetting("playbackMoneyModeEnabled", on)
            if on then
                toast("Cash-based playback enabled", C.green)
            else
                toast("Timed playback enabled", C.yellow)
            end
        end, tdsSettings.playbackMoneyModeEnabled == true, bindAlt(Enum.KeyCode.Y, 5))
        makeToggle("Auto Upgrade", "Upgrades owned towers you can afford", 33, function(on)
            setSetting("autoUpgradeEnabled", on)
            autoUpgradeEnabled = on
            if on then
                startAutoUpgrade()
                toast("Auto Upgrade on", C.green)
            else
                stopAutoUpgrade()
                toast("Auto Upgrade off", C.red)
            end
        end, tdsSettings.autoUpgradeEnabled == true, bindAlt(Enum.KeyCode.U, 33))
        makeToggle("Auto Upgrade Farms", "Only upgrades Farms when cash is ready", 34, function(on)
            setSetting("autoUpgradeFarmsEnabled", on)
            autoUpgradeFarmsEnabled = on
            if on then
                startAutoUpgradeFarms()
                toast("Auto Farm Upgrade on", C.green)
            else
                stopAutoUpgradeFarms()
                toast("Auto Farm Upgrade off", C.red)
            end
        end, tdsSettings.autoUpgradeFarmsEnabled == true, bindAlt(Enum.KeyCode.F, 34))

        local sellF = Instance.new("Frame", eScroll)
        sellF.Size = UDim2.new(1, 0, 0, isMobile and 42 or 46)
        sellF.BackgroundColor3 = C.card
        sellF.BorderSizePixel = 0
        sellF.LayoutOrder = 37
        sellF.ZIndex = 22
        Instance.new("UICorner", sellF).CornerRadius = UDim.new(0, M.cr)
        local sellS = Instance.new("UIStroke", sellF)
        sellS.Color = C.border
        sellS.Thickness = 1
        sellS.Transparency = 0.5
        local sellBtn = Instance.new("TextButton", sellF)
        sellBtn.Size = UDim2.new(1, -16, 0, isMobile and 28 or 30)
        sellBtn.Position = UDim2.new(0, 8, 0.5, -(isMobile and 14 or 15))
        sellBtn.BackgroundColor3 = C.red
        sellBtn.BorderSizePixel = 0
        sellBtn.Text = "Sell All"
        sellBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        sellBtn.TextSize = isMobile and 10 or 12
        sellBtn.Font = Enum.Font.GothamBold
        sellBtn.ZIndex = 23
        Instance.new("UICorner", sellBtn).CornerRadius = UDim.new(0, 7)
        sellBtn.MouseButton1Click:Connect(function()
            task.spawn(function()
                local count = sellAllOwnedTowers()
                toast("Sold " .. tostring(count) .. " towers", count > 0 and C.green or C.yellow)
            end)
        end)

        local fpsF = Instance.new("Frame", eScroll)
        fpsF.Size = UDim2.new(1, 0, 0, isMobile and 42 or 46)
        fpsF.BackgroundColor3 = C.card
        fpsF.BorderSizePixel = 0
        fpsF.LayoutOrder = 41
        fpsF.ZIndex = 22
        Instance.new("UICorner", fpsF).CornerRadius = UDim.new(0, M.cr)
        local fpsS = Instance.new("UIStroke", fpsF)
        fpsS.Color = C.border
        fpsS.Thickness = 1
        fpsS.Transparency = 0.5
        local fpsBtn = Instance.new("TextButton", fpsF)
        fpsBtn.Size = UDim2.new(1, -16, 0, isMobile and 28 or 30)
        fpsBtn.Position = UDim2.new(0, 8, 0.5, -(isMobile and 14 or 15))
        fpsBtn.BackgroundColor3 = C.blue
        fpsBtn.BorderSizePixel = 0
        fpsBtn.Text = "FPS Booster"
        fpsBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        fpsBtn.TextSize = isMobile and 10 or 12
        fpsBtn.Font = Enum.Font.GothamBold
        fpsBtn.ZIndex = 23
        Instance.new("UICorner", fpsBtn).CornerRadius = UDim.new(0, 7)
        fpsBtn.MouseButton1Click:Connect(function()
            task.spawn(function()
                local ok, state = applyFpsBooster()
                if ok and state == "already" then
                    toast("FPS Booster already active", C.yellow)
                elseif ok then
                    toast("FPS Booster applied", C.green)
                else
                    toast("FPS Booster failed", C.red)
                end
            end)
        end)

        eSectionHdr("Performance", 40)

        makeToggle("Enemy Stats", "Small enemy HP and DPS panel", 32, function(on)
            setSetting("enemyInspectorEnabled", on)
            enemyInspectorEnabled = on
            if on then
                if startEnemyInspector() then
                    toast("Enemy stats on", C.green)
                end
            else
                stopEnemyInspector()
                toast("Enemy stats off", C.red)
            end
        end, tdsSettings.enemyInspectorEnabled == true, bindAlt(Enum.KeyCode.N, 32))

        eSectionHdr("Unlocks", 70)

        makeToggle("Unlock Towers", "Sandbox-visible tower list", 71, function(on)
            setSetting("unlockTowersClientEnabled", on)
            local ok, result = setClientTowerUnlock(on)
            if ok then
                if on then
                    toast("Towers shown: " .. tostring(result), C.green)
                else
                    toast("Tower list restored", C.yellow)
                end
            else
                toast(tostring(result or "Tower unlock failed"), C.red)
                return false
            end
        end, tdsSettings.unlockTowersClientEnabled == true)

        makeToggle("Unlock Skins", "Shows skin names in the picker", 72, function(on)
            setSetting("unlockSkinsClientEnabled", on)
            local ok, result = setClientSkinUnlock(on)
            if ok then
                if on then
                    toast("Skins shown: " .. tostring(result), C.green)
                else
                    toast("Skin list restored", C.yellow)
                end
            else
                toast(tostring(result or "Skin unlock failed"), C.red)
                return false
            end
        end, tdsSettings.unlockSkinsClientEnabled == true)

        makeToggle("Unlock Emotes", "Shows every emote in the wheel", 73, function(on)
            setSetting("unlockEmotesClientEnabled", on)
            local ok, result = setClientEmoteUnlock(on)
            if ok then
                if on then
                    toast("Emotes shown: " .. tostring(result), C.green)
                else
                    toast("Emote list restored", C.yellow)
                end
            else
                toast(tostring(result or "Emote unlock failed"), C.red)
                return false
            end
        end, tdsSettings.unlockEmotesClientEnabled == true)

        makeToggle("Unlock Cosmetics", "Tags, totems, flairs, stickers", 74, function(on)
            setSetting("unlockCosmeticsClientEnabled", on)
            local ok, result = setClientCosmeticUnlock(on)
            if ok then
                if on then
                    toast("Cosmetics shown: " .. tostring(result), C.green)
                else
                    toast("Cosmetic list restored", C.yellow)
                end
            else
                toast(tostring(result or "Cosmetic unlock failed"), C.red)
                return false
            end
        end, tdsSettings.unlockCosmeticsClientEnabled == true)

        makeToggle("Skin Changer", "Uses the picker below", 75, function(on)
            setSetting("skinChangerEnabled", on)
            skinChangerEnabled = on
            if on then
                local ok = startSkinChanger()
                if ok then
                    local cacheModule = getClientCache()
                    if cacheModule then
                        applySavedSkinsToCache(cacheModule)
                    end
                    refreshSkinVisuals()
                    toast("Skin changer on", C.green)
                else
                    skinChangerEnabled = false
                    setSetting("skinChangerEnabled", false)
                    toast("Skin changer failed", C.red)
                    return false
                end
            else
                stopSkinChanger()
                toast("Skin changer off", C.red)
            end
        end, tdsSettings.skinChangerEnabled == true, bindAlt(Enum.KeyCode.I, 75))

        local skinPickerF = Instance.new("Frame", eScroll)
        skinPickerF.Size = UDim2.new(1, 0, 0, isMobile and 158 or 178)
        skinPickerF.BackgroundColor3 = C.card
        skinPickerF.BorderSizePixel = 0
        skinPickerF.LayoutOrder = 76
        skinPickerF.ZIndex = 22
        Instance.new("UICorner", skinPickerF).CornerRadius = UDim.new(0, M.cr)
        local skinPickerS = Instance.new("UIStroke", skinPickerF)
        skinPickerS.Color = C.border
        skinPickerS.Thickness = 1
        skinPickerS.Transparency = 0.5
        local skinPickerTitle = Instance.new("TextLabel", skinPickerF)
        skinPickerTitle.Size = UDim2.new(1, -20, 0, 16)
        skinPickerTitle.Position = UDim2.new(0, 10, 0, 6)
        skinPickerTitle.BackgroundTransparency = 1
        skinPickerTitle.Text = "Skin Picker"
        skinPickerTitle.TextColor3 = C.text
        skinPickerTitle.TextSize = isMobile and 11 or 13
        skinPickerTitle.Font = Enum.Font.GothamBold
        skinPickerTitle.TextXAlignment = Enum.TextXAlignment.Left
        skinPickerTitle.ZIndex = 23
        local skinPickerInfo = Instance.new("TextLabel", skinPickerF)
        skinPickerInfo.Size = UDim2.new(1, -20, 0, 14)
        skinPickerInfo.Position = UDim2.new(0, 10, 0, 24)
        skinPickerInfo.BackgroundTransparency = 1
        skinPickerInfo.TextColor3 = C.textDim
        skinPickerInfo.TextSize = isMobile and 8 or 9
        skinPickerInfo.Font = Enum.Font.Gotham
        skinPickerInfo.TextXAlignment = Enum.TextXAlignment.Left
        skinPickerInfo.ZIndex = 23
        local towerListFrame = Instance.new("ScrollingFrame", skinPickerF)
        towerListFrame.Size = UDim2.new(0.46, -12, 1, -48)
        towerListFrame.Position = UDim2.new(0, 8, 0, 42)
        towerListFrame.BackgroundColor3 = C.surface
        towerListFrame.BorderSizePixel = 0
        towerListFrame.ScrollBarThickness = 3
        towerListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
        towerListFrame.ZIndex = 23
        towerListFrame.Active = true
        towerListFrame.Selectable = false
        Instance.new("UICorner", towerListFrame).CornerRadius = UDim.new(0, 7)
        local skinListFrame = Instance.new("ScrollingFrame", skinPickerF)
        skinListFrame.Size = UDim2.new(0.54, -12, 1, -48)
        skinListFrame.Position = UDim2.new(0.46, 4, 0, 42)
        skinListFrame.BackgroundColor3 = C.surface
        skinListFrame.BorderSizePixel = 0
        skinListFrame.ScrollBarThickness = 3
        skinListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
        skinListFrame.ZIndex = 23
        skinListFrame.Active = true
        skinListFrame.Selectable = false
        Instance.new("UICorner", skinListFrame).CornerRadius = UDim.new(0, 7)
        local towerListLayout = Instance.new("UIListLayout", towerListFrame)
        towerListLayout.SortOrder = Enum.SortOrder.LayoutOrder
        towerListLayout.Padding = UDim.new(0, 4)
        local skinListLayout = Instance.new("UIListLayout", skinListFrame)
        skinListLayout.SortOrder = Enum.SortOrder.LayoutOrder
        skinListLayout.Padding = UDim.new(0, 4)
        local towerPad = Instance.new("UIPadding", towerListFrame)
        towerPad.PaddingTop = UDim.new(0, 4)
        towerPad.PaddingLeft = UDim.new(0, 4)
        towerPad.PaddingRight = UDim.new(0, 4)
        local skinPad = Instance.new("UIPadding", skinListFrame)
        skinPad.PaddingTop = UDim.new(0, 4)
        skinPad.PaddingLeft = UDim.new(0, 4)
        skinPad.PaddingRight = UDim.new(0, 4)

        local skinPickerTowers = getSkinPickerTowers()
        local skinPickerTower = skinPickerTowers[1] or ""
        local savedSkinSelections = getSkinSelections()
        for _, towerName in ipairs(skinPickerTowers) do
            if savedSkinSelections[towerName] then
                skinPickerTower = towerName
                break
            end
        end

        local function syncPickerCanvas(frame, layout)
            task.defer(function()
                local y = layout.AbsoluteContentSize.Y + 8
                frame.CanvasSize = UDim2.new(0, 0, 0, math.max(y, frame.AbsoluteSize.Y))
                frame.ScrollingEnabled = y > frame.AbsoluteSize.Y
            end)
        end
        towerListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            syncPickerCanvas(towerListFrame, towerListLayout)
        end)
        skinListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            syncPickerCanvas(skinListFrame, skinListLayout)
        end)

        local function clearPickerButtons(frame)
            for _, child in ipairs(frame:GetChildren()) do
                if child:IsA("TextButton") then
                    child:Destroy()
                end
            end
        end
        local function makePickerButton(parent, text, order, active, callback)
            local btn = Instance.new("TextButton", parent)
            btn.Size = UDim2.new(1, -2, 0, isMobile and 24 or 26)
            btn.LayoutOrder = order
            btn.BackgroundColor3 = active and C.accent or C.surfaceAlt
            btn.BorderSizePixel = 0
            btn.Text = text
            btn.TextColor3 = active and Color3.fromRGB(255, 255, 255) or C.textSec
            btn.TextSize = isMobile and 8 or 9
            btn.TextScaled = true
            btn.Font = Enum.Font.GothamMedium
            btn.ZIndex = 24
            local sizeLimit = Instance.new("UITextSizeConstraint", btn)
            sizeLimit.MinTextSize = 6
            sizeLimit.MaxTextSize = isMobile and 8 or 9
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
            btn.MouseButton1Click:Connect(callback)
            return btn
        end
        local function renderSkinPicker()
            clearPickerButtons(towerListFrame)
            clearPickerButtons(skinListFrame)
            if #skinPickerTowers == 0 then
                skinPickerInfo.Text = "No skin assets found"
                syncPickerCanvas(towerListFrame, towerListLayout)
                syncPickerCanvas(skinListFrame, skinListLayout)
                return
            end
            local savedSkin = getSavedSkin(skinPickerTower) or "Default"
            skinPickerInfo.Text = skinPickerTower .. " -> " .. savedSkin
            for i, towerName in ipairs(skinPickerTowers) do
                local selectedTowerName = towerName
                makePickerButton(towerListFrame, selectedTowerName, i, selectedTowerName == skinPickerTower, function()
                    skinPickerTower = selectedTowerName
                    renderSkinPicker()
                end)
            end
            local skins = getSkinsForTower(skinPickerTower)
            for i, skinName in ipairs(skins) do
                local selectedSkinName = skinName
                local selectedTowerName = skinPickerTower
                makePickerButton(skinListFrame, selectedSkinName, i, selectedSkinName == savedSkin, function()
                    setSavedSkin(selectedTowerName, selectedSkinName)
                    prefetchSavedSkinSources()
                    prefetchSpawnedUnitSkinSources()
                    skinPickerInfo.Text = selectedTowerName .. " -> " .. selectedSkinName
                    if skinChangerEnabled then
                        local cacheModule = getClientCache()
                        if cacheModule then
                            applySavedSkinsToCache(cacheModule)
                        end
                        refreshSkinVisuals()
                    end
                    toast("Saved " .. selectedTowerName .. " skin", C.green)
                    renderSkinPicker()
                end)
            end
            syncPickerCanvas(towerListFrame, towerListLayout)
            syncPickerCanvas(skinListFrame, skinListLayout)
        end
        renderSkinPicker()

        local slF = Instance.new("Frame", eScroll)
        eSectionHdr("Abilities", 80)

        makeToggle("Auto Use Abilities", "Fires DJ, Medic, and support abilities", 81, function(on)
            setSetting("abilityManagerEnabled", on)
            abilityManagerEnabled = on
            if on then
                startAbilityManager()
                toast("Auto abilities on", C.green)
            else
                stopAbilityManager()
                toast("Auto abilities off", C.red)
            end
        end, tdsSettings.abilityManagerEnabled == true, bindAlt(Enum.KeyCode.D, 81))

        makeToggle("Call To Arms Chain", "Rotates Commanders one CTA at a time", 82, function(on)
            setSetting("commanderChainEnabled", on)
            commanderChainEnabled = on
            if on then
                startCommanderChain()
                toast("Commander chain on", C.green)
            else
                stopCommanderChain()
                toast("Commander chain off", C.red)
            end
        end, tdsSettings.commanderChainEnabled == true, bindAlt(Enum.KeyCode.T, 82))

        makeToggle("Support Caravan", "Uses ready Commander caravans", 83, function(on)
            setSetting("supportCaravanEnabled", on)
            supportCaravanEnabled = on
            if on then
                startSupportCaravan()
                toast("Support Caravan enabled", C.green)
            else
                stopSupportCaravan()
                toast("Support Caravan disabled", C.red)
            end
        end, tdsSettings.supportCaravanEnabled == true, bindAlt(Enum.KeyCode.O, 83))

        slF.Size = UDim2.new(1, 0, 0, isMobile and 44 or 50)
        slF.BackgroundColor3 = C.card
        slF.BorderSizePixel = 0
        slF.LayoutOrder = 58
        slF.ZIndex = 22
        Instance.new("UICorner", slF).CornerRadius = UDim.new(0, M.cr)
        local slFS = Instance.new("UIStroke", slF)
        slFS.Color = C.border
        slFS.Thickness = 1
        slFS.Transparency = 0.5

        local slLabel = Instance.new("TextLabel", slF)
        slLabel.Size = UDim2.new(0.5, 0, 0, 14)
        slLabel.Position = UDim2.new(0, 10, 0, 4)
        slLabel.BackgroundTransparency = 1
        slLabel.Text = "Fire Rate"
        slLabel.TextColor3 = C.textSec
        slLabel.TextSize = isMobile and 9 or 11
        slLabel.Font = Enum.Font.GothamMedium
        slLabel.TextXAlignment = Enum.TextXAlignment.Left
        slLabel.ZIndex = 23

        local slVal = Instance.new("TextLabel", slF)
        slVal.Size = UDim2.new(0.5, -10, 0, 14)
        slVal.Position = UDim2.new(0.5, 0, 0, 4)
        slVal.BackgroundTransparency = 1
        slVal.TextColor3 = C.accent
        slVal.TextSize = isMobile and 9 or 11
        slVal.Font = Enum.Font.GothamBold
        slVal.TextXAlignment = Enum.TextXAlignment.Right
        slVal.ZIndex = 23

        local slArea = Instance.new("TextButton", slF)
        slArea.Size = UDim2.new(1, -20, 0, 16)
        slArea.Position = UDim2.new(0, 10, 0, isMobile and 22 or 28)
        slArea.BackgroundTransparency = 1
        slArea.Text = ""
        slArea.ZIndex = 23

        local slTrack = Instance.new("Frame", slArea)
        slTrack.Size = UDim2.new(1, 0, 0, 4)
        slTrack.Position = UDim2.new(0, 0, 0.5, -2)
        slTrack.BackgroundColor3 = C.surface
        slTrack.BorderSizePixel = 0
        slTrack.ZIndex = 23
        Instance.new("UICorner", slTrack).CornerRadius = UDim.new(0, 2)

        local slFill = Instance.new("Frame", slTrack)
        slFill.Size = UDim2.new(0.5, 0, 1, 0)
        slFill.BackgroundColor3 = C.accent
        slFill.BorderSizePixel = 0
        slFill.ZIndex = 24
        Instance.new("UICorner", slFill).CornerRadius = UDim.new(0, 2)

        local slHandle = Instance.new("Frame", slArea)
        slHandle.Size = UDim2.new(0, 14, 0, 14)
        slHandle.Position = UDim2.new(0.5, -7, 0.5, -7)
        slHandle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        slHandle.BorderSizePixel = 0
        slHandle.ZIndex = 25
        Instance.new("UICorner", slHandle).CornerRadius = UDim.new(1, 0)

        local function updateSliderVisual()
            local range = GATLING_RATE_MAX - GATLING_RATE_MIN
            local pct = (gatlingFireRateTicks - GATLING_RATE_MIN) / range
            pct = math.clamp(pct, 0, 1)
            slFill.Size = UDim2.new(pct, 0, 1, 0)
            slHandle.Position = UDim2.new(pct, -7, 0.5, -7)
            slVal.Text = string.format("%d ticks/s", math.floor(gatlingFireRateTicks + 0.5))
        end
        updateSliderVisual()
        gatlingSliderUpdateFn = updateSliderVisual

        local slDragging = false
        local function handleSliderInput(pos)
            local tPos = slTrack.AbsolutePosition
            local tW = slTrack.AbsoluteSize.X
            if tW <= 0 then
                return
            end
            local pct = math.clamp((pos.X - tPos.X) / tW, 0, 1)
            setGatlingFireRate(GATLING_RATE_MIN + pct * (GATLING_RATE_MAX - GATLING_RATE_MIN))
        end
        slArea.InputBegan:Connect(function(input)
            local t = input.UserInputType
            if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
                slDragging = true
                handleSliderInput(input.Position)
            end
        end)
        slArea.InputChanged:Connect(function(input)
            if slDragging then
                local t = input.UserInputType
                if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
                    handleSliderInput(input.Position)
                end
            end
        end)
        connectUI(UserInputService.InputEnded, function(input)
            local t = input.UserInputType
            if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
                slDragging = false
            end
        end)

        eSectionHdr("Tools", 90)

        local eqF = Instance.new("Frame", eScroll)
        eqF.Size = UDim2.new(1, 0, 0, isMobile and 76 or 82)
        eqF.BackgroundColor3 = C.card
        eqF.BorderSizePixel = 0
        eqF.LayoutOrder = 91
        eqF.ZIndex = 22
        Instance.new("UICorner", eqF).CornerRadius = UDim.new(0, M.cr)
        local eqS = Instance.new("UIStroke", eqF)
        eqS.Color = C.border
        eqS.Thickness = 1
        eqS.Transparency = 0.5

        local eqLabel = Instance.new("TextLabel", eqF)
        eqLabel.Size = UDim2.new(1, -16, 0, 14)
        eqLabel.Position = UDim2.new(0, 10, 0, 6)
        eqLabel.BackgroundTransparency = 1
        eqLabel.Text = "Equip Tower"
        eqLabel.TextColor3 = C.text
        eqLabel.TextSize = isMobile and 11 or 13
        eqLabel.Font = Enum.Font.GothamBold
        eqLabel.TextXAlignment = Enum.TextXAlignment.Left
        eqLabel.ZIndex = 23

        local eqInfo = Instance.new("TextLabel", eqF)
        eqInfo.Size = UDim2.new(1, -16, 0, 12)
        eqInfo.Position = UDim2.new(0, 10, 0, 21)
        eqInfo.BackgroundTransparency = 1
        eqInfo.Text = "Type a tower name and equip it"
        eqInfo.TextColor3 = C.textDim
        eqInfo.TextSize = isMobile and 8 or 9
        eqInfo.Font = Enum.Font.Gotham
        eqInfo.TextXAlignment = Enum.TextXAlignment.Left
        eqInfo.ZIndex = 23

        local eqRow = Instance.new("Frame", eqF)
        eqRow.Size = UDim2.new(1, -16, 0, 28)
        eqRow.Position = UDim2.new(0, 8, 1, -36)
        eqRow.BackgroundTransparency = 1
        eqRow.ZIndex = 23

        local eqInputBg = Instance.new("Frame", eqRow)
        eqInputBg.Size = UDim2.new(1, -68, 0, 28)
        eqInputBg.BackgroundColor3 = C.surface
        eqInputBg.BorderSizePixel = 0
        eqInputBg.ZIndex = 23
        Instance.new("UICorner", eqInputBg).CornerRadius = UDim.new(0, 7)
        local eqInpS = Instance.new("UIStroke", eqInputBg)
        eqInpS.Color = C.border
        eqInpS.Thickness = 1
        eqInpS.Transparency = 0.5

        local eqInp = Instance.new("TextBox", eqInputBg)
        eqInp.Size = UDim2.new(1, -10, 1, 0)
        eqInp.Position = UDim2.new(0, 5, 0, 0)
        eqInp.BackgroundTransparency = 1
        eqInp.PlaceholderText = "e.g. Trapper"
        eqInp.PlaceholderColor3 = C.textDim
        eqInp.Text = ""
        eqInp.TextColor3 = C.text
        eqInp.TextSize = isMobile and 10 or 12
        eqInp.Font = Enum.Font.Gotham
        eqInp.TextXAlignment = Enum.TextXAlignment.Left
        eqInp.ClearTextOnFocus = false
        eqInp.ZIndex = 24

        local eqBtn = Instance.new("TextButton", eqRow)
        eqBtn.Size = UDim2.new(0, 60, 0, 28)
        eqBtn.Position = UDim2.new(1, -60, 0, 0)
        eqBtn.BackgroundColor3 = C.accent
        eqBtn.BorderSizePixel = 0
        eqBtn.Text = "Equip"
        eqBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        eqBtn.TextSize = isMobile and 10 or 12
        eqBtn.Font = Enum.Font.GothamBold
        eqBtn.ZIndex = 23
        Instance.new("UICorner", eqBtn).CornerRadius = UDim.new(0, 7)
        eqBtn.MouseEnter:Connect(function()
            TweenService:Create(eqBtn, TweenInfo.new(0.1), { BackgroundColor3 = C.accentLit }):Play()
        end)
        eqBtn.MouseLeave:Connect(function()
            TweenService:Create(eqBtn, TweenInfo.new(0.1), { BackgroundColor3 = C.accent }):Play()
        end)
        eqBtn.MouseButton1Click:Connect(function()
            local towerName = capitalizeFirst(eqInp.Text)
            if not towerName or towerName == "" then
                toast("Enter a tower name", C.red)
                return
            end
            eqInp.Text = towerName
            local ok = equipTower(towerName)
            if ok then
                toast("Equipping: " .. towerName, C.green)
            else
                toast("Equip unavailable", C.red)
            end
        end)

        local stackSelectedTower = tostring(tdsSettings.towerStackName or "")
        if stackSelectedTower == "" then
            stackSelectedTower = nil
        end
        local stackLastPlace = 0
        local stackLastFailToast = 0
        local stackHolding = false
        local stackHoldTouch = nil
        local stackTouch = nil
        local stackTouchStart = 0
        local stackTouchPos = nil
        local STACK_PLACE_INTERVAL = 0.065

        local function pointInsideGui(obj, pos)
            if not obj or not obj.Visible then
                return false
            end
            local ap = obj.AbsolutePosition
            local as = obj.AbsoluteSize
            return pos.X >= ap.X and pos.X <= ap.X + as.X and pos.Y >= ap.Y and pos.Y <= ap.Y + as.Y
        end

        local function stackInputBlocked(pos)
            if not gui.Parent then
                return true
            end
            if UserInputService:GetFocusedTextBox() then
                return true
            end
            return pointInsideGui(main, pos) or pointInsideGui(toggleBtn, pos)
        end

        local function getStackWorldPosition()
            local char = LocalPlayer.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
            if not root then
                return nil, nil, nil
            end
            local cam = workspace.CurrentCamera
            local params = RaycastParams.new()
            local filterOk = pcall(function()
                params.FilterType = Enum.RaycastFilterType.Blacklist
            end)
            if not filterOk then
                pcall(function()
                    params.FilterType = Enum.RaycastFilterType.Exclude
                end)
            end
            local filtered = { char }
            if cam then
                table.insert(filtered, cam)
            end
            local towersFolder = workspace:FindFirstChild("Towers")
            if towersFolder then
                table.insert(filtered, towersFolder)
            end
            params.FilterDescendantsInstances = filtered
            params.IgnoreWater = true
            local result = workspace:Raycast(root.Position + Vector3.new(0, 8, 0), Vector3.new(0, -1000, 0), params)
            if result then
                return result.Position.X, result.Position.Y + 5, result.Position.Z
            end
            return root.Position.X, root.Position.Y, root.Position.Z
        end

        local function placeStackTower(silent)
            if not stackSelectedTower or stackSelectedTower == "" then
                toast("Set a tower first", C.red)
                return false
            end
            if tick() - stackLastPlace < STACK_PLACE_INTERVAL then
                return false
            end
            local x, y, z = getStackWorldPosition()
            if not x then
                if not silent then
                    toast("No placement point", C.red)
                end
                return false
            end
            stackLastPlace = tick()
            local ok = invokeTroops("Place", {
                Rotation = CFrame.new(),
                Position = Vector3.new(x, y, z),
            }, stackSelectedTower)
            if not ok and not silent and tick() - stackLastFailToast > 1 then
                stackLastFailToast = tick()
                toast("Stack place failed", C.red)
            end
            return ok
        end

        local stackF = Instance.new("Frame", eScroll)
        stackF.Size = UDim2.new(1, 0, 0, isMobile and 76 or 82)
        stackF.BackgroundColor3 = C.card
        stackF.BorderSizePixel = 0
        stackF.LayoutOrder = 92
        stackF.ZIndex = 22
        Instance.new("UICorner", stackF).CornerRadius = UDim.new(0, M.cr)
        local stackS = Instance.new("UIStroke", stackF)
        stackS.Color = C.border
        stackS.Thickness = 1
        stackS.Transparency = 0.5

        local stackLabel = Instance.new("TextLabel", stackF)
        stackLabel.Size = UDim2.new(1, -16, 0, 14)
        stackLabel.Position = UDim2.new(0, 10, 0, 6)
        stackLabel.BackgroundTransparency = 1
        stackLabel.Text = "Tower Stack"
        stackLabel.TextColor3 = C.text
        stackLabel.TextSize = isMobile and 11 or 13
        stackLabel.Font = Enum.Font.GothamBold
        stackLabel.TextXAlignment = Enum.TextXAlignment.Left
        stackLabel.ZIndex = 23

        local stackInfo = Instance.new("TextLabel", stackF)
        stackInfo.Size = UDim2.new(1, -16, 0, 12)
        stackInfo.Position = UDim2.new(0, 10, 0, 21)
        stackInfo.BackgroundTransparency = 1
        stackInfo.Text = isMobile and "Set tower, hold map to stack under you" or "Set tower, hold Q to stack under you"
        stackInfo.TextColor3 = C.textDim
        stackInfo.TextSize = isMobile and 8 or 9
        stackInfo.Font = Enum.Font.Gotham
        stackInfo.TextXAlignment = Enum.TextXAlignment.Left
        stackInfo.ZIndex = 23

        local stackRow = Instance.new("Frame", stackF)
        stackRow.Size = UDim2.new(1, -16, 0, 28)
        stackRow.Position = UDim2.new(0, 8, 1, -36)
        stackRow.BackgroundTransparency = 1
        stackRow.ZIndex = 23

        local stackInputBg = Instance.new("Frame", stackRow)
        stackInputBg.Size = UDim2.new(1, -68, 0, 28)
        stackInputBg.BackgroundColor3 = C.surface
        stackInputBg.BorderSizePixel = 0
        stackInputBg.ZIndex = 23
        Instance.new("UICorner", stackInputBg).CornerRadius = UDim.new(0, 7)
        local stackInpS = Instance.new("UIStroke", stackInputBg)
        stackInpS.Color = C.border
        stackInpS.Thickness = 1
        stackInpS.Transparency = 0.5

        local stackInp = Instance.new("TextBox", stackInputBg)
        stackInp.Size = UDim2.new(1, -10, 1, 0)
        stackInp.Position = UDim2.new(0, 5, 0, 0)
        stackInp.BackgroundTransparency = 1
        stackInp.PlaceholderText = "e.g. Golden Scout"
        stackInp.PlaceholderColor3 = C.textDim
        stackInp.Text = ""
        stackInp.TextColor3 = C.text
        stackInp.TextSize = isMobile and 10 or 12
        stackInp.Font = Enum.Font.Gotham
        stackInp.TextXAlignment = Enum.TextXAlignment.Left
        stackInp.ClearTextOnFocus = false
        stackInp.ZIndex = 24
        if stackSelectedTower then
            stackInp.Text = stackSelectedTower
            stackInfo.Text = (isMobile and "Hold map under you: " or "Hold Q under you: ") .. stackSelectedTower
        end

        local stackBtn = Instance.new("TextButton", stackRow)
        stackBtn.Size = UDim2.new(0, 60, 0, 28)
        stackBtn.Position = UDim2.new(1, -60, 0, 0)
        stackBtn.BackgroundColor3 = C.accent
        stackBtn.BorderSizePixel = 0
        stackBtn.Text = "Set"
        stackBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        stackBtn.TextSize = isMobile and 10 or 12
        stackBtn.Font = Enum.Font.GothamBold
        stackBtn.ZIndex = 23
        Instance.new("UICorner", stackBtn).CornerRadius = UDim.new(0, 7)
        stackBtn.MouseEnter:Connect(function()
            TweenService:Create(stackBtn, TweenInfo.new(0.1), { BackgroundColor3 = C.accentLit }):Play()
        end)
        stackBtn.MouseLeave:Connect(function()
            TweenService:Create(stackBtn, TweenInfo.new(0.1), { BackgroundColor3 = C.accent }):Play()
        end)

        local function setStackTower()
            local towerName = capitalizeFirst(stackInp.Text)
            if not towerName or towerName == "" then
                toast("Enter a tower name", C.red)
                return
            end
            stackSelectedTower = towerName
            stackInp.Text = towerName
            setSetting("towerStackName", towerName)
            stackInfo.Text = (isMobile and "Hold map under you: " or "Hold Q under you: ") .. towerName
            toast("Tower stack: " .. towerName, C.green)
        end

        stackBtn.MouseButton1Click:Connect(setStackTower)
        stackInp.FocusLost:Connect(function(enterPressed)
            if enterPressed then
                setStackTower()
            end
        end)

        local function startStackHold(input, pos)
            if stackHolding then
                return
            end
            if not stackSelectedTower or stackSelectedTower == "" then
                toast("Set a tower first", C.red)
                return
            end
            if pos and stackInputBlocked(pos) then
                return
            end
            stackHolding = true
            stackHoldTouch = input and input.UserInputType == Enum.UserInputType.Touch and input or nil
            stackTouch = input
            stackTouchStart = tick()
            stackTouchPos = pos
            placeStackTower(false)
        end

        local function stopStackHold(input)
            if input and stackHoldTouch and input ~= stackHoldTouch then
                return
            end
            stackHolding = false
            stackHoldTouch = nil
            stackTouch = nil
            stackTouchPos = nil
        end

        connectUI(UserInputService.InputBegan, function(input, processed)
            if not gui.Parent then
                return
            end
            if processed then
                return
            end
            if input.KeyCode == Enum.KeyCode.Q and stackSelectedTower then
                local mousePos = UserInputService:GetMouseLocation()
                if stackInputBlocked(mousePos) then
                    return
                end
                startStackHold(input, mousePos)
            elseif input.UserInputType == Enum.UserInputType.Touch and stackSelectedTower then
                if stackInputBlocked(input.Position) then
                    return
                end
                startStackHold(input, input.Position)
            end
        end)

        connectUI(UserInputService.InputChanged, function(input)
            if input == stackTouch then
                stackTouchPos = input.Position
            end
        end)

        connectUI(UserInputService.InputEnded, function(input)
            if input.KeyCode == Enum.KeyCode.Q then
                stopStackHold(input)
            elseif input == stackTouch or input == stackHoldTouch then
                stopStackHold(input)
            end
        end)

        task.spawn(function()
            while gui.Parent do
                if stackHolding and stackSelectedTower then
                    placeStackTower(true)
                end
                task.wait(0.02)
            end
        end)

        eSectionHdr("Settings", 95)

        local resetF = Instance.new("Frame", eScroll)
        resetF.Size = UDim2.new(1, 0, 0, isMobile and 92 or 100)
        resetF.BackgroundColor3 = C.card
        resetF.BorderSizePixel = 0
        resetF.LayoutOrder = 96
        resetF.ZIndex = 22
        Instance.new("UICorner", resetF).CornerRadius = UDim.new(0, M.cr)
        local resetS = Instance.new("UIStroke", resetF)
        resetS.Color = C.red
        resetS.Thickness = 1
        resetS.Transparency = 0.62

        local resetLabel = Instance.new("TextLabel", resetF)
        resetLabel.Size = UDim2.new(1, -20, 0, 16)
        resetLabel.Position = UDim2.new(0, 10, 0, 7)
        resetLabel.BackgroundTransparency = 1
        resetLabel.Text = "Reset Settings"
        resetLabel.TextColor3 = C.text
        resetLabel.TextSize = isMobile and 11 or 13
        resetLabel.Font = Enum.Font.GothamBold
        resetLabel.TextXAlignment = Enum.TextXAlignment.Left
        resetLabel.ZIndex = 23

        local resetInfo = Instance.new("TextLabel", resetF)
        resetInfo.Size = UDim2.new(1, -20, 0, isMobile and 30 or 34)
        resetInfo.Position = UDim2.new(0, 10, 0, 25)
        resetInfo.BackgroundTransparency = 1
        resetInfo.Text = "Clears every saved option, personal strat, favorite, vote, webhook, and cached choice."
        resetInfo.TextColor3 = C.textDim
        resetInfo.TextSize = isMobile and 8 or 9
        resetInfo.Font = Enum.Font.Gotham
        resetInfo.TextWrapped = true
        resetInfo.TextXAlignment = Enum.TextXAlignment.Left
        resetInfo.TextYAlignment = Enum.TextYAlignment.Top
        resetInfo.ZIndex = 23

        local resetBtn = Instance.new("TextButton", resetF)
        resetBtn.Size = UDim2.new(1, -16, 0, 28)
        resetBtn.Position = UDim2.new(0, 8, 1, -36)
        resetBtn.BackgroundColor3 = C.red
        resetBtn.BorderSizePixel = 0
        resetBtn.Text = "Reset Settings"
        resetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        resetBtn.TextSize = isMobile and 10 or 12
        resetBtn.Font = Enum.Font.GothamBold
        resetBtn.ZIndex = 23
        Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 7)
        resetBtn.MouseButton1Click:Connect(function()
            showConfirmPrompt(
                "Reset Settings?",
                "This wipes every Zephyr TDS setting and returns the menu to a fresh execute state. This cannot be undone.",
                "Reset",
                function()
                    local saved = resetAllTdsSettings()
                    local oldGui = gui
                    task.defer(function()
                        if oldGui and oldGui.Parent then
                            oldGui:Destroy()
                        end
                        task.wait()
                        if runtimeAlive then
                            createUI()
                            notify(saved and "Settings reset" or "Settings reset for this session")
                        end
                    end)
                end
            )
        end)

        -- Strategy editor
        local editorF = Instance.new("Frame", eScroll)
        editorF.Size = UDim2.new(1, 0, 0, isMobile and 300 or 330)
        editorF.BackgroundColor3 = C.card
        editorF.BorderSizePixel = 0
        editorF.LayoutOrder = 90
        editorF.ZIndex = 22
        Instance.new("UICorner", editorF).CornerRadius = UDim.new(0, M.cr)
        local editorStroke = Instance.new("UIStroke", editorF)
        editorStroke.Color = C.border
        editorStroke.Thickness = 1
        editorStroke.Transparency = 0.5

        local editorTitle = Instance.new("TextLabel", editorF)
        editorTitle.Size = UDim2.new(1, -20, 0, 16)
        editorTitle.Position = UDim2.new(0, 10, 0, 7)
        editorTitle.BackgroundTransparency = 1
        editorTitle.Text = "Personal Strats"
        editorTitle.TextColor3 = C.text
        editorTitle.TextSize = isMobile and 11 or 13
        editorTitle.Font = Enum.Font.GothamBold
        editorTitle.TextXAlignment = Enum.TextXAlignment.Left
        editorTitle.ZIndex = 23

        local editorSub = Instance.new("TextLabel", editorF)
        editorSub.Size = UDim2.new(1, -20, 0, 24)
        editorSub.Position = UDim2.new(0, 10, 0, 24)
        editorSub.BackgroundTransparency = 1
        editorSub.Text = "Save private strats locally. Paste the strat text; towers are detected automatically."
        editorSub.TextColor3 = C.textDim
        editorSub.TextSize = isMobile and 8 or 9
        editorSub.Font = Enum.Font.Gotham
        editorSub.TextWrapped = true
        editorSub.TextXAlignment = Enum.TextXAlignment.Left
        editorSub.ZIndex = 23

        local function editorInput(parent, placeholder, x, y, w, h)
            local box = Instance.new("TextBox", parent)
            box.Size = UDim2.new(w, -4, 0, h)
            box.Position = UDim2.new(x, 2, 0, y)
            box.BackgroundColor3 = C.surface
            box.BorderSizePixel = 0
            box.PlaceholderText = placeholder
            box.PlaceholderColor3 = C.textDim
            box.Text = ""
            box.TextColor3 = C.text
            box.TextSize = isMobile and 8 or 10
            box.Font = Enum.Font.Gotham
            box.TextXAlignment = Enum.TextXAlignment.Left
            box.ClearTextOnFocus = false
            box.ZIndex = 23
            Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
            local s = Instance.new("UIStroke", box)
            s.Color = C.border
            s.Thickness = 1
            s.Transparency = 0.6
            local p = Instance.new("UIPadding", box)
            p.PaddingLeft = UDim.new(0, 7)
            p.PaddingRight = UDim.new(0, 7)
            return box
        end

        local editName = editorInput(editorF, "Name", 0, 54, 0.5, 24)
        local editMapDrop = makeSettingsDropdown(editorF, TDS_MAP_OPTIONS, "", 0.5, 0.5, nil, 5, 54, "Map")
        local editModeDrop = makeSettingsDropdown(editorF, TDS_MODE_OPTIONS, "", 0, 0.5, nil, 5, 82, "Mode")
        local editNote = editorInput(editorF, "Note", 0.5, 82, 0.5, 24)
        local editCph = editorInput(editorF, "Coins/hr", 0, 110, 1 / 3, 24)
        local editGph = editorInput(editorF, "Gems/hr", 1 / 3, 110, 1 / 3, 24)
        local editXp = editorInput(editorF, "XP/run", 2 / 3, 110, 1 / 3, 24)
        local editTime = editorInput(editorF, "Time minutes, ex: 9.5", 0, 138, 0.5, 24)
        local autoLoadoutHint = Instance.new("TextLabel", editorF)
        autoLoadoutHint.Size = UDim2.new(0.5, -4, 0, 24)
        autoLoadoutHint.Position = UDim2.new(0.5, 2, 0, 138)
        autoLoadoutHint.BackgroundColor3 = C.surface
        autoLoadoutHint.BorderSizePixel = 0
        autoLoadoutHint.Text = "Loadout auto-detects"
        autoLoadoutHint.TextColor3 = C.textDim
        autoLoadoutHint.TextSize = isMobile and 8 or 10
        autoLoadoutHint.Font = Enum.Font.Gotham
        autoLoadoutHint.TextXAlignment = Enum.TextXAlignment.Left
        autoLoadoutHint.ZIndex = 23
        autoLoadoutHint.TextTruncate = Enum.TextTruncate.AtEnd
        Instance.new("UICorner", autoLoadoutHint).CornerRadius = UDim.new(0, 6)
        local autoHintStroke = Instance.new("UIStroke", autoLoadoutHint)
        autoHintStroke.Color = C.border
        autoHintStroke.Thickness = 1
        autoHintStroke.Transparency = 0.6
        local autoHintPad = Instance.new("UIPadding", autoLoadoutHint)
        autoHintPad.PaddingLeft = UDim.new(0, 7)
        autoHintPad.PaddingRight = UDim.new(0, 7)
        local editContent = editorInput(editorF, "Paste strat text here", 0, 166, 1, isMobile and 82 or 108)
        editContent.TextWrapped = true
        editContent.TextYAlignment = Enum.TextYAlignment.Top
        pcall(function()
            editContent.MultiLine = true
        end)
        editContent.FocusLost:Connect(function()
            local loadout = detectTowersFromContent(editContent.Text)
            autoLoadoutHint.Text = (
                #loadout > 0 and ("Detected: " .. table.concat(loadout, ", ")) or "Loadout auto-detects"
            )
        end)

        local editorIndex = nil
        local function clearCustomEditor()
            editorIndex = nil
            editorTitle.Text = "Personal Strats"
            for _, box in ipairs({ editName, editCph, editGph, editXp, editTime, editNote, editContent }) do
                box.Text = ""
            end
            editMapDrop:Set("", true)
            editModeDrop:Set("", true)
            autoLoadoutHint.Text = "Loadout auto-detects"
        end

        loadCustomEditor = function(index)
            local saved = ensureSettingsTable("customStrats")[index]
            if type(saved) ~= "table" then
                return
            end
            editorIndex = index
            editorTitle.Text = "Editing: " .. tostring(saved.name or "Saved Strat")
            editName.Text = tostring(saved.name or "")
            editMapDrop:Set(normalizeAutoRejoinMap(saved.map or "Crossroads"), true)
            editModeDrop:Set(normalizeAutoRejoinMode(saved.mode or saved.launchDifficulty or "Easy"), true)
            editCph.Text = tostring(saved.cph or "")
            editGph.Text = tostring(saved.gph or "")
            editXp.Text = tostring(saved.xp or "")
            editTime.Text = tostring(saved.time or saved.timeMinutes or "")
            editNote.Text = tostring(saved.note or "")
            editContent.Text = tostring(saved.stratContent or "")
            local loadout = detectTowersFromContent(editContent.Text)
            autoLoadoutHint.Text = (
                #loadout > 0 and ("Detected: " .. table.concat(loadout, ", ")) or "Loadout auto-detects"
            )
            toast("Loaded personal strat for editing", C.green)
        end

        local function saveCustomFromEditor(forceNew)
            local content = trimText(editContent.Text)
            if content == "" then
                toast("Paste strat text first", C.red)
                return
            end
            local name = trimText(editName.Text)
            if name == "" then
                name = "Saved Strat"
            end
            local detectedLoadout = detectTowersFromContent(content)
            autoLoadoutHint.Text = (
                #detectedLoadout > 0 and ("Detected: " .. table.concat(detectedLoadout, ", "))
                or "No towers detected yet"
            )
            local payload = {
                id = forceNew and tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999)) or nil,
                name = name,
                map = trimText(editMapDrop:Get()) ~= "" and normalizeAutoRejoinMap(editMapDrop:Get()) or "Crossroads",
                mode = trimText(editModeDrop:Get()) ~= "" and normalizeAutoRejoinMode(editModeDrop:Get()) or "Easy",
                loadout = "",
                cph = tonumber(editCph.Text) or 0,
                gph = tonumber(editGph.Text) or 0,
                xp = tonumber(editXp.Text) or 0,
                time = tonumber(editTime.Text) or 0,
                note = trimText(editNote.Text),
                stratContent = content,
            }
            local customs = ensureSettingsTable("customStrats")
            if not forceNew and editorIndex and type(customs[editorIndex]) == "table" then
                payload.id = customs[editorIndex].id or tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
                customs[editorIndex] = payload
                toast("Personal strat updated", C.green)
            else
                payload.id = payload.id or tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
                table.insert(customs, payload)
                editorIndex = #customs
                toast("Personal strat saved", C.green)
            end
            saveSettingsSoon()
            saveSettingsNow()
            if type(rebuildCustomStrats) == "function" then
                rebuildCustomStrats()
            end
        end

        local function editorButton(text, x, w, color, callback)
            local b = Instance.new("TextButton", editorF)
            b.Size = UDim2.new(w, -4, 0, isMobile and 24 or 28)
            b.Position = UDim2.new(x, 2, 1, isMobile and -32 or -38)
            b.BackgroundColor3 = color
            b.BorderSizePixel = 0
            b.Text = text
            b.TextColor3 = Color3.fromRGB(255, 255, 255)
            b.TextSize = isMobile and 9 or 11
            b.Font = Enum.Font.GothamBold
            b.ZIndex = 23
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
            b.MouseButton1Click:Connect(callback)
            return b
        end
        editorButton("Save New", 0, 1 / 3, C.green, function()
            saveCustomFromEditor(true)
        end)
        editorButton("Update", 1 / 3, 1 / 3, C.accent, function()
            saveCustomFromEditor(false)
        end)
        editorButton("Clear", 2 / 3, 1 / 3, C.surfaceAlt, clearCustomEditor)

        local srBtn = Instance.new("TextButton", eScroll)
        srBtn.Size = UDim2.new(1, 0, 0, M.btn)
        srBtn.BackgroundColor3 = C.purple
        srBtn.BorderSizePixel = 0
        srBtn.Text = "Open Strat Recorder"
        srBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        srBtn.TextSize = isMobile and 11 or 14
        srBtn.Font = Enum.Font.GothamBold
        srBtn.LayoutOrder = 93
        srBtn.ZIndex = 22
        Instance.new("UICorner", srBtn).CornerRadius = UDim.new(0, M.cr)
        local srS = Instance.new("UIStroke", srBtn)
        srS.Color = C.purpleLit
        srS.Thickness = 1
        srS.Transparency = 0.5
        srBtn.MouseEnter:Connect(function()
            TweenService:Create(srBtn, TweenInfo.new(0.12), { BackgroundColor3 = C.purpleLit }):Play()
        end)
        srBtn.MouseLeave:Connect(function()
            TweenService:Create(srBtn, TweenInfo.new(0.12), { BackgroundColor3 = C.purple }):Play()
        end)

        local srUsed = false
        srBtn.MouseButton1Click:Connect(function()
            if srUsed then
                return
            end
            srUsed = true
            srBtn.Text = "Opened"
            task.spawn(function()
                local ok, err = runRemoteScript(
                    "https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/Games/tds-recorder.lua"
                )
                if not ok then
                    srUsed = false
                    srBtn.Text = "Open Strat Recorder"
                    toast("Recorder unavailable", C.red)
                    warn("[Zephyr] Strat recorder failed:", tostring(err))
                end
            end)
        end)

        local function openExtras()
            extrasOpen = true
            extras.Visible = true
            syncExtrasCanvas()
            extras.Position = UDim2.new(1, 0, 0, M.hdr + 2)
            TweenService:Create(extras, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                Position = UDim2.new(0, 0, 0, M.hdr + 2),
            }):Play()
        end
        local function closeExtras()
            extrasOpen = false
            local tw =
                TweenService:Create(extras, TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
                    Position = UDim2.new(1, 0, 0, M.hdr + 2),
                })
            tw:Play()
            tw.Completed:Connect(function()
                if not extrasOpen then
                    extras.Visible = false
                end
            end)
        end
        miscBtn.MouseButton1Click:Connect(function()
            if extrasOpen then
                closeExtras()
            else
                openExtras()
            end
        end)
        backBtn.MouseButton1Click:Connect(function()
            closeExtras()
        end)
    end)
    if not miscPanelOk then
        extrasOpen = false
        warn("[Zephyr] Misc panel failed; continuing strategy UI:", tostring(miscPanelErr))
        miscBtn.MouseButton1Click:Connect(function()
            toast("Misc failed: " .. tostring(miscPanelErr):sub(1, 80), C.red)
        end)
    end

    local function makeSectionHdr(diff, ord)
        local f = Instance.new("Frame", content)
        f.Size = UDim2.new(1, 0, 0, 22)
        f.BackgroundTransparency = 1
        f.LayoutOrder = ord * 1000
        local bar = Instance.new("Frame", f)
        bar.Size = UDim2.new(0, 3, 0, 14)
        bar.Position = UDim2.new(0, 0, 0.5, -7)
        bar.BackgroundColor3 = difficultyColors[diff] or C.blue
        bar.BorderSizePixel = 0
        Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 2)
        local lbl = Instance.new("TextLabel", f)
        lbl.Size = UDim2.new(1, -12, 1, 0)
        lbl.Position = UDim2.new(0, 12, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = string.upper(difficultyLabels[diff] or diff) .. " STRATEGIES"
        lbl.TextColor3 = C.textDim
        lbl.TextSize = M.sec
        lbl.Font = Enum.Font.GothamBold
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        table.insert(sectionHeaders, { frame = f, section = diff })
    end

    local function makePill(parent, text, bgColor, ord)
        local pill = Instance.new("Frame", parent)
        pill.Size = UDim2.new(0, 0, 0, M.pill)
        pill.AutomaticSize = Enum.AutomaticSize.X
        pill.BackgroundColor3 = bgColor
        pill.BackgroundTransparency = 0.85
        pill.LayoutOrder = ord
        Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 5)
        local pp = Instance.new("UIPadding", pill)
        pp.PaddingLeft = UDim.new(0, 5)
        pp.PaddingRight = UDim.new(0, 5)
        local tl = Instance.new("TextLabel", pill)
        tl.Size = UDim2.new(0, 0, 1, 0)
        tl.AutomaticSize = Enum.AutomaticSize.X
        tl.BackgroundTransparency = 1
        tl.Text = text
        tl.TextColor3 = C.textSec
        tl.TextSize = M.stat
        tl.Font = Enum.Font.GothamMedium
    end

    local tooltip = Instance.new("TextLabel", main)
    tooltip.Size = UDim2.new(0, 0, 0, isMobile and 18 or 22)
    tooltip.AutomaticSize = Enum.AutomaticSize.X
    tooltip.BackgroundColor3 = Color3.fromRGB(10, 12, 22)
    tooltip.BorderSizePixel = 0
    tooltip.TextColor3 = C.text
    tooltip.TextSize = isMobile and 8 or 10
    tooltip.Font = Enum.Font.GothamBold
    tooltip.Visible = false
    tooltip.ZIndex = 95
    Instance.new("UICorner", tooltip).CornerRadius = UDim.new(0, 6)
    local tooltipPad = Instance.new("UIPadding", tooltip)
    tooltipPad.PaddingLeft = UDim.new(0, 8)
    tooltipPad.PaddingRight = UDim.new(0, 8)
    local tooltipStroke = Instance.new("UIStroke", tooltip)
    tooltipStroke.Color = C.border
    tooltipStroke.Thickness = 1
    tooltipStroke.Transparency = 0.25

    local function attachTooltip(button, text)
        if isMobile or not text or text == "" then
            return
        end
        button.MouseEnter:Connect(function()
            tooltip.Text = text
            local abs = button.AbsolutePosition
            local mainAbs = main.AbsolutePosition
            tooltip.Position = UDim2.new(0, math.max(6, abs.X - mainAbs.X), 0, math.max(6, abs.Y - mainAbs.Y - 26))
            tooltip.Visible = true
        end)
        button.MouseLeave:Connect(function()
            tooltip.Visible = false
        end)
    end

    local function setDrawnIconColor(button, color)
        local holder = button and button:FindFirstChild("Icon")
        if not holder then
            return
        end
        for _, obj in ipairs(holder:GetDescendants()) do
            if obj.Name == "IconPart" then
                if obj:IsA("Frame") then
                    obj.BackgroundColor3 = color
                elseif obj:IsA("TextLabel") then
                    obj.TextColor3 = color
                elseif obj:IsA("UIStroke") then
                    obj.Color = color
                end
            end
        end
    end

    local function drawInlineIcon(button, iconName, color)
        local holder = Instance.new("Frame", button)
        holder.Name = "Icon"
        holder.Size = UDim2.new(0, isMobile and 14 or 16, 0, isMobile and 14 or 16)
        holder.Position = UDim2.new(0.5, 0, 0.5, 0)
        holder.AnchorPoint = Vector2.new(0.5, 0.5)
        holder.BackgroundTransparency = 1
        holder.ZIndex = 7
        local scale = isMobile and 0.88 or 1
        local function part(x, y, w, h, r, rot)
            local f = Instance.new("Frame", holder)
            f.Name = "IconPart"
            f.Size = UDim2.new(0, w * scale, 0, h * scale)
            f.Position = UDim2.new(0, x * scale, 0, y * scale)
            f.BackgroundColor3 = color
            f.BorderSizePixel = 0
            f.ZIndex = 8
            f.Rotation = rot or 0
            if r then
                Instance.new("UICorner", f).CornerRadius = UDim.new(0, r * scale)
            end
            return f
        end
        local function label(text, size, y)
            local t = Instance.new("TextLabel", holder)
            t.Name = "IconPart"
            t.Size = UDim2.new(1, 0, 1, 0)
            t.Position = UDim2.new(0, 0, 0, y or 0)
            t.BackgroundTransparency = 1
            t.Text = text
            t.TextColor3 = color
            t.TextSize = size or (isMobile and 15 or 18)
            t.Font = Enum.Font.GothamBold
            t.TextXAlignment = Enum.TextXAlignment.Center
            t.TextYAlignment = Enum.TextYAlignment.Center
            t.ZIndex = 8
            return t
        end

        if iconName == "star" then
            label("*", isMobile and 18 or 22, -1)
        elseif iconName == "thumbsUp" then
            part(2, 9, 4, 5, 1)
            part(6, 7, 7, 6, 2)
            part(8, 4, 4, 5, 2, -25)
            part(11, 8, 3, 2, 1)
        elseif iconName == "thumbsDown" then
            part(2, 2, 4, 5, 1)
            part(6, 3, 7, 6, 2)
            part(8, 8, 4, 5, 2, 25)
            part(11, 6, 3, 2, 1)
        elseif iconName == "flag" then
            part(3, 2, 2, 13, 1)
            part(5, 2, 8, 6, 1)
            part(5, 7, 6, 2, 1)
        elseif iconName == "pencil" then
            part(3, 8, 10, 3, 1, -35)
            part(11, 4, 3, 3, 1, -35)
            part(2, 11, 3, 3, 1, -35)
        elseif iconName == "trash" then
            part(4, 3, 8, 2, 1)
            part(6, 1, 4, 2, 1)
            local body = Instance.new("Frame", holder)
            body.Name = "IconPart"
            body.Size = UDim2.new(0, 8 * scale, 0, 9 * scale)
            body.Position = UDim2.new(0, 4 * scale, 0, 6 * scale)
            body.BackgroundTransparency = 1
            body.BorderSizePixel = 0
            body.ZIndex = 8
            local stroke = Instance.new("UIStroke", body)
            stroke.Name = "IconPart"
            stroke.Color = color
            stroke.Thickness = math.max(1, 1.5 * scale)
            part(7, 8, 1, 5, 1)
            part(10, 8, 1, 5, 1)
        elseif iconName == "play" then
            label(">", isMobile and 14 or 17, -1)
        else
            label(tostring(iconName or "?"), isMobile and 11 or 13, 0)
        end
        return holder
    end

    local function makeIconButton(parent, iconName, fallbackText, width, color, order, tooltipText, callback)
        local b = Instance.new("TextButton", parent)
        b.Size = UDim2.new(0, width, 1, 0)
        b.BackgroundColor3 = color
        b.BorderSizePixel = 0
        b.TextColor3 = C.textSec
        b.TextSize = isMobile and 8 or 10
        b.Font = Enum.Font.GothamBold
        b.LayoutOrder = order
        b.ZIndex = 6
        b.AutoButtonColor = false
        b:SetAttribute("BaseColor", color)
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
        if iconName then
            b.Text = ""
            b:SetAttribute("HasIcon", true)
            drawInlineIcon(b, iconName, Color3.fromRGB(255, 255, 255))
        else
            local fallbackWidth = math.max(
                width,
                math.min(
                    isMobile and 54 or 72,
                    (#tostring(fallbackText or "") * (isMobile and 5 or 6)) + (isMobile and 12 or 16)
                )
            )
            b.Size = UDim2.new(0, fallbackWidth, 1, 0)
            b.Text = fallbackText
            b:SetAttribute("HasIcon", false)
        end
        attachTooltip(b, tooltipText or fallbackText)
        b.MouseEnter:Connect(function()
            local base = b:GetAttribute("BaseColor") or color
            TweenService:Create(b, TweenInfo.new(0.1), {
                BackgroundColor3 = Color3.fromRGB(
                    math.min(base.R * 255 + 14, 255),
                    math.min(base.G * 255 + 14, 255),
                    math.min(base.B * 255 + 14, 255)
                ),
            }):Play()
        end)
        b.MouseLeave:Connect(function()
            TweenService:Create(b, TweenInfo.new(0.1), { BackgroundColor3 = b:GetAttribute("BaseColor") or color })
                :Play()
        end)
        b.MouseButton1Click:Connect(callback)
        return b
    end

    local function showNotice(titleText, bodyText)
        local overlay = Instance.new("Frame", main)
        overlay.Size = UDim2.new(1, 0, 1, 0)
        overlay.Position = UDim2.new(0, 0, 0, 0)
        overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        overlay.BackgroundTransparency = 0.35
        overlay.BorderSizePixel = 0
        overlay.ZIndex = 80
        local box = Instance.new("Frame", overlay)
        box.Size = UDim2.new(0.84, 0, 0, isMobile and 132 or 150)
        box.Position = UDim2.new(0.08, 0, 0.5, isMobile and -66 or -75)
        box.BackgroundColor3 = C.card
        box.BorderSizePixel = 0
        box.ZIndex = 81
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, M.cr)
        local s = Instance.new("UIStroke", box)
        s.Color = C.accent
        s.Thickness = 1
        s.Transparency = 0.25
        local title = Instance.new("TextLabel", box)
        title.Size = UDim2.new(1, -24, 0, 22)
        title.Position = UDim2.new(0, 12, 0, 10)
        title.BackgroundTransparency = 1
        title.Text = tostring(titleText or "Notice")
        title.TextColor3 = C.text
        title.TextSize = isMobile and 12 or 15
        title.Font = Enum.Font.GothamBold
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.ZIndex = 82
        local body = Instance.new("TextLabel", box)
        body.Size = UDim2.new(1, -24, 1, -72)
        body.Position = UDim2.new(0, 12, 0, 36)
        body.BackgroundTransparency = 1
        body.Text = tostring(bodyText or "")
        body.TextColor3 = C.textSec
        body.TextSize = isMobile and 9 or 11
        body.Font = Enum.Font.Gotham
        body.TextWrapped = true
        body.TextXAlignment = Enum.TextXAlignment.Left
        body.TextYAlignment = Enum.TextYAlignment.Top
        body.ZIndex = 82
        local ok = Instance.new("TextButton", box)
        ok.Size = UDim2.new(1, -24, 0, isMobile and 24 or 30)
        ok.Position = UDim2.new(0, 12, 1, isMobile and -34 or -42)
        ok.BackgroundColor3 = C.accent
        ok.BorderSizePixel = 0
        ok.Text = "Got it"
        ok.TextColor3 = Color3.fromRGB(255, 255, 255)
        ok.TextSize = isMobile and 10 or 12
        ok.Font = Enum.Font.GothamBold
        ok.ZIndex = 82
        Instance.new("UICorner", ok).CornerRadius = UDim.new(0, 7)
        ok.MouseButton1Click:Connect(function()
            overlay:Destroy()
        end)
    end

    local function showReportPrompt(macro, stratId)
        local overlay = Instance.new("Frame", main)
        overlay.Size = UDim2.new(1, 0, 1, 0)
        overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        overlay.BackgroundTransparency = 0.35
        overlay.BorderSizePixel = 0
        overlay.ZIndex = 80
        local box = Instance.new("Frame", overlay)
        box.Size = UDim2.new(0.9, 0, 0, isMobile and 210 or 240)
        box.Position = UDim2.new(0.05, 0, 0.5, isMobile and -105 or -120)
        box.BackgroundColor3 = C.card
        box.BorderSizePixel = 0
        box.ZIndex = 81
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, M.cr)
        local s = Instance.new("UIStroke", box)
        s.Color = C.red
        s.Thickness = 1
        s.Transparency = 0.25
        local title = Instance.new("TextLabel", box)
        title.Size = UDim2.new(1, -24, 0, 22)
        title.Position = UDim2.new(0, 12, 0, 10)
        title.BackgroundTransparency = 1
        title.Text = "Report Strat"
        title.TextColor3 = C.text
        title.TextSize = isMobile and 12 or 15
        title.Font = Enum.Font.GothamBold
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.ZIndex = 82
        local hint = Instance.new("TextLabel", box)
        hint.Size = UDim2.new(1, -24, 0, 34)
        hint.Position = UDim2.new(0, 12, 0, 34)
        hint.BackgroundTransparency = 1
        hint.Text = "Tell us what went wrong with this strat. This sends the report directly so staff can review it."
        hint.TextColor3 = C.textDim
        hint.TextSize = isMobile and 8 or 10
        hint.Font = Enum.Font.Gotham
        hint.TextWrapped = true
        hint.TextXAlignment = Enum.TextXAlignment.Left
        hint.ZIndex = 82
        local input = Instance.new("TextBox", box)
        input.Size = UDim2.new(1, -24, 0, isMobile and 82 or 104)
        input.Position = UDim2.new(0, 12, 0, 74)
        input.BackgroundColor3 = C.surface
        input.BorderSizePixel = 0
        input.PlaceholderText = "Example: It stops placing at wave 12, uses the wrong map, doesnt work"
        input.PlaceholderColor3 = C.textDim
        input.Text = ""
        input.TextWrapped = true
        input.TextColor3 = C.text
        input.TextSize = isMobile and 9 or 11
        input.Font = Enum.Font.Gotham
        input.TextXAlignment = Enum.TextXAlignment.Left
        input.TextYAlignment = Enum.TextYAlignment.Top
        input.ClearTextOnFocus = false
        input.ZIndex = 82
        pcall(function()
            input.MultiLine = true
        end)
        Instance.new("UICorner", input).CornerRadius = UDim.new(0, 7)
        local pad = Instance.new("UIPadding", input)
        pad.PaddingLeft = UDim.new(0, 8)
        pad.PaddingRight = UDim.new(0, 8)
        pad.PaddingTop = UDim.new(0, 6)
        local cancel = Instance.new("TextButton", box)
        cancel.Size = UDim2.new(0.5, -18, 0, isMobile and 24 or 30)
        cancel.Position = UDim2.new(0, 12, 1, isMobile and -34 or -42)
        cancel.BackgroundColor3 = C.surfaceAlt
        cancel.BorderSizePixel = 0
        cancel.Text = "Cancel"
        cancel.TextColor3 = C.textSec
        cancel.TextSize = isMobile and 10 or 12
        cancel.Font = Enum.Font.GothamBold
        cancel.ZIndex = 82
        Instance.new("UICorner", cancel).CornerRadius = UDim.new(0, 7)
        local submit = Instance.new("TextButton", box)
        submit.Size = UDim2.new(0.5, -18, 0, isMobile and 24 or 30)
        submit.Position = UDim2.new(0.5, 6, 1, isMobile and -34 or -42)
        submit.BackgroundColor3 = C.red
        submit.BorderSizePixel = 0
        submit.Text = "Send Report"
        submit.TextColor3 = Color3.fromRGB(255, 255, 255)
        submit.TextSize = isMobile and 10 or 12
        submit.Font = Enum.Font.GothamBold
        submit.ZIndex = 82
        Instance.new("UICorner", submit).CornerRadius = UDim.new(0, 7)
        cancel.MouseButton1Click:Connect(function()
            overlay:Destroy()
        end)
        submit.MouseButton1Click:Connect(function()
            local text = trimText(input.Text)
            if text == "" then
                toast("Write what is wrong first", C.red)
                return
            end
            addLocalStratReport(stratId, text)
            if macro.isCustom then
                toast("Personal report saved", C.green)
                overlay:Destroy()
                return
            end
            submit.Text = "Sending..."
            submit.Active = false
            task.spawn(function()
                local ok, result = submitCloudReport(stratId, text)
                if ok and type(result) == "table" and result.ok == true then
                    feedbackCache[stratId] = nil
                    queueCloudFeedback(stratId)
                    toast("Report sent", C.green)
                    overlay:Destroy()
                else
                    local report = "TDS strat report\nStrat: "
                        .. tostring(macro.name or "Unknown")
                        .. "\nMap: "
                        .. tostring(macro.map or "Unknown")
                        .. "\nFile: "
                        .. tostring(macro.sourceFileName or "N/A")
                        .. "\nID: "
                        .. tostring(stratId)
                        .. "\nIssue: "
                        .. text
                    if type(setclipboard) == "function" then
                        pcall(function()
                            setclipboard(report)
                        end)
                        toast("Cloud report failed. Copied backup report.", C.red)
                    else
                        toast("Cloud report failed. Report saved locally.", C.red)
                    end
                    submit.Text = "Send Report"
                    submit.Active = true
                end
            end)
        end)
    end

    local function makeCard(macro, ord)
        if type(macro) ~= "table" then
            macro = {}
        end
        macro.name = tostring(macro.name or "Unnamed Strategy")
        macro.subtitle = tostring(macro.subtitle or "")
        macro.color = macro.color or C.blue
        if type(macro.loadout) ~= "table" then
            macro.loadout = { "Unknown" }
        end
        macro.coins = tonumber(macro.coins) or tonumber(macro.cph) or 0
        macro.xp = tonumber(macro.xp) or 0
        macro.cph = tonumber(macro.cph) or 0
        macro.gph = tonumber(macro.gph) or 0
        macro.time = tonumber(macro.time) or 0
        local launchDifficulty = trimText(macro.launchDifficulty or "")
        local isHC = macro.rewardType == "Gems"
            or string.find(macro.name, "Hardcore") ~= nil
            or string.find(macro.name, "Voidcore") ~= nil
            or launchDifficulty == "Hardcore"
            or launchDifficulty == "Voidcore"
        local cph = (macro.time and macro.time > 0) and calcPerHour(macro.coins, macro.time) or (macro.cph or 0)
        local xph = (macro.time and macro.time > 0) and calcPerHour(macro.xp or 0, macro.time) or 0
        local timeText = macro.timeLabel or tostring(macro.time or 0) .. " min"
        local titH = isMobile and 22 or 28
        local stratId = getStratIdentity(macro)
        local canUseCloudFeedback = not macro.isCustom and stratId ~= "" and stratId ~= "strat:unknown"
        local feedback = macro.feedback or feedbackFromMetadata(macro.meta)
        if canUseCloudFeedback and feedbackCache[stratId] then
            feedback = feedbackCache[stratId]
        end
        local function ratingText()
            local likes = tonumber(feedback.likes) or 0
            local dislikes = tonumber(feedback.dislikes) or 0
            local total = likes + dislikes
            if total <= 0 then
                return "No ratings"
            end
            local ratio = tostring(math.floor((likes / total) * 100 + 0.5)) .. "%"
            return ratio .. " positive"
        end
        local function publicFeedbackHint(vote)
            if canUseCloudFeedback then
                return "Your vote was sent to Zephyr feedback. Public ratings update automatically after the menu refreshes."
            end
            return "Your vote was saved on your device for this personal strat."
        end

        local card = Instance.new("TextButton", content)
        local hasStratContent = type(macro.stratContent) == "string" and macro.stratContent:match("%S") ~= nil
        local hasStratUrl = type(macro.stratUrl) == "string" and macro.stratUrl:match("^%s*https?://") ~= nil
        local hasRunner = hasStratContent or hasStratUrl or type(macro.script) == "string"
        local cachedStratContent = hasStratContent and macro.stratContent or nil
        local function applyStratPrefix(text)
            if type(macro.stratPrefix) == "string" and macro.stratPrefix:match("%S") then
                return macro.stratPrefix .. "\n" .. tostring(text or "")
            end
            return text
        end
        local function getStratText()
            if type(cachedStratContent) == "string" and cachedStratContent:match("%S") then
                return true, cachedStratContent
            end
            if hasStratUrl then
                local fetchOk, fetched = pcall(function()
                    return game:HttpGet(macro.stratUrl)
                end)
                if fetchOk and type(fetched) == "string" and fetched:match("%S") then
                    fetched = applyStratPrefix(fetched)
                    cachedStratContent = fetched
                    return true, fetched
                end
                return false, fetched
            end
            return false, "No strat content"
        end
        card.Name = macro.name .. ord
        card.Size = UDim2.new(1, 0, 0, M.cardH)
        card.BackgroundColor3 = C.card
        card.BorderSizePixel = 0
        card.AutoButtonColor = false
        card.Text = ""
        card.LayoutOrder = ord
        card.ClipsDescendants = true
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, M.cr)
        local cStroke = Instance.new("UIStroke", card)
        cStroke.Color = C.border
        cStroke.Thickness = 1
        cStroke.Transparency = 0.4
        local accentBar = Instance.new("Frame", card)
        accentBar.Size = UDim2.new(0, 3, 1, -10)
        accentBar.Position = UDim2.new(0, 4, 0, 5)
        accentBar.BackgroundColor3 = macro.color
        accentBar.BorderSizePixel = 0
        Instance.new("UICorner", accentBar).CornerRadius = UDim.new(0, 2)

        local tY = isMobile and 5 or 8
        local tit = Instance.new("TextLabel", card)
        tit.Size = UDim2.new(1, -(isMobile and 112 or 160), 0, titH)
        tit.Position = UDim2.new(0, 14, 0, tY)
        tit.BackgroundTransparency = 1
        tit.Text = macro.name
        tit.TextColor3 = C.text
        tit.TextSize = M.cTitle
        tit.Font = Enum.Font.GothamBold
        tit.TextXAlignment = Enum.TextXAlignment.Left
        tit.TextWrapped = true

        local ratingL = Instance.new("TextLabel", card)
        ratingL.Size = UDim2.new(0, isMobile and 74 or 104, 0, 16)
        ratingL.Position = UDim2.new(1, -(isMobile and 84 or 116), 0, tY + 1)
        ratingL.BackgroundTransparency = 1
        ratingL.Text = ratingText()
        ratingL.TextColor3 = C.textSec
        ratingL.TextSize = isMobile and 7 or 10
        ratingL.Font = Enum.Font.GothamBold
        ratingL.TextXAlignment = Enum.TextXAlignment.Right
        ratingL.TextTruncate = Enum.TextTruncate.AtEnd

        local sY = tY + titH + 1
        local subTxt = macro.subtitle
        if macro.map and not macro.isCommunity then
            subTxt = subTxt .. "  |  " .. macro.map
        end
        if macro.dateSummary and macro.dateSummary ~= "" then
            subTxt = subTxt .. "  |  " .. macro.dateSummary
        end
        local sub2 = Instance.new("TextLabel", card)
        sub2.Size = UDim2.new(1, -20, 0, 14)
        sub2.Position = UDim2.new(0, 14, 0, sY)
        sub2.BackgroundTransparency = 1
        sub2.Text = subTxt
        sub2.TextColor3 = C.textDim
        sub2.TextSize = M.cSub
        sub2.Font = Enum.Font.Gotham
        sub2.TextXAlignment = Enum.TextXAlignment.Left
        sub2.TextTruncate = Enum.TextTruncate.AtEnd

        local stY2 = sY + 14 + 3
        local stF2 = Instance.new("Frame", card)
        stF2.Name = "Stats"
        stF2.Size = UDim2.new(1, -20, 0, M.pill)
        stF2.Position = UDim2.new(0, 14, 0, stY2)
        stF2.BackgroundTransparency = 1
        stF2.ClipsDescendants = true
        local stLay2 = Instance.new("UIListLayout", stF2)
        stLay2.FillDirection = Enum.FillDirection.Horizontal
        stLay2.VerticalAlignment = Enum.VerticalAlignment.Center
        stLay2.Padding = UDim.new(0, 4)

        if macro.isCommunity then
            makePill(stF2, fmtNum(macro.cph or 0) .. " Coins/hr", C.yellow, 1)
            if macro.dateSummary and macro.dateSummary ~= "" then
                makePill(stF2, macro.dateSummary, Color3.fromRGB(120, 130, 155), 2)
            end
            if (macro.gph or 0) > 0 then
                makePill(stF2, fmtNum(macro.gph) .. " Gems/hr", C.purple, 3)
                makePill(stF2, macro.map, C.blue, 4)
            else
                makePill(stF2, macro.map, C.blue, 3)
            end
            if launchDifficulty ~= "" then
                local diffColor = difficultyColors[launchDifficulty] or C.textDim
                makePill(stF2, launchDifficulty, diffColor, 5)
            end
        else
            if (macro.gph or 0) > 0 then
                makePill(stF2, fmtNum(macro.cph or cph) .. " Coins/hr", C.yellow, 1)
                makePill(stF2, fmtNum(macro.gph) .. " Gems/hr", C.purple, 2)
                makePill(stF2, timeText, Color3.fromRGB(120, 130, 155), 3)
            elseif isMobile then
                makePill(stF2, fmtNum(xph) .. " XP/hr", C.blue, 1)
                makePill(stF2, fmtNum(cph) .. (isHC and " Gems/hr" or " C/hr"), isHC and C.purple or C.yellow, 2)
                makePill(stF2, timeText, Color3.fromRGB(120, 130, 155), 3)
            else
                makePill(stF2, (macro.xp or 0) .. " XP  -  " .. fmtNum(xph) .. "/hr", C.blue, 1)
                makePill(
                    stF2,
                    macro.coins .. (isHC and " Gems" or " Coins") .. "  -  " .. fmtNum(cph) .. "/hr",
                    isHC and C.purple or C.yellow,
                    2
                )
                makePill(stF2, timeText, Color3.fromRGB(120, 130, 155), 3)
            end
        end

        local divY2 = stY2 + M.pill + 5
        local div2 = Instance.new("Frame", card)
        div2.Size = UDim2.new(1, -28, 0, 1)
        div2.Position = UDim2.new(0, 14, 0, divY2)
        div2.BackgroundColor3 = C.border
        div2.BackgroundTransparency = 0.4
        div2.BorderSizePixel = 0
        div2.Visible = false

        local loadY = divY2 + 6
        local loadL = Instance.new("TextLabel", card)
        loadL.Name = "Loadout"
        loadL.Size = UDim2.new(1, -20, 0, 14)
        loadL.Position = UDim2.new(0, 14, 0, loadY)
        loadL.BackgroundTransparency = 1
        loadL.Text = "Loadout: " .. table.concat(macro.loadout, ", ")
        loadL.TextColor3 = macro.color
        loadL.TextSize = isMobile and 9 or 11
        loadL.Font = Enum.Font.GothamMedium
        loadL.TextXAlignment = Enum.TextXAlignment.Left
        loadL.TextTruncate = Enum.TextTruncate.AtEnd
        loadL.TextTransparency = 1

        local runY = loadY + 16
        local runBtn = Instance.new("TextButton", card)
        runBtn.Name = "Run"
        runBtn.Size = UDim2.new(0, isMobile and 66 or 84, 0, isMobile and 26 or 30)
        runBtn.Position = UDim2.new(1, -(isMobile and 76 or 100), 0, runY)
        runBtn.BackgroundColor3 = macro.color
        runBtn.BorderSizePixel = 0
        runBtn.Text = hasRunner and "> Run" or "Add Data"
        runBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        runBtn.TextSize = isMobile and 10 or 12
        runBtn.Font = Enum.Font.GothamBold
        runBtn.Visible = false
        runBtn.ZIndex = 5
        Instance.new("UICorner", runBtn).CornerRadius = UDim.new(0, 7)
        runBtn.MouseEnter:Connect(function()
            TweenService:Create(runBtn, TweenInfo.new(0.1), {
                BackgroundColor3 = Color3.new(
                    math.min(macro.color.R * 1.2, 1),
                    math.min(macro.color.G * 1.2, 1),
                    math.min(macro.color.B * 1.2, 1)
                ),
            }):Play()
        end)
        runBtn.MouseLeave:Connect(function()
            TweenService:Create(runBtn, TweenInfo.new(0.1), { BackgroundColor3 = macro.color }):Play()
        end)

        local expanded = false
        local runClicked = false
        local actionRow = Instance.new("ScrollingFrame", card)
        actionRow.Size = UDim2.new(1, -(isMobile and 92 or 112), 0, isMobile and 26 or 30)
        actionRow.Position = UDim2.new(0, 14, 0, runY)
        actionRow.BackgroundTransparency = 1
        actionRow.Visible = false
        actionRow.ZIndex = 5
        actionRow.BorderSizePixel = 0
        actionRow.ScrollBarThickness = 0
        actionRow.ScrollingDirection = Enum.ScrollingDirection.X
        actionRow.ClipsDescendants = true
        actionRow.CanvasSize = UDim2.new(0, 0, 0, 0)
        actionRow.Active = true
        actionRow.Selectable = false
        pcall(function()
            actionRow.AutomaticCanvasSize = Enum.AutomaticSize.X
        end)
        local actionLay = Instance.new("UIListLayout", actionRow)
        actionLay.FillDirection = Enum.FillDirection.Horizontal
        actionLay.SortOrder = Enum.SortOrder.LayoutOrder
        actionLay.Padding = UDim.new(0, 4)
        actionLay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            actionRow.CanvasSize = UDim2.new(0, actionLay.AbsoluteContentSize.X + 4, 0, 0)
        end)

        local function actionButton(text, width, accentColor, order, tooltipText, callback)
            local b = Instance.new("TextButton", actionRow)
            b.Size = UDim2.new(0, width, 1, 0)
            b.BackgroundColor3 = C.surface
            b.BackgroundTransparency = 0
            b.BorderSizePixel = 0
            b.Text = text
            b.TextColor3 = C.textSec
            b.TextSize = isMobile and 8 or 10
            b.Font = Enum.Font.GothamBold
            b.LayoutOrder = order
            b.ZIndex = 6
            b.AutoButtonColor = false
            b:SetAttribute("BaseColor", C.surface)
            b:SetAttribute("RestTextColor", C.textSec)
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
            local stroke = Instance.new("UIStroke", b)
            stroke.Color = accentColor or C.border
            stroke.Thickness = 1
            stroke.Transparency = 0.62
            attachTooltip(b, tooltipText or text)
            b.MouseEnter:Connect(function()
                TweenService:Create(b, TweenInfo.new(0.1), { BackgroundColor3 = C.surfaceAlt, TextColor3 = C.text })
                    :Play()
                TweenService:Create(stroke, TweenInfo.new(0.1), { Transparency = 0.25 }):Play()
            end)
            b.MouseLeave:Connect(function()
                TweenService:Create(b, TweenInfo.new(0.1), {
                    BackgroundColor3 = b:GetAttribute("BaseColor") or C.surface,
                    TextColor3 = b:GetAttribute("RestTextColor") or C.textSec,
                }):Play()
                TweenService
                    :Create(stroke, TweenInfo.new(0.1), { Transparency = b:GetAttribute("StrokeTransparency") or 0.62 })
                    :Play()
            end)
            b.MouseButton1Click:Connect(function()
                runClicked = true
                callback()
                task.delay(0.2, function()
                    runClicked = false
                end)
            end)
            return b, stroke
        end

        local function setActionState(btn, stroke, active, accentColor, activeText)
            if not btn then
                return
            end
            local base = active and Color3.fromRGB(25, 29, 43) or C.surface
            btn:SetAttribute("BaseColor", base)
            btn:SetAttribute("StrokeTransparency", active and 0.18 or 0.62)
            btn:SetAttribute("RestTextColor", active and (activeText or accentColor or C.text) or C.textSec)
            btn.BackgroundColor3 = base
            btn.TextColor3 = active and (activeText or accentColor or C.text) or C.textSec
            if stroke then
                stroke.Color = accentColor or C.border
                stroke.Transparency = active and 0.18 or 0.62
            end
        end

        local function refreshCardVisuals(animated)
            local fav = isStratFavorite(stratId)
            sub2.Position = UDim2.new(0, 14, 0, sY)
            accentBar.BackgroundColor3 = fav and Color3.fromRGB(250, 204, 21) or macro.color
            ratingL.Text = ratingText()
            ratingL.TextColor3 = C.textSec
            local targetBg = expanded and C.cardHover or C.card
            local targetStroke = expanded and macro.color or C.border
            local targetTransparency = expanded and 0 or 0.4
            if animated then
                TweenService:Create(card, TweenInfo.new(0.22, Enum.EasingStyle.Quint), { BackgroundColor3 = targetBg })
                    :Play()
                TweenService:Create(cStroke, TweenInfo.new(0.22, Enum.EasingStyle.Quint), {
                    Color = targetStroke,
                    Transparency = targetTransparency,
                }):Play()
            else
                card.BackgroundColor3 = targetBg
                cStroke.Color = targetStroke
                cStroke.Transparency = targetTransparency
            end
        end
        if canUseCloudFeedback then
            queueCloudFeedback(stratId, function(data)
                if type(data) == "table" then
                    feedback = data
                    refreshCardVisuals(false)
                end
            end)
        end

        local favBtn, favStroke
        local function updateFavButton()
            if not favBtn then
                return
            end
            local fav = isStratFavorite(stratId)
            local color = fav and Color3.fromRGB(69, 58, 23) or C.surface
            favBtn:SetAttribute("BaseColor", color)
            favBtn:SetAttribute("RestTextColor", fav and C.yellow or C.textSec)
            favBtn.BackgroundColor3 = color
            favBtn.Text = fav and "Saved" or "Save"
            favBtn.TextColor3 = fav and C.yellow or C.textSec
            favBtn:SetAttribute("StrokeTransparency", fav and 0.2 or 0.62)
            if favStroke then
                favStroke.Transparency = fav and 0.2 or 0.62
            end
            refreshCardVisuals(true)
        end
        favBtn, favStroke = actionButton("Save", isMobile and 36 or 44, C.yellow, 1, "Save to Favorites", function()
            setStratFavorite(stratId, not isStratFavorite(stratId))
            updateFavButton()
            applyCardFilters()
            toast(isStratFavorite(stratId) and "Added to favorites" or "Removed from favorites", C.green)
        end)
        updateFavButton()

        local likeBtn, likeStroke
        local dislikeBtn, dislikeStroke
        local function updateVoteButtons()
            local vote = getLocalStratVote(stratId)
            if likeBtn then
                likeBtn.Text = vote == "like" and "Liked" or "Like"
            end
            if dislikeBtn then
                dislikeBtn.Text = vote == "dislike" and "Disliked" or "Dislike"
            end
            setActionState(likeBtn, likeStroke, vote == "like", C.green, C.green)
            setActionState(dislikeBtn, dislikeStroke, vote == "dislike", C.red, C.red)
        end

        likeBtn, likeStroke = actionButton("Like", isMobile and 36 or 44, C.green, 2, "Like", function()
            setLocalStratVote(stratId, "like")
            ratingL.Text = ratingText()
            updateVoteButtons()
            refreshCardVisuals(true)
            if canUseCloudFeedback then
                task.spawn(function()
                    local ok, result = submitCloudVote(stratId, "like")
                    if ok and type(result) == "table" and result.ok == true then
                        feedbackCache[stratId] = nil
                        queueCloudFeedback(stratId, function(data)
                            feedback = data
                            refreshCardVisuals(false)
                        end)
                        toast("Vote sent", C.green)
                    else
                        toast("Vote saved locally", C.yellow)
                        warn("[Zephyr] Feedback vote failed:", tostring(result))
                    end
                end)
            else
                toast("Vote saved", C.green)
            end
        end)
        dislikeBtn, dislikeStroke = actionButton("Dislike", isMobile and 44 or 54, C.red, 3, "Dislike", function()
            setLocalStratVote(stratId, "dislike")
            ratingL.Text = ratingText()
            updateVoteButtons()
            refreshCardVisuals(true)
            if canUseCloudFeedback then
                task.spawn(function()
                    local ok, result = submitCloudVote(stratId, "dislike")
                    if ok and type(result) == "table" and result.ok == true then
                        feedbackCache[stratId] = nil
                        queueCloudFeedback(stratId, function(data)
                            feedback = data
                            refreshCardVisuals(false)
                        end)
                        toast("Vote sent", C.green)
                    else
                        toast("Vote saved locally", C.yellow)
                        warn("[Zephyr] Feedback vote failed:", tostring(result))
                    end
                end)
            else
                toast("Vote saved", C.green)
            end
        end)
        updateVoteButtons()
        actionButton("Report", isMobile and 44 or 54, C.red, 4, "Report", function()
            showReportPrompt(macro, stratId)
        end)
        if macro.isCustom then
            actionButton("Edit", isMobile and 34 or 42, C.accent, 5, "Edit", function()
                if type(loadCustomEditor) == "function" then
                    loadCustomEditor(macro.customIndex)
                    openExtras()
                end
            end)
            actionButton("Del", isMobile and 32 or 38, C.red, 6, "Delete", function()
                local customs = ensureSettingsTable("customStrats")
                if macro.customIndex and customs[macro.customIndex] then
                    table.remove(customs, macro.customIndex)
                    saveSettingsSoon()
                    saveSettingsNow()
                    if type(rebuildCustomStrats) == "function" then
                        rebuildCustomStrats()
                    end
                    toast("Personal strat deleted", C.red)
                end
            end)
        end

        local noteL = nil
        if macro.note and macro.note ~= "" then
            local noteY = runY + (isMobile and 30 or 36)
            noteL = Instance.new("TextLabel", card)
            noteL.Size = UDim2.new(1, -20, 0, isMobile and 14 or 18)
            noteL.AutomaticSize = Enum.AutomaticSize.Y
            noteL.Position = UDim2.new(0, 14, 0, noteY)
            noteL.BackgroundTransparency = 1
            noteL.Text = macro.note
            noteL.TextColor3 = C.textSec
            noteL.TextSize = isMobile and 9 or 10
            noteL.Font = Enum.Font.Gotham
            noteL.TextXAlignment = Enum.TextXAlignment.Left
            noteL.TextWrapped = true
            noteL.TextTransparency = 1
            noteL.ZIndex = 5
        end

        local expandedH = M.cardExp + (noteL and (isMobile and 14 or 24) or 0)

        local function expand()
            if expanded then
                return
            end
            expanded = true
            TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {
                Size = UDim2.new(1, 0, 0, expandedH),
            }):Play()
            refreshCardVisuals(true)
            TweenService:Create(loadL, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
            div2.Visible = true
            runBtn.Visible = true
            actionRow.Visible = true
            if noteL then
                TweenService:Create(noteL, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { TextTransparency = 0 }):Play()
            end
        end

        local function collapse()
            if not expanded then
                return
            end
            expanded = false
            TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {
                Size = UDim2.new(1, 0, 0, M.cardH),
            }):Play()
            refreshCardVisuals(true)
            TweenService:Create(loadL, TweenInfo.new(0.12), { TextTransparency = 1 }):Play()
            if noteL then
                TweenService:Create(noteL, TweenInfo.new(0.12), { TextTransparency = 1 }):Play()
            end
            task.delay(0.12, function()
                if not expanded then
                    div2.Visible = false
                    runBtn.Visible = false
                    actionRow.Visible = false
                end
            end)
        end

        local function startStratPlayback(isAutoRerun)
            if not (hasStratContent or hasStratUrl) then
                return false
            end
            if isAutoRerun then
                stopMacroPlayback()
                isExecuting = false
            end
            local stratOk, stratText = getStratText()
            if not stratOk then
                runBtn.Text = "> Run"
                isExecuting = false
                toast("Strat URL failed", C.red)
                warn("[Zephyr] Strat URL failed:", tostring(stratText))
                return false
            end
            local actions = parseAndLoad(stratText)
            if not actions or #actions == 0 then
                runBtn.Text = "> Run"
                isExecuting = false
                toast("No actions parsed for strat", C.red)
                return false
            end
            isExecuting = true
            local playbackStarted = false
            runBtn.Text = "Waiting W1..."
            toast("Waiting for Wave 1...", C.yellow)
            local started = playMacro(actions, function(ok, reason)
                runBtn.Text = "> Run"
                isExecuting = false
                if not ok and reason == "busy" then
                    toast("Playback was busy, retrying...", C.yellow)
                end
                if not ok then
                    return
                end
                if playbackStarted then
                    scheduleAutoRerunStrat(function()
                        if runBtn and runBtn.Parent then
                            return startStratPlayback(true)
                        end
                        return false
                    end, function()
                        toast("Waiting for restart...", C.yellow)
                    end, function()
                        toast("Auto rerunning: " .. macro.name, macro.color)
                    end)
                end
            end, function()
                playbackStarted = true
                runBtn.Text = "Running..."
            end, { actionLeadTime = tonumber(macro.actionLeadTime) or 0 })
            if not started then
                runBtn.Text = "> Run"
                isExecuting = false
                return false
            end
            return true
        end

        local function execute(force)
            if isExecuting or (extrasOpen and not force) then
                return false
            end
            if not hasRunner then
                toast("Add stratContent first", C.red)
                return false
            end
            local validatedStratText = nil
            local selectedDescriptor = nil
            if hasStratContent or hasStratUrl then
                isExecuting = true
                runBtn.Text = "Loading..."
                local stratOk, stratText = getStratText()
                if not stratOk then
                    runBtn.Text = "> Run"
                    isExecuting = false
                    toast("Strat URL failed", C.red)
                    warn("[Zephyr] Strat URL failed:", tostring(stratText))
                    return false
                end
                local previewActions = parseAndLoad(stratText)
                if not previewActions or #previewActions == 0 then
                    runBtn.Text = "> Run"
                    isExecuting = false
                    toast("No actions parsed for strat", C.red)
                    return false
                end
                validatedStratText = stratText
            end
            if hasStratContent or hasStratUrl then
                autoRerunSerial += 1
                selectedDescriptor = rememberLastStrat(macro, validatedStratText)
            end
            isExecuting = true
            TweenService:Create(card, TweenInfo.new(0.08), { BackgroundColor3 = macro.color }):Play()
            TweenService:Create(cStroke, TweenInfo.new(0.08), { Color = macro.color, Transparency = 0 }):Play()
            runBtn.Text = "Running..."
            toast("Running: " .. macro.name, macro.color)

            task.spawn(function()
                if selectedDescriptor and (hasStratContent or hasStratUrl) then
                    local voteStarted = runSelectedStratLobbyVote(selectedDescriptor, function()
                        startStratPlayback(false)
                    end, function(message)
                        runBtn.Text = "> Run"
                        isExecuting = false
                        toast(tostring(message or "Selected strat vote failed"), C.red)
                    end)
                    if voteStarted then
                        runBtn.Text = "Voting..."
                        toast("Voting map: " .. tostring(selectedDescriptor.map), C.yellow)
                        return
                    end
                end

                if game.PlaceId == 3260590327 and macro.loadout then
                    local loadoutOk, loadoutMsg = applyLoadoutList(macro.loadout)
                    if loadoutOk then
                        toast(loadoutMsg, C.green)
                    else
                        toast(loadoutMsg, C.yellow)
                    end
                    task.wait(0.2)
                end

                if game.PlaceId == 3260590327 then
                    local modeInfo = resolveMacroModeInfo(macro) or getMapDefaults(macro.map or "")
                    local payload = buildStartPayloadFromModeInfo(modeInfo)
                    local launchOk, launchResult = invokeRemoteFunction("Multiplayer", "v2:start", payload)
                    if not launchOk then
                        warn("[Zephyr] Match start failed:", tostring(launchResult))
                    end
                    task.wait(2)
                end

                if hasStratContent or hasStratUrl then
                    startStratPlayback(false)
                    return
                elseif macro.script then
                    local ok3, err3 = runSourceScript(macro.script)
                    if not ok3 then
                        warn("Execution failed:", err3)
                    end
                end

                task.wait(0.6)
                TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Quint), {
                    BackgroundColor3 = expanded and C.cardHover or C.card,
                }):Play()
                TweenService:Create(cStroke, TweenInfo.new(0.3, Enum.EasingStyle.Quint), {
                    Color = expanded and macro.color or C.border,
                    Transparency = expanded and 0 or 0.4,
                }):Play()
                runBtn.Text = "> Run"
                isExecuting = false
            end)
            return true
        end

        runBtn.MouseButton1Click:Connect(function()
            runClicked = true
            execute()
            task.delay(0.15, function()
                runClicked = false
            end)
        end)

        if isMobile then
            card.MouseButton1Click:Connect(function()
                if runClicked or extrasOpen then
                    return
                end
                if expanded then
                    collapse()
                else
                    expand()
                end
            end)
        else
            card.MouseEnter:Connect(function()
                if not extrasOpen then
                    expand()
                end
            end)
            card.MouseLeave:Connect(function()
                collapse()
            end)
            card.MouseButton1Click:Connect(function()
                if not extrasOpen then
                    execute()
                end
            end)
        end

        local loadoutText = ""
        if type(macro.loadout) == "table" then
            loadoutText = table.concat(macro.loadout, " ")
        end
        local searchBlob = table
            .concat({
                macro.name or "",
                macro.subtitle or "",
                macro.map or "",
                macro.difficulty or "",
                macro.launchDifficulty or "",
                loadoutText,
                macro.note or "",
                macro.dateSummary or "",
            }, " ")
            :lower()
        local entryCategory = macro.category
            or (macro.isCustom and "Custom" or macro.isCommunity and "Community" or "Official")

        table.insert(cardEntries, {
            card = card,
            name = macro.name or "",
            section = macro.difficulty or "Community",
            category = entryCategory,
            originalOrder = ord,
            searchText = searchBlob,
            isFavorite = function()
                return isStratFavorite(stratId)
            end,
            coinsSort = isHC and 0 or (tonumber(cph) or 0),
            gemsSort = isHC and (tonumber(cph) or 0) or (tonumber(macro.gph) or 0),
        })
        applyCardFilters()
    end

    local function makeCardSafe(macro, ord)
        local ok, err = pcall(makeCard, macro, ord)
        if not ok then
            warn("[Zephyr] Strategy card failed:", tostring(macro and macro.name), tostring(err))
        end
        return ok
    end

    -- Built-in strategies
    local organized = organizeMacros()
    for i, diff in ipairs(difficultyOrder) do
        if #organized[diff] > 0 then
            makeSectionHdr(diff, i)
            for j, macro in ipairs(organized[diff]) do
                makeCardSafe(macro, (i * 1000) + j)
            end
        end
    end

    local customOrder = #difficultyOrder + 1
    makeSectionHdr("Custom", customOrder)
    rebuildCustomStrats = function()
        for i = #cardEntries, 1, -1 do
            local entry = cardEntries[i]
            if entry and entry.category == "Custom" then
                if entry.card and entry.card.Parent then
                    entry.card:Destroy()
                end
                table.remove(cardEntries, i)
            end
        end
        local customs = ensureSettingsTable("customStrats")
        for i, saved in ipairs(customs) do
            local macro = buildCustomStratMacro(saved, i)
            if macro then
                makeCardSafe(macro, (customOrder * 1000) + i)
            end
        end
        applyCardFilters()
    end
    rebuildCustomStrats()

    -- Community strategies
    local communityLoadingLabel = Instance.new("TextLabel", content)
    communityLoadingLabel.Size = UDim2.new(1, 0, 0, 26)
    communityLoadingLabel.BackgroundTransparency = 1
    communityLoadingLabel.Text = "⏳ Loading community strats..."
    communityLoadingLabel.TextColor3 = C.textDim
    communityLoadingLabel.TextSize = M.sec
    communityLoadingLabel.Font = Enum.Font.GothamMedium
    communityLoadingLabel.LayoutOrder = 3999

    task.spawn(function()
        local HttpService = game:GetService("HttpService")
        local ok4, files = pcall(function()
            local response =
                game:HttpGet("https://api.github.com/repos/TheRealAvrwm/TdsCommunityStrats/contents/strats")
            return HttpService:JSONDecode(response)
        end)
        if not runtimeAlive or not gui.Parent then
            return
        end
        if communityLoadingLabel and communityLoadingLabel.Parent then
            communityLoadingLabel:Destroy()
        end
        if not ok4 or not files or type(files) ~= "table" or #files == 0 then
            local errLabel = Instance.new("TextLabel", content)
            errLabel.Size = UDim2.new(1, 0, 0, 22)
            errLabel.BackgroundTransparency = 1
            errLabel.Text = "No community strats yet"
            errLabel.TextColor3 = C.textDim
            errLabel.TextSize = M.sec
            errLabel.Font = Enum.Font.GothamMedium
            errLabel.LayoutOrder = 3999
            task.defer(function()
                content.CanvasSize = UDim2.new(0, 0, 0, cLay.AbsoluteContentSize.Y + 16)
            end)
            return
        end
        local communityOrder = #difficultyOrder + 2
        makeSectionHdr("Community", communityOrder)
        local cardOrder = (communityOrder * 1000) + 1
        for _, file in ipairs(files) do
            if type(file) == "table" and file.name and file.name:match("%.txt$") and file.download_url then
                local info = parseCommunityFilename(file.name)
                local rawUrl = file.download_url
                local contentOk, fileContent = pcall(function()
                    return game:HttpGet(rawUrl)
                end)
                if not runtimeAlive or not gui.Parent then
                    return
                end
                local towers = {}
                local note = nil
                local stratMeta = nil
                if contentOk and fileContent then
                    towers = detectTowersFromContent(fileContent)
                    note = detectNoteFromContent(fileContent)
                    stratMeta = detectStratMetadataFromContent(fileContent)
                end
                local launchDifficulty = trimText(info.difficulty or "")
                if launchDifficulty ~= "" then
                    launchDifficulty = normalizeAutoRejoinMode(launchDifficulty)
                end
                local launchModeInfo = nil
                if launchDifficulty ~= "" and DIFFICULTY_MAP[launchDifficulty] then
                    launchModeInfo = copyModeInfo(DIFFICULTY_MAP[launchDifficulty])
                else
                    launchModeInfo = copyModeInfo(getMapDefaults(info.map))
                    launchDifficulty = modeNameFromModeInfo(launchModeInfo, launchDifficulty)
                end
                local communityMacro = {
                    id = "github:" .. tostring(file.name),
                    sourceFileName = tostring(file.name),
                    name = info.stratName,
                    subtitle = "Community \xE2\x80\xA2 " .. (info.map or "Unknown"),
                    color = Color3.fromRGB(59, 130, 246),
                    loadout = #towers > 0 and towers or { "Unknown" },
                    difficulty = "Community",
                    category = "Community",
                    launchDifficulty = launchDifficulty,
                    modeInfo = launchModeInfo,
                    map = info.map,
                    time = 0,
                    coins = info.cph,
                    xp = 0,
                    isCommunity = true,
                    cph = info.cph,
                    gph = info.gph or 0,
                    note = note,
                    dateSummary = stratDateSummary(stratMeta) or "Published unknown | Updated unknown",
                    meta = stratMeta,
                    feedback = feedbackFromMetadata(stratMeta),
                    stratContent = contentOk and fileContent or nil,
                }
                makeCardSafe(communityMacro, cardOrder)
                cardOrder = cardOrder + 1
            end
        end
        task.wait()
        if not runtimeAlive or not gui.Parent then
            return
        end
        content.CanvasSize = UDim2.new(0, 0, 0, cLay.AbsoluteContentSize.Y + 16)
    end)

    cLay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        content.CanvasSize = UDim2.new(0, 0, 0, cLay.AbsoluteContentSize.Y + 16)
    end)
    task.defer(function()
        content.CanvasSize = UDim2.new(0, 0, 0, cLay.AbsoluteContentSize.Y + 16)
    end)

    do
        local dragging, dragStart, startPos3, dragInput3 = false, nil, nil, nil
        local function beginMainDrag(input)
            local t = input.UserInputType
            if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos3 = main.Position
                dragInput3 = input
                local ec
                ec = input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                        if ec then
                            ec:Disconnect()
                        end
                    end
                end)
            end
        end
        hdr.InputBegan:Connect(beginMainDrag)
        topLine.InputBegan:Connect(beginMainDrag)
        brandColor.InputBegan:Connect(beginMainDrag)
        subLabel.InputBegan:Connect(beginMainDrag)
        connectUI(UserInputService.InputChanged, function(input)
            if
                dragging
                and (
                    input == dragInput3
                    or (
                        dragInput3.UserInputType == Enum.UserInputType.MouseButton1
                        and input.UserInputType == Enum.UserInputType.MouseMovement
                    )
                )
            then
                local d = input.Position - dragStart
                panelRevision += 1
                if panelTween then
                    panelTween:Cancel()
                end
                targetPos = clampPosition(
                    UDim2.new(startPos3.X.Scale, startPos3.X.Offset + d.X, startPos3.Y.Scale, startPos3.Y.Offset + d.Y),
                    targetSize.X.Offset,
                    targetSize.Y.Offset
                )
                main.Position = targetPos
            end
        end)
    end
end

bootReadyOk, bootReady = pcall(waitForTdsUiReady, UserInputService.TouchEnabled and 120 or 90)
if not bootReadyOk or bootReady ~= true then
    warn(
        "[Zephyr] TDS UI was slow; building Zephyr anyway and keeping repair watchdog alive:",
        tostring(bootReady)
    )
end
pcall(startTdsUiRepairWindow, 25)

uiOk, uiErr = xpcall(createUI, function(err)
    return zephyrTraceback(err)
end)
if not uiOk then
    warn("[Zephyr] UI failed:", tostring(uiErr))
end
task.spawn(function()
    local bootWatchStart = tick()
    local rebuildAttempts = 0
    while runtimeAlive and tick() - bootWatchStart < (UserInputService.TouchEnabled and 150 or 90) do
        task.wait(rebuildAttempts == 0 and 0.5 or 1)
        if runtimeAlive and PlayerGui and not PlayerGui:FindFirstChild("ZephyrTDS") then
            rebuildAttempts += 1
            pcall(waitForTdsUiReady, UserInputService.TouchEnabled and 45 or 20)
            if not runtimeAlive then
                return
            end
            local ok, err = xpcall(createUI, function(e)
                return zephyrTraceback(e)
            end)
            if not ok then
                warn("[Zephyr] UI rebuild failed:", tostring(err))
            end
            if PlayerGui:FindFirstChild("ZephyrTDS") then
                return
            end
        end
    end
end)
registerRuntimeCleanup(function()
    local stops = {
        stopMacroPlayback,
        stopAutoskip,
        stopESP,
        stopEnemyInspector,
        stopGatling,
        stopAutoClaimAll,
        stopAutoReady,
        stopAutoRespawnVote,
        stopPickupFarm,
        stopModifierVote,
        stopResultsTracker,
        stopMatchTracker,
        stopAbilityManager,
        stopCommanderChain,
        stopSupportCaravan,
        stopAutoUpgrade,
        stopAutoUpgradeFarms,
        stopSkinChanger,
    }
    for _, stop in ipairs(stops) do
        pcall(stop)
    end
    if stopAutoAirstrike then
        pcall(stopAutoAirstrike)
    end
    if stopAutoPursuitPosition then
        pcall(stopAutoPursuitPosition)
    end
    pcall(function()
        local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then
            return
        end
        for _, child in ipairs(playerGui:GetChildren()) do
            if child.Name == "ZephyrTDS" then
                child:Destroy()
            end
        end
    end)
end)
task.defer(function()
    if runtimeAlive then
        startLobbyAutoRejoinOnLaunch()
    end
end)
