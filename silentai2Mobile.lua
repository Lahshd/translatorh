-- Services
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- HTTP Request Handler
local request = request or http.request or http_request or (syn and syn.request) or (fluxus and fluxus.request)

-- Clean up existing UI if re-executed
if PlayerGui:FindFirstChild("SilentAIBotNative") then
    PlayerGui.SilentAIBotNative:Destroy()
end

-- Config & State
local OPENROUTER_API_KEY = "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"
local OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

local botEnabled = true
local continuousTalk = true
local isProcessing = false
local lastActiveUser = nil
local lastActiveTime = 0
local targetFollowPlayer = nil
local followConnection = nil

local currentModeIndex = 1
local Modes = {
    {Name = "OwO Mode", Prompt = "You are an ultra-cute anime furry bot named Silent. Respond in OwO style with stutters. Keep replies under 12 words."},
    {Name = "Tsundere Mode", Prompt = "You are a flustered anime Tsundere bot named Silent. Respond with denial, 'b-baka!', and sass. Keep replies under 12 words."},
    {Name = "Yandere Mode", Prompt = "You are a dark possessive Yandere bot named Silent. Respond with intense affection and subtle threats. Keep replies under 12 words."}
}

-- === PURE NATIVE GUI ENGINE (NO EXTERNAL LIBS) ===
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SilentAIBotNative"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 999999
ScreenGui.Parent = PlayerGui

-- Toggle Button (Floating Icon)
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(0, 45, 0, 45)
ToggleBtn.Position = UDim2.new(0, 15, 0.3, 0)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 25, 40)
ToggleBtn.Text = "🌸"
ToggleBtn.TextSize = 22
ToggleBtn.Active = true
ToggleBtn.Parent = ScreenGui

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(1, 0)
ToggleCorner.Parent = ToggleBtn

-- Main Control Frame
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 240, 0, 200)
MainFrame.Position = UDim2.new(0, 70, 0.3, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 18, 28)
MainFrame.Visible = true -- Default open so you see it instantly
MainFrame.Active = true
MainFrame.Draggable = true -- Built-in drag support for PC
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

-- Title Banner
local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, 0, 0, 30)
TitleLabel.BackgroundColor3 = Color3.fromRGB(35, 30, 50)
TitleLabel.Text = "🌸 Silent AI & Follow Engine"
TitleLabel.TextColor3 = Color3.fromRGB(255, 180, 220)
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 13
TitleLabel.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleLabel

-- Status Label
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(0.9, 0, 0, 35)
StatusLabel.Position = UDim2.new(0.05, 0, 0.18, 0)
StatusLabel.Text = "Status: ACTIVE\nListening for 'silent' or 'follow me'"
StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextSize = 11
StatusLabel.TextWrapped = true
StatusLabel.Parent = MainFrame

-- Bot Toggle Button
local BotToggleBtn = Instance.new("TextButton")
BotToggleBtn.Size = UDim2.new(0.9, 0, 0, 30)
BotToggleBtn.Position = UDim2.new(0.05, 0, 0.38, 0)
BotToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
BotToggleBtn.Text = "BOT: ON"
BotToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
BotToggleBtn.Font = Enum.Font.GothamBold
BotToggleBtn.TextSize = 12
BotToggleBtn.Parent = MainFrame

local BotCorner = Instance.new("UICorner")
BotCorner.CornerRadius = UDim.new(0, 6)
BotCorner.Parent = BotToggleBtn

-- Mode Swap Button
local ModeBtn = Instance.new("TextButton")
ModeBtn.Size = UDim2.new(0.9, 0, 0, 30)
ModeBtn.Position = UDim2.new(0.05, 0, 0.56, 0)
ModeBtn.BackgroundColor3 = Color3.fromRGB(60, 50, 80)
ModeBtn.Text = "Mode: OwO Mode"
ModeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ModeBtn.Font = Enum.Font.GothamBold
ModeBtn.TextSize = 12
ModeBtn.Parent = MainFrame

local ModeCorner = Instance.new("UICorner")
ModeCorner.CornerRadius = UDim.new(0, 6)
ModeCorner.Parent = ModeBtn

-- Stop Follow Button
local StopFollowBtn = Instance.new("TextButton")
StopFollowBtn.Size = UDim2.new(0.9, 0, 0, 30)
StopFollowBtn.Position = UDim2.new(0.05, 0, 0.74, 0)
StopFollowBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
StopFollowBtn.Text = "Stop Following"
StopFollowBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StopFollowBtn.Font = Enum.Font.GothamBold
StopFollowBtn.TextSize = 12
StopFollowBtn.Parent = MainFrame

local StopCorner = Instance.new("UICorner")
StopCorner.CornerRadius = UDim.new(0, 6)
StopCorner.Parent = StopFollowBtn

-- Button Interactions
ToggleBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

BotToggleBtn.MouseButton1Click:Connect(function()
    botEnabled = not botEnabled
    if botEnabled then
        BotToggleBtn.Text = "BOT: ON"
        BotToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
        StatusLabel.Text = "Status: ACTIVE\nListening for 'silent'"
    else
        BotToggleBtn.Text = "BOT: OFF"
        BotToggleBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
        StatusLabel.Text = "Status: INACTIVE"
    end
end)

