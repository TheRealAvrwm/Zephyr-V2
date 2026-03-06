local function isLuarmorUrl(url)
    return url:match("luarmor") ~= nil
end

local function loadPollutedLoader()
    local success, err = pcall(function()
        local TweenService = game:GetService("TweenService")
        local CoreGui = game:GetService("CoreGui")
        local UserInputService = game:GetService("UserInputService")
        local IsMobile = UserInputService.TouchEnabled

        local ContainerSize = IsMobile and 
            (workspace.CurrentCamera.ViewportSize.Y > workspace.CurrentCamera.ViewportSize.X 
                and UDim2.new(0, 280, 0, 220) 
                or UDim2.new(0, 260, 0, 200)) 
            or UDim2.new(0, 240, 0, 180)

        local Loader = Instance.new("ScreenGui")
        Loader.Name = "PollutedLoader"
        Loader.ResetOnSpawn = false
        Loader.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        
        local protectSuccess = pcall(function()
            if gethui then
                Loader.Parent = gethui()
            elseif syn and syn.protect_gui then
                syn.protect_gui(Loader)
                Loader.Parent = CoreGui
            else
                Loader.Parent = CoreGui
            end
        end)
        
        if not protectSuccess then
            Loader.Parent = CoreGui
        end

        local Shadow = Instance.new("ImageLabel")
        Shadow.Size = UDim2.new(0, ContainerSize.X.Offset + 40, 0, ContainerSize.Y.Offset + 40)
        Shadow.Position = UDim2.new(0.5, 0, 0.5, 0)
        Shadow.AnchorPoint = Vector2.new(0.5, 0.5)
        Shadow.BackgroundTransparency = 1
        Shadow.ImageTransparency = 1
        Shadow.Image = "rbxassetid://7912134082"
        Shadow.ImageColor3 = Color3.fromRGB(0, 255, 0)
        Shadow.ScaleType = Enum.ScaleType.Slice
        Shadow.SliceCenter = Rect.new(80, 80, 80, 80)
        Shadow.Parent = Loader

        local Container = Instance.new("Frame")
        Container.Size = ContainerSize
        Container.Position = UDim2.new(0.5, 0, 0.5, 0)
        Container.AnchorPoint = Vector2.new(0.5, 0.5)
        Container.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        Container.BorderSizePixel = 0
        Container.Parent = Loader

        local UICorner = Instance.new("UICorner")
        UICorner.CornerRadius = UDim.new(0, 12)
        UICorner.Parent = Container

        local UIGradient = Instance.new("UIGradient")
        UIGradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(48, 183, 0)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(33, 125, 0)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 83, 0))
        })
        UIGradient.Rotation = 45
        UIGradient.Parent = Container

        local ToxicBubbles = Instance.new("Frame")
        ToxicBubbles.Size = UDim2.new(1, 0, 1, 0)
        ToxicBubbles.BackgroundTransparency = 0.8
        ToxicBubbles.BackgroundColor3 = Color3.fromRGB(144, 255, 96)
        ToxicBubbles.ClipsDescendants = true
        ToxicBubbles.Parent = Container

        local BubbleCorner = Instance.new("UICorner")
        BubbleCorner.CornerRadius = UDim.new(0, 12)
        BubbleCorner.Parent = ToxicBubbles

        local BubbleGradient = Instance.new("UIGradient")
        BubbleGradient.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.8),
            NumberSequenceKeypoint.new(0.5, 0.9),
            NumberSequenceKeypoint.new(1, 1)
        })
        BubbleGradient.Rotation = 90
        BubbleGradient.Parent = ToxicBubbles

        local LogoSize = IsMobile and UDim2.new(0, 100, 0, 100) or UDim2.new(0, 80, 0, 80)
        local Logo = Instance.new("ImageLabel")
        Logo.Size = LogoSize
        Logo.Position = UDim2.new(0.48, 0, 0.44, 0)
        Logo.AnchorPoint = Vector2.new(0.5, 0.5)
        Logo.BackgroundTransparency = 1
        Logo.Image = "rbxassetid://72493279214448"
        Logo.ImageColor3 = Color3.fromRGB(255, 255, 255)
        Logo.ImageTransparency = 1
        Logo.Parent = Container

        local Glow = Instance.new("ImageLabel")
        Glow.Size = UDim2.new(1.5, 0, 1.5, 0)
        Glow.Position = UDim2.new(0.5, 0, 0.5, 0)
        Glow.AnchorPoint = Vector2.new(0.5, 0.5)
        Glow.BackgroundTransparency = 1
        Glow.Image = "rbxassetid://89033969723631"
        Glow.ImageColor3 = Color3.fromRGB(144, 255, 96)
        Glow.ImageTransparency = 1
        Glow.Parent = Logo

        local BarContainer = Instance.new("Frame")
        local barSize = IsMobile and UDim2.new(0.7, 0, 0, 3) or UDim2.new(0.8, 0, 0, 2)
        BarContainer.Size = barSize
        BarContainer.Position = UDim2.new(0.5, 0, 0.9, 0)
        BarContainer.AnchorPoint = Vector2.new(0.5, 0.5)
        BarContainer.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        BarContainer.BackgroundTransparency = 1
        BarContainer.Parent = Container

        local Bar = Instance.new("Frame")
        Bar.Size = UDim2.new(0, 0, 1, 0)
        Bar.BackgroundColor3 = Color3.fromRGB(144, 255, 96)
        Bar.BackgroundTransparency = 1
        Bar.Parent = BarContainer

        local activeTweens = {}
        local animationRunning = true

        local function playIntro()
            Container.Size = UDim2.new(0, ContainerSize.X.Offset - 20, 0, ContainerSize.Y.Offset - 20)
            Container.BackgroundTransparency = 1
            Shadow.ImageTransparency = 1

            table.insert(activeTweens, TweenService:Create(Shadow, TweenInfo.new(0.8, Enum.EasingStyle.Back), {
                ImageTransparency = 0.5
            }))
            activeTweens[#activeTweens]:Play()

            table.insert(activeTweens, TweenService:Create(Container, TweenInfo.new(0.8, Enum.EasingStyle.Back), {
                Size = ContainerSize,
                BackgroundTransparency = 0
            }))
            activeTweens[#activeTweens]:Play()

            local logoStartSize = UDim2.new(0, LogoSize.X.Offset - 20, 0, LogoSize.Y.Offset - 20)
            Logo.Size = logoStartSize

            table.insert(activeTweens, TweenService:Create(Logo, TweenInfo.new(0.8, Enum.EasingStyle.Back), {
                Size = LogoSize,
                ImageTransparency = 0
            }))
            activeTweens[#activeTweens]:Play()

            table.insert(activeTweens, TweenService:Create(Glow, TweenInfo.new(1), {
                ImageTransparency = 0.8
            }))
            activeTweens[#activeTweens]:Play()

            table.insert(activeTweens, TweenService:Create(Bar, TweenInfo.new(0.7), {
                BackgroundTransparency = 0,
                Size = UDim2.new(1, 0, 1, 0)
            }))
            activeTweens[#activeTweens]:Play()

            task.spawn(function()
                while animationRunning and Loader.Parent do
                    local tween = TweenService:Create(BubbleGradient, TweenInfo.new(2, Enum.EasingStyle.Linear), {
                        Rotation = BubbleGradient.Rotation - 360
                    })
                    tween:Play()
                    task.wait(2)
                end
            end)

            task.spawn(function()
                while animationRunning and Loader.Parent do
                    local tween = TweenService:Create(UIGradient, TweenInfo.new(2, Enum.EasingStyle.Linear), {
                        Rotation = UIGradient.Rotation + 360
                    })
                    tween:Play()
                    task.wait(2)
                end
            end)
        end

        local function playOutro()
            animationRunning = false
            
            for _, tween in ipairs(activeTweens) do
                pcall(function() tween:Cancel() end)
            end
            activeTweens = {}

            TweenService:Create(Shadow, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
                ImageTransparency = 1
            }):Play()

            TweenService:Create(Container, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
                Size = UDim2.new(0, ContainerSize.X.Offset - 20, 0, ContainerSize.Y.Offset - 20),
                BackgroundTransparency = 1
            }):Play()

            TweenService:Create(Logo, TweenInfo.new(0.6), {
                Size = UDim2.new(0, LogoSize.X.Offset - 20, 0, LogoSize.Y.Offset - 20),
                ImageTransparency = 1
            }):Play()

            TweenService:Create(Glow, TweenInfo.new(0.6), {
                ImageTransparency = 1
            }):Play()

            TweenService:Create(Bar, TweenInfo.new(0.5), {
                BackgroundTransparency = 1
            }):Play()

            task.wait(0.7)
            pcall(function() Loader:Destroy() end)
        end

        playIntro()
        task.wait(2)
        playOutro()
        task.wait(0.1)
    end)
    
    if not success then
        warn("Loader error:", err)
    end
end

local function loadZephyrLoader()
    local success, err = pcall(function()
        local TweenService = game:GetService("TweenService")
        local CoreGui = game:GetService("CoreGui")
        local UserInputService = game:GetService("UserInputService")
        local IsMobile = UserInputService.TouchEnabled

        local ContainerSize
        if IsMobile then
            if workspace.CurrentCamera.ViewportSize.Y > workspace.CurrentCamera.ViewportSize.X then
                ContainerSize = UDim2.new(0, 280, 0, 220)
            else
                ContainerSize = UDim2.new(0, 260, 0, 200)
            end
        else
            ContainerSize = UDim2.new(0, 240, 0, 180)
        end

        local Loader = Instance.new("ScreenGui")
        Loader.Name = "ZephyrLoader"
        Loader.ResetOnSpawn = false
        Loader.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        
        local protectSuccess = pcall(function()
            if gethui then
                Loader.Parent = gethui()
            elseif syn and syn.protect_gui then
                syn.protect_gui(Loader)
                Loader.Parent = CoreGui
            else
                Loader.Parent = CoreGui
            end
        end)
        
        if not protectSuccess then
            Loader.Parent = CoreGui
        end

        local Shadow = Instance.new("ImageLabel")
        Shadow.Size = UDim2.new(0, ContainerSize.X.Offset + 40, 0, ContainerSize.Y.Offset + 40)
        Shadow.Position = UDim2.new(0.5, 0, 0.5, 0)
        Shadow.AnchorPoint = Vector2.new(0.5, 0.5)
        Shadow.BackgroundTransparency = 1
        Shadow.ImageTransparency = 1
        Shadow.Image = "rbxassetid://7912134082"
        Shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
        Shadow.ScaleType = Enum.ScaleType.Slice
        Shadow.SliceCenter = Rect.new(80, 80, 80, 80)
        Shadow.Parent = Loader

        local Container = Instance.new("Frame")
        Container.Size = ContainerSize
        Container.Position = UDim2.new(0.5, 0, 0.5, 0)
        Container.AnchorPoint = Vector2.new(0.5, 0.5)
        Container.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        Container.BorderSizePixel = 0
        Container.Parent = Loader

        local UICorner = Instance.new("UICorner")
        UICorner.CornerRadius = UDim.new(0, 12)
        UICorner.Parent = Container

        local UIGradient = Instance.new("UIGradient")
        UIGradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 25, 25)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 15, 15))
        })
        UIGradient.Rotation = 45
        UIGradient.Parent = Container

        local Shine = Instance.new("Frame")
        Shine.Size = UDim2.new(1, 0, 1, 0)
        Shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        Shine.BackgroundTransparency = 0.9
        Shine.Parent = Container

        local ShineCorner = Instance.new("UICorner")
        ShineCorner.CornerRadius = UDim.new(0, 12)
        ShineCorner.Parent = Shine

        local ShineGradient = Instance.new("UIGradient")
        ShineGradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255))
        })
        ShineGradient.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.4, 0.97),
            NumberSequenceKeypoint.new(0.5, 0.95),
            NumberSequenceKeypoint.new(0.6, 0.97),
            NumberSequenceKeypoint.new(1, 1)
        })
        ShineGradient.Parent = Shine

        local LogoSize = IsMobile and UDim2.new(0, 100, 0, 100) or UDim2.new(0, 80, 0, 80)
        local Logo = Instance.new("ImageLabel")
        Logo.Size = LogoSize
        Logo.Position = UDim2.new(0.48, 0, 0.44, 0)
        Logo.AnchorPoint = Vector2.new(0.5, 0.5)
        Logo.BackgroundTransparency = 1
        Logo.Image = "rbxassetid://77613174656421"
        Logo.ImageColor3 = Color3.fromRGB(255, 255, 255)
        Logo.ImageTransparency = 1
        Logo.Parent = Container

        local Glow = Instance.new("ImageLabel")
        Glow.Size = UDim2.new(1.5, 0, 1.5, 0)
        Glow.Position = UDim2.new(0.5, 0, 0.5, 0)
        Glow.AnchorPoint = Vector2.new(0.5, 0.5)
        Glow.BackgroundTransparency = 1
        Glow.Image = "rbxassetid://89033969723631"
        Glow.ImageColor3 = Color3.fromRGB(255, 255, 255)
        Glow.ImageTransparency = 1
        Glow.Parent = Logo

        local LoadingText = Instance.new("TextLabel")
        LoadingText.Size = UDim2.new(1, 0, 0, 20)
        LoadingText.Position = UDim2.new(0, 0, IsMobile and 0.82 or 0.8, 0)
        LoadingText.Font = Enum.Font.GothamBold
        LoadingText.Text = "ZEPHYR"
        LoadingText.TextColor3 = Color3.fromRGB(255, 255, 255)
        LoadingText.TextSize = IsMobile and 18 or 16
        LoadingText.BackgroundTransparency = 1
        LoadingText.TextTransparency = 1
        LoadingText.Parent = Container

        local BarContainer = Instance.new("Frame")
        local barSize = IsMobile and UDim2.new(0.7, 0, 0, 3) or UDim2.new(0.8, 0, 0, 2)
        BarContainer.Size = barSize
        BarContainer.Position = UDim2.new(0.5, 0, 0.9, 0)
        BarContainer.AnchorPoint = Vector2.new(0.5, 0.5)
        BarContainer.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        BarContainer.BackgroundTransparency = 1
        BarContainer.Parent = Container

        local Bar = Instance.new("Frame")
        Bar.Size = UDim2.new(0, 0, 1, 0)
        Bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        Bar.BackgroundTransparency = 1
        Bar.Parent = BarContainer

        local activeTweens = {}
        local animationRunning = true

        local function playIntro()
            Container.Size = UDim2.new(0, ContainerSize.X.Offset - 20, 0, ContainerSize.Y.Offset - 20)
            Container.BackgroundTransparency = 1
            Shadow.ImageTransparency = 1
            
            table.insert(activeTweens, TweenService:Create(Shadow, TweenInfo.new(0.8, Enum.EasingStyle.Back), {
                ImageTransparency = 0.5
            }))
            activeTweens[#activeTweens]:Play()
            
            table.insert(activeTweens, TweenService:Create(Container, TweenInfo.new(0.8, Enum.EasingStyle.Back), {
                Size = ContainerSize,
                BackgroundTransparency = 0
            }))
            activeTweens[#activeTweens]:Play()
            
            local logoStartSize = UDim2.new(0, LogoSize.X.Offset - 20, 0, LogoSize.Y.Offset - 20)
            Logo.Size = logoStartSize
            
            table.insert(activeTweens, TweenService:Create(Logo, TweenInfo.new(0.8, Enum.EasingStyle.Back), {
                Size = LogoSize,
                ImageTransparency = 0
            }))
            activeTweens[#activeTweens]:Play()
            
            table.insert(activeTweens, TweenService:Create(Glow, TweenInfo.new(1), {
                ImageTransparency = 0.8
            }))
            activeTweens[#activeTweens]:Play()
            
            table.insert(activeTweens, TweenService:Create(LoadingText, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, 0.2), {
                TextTransparency = 0
            }))
            activeTweens[#activeTweens]:Play()
            
            table.insert(activeTweens, TweenService:Create(BarContainer, TweenInfo.new(0.7), {
                BackgroundTransparency = 0
            }))
            activeTweens[#activeTweens]:Play()
            
            table.insert(activeTweens, TweenService:Create(Bar, TweenInfo.new(0.7), {
                BackgroundTransparency = 0,
                Size = UDim2.new(1, 0, 1, 0)
            }))
            activeTweens[#activeTweens]:Play()
            
            task.spawn(function()
                while animationRunning and Loader.Parent do
                    local tween = TweenService:Create(ShineGradient, TweenInfo.new(2), {
                        Offset = Vector2.new(1, 0)
                    })
                    tween:Play()
                    task.wait(2)
                    ShineGradient.Offset = Vector2.new(-1, 0)
                    task.wait(0.1)
                end
            end)
        end

        local function playOutro()
            animationRunning = false
            
            for _, tween in ipairs(activeTweens) do
                pcall(function() tween:Cancel() end)
            end
            activeTweens = {}
            
            TweenService:Create(Shadow, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
                ImageTransparency = 1
            }):Play()
            
            TweenService:Create(Container, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
                Size = UDim2.new(0, ContainerSize.X.Offset - 20, 0, ContainerSize.Y.Offset - 20),
                BackgroundTransparency = 1
            }):Play()
            
            TweenService:Create(Logo, TweenInfo.new(0.6), {
                Size = UDim2.new(0, LogoSize.X.Offset - 20, 0, LogoSize.Y.Offset - 20),
                ImageTransparency = 1
            }):Play()
            
            TweenService:Create(Glow, TweenInfo.new(0.6), {
                ImageTransparency = 1
            }):Play()
            
            TweenService:Create(LoadingText, TweenInfo.new(0.5), {
                TextTransparency = 1
            }):Play()
            
            TweenService:Create(BarContainer, TweenInfo.new(0.5), {
                BackgroundTransparency = 1
            }):Play()
            
            TweenService:Create(Bar, TweenInfo.new(0.5), {
                BackgroundTransparency = 1
            }):Play()
            
            task.wait(0.7)
            pcall(function() Loader:Destroy() end)
        end

        playIntro()
        task.wait(2)
        playOutro()
        task.wait(0.1)
    end)
    
    if not success then
        warn("Loader error:", err)
    end
end

local scriptInfo = {
    [4348829796] = {url = 'https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/ZephyrV2', isLuarmor = false},
    [7709344486] = {url = 'https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/Games/StealABrainrot', isLuarmor = false},
    [7344582593] = {url = 'https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/Games/DieOfDealth', isLuarmor = false},
    [5995470825] = {url = 'https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/Hypershot.lua', isLuarmor = false},
    [6035872082] = {url = 'https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/Games/Rivals.lua', isLuarmor = false},
    [9251333102] = {url = 'https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/Games/Invade%20the%20World', isLuarmor = false},
    [1176784616] = {url = 'https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/Games/TDSLoadup.lua', isLuarmor = false},
    [8353962342] = {url = "https://api.luarmor.net/files/v3/loaders/0f8751b134191b33890f77ac3be49dbc.lua", isLuarmor = true},
    [126884695634066] = {url = "https://api.luarmor.net/files/v3/loaders/22c850869e9e8c3cdc71aedbb632dac6.lua", isLuarmor = true},
    [79546208627805] = {url = "https://api.luarmor.net/files/v3/loaders/7b49a212373561851fa3bc6b9e4a45c0.lua", isLuarmor = true},
    [8316902627] = {url = "https://api.luarmor.net/files/v3/loaders/3e0e5bada3453caa36246a325f2345f3.lua", isLuarmor = true},
    [6701277882] = {url = "https://api.luarmor.net/files/v3/loaders/b9162d4ef4823b2af2f93664cf9ec393.lua", isLuarmor = true},
    [7750955984] = {url = "https://api.luarmor.net/files/v3/loaders/7b5caf0fbbd276ba9747f231e47c0b1a.lua", isLuarmor = true},
    [8066283370] = {url = "https://api.luarmor.net/files/v3/loaders/59181ae583fe3b51a97d7d7e769d857e.lua", isLuarmor = true},
    [7882829745] = {url = "https://api.luarmor.net/files/v3/loaders/c29a3e11688e5806e228f2c67a36149d.lua", isLuarmor = true},
    [7264587281] = {url = "https://api.luarmor.net/files/v3/loaders/7203478c42c592bee50a25c8056cfb74.lua", isLuarmor = true},
    [7671049560] = {url = "https://api.luarmor.net/files/v3/loaders/ecfcccea43f60fa4c46009f854c06a52.lua", isLuarmor = true},
    [8144728961] = {url = "https://api.luarmor.net/files/v4/loaders/cf7d7d4cd57d21138be3f35d4442557a.lua", isLuarmor = true},
    [7394964165] = {url = "https://api.luarmor.net/files/v4/loaders/83dfede315f32da25e5d660d5d9629cb.lua", isLuarmor = true},
}

task.spawn(function()
    local success, err = pcall(function()
        local Players = game:GetService("Players")
        local player = Players.LocalPlayer
        local universeId = game.GameId

        local info = scriptInfo[universeId] or {url = 'https://raw.githubusercontent.com/TheRealAvrwm/Zephyr-V2/refs/heads/main/Games/Universal.lua', isLuarmor = false}
        
        if info.isLuarmor then
            loadPollutedLoader()
        else
            loadZephyrLoader()
        end
        
        task.wait(0.5)
        
        local scriptSuccess, scriptErr = pcall(function()
            loadstring(game:HttpGet(info.url))()
        end)
        
        if not scriptSuccess then
        end
    end)
    
    if not success then
    end
end)
