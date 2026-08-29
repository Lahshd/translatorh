-- === DELTA & UNIVERSAL INITIALIZATION ===
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PathfindingService = game:GetService("PathfindingService")

while not LocalPlayer do
    task.wait(0.1)
    LocalPlayer = Players.LocalPlayer
end

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")

local request = request or http.request or http_request or (syn and syn.request) or (fluxus and fluxus.request) or (delta and delta.request)

pcall(function()
    for _, child in ipairs(PlayerGui:GetChildren()) do
        if child.Name == "SilentAIBotNative" then
            child:Destroy()
        end
    end
end)

-- Configuration & State
local OPENROUTER_API_KEY = "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"
local OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
local MODEL_NAME = "openrouter/free"

local botEnabled = true
local continuousTalk = true
local isProcessing = false
local lastActiveUser = nil
local lastActiveTime = 0
local targetFollowPlayer = nil
local followTask = nil
local activePathTask = nil
local chatConnections = {}

local STRICT_RULE = " Respond ONLY with spoken in-character dialogue. Do not output thinking, reasoning, or meta remarks."

local currentModeIndex = 1
local Modes = {
    {
        Name = "OwO Mode", 
        Prompt = "You are an ultra-cute anime furry bot named Silent. Respond in OwO style with stutters. Maximum 10 words." .. STRICT_RULE,
        ThinkingMsg = "H-Hold on, my brain is processing so many things >w<!"
    },
    {
        Name = "Tsundere Mode", 
        Prompt = "You are a flustered anime Tsundere bot named Silent. Respond with denial, 'b-baka!', and sass. Maximum 10 words." .. STRICT_RULE,
        ThinkingMsg = "B-Baka! Don't rush me, I'm already thinking!"
    },
    {
        Name = "Yandere Mode", 
        Prompt = "You are a dark possessive Yandere bot named Silent. Respond with intense affection and subtle threats. Maximum 10 words." .. STRICT_RULE,
        ThinkingMsg = "Wait your turn... my mind is busy right now~ ♡"
    }
}

-- === CHAT SENDER ===
local function sendMessage(msg)
    if not msg or msg == "" then return end
    pcall(function()
        local textChannels = TextChatService:FindFirstChild("TextChannels")
        if textChannels then
            local general = textChannels:FindFirstChild("RBXGeneral")
            if general then
                general:SendAsync(msg)
                return
            end
        end
        local sayRemote = game:GetService("ReplicatedStorage"):FindFirstChild("SayMessageRequest", true)
        if sayRemote then sayRemote:FireServer(msg, "All") end
    end)
end

-- === NATIVE GUI ENGINE ===
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SilentAIBotNative"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 999999
ScreenGui.Parent = PlayerGui

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

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 240, 0, 200)
MainFrame.Position = UDim2.new(0, 70, 0.3, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 18, 28)
MainFrame.Visible = true
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, 0, 0, 30)
TitleLabel.BackgroundColor3 = Color3.fromRGB(35, 30, 50)
TitleLabel.Text = "  🌸 Silent AI (Smart Bot)"
TitleLabel.TextColor3 = Color3.fromRGB(255, 180, 220)
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 12
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleLabel

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 24, 0, 24)
CloseBtn.Position = UDim2.new(1, -27, 0, 3)
CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 14
CloseBtn.Parent = MainFrame

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(0.9, 0, 0, 35)
StatusLabel.Position = UDim2.new(0.05, 0, 0.18, 0)
StatusLabel.Text = "Status: ACTIVE\nListening for 'silent' or $commands"
StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextSize = 11
StatusLabel.TextWrapped = true
StatusLabel.Parent = MainFrame

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

ToggleBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

