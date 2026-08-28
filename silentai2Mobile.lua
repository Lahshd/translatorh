-- Services & Dependencies
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local CoreGui = (gethui and gethui()) or game:GetService("CoreGui") or LocalPlayer:WaitForChild("PlayerGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local request = request or http.request or http_request

-- Chat System Detection
local isLegacyChat = false
local DefaultServerEvents = ReplicatedStorage:FindFirstChild("DefaultServerEvents")
if DefaultServerEvents and DefaultServerEvents:FindFirstChild("SayMessageRequest") then
    isLegacyChat = true
end

-- === CONFIG & STATE ===
local OPENROUTER_API_KEY = "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"
local OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

local currentMode = 1 -- 1: OwO, 2: Tsundere, 3: Yandere
local botEnabled = false
local isKeyValid = false
local isProcessing = false

-- Key Validation
local function checkKeyValidity(key)
    if not key or key == "" or key:find("PASTE_YOUR") then return false end
    if key:sub(1, 9) == "sk-or-v1-" and #key >= 40 then return true end
    return false
end
isKeyValid = checkKeyValidity(OPENROUTER_API_KEY)

-- Dynamic Memory Storage
local PlayerMemory = {} -- Format: ["displayname_lowercase"] = "custom notes"

-- Personality Themes
local Themes = {
    [1] = {
        Name = "OwO Mode",
        Primary = Color3.fromRGB(255, 145, 195),
        Bg = Color3.fromRGB(32, 25, 36),
        SystemPrompt = "You are an ultra-cute anime furry bot named Silent. Respond to the message in OwO style with stutters. Keep your response under 15 words so it fits in Roblox chat."
    },
    [2] = {
        Name = "Tsundere Mode",
        Primary = Color3.fromRGB(240, 60, 100),
        Bg = Color3.fromRGB(36, 22, 28),
        SystemPrompt = "You are a flustered anime Tsundere bot named Silent. Respond with denial, 'b-baka!', and sass. Keep your response under 15 words so it fits in Roblox chat."
    },
    [3] = {
        Name = "Yandere Mode",
        Primary = Color3.fromRGB(160, 35, 75),
        Bg = Color3.fromRGB(22, 18, 26),
        SystemPrompt = "You are a dark, possessive Yandere bot named Silent. Respond with intense affection and subtle threats. Keep your response under 15 words so it fits in Roblox chat."
    }
}

-- === GUI SETUP (MOBILE & CONSOLE RESPONSIVE) ===
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SilentAIBotGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = CoreGui

-- Mobile Floating Toggle Button
local MobileOpenBtn = Instance.new("TextButton")
MobileOpenBtn.Name = "MobileToggle"
MobileOpenBtn.Size = UDim2.new(0, 48, 0, 48)
MobileOpenBtn.Position = UDim2.new(0, 15, 0.15, 0)
MobileOpenBtn.BackgroundColor3 = Themes[1].Bg
MobileOpenBtn.Text = "🌸 AI"
MobileOpenBtn.TextColor3 = Themes[1].Primary
MobileOpenBtn.Font = Enum.Font.GothamBold
MobileOpenBtn.TextSize = 14
MobileOpenBtn.Active = true
MobileOpenBtn.Selectable = true
MobileOpenBtn.Parent = ScreenGui

local MobileOpenCorner = Instance.new("UICorner")
MobileOpenCorner.CornerRadius = UDim.new(1, 0)
MobileOpenCorner.Parent = MobileOpenBtn

local MobileOpenStroke = Instance.new("UIStroke")
MobileOpenStroke.Thickness = 2
MobileOpenStroke.Color = Themes[1].Primary
MobileOpenStroke.Parent = MobileOpenBtn

-- Main Container Frame
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0.85, 0, 0.45, 0)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.BackgroundColor3 = Themes[1].Bg
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local MainSizeConstraint = Instance.new("UISizeConstraint")
MainSizeConstraint.MaxSize = Vector2.new(560, 240)
MainSizeConstraint.MinSize = Vector2.new(300, 200)
MainSizeConstraint.Parent = MainFrame

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 14)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Thickness = 2
MainStroke.Color = Themes[1].Primary
MainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
MainStroke.Parent = MainFrame

