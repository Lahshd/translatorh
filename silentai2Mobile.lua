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

local SCRIPT_TAG_ID = "SILENT_BOT_TAG_" .. tostring(math.random(100000, 999999)) .. "_" .. tostring(os.clock())
local GUI_NAME = "SilentAIBotNative"
local env = getgenv and getgenv() or _G
local uiParent = (gethui and gethui()) or game:GetService("CoreGui") or PlayerGui

-- === SINGLE-INSTANCE SWEEP ===
local function purgeOldScriptInstances()
    if env.SilentBotCleanup then
        pcall(function() env.SilentBotCleanup() end)
        task.wait(0.1)
    end

    local function inspectAndDestroy(container)
        if not container then return end
        for _, child in ipairs(container:GetChildren()) do
            if child.Name == GUI_NAME then
                local tag = child:FindFirstChild("SilentBotInstanceTag")
                if tag and tag:IsA("StringValue") and tag.Value ~= SCRIPT_TAG_ID then
                    child:Destroy()
                elseif not tag then
                    child:Destroy()
                end
            end
        end
    end

    inspectAndDestroy(uiParent)
    if PlayerGui and uiParent ~= PlayerGui then inspectAndDestroy(PlayerGui) end
end

purgeOldScriptInstances()

local isScriptAlive = true
local scriptConnections = {}

env.SilentBotCleanup = function()
    isScriptAlive = false
    if env.SilentBotActiveTask then
        pcall(function() task.cancel(env.SilentBotActiveTask) end)
        env.SilentBotActiveTask = nil
    end
    for _, conn in ipairs(scriptConnections) do
        if conn and conn.Connected then pcall(function() conn:Disconnect() end) end
    end
    scriptConnections = {}
    for _, child in ipairs(uiParent:GetChildren()) do
        if child.Name == GUI_NAME then
            local tag = child:FindFirstChild("SilentBotInstanceTag")
            if tag and tag.Value == SCRIPT_TAG_ID then child:Destroy() end
        end
    end
end

-- Config Parameters
local OPENROUTER_API_KEY = "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"
local OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
local MODEL_FALLBACKS = {
    "openrouter/free",
    "meta-llama/llama-3.2-1b-instruct:free",
    "google/gemma-2-9b-it:free"
}

local RUN_SPEED = 24
local botEnabled = true
local isProcessing = false

local STRICT_RULE = " Maximum 18 words. You MUST incorporate the provided Visual Context details accurately into your spoken dialogue response while remaining in character."
local currentModeIndex = 3
local Modes = {
    { Name = "OwO Mode", Prompt = "You are an ultra-cute anime furry bot named Silent." .. STRICT_RULE },
    { Name = "Tsundere Mode", Prompt = "You are a flustered anime Tsundere bot named Silent." .. STRICT_RULE },
    { Name = "Yandere Mode", Prompt = "You are a possessive Yandere bot named Silent." .. STRICT_RULE }
}

-- === CREATE TAGGED GUI ===
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = GUI_NAME
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 999999

local GuiTag = Instance.new("StringValue")
GuiTag.Name = "SilentBotInstanceTag"
GuiTag.Value = SCRIPT_TAG_ID
GuiTag.Parent = ScreenGui
ScreenGui.Parent = uiParent

-- === CHAT ROUTER ===
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

-- === FIXED RAYCAST & AVATAR INSPECTOR ===
local function inspectPlayerAvatar(targetPlayer)
    if not targetPlayer or not targetPlayer.Character then return "Unknown appearance" end
    local char = targetPlayer.Character
    local info = {}

    local hairDetails = {}
    for _, acc in ipairs(char:GetChildren()) do
        if acc:IsA("Accessory") then
            local name = acc.Name
            if name:lower():find("hair") or acc.AccessoryType == Enum.AccessoryType.Hair then
                table.insert(hairDetails, name)
            end
        end
    end

    if #hairDetails > 0 then
        table.insert(info, "Hair: " .. table.concat(hairDetails, ", "))
    else
        table.insert(info, "Hair: Standard")
    end

    local shirt = char:FindFirstChildOfClass("Shirt")
    local pants = char:FindFirstChildOfClass("Pants")
    if shirt then table.insert(info, "Shirt: " .. shirt.Name) end
    if pants then table.insert(info, "Pants: " .. pants.Name) end

    -- Fixed Raycast implementation using FilterDescendantsInstances
    local camera = Workspace.CurrentCamera
    local myChar = LocalPlayer.Character
    if camera and char:FindFirstChild("Head") and myChar and myChar:FindFirstChild("Head") then
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = {myChar}
        params.FilterType = Enum.RaycastFilterType.Exclude

        local rayRes = Workspace:Raycast(myChar.Head.Position, char.Head.Position - myChar.Head.Position, params)
        if rayRes and rayRes.Instance:IsDescendantOf(char) then
            table.insert(info, "Line of Sight: Direct")
        else
            table.insert(info, "Line of Sight: Obstructed")
        end
    end

    return table.concat(info, " | ")
