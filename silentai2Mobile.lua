-- === EXECUTOR GLOBAL TEARDOWN & INSTANCE KILLER ===
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
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer
    local uiParent = (gethui and gethui()) or CoreGui or (LocalPlayer and LocalPlayer:WaitForChild("PlayerGui"))

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

-- === SERVICES & RESOLUTION ===
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PathfindingService = game:GetService("PathfindingService")
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

while not LocalPlayer do
    task.wait(0.1)
    LocalPlayer = Players.LocalPlayer
end

local request = request or http.request or http_request or (syn and syn.request) or (fluxus and fluxus.request) or (delta and delta.request)
local uiParent = (gethui and gethui()) or CoreGui or LocalPlayer:WaitForChild("PlayerGui")

-- Configurations & API Keys
local OPENROUTER_API_KEY = "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"
local OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

local RUN_SPEED = 24
local botEnabled = true
local isProcessingGlobal = false
local lastChatTimestamp = 0
local navigationVersion = 0

local STRICT_RULE = " Respond ONLY with plain spoken dialogue. NO markdown, NO special symbols, NO quotes. Max 8 words."

local currentModeIndex = 1
local Modes = {
    { Name = "OwO Mode", Prompt = "You are an ultra-cute anime furry bot named Silent. Respond in OwO style with stutters." .. STRICT_RULE },
    { Name = "Tsundere Mode", Prompt = "You are a flustered anime Tsundere bot named Silent. Respond with denial, baka, and sass." .. STRICT_RULE },
    { Name = "Yandere Mode", Prompt = "You are a dark possessive Yandere bot named Silent. Respond with intense affection." .. STRICT_RULE }
}

-- === GUI BUILDER ===
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SilentAIBotNative"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 99999999
ScreenGui.Parent = uiParent

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(0, 50, 0, 50)
ToggleBtn.Position = UDim2.new(0, 15, 0.3, 0)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 25, 45)
ToggleBtn.Text = "🌸"
ToggleBtn.TextSize = 24
ToggleBtn.Parent = ScreenGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 240, 0, 220)
MainFrame.Position = UDim2.new(0, 75, 0.3, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 18, 28)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local BotToggleBtn = Instance.new("TextButton")
BotToggleBtn.Size = UDim2.new(0.9, 0, 0, 30)
BotToggleBtn.Position = UDim2.new(0.05, 0, 0.2, 0)
BotToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
BotToggleBtn.Text = "BOT: ON"
BotToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
BotToggleBtn.Parent = MainFrame

local ModeBtn = Instance.new("TextButton")
ModeBtn.Size = UDim2.new(0.9, 0, 0, 30)
ModeBtn.Position = UDim2.new(0.05, 0, 0.4, 0)
ModeBtn.BackgroundColor3 = Color3.fromRGB(60, 50, 80)
ModeBtn.Text = "Mode: OwO Mode"
ModeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ModeBtn.Parent = MainFrame

local UnloadBtn = Instance.new("TextButton")
UnloadBtn.Size = UDim2.new(0.9, 0, 0, 30)
UnloadBtn.Position = UDim2.new(0.05, 0, 0.72, 0)
UnloadBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
UnloadBtn.Text = "UNLOAD SCRIPT"
UnloadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
UnloadBtn.Parent = MainFrame

