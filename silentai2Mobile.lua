-- Services
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- Universal Request Handler
local request = request or http.request or http_request or (syn and syn.request) or (fluxus and fluxus.request)

-- Cleanup Previous Instances
if PlayerGui:FindFirstChild("SilentAIBotGui") then
    PlayerGui.SilentAIBotGui:Destroy()
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

local SystemPrompt = "You are a cute anime bot named Silent. Respond quickly in short sentences under 12 words."

-- === INTERFACE SETUP ===
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SilentAIBotGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 999999
ScreenGui.Parent = PlayerGui

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(0, 50, 0, 50)
ToggleBtn.Position = UDim2.new(0, 10, 0.3, 0)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 30, 45)
ToggleBtn.Text = "🌸"
ToggleBtn.TextSize = 22
ToggleBtn.Active = true
ToggleBtn.Parent = ScreenGui

local BtnCorner = Instance.new("UICorner")
BtnCorner.CornerRadius = UDim.new(1, 0)
BtnCorner.Parent = ToggleBtn

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 220, 0, 160)
MainFrame.Position = UDim2.new(0, 70, 0.3, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 20, 32)
MainFrame.Visible = false
MainFrame.Parent = ScreenGui

local FrameCorner = Instance.new("UICorner")
FrameCorner.CornerRadius = UDim.new(0, 10)
FrameCorner.Parent = MainFrame

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(0.9, 0, 0.35, 0)
StatusLabel.Position = UDim2.new(0.05, 0, 0.05, 0)
StatusLabel.Text = "Status: ACTIVE\nListening: 'silent' / 'hey silent'"
StatusLabel.TextColor3 = Color3.fromRGB(255, 180, 220)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Font = Enum.Font.GothamBold
StatusLabel.TextSize = 12
StatusLabel.TextWrapped = true
StatusLabel.Parent = MainFrame

local BotToggleBtn = Instance.new("TextButton")
BotToggleBtn.Size = UDim2.new(0.9, 0, 0.25, 0)
BotToggleBtn.Position = UDim2.new(0.05, 0, 0.42, 0)
BotToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 180, 90)
BotToggleBtn.Text = "BOT: ON"
BotToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
BotToggleBtn.Font = Enum.Font.GothamBold
BotToggleBtn.TextSize = 12
BotToggleBtn.Parent = MainFrame

local StopFollowBtn = Instance.new("TextButton")
StopFollowBtn.Size = UDim2.new(0.9, 0, 0.25, 0)
StopFollowBtn.Position = UDim2.new(0.05, 0, 0.70, 0)
StopFollowBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
StopFollowBtn.Text = "Stop Following"
StopFollowBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StopFollowBtn.Font = Enum.Font.GothamBold
StopFollowBtn.TextSize = 12
StopFollowBtn.Parent = MainFrame

ToggleBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

BotToggleBtn.MouseButton1Click:Connect(function()
    botEnabled = not botEnabled
    if botEnabled then
        BotToggleBtn.Text = "BOT: ON"
        BotToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 180, 90)
        StatusLabel.Text = "Status: ACTIVE\nListening: 'silent'"
    else
        BotToggleBtn.Text = "BOT: OFF"
        BotToggleBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
        StatusLabel.Text = "Status: INACTIVE"
    end
end)

-- === CHAT ENGINE ===
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

-- === SAFE OPENROUTER QUERY (NIL SAFEGUARD INTEGRATED) ===
local function queryAI(promptText, senderName)
    if not request then return "Executor missing request function!" end

    local payload = HttpService:JSONEncode({
        model = "openrouter/free",
        max_tokens = 40,
        messages = {
            { role = "system", content = SystemPrompt },
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
            -- Safeguard against string formatting errors on nil or empty responses
            if type(rawContent) == "string" and rawContent ~= "" then
                return rawContent:gsub('^"', ''):gsub('"$', '')
            end
        end
    end

    return "B-Baka! AI timed out... ♡"
end

-- === NAVIGATION CONTROLLER ===
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

-- === MESSAGE PROCESSING & DISPATCH ===
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

        -- Baritone-style Navigation Commands
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
        StatusLabel.Text = "Thinking..."

        task.spawn(function()
            local cleanPrompt = messageText:gsub("hey silent", ""):gsub("silent", "")
            local reply = queryAI(cleanPrompt, senderName)
            if reply then sendMessage(reply) end
            StatusLabel.Text = "Status: ACTIVE\nListening: 'silent'"
            isProcessing = false
        end)
    end
end

-- === LISTENERS ===
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
