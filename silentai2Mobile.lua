-- === MOBILE COMPATIBLE SILENT BOT SCRIPT ===
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

-- Clean up any old instances safely
for _, child in ipairs(PlayerGui:GetChildren()) do
    if child.Name == "SilentAIBotMobile" then
        child:Destroy()
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
local Modes = {
    { Name = "Yandere Mode", Prompt = "You are a possessive Yandere bot named Silent." .. STRICT_RULE }
}

-- === ON-SCREEN STATUS GUI (Visible on Mobile) ===
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SilentAIBotMobile"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = PlayerGui

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(0, 200, 0, 35)
StatusLabel.Position = UDim2.new(0, 10, 0, 10)
StatusLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
StatusLabel.BackgroundTransparency = 0.5
StatusLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
StatusLabel.TextSize = 14
StatusLabel.Font = Enum.Font.SourceSansBold
StatusLabel.Text = "SilentBot: Active"
StatusLabel.Parent = ScreenGui

local function updateStatus(text)
    StatusLabel.Text = "SilentBot: " .. text
    task.delay(3, function()
        if StatusLabel and StatusLabel.Parent then
            StatusLabel.Text = "SilentBot: Active"
        end
    end)
end

-- === CHAT SENDER ===
local function sendMessage(msg)
    if not msg or msg == "" then return end
    pcall(function()
        local textChannels = TextChatService:FindFirstChild("TextChannels")
        if textChannels and textChannels:FindFirstChild("RBXGeneral") then
            textChannels.RBXGeneral:SendAsync(msg)
            return
        end
        local sayRemote = game:GetService("ReplicatedStorage"):FindFirstChild("SayMessageRequest", true)
        if sayRemote then 
            sayRemote:FireServer(msg, "All") 
        end
    end)
end

-- === AVATAR & TARGET SCANNER ===
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
    table.insert(info, #hairDetails > 0 and ("Hair: " .. table.concat(hairDetails, ", ")) or "Hair: Standard")

    local shirt = char:FindFirstChildOfClass("Shirt")
    local pants = char:FindFirstChildOfClass("Pants")
    if shirt then table.insert(info, "Shirt: " .. shirt.Name) end
    if pants then table.insert(info, "Pants: " .. pants.Name) end

    return table.concat(info, " | ")
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
        return bestMatch:IsA("BasePart") and bestMatch.Position or (bestMatch.PrimaryPart and bestMatch.PrimaryPart.Position or bestMatch:GetPivot().Position), bestMatch.Name
    end

    return nil, nil
end

local function moveToTarget(targetPos)
    pcall(function()
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
    if not request then return "Error: No HTTP request library found" end
    local fullPrompt = senderName .. " says: " .. promptText
    if visualContext and visualContext ~= "" then
        fullPrompt = fullPrompt .. "\n[Visual Context: " .. visualContext + "]"
    end

    for i = 1, #MODEL_FALLBACKS do
        local payload = HttpService:JSONEncode({
            model = MODEL_FALLBACKS[i],
            max_tokens = 70,
            temperature = 0.7,
            messages = {
                { role = "system", content = Modes[1].Prompt },
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

-- === MESSAGE PROCESSOR ===
local function processIncomingMessage(player, messageText)
    if not botEnabled or player == LocalPlayer then return end

    local lowerMsg = messageText:lower()
    if lowerMsg:find("silent") or lowerMsg:find("bot") then
        updateStatus("Processing...")
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
                visualData = visualData .. " | Target Found: " .. tostring(foundName)
                moveToTarget(pos)
                updateStatus("Moving to " .. tostring(foundName))
            else
                updateStatus("Target not found")
            end
        end

        if not isProcessing then
            isProcessing = true
            task.spawn(function()
                local reply = queryAI(messageText, player.DisplayName or player.Name, visualData)
                if reply then 
                    sendMessage(reply) 
                    updateStatus("Replied!")
                end
                isProcessing = false
            end)
        end
    end
end

-- === UNIVERSAL CHAT LISTENER (Handles both TextChatService & Legacy Chatted) ===
pcall(function()
    if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
        TextChatService.MessageReceived:Connect(function(textChatMessage)
            if textChatMessage and textChatMessage.TextSource then
                local player = Players:GetPlayerByUserId(textChatMessage.TextSource.UserId)
                if player then processIncomingMessage(player, textChatMessage.Text) end
            end
        end)
    end
    
    -- Backup listener for legacy/fallback events
    for _, p in ipairs(Players:GetPlayers()) do
        p.Chatted:Connect(function(msg) processIncomingMessage(p, msg) end)
    end
    Players.PlayerAdded:Connect(function(p)
        p.Chatted:Connect(function(msg) processIncomingMessage(p, msg) end)
    end)
end)

updateStatus("Ready!")
