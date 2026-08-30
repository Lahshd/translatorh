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
local activePathTask = nil
local currentAnimationTrack = nil
local pathFolder = nil

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

-- === PATH VISUALIZER ===
local function clearPathVisuals()
    if pathFolder then
        pathFolder:Destroy()
        pathFolder = nil
    end
end

local function visualizePath(waypoints)
    clearPathVisuals()
    pathFolder = Instance.new("Folder")
    pathFolder.Name = "SilentPathVisuals"
    pathFolder.Parent = workspace

    for i, wp in ipairs(waypoints) do
        local node = Instance.new("Part")
        node.Size = Vector3.new(0.6, 0.6, 0.6)
        node.Position = wp.Position
        node.Shape = Enum.PartType.Ball
        node.Color = Color3.fromRGB(0, 255, 180)
        node.Material = Enum.Material.Neon
        node.Anchored = true
        node.CanCollide = false
        node.Parent = pathFolder

        if i > 1 then
            local prevWp = waypoints[i - 1]
            local beamPart = Instance.new("Part")
            beamPart.Size = Vector3.new(0.15, 0.15, (wp.Position - prevWp.Position).Magnitude)
            beamPart.CFrame = CFrame.new(prevWp.Position:Lerp(wp.Position, 0.5), wp.Position)
            beamPart.Color = Color3.fromRGB(0, 200, 255)
            beamPart.Material = Enum.Material.Neon
            beamPart.Anchored = true
            beamPart.CanCollide = false
            beamPart.Parent = pathFolder
        end
    end
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

-- === DOOR & COLLISION FILTERING ===
local function getDoorFilterList()
    local filterList = {}
    local myChar = LocalPlayer.Character
    if myChar then table.insert(filterList, myChar) end

    local doorsFolder1 = workspace:FindFirstChild("System") and workspace.System:FindFirstChild("Doors")
    if doorsFolder1 then table.insert(filterList, doorsFolder1) end

    local mapFolder = workspace:FindFirstChild("System") and workspace.System:FindFirstChild("Map")
    local doorsFolder2 = mapFolder and mapFolder:FindFirstChild("Doors")
    if doorsFolder2 then table.insert(filterList, doorsFolder2) end

    return filterList
end

-- === MOVEMENT ENGINE (RAYCASTING + PATHFINDING) ===
local function stopMovement()
    followingPlayer = nil
    if activePathTask then task.cancel(activePathTask) activePathTask = nil end
    stopEmote()
    clearPathVisuals()
    
    local myChar = LocalPlayer.Character
    if myChar then
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        if humanoid then 
            humanoid.WalkSpeed = WALK_SPEED 
            humanoid:MoveTo(myChar.HumanoidRootPart.Position)
        end
    end
end

local function raycastCheckObstacle(startPos, endPos)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = getDoorFilterList()

    local direction = (endPos - startPos)
    local result = workspace:Raycast(startPos, direction, rayParams)
    return result
end

local function navigateToPosition(targetPos, targetTool)
    stopEmote()
    if activePathTask then task.cancel(activePathTask) activePathTask = nil end
    
    activePathTask = task.spawn(function()
        local myChar = LocalPlayer.Character
        if not myChar then return end
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        local myHRP = myChar:FindFirstChild("HumanoidRootPart")
        if not humanoid or not myHRP then return end

        humanoid.WalkSpeed = RUN_SPEED

        -- Check direct raycast clear line
        local obstacle = raycastCheckObstacle(myHRP.Position, targetPos)
        if not obstacle then
            humanoid:MoveTo(targetPos)
            humanoid.MoveToFinished:Wait()
        else
            local path = PathfindingService:CreatePath({
                AgentRadius = 2,
                AgentHeight = 5,
                AgentCanJump = true,
                Costs = { Doors = 1 }
            })
            
            local success = pcall(function() path:ComputeAsync(myHRP.Position, targetPos) end)

            if success and path.Status == Enum.PathStatus.Success then
                local waypoints = path:GetWaypoints()
                visualizePath(waypoints)

                for _, waypoint in ipairs(waypoints) do
                    if waypoint.Action == Enum.PathWaypointAction.Jump then humanoid.Jump = true end
                    humanoid:MoveTo(waypoint.Position)
                    humanoid.MoveToFinished:Wait()
                end
            else
                humanoid:MoveTo(targetPos)
                humanoid.MoveToFinished:Wait()
            end
        end

        humanoid:MoveTo(targetPos)
        task.wait(0.3)

        if targetTool and targetTool:IsA("Tool") then
            humanoid:EquipTool(targetTool)
        end
        clearPathVisuals()
    end)
end

