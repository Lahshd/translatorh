-- === SILENT AI BOT v16 (FIXED RAYFIELD TABS + GROQ openai/gpt-oss-20b + MOVEMENT/CHAT) ===
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PathfindingService = game:GetService("PathfindingService")
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

while not LocalPlayer do
    task.wait(0.1)
    LocalPlayer = Players.LocalPlayer
end

local request = request or http.request or http_request or (syn and syn.request) or (fluxus and fluxus.request) or (delta and delta.request)
local uiParent = (gethui and gethui()) or CoreGui or LocalPlayer:WaitForChild("PlayerGui")

-- Clean up old fallback GUIs
pcall(function()
    for _, gui in ipairs(uiParent:GetChildren()) do
        if gui.Name == "SilentAIBotFallback" then
            gui:Destroy()
        end
    end
end)

-- === GROQ & BOT CONFIG ===
local GROQ_API_KEY = "gsk_YOUR_GROQ_API_KEY_HERE"
local GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
local GROQ_MODEL = "openai/gpt-oss-20b"

local MAX_TOKENS = 220
local TEMPERATURE = 0.75
local MAX_RETRIES = 3
local RETRY_DELAY = 2

local WALK_SPEED = 16
local RUN_SPEED = 36

local botEnabled = true
local isSprinting = false
local isProcessing = false
local followingPlayer = nil
local currentPathId = 0
local currentAnimationTrack = nil
local pathFolder = nil
local nextGroqRequestAt = 0

local STRICT_RULE = " Respond ONLY with spoken in-character dialogue. Maximum 12 words. Do not output thinking, reasoning, or meta remarks."

local currentModeIndex = 1
local Modes = {
    { Name = "OwO Mode", Prompt = "You are an ultra-cute anime furry bot named Silent. Respond in OwO style with stutters." .. STRICT_RULE },
    { Name = "Tsundere Mode", Prompt = "You are a flustered anime Tsundere bot named Silent. Respond with denial, 'b-baka!', and sass." .. STRICT_RULE },
    { Name = "Yandere Mode", Prompt = "You are a dark possessive Yandere bot named Silent. Respond with intense affection and subtle threats." .. STRICT_RULE }
}

local HardcodedEmotes = {
    ["qt"] = "rbxassetid://507770818",
    ["california girls"] = "rbxassetid://591745989",
    ["captain dance"] = "rbxassetid://10214311282"
}

local function Trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function StripReasoningAndClean(raw)
    if type(raw) ~= "string" then return "" end
    local text = raw
    for _, tag in ipairs({ "think", "thinking", "analysis", "reasoning" }) do
        local lower = text:lower()
        local openStart, openEnd = lower:find("<" .. tag .. "%f[%s>][^>]*>")
        while openStart do
            local _, closeEnd = lower:find("</" .. tag .. "%s*>", openEnd + 1)
            text = text:sub(1, openStart - 1) .. (closeEnd and text:sub(closeEnd + 1) or "")
            lower = text:lower()
            openStart, openEnd = lower:find("<" .. tag .. "%f[%s>][^>]*>")
        end
        local _, closeEnd = text:lower():find("</" .. tag .. "%s*>")
        if closeEnd then
            text = text:sub(closeEnd + 1)
        end
    end
    text = text:gsub("%b[]", ""):gsub('^"', ''):gsub('"$', '')
    return Trim(text):gsub("%s+", " ")
end

-- === CHAT SENDER ===
local function sendMessage(msg)
    msg = StripReasoningAndClean(msg)
    if msg == "" then return end
    pcall(function()
        local textChannels = TextChatService:FindFirstChild("TextChannels")
        if textChannels then
            local general = textChannels:FindFirstChild("RBXGeneral")
            if general then general:SendAsync(msg); return end
        end
        local sayRemote = game:GetService("ReplicatedStorage"):FindFirstChild("SayMessageRequest", true)
        if sayRemote then sayRemote:FireServer(msg, "All") end
    end)
