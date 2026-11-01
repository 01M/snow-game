--!strict
-- Рэгдолл на горке, сторона клиента: состоянием Humanoid и физикой своего персонажа управляет его владелец.
-- Когда начать и закончить, решает SlideRagdollServer через атрибут персонажа Ragdoll.
local Players = game:GetService("Players")

local TUMBLE = 70 -- сила кувырка, умножается на массу
local STAND_LIFT = 3 -- studs, на сколько приподнимаем при подъёме, чтобы ноги не застряли в полу

local player = Players.LocalPlayer

local function watch(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart

	character:GetAttributeChangedSignal("Ragdoll"):Connect(function()
		if character:GetAttribute("Ragdoll") then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			local spin = Vector3.new(math.random() - 0.5, (math.random() - 0.5) * 0.5, -0.6 - math.random() * 0.4)
			root:ApplyAngularImpulse(spin * TUMBLE * root.AssemblyMass)
		else
			humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
			local position = root.Position + Vector3.new(0, STAND_LIFT, 0)
			local _, yaw = root.CFrame:ToOrientation()
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.CFrame = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

player.CharacterAdded:Connect(watch)
if player.Character then
	watch(player.Character)
end