BotToggleBtn.MouseButton1Click:Connect(function()
    botEnabled = not botEnabled
    if botEnabled then
        BotToggleBtn.Text = "BOT: ON"
        BotToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
        StatusLabel.Text = "Status: ACTIVE\nListening..."
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

local function stopMovement()
    targetFollowPlayer = nil
    if followTask then
        task.cancel(followTask)
        followTask = nil
    end
    if activePathTask then
        task.cancel(activePathTask)
        activePathTask = nil
    end
end

local function destroyAllInstances()
    botEnabled = false
    stopMovement()
    for _, conn in ipairs(chatConnections) do
        if conn then conn:Disconnect() end
    end
    chatConnections = {}
    pcall(function()
        for _, child in ipairs(PlayerGui:GetChildren()) do
            if child.Name == "SilentAIBotNative" then
                child:Destroy()
            end
        end
    end)
end

CloseBtn.MouseButton1Click:Connect(destroyAllInstances)

-- === AI API QUERY WITH RETRY LOOP ===
local function queryAI(promptText, senderName)
    if not request then return "[Debug Error: Executor missing request API]" end

    local payload = HttpService:JSONEncode({
        model = MODEL_NAME,
        max_tokens = 60,
        temperature = 0.7,
        messages = {
            { role = "system", content = Modes[currentModeIndex].Prompt },
            { role = "user", content = senderName .. ": " .. promptText }
        }
    })

    local maxRetries = 3
    local lastError = ""

    for attempt = 1, maxRetries do
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

        if success and response then
            if response.StatusCode == 200 and response.Body then
                local dataSuccess, data = pcall(function() return HttpService:JSONDecode(response.Body) end)
                if dataSuccess and data and data.choices and data.choices[1] and data.choices[1].message then
                    local rawContent = data.choices[1].message.content
                    if type(rawContent) == "string" and rawContent ~= "" then
                        rawContent = rawContent:gsub("<think>.-</think>", "")
                        
                        local validLines = {}
                        for line in rawContent:gmatch("[^\r\n]+") do
                            local lower = line:lower()
                            if not lower:find("^okay,") and not lower:find("^analyze") and not lower:find("^the user") and not lower:find("thought process") then
                                table.insert(validLines, line)
                            end
                        end

                        if #validLines > 0 then
                            rawContent = validLines[#validLines]
                        end

                        rawContent = rawContent:gsub("%b[]", "")
                        rawContent = rawContent:gsub('^"', ''):gsub('"$', '')
                        rawContent = rawContent:gsub("^%s*(.-)%s*$", "%1")

                        if rawContent ~= "" then
                            return rawContent
                        end
                    end
                end
            else
                if response.Body then
                    local parseOk, parsedErr = pcall(function() return HttpService:JSONDecode(response.Body) end)
                    if parseOk and parsedErr and parsedErr.error and parsedErr.error.message then
                        lastError = "HTTP " .. tostring(response.StatusCode) .. ": " .. tostring(parsedErr.error.message)
                    else
                        lastError = "HTTP " .. tostring(response.StatusCode)
                    end
                end
            end
        else
            lastError = tostring(response)
        end

        if attempt < maxRetries then
            task.wait(1)
        end
    end

    return "[Debug OpenRouter Error after " .. tostring(maxRetries) .. " attempts: " .. lastError .. "]"
end

-- === PATHFINDING & NAVIGATION ENGINE ===
local function navigateToPosition(targetPos, isSeat, seatInstance)
    stopMovement()
    
    activePathTask = task.spawn(function()
        local myChar = LocalPlayer.Character
        if not myChar then return end
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        local myHRP = myChar:FindFirstChild("HumanoidRootPart")
        if not humanoid or not myHRP then return end

        local path = PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true
        })

        local success, err = pcall(function()
            path:ComputeAsync(myHRP.Position, targetPos)
        end)

        if success and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()
            for _, waypoint in ipairs(waypoints) do
                if waypoint.Action == Enum.PathWaypointAction.Jump then
                    humanoid.Jump = true
                end
                humanoid:MoveTo(waypoint.Position)
                local moveFinished = humanoid.MoveToFinished:Wait()
                if not moveFinished then break end
            end

            if isSeat and seatInstance then
                seatInstance:Sit(humanoid)
            end
        else
            -- Fallback straight move if path calculation fails
            humanoid:MoveTo(targetPos)
        end
    end)
