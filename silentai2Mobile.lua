-- === DELTA & UNIVERSAL INITIALIZATION ===
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")

while not LocalPlayer do
    task.wait(0.1)
    LocalPlayer = Players.LocalPlayer
end

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local request = request or http.request or http_request or (syn and syn.request) or (fluxus and fluxus.request) or (delta and delta.request)

pcall(function()
    for _, child in ipairs(PlayerGui:GetChildren()) do
        if child.Name == "SilentAIBotNative" then
            child:Destroy()
        end
    end
end)

-- Configuration & Constants
local OPENROUTER_API_KEY = "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"
local OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
local MODEL_NAME = "openrouter/free"

local WALK_SPEED = 15
local RUN_SPEED = 33

local botEnabled = true
local continuousTalk = true
local isProcessing = false
local lastActiveUser = nil
local lastActiveTime = 0
local followingPlayer = nil
local followConnection = nil
local activePathTask = nil
local autoDoorConnection = nil
local chatConnections = {}

local STRICT_RULE = " Respond ONLY with spoken in-character dialogue. Do not output thinking, reasoning, or meta remarks."

local currentModeIndex = 1
local Modes = {
    {
        Name = "OwO Mode", 
        Prompt = "You are an ultra-cute anime furry bot named Silent. Respond in OwO style with stutters. Maximum 12 words." .. STRICT_RULE,
        ThinkingMsg = "H-Hold on, my brain is processing so many things >w<!"
    },
    {
        Name = "Tsundere Mode", 
        Prompt = "You are a flustered anime Tsundere bot named Silent. Respond with denial, 'b-baka!', and sass. Maximum 12 words." .. STRICT_RULE,
        ThinkingMsg = "B-Baka! Don't rush me, I'm already thinking!"
    },
    {
        Name = "Yandere Mode", 
        Prompt = "You are a dark possessive Yandere bot named Silent. Respond with intense affection and subtle threats. Maximum 12 words." .. STRICT_RULE,
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

-- === EXPLORER UI BUTTON FINDER & SPRINT TRIGGER ===
local function triggerRunButtonUI(enableSprint)
    pcall(function()
        local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not pGui then return end

        -- Scan PlayerGui for UI buttons matching sprint/run keywords
        for _, guiObj in ipairs(pGui:GetDescendants()) do
            if guiObj:IsA("ImageButton") or guiObj:IsA("TextButton") then
                local btnName = guiObj.Name:lower()
                if btnName:find("run") or btnName:find("sprint") or btnName:find("shift") or btnName:find("fast") then
                    -- Trigger button click
                    if getconnections then
                        for _, conn in ipairs(getconnections(guiObj.MouseButton1Down)) do conn:Fire() end
                        for _, conn in ipairs(getconnections(guiObj.MouseButton1Click)) do conn:Fire() end
                        for _, conn in ipairs(getconnections(guiObj.Activated)) do conn:Fire() end
                    end
                end
            end
        end
    end)
end

-- === LIVE RAYCASTING & AUTO-DOOR DETECTOR ===
local function startAutoDoorRaycast()
    if autoDoorConnection then autoDoorConnection:Disconnect() end

    autoDoorConnection = RunService.Heartbeat:Connect(function()
        local myChar = LocalPlayer.Character
        if not myChar then return end
        local myHRP = myChar:FindFirstChild("HumanoidRootPart")
        if not myHRP then return end

        -- Raycast 6 studs directly in front of the bot
        local rayOrigin = myHRP.Position
        local rayDirection = myHRP.CFrame.LookVector * 6
        
        local raycastParams = RaycastParams.new()
        raycastParams.FilterAncestorsInstances = {myChar}
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude

        local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
        if raycastResult and raycastResult.Instance then
            local hitPart = raycastResult.Instance
            
            -- Check for ProximityPrompts or ClickDetectors on doors
            local prompt = hitPart:FindFirstChildWhichIsA("ProximityPrompt", true) or hitPart.Parent:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt and fireproximityprompt then
                fireproximityprompt(prompt)
            end

            local clicker = hitPart:FindFirstChildWhichIsA("ClickDetector", true) or hitPart.Parent:FindFirstChildWhichIsA("ClickDetector", true)
            if clicker and fireclickdetector then
                fireclickdetector(clicker)
            end
        end
    end)
end
startAutoDoorRaycast()

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

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 240, 0, 200)
MainFrame.Position = UDim2.new(0, 70, 0.3, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 18, 28)
MainFrame.Visible = true
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(0.9, 0, 0, 35)
StatusLabel.Position = UDim2.new(0.05, 0, 0.18, 0)
StatusLabel.Text = "Status: ACTIVE\nListening for commands..."
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

local ModeBtn = Instance.new("TextButton")
ModeBtn.Size = UDim2.new(0.9, 0, 0, 30)
ModeBtn.Position = UDim2.new(0.05, 0, 0.56, 0)
ModeBtn.BackgroundColor3 = Color3.fromRGB(60, 50, 80)
ModeBtn.Text = "Mode: OwO Mode"
ModeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ModeBtn.Font = Enum.Font.GothamBold
ModeBtn.TextSize = 12
ModeBtn.Parent = MainFrame

local StopFollowBtn = Instance.new("TextButton")
StopFollowBtn.Size = UDim2.new(0.9, 0, 0, 0.74, 0)
StopFollowBtn.Size = UDim2.new(0.9, 0, 0, 30)
StopFollowBtn.Position = UDim2.new(0.05, 0, 0.74, 0)
StopFollowBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
StopFollowBtn.Text = "Stop Following"
StopFollowBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StopFollowBtn.Font = Enum.Font.GothamBold
StopFollowBtn.TextSize = 12
StopFollowBtn.Parent = MainFrame

ToggleBtn.MouseButton1Click:Connect(function() MainFrame.Visible = not MainFrame.Visible end)

BotToggleBtn.MouseButton1Click:Connect(function()
    botEnabled = not botEnabled
    BotToggleBtn.Text = botEnabled and "BOT: ON" or "BOT: OFF"
    BotToggleBtn.BackgroundColor3 = botEnabled and Color3.fromRGB(40, 160, 80) or Color3.fromRGB(160, 50, 50)
end)

ModeBtn.MouseButton1Click:Connect(function()
    currentModeIndex = (currentModeIndex % #Modes) + 1
    ModeBtn.Text = "Mode: " .. Modes[currentModeIndex].Name
end)

-- === MOVEMENT, SPRINT & PATHFINDING SYSTEM ===
local function stopMovement()
    followingPlayer = nil
    if followConnection then followConnection:Disconnect() followConnection = nil end
    if activePathTask then task.cancel(activePathTask) activePathTask = nil end
    local myChar = LocalPlayer.Character
    if myChar then
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid.WalkSpeed = WALK_SPEED end
    end
end

StopFollowBtn.MouseButton1Click:Connect(function()
    stopMovement()
    sendMessage("Stopped following! ♡")
end)

local function updateBotSpeed(botHumanoid, targetPlayer)
    if not targetPlayer or not targetPlayer.Character then 
        botHumanoid.WalkSpeed = WALK_SPEED
        return 
    end

    local targetHumanoid = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
    if targetHumanoid and botHumanoid then
        local isSprinting = targetHumanoid.MoveDirection.Magnitude > 0 and targetHumanoid.WalkSpeed > 18
        if isSprinting then
            botHumanoid.WalkSpeed = RUN_SPEED
            triggerRunButtonUI(true)
        else
            botHumanoid.WalkSpeed = WALK_SPEED
            triggerRunButtonUI(false)
        end
    end
end

local function startFollowingPlayer(targetPlayer)
    stopMovement()
    followingPlayer = targetPlayer

    local lastPathCompute = 0
    followConnection = RunService.Heartbeat:Connect(function()
        if not followingPlayer or not followingPlayer.Character then return end
        local targetHRP = followingPlayer.Character:FindFirstChild("HumanoidRootPart")
        local myChar = LocalPlayer.Character
        if not myChar or not targetHRP then return end
        local myHRP = myChar:FindFirstChild("HumanoidRootPart")
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        if not myHRP or not humanoid then return end

        updateBotSpeed(humanoid, followingPlayer)

        local distance = (myHRP.Position - targetHRP.Position).Magnitude
        if distance > 6 then
            if tick() - lastPathCompute > 0.4 then
                lastPathCompute = tick()
                humanoid:MoveTo(targetHRP.Position)
            end
        else
            humanoid:MoveTo(myHRP.Position)
        end
    end)
end

-- === PATHFINDING + RAYCASTING NAVIGATOR ===
local function navigateToPosition(targetPos, isSeat, seatInstance, targetTool)
    stopMovement()
    
    activePathTask = task.spawn(function()
        local myChar = LocalPlayer.Character
        if not myChar then return end
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        local myHRP = myChar:FindFirstChild("HumanoidRootPart")
        if not humanoid or not myHRP then return end

        humanoid.WalkSpeed = WALK_SPEED

        local path = PathfindingService:CreatePath({
            AgentRadius = 3,
            AgentHeight = 6,
            AgentCanJump = true
        })

        local success = pcall(function()
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
                humanoid:MoveTo(seatInstance.Position)
                humanoid.MoveToFinished:Wait()
                seatInstance:Sit(humanoid)
            elseif targetTool and targetTool:IsA("Tool") then
                humanoid:EquipTool(targetTool)
            end
        else
            humanoid:MoveTo(targetPos)
            if isSeat and seatInstance then
                humanoid.MoveToFinished:Wait()
                seatInstance:Sit(humanoid)
            end
        end
    end)
end

-- === PROXIMITY SEARCH (FIXED FOR NEARBY ITEMS/CHAIRS) ===
local function findObjectByKeywords(speakerPlayer, textPrompt)
    local refPosition = nil
    
    -- Always default reference position to the speaker's or bot's current position
    if speakerPlayer and speakerPlayer.Character and speakerPlayer.Character:FindFirstChild("HumanoidRootPart") then
        refPosition = speakerPlayer.Character.HumanoidRootPart.Position
    elseif LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        refPosition = LocalPlayer.Character.HumanoidRootPart.Position
    end

    if not refPosition then return nil end

    local closestObj = nil
    local shortestDist = 300 -- Expanded range for local searches
    local lowerPrompt = textPrompt:lower()

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") or obj:IsA("BasePart") or obj:IsA("Tool") or obj:IsA("Seat") or obj:IsA("VehicleSeat") then
            local objName = obj.Name:lower()
            if objName:len() > 2 and lowerPrompt:find(objName) then
                local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart", true)
                if part then
                    local dist = (part.Position - refPosition).Magnitude
                    if dist < shortestDist then
                        shortestDist = dist
                        
                        local seatTarget = obj:IsA("Seat") or obj:IsA("VehicleSeat")
                        if not seatTarget and obj:IsA("Model") then
                            local foundSeat = obj:FindFirstChildWhichIsA("Seat", true) or obj:FindFirstChildWhichIsA("VehicleSeat", true)
                            if foundSeat then
                                seatTarget = true
                                obj = foundSeat
                            end
                        end

                        closestObj = {
                            Instance = obj,
                            ModelName = obj.Name,
                            Position = part.Position,
                            IsSeat = seatTarget,
                            IsTool = obj:IsA("Tool")
                        }
                    end
                end
            end
        end
    end
    return closestObj
end

-- === INVENTORY & TOOL FIX ENGINE ===
local function getInventoryItems()
    local tools = {}
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    local myChar = LocalPlayer.Character

    if backpack then
        for _, item in ipairs(backpack:GetChildren()) do
            if item:IsA("Tool") then table.insert(tools, item.Name) end
        end
    end
    if myChar then
        for _, item in ipairs(myChar:GetChildren()) do
            if item:IsA("Tool") then table.insert(tools, item.Name .. " (Equipped)") end
        end
    end
    return tools
end

local function equipItemByName(itemName)
    local myChar = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not myChar or not backpack then return false end
    local humanoid = myChar:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    local lowerName = itemName:lower()
    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") and tool.Name:lower():find(lowerName) then
            humanoid:EquipTool(tool)
            return true, tool.Name
        end
    end
    for _, tool in ipairs(myChar:GetChildren()) do
        if tool:IsA("Tool") and tool.Name:lower():find(lowerName) then
            return true, tool.Name
        end
    end
    return false
end

-- === AI & MESSAGE PROCESSOR ===
local function inspectSpeakerContext(speakerPlayer)
    local details = {}
    local invList = getInventoryItems()
    if #invList > 0 then
        table.insert(details, "Bot Inventory: " .. table.concat(invList, ", "))
    else
        table.insert(details, "Bot Inventory: Empty")
    end
    return table.concat(details, " | ")
end

local function queryAI(promptText, senderName, contextData)
    if not request then return "[Debug Error: Executor missing request API]" end

    local fullPrompt = senderName .. ": " .. promptText
    if contextData and contextData ~= "" then
        fullPrompt = fullPrompt .. " [Context Info: " .. contextData .. "]"
    end

    local payload = HttpService:JSONEncode({
        model = MODEL_NAME,
        max_tokens = 60,
        temperature = 0.7,
        messages = {
            { role = "system", content = Modes[currentModeIndex].Prompt },
            { role = "user", content = fullPrompt }
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
                rawContent = rawContent:gsub("<think>.-</think>", ""):gsub("%b[]", ""):gsub('^"', ''):gsub('"$', '')
                return rawContent
            end
        end
    end
    return "..."
end

local function processIncomingMessage(player, messageText)
    local lowerMsg = messageText:lower()
    local senderName = player.DisplayName or player.Name

    if not botEnabled or player == LocalPlayer then return end

    if lowerMsg:find("%$stop") then
        stopMovement()
        sendMessage("Stopped following! ♡")
        return
    end

    local isTriggered = lowerMsg:find("hey silent") or lowerMsg:find("silent")
    local isContinuous = continuousTalk and (lastActiveUser == player) and (tick() - lastActiveTime < 25)

    if isTriggered or isContinuous then
        if isProcessing then return end

        lastActiveUser = player
        lastActiveTime = tick()

        local takeItem = lowerMsg:match("take out the%s+(.+)") or lowerMsg:match("equip the%s+(.+)") or lowerMsg:match("hold the%s+(.+)")
        if takeItem then
            local success, itemName = equipItemByName(takeItem)
            if success then sendMessage("Equipped " .. itemName .. "! ♡") end
            return
        end

        local detectedObj = findObjectByKeywords(player, messageText)

        if lowerMsg:find("follow me") or lowerMsg:find("%$follow") then
            startFollowingPlayer(player)
        elseif lowerMsg:find("come to me") or lowerMsg:find("come here") or lowerMsg:find("walk to me") then
            stopMovement()
            if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                navigateToPosition(player.Character.HumanoidRootPart.Position, false, nil, nil)
            end
        elseif lowerMsg:find("stop follow") or lowerMsg:find("stay") then
            stopMovement()
        elseif detectedObj then
            stopMovement()
            navigateToPosition(detectedObj.Position, detectedObj.IsSeat, detectedObj.Instance, detectedObj.IsTool and detectedObj.Instance or nil)
        end

        local contextInfo = inspectSpeakerContext(player)
        isProcessing = true
        StatusLabel.Text = "Status: Replying..."

        task.spawn(function()
            local cleanPrompt = messageText:gsub("hey silent", ""):gsub("silent", "")
            local reply = queryAI(cleanPrompt, senderName, contextInfo)
            if reply and reply ~= "" then sendMessage(reply) end
            StatusLabel.Text = "Status: ACTIVE"
            isProcessing = false
        end)
    end
end

-- === CHAT HOOKS ===
pcall(function()
    if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
        TextChatService.MessageReceived:Connect(function(textChatMessage)
            if textChatMessage and textChatMessage.TextSource then
                local player = Players:GetPlayerByUserId(textChatMessage.TextSource.UserId)
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
end)