-- Mobile Toggle Connection
MobileOpenBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Left Section Container
local LeftContainer = Instance.new("Frame")
LeftContainer.Size = UDim2.new(0.58, 0, 1, 0)
LeftContainer.BackgroundTransparency = 1
LeftContainer.Parent = MainFrame

-- Header
local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(0.9, 0, 0.18, 0)
TitleLabel.Position = UDim2.new(0.05, 0, 0.04, 0)
TitleLabel.Text = "🌸 Silent AI (OwO Mode)"
TitleLabel.TextColor3 = Themes[1].Primary
TitleLabel.BackgroundTransparency = 1
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextScaled = true
TitleLabel.Parent = LeftContainer

-- Status Label
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(0.9, 0, 0.1, 0)
StatusLabel.Position = UDim2.new(0.05, 0, 0.22, 0)
StatusLabel.Text = "Listening for: 'hey silent...'"
StatusLabel.TextColor3 = Color3.fromRGB(160, 150, 175)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextScaled = true
StatusLabel.Parent = LeftContainer

-- Slider Section
local SliderLabel = Instance.new("TextLabel")
SliderLabel.Size = UDim2.new(0.9, 0, 0.1, 0)
SliderLabel.Position = UDim2.new(0.05, 0, 0.38, 0)
SliderLabel.Text = "PERSONALITY MATRIX"
SliderLabel.TextColor3 = Color3.fromRGB(140, 130, 150)
SliderLabel.BackgroundTransparency = 1
SliderLabel.Font = Enum.Font.GothamBold
SliderLabel.TextScaled = true
SliderLabel.TextXAlignment = Enum.TextXAlignment.Left
SliderLabel.Parent = LeftContainer

local SliderTrack = Instance.new("Frame")
SliderTrack.Size = UDim2.new(0.9, 0, 0.1, 0)
SliderTrack.Position = UDim2.new(0.05, 0, 0.50, 0)
SliderTrack.BackgroundColor3 = Color3.fromRGB(15, 12, 18)
SliderTrack.Active = true
SliderTrack.Parent = LeftContainer

local TrackCorner = Instance.new("UICorner")
TrackCorner.CornerRadius = UDim.new(1, 0)
TrackCorner.Parent = SliderTrack

local SliderKnob = Instance.new("TextButton")
SliderKnob.Size = UDim2.new(0, 24, 1, 4)
SliderKnob.Position = UDim2.new(0, 0, 0.5, -14)
SliderKnob.BackgroundColor3 = Themes[1].Primary
SliderKnob.Text = ""
SliderKnob.Selectable = true
SliderKnob.Parent = SliderTrack

local KnobCorner = Instance.new("UICorner")
KnobCorner.CornerRadius = UDim.new(1, 0)
KnobCorner.Parent = SliderKnob

-- Bot Toggle Button
local BotToggleBtn = Instance.new("TextButton")
BotToggleBtn.Size = UDim2.new(0.9, 0, 0.20, 0)
BotToggleBtn.Position = UDim2.new(0.05, 0, 0.68, 0)
BotToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 35, 50)
BotToggleBtn.Text = "BOT: OFF"
BotToggleBtn.TextColor3 = Color3.fromRGB(160, 150, 170)
BotToggleBtn.Font = Enum.Font.GothamBold
BotToggleBtn.TextScaled = true
BotToggleBtn.Selectable = true
BotToggleBtn.Parent = LeftContainer

local BotToggleCorner = Instance.new("UICorner")
BotToggleCorner.CornerRadius = UDim.new(0, 8)
BotToggleCorner.Parent = BotToggleBtn

-- === RIGHT SIDE (MEMORY PANEL) ===
local MemoryContainer = Instance.new("Frame")
MemoryContainer.Size = UDim2.new(0.38, 0, 0.88, 0)
MemoryContainer.Position = UDim2.new(0.58, 0, 0.06, 0)
MemoryContainer.BackgroundColor3 = Color3.fromRGB(20, 16, 25)
MemoryContainer.Parent = MainFrame

