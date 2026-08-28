-- Services & Engine Init
--miss lizz is a good girl according to her word
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

-- Unified HTTP Request Handler (Mobile High-UNC Compatibility)
local request = request or http.request or http_request or (syn and syn.request) or (fluxus and fluxus.request)

-- Cleanup Previous Instances
if PlayerGui:FindFirstChild("SilentAIBotGui") then
    PlayerGui.SilentAIBotGui:Destroy()
end

-- Config & States
local OPENROUTER_API_KEY = "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"
local OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

local botEnabled = false
local isProcessing = false
local currentMode = 1
local PlayerMemory = {}

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

-- Screen Interface
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SilentAIBotGui"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 999999
ScreenGui.Parent = PlayerGui

local MobileToggleBtn = Instance.new("TextButton")
MobileToggleBtn.Name = "MobileToggle"
MobileToggleBtn.Size = UDim2.new(0, 45, 0, 45)
MobileToggleBtn.Position = UDim2.new(0, 15, 0.25, 0)
MobileToggleBtn.BackgroundColor3 = Themes[1].Bg
MobileToggleBtn.Text = "🌸"
MobileToggleBtn.TextSize = 20
MobileToggleBtn.Active = true
MobileToggleBtn.Parent = ScreenGui

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(1, 0)
ToggleCorner.Parent = MobileToggleBtn

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0.85, 0, 0.45, 0)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.BackgroundColor3 = Themes[1].Bg
MainFrame.Visible = false
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = MainFrame

MobileToggleBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(0.9, 0, 0.2, 0)
StatusLabel.Position = UDim2.new(0.05, 0, 0.1, 0)
StatusLabel.Text = "Status: Ready ('hey silent')"
StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Font = Enum.Font.GothamBold
StatusLabel.TextScaled = true
StatusLabel.Parent = MainFrame

local BotToggleBtn = Instance.new("TextButton")
BotToggleBtn.Size = UDim2.new(0.9, 0, 0.3, 0)
BotToggleBtn.Position = UDim2.new(0.05, 0, 0.55, 0)
BotToggleBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
BotToggleBtn.Text = "BOT: INACTIVE"
BotToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
BotToggleBtn.Font = Enum.Font.GothamBold
BotToggleBtn.TextScaled = true
BotToggleBtn.Parent = MainFrame

local BtnCorner = Instance.new("UICorner")
BtnCorner.CornerRadius = UDim.new(0, 8)
BtnCorner.Parent = BotToggleBtn

BotToggleBtn.MouseButton1Click:Connect(function()
    botEnabled = not botEnabled
    if botEnabled then
        BotToggleBtn.Text = "BOT: ACTIVE"
        BotToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 180, 90)
        StatusLabel.Text = "Status: Listening..."
    else
        BotToggleBtn.Text = "BOT: INACTIVE"
        BotToggleBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
        StatusLabel.Text = "Status: Off"
    end
end)

-- Modern Chat Sender Engine
local function sendMessage(msg)
    if not msg or msg == "" then return end
    pcall(function()
        local textChannel = TextChatService.TextChannels:FindFirstChild("RBXGeneral")
        if textChannel then
            textChannel:SendAsync(msg)
        else
            -- Legacy Fallback
            local sayRemote = game:GetService("ReplicatedStorage"):FindFirstChild("SayMessageRequest", true)
            if sayRemote then
                sayRemote:FireServer(msg, "All")
            end
        end
    end)
end

-- AI Query Execution
local function queryAI(promptText, senderName)
    if not request then 
        StatusLabel.Text = "Error: Executor missing 'request' API"
        return nil 
    end

    local payload = HttpService:JSONEncode({
        model = "openrouter/free",
        messages = {
            { role = "system", content = Themes[currentMode].SystemPrompt },
            { role = "user", content = "[" .. senderName .. "]: " .. promptText }
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
        if dataSuccess and data and data.choices and data.choices[1] then
            return data.choices[1].message.content:gsub('^"', ''):gsub('"$', '')
        end
    end

    return "B-Baka! Connection issue... ♡"
end

-- Modern TextChatService Event Listener
local function processIncomingMessage(senderName, messageText)
    if not botEnabled or isProcessing then return end
    if senderName == LocalPlayer.Name or senderName == LocalPlayer.DisplayName then return end

    if messageText:lower():find("hey silent") then
        isProcessing = true
        StatusLabel.Text = "Status: Generating..."

        task.spawn(function()
            local reply = queryAI(messageText, senderName)
            if reply then
                sendMessage(reply)
            end
            StatusLabel.Text = "Status: Listening..."
            isProcessing = false
        end)
    end
end

-- Connect Modern Chat Listener
if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
    TextChatService.MessageReceived:Connect(function(textChatMessage)
        local sender = textChatMessage.TextSource
        if sender then
            local player = Players:GetPlayerByUserId(sender.UserId)
            if player then
                processIncomingMessage(player.DisplayName, textChatMessage.Text)
            end
        end
    end)
else
    -- Legacy Chat Fallback hook
    for _, p in ipairs(Players:GetPlayers()) do
        p.Chatted:Connect(function(msg) processIncomingMessage(p.DisplayName, msg) end)
    end
    Players.PlayerAdded:Connect(function(p)
        p.Chatted:Connect(function(msg) processIncomingMessage(p.DisplayName, msg) end)
    end)
end
