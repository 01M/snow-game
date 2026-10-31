-- ChatTagClient: метка [VIP] перед именем в чате у владельцев пасса VIP (атрибут Pass_VIP ставит ShopServer).
-- TextChatService.OnIncomingMessage — один на клиента, другие скрипты его не ставят. Скрипт одинаковый в Lobby и House Map.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t

local VIP_COLOR = "#FFD24A"

TextChatService.OnIncomingMessage = function(message: TextChatMessage)
	local source = message.TextSource
	local sender = source and Players:GetPlayerByUserId(source.UserId)
	if sender and sender:GetAttribute("Pass_VIP") == true then
		local props = Instance.new("TextChatMessageProperties")
		props.PrefixText =
			string.format('<font color="%s">%s</font> %s', VIP_COLOR, L("Chat.VipTag"), message.PrefixText)
		return props
	end
	return nil
end