local MemCorner = Instance.new("UICorner")
MemCorner.CornerRadius = UDim.new(0, 10)
MemCorner.Parent = MemoryContainer

local MemTitle = Instance.new("TextLabel")
MemTitle.Size = UDim2.new(0.9, 0, 0.12, 0)
MemTitle.Position = UDim2.new(0.05, 0, 0.04, 0)
MemTitle.Text = "🧠 PLAYER MEMORY"
MemTitle.TextColor3 = Color3.fromRGB(200, 190, 215)
MemTitle.BackgroundTransparency = 1
MemTitle.Font = Enum.Font.GothamBold
MemTitle.TextScaled = true
MemTitle.Parent = MemoryContainer

local NameInput = Instance.new("TextBox")
NameInput.Size = UDim2.new(0.9, 0, 0.18, 0)
NameInput.Position = UDim2.new(0.05, 0, 0.18, 0)
NameInput.PlaceholderText = "Username..."
NameInput.Text = ""
NameInput.BackgroundColor3 = Color3.fromRGB(12, 10, 15)
NameInput.TextColor3 = Color3.fromRGB(255, 255, 255)
NameInput.Font = Enum.Font.Gotham
NameInput.TextSize = 12
NameInput.Selectable = true
NameInput.Parent = MemoryContainer

local NameCorner = Instance.new("UICorner")
NameCorner.CornerRadius = UDim.new(0, 6)
NameCorner.Parent = NameInput

local InfoInput = Instance.new("TextBox")
InfoInput.Size = UDim2.new(0.9, 0, 0.34, 0)
InfoInput.Position = UDim2.new(0.05, 0, 0.39, 0)
InfoInput.PlaceholderText = "Add player facts..."
InfoInput.Text = ""
InfoInput.BackgroundColor3 = Color3.fromRGB(12, 10, 15)
InfoInput.TextColor3 = Color3.fromRGB(255, 255, 255)
InfoInput.TextWrapped = true
InfoInput.Font = Enum.Font.Gotham
InfoInput.TextSize = 12
InfoInput.TextYAlignment = Enum.TextYAlignment.Top
InfoInput.Selectable = true
InfoInput.Parent = MemoryContainer

local InfoCorner = Instance.new("UICorner")
InfoCorner.CornerRadius = UDim.new(0, 6)
InfoCorner.Parent = InfoInput

local SaveMemBtn = Instance.new("TextButton")
SaveMemBtn.Size = UDim2.new(0.9, 0, 0.18, 0)
SaveMemBtn.Position = UDim2.new(0.05, 0, 0.77, 0)
SaveMemBtn.Text = "Save Memory"
SaveMemBtn.BackgroundColor3 = Color3.fromRGB(50, 45, 65)
SaveMemBtn.TextColor3 = Color3.fromRGB(220, 210, 235)
SaveMemBtn.Font = Enum.Font.GothamBold
SaveMemBtn.TextScaled = true
SaveMemBtn.Selectable = true
SaveMemBtn.Parent = MemoryContainer

local SaveCorner = Instance.new("UICorner")
SaveCorner.CornerRadius = UDim.new(0, 6)
SaveCorner.Parent = SaveMemBtn

SaveMemBtn.MouseButton1Click:Connect(function()
    local name = NameInput.Text:lower():gsub("%s+", "")
    local info = InfoInput.Text
    if name ~= "" and info ~= "" then
        PlayerMemory[name] = info
        SaveMemBtn.Text = "Saved!"
        task.delay(1.5, function() SaveMemBtn.Text = "Save Memory" end)
    end
end)

