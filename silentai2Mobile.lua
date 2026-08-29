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

-- === DYNAMIC CHARACTER GETTER ===
local function getCharacterComponents()
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hum = char:WaitForChild("Humanoid", 3)
    local hrp = char:WaitForChild("HumanoidRootPart", 3)
    if hum and hrp and hum.Health > 0 then
        return char, hum, hrp
    end
    return nil, nil, nil
end

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
MainFrame.Size = UDim2.new(0, 240, 0, 210)
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
StatusLabel.Position = UDim2.new(0.05, 0, 0.16, 0)
StatusLabel.Text = "Status: ACTIVE\nListening for 'hey silent' or $commands"
StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextSize = 11
StatusLabel.TextWrapped = true
StatusLabel.Parent = MainFrame

local BotToggleBtn = Instance.new("TextButton")
BotToggleBtn.Size = UDim2.new(0.9, 0, 0, 30)
BotToggleBtn.Position = UDim2.new(0.05, 0, 0.36, 0)
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
ModeBtn.Position = UDim2.new(0.05, 0, 0.54, 0)
ModeBtn.BackgroundColor3 = Color3.fromRGB(60, 50, 80)
ModeBtn.Text = "Mode: OwO Mode"
ModeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ModeBtn.Font = Enum.Font.GothamBold
ModeBtn.TextSize = 12
ModeBtn.Active = true
ModeBtn.Parent = MainFrame

local ModeCorner = Instance.new("UICorner")
ModeCorner.CornerRadius = UDim.new(0, 6)
ModeCorner.Parent = ModeBtn

local StopFollowBtn = Instance.new("TextButton")
StopFollowBtn.Size = UDim2.new(0.9, 0, 0, 30)
StopFollowBtn.Position = UDim2.new(0.05, 0, 0.72, 0)
StopFollowBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
StopFollowBtn.Text = "Stop Movement"
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

local function destroyAllInstances()
    botEnabled = false
    stopNavigation()
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

-- === EXPLICIT RAYCASTING & MOVEMENT ENGINE ===
local function gotoPosition(targetPosition, isSeat, seatInstance)
    stopNavigation()

    currentNavigationTask = task.spawn(function()
        local myChar, humanoid, myHRP = getCharacterComponents()
        if not myChar or not humanoid or not myHRP then return end

        local raycastParams = RaycastParams.new()
        raycastParams.FilterAncestors = {myChar}
        raycastParams.FilterType = Enum.RaycastFilterType.Blacklist

        local rayOrigin = myHRP.Position
        local rayDirection = targetPosition - rayOrigin
        local directHit = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

        if not directHit or (directHit.Position - targetPosition).Magnitude < 3 then
            humanoid:MoveTo(targetPosition)
            humanoid.MoveToFinished:Wait()
            if isSeat and seatInstance and humanoid then seatInstance:Sit(humanoid) end
            return
        end

        local path = PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
            WaypointSpacing = 4
        })

        local success, _ = pcall(function()
            path:ComputeAsync(myHRP.Position, targetPosition)
        end)

        if success and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()

            for _, waypoint in ipairs(waypoints) do
                local currentChar, currentHum, currentHRP = getCharacterComponents()
                if not currentChar or not currentHum then break end

                if waypoint.Action == Enum.PathWaypointAction.Jump then
                    currentHum.Jump = true
                end

                currentHum:MoveTo(waypoint.Position)

                local moveFinished = false
                local conn = currentHum.MoveToFinished:Connect(function()
                    moveFinished = true
                end)

                local startTime = tick()
                while not moveFinished and (tick() - startTime) < 4 do
                    if not currentHRP or not currentHum then break end
                    
                    local currentRayDir = waypoint.Position - currentHRP.Position
                    local pathHit = workspace:Raycast(currentHRP.Position, currentRayDir, raycastParams)

                    if pathHit and pathHit.Instance and pathHit.Instance.CanCollide and pathHit.Distance < 2.5 then
                        currentHum.Jump = true
                    end
                    task.wait(0.1)
                end
                if conn then conn:Disconnect() end
            end

            local finalChar, finalHum = getCharacterComponents()
            if isSeat and seatInstance and finalHum then seatInstance:Sit(finalHum) end
        else
            humanoid:MoveTo(targetPosition)
            humanoid.MoveToFinished:Wait()
            if isSeat and seatInstance and humanoid then seatInstance:Sit(humanoid) end
        end
    end)
end

-- Target Follow Loop
local function startFollowing(player)
    stopNavigation()
    targetFollowPlayer = player

    followTask = task.spawn(function()
        while targetFollowPlayer == player do
            pcall(function()
                local myChar, humanoid, myHRP = getCharacterComponents()
                local targetChar = targetFollowPlayer.Character

                if myChar and targetChar and humanoid and myHRP then
                    local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
                    if targetHRP then
                        local dist = (myHRP.Position - targetHRP.Position).Magnitude
                        if dist > 6 then
                            humanoid:MoveTo(targetHRP.Position)
                        end
                    end
                end
            end)
            task.wait(0.3)
        end
    end)