ModeBtn.MouseButton1Click:Connect(function()
    currentModeIndex = (currentModeIndex % #Modes) + 1
    ModeBtn.Text = "Mode: " .. Modes[currentModeIndex].Name
end)

-- === CHAT LOGIC ===
local function sendMessage(msg)
    if not msg or msg == "" then return end
    pcall(function()
        local textChannel = TextChatService.TextChannels:FindFirstChild("RBXGeneral")
        if textChannel then
            textChannel:SendAsync(msg)
        else
            local sayRemote = game:GetService("ReplicatedStorage"):FindFirstChild("SayMessageRequest", true)
            if sayRemote then sayRemote:FireServer(msg, "All") end
        end
    end)
end

-- === SAFE API QUERY ===
local function queryAI(promptText, senderName)
    if not request then return "Executor missing request API!" end

    local payload = HttpService:JSONEncode({
        model = "openrouter/free",
        max_tokens = 40,
        messages = {
            { role = "system", content = Modes[currentModeIndex].Prompt },
            { role = "user", content = senderName .. ": " .. promptText }
        }
    })

    local success, response = pcall(function()
        return request({
            Url = OPENROUTER_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Bearer " .. OPENROUTER_API_KEY:gsub("%s+", "")
            },
            Body = payload
        })
    end)

    if success and response and (response.StatusCode == 200 or response.StatusDescription == "OK") then
        local dataSuccess, data = pcall(function() return HttpService:JSONDecode(response.Body) end)
        if dataSuccess and data and data.choices and data.choices[1] and data.choices[1].message then
            local rawContent = data.choices[1].message.content
            if type(rawContent) == "string" and rawContent ~= "" then
                return rawContent:gsub('^"', ''):gsub('"$', '')
            end
        end
    end

    return "B-Baka! AI timed out... ♡"
end

-- === STABLE DIRECT NAVIGATION ===
local function startFollowing(player)
    targetFollowPlayer = player
    if followConnection then followConnection:Disconnect() end

    followConnection = RunService.Heartbeat:Connect(function()
        if not targetFollowPlayer or not targetFollowPlayer.Character then return end
        local myChar = LocalPlayer.Character
        local targetChar = targetFollowPlayer.Character

        if myChar and targetChar and myChar:FindFirstChild("Humanoid") and targetChar:FindFirstChild("HumanoidRootPart") then
            local myHRP = myChar:FindFirstChild("HumanoidRootPart")
            local targetHRP = targetChar.HumanoidRootPart

            if myHRP and (myHRP.Position - targetHRP.Position).Magnitude > 7 then
                myChar.Humanoid:MoveTo(targetHRP.Position)
            end
        end
    end)
end

local function stopFollowing()
    targetFollowPlayer = nil
    if followConnection then
        followConnection:Disconnect()
        followConnection = nil
    end
end

StopFollowBtn.MouseButton1Click:Connect(function()
    stopFollowing()
    sendMessage("Stopped following! ♡")
end)

-- === MESSAGE PROCESSOR ===
local function processIncomingMessage(player, messageText)
    if not botEnabled or isProcessing then return end
    if player == LocalPlayer then return end

    local lowerMsg = messageText:lower()
    local senderName = player.DisplayName
    local isTriggered = lowerMsg:find("hey silent") or lowerMsg:find("silent")
    local isContinuous = continuousTalk and (lastActiveUser == player) and (tick() - lastActiveTime < 25)

    if isTriggered or isContinuous then
        lastActiveUser = player
        lastActiveTime = tick()

        -- Navigation Trigger Commands
        if lowerMsg:find("follow me") or lowerMsg:find("come here") or lowerMsg:find("follow") then
            sendMessage("Coming to you, " .. senderName .. "! ♡")
            startFollowing(player)
            return
        elseif lowerMsg:find("stop follow") or lowerMsg:find("stop") or lowerMsg:find("stay") then
            stopFollowing()
            sendMessage("Stopped following! ♡")
            return
        end

        isProcessing = true
        StatusLabel.Text = "Status: Generating reply for " .. senderName .. "..."

        task.spawn(function()
            local cleanPrompt = messageText:gsub("hey silent", ""):gsub("silent", "")
            local reply = queryAI(cleanPrompt, senderName)
            if reply then sendMessage(reply) end
            StatusLabel.Text = "Status: ACTIVE\nListening for 'silent'"
            isProcessing = false
        end)
    end
end

-- === CHAT HOOKS ===
if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
    TextChatService.MessageReceived:Connect(function(textChatMessage)
        local sender = textChatMessage.TextSource
        if sender then
            local player = Players:GetPlayerByUserId(sender.UserId)
            if player then processIncomingMessage(player, textChatMessage.Text) end
        end
    end)
else
    for _, p in ipairs(Players:GetPlayers()) do
        p.Chatted:Connect(function(msg) processIncomingMessage(p, msg) end)
    end
    Players.PlayerAdded:Connect(function(p)
        p.Chatted:Connect(function(msg) processIncomingMessage(p, msg) end)
    end)
end
