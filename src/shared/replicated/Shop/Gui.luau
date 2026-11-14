-- Shop controller: Roblox prices and payment prompts only; View owns the local composition.
-- Catalog, receipts, grants, server authority and saved data are unchanged.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shop = require(script.Parent)
local View = require(script.Parent:WaitForChild("View"))
local L = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Locale")).t
local Ui = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Ui"))
local player = Players.LocalPlayer
local IS_MATCH = ReplicatedStorage:FindFirstChild("SnowGame") ~= nil
local Gui = {}
local window: Ui.Window? = nil
local view: View.ShopView? = nil
local entries = {}
local prices = {}
local requests = {}
local pending = nil
local delayed = {} -- presentation reminders only; never grants or acknowledges a receipt
local notice = nil
local refresh = function() end
local updateStatus = function() end

local function preview(): string?
	if RunService:IsStudio() and workspace:GetAttribute("TestSave") == true then
		local state = workspace:GetAttribute("DebugShopState")
		if
			state == "unowned"
			or state == "loading"
			or state == "error"
			or state == "pending"
			or state == "unavailable"
			or state == "delayed"
		then
			return state
		end
	end
	return nil
end

local function itemName(entry): string
	return L((if entry.isPass then "Shop.Pass." else "Shop.Product.") .. entry.item.Key .. ".Name")
end

local function notify(key: string, kind: Ui.ToastKind?, icon: string?, args: { [string]: any }?)
	notice = { text = L(key, args), kind = kind or "info", icon = icon or "Shop", expires = os.clock() + 4 }
	updateStatus()
end
local function loadPrice(id: number, infoType: Enum.InfoType, onReady: (number?, string) -> ())
	if prices[id] then
		onReady(prices[id], "ready")
		return
	end
	if requests[id] then
		table.insert(requests[id], onReady)
		return
	end
	requests[id] = { onReady }
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
		local price = if ok and type(info) == "table" then info.PriceInRobux else nil
		local state = "error"
		if ok and type(info) == "table" and info.IsForSale == false then
			state = "unavailable"
		elseif type(price) == "number" and price >= 0 then
			prices[id] = price
			state = "ready"
		end
		local callbacks = requests[id]
		requests[id] = nil
		for _, callback in callbacks do
			callback(prices[id], state)
		end
	end)
end

-- Preserve the world showcase API: its callback receives only a loaded numeric price.
function Gui.loadPassPrice(pass, onReady: (number) -> ())
	loadPrice(pass.Id, Enum.InfoType.GamePass, function(price)
		if price ~= nil then
			onReady(price)
		end
	end)
end

local function requestPrice(entry)
	entry.priceState = "loading"
	refresh()
	loadPrice(
		entry.item.Id,
		if entry.isPass then Enum.InfoType.GamePass else Enum.InfoType.Product,
		function(price, state)
			entry.price = price
			entry.priceState = state
			refresh()
		end
	)
end

local function effectValue(entry): number
	if entry.isPass then
		return if Shop.hasPass(player, entry.item.Key) then 1 else 0
	end
	local item = entry.item
	local value = if item.Cash
		then player:GetAttribute("IapCash")
		elseif item.BoostMinutes then player:GetAttribute("BoostUntil")
		else workspace:GetAttribute("BlizzardUntil")
	return if type(value) == "number" then value else 0
end

local function hasEffect(request): boolean
	local entry = request.entry
	return (not entry.item.BlizzardMinutes or workspace:GetAttribute("BlizzardBy") == player.DisplayName)
		and effectValue(entry) > request.before
end

-- Prompt completion is NOT a receipt. UI confirmation uses only the existing replicated effect.
local function checkDelivery()
	local changed = false
	if pending and pending.phase == "delivery" and hasEffect(pending) then
		local entry = pending.entry
		delayed[entry.item.Id] = nil
		pending = nil
		notify("Shop.AppliedNamed", "reward", "Check", { name = itemName(entry) })
		changed = true
	end
	for id, request in delayed do
		if hasEffect(request) then
			delayed[id] = nil
			notify("Shop.AppliedNamed", "reward", "Check", { name = itemName(request.entry) })
			changed = true
		end
	end
	if changed then
		refresh()
	end
end

local function promptFinished(entry, purchased: boolean)
	if not pending or pending.entry ~= entry or pending.phase ~= "prompt" then
		return
	end
	if not purchased then
		pending = nil
		notify("Shop.Cancelled", "info", "Shop")
		refresh()
		return
	end
	pending.phase = "delivery"
	checkDelivery()
	if pending then
		local request = pending
		task.delay(15, function()
			if pending == request then
				-- Keep the existing 15-second lock, then keep a visible reminder instead of silently
				-- implying that an unconfirmed delivery has ended. Other products remain usable.
				delayed[entry.item.Id] = request
				pending = nil
				notify("Shop.DelayedNamed", "info", "Clock", { name = itemName(entry) })
				refresh()
			end
		end)
	end
	refresh()
end

