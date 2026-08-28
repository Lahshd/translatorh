-- Load Rayfield Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Services
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")
local PathfindingService = game:GetService("PathfindingService")

-- HTTP Request Handler
local request = request or http.request or http_request or (syn and syn.request) or (fluxus and fluxus.request)

-- State & Settings
local OPENROUTER_API_KEY = "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"
local OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

local botEnabled = false
local continuousTalk = false
local isProcessing = false
local lastActiveUser = nil
local lastActiveTime = 0
local activeFollowThread = nil
local targetFollowPlayer = nil

local currentMode = "OwO Mode"
local SystemPrompts = {
    ["OwO Mode"] = "You are an ultra-cute anime furry bot named Silent. Respond in OwO style with stutters. Keep replies under 12 words.",
    ["Tsundere Mode"] = "You are a flustered anime Tsundere bot named Silent. Respond with denial, 'b-baka!', and sass. Keep replies under 12 words.",
    ["Yandere Mode"] = "You are a dark possessive Yandere bot named Silent. Respond with intense affection and subtle threats. Keep replies under 12 words."
}

-- UI Setup
local Window = Rayfield:CreateWindow({
   Name = "🌸 Silent AI & Navigation Engine",
   LoadingTitle = "Initializing Systems...",
   LoadingSubtitle = "Fast API + Pathfinding",
   ConfigurationSaving = { Enabled = false },
   KeySystem = false
})

local MainTab = Window:CreateTab("Control Hub", 4483362458)

local StatusParagraph = MainTab:CreateParagraph({
    Title = "Bot Status", 
    Content = "Inactive"
})

MainTab:CreateToggle({
   Name = "Enable Bot Engine",
   CurrentValue = false,
   Callback = function(Value)
      botEnabled = Value
      StatusParagraph:Set({Title = "Bot Status", Content = botEnabled and "Active & Listening..." or "Inactive"})
   end,
})

MainTab:CreateToggle({
   Name = "Continuous Talk Mode",
   CurrentValue = false,
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
   Name = "Stop Following Target",
   Callback = function()
      targetFollowPlayer = nil
      if activeFollowThread then task.cancel(activeFollowThread) end
      StatusParagraph:Set({Title = "Navigation Status", Content = "Follow cancelled."})
   end,
})

-- Fast Chat Dispatch
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

-- Optimized OpenRouter API Call
local function queryAIFast(promptText, senderName)
    if not request then return "Executor missing request API!" end

    -- Compact payload with max_tokens cap to force rapid generation
    local payload = HttpService:JSONEncode({
        model = "openrouter/free",
        max_tokens = 45,
        temperature = 0.7,
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
        if dataSuccess and data and data.choices and data.choices[1] then
            return data.choices[1].message.content:gsub('^"', ''):gsub('"$', '')
        end
    end

    return "B-Baka! Slow down network... ♡"
end

-- Baritone-Style Pathfinding Follow Logic
local function followPlayer(player)
    targetFollowPlayer = player
    if activeFollowThread then task.cancel(activeFollowThread) end

    activeFollowThread = task.spawn(function()
        while targetFollowPlayer == player and task.wait(0.4) do
            local myChar = LocalPlayer.Character
            local targetChar = player.Character
            if myChar and targetChar and myChar:FindFirstChild("HumanoidRootPart") and targetChar:FindFirstChild("HumanoidRootPart") then
                local myHRP = myChar.HumanoidRootPart
                local targetHRP = targetChar.HumanoidRootPart
                local humanoid = myChar:FindFirstChildOfClass("Humanoid")

                if (myHRP.Position - targetHRP.Position).Magnitude > 8 then
                    local path = PathfindingService:CreatePath({
                        AgentRadius = 2,
                        AgentHeight = 5,
                        AgentCanJump = true
                    })
                    
                    pcall(function()
                        path:ComputeAsync(myHRP.Position, targetHRP.Position)
                        local waypoints = path:GetWaypoints()
                        
                        for i = 2, math.min(#waypoints, 4) do
                            if targetFollowPlayer ~= player then break end
                            local wp = waypoints[i]
                            if wp.Action == Enum.PathWayPointAction.Jump then
                                humanoid.Jump = true
                            end
                            humanoid:MoveTo(wp.Position)
                            humanoid.MoveToFinished:Wait()
                        end
                    end)
                end
            end
        end
    end)
end

-- Main Message Processor
local function processIncomingMessage(player, messageText)
    if not botEnabled or isProcessing then return end
    if player == LocalPlayer then return end

    local lowerMsg = messageText:lower()
    local senderName = player.DisplayName
    local isTriggered = lowerMsg:find("hey silent") or lowerMsg:find("silent")
    
    -- Check Continuous Talk Timeout (30 Second Window)
    local isContinuous = continuousTalk and (lastActiveUser == player) and (tick() - lastActiveTime < 30)

    if isTriggered or isContinuous then
        lastActiveUser = player
        lastActiveTime = tick()

        -- Check for Baritone Follow Commands
        if lowerMsg:find("follow me") or lowerMsg:find("come here") or lowerMsg:find("follow") then
            sendMessage("Coming to you, " .. senderName .. "! ♡")
            followPlayer(player)
            return
        elseif lowerMsg:find("stop follow") or lowerMsg:find("stop following") or lowerMsg:find("stay") then
            targetFollowPlayer = nil
            if activeFollowThread then task.cancel(activeFollowThread) end
            sendMessage("Stopped following! ♡")
            return
        end

        -- Handle Normal AI Response
        isProcessing = true
        StatusParagraph:Set({Title = "Bot Status", Content = "Generating reply for " .. senderName .. "..."})

        task.spawn(function()
            local cleanPrompt = messageText:gsub("hey silent", ""):gsub("silent", "")
            local reply = queryAIFast(cleanPrompt, senderName)
            if reply then sendMessage(reply) end
            StatusParagraph:Set({Title = "Bot Status", Content = "Active & Listening..."})
            isProcessing = false
        end)
    end
end

-- Connect Modern & Legacy Chat Listeners
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