end

-- === PATHFINDING & BARITONE LOGIC ===
local function checkRay(origin, targetPos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LocalPlayer.Character}
    local result = Workspace:Raycast(origin, targetPos - origin, params)
    return result == nil
end

local function calculateBaritonePath(targetPos)
    local myChar = LocalPlayer.Character
    if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then return targetPos end
    local currentPos = myChar.HumanoidRootPart.Position
    
    if checkRay(currentPos, targetPos) then
        return targetPos
    end
    -- Fallback simple waypoint adjustment if direct line is blocked
    return targetPos
end

local function findTargetInWorkspace(query)
    local cleanQuery = query:lower():gsub("%s+", "")
    local myChar = LocalPlayer.Character
    local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then return nil end

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and (p.Name:lower():find(cleanQuery) or p.DisplayName:lower():find(cleanQuery)) then
            if p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                return p.Character.HumanoidRootPart.Position, p.DisplayName
            end
        end
    end

    local bestMatch = nil
    local bestDist = math.huge
    for _, desc in ipairs(Workspace:GetDescendants()) do
        if desc:IsA("BasePart") or desc:IsA("Model") then
            local name = desc.Name:lower():gsub("%s+", "")
            if name:find(cleanQuery) then
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
        local pos = bestMatch:IsA("BasePart") and bestMatch.Position or (bestMatch.PrimaryPart and bestMatch.PrimaryPart.Position or bestMatch:GetPivot().Position)
        return calculateBaritonePath(pos), bestMatch.Name
    end

    return nil, nil
end

local function moveToTarget(targetPos)
    if env.SilentBotActiveTask then
        pcall(function() task.cancel(env.SilentBotActiveTask) end)
    end

    env.SilentBotActiveTask = task.spawn(function()
        local myChar = LocalPlayer.Character
        if not myChar then return end
        local humanoid = myChar:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end

        humanoid.WalkSpeed = RUN_SPEED
        humanoid:MoveTo(targetPos)
    end)
end

-- === AI QUERY ===
local function queryAI(promptText, senderName, visualContext)
    if not request then return end
    local fullPrompt = senderName .. " says: " .. promptText
    if visualContext and visualContext ~= "" then
        fullPrompt = fullPrompt .. "\n[Visual Context: " .. visualContext .. "]"
    end

    for i = 1, #MODEL_FALLBACKS do
        local payload = HttpService:JSONEncode({
            model = MODEL_FALLBACKS[i],
            max_tokens = 70,
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
        task.wait(0.2)
    end
    return nil
end

-- === INCOMING MESSAGE PROCESSOR ===
local function processIncomingMessage(player, messageText)
    if not isScriptAlive or not botEnabled or player == LocalPlayer then return end

    local lowerMsg = messageText:lower()
    if lowerMsg:find("silent") or lowerMsg:find("bot") then
        local visualData = inspectPlayerAvatar(player)
        
        local targetQuery = nil
        if lowerMsg:find("follow me") or lowerMsg:find("follow") then
            targetQuery = player.Name
        elseif lowerMsg:find("find") or lowerMsg:find("go to") or lowerMsg:find("head to") or lowerMsg:find("get") then
            targetQuery = lowerMsg:match("find (.-)$") or lowerMsg:match("go to (.-)$") or lowerMsg:match("head to (.-)$") or lowerMsg:match("get (.-)$")
        end

        if targetQuery then
            local pos, foundName = findTargetInWorkspace(targetQuery)
            if pos then
                visualData = visualData .. " | Target Location Found: " .. tostring(foundName)
                moveToTarget(pos)
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

-- === LISTENERS ===
pcall(function()
    if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
        table.insert(scriptConnections, TextChatService.MessageReceived:Connect(function(textChatMessage)
            if textChatMessage and textChatMessage.TextSource then
                local player = Players:GetPlayerByUserId(textChatMessage.TextSource.UserId)
                if player then processIncomingMessage(player, textChatMessage.Text) end
            end
        end))
    else
        for _, p in ipairs(Players:GetPlayers()) do
            table.insert(scriptConnections, p.Chatted:Connect(function(msg) processIncomingMessage(p, msg) end))
        end
        table.insert(scriptConnections, Players.PlayerAdded:Connect(function(p)
            table.insert(scriptConnections, p.Chatted:Connect(function(msg) processIncomingMessage(p, msg) end))
        end))
    end
end)