table.insert(scriptConnections, ToggleBtn.MouseButton1Click:Connect(function() MainFrame.Visible = not MainFrame.Visible end))
table.insert(scriptConnections, BotToggleBtn.MouseButton1Click:Connect(function()
    botEnabled = not botEnabled
    BotToggleBtn.Text = botEnabled and "BOT: ON" or "BOT: OFF"
    BotToggleBtn.BackgroundColor3 = botEnabled and Color3.fromRGB(40, 160, 80) or Color3.fromRGB(160, 50, 50)
end))
table.insert(scriptConnections, ModeBtn.MouseButton1Click:Connect(function()
    currentModeIndex = (currentModeIndex % #Modes) + 1
    ModeBtn.Text = "Mode: " .. Modes[currentModeIndex].Name
end))
table.insert(scriptConnections, UnloadBtn.MouseButton1Click:Connect(function()
    if env.SilentBotCleanup then env.SilentBotCleanup() end
end))

-- === HIGH-VISIBILITY PATH RENDERER ===
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

-- === CHAT SENDER ===
local function sendMessage(msg)
    if not msg or msg == "" then return end
    local cleanMsg = msg:gsub('[%*#_~`"]', ''):gsub('%s+', ' ')
    
    pcall(function()
        local textChannels = TextChatService:FindFirstChild("TextChannels")
        if textChannels then
            local general = textChannels:FindFirstChild("RBXGeneral")
            if general then
                general:SendAsync(cleanMsg)
                return
            end
        end
        local sayRemote = game:GetService("ReplicatedStorage"):FindFirstChild("SayMessageRequest", true)
        if sayRemote then sayRemote:FireServer(cleanMsg, "All") end
    end)
end

-- === MOVEMENT ENGINE ===
local function stopMovement()
    navigationVersion = navigationVersion + 1
    if env.SilentBotActiveTask then
        pcall(function() task.cancel(env.SilentBotActiveTask) end)
        env.SilentBotActiveTask = nil
    end
    clearPathVisuals()
    local myChar = LocalPlayer.Character
    if myChar and myChar:FindFirstChildOfClass("Humanoid") then
        myChar:FindFirstChildOfClass("Humanoid"):MoveTo(myChar.HumanoidRootPart.Position)
    end
end

local function navigateToTargetPlayer(targetPlayer)
    stopMovement()
    navigationVersion = navigationVersion + 1
    local currentVersion = navigationVersion

    env.SilentBotActiveTask = task.spawn(function()
        local myChar = LocalPlayer.Character
        if not myChar then return end
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        local myHRP = myChar:FindFirstChild("HumanoidRootPart")
        if not humanoid or not myHRP then return end

        humanoid.WalkSpeed = RUN_SPEED

        while isScriptAlive and navigationVersion == currentVersion do
            if not targetPlayer.Character or not targetPlayer.Character:FindFirstChild("HumanoidRootPart") then break end
            local targetHRP = targetPlayer.Character.HumanoidRootPart
            local distance = (myHRP.Position - targetHRP.Position).Magnitude

            if distance <= 4.5 then
                break -- DESTINATION REACHED
            end

            local path = PathfindingService:CreatePath({ AgentRadius = 1.2, AgentHeight = 5.0, AgentCanJump = true })
            local success, _ = pcall(function() path:ComputeAsync(myHRP.Position, targetHRP.Position) end)

            if success and path.Status == Enum.PathStatus.Success then
                local waypoints = path:GetWaypoints()
                visualizePath(waypoints)

                for _, waypoint in ipairs(waypoints) do
                    if not isScriptAlive or navigationVersion ~= currentVersion then break end
                    if waypoint.Action == Enum.PathWaypointAction.Jump then humanoid.Jump = true end

                    humanoid:MoveTo(waypoint.Position)
                    local lastPos = myHRP.Position
                    local waypointStartTime = tick()

                    while isScriptAlive and tick() - waypointStartTime < 1.5 do
                        if navigationVersion ~= currentVersion then break end
                        if (myHRP.Position - waypoint.Position).Magnitude < 3.5 then break end
                        
                        task.wait(0.1)
                        if (myHRP.Position - lastPos).Magnitude < 0.1 then
                            humanoid.Jump = true
                            myHRP.CFrame = myHRP.CFrame * CFrame.new(2.5, 0, -1)
                            break
                        end
                        lastPos = myHRP.Position
                    end
                end
            else
                visualizePath({{Position = myHRP.Position}, {Position = targetHRP.Position}})
                humanoid:MoveTo(targetHRP.Position)
                task.wait(0.5)
            end
            task.wait(0.1)
        end

        clearPathVisuals()
        if myHRP and humanoid then humanoid:MoveTo(myHRP.Position) end
    end)
end

-- === AI QUERY ===
local function queryAI(promptText, senderName)
    if not request then return nil end

    local payload = HttpService:JSONEncode({
        model = "openrouter/auto",
        max_tokens = 25,
        temperature = 0.6,
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

-- === CHAT CONNECTIONS ===
local function processIncomingMessage(player, messageText)
    if not isScriptAlive or not botEnabled or player == LocalPlayer then return end
    if isProcessingGlobal or (tick() - lastChatTimestamp < 4) then return end

    local lowerMsg = messageText:lower()

    if lowerMsg:find("silent") or lowerMsg:find("bot") then
        isProcessingGlobal = true
        lastChatTimestamp = tick()

        if lowerMsg:find("come") or lowerMsg:find("goto") or lowerMsg:find("here") or lowerMsg:find("follow") then
            navigateToTargetPlayer(player)
        elseif lowerMsg:find("stop") then
            stopMovement()
        end

        task.spawn(function()
            local reply = queryAI(messageText, player.DisplayName or player.Name)
            if reply and isScriptAlive then 
                sendMessage(reply) 
            end
            task.wait(1.5)
            isProcessingGlobal = false
        end)
    end
end

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