end

local function getObjectInFront()
    local myChar, _, myHRP = getCharacterComponents()
    if not myChar or not myHRP then return nil end

    local rayOrigin = myHRP.Position + Vector3.new(0, 1.5, 0)
    local rayDirection = (myHRP.CFrame.LookVector * 30) + Vector3.new(0, -5, 0)

    local raycastParams = RaycastParams.new()
    raycastParams.FilterAncestors = {myChar}
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist

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

StopFollowBtn.MouseButton1Click:Connect(function()
    stopNavigation()
    sendMessage("Stopped movement! ♡")
end)

local function getPlayerInFront()
    local myChar, _, myHRP = getCharacterComponents()
    if not myChar or not myHRP then return nil end

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
    local lowerMsg = messageText:lower():gsub("^%s*(.-)%s*$", "%1")
    local senderName = player.DisplayName or player.Name

    if not botEnabled then return end

    -- Fix: Allow self-execution of $ commands for testing/control
    if lowerMsg:sub(1, 1) == "$" or lowerMsg:find("^%$") then
        if lowerMsg:find("^%$stop") then
            stopNavigation()
            sendMessage("Stopped movement! ♡")
            return
        elseif lowerMsg:find("^%$owo") then
            currentModeIndex = 1
            ModeBtn.Text = "Mode: OwO Mode"
            sendMessage("Switched to OwO mode! >w<")
            return
        elseif lowerMsg:find("^%$tsundere") then
            currentModeIndex = 2
            ModeBtn.Text = "Mode: Tsundere Mode"
            sendMessage("B-Baka! Switched to Tsundere mode!")
            return
        elseif lowerMsg:find("^%$yandere") then
            currentModeIndex = 3
            ModeBtn.Text = "Mode: Yandere Mode"
            sendMessage("Switched to Yandere mode... ♡")
            return
        elseif lowerMsg:find("^%$mode") then
            currentModeIndex = (currentModeIndex % #Modes) + 1
            ModeBtn.Text = "Mode: " .. Modes[currentModeIndex].Name
            sendMessage("Mode set to: " .. Modes[currentModeIndex].Name .. "! ♡")
            return
        end
    end

    if player == LocalPlayer then return end

    local isTriggered = lowerMsg:find("hey silent") or lowerMsg:find("silent")
    local isContinuous = continuousTalk and (lastActiveUser == player) and (tick() - lastActiveTime < 25)

    if isTriggered or isContinuous then
        if isProcessing then
            sendMessage(Modes[currentModeIndex].ThinkingMsg)
            return
        end

        lastActiveUser = player
        lastActiveTime = tick()

        local isObjectMove = lowerMsg:find("go onto") or lowerMsg:find("go on") or lowerMsg:find("sit down") or lowerMsg:find("sit on") or lowerMsg:find("sit") or lowerMsg:find("goto object") or lowerMsg:find("walk to")
        local detectedObj = nil

        if isObjectMove then
            detectedObj = getObjectInFront()
            if detectedObj then
                gotoPosition(detectedObj.Position, detectedObj.IsSeat, detectedObj.Instance)
            end
        elseif lowerMsg:find("stop follow") or lowerMsg:find("stop following") or lowerMsg:find("stay") or lowerMsg:find("stop moving") then
            stopNavigation()
        elseif lowerMsg:find("follow me") or lowerMsg:find("come here") or lowerMsg:find("follow us") then
            startFollowing(player)
        else
            local targetName = lowerMsg:match("follow%s+(%w+)") or lowerMsg:match("goto%s+(%w+)")
            if targetName and targetName ~= "me" and targetName ~= "us" then
                local foundPlayer = findPlayerByName(targetName)
                if foundPlayer then 
                    startFollowing(foundPlayer)
                end
            end
        end

        local processedPrompt = messageText
        
        if detectedObj then
            processedPrompt = processedPrompt .. " [System Note: You spotted object '" .. detectedObj.ModelName .. "' in front of you and are navigating to it via pathfinding.]"
        elseif lowerMsg:find("front") or lowerMsg:find("who is in") or lowerMsg:find("who's in") or lowerMsg:find("in front") then
            local frontPlayer = getPlayerInFront()
            if frontPlayer then
                local pName = frontPlayer.DisplayName or frontPlayer.Name
                processedPrompt = processedPrompt .. " [System Note: The player standing directly in front of you is " .. pName .. "]"
            else
                local frontObj = getObjectInFront()
                if frontObj then
                    processedPrompt = processedPrompt .. " [System Note: No player is in front of you, but you see an object named '" .. frontObj.ModelName .. "']"
                else
                    processedPrompt = processedPrompt .. " [System Note: There is currently nobody and no specific object directly in front of you]"
                end
            end
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
