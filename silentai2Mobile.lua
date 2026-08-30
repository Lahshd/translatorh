-- === DELTA & UNIVERSAL INITIALIZATION ===
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

while not LocalPlayer do
    task.wait(0.1)
    LocalPlayer = Players.LocalPlayer
end

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local request = request or http.request or http_request or (syn and syn.request) or (fluxus and fluxus.request) or (delta and delta.request)

-- === UNIQUE SCRIPT & GUI TAGGING ENGINE ===
-- Generate a unique identifier specific ONLY to this execution session
local SCRIPT_TAG_ID = "SILENT_BOT_TAG_" .. tostring(math.random(100000, 999999)) .. "_" .. tostring(os.clock())
local GUI_NAME = "SilentAIBotNative"

local env = getgenv and getgenv() or _G

-- Locate target UI container (CoreGui or PlayerGui)
local uiParent = (gethui and gethui()) or game:GetService("CoreGui") or PlayerGui

-- === SINGLE-INSTANCE SWEEP & DUPLICATE TERMINATION ===
local function purgeOldScriptInstances()
    -- 1. Execute global teardown if registered
    if env.SilentBotCleanup then
        pcall(function() env.SilentBotCleanup() end)
        task.wait(0.1)
    end

    -- 2. Scan UI container for existing GUIs with matching tags
    local function inspectAndDestroy(container)
        if not container then return end
        for _, child in ipairs(container:GetChildren()) do
            if child.Name == GUI_NAME then
                local tag = child:FindFirstChild("SilentBotInstanceTag")
                -- Check for two tags: one exists (found tag) and one isn't its own (tag.Value ~= SCRIPT_TAG_ID)
                if tag and tag:IsA("StringValue") and tag.Value ~= SCRIPT_TAG_ID then
                    child:Destroy() -- Delete entire GUI and all contained functionality
                elseif not tag then
                    -- Delete legacy untagged GUIs
                    child:Destroy()
                end
            end
        end
    end

    inspectAndDestroy(uiParent)
    if PlayerGui and uiParent ~= PlayerGui then
        inspectAndDestroy(PlayerGui)
    end
end

-- Run termination check before setting up the new GUI instance
purgeOldScriptInstances()

local isScriptAlive = true
local scriptConnections = {}

-- Register new global teardown handler bound strictly to this instance
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

    local oldFolder = Workspace:FindFirstChild("SilentPathVisuals")
    if oldFolder then oldFolder:Destroy() end

    for _, child in ipairs(uiParent:GetChildren()) do
        if child.Name == GUI_NAME then
            local tag = child:FindFirstChild("SilentBotInstanceTag")
            if tag and tag.Value == SCRIPT_TAG_ID then
                child:Destroy()
            end
        end
    end
end

-- Setup parameters & model fallbacks
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
local activePathTask = nil

local STRICT_RULE = " Respond ONLY with spoken in-character dialogue. Maximum 14 words. Base your answers on visual context if provided."
local currentModeIndex = 1
local Modes = {
    { Name = "OwO Mode", Prompt = "You are an ultra-cute anime furry bot named Silent. Respond in OwO style with stutters." .. STRICT_RULE },
    { Name = "Tsundere Mode", Prompt = "You are a flustered anime Tsundere bot named Silent. Respond with denial, 'b-baka!', and sass." .. STRICT_RULE },
    { Name = "Yandere Mode", Prompt = "You are a dark possessive Yandere bot named Silent. Respond with intense affection." .. STRICT_RULE }
}

-- === CREATE TAGGED NATIVE GUI ===
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = GUI_NAME
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 999999

-- Create unique Tag Object attached to this specific GUI
local GuiTag = Instance.new("StringValue")
GuiTag.Name = "SilentBotInstanceTag"
GuiTag.Value = SCRIPT_TAG_ID
GuiTag.Parent = ScreenGui

ScreenGui.Parent = uiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 240, 0, 180)
MainFrame.Position = UDim2.new(0, 70, 0.3, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 18, 28)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, 0, 0, 30)
TitleLabel.BackgroundColor3 = Color3.fromRGB(35, 30, 50)
TitleLabel.Text = "    🌸 Silent AI (Tagged GUI Instance)"
TitleLabel.TextColor3 = Color3.fromRGB(255, 180, 220)
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 11
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = MainFrame

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(0.9, 0, 0, 35)
StatusLabel.Position = UDim2.new(0.05, 0, 0.22, 0)
StatusLabel.Text = "Status: ACTIVE\nTagged ID: " .. SCRIPT_TAG_ID:sub(1, 18) .. "..."
StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextSize = 10
StatusLabel.TextWrapped = true
StatusLabel.Parent = MainFrame

-- === CHAT OUTBOUND ROUTER ===
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

