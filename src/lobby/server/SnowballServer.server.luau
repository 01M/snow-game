--!strict
-- Снежки в лобби: без урона и без толчка, чтобы нельзя было сбить игрока с площадки очереди.
-- Клиент присылает только направление; начало, скорость, частоту и попадание считает сервер.
-- SnowballFx всем: ("throw", id, начало, скорость, UserId) и ("hit", id, точка, UserId цели или 0).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LobbyFolder = ReplicatedStorage:WaitForChild("Lobby")
local Snowball = require(LobbyFolder:WaitForChild("Snowball")) :: any
local Remotes = LobbyFolder:WaitForChild("Remotes")
local ThrowSnowball = Remotes:WaitForChild("ThrowSnowball") :: RemoteEvent
local SnowballFx = Remotes:WaitForChild("SnowballFx") :: RemoteEvent

type Ball = { id: number, pos: Vector3, vel: Vector3, born: number, params: RaycastParams }

local balls: { Ball } = {}
local lastThrow: { [Player]: number } = {}
local nextId = 0

ThrowSnowball.OnServerEvent:Connect(function(player: Player, direction: unknown)
	if
		typeof(direction) ~= "Vector3"
		or direction ~= direction
		or direction.Magnitude < 0.1
		or direction.Magnitude > 2
	then
		return
	end
	local now = os.clock()
	if (lastThrow[player] and now - lastThrow[player] < Snowball.Cooldown) or #balls >= Snowball.MaxActive then
		return
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not head or not head:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return
	end
	lastThrow[player] = now

	local unit = direction.Unit
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	nextId += 1
	local ball: Ball =
		{ id = nextId, pos = head.Position + unit * 2, vel = unit * Snowball.Speed, born = now, params = params }
	table.insert(balls, ball)
	SnowballFx:FireAllClients("throw", ball.id, ball.pos, ball.vel, player.UserId)
end)

RunService.Heartbeat:Connect(function(dt: number)
	local now = os.clock()
	for i = #balls, 1, -1 do
		local ball = balls[i]
		local step = ball.vel * dt
		local hit = workspace:Raycast(ball.pos, step, ball.params)
		if hit then
			local model = hit.Instance:FindFirstAncestorOfClass("Model")
			local target = model and Players:GetPlayerFromCharacter(model)
			SnowballFx:FireAllClients("hit", ball.id, hit.Position, target and target.UserId or 0)
			table.remove(balls, i)
		elseif now - ball.born > Snowball.Life then
			table.remove(balls, i)
		else
			ball.pos += step
			ball.vel += Snowball.Gravity * dt
		end
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastThrow[player] = nil
end)
