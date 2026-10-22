local Runtime = {
    alive = true,
    errors = {},
    connections = {},
    threads = {},
    modules = setmetatable({}, { __mode = "k" }),
    noWait = setmetatable({}, { __mode = "k" }),
}
local NativeTask, NativeRequire = task, require
function Runtime.record(context, message)
    local ok, text = pcall(tostring, message)
    text = ok and text:sub(1, 600) or "Unprintable error"
    local last = Runtime.errors[#Runtime.errors]
    if last and last.context == context and last.message == text then
        last.count += 1
        return
    end
    if #Runtime.errors >= 30 then
        table.remove(Runtime.errors, 1)
    end
    Runtime.errors[#Runtime.errors + 1] = { context = context, message = text, count = 1 }
    if Runtime.status then
        pcall(Runtime.status, context)
    end
end
function Runtime.before(callback)
    if not Runtime.alive then
        return
    end
    local thread = coroutine.running()
    local previous = Runtime.noWait[thread]
    Runtime.noWait[thread] = true
    local ok, message = pcall(callback)
    Runtime.noWait[thread] = previous
    if not ok then
        Runtime.record("Optional game customization", message)
    end
end
function Runtime.guard(callback, context)
    local running, failures, retryAt = false, 0, 0
    return function(...)
        if not Runtime.alive or running or os.clock() < retryAt then
            return
        end
        running = true
        local thread = coroutine.running()
        local alreadyTracked = Runtime.threads[thread]
        Runtime.threads[thread] = true
        local result = table.pack(pcall(callback, ...))
        if not alreadyTracked then
            Runtime.threads[thread] = nil
        end
        running = false
        if not result[1] then
            failures = math.min(failures + 1, 5)
            retryAt = os.clock() + math.min(5, 0.25 * 2 ^ (failures - 1))
            Runtime.record(context or "Callback", result[2])
            return
        end
        failures = 0
        return table.unpack(result, 2, result.n)
    end
end
function Runtime.connect(signal, callback)
    if not Runtime.alive then
        return nil
    end
    local connection = signal:Connect(Runtime.guard(callback, "Signal"))
    Runtime.connections[connection] = true
    Runtime.connectionCount = (Runtime.connectionCount or 0) + 1
    if Runtime.connectionCount % 64 == 0 then
        for item in pairs(Runtime.connections) do
            if not item.Connected then
                Runtime.connections[item] = nil
            end
        end
    end
    return connection
end
function Runtime.stop()
    if not Runtime.alive then
        return
    end
    Runtime.alive = false
    for connection in pairs(Runtime.connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(Runtime.connections)
    local current = coroutine.running()
    for thread in pairs(Runtime.threads) do
        if thread ~= current then
            pcall(NativeTask.cancel, thread)
        end
    end
    table.clear(Runtime.threads)
end
Runtime.unload = Runtime.stop
local task = setmetatable({}, { __index = NativeTask })
local function schedule(method, seconds, callback, ...)
    local args = table.pack(...)
    local thread = coroutine.create(function()
        Runtime.guard(callback, "Background task")(table.unpack(args, 1, args.n))
        Runtime.threads[coroutine.running()] = nil
    end)
    if not Runtime.alive then
        return thread
    end
    Runtime.threads[thread] = true
    if seconds then
        NativeTask[method](seconds, thread)
    else
        NativeTask[method](thread)
    end
    return thread
end
function task.spawn(callback, ...)
    return schedule("spawn", nil, callback, ...)
end
function task.defer(callback, ...)
    return schedule("defer", nil, callback, ...)
end
function task.delay(seconds, callback, ...)
    return schedule("delay", seconds, callback, ...)
end
function task.cancel(thread)
    Runtime.threads[thread] = nil
    pcall(NativeTask.cancel, thread)
end
function Runtime.waitFor(probe, seconds)
    local deadline = os.clock() + (seconds or 120)
    repeat
        if not Runtime.alive then
            return nil
        end
        local ok, value = pcall(probe)
        if ok and value then
            return value
        end
        NativeTask.wait(0.2)
    until os.clock() >= deadline
    Runtime.record("Readiness", "Dependency did not become ready before timeout")
    return nil
end
function Runtime.module(module)
    if not Runtime.alive or typeof(module) ~= "Instance" or not module:IsA("ModuleScript") or not module.Parent then
        return nil
    end
    local entry = Runtime.modules[module]
    if entry and entry.ready then
        return entry.value
    end
    if entry and (entry.pending or os.clock() < entry.retryAt) then
        return nil
    end
    entry = { pending = true, retryAt = 0 }
    Runtime.modules[module] = entry
    task.spawn(function()
        local ok, value = pcall(NativeRequire, module)
        entry.pending = false
        if ok and value ~= nil then
            entry.ready, entry.value = true, value
        else
            entry.retryAt = os.clock() + 5
            Runtime.record("Module", value or "Module returned no value")
        end
    end)
    if entry.ready then
        return entry.value
    end
    return nil
end
local function require(module)
    -- Game hooks can't wait on a require.
    if Runtime.noWait[coroutine.running()] then
        local value = Runtime.module(module)
        if value == nil then
            error("Optional module still loading", 0)
        end
        return value
    end
    local result = Runtime.waitFor(function()
        local value = Runtime.module(module)
        if value ~= nil then
            return { value }
        end
    end, 20)
    if not result then
        error("Module unavailable", 0)
    end
    return result[1]
end
local function print(...) end
local function warn(...)
    Runtime.record("Handled failure", select(1, ...))
end
function Runtime.download(url, required)
    local source
    for attempt = 1, required and 3 or 1 do
        local finished, body
        local request = task.spawn(function()
            local ok, value = pcall(game.HttpGet, game, url)
            if ok and type(value) == "string" and #value > 0 then
                body = value
            end
            finished = true
        end)
        Runtime.waitFor(function()
            return finished
        end, 10)
        if not finished then
            task.cancel(request)
        end
        if not Runtime.alive then
            return nil
        end
        if body then
            source = body
            break
        end
        if attempt < (required and 3 or 1) then
            NativeTask.wait(attempt)
        end
    end
    if not source then
        return nil
    end
    local chunk, message = loadstring(source)
    if not chunk then
        Runtime.record("Download", message)
        return nil
    end
    if type(setfenv) == "function" and type(getfenv) == "function" then
        setfenv(chunk, setmetatable({ print = print, warn = warn }, { __index = getfenv() }))
    end
    local ok, value = pcall(chunk)
    if not ok then
        Runtime.record("Library", value)
        return nil
    end
    return value
end

local function initialize()
    do
        local Players = game:GetService("Players")
        local player = Runtime.waitFor(function()
            return Players.LocalPlayer
        end)
        if not player then
            return
        end
        local env = _G

        if type(getgenv) == "function" then
            local ok, genv = pcall(getgenv)
            if ok and type(genv) == "table" then
                env = genv
            end
        end

        local old = env.__ZEPHYR_HYPERSHOT_RUNTIME
        if type(old) == "table" and type(old.unload) == "function" then
            pcall(old.unload)
        end
        env.__ZEPHYR_HYPERSHOT_RUNTIME = Runtime
    end

    if not Runtime.waitFor(function()
        return game:IsLoaded()
    end) then
        return
    end
    local startupPlayer = game:GetService("Players").LocalPlayer
    if
        not Runtime.waitFor(function()
            return startupPlayer:FindFirstChild("PlayerGui") and workspace.CurrentCamera
        end)
    then
        return
    end
    if
        not Runtime.waitFor(function()
            local storage = game:GetService("ReplicatedStorage")
            local modules = storage:FindFirstChild("Modules")
            local global = modules and Runtime.module(modules:FindFirstChild("GlobalStuff"))
            local gui = startupPlayer:FindFirstChild("PlayerGui")
            local controller = gui and gui:FindFirstChild("ControllerGUI")
            local main = controller and controller:FindFirstChild("NewMainLocal")
            if not main then
                local folder = storage:FindFirstChild("ControllerStuff")
                main = folder and folder:FindFirstChild("NewMainLocal")
            end
            local shared = main and Runtime.module(main:FindFirstChild("Shared"))
            return type(global) == "table" and type(shared) == "table"
        end)
    then
        return
    end

    -- Interface

    local OBSIDIAN_REPO = "https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/"
    local Library = Runtime.download(OBSIDIAN_REPO .. "Library.lua", true)
    if type(Library) ~= "table" or type(Library.CreateWindow) ~= "function" then
        return
    end
    Runtime.unload = function()
        pcall(Library.Unload, Library)
        Runtime.stop()
    end
    local ThemeManager = nil
    pcall(function()
        ThemeManager = Runtime.download(OBSIDIAN_REPO .. "addons/ThemeManager.lua", false)
    end)

    local ZephyrMark = "rbxthumb://type=Asset&id=89616857457936&w=420&h=420"
    local ZephyrPalette = {
        BackgroundColor = Color3.fromRGB(18, 21, 24),
        MainColor = Color3.fromRGB(26, 31, 35),
        AccentColor = Color3.fromRGB(112, 218, 181),
        OutlineColor = Color3.fromRGB(53, 63, 68),
        FontColor = Color3.fromRGB(235, 241, 244),
    }
    for key, color in pairs(ZephyrPalette) do
        Library.Scheme[key] = color
    end
    local Window = Library:CreateWindow({
        Title = "ZEPHYR",
        Footer = "HYPERSHOT",
        Icon = ZephyrMark,
        IconSize = UDim2.fromOffset(34, 34),
        Size = UDim2.fromOffset(880, 650),
        Font = Enum.Font.Gotham,
        CornerRadius = 7,
        NotifySide = "Right",
        ShowCustomCursor = false,
        ShowMobileButtons = true,
        EnableSidebarResize = true,
        MinSidebarWidth = 170,
        SidebarCompactWidth = 56,
        ToggleKeybind = Enum.KeyCode.Insert,
    })
    for object in pairs(Library.Registry) do
        if object:IsA("ImageLabel") and object.Image == ZephyrMark then
            object.BackgroundTransparency = 0
            object.BackgroundColor3 = Color3.fromRGB(230, 239, 235)
            object.ScaleType = Enum.ScaleType.Fit
            local rounding = Instance.new("UICorner")
            rounding.CornerRadius = UDim.new(0, 6)
            rounding.Parent = object
        end
    end

    local Players = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Lighting = game:GetService("Lighting")
    local TweenService = game:GetService("TweenService")
    local HttpService = game:GetService("HttpService")

    local LocalPlayer = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera
    local GlobalStuff = nil
    local GlobalStuffSource
    Runtime.connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), function()
        Camera = Workspace.CurrentCamera
    end)

    local function getGlobalStuff()
        local modules = ReplicatedStorage:FindFirstChild("Modules")
        local globalStuffModule = modules and modules:FindFirstChild("GlobalStuff")
        if not globalStuffModule then
            return nil
        end
        if GlobalStuffSource == globalStuffModule and GlobalStuff then
            return GlobalStuff
        end
        local result = Runtime.module(globalStuffModule)
        if type(result) == "table" then
            GlobalStuffSource = globalStuffModule
            GlobalStuff = result
            return result
        end

        return nil
    end

    local function getMapRayTargets()
        local map = Workspace:FindFirstChild("Map")
        if map then
            return { map }
        end

        local maps = Workspace:FindFirstChild("Maps")
        if maps then
            local targets = {}
            for _, child in ipairs(maps:GetChildren()) do
                if child:IsA("Model") or child:IsA("Folder") then
                    table.insert(targets, child)
                end
            end
            if #targets > 0 then
                return targets
            end
        end

        local globalStuff = getGlobalStuff()
        if globalStuff and type(globalStuff.GetMap) == "function" then
            local ok, result = pcall(function()
                return globalStuff:GetMap()
            end)
            if ok and result then
                return { result }
            end
        end

        return nil
    end

    local IsMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    local IsPC = not IsMobile
    local CompatUnpack = table.unpack or unpack

    -- Tabs

    local UsedOptionIds = {}
    local RestoreHypershotSettings

    local function optionId(prefix, label)
        local base = tostring(prefix .. "_" .. label):gsub("[^%w_]", "_"):gsub("_+", "_")
        if base:match("^%d") then
            base = "_" .. base
        end
        local id = base
        local n = 2
        while UsedOptionIds[id] do
            id = base .. "_" .. tostring(n)
            n += 1
        end
        UsedOptionIds[id] = true
        return id
    end

    local function roundingFor(...)
        local values = { ... }
        for _, value in ipairs(values) do
            if type(value) == "number" and value % 1 ~= 0 then
                return 2
            end
        end
        return 0
    end

    local function safeCallback(callback, ...)
        if not Runtime.alive or type(callback) ~= "function" then
            return false
        end
        local thread = coroutine.running()
        local alreadyTracked = Runtime.threads[thread]
        Runtime.threads[thread] = true
        local ok, err = pcall(callback, ...)
        if not alreadyTracked then
            Runtime.threads[thread] = nil
        end
        if not ok then
            Runtime.record("UI callback", err)
        end
        return ok, err
    end

    local SectionRules = {
        Combat = {
            { "Rage", { "triggerbot", "kill all", "bot mode", "bots only", "farm", "rage" } },
            {
                "Aim",
                { "silent", "aimbot", "aim assist", "fov", "hitchance", "headshot", "body", "crosshair", "wall check" },
            },
            { "Weapon", { "recoil", "spread", "scope", "reload", "ammo", "firerate", "fire rate", "tank" } },
            Default = "Hitbox",
        },
        ESP = {
            {
                "Players",
                { "box", "health", "name", "distance", "skeleton", "head", "chams", "attribute", "detail", "text" },
            },
            { "Objects", { "croc", "rc car" } },
            Default = "Players",
        },
        Player = {
            { "Movement", { "walk", "speed", "fly", "jump" } },
            { "Survival", { "respawn", "revive", "name", "arm" } },
            Default = "Survival",
        },
        Visuals = {
            { "World", { "sky", "map", "dark", "purple", "galaxy", "fov" } },
            { "Effects", { "kill sound", "rainbow", "bullet" } },
            Default = "Effects",
        },
        Misc = {
            { "Shop", { "shop", "sniper", "coin", "gem" } },
            { "Utility", { "heal", "barrier", "bombardino" } },
            Default = "Utility",
        },
        Unlocks = {
            { "Inventory", { "skin", "weapon", "ability", "passive", "vfx", "icon" } },
            { "Profile", { "spoof", "streak", "title", "level" } },
            Default = "Inventory",
        },
        Colors = {
            { "ESP Colors", { "esp", "name", "chams", "croc", "rc car" } },
            { "Player Colors", { "arm" } },
            Default = "ESP Colors",
        },
        UI = {
            { "Menu", { "menu", "visibility", "toggle", "keybind", "insert" } },
            Default = "Menu",
        },
    }

    local function createObsidianTab(name, icon)
        local tab = Window:AddTab(name, icon)
        local wrapper = { Name = name, Tab = tab, Groups = {} }

        function wrapper:GetGroup(label)
            label = label or "Main"
            if self.Groups[label] then
                return self.Groups[label]
            end
            local count = 0
            for _ in pairs(self.Groups) do
                count += 1
            end
            local group
            local combatLeft = { Aim = true, Hitbox = true }
            if (self.Name == "Combat" and combatLeft[label]) or (self.Name ~= "Combat" and count % 2 == 0) then
                group = self.Tab:AddLeftGroupbox(label)
            else
                group = self.Tab:AddRightGroupbox(label)
            end
            self.Groups[label] = group
            return group
        end

        function wrapper:PickGroup(label)
            local lower = string.lower(tostring(label or ""))
            local rules = SectionRules[self.Name]
            if type(rules) == "table" then
                for _, rule in ipairs(rules) do
                    for _, word in ipairs(rule[2]) do
                        if string.find(lower, word, 1, true) then
                            return self:GetGroup(rule[1])
                        end
                    end
                end
                return self:GetGroup(rules.Default or "Main")
            end
            return self:GetGroup("Main")
        end

        function wrapper:AddToggle(label, default, callback)
            local displayNames = {
                ["HBE"] = "Hitbox expander",
                ["Triggerbot (While Aiming In)"] = "Triggerbot (while aiming)",
                ["Kill All [BAN RISK]"] = "Kill All",
                ["Bot Mode [BAN RISK]"] = "Include bots",
                ["Bots Only Mode [BAN RISK]"] = "Bots only",
                ["Auto Farm Mode [BAN RISK]"] = "Auto Farm",
                ["Rage Mode [PISTOL] [BAN RISK]"] = "Rage (pistol)",
            }
            local risk = tostring(label):find("[BAN RISK]", 1, true) ~= nil
            local toggle = self:PickGroup(label):AddToggle(optionId("Toggle_" .. self.Name, label), {
                Text = displayNames[label] or tostring(label),
                Default = default == true,
                Risky = risk,
                Tooltip = risk and "High-risk feature. May result in a game ban." or nil,
            })
            local reverting = false
            toggle:OnChanged(function()
                if reverting or not Runtime.alive then
                    return
                end
                local requested = toggle.Value
                local ok = safeCallback(callback, requested)
                if not ok and requested and toggle.Value then
                    safeCallback(callback, false)
                    reverting = true
                    pcall(toggle.SetValue, toggle, false)
                    reverting = false
                end
            end)
            return toggle
        end

        function wrapper:AddSlider(label, minValue, maxValue, default, callback)
            minValue = tonumber(minValue) or 0
            maxValue = tonumber(maxValue) or minValue + 1
            default = tonumber(default) or minValue
            if maxValue <= minValue then
                maxValue = minValue + 1
            end
            if default < minValue then
                default = minValue
            elseif default > maxValue then
                maxValue = default
            end
            local slider = self:PickGroup(label):AddSlider(optionId("Slider_" .. self.Name, label), {
                Text = tostring(label),
                Default = default,
                Min = minValue,
                Max = maxValue,
                Rounding = roundingFor(minValue, maxValue, default),
            })
            slider:OnChanged(function(value)
                safeCallback(callback, value)
            end)
            return slider
        end

        function wrapper:AddDropdown(label, values, default, callback)
            local defaultIndex = default
            if type(default) ~= "number" and type(values) == "table" then
                defaultIndex = 1
                for i, value in ipairs(values) do
                    if value == default then
                        defaultIndex = i
                        break
                    end
                end
            end
            local dropdown = self:PickGroup(label):AddDropdown(optionId("Dropdown_" .. self.Name, label), {
                Text = tostring(label),
                Values = values or {},
                Default = defaultIndex,
                Multi = false,
            })
            dropdown:OnChanged(function(value)
                safeCallback(callback, value)
            end)
            return dropdown
        end

        function wrapper:AddInput(label, placeholder, callback)
            local input = self:PickGroup(label):AddInput(optionId("Input_" .. self.Name, label), {
                Text = tostring(label),
                Placeholder = tostring(placeholder or ""),
                Default = "",
            })
            input:OnChanged(function(value)
                safeCallback(callback, value)
            end)
            return input
        end

        function wrapper:AddButton(label, description, callback)
            local group = self:PickGroup(label)
            if description and description ~= "" then
                group:AddLabel({ Text = tostring(description), DoesWrap = true })
            end
            return group:AddButton({
                Text = tostring(label),
                Func = function()
                    safeCallback(callback)
                end,
            })
        end

        function wrapper:AddKeybind(label, default, callback)
            local labelObject = self:PickGroup(label):AddLabel({ Text = tostring(label), DoesWrap = false })
            local keybind = labelObject:AddKeyPicker(optionId("Keybind_" .. self.Name, label), {
                Text = tostring(label),
                Default = tostring(default or "None"),
                Mode = "Toggle",
            })
            keybind:OnClick(function()
                safeCallback(callback)
            end)
            return keybind
        end

        return wrapper
    end

    local Tabs = {
        Combat = createObsidianTab("Combat", "crosshair"),
        ESP = createObsidianTab("ESP", "eye"),
        Player = createObsidianTab("Player", "user"),
        Visuals = createObsidianTab("Visuals", "palette"),
        Misc = createObsidianTab("Misc", "wrench"),
        Unlocks = createObsidianTab("Unlocks", "lock-open"),
        Colors = createObsidianTab("Colors", "paintbrush"),
        UI = createObsidianTab("UI", "settings"),
    }

    if ThemeManager then
        pcall(function()
            ThemeManager:SetLibrary(Library)
            ThemeManager:SetFolder("Zephyr/Hypershot")
            local theme = table.clone(ZephyrPalette)
            theme.FontFace = Enum.Font.Gotham
            ThemeManager:SetDefaultTheme(theme)
            ThemeManager:ApplyToTab(Tabs.UI.Tab)
            ThemeManager:LoadDefault()
        end)
    end
    Tabs.UI:GetGroup("Appearance"):AddButton({
        Text = "Zephyr theme",
        Func = function()
            for key, color in pairs(ZephyrPalette) do
                Library.Scheme[key] = color
            end
            Library:SetFont(Enum.Font.Gotham)
            Library:UpdateColorsUsingRegistry()
        end,
    })

    if IsPC then
        local menuVisibleToggle = nil
        local syncingMenuVisibleToggle = false

        local function setMenuVisible(value)
            value = value == true
            pcall(function()
                Library:Toggle(value)
            end)
        end

        local function syncMenuVisibleToggle()
            if not menuVisibleToggle or type(menuVisibleToggle.SetValue) ~= "function" then
                return
            end
            local visible = Library.Toggled == true
            if menuVisibleToggle.Value == visible then
                return
            end
            syncingMenuVisibleToggle = true
            pcall(function()
                menuVisibleToggle:SetValue(visible)
            end)
            syncingMenuVisibleToggle = false
        end

        Tabs.UI:GetGroup("Menu"):AddLabel({
            Text = "Press Insert to hide/show Zephyr. You can change the key below.",
            DoesWrap = true,
        })

        menuVisibleToggle = Tabs.UI:AddToggle("Menu Visible", true, function(value)
            if syncingMenuVisibleToggle then
                return
            end
            setMenuVisible(value)
            task.defer(syncMenuVisibleToggle)
        end)

        local keyLabel = Tabs.UI:GetGroup("Menu"):AddLabel({
            Text = "Menu Toggle Key",
            DoesWrap = false,
        })
        local menuKeyPicker = keyLabel:AddKeyPicker(optionId("Keybind_UI", "Menu Toggle Key"), {
            Text = "Menu Toggle Key",
            Default = "Insert",
            Mode = "Toggle",
            ChangedCallback = function(keyCode)
                if typeof(keyCode) == "EnumItem" and keyCode.EnumType == Enum.KeyCode then
                    Library.ToggleKeybind = keyCode
                end
            end,
        })
        if menuKeyPicker and type(menuKeyPicker.OnChanged) == "function" then
            menuKeyPicker:OnChanged(function(keyCode)
                if typeof(keyCode) == "EnumItem" and keyCode.EnumType == Enum.KeyCode then
                    Library.ToggleKeybind = keyCode
                end
            end)
        end

        Library.ToggleKeybind = Enum.KeyCode.Insert
        Runtime.connect(UserInputService.InputBegan, function(input, gameProcessed)
            if gameProcessed or UserInputService:GetFocusedTextBox() then
                return
            end
            if input.KeyCode == Library.ToggleKeybind then
                task.defer(syncMenuVisibleToggle)
            end
        end)
    end

    Tabs.Main = Tabs.Combat
    Tabs.Extra = Tabs.Misc

    local function safeFindFirstChild(parent, name)
        if not parent then
            return nil
        end
        local ok, r = pcall(function()
            return parent:FindFirstChild(name)
        end)
        return ok and r or nil
    end

    local function safeWaitForChild(parent, name, timeout)
        if not parent then
            return nil
        end
        return Runtime.waitFor(function()
            return parent:FindFirstChild(name)
        end, timeout or 20)
    end

    local function requireSafe(module)
        if type(require) ~= "function" or not module or not module:IsA("ModuleScript") then
            return nil
        end
        local ok, result = pcall(require, module)
        return ok and result or nil
    end

    local function getControllerSharedModule()
        local playerGui = safeFindFirstChild(LocalPlayer, "PlayerGui")
        local controllerGui = playerGui and safeFindFirstChild(playerGui, "ControllerGUI")
        local newMainLocal = controllerGui and safeFindFirstChild(controllerGui, "NewMainLocal")
        local shared = newMainLocal and safeFindFirstChild(newMainLocal, "Shared")
        if shared then
            return shared
        end

        local controllerStuff = safeFindFirstChild(ReplicatedStorage, "ControllerStuff")
        local replicatedMain = controllerStuff and safeFindFirstChild(controllerStuff, "NewMainLocal")
        return replicatedMain and safeFindFirstChild(replicatedMain, "Shared")
    end

    local function getControllerShared()
        return Runtime.module(getControllerSharedModule())
    end

    local function getControllerNewMainLocal()
        local playerGui = safeFindFirstChild(LocalPlayer, "PlayerGui")
        local controllerGui = playerGui and safeFindFirstChild(playerGui, "ControllerGUI")
        local newMainLocal = controllerGui and safeFindFirstChild(controllerGui, "NewMainLocal")
        if newMainLocal then
            return newMainLocal
        end

        local controllerStuff = safeFindFirstChild(ReplicatedStorage, "ControllerStuff")
        return controllerStuff and safeFindFirstChild(controllerStuff, "NewMainLocal")
    end

    do
        local file = "ZephyrHypershot_" .. tostring(LocalPlayer.UserId) .. ".json"
        local ready, stopped, revision = false, false, 0
        local entries, byId = {}, {}
        local saved, lastWritten
        local group = Tabs.UI:GetGroup("Preferences")
        local status = group:AddLabel({ Text = "Settings save automatically", DoesWrap = true })
        local runtimeStatus = group:AddLabel({ Text = "Runtime ready", DoesWrap = true })
        Runtime.status = function(context)
            runtimeStatus:SetText("Runtime: " .. tostring(context) .. " unavailable; console logging off")
        end
        local available = type(readfile) == "function" and type(writefile) == "function"
        local function ignored(id)
            return id == "Toggle_UI_Menu_Visible" or id:sub(1, 13) == "ThemeManager_"
        end
        if available then
            local ok, raw = pcall(readfile, file)
            if ok then
                local decoded, data = pcall(HttpService.JSONDecode, HttpService, raw)
                if
                    decoded
                    and type(data) == "table"
                    and data.version == 1
                    and data.userId == LocalPlayer.UserId
                    and type(data.values) == "table"
                then
                    saved = data.values
                else
                    status:SetText("Saved settings invalid; using defaults")
                end
            end
        else
            status:SetText("Session only: file saving unavailable")
        end
        local function encode(control)
            local kind = control.Type
            if kind == "Toggle" or kind == "Slider" or kind == "Dropdown" or kind == "Input" then
                return { kind = kind, value = control.Value }
            elseif kind == "KeyPicker" then
                return { kind = kind, value = control.Value, mode = control.Mode, modifiers = control.Modifiers }
            elseif kind == "ColorPicker" then
                return { kind = kind, value = control.Value:ToHex(), transparency = control.Transparency }
            end
        end
        local function save()
            if not available or not ready or stopped then
                return
            end
            local ok, err = pcall(function()
                local values = {}
                for _, entry in ipairs(entries) do
                    values[entry.id] = encode(entry.control)
                end
                local raw = HttpService:JSONEncode({ version = 1, userId = LocalPlayer.UserId, values = values })
                if raw ~= lastWritten then
                    writefile(file, raw)
                    lastWritten = raw
                end
            end)
            status:SetText(ok and "Settings saved automatically" or "Could not save settings")
            if not ok then
                warn("[Zephyr Hypershot] Settings: " .. tostring(err))
            end
        end
        local function changed()
            if not ready or stopped or not available then
                return
            end
            revision += 1
            local current = revision
            task.delay(0.6, function()
                if revision == current then
                    save()
                end
            end)
        end
        RestoreHypershotSettings = function()
            for _, controls in ipairs({ Library.Options, Library.Toggles }) do
                for id, control in pairs(controls) do
                    if type(id) == "string" and not ignored(id) and not byId[id] and encode(control) then
                        local entry = { id = id, control = control }
                        entries[#entries + 1], byId[id] = entry, entry
                        for _, method in ipairs({ "SetValue", "SetValueRGB" }) do
                            local original = control[method]
                            if type(original) == "function" then
                                control[method] = function(self, ...)
                                    local result = table.pack(original(self, ...))
                                    changed()
                                    return table.unpack(result, 1, result.n)
                                end
                            end
                        end
                        local original = control.RunChanged
                        if type(original) == "function" then
                            control.RunChanged = function(self, ...)
                                local result = table.pack(original(self, ...))
                                changed()
                                return table.unpack(result, 1, result.n)
                            end
                        end
                    end
                end
            end
            table.sort(entries, function(a, b)
                local aToggle, bToggle = a.control.Type == "Toggle", b.control.Type == "Toggle"
                if aToggle ~= bToggle then
                    return not aToggle
                end
                return a.id < b.id
            end)
            local failures = 0
            for _, entry in ipairs(entries) do
                local control, data = entry.control, saved and saved[entry.id]
                if type(data) ~= "table" or data.kind ~= control.Type then
                    continue
                end
                local ok = pcall(function()
                    local value, kind = data.value, data.kind
                    if kind == "Toggle" and type(value) == "boolean" then
                        control:SetValue(value)
                    elseif
                        kind == "Slider"
                        and type(value) == "number"
                        and value == value
                        and math.abs(value) < math.huge
                    then
                        control:SetValue(math.clamp(value, control.Min, control.Max))
                    elseif kind == "Input" and type(value) == "string" then
                        control:SetValue(value)
                    elseif kind == "Dropdown" and type(value) == "string" and table.find(control.Values, value) then
                        control:SetValue(value)
                    elseif
                        kind == "KeyPicker"
                        and type(value) == "string"
                        and table.find({ "Toggle", "Hold", "Always" }, data.mode)
                    then
                        control:SetValue({ value, data.mode, type(data.modifiers) == "table" and data.modifiers or {} })
                    elseif kind == "ColorPicker" and type(value) == "string" and value:match("^%x%x%x%x%x%x$") then
                        control:SetValueRGB(
                            Color3.fromHex(value),
                            type(data.transparency) == "number" and math.clamp(data.transparency, 0, 1) or 0
                        )
                    end
                end)
                if not ok then
                    failures += 1
                end
            end
            ready = true
            if available then
                status:SetText(
                    failures > 0 and "Some saved settings could not be restored"
                        or saved and "Previous settings restored"
                        or "Settings save automatically"
                )
                if failures == 0 then
                    changed()
                end
            end
        end
        -- Save before unload resets the toggles.
        local originalUnload = Library.Unload
        Library.Unload = function(self, ...)
            save()
            stopped = true
            revision += 1
            local result = table.pack(pcall(originalUnload, self, ...))
            Runtime.stop()
            if not result[1] then
                Runtime.record("Unload", result[2])
                return
            end
            return table.unpack(result, 2, result.n)
        end
    end

    local PRESET_PURPLE = Color3.fromRGB(176, 88, 255)
    local PRESET_SOFT_PURPLE = Color3.fromRGB(224, 205, 255)
    local FirstRunPreset = false

    pcall(function()
        if type(isfile) ~= "function" or type(writefile) ~= "function" then
            FirstRunPreset = true
            return
        end

        local folder = "Zephyr"
        local marker = folder .. "/HypershotPurplePreset.json"
        local presetVersion = 2
        local shouldApplyPreset = not isfile(marker)

        if not shouldApplyPreset and type(readfile) == "function" then
            local ok, data = pcall(function()
                return HttpService:JSONDecode(readfile(marker))
            end)
            if ok and type(data) == "table" and tonumber(data.version) and tonumber(data.version) < presetVersion then
                shouldApplyPreset = true
            elseif not ok or type(data) ~= "table" or not tonumber(data.version) then
                shouldApplyPreset = true
            end
        end

        if shouldApplyPreset then
            FirstRunPreset = true
            if type(makefolder) == "function" then
                if type(isfolder) ~= "function" or not isfolder(folder) then
                    pcall(makefolder, folder)
                end
            end
            writefile(
                marker,
                HttpService:JSONEncode({
                    version = presetVersion,
                    preset = "Purple Legit",
                    purpleMap = true,
                    createdAt = os.time and os.time() or 0,
                })
            )
        end
    end)

    -- Hitboxes

    local HBEEnabled = false
    local HBEHidden = false
    _G.BodySize = 10

    local function expandBody(model, scale)
        if not model or not model:IsA("Model") then
            return
        end
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp and model:FindFirstChild("EnemyHighlight") then
            hrp.Size = Vector3.new(scale, scale, scale)
            hrp.CanCollide = false
            if HBEHidden then
                hrp.Transparency = 1
                hrp.Material = Enum.Material.Plastic
                hrp.BrickColor = BrickColor.new("Medium stone grey")
            else
                hrp.Transparency = 0.35
                hrp.BrickColor = BrickColor.new("Bright red")
                hrp.Material = Enum.Material.Neon
            end
        end
    end

    local function resetBody(model)
        if not model or not model:IsA("Model") then
            return
        end
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp and model:FindFirstChild("EnemyHighlight") then
            hrp.Size = Vector3.new(2, 2, 1)
            hrp.Transparency = 1
            hrp.BrickColor = BrickColor.new("Medium stone grey")
            hrp.Material = Enum.Material.Plastic
            hrp.CanCollide = true
        end
    end

    local _hbeChildConn = nil

    local function startHBELoop()
        task.spawn(function()
            while HBEEnabled do
                for _, model in ipairs(Workspace:GetChildren()) do
                    if model:IsA("Model") then
                        pcall(expandBody, model, _G.BodySize)
                    end
                end
                task.wait(0.5)
            end
        end)
    end

    Tabs.Combat:AddToggle("HBE", false, function(value)
        HBEEnabled = value
        if value then
            for _, model in ipairs(Workspace:GetChildren()) do
                if model:IsA("Model") then
                    pcall(expandBody, model, _G.BodySize)
                end
            end
            if _hbeChildConn then
                _hbeChildConn:Disconnect()
            end
            _hbeChildConn = Runtime.connect(Workspace.ChildAdded, function(m)
                if HBEEnabled and m:IsA("Model") then
                    task.wait(0.1)
                    pcall(expandBody, m, _G.BodySize)
                end
            end)
            startHBELoop()
        else
            if _hbeChildConn then
                _hbeChildConn:Disconnect()
                _hbeChildConn = nil
            end
            for _, model in ipairs(Workspace:GetChildren()) do
                if model:IsA("Model") then
                    pcall(resetBody, model)
                end
            end
        end
    end)

    Tabs.Combat:AddToggle("Hide Hitbox", false, function(value)
        HBEHidden = value
    end)

    Tabs.Combat:AddSlider("Hitbox Size", 1, 20, 10, function(value)
        _G.BodySize = value
    end)

    -- Silent aim

    local SilentAimActive = FirstRunPreset
    local fovEnabled = true
    local fovSize = FirstRunPreset and 115 or 100
    local hitchance = FirstRunPreset and 82 or 75
    local maxDistance = FirstRunPreset and 650 or 1000
    local closeToCrosshair = false
    local headshotChance = FirstRunPreset and 10 or 15
    local bodyChance = FirstRunPreset and 90 or 85
    local currentTarget = nil
    local wallCheckEnabled = true
    local silentAimLoopRunning = false

    local fovCircle = nil
    if IsPC then
        fovCircle = Drawing.new("Circle")
        fovCircle.Color = FirstRunPreset and PRESET_PURPLE or Color3.new(1, 1, 1)
        fovCircle.Thickness = 1
        fovCircle.NumSides = 100
        fovCircle.Radius = fovSize
        fovCircle.Filled = false
        fovCircle.Visible = fovEnabled
    end

    local mobileFovGui = nil
    local mobileFovFrame = nil
    if IsMobile then
        mobileFovGui = Instance.new("ScreenGui")
        mobileFovGui.Name = "FovGui"
        mobileFovGui.ResetOnSpawn = false
        mobileFovGui.IgnoreGuiInset = true
        local ok = pcall(function()
            mobileFovGui.Parent = game:GetService("CoreGui")
        end)
        if not ok then
            mobileFovGui.Parent = safeWaitForChild(LocalPlayer, "PlayerGui", 20)
        end

        mobileFovFrame = Instance.new("Frame")
        mobileFovFrame.BackgroundTransparency = 1
        mobileFovFrame.BorderSizePixel = 0
        mobileFovFrame.AnchorPoint = Vector2.new(0.5, 0.5)
        mobileFovFrame.Parent = mobileFovGui

        local UICorner = Instance.new("UICorner")
        UICorner.CornerRadius = UDim.new(1, 0)
        UICorner.Parent = mobileFovFrame

        local UIStroke = Instance.new("UIStroke")
        UIStroke.Color = FirstRunPreset and PRESET_PURPLE or Color3.new(1, 1, 1)
        UIStroke.Thickness = 1.5
        UIStroke.Parent = mobileFovFrame
    end

    local function updateFOVCircle()
        if IsPC then
            if not fovCircle then
                return
            end
            local vp = Camera.ViewportSize
            fovCircle.Position = Vector2.new(vp.X / 2, vp.Y / 2)
            fovCircle.Radius = fovSize
            fovCircle.Visible = fovEnabled and SilentAimActive
        elseif IsMobile and mobileFovFrame then
            local vp = Camera.ViewportSize
            mobileFovFrame.Position = UDim2.new(0, vp.X / 2, 0, vp.Y / 2)
            mobileFovFrame.Size = UDim2.new(0, fovSize * 2, 0, fovSize * 2)
            mobileFovFrame.Visible = fovEnabled and SilentAimActive
        end
    end

    local function calcScreenDist(part)
        if not part then
            return math.huge
        end
        local vp = Camera:WorldToViewportPoint(part.Position)
        local c = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
        return (c - Vector2.new(vp.X, vp.Y)).Magnitude
    end

    local function isVisible(part)
        if not part then
            return false
        end
        local vp, on = Camera:WorldToViewportPoint(part.Position)
        return on and vp.Z > 0
    end

    local function isEnemy(model)
        return model ~= LocalPlayer.Character and model:FindFirstChild("EnemyHighlight") ~= nil
    end

    local function worldDist(target)
        if not target or not target:FindFirstChild("HumanoidRootPart") then
            return math.huge
        end
        local lc = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if lc then
            return (lc.Position - target.HumanoidRootPart.Position).Magnitude
        end
        return math.huge
    end

    local function getTargetParts(model)
        if not model then
            return {}
        end
        return {
            model:FindFirstChild("Head"),
            model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso"),
            model:FindFirstChild("HumanoidRootPart"),
        }
    end

    -- Only the active map should block this ray.
    local function hasLineOfSight(part)
        if not wallCheckEnabled then
            return true
        end
        if not part then
            return false
        end

        local origin = Camera.CFrame.Position
        local targetPos = part.Position
        local direction = targetPos - origin
        if direction.Magnitude <= 0 then
            return false
        end

        local mapTargets = getMapRayTargets()
        if mapTargets then
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Include
            params.FilterDescendantsInstances = mapTargets
            params.IgnoreWater = true

            return Workspace:Raycast(origin, direction, params) == nil
        end

        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local excludeList = {}
        if LocalPlayer.Character then
            table.insert(excludeList, LocalPlayer.Character)
        end
        if Workspace:FindFirstChild("IgnoreThese") then
            table.insert(excludeList, Workspace.IgnoreThese)
        end
        params.FilterDescendantsInstances = excludeList

        local result = Workspace:Raycast(origin, direction, params)
        return not result or result.Instance:IsDescendantOf(part.Parent)
    end

    local function getVisibleTargetPart(model)
        local closestPart, shortest = nil, math.huge

        for _, part in ipairs(getTargetParts(model)) do
            if part and isVisible(part) and hasLineOfSight(part) then
                local dist = calcScreenDist(part)
                if dist < shortest then
                    closestPart = part
                    shortest = dist
                end
            end
        end

        return closestPart, shortest
    end

    local function findClosestTarget()
        local closest, shortest = nil, math.huge
        local function check(model)
            if model:IsA("Model") and isEnemy(model) then
                local visiblePart, screenDist = getVisibleTargetPart(model)
                local hum = model:FindFirstChildOfClass("Humanoid")
                if
                    hum
                    and hum.Health > 0
                    and visiblePart
                    and screenDist <= fovSize
                    and worldDist(model) <= maxDistance
                then
                    if screenDist < shortest then
                        closest = model
                        shortest = screenDist
                    end
                end
            end
        end
        for _, m in ipairs(Workspace:GetChildren()) do
            check(m)
        end
        local mobs = Workspace:FindFirstChild("Mobs")
        if mobs then
            for _, m in ipairs(mobs:GetChildren()) do
                check(m)
            end
        end
        return closest
    end

    local function aimAtTarget(target)
        if not target then
            return
        end
        local head = target:FindFirstChild("Head")
        local body = target:FindFirstChild("UpperTorso") or target:FindFirstChild("Torso")
        local root = target:FindFirstChild("HumanoidRootPart")
        local part
        if closeToCrosshair then
            part = getVisibleTargetPart(target)
        else
            part = (math.random(1, headshotChance + bodyChance) <= headshotChance) and head or body
            if not (part and isVisible(part) and hasLineOfSight(part)) then
                part = getVisibleTargetPart(target) or body or head or root
            end
        end
        if part and isVisible(part) and hasLineOfSight(part) then
            Camera.CFrame = CFrame.new(Camera.CFrame.Position, part.Position)
        end
    end

    local function updateAim()
        if silentAimLoopRunning then
            return
        end
        silentAimLoopRunning = true
        while SilentAimActive do
            if math.random(0, 100) <= hitchance then
                currentTarget = findClosestTarget()
                if currentTarget then
                    aimAtTarget(currentTarget)
                end
            end
            task.wait()
        end
        silentAimLoopRunning = false
    end

    Runtime.connect(RunService.RenderStepped, updateFOVCircle)

    if SilentAimActive then
        task.spawn(updateAim)
    end

    Tabs.Combat:AddToggle("Silent Aim", SilentAimActive, function(v)
        SilentAimActive = v
        if v then
            task.spawn(updateAim)
        end
        updateFOVCircle()
    end)

    Tabs.Combat:AddToggle("FOV Circle Visibility", true, function(v)
        fovEnabled = v
        updateFOVCircle()
    end)

    Tabs.Combat:AddToggle("Wall Check", true, function(v)
        wallCheckEnabled = v
    end)
    Tabs.Combat:AddSlider("FOV Size", 10, 300, fovSize, function(v)
        fovSize = v
        updateFOVCircle()
    end)
    Tabs.Combat:AddSlider("Headshot %", 0, 100, headshotChance, function(v)
        headshotChance = v
        bodyChance = 100 - v
    end)
    Tabs.Combat:AddSlider("Body %", 0, 100, bodyChance, function(v)
        bodyChance = v
        headshotChance = 100 - v
    end)
    Tabs.Combat:AddSlider("Hitchance", 5, 100, hitchance, function(v)
        hitchance = v
    end)
    Tabs.Combat:AddToggle("Close to Crosshair Mode", false, function(v)
        closeToCrosshair = v
    end)
    Tabs.Combat:AddSlider("Max Distance", 50, 1000, maxDistance, function(v)
        maxDistance = v
    end)

    -- Aiming

    if IsPC then
        local AimbotConfig = {
            Enabled = false,
            AimKey = Enum.UserInputType.MouseButton2,
            FOVRadius = 100,
            Smoothness = 5,
            ShowFOV = false,
        }
        local AimbotTarget, AimbotHolding = nil, false

        local AimbotFOV = Drawing.new("Circle")
        AimbotFOV.Thickness = 2
        AimbotFOV.Radius = 100
        AimbotFOV.Color = Color3.new(1, 0, 0)
        AimbotFOV.Filled = false
        AimbotFOV.Visible = false

        local function isAimbotEnemy(char)
            if not char or char == LocalPlayer.Character then
                return false
            end
            local hum = char:FindFirstChildOfClass("Humanoid")
            return char:FindFirstChild("EnemyHighlight") and hum and hum.Health > 0
        end

        local function getAimbotTarget()
            local closest, closestDist = nil, AimbotConfig.FOVRadius
            local mouse = UserInputService:GetMouseLocation()
            local function check(model)
                if model:IsA("Model") and isAimbotEnemy(model) then
                    local head = model:FindFirstChild("Head")
                    if head then
                        local sp, on = Camera:WorldToViewportPoint(head.Position)
                        if on then
                            local d = (mouse - Vector2.new(sp.X, sp.Y)).Magnitude
                            if d < closestDist then
                                closestDist = d
                                closest = head
                            end
                        end
                    end
                end
            end
            for _, m in pairs(Workspace:GetChildren()) do
                check(m)
            end
            local mobs = Workspace:FindFirstChild("Mobs")
            if mobs then
                for _, m in pairs(mobs:GetChildren()) do
                    check(m)
                end
            end
            return closest
        end

        local function smoothAim(part)
            if not part then
                return
            end
            local sp = Camera:WorldToViewportPoint(part.Position)
            local mouse = UserInputService:GetMouseLocation()
            mousemoverel((sp.X - mouse.X) / AimbotConfig.Smoothness, (sp.Y - mouse.Y) / AimbotConfig.Smoothness)
        end

        Runtime.connect(RunService.RenderStepped, function()
            local mouse = UserInputService:GetMouseLocation()
            AimbotFOV.Position = Vector2.new(mouse.X, mouse.Y)
            AimbotFOV.Radius = AimbotConfig.FOVRadius
            AimbotFOV.Visible = AimbotConfig.ShowFOV
            if AimbotConfig.Enabled and AimbotHolding then
                if not AimbotTarget or not AimbotTarget.Parent then
                    AimbotTarget = getAimbotTarget()
                end
                if AimbotTarget then
                    smoothAim(AimbotTarget)
                end
            else
                AimbotTarget = nil
            end
        end)

        Runtime.connect(UserInputService.InputBegan, function(input)
            if input.UserInputType == AimbotConfig.AimKey or input.KeyCode == AimbotConfig.AimKey then
                AimbotHolding = true
            end
        end)
        Runtime.connect(UserInputService.InputEnded, function(input)
            if input.UserInputType == AimbotConfig.AimKey or input.KeyCode == AimbotConfig.AimKey then
                AimbotHolding = false
            end
        end)

        local TriggerbotEnabled = false

        local function getPartUnderMouse()
            local mouse = UserInputService:GetMouseLocation()
            local ray = Camera:ViewportPointToRay(mouse.X, mouse.Y)
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Blacklist
            params.FilterDescendantsInstances = { LocalPlayer.Character }
            local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
            return result and result.Instance or nil
        end

        Runtime.connect(RunService.Heartbeat, function()
            if not TriggerbotEnabled or not AimbotHolding then
                return
            end
            local part = getPartUnderMouse()
            if
                part
                and part.Parent
                and part.Parent:FindFirstChild("EnemyHighlight")
                and part.Parent ~= LocalPlayer.Character
            then
                mouse1press()
                task.wait()
                mouse1release()
            end
        end)

        Tabs.Combat:AddToggle("Enable Aimbot", false, function(v)
            AimbotConfig.Enabled = v
        end)
        Tabs.Combat:AddDropdown(
            "Aimbot Keybind",
            {
                "Left Mouse Button",
                "Right Mouse Button",
                "A",
                "B",
                "C",
                "D",
                "E",
                "F",
                "G",
                "H",
                "I",
                "J",
                "K",
                "L",
                "M",
                "N",
                "O",
                "P",
                "Q",
                "R",
                "S",
                "T",
                "U",
                "V",
                "W",
                "X",
                "Y",
                "Z",
                "Left Shift",
                "Right Shift",
                "Left Ctrl",
                "Right Ctrl",
                "Left Alt",
                "Right Alt",
            },
            "Right Mouse Button",
            function(sel)
                local map = {
                    ["Left Mouse Button"] = Enum.UserInputType.MouseButton1,
                    ["Right Mouse Button"] = Enum.UserInputType.MouseButton2,
                    ["Left Shift"] = Enum.KeyCode.LeftShift,
                    ["Right Shift"] = Enum.KeyCode.RightShift,
                    ["Left Ctrl"] = Enum.KeyCode.LeftControl,
                    ["Right Ctrl"] = Enum.KeyCode.RightControl,
                    ["Left Alt"] = Enum.KeyCode.LeftAlt,
                    ["Right Alt"] = Enum.KeyCode.RightAlt,
                }
                AimbotConfig.AimKey = map[sel] or Enum.KeyCode[sel]
            end
        )
        Tabs.Combat:AddSlider("Aimbot FOV", 50, 500, 100, function(v)
            AimbotConfig.FOVRadius = v
        end)
        Tabs.Combat:AddSlider("Aimbot Smoothness", 1, 20, 5, function(v)
            AimbotConfig.Smoothness = v
        end)
        Tabs.Combat:AddToggle("Show Aimbot FOV Circle", false, function(v)
            AimbotConfig.ShowFOV = v
        end)
        Tabs.Combat:AddToggle("Triggerbot (While Aiming In)", false, function(v)
            TriggerbotEnabled = v
        end)
    end

    -- Mobile aim assist

    if IsMobile then
        local menuLocal, sharedCoreData, settingsTable
        local aimAssistEnabled = false
        local aimAssistSensitivity = 10

        task.spawn(function()
            local playerGui = safeWaitForChild(LocalPlayer, "PlayerGui", 20)
            if not playerGui then
                return
            end
            while not menuLocal do
                menuLocal = playerGui:FindFirstChild("MenuUI") and playerGui.MenuUI:FindFirstChild("MenuLocal")
                task.wait(0.1)
            end
            while not sharedCoreData do
                local ok, r = pcall(function()
                    return require(menuLocal:FindFirstChild("Shared")).CoreData
                end)
                if ok then
                    sharedCoreData = r
                end
                task.wait(0.1)
            end
            settingsTable = sharedCoreData and sharedCoreData.Settings
        end)

        local function applyAimAssist()
            if settingsTable then
                settingsTable["Aim Assist"] = aimAssistEnabled and aimAssistSensitivity or 0
            end
        end

        Runtime.connect(LocalPlayer.CharacterAdded, function()
            task.wait(1)
            applyAimAssist()
        end)
        if LocalPlayer.Character then
            applyAimAssist()
        end

        Tabs.Player:AddToggle("Aim Assist", false, function(v)
            aimAssistEnabled = v
            applyAimAssist()
        end)
        Tabs.Player:AddSlider("Aim Assist Sensitivity", 1, 100, 10, function(v)
            aimAssistSensitivity = v
            if aimAssistEnabled then
                applyAimAssist()
            end
        end)
    end

    -- ESP

    local ESPManager = {
        Objects = {},
        Settings = {
            MaxDistance = FirstRunPreset and 225 or 150,
            DetailDistance = FirstRunPreset and 165 or 135,
            TextDistance = FirstRunPreset and 230 or 175,
            MinBoxHeight = 18,
            FarDot = {
                Enabled = false,
                Radius = 3,
                Color = FirstRunPreset and PRESET_PURPLE or Color3.fromRGB(255, 90, 90),
            },
            Box = {
                Enabled = FirstRunPreset,
                Style = "Corner",
                Color = FirstRunPreset and PRESET_PURPLE or Color3.fromRGB(255, 60, 60),
                Thickness = 1.5,
                CornerSize = 8,
            },
            HealthBar = {
                Enabled = FirstRunPreset,
                Position = "Side",
                Width = 3,
                FullColor = Color3.fromRGB(80, 255, 120),
                HalfColor = Color3.fromRGB(255, 210, 0),
                LowColor = Color3.fromRGB(255, 60, 60),
            },
            Name = {
                Enabled = FirstRunPreset,
                Size = 13,
                Color = FirstRunPreset and PRESET_SOFT_PURPLE or Color3.fromRGB(255, 255, 255),
                Font = 2,
            },
            Distance = {
                Enabled = FirstRunPreset,
                Size = 12,
                Color = FirstRunPreset and Color3.fromRGB(185, 155, 230) or Color3.fromRGB(200, 200, 200),
            },
            Skeleton = {
                Enabled = false,
                Color = FirstRunPreset and PRESET_PURPLE or Color3.fromRGB(255, 60, 60),
                Thickness = 1.2,
            },
            Head = { Enabled = false, Color = Color3.fromRGB(255, 255, 255), Thickness = 1.5 },
            Chams = {
                Enabled = FirstRunPreset,
                FillColor = FirstRunPreset and PRESET_PURPLE or Color3.fromRGB(255, 60, 60),
                OutlineColor = FirstRunPreset and PRESET_SOFT_PURPLE or Color3.fromRGB(255, 255, 255),
                FillTransparency = FirstRunPreset and 0.75 or 0.5,
            },
            Attributes = { Enabled = false },
        },
    }

    local function applyBoxColor(col)
        ESPManager.Settings.Box.Color = col
        ESPManager.Settings.Skeleton.Color = col
        ESPManager.Settings.FarDot.Color = col
        for _, e in pairs(ESPManager.Objects) do
            for _, d in ipairs({ e.Box, e.TLV, e.TLH, e.TRV, e.TRH, e.BLV, e.BLH, e.BRV, e.BRH }) do
                d.Color = col
            end
            for _, l in pairs(e.Skeleton) do
                l.Color = col
            end
            if e.FarDot then
                e.FarDot.Color = col
            end
        end
    end

    local function applyNameColor(col)
        ESPManager.Settings.Name.Color = col
        for _, e in pairs(ESPManager.Objects) do
            e.NameText.Color = col
        end
    end

    local function applyChamsColor(fill, outline)
        if fill then
            ESPManager.Settings.Chams.FillColor = fill
        end
        if outline then
            ESPManager.Settings.Chams.OutlineColor = outline
        end
    end

    local boxR, boxG, boxB = FirstRunPreset and 176 or 255, FirstRunPreset and 88 or 60, FirstRunPreset and 255 or 60
    local nameR, nameG, nameB =
        FirstRunPreset and 224 or 255, FirstRunPreset and 205 or 255, FirstRunPreset and 255 or 255
    local chamFR, chamFG, chamFB =
        FirstRunPreset and 176 or 255, FirstRunPreset and 88 or 60, FirstRunPreset and 255 or 60
    local chamOR, chamOG, chamOB =
        FirstRunPreset and 224 or 255, FirstRunPreset and 205 or 255, FirstRunPreset and 255 or 255

    local function IsEnemy(model)
        if not model or not model.Parent then
            return false
        end
        if not model:FindFirstChild("EnemyHighlight") then
            return false
        end
        return model ~= LocalPlayer.Character
    end

    local function GetHealthColor(h, max)
        local p = h / max
        if p > 0.6 then
            return ESPManager.Settings.HealthBar.FullColor
        elseif p > 0.3 then
            return ESPManager.Settings.HealthBar.HalfColor
        else
            return ESPManager.Settings.HealthBar.LowColor
        end
    end

    local function IsWithinDist(model)
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if not hrp then
            return false
        end
        return (hrp.Position - Camera.CFrame.Position).Magnitude <= ESPManager.Settings.MaxDistance
    end

    local BONE_DEFS = {
        Neck = { "Head", "HumanoidRootPart" },
        LeftArm = { "LeftUpperArm", "HumanoidRootPart" },
        RightArm = { "RightUpperArm", "HumanoidRootPart" },
        LeftForearm = { "LeftHand", "LeftUpperArm" },
        RightForearm = { "RightHand", "RightUpperArm" },
        LeftLeg = { "LeftUpperLeg", "HumanoidRootPart" },
        RightLeg = { "RightUpperLeg", "HumanoidRootPart" },
        LeftLower = { "LeftFoot", "LeftUpperLeg" },
        RightLower = { "RightFoot", "RightUpperLeg" },
    }

    function ESPManager:Create(model)
        if self.Objects[model] then
            return
        end
        local bc = self.Settings.Box.Color
        local e = {
            Model = model,
            CachedName = model.Name,
            CachedDistance = "",
            LastAttrUpdate = 0,
            AttrInterval = 0.12,
            Box = Drawing.new("Square"),
            TLV = Drawing.new("Line"),
            TLH = Drawing.new("Line"),
            TRV = Drawing.new("Line"),
            TRH = Drawing.new("Line"),
            BLV = Drawing.new("Line"),
            BLH = Drawing.new("Line"),
            BRV = Drawing.new("Line"),
            BRH = Drawing.new("Line"),
            HPBG = Drawing.new("Square"),
            HPBar = Drawing.new("Square"),
            NameText = Drawing.new("Text"),
            DistText = Drawing.new("Text"),
            AttrText = Drawing.new("Text"),
            HeadCircle = Drawing.new("Circle"),
            FarDot = Drawing.new("Circle"),
            Skeleton = {},
        }

        e.Box.Thickness = self.Settings.Box.Thickness
        e.Box.Filled = false
        e.Box.Visible = false
        e.Box.Color = bc
        e.Box.Transparency = 1

        for _, c in ipairs({ e.TLV, e.TLH, e.TRV, e.TRH, e.BLV, e.BLH, e.BRV, e.BRH }) do
            c.Thickness = self.Settings.Box.Thickness
            c.Visible = false
            c.Color = bc
            c.Transparency = 1
        end

        e.HPBG.Filled = true
        e.HPBG.Visible = false
        e.HPBG.Color = Color3.fromRGB(0, 0, 0)
        e.HPBG.Transparency = 0.55
        e.HPBar.Filled = true
        e.HPBar.Visible = false
        e.HPBar.Transparency = 1

        for _, t in ipairs({ e.NameText, e.DistText, e.AttrText }) do
            t.Center = true
            t.Outline = true
            t.Visible = false
            t.Transparency = 1
            t.Font = 2
        end
        e.NameText.Color = self.Settings.Name.Color
        e.NameText.Size = self.Settings.Name.Size
        e.NameText.Text = e.CachedName
        e.DistText.Color = self.Settings.Distance.Color
        e.DistText.Size = self.Settings.Distance.Size
        e.AttrText.Color = Color3.fromRGB(150, 210, 255)
        e.AttrText.Size = 11

        e.HeadCircle.Filled = false
        e.HeadCircle.Visible = false
        e.HeadCircle.NumSides = 32
        e.HeadCircle.Color = self.Settings.Head.Color
        e.HeadCircle.Thickness = self.Settings.Head.Thickness
        e.HeadCircle.Transparency = 1

        e.FarDot.Filled = true
        e.FarDot.Visible = false
        e.FarDot.NumSides = 20
        e.FarDot.Color = self.Settings.FarDot.Color
        e.FarDot.Radius = self.Settings.FarDot.Radius
        e.FarDot.Transparency = 0.9

        for key in pairs(BONE_DEFS) do
            local l = Drawing.new("Line")
            l.Thickness = self.Settings.Skeleton.Thickness
            l.Color = self.Settings.Skeleton.Color
            l.Visible = false
            l.Transparency = 1
            e.Skeleton[key] = l
        end

        self.Objects[model] = e
    end

    function ESPManager:Remove(model)
        local e = self.Objects[model]
        if not e then
            return
        end
        for _, v in ipairs({
            e.Box,
            e.TLV,
            e.TLH,
            e.TRV,
            e.TRH,
            e.BLV,
            e.BLH,
            e.BRV,
            e.BRH,
            e.HPBG,
            e.HPBar,
            e.NameText,
            e.DistText,
            e.AttrText,
            e.HeadCircle,
            e.FarDot,
        }) do
            v:Remove()
        end
        for _, l in pairs(e.Skeleton) do
            l:Remove()
        end
        self.Objects[model] = nil
    end

    local function HideAll(e)
        for _, v in ipairs({
            e.Box,
            e.TLV,
            e.TLH,
            e.TRV,
            e.TRH,
            e.BLV,
            e.BLH,
            e.BRV,
            e.BRH,
            e.HPBG,
            e.HPBar,
            e.NameText,
            e.DistText,
            e.AttrText,
            e.HeadCircle,
            e.FarDot,
        }) do
            v.Visible = false
        end
        for _, l in pairs(e.Skeleton) do
            l.Visible = false
        end
    end

    function ESPManager:AnyEnabled()
        local s = self.Settings
        return s.Box.Enabled
            or s.HealthBar.Enabled
            or s.Name.Enabled
            or s.Distance.Enabled
            or s.Skeleton.Enabled
            or s.Head.Enabled
            or s.Chams.Enabled
            or s.Attributes.Enabled
    end

    local function setDrawTransparency(drawObj, value)
        if drawObj then
            pcall(function()
                drawObj.Transparency = value
            end)
        end
    end

    local function shortenEspName(name, maxLen)
        name = tostring(name or "")
        maxLen = tonumber(maxLen) or 14
        if #name <= maxLen then
            return name
        end
        return name:sub(1, maxLen - 3) .. "..."
    end

    local function applyModelChams(model, settings)
        if not settings.Chams.Enabled then
            return
        end
        local hl = model:FindFirstChild("EnemyHighlight")
        if hl and hl:IsA("Highlight") then
            hl.FillColor = settings.Chams.FillColor
            hl.OutlineColor = settings.Chams.OutlineColor
            hl.FillTransparency = settings.Chams.FillTransparency
            hl.OutlineTransparency = 0
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        end
    end

    function ESPManager:Update(model, e)
        local hum = model:FindFirstChildOfClass("Humanoid")
        local hrp = model:FindFirstChild("HumanoidRootPart")
        local head = model:FindFirstChild("Head")

        if not hum or not hrp or not head or hum.Health <= 0 or not IsWithinDist(model) then
            HideAll(e)
            return
        end

        local rootPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
        if not onScreen then
            HideAll(e)
            return
        end
        local distance = (hrp.Position - Camera.CFrame.Position).Magnitude

        local headScreen = Camera:WorldToViewportPoint(head.Position + Vector3.new(0, head.Size.Y * 0.5, 0))
        local footScreen = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
        local rawTop = math.min(headScreen.Y, footScreen.Y)
        local rawBottom = math.max(headScreen.Y, footScreen.Y)
        local rawHeight = math.max(rawBottom - rawTop, 1)
        local tinyEsp = rawHeight < self.Settings.MinBoxHeight
        local height = tinyEsp and self.Settings.MinBoxHeight or rawHeight
        applyModelChams(model, self.Settings)

        e.FarDot.Visible = false

        local width = math.max(height * 0.55, 10)
        local bp = tinyEsp and Vector2.new(rootPos.X - width / 2, rootPos.Y - height / 2)
            or Vector2.new(rootPos.X - width / 2, rawTop)
        local bs = Vector2.new(width, height)
        local detailAllowed = distance <= self.Settings.DetailDistance and rawHeight >= 35
        local textAllowed = distance <= self.Settings.TextDistance and rawHeight >= 8
        local alpha = math.clamp(1 - ((distance / math.max(self.Settings.MaxDistance, 1)) * 0.35), 0.55, 1)

        if self.Settings.Box.Enabled then
            setDrawTransparency(e.Box, alpha)
            if self.Settings.Box.Style == "Normal" then
                e.Box.Position = bp
                e.Box.Size = bs
                e.Box.Visible = true
                for _, c in ipairs({ e.TLV, e.TLH, e.TRV, e.TRH, e.BLV, e.BLH, e.BRV, e.BRH }) do
                    c.Visible = false
                end
            else
                e.Box.Visible = false
                local cs = math.clamp(self.Settings.Box.CornerSize, 4, math.max(4, math.min(bs.X, bs.Y) * 0.33))
                e.TLV.From = bp
                e.TLV.To = Vector2.new(bp.X, bp.Y + cs)
                e.TLH.From = bp
                e.TLH.To = Vector2.new(bp.X + cs, bp.Y)
                e.TRV.From = Vector2.new(bp.X + bs.X, bp.Y)
                e.TRV.To = Vector2.new(bp.X + bs.X, bp.Y + cs)
                e.TRH.From = Vector2.new(bp.X + bs.X, bp.Y)
                e.TRH.To = Vector2.new(bp.X + bs.X - cs, bp.Y)
                e.BLV.From = Vector2.new(bp.X, bp.Y + bs.Y)
                e.BLV.To = Vector2.new(bp.X, bp.Y + bs.Y - cs)
                e.BLH.From = Vector2.new(bp.X, bp.Y + bs.Y)
                e.BLH.To = Vector2.new(bp.X + cs, bp.Y + bs.Y)
                e.BRV.From = Vector2.new(bp.X + bs.X, bp.Y + bs.Y)
                e.BRV.To = Vector2.new(bp.X + bs.X, bp.Y + bs.Y - cs)
                e.BRH.From = Vector2.new(bp.X + bs.X, bp.Y + bs.Y)
                e.BRH.To = Vector2.new(bp.X + bs.X - cs, bp.Y + bs.Y)
                for _, c in ipairs({ e.TLV, e.TLH, e.TRV, e.TRH, e.BLV, e.BLH, e.BRV, e.BRH }) do
                    setDrawTransparency(c, alpha)
                    c.Visible = true
                end
            end
        else
            e.Box.Visible = false
            for _, c in ipairs({ e.TLV, e.TLH, e.TRV, e.TRH, e.BLV, e.BLH, e.BRV, e.BRH }) do
                c.Visible = false
            end
        end

        if self.Settings.HealthBar.Enabled then
            local hp = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
            local col = GetHealthColor(hum.Health, hum.MaxHealth)
            if self.Settings.HealthBar.Position == "Side" then
                local bw = self.Settings.HealthBar.Width
                local bx = bp.X - bw - 4
                e.HPBG.Size = Vector2.new(bw, bs.Y)
                e.HPBG.Position = Vector2.new(bx, bp.Y)
                e.HPBG.Visible = true
                e.HPBar.Size = Vector2.new(bw, bs.Y * hp)
                e.HPBar.Position = Vector2.new(bx, bp.Y + bs.Y * (1 - hp))
                e.HPBar.Color = col
                e.HPBar.Visible = true
            else
                local bw = bs.X * 0.8
                local bh = 4
                local bx = bp.X + (bs.X - bw) / 2
                local by = bp.Y - 8
                e.HPBG.Size = Vector2.new(bw, bh)
                e.HPBG.Position = Vector2.new(bx, by)
                e.HPBG.Visible = true
                e.HPBar.Size = Vector2.new(bw * hp, bh)
                e.HPBar.Position = Vector2.new(bx, by)
                e.HPBar.Color = col
                e.HPBar.Visible = true
            end
        else
            e.HPBG.Visible = false
            e.HPBar.Visible = false
        end

        if self.Settings.Name.Enabled and textAllowed then
            local displayName = e.CachedName
            for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
                if p.Character == model then
                    displayName = p.DisplayName
                    break
                end
            end
            e.NameText.Text = shortenEspName(displayName, distance > 110 and 11 or 16)
            e.NameText.Position = Vector2.new(bp.X + bs.X / 2, bp.Y - 17)
            setDrawTransparency(e.NameText, alpha)
            e.NameText.Visible = true
        else
            e.NameText.Visible = false
        end

        if self.Settings.Distance.Enabled and textAllowed then
            local d = math.floor(distance)
            local dTx = d .. "m"
            if e.CachedDistance ~= dTx then
                e.CachedDistance = dTx
                e.DistText.Text = dTx
            end
            e.DistText.Position = Vector2.new(bp.X + bs.X / 2, bp.Y + bs.Y + 4)
            setDrawTransparency(e.DistText, alpha)
            e.DistText.Visible = true
        else
            e.DistText.Visible = false
        end

        if self.Settings.Head.Enabled and detailAllowed then
            local hsp, hon = Camera:WorldToViewportPoint(head.Position)
            if hon then
                local dist = (head.Position - Camera.CFrame.Position).Magnitude
                e.HeadCircle.Position = Vector2.new(hsp.X, hsp.Y)
                e.HeadCircle.Radius = math.clamp(520 / dist, 3, 14)
                setDrawTransparency(e.HeadCircle, alpha)
                e.HeadCircle.Visible = true
            else
                e.HeadCircle.Visible = false
            end
        else
            e.HeadCircle.Visible = false
        end

        if self.Settings.Skeleton.Enabled and detailAllowed then
            local function gsp(part)
                if not part then
                    return nil, false
                end
                local p, v = Camera:WorldToViewportPoint(part.Position)
                return Vector2.new(p.X, p.Y), v
            end
            for key, def in pairs(BONE_DEFS) do
                local cp, cv = gsp(model:FindFirstChild(def[1]))
                local pp, pv = gsp(model:FindFirstChild(def[2]))
                local line = e.Skeleton[key]
                if line then
                    if cv and pv then
                        line.From = pp
                        line.To = cp
                        line.Visible = true
                        setDrawTransparency(line, alpha)
                    else
                        line.Visible = false
                    end
                end
            end
        else
            for _, l in pairs(e.Skeleton) do
                l.Visible = false
            end
        end

        if self.Settings.Attributes.Enabled and detailAllowed and distance <= self.Settings.TextDistance then
            if tick() - e.LastAttrUpdate >= e.AttrInterval then
                e.LastAttrUpdate = tick()
                local attrs = {}
                for _, a in ipairs({ "Ability1", "Ability2", "Ability3", "Passive1", "Passive2", "Weapon1", "Weapon2" }) do
                    local v = model:GetAttribute(a)
                    if v then
                        table.insert(attrs, tostring(v))
                    end
                end
                e.AttrText.Text = #attrs > 0 and table.concat(attrs, " | ") or ""
            end
            if e.AttrText.Text ~= "" then
                e.AttrText.Position = Vector2.new(bp.X + bs.X / 2, bp.Y + bs.Y + 20)
                setDrawTransparency(e.AttrText, alpha)
                e.AttrText.Visible = true
            else
                e.AttrText.Visible = false
            end
        else
            e.AttrText.Visible = false
        end
    end

    function ESPManager:Scan()
        for model in pairs(self.Objects) do
            if not model or not model.Parent or not IsEnemy(model) then
                self:Remove(model)
            end
        end
        for _, m in ipairs(Workspace:GetChildren()) do
            if m:IsA("Model") and IsEnemy(m) and not self.Objects[m] then
                self:Create(m)
            end
        end
        local mobs = Workspace:FindFirstChild("Mobs")
        if mobs then
            for _, m in ipairs(mobs:GetChildren()) do
                if m:IsA("Model") and IsEnemy(m) and not self.Objects[m] then
                    self:Create(m)
                end
            end
        end
    end

    local lastScan = 0
    local espWasActive = false
    Runtime.connect(RunService.RenderStepped, function()
        if not ESPManager:AnyEnabled() then
            if espWasActive then
                for _, e in pairs(ESPManager.Objects) do
                    HideAll(e)
                end
            end
            espWasActive = false
            return
        end
        espWasActive = true
        if tick() - lastScan >= 1 then
            ESPManager:Scan()
            lastScan = tick()
        end
        for model, e in pairs(ESPManager.Objects) do
            ESPManager:Update(model, e)
        end
    end)

    Tabs.ESP:AddSlider("ESP Max Distance", 25, 500, ESPManager.Settings.MaxDistance, function(v)
        ESPManager.Settings.MaxDistance = v
    end)
    Tabs.ESP:AddSlider("ESP Detail Distance", 25, 350, ESPManager.Settings.DetailDistance, function(v)
        ESPManager.Settings.DetailDistance = v
    end)
    Tabs.ESP:AddSlider("ESP Text Distance", 25, 350, ESPManager.Settings.TextDistance, function(v)
        ESPManager.Settings.TextDistance = v
    end)

    Tabs.ESP:AddToggle("Box ESP", ESPManager.Settings.Box.Enabled, function(v)
        ESPManager.Settings.Box.Enabled = v
    end)
    Tabs.ESP:AddDropdown("Box Style", { "Normal", "Corner" }, "Corner", function(v)
        ESPManager.Settings.Box.Style = v
    end)
    Tabs.Colors:AddSlider("ESP R", 0, 255, boxR, function(v)
        boxR = v
        applyBoxColor(Color3.fromRGB(boxR, boxG, boxB))
    end)
    Tabs.Colors:AddSlider("ESP G", 0, 255, boxG, function(v)
        boxG = v
        applyBoxColor(Color3.fromRGB(boxR, boxG, boxB))
    end)
    Tabs.Colors:AddSlider("ESP B", 0, 255, boxB, function(v)
        boxB = v
        applyBoxColor(Color3.fromRGB(boxR, boxG, boxB))
    end)

    Tabs.ESP:AddToggle("Health Bar ESP", ESPManager.Settings.HealthBar.Enabled, function(v)
        ESPManager.Settings.HealthBar.Enabled = v
    end)
    Tabs.ESP:AddDropdown("Health Bar Position", { "Side", "Overhead" }, "Side", function(v)
        ESPManager.Settings.HealthBar.Position = v
    end)

    Tabs.ESP:AddToggle("Name ESP", ESPManager.Settings.Name.Enabled, function(v)
        ESPManager.Settings.Name.Enabled = v
    end)
    Tabs.Colors:AddSlider("Name R", 0, 255, nameR, function(v)
        nameR = v
        applyNameColor(Color3.fromRGB(nameR, nameG, nameB))
    end)
    Tabs.Colors:AddSlider("Name G", 0, 255, nameG, function(v)
        nameG = v
        applyNameColor(Color3.fromRGB(nameR, nameG, nameB))
    end)
    Tabs.Colors:AddSlider("Name B", 0, 255, nameB, function(v)
        nameB = v
        applyNameColor(Color3.fromRGB(nameR, nameG, nameB))
    end)

    Tabs.ESP:AddToggle("Distance ESP", ESPManager.Settings.Distance.Enabled, function(v)
        ESPManager.Settings.Distance.Enabled = v
    end)
    Tabs.ESP:AddToggle("Skeleton ESP", ESPManager.Settings.Skeleton.Enabled, function(v)
        ESPManager.Settings.Skeleton.Enabled = v
        if not v then
            for _, e in pairs(ESPManager.Objects) do
                for _, l in pairs(e.Skeleton) do
                    l.Visible = false
                end
            end
        end
    end)
    Tabs.ESP:AddToggle("Head ESP", ESPManager.Settings.Head.Enabled, function(v)
        ESPManager.Settings.Head.Enabled = v
    end)

    Tabs.ESP:AddToggle("Chams", ESPManager.Settings.Chams.Enabled, function(v)
        ESPManager.Settings.Chams.Enabled = v
    end)
    Tabs.Colors:AddSlider("Chams Fill R", 0, 255, chamFR, function(v)
        chamFR = v
        applyChamsColor(Color3.fromRGB(chamFR, chamFG, chamFB), nil)
    end)
    Tabs.Colors:AddSlider("Chams Fill G", 0, 255, chamFG, function(v)
        chamFG = v
        applyChamsColor(Color3.fromRGB(chamFR, chamFG, chamFB), nil)
    end)
    Tabs.Colors:AddSlider("Chams Fill B", 0, 255, chamFB, function(v)
        chamFB = v
        applyChamsColor(Color3.fromRGB(chamFR, chamFG, chamFB), nil)
    end)
    Tabs.Colors:AddSlider("Chams Outline R", 0, 255, chamOR, function(v)
        chamOR = v
        applyChamsColor(nil, Color3.fromRGB(chamOR, chamOG, chamOB))
    end)
    Tabs.Colors:AddSlider("Chams Outline G", 0, 255, chamOG, function(v)
        chamOG = v
        applyChamsColor(nil, Color3.fromRGB(chamOR, chamOG, chamOB))
    end)
    Tabs.Colors:AddSlider("Chams Outline B", 0, 255, chamOB, function(v)
        chamOB = v
        applyChamsColor(nil, Color3.fromRGB(chamOR, chamOG, chamOB))
    end)
    Tabs.ESP:AddSlider(
        "Chams Transparency",
        0,
        10,
        math.floor(ESPManager.Settings.Chams.FillTransparency * 10 + 0.5),
        function(v)
            ESPManager.Settings.Chams.FillTransparency = v / 10
        end
    )

    Tabs.ESP:AddToggle("Show Attributes ESP", ESPManager.Settings.Attributes.Enabled, function(v)
        ESPManager.Settings.Attributes.Enabled = v
    end)

    -- Crocodilo

    local CrocESPEnabled = false
    local trackedCrocs = {}
    local crocFillR, crocFillG, crocFillB = 30, 160, 255
    local crocEnemyR, crocEnemyG, crocEnemyB = 255, 120, 30

    local function isCroc(obj)
        local main = obj:FindFirstChild("Main")
        if not main then
            return false
        end
        return main:FindFirstChild("LinearVelocity") ~= nil
    end

    local function getCrocOwner(obj)
        return obj.Name:match("^(.+)__") or obj.Name
    end

    local function addCrocESP(plane)
        if trackedCrocs[plane] then
            return
        end
        task.wait(0.1)
        local main = plane:FindFirstChild("Main")
        if not main or not isCroc(plane) then
            return
        end

        local ownerName = getCrocOwner(plane)
        local isOwn = ownerName == LocalPlayer.Name
        local fillColor = isOwn and Color3.fromRGB(crocFillR, crocFillG, crocFillB)
            or Color3.fromRGB(crocEnemyR, crocEnemyG, crocEnemyB)

        local hl = Instance.new("Highlight")
        hl.FillColor = fillColor
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
        hl.FillTransparency = 0.3
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = plane

        local bb = Instance.new("BillboardGui")
        bb.Size = UDim2.new(0, 170, 0, 48)
        bb.StudsOffset = Vector3.new(0, 6, 0)
        bb.MaxDistance = 260
        bb.LightInfluence = 0
        bb.AlwaysOnTop = true
        bb.Parent = main

        local nl = Instance.new("TextLabel", bb)
        nl.Size = UDim2.new(1, 0, 0.4, 0)
        nl.BackgroundTransparency = 1
        nl.TextColor3 = fillColor
        nl.TextStrokeTransparency = 0
        nl.Font = Enum.Font.GothamBold
        nl.TextScaled = true
        nl.Text = ownerName .. "'s Bombardino"

        local dl = Instance.new("TextLabel", bb)
        dl.Name = "DistLabel"
        dl.Size = UDim2.new(1, 0, 0.3, 0)
        dl.Position = UDim2.new(0, 0, 0.4, 0)
        dl.BackgroundTransparency = 1
        dl.TextColor3 = Color3.fromRGB(255, 255, 255)
        dl.TextStrokeTransparency = 0
        dl.Font = Enum.Font.Gotham
        dl.TextScaled = true
        dl.Text = "-- studs"

        local sl = Instance.new("TextLabel", bb)
        sl.Name = "SpeedLabel"
        sl.Size = UDim2.new(1, 0, 0.3, 0)
        sl.Position = UDim2.new(0, 0, 0.7, 0)
        sl.BackgroundTransparency = 1
        sl.TextColor3 = Color3.fromRGB(255, 220, 80)
        sl.TextStrokeTransparency = 0
        sl.Font = Enum.Font.Gotham
        sl.TextScaled = true
        sl.Text = "speed: --"

        trackedCrocs[plane] = { hl = hl, bb = bb, main = main }
        Runtime.connect(plane.AncestryChanged, function()
            if not plane:IsDescendantOf(Workspace) then
                trackedCrocs[plane] = nil
            end
        end)
    end

    local function removeCrocESP(plane)
        local d = trackedCrocs[plane]
        if not d then
            return
        end
        if d.hl and d.hl.Parent then
            d.hl:Destroy()
        end
        if d.bb and d.bb.Parent then
            d.bb:Destroy()
        end
        trackedCrocs[plane] = nil
    end

    Runtime.connect(Workspace.ChildAdded, function(c)
        if CrocESPEnabled and isCroc(c) then
            task.spawn(addCrocESP, c)
        end
    end)

    local lastCrocEspUpdate = 0
    Runtime.connect(RunService.Heartbeat, function()
        if not CrocESPEnabled then
            return
        end
        if tick() - lastCrocEspUpdate < 0.15 then
            return
        end
        lastCrocEspUpdate = tick()
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then
            return
        end
        for plane, d in pairs(trackedCrocs) do
            if d.main and d.bb then
                pcall(function()
                    local dist = math.floor((d.main.Position - root.Position).Magnitude)
                    local dl = d.bb:FindFirstChild("DistLabel")
                    if dl then
                        dl.Text = dist .. " studs"
                    end
                    local lv = d.main:FindFirstChild("LinearVelocity")
                    local sl = d.bb:FindFirstChild("SpeedLabel")
                    if lv and sl then
                        local spd = math.floor(lv.VectorVelocity.Magnitude)
                        sl.Text = "speed: " .. spd .. (spd > 150 and " fast" or "")
                    end
                end)
            end
        end
    end)

    Tabs.ESP:AddToggle("Crocodilo ESP", false, function(v)
        CrocESPEnabled = v
        if v then
            for _, o in ipairs(Workspace:GetChildren()) do
                if isCroc(o) then
                    task.spawn(addCrocESP, o)
                end
            end
        else
            for p in pairs(trackedCrocs) do
                removeCrocESP(p)
            end
        end
    end)
    Tabs.Colors:AddSlider("Croc Own R", 0, 255, 30, function(v)
        crocFillR = v
    end)
    Tabs.Colors:AddSlider("Croc Own G", 0, 255, 160, function(v)
        crocFillG = v
    end)
    Tabs.Colors:AddSlider("Croc Own B", 0, 255, 255, function(v)
        crocFillB = v
    end)
    Tabs.Colors:AddSlider("Croc Enemy R", 0, 255, 255, function(v)
        crocEnemyR = v
    end)
    Tabs.Colors:AddSlider("Croc Enemy G", 0, 255, 120, function(v)
        crocEnemyG = v
    end)
    Tabs.Colors:AddSlider("Croc Enemy B", 0, 255, 30, function(v)
        crocEnemyB = v
    end)

    -- RC cars

    local RCCarESPEnabled = false
    local trackedTrucks = {}
    local truckR, truckG, truckB = 255, 50, 50

    local function addTruckESP(truck)
        if trackedTrucks[truck] then
            return
        end
        local ownerName = truck.Name:match("^(.+)__Truck$") or "Unknown"
        local primary = truck:FindFirstChild("Truck") or truck:FindFirstChildWhichIsA("BasePart")

        local hl = Instance.new("Highlight")
        hl.FillColor = Color3.fromRGB(truckR, truckG, truckB)
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
        hl.FillTransparency = 0.35
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = truck

        local bb
        if primary then
            bb = Instance.new("BillboardGui")
            bb.Size = UDim2.new(0, 150, 0, 42)
            bb.StudsOffset = Vector3.new(0, 4.5, 0)
            bb.MaxDistance = 240
            bb.LightInfluence = 0
            bb.AlwaysOnTop = true
            bb.Parent = primary

            local nl = Instance.new("TextLabel", bb)
            nl.Size = UDim2.new(1, 0, 0.5, 0)
            nl.BackgroundTransparency = 1
            nl.TextColor3 = Color3.fromRGB(truckR, truckG, truckB)
            nl.TextStrokeTransparency = 0
            nl.Font = Enum.Font.GothamBold
            nl.TextScaled = true
            nl.Text = ownerName .. "'s RC Bomb"

            local dl = Instance.new("TextLabel", bb)
            dl.Name = "DistLabel"
            dl.Size = UDim2.new(1, 0, 0.5, 0)
            dl.Position = UDim2.new(0, 0, 0.5, 0)
            dl.BackgroundTransparency = 1
            dl.TextColor3 = Color3.fromRGB(255, 255, 255)
            dl.TextStrokeTransparency = 0
            dl.Font = Enum.Font.Gotham
            dl.TextScaled = true
            dl.Text = "-- studs"
        end

        trackedTrucks[truck] = { hl = hl, bb = bb, primary = primary }
        Runtime.connect(truck.AncestryChanged, function()
            if not truck:IsDescendantOf(Workspace) then
                trackedTrucks[truck] = nil
            end
        end)
    end

    local function removeTruckESP(truck)
        local d = trackedTrucks[truck]
        if not d then
            return
        end
        if d.hl and d.hl.Parent then
            d.hl:Destroy()
        end
        if d.bb and d.bb.Parent then
            d.bb:Destroy()
        end
        trackedTrucks[truck] = nil
    end

    Runtime.connect(Workspace.ChildAdded, function(c)
        if RCCarESPEnabled and c.Name:match("__Truck$") then
            addTruckESP(c)
        end
    end)

    local lastTruckEspUpdate = 0
    Runtime.connect(RunService.Heartbeat, function()
        if not RCCarESPEnabled then
            return
        end
        if tick() - lastTruckEspUpdate < 0.15 then
            return
        end
        lastTruckEspUpdate = tick()
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then
            return
        end
        for _, d in pairs(trackedTrucks) do
            if d.primary and d.bb then
                local dl = d.bb:FindFirstChild("DistLabel")
                if dl then
                    dl.Text = math.floor((d.primary.Position - root.Position).Magnitude) .. " studs"
                end
            end
        end
    end)

    Tabs.ESP:AddToggle("RC Car ESP", false, function(v)
        RCCarESPEnabled = v
        if v then
            for _, o in ipairs(Workspace:GetChildren()) do
                if o.Name:match("__Truck$") then
                    addTruckESP(o)
                end
            end
        else
            for t in pairs(trackedTrucks) do
                removeTruckESP(t)
            end
        end
    end)
    Tabs.Colors:AddSlider("RC Car R", 0, 255, 255, function(v)
        truckR = v
    end)
    Tabs.Colors:AddSlider("RC Car G", 0, 255, 50, function(v)
        truckG = v
    end)
    Tabs.Colors:AddSlider("RC Car B", 0, 255, 50, function(v)
        truckB = v
    end)

    -- Name changer

    local nameChangerEnabled = false
    local nameConnections = {}
    local processed = setmetatable({}, { __mode = "k" })

    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer

    local function getTargets()
        local t = {}

        if LocalPlayer.Name then
            t[LocalPlayer.Name] = "discord.gg/zephyrmvsd"
        end

        if LocalPlayer.DisplayName and LocalPlayer.DisplayName ~= LocalPlayer.Name then
            t[LocalPlayer.DisplayName] = "discord.gg/zephyrmvsd"
        end

        return t
    end

    local function disconnectNameChanger()
        for _, c in ipairs(nameConnections) do
            pcall(function()
                c:Disconnect()
            end)
        end
        nameConnections = {}
        table.clear(processed)
    end

    local function processObject(obj)
        if not nameChangerEnabled then
            return
        end
        if processed[obj] then
            return
        end

        local textProp

        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            textProp = "Text"
        end

        if not textProp then
            return
        end

        local function update()
            if not nameChangerEnabled then
                return
            end

            local txt = obj[textProp]
            if not txt then
                return
            end

            local new = txt
            local TARGETS = getTargets()

            for target, replacement in pairs(TARGETS) do
                if string.find(new, target, 1, true) then
                    new = string.gsub(new, target, replacement)
                end
            end

            if new ~= txt then
                obj[textProp] = new
            end
        end

        update()

        local conn = Runtime.connect(obj:GetPropertyChangedSignal(textProp), update)
        table.insert(nameConnections, conn)

        processed[obj] = true
    end

    local function scanExisting(gui)
        for _, obj in ipairs(gui:GetDescendants()) do
            processObject(obj)
        end
    end

    local function enableNameChanger()
        local gui = safeWaitForChild(LocalPlayer, "PlayerGui", 20)
        if not gui then
            return
        end

        scanExisting(gui)

        table.insert(nameConnections, Runtime.connect(gui.DescendantAdded, processObject))
    end

    Tabs.Player:AddToggle("Name Changer", false, function(on)
        nameChangerEnabled = on

        if on then
            enableNameChanger()
        else
            disconnectNameChanger()
        end
    end)

    Runtime.connect(LocalPlayer.CharacterAdded, function()
        task.wait(1)
        if nameChangerEnabled then
            disconnectNameChanger()
            enableNameChanger()
        end
    end)

    -- Arms
    pcall(function()
        local armChangerEnabled = FirstRunPreset
        local armColorR = FirstRunPreset and 176 or 0
        local armColorG = FirstRunPreset and 88 or 180
        local armColorB = 255
        local armWatchConn = nil
        local wmChildConn = nil

        local function applyArms()
            if not armChangerEnabled then
                return
            end
            local it = Workspace:FindFirstChild("IgnoreThese")
            if not it then
                return
            end
            local arms = it:FindFirstChild("MyArms")
            if not arms then
                return
            end
            local color = Color3.fromRGB(armColorR, armColorG, armColorB)
            local mat = Enum.Material.ForceField
            local wm = arms:FindFirstChild("WModel")
            if wm then
                for _, p in ipairs(wm:GetDescendants()) do
                    if p:IsA("SurfaceAppearance") then
                        pcall(function()
                            p:Destroy()
                        end)
                    elseif p:IsA("BasePart") then
                        if p.Name == "Tip" or p.Name == "AnchorPoint" or p.Name == "TrinketPoint" then
                            continue
                        end
                        pcall(function()
                            p.Color = color
                            p.Material = mat
                            p.Transparency = 0
                        end)
                    end
                end
            end
            local ba = arms:FindFirstChild("BlockArms")
            if ba then
                for _, name in ipairs({ "Left Arm", "Right Arm" }) do
                    local p = ba:FindFirstChild(name)
                    if p and p:IsA("BasePart") then
                        pcall(function()
                            p.Color = color
                            p.Material = mat
                            p.Transparency = 0
                        end)
                    end
                end
                for _, name in ipairs({ "LeftGlove", "RightGlove" }) do
                    local p = ba:FindFirstChild(name)
                    if p and p:IsA("BasePart") then
                        pcall(function()
                            p.Color = color
                            p.Material = mat
                            p.Transparency = 0
                            local sa = p:FindFirstChildOfClass("SurfaceAppearance")
                            if sa then
                                sa:Destroy()
                            end
                        end)
                    end
                end
            end
            for _, name in ipairs({ "left_arm", "right_arm" }) do
                local p = arms:FindFirstChild(name)
                if p and p:IsA("BasePart") then
                    pcall(function()
                        p.Color = color
                        p.Material = mat
                        p.Transparency = 1
                        local sa = p:FindFirstChildOfClass("SurfaceAppearance")
                        if sa then
                            sa:Destroy()
                        end
                    end)
                end
            end
        end

        local function hookWModel(arms)
            if wmChildConn then
                pcall(function()
                    wmChildConn:Disconnect()
                end)
                wmChildConn = nil
            end
            if not arms then
                return
            end
            local wm = arms:FindFirstChild("WModel")
            if not wm then
                return
            end
            wmChildConn = Runtime.connect(wm.DescendantAdded, function(desc)
                if not armChangerEnabled then
                    return
                end
                if desc:IsA("SurfaceAppearance") then
                    pcall(function()
                        desc:Destroy()
                    end)
                    local parent = desc.Parent
                    if parent and parent:IsA("BasePart") then
                        pcall(function()
                            parent.Color = Color3.fromRGB(armColorR, armColorG, armColorB)
                            parent.Material = Enum.Material.ForceField
                            parent.Transparency = 0
                        end)
                    end
                    return
                end
                if desc:IsA("BasePart") then
                    if desc.Name == "Tip" or desc.Name == "AnchorPoint" or desc.Name == "TrinketPoint" then
                        return
                    end
                    task.delay(0.05, function()
                        if not armChangerEnabled then
                            return
                        end
                        local sa = desc:FindFirstChildOfClass("SurfaceAppearance")
                        if sa then
                            pcall(function()
                                sa:Destroy()
                            end)
                        end
                        pcall(function()
                            desc.Color = Color3.fromRGB(armColorR, armColorG, armColorB)
                            desc.Material = Enum.Material.ForceField
                            desc.Transparency = 0
                        end)
                    end)
                end
            end)
        end

        local function setArmChanger(on)
            armChangerEnabled = on
            if on then
                if armWatchConn then
                    pcall(function()
                        armWatchConn:Disconnect()
                    end)
                    armWatchConn = nil
                end
                if wmChildConn then
                    pcall(function()
                        wmChildConn:Disconnect()
                    end)
                    wmChildConn = nil
                end
                local lastArms = nil
                armWatchConn = Runtime.connect(RunService.Heartbeat, function()
                    if not armChangerEnabled then
                        return
                    end
                    local it = Workspace:FindFirstChild("IgnoreThese")
                    if not it then
                        return
                    end
                    local arms = it:FindFirstChild("MyArms")
                    if arms ~= lastArms then
                        lastArms = arms
                        if arms then
                            task.wait(0.1)
                            applyArms()
                            hookWModel(arms)
                        end
                    end
                end)
                local it = Workspace:FindFirstChild("IgnoreThese")
                if it then
                    local arms = it:FindFirstChild("MyArms")
                    if arms then
                        lastArms = arms
                        applyArms()
                        hookWModel(arms)
                    end
                end
            else
                if armWatchConn then
                    pcall(function()
                        armWatchConn:Disconnect()
                    end)
                    armWatchConn = nil
                end
                if wmChildConn then
                    pcall(function()
                        wmChildConn:Disconnect()
                    end)
                    wmChildConn = nil
                end
            end
        end

        Tabs.Player:AddToggle("Arm Changer", armChangerEnabled, setArmChanger)

        Tabs.Colors:AddSlider("Arm R", 0, 255, armColorR, function(v)
            armColorR = v
            applyArms()
        end)
        Tabs.Colors:AddSlider("Arm G", 0, 255, armColorG, function(v)
            armColorG = v
            applyArms()
        end)
        Tabs.Colors:AddSlider("Arm B", 0, 255, armColorB, function(v)
            armColorB = v
            applyArms()
        end)

        if armChangerEnabled then
            task.defer(function()
                setArmChanger(true)
            end)
        end
    end)

    -- Collectibles
    pcall(function()
        local autoCollectEnabled = false
        local _descConn = nil

        Tabs.Misc:AddToggle("Auto Collect Coins & Gems", false, function(on)
            autoCollectEnabled = on
            if not on then
                if _descConn then
                    _descConn:Disconnect()
                    _descConn = nil
                end
                return
            end
            task.spawn(function()
                local it = workspace:WaitForChild("IgnoreThese", 10)
                local pickups = it and it:WaitForChild("Pickups", 10)
                local loot = pickups and pickups:WaitForChild("Loot", 10)
                if not loot then
                    return
                end
                local function suckCoin(part)
                    if not part:IsA("BasePart") then
                        return
                    end
                    task.spawn(function()
                        local attempts = 0
                        while autoCollectEnabled and part and part.Parent do
                            local char = game:GetService("Players").LocalPlayer.Character
                            local hrp = char and char:FindFirstChild("HumanoidRootPart")
                            if not hrp then
                                break
                            end
                            pcall(function()
                                part.CFrame = hrp.CFrame
                            end)
                            if (part.Position - hrp.Position).Magnitude < 4 then
                                pcall(function()
                                    part:Destroy()
                                end)
                                break
                            end
                            attempts += 1
                            if attempts > 60 then
                                pcall(function()
                                    part:Destroy()
                                end)
                                break
                            end
                            task.wait(0.05)
                        end
                    end)
                end
                for _, part in ipairs(loot:GetChildren()) do
                    suckCoin(part)
                end
                _descConn = Runtime.connect(loot.ChildAdded, function(part)
                    if autoCollectEnabled then
                        suckCoin(part)
                    end
                end)
            end)
        end)
    end)

    -- Event shop
    pcall(function()
        local sniperEnabled = false
        local sniperThread = nil
        local selectedSniperPreset = "All Event Items"
        local sniperTargetsText = ""
        local sniperTargets = {}
        local sniperTargetAll = false
        local sniperScanDelay = 2
        local sniperBuyCooldown = 5
        local lastAttempt = {}
        local boughtRefresh = {}
        local soldOutRefresh = {}
        local cachedEventItems = nil
        local cachedNetworkModule = nil
        local cachedMenuShared = nil

        local sniperPresetOptions = {
            "All Event Items",
            "All Summer Weapons",
            "All Classic Weapons",
            "All Battlepass Shop",
            "Tiger's Tempest SMG",
            "Imperial Trading Booth",
            "Jade Statue",
            "Royal Decree",
            "Jade Hammer",
            "Winged Abyssal AK",
            "Duck Sniper",
            "Solar Flare Cannon",
            "Hypersoaker 9000",
            "Duck Blaster",
            "Pool Noodle Current",
            "Green Energy Sword",
            "Lord of the Federation AK",
            "Dr Ishmael Scoped AR",
        }

        local function norm(value)
            value = tostring(value or ""):lower()
            value = value:gsub("[^%w]+", " ")
            value = value:gsub("^%s+", ""):gsub("%s+$", "")
            value = value:gsub("%s+", " ")
            return value
        end

        local function currentRefreshId()
            local ok, result = pcall(function()
                return math.floor(DateTime.now().UnixTimestamp / 3600)
            end)
            if ok and tonumber(result) then
                return tonumber(result)
            end
            return math.floor(os.time() / 3600)
        end

        local function getRemotes()
            local network = safeFindFirstChild(ReplicatedStorage, "Network")
                or safeWaitForChild(ReplicatedStorage, "Network", 1)
            return network and (safeFindFirstChild(network, "Remotes") or safeWaitForChild(network, "Remotes", 1))
        end

        local function getRemote(name)
            local remotes = getRemotes()
            return remotes and safeFindFirstChild(remotes, name)
        end

        local function getNetworkModule()
            local modules = safeFindFirstChild(ReplicatedStorage, "Modules")
            local networkModule = modules and safeFindFirstChild(modules, "NetworkModule2")
            local result = requireSafe(networkModule)
            if type(result) == "table" then
                cachedNetworkModule = result
                return result
            end
            return nil
        end

        local function getMenuShared()
            local playerGui = safeFindFirstChild(LocalPlayer, "PlayerGui")
            local menuUI = playerGui and safeFindFirstChild(playerGui, "MenuUI")
            local menuLocal = menuUI and safeFindFirstChild(menuUI, "MenuLocal")
            local sharedModule = menuLocal and safeFindFirstChild(menuLocal, "Shared")
            local result = requireSafe(sharedModule)
            if type(result) == "table" then
                cachedMenuShared = result
                return result
            end
            return nil
        end

        local function requireReplicatedModule(name)
            local modules = safeFindFirstChild(ReplicatedStorage, "Modules")
            return requireSafe(modules and safeFindFirstChild(modules, name))
        end

        local function addEventItem(items, item)
            if type(item) ~= "table" then
                return
            end
            item.Sort = item.Sort or (#items + 1)
            item.Aliases = type(item.Aliases) == "table" and item.Aliases or {}
            table.insert(items, item)
        end

        local function getEventItems()
            if cachedEventItems then
                return cachedEventItems
            end

            local items = {}
            local summer = requireReplicatedModule("SummerShared")
            if type(summer) == "table" and type(summer.ShopItems) == "table" then
                for _, shopItem in ipairs(summer.ShopItems) do
                    local data = type(shopItem.Data) == "table" and shopItem.Data or {}
                    local price = type(shopItem.Price) == "table" and shopItem.Price or {}
                    local id = shopItem.Id
                    local display = data.Value or ("Summer Item " .. tostring(id))
                    local aliases = { display, tostring(display):gsub("^Blue Pool Noodle$", "Pool Noodle Current") }
                    if id == summer.PoolNoodleShopItemId then
                        table.insert(aliases, "Pool Noodle")
                        table.insert(aliases, "Pool Noodle Current")
                        if type(summer.PoolNoodleShopVariants) == "table" then
                            for _, variant in ipairs(summer.PoolNoodleShopVariants) do
                                table.insert(aliases, variant)
                            end
                        end
                    end
                    addEventItem(items, {
                        Key = "Summer:" .. tostring(id),
                        Id = id,
                        Name = display,
                        Event = "Summer",
                        Group = "All Summer Weapons",
                        PriceType = price.Type,
                        Price = tonumber(price.Value) or 0,
                        StockRemote = "RequestLatestSummerShopStock",
                        PurchaseRemote = "RequestPurchaseSummerItem",
                        PurchaseArgs = { id },
                        Aliases = aliases,
                        Pool = id == summer.PoolNoodleShopItemId,
                        Shared = summer,
                        Sort = 100 - tonumber(id or 0),
                    })
                end
            end

            local classic = requireReplicatedModule("ClassicEventShared")
            if type(classic) == "table" and type(classic.IndividualWeapons) == "table" then
                for _, weapon in ipairs(classic.IndividualWeapons) do
                    addEventItem(items, {
                        Key = "Classic:" .. tostring(weapon.Name),
                        Id = weapon.Name,
                        Name = weapon.Name,
                        Event = "Classic",
                        Group = "All Classic Weapons",
                        PriceType = "Tix",
                        Price = tonumber(weapon.Price) or 0,
                        PurchaseRemote = "RequestPurchaseClassicEventItem",
                        PurchaseArgs = { weapon.Name },
                        Aliases = { weapon.Name },
                        Sort = 200 + (tonumber(weapon.Price) or 0),
                    })
                end
            end

            local battlepass = requireReplicatedModule("BattlepassUtil")
            local passShop = type(battlepass) == "table" and battlepass.PassPointsShop
            if type(passShop) == "table" and type(passShop.Items) == "table" then
                for _, passItem in ipairs(passShop.Items) do
                    local reward = type(passItem.Reward) == "table" and passItem.Reward or {}
                    addEventItem(items, {
                        Key = "Battlepass:" .. tostring(passItem.ItemId),
                        Id = passItem.ItemId,
                        Name = tostring(passItem.DisplayName or reward.Value or passItem.ItemId),
                        Event = "Battlepass",
                        Group = "All Battlepass Shop",
                        PriceType = "PassPoints",
                        Price = tonumber(passItem.PricePassPoints) or 0,
                        PurchaseRemote = "BuyPassPointsShopItem",
                        PurchaseArgs = { passItem.ItemId },
                        Aliases = { passItem.ItemId, passItem.DisplayName, reward.Value },
                        Sort = 300 + (tonumber(passItem.PricePassPoints) or 0),
                    })
                end
            end

            table.sort(items, function(a, b)
                return (tonumber(a.Sort) or 0) > (tonumber(b.Sort) or 0)
            end)
            cachedEventItems = items
            return items
        end

        local function getCurrentItemName(item)
            if item.Pool and type(item.Shared) == "table" and type(item.Shared.GetShopItemWeaponName) == "function" then
                local ok, result = pcall(function()
                    return item.Shared.GetShopItemWeaponName(item.Id)
                end)
                if ok and type(result) == "string" and result ~= "" then
                    return result
                end
            end
            return item.Name or item.Id
        end

        local function rebuildTargets(text)
            sniperTargets = {}
            sniperTargetAll = false

            text = tostring(text or "")
            for token in text:gmatch("[^,%n;]+") do
                local key = norm(token)
                if key ~= "" then
                    if key == "all" or key == "all event items" or key == "everything" then
                        sniperTargetAll = true
                    else
                        sniperTargets[key] = true
                    end
                end
            end
        end

        local function addTargetName(name)
            if not name or name == "" then
                return
            end
            if name == "All Event Items" then
                sniperTargetsText = "All Event Items"
            elseif sniperTargetsText == "" then
                sniperTargetsText = name
            else
                local wanted = norm(name)
                local exists = false
                for token in sniperTargetsText:gmatch("[^,%n;]+") do
                    if norm(token) == wanted then
                        exists = true
                        break
                    end
                end
                if not exists then
                    sniperTargetsText = sniperTargetsText .. ", " .. name
                end
            end
            rebuildTargets(sniperTargetsText)
            print("[Zephyr HYPERSHOT] Sniper targets: " .. sniperTargetsText)
        end

        local function hasTargets()
            if sniperTargetAll then
                return true
            end
            return next(sniperTargets) ~= nil
        end

        local function targetMatches(item)
            if sniperTargetAll then
                return true
            end

            local currentName = norm(getCurrentItemName(item))
            for target in pairs(sniperTargets) do
                if target == norm(item.Group) then
                    return true
                end
                if target == currentName then
                    return true
                end

                for _, alias in ipairs(item.Aliases or {}) do
                    local aliasKey = norm(alias)
                    if target == aliasKey then
                        return true
                    end
                end
            end

            return false
        end

        local function getStockTable()
            local remote = getRemote("RequestLatestSummerShopStock")
            if remote and remote:IsA("RemoteFunction") then
                local ok, result = pcall(function()
                    return remote:InvokeServer()
                end)
                if ok and type(result) == "table" then
                    return result
                end
            end

            local networkModule = getNetworkModule()
            if networkModule and type(networkModule.InvokeServer) == "function" then
                local ok, result = pcall(function()
                    return networkModule:InvokeServer("RequestLatestSummerShopStock")
                end)
                if ok and type(result) == "table" then
                    return result
                end
            end

            return nil
        end

        local function stockLeft(stock, id)
            if type(stock) ~= "table" then
                return nil
            end
            local value = stock[id] or stock[tostring(id)]
            if type(value) == "table" then
                value = value.StockLeft or value.stockLeft or value.Stock
            end
            return tonumber(value)
        end

        local function getEventBalance(priceType)
            local shared = getMenuShared()
            local core = shared and shared.CoreData
            if type(core) ~= "table" then
                return nil
            end
            local data = core.Summer2026
            if priceType == "GoldenBeachBall" then
                return type(data) == "table" and tonumber(data.GoldenBeachBallBalance) or nil
            elseif priceType == "BeachBall" then
                return type(data) == "table" and tonumber(data.BeachBallBalance) or nil
            elseif priceType == "Tix" then
                local classic = core.Classic2026
                return tonumber(
                    type(classic) == "table" and (classic.Tix or classic.TixBalance or classic.Balance) or core.Tix
                )
            elseif priceType == "PassPoints" then
                local battlepass = core.Battlepass or core.BattlepassData
                return tonumber(
                    type(battlepass) == "table" and (battlepass.PassPoints or battlepass.Points) or core.PassPoints
                )
            end
            return nil
        end

        local function canAfford(item)
            local balance = getEventBalance(item.PriceType)
            if balance == nil then
                return true
            end
            return balance >= item.Price
        end

        local function callRemote(remoteName, ...)
            if not remoteName then
                return nil
            end
            local args = { ... }
            local remote = getRemote(remoteName)
            if remote and remote:IsA("RemoteFunction") then
                return remote:InvokeServer(CompatUnpack(args))
            elseif remote and remote:IsA("RemoteEvent") then
                remote:FireServer(CompatUnpack(args))
                return true
            end

            local networkModule = getNetworkModule()
            if networkModule and type(networkModule.InvokeServer) == "function" then
                return networkModule:InvokeServer(remoteName, CompatUnpack(args))
            end
        end

        local function purchaseEventItem(item)
            local remoteName = item and item.PurchaseRemote
            if not remoteName then
                return nil
            end
            local args = item.PurchaseArgs or { item.Id }
            return callRemote(remoteName, CompatUnpack(args))
        end

        local function runSniperPass()
            if not hasTargets() then
                addTargetName(selectedSniperPreset)
            end

            local stock = getStockTable()

            local refresh = currentRefreshId()
            local now = tick()

            for _, item in ipairs(getEventItems()) do
                local id = item.Key or item.Id
                if item and targetMatches(item) then
                    local left = item.StockRemote and stockLeft(stock, item.Id) or nil
                    local recent = (lastAttempt[id] or 0) + sniperBuyCooldown > now
                    local alreadyBought = boughtRefresh[id] == refresh
                    local soldOut = soldOutRefresh[id] == refresh or (left ~= nil and left <= 0)

                    if not recent and not alreadyBought and not soldOut and canAfford(item) then
                        lastAttempt[id] = now
                        local itemName = getCurrentItemName(item)
                        local ok, success, result, hardSoldOut = pcall(function()
                            return purchaseEventItem(item)
                        end)

                        if ok and success then
                            boughtRefresh[id] = refresh
                            print(("[Zephyr HYPERSHOT] Sniped %s."):format(itemName))
                            task.wait(0.4)
                        else
                            local message = tostring(result or "")
                            print(("[Zephyr HYPERSHOT] Failed to snipe %s: %s"):format(itemName, message))
                            if hardSoldOut or message:lower():find("sold") or message:lower():find("stock") then
                                soldOutRefresh[id] = refresh
                            elseif message:lower():find("enough") or message:lower():find("afford") then
                                lastAttempt[id] = now + 10
                            end
                        end
                    end
                end
            end
        end

        local function startSniper()
            if sniperThread then
                return
            end
            sniperThread = task.spawn(function()
                while sniperEnabled do
                    pcall(runSniperPass)
                    task.wait(math.max(1, sniperScanDelay))
                end
                sniperThread = nil
            end)
        end

        Tabs.Misc:AddDropdown("Shop Sniper Preset", sniperPresetOptions, selectedSniperPreset, function(value)
            selectedSniperPreset = tostring(value or selectedSniperPreset)
        end)

        Tabs.Misc:AddButton("Add Shop Sniper Target", "Adds selected item to sniper list", function()
            addTargetName(selectedSniperPreset)
        end)

        Tabs.Misc:AddInput("Shop Sniper Targets", "Duck Sniper, Solar Flare Cannon", function(value)
            sniperTargetsText = tostring(value or "")
            rebuildTargets(sniperTargetsText)
        end)

        Tabs.Misc:AddSlider("Shop Sniper Delay", 1, 15, sniperScanDelay, function(value)
            sniperScanDelay = tonumber(value) or 2
        end)

        Tabs.Misc:AddSlider("Shop Sniper Cooldown", 2, 30, sniperBuyCooldown, function(value)
            sniperBuyCooldown = tonumber(value) or 5
        end)

        Tabs.Misc:AddToggle("Auto Event Shop Sniper", false, function(on)
            sniperEnabled = on
            if on then
                startSniper()
            end
        end)

        Tabs.Misc:AddButton("Claim Event Rewards", "Weekly, special, and classic event claims", function()
            task.spawn(function()
                pcall(function()
                    callRemote("ClaimWeeklyBonus")
                end)
                local quests = requireReplicatedModule("Quests")
                if type(quests) == "table" then
                    if type(quests.SpecialQuests) == "table" then
                        pcall(function()
                            callRemote("ClaimSpecialQuestReward")
                        end)
                        task.wait(0.15)
                    end
                end
                local classic = requireReplicatedModule("ClassicEventShared")
                local questData = type(classic) == "table" and classic.QUEST_DATA
                local randomQuests = questData and questData.Quests and questData.Quests.Random
                if type(randomQuests) == "table" then
                    for _, quest in ipairs(randomQuests) do
                        if type(quest) == "table" and quest.Id then
                            pcall(function()
                                callRemote("ClaimClassicEventQuest", quest.Id)
                            end)
                            task.wait(0.15)
                        end
                    end
                end
                print("[Zephyr HYPERSHOT] Event reward claim pass finished.")
            end)
        end)

        Tabs.Misc:AddButton("Claim Battlepass Rewards", "Claims current pass rewards where available", function()
            task.spawn(function()
                pcall(function()
                    callRemote("TryClaimAllBattlepassItems")
                end)
                local data
                pcall(function()
                    data = callRemote("GetBattlepassData")
                end)
                if type(data) == "table" then
                    for i = 1, 120 do
                        pcall(function()
                            callRemote("TryClaimBattlepassItem", i, false)
                        end)
                        pcall(function()
                            callRemote("TryClaimBattlepassItem", i, true)
                        end)
                        if i % 10 == 0 then
                            task.wait()
                        end
                    end
                end
                print("[Zephyr HYPERSHOT] Battlepass claim pass finished.")
            end)
        end)

        Tabs.Misc:AddButton("Spin Wheel", "Uses the current wheel remote", function()
            task.spawn(function()
                pcall(function()
                    callRemote("SpinWheel")
                end)
            end)
        end)
    end)

    -- Rage
    pcall(function()
        local killAllEnabled = false
        local killAllThread = nil
        local camLockConn = nil
        local reloadHookConn2 = nil
        local killBotsEnabled = false
        local botsOnlyMode = false
        local autoShootEnabled = false
        local autoShootConn = nil
        local rageModeEnabled = false
        local rageModeConn = nil
        local killToggle, farmToggle, botToggle, botsOnlyToggle
        local respawnConn, deathConn, currentTarget
        local alive = true
        Tabs.Combat:GetGroup("Rage"):AddLabel({ Text = "High risk / may result in a ban", DoesWrap = true })
        local stateLabel = Tabs.Combat:GetGroup("Rage"):AddLabel({ Text = "Idle", DoesWrap = true })
        local stateText, lastErrorAt = "Idle", -math.huge
        local function status(text)
            if stateText == text then
                return
            end
            stateText = text
            stateLabel:SetText(text)
        end
        local function reportError(context, err)
            if os.clock() - lastErrorAt < 5 then
                return
            end
            lastErrorAt = os.clock()
            status(context .. " paused; waiting for game data")
            warn("[Zephyr Hypershot] " .. context .. ": " .. tostring(err))
        end
        local cachedModule, cachedShared
        local function getCachedShared()
            local module = getControllerSharedModule()
            if module ~= cachedModule or not cachedShared then
                cachedModule, cachedShared = module, Runtime.module(module)
            end
            return cachedShared
        end

        _G.BodySize = 10
        local function expandBody(model)
            if not model or not model:IsA("Model") then
                return
            end
            local hrp = model:FindFirstChild("HumanoidRootPart")
            if hrp and model:FindFirstChild("EnemyHighlight") then
                hrp.Size = Vector3.new(_G.BodySize, _G.BodySize, _G.BodySize)
                hrp.CanCollide = false
                hrp.Transparency = 1
                hrp.Material = Enum.Material.Plastic
                hrp.BrickColor = BrickColor.new("Medium stone grey")
            end
        end
        local function resetBody(model)
            if not model or not model:IsA("Model") then
                return
            end
            local hrp = model:FindFirstChild("HumanoidRootPart")
            if hrp and model:FindFirstChild("EnemyHighlight") then
                hrp.Size = Vector3.new(2, 2, 1)
                hrp.Transparency = 1
                hrp.BrickColor = BrickColor.new("Medium stone grey")
                hrp.Material = Enum.Material.Plastic
                hrp.CanCollide = true
            end
        end
        local hbeConn = nil
        local function startHBE()
            if hbeConn then
                return
            end
            for _, m in ipairs(Workspace:GetChildren()) do
                if m:IsA("Model") then
                    pcall(expandBody, m)
                end
            end
            hbeConn = Runtime.connect(Workspace.ChildAdded, function(m)
                if killAllEnabled and m:IsA("Model") then
                    task.wait(0.1)
                    pcall(expandBody, m)
                end
            end)
        end
        local function stopHBE()
            if hbeConn then
                hbeConn:Disconnect()
                hbeConn = nil
            end
            for _, m in ipairs(Workspace:GetChildren()) do
                if m:IsA("Model") then
                    pcall(resetBody, m)
                end
            end
        end

        local function hookFastReload()
            if reloadHookConn2 then
                pcall(function()
                    reloadHookConn2:Disconnect()
                end)
                reloadHookConn2 = nil
            end
            task.spawn(function()
                local attempts = 0
                while killAllEnabled and attempts < 30 do
                    attempts += 1
                    local ok1, ctrl = pcall(function()
                        return Workspace.IgnoreThese.MyArms.AnimationController
                    end)
                    local ok2, anims = pcall(function()
                        return Workspace.IgnoreThese.MyArms.Anims
                    end)
                    if ok1 and ok2 and ctrl and anims then
                        local reloadAnim = anims:FindFirstChild("Reload")
                        if reloadAnim then
                            if reloadHookConn2 then
                                pcall(function()
                                    reloadHookConn2:Disconnect()
                                end)
                            end
                            reloadHookConn2 = Runtime.connect(ctrl.AnimationPlayed, function(track)
                                if track.Animation and track.Animation.AnimationId == reloadAnim.AnimationId then
                                    track:AdjustSpeed(7)
                                end
                            end)
                            return
                        end
                    end
                    task.wait(0.3)
                end
            end)
        end
        task.spawn(function()
            while alive do
                task.wait(5)
                if alive and killAllEnabled then
                    hookFastReload()
                end
            end
        end)

        local function isRealPlayer(model)
            for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
                if p.Character == model then
                    return true
                end
            end
            return false
        end

        local function isValidTarget(model)
            if not model or not model:IsA("Model") then
                return false
            end
            if model == LocalPlayer.Character then
                return false
            end
            if not model:FindFirstChild("EnemyHighlight") then
                return false
            end
            local hum = model:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then
                return false
            end
            if not model:FindFirstChild("HumanoidRootPart") then
                return false
            end
            local realPlayer = isRealPlayer(model)
            if botsOnlyMode then
                if realPlayer then
                    return false
                end
            elseif not killBotsEnabled then
                if not realPlayer then
                    return false
                end
            end
            return true
        end

        local function findNearestEnemy(myRoot)
            local best, bestDist = nil, math.huge
            local function check(m)
                if isValidTarget(m) then
                    local hrp = m:FindFirstChild("HumanoidRootPart")
                    local d = (myRoot.Position - hrp.Position).Magnitude
                    if d < bestDist then
                        best = m
                        bestDist = d
                    end
                end
            end
            for _, player in ipairs(Players:GetPlayers()) do
                check(player.Character)
            end
            for _, m in ipairs(Workspace:GetChildren()) do
                check(m)
            end
            local mobs = Workspace:FindFirstChild("Mobs")
            if mobs then
                for _, m in ipairs(mobs:GetChildren()) do
                    check(m)
                end
            end
            return best
        end

        local lastOffset = Vector3.new(0, 0, 0)
        local function randomPosition(targetPos)
            local angle = math.random() * 360
            local rad = math.rad(angle)
            local radius = math.random(6, 20)
            local height = math.random(8, 30)
            local offset = Vector3.new(math.sin(rad) * radius, height, math.cos(rad) * radius)
            local att = 0
            while (offset - lastOffset).Magnitude < 5 and att < 10 do
                angle = math.random() * 360
                rad = math.rad(angle)
                radius = math.random(6, 20)
                height = math.random(8, 30)
                offset = Vector3.new(math.sin(rad) * radius, height, math.cos(rad) * radius)
                att += 1
            end
            lastOffset = offset
            return targetPos + offset
        end

        local function startAutoShoot()
            if autoShootConn then
                pcall(function()
                    autoShootConn:Disconnect()
                end)
                autoShootConn = nil
            end
            local lastFire = 0
            autoShootConn = Runtime.connect(RunService.Heartbeat, function()
                if not autoShootEnabled or not killAllEnabled or rageModeEnabled then
                    return
                end
                local now = tick()
                pcall(function()
                    local shared = getCachedShared()
                    local ct = shared and shared.CurrTool
                    if not ct then
                        return
                    end
                    local debounce = 0.2
                    pcall(function()
                        local ws = ct.WSettings or ct
                        if type(ws.Debounce) == "number" then
                            debounce = ws.Debounce
                        elseif type(ws.FireRate) == "number" then
                            debounce = 1 / ws.FireRate
                        end
                    end)
                    if now - lastFire < debounce * 1.5 then
                        return
                    end
                    lastFire = now
                    local fired = false
                    for _, method in ipairs({ "ShootLogic", "Shoot", "Fire", "PrimaryAction", "Attack" }) do
                        if type(ct[method]) == "function" and not fired then
                            local ok, err = pcall(ct[method], ct)
                            if not ok then
                                reportError("Auto Farm", err)
                            end
                            fired = true
                        end
                    end
                    if not fired then
                        local r = ct.ShootRemote or ct.FireRemote
                        if r and r:IsA("RemoteEvent") then
                            pcall(function()
                                r:FireServer()
                            end)
                        end
                    end
                end)
            end)
        end
        local function stopAutoShoot()
            if autoShootConn then
                pcall(function()
                    autoShootConn:Disconnect()
                end)
                autoShootConn = nil
            end
        end

        local function startRageMode()
            if rageModeConn then
                pcall(function()
                    rageModeConn:Disconnect()
                end)
                rageModeConn = nil
            end
            rageModeConn = Runtime.connect(RunService.Heartbeat, function()
                if not rageModeEnabled then
                    return
                end
                local ok, err = pcall(function()
                    local shared = getCachedShared()
                    local ct = shared and shared.CurrTool
                    if not ct then
                        status("Waiting for equipped weapon")
                        return
                    end
                    for _, method in ipairs({ "ShootLogic", "Shoot", "Fire", "PrimaryAction", "Attack" }) do
                        if type(ct[method]) == "function" then
                            ct[method](ct)
                            status("Rage active")
                            return
                        end
                    end
                    status("Weapon firing method unavailable")
                end)
                if not ok then
                    reportError("Rage", err)
                end
            end)
        end
        local function stopRageMode()
            if rageModeConn then
                pcall(function()
                    rageModeConn:Disconnect()
                end)
                rageModeConn = nil
            end
        end

        killToggle = Tabs.Combat:AddToggle("Kill All [BAN RISK]", false, function(on)
            killAllEnabled = on
            if on then
                startHBE()
                hookFastReload()
                if respawnConn then
                    respawnConn:Disconnect()
                end
                respawnConn = Runtime.connect(LocalPlayer.CharacterAdded, function()
                    task.wait(1)
                    if killAllEnabled then
                        hookFastReload()
                    end
                end)
                local waitingForNextKill = false
                killAllThread = task.spawn(function()
                    while killAllEnabled do
                        task.wait(0.05)
                        if waitingForNextKill then
                            continue
                        end
                        local ok, err = pcall(function()
                            local char = LocalPlayer.Character
                            local myRoot = char and char:FindFirstChild("HumanoidRootPart")
                            if not myRoot then
                                return
                            end
                            local target = findNearestEnemy(myRoot)
                            if not target then
                                currentTarget = nil
                                if camLockConn then
                                    camLockConn:Disconnect()
                                    camLockConn = nil
                                end
                                if deathConn then
                                    deathConn:Disconnect()
                                    deathConn = nil
                                end
                                status("No eligible enemy found")
                                return
                            end
                            local tRoot = target:FindFirstChild("HumanoidRootPart")
                            local tHum = target:FindFirstChildOfClass("Humanoid")
                            if not tRoot or not tHum or tHum.Health <= 0 then
                                return
                            end
                            if currentTarget ~= target then
                                currentTarget = target
                                if camLockConn then
                                    camLockConn:Disconnect()
                                    camLockConn = nil
                                end
                                if deathConn then
                                    deathConn:Disconnect()
                                    deathConn = nil
                                end
                                camLockConn = Runtime.connect(RunService.RenderStepped, function()
                                    if not killAllEnabled then
                                        camLockConn:Disconnect()
                                        camLockConn = nil
                                        return
                                    end
                                    local tr = target:FindFirstChild("HumanoidRootPart")
                                    local camera = Workspace.CurrentCamera
                                    if tr and camera then
                                        camera.CFrame = CFrame.new(camera.CFrame.Position, tr.Position)
                                    end
                                end)
                                if autoShootEnabled then
                                    deathConn = Runtime.connect(tHum:GetPropertyChangedSignal("Health"), function()
                                        if tHum.Health <= 0 and not waitingForNextKill then
                                            waitingForNextKill = true
                                            pcall(function()
                                                deathConn:Disconnect()
                                            end)
                                            task.delay(0.8, function()
                                                waitingForNextKill = false
                                            end)
                                        end
                                    end)
                                end
                            end
                            status(autoShootEnabled and "Auto Farm active" or "Kill All active")
                            local newPos = randomPosition(tRoot.Position)
                            myRoot.CFrame = CFrame.new(newPos, tRoot.Position)
                        end)
                        if not ok then
                            reportError("Kill All", err)
                        end
                    end
                end)
            else
                killAllEnabled = false
                autoShootEnabled = false
                if killAllThread then
                    task.cancel(killAllThread)
                    killAllThread = nil
                end
                if camLockConn then
                    pcall(function()
                        camLockConn:Disconnect()
                    end)
                    camLockConn = nil
                end
                if reloadHookConn2 then
                    pcall(function()
                        reloadHookConn2:Disconnect()
                    end)
                    reloadHookConn2 = nil
                end
                stopAutoShoot()
                stopHBE()
                if respawnConn then
                    respawnConn:Disconnect()
                    respawnConn = nil
                end
                if deathConn then
                    deathConn:Disconnect()
                    deathConn = nil
                end
                currentTarget = nil
                if farmToggle and farmToggle.Value then
                    farmToggle:SetValue(false)
                end
                status("Idle")
            end
        end)

        botToggle = Tabs.Combat:AddToggle("Bot Mode [BAN RISK]", false, function(on)
            killBotsEnabled = on
            if on and botsOnlyToggle and botsOnlyToggle.Value then
                botsOnlyToggle:SetValue(false)
            end
        end)
        botsOnlyToggle = Tabs.Combat:AddToggle("Bots Only Mode [BAN RISK]", false, function(on)
            botsOnlyMode = on
            if on and botToggle and botToggle.Value then
                botToggle:SetValue(false)
            end
        end)
        farmToggle = Tabs.Combat:AddToggle("Auto Farm Mode [BAN RISK]", false, function(on)
            autoShootEnabled = on
            if on then
                if not killToggle.Value then
                    killToggle:SetValue(true)
                end
                startAutoShoot()
            else
                stopAutoShoot()
            end
        end)
        Tabs.Combat:AddToggle("Rage Mode [PISTOL] [BAN RISK]", false, function(on)
            rageModeEnabled = on
            if on then
                startRageMode()
            else
                stopRageMode()
            end
        end)
        Library:OnUnload(function()
            alive = false
            killToggle:SetValue(false)
            rageModeEnabled = false
            stopRageMode()
        end)
    end)

    -- Kill sounds
    pcall(function()
        local kf = Lighting:FindFirstChild("Sounds") and Lighting.Sounds:FindFirstChild("KillSounds")
        if kf then
            local newIds = {
                "rbxassetid://93254093525275",
                "rbxassetid://151710118",
                "rbxassetid://151710120",
                "rbxassetid://937898383",
                "rbxassetid://937904734",
                "rbxassetid://937902490",
                "rbxassetid://723055264",
                "rbxassetid://6410918897",
                "rbxassetid://6417943635",
                "rbxassetid://102843336682558",
                "rbxassetid://89481514209130",
            }
            Tabs.Visuals:AddToggle("Change Kill Sounds", false, function(value)
                if not value then
                    return
                end
                for i = 1, 11 do
                    local s = kf:FindFirstChild("Kill" .. i)
                    if s and s:IsA("Sound") then
                        s.SoundId = newIds[i]
                    end
                end
            end)
        end
    end)

    -- Crosshair
    pcall(function()
        local rainbowEnabled, rainbowConn = false, nil
        Tabs.Visuals:AddToggle("Rainbow Crosshair", false, function(value)
            rainbowEnabled = value
            if rainbowConn then
                rainbowConn:Disconnect()
                rainbowConn = nil
            end
            if not value then
                return
            end
            pcall(function()
                local fpgui = safeWaitForChild(safeWaitForChild(LocalPlayer, "PlayerGui", 20), "FirstPersonGUI")
                if not fpgui then
                    return
                end
                local crosshairs = safeWaitForChild(fpgui, "CrossHairs")
                if not crosshairs then
                    return
                end
                local targets = {}
                for _, name in ipairs({ "Up", "Right", "Left", "Down", "Center" }) do
                    local p = safeFindFirstChild(crosshairs, name)
                    if p then
                        table.insert(targets, p)
                    end
                end
                local hm = safeFindFirstChild(fpgui, "Hitmarker")
                if hm then
                    local t = safeFindFirstChild(hm, "Template")
                    if t then
                        for _, name in ipairs({ "Up", "Right", "Left", "Down" }) do
                            local p = safeFindFirstChild(t, name)
                            if p then
                                table.insert(targets, p)
                            end
                        end
                    end
                end
                if #targets == 0 then
                    return
                end
                local hue = 0
                rainbowConn = Runtime.connect(RunService.RenderStepped, function(dt)
                    if not rainbowEnabled then
                        return
                    end
                    hue = (hue + dt * 0.25) % 1
                    local color = Color3.fromHSV(hue, 1, 1)
                    for _, gui in ipairs(targets) do
                        if gui and gui.Parent and gui:IsA("GuiObject") then
                            pcall(function()
                                gui.BackgroundColor3 = color
                            end)
                        end
                    end
                end)
            end)
        end)
    end)

    -- Auto heal
    pcall(function()
        local autoHealEnabled = false
        Tabs.Misc:AddToggle("Auto Heal", false, function(value)
            autoHealEnabled = value
            if not value then
                return
            end
            task.spawn(function()
                while autoHealEnabled do
                    pcall(function()
                        local char = LocalPlayer.Character
                        if not char then
                            return
                        end
                        local torso = safeFindFirstChild(char, "Torso") or safeFindFirstChild(char, "UpperTorso")
                        if not torso then
                            return
                        end
                        local heals = Workspace:FindFirstChild("IgnoreThese")
                            and Workspace.IgnoreThese:FindFirstChild("Pickups")
                            and Workspace.IgnoreThese.Pickups:FindFirstChild("Heals")
                        if heals then
                            for _, m in ipairs(heals:GetChildren()) do
                                if m:IsA("Model") and m.PrimaryPart then
                                    pcall(function()
                                        m:SetPrimaryPartCFrame(torso.CFrame)
                                    end)
                                end
                            end
                        end
                    end)
                    task.wait(0.5)
                end
            end)
        end)
    end)

    -- Auto ammo
    pcall(function()
        local autoAmmoEnabled = false
        Tabs.Misc:AddToggle("Auto Ammo", false, function(value)
            autoAmmoEnabled = value
            if not value then
                return
            end
            task.spawn(function()
                while autoAmmoEnabled do
                    pcall(function()
                        local char = LocalPlayer.Character
                        if not char then
                            return
                        end
                        local torso = safeFindFirstChild(char, "Torso") or safeFindFirstChild(char, "UpperTorso")
                        if not torso then
                            return
                        end
                        local ammo = Workspace:FindFirstChild("IgnoreThese")
                            and Workspace.IgnoreThese:FindFirstChild("Pickups")
                            and Workspace.IgnoreThese.Pickups:FindFirstChild("Ammo")
                        if ammo then
                            for _, m in ipairs(ammo:GetChildren()) do
                                if m:IsA("Model") and m.PrimaryPart then
                                    pcall(function()
                                        m:SetPrimaryPartCFrame(torso.CFrame)
                                    end)
                                end
                            end
                        end
                    end)
                    task.wait(0.5)
                end
            end)
        end)
    end)

    -- Weapon settings
    pcall(function()
        local noRecoilOriginals = {}
        Tabs.Combat:AddButton("No Recoil", "Disables all recoil effects", function()
            pcall(function()
                local z = Vector3.new(0, 0, 0)
                for _, v in next, getgc(true) do
                    if typeof(v) == "table" and rawget(v, "Spread") ~= nil and rawget(v, "Damage") ~= nil then
                        pcall(function()
                            if not noRecoilOriginals[v] then
                                noRecoilOriginals[v] = {
                                    MinCamRecoil = rawget(v, "MinCamRecoil"),
                                    MaxCamRecoil = rawget(v, "MaxCamRecoil"),
                                    MinRotRecoil = rawget(v, "MinRotRecoil"),
                                    MaxRotRecoil = rawget(v, "MaxRotRecoil"),
                                    MinTransRecoil = rawget(v, "MinTransRecoil"),
                                    MaxTransRecoil = rawget(v, "MaxTransRecoil"),
                                }
                            end
                            rawset(v, "Spread", 0)
                            rawset(v, "MinCamRecoil", z)
                            rawset(v, "MaxCamRecoil", z)
                            rawset(v, "MinRotRecoil", z)
                            rawset(v, "MaxRotRecoil", z)
                            rawset(v, "MinTransRecoil", z)
                            rawset(v, "MaxTransRecoil", z)
                        end)
                    end
                end
            end)
        end)
    end)

    pcall(function()
        local noSpreadOriginals = {}
        Tabs.Combat:AddToggle("No Spread", false, function(value)
            pcall(function()
                if value then
                    for _, v in next, getgc(true) do
                        if
                            typeof(v) == "table"
                            and rawget(v, "Spread") ~= nil
                            and rawget(v, "BaseSpread") ~= nil
                            and rawget(v, "Damage") ~= nil
                        then
                            pcall(function()
                                if not noSpreadOriginals[v] then
                                    noSpreadOriginals[v] = {
                                        Spread = rawget(v, "Spread"),
                                        BaseSpread = rawget(v, "BaseSpread"),
                                        ZoomSpread = rawget(v, "ZoomSpread"),
                                        AimSpread = rawget(v, "AimSpread"),
                                    }
                                end
                                rawset(v, "Spread", 0)
                                rawset(v, "BaseSpread", 0)
                                rawset(v, "ZoomSpread", 0)
                                rawset(v, "AimSpread", 0)
                            end)
                        end
                    end
                else
                    for v, orig in pairs(noSpreadOriginals) do
                        pcall(function()
                            rawset(v, "Spread", orig.Spread)
                            rawset(v, "BaseSpread", orig.BaseSpread)
                            rawset(v, "ZoomSpread", orig.ZoomSpread)
                            rawset(v, "AimSpread", orig.AimSpread)
                        end)
                    end
                    noSpreadOriginals = {}
                end
            end)
        end)
    end)

    pcall(function()
        Tabs.Combat:AddToggle("Insta Scope", false, function(value)
            pcall(function()
                local shared = getControllerShared()
                if shared and shared.CurrTool then
                    local ws = shared.CurrTool.WSettings or shared.CurrTool
                    pcall(function()
                        ws.ScopeSpeed = value and 100 or nil
                    end)
                end
            end)
        end)
    end)

    pcall(function()
        local reloadSpeedEnabled = false
        local reloadSpeedConn = nil
        local currentReloadSpeed = 1
        local function adjustReloadSpeed()
            pcall(function()
                local arms = Workspace:FindFirstChild("IgnoreThese") and Workspace.IgnoreThese:FindFirstChild("MyArms")
                if not arms then
                    return
                end
                local reloadAnim = arms:FindFirstChild("Anims") and arms.Anims:FindFirstChild("Reload")
                local animCtrl = arms:FindFirstChild("AnimationController")
                if not reloadAnim or not animCtrl then
                    return
                end
                for _, track in ipairs(animCtrl:GetPlayingAnimationTracks()) do
                    if track.Animation and track.Animation.AnimationId == reloadAnim.AnimationId then
                        pcall(function()
                            track:AdjustSpeed(currentReloadSpeed)
                        end)
                    end
                end
            end)
        end
        Tabs.Combat:AddToggle("Reload Speed Changer", false, function(value)
            reloadSpeedEnabled = value
            if reloadSpeedConn then
                reloadSpeedConn:Disconnect()
                reloadSpeedConn = nil
            end
            if value then
                reloadSpeedConn = Runtime.connect(RunService.RenderStepped, adjustReloadSpeed)
            end
        end)
        Tabs.Combat:AddSlider("Reload Speed", 1, 30, 1, function(v)
            currentReloadSpeed = v
            if reloadSpeedEnabled then
                adjustReloadSpeed()
            end
        end)
    end)

    pcall(function()
        local infiniteAmmoEnabled = false
        local infiniteFirerateEnabled = false
        local fireRateMultiplier = 1.0

        local function waitForPath(pathFunc, timeout)
            local start = tick()
            timeout = timeout or 10
            while tick() - start < timeout do
                local r = pathFunc()
                if r then
                    return r
                end
                task.wait(0.1)
            end
        end
        local function getGunModule()
            return waitForPath(function()
                local nml = getControllerNewMainLocal()
                if not nml then
                    return
                end
                local tools = safeFindFirstChild(nml, "Tools")
                if not tools then
                    return
                end
                local tool = safeFindFirstChild(tools, "Tool")
                if not tool then
                    return
                end
                return safeFindFirstChild(tool, "Gun")
            end)
        end
        local function getAutoModule()
            return waitForPath(function()
                local nml = getControllerNewMainLocal()
                if not nml then
                    return
                end
                local tools = safeFindFirstChild(nml, "Tools")
                if not tools then
                    return
                end
                local tool = safeFindFirstChild(tools, "Tool")
                if not tool then
                    return
                end
                local gun = safeFindFirstChild(tool, "Gun")
                if not gun then
                    return
                end
                return safeFindFirstChild(gun, "Auto")
            end)
        end
        local function applyInfiniteAmmo()
            task.spawn(function()
                pcall(function()
                    local gm = getGunModule()
                    if not gm then
                        return
                    end
                    local ok, inst = pcall(require, gm)
                    if not ok then
                        return
                    end
                    local orig = inst.ShootLogic
                    if not orig then
                        return
                    end
                    inst.ShootLogic = function(self, ...)
                        pcall(function()
                            if infiniteAmmoEnabled then
                                self.FillAmmo = math.huge
                                self.Ammo = self.WeaponFullClipAmmo
                            end
                        end)
                        return orig(self, ...)
                    end
                end)
            end)
            task.spawn(function()
                pcall(function()
                    local am = getAutoModule()
                    if not am then
                        return
                    end
                    local ok, inst = pcall(require, am)
                    if not ok then
                        return
                    end
                    local orig = inst.ShootLogic
                    if not orig then
                        return
                    end
                    inst.ShootLogic = function(self, ...)
                        pcall(function()
                            if infiniteAmmoEnabled then
                                self.FillAmmo = math.huge
                                self.Ammo = self.WeaponFullClipAmmo
                            end
                        end)
                        return orig(self, ...)
                    end
                end)
            end)
        end
        local function patchFirerate()
            task.spawn(function()
                pcall(function()
                    local gm = getGunModule()
                    if not gm then
                        return
                    end
                    local ok, inst = pcall(require, gm)
                    if not ok then
                        return
                    end
                    local orig = inst.GetDebounce
                    if not orig then
                        return
                    end
                    inst.GetDebounce = function(self, ...)
                        local d = orig(self, ...)
                        return infiniteFirerateEnabled and d * fireRateMultiplier or d
                    end
                end)
            end)
            task.spawn(function()
                pcall(function()
                    local am = getAutoModule()
                    if not am then
                        return
                    end
                    local ok, inst = pcall(require, am)
                    if not ok then
                        return
                    end
                    local orig = inst.ShootLogic
                    if not orig then
                        return
                    end
                    inst.ShootLogic = function(self, ...)
                        pcall(function()
                            if infiniteFirerateEnabled then
                                self.BurstDebounce = self.BurstDebounce * fireRateMultiplier
                            end
                        end)
                        return orig(self, ...)
                    end
                end)
            end)
        end
        local noAbilityCooldownEnabled = false
        local function removeAbilityCooldown()
            pcall(function()
                if not ReplicatedStorage then
                    return
                end
                local abilities = safeFindFirstChild(ReplicatedStorage, "Abilities")
                if not abilities then
                    return
                end
                local modules = safeFindFirstChild(abilities, "Modules")
                if not modules then
                    return
                end
                local abilityList = {}
                for _, abilityModule in pairs(modules:GetChildren()) do
                    if abilityModule:IsA("ModuleScript") then
                        local success, ability = pcall(require, abilityModule)
                        if success and typeof(ability) == "table" then
                            pcall(function()
                                ability.CD = 0
                                ability.ActivateTime = 0
                                table.insert(abilityList, ability)
                            end)
                        end
                    end
                end
                task.spawn(function()
                    while noAbilityCooldownEnabled and task.wait(0.1) do
                        for _, ability in pairs(abilityList) do
                            pcall(function()
                                if ability.ActivateTime and tick() < ability.ActivateTime then
                                    ability.ActivateTime = 0
                                end
                            end)
                        end
                    end
                end)
            end)
        end
        local function onCharLoaded()
            if infiniteAmmoEnabled then
                applyInfiniteAmmo()
            end
            if infiniteFirerateEnabled then
                patchFirerate()
            end
            if noAbilityCooldownEnabled then
                removeAbilityCooldown()
            end
        end
        Runtime.connect(LocalPlayer.CharacterAdded, function(char)
            pcall(function()
                safeWaitForChild(char, "HumanoidRootPart")
                task.wait(1)
                onCharLoaded()
            end)
        end)
        if LocalPlayer.Character then
            onCharLoaded()
        end

        Tabs.Combat:AddToggle("Infinite Ammo", false, function(v)
            infiniteAmmoEnabled = v
            if v then
                applyInfiniteAmmo()
            end
        end)
        Tabs.Combat:AddToggle("Change Firerate", false, function(v)
            infiniteFirerateEnabled = v
            if v then
                patchFirerate()
            end
        end)
        Tabs.Combat:AddSlider("Fire Rate Multiplier", 0.1, 1.0, 1.0, function(v)
            fireRateMultiplier = v
        end)
        Tabs.Combat:AddToggle("No Ability Cooldown", false, function(v)
            noAbilityCooldownEnabled = v
            if v then
                removeAbilityCooldown()
            end
        end)

        pcall(function()
            local cachedMenuShared
            local cachedLoadoutShared
            local cachedNetworkModule
            local cachedGlobalStuff
            local passiveOptions = { "None" }
            local passiveRuntimeEnabled = false
            local passiveRuntimeNames = {}

            local function refreshPassiveOptions()
                local passives = safeFindFirstChild(ReplicatedStorage, "Passives")
                local modules = passives and safeFindFirstChild(passives, "Modules")
                if modules then
                    local found = { "None" }
                    for _, module in ipairs(modules:GetChildren()) do
                        if module:IsA("ModuleScript") then
                            table.insert(found, module.Name)
                        end
                    end
                    table.sort(found, function(a, b)
                        if a == "None" then
                            return true
                        end
                        if b == "None" then
                            return false
                        end
                        return a < b
                    end)
                    passiveOptions = found
                end
                return passiveOptions
            end

            local function passiveKey(passiveName)
                return tostring(passiveName or ""):gsub("%s+", "")
            end

            local function getMenuShared()
                local playerGui = safeFindFirstChild(LocalPlayer, "PlayerGui")
                local menu = playerGui and safeFindFirstChild(playerGui, "MenuUI")
                local menuLocal = menu and safeFindFirstChild(menu, "MenuLocal")
                local shared = menuLocal and safeFindFirstChild(menuLocal, "Shared")
                if shared then
                    local ok, result = pcall(require, shared)
                    if ok and type(result) == "table" then
                        cachedMenuShared = result
                        return cachedMenuShared
                    end
                end
                return nil
            end

            local function getLoadoutShared()
                local playerGui = safeFindFirstChild(LocalPlayer, "PlayerGui")
                local menu = playerGui and safeFindFirstChild(playerGui, "MenuUI")
                local menuLocal = menu and safeFindFirstChild(menu, "MenuLocal")
                local loadout = menuLocal and safeFindFirstChild(menuLocal, "Loadout")
                local loadoutShared = loadout and safeFindFirstChild(loadout, "LoadoutShared")
                if loadoutShared then
                    local ok, result = pcall(require, loadoutShared)
                    if ok and type(result) == "table" then
                        cachedLoadoutShared = result
                        return cachedLoadoutShared
                    end
                end
                return nil
            end

            local function getNetworkModule()
                local modules = safeFindFirstChild(ReplicatedStorage, "Modules")
                local networkModule = modules and safeFindFirstChild(modules, "NetworkModule2")
                if networkModule then
                    local ok, result = pcall(require, networkModule)
                    if ok and type(result) == "table" then
                        cachedNetworkModule = result
                        return cachedNetworkModule
                    end
                end
                return nil
            end

            local function getGlobalStuff()
                local modules = safeFindFirstChild(ReplicatedStorage, "Modules")
                local globalStuff = modules and safeFindFirstChild(modules, "GlobalStuff")
                if globalStuff then
                    local ok, result = pcall(require, globalStuff)
                    if ok and type(result) == "table" then
                        cachedGlobalStuff = result
                        return cachedGlobalStuff
                    end
                end
                return nil
            end

            local function collectCoreData()
                local results = {}
                local seen = {}
                local shared = getMenuShared()
                local function add(coreData)
                    if type(coreData) == "table" and not seen[coreData] then
                        seen[coreData] = true
                        table.insert(results, coreData)
                    end
                end
                if shared then
                    add(shared.CoreData)
                    add(shared.MenuCoreData)
                end
                if type(getgc) == "function" then
                    for _, item in pairs(getgc(true)) do
                        if type(item) == "table" then
                            if rawget(item, "OwnedPassives") then
                                add(item)
                            end
                            if type(rawget(item, "CoreData")) == "table" then
                                add(item.CoreData)
                            end
                            if type(rawget(item, "MenuCoreData")) == "table" then
                                add(item.MenuCoreData)
                            end
                        end
                    end
                end
                return results
            end

            local function getLoadoutIndex(coreData)
                local selected = tonumber(coreData and coreData.SelectedLoadoutIndex)
                return selected and selected > 0 and selected or 1
            end

            local function ensureLoadout(coreData)
                if type(coreData) ~= "table" then
                    return nil, 1
                end
                coreData.Loadouts = coreData.Loadouts or {}
                local index = getLoadoutIndex(coreData)
                coreData.Loadouts[index] = coreData.Loadouts[index] or {}
                coreData.Loadouts[index].Passives = coreData.Loadouts[index].Passives or {}
                return coreData.Loadouts[index], index
            end

            local function hasPassiveOption(passiveName)
                for _, option in ipairs(refreshPassiveOptions()) do
                    if option == passiveName then
                        return true
                    end
                end
                return false
            end

            local function choosePassiveSlots(coreData)
                local loadout = ensureLoadout(coreData)
                local first = loadout and loadout.Passives and loadout.Passives[1]
                local second = loadout and loadout.Passives and loadout.Passives[2]
                if not first or first == "None" then
                    first = hasPassiveOption("Air Slide") and "Air Slide" or passiveOptions[2] or "None"
                end
                if not second or second == "None" or second == first then
                    second = hasPassiveOption("Double Jump") and "Double Jump"
                        or passiveOptions[3]
                        or passiveOptions[2]
                        or "None"
                end
                if second == first then
                    second = "None"
                end
                return { first, second }
            end

            local function unlockAllPassives()
                passiveRuntimeNames = {}
                for _, passiveName in ipairs(refreshPassiveOptions()) do
                    if passiveName ~= "None" then
                        passiveRuntimeNames[passiveName] = true
                        passiveRuntimeNames[passiveKey(passiveName)] = true
                    end
                end
                for _, coreData in ipairs(collectCoreData()) do
                    coreData.OwnedPassives = coreData.OwnedPassives or {}
                    for passiveName in pairs(passiveRuntimeNames) do
                        coreData.OwnedPassives[passiveName] = true
                    end
                end
                return true
            end

            local function patchHasPassive()
                local globalStuff = getGlobalStuff()
                if not globalStuff or type(globalStuff.HasPassive) ~= "function" then
                    return false
                end
                if globalStuff._ZephyrOriginalHasPassive then
                    return true
                end
                globalStuff._ZephyrOriginalHasPassive = globalStuff.HasPassive
                globalStuff.HasPassive = function(self, player, passiveName, ...)
                    local ok, result = pcall(globalStuff._ZephyrOriginalHasPassive, self, player, passiveName, ...)
                    if ok and result then
                        return result
                    end
                    if passiveRuntimeEnabled and (player == LocalPlayer or player == LocalPlayer.Character) then
                        local key = passiveKey(passiveName)
                        if passiveRuntimeNames[passiveName] or passiveRuntimeNames[key] then
                            return true
                        end
                    end
                    return ok and result or false
                end
                return true
            end

            local function fireEquipPassive(loadoutIndex, slot, passiveName)
                if not passiveName or passiveName == "None" then
                    return
                end
                local networkModule = getNetworkModule()
                if networkModule and type(networkModule.FireServer) == "function" then
                    pcall(function()
                        networkModule:FireServer("EquipPassive", loadoutIndex, slot, passiveName)
                    end)
                end
            end

            local function syncPassiveSlots(slots)
                local char = LocalPlayer.Character
                for slot, passiveName in ipairs(slots) do
                    if passiveName and passiveName ~= "None" then
                        pcall(function()
                            LocalPlayer:SetAttribute("Passive" .. slot, passiveName)
                        end)
                        pcall(function()
                            LocalPlayer:SetAttribute("Passive" .. slot .. "Key", passiveKey(passiveName))
                        end)
                        if char then
                            pcall(function()
                                char:SetAttribute("Passive" .. slot, passiveName)
                            end)
                            pcall(function()
                                char:SetAttribute("Passive" .. slot .. "Key", passiveKey(passiveName))
                            end)
                        end
                    end
                end
            end

            local function applyBestEffortPassives()
                passiveRuntimeEnabled = true
                unlockAllPassives()
                patchHasPassive()

                local firstCoreData = collectCoreData()[1]
                local slots = choosePassiveSlots(firstCoreData or {})
                for _, coreData in ipairs(collectCoreData()) do
                    local loadout, index = ensureLoadout(coreData)
                    if loadout then
                        loadout.Passives[1] = slots[1]
                        loadout.Passives[2] = slots[2]
                        fireEquipPassive(index, 1, slots[1])
                        fireEquipPassive(index, 2, slots[2])
                    end
                end

                local loadoutShared = getLoadoutShared()
                if loadoutShared and firstCoreData then
                    local loadout, index = ensureLoadout(firstCoreData)
                    if loadout then
                        loadoutShared.EditingLoadout = loadout
                        loadoutShared.EditingLoadoutIndex = index
                    end
                end

                syncPassiveSlots(slots)
            end

            Runtime.connect(LocalPlayer.CharacterAdded, function()
                if passiveRuntimeEnabled then
                    task.wait(1)
                    applyBestEffortPassives()
                end
            end)

            refreshPassiveOptions()
            Tabs.Unlocks:AddButton("Unlock Passives", "", function()
                applyBestEffortPassives()
            end)
        end)
    end)

    pcall(function()
        local barrierEnabled = false
        Tabs.Misc:AddToggle("Remove Enemy Barrier", false, function(v)
            barrierEnabled = v
        end)
        task.spawn(function()
            while task.wait(10) do
                if barrierEnabled then
                    pcall(function()
                        local ff = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("Forcefields")
                        if ff then
                            ff:Destroy()
                        end
                    end)
                end
            end
        end)
    end)

    -- Unlocks
    local function findUnlockGcTable(limit, predicate)
        if type(getgc) ~= "function" or type(predicate) ~= "function" then
            return nil
        end
        local ok, values = pcall(getgc, true)
        if not ok or type(values) ~= "table" then
            return nil
        end
        local scanned = 0
        for _, value in pairs(values) do
            scanned += 1
            if scanned > (limit or 500) then
                break
            end
            if type(value) == "table" and predicate(value) then
                return value
            end
        end
        return nil
    end

    pcall(function()
        local function findGcTable(limit, predicate)
            return findUnlockGcTable(limit, predicate)
        end

        Tabs.Unlocks:AddButton("Unlock All Abilities", "Can't use in-game", function()
            pcall(function()
                local mods = ReplicatedStorage:FindFirstChild("Abilities")
                    and ReplicatedStorage.Abilities:FindFirstChild("Modules")
                if not mods then
                    return
                end
                local CoreData = findGcTable(650, function(v)
                    return rawget(v, "OwnedAbilities") and rawget(v, "WeeklyAbilities")
                end)
                if not CoreData then
                    return
                end
                local changed = 0
                for _, m in pairs(mods:GetChildren()) do
                    if m:IsA("ModuleScript") then
                        local ok, ab = pcall(require, m)
                        if ok and ab and ab.Name then
                            CoreData.OwnedAbilities[ab.Name] = true
                        end
                        changed += 1
                        if changed % 10 == 0 then
                            task.wait()
                        end
                    end
                end
            end)
        end)
    end)

    pcall(function()
        local selectedKillVFXName = "Midas Touch"
        local killVFXApplyEnabled = false
        local deathEffectBound = false
        local deathRemoteConn = nil
        local deathRemoteChildConn = nil
        local deathRunStamp = setmetatable({}, { __mode = "k" })

        local function unlockRequire(module)
            if not module or not module:IsA("ModuleScript") then
                return nil
            end
            local ok, result = pcall(require, module)
            return ok and result or nil
        end

        local function addUnique(list, seen, value)
            value = tostring(value or "")
            if value == "Template" or value == "Attachments" then
                return
            end
            if value ~= "" and not seen[value] then
                seen[value] = true
                table.insert(list, value)
            end
        end

        local function getKillVFXNames()
            local names, seen = {}, {}
            addUnique(names, seen, "Ragdoll")
            addUnique(names, seen, "Default")

            local root = ReplicatedStorage:FindFirstChild("KillVFX")
            local modules = root and root:FindFirstChild("Modules")
            if modules then
                for _, module in ipairs(modules:GetChildren()) do
                    if module:IsA("ModuleScript") then
                        addUnique(names, seen, module.Name)
                    end
                end
            end

            local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
            local deathHandler = playerGui
                and playerGui:FindFirstChild("GameUI")
                and playerGui.GameUI:FindFirstChild("Effects")
                and playerGui.GameUI.Effects:FindFirstChild("DeathHandler")
            local deathRoot = deathHandler and deathHandler:FindFirstChild("DeathEffect")
            if deathRoot then
                for _, module in ipairs(deathRoot:GetDescendants()) do
                    if module:IsA("ModuleScript") then
                        addUnique(names, seen, module.Name)
                    end
                end
            end

            table.sort(names, function(a, b)
                local function priority(name)
                    if name == "Midas Touch" then
                        return 0
                    end
                    if name == "Default" or name == "Ragdoll" or name == "None" or name == "Random" then
                        return 2
                    end
                    return 1
                end
                local pa, pb = priority(a), priority(b)
                if pa ~= pb then
                    return pa < pb
                end
                return a:lower() < b:lower()
            end)
            return names
        end

        local function collectKillCoreData()
            local result, seen = {}, {}
            local function add(coreData)
                if type(coreData) == "table" and not seen[coreData] then
                    seen[coreData] = true
                    table.insert(result, coreData)
                end
            end

            local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
            local menuUI = playerGui and playerGui:FindFirstChild("MenuUI")
            local menuLocal = menuUI and menuUI:FindFirstChild("MenuLocal")
            local shared = unlockRequire(menuLocal and menuLocal:FindFirstChild("Shared"))
            if type(shared) == "table" then
                add(shared.CoreData)
                add(shared.MenuCoreData)
            end

            add(findUnlockGcTable(850, function(value)
                return rawget(value, "OwnedKillVFX") ~= nil or rawget(value, "Loadouts") ~= nil
            end))
            return result
        end

        local function unlockAllKillVFXInCoreData(coreData)
            if type(coreData) ~= "table" then
                return
            end
            if type(coreData.OwnedKillVFX) ~= "table" then
                coreData.OwnedKillVFX = {}
            end

            local modules = ReplicatedStorage:FindFirstChild("KillVFX")
                and ReplicatedStorage.KillVFX:FindFirstChild("Modules")
            if modules then
                local changed = 0
                for _, module in ipairs(modules:GetChildren()) do
                    if module:IsA("ModuleScript") then
                        coreData.OwnedKillVFX[module.Name] = true
                        changed += 1
                        if changed % 12 == 0 then
                            task.wait()
                        end
                    end
                end
            end
            for _, name in ipairs(getKillVFXNames()) do
                coreData.OwnedKillVFX[name] = true
            end
            coreData.OwnedKillVFX[selectedKillVFXName] = true
        end

        local function applyKillVFXToCoreData(coreData)
            if type(coreData) ~= "table" or not selectedKillVFXName then
                return
            end
            coreData.EquippedKillVFX = selectedKillVFXName
            coreData.KillVFX = selectedKillVFXName
            coreData.DeathEffect = selectedKillVFXName
            coreData.DeathEffectName = selectedKillVFXName

            if type(coreData.Loadouts) == "table" then
                for _, loadout in pairs(coreData.Loadouts) do
                    if type(loadout) == "table" then
                        loadout.KillVFX = selectedKillVFXName
                        loadout.DeathEffect = selectedKillVFXName
                        loadout.DeathEffectName = selectedKillVFXName
                    end
                end
            end
        end

        local function patchKillVFXChooser()
            local modules = ReplicatedStorage:FindFirstChild("Modules")
            local globalStuff = modules and unlockRequire(modules:FindFirstChild("GlobalStuff"))
            if type(globalStuff) ~= "table" or type(globalStuff.GetRandomKillVFX) ~= "function" then
                return
            end
            if globalStuff._ZephyrOriginalGetRandomKillVFX then
                return
            end

            globalStuff._ZephyrOriginalGetRandomKillVFX = globalStuff.GetRandomKillVFX
            globalStuff.GetRandomKillVFX = function(self, ...)
                if killVFXApplyEnabled and selectedKillVFXName and selectedKillVFXName ~= "" then
                    return selectedKillVFXName
                end
                return globalStuff._ZephyrOriginalGetRandomKillVFX(self, ...)
            end
        end

        local function getDeathHandlerRoot()
            local function scan(container)
                if not container then
                    return nil
                end
                for _, obj in ipairs(container:GetDescendants()) do
                    if obj.Name == "DeathHandler" and obj:IsA("ModuleScript") and obj:FindFirstChild("DeathEffect") then
                        return obj
                    end
                end
                return nil
            end

            local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
            local gameUI = playerGui and playerGui:FindFirstChild("GameUI")
            local effects = gameUI and gameUI:FindFirstChild("Effects")
            local deathHandler = effects and effects:FindFirstChild("DeathHandler")
            if deathHandler then
                return deathHandler
            end
            deathHandler = scan(playerGui)
            if deathHandler then
                return deathHandler
            end

            local starterGui = game:GetService("StarterGui")
            gameUI = starterGui and starterGui:FindFirstChild("GameUI")
            effects = gameUI and gameUI:FindFirstChild("Effects")
            deathHandler = effects and effects:FindFirstChild("DeathHandler")
            if deathHandler then
                return deathHandler
            end
            return scan(starterGui)
        end

        local function getSelectedDeathEffectName()
            local name = tostring(selectedKillVFXName or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" or name == "None" then
                return nil
            end
            if name == "Random" then
                return "Midas Touch"
            end
            return name
        end

        local function resolveDeathEffectModule(effectName)
            local deathHandler = getDeathHandlerRoot()
            if not deathHandler then
                return nil, effectName
            end

            local exact = deathHandler:FindFirstChild(effectName, true)
            if exact and exact:IsA("ModuleScript") and exact.Name ~= "Template" and exact.Name ~= "Attachments" then
                return exact, effectName
            end

            local deathRoot = deathHandler:FindFirstChild("DeathEffect")
            local default = deathRoot and deathRoot:FindFirstChild("Default")
            if default and default:IsA("ModuleScript") then
                return default, effectName
            end

            return nil, effectName
        end

        local function runSelectedDeathEffect(character, deathArgs)
            if not killVFXApplyEnabled or typeof(character) ~= "Instance" then
                return false
            end
            local effectName = getSelectedDeathEffectName()
            if not effectName then
                return false
            end

            local now = os.clock()
            local last = deathRunStamp[character]
            if last and last.name == effectName and (now - last.time) < 0.2 then
                return true
            end
            deathRunStamp[character] = { name = effectName, time = now }

            pcall(function()
                character:SetAttribute("DeathEffect", effectName)
            end)

            if character == LocalPlayer.Character then
                task.wait(0.1)
            end

            local effectModule, effectDataName = resolveDeathEffectModule(effectName)
            if not effectModule then
                return false
            end

            local effectClass = unlockRequire(effectModule)
            if type(effectClass) ~= "table" or type(effectClass.new) ~= "function" then
                return false
            end

            local ok, effect = pcall(function()
                return effectClass.new(character, table.unpack(deathArgs or {}))
            end)
            if ok and type(effect) == "table" then
                effect.DeathEffectName = effectDataName or effectName
                if type(effect.RunEffect) == "function" then
                    pcall(function()
                        effect:RunEffect()
                    end)
                    return true
                end
            end

            return false
        end

        local function connectDeathRemoteFallback()
            if deathRemoteConn then
                return
            end
            local network = ReplicatedStorage:FindFirstChild("Network")
            local clientRemotes = network and network:FindFirstChild("ClientRemotes")
            if not clientRemotes then
                return
            end

            local function hook(remote)
                if deathRemoteConn or not remote or not remote:IsA("RemoteEvent") then
                    return
                end
                deathRemoteConn = Runtime.connect(remote.OnClientEvent, function(character, ...)
                    if killVFXApplyEnabled then
                        local args = { ... }
                        pcall(function()
                            runSelectedDeathEffect(character, args)
                        end)
                    end
                end)
            end

            hook(clientRemotes:FindFirstChild("DeathEffect"))
            if not deathRemoteConn and not deathRemoteChildConn then
                deathRemoteChildConn = Runtime.connect(clientRemotes.ChildAdded, function(child)
                    if child.Name == "DeathEffect" then
                        hook(child)
                    end
                end)
            end
        end

        local function bindDeathEffectOverride()
            local modules = ReplicatedStorage:FindFirstChild("Modules")
            local network = modules and unlockRequire(modules:FindFirstChild("NetworkModule2"))
            if type(network) ~= "table" or type(network.ClientBind) ~= "function" then
                return
            end

            network:ClientBind("DeathEffect", function(character, ...)
                local deathArgs = { ... }
                runSelectedDeathEffect(character, deathArgs)
            end)

            deathEffectBound = true
        end

        local function applyKillVFXUnlocks()
            killVFXApplyEnabled = true
            patchKillVFXChooser()
            bindDeathEffectOverride()
            connectDeathRemoteFallback()
            for _, delayTime in ipairs({ 0.6, 1.6, 3 }) do
                task.delay(delayTime, function()
                    if killVFXApplyEnabled then
                        bindDeathEffectOverride()
                        connectDeathRemoteFallback()
                    end
                end)
            end
            for _, coreData in ipairs(collectKillCoreData()) do
                unlockAllKillVFXInCoreData(coreData)
                applyKillVFXToCoreData(coreData)
                task.wait()
            end
        end

        local killVFXOptions = getKillVFXNames()
        Tabs.Unlocks:AddDropdown("Kill VFX To Apply", killVFXOptions, selectedKillVFXName, function(value)
            selectedKillVFXName = tostring(value or selectedKillVFXName)
            if killVFXApplyEnabled then
                task.spawn(applyKillVFXUnlocks)
            end
        end)

        Tabs.Unlocks:AddInput("Custom Kill VFX", "Exact effect name", function(value)
            value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if value ~= "" then
                selectedKillVFXName = value
            end
        end)

        Tabs.Unlocks:AddButton("Unlock All VFX", "Client inventory + selected effect", function()
            task.spawn(applyKillVFXUnlocks)
        end)

        Tabs.Unlocks:AddButton("Apply Kill VFX", "Forces chosen effect locally", function()
            task.spawn(applyKillVFXUnlocks)
        end)
    end)

    pcall(function()
        local killIconsUnlocked = false
        local selectedKillIconName = "Default"

        local function iconRequire(module)
            if not module or not module:IsA("ModuleScript") then
                return nil
            end
            local ok, result = pcall(require, module)
            return ok and result or nil
        end

        local function getKillIconNames()
            local names, seen = {}, {}
            local modules = ReplicatedStorage:FindFirstChild("KillIcons")
                and ReplicatedStorage.KillIcons:FindFirstChild("Modules")
            if modules then
                for _, module in ipairs(modules:GetChildren()) do
                    if module:IsA("ModuleScript") and not seen[module.Name] then
                        seen[module.Name] = true
                        table.insert(names, module.Name)
                    end
                end
            end
            table.sort(names, function(a, b)
                if a == "Default" then
                    return true
                end
                if b == "Default" then
                    return false
                end
                return a:lower() < b:lower()
            end)
            selectedKillIconName = names[1] or selectedKillIconName
            return names
        end

        local function collectIconCoreData()
            local result, seen = {}, {}
            local function add(coreData)
                if type(coreData) == "table" and not seen[coreData] then
                    seen[coreData] = true
                    table.insert(result, coreData)
                end
            end

            local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
            local menuUI = playerGui and playerGui:FindFirstChild("MenuUI")
            local menuLocal = menuUI and menuUI:FindFirstChild("MenuLocal")
            local shared = iconRequire(menuLocal and menuLocal:FindFirstChild("Shared"))
            if type(shared) == "table" then
                add(shared.CoreData)
                add(shared.MenuCoreData)
            end

            add(findUnlockGcTable(850, function(value)
                return rawget(value, "OwnedKillIcons") ~= nil or rawget(value, "Loadouts") ~= nil
            end))
            return result
        end

        local function unlockKillIconsInCoreData(coreData, on)
            if type(coreData) ~= "table" then
                return
            end
            if type(coreData.OwnedKillIcons) ~= "table" then
                coreData.OwnedKillIcons = {}
            end
            local modules = ReplicatedStorage:FindFirstChild("KillIcons")
                and ReplicatedStorage.KillIcons:FindFirstChild("Modules")
            if not modules then
                return
            end
            local changed = 0
            for _, module in ipairs(modules:GetChildren()) do
                if module:IsA("ModuleScript") then
                    coreData.OwnedKillIcons[module.Name] = on and true or nil
                    changed += 1
                    if changed % 20 == 0 then
                        task.wait()
                    end
                end
            end
            if on and selectedKillIconName then
                coreData.OwnedKillIcons[selectedKillIconName] = true
            end
        end

        local function applyKillIconToCoreData(coreData)
            if type(coreData) ~= "table" or not selectedKillIconName then
                return
            end
            coreData.KillIcon = selectedKillIconName
            coreData.EquippedKillIcon = selectedKillIconName
            if type(coreData.Loadouts) == "table" then
                for _, loadout in pairs(coreData.Loadouts) do
                    if type(loadout) == "table" then
                        loadout.KillIcon = selectedKillIconName
                    end
                end
            end
        end

        local function refreshKillIconUI()
            local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
            local menuUI = playerGui and playerGui:FindFirstChild("MenuUI")
            local menuLocal = menuUI and menuUI:FindFirstChild("MenuLocal")
            local loadout = menuLocal and menuLocal:FindFirstChild("Loadout")
            local loadoutShared = iconRequire(loadout and loadout:FindFirstChild("LoadoutShared"))
            if type(loadoutShared) == "table" and type(loadoutShared.EditingLoadout) == "table" then
                loadoutShared.EditingLoadout.KillIcon = selectedKillIconName
            end

            local selection = iconRequire(loadout and loadout:FindFirstChild("KillIconSelection"))
            if type(selection) == "table" then
                if type(selection.RefreshLoadoutKillIcon) == "function" then
                    pcall(function()
                        selection:RefreshLoadoutKillIcon()
                    end)
                end
                if type(selection.RefreshSelection) == "function" then
                    pcall(function()
                        selection:RefreshSelection()
                    end)
                end
            end
        end

        local function applyKillIconUnlocks(on)
            killIconsUnlocked = on
            for _, coreData in ipairs(collectIconCoreData()) do
                unlockKillIconsInCoreData(coreData, on)
                if on then
                    applyKillIconToCoreData(coreData)
                end
                task.wait()
            end
            if on then
                refreshKillIconUI()
            end
        end

        local killIconOptions = getKillIconNames()
        Tabs.Unlocks:AddDropdown("Kill Icon To Apply", killIconOptions, selectedKillIconName, function(value)
            selectedKillIconName = tostring(value or selectedKillIconName)
            if killIconsUnlocked then
                task.spawn(function()
                    applyKillIconUnlocks(true)
                end)
            end
        end)

        Tabs.Unlocks:AddInput("Custom Kill Icon", "Exact icon name", function(value)
            value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if value ~= "" then
                selectedKillIconName = value
            end
        end)

        Tabs.Unlocks:AddToggle("Unlock Kill Icons", false, function(on)
            task.spawn(function()
                applyKillIconUnlocks(on)
            end)
        end)

        Tabs.Unlocks:AddButton("Apply Kill Icon", "Client loadout icon", function()
            task.spawn(function()
                applyKillIconUnlocks(true)
            end)
        end)
    end)

    pcall(function()
        local skinsUnlocked = false
        local weaponsUnlocked = false
        local selectedSkinApplyEnabled = false
        local selectedSkinName = "Rainbow"
        local cachedGunSkins = nil
        local cachedWeaponNames = nil
        local skinApplyBusy = false
        local skinEquipPatched = false
        local SKIN_MAX_GC_ITEMS = 450
        local SAFE_SKIN_OPTIONS = {
            "Rainbow",
            "Rainbow Camo",
            "Army Camo",
            "Gold",
            "Diamond",
            "Galaxy",
            "Lava",
            "Ice",
            "Red",
            "Blue",
        }

        local function requireModule(module)
            return requireSafe(module)
        end

        local function forLimitedGcTables(callback)
            if type(getgc) ~= "function" or type(callback) ~= "function" then
                return
            end
            local ok, values = pcall(getgc, true)
            if not ok or type(values) ~= "table" then
                return
            end
            local scanned = 0
            for _, value in pairs(values) do
                scanned += 1
                if scanned > SKIN_MAX_GC_ITEMS then
                    break
                end
                if type(value) == "table" and callback(value) == true then
                    break
                end
            end
        end

        local function getGunSkins()
            if cachedGunSkins then
                return cachedGunSkins
            end
            local modules = safeFindFirstChild(ReplicatedStorage, "Modules")
            local skinModules = modules and safeFindFirstChild(modules, "SkinModules")
            local skinModule = skinModules and safeFindFirstChild(skinModules, "SkinModule")
            local gunSkinsModule = skinModule and safeFindFirstChild(skinModule, "GunSkins")
            local gunSkins = requireModule(gunSkinsModule)

            if type(gunSkins) ~= "table" then
                forLimitedGcTables(function(value)
                    if type(value) == "table" and rawget(value, "Army Camo") and rawget(value, "Rainbow") then
                        gunSkins = value
                        return true
                    end
                end)
            end

            if type(gunSkins) == "table" then
                cachedGunSkins = gunSkins
            end
            return cachedGunSkins
        end

        local function getSkinNames()
            -- Listing every skin makes this dropdown lag.
            local names = table.clone and table.clone(SAFE_SKIN_OPTIONS) or {}
            if #names == 0 then
                for _, name in ipairs(SAFE_SKIN_OPTIONS) do
                    table.insert(names, name)
                end
            end
            table.sort(names)
            if table.find(names, "Rainbow") then
                selectedSkinName = "Rainbow"
            elseif table.find(names, "Rainbow Camo") then
                selectedSkinName = "Rainbow Camo"
            else
                selectedSkinName = names[1]
            end
            return names
        end

        local function getWeaponNames()
            if cachedWeaponNames then
                return cachedWeaponNames
            end
            local names, seen = {}, {}
            local weapons = safeFindFirstChild(ReplicatedStorage, "Weapons")
            local assets = weapons and safeFindFirstChild(weapons, "Assets")
            local modules = weapons and safeFindFirstChild(weapons, "Modules")

            local function add(name)
                if type(name) == "string" and name ~= "" and not seen[name] then
                    seen[name] = true
                    table.insert(names, name)
                end
            end

            if assets then
                for _, weapon in ipairs(assets:GetChildren()) do
                    add(weapon.Name)
                end
            end
            if modules then
                for _, weapon in ipairs(modules:GetChildren()) do
                    if weapon:IsA("ModuleScript") then
                        add(weapon.Name)
                    end
                end
            end

            table.sort(names)
            cachedWeaponNames = names
            return cachedWeaponNames
        end

        local function getMenuLoadoutModules()
            local playerGui = safeFindFirstChild(LocalPlayer, "PlayerGui")
            local menu = playerGui and safeFindFirstChild(playerGui, "MenuUI")
            local menuLocal = menu and safeFindFirstChild(menu, "MenuLocal")
            local loadout = menuLocal and safeFindFirstChild(menuLocal, "Loadout")
            return {
                Loadout = loadout,
                Shared = requireModule(menuLocal and safeFindFirstChild(menuLocal, "Shared")),
                LoadoutShared = requireModule(loadout and safeFindFirstChild(loadout, "LoadoutShared")),
                WeaponSelection = requireModule(loadout and safeFindFirstChild(loadout, "WeaponSelection")),
                LoadoutSelection = requireModule(loadout and safeFindFirstChild(loadout, "LoadoutSelection")),
            }
        end

        local function getSkinUUID(coreData, weaponName, skinName)
            if type(coreData) ~= "table" then
                return nil
            end
            local skinsTable = type(coreData.Skins) == "table" and coreData.Skins or nil
            local skins = skinsTable and rawget(skinsTable, weaponName)
            if type(skins) == "table" then
                for _, skin in pairs(skins) do
                    if
                        type(skin) == "table"
                        and (skin.Name == skinName or skin.SkinName == skinName or skin[1] == skinName)
                    then
                        return skin.UUID or skin[2]
                    end
                end
            end
            local ok, guid = pcall(function()
                return HttpService:GenerateGUID(false)
            end)
            if ok and guid then
                return guid
            end
            return tostring(math.random(100000, 999999)) .. "-" .. tostring(math.random(100000, 999999))
        end

        local function skinPack(coreData, weaponName, skinName)
            return {
                skinName,
                getSkinUUID(coreData, weaponName, skinName),
                false,
                nil,
            }
        end

        local function weaponSupportsSkin(weaponName)
            local globalStuff = getGlobalStuff()
            if globalStuff and type(globalStuff.GetWSettings) == "function" then
                local ok, settings = pcall(function()
                    return globalStuff:GetWSettings(weaponName)
                end)
                if ok and type(settings) == "table" and settings.NoSkin then
                    return false
                end
            end
            return true
        end

        local function makeSkinRecord(coreData, weaponName, skinName)
            local uuid = getSkinUUID(coreData, weaponName, skinName)
            return {
                Name = skinName,
                UUID = uuid,
                SkinName = skinName,
                IsCE = false,
                Aura = nil,
                [1] = skinName,
                [2] = uuid,
                [3] = false,
                [4] = nil,
            }
        end

        local function addSkinIfMissing(coreData, weaponName, skinName)
            if
                type(coreData) ~= "table"
                or type(weaponName) ~= "string"
                or weaponName == ""
                or type(skinName) ~= "string"
                or skinName == ""
            then
                return false
            end
            coreData.Skins = type(coreData.Skins) == "table" and coreData.Skins or {}
            local list = rawget(coreData.Skins, weaponName)
            if type(list) ~= "table" then
                list = {}
                rawset(coreData.Skins, weaponName, list)
            end
            for _, skin in pairs(list) do
                if
                    type(skin) == "table"
                    and (skin.Name == skinName or skin.SkinName == skinName or skin[1] == skinName)
                then
                    return false
                end
            end
            table.insert(list, makeSkinRecord(coreData, weaponName, skinName))
            return true
        end

        local function getWeaponNameFromEntry(key, entry)
            if type(entry) == "table" then
                if type(entry.Name) == "string" and entry.Name ~= "" then
                    return entry.Name
                end
                if type(entry.ID) == "string" and entry.ID ~= "" then
                    return entry.ID
                end
                if type(entry.Data) == "table" then
                    if type(entry.Data.ID) == "string" and entry.Data.ID ~= "" then
                        return entry.Data.ID
                    end
                    if type(entry.Data.Name) == "string" and entry.Data.Name ~= "" then
                        return entry.Data.Name
                    end
                end
            elseif type(entry) == "string" and entry ~= "" then
                return entry
            end
            if type(key) == "string" and key ~= "" then
                return key
            end
            return nil
        end

        local function putSkinIntoWeaponEntry(entry, skinName)
            if type(entry) ~= "table" or not skinName then
                return
            end
            entry.SkinName = skinName
            entry.Skin = skinName
            entry.IsCE = false
            entry.Aura = nil
            entry.SkinData = {
                SkinName = skinName,
                IsCE = false,
                Aura = nil,
            }
            if type(entry.Data) == "table" then
                entry.Data.SkinName = skinName
                entry.Data.Skin = skinName
                entry.Data.IsCE = false
                entry.Data.Aura = nil
            end
        end

        local function collectCoreDataForSkins()
            local results, seen = {}, {}
            local function add(coreData)
                if type(coreData) == "table" and not seen[coreData] then
                    if
                        rawget(coreData, "Loadouts")
                        or rawget(coreData, "Weapons")
                        or rawget(coreData, "OwnedWeapons")
                        or rawget(coreData, "EquippedSkins")
                        or rawget(coreData, "Skins")
                    then
                        seen[coreData] = true
                        table.insert(results, coreData)
                    end
                end
            end

            local playerGui = safeFindFirstChild(LocalPlayer, "PlayerGui")
            local menu = playerGui and safeFindFirstChild(playerGui, "MenuUI")
            local menuLocal = menu and safeFindFirstChild(menu, "MenuLocal")
            local menuShared = requireModule(menuLocal and safeFindFirstChild(menuLocal, "Shared"))
            if type(menuShared) == "table" then
                add(menuShared.CoreData)
                add(menuShared.MenuCoreData)
            end

            local firstPerson = playerGui and safeFindFirstChild(playerGui, "FirstPersonGUI")
            local actionHandler = firstPerson and safeFindFirstChild(firstPerson, "ActionHandler")
            local firstPersonShared = requireModule(actionHandler and safeFindFirstChild(actionHandler, "Shared"))
            if type(firstPersonShared) == "table" then
                add(firstPersonShared.CoreData)
                add(firstPersonShared.MenuCoreData)
            end

            local controllerShared = getControllerShared()
            if type(controllerShared) == "table" then
                add(controllerShared.CoreData)
                add(controllerShared.MenuCoreData)
            end

            forLimitedGcTables(function(value)
                add(value)
                add(rawget(value, "CoreData"))
                add(rawget(value, "MenuCoreData"))
                return #results >= 5
            end)

            return results
        end

        local function collectFastCoreDataForSkins()
            local results, seen = {}, {}
            local function add(coreData)
                if type(coreData) == "table" and not seen[coreData] then
                    if
                        rawget(coreData, "Loadouts")
                        or rawget(coreData, "Weapons")
                        or rawget(coreData, "OwnedWeapons")
                        or rawget(coreData, "EquippedSkins")
                        or rawget(coreData, "Skins")
                    then
                        seen[coreData] = true
                        table.insert(results, coreData)
                    end
                end
            end

            local playerGui = safeFindFirstChild(LocalPlayer, "PlayerGui")
            local menu = playerGui and safeFindFirstChild(playerGui, "MenuUI")
            local menuLocal = menu and safeFindFirstChild(menu, "MenuLocal")
            local menuShared = requireModule(menuLocal and safeFindFirstChild(menuLocal, "Shared"))
            if type(menuShared) == "table" then
                add(menuShared.CoreData)
                add(menuShared.MenuCoreData)
            end

            local firstPerson = playerGui and safeFindFirstChild(playerGui, "FirstPersonGUI")
            local actionHandler = firstPerson and safeFindFirstChild(firstPerson, "ActionHandler")
            local firstPersonShared = requireModule(actionHandler and safeFindFirstChild(actionHandler, "Shared"))
            if type(firstPersonShared) == "table" then
                add(firstPersonShared.CoreData)
                add(firstPersonShared.MenuCoreData)
            end

            local controllerShared = getControllerShared()
            if type(controllerShared) == "table" then
                add(controllerShared.CoreData)
                add(controllerShared.MenuCoreData)
            end

            return results
        end

        local function unlockAllWeaponsInCoreData(coreData)
            if type(coreData) ~= "table" then
                return false
            end

            coreData.OwnedWeapons = type(coreData.OwnedWeapons) == "table" and coreData.OwnedWeapons or {}
            coreData.ItemIndex = type(coreData.ItemIndex) == "table" and coreData.ItemIndex or {}
            coreData.ItemIndex.Weapons = type(coreData.ItemIndex.Weapons) == "table" and coreData.ItemIndex.Weapons
                or {}

            local touched = false
            local touchedCount = 0
            local globalStuff = getGlobalStuff()
            for _, weaponName in ipairs(getWeaponNames()) do
                touchedCount += 1
                if coreData.OwnedWeapons[weaponName] ~= true then
                    coreData.OwnedWeapons[weaponName] = true
                    touched = true
                end
                coreData.ItemIndex.Weapons[weaponName] = true
                if globalStuff and type(globalStuff.GetWSettings) == "function" then
                    local ok, settings = pcall(function()
                        return globalStuff:GetWSettings(weaponName)
                    end)
                    if ok and type(settings) == "table" then
                        local weaponId = settings.ID or settings.ItemID or settings.ImageID
                        if type(weaponId) == "string" or type(weaponId) == "number" then
                            coreData.ItemIndex.Weapons[weaponId] = true
                        end
                    end
                end
                if touchedCount % 18 == 0 then
                    task.wait()
                end
            end

            return touched
        end

        local function patchWeaponUnlockChecks()
            local modules = safeFindFirstChild(ReplicatedStorage, "Modules")
            local menuMod = requireModule(modules and safeFindFirstChild(modules, "MenuMod"))
            if
                type(menuMod) == "table"
                and type(menuMod.IsWeaponUnlocked) == "function"
                and not menuMod._ZephyrOriginalIsWeaponUnlocked
            then
                menuMod._ZephyrOriginalIsWeaponUnlocked = menuMod.IsWeaponUnlocked
                menuMod.IsWeaponUnlocked = function(self, weaponName, coreData, ...)
                    if weaponsUnlocked and type(weaponName) == "string" then
                        return true
                    end
                    return menuMod._ZephyrOriginalIsWeaponUnlocked(self, weaponName, coreData, ...)
                end
            end

            local globalStuff = getGlobalStuff()
            if
                type(globalStuff) == "table"
                and type(globalStuff.IsAdminUnlockAllLoadout) == "function"
                and not globalStuff._ZephyrOriginalIsAdminUnlockAllLoadout
            then
                globalStuff._ZephyrOriginalIsAdminUnlockAllLoadout = globalStuff.IsAdminUnlockAllLoadout
                globalStuff.IsAdminUnlockAllLoadout = function(self, ...)
                    if weaponsUnlocked then
                        return true
                    end
                    return globalStuff._ZephyrOriginalIsAdminUnlockAllLoadout(self, ...)
                end
            end
        end

        local function refreshLoadoutMenu()
            local mods = getMenuLoadoutModules()
            local weaponSelection = mods.WeaponSelection
            local loadoutSelection = mods.LoadoutSelection

            pcall(function()
                if type(weaponSelection) == "table" and type(weaponSelection.RefreshLoadout) == "function" then
                    weaponSelection:RefreshLoadout()
                end
            end)

            pcall(function()
                if type(loadoutSelection) == "table" and type(loadoutSelection.RefreshLoadout) == "function" then
                    loadoutSelection:RefreshLoadout()
                end
            end)
        end

        local function unlockAllWeapons()
            weaponsUnlocked = true
            patchWeaponUnlockChecks()
            for _, coreData in ipairs(collectCoreDataForSkins()) do
                unlockAllWeaponsInCoreData(coreData)
                task.wait()
            end
            refreshLoadoutMenu()
        end

        local collectLiveSharedTables

        local function getSelectedMenuWeapon()
            local playerGui = safeFindFirstChild(LocalPlayer, "PlayerGui")
            local menu = playerGui and safeFindFirstChild(playerGui, "MenuUI")
            local menuLocal = menu and safeFindFirstChild(menu, "MenuLocal")
            local loadout = menuLocal and safeFindFirstChild(menuLocal, "Loadout")
            local loadoutShared = loadout and safeFindFirstChild(loadout, "LoadoutShared")
            local shared = requireModule(loadoutShared)
            if type(shared) == "table" and type(shared.SelectedWeapon) == "string" and shared.SelectedWeapon ~= "" then
                return shared.SelectedWeapon
            end
            return nil
        end

        local function getRelevantWeaponNames(coreData)
            local names, seen = {}, {}
            local function add(name)
                if type(name) == "string" and name ~= "" and not seen[name] and weaponSupportsSkin(name) then
                    seen[name] = true
                    table.insert(names, name)
                end
            end

            add(getSelectedMenuWeapon())

            if type(coreData) == "table" then
                local selectedLoadoutIndex = tonumber(coreData.SelectedLoadoutIndex) or 1
                local loadout = type(coreData.Loadouts) == "table" and coreData.Loadouts[selectedLoadoutIndex]
                if type(loadout) == "table" and type(loadout.Weapons) == "table" then
                    for _, weaponName in pairs(loadout.Weapons) do
                        add(weaponName)
                    end
                end
            end

            for _, shared in ipairs(collectLiveSharedTables()) do
                if type(shared.Tools) == "table" then
                    for _, tool in pairs(shared.Tools) do
                        if type(tool) == "table" then
                            add(tool.Name)
                        end
                    end
                end
            end

            return names
        end

        local function fillAllSkinsForWeapon(coreData, weaponName)
            if type(coreData) ~= "table" or type(weaponName) ~= "string" or weaponName == "" then
                return false
            end
            if not weaponSupportsSkin(weaponName) then
                return false
            end
            local gunSkins = getGunSkins()
            if type(gunSkins) ~= "table" then
                return false
            end
            coreData.Skins = type(coreData.Skins) == "table" and coreData.Skins or {}
            local touched = false
            for skinName in pairs(gunSkins) do
                if addSkinIfMissing(coreData, weaponName, skinName) then
                    touched = true
                end
            end
            return touched
        end

        local function unlockAndApplySkinsToCoreData(coreData, applySelected)
            if type(coreData) ~= "table" then
                return false
            end
            local gunSkins = getGunSkins()
            if type(gunSkins) ~= "table" then
                return false
            end

            coreData.Skins = type(coreData.Skins) == "table" and coreData.Skins or {}
            coreData.EquippedSkins = type(coreData.EquippedSkins) == "table" and coreData.EquippedSkins or {}
            coreData.EquippedWeaponItems = type(coreData.EquippedWeaponItems) == "table"
                    and coreData.EquippedWeaponItems
                or {}

            local touched = false
            local weaponsToTouch, seenWeapons = {}, {}
            local function addWeapon(name)
                if type(name) == "string" and name ~= "" and not seenWeapons[name] and weaponSupportsSkin(name) then
                    seenWeapons[name] = true
                    table.insert(weaponsToTouch, name)
                end
            end

            if applySelected then
                for _, weaponName in ipairs(getRelevantWeaponNames(coreData)) do
                    addWeapon(weaponName)
                end
            elseif type(coreData.Loadouts) == "table" then
                for _, loadout in pairs(coreData.Loadouts) do
                    if type(loadout) == "table" and type(loadout.Weapons) == "table" then
                        for _, weaponName in pairs(loadout.Weapons) do
                            addWeapon(weaponName)
                        end
                    end
                end
            end

            if type(coreData.Weapons) == "table" then
                for key, entry in pairs(coreData.Weapons) do
                    addWeapon(getWeaponNameFromEntry(key, entry))
                end
            end

            local skinIsKnown = selectedSkinName ~= nil and selectedSkinName ~= ""
            if applySelected and selectedSkinName and skinIsKnown then
                local touchedCount = 0
                for _, weaponName in ipairs(weaponsToTouch) do
                    touchedCount += 1
                    if touchedCount % 8 == 0 then
                        task.wait()
                    end
                    addSkinIfMissing(coreData, weaponName, selectedSkinName)
                    coreData.EquippedSkins[weaponName] = skinPack(coreData, weaponName, selectedSkinName)
                    touched = true
                end
            elseif not applySelected then
                for _, weaponName in ipairs(getWeaponNames()) do
                    if fillAllSkinsForWeapon(coreData, weaponName) then
                        touched = true
                    end
                    task.wait()
                end
            end

            if applySelected and type(coreData.Weapons) == "table" and selectedSkinName and skinIsKnown then
                local touchedWeaponEntries = 0
                for key, entry in pairs(coreData.Weapons) do
                    touchedWeaponEntries += 1
                    local weaponName = getWeaponNameFromEntry(key, entry)
                    if weaponName and weaponSupportsSkin(weaponName) then
                        putSkinIntoWeaponEntry(entry, selectedSkinName)
                        touched = true
                    end
                end
            end

            return touched
        end

        function collectLiveSharedTables()
            local sharedTables, seen = {}, {}
            local function add(shared)
                if type(shared) == "table" and not seen[shared] then
                    seen[shared] = true
                    table.insert(sharedTables, shared)
                end
            end

            local playerGui = safeFindFirstChild(LocalPlayer, "PlayerGui")
            local firstPerson = playerGui and safeFindFirstChild(playerGui, "FirstPersonGUI")
            local actionHandler = firstPerson and safeFindFirstChild(firstPerson, "ActionHandler")
            add(requireModule(actionHandler and safeFindFirstChild(actionHandler, "Shared")))

            add(getControllerShared())

            return sharedTables
        end

        local function getViewModelModule()
            local playerGui = safeFindFirstChild(LocalPlayer, "PlayerGui")
            local firstPerson = playerGui and safeFindFirstChild(playerGui, "FirstPersonGUI")
            local actionHandler = firstPerson and safeFindFirstChild(firstPerson, "ActionHandler")
            local viewModelModule = actionHandler and safeFindFirstChild(actionHandler, "ViewModel")
            local result = requireModule(viewModelModule)
            return type(result) == "table" and result or nil
        end

        local function getSkinModule()
            local modules = safeFindFirstChild(ReplicatedStorage, "Modules")
            local skinModules = modules and safeFindFirstChild(modules, "SkinModules")
            local skinModule = skinModules and safeFindFirstChild(skinModules, "SkinModule")
            local result = requireModule(skinModule)
            return type(result) == "table" and result or nil
        end

        local function patchSkinEquipPath()
            if skinEquipPatched then
                return
            end
            local viewModel = getViewModelModule()
            if
                type(viewModel) == "table"
                and type(viewModel.Equip) == "function"
                and not viewModel._ZephyrOriginalSkinEquip
            then
                viewModel._ZephyrOriginalSkinEquip = viewModel.Equip
                viewModel.Equip = function(self, tool, sameTool, ...)
                    Runtime.before(function()
                        if
                            selectedSkinApplyEnabled
                            and type(tool) == "table"
                            and type(tool.Name) == "string"
                            and selectedSkinName
                            and selectedSkinName ~= ""
                            and weaponSupportsSkin(tool.Name)
                        then
                            putSkinIntoWeaponEntry(tool, selectedSkinName)
                            sameTool = false
                        end
                    end)
                    return viewModel._ZephyrOriginalSkinEquip(self, tool, sameTool, ...)
                end
                skinEquipPatched = true
            end
        end

        local function patchWeaponToolPaths()
            local function stampTool(tool)
                if
                    selectedSkinApplyEnabled
                    and type(tool) == "table"
                    and type(tool.Name) == "string"
                    and selectedSkinName
                    and selectedSkinName ~= ""
                    and weaponSupportsSkin(tool.Name)
                then
                    putSkinIntoWeaponEntry(tool, selectedSkinName)
                    return true
                end
                return false
            end

            local function stampSpawnPacket(packet)
                if
                    selectedSkinApplyEnabled
                    and type(packet) == "table"
                    and type(packet.Name) == "string"
                    and selectedSkinName
                    and selectedSkinName ~= ""
                    and weaponSupportsSkin(packet.Name)
                then
                    packet.SkinName = selectedSkinName
                    packet.Skin = selectedSkinName
                    packet.IsCE = false
                    packet.Aura = nil
                    packet.SkinData = {
                        SkinName = selectedSkinName,
                        IsCE = false,
                        Aura = nil,
                    }
                    return true
                end
                return false
            end

            local playerGui = safeFindFirstChild(LocalPlayer, "PlayerGui")
            local firstPerson = playerGui and safeFindFirstChild(playerGui, "FirstPersonGUI")
            local actionHandler = requireModule(firstPerson and safeFindFirstChild(firstPerson, "ActionHandler"))
            if type(actionHandler) == "table" then
                if type(actionHandler.InitTools) == "function" and not actionHandler._ZephyrOriginalSkinInitTools then
                    actionHandler._ZephyrOriginalSkinInitTools = actionHandler.InitTools
                    actionHandler.InitTools = function(self, tools, ...)
                        Runtime.before(function()
                            if selectedSkinApplyEnabled and type(tools) == "table" then
                                for _, packet in pairs(tools) do
                                    stampSpawnPacket(packet)
                                end
                            end
                        end)
                        return actionHandler._ZephyrOriginalSkinInitTools(self, tools, ...)
                    end
                end
                if type(actionHandler.Equip) == "function" and not actionHandler._ZephyrOriginalSkinEquipTool then
                    actionHandler._ZephyrOriginalSkinEquipTool = actionHandler.Equip
                    actionHandler.Equip = function(self, index, ...)
                        Runtime.before(function()
                            if selectedSkinApplyEnabled then
                                for _, shared in ipairs(collectLiveSharedTables()) do
                                    local tool = type(shared.Tools) == "table" and shared.Tools[index]
                                    if stampTool(tool) and shared.CurrTool == tool then
                                        shared.CurrTool = nil
                                    end
                                end
                            end
                        end)
                        return actionHandler._ZephyrOriginalSkinEquipTool(self, index, ...)
                    end
                end
            end

            local newMainLocal = getControllerNewMainLocal()
            local controllerFolder = newMainLocal and safeFindFirstChild(newMainLocal, "Controller")
            local toolController =
                requireModule(controllerFolder and safeFindFirstChild(controllerFolder, "ToolController"))
            if type(toolController) == "table" then
                if type(toolController.AddTool) == "function" and not toolController._ZephyrOriginalSkinAddTool then
                    toolController._ZephyrOriginalSkinAddTool = toolController.AddTool
                    toolController.AddTool = function(self, weaponName, index, superchargeTier, extra, ...)
                        Runtime.before(function()
                            if
                                selectedSkinApplyEnabled
                                and type(weaponName) == "string"
                                and selectedSkinName
                                and selectedSkinName ~= ""
                                and weaponSupportsSkin(weaponName)
                            then
                                extra = type(extra) == "table" and extra or {}
                                extra.SkinName = selectedSkinName
                                extra.Skin = selectedSkinName
                                extra.IsCE = false
                                extra.Aura = nil
                                extra.SkinData = {
                                    SkinName = selectedSkinName,
                                    IsCE = false,
                                    Aura = nil,
                                }
                            end
                        end)
                        return toolController._ZephyrOriginalSkinAddTool(
                            self,
                            weaponName,
                            index,
                            superchargeTier,
                            extra,
                            ...
                        )
                    end
                end
                if type(toolController.Equip) == "function" and not toolController._ZephyrOriginalSkinEquipTool then
                    toolController._ZephyrOriginalSkinEquipTool = toolController.Equip
                    toolController.Equip = function(self, index, ...)
                        Runtime.before(function()
                            if selectedSkinApplyEnabled then
                                for _, shared in ipairs(collectLiveSharedTables()) do
                                    local tool = type(shared.Tools) == "table" and shared.Tools[index]
                                    if stampTool(tool) and shared.CurrTool == tool then
                                        shared.CurrTool = nil
                                    end
                                end
                            end
                        end)
                        return toolController._ZephyrOriginalSkinEquipTool(self, index, ...)
                    end
                end
            end
        end

        local function applySelectedSkinToViewmodel()
            if not selectedSkinApplyEnabled or not selectedSkinName or selectedSkinName == "" then
                return false
            end
            local viewModel = getViewModelModule()
            local wModel = nil
            if type(viewModel) == "table" and type(viewModel.GetWModel) == "function" then
                pcall(function()
                    wModel = viewModel:GetWModel()
                end)
            end
            if typeof(wModel) ~= "Instance" then
                return false
            end

            local weaponName = wModel:GetAttribute("WModelName")
            if type(weaponName) == "string" and weaponName ~= "" and not weaponSupportsSkin(weaponName) then
                return false
            end

            local stamp = tostring(weaponName or "?") .. "|" .. tostring(selectedSkinName)
            if wModel:GetAttribute("ZephyrSkinApplied") == stamp then
                return false
            end

            local skinModule = getSkinModule()
            if type(skinModule) ~= "table" or type(skinModule.ApplySkin) ~= "function" then
                return false
            end

            local ok = pcall(function()
                skinModule:ApplySkin(wModel, {
                    SkinName = selectedSkinName,
                    IsCE = false,
                    Aura = nil,
                })
            end)
            if ok then
                wModel:SetAttribute("ZephyrSkinApplied", stamp)
                return true
            end
            return false
        end

        local function applySkinToCurrentWModel()
            patchSkinEquipPath()
            patchWeaponToolPaths()
            local didTouch = false
            for _, shared in ipairs(collectLiveSharedTables()) do
                if
                    type(shared.CurrTool) == "table"
                    and type(shared.CurrTool.Name) == "string"
                    and weaponSupportsSkin(shared.CurrTool.Name)
                then
                    putSkinIntoWeaponEntry(shared.CurrTool, selectedSkinName)
                    didTouch = true
                end
            end
            if applySelectedSkinToViewmodel() then
                didTouch = true
            end
            return didTouch
        end

        local function syncLiveTools()
            if not selectedSkinName then
                return
            end
            patchSkinEquipPath()
            patchWeaponToolPaths()
            for _, shared in ipairs(collectLiveSharedTables()) do
                if type(shared.Tools) == "table" then
                    local touchedTools = 0
                    for _, tool in pairs(shared.Tools) do
                        touchedTools += 1
                        if touchedTools % 8 == 0 then
                            task.wait()
                        end
                        if type(tool) == "table" then
                            local weaponName = tool.Name
                            if weaponName and weaponSupportsSkin(weaponName) then
                                putSkinIntoWeaponEntry(tool, selectedSkinName)
                            end
                        end
                    end
                end
                unlockAndApplySkinsToCoreData(shared.CoreData, true)
                unlockAndApplySkinsToCoreData(shared.MenuCoreData, true)
            end
            applySkinToCurrentWModel()
        end

        local function refreshEquippedViewmodel()
            patchSkinEquipPath()
            patchWeaponToolPaths()
            local playerGui = safeFindFirstChild(LocalPlayer, "PlayerGui")
            local firstPerson = playerGui and safeFindFirstChild(playerGui, "FirstPersonGUI")
            local actionHandlerModule = firstPerson and safeFindFirstChild(firstPerson, "ActionHandler")
            local actionHandler = requireModule(actionHandlerModule)
            if type(actionHandler) ~= "table" then
                return
            end

            for _, shared in ipairs(collectLiveSharedTables()) do
                local currTool = type(shared.CurrTool) == "table" and shared.CurrTool or nil
                local index = currTool and currTool.Index
                if currTool then
                    putSkinIntoWeaponEntry(currTool, selectedSkinName)
                end
                if index and type(actionHandler.Equip) == "function" then
                    pcall(function()
                        shared.CurrTool = nil
                        actionHandler:Equip(index)
                    end)
                    break
                end
                if type(actionHandler.UpdateWeaponFrames) == "function" then
                    pcall(function()
                        actionHandler:UpdateWeaponFrames()
                    end)
                end
            end
        end

        local function applySkinUnlocks(refreshViewmodel)
            if skinApplyBusy then
                return
            end
            skinApplyBusy = true
            skinsUnlocked = true
            selectedSkinApplyEnabled = true
            patchSkinEquipPath()
            patchWeaponToolPaths()

            pcall(function()
                for _, coreData in ipairs(collectFastCoreDataForSkins()) do
                    unlockAndApplySkinsToCoreData(coreData, true)
                    task.wait()
                end
                syncLiveTools()
                if refreshViewmodel then
                    refreshEquippedViewmodel()
                    task.wait(0.12)
                    applySkinToCurrentWModel()
                    refreshLoadoutMenu()
                end
            end)
            skinApplyBusy = false
        end

        Runtime.connect(LocalPlayer.CharacterAdded, function()
            if skinsUnlocked or selectedSkinApplyEnabled or weaponsUnlocked then
                task.delay(1, function()
                    pcall(function()
                        if weaponsUnlocked then
                            unlockAllWeapons()
                        end
                        if selectedSkinApplyEnabled then
                            applySkinUnlocks(true)
                        else
                            for _, coreData in ipairs(collectCoreDataForSkins()) do
                                unlockAndApplySkinsToCoreData(coreData, false)
                                task.wait()
                            end
                        end
                    end)
                end)
            end
        end)

        local skinOptions = getSkinNames()
        Tabs.Unlocks:AddDropdown("Skin To Apply", skinOptions, selectedSkinName, function(value)
            selectedSkinName = tostring(value or selectedSkinName)
            if selectedSkinApplyEnabled then
                task.spawn(function()
                    applySkinUnlocks(true)
                end)
            end
        end)

        Tabs.Unlocks:AddInput("Custom Skin", "Exact skin name", function(value)
            value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if value ~= "" then
                selectedSkinName = value
            end
        end)

        Tabs.Unlocks:AddButton("Unlock All Skins", "Adds every skin to client inventory", function()
            task.spawn(function()
                skinsUnlocked = true
                for _, coreData in ipairs(collectCoreDataForSkins()) do
                    unlockAndApplySkinsToCoreData(coreData, false)
                    task.wait()
                end
                refreshLoadoutMenu()
            end)
        end)

        Tabs.Unlocks:AddButton("Apply Selected Skin", "Applies to current weapon model", function()
            task.spawn(function()
                applySkinUnlocks(true)
            end)
        end)

        Tabs.Unlocks:AddButton("Unlock All Weapons", "Visual loadout unlock only", function()
            task.spawn(unlockAllWeapons)
        end)
    end)

    pcall(function()
        Tabs.Visuals:AddButton("Rainbow Bullets", "Strong executors only", function()
            pcall(function()
                local mods = ReplicatedStorage:FindFirstChild("Weapons")
                    and ReplicatedStorage.Weapons:FindFirstChild("Modules")
                if not mods then
                    return
                end
                for _, m in pairs(mods:GetChildren()) do
                    if m:IsA("ModuleScript") then
                        local ok, data = pcall(require, m)
                        if ok and data then
                            Runtime.connect(RunService.RenderStepped, function()
                                pcall(function()
                                    data.BulletColor = ColorSequence.new(Color3.fromHSV(tick() % 1, 1, 1))
                                end)
                            end)
                        end
                    end
                end
            end)
        end)
    end)

    -- Sky
    pcall(function()
        local galaxySkyEnabled = false
        local purpleMapEnabled = FirstRunPreset
        local darkMapEnabled = false
        local skyMapParts = {}

        local function clearSkyParts()
            for _, obj in ipairs(skyMapParts) do
                pcall(function()
                    obj:Destroy()
                end)
            end
            skyMapParts = {}
            local sky = Lighting:FindFirstChildOfClass("Sky")
            if sky then
                sky:Destroy()
            end
            Lighting.FogEnd = 1e6
            Lighting.FogStart = 0
            Lighting.ClockTime = 14
            Lighting.Brightness = 1
            Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
            Lighting.Ambient = Color3.fromRGB(0, 0, 0)
        end
        local function applyGalaxySky()
            if not galaxySkyEnabled then
                return
            end
            local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky", Lighting)
            sky.SkyboxBk = "http://www.roblox.com/asset/?id=159454299"
            sky.SkyboxDn = "http://www.roblox.com/asset/?id=159454296"
            sky.SkyboxFt = "http://www.roblox.com/asset/?id=159454293"
            sky.SkyboxLf = "http://www.roblox.com/asset/?id=159454286"
            sky.SkyboxRt = "http://www.roblox.com/asset/?id=159454300"
            sky.SkyboxUp = "http://www.roblox.com/asset/?id=159454288"
            sky.StarCount = 5000
            table.insert(skyMapParts, sky)
        end
        local function applyPurpleMap()
            if not purpleMapEnabled then
                return
            end
            clearSkyParts()
            local sky = Instance.new("Sky", Lighting)
            for _, f in ipairs({ "Bk", "Dn", "Ft", "Lf", "Rt", "Up" }) do
                sky["Skybox" .. f] = "rbxassetid://7850111046"
            end
            Lighting.ClockTime = 20
            Lighting.Brightness = 2
            Lighting.OutdoorAmbient = Color3.fromRGB(120, 90, 150)
            Lighting.Ambient = Color3.fromRGB(100, 70, 140)
            Lighting.FogEnd = 350
            Lighting.FogStart = 50
            Lighting.FogColor = Color3.fromRGB(150, 120, 200)
            local sp = Instance.new("Part")
            sp.Anchored = true
            sp.Transparency = 1
            sp.Size = Vector3.new(1000, 1, 1000)
            sp.Position = Vector3.new(0, 150, 0)
            sp.Parent = Workspace
            local pe = Instance.new("ParticleEmitter", sp)
            pe.Texture = "rbxassetid://7168455270"
            pe.Lifetime = NumberRange.new(10, 15)
            pe.Rate = FirstRunPreset and 80 or 300
            pe.Speed = NumberRange.new(5, 10)
            pe.Rotation = NumberRange.new(0, 360)
            pe.RotSpeed = NumberRange.new(-10, 10)
            pe.Size = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.2),
                NumberSequenceKeypoint.new(0.5, 0.4),
                NumberSequenceKeypoint.new(1, 0.2),
            })
            pe.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(0.8, 0.1),
                NumberSequenceKeypoint.new(1, 1),
            })
            pe.LightInfluence = 0
            local ss = Instance.new("Sound", Workspace)
            ss.SoundId = "rbxassetid://5419097916"
            ss.Looped = true
            ss.Volume = FirstRunPreset and 0.15 or 0.3
            ss:Play()
            table.insert(skyMapParts, sky)
            table.insert(skyMapParts, sp)
            table.insert(skyMapParts, ss)
        end
        local function applyDarkMap()
            if not darkMapEnabled then
                return
            end
            clearSkyParts()
            local sky = Instance.new("Sky", Lighting)
            for _, f in ipairs({ "Bk", "Dn", "Ft", "Lf", "Rt", "Up" }) do
                sky["Skybox" .. f] = "rbxassetid://136823597"
            end
            Lighting.ClockTime = 0
            Lighting.Brightness = 2
            Lighting.OutdoorAmbient = Color3.fromRGB(50, 50, 50)
            Lighting.Ambient = Color3.fromRGB(50, 50, 50)
            Lighting.FogEnd = 300
            Lighting.FogStart = 50
            Lighting.FogColor = Color3.fromRGB(200, 200, 255)
            local sp = Instance.new("Part")
            sp.Anchored = true
            sp.Transparency = 1
            sp.Size = Vector3.new(1000, 1, 1000)
            sp.Position = Vector3.new(0, 150, 0)
            sp.Parent = Workspace
            local pe = Instance.new("ParticleEmitter", sp)
            pe.Texture = "rbxassetid://7168455270"
            pe.Lifetime = NumberRange.new(10, 15)
            pe.Rate = 300
            pe.Speed = NumberRange.new(5, 10)
            pe.Rotation = NumberRange.new(0, 360)
            pe.RotSpeed = NumberRange.new(-10, 10)
            pe.Size = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.2),
                NumberSequenceKeypoint.new(0.5, 0.4),
                NumberSequenceKeypoint.new(1, 0.2),
            })
            pe.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(0.8, 0.1),
                NumberSequenceKeypoint.new(1, 1),
            })
            pe.LightInfluence = 0
            local ss = Instance.new("Sound", Workspace)
            ss.SoundId = "rbxassetid://5419097916"
            ss.Looped = true
            ss.Volume = 0.3
            ss:Play()
            table.insert(skyMapParts, sky)
            table.insert(skyMapParts, sp)
            table.insert(skyMapParts, ss)
        end
        Runtime.connect(RunService.Heartbeat, function()
            if galaxySkyEnabled and not Lighting:FindFirstChildOfClass("Sky") then
                applyGalaxySky()
            end
        end)
        Runtime.connect(LocalPlayer.CharacterAdded, function()
            task.wait(0.8)
            if galaxySkyEnabled then
                clearSkyParts()
                applyGalaxySky()
            end
            if purpleMapEnabled then
                applyPurpleMap()
            end
            if darkMapEnabled then
                applyDarkMap()
            end
        end)
        Tabs.Visuals:AddToggle("Galaxy Sky", false, function(on)
            galaxySkyEnabled = on
            purpleMapEnabled = false
            darkMapEnabled = false
            if on then
                clearSkyParts()
                applyGalaxySky()
            else
                clearSkyParts()
            end
        end)
        Tabs.Visuals:AddToggle("Purple Map", purpleMapEnabled, function(on)
            purpleMapEnabled = on
            galaxySkyEnabled = false
            darkMapEnabled = false
            if on then
                applyPurpleMap()
            else
                clearSkyParts()
            end
        end)
        Tabs.Visuals:AddToggle("Dark Map", false, function(on)
            darkMapEnabled = on
            galaxySkyEnabled = false
            purpleMapEnabled = false
            if on then
                applyDarkMap()
            else
                clearSkyParts()
            end
        end)
        if purpleMapEnabled then
            task.defer(applyPurpleMap)
        end
    end)

    -- Device spoofing
    pcall(function()
        local function getSpoofShared()
            return LocalPlayer.PlayerGui:FindFirstChild("MenuUI")
                and LocalPlayer.PlayerGui.MenuUI:FindFirstChild("MenuLocal")
                and LocalPlayer.PlayerGui.MenuUI.MenuLocal:FindFirstChild("Shared")
        end
        Tabs.Unlocks:AddButton("Spoof PC", "Run before entering in-game", function()
            task.spawn(function()
                pcall(function()
                    local shared = getSpoofShared()
                    if not shared then
                        return
                    end
                    local ok, m = pcall(require, shared)
                    if not ok then
                        return
                    end
                    while task.wait(1) do
                        pcall(function()
                            m.IS_CONSOLE = false
                            m.IS_MOBILE = false
                        end)
                    end
                end)
            end)
        end)
        Tabs.Unlocks:AddButton("Spoof Console", "Run before entering in-game", function()
            task.spawn(function()
                pcall(function()
                    local shared = getSpoofShared()
                    if not shared then
                        return
                    end
                    local ok, m = pcall(require, shared)
                    if not ok then
                        return
                    end
                    while task.wait(1) do
                        pcall(function()
                            m.IS_CONSOLE = true
                            m.IS_MOBILE = false
                        end)
                    end
                end)
            end)
        end)
        Tabs.Unlocks:AddButton("Spoof Mobile", "Run before entering in-game", function()
            task.spawn(function()
                pcall(function()
                    local shared = getSpoofShared()
                    if not shared then
                        return
                    end
                    local ok, m = pcall(require, shared)
                    if not ok then
                        return
                    end
                    while task.wait(1) do
                        pcall(function()
                            m.IS_MOBILE = true
                            m.IS_CONSOLE = false
                        end)
                    end
                end)
            end)
        end)
    end)

    -- Profile
    pcall(function()
        local lastWinStreak = nil
        local function getBannerLabel(path)
            local banner = LocalPlayer.PlayerGui:FindFirstChild("MenuUI")
                and LocalPlayer.PlayerGui.MenuUI:FindFirstChild("Banner")
            if not banner then
                return nil
            end
            local node = banner
            for _, step in ipairs(path) do
                node = node:FindFirstChild(step)
                if not node then
                    return nil
                end
            end
            return node
        end
        local function setWinStreak(val)
            pcall(function()
                local label = getBannerLabel({ "Streak", "TextLabel" })
                if label then
                    label.Text = tostring(val)
                    lastWinStreak = val
                end
            end)
        end
        Tabs.Unlocks:AddInput("Set Win Streak", "Enter number", function(value)
            local n = tonumber(value)
            if n then
                setWinStreak(n)
            end
        end)
        task.spawn(function()
            while task.wait(0.8) do
                if lastWinStreak then
                    pcall(function()
                        local label = getBannerLabel({ "Streak", "TextLabel" })
                        if label and tonumber(label.Text) ~= lastWinStreak then
                            setWinStreak(lastWinStreak)
                        end
                    end)
                end
            end
        end)
        local titleToggled = false
        local currentTitle = "=ZEPHYR="
        Tabs.Unlocks:AddToggle("Unlock Title", false, function(value)
            titleToggled = value
            pcall(function()
                local label = getBannerLabel({ "Title" })
                if label then
                    label.Visible = value
                    if value then
                        label.Text = currentTitle
                    end
                end
            end)
        end)
        Tabs.Unlocks:AddInput("Set Title", "Max 8 letters (A-Z only)", function(value)
            if value and #value <= 8 and value:match("^[A-Za-z]+$") then
                currentTitle = value
                if titleToggled then
                    pcall(function()
                        local label = getBannerLabel({ "Title" })
                        if label then
                            label.Text = currentTitle
                        end
                    end)
                end
            end
        end)
        Tabs.Unlocks:AddInput("Level Changer", "Enter level", function(value)
            local n = tonumber(value)
            if not n then
                return
            end
            pcall(function()
                local label = getBannerLabel({ "Header", "LevelLabel" })
                if label then
                    label.Text = "LEVEL " .. tostring(n)
                end
            end)
        end)
    end)

    -- Performance
    pcall(function()
        Tabs.Combat:AddButton("TANK MODE", "Balanced performance boost", function()
            task.spawn(function()
                pcall(function()
                    local candidates = {
                        ReplicatedStorage:FindFirstChild("Weapons")
                            and ReplicatedStorage.Weapons:FindFirstChild("Modules"),
                        ReplicatedStorage:FindFirstChild("WeaponModules"),
                    }
                    local folder = nil
                    for _, c in ipairs(candidates) do
                        if c then
                            folder = c
                            break
                        end
                    end
                    if folder then
                        for _, mod in folder:GetChildren() do
                            if mod:IsA("ModuleScript") then
                                local ok, data = pcall(require, mod)
                                if ok and type(data) == "table" then
                                    if type(data.Debounce) == "number" then
                                        data.Debounce = math.max(0.01, data.Debounce * 0.85)
                                    end
                                    if type(data.Spread) == "number" then
                                        data.Spread = data.Spread * 0.80
                                    end
                                    if type(data.BaseSpread) == "number" then
                                        data.BaseSpread = data.BaseSpread * 0.80
                                    end
                                    if type(data.ZoomSpread) == "number" then
                                        data.ZoomSpread = data.ZoomSpread * 0.80
                                    end
                                    if typeof(data.MinCamRecoil) == "Vector3" then
                                        data.MinCamRecoil = data.MinCamRecoil * 0.75
                                    end
                                    if typeof(data.MaxCamRecoil) == "Vector3" then
                                        data.MaxCamRecoil = data.MaxCamRecoil * 0.75
                                    end
                                    if typeof(data.MinRotRecoil) == "Vector3" then
                                        data.MinRotRecoil = data.MinRotRecoil * 0.75
                                    end
                                    if typeof(data.MaxRotRecoil) == "Vector3" then
                                        data.MaxRotRecoil = data.MaxRotRecoil * 0.75
                                    end
                                    if typeof(data.MinTransRecoil) == "Vector3" then
                                        data.MinTransRecoil = data.MinTransRecoil * 0.75
                                    end
                                    if typeof(data.MaxTransRecoil) == "Vector3" then
                                        data.MaxTransRecoil = data.MaxTransRecoil * 0.75
                                    end
                                    if type(data.ScopeSpeed) == "number" then
                                        data.ScopeSpeed = data.ScopeSpeed * 1.20
                                    end
                                    if type(data.Ammo) == "number" and data.Ammo > 1 then
                                        data.Ammo = math.ceil(data.Ammo * 1.20)
                                    end
                                    if type(data.FillAmmo) == "number" then
                                        data.FillAmmo = math.ceil(data.FillAmmo * 1.20)
                                    end
                                    if type(data.ProjSpeed) == "number" then
                                        data.ProjSpeed = data.ProjSpeed * 1.10
                                    end
                                end
                            end
                        end
                    end
                    local m_Shared = getControllerShared()
                    if m_Shared then
                        local lastTool = nil
                        Runtime.connect(RunService.Heartbeat, function()
                            local tool = m_Shared.CurrTool
                            if tool == lastTool then
                                return
                            end
                            lastTool = tool
                            if not tool or type(tool) ~= "table" then
                                return
                            end
                            local ws = tool.WSettings
                            if ws then
                                if type(ws.Debounce) == "number" then
                                    ws.Debounce = math.max(0.01, ws.Debounce * 0.85)
                                end
                                if type(ws.Spread) == "number" then
                                    ws.Spread = ws.Spread * 0.80
                                end
                                if type(ws.BaseSpread) == "number" then
                                    ws.BaseSpread = ws.BaseSpread * 0.80
                                end
                                if type(ws.ScopeSpreadMultiplier) == "number" then
                                    ws.ScopeSpreadMultiplier = ws.ScopeSpreadMultiplier * 0.80
                                end
                                if type(ws.ZoomSpread) == "number" then
                                    ws.ZoomSpread = ws.ZoomSpread * 0.80
                                end
                                if type(ws.AimSpread) == "number" then
                                    ws.AimSpread = ws.AimSpread * 0.80
                                end
                                if type(ws.ScopeSpeed) == "number" then
                                    ws.ScopeSpeed = ws.ScopeSpeed * 1.20
                                end
                            end
                            if type(tool.WeaponFullClipAmmo) == "number" then
                                local nc = math.ceil(tool.WeaponFullClipAmmo * 1.20)
                                if type(tool.Ammo) == "number" then
                                    tool.Ammo = math.min(nc, tool.Ammo + (nc - tool.WeaponFullClipAmmo))
                                end
                                tool.WeaponFullClipAmmo = nc
                            end
                            if type(tool.FillAmmo) == "number" then
                                tool.FillAmmo = math.ceil(tool.FillAmmo * 1.20)
                            end
                            if type(tool.BurstDebounce) == "number" then
                                tool.BurstDebounce = math.max(0.02, tool.BurstDebounce * 0.85)
                            end
                            if typeof(tool.MinCamRecoil) == "Vector3" then
                                tool.MinCamRecoil = tool.MinCamRecoil * 0.75
                            end
                            if typeof(tool.MaxCamRecoil) == "Vector3" then
                                tool.MaxCamRecoil = tool.MaxCamRecoil * 0.75
                            end
                            if typeof(tool.MinRotRecoil) == "Vector3" then
                                tool.MinRotRecoil = tool.MinRotRecoil * 0.75
                            end
                            if typeof(tool.MaxRotRecoil) == "Vector3" then
                                tool.MaxRotRecoil = tool.MaxRotRecoil * 0.75
                            end
                        end)
                    end
                    task.spawn(function()
                        while true do
                            RunService.Heartbeat:Wait()
                            pcall(function()
                                local arms = Workspace:FindFirstChild("IgnoreThese")
                                    and Workspace.IgnoreThese:FindFirstChild("MyArms")
                                if not arms then
                                    return
                                end
                                local reloadAnim = arms:FindFirstChild("Anims") and arms.Anims:FindFirstChild("Reload")
                                local animCtrl = arms:FindFirstChild("AnimationController")
                                if not reloadAnim or not animCtrl then
                                    return
                                end
                                for _, track in ipairs(animCtrl:GetPlayingAnimationTracks()) do
                                    if
                                        track.Animation
                                        and track.Animation.AnimationId == reloadAnim.AnimationId
                                        and track.Speed ~= 1.2
                                    then
                                        pcall(function()
                                            track:AdjustSpeed(1.2)
                                        end)
                                    end
                                end
                            end)
                        end
                    end)
                    pcall(function()
                        local sky = Instance.new("Sky")
                        sky.Parent = Lighting
                        for _, face in ipairs({ "Bk", "Dn", "Ft", "Lf", "Rt", "Up" }) do
                            sky["Skybox" .. face] = "rbxassetid://7850111046"
                        end
                        Lighting.ClockTime = 20
                        Lighting.Brightness = 2
                        Lighting.OutdoorAmbient = Color3.fromRGB(120, 90, 150)
                        Lighting.Ambient = Color3.fromRGB(100, 70, 140)
                        Lighting.FogEnd = 350
                        Lighting.FogStart = 50
                        Lighting.FogColor = Color3.fromRGB(150, 120, 200)
                    end)
                end)
            end)
        end)
    end)

    -- Camera
    pcall(function()
        local fovChangerConn = nil
        local fovEnabled = false
        local savedFOV = 70
        local _RS = game:GetService("RunService")
        local fovConn = nil

        local function applyFOV(v)
            if not fovEnabled then
                return
            end
            -- FieldOfView stops at 120; higher values use the camera offset.
            if v <= 120 then
                if fovConn then
                    fovConn:Disconnect()
                    fovConn = nil
                end
                workspace.CurrentCamera.FieldOfView = v
            else
                workspace.CurrentCamera.FieldOfView = 120
                local extra = (v - 120) / 120
                if fovConn then
                    fovConn:Disconnect()
                end
                fovConn = Runtime.connect(_RS.RenderStepped, function()
                    if not fovEnabled then
                        return
                    end
                    local cf = workspace.CurrentCamera.CFrame
                    workspace.CurrentCamera.CFrame = cf * CFrame.new(0, 0, extra * 8)
                end)
            end
        end

        Runtime.connect(game:GetService("Players").LocalPlayer.CharacterAdded, function()
            task.wait(1)
            if fovEnabled then
                applyFOV(savedFOV)
            end
        end)

        Runtime.connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
            task.wait(0.1)
            if fovEnabled then
                applyFOV(savedFOV)
            end
        end)

        Tabs.Visuals:AddToggle("FOV Changer", false, function(v)
            fovEnabled = v
            if not v then
                if fovConn then
                    fovConn:Disconnect()
                    fovConn = nil
                end
                if fovChangerConn then
                    fovChangerConn:Disconnect()
                    fovChangerConn = nil
                end
                workspace.CurrentCamera.FieldOfView = 70
            else
                applyFOV(savedFOV)
                fovChangerConn = Runtime.connect(
                    workspace.CurrentCamera:GetPropertyChangedSignal("FieldOfView"),
                    function()
                        if fovEnabled and savedFOV <= 120 and workspace.CurrentCamera.FieldOfView ~= savedFOV then
                            workspace.CurrentCamera.FieldOfView = savedFOV
                        end
                    end
                )
            end
        end)

        Tabs.Visuals:AddSlider("FOV", 70, 360, 70, function(v)
            savedFOV = v
            applyFOV(v)
        end)
    end)

    -- Bombardino
    pcall(function()
        local bombardinoEnabled = false
        local bombardinoMult = 1.5
        local bombardinoTracked = {}
        local function isBombardino(obj)
            local main = obj:FindFirstChild("Main")
            if not main then
                return false
            end
            return main:FindFirstChild("LinearVelocity") ~= nil
        end
        local function trackBombardino(obj)
            if bombardinoTracked[obj] then
                return
            end
            task.wait(0.1)
            if not isBombardino(obj) then
                return
            end
            bombardinoTracked[obj] = obj:FindFirstChild("Main")
            Runtime.connect(obj.AncestryChanged, function()
                if not obj:IsDescendantOf(Workspace) then
                    bombardinoTracked[obj] = nil
                end
            end)
        end
        for _, obj in Workspace:GetChildren() do
            if isBombardino(obj) then
                task.spawn(trackBombardino, obj)
            end
        end
        Runtime.connect(Workspace.ChildAdded, function(child)
            task.spawn(trackBombardino, child)
        end)
        Runtime.connect(RunService.Heartbeat, function()
            if not bombardinoEnabled then
                return
            end
            if not next(bombardinoTracked) then
                return
            end
            for _, main in pairs(bombardinoTracked) do
                pcall(function()
                    local lv = main:FindFirstChild("LinearVelocity")
                    if not lv then
                        return
                    end
                    local v = lv.VectorVelocity
                    lv.VectorVelocity = Vector3.new(v.X, v.Y, v.Z * bombardinoMult)
                end)
            end
        end)
        Tabs.Misc:AddToggle("Bombardino Speed Boost", false, function(v)
            bombardinoEnabled = v
        end)
        Tabs.Misc:AddSlider("Bombardino Speed Multiplier", 1.0, 1.0, 1.5, function(v)
            bombardinoMult = v
        end)
    end)

    pcall(function()
        if not IsPC then
            return
        end

        pcall(function()
            local AutoRespawnEnabled = false
            local InstaReviveEnabled = false
            local lastPos = nil
            local function disableMenuUI()
                pcall(function()
                    local m = LocalPlayer.PlayerGui:FindFirstChild("MenuUI")
                    if m then
                        m.Enabled = false
                    end
                end)
            end
            local function waitForMap()
                while true do
                    if Workspace:FindFirstChild("Map") then
                        return true
                    end
                    task.wait(0.1)
                end
            end
            local function doRespawn()
                if waitForMap() then
                    task.wait(1)
                    local spawn = ReplicatedStorage:FindFirstChild("Network")
                        and ReplicatedStorage.Network:FindFirstChild("Remotes")
                        and ReplicatedStorage.Network.Remotes:FindFirstChild("Spawn")
                    if spawn then
                        spawn:FireServer(false)
                    end
                    local newChar = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
                    newChar:WaitForChild("HumanoidRootPart", 5)
                    disableMenuUI()
                end
            end
            local function onAutoRespawn(char)
                local hum = char:WaitForChild("Humanoid", 10)
                if not hum then
                    return
                end
                Runtime.connect(hum.Died, function()
                    if AutoRespawnEnabled then
                        doRespawn()
                    end
                end)
            end
            local function onInstaRevive(char)
                local hum = char:WaitForChild("Humanoid", 10)
                if not hum then
                    return
                end
                Runtime.connect(hum.Died, function()
                    if InstaReviveEnabled then
                        if char:FindFirstChild("HumanoidRootPart") then
                            lastPos = char.HumanoidRootPart.CFrame
                        end
                        doRespawn()
                        if lastPos and Workspace:FindFirstChild("Map") then
                            local newChar = LocalPlayer.Character
                            local root = newChar and newChar:FindFirstChild("HumanoidRootPart")
                            if root then
                                TweenService
                                    :Create(root, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { CFrame = lastPos })
                                    :Play()
                            end
                        end
                    end
                end)
            end
            Runtime.connect(LocalPlayer.CharacterAdded, function(char)
                if AutoRespawnEnabled then
                    onAutoRespawn(char)
                end
                if InstaReviveEnabled then
                    onInstaRevive(char)
                end
            end)
            if LocalPlayer.Character then
                if AutoRespawnEnabled then
                    onAutoRespawn(LocalPlayer.Character)
                end
                if InstaReviveEnabled then
                    onInstaRevive(LocalPlayer.Character)
                end
            end
            Tabs.Player:AddToggle("Auto Respawn", false, function(v)
                AutoRespawnEnabled = v
            end)
            Tabs.Player:AddToggle("Insta Revive", false, function(v)
                InstaReviveEnabled = v
            end)
        end)

        pcall(function()
            local isFlying = false
            local flyVelocity, flyGyro
            local flySpeed = 50
            local function enableFly()
                local char = LocalPlayer.Character
                if not char then
                    return
                end
                local hum = char:FindFirstChildOfClass("Humanoid")
                local root = char:FindFirstChild("HumanoidRootPart")
                if not hum or not root then
                    return
                end
                isFlying = true
                hum.PlatformStand = true
                flyVelocity = Instance.new("BodyVelocity", root)
                flyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                flyVelocity.Velocity = Vector3.new(0, 0, 0)
                flyGyro = Instance.new("BodyGyro", root)
                flyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                flyGyro.P = 5000
            end
            local function disableFly()
                local char = LocalPlayer.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum then
                    hum.PlatformStand = false
                end
                isFlying = false
                if flyVelocity then
                    flyVelocity:Destroy()
                    flyVelocity = nil
                end
                if flyGyro then
                    flyGyro:Destroy()
                    flyGyro = nil
                end
            end
            Runtime.connect(RunService.RenderStepped, function()
                if not isFlying then
                    return
                end
                local char = LocalPlayer.Character
                if not char then
                    disableFly()
                    return
                end
                local root = char:FindFirstChild("HumanoidRootPart")
                if not root then
                    disableFly()
                    return
                end
                local dir = Vector3.new(0, 0, 0)
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                    dir += Vector3.new(0, 0, 1)
                end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                    dir += Vector3.new(0, 0, -1)
                end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                    dir += Vector3.new(-1, 0, 0)
                end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                    dir += Vector3.new(1, 0, 0)
                end
                local world = (Camera.CFrame.LookVector * dir.Z) + (Camera.CFrame.RightVector * dir.X)
                if world.Magnitude > 0 then
                    world = world.Unit
                end
                flyVelocity.Velocity = world * flySpeed
                flyGyro.CFrame = CFrame.new(root.Position, root.Position + Camera.CFrame.LookVector)
            end)
            Tabs.Player:AddToggle("Enable Fly", false, function(v)
                if v then
                    enableFly()
                else
                    disableFly()
                end
            end)
            Tabs.Player:AddSlider("Fly Speed", 10, 200, 50, function(v)
                flySpeed = v
            end)
            Tabs.Player:AddKeybind("Fly Keybind", "F", function()
                if isFlying then
                    disableFly()
                else
                    enableFly()
                end
            end)
        end)

        pcall(function()
            local walkSpeedEnabled = false
            local currentWalkSpeed = 16
            local charLoaded = false
            Runtime.connect(RunService.Stepped, function(_, dt)
                if not walkSpeedEnabled or not charLoaded then
                    return
                end
                local char = LocalPlayer.Character
                if not char then
                    return
                end
                local root = char:FindFirstChild("HumanoidRootPart")
                local hum = char:FindFirstChildOfClass("Humanoid")
                if root and hum and hum.MoveDirection.Magnitude > 0 then
                    root.CFrame = root.CFrame + (hum.MoveDirection.Unit * currentWalkSpeed * dt)
                end
            end)
            Runtime.connect(LocalPlayer.CharacterAdded, function(char)
                charLoaded = false
                char:WaitForChild("HumanoidRootPart", 10)
                task.wait(1)
                charLoaded = true
            end)
            if LocalPlayer.Character then
                task.delay(1, function()
                    charLoaded = true
                end)
            end
            Tabs.Player:AddToggle("Enable Walk Speed", false, function(v)
                walkSpeedEnabled = v
            end)
            Tabs.Player:AddSlider("Walk Speed", 0, 100, 16, function(v)
                currentWalkSpeed = v
            end)
        end)
    end)

    if RestoreHypershotSettings then
        local ok, err = pcall(RestoreHypershotSettings)
        if not ok then
            warn("[Zephyr Hypershot] Could not restore settings: " .. tostring(err))
        end
    end
    Runtime.ready = true
end

local initialized, initializationError = pcall(initialize)
if not initialized then
    Runtime.record("Initialization", initializationError)
end
if not initialized or not Runtime.ready then
    if Runtime.unload then
        pcall(Runtime.unload)
    else
        Runtime.stop()
    end
end
