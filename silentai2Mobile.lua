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

-- === GLOBAL TEARDOWN (INSTANCE KILLER) ===
local env = getgenv and getgenv() or _G

if env.SilentBotCleanup then
    pcall(function() env.SilentBotCleanup() end)
    task.wait(0.2)
end

local isScriptAlive = true
local scriptConnections = {}

env.SilentBotCleanup = function()
    isScriptAlive = false
    
    if env.SilentBotActiveTask then
        pcall(function() task.cancel(env.SilentBotActiveTask) end)
        env.SilentBotActiveTask = nil
    end

    for _, conn in ipairs(scriptConnections) do
        if conn and conn.Connected then
            pcall(function() conn:Disconnect() end)
        end
    end
    scriptConnections = {}

    local oldFolder = workspace:FindFirstChild("SilentPathVisuals")
    if oldFolder then oldFolder:Destroy() end

    local CoreGui = game:GetService("CoreGui")
    local uiParent = (gethui and gethui()) or CoreGui or (LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui"))

    if uiParent then
        for _, child in ipairs(uiParent:GetChildren()) do
            if child.Name == "SilentAIBotNative" then child:Destroy() end
        end
    end
    if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") then
        for _, child in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
            if child.Name == "SilentAIBotNative" then child:Destroy() end
        end
    end
end

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

local MODEL_FALLBACKS = {
    "openrouter/free",
    "meta-llama/llama-3.2-1b-instruct:free",
    "google/gemma-2-9b-it:free",
    "qwen/qwen-2.5-7b-instruct:free"
}

local WALK_SPEED = 16
local RUN_SPEED = 30

local botEnabled = true
local isProcessing = false
local followingPlayer = nil
local followConnection = nil
local activePathTask = nil
local currentAnimationTrack = nil

local STRICT_RULE = " Respond ONLY with spoken in-character dialogue. Maximum 12 words. Do not output thinking, reasoning, or meta remarks."

local currentModeIndex = 1
local Modes = {
    {
        Name = "OwO Mode", 
        Prompt = "You are an ultra-cute anime furry bot named Silent. Respond in OwO style with stutters." .. STRICT_RULE
    },
    {
        Name = "Tsundere Mode", 
        Prompt = "You are a flustered anime Tsundere bot named Silent. Respond with denial, 'b-baka!', and sass." .. STRICT_RULE
    },
    {
        Name = "Yandere Mode", 
        Prompt = "You are a dark possessive Yandere bot named Silent. Respond with intense affection and subtle threats." .. STRICT_RULE
    }
}

local Emotes = {
    ["qt"] = "rbxassetid://507770818",
    ["california girls"] = "rbxassetid://591745989",
    ["captain dance"] = "rbxassetid://10214311282"
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

-- === ANIMATION SYSTEM ===
local function stopEmote()
    if currentAnimationTrack then
        currentAnimationTrack:Stop()
        currentAnimationTrack = nil
    end
end

local function playEmote(emoteQuery)
    stopEmote()
    local myChar = LocalPlayer.Character
    if not myChar then return end
    local humanoid = myChar:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local lowerQuery = emoteQuery:lower()
    local animId = nil

    for name, id in pairs(Emotes) do
        if lowerQuery:find(name) then
            animId = id
            break
        end
    end

    if animId then
        local anim = Instance.new("Animation")
        anim.AnimationId = animId
        local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator")
        if animator then
            currentAnimationTrack = animator:LoadAnimation(anim)
            currentAnimationTrack:Play()
        end
    end
end

-- === VISUAL PATH SYSTEM (PATH LINES & RAYCASTING) ===
local function clearPathVisuals()
    local oldFolder = workspace:FindFirstChild("SilentPathVisuals")
    if oldFolder then oldFolder:Destroy() end
end

local function visualizePath(waypoints)
    clearPathVisuals()
    local pathFolder = Instance.new("Folder")
    pathFolder.Name = "SilentPathVisuals"
    pathFolder.Parent = workspace

    for i, wp in ipairs(waypoints) do
        -- Waypoint Node Sphere
        local sphere = Instance.new("SelectionBox")
        local nodePart = Instance.new("Part")
        nodePart.Size = Vector3.new(0.8, 0.8, 0.8)
        nodePart.Position = wp.Position + Vector3.new(0, 0.3, 0)
        nodePart.Anchored = true
        nodePart.CanCollide = false
        nodePart.Transparency = 1
        nodePart.Parent = pathFolder

        sphere.Adornee = nodePart
        sphere.Color3 = Color3.fromRGB(0, 255, 200)
        sphere.LineThickness = 0.05
        sphere.Parent = pathFolder

        -- Neon Connector Line
        if i > 1 then
            local prevWp = waypoints[i - 1]
            local dist = (wp.Position - prevWp.Position).Magnitude
            if dist > 0.1 then
                local line = Instance.new("Part")
                line.Size = Vector3.new(0.3, 0.3, dist)
                line.CFrame = CFrame.new(prevWp.Position:Lerp(wp.Position, 0.5) + Vector3.new(0, 0.3, 0), wp.Position + Vector3.new(0, 0.3, 0))
                line.Color = Color3.fromRGB(0, 170, 255)
                line.Material = Enum.Material.Neon
                line.Anchored = true
                line.CanCollide = false
                line.Parent = pathFolder
            end
        end
    end
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
TitleLabel.Text = "    🌸 Silent AI (Smart Bot)"
TitleLabel.TextColor3 = Color3.fromRGB(255, 180, 220)
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 12
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = MainFrame

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
StopFollowBtn.Size = UDim2.new(0.9, 0, 0, 30)
StopFollowBtn.Position = UDim2.new(0.05, 0, 0.74, 0)
StopFollowBtn.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
StopFollowBtn.Text = "Stop Following"
StopFollowBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StopFollowBtn.Font = Enum.Font.GothamBold
StopFollowBtn.TextSize = 12
StopFollowBtn.Parent = MainFrame

table.insert(scriptConnections, ToggleBtn.MouseButton1Click:Connect(function() MainFrame.Visible = not MainFrame.Visible end))

table.insert(scriptConnections, BotToggleBtn.MouseButton1Click:Connect(function()
    botEnabled = not botEnabled
    BotToggleBtn.Text = botEnabled and "BOT: ON" or "BOT: OFF"
    BotToggleBtn.BackgroundColor3 = botEnabled and Color3.fromRGB(40, 160, 80) or Color3.fromRGB(160, 50, 50)
    StatusLabel.Text = botEnabled and "Status: ACTIVE" or "Status: INACTIVE"
end))

table.insert(scriptConnections, ModeBtn.MouseButton1Click:Connect(function()
    currentModeIndex = (currentModeIndex % #Modes) + 1
    ModeBtn.Text = "Mode: " .. Modes[currentModeIndex].Name
end))

-- === MOVEMENT ENGINE ===
local function stopMovement()
    followingPlayer = nil
    if followConnection then followConnection:Disconnect() followConnection = nil end
    if activePathTask or env.SilentBotActiveTask then 
        pcall(function() task.cancel(activePathTask or env.SilentBotActiveTask) end) 
        activePathTask = nil 
        env.SilentBotActiveTask = nil
    end
    clearPathVisuals()
    stopEmote()
    
    local myChar = LocalPlayer.Character
    if myChar then
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        if humanoid then 
            humanoid.WalkSpeed = WALK_SPEED 
            humanoid:MoveTo(myChar.HumanoidRootPart.Position)
        end
    end
end

table.insert(scriptConnections, StopFollowBtn.MouseButton1Click:Connect(function()
    stopMovement()
    sendMessage("Stopped following! ♡")
end))

local function navigateToPosition(targetPos, targetTool)
    stopEmote()
    if activePathTask then task.cancel(activePathTask) activePathTask = nil end
    
    activePathTask = task.spawn(function()
        env.SilentBotActiveTask = activePathTask
        local myChar = LocalPlayer.Character
        if not myChar then return end
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        local myHRP = myChar:FindFirstChild("HumanoidRootPart")
        if not humanoid or not myHRP then return end

        humanoid.WalkSpeed = RUN_SPEED

        local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
        local success = pcall(function() path:ComputeAsync(myHRP.Position, targetPos) end)

        if success and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()
            visualizePath(waypoints)

            for _, waypoint in ipairs(waypoints) do
                if not isScriptAlive then break end
                if waypoint.Action == Enum.PathWaypointAction.Jump then humanoid.Jump = true end
                humanoid:MoveTo(waypoint.Position)
                humanoid.MoveToFinished:Wait()
            end
        else
            -- Raycasting Fallback Visual Line
            local raycastParams = RaycastParams.new()
            raycastParams.FilterAncestorsOfTypes = {myChar}
            raycastParams.FilterType = Enum.RaycastFilterType.Exclude

            local rayResult = workspace:Raycast(myHRP.Position, (targetPos - myHRP.Position), raycastParams)
            local finalVisualPos = rayResult and rayResult.Position or targetPos

            visualizePath({{Position = myHRP.Position}, {Position = finalVisualPos}})
            humanoid:MoveTo(targetPos)
            humanoid.MoveToFinished:Wait()
        end

        clearPathVisuals()
        humanoid:MoveTo(targetPos)
        task.wait(0.5)

        if targetTool and targetTool:IsA("Tool") then
            humanoid:EquipTool(targetTool)
        end
    end)
end

local function startFollowingPlayer(targetPlayer)
    stopMovement()
    followingPlayer = targetPlayer

    followConnection = RunService.Heartbeat:Connect(function()
        if not isScriptAlive or not followingPlayer or not followingPlayer.Character then return end
        local targetHRP = followingPlayer.Character:FindFirstChild("HumanoidRootPart")
        local myChar = LocalPlayer.Character
        if not myChar or not targetHRP then return end
        local myHRP = myChar:FindFirstChild("HumanoidRootPart")
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        if not myHRP or not humanoid then return end

        humanoid.WalkSpeed = RUN_SPEED
        local distance = (myHRP.Position - targetHRP.Position).Magnitude
        
        -- Raycasting obstruction check to keep direct path clear
        local raycastParams = RaycastParams.new()
        raycastParams.FilterAncestorsOfType = {myChar, followingPlayer.Character}
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude

        local direction = (targetHRP.Position - myHRP.Position)
        local rayResult = workspace:Raycast(myHRP.Position, direction, raycastParams)

        if rayResult then
            -- Path obstructed by obstacle: draw visual ray trace line
            visualizePath({{Position = myHRP.Position}, {Position = rayResult.Position}})
        else
            -- Direct clear path line to player
            visualizePath({{Position = myHRP.Position}, {Position = targetHRP.Position}})
        end

        if distance > 5 then
            humanoid:MoveTo(targetHRP.Position)
        else
            clearPathVisuals()
            humanoid:MoveTo(myHRP.Position)
        end
    end)
    table.insert(scriptConnections, followConnection)
end

-- === INVENTORY & SPAWNER SCANNER ===
local function unequipTools()
    local myChar = LocalPlayer.Character
    if not myChar then return end
    local humanoid = myChar:FindFirstChildOfClass("Humanoid")
    if humanoid then humanoid:UnequipTools() end
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
                return true
            end
        end
    end

    local isGeneric = lowerName:find("item") or lowerName:find("anything") or lowerName:find("something")
    local closestObj = nil
    local closestPos = nil
    local closestDist = math.huge
    local myHRP = myChar:FindFirstChild("HumanoidRootPart")

    if myHRP then
        local searchFolders = {}
        local spawnersFolder = workspace:FindFirstChild("System") and workspace.System:FindFirstChild("Spawners")
        if spawnersFolder then table.insert(searchFolders, spawnersFolder) end
        table.insert(searchFolders, workspace)

        for _, folder in ipairs(searchFolders) do
            for _, obj in ipairs(folder:GetDescendants()) do
                local matches = isGeneric or obj.Name:lower():find(lowerName)
                if matches then
                    local targetPos = nil
                    if obj:IsA("Tool") then
                        local handle = obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart")
                        if handle then targetPos = handle.Position end
                    elseif obj:IsA("BasePart") and not obj.Parent:FindFirstChildOfClass("Humanoid") then
                        targetPos = obj.Position
                    elseif obj:IsA("Model") and not obj:FindFirstChildOfClass("Humanoid") then
                        local primary = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
                        if primary then targetPos = primary.Position end
                    end

                    if targetPos then
                        local dist = (myHRP.Position - targetPos).Magnitude
                        if dist < closestDist then
                            closestDist = dist
                            closestObj = obj
                            closestPos = targetPos
                        end
                    end
                end
            end
        end
    end

    if closestPos then
        local toolToEquip = closestObj:IsA("Tool") and closestObj or nil
        navigateToPosition(closestPos, toolToEquip)
        return true
    end

    return false
end

local function useEquippedTool()
    local myChar = LocalPlayer.Character
    if not myChar then return end
    local tool = myChar:FindFirstChildOfClass("Tool")
    if tool then tool:Activate() end
end

-- === SINGLE ACTION DISPATCHER ===
local function processSingleAction(player, actionStr)
    local cmd = actionStr:lower():gsub("^%s*(.-)%s*$", "%1")

    if cmd:find("jump") then
        local myChar = LocalPlayer.Character
        if myChar then
            local humanoid = myChar:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid.Jump = true end
        end
    elseif cmd:find("unequip") or cmd:find("put away") then
        unequipTools()
    elseif cmd:find("use") then
        useEquippedTool()
    elseif cmd:find("emote") or cmd:find("dance") then
        playEmote(cmd)
    elseif cmd:find("follow") then
        startFollowingPlayer(player)
    elseif cmd:find("come") or cmd:find("goto") or cmd:find("head to") then
        local targetPlayer = player
        local targetName = cmd:match("goto%s+([%w_]+)") or cmd:match("head to%s+([%w_]+)")
        if targetName then
            for _, p in ipairs(Players:GetPlayers()) do
                if p.Name:lower():find(targetName) or p.DisplayName:lower():find(targetName) then
                    targetPlayer = p
                    break
                end
            end
        end
        stopMovement()
        if targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
            navigateToPosition(targetPlayer.Character.HumanoidRootPart.Position, nil)
        end
    elseif cmd:find("equip") or cmd:find("take out") or cmd:find("find") or cmd:find("get") then
        local targetItem = cmd:match("equip%s+(.+)") or cmd:match("take out%s+(.+)") or cmd:match("find%s+(.+)") or cmd:match("get%s+(.+)")
        if targetItem then
            equipItemByName(targetItem)
        end
    elseif cmd:find("stop") then
        stopMovement()
    end
end

-- === MULTI-COMMAND CHAINING ===
local function executeSubCommands(player, fullMessage)
    task.spawn(function()
        local rawCommands = fullMessage:split(" and ")
        local chain = {}
        for _, segment in ipairs(rawCommands) do
            for _, subSegment in ipairs(segment:split(" then ")) do
                table.insert(chain, subSegment)
            end
        end

        for _, stepCmd in ipairs(chain) do
            if not isScriptAlive then break end
            processSingleAction(player, stepCmd)
            task.wait(1.2)
        end
    end)
end

-- === SILENT AI QUERY ENGINE ===
local function queryAI(promptText, senderName)
    if not request then return end
    local fullPrompt = senderName .. ": " .. promptText

    for i = 1, #MODEL_FALLBACKS do
        local modelToUse = MODEL_FALLBACKS[i]
        local payload = HttpService:JSONEncode({
            model = modelToUse,
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
                    return rawContent:gsub("<think>.-</think>", ""):gsub("%b[]", ""):gsub('^"', ''):gsub('"$', ''):gsub("^%s*(.-)%s*$", "%1")
                end
            end
        end
        task.wait(0.3)
    end
    return nil
end

-- === INCOMING MESSAGE PROCESSOR ===
local function processIncomingMessage(player, messageText)
    if not isScriptAlive or not botEnabled or player == LocalPlayer then return end
    local lowerMsg = messageText:lower()

    if lowerMsg:find("tsundere") then
        currentModeIndex = 2
        ModeBtn.Text = "Mode: Tsundere Mode"
    elseif lowerMsg:find("owo") then
        currentModeIndex = 1
        ModeBtn.Text = "Mode: OwO Mode"
    elseif lowerMsg:find("yandere") then
        currentModeIndex = 3
        ModeBtn.Text = "Mode: Yandere Mode"
    end

    if lowerMsg:find("silent") or lowerMsg:find("bot") then
        executeSubCommands(player, lowerMsg)

        if not isProcessing then
            isProcessing = true
            task.spawn(function()
                local reply = queryAI(messageText, player.DisplayName or player.Name)
                if reply and isScriptAlive then sendMessage(reply) end
                isProcessing = false
            end)
        end
    end
end

-- === CHAT HOOKS ===
pcall(function()
    if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
        table.insert(scriptConnections, TextChatService.MessageReceived:Connect(function(textChatMessage)
            if textChatMessage and textChatMessage.TextSource then
                local player = Players:GetPlayerByUserId(textChatMessage.TextSource.UserId)
                if player then processIncomingMessage(player, textChatMessage.Text) end
            end
        end))
    else
        table.insert(scriptConnections, Players.PlayerAdded:Connect(function(p)
            table.insert(scriptConnections, p.Chatted:Connect(function(msg) processIncomingMessage(p, msg) end))
        end))
        for _, p in ipairs(Players:GetPlayers()) do
            table.insert(scriptConnections, p.Chatted:Connect(function(msg) processIncomingMessage(p, msg) end))
        end
    end
end)
