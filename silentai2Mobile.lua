-- === UNIVERSAL EXECUTOR & CONTAINER RESOLVER ===
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

while not LocalPlayer do
    task.wait(0.1)
    LocalPlayer = Players.LocalPlayer
end

local request = request or http.request or http_request or (syn and syn.request) or (fluxus and fluxus.request) or (delta and delta.request)
local uiParent = (gethui and gethui()) or CoreGui or LocalPlayer:WaitForChild("PlayerGui")

pcall(function()
    for _, child in ipairs(uiParent:GetChildren()) do
        if child.Name == "SilentAIBotNative" then child:Destroy() end
    end
    for _, child in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
        if child.Name == "SilentAIBotNative" then child:Destroy() end
    end
end)

-- Configurations & Variables
local OPENROUTER_API_KEY = "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"
local OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

local WALK_SPEED = 16
local RUN_SPEED = 28

local botEnabled = true
local lastChatTimestamp = 0 -- STOPS MULTIPLE CHAT THREAD RACE CONDITIONS
local followingPlayer = nil
local activePathTask = nil
local currentAnimationTrack = nil
local navigationVersion = 0

local STRICT_RULE = " Respond ONLY with spoken in-character dialogue. Maximum 10 words. Do not output thinking or meta remarks."

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

-- === NATIVE GUI BUILDER ===
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SilentAIBotNative"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 99999999
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = uiParent

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Name = "ToggleBtn"
ToggleBtn.Size = UDim2.new(0, 50, 0, 50)
ToggleBtn.Position = UDim2.new(0, 15, 0.3, 0)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 25, 45)
ToggleBtn.Text = "🌸"
ToggleBtn.TextSize = 24
ToggleBtn.Active = true
ToggleBtn.Parent = ScreenGui

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(1, 0)
ToggleCorner.Parent = ToggleBtn

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 240, 0, 200)
MainFrame.Position = UDim2.new(0, 75, 0.3, 0)
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

ToggleBtn.MouseButton1Click:Connect(function() MainFrame.Visible = not MainFrame.Visible end)

BotToggleBtn.MouseButton1Click:Connect(function()
    botEnabled = not botEnabled
    BotToggleBtn.Text = botEnabled and "BOT: ON" or "BOT: OFF"
    BotToggleBtn.BackgroundColor3 = botEnabled and Color3.fromRGB(40, 160, 80) or Color3.fromRGB(160, 50, 50)
    StatusLabel.Text = botEnabled and "Status: ACTIVE" or "Status: INACTIVE"
end)

