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
end

-- Configuration & Constants
local OPENROUTER_API_KEY = "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"
local OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

local MODEL_FALLBACKS = {
    "openrouter/free",
    "meta-llama/llama-3.2-1b-instruct:free",
    "google/gemma-2-9b-it:free"
}

local WALK_SPEED = 16
local RUN_SPEED = 28
local GRID_SIZE = 4

local botEnabled = true
local isProcessing = false
local followingPlayer = nil
local activePathTask = nil
local activeSteerConnection = nil
local currentAnimationTrack = nil

local STRICT_RULE = " Respond ONLY with spoken in-character dialogue. Maximum 12 words. Do not output thinking, reasoning, or meta remarks."
local currentModeIndex = 1
local Modes = {
    { Name = "OwO Mode", Prompt = "You are an ultra-cute anime furry bot named Silent. Respond in OwO style with stutters." .. STRICT_RULE },
    { Name = "Tsundere Mode", Prompt = "You are a flustered anime Tsundere bot named Silent. Respond with denial, 'b-baka!', and sass." .. STRICT_RULE },
    { Name = "Yandere Mode", Prompt = "You are a dark possessive Yandere bot named Silent. Respond with intense affection and subtle threats." .. STRICT_RULE }
}

-- === CHAT & ANIMATION ENGINE ===
local function sendMessage(msg)
    if not msg or msg == "" then return end
    pcall(function()
        local textChannels = TextChatService:FindFirstChild("TextChannels")
        if textChannels then
            local general = textChannels:FindFirstChild("RBXGeneral")
            if general then general:SendAsync(msg) return end
        end
        local sayRemote = game:GetService("ReplicatedStorage"):FindFirstChild("SayMessageRequest", true)
        if sayRemote then sayRemote:FireServer(msg, "All") end
    end)
end

-- === SPATIAL AWARENESS & DOORS ===
local function getDoorsList(ignoreChar)
    local excludeList = {ignoreChar}
    local systemFolder = workspace:FindFirstChild("System")
    if systemFolder then
        local mapFolder = systemFolder:FindFirstChild("Map")
        if mapFolder and mapFolder:FindFirstChild("Doors") then
            table.insert(excludeList, mapFolder.Doors)
        end
        if systemFolder:FindFirstChild("Doors") then
            table.insert(excludeList, systemFolder.Doors)
        end
    end
    return excludeList
end

-- Volumetric node clearance check (Better than single raycasts)
local function isNodeClear(pos, ignoreList)
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignoreList
    
    local parts = workspace:GetPartBoundsInRadius(pos + Vector3.new(0, 3, 0), 2.2, params)
    for _, part in ipairs(parts) do
        if part.CanCollide then return false end
    end
    return true
end

local function getGroundPos(pos, ignoreChar)
    local excludeList = getDoorsList(ignoreChar)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = excludeList

    local origin = pos + Vector3.new(0, 5, 0)
    local res = workspace:Raycast(origin, Vector3.new(0, -25, 0), params)
    if res and res.Instance.CanCollide and res.Normal.Y > 0.6 then
        return res.Position
    end
    return nil
end

-- === DYNAMIC 360 WHISKER STEERING ===
local function getAvoidanceVector(hrpPos, ignoreList)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignoreList

    local pushVector = Vector3.zero
    local numRays = 36 -- 10-degree intervals
    local scanRadius = 4.5

    for i = 1, numRays do
        local angle = math.rad(i * 10)
        local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
        local res = workspace:Raycast(hrpPos, dir * scanRadius, params)
        
        if res and res.Instance.CanCollide and res.Normal.Y < 0.5 then
            local dist = (res.Position - hrpPos).Magnitude
            local strength = (scanRadius - dist) / scanRadius
            pushVector = pushVector + (res.Normal * strength * 4.0) -- Repulsion force
        end
    end
    return pushVector
end

