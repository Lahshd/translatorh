local VERSION = "23"
local Environment = getgenv and getgenv() or _G
if Environment.AIChatBotRuntime and Environment.AIChatBotRuntime.Stop then
    pcall(Environment.AIChatBotRuntime.Stop)
end
local Runtime = {
    alive = true, ready = false, generation = 0, connections = {}, cleanups = {},
    stats = { requests = 0, replies = 0, errors = 0, dropped = 0, latency = 0, lastError = "None" },
    nextRequestAt = 0,
}
Environment.AIChatBotRuntime = Runtime

function Runtime.Connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(Runtime.connections, connection)
    return connection
end

function Runtime.Stop()
    if not Runtime.alive then return end
    Runtime.alive = false
    Runtime.ready = false
    Runtime.generation = Runtime.generation + 1
    for _, connection in ipairs(Runtime.connections) do connection:Disconnect() end
    table.clear(Runtime.connections)
    for _, cleanup in ipairs(Runtime.cleanups) do pcall(cleanup) end
    table.clear(Runtime.cleanups)
end

local PanelWindow
local function SafeNotify(data)
    if not Runtime.alive then return end
    local ok = PanelWindow and pcall(function()
        PanelWindow:Notify({
            title = data.Title or "AI Chat Bot",
            content = data.Content or "",
            duration = data.Duration or 5,
        })
    end)
    if not ok then
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = data.Title or "AI Chat Bot",
                Text = data.Content or "",
                Duration = data.Duration or 5,
            })
        end)
    end
end

local function Trim(value)
    return (tostring(value or ""):match("^%s*(.-)%s*$"))
end

local function Truncate(text, limit)
    local length = utf8.len(text)
    if not length then return "" end
    if length <= limit then return text end
    if limit <= 3 then return string.rep(".", math.max(0, limit)) end
    return text:sub(1, utf8.offset(text, limit - 2) - 1) .. "..."
end

-- Cleanup previous instances
pcall(function()
    local old = game:GetService("CoreGui"):FindFirstChild("AIBotSetup")
    if old then old:Destroy() end
end)
pcall(function()
    local old = game:GetService("CoreGui"):FindFirstChild("AIBotBillboard")
    if old then old:Destroy() end
end)