end

-- === GROQ API (openai/gpt-oss-20b) ===
local function queryGroq(promptText, senderName)
    if type(request) ~= "function" then
        return nil, "Executor HTTP request function missing."
    end
    local cleanKey = Trim(GROQ_API_KEY)
    if cleanKey == "" or cleanKey:match("^gsk_YOUR_") then
        return nil, "Set GROQ_API_KEY first."
    end

    local now = os.clock()
    if now < nextGroqRequestAt then
        task.wait(math.min(nextGroqRequestAt - now, 5))
    end

    local payload = HttpService:JSONEncode({
        model = GROQ_MODEL,
        max_tokens = MAX_TOKENS,
        temperature = TEMPERATURE,
        messages = {
            { role = "system", content = Modes[currentModeIndex].Prompt },
            { role = "user", content = tostring(senderName or "Player") .. ": " .. tostring(promptText or "") }
        }
    })

    local lastErr = "No response from Groq."
    for attempt = 1, MAX_RETRIES do
        local ok, res = pcall(function()
            return request({
                Url = GROQ_URL,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["Authorization"] = "Bearer " .. cleanKey
                },
                Body = payload
            })
        end)

        if ok and type(res) == "table" then
            local code = tonumber(res.StatusCode or res.Status) or 0
            if code >= 200 and code < 300 and type(res.Body) == "string" then
                local decodedOk, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
                if decodedOk and type(data) == "table" and type(data.choices) == "table" and data.choices[1] then
                    local msg = data.choices[1].message
                    local rawContent = type(msg) == "table" and msg.content or ""
                    if type(rawContent) == "table" then
                        local parts = {}
                        for _, part in ipairs(rawContent) do
                            if type(part) == "table" and type(part.text) == "string" then
                                table.insert(parts, part.text)
                            end
                        end
                        rawContent = table.concat(parts, " ")
                    end
                    local cleaned = StripReasoningAndClean(rawContent)
                    if cleaned ~= "" then
                        return cleaned, nil
                    end
                    lastErr = "Model returned empty text."
                else
                    lastErr = "Invalid JSON from Groq."
                end
            elseif code == 429 then
                nextGroqRequestAt = os.clock() + 10
                lastErr = "Groq rate limited (429)."
                break
            else
                lastErr = "Groq HTTP " .. tostring(code)
                if code < 500 and code ~= 408 then
                    break
                end
            end
        else
            lastErr = "Groq network request failed."
        end

        if attempt < MAX_RETRIES then
            task.wait(RETRY_DELAY * attempt)
        end
    end

    return nil, lastErr
end

local function triggerTestReply(notifyFn)
    if isProcessing then return end
    isProcessing = true
    task.spawn(function()
        local reply, err = queryGroq("Say hi in under 8 words.", LocalPlayer.Name)
        if reply then
            sendMessage(reply)
        else
            warn("[Silent AI] " .. tostring(err))
            if notifyFn then notifyFn("Groq Error", tostring(err)) end
        end
        isProcessing = false
    end)
end

-- === SPRINT & MOVEMENT ===
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
        isSprinting = true
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = RUN_SPEED end
    end
end)

UserInputService.InputEnded:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
        isSprinting = false
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = WALK_SPEED end
    end
end)

local function stopMovement()
    currentPathId = currentPathId + 1
    followingPlayer = nil
    if currentAnimationTrack then currentAnimationTrack:Stop() end
    if pathFolder then pathFolder:Destroy(); pathFolder = nil end

    local myChar = LocalPlayer.Character
    if myChar then
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = isSprinting and RUN_SPEED or WALK_SPEED
            if myChar:FindFirstChild("HumanoidRootPart") then
                humanoid:MoveTo(myChar.HumanoidRootPart.Position)
            end
        end
    end
end

local function clearPathVisuals()
    if pathFolder then pathFolder:Destroy(); pathFolder = nil end