-- === CUSTOM VOLUMETRIC A* PATHFINDING ===
local function calculateCustomPath(startPos, targetPos)
    local myChar = LocalPlayer.Character
    if not myChar then return {targetPos} end
    local ignoreList = getDoorsList(myChar)

    local openSet = {}
    local cameFrom = {}
    local gScore = {}
    local fScore = {}

    local startNode = Vector3.new(math.floor(startPos.X / GRID_SIZE + 0.5) * GRID_SIZE, startPos.Y, math.floor(startPos.Z / GRID_SIZE + 0.5) * GRID_SIZE)
    
    local function nodeKey(v) return math.floor(v.X) .. "," .. math.floor(v.Y) .. "," .. math.floor(v.Z) end

    table.insert(openSet, startNode)
    gScore[nodeKey(startNode)] = 0
    fScore[nodeKey(startNode)] = (startNode - targetPos).Magnitude

    local directions = {
        Vector3.new(GRID_SIZE, 0, 0), Vector3.new(-GRID_SIZE, 0, 0),
        Vector3.new(0, 0, GRID_SIZE), Vector3.new(0, 0, -GRID_SIZE),
        Vector3.new(GRID_SIZE, 0, GRID_SIZE), Vector3.new(-GRID_SIZE, 0, -GRID_SIZE),
        Vector3.new(-GRID_SIZE, 0, GRID_SIZE), Vector3.new(GRID_SIZE, 0, -GRID_SIZE)
    }

    local closestNode = startNode
    local minTargetDist = (startNode - targetPos).Magnitude
    local iterations = 0

    while #openSet > 0 and iterations < 350 do
        iterations = iterations + 1
        
        local currentIndex = 1
        local current = openSet[1]
        for i = 2, #openSet do
            if (fScore[nodeKey(openSet[i])] or math.huge) < (fScore[nodeKey(current)] or math.huge) then
                current = openSet[i]
                currentIndex = i
            end
        end

        local distToTarget = (current - targetPos).Magnitude
        if distToTarget < minTargetDist then
            minTargetDist = distToTarget
            closestNode = current
        end

        if distToTarget <= GRID_SIZE * 1.5 then
            closestNode = current
            break
        end

        table.remove(openSet, currentIndex)

        for _, dir in ipairs(directions) do
            local neighborPos = current + dir
            local ground = getGroundPos(neighborPos, myChar)

            if ground and math.abs(ground.Y - current.Y) < 6 then
                neighborPos = Vector3.new(neighborPos.X, ground.Y, neighborPos.Z)

                if isNodeClear(neighborPos, ignoreList) then
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
                        if not exists then table.insert(openSet, neighborPos) end
                    end
                end
            end
        end
    end

    local path = {closestNode}
    local currKey = nodeKey(closestNode)
    while cameFrom[currKey] do
        table.insert(path, 1, cameFrom[currKey])
        currKey = nodeKey(cameFrom[currKey])
    end
    table.insert(path, targetPos)
    return path
end

-- === MOVEMENT ENGINE ===
local function stopMovement()
    followingPlayer = nil
    if activePathTask or env.SilentBotActiveTask then 
        pcall(function() task.cancel(activePathTask or env.SilentBotActiveTask) end) 
        activePathTask = nil 
        env.SilentBotActiveTask = nil
    end
    if activeSteerConnection then
        activeSteerConnection:Disconnect()
        activeSteerConnection = nil
    end
    
    local myChar = LocalPlayer.Character
    if myChar then
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        if humanoid then 
            humanoid.WalkSpeed = WALK_SPEED 
            humanoid:MoveTo(myChar.HumanoidRootPart.Position)
        end
    end
end

