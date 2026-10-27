--[[
	CurrencyController — currency displays and the click-to-earn button.

	  * Currency pills count up/down smoothly and pop a "+X" when they grow.
	  * The EARN button sends Click to the server (rate-limited client side
	    to match the server's token bucket) and shows floating "+X" text.
	    The amount shown is predicted from the server-sent ClickReward and
	    CoinMultiplier; the server decides what is actually paid.
	  * The AFK chip appears while the server says you're in the AFK zone.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local Util = require(Modules.Util)
local Net = require(Modules.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local player = Players.LocalPlayer
local random = Random.new()

local CurrencyController = {}

local displayed: { [string]: number } = {}
local counters: { [string]: NumberValue } = {}
local lastClick = 0

local function formatAmount(value: number): string
	if value < 1000000 then
		return Util.Commas(value)
	end
	return Util.Abbreviate(value)
end

function CurrencyController:_floatText(parent: Instance, text: string, color: Color3, position: UDim2, size: number?)
	local label = UIKit.Create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(160, 30),
		Text = text,
		TextSize = size or 24,
		FontFace = UIKit.Fonts.Heavy,
		TextColor3 = color,
		ZIndex = 15,
		Parent = parent,
	})
	UIKit.TextStroke(label, Color3.new(0, 0, 0), 2)
	UIKit.Pop(label, 0.5)
	local drift = random:NextNumber(-30, 30)
	UIKit.Tween(label, 0.9, {
		Position = position + UDim2.fromOffset(drift, -70),
		TextTransparency = 1,
	}, Enum.EasingStyle.Quad)
	task.delay(0.9, function()
		label:Destroy()
	end)
end

function CurrencyController:_bindCurrency(key: string, pill)
	local counter = Instance.new("NumberValue")
	counters[key] = counter
	counter.Changed:Connect(function(value)
		pill.Label.Text = formatAmount(math.floor(value + 0.5))
	end)

	self.Controllers.DataController:Observe("Currency", function(currency)
		local target = currency[key] or 0
		local previous = displayed[key]
		displayed[key] = target
		if previous == nil then
			counter.Value = target
			pill.Label.Text = formatAmount(target)
			return
		end
		if target == previous then
			return
		end
		TweenService:Create(counter, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Value = target }):Play()
		if target > previous then
			UIKit.Pop(pill.Frame, 0.94)
			self:_floatText(
				pill.Frame,
				"+" .. Util.Abbreviate(target - previous),
				Config.Currencies[key].Color,
				UDim2.new(1, 50, 0.5, 0),
				18
			)
		end
	end)
end

function CurrencyController:_onClick()
	local now = os.clock()
	if now - lastClick < 1 / Config.Click.MaxClicksPerSecond then
		return
	end
	lastClick = now
	Net.Event("Click"):FireServer()

	local data = self.Controllers.DataController
	local reward = data:GetLive("ClickReward") or Config.Click.BaseReward
	local multiplier = data:GetLive("CoinMultiplier") or 1
	local predicted = math.floor(reward * multiplier)

	local hud = self.Controllers.UIController.Hud
	self:_floatText(
		hud.ClickButton,
		"+" .. Util.Abbreviate(predicted),
		Config.Currencies.Coins.Color,
		UDim2.new(0.5, random:NextInteger(-30, 30), 0, -10)
	)
	self.Controllers.AudioController:Play("Click", 0.5, random:NextNumber(0.95, 1.15))
end

function CurrencyController:Init(controllers)
	self.Controllers = controllers
end

function CurrencyController:Start()
	local hud = self.Controllers.UIController.Hud
	for key, pill in hud.Currency do
		self:_bindCurrency(key, pill)
	end

	hud.ClickButton.Activated:Connect(function()
		self:_onClick()
	end)

	local function updateAfk()
		local inZone = player:GetAttribute("InAFKZone") == true
		hud.AfkChip.Visible = inZone
		if inZone then
			local multiplier = self.Controllers.DataController:GetLive("CoinMultiplier") or 1
			hud.AfkLabel.Text =
				`💤 AFK ZONE  ·  +{Util.Abbreviate(Config.AFK.CoinsPerSecond * multiplier)} coins/sec`
			UIKit.Pop(hud.AfkChip, 0.8)
		end
	end
	player:GetAttributeChangedSignal("InAFKZone"):Connect(updateAfk)
	updateAfk()
end

return CurrencyController