end

local function visualizePath(waypoints)
    clearPathVisuals()
    pathFolder = Instance.new("Folder")
    pathFolder.Name = "SilentPathVisuals"
    pathFolder.Parent = workspace

    for _, wp in ipairs(waypoints) do
        local node = Instance.new("Part")
        node.Size = Vector3.new(0.6, 0.6, 0.6)
        node.Position = wp.Position
        node.Shape = Enum.PartType.Ball
        node.Color = Color3.fromRGB(146, 222, 184)
        node.Material = Enum.Material.Neon
        node.Anchored = true
        node.CanCollide = false
        node.Parent = pathFolder
    end
end

local function playEmote(emoteQuery)
    if currentAnimationTrack then currentAnimationTrack:Stop() end
    local myChar = LocalPlayer.Character
    local humanoid = myChar and myChar:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local lowerQuery = emoteQuery:lower()
    local animId = nil
    for name, id in pairs(HardcodedEmotes) do
        if lowerQuery:find(name) then animId = id; break end
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

local function findClosestMapObject(query, referencePos)
    local bestPos = nil
    local bestDist = math.huge
    local lowerQuery = query:lower()

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") or obj:IsA("Model") then
            if not obj:FindFirstChildOfClass("Humanoid") and not (obj.Parent and obj.Parent:FindFirstChildOfClass("Humanoid")) then
                if obj.Name:lower():find(lowerQuery) then
                    local pos = obj:IsA("Model") and obj:GetBoundingBox().Position or obj.Position
                    local dist = (pos - referencePos).Magnitude
                    if dist < bestDist then
                        bestDist = dist
                        bestPos = pos
                    end
                end
            end
        end
    end
    return bestPos
end

local function moveWithTimeout(humanoid, targetPosition, mutexId)
    if currentPathId ~= mutexId then return false end
    humanoid:MoveTo(targetPosition)
    local moveFinished = false
    local conn = humanoid.MoveToFinished:Connect(function() moveFinished = true end)
    local t = 0
    while not moveFinished and t < 150 and currentPathId == mutexId do
        task.wait(0.1)
        t = t + 1
    end
    conn:Disconnect()
    return currentPathId == mutexId
end

local function navigateToPosition(targetPos, targetTool)
    currentPathId = currentPathId + 1
    local thisPathId = currentPathId

    task.spawn(function()
        local myChar = LocalPlayer.Character
        local humanoid = myChar and myChar:FindFirstChildOfClass("Humanoid")
        local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not humanoid or not myHRP then return end

        humanoid.WalkSpeed = RUN_SPEED
        local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
        local success = pcall(function() path:ComputeAsync(myHRP.Position, targetPos) end)

        if success and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()
            visualizePath(waypoints)
            for _, waypoint in ipairs(waypoints) do
                if currentPathId ~= thisPathId then return end
                if waypoint.Action == Enum.PathWaypointAction.Jump then humanoid.Jump = true end
                if not moveWithTimeout(humanoid, waypoint.Position, thisPathId) then return end
            end
        else
            moveWithTimeout(humanoid, targetPos, thisPathId)
        end

        if targetTool and targetTool:IsA("Tool") and currentPathId == thisPathId then
            humanoid:EquipTool(targetTool)
        end
        if currentPathId == thisPathId then clearPathVisuals() end
    end)
end

local function startFollowingPlayer(targetPlayer)
    stopMovement()
    followingPlayer = targetPlayer
    local thisPathId = currentPathId

    task.spawn(function()
        while followingPlayer and followingPlayer.Character and currentPathId == thisPathId do
            local targetHRP = followingPlayer.Character:FindFirstChild("HumanoidRootPart")
            local myChar = LocalPlayer.Character
            local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local humanoid = myChar and myChar:FindFirstChildOfClass("Humanoid")
            if not myHRP or not humanoid or not targetHRP then break end

            humanoid.WalkSpeed = RUN_SPEED
            local distance = (myHRP.Position - targetHRP.Position).Magnitude
            if distance > 6 then
                humanoid:MoveTo(targetHRP.Position)
                task.wait(0.3)
            else
                humanoid:MoveTo(myHRP.Position)
                task.wait(0.5)
            end
        end
    end)