-- === DEX-STYLE WORKSPACE SCANNER & PATHFINDER ===
local function findObjectInWorkspace(objectName)
    local targetQuery = objectName:lower():gsub("%s+", "")
    local bestMatch = nil
    local bestDist = math.huge
    local myChar = LocalPlayer.Character
    local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")

    if not myHRP then return nil, nil end

    for _, desc in ipairs(Workspace:GetDescendants()) do
        if desc:IsA("BasePart") or desc:IsA("Model") then
            local cleanName = desc.Name:lower():gsub("%s+", "")
            if cleanName:find(targetQuery) and not desc:FindFirstAncestorOfClass("Model"):FindFirstChildOfClass("Humanoid") then
                local pos = desc:IsA("BasePart") and desc.Position or (desc.PrimaryPart and desc.PrimaryPart.Position or desc:GetPivot().Position)
                local dist = (myHRP.Position - pos).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    bestMatch = desc
                end
            end
        end
    end

    if bestMatch then
        local targetPos = bestMatch:IsA("BasePart") and bestMatch.Position or (bestMatch.PrimaryPart and bestMatch.PrimaryPart.Position or bestMatch:GetPivot().Position)
        local fullPath = bestMatch:GetFullName()
        return targetPos, fullPath
    end

    return nil, nil
end

-- === RAYCAST AVATAR INSPECTOR ===
local function inspectPlayerAvatar(targetPlayer)
    if not targetPlayer or not targetPlayer.Character then return "Unknown appearance" end
    local char = targetPlayer.Character
    local info = {}

    local hairColors = {}
    for _, acc in ipairs(char:GetChildren()) do
        if acc:IsA("Accessory") then
            local handle = acc:FindFirstChild("Handle")
            if handle and (acc.Name:lower():find("hair") or acc.AccessoryType == Enum.AccessoryType.Hair) then
                table.insert(hairColors, handle.Color:ToHex() .. " (" .. acc.Name .. ")")
            end
        end
    end

    if #hairColors > 0 then
        table.insert(info, "Hair: " .. table.concat(hairColors, ", "))
    else
        table.insert(info, "Hair: Standard character head color")
    end

    local camera = Workspace.CurrentCamera
    local myChar = LocalPlayer.Character
    if camera and char:FindFirstChild("Head") and myChar and myChar:FindFirstChild("Head") then
        local params = RaycastParams.new()
        params.FilterAncestorsOfTypes = {myChar}
        params.FilterType = Enum.RaycastFilterType.Exclude

        local rayRes = Workspace:Raycast(myChar.Head.Position, char.Head.Position - myChar.Head.Position, params)
        if rayRes and rayRes.Instance:IsDescendantOf(char) then
            table.insert(info, "Line of Sight: Direct line to target head")
        else
            table.insert(info, "Line of Sight: Obstructed")
        end
    end

    return table.concat(info, " | ")
end

-- === PATH NAVIGATION ===
local function clearPathVisuals()
    local oldFolder = Workspace:FindFirstChild("SilentPathVisuals")
    if oldFolder then oldFolder:Destroy() end
end

local function stopMovement()
    if activePathTask or env.SilentBotActiveTask then 
        pcall(function() task.cancel(activePathTask or env.SilentBotActiveTask) end) 
        activePathTask = nil 
        env.SilentBotActiveTask = nil
    end
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

local function navigateToPosition(targetPos)
    stopMovement()
    activePathTask = task.spawn(function()
        env.SilentBotActiveTask = activePathTask
        local myChar = LocalPlayer.Character
        if not myChar then return end
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        local myHRP = myChar:FindFirstChild("HumanoidRootPart")
        if not humanoid or not myHRP then return end

        humanoid.WalkSpeed = RUN_SPEED
        humanoid:MoveTo(targetPos)
    end)
end

-- === AI QUERY EXECUTOR ===
local function queryAI(promptText, senderName, visualContext)
    if not request then return end
    local fullPrompt = senderName .. ": " .. promptText
    if visualContext and visualContext ~= "" then
        fullPrompt = fullPrompt .. " [Visual Context: " .. visualContext .. "]"
    end

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
                    return rawContent:gsub("<think>.-</think>", ""):gsub("%b[]", ""):gsub('"', ''):gsub("^%s*(.-)%s*$", "%1")
                end
            end
        end
        task.wait(0.3)
    end
    return nil
end

-- === INCOMING CHAT HANDLER ===
local function processIncomingMessage(player, messageText)
    if not isScriptAlive or not botEnabled or player == LocalPlayer then return end

    local lowerMsg = messageText:lower()

    if lowerMsg:find("silent") or lowerMsg:find("bot") then
        local visualData = inspectPlayerAvatar(player)
        
        if lowerMsg:find("go to") or lowerMsg:find("head to") or lowerMsg:find("walk to") then
            local targetObject = lowerMsg:match("go to (.-)$") or lowerMsg:match("head to (.-)$") or lowerMsg:match("walk to (.-)$")
            if targetObject then
                local objPos, fullPath = findObjectInWorkspace(targetObject)
                if objPos then
                    visualData = visualData .. " | Object Path: " .. tostring(fullPath)
                    navigateToPosition(objPos)
                end
            end
        end

        if not isProcessing then
            isProcessing = true
            task.spawn(function()
                local reply = queryAI(messageText, player.DisplayName or player.Name, visualData)
                if reply and isScriptAlive then sendMessage(reply) end
                isProcessing = false
            end)
        end
    end
end

-- Hook up chat listeners
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