local function buy(entry)
	local fixture = preview()
	if fixture then
		if fixture == "error" then
			notify("Shop.PriceError", "error", "Robux")
		elseif fixture == "pending" then
			notify("Shop.ProcessingNamed", "info", "Clock", { name = itemName(entry) })
		elseif fixture == "unavailable" then
			notify("Shop.UnavailableHint", "info", "Lock")
		else
			notify("Shop.Preview", "info", "Shop")
		end
		return
	end
	if pending then
		return
	end
	if entry.isPass and Shop.hasPass(player, entry.item.Key) then
		notify("Shop.AlreadyOwned", "info", "Check", { name = itemName(entry) })
		return
	end
	if entry.priceState == "error" then
		requestPrice(entry)
		return
	end
	if entry.priceState ~= "ready" then
		return
	end
	pending = { entry = entry, phase = "prompt", before = effectValue(entry) }
	refresh()
	local ok = pcall(function()
		if entry.isPass then
			MarketplaceService:PromptGamePassPurchase(player, entry.item.Id)
		else
			MarketplaceService:PromptProductPurchase(player, entry.item.Id)
		end
	end)
	if not ok then
		pending = nil
		notify("Shop.PurchaseError", "error", "Close")
		refresh()
	end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who, id, purchased)
	if who == player and pending and pending.entry.isPass and pending.entry.item.Id == id then
		promptFinished(pending.entry, purchased)
	end
end)
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, id, purchased)
	if userId == player.UserId and pending and not pending.entry.isPass and pending.entry.item.Id == id then
		promptFinished(pending.entry, purchased)
	end
end)

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", seconds // 60, seconds % 60)
end

local function build()
	view = View.new(IS_MATCH, buy, function()
		refresh()
	end)
	local shopView = view :: View.ShopView
	window = shopView.window
	entries = shopView.entries

	local function visibleEntry()
		for _, entry in entries do
			if entry.isPass == (shopView.activeTab() == "Passes") then
				return entry
			end
		end
		return entries[1]
	end
	updateStatus = function()
		local fixture = preview()
		local first = visibleEntry()
		if notice and notice.expires <= os.clock() then
			notice = nil
		end
		local text, kind, icon
		local priorityState = pending or (fixture and fixture ~= "unowned")
		if notice and (notice.kind == "error" or not priorityState) then
			text, kind, icon = notice.text, notice.kind, notice.icon
		elseif fixture == "pending" then
			text, kind, icon = L("Shop.ProcessingNamed", { name = itemName(first) }), "info", "Clock"
		elseif fixture == "loading" then
			text, kind, icon = L("Shop.Loading"), "idle", "Clock"
		elseif fixture == "error" then
			text, kind, icon = L("Shop.PriceError"), "error", "Robux"
		elseif fixture == "unavailable" then
			text, kind, icon = L("Shop.UnavailableHint"), "idle", "Lock"
		elseif fixture == "delayed" then
			text, kind, icon = L("Shop.DelayedNamed", { name = itemName(first) }), "info", "Clock"
		elseif pending then
			text = L(
				if pending.phase == "prompt" then "Shop.PromptNamed" else "Shop.ProcessingNamed",
				{ name = itemName(pending.entry) }
			)
			kind, icon = "info", "Clock"
		else
			local _, waiting = next(delayed)
			if waiting then
				text, kind, icon = L("Shop.DelayedNamed", { name = itemName(waiting.entry) }), "info", "Clock"
			else
				local active = {}
				local boost, blizzard = Shop.boostLeft(player), Shop.blizzardLeft()
				if boost > 0 then
					table.insert(active, L("Shop.BoostActive", { time = formatTime(boost) }))
				end
				if blizzard > 0 then
					table.insert(active, L("Shop.BlizzardActive", { time = formatTime(blizzard) }))
				end
				if shopView.activeTab() == "Passes" then
					text, icon =
						L(if shopView.window.layout() == "normal" then "Shop.SecureHint" else "Shop.PassesHint"), "Vip"
				elseif #active > 0 then
					text, icon = table.concat(active, "   ·   "), "Clock"
				elseif not IS_MATCH then
					text, icon = L("Shop.LobbyTimingHint"), "Clock"
				else
					text, icon = L("Shop.TimingHint"), "Clock"
				end
				kind = "idle"
			end
		end
		shopView.setStatus(text, kind, icon)
	end
	refresh = function()
		local fixture = preview()
		shopView.setPreview(fixture ~= nil)
		for _, entry in entries do
			local owned = entry.isPass and not fixture and Shop.hasPass(player, entry.item.Key)
			local state = if owned
				then "owned"
				elseif pending and pending.entry == entry then "pending"
				elseif fixture and fixture ~= "unowned" and fixture ~= "delayed" then fixture
				else entry.priceState
			shopView.render(entry, state, entry.price, pending ~= nil)
		end
		shopView.layout()
		updateStatus()
	end
	for _, entry in entries do
		if entry.isPass then
			player:GetAttributeChangedSignal("Pass_" .. entry.item.Key):Connect(function()
				checkDelivery()
				refresh()
			end)
		end
		requestPrice(entry)
	end
	for _, attr in { "IapCash", "BoostUntil" } do
		player:GetAttributeChangedSignal(attr):Connect(checkDelivery)
	end
	workspace:GetAttributeChangedSignal("BlizzardUntil"):Connect(checkDelivery)
	workspace:GetAttributeChangedSignal("BlizzardBy"):Connect(checkDelivery)
	workspace:GetAttributeChangedSignal("DebugShopState"):Connect(function()
		notice = nil
		refresh()
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 1 then
			elapsed = 0
			if shopView.window.isOpen() then
				updateStatus()
			end
		end
	end)
end

function Gui.open()
	if not window then
		build()
	end
	(window :: Ui.Window).open()
end
function Gui.close()
	if window then
		window.close()
	end
end
function Gui.toggle()
	if not window then
		build()
	end
	(window :: Ui.Window).toggle()
end
return Gui