end

local function startFollowing(player)
    stopMovement()
    targetFollowPlayer = player

    followTask = task.spawn(function()
        while targetFollowPlayer == player do
            pcall(function()
                local myChar = LocalPlayer.Character
                local targetChar = targetFollowPlayer.Character

                if myChar and targetChar then
                    local humanoid = myChar:FindFirstChildOfClass("Humanoid")
                    local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
                    local myHRP = myChar:FindFirstChild("HumanoidRootPart")

                    if humanoid and targetHRP and myHRP then
                        local dist = (myHRP.Position - targetHRP.Position).Magnitude
                        if dist > 6 then
                            navigateToPosition(targetHRP.Position, false, nil)
                        end
                    end
                end
            end)
            task.wait(1.5)
        end
    end)
end

-- Scan objects relative to either the Speaker or the Bot
local function findTargetObjectNearPlayer(speakerPlayer)
    local refPosition = nil
    
    if speakerPlayer and speakerPlayer.Character and speakerPlayer.Character:FindFirstChild("HumanoidRootPart") then
        refPosition = speakerPlayer.Character.HumanoidRootPart.Position
    else
        local myChar = LocalPlayer.Character
        if myChar and myChar:FindFirstChild("HumanoidRootPart") then
            refPosition = myChar.HumanoidRootPart.Position
        end
    end

    if not refPosition then return nil end

    local closestObj = nil
    local shortestDist = 120

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") or obj:IsA("BasePart") then
            local name = obj.Name:lower()
            if name:find("chair") or name:find("seat") or name:find("stool") or name:find("bench") then
                local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true)
                if part then
                    local dist = (part.Position - refPosition).Magnitude
                    if dist < shortestDist then
                        shortestDist = dist
                        closestObj = {
                            Instance = obj,
                            ModelName = obj.Name,
                            Position = part.Position,
                            IsSeat = obj:IsA("Seat") or obj:IsA("VehicleSeat") or (obj:FindFirstChildWhichIsA("Seat", true) ~= nil)
                        }
                    end
                end
            end
        end
    end
    return closestObj
end

StopFollowBtn.MouseButton1Click:Connect(function()
    stopMovement()
    sendMessage("Stopped following! ♡")
end)

local function getPlayerInFront()
    local myChar = LocalPlayer.Character
    if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then return nil end

    local myHRP = myChar.HumanoidRootPart
    local closestPlayer = nil
    local shortestDist = 25

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            local targetHRP = p.Character.HumanoidRootPart
            local dirToTarget = (targetHRP.Position - myHRP.Position)
            local dist = dirToTarget.Magnitude

            if dist < shortestDist then
                local dot = myHRP.CFrame.LookVector:Dot(dirToTarget.Unit)
                if dot > 0.2 then
                    shortestDist = dist
                    closestPlayer = p
                end
            end
        end
    end
    return closestPlayer
end

local function findPlayerByName(nameQuery)
    local query = nameQuery:lower()
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower():find(query) or p.DisplayName:lower():find(query) then
            return p
        end
    end
    return nil
end

