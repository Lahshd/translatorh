-- === DELTA & UNIVERSAL INITIALIZATION ===
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
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

    local uiParent = (gethui and gethui()) or game:GetService("CoreGui") or (LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui"))

    if uiParent then
        for _, child in ipairs(uiParent:GetChildren()) do
            if child.Name == "SilentAIBotNative" then child:Destroy() end
        end
    end
    if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") then
        for _, child in ipairs(PlayerGui:GetChildren()) do
            if child.Name == "SilentAIBotNative" then child:Destroy() end
        end
    end
end

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
local RUN_SPEED = 28

local botEnabled = true
local isProcessing = false
local followingPlayer = nil
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

-- === ALWAYS-VISIBLE PATH DRAWING ENGINE ===
local function clearPathVisuals()
    local oldFolder = workspace:FindFirstChild("SilentPathVisuals")
    if oldFolder then oldFolder:Destroy() end
end

local function visualizePath(nodes)
    clearPathVisuals()
    local pathFolder = Instance.new("Folder")
    pathFolder.Name = "SilentPathVisuals"
    pathFolder.Parent = workspace

    for i, pos in ipairs(nodes) do
        local nodePart = Instance.new("Part")
        nodePart.Size = Vector3.new(0.6, 0.6, 0.6)
        nodePart.Position = pos + Vector3.new(0, 0.2, 0)
        nodePart.Color = Color3.fromRGB(0, 255, 200)
        nodePart.Material = Enum.Material.Neon
        nodePart.Anchored = true
        nodePart.CanCollide = false
        nodePart.Parent = pathFolder

        if i > 1 then
            local prevPos = nodes[i - 1]
            local dist = (pos - prevPos).Magnitude
            if dist > 0.05 then
                local line = Instance.new("Part")
                line.Size = Vector3.new(0.25, 0.25, dist)
                line.CFrame = CFrame.new(prevPos:Lerp(pos, 0.5) + Vector3.new(0, 0.2, 0), pos + Vector3.new(0, 0.2, 0))
                line.Color = Color3.fromRGB(0, 150, 255)
                line.Material = Enum.Material.Neon
                line.Anchored = true
                line.CanCollide = false
                line.Parent = pathFolder
            end
        end
    end
end

-- === BARITONE-STYLE A* & RAYCAST NAVIGATION ENGINE (FIXED) ===
local GRID_SIZE = 3.5

local function checkRay(startPos, targetPos, ignoreChar)
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {ignoreChar} -- FIXED FROM FilterAncestorsOfTypes
    params.FilterType = Enum.RaycastFilterType.Exclude
    local res = workspace:Raycast(startPos, targetPos - startPos, params)
    return res
end

local function getGroundPos(pos, ignoreChar)
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {ignoreChar} -- FIXED FROM FilterAncestorsOfTypes
    params.FilterType = Enum.RaycastFilterType.Exclude
    local res = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -15, 0), params)
    if res then
        return res.Position
    end
    return nil
end

local function calculateBaritonePath(startPos, targetPos)
    local myChar = LocalPlayer.Character
    if not myChar then return {targetPos} end

    if not checkRay(startPos + Vector3.new(0, 2, 0), targetPos + Vector3.new(0, 2, 0), myChar) then
        return {startPos, targetPos}
    end

    local openSet = {}
    local cameFrom = {}
    local gScore = {}
    local fScore = {}

    local startNode = Vector3.new(math.floor(startPos.X / GRID_SIZE + 0.5) * GRID_SIZE, startPos.Y, math.floor(startPos.Z / GRID_SIZE + 0.5) * GRID_SIZE)
    
    local function nodeKey(v)
        return math.floor(v.X) .. "," .. math.floor(v.Y) .. "," .. math.floor(v.Z)
    end

    table.insert(openSet, startNode)
    gScore[nodeKey(startNode)] = 0
    fScore[nodeKey(startNode)] = (startNode - targetPos).Magnitude

    local directions = {
        Vector3.new(GRID_SIZE, 0, 0), Vector3.new(-GRID_SIZE, 0, 0),
        Vector3.new(0, 0, GRID_SIZE), Vector3.new(0, 0, -GRID_SIZE),
        Vector3.new(GRID_SIZE, 0, GRID_SIZE), Vector3.new(-GRID_SIZE, 0, -GRID_SIZE),
        Vector3.new(-GRID_SIZE, 0, GRID_SIZE), Vector3.new(GRID_SIZE, 0, -GRID_SIZE)
    }

    local iterations = 0
    while #openSet > 0 and iterations < 180 do
        iterations = iterations + 1
        
        local currentIndex = 1
        local current = openSet[1]
        for i = 2, #openSet do
            if (fScore[nodeKey(openSet[i])] or math.huge) < (fScore[nodeKey(current)] or math.huge) then
                current = openSet[i]
                currentIndex = i
            end
        end

        if (current - targetPos).Magnitude <= GRID_SIZE * 1.5 then
            local path = {targetPos}
            local currKey = nodeKey(current)
            while cameFrom[currKey] do
                table.insert(path, 1, current)
                current = cameFrom[currKey]
                currKey = nodeKey(current)
            end
            table.insert(path, 1, startPos)
            return path
        end

        table.remove(openSet, currentIndex)

        for _, dir in ipairs(directions) do
            local neighborPos = current + dir
            local ground = getGroundPos(neighborPos, myChar)

            if ground and math.abs(ground.Y - current.Y) < 6 then
                neighborPos = Vector3.new(neighborPos.X, ground.Y + 2.5, neighborPos.Z)

                local obsCheck = checkRay(current + Vector3.new(0, 1.5, 0), neighborPos + Vector3.new(0, 1.5, 0), myChar)
                if not obsCheck then
                    local tentativeG = (gScore[nodeKey(current)] or math.huge) + (neighborPos - current).Magnitude
                    local nKey = nodeKey(neighborPos)

                    if tentativeG < (gScore[nKey] or math.huge) then
                        cameFrom[nKey] = current
                        gScore[nKey] = tentativeG
                        fScore[nKey] = tentativeG + (neighborPos - targetPos).Magnitude

                        local exists = false
                        for _, v in ipairs(openSet) do
                            if nodeKey(v) == nKey then exists = true break end
                        end
                        if not exists then
                            table.insert(openSet, neighborPos)
                        end
                    end
                end
            end
        end
    end

    return {startPos, targetPos}
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