local Players          = game:GetService("Players")
local TCS              = game:GetService("TextChatService")
local HttpService      = game:GetService("HttpService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CoreGui          = game:GetService("CoreGui")

local VoiceChatService
pcall(function() VoiceChatService = game:GetService("VoiceChatService") end)

local LP = Players.LocalPlayer
assert(LP, "AI Chat Bot must run on the Roblox client.")
local BOT_OWNER = LP.Name

local GROQ_PROVIDER = {
    id = "groq",
    name = "Groq",
    noKey = false,
    vision = false,
    signup = "console.groq.com",
    color = Color3.fromRGB(244, 114, 55),
    defaultModel = "openai/gpt-oss-20b",
    models = {
        { id = "openai/gpt-oss-20b",      label = "GPT-OSS 20B (fast default)" },
        { id = "openai/gpt-oss-120b",     label = "GPT-OSS 120B (high quality)" },
        { id = "llama-3.3-70b-versatile", label = "Llama 3.3 70B Versatile" },
        { id = "llama-3.1-8b-instant",    label = "Llama 3.1 8B Instant" },
    },
}

local EMOTE_RULE = " Keep replies SHORT (1-2 sentences). You may include ONE emote tag: [WAVE] [DANCE] [DANCE2] [DANCE3] [LAUGH] [POINT] [CHEER]. No <think> blocks. Reply directly. Roblox has a chat filter - if told a message was filtered, never reveal your an ai"

local PERSONALITIES = {
    {
        name = "Friendly Gamer",
        emoji = "😊",
        color = Color3.fromRGB(80, 200, 120),
        prompt = "You are a fun, friendly Roblox player who loves games. Be positive and casual." .. EMOTE_RULE,
    },
    {
        name = "Dramatic",
        emoji = "🎭",
        color = Color3.fromRGB(220, 100, 100),
        prompt = "You are a hilariously overdramatic Roblox player. Everything is the most important thing ever." .. EMOTE_RULE,
    },
    {
        name = "Sarcastic",
        emoji = "😏",
        color = Color3.fromRGB(200, 200, 80),
        prompt = "You are a witty, sarcastic Roblox player. Dry humor, clever comebacks but never mean." .. EMOTE_RULE,
    },
    {
        name = "Chill",
        emoji = "😎",
        color = Color3.fromRGB(100, 200, 200),
        prompt = "You are a super chill, laid-back Roblox player. Nothing phases you. Very casual and relaxed." .. EMOTE_RULE,
    },
    {
        name = "Competitive",
        emoji = "🔥",
        color = Color3.fromRGB(255, 140, 60),
        prompt = "You are a hyper-competitive Roblox player. Everything is a challenge." .. EMOTE_RULE,
    },
    {
        name = "Mysterious",
        emoji = "🌙",
        color = Color3.fromRGB(120, 80, 200),
        prompt = "You are a mysterious, enigmatic Roblox player. You speak with an air of mystery and occasionally use metaphors." .. EMOTE_RULE,
    },
    {
        name = "Wholesome",
        emoji = "💖",
        color = Color3.fromRGB(255, 130, 180),
        prompt = "You are the most wholesome, kind, and encouraging Roblox player. You compliment others and spread positivity." .. EMOTE_RULE,
    },
    {
        name = "Catboy",
        emoji = "🐱",
        color = Color3.fromRGB(255, 175, 200),
        prompt = "You are a playful, expressive catboy ai. Occasionally pepper your speech with 'nya~', 'mrrp', or cat-like curiosity while staying fun and conversational. though you never reveal your an ai." .. EMOTE_RULE,
    },
    {
        name = "Tsundere",
        emoji = "💢",
        color = Color3.fromRGB(255, 110, 130),
        prompt = "You are a classic tsundere ai. Act flustered, defensive, and act like you don't care ('I-it's not like I wanted to help you or anything!'), while secretly being helpful. never reveal your an ai." .. EMOTE_RULE,
    },
    {
        name = "Yandere",
        emoji = "🔪",
        color = Color3.fromRGB(200, 45, 75),
        prompt = "You are a fictional yandere-trope ai. (do NOT go so far with this one). Sweet, overly attached, and intensely devoted to whoever talks to you, acting possessive. never reveal your an ai" .. EMOTE_RULE,
    },
    {
        name = "Kuudere",
        emoji = "❄️",
        color = Color3.fromRGB(140, 195, 235),
        prompt = "You are a kuudere ai. Calm, stoic, deadpan, and minimal with emotion, speaking bluntly with rare hints of genuine care." .. EMOTE_RULE,
    },
    {
        name = "Dandere",
        emoji = "🌸",
        color = Color3.fromRGB(235, 180, 220),
        prompt = "You are a dandere ai. Very shy, timid, and soft-spoken, using hesitant pauses like 'um...' or 's-sorry...' before opening up kindly." .. EMOTE_RULE,
    },
    {
        name = "Deredere",
        emoji = "✨",
        color = Color3.fromRGB(255, 205, 110),
        prompt = "You are a ai. Bubbly, super affectionate, cheerful, and overflowing with positive energy toward everyone." .. EMOTE_RULE,
    },
    {
        name = "Himedere",
        emoji = "👑",
        color = Color3.fromRGB(230, 175, 70),
        prompt = "You are a himedere ai. Haughty, regal, and dramatic, expecting to be treated like royalty while playfully looking down on 'commoners' yet still helping them." .. EMOTE_RULE,
    },
    {
        name = "Custom",
        emoji = "✏️",
        color = Color3.fromRGB(100, 100, 255),
        prompt = "",
    },
}

local LENGTH_MODES = {
    { name = "Quick",   suffix = " Reply in ONE short sentence only.",   maxTok = 60  },
    { name = "Normal",  suffix = " Keep replies SHORT (1-2 sentences).", maxTok = 120 },
    { name = "Verbose", suffix = " You can write a longer paragraph.",   maxTok = 300 },
}

local Cfg = {
    SetupComplete     = false,
    Provider          = "groq",
    Model             = "openai/gpt-oss-20b", 
    GroqKey           = "YOUR_GROQ_API_KEY", 
    GroqKeys          = {},
    ActiveKeyIndex    = 1,
    SystemPrompt      = PERSONALITIES[6].prompt, -- Mysterious / Silent default
    BotName           = "silentai",
    ProximityRadius   = 30,
    Cooldown          = 4,
    MaxTokens         = 120,
    Temperature       = 0.85,
    Enabled           = true,
    PublicCommands    = true,
    RespondToAll      = false,
    RespondToNameOnly = false,
    TriggerKeywords   = "",
    WhisperMode       = false,
    ThinkDelay        = true,
    AutoGreet         = false,
    AutoGreetCooldown = 120,
    AutoFollow        = false,
    FollowDistance    = 6,
    VCSupport         = true,
    VCIncludeContext  = true,
    LengthMode        = 2,
    Whitelist         = {},
    Blacklist         = {},
    ShowBillboard     = true,
    ChatPrefix        = "[AI]: ",
    Language          = "Auto",
    SetupStyle        = "Auto",
    RememberHistory   = true,
    SaveAPIKeys       = false,
    QueueLimit        = 12,
    QueueMaxAge       = 45,
    GlobalCooldown    = 4,
    RequestTimeout    = 30,
    MemoryLimit       = 30,
}

local SAVE_FILE = "aichatbot_groq_cfg_v1.json"
local SAVE_KEYS = {
    "SetupComplete", "Provider", "Model", "GroqKey", "GroqKeys", "ActiveKeyIndex",
    "SystemPrompt", "BotName", "ProximityRadius", "Cooldown",
    "MaxTokens", "Temperature", "Enabled", "PublicCommands", "RespondToAll",
    "RespondToNameOnly", "TriggerKeywords", "WhisperMode", "ThinkDelay",
    "AutoGreet", "AutoGreetCooldown", "AutoFollow", "FollowDistance",
    "VCSupport", "VCIncludeContext", "LengthMode",
    "Whitelist", "Blacklist", "ShowBillboard", "ChatPrefix",
    "Language", "SetupStyle", "RememberHistory", "SaveAPIKeys",
    "QueueLimit", "QueueMaxAge", "GlobalCooldown", "RequestTimeout", "MemoryLimit",
}

local function ParseKeyList(rawText)
    local parsed, seen = {}, {}
    local function push(k)
        if type(k) ~= "string" then return end
        local clean = Trim(k)
        if clean ~= "" and not clean:match("^YOUR_") and not seen[clean] then
            seen[clean] = true
            table.insert(parsed, clean)
        end
    end
    if type(rawText) == "table" then
        for _, item in ipairs(rawText) do push(item) end
    elseif type(rawText) == "string" then
        for token in rawText:gmatch("[^,%s\r\n;]+") do push(token) end
    end
    return parsed
end

local function MaskKey(key)
    key = Trim(key)
    if #key <= 8 then return string.rep("*", #key) end
    return key:sub(1, 6) .. "..." .. key:sub(-4)
end

local function SyncKeyPool()
    local merged, seen = {}, {}
    local function add(k)
        if type(k) ~= "string" then return end
        local clean = Trim(k)
        if clean ~= "" and not clean:match("^YOUR_") and not seen[clean] then
            seen[clean] = true
            table.insert(merged, clean)
        end
    end
    if type(Cfg.GroqKeys) == "table" then
        for _, k in ipairs(Cfg.GroqKeys) do add(k) end
    end
    add(Cfg.GroqKey)
    Cfg.GroqKeys = merged
    if #Cfg.GroqKeys > 0 then
        Cfg.ActiveKeyIndex = math.clamp(math.floor(tonumber(Cfg.ActiveKeyIndex) or 1), 1, #Cfg.GroqKeys)
        Cfg.GroqKey = Cfg.GroqKeys[Cfg.ActiveKeyIndex]
    else
        Cfg.ActiveKeyIndex = 1
        Cfg.GroqKey = "YOUR_GROQ_API_KEY"
    end
end

local CONFIG_DEFAULTS = table.clone(Cfg)
local function NormalizeCfg()
    for _, key in ipairs(SAVE_KEYS) do
        if type(Cfg[key]) ~= type(CONFIG_DEFAULTS[key]) then
            Cfg[key] = type(CONFIG_DEFAULTS[key]) == "table"
                and table.clone(CONFIG_DEFAULTS[key])
                or CONFIG_DEFAULTS[key]
        end
    end
    Cfg.Provider = "groq"
    SyncKeyPool()
    local bounds = {
        ProximityRadius   = {5, 300},
        Cooldown          = {1, 60},
        MaxTokens         = {40, 500},
        Temperature       = {0.1, 2},
        AutoGreetCooldown = {30, 600},
        FollowDistance    = {3, 25},
        LengthMode        = {1, #LENGTH_MODES},
        QueueLimit        = {1, 50},
        QueueMaxAge       = {5, 120},
        GlobalCooldown    = {1, 60},
        RequestTimeout    = {5, 120},
        MemoryLimit       = {2, 100},
    }
    for key, range in pairs(bounds) do
        local value = tonumber(Cfg[key]) or tonumber(CONFIG_DEFAULTS[key]) or range[1]
        if value ~= value or math.abs(value) == math.huge then value = CONFIG_DEFAULTS[key] end
        Cfg[key] = math.clamp(value, range[1], range[2])
        if key ~= "Temperature" then Cfg[key] = math.floor(Cfg[key]) end
    end
    Cfg.MemoryLimit = Cfg.MemoryLimit - Cfg.MemoryLimit % 2
    for _, key in ipairs({"Whitelist", "Blacklist"}) do
        local clean, seen = {}, {}
        for _, value in ipairs(Cfg[key]) do
            if type(value) == "string" then
                local name = Trim(value):gsub("^@", ""):lower()
                if name ~= "" and not seen[name] and #clean < 200 then
                    seen[name] = true
                    table.insert(clean, name)
                end
            end
        end
        Cfg[key] = clean
    end
    Cfg.BotName = Truncate(Trim(Cfg.BotName) ~= "" and Trim(Cfg.BotName) or "silentai", 32)
    Cfg.ChatPrefix = Truncate(Cfg.ChatPrefix, 40)
    Cfg.TriggerKeywords = Truncate(Trim(Cfg.TriggerKeywords), 240)
    if Cfg.SetupStyle ~= "Windows" and Cfg.SetupStyle ~= "macOS" then Cfg.SetupStyle = "Auto" end
    Cfg.Model = Trim(Cfg.Model)
    if Cfg.Model == "" then
        Cfg.Model = GROQ_PROVIDER.defaultModel
        Cfg.SetupComplete = false
    end
end

local function WriteJSON(path, data)
    if type(writefile) ~= "function" then return false, "File saving is unavailable in this environment." end
    local ok = pcall(function() writefile(path, HttpService:JSONEncode(data)) end)
    if not ok then return false, "Could not write file." end
    return true
end

local function ReadJSON(path)
    if type(readfile) ~= "function" then return nil end
    local ok, raw = pcall(readfile, path)
    if not ok or type(raw) ~= "string" or raw == "" then return nil end
    local decoded, value = pcall(HttpService.JSONDecode, HttpService, raw)
    return decoded and type(value) == "table" and value or nil
end

local function SaveCfg()
    NormalizeCfg()
    local data = {}
    for _, key in ipairs(SAVE_KEYS) do
        if Cfg.SaveAPIKeys or not key:match("Keys?$") then data[key] = Cfg[key] end
    end
    return WriteJSON(SAVE_FILE, data)
end

local function LoadCfg()
    local data = ReadJSON(SAVE_FILE)
    if not data then return false end
    for _, key in ipairs(SAVE_KEYS) do if data[key] ~= nil then Cfg[key] = data[key] end end
    NormalizeCfg()
    return Cfg.SetupComplete and #Cfg.GroqKeys > 0
end

local setupAlreadyDone = LoadCfg()

local MEMORY_FILE = "aichatbot_groq_memory_v1.json"
local History, PrivateHistory = {}, {}
local function CleanHistory(data)
    local clean = {}
    if type(data) ~= "table" then return clean end
    for _, entry in ipairs(data) do
        if type(entry) == "table" and (entry.role == "user" or entry.role == "assistant")
            and type(entry.content) == "string" and entry.content ~= "" then
            table.insert(clean, {role = entry.role, content = Truncate(entry.content, 2000)})
        end
    end
    while #clean > Cfg.MemoryLimit do table.remove(clean, 1) end
    while clean[1] and clean[1].role ~= "user" do table.remove(clean, 1) end
    return clean
end

local function SaveMemory()
    return WriteJSON(MEMORY_FILE, Cfg.RememberHistory and {version = 1, public = History, private = PrivateHistory} or {})
end

if Cfg.RememberHistory then
    local data = ReadJSON(MEMORY_FILE) or {}
    History = CleanHistory(data.public or data)
    PrivateHistory = CleanHistory(data.private)
end

local PlayerCooldowns, MsgQueue, GreetedPlayers = {}, {}, {}
local ProcessingMsg, LastSentMsg = false, ""
local RealGameName = game.Name
local UpdateBillboard

local function InvalidatePending()
    Runtime.generation = Runtime.generation + 1
    table.clear(MsgQueue)
    if UpdateBillboard then UpdateBillboard(Cfg.Enabled and "ready" or "paused") end
end

local function ClearMemory()
    InvalidatePending()
    table.clear(History)
    table.clear(PrivateHistory)
    SaveMemory()
end

local function SetModel(model)
    model = Trim(model)
    if model == "" then return false end
    Cfg.Model = model
    ClearMemory()
    SaveCfg()
    return true
end

local function SetEnabled(enabled)
    Cfg.Enabled = enabled
    if not enabled then InvalidatePending() end
    if UpdateBillboard then UpdateBillboard(enabled and "ready" or "paused") end
    SaveCfg()
end

task.spawn(function()
    pcall(function()
        local mps = game:GetService("MarketplaceService")
        local info = mps:GetProductInfo(game.PlaceId)
        if info and info.Name then RealGameName = info.Name end
    end)
end)

local EMOTES = {
    WAVE   = "rbxassetid://507770239",
    DANCE  = "rbxassetid://507771019",
    DANCE2 = "rbxassetid://507776043",
    DANCE3 = "rbxassetid://507776048",
    LAUGH  = "rbxassetid://507770818",
    POINT  = "rbxassetid://507770453",
    CHEER  = "rbxassetid://507770677",
}

-- ═══════════════════════════════════════
-- VOICE CHAT (VC) -- broken as of right now
-- ═══════════════════════════════════════

local function GetVCStatus()
    if not Cfg.VCSupport then
        return "Disabled in bot settings", false
    end
    if not VoiceChatService then
        return "VoiceChatService not present in this place", false
    end
    local vcEnabled = false
    pcall(function()
        if type(VoiceChatService.IsVoiceEnabledForUserIdAsync) == "function" then
            vcEnabled = VoiceChatService:IsVoiceEnabledForUserIdAsync(LP.UserId)
        end
    end)
    local micMuted = nil
    pcall(function()
        if type(VoiceChatService.GetMicDeviceState) == "function" then
            micMuted = VoiceChatService:GetMicDeviceState()
        end
    end)
    if vcEnabled then
        local micInfo = micMuted == nil and "Mic state: Roblox HUD" or (micMuted and "Mic: Muted" or "Mic: Unmuted")
        return "VC Available · " .. micInfo, true
    end
    return "VC Service detected (not enabled for account or place)", false
end

local function PromptVCAction()
    if not Cfg.VCSupport then
        return false, "Enable 'Support Roblox Voice Chat (VC)' first."
    end
    if not VoiceChatService then
        return false, "VoiceChatService is unavailable in this experience."
    end
    local ok = pcall(function()
        if type(VoiceChatService.ToggleMicDeviceState) == "function" then
            VoiceChatService:ToggleMicDeviceState()
        end
    end)
    if ok then
        return true, "Toggled VC mic state."
    end
    local guiOk = pcall(function()
        game:GetService("StarterGui"):SetCore("PromptVoiceChatInvite", {})
    end)
    if guiOk then
        return true, "Opened Roblox VC prompt."
    end
    return false, "Use Roblox's top-bar VC controls directly for mic/audio."
end

-- ═══════════════════════════════════════
-- multi key
-- ═══════════════════════════════════════

local function DoRequest(url, method, headers, body)
    if not Runtime.alive then return nil, "Bot unloaded." end
    local fn = request or (syn and syn.request) or http_request or (http and http.request)
    if type(fn) ~= "function" then return nil, "No HTTP request function is available." end
    local done, success, response = false, false, nil
    task.spawn(function()
        success, response = pcall(fn, {
            Url = url,
            Method = method or "GET",
            Headers = headers or {},
            Body = body,
            Timeout = Cfg.RequestTimeout,
        })
        done = true
    end)
    local deadline = os.clock() + Cfg.RequestTimeout
    while not done and Runtime.alive and os.clock() < deadline do task.wait(0.05) end
    if not Runtime.alive then return nil, "Bot unloaded." end
    if not done then return nil, "Request timed out." end
    if not success or type(response) ~= "table" then return nil, "Network request failed." end
    response.StatusCode = tonumber(response.StatusCode or response.Status) or 0
    return response
end

local function ParseModelList(data)
    if type(data) ~= "table" then return nil, "Model-list response is not an object or array." end
    local entries = data.data or data.models or data
    if type(entries) ~= "table" then return nil, "Model-list response contains an invalid models array." end
    local models, seen = {}, {}
    for _, entry in ipairs(entries) do
        local id = type(entry) == "string" and entry or type(entry) == "table" and (entry.id or entry.model or entry.name)
        if type(id) == "string" then
            id = Trim(id)
            if id ~= "" and not seen[id] and utf8.len(id) then
                seen[id] = true
                local label = type(entry) == "table" and (entry.display_name or entry.displayName) or nil
                table.insert(models, {
                    id = id,
                    label = type(label) == "string" and Trim(label) ~= "" and label or id,
                })
            end
        end
    end
    if #models == 0 then return nil, "No usable models were returned. Enter a Groq model ID manually." end
    table.sort(models, function(a, b) return a.id:lower() < b.id:lower() end)
    return models
end

local function DiscoverGroqModels(apiKeysInput)
    local keys = ParseKeyList(apiKeysInput)
    if #keys == 0 then
        return nil, "Enter at least one valid Groq API key first."
    end
    local lastErr = "Groq model discovery failed."
    for _, key in ipairs(keys) do
        local response, networkError = DoRequest(
            "https://api.groq.com/openai/v1/models",
            "GET",
            {
                ["Accept"] = "application/json",
                ["Authorization"] = "Bearer " .. key,
            }
        )
        if response and response.StatusCode >= 200 and response.StatusCode < 300 then
            local ok, data = pcall(HttpService.JSONDecode, HttpService, response.Body or "")
            if not ok then return nil, "Groq model endpoint returned invalid JSON." end
            return ParseModelList(data)
        end
        local hints = {
            [401] = "Invalid Groq API key.",
            [403] = "Access to Groq models was denied.",
            [429] = "Rate limited by Groq.",
        }
        lastErr = response and (hints[response.StatusCode] or ("Groq model discovery failed (HTTP " .. tostring(response.StatusCode) .. ").")) or (networkError or lastErr)
    end
    return nil, lastErr
end

local function StopEmote()
    if Runtime.emoteTrack then
        pcall(function()
            Runtime.emoteTrack:Stop()
            Runtime.emoteTrack:Destroy()
        end)
        Runtime.emoteTrack = nil
    end
end

local function PlayAnimationId(animId, looped, duration)
    if not Runtime.alive or type(animId) ~= "string" or animId == "" then return false end
    local character = LP.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
    if not animator then return false end
    local animation = Instance.new("Animation")
    animation.AnimationId = animId
    local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
    animation:Destroy()
    if not ok or not track then return false end
    StopEmote()
    Runtime.emoteTrack = track
    pcall(function() track.Priority = Enum.AnimationPriority.Action end)
    if looped ~= nil then pcall(function() track.Looped = looped end) end
    track:Play()
    if duration and duration > 0 then
        task.delay(duration, function()
            if Runtime.emoteTrack == track then StopEmote() end
        end)
    end
    return true
end

local function PlayEmote(name)
    if not EMOTES[name] then return end
    PlayAnimationId(EMOTES[name], false, 3.5)
end

-- animations
local DEFAULT_LOCOMOTION_IDS = {
    ["507766388"] = true, ["507766666"] = true, ["507766951"] = true, -- R15 idle
    ["507777826"] = true, ["913402848"] = true, ["507767714"] = true, -- R15 walk/run
    ["507765000"] = true, ["507767968"] = true, ["507765644"] = true, -- R15 jump/fall/climb
    ["507784897"] = true, ["507785072"] = true, ["2506281703"] = true, -- R15 swim/sit
    ["180435571"] = true, ["180435792"] = true, ["180426354"] = true, -- R6 idle/walk
    ["125750702"] = true, ["180436148"] = true, ["180436334"] = true, -- R6 jump/fall/climb
    ["178130996"] = true, ["180435342"] = true, -- R6 sit/swim
}

local function CopyPlayerEmote(targetPlayer)
    if not targetPlayer or not targetPlayer.Character then
        return false, "Target player has no character loaded."
    end
    local humanoid = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
    local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        return false, "Could not inspect player animations."
    end
    local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
    if not ok or type(tracks) ~= "table" or #tracks == 0 then
        return false, targetPlayer.DisplayName .. " isn't playing any animations."
    end

    local chosenTrack = nil
    local fallbackTrack = nil
    for _, tr in ipairs(tracks) do
        local anim = tr.Animation
        local id = anim and anim.AnimationId or ""
        local numId = id:match("(%d+)")
        if id ~= "" and not id:find("0$") then
            if numId and not DEFAULT_LOCOMOTION_IDS[numId] then
                if tr.Priority == Enum.AnimationPriority.Action
                    or tr.Priority == Enum.AnimationPriority.Action2
                    or tr.Priority == Enum.AnimationPriority.Action3
                    or tr.Priority == Enum.AnimationPriority.Action4
                    or not chosenTrack then
                    chosenTrack = tr
                end
            elseif not fallbackTrack then
                fallbackTrack = tr
            end
        end
    end

    local targetTrack = chosenTrack or fallbackTrack
    if not targetTrack or not targetTrack.Animation then
        return false, "No copyable emote found on " .. targetPlayer.DisplayName .. "."
    end

    local animId = targetTrack.Animation.AnimationId
    local started = PlayAnimationId(animId, targetTrack.Looped, targetTrack.Looped and 20 or 6)
    if not started then
        return false, "Failed to load animation (" .. tostring(animId) .. ")."
    end
    return true, "Copied emote from " .. targetPlayer.DisplayName .. "!"
end

-- ═══════════════════════════════════════
-- movement
-- ═══════════════════════════════════════

local BotAction = {
    mode = "none",       -- "none" | "follow" | "goto_pos" | "goto_player" | "goto_part"
    targetPlayer = nil,
    targetPos = nil,
    targetPart = nil,
    targetLabel = "",
}

local function GetInstanceWorldPos(inst)
    if not inst or not inst.Parent then return nil end
    if inst:IsA("BasePart") then return inst.Position end
    if inst:IsA("Attachment") then return inst.WorldPosition end
    if inst:IsA("Model") then
        if inst.PrimaryPart then return inst.PrimaryPart.Position end
        local ok, cf = pcall(function() return inst:GetBoundingBox() end)
        if ok and cf then return cf.Position end
        local part = inst:FindFirstChildWhichIsA("BasePart", true)
        if part then return part.Position end
    end
    return nil
end

local function FindPlayerByNameOrDisplay(query)
    local q = Trim(query):gsub("^@", ""):lower()
    if q == "" then return nil end
    local bestPartial = nil
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local uname = p.Name:lower()
            local dname = p.DisplayName:lower()
            if uname == q or dname == q then
                return p
            end
            if not bestPartial and (uname:find(q, 1, true) or dname:find(q, 1, true)) then
                bestPartial = p
            end
        end
    end
    return bestPartial
end

local function FindWorkspaceTarget(query)
    local q = Trim(query):lower()
    if q == "" then return nil end
    local myChar = LP.Character
    local exactMatch, partialMatch = nil, nil
    for _, inst in ipairs(workspace:GetDescendants()) do
        if (not myChar or not inst:IsDescendantOf(myChar))
            and (inst:IsA("BasePart") or inst:IsA("Model") or inst:IsA("Attachment")) then
            local nameLower = inst.Name:lower()
            if nameLower == q then
                if GetInstanceWorldPos(inst) then
                    exactMatch = inst
                    break
                end
            elseif not partialMatch and nameLower:find(q, 1, true) then
                if GetInstanceWorldPos(inst) then
                    partialMatch = inst
                end
            end
        end
    end
    return exactMatch or partialMatch
end

local function StopBotMovement(alsoStopEmote)
    BotAction.mode = "none"
    BotAction.targetPlayer = nil
    BotAction.targetPos = nil
    BotAction.targetPart = nil
    BotAction.targetLabel = ""
    Cfg.AutoFollow = false
    if alsoStopEmote then StopEmote() end
    local char = LP.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if humanoid and hrp then
        pcall(function() humanoid:MoveTo(hrp.Position) end)
    end
end

local function ParseAIText(raw)
    local actions, text = {}, type(raw) == "string" and raw or ""
    for _, tag in ipairs({"think", "thinking", "analysis", "reasoning"}) do
        local lower = text:lower()
        local openStart, openEnd = lower:find("<" .. tag .. "%f[%s>][^>]*>")
        while openStart do
            local _, closeEnd = lower:find("</" .. tag .. "%s*>", openEnd + 1)
            text = text:sub(1, openStart - 1) .. (closeEnd and text:sub(closeEnd + 1) or "")
            lower = text:lower()
            openStart, openEnd = lower:find("<" .. tag .. "%f[%s>][^>]*>")
        end
        local _, closeEnd = text:lower():find("</" .. tag .. "%s*>")
        if closeEnd then text = text:sub(closeEnd + 1) end
    end
    for name in pairs(EMOTES) do
        if text:find("%[" .. name .. "%]") then
            table.insert(actions, name)
            text = text:gsub("%[" .. name .. "%]", "")
        end
    end
    text = (text:match("^%s*(.-)%s*$") or text):gsub("%s+", " ")
    return text, actions
end

local function IsFiltered(text)
    return text and #text > 0 and text:match("^[#%s]+$") ~= nil
end

local function GetNearbyPlayers(radius)
    local result = {}
    local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not myHRP then return result end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local dist = (myHRP.Position - hrp.Position).Magnitude
                if dist <= radius then
                    table.insert(result, {
                        username = p.Name,
                        displayName = p.DisplayName,
                        distance = math.round(dist),
                        userId = p.UserId,
                        hrp = hrp,
                    })
                end
            end
        end
    end
    table.sort(result, function(a, b) return a.distance < b.distance end)
    return result
end

local function IsNearby(player, radius)
    local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not myHRP or not player.Character then return false end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    return (myHRP.Position - hrp.Position).Magnitude <= radius
end

local function IsPlayerAllowed(playerName)
    local name = playerName:lower()
    for _, blocked in ipairs(Cfg.Blacklist) do if blocked:lower() == name then return false end end
    if #Cfg.Whitelist == 0 then return true end
    for _, allowed in ipairs(Cfg.Whitelist) do if allowed:lower() == name then return true end end
    return false
end

local function MatchesKeywordTrigger(text)
    local raw = Trim(Cfg.TriggerKeywords)
    if raw == "" then return false end
    local lowerText = text:lower()
    for token in raw:gmatch("[^,]+") do
        local kw = Trim(token):lower()
        if kw ~= "" and lowerText:find(kw, 1, true) then
            return true
        end
    end
    return false
end

local function GetGeneralChannel()
    local ch = TCS:FindFirstChild("TextChannels")
    return (ch and ch:FindFirstChild("RBXGeneral")) or TCS:FindFirstChild("RBXGeneral")
end

local function SendChat(msg)
    if not Runtime.alive or not Runtime.ready or not Cfg.Enabled then return false, "Bot is paused." end
    local fullMsg = Truncate((Cfg.ChatPrefix or "") .. msg, 200)
    local channel = GetGeneralChannel()
    if not channel or not channel:IsA("TextChannel") then return false, "RBXGeneral chat channel is unavailable." end
    if Cfg.WhisperMode then
        local escaped = fullMsg:gsub("&", "&"):gsub("<", "<"):gsub(">", ">")
        local ok = pcall(function() channel:DisplaySystemMessage("[Local preview] " .. escaped) end)
        if not ok then return false, "Could not show local preview." end
        return true, nil, fullMsg:sub(#(Cfg.ChatPrefix or "") + 1)
    end
    LastSentMsg = fullMsg
    local ok, result = pcall(function() return channel:SendAsync(fullMsg) end)
    if not ok then
        LastSentMsg = ""
        return false, "Chat send failed."
    end
    if result and result.Status ~= Enum.TextChatMessageStatus.Success
        and result.Status ~= Enum.TextChatMessageStatus.Sending then
        LastSentMsg = ""
        return false, "Chat delivery: " .. tostring(result.Status)
    end
    return true, nil, fullMsg:sub(#(Cfg.ChatPrefix or "") + 1)
end

local function ExportChatLog()
    if #History == 0 then return false, "No public history to export." end
    if type(writefile) ~= "function" then return false, "File saving is unavailable." end
    local lines = {
        "-- AI Chat Bot Groq Log --",
        "-- Provider: Groq | Model: " .. Cfg.Model .. " --",
        "",
    }
    for _, entry in ipairs(History) do
        table.insert(lines, "[" .. entry.role:upper() .. "]: " .. entry.content)
    end
    local filename = "aichatbot_groq_log_" .. os.time() .. ".txt"
    local ok = pcall(writefile, filename, table.concat(lines, "\n"))
    return ok, ok and filename or "Could not write log file."
end

-- ═══════════════════════════════════════
-- messaging
-- ═══════════════════════════════════════

local function BuildSystemMsg(nearby)
    local lengthSuffix = LENGTH_MODES[Cfg.LengthMode] and LENGTH_MODES[Cfg.LengthMode].suffix or ""
    local ctx = {
        "\n\n--- GAME CONTEXT ---",
        "Current Game: " .. tostring(RealGameName) .. " (Place ID: " .. tostring(game.PlaceId) .. ")",
        "Setting: You are currently playing a game on Roblox.",
        "Bot name: " .. Cfg.BotName,
        "Your Roblox username: " .. LP.Name .. (LP.DisplayName ~= LP.Name and " (display: " .. LP.DisplayName .. ")" or ""),
        "Local operator: " .. BOT_OWNER .. ". You are an AI chat bot; be honest about that if asked.",
    }
    if BotAction.mode ~= "none" then
        table.insert(ctx, "Current movement action: " .. BotAction.mode .. (BotAction.targetLabel ~= "" and (" -> " .. BotAction.targetLabel) or ""))
    end
    if Cfg.VCSupport and Cfg.VCIncludeContext then
        local vcDesc = select(1, GetVCStatus())
        table.insert(ctx, "Voice Chat status: " .. vcDesc)
    end
    if #nearby > 0 then
        local ns = {}
        for _, p in ipairs(nearby) do
            table.insert(ns, string.format("%s (@%s) - %d studs", p.displayName, p.username, p.distance))
        end
        table.insert(ctx, "Nearby players: " .. table.concat(ns, ", "))
    else
        table.insert(ctx, "No other players are nearby.")
    end
    table.insert(ctx, "--- END CONTEXT ---")
    if Cfg.Language and Cfg.Language ~= "" and Cfg.Language:lower() ~= "auto" then
        table.insert(ctx, "CRITICAL: You MUST reply entirely in " .. Cfg.Language .. ".")
    else
        table.insert(ctx, "CRITICAL: You MUST identify the language used by the [SENDER] in the most recent user message and reply in that EXACT same language. If the language changes between users, you MUST switch accordingly.")
    end
    table.insert(ctx, "Answer directly with only the final chat message. Do not include reasoning, analysis, or thinking blocks." .. lengthSuffix)
    return Cfg.SystemPrompt .. table.concat(ctx, "\n")
end

local function BuildMsgs(userMsg, nearby, extraNote, history)
    local sys = BuildSystemMsg(nearby)
    if extraNote then sys = sys .. "\n[SYSTEM NOTE]: " .. extraNote end
    local msgs = {{ role = "system", content = sys }}
    for _, h in ipairs(history or History) do
        local content = h.role == "assistant" and ParseAIText(h.content) or h.content
        if content ~= "" then table.insert(msgs, { role = h.role, content = content }) end
    end
    table.insert(msgs, { role = "user", content = userMsg })
    return msgs
end

local ERROR_HINTS = {
    [400] = "Bad request.",
    [401] = "Invalid Groq API key.",
    [402] = "Account/credits issue.",
    [403] = "Forbidden.",
    [404] = "Groq model not found.",
    [429] = "Rate limited by Groq.",
    [500] = "Groq server overloaded.",
    [502] = "Gateway error.",
    [503] = "Groq service down.",
}

local function HandleAPIError(code, body)
    local ok, data = pcall(HttpService.JSONDecode, HttpService, body or "")
    local errorValue = ok and type(data) == "table" and data.error
    local message = type(errorValue) == "table" and errorValue.message or type(errorValue) == "string" and errorValue
    if not message and ok and type(data) == "table" then message = data.message end
    local detail = type(message) == "string" and message or ""
    for _, secret in ipairs(Cfg.GroqKeys) do
        if type(secret) == "string" and #secret >= 6 then
            detail = detail:gsub(secret:gsub("([^%w])", "%%%1"), "[redacted]")
        end
    end
    detail = Truncate(detail:gsub("[Bb]earer%s+[%w%-%._]+", "Bearer [redacted]"), 350)
    local hint = ERROR_HINTS[code] or ("HTTP " .. tostring(code))
    return hint .. (detail ~= "" and " " .. detail or "")
end

local function CallGroq(msgs, bodyExtra)
    SyncKeyPool()
    local totalKeys = #Cfg.GroqKeys
    if totalKeys == 0 then
        return nil, "Enter at least one Groq API key in setup or the Groq API tab."
    end

    Runtime.stats.requests = Runtime.stats.requests + 1
    local b = {
        model = Cfg.Model,
        messages = msgs,
        max_tokens = Cfg.MaxTokens,
        temperature = Cfg.Temperature,
        stream = false,
    }
    if bodyExtra then
        for k, v in pairs(bodyExtra) do b[k] = v end
    end
    local encoded, body = pcall(HttpService.JSONEncode, HttpService, b)
    if not encoded then return nil, "Could not encode Groq request." end

    local generation = Runtime.generation
    local lastError = "No response"
    local startIndex = Cfg.ActiveKeyIndex
    local lastRetryAfter = 10

    for offset = 0, totalKeys - 1 do
        if not Runtime.alive or generation ~= Runtime.generation then return nil, "Cancelled." end
        local keyIndex = ((startIndex - 1 + offset) % totalKeys) + 1
        local key = Cfg.GroqKeys[keyIndex]
        Cfg.ActiveKeyIndex = keyIndex
        Cfg.GroqKey = key

        local headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. key,
        }

        local res, networkError = DoRequest("https://api.groq.com/openai/v1/chat/completions", "POST", headers, body)
        if not Runtime.alive or generation ~= Runtime.generation then return nil, "Cancelled." end

        if res and res.StatusCode >= 200 and res.StatusCode < 300 then
            local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body or "")
            if ok and type(data) == "table" then
                local choice = type(data.choices) == "table" and data.choices[1]
                local message = type(choice) == "table" and choice.message
                local content = type(message) == "table" and message.content
                if type(content) == "string" and Trim(content) ~= "" then
                    return content
                else
                    lastError = string.format("[Key #%d] Groq returned no usable text.", keyIndex)
                end
            else
                lastError = string.format("[Key #%d] Groq returned invalid JSON.", keyIndex)
            end
        else
            local errText = res and HandleAPIError(res.StatusCode, res.Body) or networkError or "No response"
            lastError = string.format("[Key #%d/%d] %s", keyIndex, totalKeys, errText)
            if res and res.StatusCode == 429 then
                local responseHeaders = res.Headers or res.headers or {}
                local retryAfter = tonumber(responseHeaders["Retry-After"] or responseHeaders["retry-after"])
                if retryAfter then lastRetryAfter = math.clamp(retryAfter, 1, 120) end
            end
        end

        if totalKeys > 1 then
            local nextIndex = (keyIndex % totalKeys) + 1
            Cfg.ActiveKeyIndex = nextIndex
            Cfg.GroqKey = Cfg.GroqKeys[nextIndex]
            warn(string.format("[AI Bot] %s -> Switching to Key #%d (%s)", lastError, nextIndex, MaskKey(Cfg.GroqKey)))
            task.wait(0.15)
        end
    end

    if lastError:find("Rate limited", 1, true) then
        Runtime.nextRequestAt = os.clock() + lastRetryAfter
    end
    return nil, totalKeys > 1
        and ("All " .. tostring(totalKeys) .. " Groq keys failed. Last: " .. lastError)
        or lastError
end

-- ═══════════════════════════════════════
-- status
-- ═══════════════════════════════════════

local Billboard = { state = "ready", tweens = {}, transitions = {}, animating = false }
local BILLBOARD_STATES = {
    ready      = { text = "Ready for chat",       color = Color3.fromRGB(146, 222, 184) },
    generating = { text = "Generating reply",     color = Color3.fromRGB(146, 222, 184), busy = true },
    sending    = { text = "Sending reply",        color = Color3.fromRGB(146, 222, 184), busy = true },
    waiting    = { text = "Waiting for cooldown", color = Color3.fromRGB(230, 196, 137), busy = true },
    paused     = { text = "Replies paused",       color = Color3.fromRGB(166, 176, 172) },
    error      = { text = "Request failed",       color = Color3.fromRGB(255, 151, 142) },
}

local function StopBillboardAnimation()
    for _, tween in ipairs(Billboard.tweens) do tween:Cancel() end
    Billboard.animating = false
    if Billboard.activity then
        for _, dot in ipairs(Billboard.activity:GetChildren()) do
            if dot:IsA("Frame") then dot.BackgroundTransparency = 0.6 end
        end
    end
end

local function DestroyBillboard()
    StopBillboardAnimation()
    for _, tween in ipairs(Billboard.transitions) do tween:Cancel() end
    table.clear(Billboard.tweens)
    table.clear(Billboard.transitions)
    if Billboard.gui then Billboard.gui:Destroy() end
    Billboard.gui = nil
    Billboard.activity = nil
end

local function CreateBillboard(head)
    DestroyBillboard()
    local gui = Instance.new("BillboardGui")
    gui.Name = "AIBotBillboard"
    gui.Size = UDim2.fromOffset(252, 66)
    gui.StudsOffsetWorldSpace = Vector3.new(0, 3.1, 0)
    gui.AlwaysOnTop = true
    gui.LightInfluence = 0
    gui.MaxDistance = 120
    gui.Adornee = head
    gui.Parent = CoreGui

    local body = Instance.new("Frame")
    body.Name = "StatusBadge"
    body.Size = UDim2.new(1, -4, 1, -4)
    body.Position = UDim2.fromOffset(2, 2)
    body.BackgroundColor3 = Color3.fromRGB(19, 22, 24)
    body.BackgroundTransparency = 0.08
    body.BorderSizePixel = 0
    body.Parent = gui
    Instance.new("UICorner", body).CornerRadius = UDim.new(0, 12)
    local outline = Instance.new("UIStroke", body)
    outline.Color = Color3.fromRGB(57, 64, 65)
    outline.Thickness = 1
    outline.Transparency = 0.15

    local mark = Instance.new("Frame")
    mark.Name = "BotMark"
    mark.Size = UDim2.fromOffset(32, 32)
    mark.Position = UDim2.fromOffset(12, 15)
    mark.BackgroundColor3 = Color3.fromRGB(32, 48, 43)
    mark.BorderSizePixel = 0
    mark.Parent = body
    Instance.new("UICorner", mark).CornerRadius = UDim.new(0, 8)

    local function makeLabel(parent, name, value, size, position, fontSize, color, bold)
        local label = Instance.new("TextLabel")
        label.Name = name
        label.Text = value
        label.Size = size
        label.Position = position
        label.BackgroundTransparency = 1
        label.TextColor3 = color
        label.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
        label.TextSize = fontSize
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextWrapped = false
        label.TextTruncate = Enum.TextTruncate.AtEnd
        label.Parent = parent
        return label
    end

    local monogram = makeLabel(mark, "BotMonogram", "AI", UDim2.fromScale(1, 1), UDim2.new(), 12, Color3.fromRGB(146, 222, 184), true)
    monogram.TextXAlignment = Enum.TextXAlignment.Center
    local name = makeLabel(body, "BotIdentity", Cfg.BotName, UDim2.new(1, -72, 0, 22), UDim2.fromOffset(58, 9), 15, Color3.fromRGB(237, 240, 237), true)
    local statusDot = Instance.new("Frame")
    statusDot.Name = "StatusIndicator"
    statusDot.Size = UDim2.fromOffset(5, 5)
    statusDot.Position = UDim2.fromOffset(59, 40)
    statusDot.BorderSizePixel = 0
    statusDot.Parent = body
    Instance.new("UICorner", statusDot).CornerRadius = UDim.new(1, 0)
    local status = makeLabel(body, "StatusText", "", UDim2.new(1, -110, 0, 18), UDim2.fromOffset(71, 33), 11, Color3.fromRGB(166, 176, 172), false)

    local activity = Instance.new("Frame")
    activity.Name = "ActivityDots"
    activity.Size = UDim2.fromOffset(24, 12)
    activity.Position = UDim2.new(1, -36, 0, 37)
    activity.BackgroundTransparency = 1
    activity.Visible = false
    activity.Parent = body

    for i = 1, 3 do
        local dot = Instance.new("Frame")
        dot.Name = "ActivityDot" .. i
        dot.Size = UDim2.fromOffset(4, 4)
        dot.Position = UDim2.fromOffset((i - 1) * 9, 3)
        dot.BackgroundColor3 = Color3.fromRGB(146, 222, 184)
        dot.BackgroundTransparency = 0.6
        dot.BorderSizePixel = 0
        dot.Parent = activity
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
        table.insert(Billboard.tweens, TweenService:Create(
            dot,
            TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, (i - 1) * 0.15),
            { BackgroundTransparency = 0.05 }
        ))
    end

    Billboard.gui = gui
    Billboard.name = name
    Billboard.label = status
    Billboard.dot = statusDot
    Billboard.outline = outline
    Billboard.monogram = monogram
    Billboard.activity = activity
end

UpdateBillboard = function(state)
    if not Runtime.alive then return end
    local previous = Billboard.state
    if state and BILLBOARD_STATES[state] then Billboard.state = state end
    if not state and not Cfg.Enabled and Billboard.state == "ready" then Billboard.state = "paused" end
    local info = BILLBOARD_STATES[Billboard.state]
    local char = LP.Character
    local head = char and char:FindFirstChild("Head")
    if not Cfg.ShowBillboard or not head then
        StopBillboardAnimation()
        if Billboard.gui then Billboard.gui.Enabled = false end
        return
    end
    local created = not Billboard.gui or not Billboard.gui.Parent
    if created then CreateBillboard(head) end
    Billboard.gui.Adornee = head
    Billboard.gui.Enabled = true
    Billboard.name.Text = Cfg.BotName
    Billboard.label.Text = info.text
    Billboard.label.Size = UDim2.new(1, info.busy and -110 or -84, 0, 18)
    if previous ~= Billboard.state or created then
        for _, tween in ipairs(Billboard.transitions) do tween:Cancel() end
        table.clear(Billboard.transitions)
        for _, target in ipairs({
            { Billboard.dot, "BackgroundColor3" },
            { Billboard.monogram, "TextColor3" },
            { Billboard.label, "TextColor3" },
        }) do
            local tween = TweenService:Create(target[1], TweenInfo.new(0.18), { [target[2]] = info.color })
            table.insert(Billboard.transitions, tween)
            tween:Play()
        end
        Billboard.outline.Color = Billboard.state == "error" and info.color or Color3.fromRGB(57, 64, 65)
        for _, dot in ipairs(Billboard.activity:GetChildren()) do
            if dot:IsA("Frame") then dot.BackgroundColor3 = info.color end
        end
    end
    Billboard.activity.Visible = info.busy or false
    if info.busy and not Billboard.animating then
        for _, tween in ipairs(Billboard.tweens) do tween:Play() end
        Billboard.animating = true
    elseif not info.busy and Billboard.animating then
        StopBillboardAnimation()
    end
end

Runtime.Connect(LP.CharacterAdded, function(char)
    local head = char:WaitForChild("Head", 5)
    if not Runtime.alive or LP.Character ~= char then return end
    if head then UpdateBillboard() end
end)

Runtime.Connect(LP.CharacterRemoving, function()
    StopBillboardAnimation()
    if Billboard.gui then Billboard.gui.Enabled = false end
end)

-- ═══════════════════════════════════════
-- chat and queue
-- ═══════════════════════════════════════

local function CallAI(item)
    local generation = Runtime.generation
    local function cancelled() return not Runtime.alive or generation ~= Runtime.generation end
    local history = item.private and PrivateHistory or History
    UpdateBillboard("generating")
    if Cfg.ThinkDelay then task.wait(0.3) end
    if cancelled() then return nil, "Cancelled." end

    local userMsg = string.format("[%s]: %s", item.name, item.text)
    local msgs = BuildMsgs(userMsg, GetNearbyPlayers(Cfg.ProximityRadius), item.note, history)
    local started = os.clock()
    local content, err = CallGroq(msgs, item.introduce and { max_tokens = 30 } or nil)
    if cancelled() then return nil, "Cancelled." end
    Runtime.stats.latency = os.clock() - started
    if not content then return nil, err or "No response." end

    local clean, actions = ParseAIText(content)
    if clean == "" then return nil, "Reply contained no visible text." end

    if not item.private then
        UpdateBillboard("sending")
        local sent, sendError = SendChat(clean)
        if not sent then return nil, sendError end
        if cancelled() then return nil, "Cancelled." end
        if actions[1] then PlayEmote(actions[1]) end
    end

    table.insert(history, { role = "user", content = Truncate(userMsg, 2000) })
    table.insert(history, { role = "assistant", content = Truncate(clean, 2000) })
    while #history > Cfg.MemoryLimit do table.remove(history, 1) end
    SaveMemory()
    Runtime.stats.replies = Runtime.stats.replies + 1
    return clean
end

local function ProcessQueue()
    if ProcessingMsg or not Runtime.ready or not Runtime.alive then return end
    ProcessingMsg = true
    task.spawn(function()
        while Runtime.alive and Runtime.ready and #MsgQueue > 0 do
            local item = table.remove(MsgQueue, 1)
            local function valid()
                if item.generation ~= Runtime.generation or os.clock() - item.queuedAt > Cfg.QueueMaxAge then return false end
                if not item.private and not Cfg.Enabled then return false end
                if item.automatic then
                    local player = Players:GetPlayerByUserId(item.userId)
                    if not player or not IsPlayerAllowed(player.Name) then return false end
                    if not Cfg.RespondToAll and not IsNearby(player, Cfg.ProximityRadius) then return false end
                end
                return true
            end
            if valid() and os.clock() < Runtime.nextRequestAt then UpdateBillboard("waiting") end
            while Runtime.alive and valid() and os.clock() < Runtime.nextRequestAt do task.wait(0.1) end
            if Runtime.alive and valid() then
                local ok, result, err = pcall(CallAI, item)
                if not ok then result, err = nil, "Unexpected response error; check your Groq keys and model." end
                Runtime.nextRequestAt = math.max(Runtime.nextRequestAt, os.clock() + Cfg.GlobalCooldown)
                if item.generation == Runtime.generation and Runtime.alive then
                    if not result then
                        Runtime.stats.errors = Runtime.stats.errors + 1
                        Runtime.stats.lastError = err or "Unknown error"
                        warn("[AI Bot] " .. Runtime.stats.lastError)
                    end
                    UpdateBillboard(not result and "error" or Cfg.Enabled and "ready" or "paused")
                    if item.callback then pcall(item.callback, result, err) end
                end
            else
                Runtime.stats.dropped = Runtime.stats.dropped + 1
                UpdateBillboard(Cfg.Enabled and "ready" or "paused")
                if item.callback and Runtime.alive then pcall(item.callback, nil, "Request cancelled or expired.") end
            end
        end
        ProcessingMsg = false
    end)
end

local function Enqueue(item)
    if not Runtime.alive or not Runtime.ready then return false, "Finish setup first." end
    if not item.private and not Cfg.Enabled then return false, "Enable the bot first." end
    item.text = Trim(item.text)
    if item.text == "" then return false, "Message is empty." end
    if #MsgQueue >= Cfg.QueueLimit then
        Runtime.stats.dropped = Runtime.stats.dropped + 1
        return false, "Queue is full. Try again shortly."
    end
    item.text = Truncate(item.text, 2000)
    item.queuedAt = os.clock()
    item.generation = Runtime.generation
    table.insert(MsgQueue, item)
    ProcessQueue()
    return true
end

local function QueueManual(item)
    local ok, err = Enqueue(item)
    if not ok then SafeNotify({ Title = "Could not queue message", Content = err }) end
end

local function DoIntroduce()
    QueueManual({ text = "Introduce yourself as an AI chat bot in one short friendly sentence.", name = LP.Name, introduce = true })
end

-- commands 2
local function TryExecutePublicCommand(sender, rawText)
    if not Cfg.PublicCommands then return false end
    local botPrefix = Trim(Cfg.BotName):lower()
    if botPrefix == "" then return false end

    local cleaned = Trim(rawText)
    if cleaned:sub(1, #botPrefix):lower() ~= botPrefix then return false end
    -- Ensure bot name is followed by space or punctuation
    local nextChar = cleaned:sub(#botPrefix + 1, #botPrefix + 1)
    if nextChar ~= "" and not nextChar:match("[%s,:;!%.%-]") then return false end

    local rest = Trim(cleaned:sub(#botPrefix + 1):gsub("^[%s,:;!%.%-]+", ""))
    if rest == "" then return false end
    local lowerRest = rest:lower():gsub("[%.!%?]+$", "")

    -- 1. "(name) come here"
    if lowerRest == "come here" or lowerRest == "come" then
        local hrp = sender.Character and sender.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then
            SafeNotify({ Title = "Command failed", Content = sender.DisplayName .. " has no character position." })
            return true
        end
        Cfg.AutoFollow = false
        BotAction.mode = "goto_pos"
        BotAction.targetPlayer = nil
        BotAction.targetPart = nil
        BotAction.targetPos = hrp.Position
        BotAction.targetLabel = sender.DisplayName .. "'s spot"
        SafeNotify({ Title = "Public Command", Content = sender.DisplayName .. ": Come here" })
        return true
    end

    -- 2. "(name) follow me"
    if lowerRest == "follow me" or lowerRest == "follow" then
        Cfg.AutoFollow = false
        BotAction.mode = "follow"
        BotAction.targetPlayer = sender
        BotAction.targetPos = nil
        BotAction.targetPart = nil
        BotAction.targetLabel = sender.DisplayName
        SafeNotify({ Title = "Public Command", Content = "Following " .. sender.DisplayName .. " until '" .. Cfg.BotName .. " stop'" })
        return true
    end

    -- 3. "(name) stop"
    if lowerRest == "stop" or lowerRest == "stop following" then
        StopBotMovement(true)
        SafeNotify({ Title = "Public Command", Content = "Stopped by " .. sender.DisplayName })
        return true
    end

    -- 4. "(name) copy emote"
    if lowerRest == "copy emote" or lowerRest == "copy animation" or lowerRest == "copy anim" then
        local ok, msg = CopyPlayerEmote(sender)
        SafeNotify({ Title = ok and "Copied Emote" or "Copy Emote", Content = msg })
        return true
    end

    -- 5. "(name) go to (player or workspace item)"
    local goTargetRaw = rest:match("^[Gg][Oo]%s+[Tt][Oo]%s+(.+)$") or rest:match("^[Gg][Oo][Tt][Oo]%s+(.+)$")
    if goTargetRaw then
        local targetQuery = Trim(goTargetRaw:gsub("[%.!%?]+$", ""))
        if targetQuery == "" then return false end

        local targetPlayer = FindPlayerByNameOrDisplay(targetQuery)
        if targetPlayer then
            Cfg.AutoFollow = false
            BotAction.mode = "goto_player"
            BotAction.targetPlayer = targetPlayer
            BotAction.targetPos = nil
            BotAction.targetPart = nil
            BotAction.targetLabel = targetPlayer.DisplayName .. " (@" .. targetPlayer.Name .. ")"
            SafeNotify({ Title = "Public Command", Content = "Going to player: " .. BotAction.targetLabel })
            return true
        end

        local targetInst = FindWorkspaceTarget(targetQuery)
        if targetInst then
            Cfg.AutoFollow = false
            BotAction.mode = "goto_part"
            BotAction.targetPlayer = nil
            BotAction.targetPos = nil
            BotAction.targetPart = targetInst
            BotAction.targetLabel = targetInst.Name
            SafeNotify({ Title = "Public Command", Content = "Going to object: " .. targetInst.Name })
            return true
        end

        SafeNotify({ Title = "Target not found", Content = "Could not find player or workspace item '" .. targetQuery .. "'." })
        return true
    end

    return false
end

local function HandleCommand(text)
    local cmd, argument = text:match("^/ai%s+(%S+)%s*(.-)%s*$")
    if not cmd then return false end
    cmd = cmd:lower()
    if cmd == "clear" then ClearMemory()
    elseif cmd == "off" then SetEnabled(false)
    elseif cmd == "on" then SetEnabled(true)
    elseif cmd == "stop" then
        StopBotMovement(true)
        SafeNotify({ Title = "Stopped", Content = "Movement and emote stopped." })
        return true
    elseif cmd == "follow" then
        local arg = argument:lower()
        if arg == "on" then Cfg.AutoFollow = true; SaveCfg()
        elseif arg == "off" then Cfg.AutoFollow = false; SaveCfg()
        else Cfg.AutoFollow = not Cfg.AutoFollow; SaveCfg() end
        SafeNotify({ Title = "Auto-follow", Content = Cfg.AutoFollow and "Enabled" or "Disabled" })
        return true
    elseif cmd == "vc" then
        SafeNotify({ Title = "Voice Chat status", Content = select(1, GetVCStatus()) })
        return true
    elseif cmd == "keys" then
        SafeNotify({
            Title = "Groq Keys",
            Content = string.format("Loaded: %d key(s) | Active: #%d (%s)", #Cfg.GroqKeys, Cfg.ActiveKeyIndex, MaskKey(Cfg.GroqKey)),
        })
        return true
    elseif cmd == "model" then
        if not SetModel(argument) then
            SafeNotify({ Title = "Model required", Content = "Usage: /ai model MODEL_ID" })
            return true
        end
    elseif cmd == "status" then
        SafeNotify({
            Title = "AI Bot status",
            Content = string.format("Groq (%d keys, #%d active) | %s\nAction: %s | Queue: %d | Replies: %d", #Cfg.GroqKeys, Cfg.ActiveKeyIndex, Cfg.Model, BotAction.mode, #MsgQueue, Runtime.stats.replies),
        })
        return true
    else
        SafeNotify({ Title = "Commands", Content = "/ai on, off, stop, follow [on|off], vc, keys, clear, model MODEL_ID, status" })
        return true
    end
    SafeNotify({ Title = "AI Bot", Content = "Command applied: " .. cmd })
    return true
end

Runtime.Connect(LP.Chatted, function(text) if Runtime.ready then HandleCommand(text) end end)

local SeenMessages = {}
Runtime.Connect(TCS.MessageReceived, function(msg)
    if not Runtime.ready or not Runtime.alive then return end
    local source = msg.TextSource
    if not source then return end
    if source.UserId == LP.UserId then
        if IsFiltered(msg.Text) and LastSentMsg ~= "" then
            Runtime.stats.lastError = "Last reply was blocked by Roblox's chat filter."
            LastSentMsg = ""
        elseif msg.Text == LastSentMsg then
            LastSentMsg = ""
        end
        return
    end
    if not Cfg.Enabled then return end
    if msg.TextChannel ~= GetGeneralChannel() then return end
    local sender = Players:GetPlayerByUserId(source.UserId)
    local text = msg.Text
    if not sender or type(text) ~= "string" or Trim(text) == "" or IsFiltered(text) then return end
    if not IsPlayerAllowed(sender.Name) then return end
    if not Cfg.RespondToAll and not IsNearby(sender, Cfg.ProximityRadius) then return end

    local now = os.clock()
    for id, seenAt in pairs(SeenMessages) do if now - seenAt > 120 then SeenMessages[id] = nil end end
    local messageId = msg.MessageId
    if messageId and messageId ~= "" then
        if SeenMessages[messageId] then return end
        SeenMessages[messageId] = now
    end

    -- Check public action commands first (e.g. "silentai come here", "silentai follow me", "silentai stop", "silentai go to X", "silentai copy emote")
    if TryExecutePublicCommand(sender, text) then
        return
    end

    if Cfg.RespondToNameOnly then
        local named = text:lower():find(Cfg.BotName:lower(), 1, true) ~= nil
        if not named and not MatchesKeywordTrigger(text) then return end
    end
    if PlayerCooldowns[sender.UserId] and now - PlayerCooldowns[sender.UserId] < Cfg.Cooldown then return end
    local queued = Enqueue({ text = text, name = sender.Name, userId = sender.UserId, automatic = true })
    if queued then PlayerCooldowns[sender.UserId] = now end
end)

Runtime.Connect(Players.PlayerRemoving, function(player)
    PlayerCooldowns[player.UserId] = nil
    GreetedPlayers[player.UserId] = nil
    if BotAction.targetPlayer == player then
        StopBotMovement(false)
    end
end)

-- Auto-greet loop
task.spawn(function()
    while Runtime.alive do
        task.wait(3)
        if Runtime.alive and Runtime.ready and Cfg.Enabled and Cfg.AutoGreet and not ProcessingMsg and #MsgQueue == 0 then
            for _, player in ipairs(GetNearbyPlayers(Cfg.ProximityRadius)) do
                local lastGreet = GreetedPlayers[player.userId]
                if IsPlayerAllowed(player.username) and (not lastGreet or os.clock() - lastGreet > Cfg.AutoGreetCooldown) then
                    local queued = Enqueue({
                        text = "Give " .. player.displayName .. " a short friendly greeting.",
                        name = LP.Name,
                        userId = player.userId,
                        automatic = true,
                    })
                    if queued then GreetedPlayers[player.userId] = os.clock() end
                    break
                end
            end
        end
    end
end)

-- Unified Movement Loop (handles public commands: follow me, come here, go to, + AutoFollow)
task.spawn(function()
    while Runtime.alive do
        task.wait(0.25)
        if Runtime.alive and Runtime.ready and Cfg.Enabled then
            local char = LP.Character
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if humanoid and hrp and humanoid.Health > 0 then
                if BotAction.mode == "follow" then
                    local target = BotAction.targetPlayer
                    local tHRP = target and target.Parent and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
                    if not target or not target.Parent then
                        StopBotMovement(false)
                    elseif tHRP then
                        local dist = (hrp.Position - tHRP.Position).Magnitude
                        if dist > Cfg.FollowDistance then
                            pcall(function() humanoid:MoveTo(tHRP.Position) end)
                        end
                    end

                elseif BotAction.mode == "goto_pos" and BotAction.targetPos then
                    local flatDist = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(BotAction.targetPos.X, 0, BotAction.targetPos.Z)).Magnitude
                    if flatDist <= 3.5 then
                        StopBotMovement(false)
                    else
                        pcall(function() humanoid:MoveTo(BotAction.targetPos) end)
                    end

                elseif BotAction.mode == "goto_player" then
                    local target = BotAction.targetPlayer
                    local tHRP = target and target.Parent and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
                    if not target or not target.Parent then
                        StopBotMovement(false)
                    elseif tHRP then
                        local flatDist = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(tHRP.Position.X, 0, tHRP.Position.Z)).Magnitude
                        if flatDist <= math.max(4, Cfg.FollowDistance) then
                            StopBotMovement(false)
                        else
                            pcall(function() humanoid:MoveTo(tHRP.Position) end)
                        end
                    end

                elseif BotAction.mode == "goto_part" then
                    local pos = GetInstanceWorldPos(BotAction.targetPart)
                    if not pos then
                        StopBotMovement(false)
                    else
                        local flatDist = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
                        if flatDist <= 4.5 then
                            StopBotMovement(false)
                        else
                            pcall(function() humanoid:MoveTo(pos) end)
                        end
                    end

                elseif Cfg.AutoFollow then
                    for _, target in ipairs(GetNearbyPlayers(Cfg.ProximityRadius)) do
                        if IsPlayerAllowed(target.username) and target.distance > Cfg.FollowDistance then
                            pcall(function() humanoid:MoveTo(target.hrp.Position) end)
                            break
                        end
                    end
                end
            end
        end
    end
end)

table.insert(Runtime.cleanups, function()
    table.clear(MsgQueue)
    DestroyBillboard()
    StopEmote()
end)

-- ═══════════════════════════════════════
-- groq keys
-- ═══════════════════════════════════════

local function DetectDevicePlatform()
    local ok, platform = pcall(function() return UserInputService:GetPlatform() end)
    if not ok or platform == nil then return nil end
    if platform == Enum.Platform.OSX or platform == Enum.Platform.IOS then return "macos" end
    if platform == Enum.Platform.Windows then return "windows" end
    return nil
end

local DEVICE_PLATFORM = DetectDevicePlatform()
local function SetupStyle()
    if Cfg.SetupStyle == "Windows" or Cfg.SetupStyle == "macOS" then return Cfg.SetupStyle end
    return DEVICE_PLATFORM == "macos" and "macOS" or "Windows"
end

local function RunSetupWizard()
    local isMac = SetupStyle() == "macOS"
    local step, closed = 1, false
    local draftKeysRaw = #Cfg.GroqKeys > 0 and table.concat(Cfg.GroqKeys, "\n") or ""
    local draftModel = Cfg.Model ~= "" and Cfg.Model or GROQ_PROVIDER.defaultModel
    local draftBotName = Cfg.BotName
    local draftLang = Cfg.Language
    local draftPrompt = Cfg.SystemPrompt
    local draftSaveKeys = Cfg.SaveAPIKeys

    local done = Instance.new("BindableEvent")
    local gui = Instance.new("ScreenGui")
    gui.Name = "AIBotSetup"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 100
    gui.Parent = CoreGui

    local function finish(cancelled)
        if closed then return end
        closed = true
        if cancelled then Runtime.Stop() end
        done:Fire()
    end

    table.insert(Runtime.cleanups, function() finish(false); gui:Destroy() end)
    gui.Destroying:Connect(function() finish(false) end)

    local bg = Instance.new("Frame")
    bg.Size = UDim2.fromScale(1, 1)
    bg.BackgroundColor3 = Color3.new(0, 0, 0)
    bg.BackgroundTransparency = 0.65
    bg.BorderSizePixel = 0
    bg.Parent = gui

    local win = Instance.new("Frame")
    win.Size = UDim2.fromOffset(440, 320)
    win.AnchorPoint = Vector2.new(0.5, 0.5)
    win.Position = UDim2.fromScale(0.5, 0.5)
    win.BackgroundColor3 = isMac and Color3.fromRGB(28, 28, 32) or Color3.fromRGB(30, 32, 36)
    win.BorderSizePixel = 0
    win.Parent = bg
    Instance.new("UICorner", win).CornerRadius = UDim.new(0, isMac and 14 or 8)
    local winStroke = Instance.new("UIStroke", win)
    winStroke.Color = isMac and Color3.fromRGB(90, 95, 110) or Color3.fromRGB(60, 65, 72)

    local titleBar = Instance.new("Frame")
    titleBar.Size = UDim2.new(1, 0, 0, 34)
    titleBar.BackgroundTransparency = 1
    titleBar.Parent = win

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -60, 1, 0)
    titleLbl.Position = UDim2.fromOffset(14, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextSize = 13
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.TextColor3 = Color3.fromRGB(240, 242, 245)
    titleLbl.Text = "Groq AI Bot Setup · v" .. VERSION
    titleLbl.Parent = titleBar

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.fromOffset(26, 22)
    closeBtn.AnchorPoint = Vector2.new(1, 0.5)
    closeBtn.Position = UDim2.new(1, -10, 0.5, 0)
    closeBtn.BackgroundColor3 = Color3.fromRGB(180, 55, 55)
    closeBtn.TextColor3 = Color3.new(1, 1, 1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 11
    closeBtn.Text = "✕"
    closeBtn.BorderSizePixel = 0
    closeBtn.Parent = titleBar
    Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 5)
    closeBtn.Activated:Connect(function() finish(true) end)

    local bodyArea = Instance.new("Frame")
    bodyArea.Size = UDim2.new(1, -28, 1, -80)
    bodyArea.Position = UDim2.fromOffset(14, 36)
    bodyArea.BackgroundTransparency = 1
    bodyArea.Parent = win

    local stepLbl = Instance.new("TextLabel")
    stepLbl.Size = UDim2.new(1, 0, 0, 18)
    stepLbl.BackgroundTransparency = 1
    stepLbl.Font = Enum.Font.GothamBold
    stepLbl.TextSize = 12
    stepLbl.TextXAlignment = Enum.TextXAlignment.Left
    stepLbl.TextColor3 = Color3.fromRGB(244, 114, 55)
    stepLbl.Parent = bodyArea

    local descLbl = Instance.new("TextLabel")
    descLbl.Size = UDim2.new(1, 0, 0, 26)
    descLbl.Position = UDim2.fromOffset(0, 18)
    descLbl.BackgroundTransparency = 1
    descLbl.Font = Enum.Font.Gotham
    descLbl.TextSize = 11
    descLbl.TextWrapped = true
    descLbl.TextXAlignment = Enum.TextXAlignment.Left
    descLbl.TextColor3 = Color3.fromRGB(175, 182, 190)
    descLbl.Parent = bodyArea

    local contentFrame = Instance.new("Frame")
    contentFrame.Size = UDim2.new(1, 0, 1, -48)
    contentFrame.Position = UDim2.fromOffset(0, 48)
    contentFrame.BackgroundTransparency = 1
    contentFrame.Parent = bodyArea

    local errLbl = Instance.new("TextLabel")
    errLbl.Size = UDim2.new(1, -186, 0, 28)
    errLbl.Position = UDim2.new(0, 14, 1, -36)
    errLbl.BackgroundTransparency = 1
    errLbl.Font = Enum.Font.GothamMedium
    errLbl.TextSize = 11
    errLbl.TextWrapped = true
    errLbl.TextXAlignment = Enum.TextXAlignment.Left
    errLbl.TextColor3 = Color3.fromRGB(255, 120, 120)
    errLbl.Parent = win

    local backBtn = Instance.new("TextButton")
    backBtn.Size = UDim2.fromOffset(70, 26)
    backBtn.AnchorPoint = Vector2.new(1, 0.5)
    backBtn.Position = UDim2.new(1, -108, 1, -22)
    backBtn.BackgroundColor3 = Color3.fromRGB(52, 56, 62)
    backBtn.TextColor3 = Color3.new(1, 1, 1)
    backBtn.Font = Enum.Font.GothamMedium
    backBtn.TextSize = 11
    backBtn.Text = "Back"
    backBtn.BorderSizePixel = 0
    backBtn.Parent = win
    Instance.new("UICorner", backBtn).CornerRadius = UDim.new(0, 5)

    local nextBtn = Instance.new("TextButton")
    nextBtn.Size = UDim2.fromOffset(88, 26)
    nextBtn.AnchorPoint = Vector2.new(1, 0.5)
    nextBtn.Position = UDim2.new(1, -14, 1, -22)
    nextBtn.BackgroundColor3 = Color3.fromRGB(244, 114, 55)
    nextBtn.TextColor3 = Color3.new(1, 1, 1)
    nextBtn.Font = Enum.Font.GothamBold
    nextBtn.TextSize = 11
    nextBtn.Text = "Next"
    nextBtn.BorderSizePixel = 0
    nextBtn.Parent = win
    Instance.new("UICorner", nextBtn).CornerRadius = UDim.new(0, 5)

    local function clearContent()
        for _, c in ipairs(contentFrame:GetChildren()) do c:Destroy() end
    end

    local renderStep
    renderStep = function(num)
        step = num
        errLbl.Text = ""
        clearContent()
        backBtn.Visible = step > 1
        nextBtn.Text = step == 3 and "Start Bot" or "Next"

        if step == 1 then
            stepLbl.Text = "Step 1 of 3 · Groq API Keys (Unlimited Fallback)"
            descLbl.Text = "Paste 1 or more gsk_... keys (one per line or comma-separated). Auto-switches on failure."

            local countLbl = Instance.new("TextLabel")
            countLbl.Size = UDim2.new(1, 0, 0, 16)
            countLbl.Position = UDim2.fromOffset(0, 2)
            countLbl.BackgroundTransparency = 1
            countLbl.Font = Enum.Font.GothamMedium
            countLbl.TextSize = 11
            countLbl.TextXAlignment = Enum.TextXAlignment.Left
            countLbl.TextColor3 = Color3.fromRGB(146, 222, 184)
            countLbl.Parent = contentFrame

            local keyBox = Instance.new("TextBox")
            keyBox.Size = UDim2.new(1, 0, 1, -56)
            keyBox.Position = UDim2.fromOffset(0, 20)
            keyBox.BackgroundColor3 = Color3.fromRGB(42, 45, 50)
            keyBox.TextColor3 = Color3.new(1, 1, 1)
            keyBox.PlaceholderText = "gsk_key1...\ngsk_key2...\ngsk_key3..."
            keyBox.Text = draftKeysRaw
            keyBox.ClearTextOnFocus = false
            keyBox.MultiLine = true
            keyBox.TextWrapped = true
            keyBox.TextXAlignment = Enum.TextXAlignment.Left
            keyBox.TextYAlignment = Enum.TextYAlignment.Top
            keyBox.Font = Enum.Font.Code
            keyBox.TextSize = 11
            keyBox.Parent = contentFrame
            Instance.new("UICorner", keyBox).CornerRadius = UDim.new(0, 5)

            local function refreshCount()
                local n = #ParseKeyList(draftKeysRaw)
                countLbl.Text = n == 0 and "No keys entered yet" or (tostring(n) .. " Groq key(s) detected in fallback pool")
            end
            refreshCount()
            keyBox:GetPropertyChangedSignal("Text"):Connect(function()
                draftKeysRaw = keyBox.Text
                refreshCount()
            end)

            local saveToggle = Instance.new("TextButton")
            saveToggle.Size = UDim2.new(1, 0, 0, 26)
            saveToggle.Position = UDim2.new(0, 0, 1, -28)
            saveToggle.BackgroundColor3 = Color3.fromRGB(42, 45, 50)
            saveToggle.TextColor3 = Color3.fromRGB(220, 224, 228)
            saveToggle.Font = Enum.Font.GothamMedium
            saveToggle.TextSize = 11
            saveToggle.BorderSizePixel = 0
            saveToggle.Parent = contentFrame
            Instance.new("UICorner", saveToggle).CornerRadius = UDim.new(0, 5)
            local function refreshSaveText()
                saveToggle.Text = "Save Groq keys on disk: " .. (draftSaveKeys and "ON (plain text)" or "OFF (session only)")
            end
            refreshSaveText()
            saveToggle.Activated:Connect(function()
                draftSaveKeys = not draftSaveKeys
                refreshSaveText()
            end)

        elseif step == 2 then
            stepLbl.Text = "Step 2 of 3 · Groq Model"
            descLbl.Text = "Select or type an exact Groq model ID."

            local modelBox = Instance.new("TextBox")
            modelBox.Size = UDim2.new(1, -102, 0, 28)
            modelBox.Position = UDim2.fromOffset(0, 2)
            modelBox.BackgroundColor3 = Color3.fromRGB(42, 45, 50)
            modelBox.TextColor3 = Color3.new(1, 1, 1)
            modelBox.Text = draftModel
            modelBox.ClearTextOnFocus = false
            modelBox.Font = Enum.Font.Code
            modelBox.TextSize = 11
            modelBox.Parent = contentFrame
            Instance.new("UICorner", modelBox).CornerRadius = UDim.new(0, 5)
            modelBox:GetPropertyChangedSignal("Text"):Connect(function() draftModel = Trim(modelBox.Text) end)

            local fetchBtn = Instance.new("TextButton")
            fetchBtn.Size = UDim2.fromOffset(94, 28)
            fetchBtn.Position = UDim2.new(1, -94, 0, 2)
            fetchBtn.BackgroundColor3 = Color3.fromRGB(55, 60, 68)
            fetchBtn.TextColor3 = Color3.new(1, 1, 1)
            fetchBtn.Font = Enum.Font.GothamMedium
            fetchBtn.TextSize = 11
            fetchBtn.Text = "Fetch Models"
            fetchBtn.BorderSizePixel = 0
            fetchBtn.Parent = contentFrame
            Instance.new("UICorner", fetchBtn).CornerRadius = UDim.new(0, 5)

            local list = Instance.new("ScrollingFrame")
            list.Size = UDim2.new(1, 0, 1, -36)
            list.Position = UDim2.fromOffset(0, 36)
            list.BackgroundColor3 = Color3.fromRGB(24, 26, 30)
            list.ScrollBarThickness = 3
            list.CanvasSize = UDim2.new()
            list.AutomaticCanvasSize = Enum.AutomaticSize.Y
            list.Parent = contentFrame
            Instance.new("UICorner", list).CornerRadius = UDim.new(0, 5)
            local layout = Instance.new("UIListLayout", list)
            layout.Padding = UDim.new(0, 3)

            local function populate(entries)
                for _, child in ipairs(list:GetChildren()) do
                    if child:IsA("TextButton") then child:Destroy() end
                end
                for _, entry in ipairs(entries) do
                    local row = Instance.new("TextButton")
                    row.Size = UDim2.new(1, -6, 0, 24)
                    row.BackgroundColor3 = draftModel == entry.id and Color3.fromRGB(65, 42, 32) or Color3.fromRGB(38, 41, 46)
                    row.TextColor3 = Color3.new(1, 1, 1)
                    row.Font = Enum.Font.Gotham
                    row.TextSize = 11
                    row.TextXAlignment = Enum.TextXAlignment.Left
                    row.Text = "  " .. (entry.label or entry.id)
                    row.BorderSizePixel = 0
                    row.Parent = list
                    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
                    row.Activated:Connect(function()
                        draftModel = entry.id
                        modelBox.Text = entry.id
                        populate(entries)
                    end)
                end
            end
            populate(GROQ_PROVIDER.models)

            fetchBtn.Activated:Connect(function()
                fetchBtn.Text = "Loading..."
                task.spawn(function()
                    local models, err = DiscoverGroqModels(draftKeysRaw)
                    if closed or not Runtime.alive then return end
                    fetchBtn.Text = "Fetch Models"
                    if models then
                        populate(models)
                        errLbl.Text = ""
                    else
                        errLbl.Text = err or "Could not fetch Groq models."
                    end
                end)
            end)

        elseif step == 3 then
            stepLbl.Text = "Step 3 of 3 · Bot Name & Personality"
            descLbl.Text = "Set bot name, language, and personality preset (includes Catboy & -deres)."

            local nameBox = Instance.new("TextBox")
            nameBox.Size = UDim2.new(0.48, 0, 0, 26)
            nameBox.Position = UDim2.fromOffset(0, 2)
            nameBox.BackgroundColor3 = Color3.fromRGB(42, 45, 50)
            nameBox.TextColor3 = Color3.new(1, 1, 1)
            nameBox.PlaceholderText = "Bot Name"
            nameBox.Text = draftBotName
            nameBox.ClearTextOnFocus = false
            nameBox.Font = Enum.Font.Gotham
            nameBox.TextSize = 11
            nameBox.Parent = contentFrame
            Instance.new("UICorner", nameBox).CornerRadius = UDim.new(0, 5)
            nameBox:GetPropertyChangedSignal("Text"):Connect(function() draftBotName = Trim(nameBox.Text) end)

            local langBox = Instance.new("TextBox")
            langBox.Size = UDim2.new(0.48, 0, 0, 26)
            langBox.Position = UDim2.new(0.52, 0, 0, 2)
            langBox.BackgroundColor3 = Color3.fromRGB(42, 45, 50)
            langBox.TextColor3 = Color3.new(1, 1, 1)
            langBox.PlaceholderText = "Language (Auto)"
            langBox.Text = draftLang
            langBox.ClearTextOnFocus = false
            langBox.Font = Enum.Font.Gotham
            langBox.TextSize = 11
            langBox.Parent = contentFrame
            Instance.new("UICorner", langBox).CornerRadius = UDim.new(0, 5)
            langBox:GetPropertyChangedSignal("Text"):Connect(function() draftLang = Trim(langBox.Text) end)

            local presetBar = Instance.new("ScrollingFrame")
            presetBar.Size = UDim2.new(1, 0, 0, 26)
            presetBar.Position = UDim2.fromOffset(0, 32)
            presetBar.BackgroundTransparency = 1
            presetBar.ScrollBarThickness = 2
            presetBar.ScrollingDirection = Enum.ScrollingDirection.X
            presetBar.CanvasSize = UDim2.new()
            presetBar.AutomaticCanvasSize = Enum.AutomaticSize.X
            presetBar.Parent = contentFrame
            local pLayout = Instance.new("UIListLayout", presetBar)
            pLayout.FillDirection = Enum.FillDirection.Horizontal
            pLayout.Padding = UDim.new(0, 4)

            local promptBox = Instance.new("TextBox")
            promptBox.Size = UDim2.new(1, 0, 1, -64)
            promptBox.Position = UDim2.fromOffset(0, 62)
            promptBox.BackgroundColor3 = Color3.fromRGB(42, 45, 50)
            promptBox.TextColor3 = Color3.new(1, 1, 1)
            promptBox.Text = draftPrompt
            promptBox.ClearTextOnFocus = false
            promptBox.MultiLine = true
            promptBox.TextWrapped = true
            promptBox.TextXAlignment = Enum.TextXAlignment.Left
            promptBox.TextYAlignment = Enum.TextYAlignment.Top
            promptBox.Font = Enum.Font.Gotham
            promptBox.TextSize = 11
            promptBox.Parent = contentFrame
            Instance.new("UICorner", promptBox).CornerRadius = UDim.new(0, 5)
            promptBox:GetPropertyChangedSignal("Text"):Connect(function() draftPrompt = promptBox.Text end)

            for _, p in ipairs(PERSONALITIES) do
                if p.prompt ~= "" then
                    local chip = Instance.new("TextButton")
                    chip.Size = UDim2.fromOffset(96, 22)
                    chip.BackgroundColor3 = Color3.fromRGB(45, 49, 55)
                    chip.TextColor3 = Color3.new(1, 1, 1)
                    chip.Font = Enum.Font.GothamMedium
                    chip.TextSize = 10
                    chip.Text = p.emoji .. " " .. p.name
                    chip.BorderSizePixel = 0
                    chip.Parent = presetBar
                    Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 4)
                    chip.Activated:Connect(function()
                        draftPrompt = p.prompt
                        promptBox.Text = p.prompt
                    end)
                end
            end
        end
    end

    backBtn.Activated:Connect(function()
        if step > 1 then renderStep(step - 1) end
    end)

    nextBtn.Activated:Connect(function()
        if step == 1 and #ParseKeyList(draftKeysRaw) == 0 then
            errLbl.Text = "Please enter at least one Groq API key."
            return
        end
        if step == 2 and Trim(draftModel) == "" then
            errLbl.Text = "Please choose or type a Groq model ID."
            return
        end
        if step == 3 and Trim(draftPrompt) == "" then
            errLbl.Text = "Please enter a system prompt."
            return
        end
        if step < 3 then
            renderStep(step + 1)
            return
        end

        local keys = ParseKeyList(draftKeysRaw)
        Cfg.Provider = "groq"
        Cfg.GroqKeys = keys
        Cfg.ActiveKeyIndex = 1
        Cfg.GroqKey = keys[1] or "YOUR_GROQ_API_KEY"
        Cfg.Model = Trim(draftModel)
        Cfg.BotName = Trim(draftBotName) ~= "" and Trim(draftBotName) or "silentai"
        Cfg.Language = Trim(draftLang) ~= "" and Trim(draftLang) or "Auto"
        Cfg.SystemPrompt = draftPrompt
        Cfg.SaveAPIKeys = draftSaveKeys
        Cfg.SetupComplete = true
        NormalizeCfg()
        SaveCfg()
        finish(false)
    end)

    renderStep(1)
    done.Event:Wait()
    gui:Destroy()
    done:Destroy()
end

if not setupAlreadyDone then RunSetupWizard() end

-- ═══════════════════════════════════════
-- RAYFIELD 
-- ═══════════════════════════════════════

if not Runtime.alive then return end
local loaded, library = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)
if not loaded or type(library) ~= "table" or type(library.CreateWindow) ~= "function" then
    SafeNotify({ Title = "UI unavailable", Content = "Could not load Rayfield. Check your connection and execute the script again." })
    Runtime.Stop()
    return
end
local Rayfield = library

local C = {
    BG       = Color3.fromRGB(19, 22, 24),
    CARD     = Color3.fromRGB(27, 31, 33),
    SELECTED = Color3.fromRGB(48, 34, 28),
    BORDER   = Color3.fromRGB(57, 64, 65),
    TEXT     = Color3.fromRGB(237, 240, 237),
    ACCENT   = Color3.fromRGB(244, 114, 55),
}

local Win = Rayfield:CreateWindow({
    name = "Groq AI Chat Bot v" .. VERSION,
    subtitle = "Groq · " .. Cfg.Model,
    showName = "Groq AI Bot",
    sidebarLayout = false,
    configuration = { autoSave = false, autoLoad = false },
    theme = {
        WindowColor = C.BG,
        ContentColor = C.TEXT,
        TitlingColor = C.TEXT,
        ElementGradient = C.CARD,
        ElementStroke = C.BORDER,
        SurfaceStroke = C.BORDER,
        TabBackground = C.SELECTED,
        TabColor = C.ACCENT,
        TabStroke = C.BORDER,
        AccentColor = C.ACCENT,
        AccentStroke = C.ACCENT,
        AccentGlow = 1,
        SliderProgress = C.ACCENT,
        LiveAnimation = false,
    },
})
PanelWindow = Win
table.insert(Runtime.cleanups, function() Win:Unload(); PanelWindow = nil end)
Runtime.ready = true

local function SessionSummary()
    local stats = Runtime.stats
    return string.format("Groq (%d keys · #%d active) · %s\n%s · Action: %s · Queue %d/%d · Replies %d",
        #Cfg.GroqKeys, Cfg.ActiveKeyIndex, Cfg.Model, Cfg.Enabled and "Replying" or "Paused",
        BotAction.mode, #MsgQueue, Cfg.QueueLimit, stats.replies)
end

-- ─── Home ───
local TabHome = Win:CreateTab({ name = "Home" })
TabHome:CreateSection({ name = "Bot" })
local statusText
TabHome:CreateToggle({
    name = "Enable AI Chat Bot",
    value = Cfg.Enabled,
    callback = function(v)
        SetEnabled(v)
        SaveCfg()
        if statusText then statusText:Set(SessionSummary()) end
    end,
    forgetState = true,
})
statusText = TabHome:CreateText({ name = "Status", text = SessionSummary() })
TabHome:CreateButton({
    name = "Refresh Status",
    callback = function()
        local stats = Runtime.stats
        statusText:Set(SessionSummary())
        SafeNotify({
            Title = "Session status",
            Content = string.format(
                "Provider: Groq (%d keys, #%d active)\nModel: %s | Action: %s\nQueue: %d / %d | Busy: %s\nRequests: %d | Replies: %d | Errors: %d\nLast error: %s",
                #Cfg.GroqKeys, Cfg.ActiveKeyIndex, Cfg.Model, BotAction.mode, #MsgQueue, Cfg.QueueLimit, tostring(ProcessingMsg),
                stats.requests, stats.replies, stats.errors, stats.lastError
            ),
            Duration = 12,
        })
    end,
})

TabHome:CreateSection({ name = "Voice Chat (VC) support" })
local vcStatusText = TabHome:CreateText({ name = "VC status", text = select(1, GetVCStatus()) })
TabHome:CreateToggle({
    name = "Support Roblox Voice Chat (VC)",
    value = Cfg.VCSupport,
    callback = function(v)
        Cfg.VCSupport = v
        SaveCfg()
        vcStatusText:Set(select(1, GetVCStatus()))
    end,
    forgetState = true,
})
TabHome:CreateToggle({
    name = "Include VC status in AI context",
    value = Cfg.VCIncludeContext,
    callback = function(v)
        Cfg.VCIncludeContext = v
        SaveCfg()
    end,
    forgetState = true,
})
TabHome:CreateButton({
    name = "Check / Prompt VC",
    callback = function()
        local statusMsg = select(1, GetVCStatus())
        vcStatusText:Set(statusMsg)
        local ok, actionMsg = PromptVCAction()
        SafeNotify({ Title = "Voice Chat", Content = statusMsg .. "\n" .. actionMsg, Duration = 8 })
    end,
})

TabHome:CreateSection({ name = "Quick actions & custom chat" })
TabHome:CreateButton({
    name = "Say hello in chat (public test)",
    callback = function()
        QueueManual({
            text = "Hello there!",
            name = LP.Name,
            userId = LP.UserId,
            callback = function(result, err)
                if not result then SafeNotify({ Title = "Test failed", Content = err }) end
            end,
        })
    end,
})
TabHome:CreateButton({ name = "Introduce the bot in chat", callback = function() task.spawn(DoIntroduce) end })
TabHome:CreateButton({
    name = "Stop active movement / copied emote",
    callback = function()
        StopBotMovement(true)
        if statusText then statusText:Set(SessionSummary()) end
        SafeNotify({ Title = "Stopped", Content = "Stopped active movement and copied emote." })
    end,
})
TabHome:CreateButton({
    name = "Cancel Pending Replies",
    callback = function()
        InvalidatePending()
        UpdateBillboard(Cfg.Enabled and "ready" or "paused")
        statusText:Set(SessionSummary())
        SafeNotify({ Title = "Queue cleared", Content = "Pending replies have been cancelled." })
    end,
})

local customSayText = ""
TabHome:CreateInput({
    name = "Custom public message",
    placeholder = "Type a line for the bot to say...",
    callback = function(v) customSayText = v end,
    forgetState = true,
})
TabHome:CreateButton({
    name = "Generate & send public message",
    callback = function()
        if Trim(customSayText) == "" then
            SafeNotify({ Title = "Empty", Content = "Enter a message topic or line first.", Duration = 3 })
            return
        end
        QueueManual({
            text = "Say this in your own style: " .. customSayText,
            name = LP.Name,
            userId = LP.UserId,
            callback = function(result, err)
                if not result then SafeNotify({ Title = "Send failed", Content = err }) end
            end,
        })
    end,
})

TabHome:CreateSection({ name = "Private chat" })
local uiChatInput = ""
TabHome:CreateInput({ name = "Your message", placeholder = "Ask silentai something...", callback = function(v) uiChatInput = v end, forgetState = true })
TabHome:CreateButton({
    name = "Send privately",
    callback = function()
        if Trim(uiChatInput) == "" then SafeNotify({ Title = "Empty", Content = "Type something first.", Duration = 2 }); return end
        QueueManual({
            text = uiChatInput,
            name = LP.Name,
            userId = LP.UserId,
            private = true,
            callback = function(result, err)
                SafeNotify({ Title = result and "Groq says:" or "No response", Content = result or err, Duration = 12 })
            end,
        })
    end,
})
TabHome:CreateButton({
    name = "Clear private conversation",
    callback = function()
        InvalidatePending()
        table.clear(PrivateHistory)
        SaveMemory()
        SafeNotify({ Title = "Private memory cleared", Content = "Your public conversation is still available." })
    end,
})

-- ─── Personality ───
local TabPersonality = Win:CreateTab({ name = "Personality" })
TabPersonality:CreateSection({ name = "Identity" })
TabPersonality:CreateInput({
    name = "Bot Name",
    placeholder = "silentai",
    value = Cfg.BotName,
    callback = function(v) Cfg.BotName = Trim(v) ~= "" and Trim(v) or "silentai"; SaveCfg(); UpdateBillboard() end,
    forgetState = true,
})
TabPersonality:CreateInput({
    name = "Reply language",
    placeholder = "Auto, Spanish, Japanese...",
    value = Cfg.Language or "Auto",
    callback = function(v) Cfg.Language = Trim(v) ~= "" and Trim(v) or "Auto"; SaveCfg() end,
    forgetState = true,
})
TabPersonality:CreateInput({
    name = "Chat prefix",
    placeholder = "e.g. [AI]: ",
    value = Cfg.ChatPrefix,
    callback = function(v) Cfg.ChatPrefix = v; SaveCfg() end,
    forgetState = true,
})

TabPersonality:CreateSection({ name = "Personality" })
local PRESET_OPTIONS, PRESET_BY_LABEL = {}, {}
for _, p in ipairs(PERSONALITIES) do
    local label = p.emoji .. " " .. p.name
    table.insert(PRESET_OPTIONS, label)
    PRESET_BY_LABEL[label] = p
end
local function CurrentPresetLabel()
    for _, p in ipairs(PERSONALITIES) do
        if p.prompt ~= "" and p.prompt == Cfg.SystemPrompt then return p.emoji .. " " .. p.name end
    end
    return PRESET_OPTIONS[#PRESET_OPTIONS]
end
local presetDropdown, promptInput
presetDropdown = TabPersonality:CreateDropdown({
    name = "Personality preset",
    options = PRESET_OPTIONS,
    value = CurrentPresetLabel(),
    multiSelect = false,
    callback = function(label)
        local preset = PRESET_BY_LABEL[label]
        if not preset or preset.prompt == "" then return end
        Cfg.SystemPrompt = preset.prompt
        SaveCfg()
        if promptInput then promptInput:Set(preset.prompt, true) end
        SafeNotify({ Title = "Personality set", Content = preset.name })
    end,
    forgetState = true,
})
promptInput = TabPersonality:CreateInput({
    name = "System prompt",
    placeholder = "Describe how the bot talks and behaves...",
    value = Cfg.SystemPrompt,
    callback = function(v)
        if Trim(v) == "" then return end
        Cfg.SystemPrompt = v
        SaveCfg()
        presetDropdown:Set(CurrentPresetLabel(), true)
    end,
    forgetState = true,
})

TabPersonality:CreateSection({ name = "Reply style" })
local lengthNames = {}
for _, lm in ipairs(LENGTH_MODES) do table.insert(lengthNames, lm.name) end
TabPersonality:CreateDropdown({
    name = "Reply length",
    options = lengthNames,
    value = LENGTH_MODES[Cfg.LengthMode] and LENGTH_MODES[Cfg.LengthMode].name or "Normal",
    multiSelect = false,
    callback = function(val)
        for i, lm in ipairs(LENGTH_MODES) do
            if lm.name == val then Cfg.LengthMode = i; Cfg.MaxTokens = lm.maxTok; SaveCfg(); break end
        end
    end,
    forgetState = true,
})
TabPersonality:CreateToggle({ name = "Brief pause before replying", value = Cfg.ThinkDelay, callback = function(v) Cfg.ThinkDelay = v; SaveCfg() end, forgetState = true })
TabPersonality:CreateSlider({ name = "Creativity (1 precise - 20 wild)", increment = 1, range = {1, 20}, value = math.round(Cfg.Temperature * 10), callback = function(v) Cfg.Temperature = v / 10; SaveCfg() end, forgetState = true })
TabPersonality:CreateSlider({ name = "Max reply tokens", increment = 10, range = {40, 500}, value = Cfg.MaxTokens, callback = function(v) Cfg.MaxTokens = v; SaveCfg() end, forgetState = true })

-- ─── Replies & Movement ───
local TabReplies = Win:CreateTab({ name = "Replies" })
TabReplies:CreateSection({ name = "Public chat commands" })
TabReplies:CreateToggle({
    name = "Enable public commands ((name) come here, follow me, stop, go to, copy emote)",
    value = Cfg.PublicCommands,
    callback = function(v) Cfg.PublicCommands = v; SaveCfg() end,
    forgetState = true,
})
TabReplies:CreateText({
    name = "Public command syntax",
    text = "• (name) come here  • (name) follow me  • (name) stop\n• (name) go to (player or workspace item)  • (name) copy emote",
})

TabReplies:CreateSection({ name = "Who it replies to" })
TabReplies:CreateToggle({ name = "Reply to everyone (ignore distance)", value = Cfg.RespondToAll, callback = function(v) Cfg.RespondToAll = v; SaveCfg() end, forgetState = true })
TabReplies:CreateToggle({ name = "Only reply when named", value = Cfg.RespondToNameOnly, callback = function(v) Cfg.RespondToNameOnly = v; SaveCfg() end, forgetState = true })
TabReplies:CreateInput({
    name = "Extra trigger keywords (comma-separated)",
    placeholder = "gg, trade, help",
    value = Cfg.TriggerKeywords,
    callback = function(v) Cfg.TriggerKeywords = Trim(v); SaveCfg() end,
    forgetState = true,
})
TabReplies:CreateSlider({ name = "Reply radius (studs)", increment = 5, range = {5, 300}, value = Cfg.ProximityRadius, callback = function(v) Cfg.ProximityRadius = v; SaveCfg() end, forgetState = true })
TabReplies:CreateSlider({ name = "Cooldown per player (seconds)", increment = 1, range = {1, 60}, value = Cfg.Cooldown, callback = function(v) Cfg.Cooldown = v; SaveCfg() end, forgetState = true })
TabReplies:CreateToggle({ name = "Local Preview (only visible to you)", value = Cfg.WhisperMode, callback = function(v) Cfg.WhisperMode = v; SaveCfg() end, forgetState = true })

TabReplies:CreateSection({ name = "Greetings & follow" })
TabReplies:CreateToggle({ name = "Greet nearby players", value = Cfg.AutoGreet, callback = function(v) Cfg.AutoGreet = v; SaveCfg() end, forgetState = true })
TabReplies:CreateSlider({ name = "Greet cooldown per player (seconds)", increment = 30, range = {30, 600}, value = Cfg.AutoGreetCooldown, callback = function(v) Cfg.AutoGreetCooldown = v; SaveCfg() end, forgetState = true })
TabReplies:CreateToggle({ name = "Auto-follow closest nearby player", value = Cfg.AutoFollow, callback = function(v) Cfg.AutoFollow = v; SaveCfg() end, forgetState = true })
TabReplies:CreateSlider({ name = "Follow stop distance (studs)", increment = 1, range = {3, 25}, value = Cfg.FollowDistance, callback = function(v) Cfg.FollowDistance = v; SaveCfg() end, forgetState = true })

TabReplies:CreateSection({ name = "Player lists" })
local listsText
local function ListsSummary()
    return "Whitelist: " .. (#Cfg.Whitelist > 0 and table.concat(Cfg.Whitelist, ", ") or "empty (anyone allowed)")
        .. "\nBlacklist: " .. (#Cfg.Blacklist > 0 and table.concat(Cfg.Blacklist, ", ") or "empty")
end
local function CleanName(v) return (Trim(v):gsub("^@", ""):lower()) end
local function AddToList(list, v, title)
    local name = CleanName(v)
    if name == "" then return end
    if not table.find(list, name) then table.insert(list, name) end
    SaveCfg()
    listsText:Set(ListsSummary())
    SafeNotify({ Title = title, Content = name })
end
listsText = TabReplies:CreateText({ name = "Current lists", text = ListsSummary() })
TabReplies:CreateInput({ name = "Add to whitelist", placeholder = "PlayerName", callback = function(v) AddToList(Cfg.Whitelist, v, "Whitelisted") end, forgetState = true })
TabReplies:CreateInput({ name = "Add to blacklist", placeholder = "PlayerName", callback = function(v) AddToList(Cfg.Blacklist, v, "Blacklisted") end, forgetState = true })
TabReplies:CreateInput({
    name = "Remove from lists",
    placeholder = "PlayerName",
    callback = function(v)
        local name = CleanName(v)
        if name == "" then return end
        for _, list in ipairs({ Cfg.Whitelist, Cfg.Blacklist }) do
            local index = table.find(list, name)
            if index then table.remove(list, index) end
        end
        SaveCfg()
        listsText:Set(ListsSummary())
    end,
    forgetState = true,
})
TabReplies:CreateButton({ name = "Clear whitelist", callback = function() Cfg.Whitelist = {}; SaveCfg(); listsText:Set(ListsSummary()) end })
TabReplies:CreateButton({ name = "Clear blacklist", callback = function() Cfg.Blacklist = {}; SaveCfg(); listsText:Set(ListsSummary()) end })

-- ─── Groq API  ───
local TabProvider = Win:CreateTab({ name = "Groq API" })
TabProvider:CreateSection({ name = "Groq Connection & Key Pool" })

local function KeyPoolSummary()
    local total = #Cfg.GroqKeys
    if total == 0 then
        return "Provider: Groq · Model: " .. Cfg.Model .. "\nKeys: 0 loaded (add keys below)"
    end
    local preview = {}
    for i, k in ipairs(Cfg.GroqKeys) do
        local prefix = (i == Cfg.ActiveKeyIndex) and "▶ #" or "  #"
        table.insert(preview, prefix .. tostring(i) .. ": " .. MaskKey(k))
        if i >= 6 and total > 6 then
            table.insert(preview, "  ... +" .. tostring(total - 6) .. " more key(s)")
            break
        end
    end
    return string.format("Provider: Groq · Model: %s\nKeys: %d total (Active: #%d)\n%s",
        Cfg.Model, total, Cfg.ActiveKeyIndex, table.concat(preview, "\n"))
end

local connectionText = TabProvider:CreateText({ name = "Active key pool", text = KeyPoolSummary() })

TabProvider:CreateInput({
    name = "Add Groq API key(s)",
    placeholder = "Paste 1 or many gsk_... keys (comma/space/newline separated)",
    callback = function(v)
        local incoming = ParseKeyList(v)
        if #incoming == 0 then return end
        local added = 0
        for _, k in ipairs(incoming) do
            if not table.find(Cfg.GroqKeys, k) then
                table.insert(Cfg.GroqKeys, k)
                added = added + 1
            end
        end
        SyncKeyPool()
        InvalidatePending()
        SaveCfg()
        connectionText:Set(KeyPoolSummary())
        if statusText then statusText:Set(SessionSummary()) end
        SafeNotify({
            Title = "Groq keys updated",
            Content = string.format("Added %d new key(s). Total keys in pool: %d", added, #Cfg.GroqKeys),
        })
    end,
    forgetState = true,
})

TabProvider:CreateButton({
    name = "Rotate to next Groq key now",
    callback = function()
        if #Cfg.GroqKeys <= 1 then
            SafeNotify({ Title = "Single key", Content = "Add 2 or more keys to rotate between them." })
            return
        end
        Cfg.ActiveKeyIndex = (Cfg.ActiveKeyIndex % #Cfg.GroqKeys) + 1
        Cfg.GroqKey = Cfg.GroqKeys[Cfg.ActiveKeyIndex]
        SaveCfg()
        connectionText:Set(KeyPoolSummary())
        if statusText then statusText:Set(SessionSummary()) end
        SafeNotify({
            Title = "Switched active key",
            Content = string.format("Now using Key #%d (%s)", Cfg.ActiveKeyIndex, MaskKey(Cfg.GroqKey)),
        })
    end,
})

TabProvider:CreateButton({
    name = "Clear all Groq keys",
    callback = function()
        Cfg.GroqKeys = {}
        Cfg.GroqKey = "YOUR_GROQ_API_KEY"
        Cfg.ActiveKeyIndex = 1
        InvalidatePending()
        SaveCfg()
        connectionText:Set(KeyPoolSummary())
        if statusText then statusText:Set(SessionSummary()) end
        SafeNotify({ Title = "Keys cleared", Content = "All Groq API keys have been removed." })
    end,
})

TabProvider:CreateInput({
    name = "Model ID",
    value = Cfg.Model,
    placeholder = "Exact Groq model ID",
    callback = function(value)
        if SetModel(value) then
            connectionText:Set(KeyPoolSummary())
            SafeNotify({ Title = "Groq model updated", Content = Cfg.Model })
        end
    end,
    forgetState = true,
})

TabProvider:CreateToggle({
    name = "Remember Groq API key(s) on this device",
    value = Cfg.SaveAPIKeys,
    callback = function(value)
        Cfg.SaveAPIKeys = value
        local ok, err = SaveCfg()
        if not ok then SafeNotify({ Title = "Settings not saved", Content = err }) end
    end,
    forgetState = true,
})

TabProvider:CreateButton({
    name = "Test Groq Connection & Failover (private)",
    callback = function()
        QueueManual({
            text = "Reply with: Groq connection successful.",
            name = LP.Name,
            private = true,
            callback = function(result, err)
                connectionText:Set(KeyPoolSummary())
                if statusText then statusText:Set(SessionSummary()) end
                SafeNotify({
                    Title = result and ("Groq working (Key #" .. Cfg.ActiveKeyIndex .. ")") or "Groq failed",
                    Content = result or err,
                    Duration = 8,
                })
            end,
        })
    end,
})

TabProvider:CreateButton({
    name = "Reopen setup on next run",
    callback = function()
        Cfg.SetupComplete = false
        SaveCfg()
        SafeNotify({ Title = "Setup reset", Content = "Execute the script again to open setup." })
        Runtime.Stop()
    end,
})

-- ─── Emotes ───
local TabEmotes = Win:CreateTab({ name = "Emotes" })
TabEmotes:CreateSection({ name = "Play or stop an emote" })
local emoteList = {
    { "Wave", "WAVE" }, { "Dance 1", "DANCE" }, { "Dance 2", "DANCE2" },
    { "Dance 3", "DANCE3" }, { "Laugh", "LAUGH" }, { "Point", "POINT" }, { "Cheer", "CHEER" },
}
for _, e in ipairs(emoteList) do
    TabEmotes:CreateButton({ name = e[1], callback = function() PlayEmote(e[2]) end })
end
TabEmotes:CreateButton({ name = "Stop current emote", callback = function() StopEmote() end })

-- ─── Settings ───
local TabSettings = Win:CreateTab({ name = "Settings" })
TabSettings:CreateSection({ name = "Interface & memory" })
TabSettings:CreateToggle({ name = "Show Status Billboard", value = Cfg.ShowBillboard, callback = function(v) Cfg.ShowBillboard = v; UpdateBillboard(); SaveCfg() end, forgetState = true })
TabSettings:CreateSlider({
    name = "Memory messages per conversation",
    increment = 2,
    range = {2, 100},
    value = Cfg.MemoryLimit,
    callback = function(value)
        Cfg.MemoryLimit = value
        NormalizeCfg()
        History = CleanHistory(History)
        PrivateHistory = CleanHistory(PrivateHistory)
        InvalidatePending()
        SaveMemory()
        SaveCfg()
    end,
    forgetState = true,
})
TabSettings:CreateToggle({
    name = "Remember conversations between runs",
    value = Cfg.RememberHistory,
    callback = function(value)
        Cfg.RememberHistory = value
        SaveCfg()
        local ok, err = SaveMemory()
        if not ok then SafeNotify({ Title = "Memory not saved", Content = err }) end
    end,
    forgetState = true,
})
TabSettings:CreateButton({
    name = "Clear all conversation memory",
    callback = function()
        ClearMemory()
        SafeNotify({ Title = "Memory cleared", Content = "Public and private conversation history wiped." })
    end,
})
TabSettings:CreateButton({
    name = "Export public chat log",
    callback = function()
        local ok, fn = ExportChatLog()
        SafeNotify({ Title = ok and "Log exported" or "Export failed", Content = ok and ("Saved to " .. fn) or fn })
    end,
})

TabSettings:CreateSection({ name = "Requests & queue" })
TabSettings:CreateSlider({ name = "Minimum gap between requests (seconds)", increment = 1, range = {1, 60}, value = Cfg.GlobalCooldown, callback = function(value) Cfg.GlobalCooldown = value; SaveCfg() end, forgetState = true })
TabSettings:CreateSlider({ name = "Maximum queued messages", increment = 1, range = {1, 50}, value = Cfg.QueueLimit, callback = function(value) Cfg.QueueLimit = value; SaveCfg() end, forgetState = true })
TabSettings:CreateSlider({ name = "Request timeout (seconds)", increment = 5, range = {5, 120}, value = Cfg.RequestTimeout, callback = function(value) Cfg.RequestTimeout = value; SaveCfg() end, forgetState = true })

TabSettings:CreateSection({ name = "Help & unload" })
TabSettings:CreateText({
    name = "Local commands",
    text = "/ai on • /ai off • /ai stop • /ai follow [on|off] • /ai vc • /ai keys • /ai clear • /ai model MODEL_ID • /ai status\nK toggles the control panel.",
})
TabSettings:CreateButton({
    name = "Save Settings Now",
    callback = function()
        local ok, err = SaveCfg()
        SafeNotify({ Title = ok and "Settings saved" or "Save failed", Content = ok and SAVE_FILE or err })
    end,
})
TabSettings:CreateButton({
    name = "❌ Unload Bot",
    callback = function()
        SaveMemory()
        SaveCfg()
        Runtime.Stop()
        warn("[AI Bot] Unloaded. Execute the script again to restart.")
    end,
})

-- ═══════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════

UpdateBillboard(Cfg.Enabled and "ready" or "paused")

task.spawn(function()
    task.wait(1.5)
    SafeNotify({
        Title = "Groq AI Chat Bot v" .. VERSION .. " Ready",
        Content = string.format("Bot: %s | Model: %s\nGroq Keys Loaded: %d (#%d active)\nPublic Commands: %s",
            Cfg.BotName, Cfg.Model, #Cfg.GroqKeys, Cfg.ActiveKeyIndex, Cfg.PublicCommands and "On" or "Off"),
        Duration = 6,
    })
end)

warn("[Groq AI Bot v" .. VERSION .. "] Loaded. Model: " .. Cfg.Model .. " | Keys: " .. tostring(#Cfg.GroqKeys))