-- === MESSAGE PROCESSOR ===
local function processIncomingMessage(player, messageText)
    local lowerMsg = messageText:lower()
    local senderName = player.DisplayName or player.Name

    if not botEnabled then return end
    if player == LocalPlayer then return end

    -- 1. Explicit Prefix Commands
    if lowerMsg:find("%$stop") then
        stopMovement()
        sendMessage("Stopped following! ♡")
        return
    elseif lowerMsg:find("%$owo") then
        currentModeIndex = 1
        ModeBtn.Text = "Mode: OwO Mode"
        sendMessage("Switched to OwO mode! >w<")
        return
    elseif lowerMsg:find("%$tsundere") then
        currentModeIndex = 2
        ModeBtn.Text = "Mode: Tsundere Mode"
        sendMessage("B-Baka! Switched to Tsundere mode!")
        return
    elseif lowerMsg:find("%$yandere") then
        currentModeIndex = 3
        ModeBtn.Text = "Mode: Yandere Mode"
        sendMessage("Switched to Yandere mode... ♡")
        return
    elseif lowerMsg:find("%$mode") then
        currentModeIndex = (currentModeIndex % #Modes) + 1
        ModeBtn.Text = "Mode: " .. Modes[currentModeIndex].Name
        sendMessage("Mode set to: " .. Modes[currentModeIndex].Name .. "! ♡")
        return
    end

    -- 2. Trigger Check
    local isTriggered = lowerMsg:find("hey silent") or lowerMsg:find("silent")
    local isContinuous = continuousTalk and (lastActiveUser == player) and (tick() - lastActiveTime < 25)

    if isTriggered or isContinuous then
        if isProcessing then
            sendMessage(Modes[currentModeIndex].ThinkingMsg)
            return
        end

        lastActiveUser = player
        lastActiveTime = tick()

        local detectedObj = nil

        -- Process Command Intent
        if lowerMsg:find("walk to me") or lowerMsg:find("come to me") or lowerMsg:find("come here") or lowerMsg:find("follow me") or lowerMsg:find("%$follow") then
            if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                navigateToPosition(player.Character.HumanoidRootPart.Position, false, nil)
            end
        elseif lowerMsg:find("stop follow") or lowerMsg:find("stop following") or lowerMsg:find("stay") then
            stopMovement()
        elseif lowerMsg:find("chair") or lowerMsg:find("seat") or lowerMsg:find("bench") or lowerMsg:find("sit") then
            stopMovement()
            detectedObj = findTargetObjectNearPlayer(player)
            if detectedObj then
                navigateToPosition(detectedObj.Position, detectedObj.IsSeat, detectedObj.Instance)
            end
        else
            local targetName = lowerMsg:match("follow%s+(%w+)") or lowerMsg:match("goto%s+(%w+)") or lowerMsg:match("walk to%s+(%w+)")
            if targetName and targetName ~= "me" and targetName ~= "us" then
                local foundPlayer = findPlayerByName(targetName)
                if foundPlayer then startFollowing(foundPlayer) end
            end
        end

        -- Context Prompt Generation
        local processedPrompt = messageText
        
        if detectedObj then
            processedPrompt = processedPrompt .. " [System Note: You located an object named '" .. detectedObj.ModelName .. "' near the user and are pathfinding toward it.]"
        end

        isProcessing = true
        StatusLabel.Text = "Status: Replying to " .. senderName .. "..."

        task.spawn(function()
            local cleanPrompt = processedPrompt:gsub("hey silent", ""):gsub("silent", "")
            local ok, reply = pcall(function()
                return queryAI(cleanPrompt, senderName)
            end)

            if ok and reply and reply ~= "" then 
                sendMessage(reply) 
            else
                sendMessage("[Debug Error: Request failed]")
            end

            StatusLabel.Text = "Status: ACTIVE\nListening..."
            isProcessing = false
        end)
    end
end

-- === CHAT HOOKS ===
pcall(function()
    if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
        local c = TextChatService.MessageReceived:Connect(function(textChatMessage)
            if textChatMessage and textChatMessage.TextSource then
                local player = Players:GetPlayerByUserId(textChatMessage.TextSource.UserId)
                if player then processIncomingMessage(player, textChatMessage.Text) end
            end
        end)
        table.insert(chatConnections, c)
    else
        for _, p in ipairs(Players:GetPlayers()) do
            local c = p.Chatted:Connect(function(msg) processIncomingMessage(p, msg) end)
            table.insert(chatConnections, c)
        end
        local c2 = Players.PlayerAdded:Connect(function(p)
            local c = p.Chatted:Connect(function(msg) processIncomingMessage(p, msg) end)
            table.insert(chatConnections, c2)
        end)
        table.insert(chatConnections, c2)
    end
end)
