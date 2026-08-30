local TextChatService = game:GetService("TextChatService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

print("Chat Version detected:", TextChatService.ChatVersion)

if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
    TextChatService.MessageReceived:Connect(function(msg)
        print("TextChatService received:", msg.Text, "from:", msg.TextSource and msg.TextSource.UserId)
    end)
else
    for _, p in ipairs(Players:GetPlayers()) do
        p.Chatted:Connect(function(msg)
            print(p.Name, "chatted:", msg)
        end)
    end
end
print("Diagnostic chat hook loaded successfully!")