end

local function equipItemByName(itemName)
    local myChar = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    local humanoid = myChar and myChar:FindFirstChildOfClass("Humanoid")
    if not humanoid or not backpack then return false end

    local lowerName = itemName:lower()
    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") and tool.Name:lower():find(lowerName) then
            humanoid:EquipTool(tool)
            return true
        end
    end
    return false
end

-- === COMMAND EXECUTION ===
local function processSingleAction(player, actionStr)
    local cmd = Trim(actionStr:lower())
    if cmd:find("jump") then
        local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid.Jump = true end
    elseif cmd:find("unequip") then
        local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid:UnequipTools() end
    elseif cmd:find("emote") or cmd:find("dance") then
        playEmote(cmd)
    elseif cmd:find("follow") then
        startFollowingPlayer(player)
    elseif cmd:find("look at me") or cmd:find("face me") then
        if player.Character and player.Character:FindFirstChild("Head") and player.Character:FindFirstChild("HumanoidRootPart") then
            local targetHead = player.Character.Head
            local targetHRP = player.Character.HumanoidRootPart
            local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if myHRP then
                myHRP.CFrame = CFrame.lookAt(myHRP.Position, Vector3.new(targetHRP.Position.X, myHRP.Position.Y, targetHRP.Position.Z))
                local cam = workspace.CurrentCamera
                if cam then cam.CFrame = CFrame.lookAt(cam.CFrame.Position, targetHead.Position) end
            end
        end
    elseif cmd:find("go to") or cmd:find("goto") or cmd:find("head to") or cmd:find("sit in") or cmd:find("come") then
        local targetPlayer = nil
        if cmd:find("me") or cmd:find("myself") or cmd:find("come") then
            targetPlayer = player
        else
            for _, p in ipairs(Players:GetPlayers()) do
                if cmd:find(p.Name:lower()) or cmd:find(p.DisplayName:lower()) then
                    targetPlayer = p
                    break
                end
            end
        end

        if targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
            navigateToPosition(targetPlayer.Character.HumanoidRootPart.Position, nil)
        else
            local objQuery = cmd:match("go to (.*)") or cmd:match("goto (.*)") or cmd:match("head to (.*)") or cmd:match("sit in (.*)")
            if objQuery then
                local refPos = (player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position)
                    or (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character.HumanoidRootPart.Position)
                if refPos then
                    local targetPos = findClosestMapObject(objQuery, refPos)
                    if targetPos then navigateToPosition(targetPos, nil) end
                end
            end
        end
    elseif cmd:find("equip") or cmd:find("take out") or cmd:find("find") or cmd:find("get") then
        local targetItem = cmd:match("equip%s+(.+)") or cmd:match("take out%s+(.+)") or cmd:match("find%s+(.+)") or cmd:match("get%s+(.+)")
        if targetItem then equipItemByName(targetItem) end
    elseif cmd == "stop" or cmd == "stop moving" or cmd == "halt" then
        stopMovement()
    end
end

local function executeSubCommands(player, fullMessage)
    task.spawn(function()
        local cleanedMsg = fullMessage:lower():gsub("^%s*silent%s*", ""):gsub(",", " and "):gsub("and then", "then")
        local chain = {}
        for _, segment in ipairs(cleanedMsg:split(" then ")) do
            for _, subSegment in ipairs(segment:split(" and ")) do
                local trimmed = Trim(subSegment)
                if trimmed ~= "" then table.insert(chain, trimmed) end
            end
        end
        for _, stepCmd in ipairs(chain) do
            processSingleAction(player, stepCmd)
            task.wait(1.5)
        end
    end)