-- Theme Switcher Function
local function applyTheme(modeIndex)
    local theme = Themes[modeIndex]
    local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    
    local titleIcons = {[1] = "🌸 ", [2] = "🎒 ", [3] = "🔪 "}
    TitleLabel.Text = titleIcons[modeIndex] .. "Silent AI (" .. theme.Name .. ")"

    TweenService:Create(MainFrame, tweenInfo, {BackgroundColor3 = theme.Bg}):Play()
    TweenService:Create(MainStroke, tweenInfo, {Color = theme.Primary}):Play()
    TweenService:Create(TitleLabel, tweenInfo, {TextColor3 = theme.Primary}):Play()
    TweenService:Create(SliderKnob, tweenInfo, {BackgroundColor3 = theme.Primary}):Play()
    TweenService:Create(MobileOpenBtn, tweenInfo, {BackgroundColor3 = theme.Bg, TextColor3 = theme.Primary}):Play()
    TweenService:Create(MobileOpenStroke, tweenInfo, {Color = theme.Primary}):Play()
end

-- Fixed Dragging & Touch Slider Logic
local isDragging = false

local function snapSlider(pct)
    local targetMode = 1
    local knobX = 0

    if pct < 0.33 then
        targetMode = 1
        knobX = 0
    elseif pct < 0.66 then
        targetMode = 2
        knobX = 0.5
    else
        targetMode = 3
        knobX = 1
    end

    if currentMode ~= targetMode then
        currentMode = targetMode
        applyTheme(currentMode)
    end

    local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(SliderKnob, tweenInfo, {
        Position = UDim2.new(knobX, knobX == 1 and -24 or (knobX == 0.5 and -12 or 0), 0.5, -14)
    }):Play()
end

local function updateSlider(input)
    local trackPos = SliderTrack.AbsolutePosition.X
    local trackSize = SliderTrack.AbsoluteSize.X
    local mousePos = input.Position.X
    local relativeX = math.clamp(mousePos - trackPos, 0, trackSize)
    snapSlider(relativeX / trackSize)
end

SliderTrack.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isDragging = true
        updateSlider(input)
    end
end)

SliderKnob.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isDragging = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isDragging = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        updateSlider(input)
    end
end)

-- Helper: Find Player Mentions (by full/partial Username or Display Name)
local function getMentionedPlayer(text)
    local lowerText = text:lower()
    for _, player in ipairs(Players:GetPlayers()) do
        local uName = player.Name:lower()
        local dName = player.DisplayName:lower()
        
        if lowerText:find(uName) or lowerText:find(dName) then
            return player
        end
    end
    return nil
end

-- Send Roblox Chat Message
local function sendMessage(message)
    if message == "" then return end
    if isLegacyChat then
        pcall(function() DefaultServerEvents.SayMessageRequest:FireServer(message, "All") end)
    else
        local channel = TextChatService.TextChannels:FindFirstChild("RBXGeneral")
        if channel then
            pcall(function() channel:SendAsync(message) end)
        else
            pcall(function() LocalPlayer:Chat(message) end)
        end
    end
end

-- OpenRouter AI Request with Vision & Context Support
local function queryAI(promptText, senderPlayer, targetPlayer, mode)
    if not request or not isKeyValid then
        return "B-Baka! AI Key missing... (⁠｡⁠･⁠ω⁠･⁠｡⁠)"
    end

    local cleanKey = OPENROUTER_API_KEY:gsub("%s+", "")
    
    -- Build Context Payload
    local contextInfo = "Speaker: " .. senderPlayer.DisplayName .. " (@" .. senderPlayer.Name .. "). "
    
    -- Check Memory Bank for Speaker
    local speakerKey = senderPlayer.DisplayName:lower():gsub("%s+", "")
    if PlayerMemory[speakerKey] then
        contextInfo = contextInfo .. "Speaker Info/Notes: " .. PlayerMemory[speakerKey] .. ". "
    end

    -- Check Mentions & Target Player
    local imageUrl = nil
    if targetPlayer then
        contextInfo = contextInfo .. "Mentioned Player: " .. targetPlayer.DisplayName .. " (@" .. targetPlayer.Name .. "). "
        local targetKey = targetPlayer.DisplayName:lower():gsub("%s+", "")
        if PlayerMemory[targetKey] then
            contextInfo = contextInfo .. "Mentioned Player Notes: " .. PlayerMemory[targetKey] .. ". "
        end
        
        -- Generate Roblox Avatar Image URL
        imageUrl = "https://rbxthumb.com/v1/avatar-headshot?userId=" .. targetPlayer.UserId .. "&width=150&height=150"
    else
        -- Default to speaker's avatar picture
        imageUrl = "https://rbxthumb.com/v1/avatar-headshot?userId=" .. senderPlayer.UserId .. "&width=150&height=150"
    end

    -- Construct Vision & Text Message Object
    local userMessageContent = {
        { type = "text", text = "[Context: " .. contextInfo .. "] Message: " .. promptText }
    }

    if imageUrl then
        table.insert(userMessageContent, {
            type = "image_url",
            image_url = { url = imageUrl }
        })
    end

    local payload = HttpService:JSONEncode({
        model = "openrouter/free",
        messages = {
            { role = "system", content = Themes[mode].SystemPrompt },
            { role = "user", content = userMessageContent }
        }
    })

    local success, response = pcall(function()
        return request({
            Url = OPENROUTER_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Bearer " .. cleanKey,
                ["HTTP-Referer"] = "https://roblox.com",
                ["X-Title"] = "Roblox Silent Bot"
            },
            Body = payload
        })
    end)

    if success and response and response.StatusCode == 200 then
        local dataSuccess, data = pcall(function() return HttpService:JSONDecode(response.Body) end)
        if dataSuccess and data and data.choices and data.choices[1] then
            return data.choices[1].message.content:gsub('^"', ''):gsub('"$', '')
        end
    end

    return "Ah... something went wrong processing that request ♡"
