--!strict
-- Run from the Server context of an isolated Studio Play. Change the observed zone for this session.
local ZONE_NAME = "Backyard"

local players = game:GetService("Players")
local rs = game:GetService("RunService")
local storage = game:GetService("ServerStorage")
local hs = game:GetService("HttpService")
assert(rs:IsStudio() and rs:IsServer() and workspace:GetAttribute("TestSave") == true, "Use the Studio TestSave server")
assert(#players:GetPlayers() == 1 and workspace:GetAttribute("MatchState") == "playing", "Start a solo match first")
assert(not storage:FindFirstChild("ProgressionPlaytestRead"), "Observer already running")
local p = players:GetPlayers()[1]
local ls = p:WaitForChild("leaderstats")
local bag = ls:WaitForChild("Backpack") :: IntValue
local cash = ls:WaitForChild("Cash") :: IntValue
local yard = workspace:WaitForChild("SnowYard")
local zone = assert(yard:FindFirstChild(ZONE_NAME), "Unknown zone")
local zoneState = zone:WaitForChild("State") :: StringValue
local zoneScore = zone:WaitForChild("Score") :: IntValue
local zoneTotal = zone:WaitForChild("Total") :: IntValue
local front = yard:WaitForChild("Snowmelter"):WaitForChild("SellZone") :: BasePart
local logTag = "[SnowPlaytest:" .. hs:GenerateGUID(false) .. "] "
local function equipped()
	local item = p.Character and p.Character:FindFirstChildOfClass("Tool")
	return item and item:GetAttribute("SnowToolId") or "Hand"
end
local function serverTime()
	return workspace:GetServerTimeNow()
end
local function count(key: string): number
	return (p:GetAttribute(key) or 0) :: number
end
local function round(n: number)
	return math.round(n * 100) / 100
end
local function xyz(v: Vector3)
	return { round(v.X), round(v.Y), round(v.Z) }
end
local function planar(a: Vector3, b: Vector3)
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end
local function position()
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end
local function contains(part: BasePart, pos: Vector3): boolean
	local d = pos - part.Position
	local h = part.Size / 2
	return math.abs(d.X) <= h.X and math.abs(d.Y) <= h.Y and math.abs(d.Z) <= h.Z
end
local function stopAt(pos: Vector3?): string?
	if not pos then
		return nil
	end
	if contains(front, pos) then
		return "front"
	end
	local late = yard:FindFirstChild("LateSnowDrop")
	return if late and late:IsA("BasePart") and contains(late, pos) then "late" else nil
end
local armedAt = serverTime()
type Point = { pos: Vector3?, time: number, studs: number, breaks: number }
type Load = { pos: Vector3, time: number, studs: number, breaks: number, full: boolean }
type Sale = { id: number, station: string, amount: number, cash: number, at: Point, load: Load }
type Empty = { time: number, amount: number, fromCash: number, load: Load? }
local events: { [number]: { [string]: any } } = {}
local seq, first = 0, 1
local origin = assert(position())
local lastPoint: Point = { pos = origin, time = armedAt, studs = 0, breaks = 0 }
local activeSince: number? = nil
local saleCount, cycleCount = 0, 0
local lastLoad: Load? = nil
local pending: Sale? = nil
local emptied: Empty? = nil
local function point()
	local now, pos = serverTime(), position()
	local studs, breaks = lastPoint.studs, lastPoint.breaks
	if pos and lastPoint.pos then
		local step = planar(pos, lastPoint.pos)
		if step > math.max(8, 30 * (now - lastPoint.time)) then
			breaks += 1
		elseif step >= 0.03 then
			studs += step
		end
	elseif pos ~= lastPoint.pos then
		breaks += 1
	end
	lastPoint = { pos = pos, time = now, studs = studs, breaks = breaks }
	return lastPoint
end
local function values(): { [string]: any }
	return {
		snowCut = count("SnowCut"),
		snowSold = count("SnowSold"),
		bag = bag.Value,
		cash = cash.Value,
		score = zoneScore.Value,
		total = zoneTotal.Value,
		state = zoneState.Value,
		tool = equipped(),
		findCash = count("FindCash"),
	}
end
local function add(kind: string, at: number, data: { [string]: any }?)
	seq += 1
	local e: { [string]: any } = data or {}
	e.id = seq
	e.kind = kind
	e.t = round(at - armedAt)
	if activeSince then
		e.activeT = round(at - activeSince)
	end
	events[seq] = e
	-- Studio writes each record to its local log before the server can teleport away.
	print(logTag .. hs:JSONEncode(e))
	if seq - first >= 1800 then
		events[first] = nil
		first += 1
	end
end
local function start(q: Point, reason: string)
	if not activeSince then
		activeSince = q.time
		add("start", q.time, { reason = reason, pos = q.pos and xyz(q.pos), values = values() })
	end
end
local function closeCycle(q: Point, reason: string)
	local s = pending
	pending = nil
	if not s then
		return
	end
	cycleCount += 1
	local clean = q.breaks == s.load.breaks
	add("cycle", q.time, {
		saleId = s.id,
		station = s.station,
		amount = s.amount,
		reason = reason,
		cash = s.cash,
		snowCut = count("SnowCut"),
		departurePos = xyz(s.load.pos),
		returnPos = q.pos and xyz(q.pos),
		packWasFull = s.load.full,
		outboundSeconds = round(s.at.time - s.load.time),
		outboundStuds = clean and round(s.at.studs - s.load.studs) or nil,
		returnSeconds = round(q.time - s.at.time),
		returnStuds = clean and round(q.studs - s.at.studs) or nil,
		cycleSeconds = round(q.time - s.load.time),
		cycleStuds = clean and round(q.studs - s.load.studs) or nil,
		pathDiscontinuity = not clean,
	})
end
local function abortCycle(q: Point, reason: string)
	if pending then
		add("cycleIncomplete", q.time, { saleId = pending.id, station = pending.station, reason = reason })
		pending = nil
	end
end
local function tryReturn(q: Point, resumed: boolean)
	if not pending or not q.pos or stopAt(q.pos) then
		return
	end
	if planar(q.pos, pending.load.pos) <= 8 then
		closeCycle(q, "returnedWithin8Studs")
	elseif resumed then
		closeCycle(q, "resumedClearingElsewhere")
	end
end
local current = values()
current.levels = hs:JSONDecode((p:GetAttribute("ToolUpgrades") or "[]") :: string)
current.capacity = p:GetAttribute("BackpackCapacity")
current.pos = xyz(origin)
current.zone = ZONE_NAME
add("baseline", armedAt, current)
local prevBag, prevCash, prevSold, prevCut = bag.Value, cash.Value, count("SnowSold"), count("SnowCut")
bag.Changed:Connect(function(n)
	local q = point()
	if n > prevBag and q.pos then
		start(q, "collection")
		tryReturn(q, true)
		lastLoad = {
			pos = q.pos,
			time = q.time,
			studs = q.studs,
			breaks = q.breaks,
			full = n == p:GetAttribute("BackpackCapacity"),
		}
	elseif n == 0 and prevBag > 0 then
		emptied = { time = q.time, amount = prevBag, fromCash = prevCash, load = lastLoad }
		lastLoad = nil
	end
	prevBag = n
end)
cash.Changed:Connect(function(n)
	add("cash", serverTime(), { before = prevCash, after = n, delta = n - prevCash })
	prevCash = n
end)
p:GetAttributeChangedSignal("SnowCut"):Connect(function()
	local n = count("SnowCut")
	if n > prevCut then
		local q = point()
		start(q, "snowCut")
		tryReturn(q, true)
	end
	prevCut = n
end)
p:GetAttributeChangedSignal("SnowSold"):Connect(function()
	local total = count("SnowSold")
	local amount = total - prevSold
	prevSold = total
	if amount <= 0 then
		return
	end
	local q = point()
	local station = stopAt(q.pos)
	local trace = emptied
	local fromBag = trace and trace.amount == amount and q.time - trace.time < 0.5 and bag.Value == 0
	if not station or not trace or not fromBag then
		add("snowSoldOther", q.time, { amount = amount, total = total, station = station, pos = q.pos and xyz(q.pos) })
		return
	end
	emptied = nil
	abortCycle(q, "newSaleBeforeReturn")
	saleCount += 1
	local earned = cash.Value - trace.fromCash
	add("sale", q.time, {
		station = station,
		amount = amount,
		soldTotal = total,
		cash = earned,
		wallet = cash.Value,
		pos = q.pos and xyz(q.pos),
		snowCut = count("SnowCut"),
	})
	if trace.load then
		pending = { id = seq, station = station, amount = amount, cash = earned, at = q, load = trace.load }
	else
		add("cycleIncomplete", q.time, { saleId = seq, station = station, reason = "noLoadPoint" })
	end
end)
local thresholds = { 90, 95, 99 }
local reached = {}
local function recordProgress()
	local score, total = zoneScore.Value, zoneTotal.Value
	for _, pct in thresholds do
		if score * 100 >= total * pct and not reached[pct] then
			reached[pct] = true
			add("zoneProgress", serverTime(), { zone = ZONE_NAME, percent = pct, score = score, total = total })
		end
	end
end
recordProgress()
zoneScore.Changed:Connect(recordProgress)
zoneState.Changed:Connect(function(state)
	add("zone", serverTime(), { zone = ZONE_NAME, state = state, score = zoneScore.Value, total = zoneTotal.Value })
end)
zone:GetAttributeChangedSignal("WaitingForPiles"):Connect(function()
	add("zonePiles", serverTime(), { zone = ZONE_NAME, waiting = zone:GetAttribute("WaitingForPiles") == true })
end)
workspace:GetAttributeChangedSignal("MatchState"):Connect(function()
	local q = point()
	local state = workspace:GetAttribute("MatchState")
	add("match", q.time, { state = state, values = values(), endBag = emptied and emptied.amount })
	if state ~= "playing" then
		abortCycle(q, "matchEnded")
		task.defer(function()
			add("settlement", serverTime(), { values = values(), matchCashEarned = count("MatchCashEarned") })
		end)
	end
end)
local elapsed, nextSample = 0, armedAt
rs.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < 0.15 or workspace:GetAttribute("MatchState") ~= "playing" then
		return
	end
	elapsed = 0
	local q = point()
	if not activeSince and q.pos and planar(q.pos, origin) >= 2 then
		start(q, "movement")
	end
	tryReturn(q, false)
	if activeSince and q.time >= nextSample then
		nextSample = q.time + 5
		local s = values()
		s.pos = q.pos and xyz(q.pos)
		s.studs = round(q.studs)
		add("sample", q.time, s)
	end
end)
local reader = Instance.new("BindableFunction")
reader.Name = "ProgressionPlaytestRead"
reader.OnInvoke = function(after, limit)
	if after == "probe" then
		add("probe", serverTime(), {})
		return events[seq]
	end
	local from = math.max(first, (tonumber(after) or 0) + 1)
	local last = math.min(seq, from + math.clamp(tonumber(limit) or 100, 1, 250) - 1)
	local page = {}
	for i = from, last do
		table.insert(page, events[i])
	end
	return {
		events = page,
		total = seq,
		first = first,
		active = activeSince ~= nil,
		sales = saleCount,
		cycles = cycleCount,
		pending = pending and pending.id,
		values = values(),
	}
end
reader.Parent = storage
return logTag .. reader:GetFullName()
