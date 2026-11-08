--!strict
-- ShovelSwing: связь анимации копания лопатой (ToolClient) с комьями, звуком и толчком камеры (ShovelChunksClient).
-- Только клиент и только своя лопата. ToolClient проигрывает цикл «вонзить → поддеть → бросок → покой»
-- и сообщает два момента: Impact (лезвие вошло в снег — звук лезвия и толчок камеры) и Throw (бросок — комья
-- и мягкий шорох). Анимация только визуальная: сервер срезает снег непрерывно, 15 раз в секунду (MeltTickRate).
local ShovelSwing = {}

local impactEvent = Instance.new("BindableEvent")
local throwEvent = Instance.new("BindableEvent")

ShovelSwing.Impact = impactEvent.Event
ShovelSwing.Throw = throwEvent.Event

function ShovelSwing.fireImpact()
	impactEvent:Fire()
end

function ShovelSwing.fireThrow()
	throwEvent:Fire()
end

return ShovelSwing