end

-- Central Chat Handler
local function handleIncomingChat(senderPlayer, messageText)
    if not botEnabled or isProcessing then return end
    
    local lowerMsg = messageText:lower()
    local trigger = "hey silent"
    
    if lowerMsg:find(trigger) then
        isProcessing = true
        StatusLabel.Text = "Status: Reading & Thinking..."
        
        local _, endIndex = lowerMsg:find(trigger)
        local userQuery = messageText:sub(endIndex + 1):gsub("^%s+", "")
        if userQuery == "" then userQuery = "Hello!" end
        
        -- Detect Player Mention
        local targetPlayer = getMentionedPlayer(userQuery)

        task.spawn(function()
            local aiResponse = queryAI(userQuery, senderPlayer, targetPlayer, currentMode)
            sendMessage(aiResponse)
            StatusLabel.Text = "Listening for: 'hey silent...'"
            isProcessing = false
        end)
    end
end

-- Chat Listeners Hook
if isLegacyChat then
    local function hookPlayer(player)
        player.Chatted:Connect(function(msg)
            handleIncomingChat(player, msg)
        end)
    end
    Players.PlayerAdded:Connect(hookPlayer)
    for _, player in ipairs(Players:GetPlayers()) do hookPlayer(player) end
else
    local function connectChannel(channel)
        if channel:IsA("TextChannel") then
            channel.MessageReceived:Connect(function(textChatMessage)
                if textChatMessage.TextSource then
                    local senderPlayer = Players:GetPlayerByUserId(textChatMessage.TextSource.UserId)
                    if senderPlayer then
                        handleIncomingChat(senderPlayer, textChatMessage.Text)
                    end
                end
            end)
        end
    end

    local TextChannels = TextChatService:WaitForChild("TextChannels", 5)
    if TextChannels then
        for _, channel in ipairs(TextChannels:GetChildren()) do connectChannel(channel) end
        TextChannels.ChildAdded:Connect(connectChannel)
    end
end

-- Toggle Handler
BotToggleBtn.MouseButton1Click:Connect(function()
    botEnabled = not botEnabled
    local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    
    if botEnabled then
        BotToggleBtn.Text = "BOT: ACTIVE"
        TweenService:Create(BotToggleBtn, tweenInfo, {BackgroundColor3 = Color3.fromRGB(40, 190, 110), TextColor3 = Color3.fromRGB(255, 255, 255)}):Play()
    else
        BotToggleBtn.Text = "BOT: OFF"
        TweenService:Create(BotToggleBtn, tweenInfo, {BackgroundColor3 = Color3.fromRGB(40, 35, 50), TextColor3 = Color3.fromRGB(160, 150, 170)}):Play()
    end
end)
