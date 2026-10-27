--[[
	EventService — global events and player-facing notifications.

	Luck Hour: aligned to the UTC clock (Config.LuckHour) so every server runs it
	at the same moment. State is published as attributes on ReplicatedStorage:
	  LuckHourActive (bool), LuckHourEndsAt (unix), LuckHourNextAt (unix)
	Admins can start one immediately with :StartLuckHour(seconds).

	Notifications:
	  :Notify(player, kind, payload)   kind = "Toast" | "Popup" | "Purchase" | "Offline" | "QuestReady"
	  :Announce(text, color?, tier?)   server-wide banner (not chat)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local Signal = require(Modules.Signal)
local Net = require(Modules.Net)

local EventService = {}
EventService.LuckHourChanged = Signal.new() -- (active: boolean)

local notifyRemote: RemoteEvent
local announceRemote: RemoteEvent

local manualEndsAt = 0
local luckHourActive = false

local function computeLuckHour(now: number): (boolean, number, number)
	local cfg = Config.LuckHour
	local phase = (now - cfg.Offset) % cfg.Interval
	local cycleStart = now - phase
	local scheduledActive = phase < cfg.Duration
	local endsAt = cycleStart + cfg.Duration
	local nextAt = cycleStart + cfg.Interval

	if manualEndsAt > now then
		if scheduledActive then
			endsAt = math.max(endsAt, manualEndsAt)
		else
			endsAt = manualEndsAt
		end
		return true, endsAt, nextAt
	end
	return scheduledActive, endsAt, nextAt
end

function EventService:IsLuckHour(): boolean
	return luckHourActive
end

function EventService:StartLuckHour(seconds: number)
	manualEndsAt = math.max(manualEndsAt, os.time()) + seconds
	self:_refreshLuckHour()
end

function EventService:_refreshLuckHour()
	local now = os.time()
	local active, endsAt, nextAt = computeLuckHour(now)
	ReplicatedStorage:SetAttribute("LuckHourActive", active)
	ReplicatedStorage:SetAttribute("LuckHourEndsAt", endsAt)
	ReplicatedStorage:SetAttribute("LuckHourNextAt", nextAt)
	ReplicatedStorage:SetAttribute("LuckHourMultiplier", Config.LuckHour.Multiplier)

	if active ~= luckHourActive then
		luckHourActive = active
		self.LuckHourChanged:Fire(active)
		if active then
			self:Announce(
				`🍀 LUCK HOUR has begun! x{Config.LuckHour.Multiplier} luck for everyone!`,
				Color3.fromRGB(90, 230, 120)
			)
		else
			self:Announce("Luck Hour has ended. See you at the next one!", Color3.fromRGB(170, 180, 200))
		end
	end
end

function EventService:Notify(player: Player, kind: string, payload: { [string]: any })
	if player.Parent then
		notifyRemote:FireClient(player, kind, payload)
	end
end

function EventService:Toast(player: Player, text: string, color: Color3?)
	self:Notify(player, "Toast", { Text = text, Color = color })
end

function EventService:Announce(text: string, color: Color3?, tier: number?)
	announceRemote:FireAllClients({
		Text = text,
		Color = color or Color3.fromRGB(255, 255, 255),
		Tier = tier,
	})
end

function EventService:Init(services)
	self.Services = services
	notifyRemote = Net.Event("Notify")
	announceRemote = Net.Event("Announce")
end

function EventService:Start()
	self:_refreshLuckHour()
	task.spawn(function()
		while true do
			task.wait(1)
			self:_refreshLuckHour()
		end
	end)

	-- Let late joiners know an event is running.
	Players.PlayerAdded:Connect(function(player)
		task.delay(6, function()
			if luckHourActive and player.Parent then
				self:Toast(player, "🍀 A Luck Hour is active right now!", Color3.fromRGB(90, 230, 120))
			end
		end)
	end)
end

return EventService
