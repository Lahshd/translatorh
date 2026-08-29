-- === DELTA & UNIVERSAL INITIALIZATION ===
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local LocalPlayer = Players.LocalPlayer

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
local currentNavigationTask = nil
local chatConnections = {}
local detectedObjectCache = nil

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

-- === DYNAMIC RAYCASTING & PERCEPTION ENGINE ===
local function performDynamicRaycast()
    local myChar = LocalPlayer.Character
    if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then return nil end

    local myHRP = myChar.HumanoidRootPart
    local rayOrigin = myHRP.Position
    local rayDirection = myHRP.CFrame.LookVector * 30

    local raycastParams = RaycastParams.new()
    raycastParams.FilterAncestors = {myChar}
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude

    local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
    if result and result.Instance then
        local hitObject = result.Instance
        local hitModel = hitObject:FindFirstAncestorOfClass("Model") or hitObject
        return {
            Instance = hitObject,
            ModelName = hitModel.Name,
            Position = result.Position,
            IsSeat = hitObject:IsA("Seat") or hitObject:IsA("VehicleSeat")
        }
    end
    return nil
end

-- Background Raycast Scanner Loop
task.spawn(function()
    while true do
        if botEnabled then
            detectedObjectCache = performDynamicRaycast()
        end
        task.wait(0.3)
    end
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

-- === DYNAMIC PATHFINDING & NAVIGATION ===
local function stopNavigation()
    targetFollowPlayer = nil
    if followTask then
        task.cancel(followTask)
        followTask = nil
    end
    if currentNavigationTask then
        task.cancel(currentNavigationTask)
        currentNavigationTask = nil
    end
end

local function gotoPositionDynamic(targetPosition, isSeat, seatInstance)
    stopNavigation()

    currentNavigationTask = task.spawn(function()
        local myChar = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local humanoid = myChar:WaitForChild("Humanoid")
        local myHRP = myChar:WaitForChild("HumanoidRootPart")

        local raycastParams = RaycastParams.new()
        raycastParams.FilterAncestors = {myChar}
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude

        local directHit = workspace:Raycast(myHRP.Position, targetPosition - myHRP.Position, raycastParams)
        if not directHit or (directHit.Position - targetPosition).Magnitude < 3 then
            humanoid:MoveTo(targetPosition)
            humanoid.MoveToFinished:Wait()
            if isSeat and seatInstance then seatInstance:Sit(humanoid) end
            return
        end

        local path = PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
            WaypointSpacing = 3
        })

        local success, _ = pcall(function() path:ComputeAsync(myHRP.Position, targetPosition) end)

        if success and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()

            for _, waypoint in ipairs(waypoints) do
                if waypoint.Action == Enum.PathWaypointAction.Jump then
                    humanoid.Jump = true
                end

                humanoid:MoveTo(waypoint.Position)

                local moveFinished = false
                local conn = humanoid.MoveToFinished:Connect(function() moveFinished = true end)

                local startTime = tick()
                while not moveFinished and (tick() - startTime) < 4 do
                    local pathHit = workspace:Raycast(myHRP.Position, waypoint.Position - myHRP.Position, raycastParams)
                    if pathHit and pathHit.Instance and pathHit.Instance.CanCollide and pathHit.Distance < 2.5 then
                        conn:Disconnect()
                        gotoPositionDynamic(targetPosition, isSeat, seatInstance)
                        return
                    end
                    task.wait(0.1)
                end
                conn:Disconnect()
            end

            if isSeat and seatInstance then seatInstance:Sit(humanoid) end
        else
            humanoid:MoveTo(targetPosition)
        end
    end)
end

