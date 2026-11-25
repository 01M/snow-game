--!strict
-- Printed directory signs and live queue information on the original truck boards.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local LocaleModule = shared:WaitForChild("Locale")
local L = require(LocaleModule).t
local Ui = require(shared:WaitForChild("Ui"))

local TAG = "LobbySignFace"
local surfaces: { [Instance]: SurfaceGui } = {}
local icons = {
	["Lobby.World.Shop"] = "Shop",
	["Lobby.World.Upgrades"] = "Upgrade",
	["Lobby.World.Records"] = "Star",
}

local function line(
	parent: Instance,
	name: string,
	color: Color3,
	x: number,
	y: number,
	w: number,
	h: number,
	maxSize: number,
	align: Enum.TextXAlignment
): TextLabel
	return Ui.label({
		Name = name,
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		Text = "",
		TextScaled = true,
		TextColor3 = color,
		TextXAlignment = align,
		Parent = parent,
	}, { Ui.new("UITextSizeConstraint", { MaxTextSize = maxSize }) })
end

local function textLabel(parent: Instance?, name: string): TextLabel?
	local inst = parent and parent:FindFirstChild(name)
	return if inst and inst:IsA("TextLabel") then inst else nil
end

local function bindDirectory(gui: SurfaceGui, anchor: Instance, key: string)
	local billboard = anchor:FindFirstChildWhichIsA("BillboardGui")
	local title = line(gui, "Title", Ui.Color.ink, 0.17, 0.10, 0.74, 0.80, 66, Enum.TextXAlignment.Center)
	local icon = icons[key]
	if icon then
		Ui.icon(icon, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.07, 0.5),
			Size = UDim2.fromOffset(54, 54),
			Parent = gui,
		})
	end
	local function localize()
		title.Text = L(key)
	end
	localize()
	local language = LocaleModule:GetAttributeChangedSignal("ForceLanguage"):Connect(localize)
	if billboard then
		billboard.Enabled = false
	end
	gui.Destroying:Once(function()
		language:Disconnect()
		if billboard and billboard.Parent then
			billboard.Enabled = true
		end
	end)
end

local function bindQueue(gui: SurfaceGui, queue: Instance)
	local board = gui:FindFirstChild("Board")
	local map = textLabel(board, "Main")
	if not board or not map or board:FindFirstChild("QueueStatus") then
		return
	end

	-- Preserve the orange strip, border and original title typography. Use only
	-- the bottom of the dark field for the two secondary queue labels.
	map.Position = UDim2.fromScale(0.05, 0.225)
	map.Size = UDim2.fromScale(0.90, 0.58)
	local status = line(board, "QueueStatus", Ui.Color.textSoft, 0.055, 0.82, 0.70, 0.145, 48, Enum.TextXAlignment.Left)
	local count = line(board, "QueueCount", Ui.Color.text, 0.77, 0.82, 0.175, 0.145, 54, Enum.TextXAlignment.Right)
	status.FontFace = Ui.Font.bold

	local links: { RBXScriptConnection } = {}
	local oldPad: BillboardGui?
	local padWasEnabled = false
	local function disconnect()
		for _, connection in links do
			connection:Disconnect()
		end
		table.clear(links)
		if oldPad and oldPad.Parent then
			oldPad.Enabled = padWasEnabled
		end
		oldPad = nil
	end
	local function bindSources()
		if not gui.Parent then
			return
		end
		disconnect()
		local pad = queue:FindFirstChild("Pad")
		local padGui = pad and pad:FindFirstChild("PadGui")
		local sourceStatus = textLabel(padGui, "Status")
		local sourceCount = textLabel(padGui, "Count")
		if not padGui or not padGui:IsA("BillboardGui") or not sourceStatus or not sourceCount then
			status.Text = ""
			count.Text = ""
			return
		end

		local function refresh()
			status.Text = sourceStatus.Text
			status.TextColor3 = if sourceStatus:GetAttribute("LocaleKey") == "Lobby.Pad.Create"
				then Ui.Color.textSoft
				else Ui.Color.goldLight
			count.Text = sourceCount.Text
		end
		oldPad = padGui
		padWasEnabled = padGui.Enabled
		local function refreshVisibility()
			padGui.Enabled = padWasEnabled and not gui.Enabled
		end
		refresh()
		refreshVisibility()
		table.insert(links, sourceStatus:GetPropertyChangedSignal("Text"):Connect(refresh))
		table.insert(links, sourceStatus:GetAttributeChangedSignal("LocaleKey"):Connect(refresh))
		table.insert(links, sourceCount:GetPropertyChangedSignal("Text"):Connect(refresh))
		table.insert(links, gui:GetPropertyChangedSignal("Enabled"):Connect(refreshVisibility))
	end

	local sources = { Pad = true, PadGui = true, Status = true, Count = true }
	local function changed(inst: Instance)
		if sources[inst.Name] and not inst:IsDescendantOf(gui) then
			task.defer(bindSources)
		end
	end
	local added = queue.DescendantAdded:Connect(changed)
	local removed = queue.DescendantRemoving:Connect(changed)
	gui.Destroying:Once(function()
		added:Disconnect()
		removed:Disconnect()
		disconnect()
	end)
	bindSources()
end

local function mount(inst: Instance)
	if not inst:IsA("MeshPart") or surfaces[inst] then
		return
	end
	local art = inst.Parent
	local anchor = art and art.Parent
	local key = inst:GetAttribute("SignText")
	if not anchor or typeof(key) ~= "string" then
		return
	end
	local canvasWidth = 640
	local canvasHeight = math.round(canvasWidth * inst.Size.Y / inst.Size.X)
	local gui = Ui.new("SurfaceGui", {
		Name = "LobbyPrint",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(canvasWidth, canvasHeight),
		LightInfluence = 0.24,
		MaxDistance = 68,
		Parent = inst,
	}) :: SurfaceGui
	surfaces[inst] = gui
	bindDirectory(gui, anchor, key)
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(mount)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
	local gui = surfaces[inst]
	if gui then
		surfaces[inst] = nil
		gui:Destroy()
	end
end)
for _, face in CollectionService:GetTagged(TAG) do
	mount(face)
end

local queues = workspace:WaitForChild("Blockout"):WaitForChild("QueuePads")
local function mountTruck(inst: Instance)
	if inst.Name ~= "BoardGui" and inst.Name ~= "Board" and inst.Name ~= "Main" then
		return
	end
	local gui = if inst:IsA("SurfaceGui") then inst else inst:FindFirstAncestorWhichIsA("SurfaceGui")
	local sign = gui and gui.Parent
	local queue = sign and sign.Parent
	if gui and gui.Name == "BoardGui" and queue and queue.Parent == queues then
		bindQueue(gui, queue)
	end
end
queues.DescendantAdded:Connect(mountTruck)
for _, inst in queues:GetDescendants() do
	mountTruck(inst)
end
