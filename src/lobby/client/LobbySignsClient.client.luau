--!strict
-- Printed faces on the Lobby mounts. The queue keeps its replicated state and its fallback signs.
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
	gui: SurfaceGui,
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
		Parent = gui,
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

local function bindQueue(gui: SurfaceGui, sign: Instance, queue: Instance)
	local section = line(gui, "Section", Ui.Color.goldLight, 0.07, 0.065, 0.86, 0.17, 40, Enum.TextXAlignment.Center)
	local map = line(gui, "Map", Ui.Color.text, 0.07, 0.235, 0.86, 0.41, 116, Enum.TextXAlignment.Center)
	local status = line(gui, "Status", Ui.Color.textSoft, 0.09, 0.725, 0.67, 0.20, 50, Enum.TextXAlignment.Left)
	local count = line(gui, "Count", Ui.Color.text, 0.78, 0.72, 0.13, 0.21, 54, Enum.TextXAlignment.Right)
	Ui.new("Frame", {
		Name = "Rule",
		BorderSizePixel = 0,
		BackgroundColor3 = Ui.Color.surfaceLine,
		BackgroundTransparency = 0.50,
		Position = UDim2.fromScale(0.09, 0.69),
		Size = UDim2.fromScale(0.82, 0.007),
		Parent = gui,
	})

	local links: { RBXScriptConnection } = {}
	local oldBoard: SurfaceGui?
	local oldPad: BillboardGui?
	local function disconnect()
		for _, connection in links do
			connection:Disconnect()
		end
		table.clear(links)
		if oldBoard and oldBoard.Parent then
			oldBoard.Enabled = true
		end
		if oldPad and oldPad.Parent then
			oldPad.Enabled = true
		end
	end
	local function bindSources()
		if not gui.Parent then
			return
		end
		disconnect()
		local boardGui = sign:FindFirstChild("BoardGui")
		local layout = boardGui and boardGui:FindFirstChild("Board")
		local pad = queue:FindFirstChild("Pad")
		local padGui = pad and pad:FindFirstChild("PadGui")
		local sourceSection = textLabel(layout and layout:FindFirstChild("Strip"), "Top")
		local sourceMap = textLabel(layout, "Main")
		local sourceStatus = textLabel(padGui, "Status")
		local sourceCount = textLabel(padGui, "Count")
		local function mirror(from: TextLabel?, to: TextLabel, fallback: string)
			if not from then
				to.Text = fallback
				return
			end
			local function refresh()
				to.Text = from.Text
				if to == status then
					status.TextColor3 = if from:GetAttribute("LocaleKey") == "Lobby.Pad.Create"
						then Ui.Color.textSoft
						else Ui.Color.goldLight
				end
			end
			refresh()
			table.insert(links, from:GetPropertyChangedSignal("Text"):Connect(refresh))
			if to == status then
				table.insert(links, from:GetAttributeChangedSignal("LocaleKey"):Connect(refresh))
			end
		end
		mirror(sourceSection, section, L("Lobby.Board.Unknown"))
		mirror(sourceMap, map, L("Lobby.Board.PickMap"))
		mirror(sourceStatus, status, "")
		mirror(sourceCount, count, "")
		if boardGui and boardGui:IsA("SurfaceGui") then
			oldBoard = boardGui
			boardGui.Enabled = false
		end
		if padGui and padGui:IsA("BillboardGui") and sourceStatus and sourceCount then
			oldPad = padGui
			padGui.Enabled = false
		end
	end

	local sources = { Pad = true, PadGui = true, BoardGui = true, Main = true, Top = true, Status = true, Count = true }
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
	if not anchor or (typeof(key) ~= "string" and not anchor.Parent) then
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
		MaxDistance = if typeof(key) == "string" then 68 else 120,
		Parent = inst,
	}) :: SurfaceGui
	surfaces[inst] = gui
	if typeof(key) == "string" then
		bindDirectory(gui, anchor, key)
	else
		bindQueue(gui, anchor, anchor.Parent :: Instance)
	end
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
