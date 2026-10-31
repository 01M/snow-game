-- HideCoreGui: скрывает встроенный список игроков (PlayerList) в матче.
-- Справа сверху там деньги и кнопка журнала, а Tab открывает журнал (в нём и так есть все игроки матча).
-- Добавить в друзья можно через меню Roblox (Esc → People). Чат включён (с 2026-10-28): окно чата
-- стоит слева по центру (TextChatService.ChatWindowConfiguration), чтобы не закрывать карточку задачи.
local StarterGui = game:GetService("StarterGui")

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
