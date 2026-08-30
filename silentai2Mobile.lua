local function processIncomingMessage(player, messageText)
    if not botEnabled or player == LocalPlayer then return end
    local lowerMsg = messageText:lower()

    -- Check for prefix or direct mode commands ($mode, mode, or standard chat triggers)
    if lowerMsg:find("tsun") or lowerMsg:find("tsud") then
        currentModeIndex = 2
        ModeBtn.Text = "Mode: Tsundere Mode"
        if lowerMsg:find("%$mode") or lowerMsg:find("mode") then
            sendMessage("Switched to Tsundere Mode! B-Baka! ♡")
            return
        end
    elseif lowerMsg:find("owo") or lowerMsg:find("uwu") then
        currentModeIndex = 1
        ModeBtn.Text = "Mode: OwO Mode"
        if lowerMsg:find("%$mode") or lowerMsg:find("mode") then
            sendMessage("Switched to OwO Mode! UwU ♡")
            return
        end
    elseif lowerMsg:find("yan") or lowerMsg:find("yand") then
        currentModeIndex = 3
        ModeBtn.Text = "Mode: Yandere Mode"
        if lowerMsg:find("%$mode") or lowerMsg:find("mode") then
            sendMessage("Switched to Yandere Mode... ♡")
            return
        end
    end

    -- Process standard AI and action commands
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
