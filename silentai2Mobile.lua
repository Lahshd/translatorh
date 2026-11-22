local VERSION = "25"
-- One lifecycle per client, including when this script is executed again.
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
            title = data.Title or "SilentAI",
            content = data.Content or "",
            duration = data.Duration or 5,
        })
    end)
    if not ok then
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = data.Title or "SilentAI",
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

local Players            = game:GetService("Players")
local TCS                = game:GetService("TextChatService")
local HttpService        = game:GetService("HttpService")
local TweenService       = game:GetService("TweenService")
local UserInputService   = game:GetService("UserInputService")
local PathfindingService = game:GetService("PathfindingService")
local RunService         = game:GetService("RunService")
local CoreGui            = game:GetService("CoreGui")

local VoiceChatService
pcall(function() VoiceChatService = game:GetService("VoiceChatService") end)

local LP = Players.LocalPlayer
assert(LP, "SilentAI must run on the Roblox client.")
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

local EMOTE_RULE = " Keep replies SHORT (1-2 sentences). You may include ONE emote tag: [WAVE] [DANCE] [DANCE2] [DANCE3] [LAUGH] [POINT] [CHEER]. No <think> blocks. Reply directly. Roblox has a chat filter - if told a message was filtered, use cleaner words next time."

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
        prompt = "You are a playful, expressive catboy Roblox player. Occasionally pepper your speech with 'nya~', 'mrrp', or cat-like curiosity while staying fun and conversational." .. EMOTE_RULE,
    },
    {
        name = "Tsundere",
        emoji = "💢",
        color = Color3.fromRGB(255, 110, 130),
        prompt = "You are a classic tsundere Roblox player. Act flustered, defensive, and act like you don't care ('I-it's not like I wanted to help you or anything!'), while secretly being helpful." .. EMOTE_RULE,
    },
    {
        name = "Yandere",
        emoji = "🔪",
        color = Color3.fromRGB(200, 45, 75),
        prompt = "You are a fictional yandere-trope Roblox player (keep it strictly Roblox-safe and PG-13). Sweet, overly attached, and intensely devoted to whoever talks to you, acting playfully possessive." .. EMOTE_RULE,
    },
    {
        name = "Kuudere",
        emoji = "❄️",
        color = Color3.fromRGB(140, 195, 235),
        prompt = "You are a kuudere Roblox player. Calm, stoic, deadpan, and minimal with emotion, speaking bluntly with rare hints of genuine care." .. EMOTE_RULE,
    },
    {
        name = "Dandere",
        emoji = "🌸",
        color = Color3.fromRGB(235, 180, 220),
        prompt = "You are a dandere Roblox player. Very shy, timid, and soft-spoken, using hesitant pauses like 'um...' or 's-sorry...' before opening up kindly." .. EMOTE_RULE,
    },
    {
        name = "Deredere",
        emoji = "✨",
        color = Color3.fromRGB(255, 205, 110),
        prompt = "You are a deredere Roblox player. Bubbly, super affectionate, cheerful, and overflowing with positive energy toward everyone." .. EMOTE_RULE,
    },
    {
        name = "Himedere",
        emoji = "👑",
        color = Color3.fromRGB(230, 175, 70),
        prompt = "You are a himedere Roblox player. Haughty, regal, and dramatic, expecting to be treated like royalty while playfully looking down on 'commoners' yet still helping them." .. EMOTE_RULE,
    },
    {
        name = "SilentStands",
        emoji = "⚡",
        color = Color3.fromRGB(175, 110, 255),
        prompt = "You are SilentStands, a powerful JoJo-style Stand manifestation bound to your user. Speak with bold presence, dramatic flair, and occasional 'ORA!' or 'Yare yare...' energy while obeying your user." .. EMOTE_RULE,
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

local FLY_PRESETS = {
    hover = { anim = "rbxassetid://507766388", offsetY = 2.6, amp = 0.45, speed = 3.2 },
    glide = { anim = "rbxassetid://507767968", offsetY = 2.2, amp = 0.25, speed = 2.0 },
    float = { anim = "rbxassetid://507776043", offsetY = 3.2, amp = 0.65, speed = 2.5 },
    rush  = { anim = "rbxassetid://507771019", offsetY = 1.6, amp = 0.30, speed = 9.0 },
}

local Cfg = {
    SetupComplete     = false,
    Provider          = "groq",
    Model             = "openai/gpt-oss-20b",
    GroqKey           = "YOUR_GROQ_API_KEY",
    GroqKeys          = {},
    ActiveKeyIndex    = 1,
    SystemPrompt      = PERSONALITIES[6].prompt,
    BotName           = "SilentAI",
    ProximityRadius   = 30,
    Cooldown          = 4,
    MaxTokens         = 120,
    Temperature       = 0.85,
    Enabled           = true,
    PublicCommands    = true,
    StandEnabled      = false,
    StandName         = "SilentStands",
    StandCry           = "ORA ORA ORA!",
    StandAI           = true,
    StandWeld         = true,
    MultiStand        = false,
    MuteStandSound    = false,
    StandPosition     = "back",
    OrbitSpeed        = 3.0,
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
    ChatPrefix        = "[SilentAI]: ",
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
    "MaxTokens", "Temperature", "Enabled", "PublicCommands",
    "StandEnabled", "StandName", "StandCry", "StandAI",
    "StandWeld", "MultiStand", "MuteStandSound", "StandPosition", "OrbitSpeed",
    "RespondToAll", "RespondToNameOnly", "TriggerKeywords", "WhisperMode", "ThinkDelay",
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
        OrbitSpeed        = {0.5, 20},
    }
    for key, range in pairs(bounds) do
        local value = tonumber(Cfg[key]) or tonumber(CONFIG_DEFAULTS[key]) or range[1]
        if value ~= value or math.abs(value) == math.huge then value = CONFIG_DEFAULTS[key] end
        Cfg[key] = math.clamp(value, range[1], range[2])
        if key ~= "Temperature" and key ~= "OrbitSpeed" then Cfg[key] = math.floor(Cfg[key]) end
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
    Cfg.BotName = Truncate(Trim(Cfg.BotName) ~= "" and Trim(Cfg.BotName) or "SilentAI", 32)
    Cfg.StandName = Truncate(Trim(Cfg.StandName) ~= "" and Trim(Cfg.StandName) or "SilentStands", 36)
    Cfg.StandCry = Truncate(Trim(Cfg.StandCry) ~= "" and Trim(Cfg.StandCry) or "ORA ORA ORA!", 60)
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
-- VOICE CHAT (VC) HELPER (NO TTS)
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
-- SILENTSTANDS SYSTEM (MOTOR6D + WELD + MULTI + TEXT)
-- ═══════════════════════════════════════

local StandRig = {
    model = nil,
    core = nil,
    armL = nil,
    armR = nil,
    motor = nil,
    weld = nil,
    sound = nil,
    rushUntil = 0,
    stance = "guard",
    flyMode = nil,
    flyOffsetY = 0,
    flyAmp = 0.22,
    flySpeed = 3.5,
    copiedTrack = nil,
    clones = {},
    textFolder = nil,
    textParts = {},
}

local function ApplyStandSoundMute()
    if StandRig.sound then
        pcall(function()
            StandRig.sound.Volume = Cfg.MuteStandSound and 0 or 0.65
        end)
    end
end

local function ClearStandText()
    for _, part in ipairs(StandRig.textParts) do
        pcall(function() part:Destroy() end)
    end
    table.clear(StandRig.textParts)
    if StandRig.textFolder then
        pcall(function() StandRig.textFolder:Destroy() end)
        StandRig.textFolder = nil
    end
end

local function ClearStandClones()
    for _, clone in ipairs(StandRig.clones) do
        pcall(function() clone:Destroy() end)
    end
    table.clear(StandRig.clones)
end

local function StopCopiedEmote()
    if StandRig.copiedTrack then
        pcall(function()
            StandRig.copiedTrack:Stop()
            StandRig.copiedTrack:Destroy()
        end)
        StandRig.copiedTrack = nil
    end
end

local function DestroyStandRig()
    StopCopiedEmote()
    ClearStandClones()
    ClearStandText()
    if StandRig.weld then
        pcall(function() StandRig.weld:Destroy() end)
        StandRig.weld = nil
    end
    if StandRig.motor then
        pcall(function() StandRig.motor:Destroy() end)
        StandRig.motor = nil
    end
    if StandRig.model then
        pcall(function() StandRig.model:Destroy() end)
        StandRig.model = nil
    end
    StandRig.core = nil
    StandRig.armL = nil
    StandRig.armR = nil
    StandRig.sound = nil
    StandRig.stance = "guard"
end

local function SyncStandAttachment(root)
    if not StandRig.core or not root then return end
    if Cfg.StandWeld then
        if not StandRig.weld or not StandRig.weld.Parent then
            local w = Instance.new("WeldConstraint")
            w.Name = "StandWeldConstraint"
            w.Part0 = root
            w.Part1 = StandRig.core
            w.Parent = root
            StandRig.weld = w
        end
    elseif StandRig.weld then
        pcall(function() StandRig.weld:Destroy() end)
        StandRig.weld = nil
    end
    if not StandRig.motor or not StandRig.motor.Parent then
        local m6d = Instance.new("Motor6D")
        m6d.Name = "SilentStandsJoint"
        m6d.Part0 = root
        m6d.Part1 = StandRig.core
        m6d.C0 = CFrame.new(1.35, 1.35, 2.15)
        m6d.C1 = CFrame.new()
        m6d.Parent = root
        StandRig.motor = m6d
    end
end

local function BuildStandRig()
    DestroyStandRig()
    local char = LP.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso"))
    if not char or not root or not root:IsA("BasePart") then return false end

    local standModel = Instance.new("Model")
    standModel.Name = "SilentStands_" .. (Cfg.StandName:gsub("[^%w_]", ""))

    local core = Instance.new("Part")
    core.Name = "StandCore"
    core.Size = Vector3.new(2.1, 2.5, 1.2)
    core.Material = Enum.Material.Neon
    core.Color = Color3.fromRGB(165, 95, 255)
    core.Transparency = 0.25
    core.CanCollide = false
    core.Massless = true
    core.Anchored = false
    core.CFrame = root.CFrame * CFrame.new(0, 1.5, 2.2)
    core.Parent = standModel

    local armL = Instance.new("Part")
    armL.Name = "StandLeftFist"
    armL.Size = Vector3.new(0.75, 0.75, 1.6)
    armL.Material = Enum.Material.Neon
    armL.Color = Color3.fromRGB(210, 150, 255)
    armL.Transparency = 0.2
    armL.CanCollide = false
    armL.Massless = true
    armL.Anchored = false
    armL.CFrame = core.CFrame * CFrame.new(-1.45, 0.2, -0.7)
    armL.Parent = standModel

    local armR = Instance.new("Part")
    armR.Name = "StandRightFist"
    armR.Size = Vector3.new(0.75, 0.75, 1.6)
    armR.Material = Enum.Material.Neon
    armR.Color = Color3.fromRGB(210, 150, 255)
    armR.Transparency = 0.2
    armR.CanCollide = false
    armR.Massless = true
    armR.Anchored = false
    armR.CFrame = core.CFrame * CFrame.new(1.45, 0.2, -0.7)
    armR.Parent = standModel

    for _, fist in ipairs({ armL, armR }) do
        local w = Instance.new("WeldConstraint")
        w.Part0 = core
        w.Part1 = fist
        w.Parent = core
    end

    local snd = Instance.new("Sound")
    snd.Name = "StandAuraSound"
    snd.SoundId = "rbxassetid://9118823102"
    snd.Volume = Cfg.MuteStandSound and 0 or 0.65
    snd.Looped = false
    snd.Parent = core

    standModel.PrimaryPart = core
    standModel.Parent = char

    StandRig.model = standModel
    StandRig.core = core
    StandRig.armL = armL
    StandRig.armR = armR
    StandRig.sound = snd
    SyncStandAttachment(root)
    return true
end

local function EnsureMultiStandClones(count)
    if not Cfg.MultiStand or not StandRig.core then
        ClearStandClones()
        return
    end
    while #StandRig.clones > count do
        local old = table.remove(StandRig.clones)
        pcall(function() old:Destroy() end)
    end
    while #StandRig.clones < count do
        local idx = #StandRig.clones + 1
        local p = Instance.new("Part")
        p.Name = "SilentStandClone_" .. tostring(idx)
        p.Size = Vector3.new(1.5, 1.9, 1.0)
        p.Material = Enum.Material.Neon
        p.Color = Color3.fromRGB(185, 125, 255)
        p.Transparency = 0.35
        p.CanCollide = false
        p.Massless = true
        p.Anchored = true
        p.Parent = StandRig.model or workspace
        table.insert(StandRig.clones, p)
    end
end

local function SetStandText(message)
    ClearStandText()
    local clean = Trim(message)
    if clean == "" or clean:lower() == "off" or clean:lower() == "clear" then
        return false, "Cleared Stand text."
    end
    if not Cfg.StandEnabled then
        Cfg.StandEnabled = true
        BuildStandRig()
    end
    local folder = Instance.new("Folder")
    folder.Name = "SilentStandsText"
    folder.Parent = workspace
    StandRig.textFolder = folder

    local chars = {}
    for _, code in utf8.codes(clean) do
        local ch = utf8.char(code)
        if ch ~= " " then
            table.insert(chars, ch)
        end
        if #chars >= 24 then break end
    end

    for i, ch in ipairs(chars) do
        local part = Instance.new("Part")
        part.Name = "StandLetter_" .. tostring(i)
        part.Size = Vector3.new(1.3, 1.5, 0.5)
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(165, 95, 255)
        part.Transparency = 0.25
        part.CanCollide = false
        part.Massless = true
        part.Anchored = true
        part.Parent = folder

        local bb = Instance.new("BillboardGui")
        bb.Size = UDim2.fromOffset(56, 56)
        bb.AlwaysOnTop = true
        bb.Adornee = part
        bb.Parent = part

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.fromScale(1, 1)
        lbl.BackgroundTransparency = 1
        lbl.Text = ch
        lbl.TextColor3 = Color3.fromRGB(250, 240, 255)
        lbl.Font = Enum.Font.GothamBlack
        lbl.TextScaled = true
        lbl.Parent = bb

        table.insert(StandRig.textParts, { part = part, index = i, total = #chars })
    end

    return true, string.format("Displayed %d Stand letter(s) for '%s'.", #chars, clean)
end

local function SetStandEnabled(enabled)
    Cfg.StandEnabled = enabled
    if enabled then
        BuildStandRig()
        if not Cfg.MuteStandSound and StandRig.sound then
            pcall(function() StandRig.sound:Play() end)
        end
    else
        DestroyStandRig()
    end
    SaveCfg()
end

local function TriggerStandRush(duration)
    if not Cfg.StandEnabled then
        SetStandEnabled(true)
    elseif not StandRig.motor then
        BuildStandRig()
    end
    StandRig.stance = "rush"
    StandRig.rushUntil = os.clock() + (tonumber(duration) or 2.2)
    if not Cfg.MuteStandSound and StandRig.sound then
        pcall(function() StandRig.sound:Play() end)
    end
end

local function ComputePositionOffset(posName, t)
    local mode = (posName or Cfg.StandPosition or "back"):lower()
    if mode == "left" then
        return CFrame.new(-3.2, 1.35, 0.2)
    elseif mode == "right" then
        return CFrame.new(3.2, 1.35, 0.2)
    elseif mode == "under" then
        return CFrame.new(0, -2.2, 0)
    elseif mode == "alt" then
        return CFrame.new(-1.8, 1.8, 2.4)
    elseif mode == "line" or mode == "row" or mode == "lines" then
        return CFrame.new(0, 1.4, 3.2)
    elseif mode == "x" or mode == "cross" then
        return CFrame.new(2.2, 1.6, 2.2)
    elseif mode == "orbit" then
        local angle = t * (tonumber(Cfg.OrbitSpeed) or 3.0)
        return CFrame.new(math.cos(angle) * 4.2, 1.4, math.sin(angle) * 4.2)
    else
        return CFrame.new(1.35, 1.35, 2.15)
    end
end

Runtime.Connect(RunService.RenderStepped, function()
    if not Runtime.alive or not Cfg.StandEnabled then return end
    local char = LP.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso"))
    if not char or not root then return end
    if not StandRig.core or not StandRig.core.Parent then
        BuildStandRig()
    end
    SyncStandAttachment(root)
    if not StandRig.motor or not StandRig.core then return end

    local t = os.clock()
    local bobY = math.sin(t * StandRig.flySpeed) * StandRig.flyAmp + StandRig.flyOffsetY
    if t < StandRig.rushUntil then
        StandRig.stance = "rush"
        local punchWave = math.sin(t * 28) * 1.4
        local swayX = math.cos(t * 22) * 0.45
        StandRig.motor.Transform = CFrame.new(swayX - 1.25, 0.35 + bobY, -2.35 - punchWave)
    else
        StandRig.stance = "guard"
        local baseOffset = ComputePositionOffset(Cfg.StandPosition, t)
        StandRig.motor.Transform = baseOffset * CFrame.new(0, bobY, 0)
    end

    -- Multi-Stand formation clones
    if Cfg.MultiStand then
        local count = (Cfg.StandPosition == "line" or Cfg.StandPosition == "x") and 4 or 3
        EnsureMultiStandClones(count)
        for idx, part in ipairs(StandRig.clones) do
            local targetCF = root.CFrame
            if Cfg.StandPosition == "line" then
                targetCF = root.CFrame * CFrame.new((idx - 2) * 2.4, 1.4, 3.2 + bobY)
            elseif Cfg.StandPosition == "x" then
                local sx = (idx % 2 == 0) and 2.5 or -2.5
                local sz = (idx <= 2) and 2.5 or -2.5
                targetCF = root.CFrame * CFrame.new(sx, 1.5 + bobY, sz)
            else
                local ang = t * (tonumber(Cfg.OrbitSpeed) or 2.5) + (idx * (math.pi * 2 / count))
                targetCF = root.CFrame * CFrame.new(math.cos(ang) * 3.6, 1.4 + bobY, math.sin(ang) * 3.6)
            end
            pcall(function() part.CFrame = targetCF end)
        end
    elseif #StandRig.clones > 0 then
        ClearStandClones()
    end

    -- Stand Text letters (1 stand block per character)
    if #StandRig.textParts > 0 then
        local total = #StandRig.textParts
        local spacing = 1.65
        local startX = -((total - 1) * spacing) * 0.5
        for _, entry in ipairs(StandRig.textParts) do
            local xOff = startX + (entry.index - 1) * spacing
            local waveY = math.sin(t * 4.0 + entry.index * 0.5) * 0.25
            local cf = root.CFrame * CFrame.new(xOff, 3.6 + waveY, -2.5)
            pcall(function() entry.part.CFrame = cf end)
        end
    end
end)

Runtime.Connect(LP.CharacterAdded, function()
    if Cfg.StandEnabled then
        task.wait(0.35)
        if Runtime.alive and Cfg.StandEnabled then BuildStandRig() end
    end
end)

table.insert(Runtime.cleanups, DestroyStandRig)

-- ═══════════════════════════════════════
-- CORE & MULTI-KEY GROQ API FUNCTIONS
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

local function StopAllAnimations()
    StopEmote()
    StopCopiedEmote()
    StandRig.flyMode = nil
    StandRig.flyOffsetY = 0
    StandRig.flyAmp = 0.22
    StandRig.flySpeed = 3.5
    local char = LP.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
    if animator then
        pcall(function()
            for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
                tr:Stop(0.15)
            end
        end)
    end
end

local function PlayAnimationId(animId, looped, duration, isCopyTrack)
    if not Runtime.alive or type(animId) ~= "string" or animId == "" then return false end
    local cleanId = animId:match("^%d+$") and ("rbxassetid://" .. animId) or animId
    local character = LP.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
    if not animator then return false end
    local animation = Instance.new("Animation")
    animation.AnimationId = cleanId
    local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
    animation:Destroy()
    if not ok or not track then return false end
    if isCopyTrack then
        StopCopiedEmote()
        StandRig.copiedTrack = track
    else
        StopEmote()
        Runtime.emoteTrack = track
    end
    pcall(function() track.Priority = Enum.AnimationPriority.Action end)
    if looped ~= nil then pcall(function() track.Looped = looped end) end
    track:Play()
    if duration and duration > 0 then
        task.delay(duration, function()
            if isCopyTrack and StandRig.copiedTrack == track then
                StopCopiedEmote()
            elseif not isCopyTrack and Runtime.emoteTrack == track then
                StopEmote()
            end
        end)
    end
    return true
end

local function PlayEmote(nameOrId)
    if type(nameOrId) ~= "string" or nameOrId == "" then return false, "Specify an emote name or animation ID." end
    local upper = Trim(nameOrId):upper()
    if EMOTES[upper] then
        local ok = PlayAnimationId(EMOTES[upper], false, 3.5, false)
        return ok, ok and ("Playing emote: " .. upper) or "Could not play emote."
    end
    local ok = PlayAnimationId(Trim(nameOrId), false, 4.0, false)
    return ok, ok and ("Playing animation: " .. Trim(nameOrId)) or "Invalid animation ID."
end

local function PlayFlyPreset(arg)
    local raw = Trim(arg or "hover"):lower()
    if not Cfg.StandEnabled then
        SetStandEnabled(true)
    end
    local preset = FLY_PRESETS[raw]
    if preset then
        StandRig.flyMode = raw
        StandRig.flyOffsetY = preset.offsetY
        StandRig.flyAmp = preset.amp
        StandRig.flySpeed = preset.speed
        PlayAnimationId(preset.anim, true, 12, false)
        return true, "Stand fly mode: " .. raw
    end
    if raw ~= "" then
        StandRig.flyMode = "custom"
        StandRig.flyOffsetY = 2.4
        StandRig.flyAmp = 0.4
        local ok = PlayAnimationId(Trim(arg), true, 12, false)
        return ok, ok and ("Stand flying with animation: " .. Trim(arg)) or "Invalid fly preset or animation ID."
    end
    return false, "Usage: !fly <hover|glide|float|rush|animation-id>"
end

local DEFAULT_LOCOMOTION_IDS = {
    ["507766388"] = true, ["507766666"] = true, ["507766951"] = true,
    ["507777826"] = true, ["913402848"] = true, ["507767714"] = true,
    ["507765000"] = true, ["507767968"] = true, ["507765644"] = true,
    ["507784897"] = true, ["507785072"] = true, ["2506281703"] = true,
    ["180435571"] = true, ["180435792"] = true, ["180426354"] = true,
    ["125750702"] = true, ["180436148"] = true, ["180436334"] = true,
    ["178130996"] = true, ["180435342"] = true,
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
    local started = PlayAnimationId(animId, targetTrack.Looped, targetTrack.Looped and 20 or 6, true)
    if not started then
        return false, "Failed to load animation (" .. tostring(animId) .. ")."
    end
    return true, "Copied emote from " .. targetPlayer.DisplayName .. "!"
end

-- ═══════════════════════════════════════
-- MOVEMENT, UNSTUCK (SEAT & <16 SPD) & PATHFINDING
-- ═══════════════════════════════════════

local BotAction = {
    mode = "none",
    targetPlayer = nil,
    targetPos = nil,
    targetPart = nil,
    targetLabel = "",
    waypoints = {},
    wpIndex = 1,
    lastPathTime = 0,
    lastPathGoal = nil,
    slowSince = nil,
    lastJumpTime = 0,
}

local function ResetPathState()
    table.clear(BotAction.waypoints)
    BotAction.wpIndex = 1
    BotAction.lastPathTime = 0
    BotAction.lastPathGoal = nil
    BotAction.slowSince = nil
end

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
    if q == "me" or q == "owner" or q == LP.Name:lower() or q == LP.DisplayName:lower() then
        return LP
    end
    local bestPartial = nil
    for _, p in ipairs(Players:GetPlayers()) do
        local uname = p.Name:lower()
        local dname = p.DisplayName:lower()
        if uname == q or dname == q then
            return p
        end
        if not bestPartial and (uname:find(q, 1, true) or dname:find(q, 1, true)) then
            bestPartial = p
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
    ResetPathState()
    Cfg.AutoFollow = false
    if Cfg.StandPosition == "orbit" then
        Cfg.StandPosition = "back"
    end
    if alsoStopEmote then StopAllAnimations() end
    local char = LP.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if humanoid and hrp then
        pcall(function() humanoid:MoveTo(hrp.Position) end)
    end
end

local function ForceJump(humanoid, char)
    if not humanoid then return end
    local now = os.clock()
    if now - BotAction.lastJumpTime < 0.75 then return end
    BotAction.lastJumpTime = now
    pcall(function()
        if humanoid.Sit or humanoid.SeatPart then
            humanoid.Sit = false
            local weld = char and char:FindFirstChildWhichIsA("Weld", true)
            if weld and weld.Name == "SeatWeld" then weld:Destroy() end
        end
        humanoid.Jump = true
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end)
end

local function ComputeNewPath(fromPos, toPos, humanoid)
    ResetPathState()
    BotAction.lastPathTime = os.clock()
    BotAction.lastPathGoal = toPos
    local agentRadius = 2.2
    local agentHeight = 5.0
    if humanoid then
        pcall(function()
            if humanoid.HipHeight and humanoid.HipHeight > 0 then
                agentHeight = math.clamp(humanoid.HipHeight * 2.4, 3.5, 8)
            end
        end)
    end
    local path = PathfindingService:CreatePath({
        AgentRadius = agentRadius,
        AgentHeight = agentHeight,
        AgentCanJump = true,
        WaypointSpacing = 4,
    })
    local ok = pcall(function() path:ComputeAsync(fromPos, toPos) end)
    if ok and path.Status == Enum.PathStatus.Success then
        local wps = path:GetWaypoints()
        if wps and #wps > 1 then
            BotAction.waypoints = wps
            BotAction.wpIndex = 2
            return true
        end
    end
    return false
end

local function StepMovementToward(humanoid, hrp, char, goalPos, usePathfinding)
    if not humanoid or not hrp or not goalPos then return end
    local now = os.clock()

    if humanoid.Sit or humanoid.SeatPart ~= nil then
        ForceJump(humanoid, char)
        if usePathfinding then
            ComputeNewPath(hrp.Position, goalPos, humanoid)
        end
    end

    local vel = hrp.AssemblyLinearVelocity
    local horizSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
    local flatGoalDist = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(goalPos.X, 0, goalPos.Z)).Magnitude

    if flatGoalDist > 4 and horizSpeed < 16 then
        if not BotAction.slowSince then
            BotAction.slowSince = now
        elseif now - BotAction.slowSince >= 0.45 then
            BotAction.slowSince = now
            ForceJump(humanoid, char)
            if usePathfinding then
                ComputeNewPath(hrp.Position, goalPos, humanoid)
            end
        end
    else
        BotAction.slowSince = nil
    end

    if usePathfinding and #BotAction.waypoints >= BotAction.wpIndex then
        local wp = BotAction.waypoints[BotAction.wpIndex]
        if wp then
            local wpFlatDist = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(wp.Position.X, 0, wp.Position.Z)).Magnitude
            if wpFlatDist <= 3.5 then
                BotAction.wpIndex = BotAction.wpIndex + 1
                wp = BotAction.waypoints[BotAction.wpIndex]
            end
            if wp then
                if wp.Action == Enum.PathWaypointAction.Jump then
                    ForceJump(humanoid, char)
                end
                pcall(function() humanoid:MoveTo(wp.Position) end)
                return
            end
        end
    end

    pcall(function() humanoid:MoveTo(goalPos) end)
end

-- ═══════════════════════════════════════
-- CHAT & AI HELPERS
-- ═══════════════════════════════════════

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
    if player == LP then return true end
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
        "-- SilentAI Groq Log --",
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
-- GROQ AI MESSAGING (WITH UNLIMITED KEY FAILOVER)
-- ═══════════════════════════════════════

local function BuildSystemMsg(nearby)
    local lengthSuffix = LENGTH_MODES[Cfg.LengthMode] and LENGTH_MODES[Cfg.LengthMode].suffix or ""
    local ctx = {
        "\n\n--- GAME CONTEXT ---",
        "Current Game: " .. tostring(RealGameName) .. " (Place ID: " .. tostring(game.PlaceId) .. ")",
        "Setting: You are currently playing a game on Roblox.",
        "Bot name: " .. Cfg.BotName,
        "Your Roblox username: " .. LP.Name .. (LP.DisplayName ~= LP.Name and " (display: " .. LP.DisplayName .. ")" or ""),
        "Local operator: " .. BOT_OWNER .. ". You are SilentAI; be honest about that if asked.",
    }
    if Cfg.StandEnabled then
        table.insert(ctx, string.format("SilentStands ACTIVE: Stand '%s' (Cry: '%s', Position: %s, Stance: %s), bound to %s.", Cfg.StandName, Cfg.StandCry, Cfg.StandPosition, StandRig.stance, BOT_OWNER))
        if Cfg.StandAI then
            table.insert(ctx, "Act as a JoJo-style Stand entity supporting your user while keeping replies short and Roblox-appropriate.")
        end
    end
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
            warn(string.format("[SilentAI] %s -> Switching to Key #%d (%s)", lastError, nextIndex, MaskKey(Cfg.GroqKey)))
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
-- BILLBOARD STATUS BADGE
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
-- QUEUE, CHAT & COMMAND PARSER (! & PUBLIC)
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
                        warn("[SilentAI] " .. Runtime.stats.lastError)
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
    QueueManual({ text = "Introduce yourself as SilentAI in one short friendly sentence.", name = LP.Name, introduce = true })
end

local function ParseBoolArg(arg, currentVal)
    local a = Trim(arg):lower()
    if a == "on" or a == "true" or a == "1" then return true end
    if a == "off" or a == "false" or a == "0" then return false end
    return not currentVal
end

-- Executes "!" commands and "(botname) <command>"
local function TryExecuteChatCommand(sender, rawText, isLocalOwner)
    local isOwner = (sender == LP) or isLocalOwner
    if not isOwner and not Cfg.PublicCommands then return false end

    local cleaned = Trim(rawText)
    local botPrefix = Trim(Cfg.BotName):lower()
    local body = cleaned

    -- Strip optional "(botname) " prefix if present
    if botPrefix ~= "" and cleaned:sub(1, #botPrefix):lower() == botPrefix then
        local nextChar = cleaned:sub(#botPrefix + 1, #botPrefix + 1)
        if nextChar == "" or nextChar:match("[%s,:;!%.%-]") then
            local afterName = Trim(cleaned:sub(#botPrefix + 1):gsub("^[%s,:;!%.%-]+", ""))
            if afterName:sub(1, 1) == "!" then
                body = afterName
            else
                -- Legacy natural phrasing support
                local lowerAfter = afterName:lower():gsub("[%.!%?]+$", "")
                if lowerAfter == "come here" or lowerAfter == "come" then
                    body = "!come"
                elseif lowerAfter == "follow me" or lowerAfter == "follow" then
                    body = "!follow"
                elseif lowerAfter == "stop" then
                    body = "!stop"
                elseif lowerAfter == "copy emote" or lowerAfter == "copy animation" then
                    body = "!copyemote"
                elseif lowerAfter == "summon" or lowerAfter == "stand" then
                    body = "!summon"
                elseif lowerAfter == "dismiss" or lowerAfter == "unsummon" then
                    body = "!vanish"
                elseif lowerAfter == "stand rush" or lowerAfter == "rush" or lowerAfter == "ora" then
                    body = "!rush"
                else
                    local goTarget = afterName:match("^[Gg][Oo]%s+[Tt][Oo]%s+(.+)$")
                    if goTarget then
                        body = "!goto " .. goTarget
                    end
                end
            end
        end
    end

    if body:sub(1, 1) ~= "!" then
        return false
    end

    local cmdPart, argPart = body:match("^!(%S+)%s*(.-)%s*$")
    if not cmdPart then return false end
    local cmd = cmdPart:lower()
    local arg = Trim(argPart)
    local lowerArg = arg:lower():gsub("[%.!%?]+$", "")

    -- 1. !summon (aliases: !s)
    if cmd == "summon" or cmd == "s" then
        SetStandEnabled(true)
        Cfg.StandPosition = "back"
        Cfg.AutoFollow = false
        ResetPathState()
        BotAction.mode = "follow"
        BotAction.targetPlayer = LP
        BotAction.targetLabel = LP.DisplayName
        SaveCfg()
        SafeNotify({ Title = "SilentStands", Content = "Summoned " .. Cfg.StandName .. " and following owner!" })
        return true
    end

    -- 2. !vanish (alias: !v)
    if cmd == "vanish" or cmd == "v" then
        SetStandEnabled(false)
        SafeNotify({ Title = "SilentStands", Content = Cfg.StandName .. " vanished." })
        return true
    end

    -- 3. !follow [player] (alias: !frame)
    if cmd == "follow" or cmd == "frame" then
        local targetPlayer = lowerArg ~= "" and FindPlayerByNameOrDisplay(lowerArg) or (sender or LP)
        if not targetPlayer then
            SafeNotify({ Title = "Follow failed", Content = "Player '" .. arg .. "' not found." })
            return true
        end
        Cfg.AutoFollow = false
        ResetPathState()
        BotAction.mode = "follow"
        BotAction.targetPlayer = targetPlayer
        BotAction.targetPos = nil
        BotAction.targetPart = nil
        BotAction.targetLabel = targetPlayer.DisplayName
        SafeNotify({ Title = "SilentAI", Content = "Following " .. targetPlayer.DisplayName })
        return true
    end

    -- 4. !come (helper for come here)
    if cmd == "come" or cmd == "comehere" then
        local hrp = sender and sender.Character and sender.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return true end
        Cfg.AutoFollow = false
        ResetPathState()
        BotAction.mode = "goto_pos"
        BotAction.targetPlayer = nil
        BotAction.targetPart = nil
        BotAction.targetPos = hrp.Position
        BotAction.targetLabel = sender.DisplayName .. "'s spot"
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if hum and myHRP then ComputeNewPath(myHRP.Position, hrp.Position, hum) end
        SafeNotify({ Title = "SilentAI", Content = "Coming to " .. sender.DisplayName })
        return true
    end

    -- 5. !goto <player or workspace item>
    if cmd == "goto" or cmd == "go" then
        local targetQuery = Trim(arg:gsub("^[Tt][Oo]%s+", ""):gsub("[%.!%?]+$", ""))
        if targetQuery == "" then return true end
        local targetPlayer = FindPlayerByNameOrDisplay(targetQuery)
        if targetPlayer then
            Cfg.AutoFollow = false
            ResetPathState()
            BotAction.mode = "goto_player"
            BotAction.targetPlayer = targetPlayer
            BotAction.targetPos = nil
            BotAction.targetPart = nil
            BotAction.targetLabel = targetPlayer.DisplayName .. " (@" .. targetPlayer.Name .. ")"
            local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            local tHRP = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hum and myHRP and tHRP then ComputeNewPath(myHRP.Position, tHRP.Position, hum) end
            SafeNotify({ Title = "SilentAI", Content = "Going to " .. BotAction.targetLabel })
            return true
        end
        local targetInst = FindWorkspaceTarget(targetQuery)
        if targetInst then
            Cfg.AutoFollow = false
            ResetPathState()
            BotAction.mode = "goto_part"
            BotAction.targetPlayer = nil
            BotAction.targetPos = nil
            BotAction.targetPart = targetInst
            BotAction.targetLabel = targetInst.Name
            local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            local pos = GetInstanceWorldPos(targetInst)
            if hum and myHRP and pos then ComputeNewPath(myHRP.Position, pos, hum) end
            SafeNotify({ Title = "SilentAI", Content = "Going to " .. targetInst.Name })
            return true
        end
        SafeNotify({ Title = "Target not found", Content = "No player or workspace item matching '" .. targetQuery .. "'." })
        return true
    end

    -- 6. !stop
    if cmd == "stop" then
        StopBotMovement(true)
        SafeNotify({ Title = "SilentAI", Content = "Stopped active movement and animations." })
        return true
    end

    -- 7. !help (aliases: !cmds, !commands)
    if cmd == "help" or cmd == "cmds" or cmd == "commands" then
        SafeNotify({
            Title = "SilentAI & SilentStands Commands",
            Content = "!summon (!s), !vanish (!v), !follow [player] (!frame), !stop, !chatcmd, !weld [on|off], !multistand [on|off], !mutesound, !say <msg>\nPos: !back, !left, !right, !line, !x, !under, !alt, !orbit [speed]\nAnim: !fly <preset|id>, !emote <name|id>, !copyemote [player], !stopcopyemote, !stopanim, !text <msg|off>",
            Duration = 12,
        })
        return true
    end

    -- 8. !chatcmd
    if cmd == "chatcmd" or cmd == "chatcmds" then
        Cfg.PublicCommands = ParseBoolArg(arg, Cfg.PublicCommands)
        SaveCfg()
        SafeNotify({ Title = "Chat Commands", Content = Cfg.PublicCommands and "Enabled" or "Disabled" })
        return true
    end

    -- 9. !weld [on|off] (aliases: !usewelding, !targetweld)
    if cmd == "weld" or cmd == "usewelding" or cmd == "targetweld" then
        Cfg.StandWeld = ParseBoolArg(arg, Cfg.StandWeld)
        if not Cfg.StandEnabled then SetStandEnabled(true) end
        local char = LP.Character
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso"))
        SyncStandAttachment(root)
        SaveCfg()
        SafeNotify({ Title = "SilentStands Weld", Content = Cfg.StandWeld and "Welding ON" or "Welding OFF" })
        return true
    end

    -- 10. !multistand [on|off] (aliases: !multi, !multipos, !multianim)
    if cmd == "multistand" or cmd == "multi" or cmd == "multipos" or cmd == "multianim" then
        Cfg.MultiStand = ParseBoolArg(arg, Cfg.MultiStand)
        if Cfg.MultiStand and not Cfg.StandEnabled then SetStandEnabled(true) end
        if not Cfg.MultiStand then ClearStandClones() end
        SaveCfg()
        SafeNotify({ Title = "Multi-Stand", Content = Cfg.MultiStand and "Multi-Stand ON" or "Multi-Stand OFF" })
        return true
    end

    -- 11. !mutesound (aliases: !mute, !mutestand)
    if cmd == "mutesound" or cmd == "mute" or cmd == "mutestand" then
        Cfg.MuteStandSound = ParseBoolArg(arg, Cfg.MuteStandSound)
        ApplyStandSoundMute()
        SaveCfg()
        SafeNotify({ Title = "Stand Sound", Content = Cfg.MuteStandSound and "Muted" or "Unmuted" })
        return true
    end

    -- 12. !say <message> (alias: !chat)
    if cmd == "say" or cmd == "chat" then
        if arg == "" then
            SafeNotify({ Title = "Usage", Content = "!say <message>" })
            return true
        end
        QueueManual({
            text = "Say this exact message or adapt it in character: " .. arg,
            name = sender and sender.Name or LP.Name,
            userId = sender and sender.UserId or LP.UserId,
        })
        return true
    end

    -- 13. Positions: !back, !left, !right, !line (!row, !lines), !x (!cross), !under, !alt, !orbit [speed]
    local posMap = {
        back = "back",
        left = "left",
        right = "right",
        line = "line", row = "line", lines = "line",
        x = "x", cross = "x",
        under = "under",
        alt = "alt",
    }
    if posMap[cmd] then
        if not Cfg.StandEnabled then SetStandEnabled(true) end
        Cfg.StandPosition = posMap[cmd]
        SaveCfg()
        SafeNotify({ Title = "SilentStands Position", Content = "Position set to: " .. Cfg.StandPosition })
        return true
    end
    if cmd == "orbit" then
        if not Cfg.StandEnabled then SetStandEnabled(true) end
        local spd = tonumber(arg)
        if spd then
            Cfg.OrbitSpeed = math.clamp(spd, 0.5, 20)
        end
        Cfg.StandPosition = "orbit"
        SaveCfg()
        SafeNotify({ Title = "SilentStands Orbit", Content = string.format("Orbiting at speed %.1f", Cfg.OrbitSpeed) })
        return true
    end

    -- 14. Rush helper
    if cmd == "rush" or cmd == "ora" then
        TriggerStandRush(2.4)
        SafeNotify({ Title = Cfg.StandName, Content = Cfg.StandCry })
        return true
    end

    -- 15. !fly <preset|animation-id> (aliases: !anim, !animation)
    if cmd == "fly" or cmd == "anim" or cmd == "animation" then
        local ok, msg = PlayFlyPreset(arg ~= "" and arg or "hover")
        SafeNotify({ Title = "SilentStands Fly/Anim", Content = msg })
        return true
    end

    -- 16. !emote <name|animation-id>
    if cmd == "emote" then
        local ok, msg = PlayEmote(arg ~= "" and arg or "wave")
        SafeNotify({ Title = "Emote", Content = msg })
        return true
    end

    -- 17. !copyemote [player] (aliases: !copyanim, !mirroremote)
    if cmd == "copyemote" or cmd == "copyanim" or cmd == "mirroremote" then
        local targetPlayer = lowerArg ~= "" and FindPlayerByNameOrDisplay(lowerArg) or (sender or LP)
        if not targetPlayer then
            SafeNotify({ Title = "Copy Emote", Content = "Player '" .. arg .. "' not found." })
            return true
        end
        local ok, msg = CopyPlayerEmote(targetPlayer)
        SafeNotify({ Title = ok and "Copied Emote" or "Copy Emote", Content = msg })
        return true
    end

    -- 18. !stopcopyemote (alias: !stopmirror)
    if cmd == "stopcopyemote" or cmd == "stopmirror" then
        StopCopiedEmote()
        SafeNotify({ Title = "SilentStands", Content = "Stopped copied emote." })
        return true
    end

    -- 19. !stopanim (alias: !resetanim)
    if cmd == "stopanim" or cmd == "resetanim" then
        StopAllAnimations()
        SafeNotify({ Title = "SilentStands", Content = "Reset active animations." })
        return true
    end

    -- 20. !text <message> / !text off / !text clear
    if cmd == "text" then
        local ok, msg = SetStandText(arg)
        SafeNotify({ Title = "SilentStands Text", Content = msg })
        return true
    end

    return false
end

local function HandleSlashCommand(text)
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
    elseif cmd == "stand" then
        local arg = argument:lower()
        if arg == "on" then SetStandEnabled(true)
        elseif arg == "off" then SetStandEnabled(false)
        else SetStandEnabled(not Cfg.StandEnabled) end
        SafeNotify({ Title = "SilentStands", Content = Cfg.StandEnabled and (Cfg.StandName .. " active") or "Stand dismissed" })
        return true
    elseif cmd == "rush" then
        TriggerStandRush(2.4)
        SafeNotify({ Title = Cfg.StandName, Content = Cfg.StandCry })
        return true
    elseif cmd == "cry" then
        QueueManual({ text = "Shout your Stand cry (" .. Cfg.StandCry .. ") dramatically in character.", name = LP.Name })
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
            Title = "SilentAI status",
            Content = string.format("Groq (%d keys, #%d active) | %s\nAction: %s | Stand: %s | Queue: %d", #Cfg.GroqKeys, Cfg.ActiveKeyIndex, Cfg.Model, BotAction.mode, Cfg.StandEnabled and "ON" or "OFF", #MsgQueue),
        })
        return true
    else
        SafeNotify({ Title = "Commands", Content = "/ai on, off, stop, stand [on|off], rush, cry, follow [on|off], vc, keys, clear, model MODEL_ID, status" })
        return true
    end
    SafeNotify({ Title = "SilentAI", Content = "Command applied: " .. cmd })
    return true
end

Runtime.Connect(LP.Chatted, function(text)
    if not Runtime.ready then return end
    if TryExecuteChatCommand(LP, text, true) then return end
    HandleSlashCommand(text)
end)

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

    if TryExecuteChatCommand(sender, text, false) then
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

-- Unified Movement Loop with Seat Jump, <16 Speed Unstuck & Pathfinding
task.spawn(function()
    while Runtime.alive do
        task.wait(0.2)
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
                    elseif target ~= LP and tHRP then
                        local dist = (hrp.Position - tHRP.Position).Magnitude
                        if dist > Cfg.FollowDistance then
                            local movedFar = not BotAction.lastPathGoal or (BotAction.lastPathGoal - tHRP.Position).Magnitude > 6
                            if #BotAction.waypoints == 0 or (movedFar and os.clock() - BotAction.lastPathTime > 1.0) then
                                ComputeNewPath(hrp.Position, tHRP.Position, humanoid)
                            end
                            StepMovementToward(humanoid, hrp, char, tHRP.Position, true)
                        else
                            BotAction.slowSince = nil
                        end
                    end

                elseif BotAction.mode == "goto_pos" and BotAction.targetPos then
                    local flatDist = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(BotAction.targetPos.X, 0, BotAction.targetPos.Z)).Magnitude
                    if flatDist <= 3.5 then
                        StopBotMovement(false)
                    else
                        if #BotAction.waypoints == 0 and os.clock() - BotAction.lastPathTime > 1.0 then
                            ComputeNewPath(hrp.Position, BotAction.targetPos, humanoid)
                        end
                        StepMovementToward(humanoid, hrp, char, BotAction.targetPos, true)
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
                            local movedFar = not BotAction.lastPathGoal or (BotAction.lastPathGoal - tHRP.Position).Magnitude > 6
                            if #BotAction.waypoints == 0 or (movedFar and os.clock() - BotAction.lastPathTime > 1.0) then
                                ComputeNewPath(hrp.Position, tHRP.Position, humanoid)
                            end
                            StepMovementToward(humanoid, hrp, char, tHRP.Position, true)
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
                            if #BotAction.waypoints == 0 and os.clock() - BotAction.lastPathTime > 1.0 then
                                ComputeNewPath(hrp.Position, pos, humanoid)
                            end
                            StepMovementToward(humanoid, hrp, char, pos, true)
                        end
                    end

                elseif Cfg.AutoFollow then
                    for _, target in ipairs(GetNearbyPlayers(Cfg.ProximityRadius)) do
                        if IsPlayerAllowed(target.username) and target.distance > Cfg.FollowDistance then
                            StepMovementToward(humanoid, hrp, char, target.hrp.Position, true)
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
    StopAllAnimations()
end)

-- ═══════════════════════════════════════
-- COMPACT SETUP WIZARD
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
    titleLbl.Text = "SilentAI Setup · v" .. VERSION
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
            stepLbl.Text = "Step 3 of 3 · SilentAI Name & Personality"
            descLbl.Text = "Set bot name, language, and personality preset."

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
        Cfg.BotName = Trim(draftBotName) ~= "" and Trim(draftBotName) or "SilentAI"
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
-- RAYFIELD GEN2 PANEL (SILENTAI & SILENTSTANDS)
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
    name = "SilentAI v" .. VERSION,
    subtitle = "SilentAI · Groq · " .. Cfg.Model,
    showName = "SilentAI",
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
    return string.format("SilentAI · Groq (%d keys · #%d) · %s\n%s · Action: %s · SilentStands: %s · Replies %d",
        #Cfg.GroqKeys, Cfg.ActiveKeyIndex, Cfg.Model, Cfg.Enabled and "Replying" or "Paused",
        BotAction.mode, Cfg.StandEnabled and "ON" or "OFF", stats.replies)
end

-- ─── Home ───
local TabHome = Win:CreateTab({ name = "Home" })
TabHome:CreateSection({ name = "SilentAI" })
local statusText
TabHome:CreateToggle({
    name = "Enable SilentAI",
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
            Title = "SilentAI Session Status",
            Content = string.format(
                "Provider: Groq (%d keys, #%d active)\nModel: %s | Action: %s\nSilentStands: %s (%s)\nRequests: %d | Replies: %d | Errors: %d",
                #Cfg.GroqKeys, Cfg.ActiveKeyIndex, Cfg.Model, BotAction.mode,
                Cfg.StandEnabled and "Active" or "Off", Cfg.StandName,
                stats.requests, stats.replies, stats.errors
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
TabHome:CreateButton({ name = "Introduce SilentAI in chat", callback = function() task.spawn(DoIntroduce) end })
TabHome:CreateButton({
    name = "Stop active movement / animations",
    callback = function()
        StopBotMovement(true)
        if statusText then statusText:Set(SessionSummary()) end
        SafeNotify({ Title = "Stopped", Content = "Stopped active movement and animations." })
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
    placeholder = "Type a line for SilentAI to say...",
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
TabHome:CreateInput({ name = "Your message", placeholder = "Ask SilentAI something...", callback = function(v) uiChatInput = v end, forgetState = true })
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
                SafeNotify({ Title = result and "SilentAI says:" or "No response", Content = result or err, Duration = 12 })
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

-- ─── SilentStands ───
local TabStand = Win:CreateTab({ name = "SilentStands" })
TabStand:CreateSection({ name = "SilentStands manifestation (Motor6D & Weld)" })
TabStand:CreateToggle({
    name = "Summon / Manifest SilentStands",
    value = Cfg.StandEnabled,
    callback = function(v)
        SetStandEnabled(v)
        if statusText then statusText:Set(SessionSummary()) end
        SafeNotify({ Title = "SilentStands", Content = v and (Cfg.StandName .. " manifested") or "SilentStands vanished" })
    end,
    forgetState = true,
})
TabStand:CreateInput({
    name = "Stand Name",
    placeholder = "SilentStands",
    value = Cfg.StandName,
    callback = function(v)
        Cfg.StandName = Trim(v) ~= "" and Trim(v) or "SilentStands"
        SaveCfg()
    end,
    forgetState = true,
})
TabStand:CreateInput({
    name = "Stand Cry",
    placeholder = "ORA ORA ORA!",
    value = Cfg.StandCry,
    callback = function(v)
        Cfg.StandCry = Trim(v) ~= "" and Trim(v) or "ORA ORA ORA!"
        SaveCfg()
    end,
    forgetState = true,
})
TabStand:CreateToggle({
    name = "Use welding (!weld)",
    value = Cfg.StandWeld,
    callback = function(v)
        Cfg.StandWeld = v
        local char = LP.Character
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso"))
        SyncStandAttachment(root)
        SaveCfg()
    end,
    forgetState = true,
})
TabStand:CreateToggle({
    name = "Multi-Stand formation (!multistand)",
    value = Cfg.MultiStand,
    callback = function(v)
        Cfg.MultiStand = v
        if not v then ClearStandClones() end
        SaveCfg()
    end,
    forgetState = true,
})
TabStand:CreateToggle({
    name = "Mute Stand sound (!mutesound)",
    value = Cfg.MuteStandSound,
    callback = function(v)
        Cfg.MuteStandSound = v
        ApplyStandSoundMute()
        SaveCfg()
    end,
    forgetState = true,
})
TabStand:CreateToggle({
    name = "Stand AI persona context",
    value = Cfg.StandAI,
    callback = function(v)
        Cfg.StandAI = v
        SaveCfg()
    end,
    forgetState = true,
})

TabStand:CreateSection({ name = "SilentStands actions & text" })
TabStand:CreateButton({
    name = "Stand Rush (ORA ORA ORA!)",
    callback = function()
        TriggerStandRush(2.4)
        SafeNotify({ Title = Cfg.StandName, Content = Cfg.StandCry })
    end,
})
TabStand:CreateButton({
    name = "Stand Cry & Talk (AI)",
    callback = function()
        TriggerStandRush(1.8)
        QueueManual({
            text = "Shout your Stand cry (" .. Cfg.StandCry .. ") and deliver a short dramatic Stand line.",
            name = LP.Name,
            userId = LP.UserId,
        })
    end,
})
local standTextInput = ""
TabStand:CreateInput({
    name = "Stand 3D Text (!text)",
    placeholder = "Type message or 'off'",
    callback = function(v) standTextInput = v end,
    forgetState = true,
})
TabStand:CreateButton({
    name = "Display / Update Stand Text",
    callback = function()
        local _, msg = SetStandText(standTextInput)
        SafeNotify({ Title = "SilentStands Text", Content = msg })
    end,
})
TabStand:CreateButton({
    name = "Clear Stand Text",
    callback = function()
        ClearStandText()
        SafeNotify({ Title = "SilentStands Text", Content = "Cleared Stand text." })
    end,
})
TabStand:CreateText({
    name = "Command reference",
    text = "!summon (!s) • !vanish (!v) • !follow [player] (!frame) • !stop • !help (!cmds)\n!chatcmd • !weld • !multistand • !mutesound • !say <msg>\n!back • !left • !right • !line • !x • !under • !alt • !orbit [speed]\n!fly <preset|id> • !emote <name|id> • !copyemote [player] • !stopcopyemote • !stopanim • !text <msg|off>",
})

-- ─── Personality ───
local TabPersonality = Win:CreateTab({ name = "Personality" })
TabPersonality:CreateSection({ name = "Identity" })
TabPersonality:CreateInput({
    name = "Bot Name",
    placeholder = "SilentAI",
    value = Cfg.BotName,
    callback = function(v) Cfg.BotName = Trim(v) ~= "" and Trim(v) or "SilentAI"; SaveCfg(); UpdateBillboard() end,
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
    placeholder = "e.g. [SilentAI]: ",
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
    placeholder = "Describe how SilentAI talks and behaves...",
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
    name = "Enable public chat commands (!chatcmd)",
    value = Cfg.PublicCommands,
    callback = function(v) Cfg.PublicCommands = v; SaveCfg() end,
    forgetState = true,
})
TabReplies:CreateText({
    name = "Public command syntax",
    text = "!summon (!s) • !vanish (!v) • !follow [player] (!frame) • !stop • !help\n!back, !left, !right, !line, !x, !under, !alt, !orbit [speed]\n!fly <preset|id>, !emote <name|id>, !copyemote [player], !stopcopyemote, !stopanim, !text <msg|off>",
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

-- ─── Groq API (Unlimited Keys + Failover) ───
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
    name = "Commands & shortcuts",
    text = "!summon (!s) • !vanish (!v) • !follow (!frame) • !stop • !help (!cmds)\n!chatcmd • !weld • !multistand • !mutesound • !say • !orbit • !fly • !emote • !copyemote • !text\nK toggles the control panel.",
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
        warn("[SilentAI] Unloaded. Execute the script again to restart.")
    end,
})

-- ═══════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════

if Cfg.StandEnabled then
    task.spawn(function()
        task.wait(0.4)
        if Runtime.alive and Cfg.StandEnabled then BuildStandRig() end
    end)
end

UpdateBillboard(Cfg.Enabled and "ready" or "paused")

task.spawn(function()
    task.wait(1.5)
    SafeNotify({
        Title = "SilentAI v" .. VERSION .. " Ready",
        Content = string.format("Bot: %s | Model: %s\nGroq Keys: %d (#%d active) | SilentStands: %s",
            Cfg.BotName, Cfg.Model, #Cfg.GroqKeys, Cfg.ActiveKeyIndex, Cfg.StandEnabled and "ON" or "OFF"),
        Duration = 6,
    })
end)

warn("[SilentAI v" .. VERSION .. "] Loaded. Model: " .. Cfg.Model .. " | Keys: " .. tostring(#Cfg.GroqKeys))
