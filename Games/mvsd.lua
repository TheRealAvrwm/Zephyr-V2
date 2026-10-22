local zephyrOk, zephyrErr = pcall(function()
    local function getGlobalEnv()
        if type(getgenv) == "function" then
            local ok, env = pcall(getgenv)
            if ok and type(env) == "table" then
                return env
            end
        end
        return _G
    end

    local G = getGlobalEnv()
    if type(G.ZephyrUnifiedUnload) == "function" then
        pcall(G.ZephyrUnifiedUnload)
    end

    local runtimeAlive = true
    local unload
    local Connections = {}
    local Drawings = {}
    local Instances = {}
    local Cleanups = {}
    local SkippedFeatures = {}

    local function rememberConnection(conn)
        if conn then
            table.insert(Connections, conn)
        end
        return conn
    end

    local function rememberDrawing(obj)
        if obj then
            table.insert(Drawings, obj)
        end
        return obj
    end

    local function rememberInstance(obj)
        if obj then
            table.insert(Instances, obj)
        end
        return obj
    end

    local function rememberCleanup(callback)
        if type(callback) == "function" then
            table.insert(Cleanups, callback)
        end
        return callback
    end

    local function removeDrawing(obj)
        if obj then
            pcall(function()
                obj:Remove()
            end)
        end
    end

    local function destroyInstance(obj)
        if obj then
            pcall(function()
                obj:Destroy()
            end)
        end
    end

    local function recordSkip(name, reason)
        table.insert(SkippedFeatures, tostring(name) .. ": " .. tostring(reason))
    end

    local RuntimeErrors = {}
    local unpackArgs = table.unpack or unpack
    G.ZephyrRuntimeErrors = RuntimeErrors

    local function recordRuntimeError(source, err)
        local key = tostring(source or "runtime")
        local rec = RuntimeErrors[key]
        if not rec then
            rec = { count = 0, last = 0, message = "" }
            RuntimeErrors[key] = rec
        end
        rec.count += 1
        rec.last = tick()
        rec.message = tostring(err or "")
    end

    local function runSafely(source, callback, ...)
        local args = { ... }
        local count = select("#", ...)
        local ok, result = xpcall(function()
            return callback(unpackArgs(args, 1, count))
        end, function(err)
            return tostring(err)
        end)
        if not ok then
            recordRuntimeError(source, result)
            return nil
        end
        return result
    end

    local function connectSafe(signal, source, callback)
        if not signal then
            return nil
        end
        return rememberConnection(signal:Connect(function(...)
            if not runtimeAlive then
                return
            end
            runSafely(source, callback, ...)
        end))
    end

    unload = function()
        if not runtimeAlive then
            return
        end
        runtimeAlive = false
        for i = #Cleanups, 1, -1 do
            pcall(Cleanups[i])
        end
        for _, conn in ipairs(Connections) do
            pcall(function()
                if conn and conn.Connected then
                    conn:Disconnect()
                end
            end)
        end
        for _, obj in ipairs(Drawings) do
            removeDrawing(obj)
        end
        for _, obj in ipairs(Instances) do
            destroyInstance(obj)
        end
        table.clear(Connections)
        table.clear(Drawings)
        table.clear(Instances)
        table.clear(Cleanups)
        if G.ZephyrUnifiedUnload == unload then
            G.ZephyrUnifiedLoaded = nil
            G.ZephyrUnifiedUnload = nil
        end
    end
    G.ZephyrUnifiedUnload = unload
    G.ZephyrUnifiedLoaded = true

    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace = game:GetService("Workspace")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local CollectionService = game:GetService("CollectionService")
    local TweenService = game:GetService("TweenService")
    local Debris = game:GetService("Debris")
    local Lighting = game:GetService("Lighting")
    local GuiService = game:GetService("GuiService")

    local readyDeadline = os.clock() + 30
    while runtimeAlive and (not Players.LocalPlayer or not Workspace.CurrentCamera) and os.clock() < readyDeadline do
        task.wait(0.05)
    end
    if not runtimeAlive or not Players.LocalPlayer or not Workspace.CurrentCamera then
        unload()
        return
    end
    local LocalPlayer = Players.LocalPlayer
    local Mouse = LocalPlayer:GetMouse()
    local Camera = Workspace.CurrentCamera

    local function getGuiInset()
        local ok, inset = pcall(function()
            return GuiService:GetGuiInset()
        end)
        return ok and inset or Vector2.zero
    end

    local function toVector2(position)
        if typeof(position) == "Vector2" then
            return position
        end
        return Vector2.new(position.X, position.Y)
    end

    local function inputPointToViewport(position)
        local point = toVector2(position)
        local inset = getGuiInset()
        return Vector2.new(point.X - inset.X, point.Y - inset.Y)
    end

    local function viewportPointToScreen(point)
        point = toVector2(point)
        local inset = getGuiInset()
        return Vector2.new(point.X + inset.X, point.Y + inset.Y)
    end

    local function viewportPointToInsetGui(point)
        return viewportPointToScreen(point)
    end

    local function getMousePoint()
        return inputPointToViewport(UserInputService:GetMouseLocation())
    end

    local function getMouseScreenPoint()
        return toVector2(UserInputService:GetMouseLocation())
    end

    local AbilityInputBlockers = setmetatable({}, { __mode = "k" })
    local lastAbilityInputAt = 0

    local function markAbilityInput()
        lastAbilityInputAt = tick()
        local character = LocalPlayer.Character
        local tool = character and character:FindFirstChildOfClass("Tool")
        if tool then
            local ok, wasEnabled = pcall(function()
                return tool.Enabled
            end)
            if ok and wasEnabled then
                pcall(function()
                    tool.Enabled = false
                end)
                task.delay(0.18, function()
                    if tool and tool.Parent then
                        pcall(function()
                            tool.Enabled = true
                        end)
                    end
                end)
            end
        end
    end

    local function registerAbilityInputBlocker(frame)
        if frame then
            AbilityInputBlockers[frame] = true
        end
        return frame
    end

    local function isPointInsideFrame(frame, point)
        if not frame or not frame.Parent or not point then
            return false
        end
        local pos = frame.AbsolutePosition
        local size = frame.AbsoluteSize
        return point.X >= pos.X and point.X <= pos.X + size.X and point.Y >= pos.Y and point.Y <= pos.Y + size.Y
    end

    local function isAbilityInputPoint(position)
        if tick() - lastAbilityInputAt <= 0.35 then
            return true
        end
        if not position then
            return false
        end

        local point = toVector2(position)
        local screenPoint = viewportPointToScreen(point)
        for frame in pairs(AbilityInputBlockers) do
            if frame and frame.Parent then
                if isPointInsideFrame(frame, point) or isPointInsideFrame(frame, screenPoint) then
                    return true
                end
            else
                AbilityInputBlockers[frame] = nil
            end
        end
        return false
    end

    local function enumFromString(value)
        if typeof(value) == "EnumItem" then
            return value
        end
        local name = tostring(value)
        name = name:gsub("Enum%.KeyCode%.", "")
        name = name:gsub("Enum%.UserInputType%.", "")
        local okKey, keyValue = pcall(function()
            return Enum.KeyCode[name]
        end)
        if okKey and keyValue then
            return keyValue
        end
        local okInput, inputValue = pcall(function()
            return Enum.UserInputType[name]
        end)
        if okInput and inputValue then
            return inputValue
        end
        return value
    end

    local function inputMatches(input, target)
        target = enumFromString(target)
        return input.KeyCode == target or input.UserInputType == target
    end

    local function executorEnv()
        if type(getfenv) == "function" then
            local ok, env = pcall(getfenv)
            if ok and type(env) == "table" then
                return env
            end
        end
        return _G
    end

    local function hasFunction(name)
        local env = executorEnv()
        return type(env[name]) == "function" or type(_G[name]) == "function" or type(G[name]) == "function"
    end

    local function getFunction(name)
        local env = executorEnv()
        if type(env[name]) == "function" then
            return env[name]
        end
        if type(_G[name]) == "function" then
            return _G[name]
        end
        if type(G[name]) == "function" then
            return G[name]
        end
        return nil
    end

    local Caps = {
        IsMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
        HasTouch = UserInputService.TouchEnabled,
        HasMouseMove = hasFunction("mousemoverel"),
        HasMouseButtons = hasFunction("mouse1press") and hasFunction("mouse1release"),
        HasMouseClick = hasFunction("mouse1click") or (hasFunction("mouse1press") and hasFunction("mouse1release")),
        HasHook = hasFunction("hookmetamethod") and hasFunction("newcclosure") and hasFunction("getnamecallmethod"),
        HasNilInstances = hasFunction("getnilinstances"),
        HasFiles = hasFunction("writefile") and hasFunction("readfile") and hasFunction("isfile"),
        HasRegistry = type(getFunction("getregistry")) == "function"
            or (type(debug) == "table" and type(debug.getregistry) == "function"),
    }

    do
        local ok, circle = pcall(function()
            if type(Drawing) ~= "table" then
                return nil
            end
            return Drawing.new("Circle")
        end)
        Caps.HasDrawing = ok and circle ~= nil
        if circle then
            pcall(function()
                circle:Remove()
            end)
        end
    end
    Caps.HasExecutorHooks = Caps.HasHook and Caps.HasNilInstances and Caps.HasRegistry

    local DEVICE_PREF_FILE = "ZephyrMVSD_DeviceMode.txt"
    local MENU_TOGGLE_PREF_FILE = "ZephyrMVSD_MenuToggleVisible.txt"
    local function normalizeDeviceMode(value)
        value = tostring(value or ""):lower()
        if value == "mobile" or value == "android" or value == "ios" or value == "phone" or value == "tablet" then
            return "Mobile"
        end
        if value == "pc" or value == "desktop" or value == "windows" or value == "computer" then
            return "PC"
        end
        return nil
    end

    local function readDevicePreference()
        local sessionChoice = normalizeDeviceMode(G.ZephyrDeviceMode)
        if sessionChoice then
            return sessionChoice, "session"
        end

        if Caps.HasFiles then
            local isfileFn = getFunction("isfile")
            local readfileFn = getFunction("readfile")
            if isfileFn and readfileFn then
                local okExists, exists = pcall(isfileFn, DEVICE_PREF_FILE)
                if okExists and exists then
                    local okRead, saved = pcall(readfileFn, DEVICE_PREF_FILE)
                    local fileChoice = okRead and normalizeDeviceMode(saved)
                    if fileChoice then
                        G.ZephyrDeviceMode = fileChoice
                        return fileChoice, "saved"
                    end
                end
            end
        end

        return nil, nil
    end

    local function writeDevicePreference(mode)
        mode = normalizeDeviceMode(mode)
        if not mode then
            return
        end
        G.ZephyrDeviceMode = mode

        if Caps.HasFiles then
            local writefileFn = getFunction("writefile")
            if writefileFn then
                pcall(writefileFn, DEVICE_PREF_FILE, mode)
            end
        end
    end

    local function clearDevicePreference()
        G.ZephyrDeviceMode = nil
        if Caps.HasFiles then
            local writefileFn = getFunction("writefile")
            if writefileFn then
                pcall(writefileFn, DEVICE_PREF_FILE, "ask")
            end
        end
    end

    local function readMenuToggleHiddenPreference()
        if Caps.HasFiles then
            local isfileFn = getFunction("isfile")
            local readfileFn = getFunction("readfile")
            if isfileFn and readfileFn then
                local okExists, exists = pcall(isfileFn, MENU_TOGGLE_PREF_FILE)
                if okExists and exists then
                    local okRead, saved = pcall(readfileFn, MENU_TOGGLE_PREF_FILE)
                    if okRead then
                        saved = tostring(saved or ""):lower()
                        return saved == "hidden" or saved == "hide" or saved == "false" or saved == "0"
                    end
                end
            end
        end
        return G.ZephyrMVSDMenuToggleHidden == true
    end

    local function writeMenuToggleHiddenPreference(hidden)
        hidden = hidden == true
        G.ZephyrMVSDMenuToggleHidden = hidden
        if Caps.HasFiles then
            local writefileFn = getFunction("writefile")
            if writefileFn then
                pcall(writefileFn, MENU_TOGGLE_PREF_FILE, hidden and "hidden" or "visible")
            end
        end
    end

    local function promptDeviceMode()
        local savedChoice, source = readDevicePreference()
        if savedChoice then
            return savedChoice, source
        end

        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui")
        local gui = rememberInstance(Instance.new("ScreenGui"))
        gui.Name = "ZephyrDevicePrompt"
        gui.IgnoreGuiInset = true
        gui.ResetOnSpawn = false
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.DisplayOrder = 1000002
        gui.Parent = playerGui

        local dim = Instance.new("Frame")
        dim.Size = UDim2.fromScale(1, 1)
        dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        dim.BackgroundTransparency = 0.35
        dim.BorderSizePixel = 0
        dim.Parent = gui

        local card = Instance.new("Frame")
        card.AnchorPoint = Vector2.new(0.5, 0.5)
        card.Position = UDim2.fromScale(0.5, 0.5)
        card.Size = UDim2.fromOffset(330, 190)
        card.BackgroundColor3 = Color3.fromRGB(15, 17, 26)
        card.BorderSizePixel = 0
        card.Parent = dim
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 16)
        corner.Parent = card
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(120, 145, 255)
        stroke.Thickness = 1.4
        stroke.Transparency = 0.15
        stroke.Parent = card

        local title = Instance.new("TextLabel")
        title.BackgroundTransparency = 1
        title.Position = UDim2.fromOffset(18, 16)
        title.Size = UDim2.new(1, -36, 0, 26)
        title.Font = Enum.Font.GothamBlack
        title.Text = "Choose Device"
        title.TextColor3 = Color3.fromRGB(245, 247, 255)
        title.TextSize = 20
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = card

        local body = Instance.new("TextLabel")
        body.BackgroundTransparency = 1
        body.Position = UDim2.fromOffset(18, 49)
        body.Size = UDim2.new(1, -36, 0, 50)
        body.Font = Enum.Font.Gotham
        body.Text = "This overrides Roblox device spoofing and will be remembered on this executor."
        body.TextColor3 = Color3.fromRGB(165, 175, 205)
        body.TextSize = 13
        body.TextWrapped = true
        body.TextXAlignment = Enum.TextXAlignment.Left
        body.TextYAlignment = Enum.TextYAlignment.Top
        body.Parent = card

        local chosen = nil
        local function makeButton(text, x, color, mode)
            local button = Instance.new("TextButton")
            button.Position = UDim2.fromOffset(x, 120)
            button.Size = UDim2.fromOffset(138, 42)
            button.BackgroundColor3 = color
            button.BorderSizePixel = 0
            button.AutoButtonColor = true
            button.Text = text
            button.TextColor3 = Color3.fromRGB(255, 255, 255)
            button.Font = Enum.Font.GothamBold
            button.TextSize = 14
            button.Parent = card
            local buttonCorner = Instance.new("UICorner")
            buttonCorner.CornerRadius = UDim.new(0, 10)
            buttonCorner.Parent = button
            button.MouseButton1Click:Connect(function()
                chosen = mode
                writeDevicePreference(mode)
                pcall(function()
                    gui:Destroy()
                end)
            end)
        end

        makeButton("Android / Mobile", 18, Color3.fromRGB(88, 101, 242), "Mobile")
        makeButton("PC", 174, Color3.fromRGB(38, 43, 60), "PC")

        while not chosen do
            task.wait()
        end
        return chosen, "prompt"
    end

    local DeviceMode, DeviceModeSource = promptDeviceMode()
    Caps.DeviceMode = DeviceMode
    Caps.DeviceModeSource = DeviceModeSource or "auto"
    Caps.IsMobile = DeviceMode == "Mobile"
    Caps.HasTouch = Caps.HasTouch or Caps.IsMobile

    local function safeHttpLoad(name, url, required)
        local okGet, source = pcall(function()
            return game:HttpGet(url)
        end)
        if not okGet or type(source) ~= "string" then
            if required then
                error(name .. " failed to download")
            end
            recordSkip(name, "download failed")
            return nil
        end

        local fn, loadErr = loadstring(source)
        if not fn then
            if required then
                error(name .. " failed to compile: " .. tostring(loadErr))
            end
            recordSkip(name, "compile failed")
            return nil
        end

        local okRun, result = pcall(fn)
        if not okRun then
            if required then
                error(name .. " failed to run: " .. tostring(result))
            end
            recordSkip(name, "runtime failed")
            return nil
        end
        return result
    end

    task.spawn(function()
        if G.ZephyrMVSDMiscLoaded or G.ZephyrMVSDMiscLaunchStarted then
            return
        end
        G.ZephyrMVSDMiscLaunchStarted = true
        safeHttpLoad(
            "Misc",
            "https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/Games/mvsd-misc.lua",
            false
        )
        G.ZephyrMVSDMiscLoaded = true
    end)

    local Fluent =
        safeHttpLoad("Fluent", "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua", true)
    local SaveManager = safeHttpLoad(
        "SaveManager",
        "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua",
        false
    )
    local InterfaceManager = safeHttpLoad(
        "InterfaceManager",
        "https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua",
        false
    )

    local mobileViewport = Camera and Camera.ViewportSize or Vector2.new(800, 600)
    local mobileWindowWidth = math.floor(math.clamp(mobileViewport.X * 0.48, 360, 460))
    local mobileWindowHeight = math.floor(math.clamp(mobileViewport.Y * 0.68, 300, 380))
    local Window = Fluent:CreateWindow({
        Title = "Zephyr",
        SubTitle = Caps.IsMobile and "Mobile | discord.gg/zephyrmvsd" or "discord.gg/zephyrmvsd",
        TabWidth = Caps.IsMobile and 96 or 150,
        Size = Caps.IsMobile and UDim2.fromOffset(mobileWindowWidth, mobileWindowHeight) or UDim2.fromOffset(640, 480),
        Acrylic = false,
        Theme = "Dark",
        MinimizeKey = Enum.KeyCode.LeftControl,
    })

    if Caps.IsMobile then
        task.defer(function()
            local root = Window.Root
            local camera = Workspace.CurrentCamera
            if root and root:IsA("GuiObject") and camera then
                local viewport = camera.ViewportSize
                root.Position = UDim2.fromOffset(math.floor(viewport.X * 0.3), math.floor(viewport.Y * 0.5))
            end
        end)
    end

    local function getDeviceUiScale(minScale, maxScale)
        minScale = tonumber(minScale) or 0.78
        maxScale = tonumber(maxScale) or 1
        local viewport = Camera and Camera.ViewportSize or Vector2.new(800, 600)
        local shortestSide = math.min(viewport.X, viewport.Y)
        local baseSide = Caps.IsMobile and 430 or 720
        return math.clamp(shortestSide / baseSide, minScale, maxScale)
    end

    local function scaledUiPx(value, minScale, maxScale)
        return math.floor((tonumber(value) or 0) * getDeviceUiScale(minScale, maxScale) + 0.5)
    end

    local function installMobileMenuToggle()
        if not Caps.IsMobile then
            return
        end

        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui")
        for _, oldName in ipairs({ "ZephyrMobileMenuToggle", "ZephyrMiscMobileToggle" }) do
            local oldToggle = playerGui:FindFirstChild(oldName)
            if oldToggle then
                oldToggle:Destroy()
            end
        end

        local existingToggle = playerGui:FindFirstChild("ZephyrSharedMenuToggle")
        if existingToggle then
            local shouldHide = readMenuToggleHiddenPreference()
            pcall(function()
                existingToggle.Enabled = not shouldHide
            end)
            if shouldHide then
                pcall(function()
                    local root = Window.Root
                    local screenGui = root and root:FindFirstAncestorWhichIsA("ScreenGui")
                    if screenGui then
                        screenGui.Enabled = false
                    end
                end)
            end
            return
        end

        local toggleGui = rememberInstance(Instance.new("ScreenGui"))
        toggleGui.Name = "ZephyrSharedMenuToggle"
        toggleGui.ResetOnSpawn = false
        toggleGui.IgnoreGuiInset = true
        toggleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        toggleGui.DisplayOrder = 1000000
        toggleGui.Parent = playerGui

        local toggleSize = scaledUiPx(42, 0.78, 1)
        local toggleMargin = scaledUiPx(16, 0.78, 1)
        local toggleTextSize = scaledUiPx(19, 0.84, 1)
        local glowPad = scaledUiPx(8, 0.78, 1)
        local dotSize = scaledUiPx(7, 0.78, 1)

        local button = rememberInstance(Instance.new("TextButton"))
        button.Name = "ToggleButton"
        button.Size = UDim2.fromOffset(toggleSize, toggleSize)
        button.Position = UDim2.new(1, -(toggleSize + toggleMargin), 0.5, -(toggleSize / 2))
        button.AnchorPoint = Vector2.new(0, 0)
        button.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
        button.BorderSizePixel = 0
        button.AutoButtonColor = false
        button.Text = ""
        button.TextColor3 = Color3.fromRGB(245, 248, 255)
        button.TextSize = scaledUiPx(22, 0.84, 1)
        button.Font = Enum.Font.GothamBlack
        button.ZIndex = 50
        button.ClipsDescendants = false
        button.Parent = toggleGui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = button

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(150, 170, 255)
        stroke.Thickness = 1.5
        stroke.Transparency = 0.15
        stroke.Parent = button

        local gradient = Instance.new("UIGradient")
        gradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(44, 50, 78)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 16, 24)),
        })
        gradient.Rotation = 135
        gradient.Parent = button

        local shine = Instance.new("Frame")
        shine.Name = "GlassHighlight"
        shine.Size = UDim2.new(1, -scaledUiPx(12, 0.78, 1), 0, scaledUiPx(18, 0.78, 1))
        shine.Position = UDim2.fromOffset(scaledUiPx(6, 0.78, 1), scaledUiPx(5, 0.78, 1))
        shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        shine.BackgroundTransparency = 1
        shine.BorderSizePixel = 0
        shine.ZIndex = 51
        shine.Parent = button

        local shineCorner = Instance.new("UICorner")
        shineCorner.CornerRadius = UDim.new(0, 11)
        shineCorner.Parent = shine

        local buttonLabel = Instance.new("TextLabel")
        buttonLabel.Name = "Glyph"
        buttonLabel.Size = UDim2.fromScale(1, 1)
        buttonLabel.BackgroundTransparency = 1
        buttonLabel.Text = "Z"
        buttonLabel.TextColor3 = Color3.fromRGB(250, 252, 255)
        buttonLabel.TextSize = toggleTextSize
        buttonLabel.Font = Enum.Font.GothamBlack
        buttonLabel.ZIndex = 52
        buttonLabel.Parent = button

        local scale = Instance.new("UIScale")
        scale.Scale = 1
        scale.Parent = button

        local glow = rememberInstance(Instance.new("Frame"))
        glow.Name = "Glow"
        glow.Size = UDim2.new(1, glowPad * 2, 1, glowPad * 2)
        glow.Position = UDim2.fromOffset(-glowPad, -glowPad)
        glow.BackgroundColor3 = Color3.fromRGB(75, 115, 255)
        glow.BackgroundTransparency = 1
        glow.BorderSizePixel = 0
        glow.ZIndex = 49
        glow.Parent = button

        local glowCorner = Instance.new("UICorner")
        glowCorner.CornerRadius = UDim.new(1, 0)
        glowCorner.Parent = glow

        local dot = Instance.new("Frame")
        dot.Name = "StatusDot"
        dot.Size = UDim2.fromOffset(dotSize, dotSize)
        dot.Position = UDim2.new(1, -scaledUiPx(10, 0.78, 1), 0, scaledUiPx(7, 0.78, 1))
        dot.BackgroundColor3 = Color3.fromRGB(80, 255, 165)
        dot.BorderSizePixel = 0
        dot.ZIndex = 53
        dot.Parent = button

        local dotCorner = Instance.new("UICorner")
        dotCorner.CornerRadius = UDim.new(1, 0)
        dotCorner.Parent = dot

        local cachedTargetGui = nil
        local menuOpen = true
        local hiddenByChat = readMenuToggleHiddenPreference()
        toggleGui.Enabled = not hiddenByChat
        local targetTitles = {
            ["Zephyr"] = true,
            ["Zephyrs Rage Cheats"] = true,
        }

        local function getOptionalContainer(serviceName)
            local ok, service = pcall(game.GetService, game, serviceName)
            if ok then
                return service
            end
            return nil
        end

        local function hasZephyrTitle(root)
            for _, obj in ipairs(root:GetDescendants()) do
                if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                    local text = tostring(obj.Text or "")
                    if targetTitles[text] then
                        return true
                    end
                end
            end
            return false
        end

        local function findZephyrGuis()
            local found = {}
            local seen = {}
            local containers = { playerGui }
            local coreGui = getOptionalContainer("CoreGui")
            if coreGui then
                table.insert(containers, coreGui)
            end

            local gethuiFn = getFunction("gethui")
            if gethuiFn then
                local ok, hui = pcall(gethuiFn)
                if ok and hui then
                    table.insert(containers, hui)
                end
            end

            for _, container in ipairs(containers) do
                for _, gui in ipairs(container:GetChildren()) do
                    if
                        gui:IsA("ScreenGui")
                        and gui ~= toggleGui
                        and gui.Name ~= "ZephyrSharedMenuToggle"
                        and not seen[gui]
                        and hasZephyrTitle(gui)
                    then
                        seen[gui] = true
                        cachedTargetGui = gui
                        table.insert(found, gui)
                    end
                end
            end

            return found
        end

        local function setButtonState(open)
            menuOpen = open
            dot.BackgroundColor3 = open and Color3.fromRGB(80, 255, 165) or Color3.fromRGB(255, 190, 85)
            stroke.Color = open and Color3.fromRGB(135, 165, 255) or Color3.fromRGB(255, 205, 120)
            buttonLabel.Text = open and "Z" or "+"
        end

        local function setMenuOpen(open)
            local targetGuis = findZephyrGuis()
            if #targetGuis > 0 then
                for _, targetGui in ipairs(targetGuis) do
                    pcall(function()
                        targetGui.Enabled = open
                    end)
                end
                setButtonState(open)
            else
                setButtonState(true)
                Fluent:Notify({ Title = "Zephyr", Content = "Menu UI not found yet", Duration = 2 })
            end
        end

        local function setAllZephyrGuisVisible(visible)
            local targetGuis = findZephyrGuis()
            for _, targetGui in ipairs(targetGuis) do
                pcall(function()
                    targetGui.Enabled = visible
                end)
            end
            setButtonState(visible)
            return #targetGuis > 0
        end

        local function refreshButtonState()
            local targetGuis = findZephyrGuis()
            if #targetGuis == 0 then
                return
            end
            local anyOpen = false
            for _, targetGui in ipairs(targetGuis) do
                pcall(function()
                    if targetGui.Enabled then
                        anyOpen = true
                    end
                end)
            end
            setButtonState(anyOpen)
        end

        local dragging = false
        local moved = false
        local dragStart = nil
        local dragInput = nil
        local dragThreshold = 14

        local function inputPoint(input)
            local inset = GuiService:GetGuiInset()
            return Vector2.new(input.Position.X + inset.X, input.Position.Y + inset.Y)
        end

        local function placeButtonAt(point)
            local viewport = Camera.ViewportSize
            local size = button.AbsoluteSize
            local x = math.clamp(point.X - (size.X / 2), 8, viewport.X - size.X - 8)
            local y = math.clamp(point.Y - (size.Y / 2), 8, viewport.Y - size.Y - 8)
            button.Position = UDim2.fromOffset(x, y)
        end

        button.InputBegan:Connect(function(input)
            if
                input.UserInputType ~= Enum.UserInputType.Touch
                and input.UserInputType ~= Enum.UserInputType.MouseButton1
            then
                return
            end

            dragging = true
            moved = false
            dragInput = input
            dragStart = inputPoint(input)

            TweenService
                :Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 0.92 })
                :Play()

            local endConn
            endConn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    dragStart = nil
                    dragInput = nil
                    TweenService
                        :Create(
                            scale,
                            TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                            { Scale = 1 }
                        )
                        :Play()
                    if endConn then
                        endConn:Disconnect()
                    end
                end
            end)
            rememberConnection(endConn)
        end)

        rememberConnection(UserInputService.InputChanged:Connect(function(input)
            if not dragging or not dragStart then
                return
            end
            if dragInput and dragInput.UserInputType == Enum.UserInputType.Touch and input ~= dragInput then
                return
            end
            if
                dragInput
                and dragInput.UserInputType ~= Enum.UserInputType.Touch
                and input.UserInputType ~= Enum.UserInputType.MouseMovement
            then
                return
            end

            local currentPoint = inputPoint(input)
            local delta = currentPoint - dragStart
            if delta.Magnitude > dragThreshold then
                moved = true
            end
            if not moved then
                return
            end

            placeButtonAt(currentPoint)
        end))

        button.MouseButton1Click:Connect(function()
            if moved or hiddenByChat then
                return
            end
            setMenuOpen(not menuOpen)
        end)

        local function handleChatCommand(message)
            local command = tostring(message or ""):lower():match("^%s*(.-)%s*$")
            if command == "/e hide" then
                hiddenByChat = true
                writeMenuToggleHiddenPreference(true)
                setAllZephyrGuisVisible(false)
                toggleGui.Enabled = false
            elseif command == "/e unhide" then
                hiddenByChat = false
                writeMenuToggleHiddenPreference(false)
                toggleGui.Enabled = true
                task.defer(function()
                    setAllZephyrGuisVisible(true)
                end)
            end
        end

        rememberConnection(LocalPlayer.Chatted:Connect(handleChatCommand))
        pcall(function()
            local TextChatService = game:GetService("TextChatService")
            rememberConnection(TextChatService.MessageReceived:Connect(function(message)
                local source = message.TextSource
                if source and source.UserId == LocalPlayer.UserId then
                    handleChatCommand(message.Text)
                end
            end))
        end)

        task.defer(function()
            if hiddenByChat then
                setAllZephyrGuisVisible(false)
                toggleGui.Enabled = false
            else
                refreshButtonState()
            end
        end)
    end

    installMobileMenuToggle()

    local Tabs = {}
    if not Caps.IsMobile and Caps.HasMouseMove then
        Tabs.Aim = Window:AddTab({ Title = "Aim", Icon = "crosshair" })
    end
    Tabs.Shots = Window:AddTab({ Title = "Shots", Icon = "target" })
    Tabs.Trigger = Window:AddTab({ Title = "Trigger", Icon = "crosshair" })
    Tabs.Hitbox = Window:AddTab({ Title = "Hitbox", Icon = "box" })
    Tabs.Visuals = Window:AddTab({ Title = "Visuals", Icon = "eye" })
    Tabs.Abilities = Window:AddTab({ Title = "Abilities", Icon = "gem" })
    Tabs.Player = Window:AddTab({ Title = "Player", Icon = "user" })
    Tabs.Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
    Tabs.Main = Tabs.Aim or Tabs.Shots

    local Options = Fluent.Options

    local function hasRequirements(requirements)
        for _, req in ipairs(requirements or {}) do
            if not Caps[req] then
                return false, req
            end
        end
        return true
    end

    local function registerFeature(name, requirements, device, init)
        if device == "Mobile" and not Caps.IsMobile then
            recordSkip(name, "mobile only")
            return
        end
        if device == "PC" and Caps.IsMobile then
            recordSkip(name, "PC only")
            return
        end

        local okReq, missing = hasRequirements(requirements)
        if not okReq then
            recordSkip(name, "missing " .. tostring(missing))
            return
        end

        local ok, err = pcall(init)
        if not ok then
            recordSkip(name, err)
        end
    end

    local Perf = {
        AutoShootScanRate = Caps.IsMobile and (1 / 24) or (1 / 75),
        TriggerbotRate = 1 / 45,
        HBEInterval = Caps.IsMobile and 0.65 or 0.45,
        ESPUpdateRate = Caps.IsMobile and (1 / 45) or (1 / 60),
        ESPHeavyRate = Caps.IsMobile and (1 / 24) or (1 / 30),
        ESPMaxTargets = math.huge,
        ESPMaxDistance = math.huge,
        AdornmentRefreshRate = 0.9,
        HiddenRefreshRate = 1.5,
    }

    local HiddenMaps = ReplicatedStorage:FindFirstChild("HiddenMaps")
    local HiddenCharacters = ReplicatedStorage:FindFirstChild("HiddenCharacters")
    local lastHiddenRefresh = 0

    local function refreshHiddenFolders(force)
        local now = tick()
        if force or now - lastHiddenRefresh >= Perf.HiddenRefreshRate then
            HiddenMaps = ReplicatedStorage:FindFirstChild("HiddenMaps")
            HiddenCharacters = ReplicatedStorage:FindFirstChild("HiddenCharacters")
            lastHiddenRefresh = now
        end
    end

    rememberConnection(ReplicatedStorage.ChildAdded:Connect(function(child)
        if child.Name == "HiddenMaps" then
            HiddenMaps = child
        end
        if child.Name == "HiddenCharacters" then
            HiddenCharacters = child
        end
    end))

    rememberConnection(ReplicatedStorage.ChildRemoved:Connect(function(child)
        if child == HiddenMaps then
            HiddenMaps = nil
        end
        if child == HiddenCharacters then
            HiddenCharacters = nil
        end
    end))

    local TrackedPlayers = {}
    local function rebuildTrackedPlayers()
        table.clear(TrackedPlayers)
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                table.insert(TrackedPlayers, player)
            end
        end
    end
    rebuildTrackedPlayers()
    rememberConnection(Players.PlayerAdded:Connect(function(player)
        if player ~= LocalPlayer then
            table.insert(TrackedPlayers, player)
        end
    end))
    rememberConnection(Players.PlayerRemoving:Connect(function(player)
        for i = #TrackedPlayers, 1, -1 do
            if TrackedPlayers[i] == player then
                table.remove(TrackedPlayers, i)
                break
            end
        end
    end))

    local function hiddenFolders()
        refreshHiddenFolders(false)
        return { HiddenMaps, HiddenCharacters }
    end

    local function areHiddenFoldersPresent()
        for _, folder in ipairs(hiddenFolders()) do
            if folder then
                return true
            end
        end
        return false
    end

    local function isCharacterHidden(character)
        for _, folder in ipairs(hiddenFolders()) do
            if folder and character and folder:IsAncestorOf(character) then
                return true
            end
        end
        return false
    end

    local function safeGetHumanoid(character)
        if not character then
            return nil
        end
        return character:FindFirstChildOfClass("Humanoid")
    end

    local function isTeammateOf(player)
        return player and player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team
    end

    local function isEnemyOf(player)
        return player and player.Team and LocalPlayer.Team and player.Team ~= LocalPlayer.Team
    end

    local function isOnTeam(player)
        return player and player.Team ~= nil
    end

    local function getTeamColor(player)
        return isTeammateOf(player) and Color3.new(0.1, 0.4, 0.8) or Color3.new(0.8, 0.1, 0.1)
    end

    local function isPlayerAlive(player)
        local hum = player and player.Character and safeGetHumanoid(player.Character)
        return hum and hum.Health > 0
    end

    local function getMatchValue(player)
        if not player then
            return nil
        end
        local ok, value = pcall(function()
            return player:GetAttribute("Match")
        end)
        if ok then
            return value
        end
        return nil
    end

    local function hasMatchValue(value)
        return value ~= nil and value ~= false and value ~= 0 and value ~= ""
    end

    local function isLocalInMatch()
        return hasMatchValue(getMatchValue(LocalPlayer))
    end

    local function isPlayerInSameMatch(player)
        if not player or player == LocalPlayer then
            return false
        end

        local localMatch = getMatchValue(LocalPlayer)
        if not hasMatchValue(localMatch) then
            return false
        end

        local targetMatch = getMatchValue(player)
        if targetMatch ~= nil and not hasMatchValue(targetMatch) then
            return false
        end
        if targetMatch == nil then
            return true
        end

        if type(localMatch) == "boolean" or type(targetMatch) == "boolean" then
            return true
        end

        return tostring(localMatch) == tostring(targetMatch)
    end

    local function isCharacterInWorld(character)
        return character and character.Parent and character:IsDescendantOf(Workspace)
    end

    local function shouldShowPlayerESP(player, character, humanoid, root, teamCheck, aliveCheck)
        if not player or player == LocalPlayer or not player.Parent then
            return false
        end
        if not isPlayerInSameMatch(player) then
            return false
        end
        if not isCharacterInWorld(character) or isCharacterHidden(character) then
            return false
        end
        if not humanoid or not root or not root.Parent then
            return false
        end
        if aliveCheck ~= false and humanoid.Health <= 0 then
            return false
        end
        if teamCheck and isTeammateOf(player) then
            return false
        end
        return true
    end

    local function isInSoulReapMode(player)
        local character = player and player.Character
        if not character then
            return false
        end
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") and part.Material == Enum.Material.ForceField then
                return true
            end
        end
        return false
    end

    local shootRemote
    do
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local remote = remotes and remotes:FindFirstChild("ShootGun")
        if remote and remote:IsA("RemoteEvent") then
            shootRemote = remote
        end
    end

    local BulletBeamTemplate
    do
        local modules = ReplicatedStorage:FindFirstChild("Modules")
        local br = modules and modules:FindFirstChild("BulletRenderer")
        local db = br and br:FindFirstChild("DefaultBullet")
        BulletBeamTemplate = db and db:FindFirstChild("BulletBeam") or nil
    end

    local lastToolEquipTime = 0
    local TOOL_EQUIP_DELAY = 0.3
    local cachedToolValid = false
    local cachedToolValidTime = 0
    local TOOL_CACHE_DURATION = 0.2
    local SHOT_LOCK_TIME = 0.15
    local scriptShotLockUntil = 0
    local scriptShotToken = 0
    local cachedAnimationTrack = nil
    local fireSoundCache = setmetatable({}, { __mode = "k" })

    local function canUseScriptShot()
        return tick() >= scriptShotLockUntil
    end

    local function reserveScriptShot(lockTime)
        local now = tick()
        if now < scriptShotLockUntil then
            return nil
        end
        scriptShotToken = scriptShotToken + 1
        scriptShotLockUntil = now + math.max(tonumber(lockTime) or SHOT_LOCK_TIME, SHOT_LOCK_TIME)
        return scriptShotToken
    end

    local function commitScriptShot(token, cooldown)
        if token and token ~= scriptShotToken then
            return
        end
        local now = tick()
        scriptShotLockUntil =
            math.max(scriptShotLockUntil, now + math.max(tonumber(cooldown) or SHOT_LOCK_TIME, SHOT_LOCK_TIME))
    end

    local function releaseScriptShot(token, graceTime)
        if token and token ~= scriptShotToken then
            return
        end
        local now = tick()
        scriptShotLockUntil = math.min(scriptShotLockUntil, now + math.max(tonumber(graceTime) or 0, 0))
    end

    local function isScriptShotTokenCurrent(token)
        return token ~= nil and token == scriptShotToken
    end

    local function isToolFullyEquipped()
        return (tick() - lastToolEquipTime) >= TOOL_EQUIP_DELAY
    end

    local function findEquippedTool()
        local character = LocalPlayer.Character
        if not character then
            return nil
        end
        return character:FindFirstChildOfClass("Tool")
    end

    local function findFireSoundInTool(tool)
        if not tool then
            return nil
        end
        local cached = fireSoundCache[tool]
        if cached ~= nil then
            return cached ~= false and cached or nil
        end

        local direct = tool:FindFirstChild("Fire", true)
        if direct and direct:IsA("Sound") then
            fireSoundCache[tool] = direct
            return direct
        end

        for _, desc in ipairs(tool:GetDescendants()) do
            if desc:IsA("Sound") and desc.Name:lower() == "fire" then
                fireSoundCache[tool] = desc
                return desc
            end
        end
        fireSoundCache[tool] = false
        return nil
    end

    local function findToolAudio()
        return findFireSoundInTool(findEquippedTool())
    end

    local function isGunTool(tool)
        return findFireSoundInTool(tool) ~= nil
    end

    local function getEffectiveGunCooldown(fallback)
        local fallbackTime = tonumber(fallback) or 2.5
        local tool = findEquippedTool()
        if tool and isGunTool(tool) then
            local liveCooldown = tonumber(tool:GetAttribute("Cooldown"))
            if liveCooldown and liveCooldown > 0 then
                return math.max(SHOT_LOCK_TIME, math.min(fallbackTime, liveCooldown))
            end
        end
        return math.max(SHOT_LOCK_TIME, fallbackTime)
    end

    local function isToolValidRaw()
        return findToolAudio() ~= nil
    end

    local function isToolValid()
        local now = tick()
        if now - cachedToolValidTime > TOOL_CACHE_DURATION then
            cachedToolValid = isToolValidRaw()
            cachedToolValidTime = now
        end
        return cachedToolValid
    end

    local function isAnyToolEquipped()
        return findEquippedTool() ~= nil
    end

    local function getTracerOrigin()
        local character = LocalPlayer.Character
        if not character then
            return nil, nil
        end
        local tool = findEquippedTool()
        if tool then
            local rightHandle = tool:FindFirstChild("RightHandle")
            local muzzle = rightHandle and rightHandle:FindFirstChild("Muzzle")
            if muzzle and muzzle:IsA("Attachment") then
                return muzzle.WorldPosition, muzzle
            end

            local deepMuzzle = tool:FindFirstChild("Muzzle", true)
            if deepMuzzle then
                if deepMuzzle:IsA("Attachment") then
                    return deepMuzzle.WorldPosition, deepMuzzle
                end
                if deepMuzzle:IsA("BasePart") then
                    return deepMuzzle.Position, deepMuzzle
                end
            end
        end

        local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
        if torso then
            return torso.Position, nil
        end
        local head = character:FindFirstChild("Head")
        if head then
            return head.Position, nil
        end
        return nil, nil
    end

    local function getShotOrigin()
        local character = LocalPlayer.Character
        if not character then
            return nil
        end

        local head = character:FindFirstChild("Head")
        if head then
            return head.Position
        end

        local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
        if torso then
            return torso.Position
        end

        local root = character:FindFirstChild("HumanoidRootPart")
        if root then
            return root.Position
        end

        local fallback = getTracerOrigin()
        return fallback
    end

    local function getTorsoPosition()
        local character = LocalPlayer.Character
        if not character then
            return nil
        end
        local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
        return torso and torso.Position or nil
    end

    local sharedRayParams = RaycastParams.new()
    sharedRayParams.FilterType = Enum.RaycastFilterType.Blacklist
    local tapRayParams = RaycastParams.new()
    tapRayParams.FilterType = Enum.RaycastFilterType.Blacklist

    local function getWorldPointFromViewport(point, distance)
        point = toVector2(point)
        distance = distance or 5000
        local ray = Camera:ViewportPointToRay(point.X, point.Y)
        tapRayParams.FilterDescendantsInstances = { LocalPlayer.Character }
        local result = Workspace:Raycast(ray.Origin, ray.Direction * distance, tapRayParams)
        return result and result.Position or (ray.Origin + ray.Direction * distance)
    end

    local function getWorldPointFromScreen(point, distance)
        point = toVector2(point)
        distance = distance or 5000
        local ray = Camera:ScreenPointToRay(point.X, point.Y)
        tapRayParams.FilterDescendantsInstances = { LocalPlayer.Character }
        local result = Workspace:Raycast(ray.Origin, ray.Direction * distance, tapRayParams)
        return result and result.Position or (ray.Origin + ray.Direction * distance)
    end

    local function isLikelyMobileFireControl(position)
        if not position or not Caps.IsMobile then
            return false
        end
        local point = toVector2(position)
        local viewport = Camera.ViewportSize
        return point.X >= viewport.X * 0.82 and point.Y >= viewport.Y * 0.30 and point.Y <= viewport.Y * 0.48
    end

    local function isLikelyMobileJumpControl(position)
        if not position or not Caps.IsMobile then
            return false
        end
        local point = toVector2(position)
        local viewport = Camera.ViewportSize
        return point.X >= viewport.X * 0.78 and point.Y > viewport.Y * 0.62
    end

    local function isLikelyMobileControlArea(position)
        if not position or not Caps.IsMobile then
            return false
        end
        if isLikelyMobileJumpControl(position) then
            return true
        end

        local point = toVector2(position)
        local viewport = Camera.ViewportSize

        if point.X >= viewport.X * 0.68 and point.Y >= viewport.Y * 0.46 then
            return true
        end
        if point.Y >= viewport.Y * 0.66 then
            return true
        end
        if point.X <= viewport.X * 0.42 and point.Y >= viewport.Y * 0.48 then
            return true
        end
        if point.Y >= viewport.Y * 0.58 and point.X >= viewport.X * 0.35 then
            return true
        end

        return false
    end

    local function getMouseHitPoint()
        local ok, hit = pcall(function()
            return Mouse and Mouse.Hit
        end)
        if ok and typeof(hit) == "CFrame" then
            return hit.Position
        end
        return nil
    end

    local function getPcMouseWorldPoint(distance)
        local mouseHit = getMouseHitPoint()
        if mouseHit then
            return mouseHit
        end
        return getWorldPointFromScreen(getMouseScreenPoint(), distance or 5000)
    end

    local function worldPointToViewportPoint(worldPoint)
        if not worldPoint then
            return nil
        end
        local screenPoint = Camera:WorldToViewportPoint(worldPoint)
        return Vector2.new(screenPoint.X, screenPoint.Y)
    end

    local function getManualAimWorldPoint(touchPosition, distance)
        distance = distance or 5000
        local touchIsFireControl = isLikelyMobileFireControl(touchPosition)
        if touchPosition then
            if touchIsFireControl then
                local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
                return getWorldPointFromViewport(center, distance), center
            end

            local touchPoint = toVector2(touchPosition)
            return getWorldPointFromScreen(touchPoint, distance), touchPoint
        end

        local mouseHit = getMouseHitPoint()
        if mouseHit then
            return mouseHit, worldPointToViewportPoint(mouseHit)
        end

        local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
        return getWorldPointFromViewport(center, distance), center
    end

    local function isTargetVisible(origin, targetPart)
        if not origin or not targetPart or not targetPart:IsA("BasePart") then
            return false
        end
        sharedRayParams.FilterDescendantsInstances = { LocalPlayer.Character }
        local result = Workspace:Raycast(origin, targetPart.Position - origin, sharedRayParams)
        return not result or (result.Instance and result.Instance:IsDescendantOf(targetPart.Parent)) or false
    end

    local function isTargetOnScreen(targetPart)
        if not targetPart then
            return false
        end
        local _, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
        return onScreen
    end

    local bodyPartCornerScales = {
        Vector3.new(0, 0, 0),
        Vector3.new(-0.5, -0.5, -0.5),
        Vector3.new(-0.5, -0.5, 0.5),
        Vector3.new(-0.5, 0.5, -0.5),
        Vector3.new(-0.5, 0.5, 0.5),
        Vector3.new(0.5, -0.5, -0.5),
        Vector3.new(0.5, -0.5, 0.5),
        Vector3.new(0.5, 0.5, -0.5),
        Vector3.new(0.5, 0.5, 0.5),
    }

    local bodyPartAimScales = {
        Vector3.new(0, 0, 0),
        Vector3.new(0, 0.5, 0),
        Vector3.new(0, -0.5, 0),
        Vector3.new(0.5, 0, 0),
        Vector3.new(-0.5, 0, 0),
        Vector3.new(0, 0, 0.5),
        Vector3.new(0, 0, -0.5),
        Vector3.new(0.35, 0.35, 0),
        Vector3.new(-0.35, 0.35, 0),
        Vector3.new(0.35, -0.35, 0),
        Vector3.new(-0.35, -0.35, 0),
    }

    local function projectBodyPartPoint(worldPoint, useScreenPoint)
        local ok, projected, onScreen = pcall(function()
            if useScreenPoint then
                return Camera:WorldToScreenPoint(worldPoint)
            end
            return Camera:WorldToViewportPoint(worldPoint)
        end)
        if not ok or not projected or not onScreen then
            return nil, false
        end
        return Vector2.new(projected.X, projected.Y), true
    end

    local function getProjectedBodyPartDistance(part, point, useScreenPoint)
        if not part or not part:IsA("BasePart") then
            return nil, math.huge
        end
        point = toVector2(point)

        local centerPoint, onScreen = projectBodyPartPoint(part.Position, useScreenPoint)
        if not onScreen then
            return nil, math.huge
        end
        local centerDistance = (centerPoint - point).Magnitude
        local projectedRadius = 0
        local size = part.Size

        for _, scale in ipairs(bodyPartCornerScales) do
            local cornerWorld =
                part.CFrame:PointToWorldSpace(Vector3.new(size.X * scale.X, size.Y * scale.Y, size.Z * scale.Z))
            local cornerPoint, cornerOnScreen = projectBodyPartPoint(cornerWorld, useScreenPoint)
            if cornerOnScreen then
                local cornerDistance = (cornerPoint - centerPoint).Magnitude
                if cornerDistance > projectedRadius then
                    projectedRadius = cornerDistance
                end
            end
        end

        return math.max(centerDistance - projectedRadius, 0), centerDistance
    end

    local function getBodyPartViewportDistance(part, point)
        return getProjectedBodyPartDistance(part, point, false)
    end

    local function getBodyPartScreenDistance(part, point)
        return getProjectedBodyPartDistance(part, point, true)
    end

    local function getClosestAimPositionOnPart(part, point, useScreenPoint)
        if not part or not part:IsA("BasePart") then
            return nil
        end
        if not point then
            return part.Position
        end
        point = toVector2(point)

        local bestWorld = part.Position
        local bestDistance = math.huge
        local size = part.Size

        for _, scale in ipairs(bodyPartAimScales) do
            local worldPoint =
                part.CFrame:PointToWorldSpace(Vector3.new(size.X * scale.X, size.Y * scale.Y, size.Z * scale.Z))
            local projected, onScreen = projectBodyPartPoint(worldPoint, useScreenPoint)
            if onScreen then
                local distance = (projected - point).Magnitude
                if distance < bestDistance then
                    bestDistance = distance
                    bestWorld = worldPoint
                end
            end
        end

        return bestWorld
    end

    local function getClosestBodyPartByProjectedDistance(player, point, useScreenPoint)
        local closestPart = nil
        local shortestEdgeDistance = math.huge
        local shortestCenterDistance = math.huge
        if not player or not player.Character then
            return nil, shortestEdgeDistance
        end
        point = toVector2(point)

        for pass = 1, 2 do
            local allowRoot = pass == 2
            for _, part in ipairs(player.Character:GetChildren()) do
                if part:IsA("BasePart") and (allowRoot or part.Name ~= "HumanoidRootPart") then
                    local edgeDistance, centerDistance = getProjectedBodyPartDistance(part, point, useScreenPoint)
                    if
                        edgeDistance
                        and (
                            edgeDistance < shortestEdgeDistance
                            or (edgeDistance == shortestEdgeDistance and centerDistance < shortestCenterDistance)
                        )
                    then
                        closestPart = part
                        shortestEdgeDistance = edgeDistance
                        shortestCenterDistance = centerDistance
                    end
                end
            end
            if closestPart then
                break
            end
        end

        return closestPart, shortestEdgeDistance
    end

    local function getClosestBodyPartToPoint(player, point)
        return getClosestBodyPartByProjectedDistance(player, point, false)
    end

    local function getClosestBodyPartToScreenPoint(player, point)
        return getClosestBodyPartByProjectedDistance(player, point, true)
    end

    local function isBodyPartInsidePointRadius(part, point, radius)
        local edgeDistance = getBodyPartViewportDistance(part, point)
        return edgeDistance ~= nil and edgeDistance <= (tonumber(radius) or 0)
    end

    local function isWorldPointOnScreen(worldPoint)
        if not worldPoint then
            return false
        end
        local _, onScreen = Camera:WorldToViewportPoint(worldPoint)
        return onScreen
    end

    local function isCharacterPointVisible(origin, character, worldPoint)
        if not origin or not character or not worldPoint then
            return false
        end
        sharedRayParams.FilterDescendantsInstances = { LocalPlayer.Character }
        local result = Workspace:Raycast(origin, worldPoint - origin, sharedRayParams)
        return not result or (result.Instance and result.Instance:IsDescendantOf(character)) or false
    end

    local function isShotCandidate(player)
        return player ~= LocalPlayer
            and player.Character
            and isPlayerAlive(player)
            and not isTeammateOf(player)
            and not isCharacterHidden(player.Character)
            and not isInSoulReapMode(player)
    end

    local function getPlayerFromPart(part)
        if not part then
            return nil
        end
        for _, player in ipairs(TrackedPlayers) do
            local character = player.Character
            if character and part:IsDescendantOf(character) then
                return player
            end
        end
        return nil
    end

    local function normalizeTargetPart(player, hitPart, point)
        local character = player and player.Character
        if not character then
            return nil
        end
        if hitPart and hitPart:IsA("BasePart") and hitPart.Parent == character then
            return hitPart
        end
        return getClosestBodyPartToPoint(player, point)
    end

    local function getDirectPlayerAtPoint(point)
        point = toVector2(point)
        local origin = getShotOrigin()
        if not origin then
            return nil, nil
        end

        local ray = Camera:ScreenPointToRay(point.X, point.Y)
        tapRayParams.FilterDescendantsInstances = { LocalPlayer.Character }
        local result = Workspace:Raycast(ray.Origin, ray.Direction * 5000, tapRayParams)
        local hitPart = result and result.Instance
        if not hitPart or not hitPart:IsA("BasePart") then
            return nil, nil
        end

        local player = getPlayerFromPart(hitPart)
        if not player or not isShotCandidate(player) then
            return nil, nil
        end

        local targetPart = normalizeTargetPart(player, hitPart, point)
        if targetPart and isTargetVisible(origin, targetPart) and isTargetOnScreen(targetPart) then
            return player, targetPart
        end
        return nil, nil
    end

    local function getDirectPlayerAtScreenPoint(screenPoint)
        screenPoint = toVector2(screenPoint)

        local origin = getShotOrigin()
        if not origin then
            return nil, nil
        end

        local ray = Camera:ScreenPointToRay(screenPoint.X, screenPoint.Y)
        tapRayParams.FilterDescendantsInstances = { LocalPlayer.Character }
        local result = Workspace:Raycast(ray.Origin, ray.Direction * 5000, tapRayParams)
        local hitPart = result and result.Instance
        if not hitPart or not hitPart:IsA("BasePart") then
            return nil, nil
        end

        local player = getPlayerFromPart(hitPart)
        if not player or not isShotCandidate(player) then
            return nil, nil
        end

        local targetPart = nil
        local character = player.Character
        if character and hitPart.Parent == character then
            targetPart = hitPart
        else
            targetPart = getClosestBodyPartToScreenPoint(player, screenPoint)
        end
        if targetPart and isTargetVisible(origin, targetPart) and isTargetOnScreen(targetPart) then
            return player, targetPart
        end
        return nil, nil
    end

    local function getClosestPlayerToPoint(point, radius)
        local directPlayer, directPart = getDirectPlayerAtPoint(point)
        if directPlayer then
            return directPlayer, directPart
        end

        local closestPlayer = nil
        local closestPart = nil
        local shortestDistance = math.huge
        local origin = getShotOrigin()
        if not origin then
            return nil
        end

        for _, player in ipairs(TrackedPlayers) do
            if isShotCandidate(player) then
                local closestBodyPart, distance = getClosestBodyPartToPoint(player, point)
                if
                    closestBodyPart
                    and distance < shortestDistance
                    and (not radius or distance <= radius)
                    and isTargetVisible(origin, closestBodyPart)
                then
                    closestPlayer = player
                    closestPart = closestBodyPart
                    shortestDistance = distance
                end
            end
        end

        return closestPlayer, closestPart
    end

    local function getClosestPlayerByBodyPartRadius(point, radius)
        point = toVector2(point)
        radius = tonumber(radius) or 0

        local closestPlayer = nil
        local closestPart = nil
        local shortestEdgeDistance = math.huge
        local shortestCenterDistance = math.huge
        local origin = getShotOrigin()
        if not origin then
            return nil, nil
        end

        for _, player in ipairs(TrackedPlayers) do
            if isShotCandidate(player) then
                for _, part in ipairs(player.Character:GetChildren()) do
                    if part:IsA("BasePart") then
                        local edgeDistance, centerDistance = getBodyPartViewportDistance(part, point)
                        if
                            edgeDistance
                            and edgeDistance <= radius
                            and isTargetVisible(origin, part)
                            and (
                                edgeDistance < shortestEdgeDistance
                                or (edgeDistance == shortestEdgeDistance and centerDistance < shortestCenterDistance)
                            )
                        then
                            closestPlayer = player
                            closestPart = part
                            shortestEdgeDistance = edgeDistance
                            shortestCenterDistance = centerDistance
                        end
                    end
                end
            end
        end

        return closestPlayer, closestPart
    end

    local toeShotPriorityNames = {
        "LeftFoot",
        "RightFoot",
        "LeftLowerLeg",
        "RightLowerLeg",
        "Left Leg",
        "Right Leg",
        "LowerTorso",
        "Torso",
        "HumanoidRootPart",
    }

    local function getToeShotCandidateParts(character)
        local parts = {}
        local seen = {}

        for _, name in ipairs(toeShotPriorityNames) do
            local part = character and character:FindFirstChild(name)
            if part and part:IsA("BasePart") and not seen[part] then
                seen[part] = true
                table.insert(parts, part)
            end
        end

        local root = character and character:FindFirstChild("HumanoidRootPart")
        local rootY = root and root.Position.Y or nil
        if character then
            for _, part in ipairs(character:GetChildren()) do
                if part:IsA("BasePart") and not seen[part] then
                    if not rootY or part.Position.Y <= rootY + 0.5 then
                        seen[part] = true
                        table.insert(parts, part)
                    end
                end
            end
        end

        return parts
    end

    local function getToeShotSamplePoints(part)
        local size = part.Size
        local bottom = -size.Y * 0.48
        local sideX = size.X * 0.34
        local sideZ = size.Z * 0.34
        local samples = {
            Vector3.new(0, bottom, 0),
            Vector3.new(sideX, bottom, 0),
            Vector3.new(-sideX, bottom, 0),
            Vector3.new(0, bottom, sideZ),
            Vector3.new(0, bottom, -sideZ),
            Vector3.new(0, -size.Y * 0.28, 0),
        }
        local points = {}
        for _, offset in ipairs(samples) do
            table.insert(points, part.CFrame:PointToWorldSpace(offset))
        end
        return points
    end

    local function getClosestToeShotTarget(point, radius)
        point = toVector2(point)
        radius = tonumber(radius) or math.huge

        local origin = getShotOrigin()
        if not origin then
            return nil, nil, nil, point
        end

        local bestPlayer = nil
        local bestPart = nil
        local bestAimPosition = nil
        local bestScreenPoint = nil
        local bestScore = math.huge

        for _, player in ipairs(TrackedPlayers) do
            if isShotCandidate(player) then
                local character = player.Character
                local parts = getToeShotCandidateParts(character)
                for priority, part in ipairs(parts) do
                    for sampleIndex, aimPosition in ipairs(getToeShotSamplePoints(part)) do
                        local screenPos, onScreen = Camera:WorldToViewportPoint(aimPosition)
                        if onScreen and isCharacterPointVisible(origin, character, aimPosition) then
                            local screenPoint = Vector2.new(screenPos.X, screenPos.Y)
                            local distance = (screenPoint - point).Magnitude
                            if distance <= radius then
                                local score = distance + (priority * 6) + (sampleIndex * 0.35)
                                if score < bestScore then
                                    bestPlayer = player
                                    bestPart = part
                                    bestAimPosition = aimPosition
                                    bestScreenPoint = screenPoint
                                    bestScore = score
                                end
                            end
                        end
                    end
                end
            end
        end

        return bestPlayer, bestPart, bestAimPosition, bestScreenPoint or point
    end

    local function getClosestPlayerToPcMouse(radius)
        local screenPoint = getMouseScreenPoint()
        local viewportPoint = inputPointToViewport(screenPoint)

        local directPlayer, directPart = getDirectPlayerAtScreenPoint(screenPoint)
        if directPlayer then
            return directPlayer, directPart, viewportPoint, screenPoint
        end

        local closestPlayer = nil
        local closestPart = nil
        local shortestDistance = math.huge
        local origin = getShotOrigin()
        if not origin then
            return nil, nil, viewportPoint, screenPoint
        end

        for _, player in ipairs(TrackedPlayers) do
            if isShotCandidate(player) then
                local closestBodyPart, distance = getClosestBodyPartToScreenPoint(player, screenPoint)
                if
                    closestBodyPart
                    and distance < shortestDistance
                    and (not radius or distance <= radius)
                    and isTargetVisible(origin, closestBodyPart)
                then
                    closestPlayer = player
                    closestPart = closestBodyPart
                    shortestDistance = distance
                end
            end
        end

        return closestPlayer, closestPart, viewportPoint, screenPoint
    end

    local function getPlayerHitAlongShot(origin, target, point)
        if not origin or not target then
            return nil, nil
        end

        local direction = target - origin
        if direction.Magnitude <= 0 then
            return nil, nil
        end

        tapRayParams.FilterDescendantsInstances = { LocalPlayer.Character }
        local result = Workspace:Raycast(origin, direction, tapRayParams)
        local hitPart = result and result.Instance
        if not hitPart or not hitPart:IsA("BasePart") then
            return nil, nil
        end

        local player = getPlayerFromPart(hitPart)
        if not player or not isShotCandidate(player) then
            return nil, nil
        end

        local targetPart = normalizeTargetPart(player, hitPart, point or worldPointToViewportPoint(hitPart.Position))
        if targetPart and isTargetOnScreen(targetPart) then
            return player, targetPart
        end

        return nil, nil
    end

    local function isLargePortionVisible(targetPlayer)
        if not targetPlayer or not targetPlayer.Character then
            return false
        end
        local visibleParts = 0
        local totalParts = 0
        local origin = getShotOrigin()
        if not origin then
            return false
        end

        for _, part in ipairs(targetPlayer.Character:GetChildren()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                totalParts += 1
                if isTargetVisible(origin, part) and isTargetOnScreen(part) then
                    visibleParts += 1
                end
            end
        end

        return totalParts > 0 and (visibleParts / totalParts >= 0.5)
    end

    local function applyHitChance(targetPosition, hitChance)
        hitChance = tonumber(hitChance) or 100
        if math.random(0, 100) <= hitChance then
            return targetPosition, true
        end
        local offset = Vector3.new(math.random(-5, 5), math.random(-5, 5), math.random(-5, 5))
        return targetPosition + offset, false
    end

    local function resolveShotAimPosition(
        origin,
        targetPlayer,
        targetPart,
        preferredAimPosition,
        aimPoint,
        useScreenPoint
    )
        local character = targetPlayer and targetPlayer.Character
        if
            preferredAimPosition
            and character
            and isCharacterPointVisible(origin, character, preferredAimPosition)
            and isWorldPointOnScreen(preferredAimPosition)
        then
            return preferredAimPosition
        end

        if targetPart and character and targetPart:IsDescendantOf(character) then
            local sampledAim = getClosestAimPositionOnPart(targetPart, aimPoint, useScreenPoint)
            if
                sampledAim
                and isCharacterPointVisible(origin, character, sampledAim)
                and isWorldPointOnScreen(sampledAim)
            then
                return sampledAim
            end

            if isTargetVisible(origin, targetPart) and isTargetOnScreen(targetPart) then
                return targetPart.Position
            end
        end

        return nil
    end

    local function preloadShootAnimation()
        cachedAnimationTrack = nil
        local character = LocalPlayer.Character
        local humanoid = safeGetHumanoid(character)
        local animFolder = ReplicatedStorage:FindFirstChild("Animations")
        local shootAnim = animFolder and animFolder:FindFirstChild("Shoot")
        if not humanoid or not shootAnim then
            return
        end

        local anim = Instance.new("Animation")
        anim.AnimationId = shootAnim.AnimationId
        cachedAnimationTrack = humanoid:LoadAnimation(anim)
    end

    local function stopShootAnimation()
        if cachedAnimationTrack then
            pcall(function()
                if cachedAnimationTrack.IsPlaying then
                    cachedAnimationTrack:Stop(0)
                end
            end)
        end
    end

    local function playShootAnimation()
        if not cachedAnimationTrack then
            preloadShootAnimation()
        end
        if cachedAnimationTrack then
            pcall(function()
                if cachedAnimationTrack.IsPlaying then
                    cachedAnimationTrack:Stop(0)
                end
                cachedAnimationTrack:Play()
            end)
        end
    end

    local function playFireSound()
        local fireSound = findToolAudio()
        if fireSound then
            pcall(function()
                fireSound:Play()
            end)
        end
    end

    local function createTracer(origin, target, muzzlePart, respectWorldHit)
        if not origin or not target then
            return
        end
        if respectWorldHit == nil then
            respectWorldHit = true
        end

        local visualOrigin, visualMuzzle = getTracerOrigin()
        local startPos = visualOrigin or origin
        muzzlePart = muzzlePart or visualMuzzle
        if muzzlePart then
            if muzzlePart:IsA("Attachment") then
                startPos = muzzlePart.WorldPosition
            elseif muzzlePart:IsA("BasePart") then
                startPos = muzzlePart.Position
            end
        end

        if respectWorldHit then
            local rayParams = RaycastParams.new()
            rayParams.FilterDescendantsInstances = { LocalPlayer.Character }
            rayParams.FilterType = Enum.RaycastFilterType.Blacklist
            local result = Workspace:Raycast(startPos, target - startPos, rayParams)
            if result then
                target = result.Position
            end
        end

        local distance = (startPos - target).Magnitude
        if distance <= 0.05 then
            return
        end

        local beamMade = false
        if BulletBeamTemplate then
            local ok = pcall(function()
                local startAttach = rememberInstance(Instance.new("Attachment"))
                startAttach.Parent = Workspace.Terrain
                startAttach.WorldPosition = startPos

                local endAttach = rememberInstance(Instance.new("Attachment"))
                endAttach.Parent = Workspace.Terrain
                endAttach.WorldPosition = target

                local beam = rememberInstance(BulletBeamTemplate:Clone())
                beam.Attachment0 = startAttach
                beam.Attachment1 = endAttach
                beam.Parent = startAttach

                local savedW0 = math.max(beam.Width0 or 0, 0.06)
                local savedW1 = math.max(beam.Width1 or 0, 0.06)
                beam.Width0 = 0
                beam.Width1 = 0
                local tweenIn = TweenService:Create(
                    beam,
                    TweenInfo.new(0.08, Enum.EasingStyle.Cubic, Enum.EasingDirection.In),
                    { Width0 = savedW0, Width1 = savedW1 }
                )
                tweenIn:Play()
                tweenIn.Completed:Connect(function()
                    pcall(function()
                        TweenService
                            :Create(
                                beam,
                                TweenInfo.new(0.08, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out),
                                { Width0 = 0, Width1 = 0 }
                            )
                            :Play()
                    end)
                end)
                Debris:AddItem(startAttach, 0.28)
                Debris:AddItem(endAttach, 0.28)
                Debris:AddItem(beam, 0.28)
            end)
            beamMade = ok
        end

        pcall(function()
            local tracer = rememberInstance(Instance.new("Part"))
            tracer.Size = Vector3.new(0.045, 0.045, distance)
            tracer.CFrame = CFrame.new(startPos, target) * CFrame.new(0, 0, -distance / 2)
            tracer.Anchored = true
            tracer.CanCollide = false
            tracer.CanTouch = false
            tracer.CanQuery = false
            tracer.CastShadow = false
            tracer.Color = beamMade and Color3.fromRGB(255, 235, 120) or Color3.fromRGB(255, 70, 70)
            tracer.Transparency = beamMade and 0.35 or 0.05
            tracer.Material = Enum.Material.Neon
            tracer.Parent = Workspace
            Debris:AddItem(tracer, 0.1)
        end)
    end

    local cooldownBarConnection = nil

    local function displayCooldownBar(duration)
        duration = tonumber(duration) or 2.5
        pcall(function()
            if cooldownBarConnection then
                cooldownBarConnection:Disconnect()
                cooldownBarConnection = nil
            end

            local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
            local backpack = playerGui and playerGui:FindFirstChild("Backpack")
            local container = backpack and backpack:FindFirstChild("Container")
            local buttonFrame = container and container:FindFirstChild("ButtonFrame")
            if not buttonFrame then
                return
            end

            local selectedButton = nil
            for _, button in ipairs(buttonFrame:GetChildren()) do
                if button.Name == "Button" then
                    local btnContainer = button:FindFirstChild("Container")
                    local number = btnContainer and btnContainer:FindFirstChild("Number")
                    if number and number:IsA("TextLabel") and number.Text == "2" then
                        selectedButton = button
                        break
                    end
                end
            end

            local cooldownbar = selectedButton and selectedButton:FindFirstChild("CooldownBar")
            local bar = cooldownbar and cooldownbar:FindFirstChild("Bar")
            local uiGradient = bar and bar:FindFirstChild("UIGradient")
            if not uiGradient then
                return
            end

            local startOffset = Vector2.new(-0.001, 0)
            local goalOffset = Vector2.new(-1, 0)
            local startTime = tick()
            uiGradient.Offset = startOffset
            cooldownbar.Visible = true

            cooldownBarConnection = RunService.RenderStepped:Connect(function()
                local alpha = math.clamp((tick() - startTime) / duration, 0, 1)
                uiGradient.Offset = startOffset:Lerp(goalOffset, alpha)
                if alpha >= 1 then
                    uiGradient.Offset = goalOffset
                    cooldownbar.Visible = false
                    if cooldownBarConnection then
                        cooldownBarConnection:Disconnect()
                        cooldownBarConnection = nil
                    end
                end
            end)
            rememberConnection(cooldownBarConnection)
        end)
    end

    local function setupCharacterTracking(character)
        if not character then
            return
        end
        rememberConnection(character.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then
                fireSoundCache[child] = nil
                lastToolEquipTime = tick()
                cachedToolValid = false
                cachedToolValidTime = 0
                task.delay(0.1, preloadShootAnimation)
            end
        end))
        rememberConnection(character.ChildRemoved:Connect(function(child)
            if child:IsA("Tool") then
                fireSoundCache[child] = nil
                stopShootAnimation()
                cachedToolValid = false
                cachedToolValidTime = 0
            end
        end))
        task.delay(0.5, preloadShootAnimation)
    end

    if LocalPlayer.Character then
        setupCharacterTracking(LocalPlayer.Character)
    end
    rememberConnection(LocalPlayer.CharacterAdded:Connect(function(character)
        lastToolEquipTime = tick()
        setupCharacterTracking(character)
    end))

    registerFeature("PC Aimbot", { "HasMouseMove" }, "PC", function()
        local mouseMoveRel = getFunction("mousemoverel")
        local AimbotConfig = {
            Enabled = false,
            AimKey = Enum.UserInputType.MouseButton2,
            FoVRadius = 100,
            Sensitivity = 10,
            AimPart = "Head",
            TeamCheck = true,
            WallCheck = true,
            DeathCheck = true,
        }
        local aiming = false
        local target = nil

        local function isVisible(targetPart)
            local origin = Camera.CFrame.Position
            local params = RaycastParams.new()
            params.FilterDescendantsInstances = { LocalPlayer.Character }
            params.FilterType = Enum.RaycastFilterType.Blacklist
            local result = Workspace:Raycast(origin, targetPart.Position - origin, params)
            return not result or result.Instance:IsDescendantOf(targetPart.Parent)
        end

        local function validCharacter(character)
            if not character or isCharacterHidden(character) then
                return false
            end
            local hum = safeGetHumanoid(character)
            return not AimbotConfig.DeathCheck or (hum and hum.Health > 0)
        end

        local function getClosestTarget()
            local closestTarget = nil
            local closestDistance = tonumber(AimbotConfig.FoVRadius) or 100
            local mousePosition = UserInputService:GetMouseLocation()

            for _, player in ipairs(TrackedPlayers) do
                local character = player.Character
                local part = character and character:FindFirstChild(AimbotConfig.AimPart)
                if player ~= LocalPlayer and part and validCharacter(character) then
                    if
                        (not AimbotConfig.TeamCheck or not isTeammateOf(player))
                        and (not AimbotConfig.WallCheck or isVisible(part))
                    then
                        local screenPoint, onScreen = Camera:WorldToViewportPoint(part.Position)
                        if onScreen then
                            local distance = (mousePosition - Vector2.new(screenPoint.X, screenPoint.Y)).Magnitude
                            if distance < closestDistance then
                                closestDistance = distance
                                closestTarget = player
                            end
                        end
                    end
                end
            end

            return closestTarget
        end

        local function aimAt(part)
            local screenPoint = Camera:WorldToViewportPoint(part.Position)
            local mousePosition = UserInputService:GetMouseLocation()
            mouseMoveRel(
                (screenPoint.X - mousePosition.X) / AimbotConfig.Sensitivity,
                (screenPoint.Y - mousePosition.Y) / AimbotConfig.Sensitivity
            )
        end

        rememberConnection(UserInputService.InputBegan:Connect(function(input)
            if inputMatches(input, AimbotConfig.AimKey) then
                aiming = true
            end
        end))
        rememberConnection(UserInputService.InputEnded:Connect(function(input)
            if inputMatches(input, AimbotConfig.AimKey) then
                aiming = false
                target = nil
            end
        end))
        rememberConnection(RunService.RenderStepped:Connect(function()
            if not AimbotConfig.Enabled or not aiming then
                return
            end
            if not target or not target.Character or not target.Character:FindFirstChild(AimbotConfig.AimPart) then
                target = getClosestTarget()
            end
            local part = target and target.Character and target.Character:FindFirstChild(AimbotConfig.AimPart)
            if part then
                aimAt(part)
            end
        end))

        Tabs.Aim:AddToggle("AimbotEnabled", { Title = "Enable Aimbot", Default = false }):OnChanged(function(value)
            AimbotConfig.Enabled = value
        end)
        Tabs.Aim:AddKeybind("AimKey", {
            Title = "Aim Key",
            Mode = "Hold",
            Default = "MouseButton2",
            Callback = function() end,
            ChangedCallback = function(newKey)
                AimbotConfig.AimKey = enumFromString(newKey)
            end,
        })
        Tabs.Aim
            :AddDropdown("AimPart", {
                Title = "Aim Part",
                Values = { "Head", "HumanoidRootPart" },
                Default = "Head",
            })
            :OnChanged(function(value)
                AimbotConfig.AimPart = value
            end)
        Tabs.Aim
            :AddSlider("AimbotFoVRadius", {
                Title = "Aimbot FoV Radius",
                Default = AimbotConfig.FoVRadius,
                Min = 50,
                Max = 500,
                Rounding = 1,
            })
            :OnChanged(function(value)
                AimbotConfig.FoVRadius = tonumber(value) or AimbotConfig.FoVRadius
            end)
        Tabs.Aim
            :AddSlider("AimbotSensitivity", {
                Title = "Aimbot Sensitivity",
                Default = AimbotConfig.Sensitivity,
                Min = 1,
                Max = 20,
                Rounding = 1,
            })
            :OnChanged(function(value)
                AimbotConfig.Sensitivity = tonumber(value) or AimbotConfig.Sensitivity
            end)
        Tabs.Aim:AddToggle("AimbotWallCheck", { Title = "Aimbot Wall Check", Default = true }):OnChanged(function(value)
            AimbotConfig.WallCheck = value
        end)
    end)

    registerFeature("PC Silent Aim Suite", {}, "PC", function()
        if not shootRemote then
            recordSkip("PC Silent Aim Suite", "ShootGun remote missing")
            return
        end

        local config = {
            cooldownTime = 2.5,
            silentAimHitChance = 100,
            autoShootHitChance = 100,
            autoShootReactionTime = 0,
            fovRadius = 100,
            toeShotRadius = 140,
        }

        local state = {
            silentAim = false,
            aimAssist = false,
            autoShoot = false,
            antiCrackshots = false,
            toeShots = false,
            showFOVCircle = false,
            lastShootTime = 0,
            shotLockUntil = 0,
            targetStartTime = nil,
            currentTarget = nil,
            fovCircle = nil,
        }
        local lastToolMonitor = 0
        local monitoredTool = nil
        local suppressConn = nil
        local suppressedTools = setmetatable({}, { __mode = "k" })

        local function canShootNow()
            local now = tick()
            return now >= state.shotLockUntil
                and (now - state.lastShootTime) >= getEffectiveGunCooldown(config.cooldownTime)
                and canUseScriptShot()
        end

        local function shootingCanShoot()
            return canShootNow() and isToolValid() and isToolFullyEquipped()
        end

        local function markShotFired()
            local now = tick()
            state.lastShootTime = now
            state.shotLockUntil = now + SHOT_LOCK_TIME
        end

        local function restoreDefaultToolFire()
            local hadSuppression = suppressConn ~= nil or monitoredTool ~= nil or next(suppressedTools) ~= nil

            if suppressConn then
                pcall(function()
                    suppressConn:Disconnect()
                end)
                suppressConn = nil
            end

            for tool in pairs(suppressedTools) do
                if tool and tool.Parent and isGunTool(tool) then
                    pcall(function()
                        tool.Enabled = true
                    end)
                end
                suppressedTools[tool] = nil
            end

            if hadSuppression then
                local tool = findEquippedTool()
                if tool and isGunTool(tool) then
                    pcall(function()
                        tool.Enabled = true
                    end)
                end
            end

            monitoredTool = nil
            cachedToolValid = false
            cachedToolValidTime = 0
        end

        local function disableDefaultToolFire()
            local tool = findEquippedTool()
            if not tool then
                return
            end

            if not isGunTool(tool) then
                return
            end
            suppressedTools[tool] = true

            if monitoredTool ~= tool then
                if suppressConn then
                    pcall(function()
                        suppressConn:Disconnect()
                    end)
                    suppressConn = nil
                end
                suppressConn = connectSafe(tool:GetPropertyChangedSignal("Enabled"), "PC Gun Suppression", function()
                    if (state.silentAim or state.autoShoot or state.aimAssist) and tool.Enabled then
                        pcall(function()
                            tool.Enabled = false
                        end)
                    end
                end)
            end

            local now = tick()
            if monitoredTool == tool and now - lastToolMonitor < 0.25 then
                if tool.Enabled then
                    pcall(function()
                        tool.Enabled = false
                    end)
                end
                return
            end
            monitoredTool = tool
            lastToolMonitor = now
            pcall(function()
                tool.Enabled = false
            end)
        end

        local function executeShot(targetPlayer, hitChance, aimPoint, preferredTargetPart, preferredAimPosition)
            if not shootRemote or not shootingCanShoot() then
                return false
            end
            local shotToken = reserveScriptShot(SHOT_LOCK_TIME)
            if not shotToken then
                return false
            end
            disableDefaultToolFire()

            local origin = getShotOrigin()
            if not origin then
                releaseScriptShot(shotToken, 0.05)
                return false
            end
            aimPoint = aimPoint or getMousePoint()

            if targetPlayer then
                local targetPart = preferredTargetPart or getClosestBodyPartToPoint(targetPlayer, aimPoint)
                if
                    not (targetPart and targetPlayer.Character and targetPart:IsDescendantOf(targetPlayer.Character))
                then
                    targetPart = getClosestBodyPartToPoint(targetPlayer, aimPoint)
                end
                local rayEnd =
                    resolveShotAimPosition(origin, targetPlayer, targetPart, preferredAimPosition, aimPoint, false)
                if targetPart and rayEnd then
                    local cooldown = getEffectiveGunCooldown(config.cooldownTime)
                    local finalRayEnd, shouldHit = applyHitChance(rayEnd, hitChance)
                    playShootAnimation()
                    playFireSound()
                    if shouldHit then
                        createTracer(origin, rayEnd, nil, false)
                        shootRemote:FireServer(origin, rayEnd, targetPart, rayEnd)
                    else
                        createTracer(origin, finalRayEnd, nil, true)
                    end
                    markShotFired()
                    commitScriptShot(shotToken, cooldown)
                    displayCooldownBar(cooldown)
                    return true
                end
            else
                local cooldown = getEffectiveGunCooldown(config.cooldownTime)
                local rayEnd = getPcMouseWorldPoint(5000)
                local finalRayEnd, shouldHit = applyHitChance(rayEnd, hitChance)
                playShootAnimation()
                playFireSound()
                if shouldHit then
                    createTracer(origin, rayEnd, nil, true)
                    shootRemote:FireServer(origin, rayEnd, nil, rayEnd)
                else
                    createTracer(origin, finalRayEnd, nil, true)
                end
                markShotFired()
                commitScriptShot(shotToken, cooldown)
                displayCooldownBar(cooldown)
                return true
            end

            releaseScriptShot(shotToken, 0.05)
            return false
        end

        local FOVCircle = {}
        function FOVCircle.create()
            if not Caps.HasDrawing then
                return
            end
            if state.fovCircle then
                removeDrawing(state.fovCircle)
            end
            state.fovCircle = rememberDrawing(Drawing.new("Circle"))
            state.fovCircle.Thickness = 2
            state.fovCircle.NumSides = 64
            state.fovCircle.Radius = config.fovRadius
            state.fovCircle.Filled = false
            state.fovCircle.Color = Color3.fromRGB(255, 255, 255)
            state.fovCircle.Transparency = 0.7
            state.fovCircle.Visible = state.showFOVCircle
        end
        function FOVCircle.update()
            if not Caps.HasDrawing then
                return
            end
            if not state.showFOVCircle then
                if state.fovCircle then
                    state.fovCircle.Visible = false
                end
                return
            end
            if not state.fovCircle then
                FOVCircle.create()
            end
            local circle = state.fovCircle
            if not circle then
                return
            end
            local mp = getMouseScreenPoint()
            circle.Position = Vector2.new(mp.X, mp.Y)
            circle.Radius = config.fovRadius
            circle.Visible = true
        end

        local lastAutoScan = 0
        local cachedAutoTarget = nil
        local cachedAutoPart = nil
        local cachedAutoAimPosition = nil
        local cachedMousePoint = nil

        local function resolvePcShotTarget()
            local screenPoint = getMouseScreenPoint()
            local viewportPoint = inputPointToViewport(screenPoint)
            if state.toeShots then
                local targetPlayer, targetPart, aimPosition, aimPoint =
                    getClosestToeShotTarget(viewportPoint, config.toeShotRadius)
                if targetPlayer then
                    return targetPlayer, targetPart, aimPoint or viewportPoint, screenPoint, aimPosition
                end
            end
            local targetPlayer, targetPart, aimPoint, rawScreenPoint = getClosestPlayerToPcMouse(config.fovRadius)
            return targetPlayer, targetPart, aimPoint, rawScreenPoint, nil
        end

        connectSafe(UserInputService.InputBegan, "PC Silent Aim Manual", function(input, gameProcessed)
            if gameProcessed or (not state.silentAim and not state.autoShoot) then
                return
            end
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                if isAbilityInputPoint(getMouseScreenPoint()) then
                    return
                end
                local manualHitChance = state.silentAim and config.silentAimHitChance or config.autoShootHitChance
                local targetPlayer, targetPart, aimPoint, _, aimPosition = resolvePcShotTarget()
                if
                    not executeShot(targetPlayer, manualHitChance, aimPoint, targetPart, aimPosition) and targetPlayer
                then
                    executeShot(nil, manualHitChance, aimPoint)
                end
            end
        end)

        connectSafe(UserInputService.InputBegan, "PC Aim Assist", function(input, gameProcessed)
            if gameProcessed or not state.aimAssist or input.KeyCode ~= Enum.KeyCode.E then
                return
            end
            if not shootingCanShoot() then
                return
            end
            local targetPlayer, targetPart, aimPoint, _, aimPosition = resolvePcShotTarget()
            if targetPlayer then
                executeShot(targetPlayer, 100, aimPoint, targetPart, aimPosition)
            end
        end)

        connectSafe(RunService.RenderStepped, "PC Silent Aim Render", function()
            if state.showFOVCircle then
                FOVCircle.update()
            end

            if not state.silentAim and not state.autoShoot then
                if not state.aimAssist then
                    restoreDefaultToolFire()
                end
                return
            end
            disableDefaultToolFire()
            if not isAnyToolEquipped() then
                stopShootAnimation()
            end

            if not state.autoShoot or not isToolValid() or not isToolFullyEquipped() or not canShootNow() then
                state.targetStartTime = nil
                state.currentTarget = nil
                cachedAutoPart = nil
                cachedAutoAimPosition = nil
                return
            end

            local now = tick()
            local mousePoint = getMousePoint()
            local reactionTime = tonumber(config.autoShootReactionTime) or 0
            local scanRate = (reactionTime <= 0.1 and not Caps.IsMobile) and 0 or Perf.AutoShootScanRate
            if scanRate <= 0 or now - lastAutoScan >= scanRate then
                local targetPlayer, targetPart, aimPoint, _, aimPosition = resolvePcShotTarget()
                cachedMousePoint = aimPoint or mousePoint
                cachedAutoTarget = targetPlayer
                cachedAutoPart = targetPart
                cachedAutoAimPosition = aimPosition
                lastAutoScan = now
            end

            local closestPlayer = cachedAutoTarget
            if not closestPlayer then
                state.targetStartTime = nil
                state.currentTarget = nil
                cachedAutoPart = nil
                cachedAutoAimPosition = nil
                return
            end

            local targetPart = cachedAutoPart
                or getClosestBodyPartToPoint(closestPlayer, cachedMousePoint or mousePoint)
            local shotOrigin = getShotOrigin()
            local aimPosition = cachedAutoAimPosition
            local resolvedAimPosition = shotOrigin
                and resolveShotAimPosition(
                    shotOrigin,
                    closestPlayer,
                    targetPart,
                    aimPosition,
                    cachedMousePoint or mousePoint,
                    false
                )
            if not (targetPart and shotOrigin and resolvedAimPosition) then
                state.targetStartTime = nil
                state.currentTarget = nil
                cachedAutoPart = nil
                cachedAutoAimPosition = nil
                return
            end
            aimPosition = resolvedAimPosition

            if reactionTime > 0 and state.antiCrackshots and not isLargePortionVisible(closestPlayer) then
                state.targetStartTime = nil
                state.currentTarget = nil
                return
            end

            if reactionTime > 0 then
                if state.currentTarget ~= closestPlayer then
                    state.currentTarget = closestPlayer
                    state.targetStartTime = tick()
                    return
                end
                if not state.targetStartTime or tick() - state.targetStartTime < reactionTime then
                    return
                end
            end

            executeShot(
                closestPlayer,
                config.autoShootHitChance,
                cachedMousePoint or mousePoint,
                targetPart,
                aimPosition
            )
            state.targetStartTime = nil
            state.currentTarget = nil
            cachedAutoPart = nil
            cachedAutoAimPosition = nil
        end)

        Tabs.Shots:AddKeybind("PerfectSilentAimKeybind", {
            Title = "Perfect Silent Aim",
            Mode = "Toggle",
            Default = "LeftAlt",
            Callback = function(value)
                state.silentAim = value
                if value then
                    disableDefaultToolFire()
                end
                if not value and not state.autoShoot and not state.aimAssist then
                    restoreDefaultToolFire()
                end
                Fluent:Notify({
                    Title = "Perfect Silent Aim",
                    Content = value and "Enabled" or "Disabled",
                    Duration = 3,
                })
            end,
        })
        Tabs.Shots:AddSlider("SilentAimHitChanceSlider", {
            Title = "Silent Aim Hit Chance",
            Default = config.silentAimHitChance,
            Min = 0,
            Max = 100,
            Rounding = 0,
            Callback = function(value)
                config.silentAimHitChance = tonumber(value) or config.silentAimHitChance
            end,
        })
        Tabs.Shots:AddKeybind("AutoshootKeybind", {
            Title = "Autoshoot",
            Mode = "Toggle",
            Default = "LeftControl",
            Callback = function(value)
                state.autoShoot = value
                state.targetStartTime = nil
                state.currentTarget = nil
                if value then
                    disableDefaultToolFire()
                end
                if not value and not state.silentAim and not state.aimAssist then
                    restoreDefaultToolFire()
                end
                Fluent:Notify({ Title = "Autoshoot", Content = value and "Enabled" or "Disabled", Duration = 3 })
            end,
        })
        Tabs.Shots:AddSlider("AutoShootHitChanceSlider", {
            Title = "Autoshoot Hit Chance",
            Default = config.autoShootHitChance,
            Min = 0,
            Max = 100,
            Rounding = 0,
            Callback = function(value)
                config.autoShootHitChance = tonumber(value) or config.autoShootHitChance
            end,
        })
        Tabs.Shots:AddSlider("AutoShootReactionTimeSlider", {
            Title = "Autoshoot Reaction Time (ms)",
            Default = config.autoShootReactionTime * 1000,
            Min = 0,
            Max = 1000,
            Rounding = 0,
            Callback = function(value)
                config.autoShootReactionTime = (tonumber(value) or 0) / 1000
                state.targetStartTime = nil
                state.currentTarget = nil
            end,
        })
        Tabs.Shots:AddToggle("AntiCrackshots", { Title = "Anti-Crackshots", Default = false }):OnChanged(function(value)
            state.antiCrackshots = value
        end)
        Tabs.Shots:AddToggle("ToeShotsToggle", { Title = "Toeshots", Default = false }):OnChanged(function(value)
            state.toeShots = value
            state.targetStartTime = nil
            state.currentTarget = nil
            cachedAutoTarget = nil
            cachedAutoPart = nil
            cachedAutoAimPosition = nil
        end)
        Tabs.Shots:AddSlider("ToeShotRadiusSlider", {
            Title = "Toeshots Radius",
            Default = config.toeShotRadius,
            Min = 20,
            Max = 500,
            Rounding = 0,
            Callback = function(value)
                config.toeShotRadius = tonumber(value) or config.toeShotRadius
            end,
        })
        Tabs.Shots:AddToggle("AimAssist", { Title = "Aim Assist [E]", Default = false }):OnChanged(function(value)
            state.aimAssist = value
            if not value and not state.silentAim and not state.autoShoot then
                restoreDefaultToolFire()
            end
            Fluent:Notify({ Title = "Aim Assist", Content = value and "Enabled" or "Disabled", Duration = 3 })
        end)
        Tabs.Shots:AddSlider("CooldownSlider", {
            Title = "Cooldown",
            Default = config.cooldownTime,
            Min = 0,
            Max = 5,
            Rounding = 1,
            Callback = function(value)
                config.cooldownTime = tonumber(value) or config.cooldownTime
            end,
        })

        if Caps.HasDrawing then
            FOVCircle.create()
            Tabs.Shots
                :AddToggle("ShowFOVCircle", { Title = "Show FOV Circle", Default = false })
                :OnChanged(function(value)
                    state.showFOVCircle = value
                    if state.fovCircle then
                        state.fovCircle.Visible = value
                    end
                end)
            Tabs.Shots:AddSlider("FOVRadius", {
                Title = "FOV Radius",
                Default = config.fovRadius,
                Min = 1,
                Max = 500,
                Rounding = 0,
                Callback = function(value)
                    config.fovRadius = tonumber(value) or config.fovRadius
                    if state.fovCircle then
                        state.fovCircle.Radius = config.fovRadius
                    end
                end,
            })
        else
            recordSkip("FOV Circle", "missing Drawing")
        end
    end)

    registerFeature("Mobile Silent Aim", { "HasTouch" }, "Mobile", function()
        if not shootRemote then
            recordSkip("Mobile Silent Aim", "ShootGun remote missing")
            return
        end

        local enabled = false
        local autoShoot = false
        local hitChance = 100
        local autoShootHitChance = 100
        local autoShootReactionTime = 0
        local cooldownTime = 2.5
        local isOnCooldown = false
        local lastShotTime = 0
        local closeToFinger = false
        local toeShots = false
        local fingerRadius = 200
        local toeShotRadius = 160
        local showRadius = false
        local touchStartTimes = {}
        local touchStartPoints = {}
        local touchMovedTooFar = {}
        local lastTouchPoint = nil
        local currentAutoTarget = nil
        local autoTargetStartTime = nil
        local lastAutoScan = 0
        local cachedAutoTarget = nil
        local cachedAutoPart = nil
        local cachedAutoAimPosition = nil
        local cachedAutoPoint = nil
        local monitoredTool = nil
        local lastToolMonitor = 0
        local suppressConn = nil
        local suppressedTools = setmetatable({}, { __mode = "k" })
        local radiusGui, radiusFrame
        local autoButtonGui, autoButton, autoButtonLabel, autoButtonStroke
        local autoButtonUnlocked = false

        local function mobileTapMoveLimit(position)
            local viewport = Camera.ViewportSize
            local point = position and toVector2(position) or nil
            if point and point.Y >= viewport.Y * 0.55 then
                return math.clamp(viewport.X * 0.010, 10, 18)
            end
            return math.clamp(viewport.X * 0.018, 18, 34)
        end

        local function clearTouchState(touch)
            touchStartTimes[touch] = nil
            touchStartPoints[touch] = nil
            touchMovedTooFar[touch] = nil
        end

        local function shootingCanShoot()
            return not isOnCooldown
                and (tick() - lastShotTime) >= SHOT_LOCK_TIME
                and isToolValid()
                and isToolFullyEquipped()
        end

        local function resetAutoShootTarget()
            currentAutoTarget = nil
            autoTargetStartTime = nil
            cachedAutoTarget = nil
            cachedAutoPart = nil
            cachedAutoAimPosition = nil
            cachedAutoPoint = nil
        end

        local function restoreDefaultToolFire()
            local hadSuppression = suppressConn ~= nil or monitoredTool ~= nil or next(suppressedTools) ~= nil

            if suppressConn then
                pcall(function()
                    suppressConn:Disconnect()
                end)
                suppressConn = nil
            end

            for tool in pairs(suppressedTools) do
                if tool and tool.Parent and isGunTool(tool) then
                    pcall(function()
                        tool.Enabled = true
                    end)
                end
                suppressedTools[tool] = nil
            end

            if hadSuppression then
                local tool = findEquippedTool()
                if tool and isGunTool(tool) then
                    pcall(function()
                        tool.Enabled = true
                    end)
                end
            end

            monitoredTool = nil
            cachedToolValid = false
            cachedToolValidTime = 0
        end

        local function updateAutoShootButton()
            if not autoButtonLabel or not autoButtonStroke or not autoButton then
                return
            end

            if autoShoot then
                autoButtonLabel.Text = "AUTOSHOOT: ON"
                autoButton.BackgroundColor3 = Color3.fromRGB(19, 82, 55)
                autoButtonStroke.Color = Color3.fromRGB(86, 255, 169)
            else
                autoButtonLabel.Text = "AUTOSHOOT: OFF"
                autoButton.BackgroundColor3 = Color3.fromRGB(28, 30, 42)
                autoButtonStroke.Color = Color3.fromRGB(145, 160, 205)
            end
        end

        local function setAutoShoot(value, notify)
            autoShoot = value == true
            resetAutoShootTarget()
            updateAutoShootButton()
            if not autoShoot and not enabled then
                restoreDefaultToolFire()
            end

            if notify then
                Fluent:Notify({
                    Title = "Autoshoot",
                    Content = autoShoot and "Enabled" or "Disabled",
                    Duration = 2,
                })
            end
        end

        local function beginCooldown()
            local effectiveCooldown = getEffectiveGunCooldown(cooldownTime)
            lastShotTime = tick()
            isOnCooldown = true
            displayCooldownBar(effectiveCooldown)
            task.delay(effectiveCooldown, function()
                isOnCooldown = false
            end)
        end

        local function disableDefaultToolFire()
            local tool = findEquippedTool()
            if not tool then
                return
            end

            if not isGunTool(tool) then
                return
            end
            suppressedTools[tool] = true

            if monitoredTool ~= tool then
                if suppressConn then
                    pcall(function()
                        suppressConn:Disconnect()
                    end)
                    suppressConn = nil
                end
                suppressConn = connectSafe(
                    tool:GetPropertyChangedSignal("Enabled"),
                    "Mobile Gun Suppression",
                    function()
                        if (enabled or autoShoot) and tool.Enabled then
                            pcall(function()
                                tool.Enabled = false
                            end)
                        end
                    end
                )
            end

            local now = tick()
            if monitoredTool == tool and now - lastToolMonitor < 0.25 then
                if tool.Enabled then
                    pcall(function()
                        tool.Enabled = false
                    end)
                end
                return
            end

            monitoredTool = tool
            lastToolMonitor = now

            pcall(function()
                tool.Enabled = false
            end)
        end

        local function setRadiusVisible(visible)
            if radiusFrame then
                radiusFrame.Visible = visible and showRadius and closeToFinger
            end
        end

        local function updateRadiusPosition(pos)
            if not radiusFrame then
                return
            end
            local guiPoint = viewportPointToScreen(pos)
            radiusFrame.Size = UDim2.fromOffset(fingerRadius * 2, fingerRadius * 2)
            radiusFrame.Position = UDim2.fromOffset(guiPoint.X - fingerRadius, guiPoint.Y - fingerRadius)
            setRadiusVisible(true)
        end

        local function ensureRadiusGui()
            if radiusGui then
                return
            end
            radiusGui = rememberInstance(Instance.new("ScreenGui"))
            radiusGui.Name = "ZephyrTouchRadius"
            radiusGui.ResetOnSpawn = false
            radiusGui.IgnoreGuiInset = true
            radiusGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

            radiusFrame = rememberInstance(Instance.new("Frame"))
            radiusFrame.Name = "Radius"
            radiusFrame.BackgroundTransparency = 1
            radiusFrame.Visible = false
            radiusFrame.Parent = radiusGui

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(1, 0)
            corner.Parent = radiusFrame

            local stroke = Instance.new("UIStroke")
            stroke.Color = Color3.fromRGB(255, 255, 255)
            stroke.Transparency = 0.35
            stroke.Thickness = 2
            stroke.Parent = radiusFrame
        end

        local function ensureAutoShootButton()
            if autoButtonGui then
                updateAutoShootButton()
                return
            end

            autoButtonGui = rememberInstance(Instance.new("ScreenGui"))
            autoButtonGui.Name = "ZephyrMobileAutoshootControl"
            autoButtonGui.ResetOnSpawn = false
            autoButtonGui.IgnoreGuiInset = true
            autoButtonGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            autoButtonGui.DisplayOrder = 999998
            autoButtonGui.Enabled = false
            autoButtonGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

            local autoButtonScale = getDeviceUiScale(0.76, 1)
            local autoButtonWidth = math.floor(172 * autoButtonScale + 0.5)
            local autoButtonHeight = math.floor(44 * autoButtonScale + 0.5)
            local autoButtonBottom = math.floor(154 * autoButtonScale + 0.5)

            autoButton = rememberInstance(Instance.new("TextButton"))
            autoButton.Name = "AutoshootButton"
            autoButton.Size = UDim2.fromOffset(autoButtonWidth, autoButtonHeight)
            autoButton.Position = UDim2.new(0.5, -(autoButtonWidth / 2), 1, -autoButtonBottom)
            autoButton.BackgroundColor3 = Color3.fromRGB(28, 30, 42)
            autoButton.BorderSizePixel = 0
            autoButton.AutoButtonColor = false
            autoButton.Text = ""
            autoButton.ZIndex = 30
            autoButton.Parent = autoButtonGui

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, math.floor(14 * autoButtonScale + 0.5))
            corner.Parent = autoButton

            autoButtonStroke = Instance.new("UIStroke")
            autoButtonStroke.Color = Color3.fromRGB(145, 160, 205)
            autoButtonStroke.Thickness = math.max(1, 1.5 * autoButtonScale)
            autoButtonStroke.Transparency = 0.05
            autoButtonStroke.Parent = autoButton

            local gradient = Instance.new("UIGradient")
            gradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(47, 52, 75)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 20, 30)),
            })
            gradient.Rotation = 90
            gradient.Parent = autoButton

            autoButtonLabel = Instance.new("TextLabel")
            autoButtonLabel.Name = "Label"
            autoButtonLabel.Size = UDim2.fromScale(1, 1)
            autoButtonLabel.BackgroundTransparency = 1
            autoButtonLabel.Text = "AUTOSHOOT: OFF"
            autoButtonLabel.TextColor3 = Color3.fromRGB(250, 252, 255)
            autoButtonLabel.TextSize = math.floor(15 * math.clamp(autoButtonScale, 0.84, 1) + 0.5)
            autoButtonLabel.Font = Enum.Font.GothamBold
            autoButtonLabel.ZIndex = 31
            autoButtonLabel.Parent = autoButton

            local scale = Instance.new("UIScale")
            scale.Scale = 1
            scale.Parent = autoButton

            local dragging = false
            local moved = false
            local dragStart = nil
            local dragInput = nil
            local dragOffset = nil
            local dragThreshold = math.floor(14 * autoButtonScale + 0.5)
            local lastButtonToggle = 0

            local function inputPoint(input)
                return viewportPointToScreen(Vector2.new(input.Position.X, input.Position.Y))
            end

            local function placeButtonAt(point, offset)
                local viewport = Camera.ViewportSize
                local size = autoButton.AbsoluteSize
                offset = offset or Vector2.new(size.X / 2, size.Y / 2)
                local x = math.clamp(point.X - offset.X, 8, viewport.X - size.X - 8)
                local y = math.clamp(point.Y - offset.Y, 8, viewport.Y - size.Y - 8)
                autoButton.Position = UDim2.fromOffset(x, y)
            end

            autoButton.InputBegan:Connect(function(input)
                if
                    input.UserInputType ~= Enum.UserInputType.Touch
                    and input.UserInputType ~= Enum.UserInputType.MouseButton1
                then
                    return
                end

                dragging = true
                moved = false
                dragInput = input
                dragStart = inputPoint(input)
                local buttonPos = autoButton.AbsolutePosition
                local buttonSize = autoButton.AbsoluteSize
                dragOffset = Vector2.new(
                    math.clamp(dragStart.X - buttonPos.X, 0, buttonSize.X),
                    math.clamp(dragStart.Y - buttonPos.Y, 0, buttonSize.Y)
                )
                TweenService
                    :Create(
                        scale,
                        TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                        { Scale = 0.96 }
                    )
                    :Play()

                local endConn
                endConn = input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                        dragInput = nil
                        dragStart = nil
                        dragOffset = nil
                        TweenService
                            :Create(
                                scale,
                                TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
                                { Scale = 1 }
                            )
                            :Play()
                        if endConn then
                            endConn:Disconnect()
                        end
                    end
                end)
                rememberConnection(endConn)
            end)

            connectSafe(UserInputService.InputChanged, "Mobile Autoshoot Button Drag", function(input)
                if not dragging or not dragStart then
                    return
                end
                if dragInput and dragInput.UserInputType == Enum.UserInputType.Touch and input ~= dragInput then
                    return
                end
                if
                    dragInput
                    and dragInput.UserInputType ~= Enum.UserInputType.Touch
                    and input.UserInputType ~= Enum.UserInputType.MouseMovement
                then
                    return
                end

                local currentPoint = inputPoint(input)
                if (currentPoint - dragStart).Magnitude > dragThreshold then
                    moved = true
                end
                if not moved then
                    return
                end

                placeButtonAt(currentPoint, dragOffset)
            end)

            autoButton.MouseButton1Click:Connect(function()
                if moved then
                    return
                end
                if tick() - lastButtonToggle < 0.18 then
                    return
                end
                lastButtonToggle = tick()
                setAutoShoot(not autoShoot, true)
            end)

            updateAutoShootButton()
        end

        local function isPointInsideAutoShootButton(position)
            if not autoButton or not autoButtonGui or not autoButtonGui.Enabled then
                return false
            end

            local point = viewportPointToScreen(position)
            local pos = autoButton.AbsolutePosition
            local size = autoButton.AbsoluteSize

            return point.X >= pos.X and point.X <= pos.X + size.X and point.Y >= pos.Y and point.Y <= pos.Y + size.Y
        end

        local function fireAtPlayer(targetPlayer, point, shotHitChance, preferredPart, preferredAimPosition)
            if not targetPlayer or not shootingCanShoot() then
                return false
            end
            disableDefaultToolFire()

            local origin = getShotOrigin()
            if not origin then
                return false
            end

            local targetPart = preferredPart
            if not (targetPart and targetPlayer.Character and targetPart:IsDescendantOf(targetPlayer.Character)) then
                targetPart = getClosestBodyPartToPoint(targetPlayer, point)
            end
            local rayEnd = resolveShotAimPosition(origin, targetPlayer, targetPart, preferredAimPosition, point, false)
            if not targetPart or not rayEnd then
                return false
            end

            local finalRayEnd, shouldHit = applyHitChance(rayEnd, shotHitChance or hitChance)

            playShootAnimation()
            playFireSound()

            if shouldHit then
                createTracer(origin, rayEnd, nil, false)
                shootRemote:FireServer(origin, rayEnd, targetPart, rayEnd)
            else
                createTracer(origin, finalRayEnd, nil, true)
                shootRemote:FireServer(origin, finalRayEnd, nil, finalRayEnd)
            end

            beginCooldown()
            return true
        end

        local function fireShotAtTouch(touchPoint)
            if not shootingCanShoot() then
                return
            end
            disableDefaultToolFire()

            local aimWorldPoint, aimViewportPoint = getManualAimWorldPoint(touchPoint, 5000)
            local usingFingerPoint = touchPoint and closeToFinger and not isLikelyMobileFireControl(touchPoint)
            local point = usingFingerPoint and toVector2(touchPoint)
                or aimViewportPoint
                or Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

            local targetPlayer, targetPart
            local toeAimPosition = nil
            if toeShots then
                targetPlayer, targetPart, toeAimPosition =
                    getClosestToeShotTarget(point, closeToFinger and fingerRadius or toeShotRadius)
            elseif closeToFinger then
                targetPlayer, targetPart = getClosestPlayerByBodyPartRadius(point, fingerRadius)
            else
                targetPlayer, targetPart = getClosestPlayerToPoint(point, nil)
            end
            if targetPlayer and fireAtPlayer(targetPlayer, point, hitChance, targetPart, toeAimPosition) then
                return
            end

            local origin = getShotOrigin()
            if not origin then
                return
            end

            local rayEnd = aimWorldPoint or getWorldPointFromViewport(point, 5000)
            local lineHitPlayer, lineHitPart = getPlayerHitAlongShot(origin, rayEnd, point)
            if
                lineHitPlayer
                and (not closeToFinger or isBodyPartInsidePointRadius(lineHitPart, point, fingerRadius))
                and fireAtPlayer(lineHitPlayer, point, hitChance, lineHitPart)
            then
                return
            end

            local finalRayEnd, shouldHit = applyHitChance(rayEnd, hitChance)

            playShootAnimation()
            playFireSound()

            if shouldHit then
                createTracer(origin, rayEnd, nil, true)
                shootRemote:FireServer(origin, rayEnd, nil, rayEnd)
            else
                createTracer(origin, finalRayEnd, nil, true)
                shootRemote:FireServer(origin, finalRayEnd, nil, finalRayEnd)
            end

            beginCooldown()
        end

        connectSafe(RunService.RenderStepped, "Mobile Silent Aim Render", function()
            if not enabled and not autoShoot then
                restoreDefaultToolFire()
                return
            end

            disableDefaultToolFire()
            if not isAnyToolEquipped() then
                stopShootAnimation()
            end

            if not autoShoot or not shootingCanShoot() then
                currentAutoTarget = nil
                autoTargetStartTime = nil
                cachedAutoPart = nil
                cachedAutoAimPosition = nil
                return
            end

            if closeToFinger and not lastTouchPoint then
                resetAutoShootTarget()
                setRadiusVisible(false)
                return
            end

            local point = closeToFinger and lastTouchPoint
                or Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
            local radius = closeToFinger and fingerRadius or nil
            local reactionTime = tonumber(autoShootReactionTime) or 0
            local now = tick()
            local scanRate = (reactionTime <= 0.1 and not Caps.IsMobile) and 0 or Perf.AutoShootScanRate

            if scanRate <= 0 or now - lastAutoScan >= scanRate then
                cachedAutoPoint = point
                cachedAutoAimPosition = nil
                if toeShots then
                    cachedAutoTarget, cachedAutoPart, cachedAutoAimPosition =
                        getClosestToeShotTarget(point, closeToFinger and fingerRadius or toeShotRadius)
                elseif closeToFinger then
                    cachedAutoTarget, cachedAutoPart = getClosestPlayerByBodyPartRadius(point, fingerRadius)
                else
                    cachedAutoTarget, cachedAutoPart = getClosestPlayerToPoint(point, radius)
                end
                lastAutoScan = now
            end

            local targetPlayer = cachedAutoTarget
            if not targetPlayer then
                currentAutoTarget = nil
                autoTargetStartTime = nil
                cachedAutoPart = nil
                cachedAutoAimPosition = nil
                return
            end

            local targetPart = cachedAutoPart
            local aimPosition = cachedAutoAimPosition
            if not (targetPart and targetPlayer.Character and targetPart:IsDescendantOf(targetPlayer.Character)) then
                if toeShots then
                    local toePlayer, toePart, toeAimPosition = getClosestToeShotTarget(
                        cachedAutoPoint or point,
                        closeToFinger and fingerRadius or toeShotRadius
                    )
                    if toePlayer == targetPlayer then
                        targetPart = toePart
                        aimPosition = toeAimPosition
                    end
                elseif closeToFinger then
                    local radiusPlayer, radiusPart =
                        getClosestPlayerByBodyPartRadius(cachedAutoPoint or point, fingerRadius)
                    if radiusPlayer == targetPlayer then
                        targetPart = radiusPart
                    end
                else
                    targetPart = getClosestBodyPartToPoint(targetPlayer, cachedAutoPoint or point)
                end
            end
            if not targetPart then
                currentAutoTarget = nil
                autoTargetStartTime = nil
                cachedAutoAimPosition = nil
                return
            end

            if reactionTime > 0 then
                if currentAutoTarget ~= targetPlayer then
                    currentAutoTarget = targetPlayer
                    autoTargetStartTime = tick()
                    return
                end

                if not autoTargetStartTime or tick() - autoTargetStartTime < reactionTime then
                    return
                end
            end

            if fireAtPlayer(targetPlayer, cachedAutoPoint or point, autoShootHitChance, targetPart, aimPosition) then
                currentAutoTarget = nil
                autoTargetStartTime = nil
                cachedAutoPart = nil
                cachedAutoAimPosition = nil
            end
        end)

        connectSafe(UserInputService.TouchStarted, "Mobile Touch Started", function(touch, processed)
            if isAbilityInputPoint(touch.Position) then
                clearTouchState(touch)
                return
            end
            if isPointInsideAutoShootButton(touch.Position) then
                return
            end
            if isLikelyMobileControlArea(touch.Position) then
                return
            end
            local fireControlTouch = isLikelyMobileFireControl(touch.Position)
            if processed and not fireControlTouch then
                return
            end
            touchStartTimes[touch] = tick()
            touchStartPoints[touch] = toVector2(touch.Position)
            touchMovedTooFar[touch] = false
            if fireControlTouch then
                return
            end
            lastTouchPoint = toVector2(touch.Position)
            if showRadius and closeToFinger then
                ensureRadiusGui()
                updateRadiusPosition(touch.Position)
            end
        end)

        connectSafe(UserInputService.TouchMoved, "Mobile Touch Moved", function(touch)
            if isAbilityInputPoint(touch.Position) then
                clearTouchState(touch)
                lastTouchPoint = nil
                setRadiusVisible(false)
                return
            end
            if isPointInsideAutoShootButton(touch.Position) then
                return
            end
            if not touchStartTimes[touch] then
                return
            end

            if isLikelyMobileControlArea(touch.Position) then
                touchMovedTooFar[touch] = true
                lastTouchPoint = nil
                setRadiusVisible(false)
                return
            end

            local fireControlTouch = isLikelyMobileFireControl(touch.Position)

            local startPoint = touchStartPoints[touch]
            local currentPoint = toVector2(touch.Position)
            if startPoint and (currentPoint - startPoint).Magnitude > mobileTapMoveLimit(currentPoint) then
                touchMovedTooFar[touch] = true
                if autoShoot and closeToFinger and not fireControlTouch then
                    lastTouchPoint = currentPoint
                    if showRadius then
                        ensureRadiusGui()
                        updateRadiusPosition(touch.Position)
                    end
                    return
                end
                lastTouchPoint = nil
                setRadiusVisible(false)
                return
            end

            if fireControlTouch then
                return
            end

            lastTouchPoint = toVector2(touch.Position)
            if showRadius and closeToFinger then
                ensureRadiusGui()
                updateRadiusPosition(touch.Position)
            end
        end)

        connectSafe(UserInputService.TouchEnded, "Mobile Touch Ended", function(touch, processed)
            setRadiusVisible(false)
            lastTouchPoint = nil
            if isAbilityInputPoint(touch.Position) then
                clearTouchState(touch)
                return
            end
            if isPointInsideAutoShootButton(touch.Position) then
                clearTouchState(touch)
                return
            end
            if isLikelyMobileControlArea(touch.Position) then
                clearTouchState(touch)
                return
            end
            local fireControlTouch = isLikelyMobileFireControl(touch.Position)
            if processed and not fireControlTouch then
                clearTouchState(touch)
                return
            end
            if not enabled and not autoShoot then
                clearTouchState(touch)
                return
            end
            local touchStartedAt = touchStartTimes[touch]
            local touchStartedAtPoint = touchStartPoints[touch]
            local movedTooFar = touchMovedTooFar[touch]
            clearTouchState(touch)
            if not touchStartedAt and not fireControlTouch then
                return
            end
            if movedTooFar then
                return
            end
            if
                touchStartedAtPoint
                and (toVector2(touch.Position) - touchStartedAtPoint).Magnitude > mobileTapMoveLimit(touch.Position)
            then
                return
            end
            local touchDuration = tick() - (touchStartedAt or tick())
            if touchDuration > 0.2 and not fireControlTouch then
                return
            end
            fireShotAtTouch(touch.Position)
        end)

        Tabs.Shots
            :AddToggle("MobileSilentAimToggle", { Title = "Tap Aim Assist", Default = false })
            :OnChanged(function(value)
                enabled = value
                if value then
                    disableDefaultToolFire()
                elseif not autoShoot then
                    restoreDefaultToolFire()
                end
            end)
        Tabs.Shots:AddSlider("MobileSilentAimHitChance", {
            Title = "Tap Accuracy",
            Default = hitChance,
            Min = 0,
            Max = 100,
            Rounding = 0,
            Callback = function(value)
                hitChance = tonumber(value) or hitChance
            end,
        })
        Tabs.Shots
            :AddToggle("MobileAutoshootToggle", { Title = "Show Autoshoot Button", Default = false })
            :OnChanged(function(value)
                autoButtonUnlocked = value == true
                if autoButtonUnlocked then
                    ensureAutoShootButton()
                end
                if autoButtonGui then
                    autoButtonGui.Enabled = autoButtonUnlocked
                end
                setAutoShoot(value, true)
                if value then
                    disableDefaultToolFire()
                end
            end)
        Tabs.Shots:AddSlider("MobileAutoshootHitChance", {
            Title = "Autoshoot Accuracy",
            Default = autoShootHitChance,
            Min = 0,
            Max = 100,
            Rounding = 0,
            Callback = function(value)
                autoShootHitChance = tonumber(value) or autoShootHitChance
            end,
        })
        Tabs.Shots:AddSlider("MobileAutoshootReactionTime", {
            Title = "Autoshoot Delay (ms)",
            Default = autoShootReactionTime * 1000,
            Min = 0,
            Max = 1000,
            Rounding = 0,
            Callback = function(value)
                autoShootReactionTime = (tonumber(value) or 0) / 1000
                currentAutoTarget = nil
                autoTargetStartTime = nil
            end,
        })
        Tabs.Shots
            :AddToggle("CloseToFingerToggle", { Title = "Use Finger Zone", Default = false })
            :OnChanged(function(value)
                closeToFinger = value
                resetAutoShootTarget()
                if not value then
                    setRadiusVisible(false)
                end
            end)
        Tabs.Shots:AddToggle("MobileToeShotsToggle", { Title = "Toeshots", Default = false }):OnChanged(function(value)
            toeShots = value
            resetAutoShootTarget()
        end)
        Tabs.Shots:AddSlider("FingerRadiusSlider", {
            Title = "Finger Zone Size",
            Default = fingerRadius,
            Min = 1,
            Max = 500,
            Rounding = 0,
            Callback = function(value)
                fingerRadius = tonumber(value) or fingerRadius
                if radiusFrame and lastTouchPoint then
                    updateRadiusPosition(lastTouchPoint)
                end
            end,
        })
        Tabs.Shots:AddSlider("MobileToeShotRadiusSlider", {
            Title = "Toeshots Radius",
            Default = toeShotRadius,
            Min = 20,
            Max = 500,
            Rounding = 0,
            Callback = function(value)
                toeShotRadius = tonumber(value) or toeShotRadius
                resetAutoShootTarget()
            end,
        })
        Tabs.Shots
            :AddToggle("RadiusVisualizerToggle", { Title = "Show Finger Zone", Default = false })
            :OnChanged(function(value)
                showRadius = value
                if value then
                    ensureRadiusGui()
                else
                    setRadiusVisible(false)
                end
            end)
        Tabs.Shots:AddSlider("MobileShotCooldown", {
            Title = "Shot Cooldown (s)",
            Default = cooldownTime,
            Min = 0,
            Max = 5,
            Rounding = 1,
            Callback = function(value)
                cooldownTime = tonumber(value) or cooldownTime
            end,
        })
    end)

    registerFeature("Mobile Triggerbot", { "HasTouch" }, "Mobile", function()
        if not shootRemote then
            recordSkip("Mobile Triggerbot", "ShootGun remote missing")
            return
        end

        local modules = ReplicatedStorage:FindFirstChild("Modules")
        local weaponRaycast
        local collisionGroups
        pcall(function()
            weaponRaycast = modules and require(modules:WaitForChild("WeaponRaycast", 3)) or nil
            collisionGroups = modules and require(modules:WaitForChild("CollisionGroups", 3)) or nil
        end)

        local enabled = false
        local delay = 0
        local smartAim = true
        local lastTouchPoint = nil
        local activeTouch = nil
        local lastScan = 0
        local lastShot = 0
        local pendingPart = nil
        local pendingSince = 0

        local function equippedGun()
            local tool = findEquippedTool()
            if tool and isGunTool(tool) and isToolFullyEquipped() then
                return tool
            end
            return nil
        end

        local function raycastLikeGame(origin, target, collisionGroup)
            if not origin or not target then
                return nil
            end
            if weaponRaycast then
                local ok, result = pcall(function()
                    return weaponRaycast(origin, target, nil, collisionGroup)
                end)
                if ok then
                    return result
                end
            end
            local direction = target - origin
            if direction.Magnitude <= 0 then
                return nil
            end
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = { LocalPlayer.Character }
            if collisionGroup then
                pcall(function()
                    params.CollisionGroup = collisionGroup
                end)
            end
            return Workspace:Raycast(origin, direction, params)
        end

        local function screenPointToWorld(point)
            if weaponRaycast and weaponRaycast.convertScreenPointToVector3 then
                local ok, result = pcall(weaponRaycast.convertScreenPointToVector3, point)
                if ok and result then
                    return result
                end
            end
            local camera = Workspace.CurrentCamera
            if not camera then
                return nil
            end
            local ray = camera:ViewportPointToRay(point.X, point.Y, 0)
            local target = ray.Origin + ray.Direction * 1000
            local group = collisionGroups and collisionGroups.SCREEN_RAYCAST or "ScreenRaycast"
            local hit = raycastLikeGame(ray.Origin, target, group)
            return hit and (hit.Position + ray.Direction * 10) or target
        end

        local function buildMobileHit()
            local tool = equippedGun()
            local camera = Workspace.CurrentCamera
            local origin = getShotOrigin()
            if not tool or not camera or not origin or not activeTouch or not lastTouchPoint then
                return nil
            end

            local point = inputPointToViewport(lastTouchPoint)
            local direction = screenPointToWorld(point)
            if not direction then
                return nil
            end
            local screenGroup = collisionGroups and collisionGroups.SCREEN_RAYCAST or "ScreenRaycast"
            local screenHit = raycastLikeGame(camera.CFrame.Position, direction, screenGroup)
            local rayTarget = screenHit and screenHit.Position or direction
            local shotHit = raycastLikeGame(origin, rayTarget, nil)
            local finalHit = shotHit or screenHit
            if not finalHit then
                return nil
            end

            local player = getPlayerFromPart(finalHit.Instance)
            if not player or not isShotCandidate(player) then
                return nil
            end

            local finalPart = finalHit.Instance
            local finalPosition = finalHit.Position
            local finalDirection = direction
            if smartAim then
                local targetPart = normalizeTargetPart(player, finalHit.Instance, point)
                    or getClosestBodyPartToPoint(player, point)
                local aimPosition = resolveShotAimPosition(origin, player, targetPart, nil, point, false)
                if targetPart and aimPosition then
                    finalPart = targetPart
                    finalPosition = aimPosition
                    finalDirection = aimPosition
                end
            end

            return {
                tool = tool,
                part = finalPart,
                position = finalPosition,
                direction = finalDirection,
                origin = origin,
                cooldown = math.max(tonumber(tool:GetAttribute("Cooldown")) or 2.5, SHOT_LOCK_TIME),
            }
        end

        rememberConnection(UserInputService.TouchStarted:Connect(function(input, processed)
            if not processed and not isAbilityInputPoint(inputPointToViewport(input.Position)) then
                activeTouch = input
                lastTouchPoint = toVector2(input.Position)
            end
        end))
        rememberConnection(UserInputService.TouchMoved:Connect(function(input, processed)
            if
                input == activeTouch
                and not processed
                and not isAbilityInputPoint(inputPointToViewport(input.Position))
            then
                lastTouchPoint = toVector2(input.Position)
            end
        end))
        rememberConnection(UserInputService.TouchEnded:Connect(function(input)
            if input == activeTouch then
                activeTouch = nil
                lastTouchPoint = nil
                pendingPart = nil
            end
        end))

        connectSafe(RunService.RenderStepped, "Mobile Game Raycast Triggerbot", function()
            if not enabled then
                pendingPart = nil
                return
            end
            local now = tick()
            if now - lastScan < Perf.TriggerbotRate then
                return
            end
            lastScan = now

            local hit = buildMobileHit()
            if not hit then
                pendingPart = nil
                return
            end
            if pendingPart ~= hit.part then
                pendingPart = hit.part
                pendingSince = now
            end
            if now - pendingSince < delay or now - lastShot < hit.cooldown then
                return
            end

            local token = reserveScriptShot(hit.cooldown)
            if not token then
                return
            end
            playShootAnimation()
            playFireSound()
            createTracer(hit.origin, hit.position, nil, false)
            shootRemote:FireServer(hit.origin, hit.direction, hit.part, hit.position)
            displayCooldownBar(hit.cooldown)
            commitScriptShot(token, hit.cooldown)
            lastShot = now
            pendingPart = nil
        end)

        Tabs.Trigger
            :AddToggle("MobileTriggerbotToggle", {
                Title = "Mobile Triggerbot [Finger]",
                Default = false,
            })
            :OnChanged(function(value)
                enabled = value
                pendingPart = nil
            end)
        Tabs.Trigger
            :AddToggle("MobileTriggerbotSmartAim", {
                Title = "Smart Trigger Aim",
                Default = true,
            })
            :OnChanged(function(value)
                smartAim = value == true
                pendingPart = nil
            end)
        Tabs.Trigger:AddSlider("MobileTriggerbotDelay", {
            Title = "Trigger Delay (ms)",
            Default = 0,
            Min = 0,
            Max = 500,
            Rounding = 0,
            Callback = function(value)
                delay = math.max(0, (tonumber(value) or 0) / 1000)
                pendingPart = nil
            end,
        })
    end)

    registerFeature("Knife Silent Aim", {}, nil, function()
        local modules = ReplicatedStorage:FindFirstChild("Modules")
        local weaponRaycast
        pcall(function()
            weaponRaycast = modules and require(modules:WaitForChild("WeaponRaycast", 3)) or nil
        end)
        if type(weaponRaycast) ~= "table" or type(weaponRaycast.convertScreenPointToVector3) ~= "function" then
            recordSkip("Knife Silent Aim", "WeaponRaycast module unavailable")
            return
        end

        local enabled = false
        local mode = "Prediction"
        local targetMode = "Finger"
        local radius = 180
        local predictionAmount = 1
        local autoPrediction = true
        local wallCheck = false
        local currentTarget = nil
        local targetUntil = 0
        local convertTarget = weaponRaycast.convertScreenPointToVector3
        local predictionSliderControl = nil

        local function knifeEquipped()
            local tool = findEquippedTool()
            return tool and not isGunTool(tool) and tool:GetAttribute("ThrowSpeed") ~= nil
        end

        local function getKnifeOrigin()
            local character = LocalPlayer.Character
            local head = character and character:FindFirstChild("Head")
            if head then
                return (head.CFrame * CFrame.new(0, head.Size.Y / 2, head.Size.Z / 2)).Position
            end
            return character and character:FindFirstChild("HumanoidRootPart") and character.HumanoidRootPart.Position
                or nil
        end

        local function isKnifeAimVisible(character, worldPoint)
            if not wallCheck then
                return true
            end
            if not character or not worldPoint then
                return false
            end

            local origin = getKnifeOrigin()
            if not origin then
                local camera = Workspace.CurrentCamera
                origin = camera and camera.CFrame.Position or nil
            end
            if not origin then
                return false
            end

            return isCharacterPointVisible(origin, character, worldPoint)
        end

        local function closestKnifePart(tapPosition)
            local camera = Workspace.CurrentCamera
            if not camera then
                return nil
            end
            local anchor = inputPointToViewport(tapPosition)
            local closestPart = nil
            local minDistance = targetMode == "Nearest" and math.huge or radius
            local localRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

            for _, player in ipairs(TrackedPlayers) do
                if isShotCandidate(player) then
                    local character = player.Character
                    local part
                    local distance
                    if targetMode == "Nearest" and localRoot then
                        local root = character and character:FindFirstChild("HumanoidRootPart")
                        part = character
                            and (
                                character:FindFirstChild("UpperTorso")
                                or character:FindFirstChild("Torso")
                                or root
                                or character:FindFirstChild("Head")
                            )
                        if part then
                            distance = (part.Position - localRoot.Position).Magnitude
                        end
                    else
                        part, distance = getClosestBodyPartToPoint(player, anchor)
                    end
                    if part then
                        if distance and distance <= minDistance and isKnifeAimVisible(character, part.Position) then
                            minDistance = distance
                            closestPart = part
                        end
                    end
                end
            end
            return closestPart
        end

        local function getPredictedPosition(part)
            local origin = getKnifeOrigin()
            local tool = findEquippedTool()
            if not origin or not tool or not part then
                return part and part.Position or nil
            end

            local speed = tonumber(tool:GetAttribute("ThrowSpeed")) or 100
            speed = math.max(speed, 1)
            local ping = 0
            pcall(function()
                ping = LocalPlayer:GetNetworkPing()
            end)
            ping = math.clamp(tonumber(ping) or 0, 0, 0.35)
            local travelTime = (part.Position - origin).Magnitude / speed + ping
            if autoPrediction then
                travelTime += math.clamp(ping * 0.35, 0, 0.08)
            end
            travelTime = math.clamp(travelTime, 0, 3)
            local velocity = part.AssemblyLinearVelocity
            if typeof(velocity) ~= "Vector3" then
                velocity = Vector3.zero
            end
            local root = part.Parent and part.Parent:FindFirstChild("HumanoidRootPart")
            if root and root:IsA("BasePart") and velocity.Magnitude < 1 then
                velocity = root.AssemblyLinearVelocity
            end
            return part.Position + velocity * travelTime * predictionAmount
        end

        local silentAimConvert
        silentAimConvert = function(screenPoint, distance)
            if enabled and knifeEquipped() then
                currentTarget = closestKnifePart(screenPoint)
                targetUntil = tick() + 3
                if mode == "Prediction" and currentTarget then
                    local predicted = getPredictedPosition(currentTarget)
                    local character = currentTarget.Parent
                    if predicted and isKnifeAimVisible(character, predicted) then
                        return predicted
                    end
                end
            end
            return convertTarget(screenPoint, distance)
        end

        local function refreshConvertOverride()
            if enabled and mode == "Prediction" then
                if weaponRaycast.convertScreenPointToVector3 ~= silentAimConvert then
                    if type(weaponRaycast.convertScreenPointToVector3) == "function" then
                        convertTarget = weaponRaycast.convertScreenPointToVector3
                    end
                    weaponRaycast.convertScreenPointToVector3 = silentAimConvert
                end
            elseif weaponRaycast.convertScreenPointToVector3 == silentAimConvert then
                weaponRaycast.convertScreenPointToVector3 = convertTarget
            end
        end

        local function captureKnifeTarget(position)
            if enabled and knifeEquipped() and position then
                currentTarget = closestKnifePart(position)
                targetUntil = tick() + 3
            end
        end

        rememberConnection(UserInputService.TouchStarted:Connect(function(input, processed)
            if not processed then
                captureKnifeTarget(input.Position)
            end
        end))
        rememberConnection(UserInputService.InputBegan:Connect(function(input, processed)
            if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
                captureKnifeTarget(UserInputService:GetMouseLocation())
            end
        end))
        rememberConnection(UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                captureKnifeTarget(UserInputService:GetMouseLocation())
            end
        end))

        connectSafe(RunService.RenderStepped, "Knife Silent Aim Hook Watchdog", function()
            if enabled then
                refreshConvertOverride()
            elseif weaponRaycast.convertScreenPointToVector3 == silentAimConvert then
                weaponRaycast.convertScreenPointToVector3 = convertTarget
            end
            if currentTarget and (not currentTarget.Parent or tick() > targetUntil) then
                currentTarget = nil
            end
        end)

        rememberCleanup(function()
            enabled = false
            currentTarget = nil
            if weaponRaycast.convertScreenPointToVector3 == silentAimConvert then
                weaponRaycast.convertScreenPointToVector3 = convertTarget
            end
        end)

        Tabs.Shots
            :AddToggle("KnifeSilentAimToggle", {
                Title = "Knife Silent Aim",
                Default = false,
            })
            :OnChanged(function(value)
                enabled = value
                currentTarget = nil
                refreshConvertOverride()
            end)
        Tabs.Shots:AddDropdown("KnifeSilentAimMode", {
            Title = "Mode",
            Values = { "Prediction" },
            Default = "Prediction",
            Callback = function(value)
                mode = value
                currentTarget = nil
                refreshConvertOverride()
            end,
        })
        Tabs.Shots:AddDropdown("KnifeSilentAimTarget", {
            Title = "Target",
            Values = { "Finger", "Nearest" },
            Default = "Finger",
            Callback = function(value)
                targetMode = value
                currentTarget = nil
            end,
        })
        Tabs.Shots
            :AddToggle("KnifeSilentAimWallCheck", {
                Title = "Knife Wall Check",
                Default = false,
            })
            :OnChanged(function(value)
                wallCheck = value == true
                currentTarget = nil
            end)
        Tabs.Shots
            :AddToggle("KnifeSilentAimAutoPrediction", {
                Title = "Auto Knife Prediction",
                Default = true,
            })
            :OnChanged(function(value)
                autoPrediction = value == true
                currentTarget = nil
            end)
        Tabs.Shots:AddSlider("KnifeSilentAimRadius", {
            Title = "Radius",
            Default = radius,
            Min = 20,
            Max = 500,
            Rounding = 0,
            Callback = function(value)
                radius = tonumber(value) or radius
            end,
        })
        predictionSliderControl = Tabs.Shots:AddSlider("KnifeSilentAimPrediction", {
            Title = "Prediction",
            Default = 100,
            Min = 0,
            Max = 200,
            Rounding = 0,
            Callback = function(value)
                predictionAmount = math.max(0, (tonumber(value) or 100) / 100)
            end,
        })
        Tabs.Shots:AddButton({
            Title = "Calibrate Knife Prediction",
            Description = "Sets prediction from current ping.",
            Callback = function()
                local ping = 0
                pcall(function()
                    ping = LocalPlayer:GetNetworkPing()
                end)
                ping = math.clamp(tonumber(ping) or 0, 0, 0.35)
                local tuned = math.clamp(math.floor(100 + ping * 180 + 0.5), 80, 165)
                predictionAmount = tuned / 100
                if predictionSliderControl and type(predictionSliderControl.SetValue) == "function" then
                    predictionSliderControl:SetValue(tuned)
                end
                Fluent:Notify({
                    Title = "Knife Prediction",
                    Content = "Calibrated to " .. tostring(tuned) .. "% for current ping.",
                    Duration = 3,
                })
            end,
        })
    end)

    registerFeature("PC Triggerbots", {}, "PC", function()
        if not shootRemote then
            recordSkip("PC Triggerbot", "ShootGun remote missing")
            return
        end

        local weaponRaycast = nil
        local collisionGroups = nil
        pcall(function()
            local modules = ReplicatedStorage:FindFirstChild("Modules")
            weaponRaycast = modules and require(modules:WaitForChild("WeaponRaycast", 3)) or nil
            collisionGroups = modules and require(modules:WaitForChild("CollisionGroups", 3)) or nil
        end)

        local triggerSettings = {
            enabled = false,
            keybindEnabled = false,
            keybind = Enum.KeyCode.T,
            mode = "Hold",
            delay = 0,
            smartAim = false,
        }
        local DEFAULT_TRIGGER_COOLDOWN = 2.5
        local keybindActive = false
        local lastTriggerScan = 0
        local lastTriggerShot = 0
        local pendingPlayer = nil
        local pendingInstance = nil
        local pendingStartedAt = 0
        local pendingShotToken = nil
        local triggerMonitoredTool = nil
        local triggerSuppressConn = nil
        local lastTriggerToolMonitor = 0
        local triggerSuppressedTools = setmetatable({}, { __mode = "k" })

        local function activeTriggerbot()
            return triggerSettings.enabled or (triggerSettings.keybindEnabled and keybindActive)
        end

        local function getEquippedGun()
            local tool = findEquippedTool()
            if tool and isGunTool(tool) and isToolFullyEquipped() then
                return tool
            end
            return nil
        end

        local function restoreTriggerToolFire()
            local hadSuppression = triggerSuppressConn ~= nil
                or triggerMonitoredTool ~= nil
                or next(triggerSuppressedTools) ~= nil

            if triggerSuppressConn then
                pcall(function()
                    triggerSuppressConn:Disconnect()
                end)
                triggerSuppressConn = nil
            end

            for tool in pairs(triggerSuppressedTools) do
                if tool and tool.Parent and isGunTool(tool) then
                    pcall(function()
                        tool.Enabled = true
                    end)
                end
                triggerSuppressedTools[tool] = nil
            end

            if hadSuppression then
                local tool = findEquippedTool()
                if tool and isGunTool(tool) then
                    pcall(function()
                        tool.Enabled = true
                    end)
                end
            end

            triggerMonitoredTool = nil
            cachedToolValid = false
            cachedToolValidTime = 0
        end

        local function disableTriggerDefaultToolFire()
            local tool = findEquippedTool()
            if not tool or not isGunTool(tool) then
                return
            end

            triggerSuppressedTools[tool] = true

            if triggerMonitoredTool ~= tool then
                if triggerSuppressConn then
                    pcall(function()
                        triggerSuppressConn:Disconnect()
                    end)
                    triggerSuppressConn = nil
                end
                triggerSuppressConn = connectSafe(
                    tool:GetPropertyChangedSignal("Enabled"),
                    "PC Triggerbot Gun Suppression",
                    function()
                        if activeTriggerbot() and tool.Enabled then
                            pcall(function()
                                tool.Enabled = false
                            end)
                        end
                    end
                )
            end

            local now = tick()
            if triggerMonitoredTool == tool and now - lastTriggerToolMonitor < 0.25 then
                if tool.Enabled then
                    pcall(function()
                        tool.Enabled = false
                    end)
                end
                return
            end

            triggerMonitoredTool = tool
            lastTriggerToolMonitor = now
            pcall(function()
                tool.Enabled = false
            end)
        end

        local function weaponRaycastLikeGame(origin, target, collisionGroup)
            if not origin or not target then
                return nil
            end
            if weaponRaycast then
                local ok, result = pcall(function()
                    return weaponRaycast(origin, target, nil, collisionGroup)
                end)
                if ok then
                    return result
                end
            end

            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Blacklist
            params.FilterDescendantsInstances = { LocalPlayer.Character }
            if collisionGroup then
                pcall(function()
                    params.CollisionGroup = collisionGroup
                end)
            end
            local direction = target - origin
            if direction.Magnitude <= 0 then
                return nil
            end
            return Workspace:Raycast(origin, direction, params)
        end

        local function convertTriggerScreenPoint(screenPoint)
            if weaponRaycast and weaponRaycast.convertScreenPointToVector3 then
                local ok, target = pcall(function()
                    return weaponRaycast.convertScreenPointToVector3(screenPoint)
                end)
                if ok and target then
                    return target
                end
            end

            local ray = Camera:ViewportPointToRay(screenPoint.X, screenPoint.Y, 0)
            local distance = 1000
            local screenTarget = ray.Origin + ray.Direction * distance
            local screenGroup = collisionGroups and collisionGroups.SCREEN_RAYCAST or "ScreenRaycast"
            local screenHit = weaponRaycastLikeGame(ray.Origin, screenTarget, screenGroup)
            return screenHit and (screenHit.Position + ray.Direction * 10) or screenTarget
        end

        local function getTriggerHit()
            if isAbilityInputPoint(getMouseScreenPoint()) then
                return nil
            end
            local tool = getEquippedGun()
            if not tool then
                return nil
            end

            local origin = getShotOrigin()
            local camera = Workspace.CurrentCamera
            if not origin or not camera then
                return nil
            end

            local screenPoint = getMouseScreenPoint()
            local direction = convertTriggerScreenPoint(screenPoint)
            local screenGroup = collisionGroups and collisionGroups.SCREEN_RAYCAST or "ScreenRaycast"
            local screenHit = weaponRaycastLikeGame(camera.CFrame.Position, direction, screenGroup)
            local rayTarget = screenHit and screenHit.Position or direction
            local shotHit = weaponRaycastLikeGame(origin, rayTarget, nil)
            local finalHit = shotHit or screenHit
            local hitInstance = finalHit and finalHit.Instance
            local hitPosition = finalHit and finalHit.Position
            if not hitInstance or not hitPosition then
                return nil
            end

            local player = getPlayerFromPart(hitInstance)
            if not player or not isShotCandidate(player) then
                return nil
            end

            local finalInstance = hitInstance
            local finalPosition = hitPosition
            local finalDirection = direction
            if triggerSettings.smartAim then
                local targetPart = normalizeTargetPart(player, hitInstance, screenPoint)
                    or getClosestBodyPartToScreenPoint(player, screenPoint)
                local aimPosition = resolveShotAimPosition(origin, player, targetPart, nil, screenPoint, true)
                if targetPart and aimPosition then
                    finalInstance = targetPart
                    finalPosition = aimPosition
                    finalDirection = aimPosition
                end
            end

            return {
                tool = tool,
                player = player,
                instance = finalInstance,
                position = finalPosition,
                origin = origin,
                direction = finalDirection,
                cooldown = math.max(
                    tonumber(tool:GetAttribute("Cooldown")) or DEFAULT_TRIGGER_COOLDOWN,
                    SHOT_LOCK_TIME
                ),
            }
        end

        local function clearPendingTrigger(releaseShotToken)
            if releaseShotToken and pendingShotToken then
                releaseScriptShot(pendingShotToken, 0.05)
            end
            pendingPlayer = nil
            pendingInstance = nil
            pendingStartedAt = 0
            pendingShotToken = nil
        end

        local function fireTriggerShot(hit)
            if not hit then
                return false
            end
            if pendingShotToken and not isScriptShotTokenCurrent(pendingShotToken) then
                pendingShotToken = nil
                return false
            end
            local shotToken = pendingShotToken or reserveScriptShot(SHOT_LOCK_TIME)
            if not shotToken then
                return false
            end

            local now = tick()
            if now - lastTriggerShot < hit.cooldown then
                releaseScriptShot(shotToken, 0.05)
                if shotToken == pendingShotToken then
                    pendingShotToken = nil
                end
                return false
            end

            disableTriggerDefaultToolFire()
            playShootAnimation()
            playFireSound()
            createTracer(hit.origin, hit.position, nil, false)
            shootRemote:FireServer(hit.origin, hit.direction, hit.instance, hit.position)
            displayCooldownBar(hit.cooldown)
            lastTriggerShot = now
            commitScriptShot(shotToken, hit.cooldown)
            if shotToken == pendingShotToken then
                pendingShotToken = nil
            end
            return true
        end

        local function cleanupInactiveTriggerbot()
            if activeTriggerbot() then
                return
            end
            clearPendingTrigger(true)
            restoreTriggerToolFire()
        end

        connectSafe(RunService.RenderStepped, "PC Game Raycast Triggerbot", function()
            if not activeTriggerbot() then
                clearPendingTrigger(true)
                restoreTriggerToolFire()
                return
            end

            disableTriggerDefaultToolFire()

            local now = tick()
            if now - lastTriggerScan < Perf.TriggerbotRate then
                return
            end
            lastTriggerScan = now

            local hit = getTriggerHit()
            if not hit then
                clearPendingTrigger(true)
                return
            end

            if pendingPlayer ~= hit.player or pendingInstance ~= hit.instance then
                clearPendingTrigger(true)
                pendingPlayer = hit.player
                pendingInstance = hit.instance
                pendingStartedAt = now
                if triggerSettings.delay > 0 then
                    pendingShotToken = reserveScriptShot(triggerSettings.delay + hit.cooldown)
                    if not pendingShotToken then
                        clearPendingTrigger(false)
                    end
                    return
                end
            end

            if triggerSettings.delay > 0 and now - pendingStartedAt < triggerSettings.delay then
                return
            end

            if fireTriggerShot(hit) then
                clearPendingTrigger(false)
            end
        end)

        rememberConnection(UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed or input.KeyCode ~= triggerSettings.keybind then
                return
            end
            if triggerSettings.mode == "Toggle" then
                keybindActive = not keybindActive
            else
                keybindActive = true
            end
            cleanupInactiveTriggerbot()
        end))
        rememberConnection(UserInputService.InputEnded:Connect(function(input)
            if triggerSettings.mode == "Hold" and input.KeyCode == triggerSettings.keybind then
                keybindActive = false
                cleanupInactiveTriggerbot()
            end
        end))

        Tabs.Trigger
            :AddToggle("TriggerbotV1Toggle", { Title = "Triggerbot", Default = false })
            :OnChanged(function(value)
                triggerSettings.enabled = value
                clearPendingTrigger(true)
                cleanupInactiveTriggerbot()
            end)
        Tabs.Trigger
            :AddToggle("TriggerbotSmartAim", { Title = "Smart Trigger Aim", Default = false })
            :OnChanged(function(value)
                triggerSettings.smartAim = value == true
                clearPendingTrigger(true)
            end)
        Tabs.Trigger
            :AddToggle("TriggerbotV2Enabled", { Title = "Use Keybind", Default = false })
            :OnChanged(function(value)
                triggerSettings.keybindEnabled = value
                if not value then
                    keybindActive = false
                end
                clearPendingTrigger(true)
                cleanupInactiveTriggerbot()
            end)
        Tabs.Trigger:AddDropdown("TriggerbotV2Keybind", {
            Title = "Trigger Key",
            Values = {
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
                "LeftShift",
                "LeftAlt",
                "CapsLock",
                "Space",
                "LeftControl",
                "RightControl",
            },
            Default = "T",
            Callback = function(value)
                triggerSettings.keybind = enumFromString(value)
            end,
        })
        Tabs.Trigger:AddDropdown("TriggerbotV2Mode", {
            Title = "Trigger Mode",
            Values = { "Hold", "Toggle" },
            Default = "Hold",
            Callback = function(value)
                triggerSettings.mode = value
                keybindActive = false
                cleanupInactiveTriggerbot()
            end,
        })
        Tabs.Trigger:AddSlider("TriggerbotDelay", {
            Title = "Trigger Delay (ms)",
            Default = 0,
            Min = 0,
            Max = 500,
            Rounding = 0,
            Callback = function(value)
                triggerSettings.delay = math.max(0, (tonumber(value) or 0) / 1000)
                clearPendingTrigger(true)
            end,
        })
    end)

    registerFeature("Hitbox Expander", {}, nil, function()
        local hbeEnabled = false
        local hbeSize = 4.1
        local visualizeHitbox = false
        local hbeWallCheck = true
        local knifeHBE = false
        local partsToCheck = { "Head", "HumanoidRootPart", "UpperTorso", "Torso" }
        local hbeTouched = {}
        local hbeWasActive = false
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Blacklist

        local function resetCharacter(character)
            local hrp = character and character:FindFirstChild("HumanoidRootPart")
            if not hrp then
                return
            end
            hrp.Size = Vector3.new(2, 2, 1)
            hrp.Material = Enum.Material.Plastic
            hrp.BrickColor = BrickColor.new("White")
            hrp.Transparency = 1
        end

        local function resetAll()
            for character in pairs(hbeTouched) do
                resetCharacter(character)
                hbeTouched[character] = nil
            end
        end

        local function visible(part)
            rayParams.FilterDescendantsInstances = { LocalPlayer.Character }
            local origin = Camera.CFrame.Position
            local result = Workspace:Raycast(origin, (part.Position - origin).Unit * 500, rayParams)
            return result and result.Instance and result.Instance:IsDescendantOf(part.Parent)
        end

        local function apply(character, currentSize, isVisible)
            local hrp = character and character:FindFirstChild("HumanoidRootPart")
            if not hrp then
                return
            end
            if isVisible or not hbeWallCheck then
                hbeTouched[character] = true
                hrp.Size = Vector3.new(currentSize, currentSize * 1.6, currentSize)
                hrp.Material = Enum.Material.Metal
                hrp.BrickColor = BrickColor.new("Black")
                hrp.Transparency = visualizeHitbox and 0.8 or 1
            else
                resetCharacter(character)
                hbeTouched[character] = nil
            end
        end

        local function manage()
            local hasTool = knifeHBE and isAnyToolEquipped() or isToolValid()
            if not hbeEnabled or not hasTool then
                if hbeWasActive then
                    resetAll()
                end
                hbeWasActive = false
                return
            end

            hbeWasActive = true

            for _, player in ipairs(TrackedPlayers) do
                local character = player.Character
                local hum = safeGetHumanoid(character)
                if player ~= LocalPlayer and isEnemyOf(player) and hum and hum.Health > 0 then
                    local isVisible = not hbeWallCheck
                    if hbeWallCheck then
                        for _, partName in ipairs(partsToCheck) do
                            local part = character:FindFirstChild(partName)
                            if part and visible(part) then
                                isVisible = true
                                break
                            end
                        end
                    end
                    apply(character, hbeSize, isVisible)
                elseif character then
                    if hbeTouched[character] then
                        resetCharacter(character)
                        hbeTouched[character] = nil
                    end
                end
            end
        end

        task.spawn(function()
            while runtimeAlive do
                task.wait(Perf.HBEInterval)
                if not hbeEnabled then
                    if hbeWasActive then
                        resetAll()
                    end
                    hbeWasActive = false
                    continue
                end
                local hum = safeGetHumanoid(LocalPlayer.Character)
                if hum and hum.Health > 0 then
                    manage()
                else
                    resetAll()
                    hbeWasActive = false
                end
            end
        end)

        Tabs.Hitbox:AddToggle("EnableHBE", { Title = "Enable HBE", Default = false }):OnChanged(function(value)
            hbeEnabled = value
            if not value then
                resetAll()
            end
        end)
        Tabs.Hitbox
            :AddToggle("EnableKnifeHBE", { Title = "Enable Knife HBE", Default = false })
            :OnChanged(function(value)
                knifeHBE = value
                if not hbeEnabled then
                    resetAll()
                end
            end)
        Tabs.Hitbox:AddSlider("HBEHitboxSize", {
            Title = "HBE Size",
            Default = hbeSize,
            Min = 2,
            Max = 10,
            Rounding = 1,
            Callback = function(value)
                hbeSize = tonumber(value) or hbeSize
            end,
        })
        Tabs.Hitbox:AddToggle("VisualizeHBE", { Title = "Visualize Hitbox", Default = false }):OnChanged(function(value)
            visualizeHitbox = value
        end)
        Tabs.Hitbox:AddToggle("WallCheckHBE", { Title = "HBE Wall Check", Default = true }):OnChanged(function(value)
            hbeWallCheck = value
        end)
    end)

    -- Separate function: the outer one is near the local register limit.
    registerFeature("Visuals", {}, nil, function()
        local function getCharacterRole(character, player)
            local function readRole(container)
                if not container then
                    return nil
                end
                local ok, role = pcall(function()
                    return container:GetAttribute("Role")
                end)
                if ok and role ~= nil and role ~= false and role ~= "" then
                    return tostring(role)
                end
                local valueObj = container:FindFirstChild("Role")
                if valueObj then
                    ok, role = pcall(function()
                        return valueObj.Value
                    end)
                    if ok and role ~= nil and role ~= false and role ~= "" then
                        return tostring(role)
                    end
                end
                return nil
            end
            return readRole(character) or readRole(player)
        end

        local function getPlayerMatchAttribute(player)
            if not player then
                return nil
            end
            local ok, value = pcall(function()
                return player:GetAttribute("Match")
            end)
            if not ok or value == nil or value == false or value == 0 or value == "" then
                return nil
            end
            return value
        end

        local function countWorkspacePlayerModels()
            local count = 0
            for _, player in pairs(Players:GetPlayers()) do
                local model = Workspace:FindFirstChild(player.Name)
                if model and model:IsA("Model") then
                    count += 1
                end
            end
            return count
        end

        local function isEspMatchActive()
            if countWorkspacePlayerModels() > 8 then
                return false
            end
            if getCharacterRole(LocalPlayer.Character, LocalPlayer) ~= nil then
                return true
            end
            return getPlayerMatchAttribute(LocalPlayer) ~= nil or isLocalInMatch()
        end

        local function isRelevantEspCharacter(character, player, localHasRole)
            if localHasRole == nil then
                localHasRole = getCharacterRole(LocalPlayer.Character, LocalPlayer) ~= nil
            end
            if localHasRole then
                return getCharacterRole(character, player) ~= nil
            end
            return true
        end

        local PremiumEspSettings = {
            Enabled = false,
            TeamCheck = false,
            AliveCheck = true,
            ShowBox = true,
            BoxStyle = "Corner",
            GlowFill = false,
            ShowName = false,
            ShowRole = false,
            ShowDistance = false,
            ShowHealth = false,
            ShowSkeleton = false,
            ShowHeadDot = false,
            ShowTracer = false,
            ShowChams = false,
            ShowOffscreen = false,
            ColorMode = "Role",
            InfoMode = "Clean",
            MaxDistance = 2500,
            ChamsFill = 0.68,
            TextSize = Caps.IsMobile and 11 or 12,
            UpdateRate = Caps.IsMobile and (1 / 20) or (1 / 30),
            DetailRate = Caps.IsMobile and 0.35 or 0.24,
            SkeletonRate = Caps.IsMobile and (1 / 12) or (1 / 18),
        }

        local RolePalette = {
            murderer = Color3.fromRGB(255, 72, 92),
            murder = Color3.fromRGB(255, 72, 92),
            killer = Color3.fromRGB(255, 72, 92),
            sheriff = Color3.fromRGB(68, 188, 255),
            hero = Color3.fromRGB(255, 215, 92),
            innocent = Color3.fromRGB(96, 255, 154),
            dual = Color3.fromRGB(178, 124, 255),
        }
        local AllyColor = Color3.fromRGB(96, 172, 255)
        local EnemyColor = Color3.fromRGB(255, 85, 112)
        local UnknownColor = Color3.fromRGB(235, 238, 255)
        local ShadowColor = Color3.fromRGB(2, 4, 10)

        local function roleKey(role)
            return tostring(role or ""):lower():gsub("%s+", "")
        end

        local function getEspColor(player, character)
            if PremiumEspSettings.ColorMode == "Team" then
                return isTeammateOf(player) and AllyColor or EnemyColor
            end
            local role = getCharacterRole(character, player)
            local color = RolePalette[roleKey(role)]
            if color then
                return color
            end
            if isTeammateOf(player) then
                return AllyColor
            end
            if isEnemyOf(player) then
                return EnemyColor
            end
            return UnknownColor
        end

        local function getReadableRole(player, character)
            local role = getCharacterRole(character, player)
            if role and role ~= "" then
                return tostring(role)
            end
            if player and player.Team then
                return tostring(player.Team.Name)
            end
            return "Player"
        end

        local function getHealthColor(percent)
            percent = math.clamp(tonumber(percent) or 0, 0, 1)
            if percent > 0.62 then
                return Color3.fromRGB(68, 255, 142)
            elseif percent > 0.32 then
                return Color3.fromRGB(255, 218, 86)
            end
            return Color3.fromRGB(255, 82, 98)
        end

        local function makeDrawing(kind, props)
            if not Caps.HasDrawing or type(Drawing) ~= "table" then
                return nil
            end
            local ok, obj = pcall(function()
                return Drawing.new(kind)
            end)
            if not ok or not obj then
                return nil
            end
            rememberDrawing(obj)
            for k, v in pairs(props or {}) do
                pcall(function()
                    obj[k] = v
                end)
            end
            return obj
        end

        local function setDrawingVisible(obj, visible)
            if obj then
                pcall(function()
                    obj.Visible = visible == true
                end)
            end
        end

        local function setDrawingProps(obj, props)
            if not obj then
                return
            end
            for k, v in pairs(props or {}) do
                pcall(function()
                    obj[k] = v
                end)
            end
        end

        local function setLineDrawing(line, fromPoint, toPoint, color, thickness, transparency)
            if not line then
                return
            end
            pcall(function()
                line.From = fromPoint
                line.To = toPoint
                line.Color = color
                line.Transparency = transparency or 1
                line.Thickness = thickness or 1.6
                line.Visible = true
            end)
        end

        local function getEspCamera()
            local current = Workspace.CurrentCamera
            if current then
                Camera = current
            end
            return current or Camera
        end

        local function isFiniteScreenNumber(value)
            return type(value) == "number" and value == value and math.abs(value) < math.huge
        end

        local function isUsableViewportPoint(point)
            return point
                and isFiniteScreenNumber(point.X)
                and isFiniteScreenNumber(point.Y)
                and isFiniteScreenNumber(point.Z)
                and point.Z > 0
        end

        local function isViewportPointInside(camera, point, padding)
            if not camera or not isUsableViewportPoint(point) then
                return false
            end
            padding = padding or 0
            local viewport = camera.ViewportSize
            return point.X >= -padding
                and point.X <= viewport.X + padding
                and point.Y >= -padding
                and point.Y <= viewport.Y + padding
        end

        local function projectEspPoint(camera, worldPoint, padding)
            if not camera or not worldPoint then
                return nil, false
            end
            local point, onScreen = camera:WorldToViewportPoint(worldPoint)
            return point, onScreen == true and isViewportPointInside(camera, point, padding)
        end

        local PremiumEspObjects = {}

        local function makeLine(thickness, color)
            return makeDrawing("Line", {
                Thickness = thickness or 1.5,
                Color = color or UnknownColor,
                Transparency = 1,
                Visible = false,
            })
        end

        local function createPremiumEsp(player)
            local obj = {
                Drawings = {},
                Skeleton = {},
                Connections = {},
                Chams = nil,
                LastDetailUpdate = 0,
                LastSkeletonUpdate = 0,
                CachedColor = nil,
                CachedInfoText = "",
            }
            local d = obj.Drawings
            d.BoxShadow = makeDrawing(
                "Square",
                { Filled = false, Thickness = 3.5, Color = ShadowColor, Transparency = 0.72, Visible = false }
            )
            d.Box = makeDrawing(
                "Square",
                { Filled = false, Thickness = 1.35, Color = UnknownColor, Transparency = 1, Visible = false }
            )
            d.BoxFill = makeDrawing(
                "Square",
                { Filled = true, Thickness = 0, Color = UnknownColor, Transparency = 0.12, Visible = false }
            )
            d.HealthBack = makeDrawing(
                "Square",
                { Filled = true, Thickness = 0, Color = ShadowColor, Transparency = 0.82, Visible = false }
            )
            d.Health = makeDrawing("Square", {
                Filled = true,
                Thickness = 0,
                Color = Color3.fromRGB(80, 255, 140),
                Transparency = 1,
                Visible = false,
            })
            d.Name = makeDrawing("Text", {
                Center = true,
                Outline = true,
                Color = Color3.fromRGB(255, 255, 255),
                Size = PremiumEspSettings.TextSize,
                Transparency = 1,
                Visible = false,
            })
            d.Info = makeDrawing("Text", {
                Center = true,
                Outline = true,
                Color = Color3.fromRGB(205, 214, 255),
                Size = PremiumEspSettings.TextSize - 1,
                Transparency = 1,
                Visible = false,
            })
            d.Tracer = makeLine(1.25, UnknownColor)
            d.HeadDot = makeDrawing(
                "Circle",
                { Filled = true, Radius = 4, Thickness = 1, Color = UnknownColor, Transparency = 0.9, Visible = false }
            )
            d.Arrow = makeDrawing(
                "Triangle",
                { Filled = true, Thickness = 1, Color = UnknownColor, Transparency = 0.92, Visible = false }
            )
            d.ArrowOutline = makeDrawing(
                "Triangle",
                { Filled = false, Thickness = 2, Color = ShadowColor, Transparency = 0.75, Visible = false }
            )

            local function addConnection(conn)
                if conn then
                    table.insert(obj.Connections, conn)
                    rememberConnection(conn)
                end
            end

            addConnection(player.CharacterAdded:Connect(function(character)
                task.defer(function()
                    if obj.Chams and character then
                        pcall(function()
                            obj.Chams.Parent = character
                        end)
                    end
                end)
            end))
            addConnection(player.CharacterRemoving:Connect(function()
                if obj.Chams then
                    pcall(function()
                        obj.Chams.Enabled = false
                    end)
                end
            end))

            if player.Character and obj.Chams then
                pcall(function()
                    obj.Chams.Parent = player.Character
                end)
            end

            PremiumEspObjects[player] = obj
            return obj
        end

        local function hidePremiumEsp(obj)
            if not obj then
                return
            end
            for _, drawing in pairs(obj.Drawings) do
                setDrawingVisible(drawing, false)
            end
            for _, line in ipairs(obj.Skeleton or {}) do
                setDrawingVisible(line, false)
            end
            if obj.Corners then
                for _, line in pairs(obj.Corners) do
                    setDrawingVisible(line, false)
                end
            end
            if obj.Chams then
                pcall(function()
                    obj.Chams.Enabled = false
                end)
            end
        end

        local function removePremiumEsp(player)
            local obj = PremiumEspObjects[player]
            if not obj then
                return
            end
            hidePremiumEsp(obj)
            for _, conn in ipairs(obj.Connections or {}) do
                pcall(function()
                    if conn and conn.Connected then
                        conn:Disconnect()
                    end
                end)
            end
            for _, drawing in pairs(obj.Drawings or {}) do
                removeDrawing(drawing)
            end
            for _, line in ipairs(obj.Skeleton or {}) do
                removeDrawing(line)
            end
            if obj.Corners then
                for _, line in pairs(obj.Corners) do
                    removeDrawing(line)
                end
            end
            if obj.Chams then
                destroyInstance(obj.Chams)
            end
            PremiumEspObjects[player] = nil
        end

        local function ensurePremiumEsp(player)
            if player == LocalPlayer then
                return nil
            end
            return PremiumEspObjects[player] or createPremiumEsp(player)
        end

        local function ensurePremiumChams(obj, character)
            if not obj then
                return nil
            end
            if not obj.Chams then
                local ok, chams = pcall(function()
                    local highlight = Instance.new("Highlight")
                    highlight.Name = "ZephyrPremiumESP"
                    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    highlight.FillTransparency = PremiumEspSettings.ChamsFill
                    highlight.OutlineTransparency = 0
                    highlight.Enabled = false
                    return highlight
                end)
                if ok and chams then
                    rememberInstance(chams)
                    obj.Chams = chams
                end
            end
            if obj.Chams and character then
                pcall(function()
                    obj.Chams.Parent = character
                end)
            end
            return obj.Chams
        end

        local function setPremiumChams(obj, character, color, enabled)
            local chams = enabled and ensurePremiumChams(obj, character) or (obj and obj.Chams)
            if not chams then
                return
            end
            pcall(function()
                if enabled then
                    chams.Parent = character
                    chams.Enabled = true
                    chams.FillColor = color
                    chams.OutlineColor = color
                    chams.FillTransparency = PremiumEspSettings.ChamsFill
                    chams.OutlineTransparency = 0
                else
                    chams.Enabled = false
                end
            end)
        end

        local function hideAllPremiumEsp()
            for _, obj in pairs(PremiumEspObjects) do
                hidePremiumEsp(obj)
            end
        end

        local function invalidatePremiumDetails()
            for _, obj in pairs(PremiumEspObjects) do
                obj.CachedColor = nil
                obj.CachedInfoText = nil
                obj.LastDetailUpdate = 0
            end
        end

        local function getFastCharacterBounds(character, root, camera)
            if not character or not root or not camera then
                return nil
            end
            local rootScreen, rootVisible = projectEspPoint(camera, root.Position, 8)
            if not rootVisible then
                return nil
            end

            local head = character:FindFirstChild("Head")
            local topWorld = (head and head.Position or root.Position + Vector3.new(0, 2.7, 0))
                + Vector3.new(0, 0.55, 0)
            local bottomWorld = root.Position - Vector3.new(0, 3.0, 0)
            local top = camera:WorldToViewportPoint(topWorld)
            local bottom = camera:WorldToViewportPoint(bottomWorld)
            if not isUsableViewportPoint(top) or not isUsableViewportPoint(bottom) then
                return nil
            end

            local viewport = camera.ViewportSize
            local rawHeight = math.abs(bottom.Y - top.Y)
            if rawHeight < 2 then
                return nil
            end
            local minHeight = Caps.IsMobile and 16 or 18
            local minWidth = Caps.IsMobile and 8 or 10
            local maxHeight = math.max(minHeight, math.min(viewport.Y * 0.58, Caps.IsMobile and 250 or 310))
            local maxWidth = math.max(minWidth, math.min(viewport.X * 0.2, Caps.IsMobile and 82 or 118))
            local height = math.clamp(rawHeight, minHeight, maxHeight)
            local width = math.clamp(height * 0.42, minWidth, maxWidth)
            local centerY = (top.Y + bottom.Y) * 0.5
            return Vector2.new(rootScreen.X - width * 0.5, centerY - height * 0.5),
                Vector2.new(width, height),
                rootScreen
        end

        local function drawCornerBox(obj, pos, size, color)
            local d = obj.Drawings
            if not obj.Corners then
                obj.Corners = {}
                for _, name in ipairs({ "C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8" }) do
                    obj.Corners[name] = makeLine(1.5, color)
                end
            end
            setDrawingVisible(d.Box, false)
            setDrawingVisible(d.BoxShadow, false)
            local x, y, w, h = pos.X, pos.Y, size.X, size.Y
            local corner = math.clamp(math.min(w, h) * 0.24, 7, 18)
            local c = obj.Corners
            setLineDrawing(c.C1, Vector2.new(x, y), Vector2.new(x + corner, y), color, 1.6, 1)
            setLineDrawing(c.C2, Vector2.new(x, y), Vector2.new(x, y + corner), color, 1.6, 1)
            setLineDrawing(c.C3, Vector2.new(x + w, y), Vector2.new(x + w - corner, y), color, 1.6, 1)
            setLineDrawing(c.C4, Vector2.new(x + w, y), Vector2.new(x + w, y + corner), color, 1.6, 1)
            setLineDrawing(c.C5, Vector2.new(x, y + h), Vector2.new(x + corner, y + h), color, 1.6, 1)
            setLineDrawing(c.C6, Vector2.new(x, y + h), Vector2.new(x, y + h - corner), color, 1.6, 1)
            setLineDrawing(c.C7, Vector2.new(x + w, y + h), Vector2.new(x + w - corner, y + h), color, 1.6, 1)
            setLineDrawing(c.C8, Vector2.new(x + w, y + h), Vector2.new(x + w, y + h - corner), color, 1.6, 1)
        end

        local function hideCornerBox(obj)
            if not obj or not obj.Corners then
                return
            end
            for _, line in pairs(obj.Corners) do
                setDrawingVisible(line, false)
            end
        end

        local function getSkeletonPairs(character)
            local head = character:FindFirstChild("Head")
            local torso = character:FindFirstChild("UpperTorso")
                or character:FindFirstChild("Torso")
                or character:FindFirstChild("HumanoidRootPart")
            local lower = character:FindFirstChild("LowerTorso") or torso
            local lUpperArm = character:FindFirstChild("LeftUpperArm") or character:FindFirstChild("Left Arm")
            local rUpperArm = character:FindFirstChild("RightUpperArm") or character:FindFirstChild("Right Arm")
            local lLowerArm = character:FindFirstChild("LeftLowerArm") or lUpperArm
            local rLowerArm = character:FindFirstChild("RightLowerArm") or rUpperArm
            local lHand = character:FindFirstChild("LeftHand") or lLowerArm
            local rHand = character:FindFirstChild("RightHand") or rLowerArm
            local lUpperLeg = character:FindFirstChild("LeftUpperLeg") or character:FindFirstChild("Left Leg")
            local rUpperLeg = character:FindFirstChild("RightUpperLeg") or character:FindFirstChild("Right Leg")
            local lLowerLeg = character:FindFirstChild("LeftLowerLeg") or lUpperLeg
            local rLowerLeg = character:FindFirstChild("RightLowerLeg") or rUpperLeg
            local lFoot = character:FindFirstChild("LeftFoot") or lLowerLeg
            local rFoot = character:FindFirstChild("RightFoot") or rLowerLeg
            return {
                { head, torso },
                { torso, lower },
                { torso, lUpperArm },
                { lUpperArm, lLowerArm },
                { lLowerArm, lHand },
                { torso, rUpperArm },
                { rUpperArm, rLowerArm },
                { rLowerArm, rHand },
                { lower, lUpperLeg },
                { lUpperLeg, lLowerLeg },
                { lLowerLeg, lFoot },
                { lower, rUpperLeg },
                { rUpperLeg, rLowerLeg },
                { rLowerLeg, rFoot },
            }
        end

        local function drawSkeleton(obj, character, color, camera)
            if not PremiumEspSettings.ShowSkeleton then
                for _, line in ipairs(obj.Skeleton or {}) do
                    setDrawingVisible(line, false)
                end
                return
            end
            obj.Skeleton = obj.Skeleton or {}
            for i = 1, 16 do
                if not obj.Skeleton[i] then
                    obj.Skeleton[i] = makeLine(1.35, UnknownColor)
                end
            end
            local pairs = getSkeletonPairs(character)
            for i, line in ipairs(obj.Skeleton or {}) do
                local pair = pairs[i]
                if pair and pair[1] and pair[2] then
                    local a, aVisible = projectEspPoint(camera, pair[1].Position, 2)
                    local b, bVisible = projectEspPoint(camera, pair[2].Position, 2)
                    if aVisible and bVisible then
                        setLineDrawing(line, Vector2.new(a.X, a.Y), Vector2.new(b.X, b.Y), color, 1.35, 0.92)
                    else
                        setDrawingVisible(line, false)
                    end
                else
                    setDrawingVisible(line, false)
                end
            end
        end

        local function drawOffscreenArrow(obj, root, color, camera)
            local d = obj.Drawings
            if not PremiumEspSettings.ShowOffscreen then
                setDrawingVisible(d.Arrow, false)
                setDrawingVisible(d.ArrowOutline, false)
                return
            end
            if not camera or not root then
                setDrawingVisible(d.Arrow, false)
                setDrawingVisible(d.ArrowOutline, false)
                return
            end
            local viewport = camera.ViewportSize
            local center = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
            local screen = camera:WorldToViewportPoint(root.Position)
            if
                not screen
                or not isFiniteScreenNumber(screen.X)
                or not isFiniteScreenNumber(screen.Y)
                or not isFiniteScreenNumber(screen.Z)
            then
                setDrawingVisible(d.Arrow, false)
                setDrawingVisible(d.ArrowOutline, false)
                return
            end
            local direction = Vector2.new(screen.X, screen.Y) - center
            if screen.Z < 0 then
                direction = -direction
            end
            if direction.Magnitude < 1 then
                direction = Vector2.new(0, -1)
            end
            direction = direction.Unit
            local radius = math.min(viewport.X, viewport.Y) * 0.43
            local tip = center + direction * radius
            local side = Vector2.new(-direction.Y, direction.X)
            local size = Caps.IsMobile and 13 or 15
            local a = tip + direction * size
            local b = tip - direction * size * 0.82 + side * size * 0.72
            local c = tip - direction * size * 0.82 - side * size * 0.72
            setDrawingProps(d.ArrowOutline, { PointA = a, PointB = b, PointC = c, Color = ShadowColor, Visible = true })
            setDrawingProps(d.Arrow, { PointA = a, PointB = b, PointC = c, Color = color, Visible = true })
        end

        local function hideOffscreenArrow(obj)
            setDrawingVisible(obj.Drawings.Arrow, false)
            setDrawingVisible(obj.Drawings.ArrowOutline, false)
        end

        local function getToolTag(player, character)
            local function scan(container)
                if not container then
                    return nil
                end
                for _, item in ipairs(container:GetChildren()) do
                    if item:IsA("Tool") then
                        local name = tostring(item.Name):lower()
                        if name:find("knife", 1, true) then
                            return "KNIFE"
                        end
                        if name:find("gun", 1, true) or name:find("revolver", 1, true) then
                            return "GUN"
                        end
                    end
                end
                return nil
            end
            return scan(character) or scan(player and player:FindFirstChildOfClass("Backpack"))
        end

        local function buildInfoText(player, character, humanoid, distance)
            local parts = {}
            if PremiumEspSettings.ShowRole then
                table.insert(parts, getReadableRole(player, character))
                local toolTag = getToolTag(player, character)
                if toolTag then
                    table.insert(parts, toolTag)
                end
            end
            if PremiumEspSettings.ShowHealth and humanoid and humanoid.MaxHealth > 0 then
                table.insert(parts, tostring(math.floor(humanoid.Health + 0.5)) .. " HP")
            end
            if PremiumEspSettings.ShowDistance and distance then
                table.insert(parts, tostring(math.floor(distance + 0.5)) .. "m")
            end
            if PremiumEspSettings.InfoMode == "Clean" and #parts > 2 then
                return parts[1] .. " | " .. parts[#parts]
            end
            return table.concat(parts, " | ")
        end

        local premiumEspWasActive = false
        local premiumEspLastUpdate = 0

        local function premiumEspEnabled()
            return PremiumEspSettings.Enabled
                and (
                    PremiumEspSettings.ShowBox
                    or PremiumEspSettings.ShowName
                    or PremiumEspSettings.ShowRole
                    or PremiumEspSettings.ShowDistance
                    or PremiumEspSettings.ShowHealth
                    or PremiumEspSettings.ShowSkeleton
                    or PremiumEspSettings.ShowHeadDot
                    or PremiumEspSettings.ShowTracer
                    or PremiumEspSettings.ShowChams
                    or PremiumEspSettings.ShowOffscreen
                )
        end

        connectSafe(Players.PlayerRemoving, "Premium ESP PlayerRemoving", function(player)
            removePremiumEsp(player)
        end)

        connectSafe(RunService.RenderStepped, "Premium ESP Render", function()
            if not premiumEspEnabled() then
                if premiumEspWasActive then
                    hideAllPremiumEsp()
                    premiumEspWasActive = false
                end
                return
            end
            local now = tick()
            if now - premiumEspLastUpdate < PremiumEspSettings.UpdateRate then
                return
            end
            premiumEspLastUpdate = now
            premiumEspWasActive = true

            local camera = getEspCamera()
            if not camera or not isEspMatchActive() then
                hideAllPremiumEsp()
                return
            end

            local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            local localHasRole = getCharacterRole(LocalPlayer.Character, LocalPlayer) ~= nil
            local processed = 0
            for _, player in ipairs(TrackedPlayers) do
                if processed >= Perf.ESPMaxTargets then
                    break
                end
                local obj = PremiumEspObjects[player]
                runSafely("Premium ESP PlayerUpdate", function()
                    if not player or not player.Parent then
                        return
                    end
                    local character = player.Character
                    local root = character and character:FindFirstChild("HumanoidRootPart")
                    local humanoid = character and safeGetHumanoid(character)
                    if
                        not shouldShowPlayerESP(
                            player,
                            character,
                            humanoid,
                            root,
                            PremiumEspSettings.TeamCheck,
                            PremiumEspSettings.AliveCheck
                        ) or not isRelevantEspCharacter(character, player, localHasRole)
                    then
                        if obj then
                            hidePremiumEsp(obj)
                        end
                        return
                    end
                    local distance = myRoot and (root.Position - myRoot.Position).Magnitude or nil
                    if distance and distance > math.min(PremiumEspSettings.MaxDistance, Perf.ESPMaxDistance) then
                        if obj then
                            hidePremiumEsp(obj)
                        end
                        return
                    end
                    processed += 1

                    local boundsPos, boundsSize, rootScreen = getFastCharacterBounds(character, root, camera)
                    local onScreen = boundsPos and boundsSize and rootScreen
                    if not onScreen and not PremiumEspSettings.ShowOffscreen and not PremiumEspSettings.ShowChams then
                        if obj then
                            hidePremiumEsp(obj)
                        end
                        return
                    end

                    obj = obj or ensurePremiumEsp(player)
                    if not obj then
                        return
                    end

                    local detailDue = now - (obj.LastDetailUpdate or 0) >= PremiumEspSettings.DetailRate
                    if detailDue or not obj.CachedColor then
                        obj.CachedColor = getEspColor(player, character)
                        obj.LastDetailUpdate = now
                    end
                    local color = obj.CachedColor or UnknownColor
                    if not onScreen then
                        for _, drawing in pairs(obj.Drawings) do
                            setDrawingVisible(drawing, false)
                        end
                        for _, line in ipairs(obj.Skeleton or {}) do
                            setDrawingVisible(line, false)
                        end
                        hideCornerBox(obj)
                        if PremiumEspSettings.ShowChams then
                            if detailDue or not obj.Chams or obj.Chams.Enabled ~= true then
                                setPremiumChams(obj, character, color, true)
                            end
                        else
                            setPremiumChams(obj, character, color, false)
                        end
                        drawOffscreenArrow(obj, root, color, camera)
                        return
                    end

                    hideOffscreenArrow(obj)
                    if PremiumEspSettings.GlowFill then
                        setDrawingProps(obj.Drawings.BoxFill, {
                            Position = boundsPos,
                            Size = boundsSize,
                            Color = color,
                            Transparency = 0.11,
                            Visible = true,
                        })
                    else
                        setDrawingVisible(obj.Drawings.BoxFill, false)
                    end

                    if PremiumEspSettings.ShowBox then
                        if PremiumEspSettings.BoxStyle == "Full" then
                            hideCornerBox(obj)
                            setDrawingProps(
                                obj.Drawings.BoxShadow,
                                { Position = boundsPos, Size = boundsSize, Visible = true }
                            )
                            setDrawingProps(
                                obj.Drawings.Box,
                                { Position = boundsPos, Size = boundsSize, Color = color, Visible = true }
                            )
                        else
                            drawCornerBox(obj, boundsPos, boundsSize, color)
                        end
                    else
                        hideCornerBox(obj)
                        setDrawingVisible(obj.Drawings.BoxShadow, false)
                        setDrawingVisible(obj.Drawings.Box, false)
                    end

                    local healthPct = humanoid.MaxHealth > 0 and math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
                        or 0
                    if PremiumEspSettings.ShowHealth then
                        local barHeight = boundsSize.Y
                        local barX = boundsPos.X - 6
                        setDrawingProps(obj.Drawings.HealthBack, {
                            Position = Vector2.new(barX, boundsPos.Y - 1),
                            Size = Vector2.new(3, barHeight + 2),
                            Visible = true,
                        })
                        setDrawingProps(obj.Drawings.Health, {
                            Position = Vector2.new(barX + 1, boundsPos.Y + barHeight * (1 - healthPct)),
                            Size = Vector2.new(1, math.max(1, barHeight * healthPct)),
                            Color = getHealthColor(healthPct),
                            Visible = true,
                        })
                    else
                        setDrawingVisible(obj.Drawings.HealthBack, false)
                        setDrawingVisible(obj.Drawings.Health, false)
                    end

                    local centerX = boundsPos.X + boundsSize.X * 0.5
                    if PremiumEspSettings.ShowName then
                        setDrawingProps(obj.Drawings.Name, {
                            Text = tostring(player.DisplayName or player.Name),
                            Position = Vector2.new(centerX, boundsPos.Y - 17),
                            Color = color,
                            Size = PremiumEspSettings.TextSize,
                            Visible = true,
                        })
                    else
                        setDrawingVisible(obj.Drawings.Name, false)
                    end

                    local wantsInfoText = PremiumEspSettings.ShowRole
                        or PremiumEspSettings.ShowHealth
                        or PremiumEspSettings.ShowDistance
                    local infoText = ""
                    if wantsInfoText then
                        if detailDue or obj.CachedInfoText == nil then
                            obj.CachedInfoText = buildInfoText(player, character, humanoid, distance)
                        end
                        infoText = obj.CachedInfoText or ""
                    else
                        obj.CachedInfoText = ""
                    end
                    if infoText ~= "" then
                        setDrawingProps(obj.Drawings.Info, {
                            Text = infoText,
                            Position = Vector2.new(centerX, boundsPos.Y + boundsSize.Y + 3),
                            Color = Color3.fromRGB(218, 225, 255),
                            Size = math.max(9, PremiumEspSettings.TextSize - 1),
                            Visible = true,
                        })
                    else
                        setDrawingVisible(obj.Drawings.Info, false)
                    end

                    if PremiumEspSettings.ShowHeadDot then
                        local head = character:FindFirstChild("Head")
                        local headScreen, headVisible = nil, false
                        if head then
                            headScreen, headVisible = projectEspPoint(camera, head.Position, 2)
                        end
                        if headVisible then
                            local radius = math.clamp(boundsSize.Y * 0.045, 3, 7)
                            setDrawingProps(obj.Drawings.HeadDot, {
                                Position = Vector2.new(headScreen.X, headScreen.Y),
                                Radius = radius,
                                Color = color,
                                Visible = true,
                            })
                        else
                            setDrawingVisible(obj.Drawings.HeadDot, false)
                        end
                    else
                        setDrawingVisible(obj.Drawings.HeadDot, false)
                    end

                    if PremiumEspSettings.ShowTracer then
                        local viewport = camera.ViewportSize
                        local from
                        if PremiumEspSettings.TracerOrigin == "Mouse" then
                            from = UserInputService:GetMouseLocation()
                        elseif PremiumEspSettings.TracerOrigin == "Center" then
                            from = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
                        else
                            from = Vector2.new(viewport.X * 0.5, viewport.Y - 18)
                        end
                        setDrawingProps(obj.Drawings.Tracer, {
                            From = from,
                            To = Vector2.new(rootScreen.X, rootScreen.Y),
                            Color = color,
                            Transparency = 0.72,
                            Visible = true,
                        })
                    else
                        setDrawingVisible(obj.Drawings.Tracer, false)
                    end

                    if PremiumEspSettings.ShowSkeleton then
                        if now - (obj.LastSkeletonUpdate or 0) >= PremiumEspSettings.SkeletonRate then
                            obj.LastSkeletonUpdate = now
                            drawSkeleton(obj, character, color, camera)
                        end
                    else
                        drawSkeleton(obj, character, color, camera)
                    end

                    if PremiumEspSettings.ShowChams then
                        if detailDue or not obj.Chams or obj.Chams.Enabled ~= true then
                            setPremiumChams(obj, character, color, true)
                        end
                    else
                        setPremiumChams(obj, character, color, false)
                    end
                end)
            end
        end)

        do
            Tabs.Visuals:AddToggle("PremiumESP", { Title = "Enable ESP", Default = false }):OnChanged(function(value)
                PremiumEspSettings.Enabled = value
                if not value then
                    hideAllPremiumEsp()
                end
            end)

            Tabs.Visuals
                :AddToggle("PremiumESPTeamCheck", { Title = "Team Check", Default = false })
                :OnChanged(function(value)
                    PremiumEspSettings.TeamCheck = value
                end)

            Tabs.Visuals
                :AddDropdown(
                    "PremiumESPBoxStyle",
                    { Title = "Box Style", Values = { "Corner", "Full" }, Default = "Corner" }
                )
                :OnChanged(function(value)
                    PremiumEspSettings.BoxStyle = value
                end)

            Tabs.Visuals
                :AddDropdown(
                    "PremiumESPColorMode",
                    { Title = "Color Mode", Values = { "Role", "Team" }, Default = "Role" }
                )
                :OnChanged(function(value)
                    PremiumEspSettings.ColorMode = value
                    invalidatePremiumDetails()
                end)

            Tabs.Visuals
                :AddDropdown(
                    "PremiumESPInfoMode",
                    { Title = "Info Style", Values = { "Clean", "Detailed" }, Default = "Clean" }
                )
                :OnChanged(function(value)
                    PremiumEspSettings.InfoMode = value
                    invalidatePremiumDetails()
                end)

            Tabs.Visuals:AddSlider("PremiumESPDistance", {
                Title = "Max Distance",
                Default = PremiumEspSettings.MaxDistance,
                Min = 100,
                Max = 5000,
                Rounding = 0,
                Callback = function(value)
                    PremiumEspSettings.MaxDistance = tonumber(value) or PremiumEspSettings.MaxDistance
                end,
            })

            Tabs.Visuals:AddToggle("PremiumESPBox", { Title = "Box", Default = true }):OnChanged(function(value)
                PremiumEspSettings.ShowBox = value
            end)
            Tabs.Visuals
                :AddToggle("PremiumESPGlowFill", { Title = "Soft Fill", Default = false })
                :OnChanged(function(value)
                    PremiumEspSettings.GlowFill = value
                end)
            Tabs.Visuals
                :AddToggle("PremiumESPName", { Title = "Name", Default = PremiumEspSettings.ShowName })
                :OnChanged(function(value)
                    PremiumEspSettings.ShowName = value
                end)
            Tabs.Visuals
                :AddToggle("PremiumESPRole", { Title = "Role / Team", Default = PremiumEspSettings.ShowRole })
                :OnChanged(function(value)
                    PremiumEspSettings.ShowRole = value
                    invalidatePremiumDetails()
                end)
            Tabs.Visuals
                :AddToggle("PremiumESPDistanceText", { Title = "Distance", Default = PremiumEspSettings.ShowDistance })
                :OnChanged(function(value)
                    PremiumEspSettings.ShowDistance = value
                    invalidatePremiumDetails()
                end)
            Tabs.Visuals
                :AddToggle("PremiumESPHealth", { Title = "Health Bar", Default = PremiumEspSettings.ShowHealth })
                :OnChanged(function(value)
                    PremiumEspSettings.ShowHealth = value
                    invalidatePremiumDetails()
                end)
            Tabs.Visuals
                :AddToggle("PremiumESPChams", { Title = "Highlight Chams", Default = PremiumEspSettings.ShowChams })
                :OnChanged(function(value)
                    PremiumEspSettings.ShowChams = value
                    if not value then
                        for _, obj in pairs(PremiumEspObjects) do
                            if obj.Chams then
                                pcall(function()
                                    obj.Chams.Enabled = false
                                end)
                            end
                        end
                    end
                end)
            Tabs.Visuals
                :AddToggle("PremiumESPSkeleton", { Title = "Skeleton", Default = false })
                :OnChanged(function(value)
                    PremiumEspSettings.ShowSkeleton = value
                    if not value then
                        for _, obj in pairs(PremiumEspObjects) do
                            for _, line in ipairs(obj.Skeleton or {}) do
                                setDrawingVisible(line, false)
                            end
                        end
                    else
                        for _, obj in pairs(PremiumEspObjects) do
                            obj.LastSkeletonUpdate = 0
                        end
                    end
                end)
            Tabs.Visuals
                :AddToggle("PremiumESPHeadDot", { Title = "Head Dot", Default = false })
                :OnChanged(function(value)
                    PremiumEspSettings.ShowHeadDot = value
                end)
            Tabs.Visuals:AddToggle("PremiumESPTracer", { Title = "Tracers", Default = false }):OnChanged(function(value)
                PremiumEspSettings.ShowTracer = value
            end)
            Tabs.Visuals
                :AddDropdown(
                    "PremiumESPTracerOrigin",
                    { Title = "Tracer Origin", Values = { "Bottom", "Center", "Mouse" }, Default = "Bottom" }
                )
                :OnChanged(function(value)
                    PremiumEspSettings.TracerOrigin = value
                end)
            Tabs.Visuals
                :AddToggle(
                    "PremiumESPOffscreen",
                    { Title = "Offscreen Arrows", Default = PremiumEspSettings.ShowOffscreen }
                )
                :OnChanged(function(value)
                    PremiumEspSettings.ShowOffscreen = value
                end)

            if not Caps.HasDrawing then
                recordSkip("Premium Drawing ESP", "missing Drawing API; highlight chams may still work")
            end
        end

        do
            local EspSettings = {
                Checks = { TeamCheck = false, AliveCheck = true },
                Box = {
                    Enabled = false,
                    Style = "Normal",
                    Color = Color3.fromRGB(255, 255, 255),
                    Thickness = 1,
                    Transparency = 1,
                    CornerSize = 5,
                },
                HealthBar = {
                    Enabled = false,
                    Thickness = 1,
                    Transparency = 1,
                    FullColor = Color3.fromRGB(0, 255, 0),
                    HalfColor = Color3.fromRGB(255, 255, 0),
                    LowColor = Color3.fromRGB(255, 0, 0),
                    Position = "Overhead",
                    Width = 50,
                },
                Chams = { Enabled = false, Transparency = 0.5 },
            }

            local function GetHealthBarColor(health, maxHealth)
                local pct = health / maxHealth
                if pct > 0.65 then
                    return EspSettings.HealthBar.FullColor
                elseif pct > 0.35 then
                    return EspSettings.HealthBar.HalfColor
                else
                    return EspSettings.HealthBar.LowColor
                end
            end

            local EspObjects = {}

            local function getCornerLines(drawings)
                if not drawings then
                    return {}
                end
                if not drawings.CornerLines then
                    drawings.CornerLines = {
                        drawings.TopLeftVert,
                        drawings.TopLeftHor,
                        drawings.TopRightVert,
                        drawings.TopRightHor,
                        drawings.BottomLeftVert,
                        drawings.BottomLeftHor,
                        drawings.BottomRightVert,
                        drawings.BottomRightHor,
                    }
                end
                return drawings.CornerLines
            end

            local function getCharacterRole(character)
                if not character then
                    return nil
                end
                local ok, role = pcall(function()
                    return character:GetAttribute("Role")
                end)
                if not ok or role == nil or role == false or role == "" then
                    return nil
                end
                return role
            end

            local function getPlayerMatchAttribute(player)
                if not player then
                    return nil
                end
                local ok, value = pcall(function()
                    return player:GetAttribute("Match")
                end)
                if not ok or value == nil or value == false or value == 0 or value == "" then
                    return nil
                end
                return value
            end

            local function countWorkspacePlayerModels()
                local count = 0
                for _, player in pairs(Players:GetPlayers()) do
                    local model = Workspace:FindFirstChild(player.Name)
                    if model and model:IsA("Model") then
                        count += 1
                    end
                end
                return count
            end

            local function isEspMatchActive()
                if countWorkspacePlayerModels() > 8 then
                    return false
                end
                if getCharacterRole(LocalPlayer.Character) ~= nil then
                    return true
                end
                return getPlayerMatchAttribute(LocalPlayer) ~= nil
            end

            local function isRelevantEspCharacter(character)
                if getCharacterRole(LocalPlayer.Character) ~= nil then
                    return getCharacterRole(character) ~= nil
                end
                return true
            end

            local function safeSetChamsEnabled(esp, enabled)
                if esp.Chams then
                    pcall(function()
                        esp.Chams.Enabled = enabled
                    end)
                end
            end

            local function safeSetChamsParent(esp, character)
                if not esp.Chams or not esp.Chams.Parent then
                    pcall(function()
                        if esp.Chams then
                            esp.Chams:Destroy()
                        end
                    end)
                    local newChams = Instance.new("Highlight")
                    newChams.FillTransparency = EspSettings.Chams.Transparency
                    newChams.OutlineTransparency = 0
                    newChams.Enabled = false
                    esp.Chams = newChams
                end
                pcall(function()
                    esp.Chams.Parent = character
                end)
            end

            local function hideEsp(drawings)
                if not drawings then
                    return
                end
                drawings.Box.Visible = false
                drawings.HealthBarOutline.Visible = false
                drawings.HealthBar.Visible = false
                safeSetChamsEnabled(drawings, false)
                for _, line in ipairs(getCornerLines(drawings)) do
                    if line then
                        line.Visible = false
                    end
                end
            end

            local function hideAllEsp()
                for _, drawings in pairs(EspObjects) do
                    hideEsp(drawings)
                end
            end

            local function RemoveEsp(player)
                local esp = EspObjects[player]
                if not esp then
                    return
                end
                if esp.Connections then
                    for _, conn in ipairs(esp.Connections) do
                        pcall(function()
                            if conn and conn.Connected then
                                conn:Disconnect()
                            end
                        end)
                    end
                end
                pcall(function()
                    esp.Box:Remove()
                    esp.HealthBarOutline:Remove()
                    esp.HealthBar:Remove()
                    if esp.Chams then
                        esp.Chams:Destroy()
                    end
                    esp.TopLeftVert:Remove()
                    esp.TopLeftHor:Remove()
                    esp.TopRightVert:Remove()
                    esp.TopRightHor:Remove()
                    esp.BottomLeftVert:Remove()
                    esp.BottomLeftHor:Remove()
                    esp.BottomRightVert:Remove()
                    esp.BottomRightHor:Remove()
                end)
                EspObjects[player] = nil
            end

            local function CreateEsp(player)
                if EspObjects[player] then
                    RemoveEsp(player)
                end

                local esp = {
                    Box = Drawing.new("Square"),
                    HealthBarOutline = Drawing.new("Square"),
                    HealthBar = Drawing.new("Square"),
                    Chams = nil,
                    TopLeftVert = Drawing.new("Line"),
                    TopLeftHor = Drawing.new("Line"),
                    TopRightVert = Drawing.new("Line"),
                    TopRightHor = Drawing.new("Line"),
                    BottomLeftVert = Drawing.new("Line"),
                    BottomLeftHor = Drawing.new("Line"),
                    BottomRightVert = Drawing.new("Line"),
                    BottomRightHor = Drawing.new("Line"),
                    Connections = {},
                }
                esp.CornerLines = {
                    esp.TopLeftVert,
                    esp.TopLeftHor,
                    esp.TopRightVert,
                    esp.TopRightHor,
                    esp.BottomLeftVert,
                    esp.BottomLeftHor,
                    esp.BottomRightVert,
                    esp.BottomRightHor,
                }

                local function addEspConnection(conn)
                    if conn then
                        table.insert(esp.Connections, conn)
                        rememberConnection(conn)
                    end
                end

                esp.Box.Thickness = EspSettings.Box.Thickness
                esp.Box.Color = EspSettings.Box.Color
                esp.Box.Transparency = EspSettings.Box.Transparency
                esp.Box.Filled = false
                esp.Box.Visible = false

                local cornerProps = {
                    Thickness = EspSettings.Box.Thickness,
                    Color = EspSettings.Box.Color,
                    Transparency = EspSettings.Box.Transparency,
                    Visible = false,
                }
                for _, line in ipairs(esp.CornerLines) do
                    for p, v in pairs(cornerProps) do
                        line[p] = v
                    end
                end

                esp.HealthBarOutline.Thickness = EspSettings.HealthBar.Thickness
                esp.HealthBarOutline.Color = Color3.fromRGB(0, 0, 0)
                esp.HealthBarOutline.Transparency = EspSettings.HealthBar.Transparency
                esp.HealthBarOutline.Filled = true
                esp.HealthBarOutline.Visible = false

                esp.HealthBar.Thickness = EspSettings.HealthBar.Thickness
                esp.HealthBar.Transparency = EspSettings.HealthBar.Transparency
                esp.HealthBar.Filled = true
                esp.HealthBar.Visible = false

                pcall(function()
                    local chams = Instance.new("Highlight")
                    chams.FillTransparency = EspSettings.Chams.Transparency
                    chams.OutlineTransparency = 0
                    chams.Enabled = false
                    if player.Character then
                        chams.Parent = player.Character
                    end
                    esp.Chams = chams
                end)

                EspObjects[player] = esp

                if player.Character then
                    local hum = safeGetHumanoid(player.Character)
                    if hum then
                        addEspConnection(hum.Died:Connect(function()
                            runSafely("Drawing ESP HumanoidDied", function()
                                hideEsp(esp)
                            end)
                        end))
                    end
                end

                addEspConnection(player.CharacterAdded:Connect(function(char)
                    runSafely("Drawing ESP CharacterAdded", function()
                        safeSetChamsParent(esp, char)
                        task.spawn(function()
                            local hum = char:WaitForChild("Humanoid", 5)
                            if hum then
                                addEspConnection(hum.Died:Connect(function()
                                    runSafely("Drawing ESP HumanoidDied", function()
                                        hideEsp(esp)
                                    end)
                                end))
                            end
                        end)
                    end)
                end))
            end

            local function anyDrawingEspEnabled()
                return EspSettings.Box.Enabled or EspSettings.HealthBar.Enabled or EspSettings.Chams.Enabled
            end

            local function ensureEsp(player)
                if player ~= LocalPlayer and not EspObjects[player] then
                    CreateEsp(player)
                end
                return EspObjects[player]
            end

            connectSafe(Players.PlayerAdded, "Drawing ESP PlayerAdded", function(player)
                if anyDrawingEspEnabled() then
                    ensureEsp(player)
                end
            end)
            connectSafe(Players.PlayerRemoving, "Drawing ESP PlayerRemoving", function(player)
                RemoveEsp(player)
            end)

            local espLastUpdate = tick()
            local espUpdateRate = Perf.ESPUpdateRate
            local drawingEspWasActive = false

            connectSafe(RunService.RenderStepped, "Drawing ESP Render", function()
                -- Old configs can enable both ESPs. Let the main one draw the boxes.
                if PremiumEspSettings.Enabled or not anyDrawingEspEnabled() then
                    if drawingEspWasActive then
                        hideAllEsp()
                        drawingEspWasActive = false
                    end
                    return
                end

                if not areHiddenFoldersPresent() or not isEspMatchActive() then
                    if drawingEspWasActive then
                        hideAllEsp()
                        drawingEspWasActive = false
                    end
                    return
                end

                local camera = getEspCamera()
                if not camera then
                    hideAllEsp()
                    drawingEspWasActive = false
                    return
                end

                local now = tick()
                if now - espLastUpdate < espUpdateRate then
                    return
                end
                espLastUpdate = now
                drawingEspWasActive = true

                local processed = 0
                local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

                for _, player in ipairs(TrackedPlayers) do
                    if processed >= Perf.ESPMaxTargets then
                        break
                    end
                    local drawings = ensureEsp(player)
                    if drawings then
                        runSafely("Drawing ESP PlayerUpdate", function()
                            if not player or not player.Parent then
                                RemoveEsp(player)
                                return
                            end

                            local character = player.Character
                            if not character or not character:FindFirstChild("HumanoidRootPart") then
                                hideEsp(drawings)
                                return
                            end

                            local humanoid = safeGetHumanoid(character)
                            if not humanoid then
                                hideEsp(drawings)
                                return
                            end
                            if not isRelevantEspCharacter(character) then
                                hideEsp(drawings)
                                return
                            end
                            if isCharacterHidden(character) then
                                hideEsp(drawings)
                                return
                            end
                            if EspSettings.Checks.AliveCheck and humanoid.Health <= 0 then
                                hideEsp(drawings)
                                return
                            end
                            if EspSettings.Checks.TeamCheck and isTeammateOf(player) then
                                hideEsp(drawings)
                                return
                            end

                            local hrp = character.HumanoidRootPart
                            if myRoot and (hrp.Position - myRoot.Position).Magnitude > Perf.ESPMaxDistance then
                                hideEsp(drawings)
                                return
                            end
                            local rootVec, onScreen = projectEspPoint(camera, hrp.Position, 2)

                            if not onScreen then
                                hideEsp(drawings)
                                return
                            end
                            processed += 1
                            if processed > Perf.ESPMaxTargets then
                                hideEsp(drawings)
                                return
                            end

                            local topVec = camera:WorldToViewportPoint(hrp.Position + Vector3.new(0, 3, 0))
                            local bottomVec = camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                            if not isUsableViewportPoint(topVec) or not isUsableViewportPoint(bottomVec) then
                                hideEsp(drawings)
                                return
                            end
                            local boxHeight =
                                math.clamp(math.abs(topVec.Y - bottomVec.Y), 8, camera.ViewportSize.Y * 1.5)
                            local boxWidth = math.clamp(boxHeight / 2, 4, camera.ViewportSize.X * 0.8)
                            local boxSize = Vector2.new(boxWidth, boxHeight)
                            local boxPos = Vector2.new(rootVec.X - boxSize.X / 2, rootVec.Y - boxSize.Y / 2)

                            if EspSettings.Box.Enabled then
                                if EspSettings.Box.Style == "Normal" then
                                    drawings.Box.Size = boxSize
                                    drawings.Box.Position = boxPos
                                    drawings.Box.Visible = true
                                    drawings.Box.Color = getTeamColor(player)
                                    for _, line in ipairs(getCornerLines(drawings)) do
                                        if line then
                                            line.Visible = false
                                        end
                                    end
                                else
                                    drawings.Box.Visible = false
                                    local cs = EspSettings.Box.CornerSize
                                    local cc = getTeamColor(player)
                                    drawings.TopLeftVert.From = Vector2.new(boxPos.X, boxPos.Y)
                                    drawings.TopLeftVert.To = Vector2.new(boxPos.X, boxPos.Y + cs)
                                    drawings.TopLeftHor.From = Vector2.new(boxPos.X, boxPos.Y)
                                    drawings.TopLeftHor.To = Vector2.new(boxPos.X + cs, boxPos.Y)
                                    drawings.TopRightVert.From = Vector2.new(boxPos.X + boxSize.X, boxPos.Y)
                                    drawings.TopRightVert.To = Vector2.new(boxPos.X + boxSize.X, boxPos.Y + cs)
                                    drawings.TopRightHor.From = Vector2.new(boxPos.X + boxSize.X, boxPos.Y)
                                    drawings.TopRightHor.To = Vector2.new(boxPos.X + boxSize.X - cs, boxPos.Y)
                                    drawings.BottomLeftVert.From = Vector2.new(boxPos.X, boxPos.Y + boxSize.Y)
                                    drawings.BottomLeftVert.To = Vector2.new(boxPos.X, boxPos.Y + boxSize.Y - cs)
                                    drawings.BottomLeftHor.From = Vector2.new(boxPos.X, boxPos.Y + boxSize.Y)
                                    drawings.BottomLeftHor.To = Vector2.new(boxPos.X + cs, boxPos.Y + boxSize.Y)
                                    drawings.BottomRightVert.From =
                                        Vector2.new(boxPos.X + boxSize.X, boxPos.Y + boxSize.Y)
                                    drawings.BottomRightVert.To =
                                        Vector2.new(boxPos.X + boxSize.X, boxPos.Y + boxSize.Y - cs)
                                    drawings.BottomRightHor.From =
                                        Vector2.new(boxPos.X + boxSize.X, boxPos.Y + boxSize.Y)
                                    drawings.BottomRightHor.To =
                                        Vector2.new(boxPos.X + boxSize.X - cs, boxPos.Y + boxSize.Y)
                                    for _, line in ipairs(getCornerLines(drawings)) do
                                        if line then
                                            line.Visible = true
                                            line.Color = cc
                                        end
                                    end
                                end
                            else
                                drawings.Box.Visible = false
                                for _, line in ipairs(getCornerLines(drawings)) do
                                    if line then
                                        line.Visible = false
                                    end
                                end
                            end

                            if EspSettings.HealthBar.Enabled then
                                local healthPct = humanoid.Health / humanoid.MaxHealth
                                if EspSettings.HealthBar.Position == "Side" then
                                    local hbH = boxSize.Y
                                    local hbPos = Vector2.new(boxPos.X - 5, boxPos.Y)
                                    drawings.HealthBarOutline.Size = Vector2.new(4, hbH + 2)
                                    drawings.HealthBarOutline.Position = Vector2.new(hbPos.X - 1, hbPos.Y - 1)
                                    drawings.HealthBarOutline.Visible = true
                                    drawings.HealthBar.Size = Vector2.new(2, hbH * healthPct)
                                    drawings.HealthBar.Position = Vector2.new(hbPos.X, hbPos.Y + hbH * (1 - healthPct))
                                    drawings.HealthBar.Color = GetHealthBarColor(humanoid.Health, humanoid.MaxHealth)
                                    drawings.HealthBar.Visible = true
                                else
                                    local hbW = EspSettings.HealthBar.Width
                                    local hbH = 4
                                    local hbPos = Vector2.new(boxPos.X + (boxSize.X - hbW) / 2, boxPos.Y - 10)
                                    drawings.HealthBarOutline.Size = Vector2.new(hbW + 2, hbH + 2)
                                    drawings.HealthBarOutline.Position = Vector2.new(hbPos.X - 1, hbPos.Y - 1)
                                    drawings.HealthBarOutline.Visible = true
                                    drawings.HealthBar.Size = Vector2.new(hbW * healthPct, hbH)
                                    drawings.HealthBar.Position = hbPos
                                    drawings.HealthBar.Color = GetHealthBarColor(humanoid.Health, humanoid.MaxHealth)
                                    drawings.HealthBar.Visible = true
                                end
                            else
                                drawings.HealthBar.Visible = false
                                drawings.HealthBarOutline.Visible = false
                            end

                            if EspSettings.Chams.Enabled then
                                if not drawings.Chams or not drawings.Chams.Parent then
                                    safeSetChamsParent(drawings, character)
                                end
                                pcall(function()
                                    drawings.Chams.Enabled = true
                                    drawings.Chams.FillColor = getTeamColor(player)
                                    drawings.Chams.OutlineColor = getTeamColor(player)
                                end)
                            else
                                safeSetChamsEnabled(drawings, false)
                            end
                        end)
                    end
                end
            end)

            Tabs.Visuals:AddParagraph({ Title = "ESP", Content = "Box, Health Bar, and Highlight Chams." })

            Tabs.Visuals:AddToggle("BoxESP", { Title = "Box ESP", Default = false }):OnChanged(function()
                EspSettings.Box.Enabled = Options.BoxESP.Value
                if not Options.BoxESP.Value then
                    for _, esp in pairs(EspObjects) do
                        esp.Box.Visible = false
                        for _, line in ipairs(getCornerLines(esp)) do
                            if line then
                                line.Visible = false
                            end
                        end
                    end
                end
            end)

            Tabs.Visuals
                :AddDropdown("BoxStyle", { Title = "Box Style", Values = { "Normal", "Corner" }, Default = "Normal" })
                :OnChanged(function(Value)
                    EspSettings.Box.Style = Value
                end)

            Tabs.Visuals:AddToggle("HealthBarESP", { Title = "Health Bar ESP", Default = false }):OnChanged(function()
                EspSettings.HealthBar.Enabled = Options.HealthBarESP.Value
                if not Options.HealthBarESP.Value then
                    for _, esp in pairs(EspObjects) do
                        esp.HealthBar.Visible = false
                        esp.HealthBarOutline.Visible = false
                    end
                end
            end)

            Tabs.Visuals
                :AddDropdown(
                    "HealthBarPosition",
                    { Title = "Health Bar Position", Values = { "Overhead", "Side" }, Default = "Overhead" }
                )
                :OnChanged(function(Value)
                    EspSettings.HealthBar.Position = Value
                end)

            Tabs.Visuals:AddToggle("TeamCheck", { Title = "Team Check", Default = false }):OnChanged(function()
                EspSettings.Checks.TeamCheck = Options.TeamCheck.Value
            end)

            Tabs.Visuals:AddToggle("Chams", { Title = "Highlight Chams", Default = false }):OnChanged(function()
                EspSettings.Chams.Enabled = Options.Chams.Value
                if not Options.Chams.Value then
                    for _, esp in pairs(EspObjects) do
                        safeSetChamsEnabled(esp, false)
                    end
                end
            end)

            do
                local coreGui = nil
                pcall(function()
                    coreGui = game:GetService("CoreGui")
                end)
                if coreGui then
                    connectSafe(coreGui.ChildRemoved, "Drawing ESP CoreGuiRemoved", function(child)
                        if child.Name == "ESP GUI" then
                            for p, _ in pairs(EspObjects) do
                                RemoveEsp(p)
                            end
                            EspObjects = {}
                        end
                    end)
                end
            end

            -- Skeletons and chams

            Tabs.Visuals:AddParagraph({ Title = "Extra ESP", Content = "Skeleton, Head dot, and Adornment Chams." })

            local espStates = { skeletonEspEnabled = false, headEspEnabled = false, chamsEspEnabled = false }
            local espDrawings = { skeletonLines = {}, headCircles = {} }
            local chamsCache = {}

            local function createDrawingObj(dtype, properties)
                local d = Drawing.new(dtype)
                for p, v in pairs(properties) do
                    d[p] = v
                end
                return d
            end

            local function clearSkeletonESP(player)
                if espDrawings.skeletonLines[player] then
                    for _, line in ipairs(espDrawings.skeletonLines[player]) do
                        line.Visible = false
                        line:Remove()
                    end
                    espDrawings.skeletonLines[player] = nil
                end
            end

            local function clearHeadESP(player)
                if espDrawings.headCircles[player] then
                    espDrawings.headCircles[player].Visible = false
                    espDrawings.headCircles[player]:Remove()
                    espDrawings.headCircles[player] = nil
                end
            end

            local function clearChams2(player)
                if chamsCache[player] then
                    for _, adorn in pairs(chamsCache[player]) do
                        pcall(function()
                            adorn:Destroy()
                        end)
                    end
                    chamsCache[player] = nil
                end
            end

            local function applyChams2(player)
                if not espStates.chamsEspEnabled then
                    return
                end
                local character = player.Character
                if not character then
                    clearChams2(player)
                    return
                end
                local hum = safeGetHumanoid(character)
                if not hum or hum.Health <= 0 then
                    clearChams2(player)
                    return
                end
                if not isEspMatchActive() or not isRelevantEspCharacter(character) then
                    clearChams2(player)
                    return
                end
                if not chamsCache[player] then
                    chamsCache[player] = {}
                end
                local chamColor = isTeammateOf(player) and Color3.fromRGB(0, 0, 255) or Color3.fromRGB(255, 0, 0)
                for _, part in ipairs(character:GetChildren()) do
                    if part:IsA("BasePart") and not chamsCache[player][part] then
                        local adorn = Instance.new("BoxHandleAdornment")
                        adorn.Name = "ChamsAdornment"
                        adorn.Adornee = part
                        adorn.AlwaysOnTop = true
                        adorn.ZIndex = 10
                        adorn.Size = part.Size + Vector3.new(0.05, 0.05, 0.05)
                        adorn.Color3 = chamColor
                        adorn.Transparency = 0.7
                        adorn.Parent = part
                        chamsCache[player][part] = adorn
                    elseif chamsCache[player][part] then
                        chamsCache[player][part].Color3 = chamColor
                    end
                end
            end

            local function updateSkeletonESP(player)
                local character = player.Character
                local humanoid = character and safeGetHumanoid(character)
                if
                    not character
                    or not humanoid
                    or humanoid.Health <= 0
                    or not isOnTeam(player)
                    or isCharacterHidden(character)
                    or not isEspMatchActive()
                    or not isRelevantEspCharacter(character)
                then
                    clearSkeletonESP(player)
                    return
                end
                if not espDrawings.skeletonLines[player] then
                    espDrawings.skeletonLines[player] = {}
                    for i = 1, 15 do
                        table.insert(
                            espDrawings.skeletonLines[player],
                            createDrawingObj("Line", { Thickness = 1.5, Transparency = 1 })
                        )
                    end
                end
                local camera = getEspCamera()
                if not camera then
                    clearSkeletonESP(player)
                    return
                end
                local parts = {
                    head = character:FindFirstChild("Head"),
                    torso = character:FindFirstChild("HumanoidRootPart"),
                    leftArm = character:FindFirstChild("LeftUpperArm"),
                    rightArm = character:FindFirstChild("RightUpperArm"),
                    leftLeg = character:FindFirstChild("LeftUpperLeg"),
                    rightLeg = character:FindFirstChild("RightUpperLeg"),
                    leftForearm = character:FindFirstChild("LeftLowerArm"),
                    rightForearm = character:FindFirstChild("RightLowerArm"),
                    leftThigh = character:FindFirstChild("LeftLowerLeg"),
                    rightThigh = character:FindFirstChild("RightLowerLeg"),
                    leftHand = character:FindFirstChild("LeftHand"),
                    rightHand = character:FindFirstChild("RightHand"),
                    leftFoot = character:FindFirstChild("LeftFoot"),
                    rightFoot = character:FindFirstChild("RightFoot"),
                }
                local connections = {
                    { parts.head, parts.torso },
                    { parts.torso, parts.leftArm },
                    { parts.torso, parts.rightArm },
                    { parts.torso, parts.leftLeg },
                    { parts.torso, parts.rightLeg },
                    { parts.leftArm, parts.leftForearm },
                    { parts.rightArm, parts.rightForearm },
                    { parts.leftForearm, parts.leftHand },
                    { parts.rightForearm, parts.rightHand },
                    { parts.leftLeg, parts.leftThigh },
                    { parts.rightLeg, parts.rightThigh },
                    { parts.leftThigh, parts.leftFoot },
                    { parts.rightThigh, parts.rightFoot },
                }
                for i, conn in ipairs(connections) do
                    local p1, p2 = conn[1], conn[2]
                    if p1 and p2 and espDrawings.skeletonLines[player][i] then
                        local pos1, pos1Visible = projectEspPoint(camera, p1.Position, 2)
                        local pos2, pos2Visible = projectEspPoint(camera, p2.Position, 2)
                        if pos1Visible and pos2Visible then
                            espDrawings.skeletonLines[player][i].From = Vector2.new(pos1.X, pos1.Y)
                            espDrawings.skeletonLines[player][i].To = Vector2.new(pos2.X, pos2.Y)
                            espDrawings.skeletonLines[player][i].Color = getTeamColor(player)
                            espDrawings.skeletonLines[player][i].Visible = true
                        else
                            espDrawings.skeletonLines[player][i].Visible = false
                        end
                    elseif espDrawings.skeletonLines[player][i] then
                        espDrawings.skeletonLines[player][i].Visible = false
                    end
                end
            end

            local function updateHeadESP(player)
                local character = player.Character
                local humanoid = character and safeGetHumanoid(character)
                if
                    not character
                    or not humanoid
                    or humanoid.Health <= 0
                    or not isOnTeam(player)
                    or isCharacterHidden(character)
                    or not isEspMatchActive()
                    or not isRelevantEspCharacter(character)
                then
                    clearHeadESP(player)
                    return
                end
                local head = character:FindFirstChild("Head")
                if not head then
                    if espDrawings.headCircles[player] then
                        espDrawings.headCircles[player].Visible = false
                    end
                    return
                end
                if not espDrawings.headCircles[player] then
                    espDrawings.headCircles[player] =
                        createDrawingObj("Circle", { Filled = true, Thickness = 1, Transparency = 0.5 })
                end
                local camera = getEspCamera()
                local pos, visible = projectEspPoint(camera, head.Position, 2)
                if visible then
                    espDrawings.headCircles[player].Position = Vector2.new(pos.X, pos.Y)
                    espDrawings.headCircles[player].Radius = 8
                    espDrawings.headCircles[player].Color = getTeamColor(player)
                    espDrawings.headCircles[player].Visible = true
                else
                    espDrawings.headCircles[player].Visible = false
                end
            end

            local extraEspLastUpdate = 0
            local extraEspWasActive = false
            local function anyExtraEspEnabled()
                return (
                    espStates.skeletonEspEnabled
                    and not (PremiumEspSettings.Enabled and PremiumEspSettings.ShowSkeleton)
                )
                    or (espStates.headEspEnabled and not (PremiumEspSettings.Enabled and PremiumEspSettings.ShowHeadDot))
                    or espStates.chamsEspEnabled
            end
            local function clearAllExtraEsp()
                for _, player in ipairs(TrackedPlayers) do
                    clearSkeletonESP(player)
                    clearHeadESP(player)
                    clearChams2(player)
                end
            end

            connectSafe(RunService.Heartbeat, "Extra ESP Heartbeat", function()
                if not anyExtraEspEnabled() then
                    if extraEspWasActive then
                        clearAllExtraEsp()
                        extraEspWasActive = false
                    end
                    return
                end

                local now = tick()
                if now - extraEspLastUpdate < Perf.ESPHeavyRate then
                    return
                end
                extraEspLastUpdate = now
                extraEspWasActive = true

                if not areHiddenFoldersPresent() or not isEspMatchActive() then
                    clearAllExtraEsp()
                    return
                end
                local processed = 0
                local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                for _, player in ipairs(TrackedPlayers) do
                    if processed >= Perf.ESPMaxTargets then
                        break
                    end
                    if player ~= LocalPlayer and isOnTeam(player) then
                        local character = player.Character
                        local root = character and character:FindFirstChild("HumanoidRootPart")
                        if myRoot and root and (root.Position - myRoot.Position).Magnitude > Perf.ESPMaxDistance then
                            clearSkeletonESP(player)
                            clearHeadESP(player)
                            clearChams2(player)
                            continue
                        end
                        processed += 1
                        if
                            espStates.skeletonEspEnabled
                            and not (PremiumEspSettings.Enabled and PremiumEspSettings.ShowSkeleton)
                        then
                            updateSkeletonESP(player)
                        else
                            clearSkeletonESP(player)
                        end
                        if
                            espStates.headEspEnabled
                            and not (PremiumEspSettings.Enabled and PremiumEspSettings.ShowHeadDot)
                        then
                            updateHeadESP(player)
                        else
                            clearHeadESP(player)
                        end
                        if espStates.chamsEspEnabled then
                            applyChams2(player)
                        else
                            clearChams2(player)
                        end
                    else
                        clearSkeletonESP(player)
                        clearHeadESP(player)
                        clearChams2(player)
                    end
                end
            end)

            connectSafe(Players.PlayerRemoving, "Extra ESP PlayerRemoving", function(player)
                clearSkeletonESP(player)
                clearHeadESP(player)
                clearChams2(player)
            end)

            Tabs.Visuals:AddToggle("SkeletonESP", {
                Title = "Skeleton ESP",
                Default = false,
                Callback = function(s)
                    espStates.skeletonEspEnabled = s
                    if not s then
                        for _, p in pairs(Players:GetPlayers()) do
                            clearSkeletonESP(p)
                        end
                    end
                end,
            })

            Tabs.Visuals:AddToggle("HeadESP", {
                Title = "Head ESP",
                Default = false,
                Callback = function(s)
                    espStates.headEspEnabled = s
                    if not s then
                        for _, p in pairs(Players:GetPlayers()) do
                            clearHeadESP(p)
                        end
                    end
                end,
            })

            Tabs.Visuals:AddToggle("ChamsESP", {
                Title = "Adornment Chams",
                Default = false,
                Callback = function(s)
                    espStates.chamsEspEnabled = s
                    if not s then
                        for _, p in pairs(Players:GetPlayers()) do
                            clearChams2(p)
                        end
                    end
                end,
            })
        end

        Tabs.Visuals:AddParagraph({ Title = "Ability ESP", Content = "Timers for Soul Reap and Blind tracking." })

        -- Soul Reap
        local soulReapEspEnabled = false
        local soulReapBillboards = {}

        local function createSoulReapBillboard(head)
            local bg = Instance.new("BillboardGui")
            bg.Name = "SoulReapESP_Billboard"
            bg.Adornee = head
            bg.Size = UDim2.new(4, 0, 1, 0)
            bg.StudsOffset = Vector3.new(0, 2, 0)
            bg.AlwaysOnTop = true
            local tl = Instance.new("TextLabel")
            tl.Parent = bg
            tl.Size = UDim2.new(1, 0, 1, 0)
            tl.BackgroundTransparency = 1
            tl.TextColor3 = Color3.fromRGB(255, 0, 0)
            tl.TextScaled = true
            tl.Font = Enum.Font.Arcade
            tl.Text = "3.0"
            return bg, tl
        end

        local function startSoulReapTimer(character, duration)
            if not soulReapEspEnabled or not isEspMatchActive() or not isRelevantEspCharacter(character) then
                return
            end
            local head = character:FindFirstChild("Head")
            if not head then
                return
            end
            if soulReapBillboards[character] then
                pcall(function()
                    soulReapBillboards[character]:Destroy()
                end)
                soulReapBillboards[character] = nil
            end
            local bg, tl = createSoulReapBillboard(head)
            bg.Parent = head
            soulReapBillboards[character] = bg
            local countdown = duration
            local conn
            conn = connectSafe(RunService.Heartbeat, "SoulReap Timer", function(dt)
                if not soulReapEspEnabled or not character.Parent or not head.Parent then
                    if soulReapBillboards[character] then
                        pcall(function()
                            soulReapBillboards[character]:Destroy()
                        end)
                        soulReapBillboards[character] = nil
                    end
                    if conn then
                        conn:Disconnect()
                    end
                    return
                end
                countdown -= dt
                if countdown <= 0 then
                    if soulReapBillboards[character] then
                        pcall(function()
                            soulReapBillboards[character]:Destroy()
                        end)
                        soulReapBillboards[character] = nil
                    end
                    if conn then
                        conn:Disconnect()
                    end
                else
                    tl.Text = string.format("%.1f", countdown)
                end
            end)
        end

        local function detectSoulReapEffect(player)
            local character = player.Character or player.CharacterAdded:Wait()
            if not character then
                return
            end
            local isSRActive = false
            local conn
            conn = connectSafe(character.DescendantAdded, "SoulReap DescendantAdded", function(desc)
                if not soulReapEspEnabled or not isEspMatchActive() or not isRelevantEspCharacter(character) then
                    return
                end
                if desc:IsA("BasePart") and desc.Material == Enum.Material.ForceField then
                    if not isSRActive then
                        isSRActive = true
                        startSoulReapTimer(character, 3)
                    end
                end
            end)
            connectSafe(character.DescendantRemoving, "SoulReap DescendantRemoving", function(desc)
                if desc:IsA("BasePart") and desc.Material == Enum.Material.ForceField then
                    isSRActive = false
                end
            end)
            connectSafe(player.CharacterRemoving, "SoulReap CharacterRemoving", function()
                if conn then
                    conn:Disconnect()
                end
                if soulReapBillboards[character] then
                    pcall(function()
                        soulReapBillboards[character]:Destroy()
                    end)
                    soulReapBillboards[character] = nil
                end
            end)
        end

        local soulReapMonitorStarted = false
        local function monitorSoulReap()
            if soulReapMonitorStarted then
                return
            end
            soulReapMonitorStarted = true
            for _, player in ipairs(TrackedPlayers) do
                if player ~= LocalPlayer then
                    task.spawn(detectSoulReapEffect, player)
                end
            end
            connectSafe(Players.PlayerAdded, "SoulReap PlayerAdded", function(player)
                if player ~= LocalPlayer then
                    task.spawn(detectSoulReapEffect, player)
                end
            end)
        end

        Tabs.Visuals:AddToggle("SoulReapTimerESP", {
            Title = "SoulReap Timer ESP",
            Default = false,
            Callback = function(s)
                if s then
                    soulReapEspEnabled = true
                    task.spawn(monitorSoulReap)
                else
                    soulReapEspEnabled = false
                    for char, bb in pairs(soulReapBillboards) do
                        pcall(function()
                            bb:Destroy()
                        end)
                    end
                    soulReapBillboards = {}
                end
            end,
        })

        -- Blind ESP
        local blindEspEnabled = false

        local function createBlindCountdown(character)
            if not isEspMatchActive() or not isRelevantEspCharacter(character) then
                return
            end
            local head = character:FindFirstChild("Head")
            if not head then
                return
            end
            local existing = head:FindFirstChild("BlindESP_Billboard")
            if existing then
                existing:Destroy()
            end
            local bg = Instance.new("BillboardGui")
            bg.Name = "BlindESP_Billboard"
            bg.Adornee = head
            bg.Size = UDim2.new(4, 0, 1, 0)
            bg.StudsOffset = Vector3.new(0, 2, 0)
            bg.AlwaysOnTop = true
            local tl = Instance.new("TextLabel")
            tl.Parent = bg
            tl.Size = UDim2.new(1, 0, 1, 0)
            tl.BackgroundTransparency = 1
            tl.TextColor3 = Color3.fromRGB(255, 0, 0)
            tl.TextScaled = true
            tl.Font = Enum.Font.GothamBold
            bg.Parent = head
            local countdown = 2.5
            while runtimeAlive and countdown > 0 and blindEspEnabled and character.Parent and head.Parent do
                tl.Text = string.format("%.1f", countdown)
                countdown -= RunService.Heartbeat:Wait()
                if not character:FindFirstChild("ShroudStatePart") then
                    break
                end
            end
            pcall(function()
                bg:Destroy()
            end)
        end

        local function detectShroudEffect(player)
            while runtimeAlive and player and player.Parent do
                if blindEspEnabled then
                    local character = player.Character
                    if
                        isEspMatchActive()
                        and character
                        and isRelevantEspCharacter(character)
                        and character:FindFirstChild("ShroudStatePart")
                    then
                        createBlindCountdown(character)
                    end
                end
                task.wait(blindEspEnabled and (Caps.IsMobile and 0.25 or 0.1) or 1)
            end
        end

        local blindMonitorStarted = false
        local function monitorBlindESP()
            if blindMonitorStarted then
                return
            end
            blindMonitorStarted = true
            for _, player in ipairs(TrackedPlayers) do
                if player ~= LocalPlayer then
                    task.spawn(detectShroudEffect, player)
                end
            end
            connectSafe(Players.PlayerAdded, "BlindESP PlayerAdded", function(player)
                if player ~= LocalPlayer then
                    task.spawn(detectShroudEffect, player)
                end
            end)
        end

        Tabs.Visuals:AddToggle("BlindESP", {
            Title = "Blind ESP [Shows unblind timer]",
            Default = false,
            Callback = function(s)
                if s then
                    if not blindEspEnabled then
                        blindEspEnabled = true
                        task.spawn(monitorBlindESP)
                    end
                else
                    blindEspEnabled = false
                    for _, player in pairs(Players:GetPlayers()) do
                        local char = player.Character
                        if char then
                            local head = char:FindFirstChild("Head")
                            if head then
                                local bb = head:FindFirstChild("BlindESP_Billboard")
                                if bb then
                                    bb:Destroy()
                                end
                            end
                        end
                    end
                end
            end,
        })

        -- Anti-blind
        local antiBlindEnabled = false
        local originalLightingProps = {}
        local originalSkyProps = {}

        local function storeOriginalLighting()
            originalLightingProps = {
                FogEnd = Lighting.FogEnd,
                FogStart = Lighting.FogStart,
                Brightness = Lighting.Brightness,
                Ambient = Lighting.Ambient,
                OutdoorAmbient = Lighting.OutdoorAmbient,
            }
            local sky = Lighting:FindFirstChildOfClass("Sky")
            if sky then
                originalSkyProps = {
                    SkyboxBk = sky.SkyboxBk,
                    SkyboxDn = sky.SkyboxDn,
                    SkyboxFt = sky.SkyboxFt,
                    SkyboxLf = sky.SkyboxLf,
                    SkyboxRt = sky.SkyboxRt,
                    SkyboxUp = sky.SkyboxUp,
                }
            end
        end

        local function restoreOriginalLighting()
            if originalLightingProps.FogEnd then
                Lighting.FogEnd = originalLightingProps.FogEnd
                Lighting.FogStart = originalLightingProps.FogStart
                Lighting.Brightness = originalLightingProps.Brightness
                Lighting.Ambient = originalLightingProps.Ambient
                Lighting.OutdoorAmbient = originalLightingProps.OutdoorAmbient
            end
            local sky = Lighting:FindFirstChildOfClass("Sky")
            if sky and originalSkyProps.SkyboxBk then
                sky.SkyboxBk = originalSkyProps.SkyboxBk
                sky.SkyboxDn = originalSkyProps.SkyboxDn
                sky.SkyboxFt = originalSkyProps.SkyboxFt
                sky.SkyboxLf = originalSkyProps.SkyboxLf
                sky.SkyboxRt = originalSkyProps.SkyboxRt
                sky.SkyboxUp = originalSkyProps.SkyboxUp
            end
        end

        local function resetLightingEffects()
            restoreOriginalLighting()
            for _, effect in pairs(Lighting:GetChildren()) do
                if effect:IsA("ColorCorrectionEffect") or effect:IsA("BlurEffect") then
                    effect:Destroy()
                end
            end
        end

        local function removeShroudFromLocal(character)
            if not character then
                return
            end
            local shroud = character:FindFirstChild("ShroudStatePart")
            if shroud and shroud:IsA("BasePart") then
                shroud:Destroy()
            end
            resetLightingEffects()
        end

        Tabs.Visuals:AddToggle("AntiBlind", {
            Title = "AntiBlind [Prevents blindness]",
            Default = false,
            Callback = function(s)
                if s then
                    if not antiBlindEnabled then
                        antiBlindEnabled = true
                        storeOriginalLighting()
                        task.spawn(function()
                            while runtimeAlive and antiBlindEnabled do
                                if LocalPlayer.Character then
                                    removeShroudFromLocal(LocalPlayer.Character)
                                end
                                task.wait(0.1)
                            end
                        end)
                    end
                else
                    antiBlindEnabled = false
                end
            end,
        })

        -- Player

        rememberCleanup(function()
            soulReapEspEnabled = false
            blindEspEnabled = false
            antiBlindEnabled = false
            restoreOriginalLighting()
            for _, billboard in pairs(soulReapBillboards) do
                destroyInstance(billboard)
            end
        end)
    end)

    registerFeature("Abilities", {}, nil, function()
        local abilityFolder = ReplicatedStorage:FindFirstChild("Ability")
        local configModule = abilityFolder and abilityFolder:FindFirstChild("AbilityConfig")
        if not configModule then
            recordSkip("Abilities", "unavailable")
            Tabs.Abilities:AddParagraph({ Title = "Abilities", Content = "Unavailable." })
            return
        end

        local okConfig, gameAbilityConfig = pcall(require, configModule)
        if not okConfig or type(gameAbilityConfig) ~= "table" then
            recordSkip("Abilities", "unavailable")
            Tabs.Abilities:AddParagraph({ Title = "Abilities", Content = "Unavailable." })
            return
        end

        local defaults = {}
        for key, value in pairs(gameAbilityConfig) do
            if type(value) == "number" then
                defaults[key] = value
            end
        end

        local function setGameAbilityValue(key, value)
            value = tonumber(value)
            if value == nil then
                return
            end
            gameAbilityConfig[key] = value
        end

        local liveWeaponBuffEnabled = false
        local liveWeaponBuffWatcherStarted = false
        local lastLiveWeaponBuffScan = 0
        local lastLiveWeaponBuffReequip = 0
        local originalWeaponAttributes = setmetatable({}, { __mode = "k" })
        local applyLiveWeaponBuff
        local ORIGINAL_COOLDOWN_ATTR = "ZephyrOriginalCooldown"
        local ORIGINAL_THROW_SPEED_ATTR = "ZephyrOriginalThrowSpeed"

        local function getToolOriginalAttributes(tool)
            if not tool or not tool:IsA("Tool") then
                return nil
            end
            local saved = originalWeaponAttributes[tool]
            if saved then
                local currentCooldown = tool:GetAttribute("Cooldown")
                local currentThrowSpeed = tool:GetAttribute("ThrowSpeed")
                if saved.Cooldown == nil and currentCooldown ~= nil then
                    saved.Cooldown = currentCooldown
                    pcall(function()
                        tool:SetAttribute(ORIGINAL_COOLDOWN_ATTR, currentCooldown)
                    end)
                end
                if saved.ThrowSpeed == nil and currentThrowSpeed ~= nil then
                    saved.ThrowSpeed = currentThrowSpeed
                    pcall(function()
                        tool:SetAttribute(ORIGINAL_THROW_SPEED_ATTR, currentThrowSpeed)
                    end)
                end
                return saved
            end
            local storedCooldown = tool:GetAttribute(ORIGINAL_COOLDOWN_ATTR)
            local storedThrowSpeed = tool:GetAttribute(ORIGINAL_THROW_SPEED_ATTR)
            local currentCooldown = tool:GetAttribute("Cooldown")
            local currentThrowSpeed = tool:GetAttribute("ThrowSpeed")
            saved = {
                Cooldown = storedCooldown ~= nil and storedCooldown or currentCooldown,
                ThrowSpeed = storedThrowSpeed ~= nil and storedThrowSpeed or currentThrowSpeed,
            }
            originalWeaponAttributes[tool] = saved
            if saved.Cooldown ~= nil and storedCooldown == nil then
                pcall(function()
                    tool:SetAttribute(ORIGINAL_COOLDOWN_ATTR, saved.Cooldown)
                end)
            end
            if saved.ThrowSpeed ~= nil and storedThrowSpeed == nil then
                pcall(function()
                    tool:SetAttribute(ORIGINAL_THROW_SPEED_ATTR, saved.ThrowSpeed)
                end)
            end
            return saved
        end

        local function forEachLocalTool(callback)
            local character = LocalPlayer.Character
            local backpack = LocalPlayer:FindFirstChildOfClass("Backpack") or LocalPlayer:FindFirstChild("Backpack")
            for _, container in ipairs({ character, backpack }) do
                if container then
                    for _, child in ipairs(container:GetChildren()) do
                        if child:IsA("Tool") then
                            callback(child, container)
                        end
                    end
                end
            end
        end

        local function applyLiveWeaponBuffToTool(tool)
            local saved = getToolOriginalAttributes(tool)
            if not saved then
                return false
            end

            local changed = false
            local shootBuff = math.max(0, tonumber(gameAbilityConfig.ShootSpeedBuff) or 0)
            local throwBuff = math.max(0, tonumber(gameAbilityConfig.ThrowSpeedBuff) or 0)

            local baseCooldown = tonumber(saved.Cooldown)
            if baseCooldown and isGunTool(tool) then
                local newCooldown = math.clamp(baseCooldown / math.max(1 + shootBuff, 0.05), 0.05, baseCooldown)
                if math.abs((tonumber(tool:GetAttribute("Cooldown")) or baseCooldown) - newCooldown) > 0.001 then
                    tool:SetAttribute("Cooldown", newCooldown)
                    changed = true
                end
            end

            local baseThrowSpeed = tonumber(saved.ThrowSpeed)
            if baseThrowSpeed then
                local newThrowSpeed = math.clamp(baseThrowSpeed * math.max(1 + throwBuff, 0.05), 1, 10000)
                if math.abs((tonumber(tool:GetAttribute("ThrowSpeed")) or baseThrowSpeed) - newThrowSpeed) > 0.001 then
                    tool:SetAttribute("ThrowSpeed", newThrowSpeed)
                    changed = true
                end
            end

            return changed
        end

        local function restoreLiveWeaponBuffToTool(tool)
            local saved = originalWeaponAttributes[tool]
            if not saved or not tool or not tool.Parent then
                return false
            end
            local changed = false
            if saved.Cooldown ~= nil and tool:GetAttribute("Cooldown") ~= saved.Cooldown then
                tool:SetAttribute("Cooldown", saved.Cooldown)
                changed = true
            end
            if saved.ThrowSpeed ~= nil and tool:GetAttribute("ThrowSpeed") ~= saved.ThrowSpeed then
                tool:SetAttribute("ThrowSpeed", saved.ThrowSpeed)
                changed = true
            end
            return changed
        end

        local function refreshEquippedWeaponController()
            local now = tick()
            if now - lastLiveWeaponBuffReequip < 0.75 then
                return
            end
            local character = LocalPlayer.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local tool = findEquippedTool()
            if not character or not humanoid or not tool then
                return
            end

            lastLiveWeaponBuffReequip = now
            task.defer(function()
                if not tool or not tool.Parent or not humanoid.Parent then
                    return
                end
                pcall(function()
                    humanoid:UnequipTools()
                end)
                task.wait(0.05)
                if tool and tool.Parent and humanoid.Parent then
                    pcall(function()
                        humanoid:EquipTool(tool)
                    end)
                end
            end)
        end

        applyLiveWeaponBuff = function(refreshEquipped)
            local anyChanged = false
            forEachLocalTool(function(tool)
                if liveWeaponBuffEnabled then
                    if applyLiveWeaponBuffToTool(tool) then
                        anyChanged = true
                    end
                elseif restoreLiveWeaponBuffToTool(tool) then
                    anyChanged = true
                end
            end)
            if refreshEquipped and anyChanged then
                refreshEquippedWeaponController()
            end
        end

        local function startLiveWeaponBuffWatcher()
            if liveWeaponBuffWatcherStarted then
                return
            end
            liveWeaponBuffWatcherStarted = true
            local function hookToolContainer(container, label)
                if not container then
                    return
                end
                connectSafe(container.ChildAdded, "LiveWeaponBuffToolAdded" .. tostring(label), function(child)
                    if not liveWeaponBuffEnabled or not child:IsA("Tool") then
                        return
                    end
                    task.defer(function()
                        applyLiveWeaponBuff(true)
                    end)
                end)
                connectSafe(
                    container.DescendantAdded,
                    "LiveWeaponBuffToolDescendant" .. tostring(label),
                    function(child)
                        if not liveWeaponBuffEnabled then
                            return
                        end
                        local tool = child and child:FindFirstAncestorOfClass("Tool")
                        if tool then
                            task.defer(function()
                                applyLiveWeaponBuff(false)
                            end)
                        end
                    end
                )
            end
            connectSafe(RunService.Heartbeat, "LiveWeaponBuffScan", function()
                if not liveWeaponBuffEnabled then
                    return
                end
                local now = tick()
                if now - lastLiveWeaponBuffScan < 0.12 then
                    return
                end
                lastLiveWeaponBuffScan = now
                applyLiveWeaponBuff(false)
            end)
            connectSafe(LocalPlayer.CharacterAdded, "LiveWeaponBuffCharacter", function()
                task.wait(0.25)
                hookToolContainer(LocalPlayer.Character, "Character")
                if liveWeaponBuffEnabled then
                    applyLiveWeaponBuff(true)
                end
            end)
            hookToolContainer(
                LocalPlayer:FindFirstChildOfClass("Backpack") or LocalPlayer:FindFirstChild("Backpack"),
                "Backpack"
            )
            if LocalPlayer.Character then
                hookToolContainer(LocalPlayer.Character, "Character")
            end
        end

        rememberCleanup(function()
            liveWeaponBuffEnabled = false
            applyLiveWeaponBuff(true)
        end)

        local abilitySliders = {}
        local percentKeys = {
            SprintBoost = true,
            SoulReapSpeedBoost = true,
            ShootSpeedBuff = true,
            ThrowSpeedBuff = true,
            PropellerJumpBoost = true,
        }
        local function addAbilitySlider(id, title, key, minValue, maxValue, rounding)
            local default = defaults[key]
            if type(default) ~= "number" then
                return
            end
            local percent = percentKeys[key] == true
            abilitySliders[key] = Tabs.Abilities:AddSlider(id, {
                Title = title,
                Default = percent and default * 100 or default,
                Min = minValue,
                Max = maxValue,
                Rounding = rounding,
                Callback = function(value)
                    local number = tonumber(value)
                    if number then
                        setGameAbilityValue(key, percent and number / 100 or number)
                        if applyLiveWeaponBuff and (key == "ShootSpeedBuff" or key == "ThrowSpeedBuff") then
                            applyLiveWeaponBuff(true)
                        end
                    end
                end,
            })
        end

        Tabs.Abilities:AddParagraph({ Title = "Sprint", Content = "" })
        addAbilitySlider("GameSprintTime", "Duration", "SprintTime", 0, 20, 2)
        addAbilitySlider("GameSprintCooldown", "Cooldown", "SprintCooldown", 0, 60, 2)
        addAbilitySlider("GameSprintBoost", "Speed Boost (%)", "SprintBoost", 0, 300, 0)

        Tabs.Abilities:AddParagraph({ Title = "Soul Reap", Content = "" })
        addAbilitySlider("GameSoulLifetime", "Soul Lifetime", "SoulLifetime", 0, 30, 2)
        addAbilitySlider("GameSoulReapTime", "Effect Duration", "SoulReapTime", 0, 20, 2)
        addAbilitySlider("GameSoulReapSpeed", "Speed Boost (%)", "SoulReapSpeedBoost", 0, 300, 0)
        addAbilitySlider("GameSoulReapCombatDelay", "Combat Delay", "SoulReapCombatDelay", 0, 10, 2)

        local tagsModule = ReplicatedStorage:FindFirstChild("Modules")
            and ReplicatedStorage.Modules:FindFirstChild("Tags")
        local okTags, gameTags = pcall(function()
            return tagsModule and require(tagsModule)
        end)
        local soulPromptTag = (okTags and type(gameTags) == "table" and gameTags.SOUL_PROMPT) or "SoulPrompt"
        local soulReapCharacterTag = (okTags and type(gameTags) == "table" and gameTags.SOUL_REAP_CHARACTER)
            or "SoulReapCharacter"
        local speedControllerModule = abilityFolder:FindFirstChild("SpeedController")
        local combatDisabledModule = abilityFolder:FindFirstChild("CombatDisabledStateController")
        local okSpeedController, speedController = pcall(function()
            return speedControllerModule and require(speedControllerModule)
        end)
        local okCombatDisabled, combatDisabledController = pcall(function()
            return combatDisabledModule and require(combatDisabledModule)
        end)
        local instantSoulReapEnabled = false
        local instantSoulReapDelay = 0
        local instantSoulReapStarted = false
        local instantSoulReapQueued = setmetatable({}, { __mode = "k" })

        local function getAliveLocalCharacter()
            local character = LocalPlayer.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if not character or not humanoid or humanoid.Health <= 0 then
                return nil
            end
            return character
        end

        local function isLocalSoulPrompt(prompt)
            if not prompt or not prompt:IsA("ProximityPrompt") then
                return false
            end
            if prompt:GetAttribute("PlayerId") ~= LocalPlayer.UserId then
                return false
            end
            if not prompt:IsDescendantOf(Workspace) then
                return false
            end
            local character = getAliveLocalCharacter()
            if not character then
                return false
            end
            if CollectionService:HasTag(character, soulReapCharacterTag) then
                return false
            end
            return true
        end

        local function applySoulReapDirectly(prompt)
            if not isLocalSoulPrompt(prompt) then
                return
            end
            if not okSpeedController or type(speedController) ~= "function" then
                return
            end
            if
                not okCombatDisabled
                or type(combatDisabledController) ~= "table"
                or type(combatDisabledController.Activate) ~= "function"
            then
                return
            end

            local character = getAliveLocalCharacter()
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if not character or not humanoid then
                return
            end

            local soulModel = prompt.Parent and prompt.Parent.Parent
            if soulModel then
                pcall(function()
                    soulModel:Destroy()
                end)
            end

            local cleanupSpeed
            pcall(function()
                cleanupSpeed = speedController(humanoid, tonumber(gameAbilityConfig.SoulReapSpeedBoost) or 0.6)
            end)

            CollectionService:AddTag(character, soulReapCharacterTag)

            local cleanupCombat
            pcall(function()
                cleanupCombat = combatDisabledController.Activate(character)
            end)

            task.spawn(function()
                task.wait(math.max(0, tonumber(gameAbilityConfig.SoulReapTime) or 3))
                if type(cleanupSpeed) == "function" then
                    pcall(cleanupSpeed)
                end
                if character and character.Parent then
                    pcall(function()
                        CollectionService:RemoveTag(character, soulReapCharacterTag)
                    end)
                end
                task.wait(math.max(0, tonumber(gameAbilityConfig.SoulReapCombatDelay) or 0.35))
                if type(cleanupCombat) == "function" then
                    pcall(cleanupCombat)
                end
            end)
        end

        local function fireSoulPrompt(prompt)
            if not isLocalSoulPrompt(prompt) then
                return
            end
            pcall(function()
                prompt.Enabled = true
            end)

            local fired = false
            if type(fireproximityprompt) == "function" then
                fired = pcall(fireproximityprompt, prompt)
            end
            if not fired then
                pcall(function()
                    prompt:InputHoldBegin()
                    task.wait(math.max(tonumber(prompt.HoldDuration) or 0, 0.03))
                    prompt:InputHoldEnd()
                end)
            end
            task.delay(0.12, function()
                local character = getAliveLocalCharacter()
                if character and not CollectionService:HasTag(character, soulReapCharacterTag) then
                    applySoulReapDirectly(prompt)
                end
            end)
        end

        local function queueSoulPrompt(prompt)
            if not instantSoulReapEnabled or instantSoulReapQueued[prompt] then
                return
            end
            if not isLocalSoulPrompt(prompt) then
                return
            end
            instantSoulReapQueued[prompt] = true
            task.spawn(function()
                local delayTime = tonumber(instantSoulReapDelay) or 0
                if delayTime > 0 then
                    task.wait(delayTime)
                end
                if instantSoulReapEnabled then
                    fireSoulPrompt(prompt)
                end
            end)
        end

        local function scanSoulPrompts()
            local ok, tagged = pcall(function()
                return CollectionService:GetTagged(soulPromptTag)
            end)
            if ok and type(tagged) == "table" then
                for _, prompt in ipairs(tagged) do
                    queueSoulPrompt(prompt)
                end
            end
        end

        local function startInstantSoulReap()
            if instantSoulReapStarted then
                scanSoulPrompts()
                return
            end
            instantSoulReapStarted = true
            connectSafe(
                CollectionService:GetInstanceAddedSignal(soulPromptTag),
                "InstantSoulReapPrompt",
                queueSoulPrompt
            )
            connectSafe(LocalPlayer.CharacterAdded, "InstantSoulReapCharacter", function()
                task.wait(0.25)
                if instantSoulReapEnabled then
                    scanSoulPrompts()
                end
            end)
            scanSoulPrompts()
        end

        Tabs.Abilities:AddParagraph({
            Title = "Instant Reap",
            Content = "Automatically triggers your Soul Reap prompt after a kill. Set delay to 0 for instant mobile-friendly reaps.",
        })
        Tabs.Abilities:AddToggle("InstantSoulReap", {
            Title = "Instant Soul Reap",
            Default = false,
            Callback = function(value)
                instantSoulReapEnabled = value == true
                if instantSoulReapEnabled then
                    startInstantSoulReap()
                end
            end,
        })
        Tabs.Abilities:AddSlider("InstantSoulReapDelay", {
            Title = "Reap Delay",
            Default = 0,
            Min = 0,
            Max = 10,
            Rounding = 2,
            Callback = function(value)
                instantSoulReapDelay = math.max(0, tonumber(value) or 0)
            end,
        })

        Tabs.Abilities:AddParagraph({
            Title = "Weapon Buff",
            Content = "Enable live apply if you want the buff to affect normal shooting/throwing while using other features like HBE.",
        })
        Tabs.Abilities:AddToggle("LiveWeaponBuff", {
            Title = "Apply Weapon Buff To Tools",
            Default = false,
            Callback = function(value)
                liveWeaponBuffEnabled = value == true
                startLiveWeaponBuffWatcher()
                applyLiveWeaponBuff(true)
                Fluent:Notify({
                    Title = "Weapon Buff",
                    Content = liveWeaponBuffEnabled and "Applied to live tools." or "Restored live tool stats.",
                    Duration = 3,
                })
            end,
        })
        Tabs.Abilities:AddButton({
            Title = "Refresh Current Weapon Buff",
            Description = "Re-applies buff and re-equips your current tool once.",
            Callback = function()
                applyLiveWeaponBuff(true)
                Fluent:Notify({
                    Title = "Weapon Buff",
                    Content = "Refreshed current weapon.",
                    Duration = 2,
                })
            end,
        })
        addAbilitySlider("GameShootSpeedBuff", "Gun Speed Buff (%)", "ShootSpeedBuff", 0, 300, 0)
        addAbilitySlider("GameThrowSpeedBuff", "Knife Speed Buff (%)", "ThrowSpeedBuff", 0, 300, 0)

        Tabs.Abilities:AddParagraph({ Title = "Dash / Propeller / Teleport", Content = "" })
        addAbilitySlider("GameDashCooldown", "Dash Cooldown", "DashCooldown", 0, 30, 2)
        addAbilitySlider("GameDashActiveTime", "Dash Active Time", "DashActivatedTime", 0.05, 3, 2)
        addAbilitySlider("GamePropellerBoost", "Propeller Jump Boost (%)", "PropellerJumpBoost", 0, 300, 0)
        addAbilitySlider("GameTeleportCooldown", "Teleport Cooldown", "TeleportCooldown", 0, 60, 2)

        Tabs.Abilities:AddParagraph({ Title = "Shroud", Content = "" })
        addAbilitySlider("GameShroudTime", "Blind Duration", "ShroudTime", 0, 30, 2)
        addAbilitySlider("GameShroudCooldown", "Cooldown", "ShroudCooldown", 0, 30, 2)
        addAbilitySlider("GameShroudSpeed", "Projectile Speed", "ShroudProjectileSpeed", 1, 500, 0)
        addAbilitySlider("GameShroudRange", "Projectile Range", "ShroudProjectileRange", 10, 2000, 0)

        Tabs.Abilities:AddButton({
            Title = "Reset",
            Callback = function()
                for key, value in pairs(defaults) do
                    setGameAbilityValue(key, value)
                    local control = abilitySliders[key]
                    if control and type(control.SetValue) == "function" then
                        control:SetValue(percentKeys[key] and value * 100 or value)
                    end
                end
                applyLiveWeaponBuff(true)
            end,
        })
    end)

    registerFeature("Player", {}, nil, function()
        local AbilityConfig = {
            SprintTime = 2.5,
            SprintCooldown = 15,
            SprintBoost = 0.5,
            DashCooldown = 6,
            DashActivatedTime = 0.25,
            DashPower = 60,
        }

        local portalPart = nil
        local portalEffects = {}
        local teleportCooldown = false
        local portalPlaceCooldown = false
        local TELEPORT_COOLDOWN_TIME = 3
        local PORTAL_PLACE_COOLDOWN_TIME = 1
        local portalEnabled = false
        local portalPlaceSlot, portalTeleportSlot
        local portalInputConnections = {}
        local placePortalKey = Enum.KeyCode.Q
        local teleportKey = Enum.KeyCode.E
        local portalGui = nil

        local currentGui = nil
        local dashSlot = nil
        local sprintSlot = nil
        local dashController = nil
        local sprintController = nil
        local sprintDashInputConnections = {}
        local sprintDashEnabled = false
        local dashEnabled = false
        local sprintEnabled = false
        local dashKey = Enum.KeyCode.Q
        local sprintKey = Enum.KeyCode.E

        local function updateSprintDashEnabled()
            sprintDashEnabled = dashEnabled or sprintEnabled
        end

        local function isMobile()
            return Caps.IsMobile or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
        end

        local function getTouchButtonMetrics()
            local mobile = isMobile()
            local scale = mobile and getDeviceUiScale(0.78, 1) or 1
            local baseSize = mobile and math.floor(60 * scale + 0.5) or 70
            return {
                mobile = mobile,
                scale = scale,
                baseSize = baseSize,
                spacing = mobile and math.floor(8 * scale + 0.5) or 10,
                sideMargin = mobile and math.floor(15 * scale + 0.5) or 15,
                corner = mobile and math.floor(8 * scale + 0.5) or 10,
                stroke = mobile and math.max(1, 1.5 * scale) or 2,
                iconInset = mobile and math.floor(20 * scale + 0.5) or 25,
                emojiText = mobile and math.floor(28 * math.clamp(scale, 0.84, 1) + 0.5) or 32,
                cooldownText = mobile and math.floor(22 * math.clamp(scale, 0.84, 1) + 0.5) or 24,
            }
        end

        local function getVerticalOffset()
            local metrics = getTouchButtonMetrics()
            local spacing = metrics.spacing
            local buttonSize = metrics.baseSize
            local total = 0
            if portalEnabled then
                total += 2
            end
            if dashEnabled then
                total += 1
            end
            if sprintEnabled then
                total += 1
            end

            local offsets = { portalPlace = 0, portalTeleport = 0, dash = 0, sprint = 0 }
            if total <= 0 then
                return offsets
            end

            local index = 0
            local function nextOffset()
                index += 1
                return (index - ((total + 1) / 2)) * (buttonSize + spacing)
            end

            if portalEnabled then
                offsets.portalPlace = nextOffset()
                offsets.portalTeleport = nextOffset()
            end
            if dashEnabled then
                offsets.dash = nextOffset()
            end
            if sprintEnabled then
                offsets.sprint = nextOffset()
            end
            return offsets
        end

        local function updateAllPositions()
            local offsets = getVerticalOffset()
            local metrics = getTouchButtonMetrics()
            local baseSize = metrics.baseSize
            local sideOffset = -(baseSize + metrics.sideMargin)
            if portalPlaceSlot and portalPlaceSlot.Frame then
                portalPlaceSlot.Frame.Position = UDim2.new(1, sideOffset, 0.5, offsets.portalPlace)
            end
            if portalTeleportSlot and portalTeleportSlot.Frame then
                portalTeleportSlot.Frame.Position = UDim2.new(1, sideOffset, 0.5, offsets.portalTeleport)
            end
            if dashSlot and dashSlot.Frame then
                dashSlot.Frame.Position = UDim2.new(1, sideOffset, 0.5, offsets.dash)
            end
            if sprintSlot and sprintSlot.Frame then
                sprintSlot.Frame.Position = UDim2.new(1, sideOffset, 0.5, offsets.sprint)
            end
        end

        local function createSlotUI(screenGui, abilityName, keyRef, yOffset, iconContent, isEmoji)
            local metrics = getTouchButtonMetrics()
            local mobile = metrics.mobile
            local baseSize = metrics.baseSize

            local function keyTextFor(key)
                key = enumFromString(key)
                if typeof(key) == "EnumItem" and tostring(key):find("Enum.KeyCode.", 1, true) then
                    local ok, text = pcall(function()
                        return UserInputService:GetStringForKeyCode(key)
                    end)
                    if ok and text and text ~= "" then
                        return text
                    end
                end
                return tostring(key):gsub("Enum%.KeyCode%.", ""):gsub("Enum%.UserInputType%.", "")
            end

            local function tryCreateGameSlot()
                if isEmoji then
                    return nil
                end
                local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
                local abilityGui = playerGui and playerGui:FindFirstChild("AbilitySlot")
                local abilityFrame = abilityGui and abilityGui:FindFirstChild("Frame")
                local template = abilityFrame and abilityFrame:FindFirstChild("Entry")
                if not template then
                    return nil
                end

                local entry = template:Clone()
                entry.Name = abilityName .. "Slot"
                entry.Visible = true
                entry.Size = UDim2.fromOffset(baseSize, baseSize)
                entry.Position = UDim2.new(1, -(baseSize + metrics.sideMargin), 0.5, yOffset)
                entry.AnchorPoint = Vector2.new(0, 0.5)
                entry.Active = true
                entry.Parent = screenGui
                registerAbilityInputBlocker(entry)

                local contentFrame = entry:FindFirstChild("Frame", true)
                local cooldownFrame = entry:FindFirstChild("Cooldown", true)
                local cooldownText = cooldownFrame and cooldownFrame:FindFirstChild("TextLabel", true)
                local keyLabel = contentFrame and contentFrame:FindFirstChild("KeyBind", true)
                local gamepadIcon = entry:FindFirstChild("GamepadButtonIcon", true)
                local icon = contentFrame and contentFrame:FindFirstChild("Icon", true)
                if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
                    icon.Image = iconContent
                end
                if keyLabel and keyLabel:IsA("TextLabel") then
                    keyLabel.Text = keyTextFor(keyRef)
                    keyLabel.Visible = not mobile
                end
                if gamepadIcon and gamepadIcon:IsA("ImageLabel") then
                    local ok, image = pcall(function()
                        return UserInputService:GetImageForKeyCode(enumFromString(keyRef))
                    end)
                    if ok and image then
                        gamepadIcon.Image = image
                    end
                    gamepadIcon.Visible = UserInputService.GamepadEnabled
                end
                if contentFrame then
                    contentFrame.Visible = true
                end
                if cooldownFrame then
                    cooldownFrame.Visible = false
                end

                local button = Instance.new("TextButton")
                button.Name = "ClickButton"
                button.Size = UDim2.fromScale(1, 1)
                button.BackgroundTransparency = 1
                button.Text = ""
                button.Active = true
                button.AutoButtonColor = false
                button.ZIndex = 100
                pcall(function()
                    button.Modal = true
                end)
                button.Parent = entry
                button.InputBegan:Connect(markAbilityInput)
                button.InputEnded:Connect(markAbilityInput)
                button.MouseButton1Down:Connect(markAbilityInput)

                local cooldownConn = nil
                return {
                    Frame = entry,
                    Button = button,
                    KeyLabel = keyLabel,
                    UpdateKey = function(newKey)
                        if keyLabel and keyLabel:IsA("TextLabel") then
                            keyLabel.Text = keyTextFor(newKey)
                        end
                        if gamepadIcon and gamepadIcon:IsA("ImageLabel") then
                            local ok, image = pcall(function()
                                return UserInputService:GetImageForKeyCode(enumFromString(newKey))
                            end)
                            if ok and image then
                                gamepadIcon.Image = image
                            end
                        end
                    end,
                    Activate = function()
                        if cooldownConn then
                            cooldownConn:Disconnect()
                            cooldownConn = nil
                        end
                        if contentFrame then
                            contentFrame.Visible = true
                        end
                        if cooldownFrame then
                            cooldownFrame.Visible = false
                        end
                        if cooldownText then
                            cooldownText.Text = ""
                        end
                    end,
                    Deactivate = function(cdTime)
                        cdTime = tonumber(cdTime) or 0
                        if cooldownConn then
                            cooldownConn:Disconnect()
                            cooldownConn = nil
                        end
                        if cdTime <= 0 then
                            if contentFrame then
                                contentFrame.Visible = true
                            end
                            if cooldownFrame then
                                cooldownFrame.Visible = false
                            end
                            if cooldownText then
                                cooldownText.Text = ""
                            end
                            return
                        end
                        if contentFrame then
                            contentFrame.Visible = false
                        end
                        if cooldownFrame then
                            cooldownFrame.Visible = true
                        end
                        local startTime = tick()
                        cooldownConn = RunService.Heartbeat:Connect(function()
                            local remaining = cdTime - (tick() - startTime)
                            if remaining <= 0 then
                                if cooldownConn then
                                    cooldownConn:Disconnect()
                                    cooldownConn = nil
                                end
                                if contentFrame then
                                    contentFrame.Visible = true
                                end
                                if cooldownFrame then
                                    cooldownFrame.Visible = false
                                end
                                if cooldownText then
                                    cooldownText.Text = ""
                                end
                            elseif cooldownText then
                                cooldownText.Text = tostring(math.clamp(math.ceil(remaining), 0, math.ceil(cdTime)))
                            end
                        end)
                    end,
                    Destroy = function()
                        if cooldownConn then
                            cooldownConn:Disconnect()
                            cooldownConn = nil
                        end
                        entry:Destroy()
                    end,
                }
            end

            local gameSlot = tryCreateGameSlot()
            if gameSlot then
                return gameSlot
            end

            local frame = Instance.new("Frame")
            frame.Name = abilityName .. "Slot"
            frame.Size = UDim2.new(0, baseSize, 0, baseSize)
            frame.Position = UDim2.new(1, -(baseSize + metrics.sideMargin), 0.5, yOffset)
            frame.AnchorPoint = Vector2.new(0, 0.5)
            frame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
            frame.BorderSizePixel = 0
            frame.Active = true
            frame.Parent = screenGui
            registerAbilityInputBlocker(frame)

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, metrics.corner)
            corner.Parent = frame

            local stroke = Instance.new("UIStroke")
            stroke.Color = isEmoji and Color3.fromRGB(100, 200, 255) or Color3.fromRGB(70, 70, 70)
            stroke.Thickness = metrics.stroke
            stroke.Parent = frame

            if isEmoji then
                local icon = Instance.new("TextLabel")
                icon.Name = "Icon"
                icon.Size = UDim2.new(0, baseSize - metrics.iconInset, 0, baseSize - metrics.iconInset)
                icon.Position = UDim2.new(0.5, 0, 0.5, 0)
                icon.AnchorPoint = Vector2.new(0.5, 0.5)
                icon.BackgroundTransparency = 1
                icon.Text = iconContent
                icon.TextSize = metrics.emojiText
                icon.TextColor3 = Color3.fromRGB(100, 200, 255)
                icon.Font = Enum.Font.GothamBold
                icon.Parent = frame
            else
                local icon = Instance.new("ImageLabel")
                icon.Name = "Icon"
                icon.Size = UDim2.new(0, baseSize - metrics.iconInset, 0, baseSize - metrics.iconInset)
                icon.Position = UDim2.new(0.5, 0, 0.5, 0)
                icon.AnchorPoint = Vector2.new(0.5, 0.5)
                icon.BackgroundTransparency = 1
                icon.Image = iconContent
                icon.ScaleType = Enum.ScaleType.Fit
                icon.Parent = frame
            end

            local keyLabel
            if not mobile then
                keyLabel = Instance.new("TextLabel")
                keyLabel.Name = "Key"
                keyLabel.Size = UDim2.new(0, 22, 0, 22)
                keyLabel.Position = UDim2.new(0, 4, 0, 4)
                keyLabel.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
                keyLabel.BorderSizePixel = 0
                keyLabel.Text = keyTextFor(keyRef)
                keyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                keyLabel.Font = Enum.Font.GothamBold
                keyLabel.TextSize = 13
                keyLabel.Parent = frame
                local kc = Instance.new("UICorner")
                kc.CornerRadius = UDim.new(0, 5)
                kc.Parent = keyLabel
            end

            local cooldownText = Instance.new("TextLabel")
            cooldownText.Name = "CooldownText"
            cooldownText.Size = UDim2.new(1, 0, 1, 0)
            cooldownText.BackgroundTransparency = 1
            cooldownText.Text = ""
            cooldownText.TextColor3 = Color3.fromRGB(255, 255, 255)
            cooldownText.Font = Enum.Font.GothamBold
            cooldownText.TextSize = metrics.cooldownText
            cooldownText.ZIndex = 10
            cooldownText.Parent = frame

            local cooldownFill = Instance.new("Frame")
            cooldownFill.Name = "CooldownFill"
            cooldownFill.Size = UDim2.new(1, 0, 1, 0)
            cooldownFill.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            cooldownFill.BackgroundTransparency = 0.7
            cooldownFill.BorderSizePixel = 0
            cooldownFill.Visible = false
            cooldownFill.ZIndex = 5
            cooldownFill.Parent = frame
            local fc = Instance.new("UICorner")
            fc.CornerRadius = UDim.new(0, metrics.corner)
            fc.Parent = cooldownFill

            local button = Instance.new("TextButton")
            button.Name = "ClickButton"
            button.Size = UDim2.new(1, 0, 1, 0)
            button.BackgroundTransparency = 1
            button.Text = ""
            button.Active = true
            button.AutoButtonColor = false
            button.ZIndex = 15
            button.Parent = frame
            pcall(function()
                button.Modal = true
            end)
            button.InputBegan:Connect(markAbilityInput)
            button.InputEnded:Connect(markAbilityInput)
            button.MouseButton1Down:Connect(markAbilityInput)

            local cooldownConn = nil

            local slotAPI = {
                Frame = frame,
                Button = button,
                KeyLabel = keyLabel,
                UpdateKey = function(newKey)
                    if keyLabel then
                        keyLabel.Text = keyTextFor(newKey)
                    end
                end,
                Activate = function(activeTime)
                    stroke.Color = Color3.fromRGB(100, 200, 255)
                    cooldownFill.Visible = false
                    cooldownText.Text = ""
                end,
                Deactivate = function(cdTime)
                    stroke.Color = Color3.fromRGB(200, 100, 100)
                    cooldownFill.Visible = true
                    if cooldownConn then
                        cooldownConn:Disconnect()
                    end
                    local startT = tick()
                    local endT = startT + cdTime
                    cooldownConn = RunService.Heartbeat:Connect(function()
                        local remaining = endT - tick()
                        if remaining <= 0 then
                            cooldownConn:Disconnect()
                            cooldownConn = nil
                            stroke.Color = isEmoji and Color3.fromRGB(100, 200, 255) or Color3.fromRGB(70, 70, 70)
                            cooldownFill.Visible = false
                            cooldownText.Text = ""
                        else
                            cooldownText.Text = string.format("%.1f", remaining)
                            cooldownFill.BackgroundTransparency = 0.3 + (0.4 * (1 - remaining / cdTime))
                        end
                    end)
                end,
                Destroy = function()
                    if cooldownConn then
                        cooldownConn:Disconnect()
                        cooldownConn = nil
                    end
                    if frame then
                        frame:Destroy()
                    end
                end,
            }
            return slotAPI
        end

        -- Portal
        local function createPortalEffect(position)
            local portal = Instance.new("Part")
            portal.Name = "Portal"
            portal.Size = Vector3.new(6, 0.5, 6)
            portal.CFrame = CFrame.new(position)
            portal.Anchored = true
            portal.CanCollide = false
            portal.Material = Enum.Material.Neon
            portal.Color = Color3.fromRGB(100, 200, 255)
            portal.Transparency = 0.3
            portal.Parent = Workspace
            local pl2 = Instance.new("PointLight")
            pl2.Color = Color3.fromRGB(100, 200, 255)
            pl2.Brightness = 3
            pl2.Range = 15
            pl2.Parent = portal
            local spinPart = Instance.new("Part")
            spinPart.Name = "SpinEffect"
            spinPart.Size = Vector3.new(7, 0.3, 7)
            spinPart.CFrame = portal.CFrame
            spinPart.Anchored = true
            spinPart.CanCollide = false
            spinPart.Material = Enum.Material.Neon
            spinPart.Color = Color3.fromRGB(150, 220, 255)
            spinPart.Transparency = 0.5
            spinPart.Parent = portal
            local mesh = Instance.new("SpecialMesh")
            mesh.MeshType = Enum.MeshType.Cylinder
            mesh.Parent = portal
            local mesh2 = Instance.new("SpecialMesh")
            mesh2.MeshType = Enum.MeshType.Cylinder
            mesh2.Parent = spinPart
            local pAttach = Instance.new("Attachment")
            pAttach.Parent = portal
            local particles = Instance.new("ParticleEmitter")
            particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
            particles.Color = ColorSequence.new(Color3.fromRGB(100, 200, 255))
            particles.LightEmission = 1
            particles.Size = NumberSequence.new(0.5)
            particles.Transparency =
                NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
            particles.Lifetime = NumberRange.new(1, 2)
            particles.Rate = 50
            particles.Speed = NumberRange.new(5, 10)
            particles.SpreadAngle = Vector2.new(180, 180)
            particles.Parent = pAttach
            local spinConn
            spinConn = RunService.Heartbeat:Connect(function()
                if not portal or not portal.Parent then
                    if spinConn then
                        spinConn:Disconnect()
                    end
                    return
                end
                spinPart.CFrame = spinPart.CFrame * CFrame.Angles(0, math.rad(2), 0)
                local pulse = 0.3 + math.sin(tick() * 3) * 0.2
                portal.Transparency = pulse
                spinPart.Transparency = pulse + 0.2
            end)
            table.insert(portalEffects, { portal = portal, connection = spinConn })
            return portal
        end

        local function clearPortal()
            if portalPart then
                portalPart:Destroy()
                portalPart = nil
            end
            for _, e in ipairs(portalEffects) do
                if e.connection then
                    e.connection:Disconnect()
                end
                if e.portal then
                    e.portal:Destroy()
                end
            end
            portalEffects = {}
        end

        local function playTeleportAnimation(humanoid)
            if not humanoid then
                return
            end
            local animator = humanoid:FindFirstChild("Animator")
            if not animator then
                return
            end
            local character = humanoid.Parent
            local rootPart = character and character:FindFirstChild("HumanoidRootPart")
            if not rootPart then
                return
            end
            local te = Instance.new("Part")
            te.Size = Vector3.new(4, 8, 4)
            te.CFrame = rootPart.CFrame
            te.Anchored = true
            te.CanCollide = false
            te.Material = Enum.Material.Neon
            te.Color = Color3.fromRGB(100, 200, 255)
            te.Transparency = 0.5
            te.Parent = Workspace
            local mesh = Instance.new("SpecialMesh")
            mesh.MeshType = Enum.MeshType.Sphere
            mesh.Parent = te
            TweenService:Create(te, TweenInfo.new(0.5), { Transparency = 1, Size = Vector3.new(8, 12, 8) }):Play()
            Debris:AddItem(te, 0.5)
        end

        local function placePortal()
            if not portalEnabled or not LocalPlayer:GetAttribute("Match") or portalPlaceCooldown then
                return
            end
            local character = LocalPlayer.Character
            if not character then
                return
            end
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if not rootPart then
                return
            end
            clearPortal()
            portalPlaceCooldown = true
            local tpSound = ReplicatedStorage:FindFirstChild("Ability")
                and ReplicatedStorage.Ability:FindFirstChild("TeleportSound")
            if tpSound then
                local s = tpSound:Clone()
                s.Parent = rootPart
                s:Play()
                Debris:AddItem(s, s.TimeLength)
            end
            portalPart = createPortalEffect(rootPart.Position + Vector3.new(0, -2.5, 0))
            playTeleportAnimation(safeGetHumanoid(character))
            if portalPlaceSlot then
                portalPlaceSlot.Deactivate(PORTAL_PLACE_COOLDOWN_TIME)
            end
            task.delay(PORTAL_PLACE_COOLDOWN_TIME, function()
                portalPlaceCooldown = false
            end)
        end

        local function teleportToPortal(slotRef)
            if not portalEnabled or not LocalPlayer:GetAttribute("Match") or teleportCooldown then
                return
            end
            if not portalPart or not portalPart.Parent then
                return
            end
            local character = LocalPlayer.Character
            if not character then
                return
            end
            local humanoid = safeGetHumanoid(character)
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if not humanoid or not rootPart then
                return
            end
            playTeleportAnimation(humanoid)
            local tpSound = ReplicatedStorage:FindFirstChild("Ability")
                and ReplicatedStorage.Ability:FindFirstChild("TeleportSound")
            if tpSound then
                local s = tpSound:Clone()
                s.Parent = rootPart
                s:Play()
                Debris:AddItem(s, s.TimeLength)
            end
            task.wait(0.2)
            rootPart.CFrame = portalPart.CFrame + Vector3.new(0, 3, 0)
            playTeleportAnimation(humanoid)
            if tpSound then
                local s2 = tpSound:Clone()
                s2.Parent = rootPart
                s2:Play()
                Debris:AddItem(s2, s2.TimeLength)
            end
            clearPortal()
            teleportCooldown = true
            if slotRef then
                slotRef.Deactivate(TELEPORT_COOLDOWN_TIME)
            end
            task.delay(TELEPORT_COOLDOWN_TIME, function()
                teleportCooldown = false
            end)
        end

        local function createPortalUI()
            local sg = Instance.new("ScreenGui")
            sg.Name = "PortalAbilityUI"
            sg.ResetOnSpawn = false
            sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            sg.IgnoreGuiInset = false
            sg.DisplayOrder = 999997
            local offsets = getVerticalOffset()
            portalPlaceSlot = createSlotUI(
                sg,
                "PlacePortal",
                placePortalKey,
                offsets.portalPlace,
                "http://www.roblox.com/asset/?id=15203104398",
                false
            )
            portalTeleportSlot = createSlotUI(
                sg,
                "Teleport",
                teleportKey,
                offsets.portalTeleport,
                "http://www.roblox.com/asset/?id=15386331894",
                false
            )
            sg.Parent = LocalPlayer:WaitForChild("PlayerGui")
            return sg
        end

        local function initializePortal()
            portalGui = createPortalUI()
            table.insert(
                portalInputConnections,
                UserInputService.InputBegan:Connect(function(input, processed)
                    if not portalEnabled or not LocalPlayer:GetAttribute("Match") then
                        return
                    end
                    if processed or UserInputService:GetFocusedTextBox() then
                        return
                    end
                    if input.KeyCode == placePortalKey then
                        placePortal()
                    elseif input.KeyCode == teleportKey then
                        teleportToPortal(portalTeleportSlot)
                    end
                end)
            )
            table.insert(
                portalInputConnections,
                portalPlaceSlot.Button.MouseButton1Click:Connect(function()
                    placePortal()
                end)
            )
            table.insert(
                portalInputConnections,
                portalTeleportSlot.Button.MouseButton1Click:Connect(function()
                    teleportToPortal(portalTeleportSlot)
                end)
            )
        end

        local function cleanupPortal()
            clearPortal()
            teleportCooldown = false
            portalPlaceCooldown = false
            for _, c in ipairs(portalInputConnections) do
                c:Disconnect()
            end
            portalInputConnections = {}
            if portalPlaceSlot and portalPlaceSlot.Destroy then
                portalPlaceSlot.Destroy()
            end
            if portalTeleportSlot and portalTeleportSlot.Destroy then
                portalTeleportSlot.Destroy()
            end
            if portalGui then
                portalGui:Destroy()
                portalGui = nil
            end
            portalPlaceSlot = nil
            portalTeleportSlot = nil
        end

        -- Sprint and dash
        local function createSpeedController(humanoidRef, speedBoost)
            local base = humanoidRef.WalkSpeed
            humanoidRef.WalkSpeed = base * (1 + speedBoost)
            return function()
                humanoidRef.WalkSpeed = base
            end
        end

        local function createSpeedTrailEffect(rootPart)
            local attach = Instance.new("Attachment")
            attach.Name = "SpeedTrailAttachment"
            attach.Parent = rootPart
            local trail = Instance.new("Trail")
            trail.Attachment0 = attach
            trail.Attachment1 = attach
            trail.Color = ColorSequence.new(Color3.fromRGB(100, 200, 255))
            trail.Lifetime = 0.5
            trail.MinLength = 0
            trail.FaceCamera = true
            trail.LightEmission = 1
            trail.Transparency =
                NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
            trail.WidthScale = NumberSequence.new(1)
            trail.Parent = attach
            return attach
        end

        local function createDashControllerFunc(humanoidRef, slotRef)
            local parent = humanoidRef.Parent
            local hrp = parent:WaitForChild("HumanoidRootPart")
            local animator = humanoidRef:WaitForChild("Animator")
            local rootAttachment = hrp:WaitForChild("RootAttachment")
            local dashAnimation = ReplicatedStorage:FindFirstChild("Ability")
                and ReplicatedStorage.Ability:FindFirstChild("DashAnimation")
            local dashAnim = dashAnimation and animator:LoadAnimation(dashAnimation)
            if dashAnim then
                dashAnim:GetMarkerReachedSignal("Completed"):Connect(function()
                    dashAnim:AdjustSpeed(0)
                end)
            end
            local isActive = false
            return {
                Activate = function()
                    if not dashEnabled or isActive or hrp.Anchored then
                        return
                    end
                    isActive = true
                    if liveWeaponBuffEnabled and applyLiveWeaponBuff then
                        applyLiveWeaponBuff(false)
                    end
                    if dashAnim then
                        dashAnim:Play(nil, nil, 1)
                    end
                    local lv = hrp.CFrame.LookVector
                    local lvel = Instance.new("LinearVelocity")
                    lvel.VectorVelocity = lv * AbilityConfig.DashPower
                    lvel.MaxForce = 50000
                    lvel.Attachment0 = rootAttachment
                    lvel.Parent = hrp
                    Debris:AddItem(lvel, 0.1)
                    task.delay(0.03, function()
                        if liveWeaponBuffEnabled and applyLiveWeaponBuff then
                            applyLiveWeaponBuff(false)
                        end
                    end)
                    if slotRef then
                        slotRef.Activate(AbilityConfig.DashActivatedTime)
                    end
                    task.delay(AbilityConfig.DashActivatedTime, function()
                        if dashAnim then
                            dashAnim:Stop()
                        end
                        if liveWeaponBuffEnabled and applyLiveWeaponBuff then
                            applyLiveWeaponBuff(false)
                        end
                        if slotRef then
                            slotRef.Deactivate(AbilityConfig.DashCooldown)
                        end
                        task.delay(AbilityConfig.DashCooldown, function()
                            isActive = false
                        end)
                    end)
                end,
            }
        end

        local function createSprintControllerFunc(humanoidRef, slotRef)
            local isActive = nil
            return {
                Activate = function()
                    if not sprintEnabled or isActive then
                        return
                    end
                    local parent = humanoidRef.Parent
                    if not parent then
                        return
                    end
                    local hrp = parent:FindFirstChild("HumanoidRootPart")
                    if not hrp then
                        return
                    end
                    local trailAttach = createSpeedTrailEffect(hrp)
                    isActive = true
                    local cleanupSpeed = createSpeedController(humanoidRef, AbilityConfig.SprintBoost)
                    if slotRef then
                        slotRef.Activate(AbilityConfig.SprintTime)
                    end
                    task.delay(AbilityConfig.SprintTime, function()
                        if slotRef then
                            slotRef.Deactivate(AbilityConfig.SprintCooldown)
                        end
                        cleanupSpeed()
                        if trailAttach then
                            trailAttach:Destroy()
                        end
                        task.delay(AbilityConfig.SprintCooldown, function()
                            isActive = nil
                        end)
                    end)
                end,
            }
        end

        local function createAbilityUI()
            local sg = Instance.new("ScreenGui")
            sg.Name = "CustomAbilityUI"
            sg.ResetOnSpawn = false
            sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            sg.IgnoreGuiInset = false
            sg.DisplayOrder = 999997
            local offsets = getVerticalOffset()
            if dashEnabled then
                dashSlot = createSlotUI(
                    sg,
                    "Dash",
                    dashKey,
                    offsets.dash,
                    "http://www.roblox.com/asset/?id=17605583293",
                    false
                )
            end
            if sprintEnabled then
                sprintSlot = createSlotUI(
                    sg,
                    "Sprint",
                    sprintKey,
                    offsets.sprint,
                    "http://www.roblox.com/asset/?id=13318881043",
                    false
                )
            end
            sg.Parent = LocalPlayer:WaitForChild("PlayerGui")
            return sg
        end

        local function cleanupSprintDash()
            for _, c in ipairs(sprintDashInputConnections) do
                c:Disconnect()
            end
            sprintDashInputConnections = {}
            if dashController and dashController.Destroy then
                pcall(function()
                    dashController.Destroy()
                end)
            end
            if sprintController and sprintController.Destroy then
                pcall(function()
                    sprintController.Destroy()
                end)
            end
            if dashSlot and dashSlot.Destroy then
                dashSlot.Destroy()
            end
            if sprintSlot and sprintSlot.Destroy then
                sprintSlot.Destroy()
            end
            if currentGui then
                currentGui:Destroy()
                currentGui = nil
            end
            dashSlot = nil
            sprintSlot = nil
            dashController = nil
            sprintController = nil
        end

        local function initializeSprintDash()
            local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
            local humanoid = character:WaitForChild("Humanoid")
            local rootPart = character:WaitForChild("HumanoidRootPart")
            currentGui = createAbilityUI()
            if dashEnabled and dashSlot then
                dashController = createDashControllerFunc(humanoid, dashSlot)
            end
            if sprintEnabled and sprintSlot then
                sprintController = createSprintControllerFunc(humanoid, sprintSlot)
            end
            table.insert(
                sprintDashInputConnections,
                UserInputService.InputBegan:Connect(function(input, processed)
                    if not sprintDashEnabled or processed or UserInputService:GetFocusedTextBox() then
                        return
                    end
                    if rootPart.Anchored then
                        return
                    end
                    if input.KeyCode == dashKey and dashController then
                        dashController.Activate()
                    elseif input.KeyCode == sprintKey and sprintController then
                        sprintController.Activate()
                    end
                end)
            )
            if dashSlot and dashController then
                table.insert(
                    sprintDashInputConnections,
                    dashSlot.Button.MouseButton1Click:Connect(function()
                        if not rootPart.Anchored then
                            dashController.Activate()
                        end
                    end)
                )
            end
            if sprintSlot and sprintController then
                table.insert(
                    sprintDashInputConnections,
                    sprintSlot.Button.MouseButton1Click:Connect(function()
                        if not rootPart.Anchored then
                            sprintController.Activate()
                        end
                    end)
                )
            end
        end

        local function checkAndManageMatch()
            local inMatch = LocalPlayer:GetAttribute("Match")
            if inMatch and sprintDashEnabled then
                if not currentGui then
                    initializeSprintDash()
                end
            else
                if currentGui then
                    cleanupSprintDash()
                end
            end
            if inMatch and portalEnabled then
                if not portalGui then
                    initializePortal()
                end
            else
                if portalGui then
                    cleanupPortal()
                end
            end
            updateAllPositions()
        end

        Tabs.Player:AddParagraph({ Title = "teleportie", Content = "" })

        Tabs.Player:AddToggle("PortalToggle", { Title = "Teleport", Default = false }):OnChanged(function()
            portalEnabled = Options.PortalToggle.Value
            checkAndManageMatch()
        end)

        Tabs.Player:AddKeybind("PlacePortalKey", {
            Title = "Place Portal Key",
            Mode = "Toggle",
            Default = "Q",
            ChangedCallback = function(New)
                placePortalKey = New
                if portalPlaceSlot and portalPlaceSlot.UpdateKey then
                    portalPlaceSlot.UpdateKey(New)
                end
            end,
        })

        Tabs.Player:AddKeybind("TeleportKey", {
            Title = "Teleport Key",
            Mode = "Toggle",
            Default = "E",
            ChangedCallback = function(New)
                teleportKey = New
                if portalTeleportSlot and portalTeleportSlot.UpdateKey then
                    portalTeleportSlot.UpdateKey(New)
                end
            end,
        })

        Tabs.Player:AddSlider("CustomTeleportCooldownSlider", {
            Title = "Teleport Cooldown",
            Default = TELEPORT_COOLDOWN_TIME,
            Min = 0,
            Max = 30,
            Rounding = 1,
            Callback = function(Value)
                TELEPORT_COOLDOWN_TIME = tonumber(Value) or TELEPORT_COOLDOWN_TIME
            end,
        })

        Tabs.Player:AddParagraph({ Title = "Movement", Content = "Dash & sprint unlocker" })

        Tabs.Player:AddToggle("UnlockDashToggle", { Title = "Unlock Dash", Default = false }):OnChanged(function()
            dashEnabled = Options.UnlockDashToggle.Value
            updateSprintDashEnabled()
            if currentGui then
                cleanupSprintDash()
            end
            checkAndManageMatch()
        end)

        Tabs.Player:AddToggle("UnlockSprintToggle", { Title = "Unlock Sprint", Default = false }):OnChanged(function()
            sprintEnabled = Options.UnlockSprintToggle.Value
            updateSprintDashEnabled()
            if currentGui then
                cleanupSprintDash()
            end
            checkAndManageMatch()
        end)

        Tabs.Player:AddKeybind("DashKey", {
            Title = "Dash Key",
            Mode = "Toggle",
            Default = "Q",
            ChangedCallback = function(New)
                dashKey = New
                if dashSlot and dashSlot.UpdateKey then
                    dashSlot.UpdateKey(New)
                end
            end,
        })

        Tabs.Player:AddKeybind("SprintKey", {
            Title = "Sprint Key",
            Mode = "Toggle",
            Default = "E",
            ChangedCallback = function(New)
                sprintKey = New
                if sprintSlot and sprintSlot.UpdateKey then
                    sprintSlot.UpdateKey(New)
                end
            end,
        })

        Tabs.Player:AddSlider("CustomDashCooldownSlider", {
            Title = "Dash Cooldown",
            Default = 6,
            Min = 0,
            Max = 30,
            Rounding = 1,
            Callback = function(Value)
                AbilityConfig.DashCooldown = tonumber(Value) or AbilityConfig.DashCooldown
            end,
        })

        Tabs.Player:AddSlider("CustomDashPowerSlider", {
            Title = "Dash Power",
            Default = AbilityConfig.DashPower,
            Min = 20,
            Max = 120,
            Rounding = 0,
            Callback = function(Value)
                AbilityConfig.DashPower = tonumber(Value) or AbilityConfig.DashPower
            end,
        })

        Tabs.Player:AddSlider("CustomSprintDurationSlider", {
            Title = "Sprint Duration",
            Default = AbilityConfig.SprintTime,
            Min = 0.5,
            Max = 10,
            Rounding = 1,
            Callback = function(Value)
                AbilityConfig.SprintTime = tonumber(Value) or AbilityConfig.SprintTime
            end,
        })

        Tabs.Player:AddSlider("CustomSprintCooldownSlider", {
            Title = "Sprint Cooldown",
            Default = 15,
            Min = 0,
            Max = 60,
            Rounding = 1,
            Callback = function(Value)
                AbilityConfig.SprintCooldown = tonumber(Value) or AbilityConfig.SprintCooldown
            end,
        })

        Tabs.Player:AddSlider("CustomSprintBoostSlider", {
            Title = "Sprint Boost",
            Default = AbilityConfig.SprintBoost * 100,
            Min = 5,
            Max = 150,
            Rounding = 0,
            Callback = function(Value)
                AbilityConfig.SprintBoost = (tonumber(Value) or 50) / 100
            end,
        })

        connectSafe(LocalPlayer.CharacterAdded, "Player CharacterAdded", function()
            if portalEnabled then
                cleanupPortal()
            end
            if sprintDashEnabled then
                cleanupSprintDash()
            end
            task.wait(0.1)
            checkAndManageMatch()
        end)

        connectSafe(LocalPlayer:GetAttributeChangedSignal("Match"), "Player MatchChanged", function()
            checkAndManageMatch()
        end)
        rememberCleanup(function()
            portalEnabled = false
            sprintDashEnabled = false
            cleanupPortal()
            cleanupSprintDash()
        end)
    end)

    if InterfaceManager then
        pcall(function()
            InterfaceManager:SetLibrary(Fluent)
            InterfaceManager:SetFolder("ZephyrUnified")
            InterfaceManager:BuildInterfaceSection(Tabs.Settings)
        end)
    end

    if SaveManager and Caps.HasFiles then
        pcall(function()
            SaveManager:SetLibrary(Fluent)
            SaveManager:IgnoreThemeSettings()
            SaveManager:SetIgnoreIndexes({})
            SaveManager:SetFolder(Caps.IsMobile and "ZephyrUnified/mobile" or "ZephyrUnified/desktop")
            SaveManager:BuildConfigSection(Tabs.Settings)
            SaveManager:LoadAutoloadConfig()
        end)
    else
        recordSkip("Config Saving", "missing file functions")
        Tabs.Settings:AddParagraph({
            Title = "Config Saving",
            Content = "Skipped because this executor does not expose readfile/writefile/isfile.",
        })
    end

    Tabs.Settings:AddParagraph({
        Title = "Loaded Features",
        Content = "Device: "
            .. (Caps.IsMobile and "Mobile" or "PC")
            .. " ("
            .. tostring(Caps.DeviceModeSource)
            .. ") | Drawing: "
            .. tostring(Caps.HasDrawing)
            .. " | Hooks: "
            .. tostring(Caps.HasExecutorHooks),
    })

    Tabs.Settings:AddButton({
        Title = "Reset Device Choice",
        Callback = function()
            clearDevicePreference()
            Fluent:Notify({
                Title = "Device Choice Reset",
                Content = "Restart Zephyr to choose Android/Mobile or PC again.",
                Duration = 4,
            })
        end,
    })

    if #SkippedFeatures > 0 then
        local text = table.concat(SkippedFeatures, "\n")
        if #text > 1800 then
            text = text:sub(1, 1800) .. "\n..."
        end
        Tabs.Settings:AddParagraph({ Title = "Skipped Features", Content = text })
    end

    Tabs.Settings:AddButton({
        Title = "Unload Zephyr",
        Callback = function()
            if type(G.ZephyrUnifiedUnload) == "function" then
                G.ZephyrUnifiedUnload()
            end
        end,
    })

    Window:SelectTab(1)
end)

if not zephyrOk then
    pcall(function()
        warn("Zephyr Unified failed. Startup stopped safely.")
    end)
end