-- === MOVEMENT & EXECUTION ENGINE ===
local function stopMovement()
    followingPlayer = nil
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
    stopMovement()
    
    activePathTask = task.spawn(function()
        env.SilentBotActiveTask = activePathTask
        local myChar = LocalPlayer.Character
        if not myChar then return end
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        local myHRP = myChar:FindFirstChild("HumanoidRootPart")
        if not humanoid or not myHRP then return end

        humanoid.WalkSpeed = RUN_SPEED

        local computedNodes = calculateBaritonePath(myHRP.Position, targetPos)
        visualizePath(computedNodes)

        for _, waypointPos in ipairs(computedNodes) do
            if not isScriptAlive then break end

            local obstacle = checkRay(myHRP.Position, waypointPos, myChar)
            if obstacle or waypointPos.Y > myHRP.Position.Y + 1.2 then
                humanoid.Jump = true
            end

            humanoid:MoveTo(waypointPos)
            
            local startTime = tick()
            local lastPos = myHRP.Position

            while isScriptAlive and (myHRP.Position - waypointPos).Magnitude > 3.0 do
                task.wait(0.05)
                if tick() - startTime > 2.5 then break end

                if (myHRP.Position - lastPos).Magnitude < 0.1 then
                    humanoid.Jump = true
                    break
                end
                lastPos = myHRP.Position
            end
        end

        clearPathVisuals()
        humanoid:MoveTo(targetPos)
        task.wait(0.3)

        if targetTool and targetTool:IsA("Tool") then
            humanoid:EquipTool(targetTool)
        end
    end)
end

local function startFollowingPlayer(targetPlayer)
    stopMovement()
    followingPlayer = targetPlayer

    activePathTask = task.spawn(function()
        env.SilentBotActiveTask = activePathTask
        while isScriptAlive and followingPlayer do
            local myChar = LocalPlayer.Character
            local targetChar = followingPlayer.Character
            if myChar and targetChar and targetChar:FindFirstChild("HumanoidRootPart") and myChar:FindFirstChild("HumanoidRootPart") then
                local myHRP = myChar.HumanoidRootPart
                local targetHRP = targetChar.HumanoidRootPart
                local humanoid = myChar:FindFirstChildOfClass("Humanoid")

                if humanoid then
                    humanoid.WalkSpeed = RUN_SPEED
                    local dist = (myHRP.Position - targetHRP.Position).Magnitude

                    if dist > 5 then
                        local nodes = calculateBaritonePath(myHRP.Position, targetHRP.Position)
                        visualizePath(nodes)

                        if nodes[2] then
                            if checkRay(myHRP.Position, nodes[2], myChar) or nodes[2].Y > myHRP.Position.Y + 1.2 then
                                humanoid.Jump = true
                            end
                            humanoid:MoveTo(nodes[2])
                        else
                            humanoid:MoveTo(targetHRP.Position)
                        end
                    else
                        clearPathVisuals()
                        humanoid:MoveTo(myHRP.Position)
                    end
                end
            end
            task.wait(0.15)
        end
        clearPathVisuals()
    end)
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