local function startFollowingDynamic(player)
    stopNavigation()
    targetFollowPlayer = player

    followTask = task.spawn(function()
        while targetFollowPlayer == player do
            local myChar = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
            local targetChar = player.Character

            if myChar and targetChar then
                local humanoid = myChar:FindFirstChildOfClass("Humanoid")
                local myHRP = myChar:FindFirstChild("HumanoidRootPart")
                local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")

                if humanoid and myHRP and targetHRP then
                    local dist = (myHRP.Position - targetHRP.Position).Magnitude
                    
                    if dist > 6 then
                        local raycastParams = RaycastParams.new()
                        raycastParams.FilterAncestors = {myChar, targetChar}
                        raycastParams.FilterType = Enum.RaycastFilterType.Exclude

                        local hit = workspace:Raycast(myHRP.Position, targetHRP.Position - myHRP.Position, raycastParams)
                        
                        if hit and hit.Instance and hit.Instance.CanCollide then
                            gotoPositionDynamic(targetHRP.Position, false, nil)
                            task.wait(1.5)
                        else
                            humanoid:MoveTo(targetHRP.Position)
                        end
                    end
                end
            end
            task.wait(0.25)
        end
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
TitleLabel.Text = "   🌸 Silent AI (Smart Bot)"
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
StatusLabel.Text = "Status: ACTIVE\nListening..."
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
StopFollowBtn.Text = "Stop Movement"
StopFollowBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StopFollowBtn.Font = Enum.Font.GothamBold
StopFollowBtn.TextSize = 12
StopFollowBtn.Parent = MainFrame

local StopCorner = Instance.new("UICorner")
StopCorner.CornerRadius = UDim.new(0, 6)
StopCorner.Parent = StopFollowBtn

ToggleBtn.MouseButton1Click:Connect(function() MainFrame.Visible = not MainFrame.Visible end)

BotToggleBtn.MouseButton1Click:Connect(function()
    botEnabled = not botEnabled
    BotToggleBtn.Text = botEnabled and "BOT: ON" or "BOT: OFF"
    BotToggleBtn.BackgroundColor3 = botEnabled and Color3.fromRGB(40, 160, 80) or Color3.fromRGB(160, 50, 50)
    StatusLabel.Text = botEnabled and "Status: ACTIVE\nListening..." or "Status: INACTIVE"
end)

ModeBtn.MouseButton1Click:Connect(function()
    currentModeIndex = (currentModeIndex % #Modes) + 1
    ModeBtn.Text = "Mode: " .. Modes[currentModeIndex].Name
end)

StopFollowBtn.MouseButton1Click:Connect(function()
    stopNavigation()
    sendMessage("Stopped movement! ♡")
end)

CloseBtn.MouseButton1Click:Connect(function()
    botEnabled = false
    stopNavigation()
    for _, conn in ipairs(chatConnections) do if conn then conn:Disconnect() end end
    chatConnections = {}
    pcall(function() ScreenGui:Destroy() end)
end)

-- === AI QUERY EXECUTOR ===
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

    if success and response and response.StatusCode == 200 and response.Body then
        local dataSuccess, data = pcall(function() return HttpService:JSONDecode(response.Body) end)
        if dataSuccess and data and data.choices and data.choices[1] and data.choices[1].message then
            local rawContent = data.choices[1].message.content
            if type(rawContent) == "string" and rawContent ~= "" then
                rawContent = rawContent:gsub("<think>.-</think>", ""):gsub("%b[]", ""):gsub('^"', ''):gsub('"$', ''):gsub("^%s*(.-)%s*$", "%1")
                return rawContent
            end
        end
    end
    return "[Debug OpenRouter Error: Request Failed]"
end

-- === DYNAMIC MESSAGE & COMMAND PROCESSOR ===
local function processIncomingMessage(player, messageText)
    if not botEnabled then return end

    local lowerMsg = messageText:lower()
    local senderName = player and (player.DisplayName or player.Name) or "User"

    -- 1. Explicit Prefixed Commands
    if lowerMsg:find("$stop") then 
        stopNavigation() 
        sendMessage("Stopped movement! ♡") 
        return 
    end

    if lowerMsg:find("$owo") or lowerMsg:find("$mode owo") then 
        currentModeIndex = 1 
        ModeBtn.Text = "Mode: OwO Mode" 
        sendMessage("Switched to OwO mode! >w<") 
        return 
    end

    if lowerMsg:find("$tsundere") or lowerMsg:find("$mode tsundere") then 
        currentModeIndex = 2 
        ModeBtn.Text = "Mode: Tsundere Mode" 
        sendMessage("B-Baka! Switched to Tsundere mode!") 
        return 
    end

    if lowerMsg:find("$yandere") or lowerMsg:find("$mode yandere") then 
        currentModeIndex = 3 
        ModeBtn.Text = "Mode: Yandere Mode" 
        sendMessage("Switched to Yandere mode... ♡") 
        return 
    end

    if lowerMsg:find("$follow") then 
        if player then startFollowingDynamic(player) end
        sendMessage("Following you! ♡") 
        return 
    end

    -- 2. Dynamic Movement & Raycast Trigger Processing
    local dynamicActionExecuted = false

    if lowerMsg:find("come to me") or lowerMsg:find("come here") or lowerMsg:find("follow me") or lowerMsg:find("come") then
        if player then startFollowingDynamic(player) end
        dynamicActionExecuted = true
    elseif lowerMsg:find("go onto") or lowerMsg:find("go on") or lowerMsg:find("sit down") or lowerMsg:find("sit on") or lowerMsg:find("go to that") then
        local obj = detectedObjectCache or performDynamicRaycast()
        if obj then
            gotoPositionDynamic(obj.Position, obj.IsSeat, obj.Instance)
            dynamicActionExecuted = true
        end
    elseif lowerMsg:find("stop") or lowerMsg:find("stay") then
        stopNavigation()
        dynamicActionExecuted = true
    end

    -- 3. Dynamic AI Chat Trigger Check
    local isTriggered = lowerMsg:find("hey silent") or lowerMsg:find("silent")
    local isContinuous = continuousTalk and (lastActiveUser == player) and (tick() - lastActiveTime < 25)

    if isTriggered or isContinuous or dynamicActionExecuted then
        if isProcessing then return end

        lastActiveUser = player
        lastActiveTime = tick()

        local contextText = messageText
        local currentScanObj = detectedObjectCache or performDynamicRaycast()

        if currentScanObj then
            contextText = contextText .. " [System Note: Dynamic Raycast detected object '" .. currentScanObj.ModelName .. "' ahead.]"
        end

        local frontPlayer = getPlayerInFront()
        if frontPlayer then
            contextText = contextText .. " [System Note: Player '" .. (frontPlayer.DisplayName or frontPlayer.Name) .. "' is right in front of you.]"
        end

        isProcessing = true
        StatusLabel.Text = "Status: Replying..."

        task.spawn(function()
            local cleanPrompt = contextText:gsub("hey silent", ""):gsub("silent", "")
            local reply = queryAI(cleanPrompt, senderName)

            if reply and reply ~= "" and not reply:find("%[Debug Error") then
                sendMessage(reply)
            end

            StatusLabel.Text = "Status: ACTIVE\nListening..."
            isProcessing = false
        end)
    end
end

-- === CHAT HOOKS ===
local function hookPlayerChat(player)
    local conn = player.Chatted:Connect(function(msg)
        processIncomingMessage(player, msg)
    end)
    table.insert(chatConnections, conn)
end

for _, p in ipairs(Players:GetPlayers()) do
    hookPlayerChat(p)
end
table.insert(chatConnections, Players.PlayerAdded:Connect(hookPlayerChat))

pcall(function()
    if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
        local c = TextChatService.MessageReceived:Connect(function(textChatMessage)
            if not textChatMessage then return end

            local senderPlayer = nil

            if textChatMessage.TextSource then
                senderPlayer = Players:GetPlayerByUserId(textChatMessage.TextSource.UserId)
            end

            if not senderPlayer and textChatMessage.PrefixText ~= "" then
                local cleanPrefix = textChatMessage.PrefixText:gsub("%s*:%s*$", ""):gsub("^%s*", "")
                for _, p in ipairs(Players:GetPlayers()) do
                    if p.Name == cleanPrefix or p.DisplayName == cleanPrefix then
                        senderPlayer = p
                        break
                    end
                end
            end

            senderPlayer = senderPlayer or LocalPlayer

            processIncomingMessage(senderPlayer, textChatMessage.Text)
        end)
        table.insert(chatConnections, c)
    end
end)
