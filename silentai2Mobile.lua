-- Services
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- HTTP Request Handler (Mobile & PC Compatibility)
local request = request or http.request or http_request or (syn and syn.request) or (fluxus and fluxus.request)

-- Load Rayfield Safely
local RayfieldSuccess, Rayfield = pcall(function()
    return loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
end)

if not RayfieldSuccess or not Rayfield then
    warn("Failed to load Rayfield UI Library!")
    return
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

local currentMode = "OwO Mode"
local SystemPrompts = {
    ["OwO Mode"] = "You are an ultra-cute anime furry bot named Silent. Respond in OwO style with stutters. Keep replies under 12 words.",
    ["Tsundere Mode"] = "You are a flustered anime Tsundere bot named Silent. Respond with denial, 'b-baka!', and sass. Keep replies under 12 words.",
    ["Yandere Mode"] = "You are a dark possessive Yandere bot named Silent. Respond with intense affection and subtle threats. Keep replies under 12 words."
}

-- === RAYFIELD INTERFACE ===
local Window = Rayfield:CreateWindow({
   Name = "🌸 Silent AI & Navigation",
   LoadingTitle = "Silent AI Loading...",
   LoadingSubtitle = "Rayfield Cross-Platform Edition",
   ConfigurationSaving = { Enabled = false },
   KeySystem = false
})

local MainTab = Window:CreateTab("Control Hub", 4483362458)

local StatusParagraph = MainTab:CreateParagraph({
    Title = "Bot Status", 
    Content = "Active | Listening for 'silent' or 'hey silent'"
})

MainTab:CreateToggle({
   Name = "Enable Silent AI",
   CurrentValue = true,
   Callback = function(Value)
      botEnabled = Value
      StatusParagraph:Set({
          Title = "Bot Status", 
          Content = botEnabled and "Active | Listening..." or "Inactive"
      })
   end,
})

MainTab:CreateToggle({
   Name = "Continuous Talk Mode",
   CurrentValue = true,
   Callback = function(Value)
      continuousTalk = Value
      if not Value then lastActiveUser = nil end
   end,
})

MainTab:CreateDropdown({
   Name = "Personality Mode",
   Options = {"OwO Mode", "Tsundere Mode", "Yandere Mode"},
   CurrentOption = {"OwO Mode"},
   MultipleOptions = false,
   Callback = function(Option)
      currentMode = Option[1]
   end,
})

MainTab:CreateButton({
   Name = "Stop Following",
   Callback = function()
      targetFollowPlayer = nil
      if followConnection then
          followConnection:Disconnect()
          followConnection = nil
      end
      StatusParagraph:Set({Title = "Navigation", Content = "Stopped following player."})
   end,
})

-- === CHAT SENDER ===
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

-- === SAFE API QUERY (NIL SAFEGUARD INTEGRATED) ===
local function queryAI(promptText, senderName)
    if not request then return "Executor missing request function!" end

    local payload = HttpService:JSONEncode({
        model = "openrouter/free",
        max_tokens = 40,
        messages = {
            { role = "system", content = SystemPrompts[currentMode] },
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

-- === STABLE DIRECT NAVIGATION (MOBILE & PC) ===
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

        -- Navigation commands
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
        StatusParagraph:Set({Title = "Bot Status", Content = "Generating reply for " .. senderName .. "..."})

        task.spawn(function()
            local cleanPrompt = messageText:gsub("hey silent", ""):gsub("silent", "")
            local reply = queryAI(cleanPrompt, senderName)
            if reply then sendMessage(reply) end
            StatusParagraph:Set({Title = "Bot Status", Content = "Active | Listening..."})
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