local function executePath(targetPos, isFollowing)
    stopMovement()
    
    activePathTask = task.spawn(function()
        env.SilentBotActiveTask = activePathTask
        local myChar = LocalPlayer.Character
        local humanoid = myChar and myChar:FindFirstChildOfClass("Humanoid")
        local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not humanoid or not myHRP then return end

        humanoid.WalkSpeed = RUN_SPEED
        local ignoreList = getDoorsList(myChar)

        local currentWaypoint = nil
        
        -- Start dynamic steering
        activeSteerConnection = RunService.Heartbeat:Connect(function()
            if not currentWaypoint or not myHRP or not humanoid then return end
            local avoidanceVec = getAvoidanceVector(myHRP.Position, ignoreList)
            humanoid:MoveTo(currentWaypoint + avoidanceVec)
        end)

        while isScriptAlive do
            local dest = isFollowing and followingPlayer and followingPlayer.Character and followingPlayer.Character:FindFirstChild("HumanoidRootPart")
            local actualTarget = isFollowing and dest and dest.Position or targetPos
            
            if not actualTarget then break end
            
            local nodes = calculateCustomPath(myHRP.Position, actualTarget)
            
            for i = 2, #nodes do
                currentWaypoint = nodes[i]
                local startTime = tick()
                
                while isScriptAlive and (myHRP.Position - Vector3.new(currentWaypoint.X, myHRP.Position.Y, currentWaypoint.Z)).Magnitude > 3.5 do
                    task.wait(0.05)
                    if tick() - startTime > 1.8 then break end -- Recalculate if stuck
                    
                    if currentWaypoint.Y > myHRP.Position.Y + 2.0 then
                        humanoid.Jump = true
                    end
                end
            end
            
            if not isFollowing then break end
            task.wait(0.2)
        end
        
        if activeSteerConnection then activeSteerConnection:Disconnect() end
        currentWaypoint = nil
        if humanoid then humanoid:MoveTo(myHRP.Position) end
    end)
end

-- === COMMAND DISPATCH & AI ===
local function processSingleAction(player, actionStr)
    local cmd = actionStr:lower():gsub("^%s*(.-)%s*$", "%1")
    if cmd:find("stop") then stopMovement()
    elseif cmd:find("follow") then
        followingPlayer = player
        executePath(nil, true)
    elseif cmd:find("come") or cmd:find("goto") then
        local targetPlayer = player
        for _, p in ipairs(Players:GetPlayers()) do
            if cmd:find(p.Name:lower()) or cmd:find(p.DisplayName:lower()) then targetPlayer = p break end
        end
        if targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
            executePath(targetPlayer.Character.HumanoidRootPart.Position, false)
        end
    end
end

local function queryAI(promptText, senderName)
    if not request then return end
    local fullPrompt = senderName .. ": " .. promptText
    for _, modelToUse in ipairs(MODEL_FALLBACKS) do
        local payload = HttpService:JSONEncode({
            model = modelToUse,
            max_tokens = 60,
            messages = { { role = "system", content = Modes[currentModeIndex].Prompt }, { role = "user", content = fullPrompt } }
        })
        local success, response = pcall(function()
            return request({ Url = OPENROUTER_URL, Method = "POST", Headers = { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. OPENROUTER_API_KEY }, Body = payload })
        end)
        if success and response.StatusCode == 200 then
            local dataSuccess, data = pcall(function() return HttpService:JSONDecode(response.Body) end)
            if dataSuccess and data.choices and data.choices[1] then
                return data.choices[1].message.content:gsub("<think>.-</think>", ""):gsub('"', '')
            end
        end
    end
end

-- === CHAT HOOKS ===
pcall(function()
    local function handleChat(p, msg)
        if not isScriptAlive or not botEnabled or p == LocalPlayer then return end
        local lowerMsg = msg:lower()
        if lowerMsg:find("silent") or lowerMsg:find("bot") then
            for _, step in ipairs(lowerMsg:split(" then ")) do processSingleAction(p, step) end
            if not isProcessing then
                isProcessing = true
                task.spawn(function()
                    local reply = queryAI(msg, p.DisplayName)
                    if reply then sendMessage(reply) end
                    isProcessing = false
                end)
            end
        end
    end

    if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
        table.insert(scriptConnections, TextChatService.MessageReceived:Connect(function(msg)
            if msg.TextSource then
                local p = Players:GetPlayerByUserId(msg.TextSource.UserId)
                if p then handleChat(p, msg.Text) end
            end
        end))
    else
        for _, p in ipairs(Players:GetPlayers()) do table.insert(scriptConnections, p.Chatted:Connect(function(m) handleChat(p, m) end)) end
        table.insert(scriptConnections, Players.PlayerAdded:Connect(function(p) table.insert(scriptConnections, p.Chatted:Connect(function(m) handleChat(p, m) end)) end))
    end
end)