end

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
                local reply, err = queryGroq(messageText, player.DisplayName or player.Name)
                if reply then
                    sendMessage(reply)
                else
                    warn("[Silent AI] " .. tostring(err))
                end
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

-- === RAYFIELD UI (DEFENSIVE) ===
local tabsCreated = false
local rayOk, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)

if rayOk and type(Rayfield) == "table" and type(Rayfield.CreateWindow) == "function" then
    local winOk, Window = pcall(function()
        return Rayfield:CreateWindow({
            Name = "Silent AI Bot · v16",
            LoadingTitle = "Silent AI Bot",
            LoadingSubtitle = "Groq (gpt-oss-20b)",
            ConfigurationSaving = { Enabled = false }
        })
    end)

    if winOk and Window and type(Window.CreateTab) == "function" then
        local aiTabOk, BotTab = pcall(function()
            return Window:CreateTab("AI & Chat")
        end)

        if aiTabOk and BotTab then
            tabsCreated = true
            pcall(function()
                BotTab:CreateToggle({
                    Name = "Bot Enabled",
                    CurrentValue = botEnabled,
                    Callback = function(val) botEnabled = val end
                })
            end)
            pcall(function()
                BotTab:CreateDropdown({
                    Name = "Persona Mode",
                    Options = { "OwO Mode", "Tsundere Mode", "Yandere Mode" },
                    CurrentOption = { Modes[currentModeIndex].Name },
                    Callback = function(opt)
                        local chosen = type(opt) == "table" and opt[1] or opt
                        for idx, m in ipairs(Modes) do
                            if m.Name == chosen then currentModeIndex = idx; break end
                        end
                    end
                })
            end)
            pcall(function()
                BotTab:CreateButton({
                    Name = "Test Groq Chat Reply",
                    Callback = function()
                        triggerTestReply(function(title, msg)
                            pcall(function()
                                Rayfield:Notify({ Title = title, Content = msg, Duration = 4 })
                            end)
                        end)
                    end
                })
            end)
        end

        local moveTabOk, MoveTab = pcall(function()
            return Window:CreateTab("Movement")
        end)

        if moveTabOk and MoveTab then
            tabsCreated = true
            pcall(function()
                MoveTab:CreateButton({
                    Name = "Stop Movement / Follow",
                    Callback = function()
                        stopMovement()
                        sendMessage("Stopped moving! ♡")
                    end
                })
            end)
        end
    end
end

if not tabsCreated then
    local gui = Instance.new("ScreenGui")
    gui.Name = "SilentAIBotFallback"
    gui.ResetOnSpawn = false
    gui.Parent = uiParent

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(200, 148)
    frame.Position = UDim2.new(0, 16, 0.3, 0)
    frame.BackgroundColor3 = Color3.fromRGB(27, 31, 33)
    frame.Active = true
    frame.Draggable = true
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

    local function mkBtn(text, y, fn)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -16, 0, 30)
        b.Position = UDim2.fromOffset(8, y)
        b.BackgroundColor3 = Color3.fromRGB(32, 48, 43)
        b.TextColor3 = Color3.fromRGB(146, 222, 184)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 11
        b.Text = text
        b.Parent = frame
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        b.MouseButton1Click:Connect(function() fn(b) end)
    end

    mkBtn("Bot: ON", 8, function(b)
        botEnabled = not botEnabled
        b.Text = botEnabled and "Bot: ON" or "Bot: OFF"
    end)

    mkBtn("Mode: " .. Modes[currentModeIndex].Name, 44, function(b)
        currentModeIndex = (currentModeIndex % #Modes) + 1
        b.Text = "Mode: " .. Modes[currentModeIndex].Name
    end)

    mkBtn("Test Groq Reply", 80, function()
        triggerTestReply()
    end)

    mkBtn("Stop Movement", 114, function()
        stopMovement()
        sendMessage("Stopped moving! ♡")
    end)
end