ModeBtn.MouseButton1Click:Connect(function()
    currentModeIndex = (currentModeIndex % #Modes) + 1
    ModeBtn.Text = "Mode: " .. Modes[currentModeIndex].Name
end)

-- === VISUAL PATH RENDERER ===
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
        local node = Instance.new("Part")
        node.Size = Vector3.new(0.8, 0.8, 0.8)
        node.Position = wp.Position + Vector3.new(0, 1, 0)
        node.Shape = Enum.PartType.Ball
        node.Color = Color3.fromRGB(0, 255, 180)
        node.Material = Enum.Material.Neon
        node.Anchored = true
        node.CanCollide = false
        node.Parent = pathFolder

        if i > 1 then
            local prevWp = waypoints[i - 1]
            local dist = (wp.Position - prevWp.Position).Magnitude
            if dist > 0.1 then
                local line = Instance.new("Part")
                line.Size = Vector3.new(0.2, 0.2, dist)
                line.CFrame = CFrame.new(prevWp.Position:Lerp(wp.Position, 0.5) + Vector3.new(0, 1, 0), wp.Position + Vector3.new(0, 1, 0))
                line.Color = Color3.fromRGB(0, 200, 255)
                line.Material = Enum.Material.Neon
                line.Anchored = true
                line.CanCollide = false
                line.Parent = pathFolder
            end
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

-- === NAVIGATION ENGINE (WITH RAYCAST WALL UN-STICK) ===
local function stopMovement()
    followingPlayer = nil
    navigationVersion = navigationVersion + 1
    if activePathTask then
        task.cancel(activePathTask)
        activePathTask = nil
    end
    stopEmote()
    clearPathVisuals()

    local myChar = LocalPlayer.Character
    if myChar then
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        local myHRP = myChar:FindFirstChild("HumanoidRootPart")
        if humanoid and myHRP then
            humanoid.WalkSpeed = WALK_SPEED
            humanoid:MoveTo(myHRP.Position)
        end
    end
end

StopFollowBtn.MouseButton1Click:Connect(function()
    stopMovement()
    sendMessage("Stopped following! ♡")
end)

local function navigateToPosition(targetPos, targetObject)
    stopEmote()
    navigationVersion = navigationVersion + 1
    local currentVersion = navigationVersion

    if activePathTask then
        task.cancel(activePathTask)
        activePathTask = nil
    end

    local yieldSignal = Instance.new("BindableEvent")

    activePathTask = task.spawn(function()
        local myChar = LocalPlayer.Character
        if not myChar then yieldSignal:Fire() return end
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        local myHRP = myChar:FindFirstChild("HumanoidRootPart")
        if not humanoid or not myHRP then yieldSignal:Fire() return end

        humanoid.WalkSpeed = RUN_SPEED

        -- Tighter Agent Parameters for tight Backrooms corners
        local path = PathfindingService:CreatePath({
            AgentRadius = 1.0,
            AgentHeight = 4.5,
            AgentCanJump = true
        })

        local success, _ = pcall(function() path:ComputeAsync(myHRP.Position, targetPos) end)

        if success and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()
            visualizePath(waypoints)

            for _, waypoint in ipairs(waypoints) do
                if navigationVersion ~= currentVersion then break end
                if waypoint.Action == Enum.PathWaypointAction.Jump then humanoid.Jump = true end

                humanoid:MoveTo(waypoint.Position)
                local startT = tick()

                while tick() - startT < 2.5 do
                    if navigationVersion ~= currentVersion then break end
                    if (myHRP.Position - waypoint.Position).Magnitude < 3 then break end
                    task.wait(0.05)
                end
            end
        else
            -- Raycast Fallback Navigation around walls
            local rayParams = RaycastParams.new()
            rayParams.FilterType = RaycastParamsFilterType.Exclude
            rayParams.FilterDescendantsInstances = {myChar}

            visualizePath({{Position = myHRP.Position}, {Position = targetPos}})
            local startT = tick()

            while (myHRP.Position - targetPos).Magnitude > 5 and tick() - startT < 10 do
                if navigationVersion ~= currentVersion then break end

                local dir = (targetPos - myHRP.Position).Unit
                local rayResult = workspace:Raycast(myHRP.Position, dir * 4, rayParams)

                if rayResult then
                    local sideDir = dir:Cross(Vector3.new(0, 1, 0))
                    humanoid:MoveTo(myHRP.Position + sideDir * 5)
                    humanoid.Jump = true
                    task.wait(0.4)
                else
                    humanoid:MoveTo(targetPos)
                end

                task.wait(0.1)
            end
        end

        if navigationVersion == currentVersion and targetObject then
            if targetObject:IsA("Tool") then
                humanoid:EquipTool(targetObject)
            else
                local prompt = targetObject:FindFirstChildWhichIsA("ProximityPrompt", true)
                if prompt then fireproximityprompt(prompt) end
            end
        end

        clearPathVisuals()
        yieldSignal:Fire()
    end)

    yieldSignal.Event:Wait()
    yieldSignal:Destroy()
end

local function startFollowingPlayer(targetPlayer)
    stopMovement()
    followingPlayer = targetPlayer
    navigationVersion = navigationVersion + 1
    local currentVersion = navigationVersion

    activePathTask = task.spawn(function()
        while followingPlayer and followingPlayer.Character and navigationVersion == currentVersion do
            local targetHRP = followingPlayer.Character:FindFirstChild("HumanoidRootPart")
            local myChar = LocalPlayer.Character
            if not myChar or not targetHRP then break end
            local myHRP = myChar:FindFirstChild("HumanoidRootPart")
            local humanoid = myChar:FindFirstChildOfClass("Humanoid")
            if not myHRP or not humanoid then break end

            humanoid.WalkSpeed = RUN_SPEED
            local distance = (myHRP.Position - targetHRP.Position).Magnitude

            if distance > 6 then
                navigateToPosition(targetHRP.Position, nil)
            else
                humanoid:MoveTo(myHRP.Position)
                clearPathVisuals()
                task.wait(0.5)
            end
        end
    end)
end

-- === COMMAND EXECUTION ===
local function processSingleAction(player, actionStr)
    local cmd = actionStr:lower():gsub("^%s*(.-)%s*$", "%1")

    if cmd:find("jump") then
        local myChar = LocalPlayer.Character
        if myChar and myChar:FindFirstChildOfClass("Humanoid") then
            myChar:FindFirstChildOfClass("Humanoid").Jump = true
        end
    elseif cmd:find("emote") or cmd:find("dance") then
        playEmote(cmd)
    elseif cmd:find("follow") then
        startFollowingPlayer(player)
    elseif cmd:find("come") or cmd:find("goto") or cmd:find("go to") or cmd:find("head to") then
        if player and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            navigateToPosition(player.Character.HumanoidRootPart.Position, nil)
        end
    elseif cmd:find("stop") then
        stopMovement()
    end
end

-- === SINGLE REQUEST AI CALL ===
local function queryAI(promptText, senderName)
    if not request then return nil end

    local payload = HttpService:JSONEncode({
        model = "openrouter/auto",
        max_tokens = 35,
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
            if type(rawContent) == "string" and #rawContent > 0 then
                return rawContent:gsub("<think>.-</think>", ""):gsub("%b[]", ""):gsub('^"', ''):gsub('"$', ''):gsub("^%s*(.-)%s*$", "%1")
            end
        end
    end

    return nil
end

-- === CHAT DEBOUNCE HOOK ===
local function processIncomingMessage(player, messageText)
    if not botEnabled or player == LocalPlayer then return end
    
    -- HARD LOCKOUT: Ignores microsecond duplicate events
    if tick() - lastChatTimestamp < 3 then return end

    local lowerMsg = messageText:lower()

    if lowerMsg:find("silent") or lowerMsg:find("bot") then
        lastChatTimestamp = tick()

        processSingleAction(player, lowerMsg)

        task.spawn(function()
            local reply = queryAI(messageText, player.DisplayName or player.Name)
            if reply then 
                sendMessage(reply) 
            end
        end)
    end
end

-- SINGLE CHAT BINDING
if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
    TextChatService.MessageReceived:Connect(function(textChatMessage)
        if textChatMessage and textChatMessage.TextSource then
            local player = Players:GetPlayerByUserId(textChatMessage.TextSource.UserId)
            if player then 
                processIncomingMessage(player, textChatMessage.Text) 
            end
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
