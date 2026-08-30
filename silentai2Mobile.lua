-- === DELTA & UNIVERSAL INITIALIZATION ===
local Players = game:GetService("Players")
LocalPlayer = Players.LocalPlayer
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
local isSprintingActive = false
local lastActiveUser = nil
local lastActiveTime = 0
local followingPlayer = nil
local followConnection = nil
local activePathTask = nil
local autoScanConnection = nil
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

-- === SPRINT TOGGLER (UI BUTTON FINDER) ===
local function setSprintUIState(enable)
    if isSprintingActive == enable then return end
    isSprintingActive = enable

    pcall(function()
        local pGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not pGui then return end

        for _, guiObj in ipairs(pGui:GetDescendants()) do
            if guiObj:IsA("ImageButton") or guiObj:IsA("TextButton") then
                local btnName = guiObj.Name:lower()
                if btnName:find("run") or btnName:find("sprint") or btnName:find("shift") or btnName:find("fast") then
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

CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
end)

BotToggleBtn.MouseButton1Click:Connect(function()
    botEnabled = not botEnabled
    if botEnabled then
        BotToggleBtn.Text = "BOT: ON"
        BotToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
        StatusLabel.Text = "Status: ACTIVE"
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

-- === MOVEMENT & FOLLOW SYSTEM ===
local function stopMovement()
    followingPlayer = nil
    if followConnection then followConnection:Disconnect() followConnection = nil end
    if activePathTask then task.cancel(activePathTask) activePathTask = nil end
    setSprintUIState(false)
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

-- Pathfinding + Raycasting Navigation Engine
local function navigateToPosition(targetPos, isSeat, seatInstance, targetTool)
    if activePathTask then task.cancel(activePathTask) activePathTask = nil end
    
    local isDone = false
    activePathTask = task.spawn(function()
        local myChar = LocalPlayer.Character
        if not myChar then return end
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        local myHRP = myChar:FindFirstChild("HumanoidRootPart")
        if not humanoid or not myHRP then return end

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
            humanoid.MoveToFinished:Wait()
            if isSeat and seatInstance then
                seatInstance:Sit(humanoid)
            end
        end
        isDone = true
    end)

    while not isDone and activePathTask do
        task.wait(0.1)
    end
end

local function startFollowingPlayer(targetPlayer)
    stopMovement()
    followingPlayer = targetPlayer

    local lastPathCompute = 0
    followConnection = RunService.Heartbeat:Connect(function()
        if not followingPlayer or not followingPlayer.Character then return end
        local targetHRP = followingPlayer.Character:FindFirstChild("HumanoidRootPart")
        local targetHumanoid = followingPlayer.Character:FindFirstChildOfClass("Humanoid")
        local myChar = LocalPlayer.Character
        if not myChar or not targetHRP then return end
        local myHRP = myChar:FindFirstChild("HumanoidRootPart")
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        if not myHRP or not humanoid then return end

        if targetHumanoid then
            local isSprinting = targetHumanoid.MoveDirection.Magnitude > 0 and targetHumanoid.WalkSpeed > 18
            if isSprinting then
                humanoid.WalkSpeed = RUN_SPEED
                setSprintUIState(true)
            else
                humanoid.WalkSpeed = WALK_SPEED
                setSprintUIState(false)
            end
        end

        local distance = (myHRP.Position - targetHRP.Position).Magnitude
        if distance > 6 then
            if tick() - lastPathCompute > 0.5 then
                lastPathCompute = tick()
                task.spawn(function()
                    navigateToPosition(targetHRP.Position, false, nil, nil)
                end)
            end
        end
    end)
end

-- === LIVE RAYCASTING & SCANNER FOR NEARBY ITEMS / DOORS ===
local function startAutoScanRaycast()
    if autoScanConnection then autoScanConnection:Disconnect() end

    autoScanConnection = RunService.Heartbeat:Connect(function()
        local myChar = LocalPlayer.Character
        if not myChar then return end
        local myHRP = myChar:FindFirstChild("HumanoidRootPart")
        if not myHRP then return end

        local rayOrigin = myHRP.Position
        local rayDirection = myHRP.CFrame.LookVector * 8
        
        local raycastParams = RaycastParams.new()
        raycastParams.FilterAncestorsInstances = {myChar}
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude

        local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
        if raycastResult and raycastResult.Instance then
            local hitPart = raycastResult.Instance
            
            local prompt = hitPart:FindFirstChildWhichIsA("ProximityPrompt", true) or hitPart.Parent:FindFirstChildWhichIsA("ProximityPrompt", true)
            if prompt and fireproximityprompt then
                fireproximityprompt(prompt)
            end

            local clicker = hitPart:FindFirstChildWhichIsA("ClickDetector", true) or hitPart.Parent:FindFirstChildWhichIsA("ClickDetector", true)
            if clicker and fireclickdetector then
                fireclickdetector(clicker)
            end
            
            -- Auto-pickup workspace tool dropped directly ahead
            local toolAncestor = hitPart:FindFirstAncestorWhichIsA("Tool")
            if toolAncestor then
                local humanoid = myChar:FindFirstChildOfClass("Humanoid")
                if humanoid then humanoid:EquipTool(toolAncestor) end
            end
        end
    end)
end
startAutoScanRaycast()

-- === INVENTORY & WORKSPACE TOOL PICKUP ===
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
    if not myChar then return false end
    local humanoid = myChar:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    local lowerName = itemName:lower()
    
    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") and tool.Name:lower():find(lowerName) then
                humanoid:EquipTool(tool)
                return true, tool.Name
            end
        end
    end

    for _, tool in ipairs(myChar:GetChildren()) do
        if tool:IsA("Tool") and tool.Name:lower():find(lowerName) then
            return true, tool.Name
        end
    end

    -- Scans Workspace to find and pick up dropped tools matching keyword
    local myHRP = myChar:FindFirstChild("HumanoidRootPart")
    if myHRP then
        local closestTool = nil
        local shortestDist = 150
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Tool") and obj.Name:lower():find(lowerName) then
                local handle = obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart")
                if handle then
                    local dist = (handle.Position - myHRP.Position).Magnitude
                    if dist < shortestDist then
                        shortestDist = dist
                        closestTool = {Tool = obj, Position = handle.Position}
                    end
                end
            end
        end
        if closestTool then
            navigateToPosition(closestTool.Position, false, nil, closestTool.Tool)
            return true, closestTool.Tool.Name
        end
    end
    
    return false
end

local function unequipTools()
    local myChar = LocalPlayer.Character
    if not myChar then return false end
    local humanoid = myChar:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid:UnequipTools()
        return true
    end
    return false
end

local function useEquippedItem()
    local myChar = LocalPlayer.Character
    if not myChar then return false end
    local tool = myChar:FindFirstChildOfClass("Tool")
    if tool then
        tool:Activate()
        return true, tool.Name
    end
    return false
end

-- === ENVIRONMENT & CONTEXT INSPECTOR ===
local function inspectSpeakerContext(speakerPlayer)
    local details = {}
    
    local invList = getInventoryItems()
    if #invList > 0 then
        table.insert(details, "Bot Inventory: " .. table.concat(invList, ", "))
    else
        table.insert(details, "Bot Inventory: Empty")
    end

    if speakerPlayer and speakerPlayer.Character then
        local char = speakerPlayer.Character
        local heldTool = char:FindFirstChildOfClass("Tool")
        if heldTool then
            table.insert(details, "Speaker is holding: " .. heldTool.Name)
        else
            table.insert(details, "Speaker is holding nothing")
        end
        
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj:IsA("SurfaceGui") or obj:IsA("TextLabel") or obj:IsA("Decal") then
                    local part = obj:FindFirstAncestorWhichIsA("BasePart")
                    if part and (part.Position - hrp.Position).Magnitude < 15 then
                        if obj:IsA("TextLabel") and obj.Text ~= "" then
                            table.insert(details, "Wall Text on '" .. part.Name .. "': '" .. obj.Text .. "'")
                        end
                    end
                end
            end
        end
    end
    
    return table.concat(details, " | ")
end

local function findObjectByKeywords(speakerPlayer, textPrompt)
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
    local shortestDist = 150
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

local function findPlayerByName(nameQuery)
    local query = nameQuery:lower()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and (p.Name:lower():find(query) or p.DisplayName:lower():find(query)) then
            return p
        end
    end
    return nil
end

-- === AI API QUERY ===
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

                        if #validLines > 0 then rawContent = validLines[#validLines] end
                        rawContent = rawContent:gsub("%b[]", ""):gsub('^"', ''):gsub('"$', ''):gsub("^%s*(.-)%s*$", "%1")

                        if rawContent ~= "" then return rawContent end
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
        if attempt < maxRetries then task.wait(1) end
    end

    return "[Debug Error: " .. lastError .. "]"
end

-- === MULTI-COMMAND PARSER & MESSAGE PROCESSOR ===
local function executeSubCommand(player, commandText)
    local lowerCmd = commandText:lower()

    if lowerCmd:find("jump") then
        local myChar = LocalPlayer.Character
        if myChar then
            local humanoid = myChar:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid.Jump = true end
        end
        return
    end

    if lowerCmd:find("put") and (lowerCmd:find("away") or lowerCmd:find("back")) or lowerCmd:find("unequip") then
        unequipTools()
        return
    end

    local pickItem = lowerCmd:match("pick up%s+(.+)") or lowerCmd:match("take out the%s+(.+)") or lowerCmd:match("equip the%s+(.+)") or lowerCmd:match("hold the%s+(.+)") or lowerCmd:match("take out%s+(.+)")
    if pickItem then
        equipItemByName(pickItem)
        return
    end

    if lowerCmd:find("use the") or lowerCmd:find("use item") or lowerCmd:find("activate tool") or lowerCmd:find("swing") then
        useEquippedItem()
        return
    end

    if lowerCmd:find("follow me") or lowerCmd:find("%$follow") then
        startFollowingPlayer(player)
        return
    elseif lowerCmd:find("come to me") or lowerCmd:find("come here") or lowerCmd:find("walk to me") then
        stopMovement()
        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            navigateToPosition(player.Character.HumanoidRootPart.Position, false, nil, nil)
        end
        return
    elseif lowerCmd:find("stop follow") or lowerCmd:find("stay") then
        stopMovement()
        return
    end

    local targetPlayerName = lowerCmd:match("go to%s+(%w+)") or lowerCmd:match("walk to%s+(%w+)") or lowerCmd:match("follow%s+(%w+)")
    if targetPlayerName then
        if targetPlayerName == "me" or targetPlayerName == "us" then
            if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                stopMovement()
                navigateToPosition(player.Character.HumanoidRootPart.Position, false, nil, nil)
            end
        else
            local targetPlayer = findPlayerByName(targetPlayerName)
            if targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
                stopMovement()
                navigateToPosition(targetPlayer.Character.HumanoidRootPart.Position, false, nil, nil)
            end
        end
        return
    end

    local detectedObj = findObjectByKeywords(player, commandText)
    if detectedObj then
        stopMovement()
        navigateToPosition(detectedObj.Position, detectedObj.IsSeat, detectedObj.Instance, detectedObj.IsTool and detectedObj.Instance or nil)
    end
end

local function processIncomingMessage(player, messageText)
    local lowerMsg = messageText:lower()
    local senderName = player.DisplayName or player.Name

    if not botEnabled or player == LocalPlayer then return end

    if lowerMsg:find("%$stop") then
        stopMovement()
        sendMessage("Stopped following! ♡")
        return
    elseif lowerMsg:find("%$owo") or lowerMsg:find("%$mode owo") then
        currentModeIndex = 1
        ModeBtn.Text = "Mode: OwO Mode"
        sendMessage("Switched to OwO mode! >w<")
        return
    elseif lowerMsg:find("%$tsundere") or lowerMsg:find("%$mode tsundere") then
        currentModeIndex = 2
        ModeBtn.Text = "Mode: Tsundere Mode"
        sendMessage("B-Baka! Switched to Tsundere mode!")
        return
    elseif lowerMsg:find("%$yandere") or lowerMsg:find("%$mode yandere") then
        currentModeIndex = 3
        ModeBtn.Text = "Mode: Yandere Mode"
        sendMessage("Switched to Yandere mode... ♡")
        return
    end

    local isTriggered = lowerMsg:find("hey silent") or lowerMsg:find("silent")
    local isContinuous = continuousTalk and (lastActiveUser == player) and (tick() - lastActiveTime < 25)

    if isTriggered or isContinuous then
        if isProcessing then
            sendMessage(Modes[currentModeIndex].ThinkingMsg)
            return
        end

        lastActiveUser = player
        lastActiveTime = tick()

        -- Multi-Command Segment Splitting ("and then", "and", ",")
        local cleanCommandText = messageText:gsub("hey silent", ""):gsub("silent", "")
        local subCommands = {}
        for segment in cleanCommandText:gmatch("[^,]+") do
            for subSegment in segment:gmatch("[^and then]+") do
                if #subSegment:gsub("%s+", "") > 0 then
                    table.insert(subCommands, subSegment)
                end
            end
        end

        task.spawn(function()
            for _, subCmd in ipairs(subCommands) do
                executeSubCommand(player, subCmd)
            end
        end)

        local contextInfo = inspectSpeakerContext(player)
        isProcessing = true
        StatusLabel.Text = "Status: Replying to " .. senderName .. "..."

        task.spawn(function()
            local reply = queryAI(cleanCommandText, senderName, contextInfo)
            if reply and reply ~= "" then 
                sendMessage(reply) 
            end

            StatusLabel.Text = "Status: ACTIVE"
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