local function startFollowingPlayer(targetPlayer)
    stopMovement()
    followingPlayer = targetPlayer

    activePathTask = task.spawn(function()
        while followingPlayer and followingPlayer.Character do
            local targetHRP = followingPlayer.Character:FindFirstChild("HumanoidRootPart")
            local myChar = LocalPlayer.Character
            if not myChar or not targetHRP then break end
            local myHRP = myChar:FindFirstChild("HumanoidRootPart")
            local humanoid = myChar:FindFirstChildOfClass("Humanoid")
            if not myHRP or not humanoid then break end

            humanoid.WalkSpeed = RUN_SPEED
            local distance = (myHRP.Position - targetHRP.Position).Magnitude

            if distance > 6 then
                local obstacle = raycastCheckObstacle(myHRP.Position, targetHRP.Position)
                if not obstacle then
                    humanoid:MoveTo(targetHRP.Position)
                    task.wait(0.3)
                else
                    local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
                    local success = pcall(function() path:ComputeAsync(myHRP.Position, targetHRP.Position) end)

                    if success and path.Status == Enum.PathStatus.Success then
                        local waypoints = path:GetWaypoints()
                        visualizePath(waypoints)
                        for i = 1, math.min(#waypoints, 4) do
                            local wp = waypoints[i]
                            if wp.Action == Enum.PathWaypointAction.Jump then humanoid.Jump = true end
                            humanoid:MoveTo(wp.Position)
                            humanoid.MoveToFinished:Wait()
                        end
                    else
                        humanoid:MoveTo(targetHRP.Position)
                        task.wait(0.4)
                    end
                end
            else
                humanoid:MoveTo(myHRP.Position)
                clearPathVisuals()
                task.wait(0.5)
            end
        end
    end)
end

-- === INVENTORY & SPAWNER SCANNER ===
local function equipItemByName(itemName)
    local myChar = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not myChar then return false end
    local humanoid = myChar:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end

    local lowerName = itemName:lower()
    
    -- Inventory Check
    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") and tool.Name:lower():find(lowerName) then
                humanoid:EquipTool(tool)
                return true
            end
        end
    end

    -- Generic item / spawner scan
    local isGeneric = lowerName:find("an item") or lowerName:find("a item") or lowerName:find("item") or lowerName:find("anything")
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
                if matches and obj ~= myChar and not obj:IsDescendantOf(myChar) then
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
    if tool then 
        tool:Activate() 
    end
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
        local myChar = LocalPlayer.Character
        if myChar then
            local humanoid = myChar:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid:UnequipTools() end
        end
    elseif cmd:find("use") then
        useEquippedTool()
    elseif cmd:find("emote") or cmd:find("dance") then
        playEmote(cmd)
    elseif cmd:find("follow") then
        startFollowingPlayer(player)
    elseif cmd:find("come") or cmd:find("goto") or cmd:find("go to") or cmd:find("head to") then
        local targetPlayer = player
        if cmd:find("me") or cmd:find("myself") then
            targetPlayer = player
        else
            local targetName = cmd:match("goto%s+([%w_]+)") or cmd:match("go to%s+([%w_]+)") or cmd:match("head to%s+([%w_]+)")
            if targetName then
                for _, p in ipairs(Players:GetPlayers()) do
                    if p.Name:lower():find(targetName) or p.DisplayName:lower():find(targetName) then
                        targetPlayer = p
                        break
                    end
                end
            end
        end
        
        if targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
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
        local cleanedMsg = fullMessage:gsub("and then", "then")
        local rawCommands = cleanedMsg:split(" then ")
        local chain = {}
        
        for _, segment in ipairs(rawCommands) do
            for _, subSegment in ipairs(segment:split(" and ")) do
                table.insert(chain, subSegment)
            end
        end

        for _, stepCmd in ipairs(chain) do
            processSingleAction(player, stepCmd)
            task.wait(1.5)
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
    if not botEnabled or player == LocalPlayer then return end
    local lowerMsg = messageText:lower()

    if lowerMsg:find("tsundere") then
        currentModeIndex = 2
    elseif lowerMsg:find("owo") then
        currentModeIndex = 1
    elseif lowerMsg:find("yandere") then
        currentModeIndex = 3
    end

    if lowerMsg:find("silent") or lowerMsg:find("bot") then
        executeSubCommands(player, lowerMsg)

        if not isProcessing then
            isProcessing = true
            task.spawn(function()
                local reply = queryAI(messageText, player.DisplayName or player.Name)
                if reply then sendMessage(reply) end
                isProcessing = false
            end)
        end
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
        Players.PlayerAdded:Connect(function(p)
            p.Chatted:Connect(function(msg) processIncomingMessage(p, msg) end)
        end)
        for _, p in ipairs(Players:GetPlayers()) do
            p.Chatted:Connect(function(msg) processIncomingMessage(p, msg) end)
        end
    end
end)
