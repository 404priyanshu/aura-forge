--[[
	RollController — roll input, auto-roll toggle, token toggle and the queue
	of results waiting to be revealed.

	The client never decides a result. It asks (RollRequest), the server
	answers (RollResult), and results are revealed one at a time. While a
	result is being held on screen, pressing Roll again skips the hold and
	requests the next roll immediately.

	Input: the ROLL button, keyboard R, gamepad X.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local Formulas = require(Modules.Formulas)
local Signal = require(Modules.Signal)
local Util = require(Modules.Util)
local Net = require(Modules.Net)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local RollReveal = require(script.Parent.Parent.UI.RollReveal)

local Theme = UIKit.Theme

local RollController = {}

local queue = {}
local queueSignal = Signal.new()
local awaiting = false
local awaitingSince = 0
local spinning = false
local skipHold = false
local useToken = false
local readyAt = 0
local cooldownTotal = 1

local alwaysFullTier = Formulas.TierIndex(Config.Roll.AlwaysFullRevealRarity) or 1

local function shakeButton(button: GuiObject)
	local origin = button.Position
	task.spawn(function()
		for i = 1, 6 do
			button.Position = origin + UDim2.fromOffset(if i % 2 == 0 then 6 else -6, 0)
			task.wait(0.03)
		end
		button.Position = origin
	end)
end

function RollController:_toast(text: string, color: Color3?)
	self.Controllers.UIController.Notifications:Toast(text, color)
end

function RollController:RequestRoll()
	local data = self.Controllers.DataController
	if not data.Loaded then
		return
	end
	if awaiting then
		return
	end
	if spinning then
		-- Still animating the spin: ignore. (During the hold, spinning is false.)
		return
	end
	local now = os.clock()
	if now < readyAt then
		return
	end

	local currency = data:Get("Currency")
	local cost = data:GetLive("RollCost") or Formulas.RollCost(0)
	if useToken then
		if currency.RerollTokens < 1 then
			useToken = false
			self:_renderInfo()
			self:_toast("You're out of Lucky Tokens.", Theme.Warning)
			return
		end
	elseif currency.Coins < cost then
		shakeButton(self.Hud.RollButton)
		self.Controllers.AudioController:Play("Error")
		self:_toast(`Not enough coins! Rolling costs {Util.Commas(cost)} — click EARN or visit the AFK zone.`, Theme.Danger)
		return
	end

	skipHold = true
	awaiting = true
	awaitingSince = now
	Net.Event("RollRequest"):FireServer(useToken)
	self.Controllers.AudioController:Play("Whoosh", 0.5)

	-- Never get stuck if a response is lost.
	task.delay(5, function()
		if awaiting and awaitingSince == now then
			awaiting = false
		end
	end)
end

function RollController:_onResult(result)
	if not result.Ok then
		awaiting = false
		if result.Reason == "NoCoins" then
			shakeButton(self.Hud.RollButton)
			self:_toast("Not enough coins to roll!", Theme.Danger)
		elseif result.Reason == "NoTokens" then
			useToken = false
			self:_renderInfo()
			self:_toast("You're out of Lucky Tokens.", Theme.Warning)
		end
		return
	end

	if not result.Auto then
		awaiting = false
	end
	cooldownTotal = Formulas.RollCooldown(result.Fast == true, result.Tier)
	readyAt = os.clock() + cooldownTotal - Config.Roll.CooldownTolerance
	if result.UsedToken and (self.Controllers.DataController:Get("Currency").RerollTokens or 0) <= 1 then
		useToken = false
		self:_renderInfo()
	end
	table.insert(queue, result)
	queueSignal:Fire()
end

function RollController:_runQueue()
	while true do
		if #queue == 0 then
			queueSignal:Wait()
		end
		local result = table.remove(queue, 1)
		if result then
			local settings = self.Controllers.DataController:Get("Settings") or {}
			local compact = result.Tier < alwaysFullTier and (settings.QuickReveals or #queue >= 2)
			if compact then
				self.Reveal:ShowCompact(result)
				task.wait(0.15)
			else
				spinning = true
				skipHold = false
				self.Reveal:Play(result, {
					Shake = settings.ScreenShake ~= false,
					OnSpinDone = function()
						spinning = false
					end,
					ShouldSkipHold = function()
						return skipHold or #queue > 0
					end,
				})
				spinning = false
			end
		end
	end
end

function RollController:_renderInfo()
	local data = self.Controllers.DataController
	local hud = self.Hud
	local currency = data:Get("Currency") or {}
	local cost = data:GetLive("RollCost") or Formulas.RollCost(0)
	local tokens = currency.RerollTokens or 0

	if useToken then
		hud.CostLabel.Text = `Cost: {Config.Currencies.RerollTokens.Icon} 1  <font color="#c08cff">(x{Config.Roll.RerollTokenLuck} luck)</font>`
	else
		hud.CostLabel.Text = `Cost: {Config.Currencies.Coins.Icon} {Util.Commas(cost)}`
	end
	hud.TokenToggle.Text = `🎟️ {if useToken then "Using Token" else "Use Token"} ({tokens})`
	hud.TokenToggle.BackgroundColor3 = if useToken then Color3.fromRGB(120, 60, 200) else Theme.PanelLight
	hud.TokenToggle.Visible = tokens > 0 or useToken
end

function RollController:_renderAuto(enabled: boolean)
	local hud = self.Hud
	hud.AutoButton.BackgroundColor3 = if enabled then Theme.Success else Theme.PanelLighter
	hud.AutoButton.Text = if enabled then "🔁\nAUTO ON" else "🔁\nAUTO"
end

function RollController:Init(controllers)
	self.Controllers = controllers
end

function RollController:Start()
	local ui = self.Controllers.UIController
	local data = self.Controllers.DataController
	self.Hud = ui.Hud
	self.Reveal = RollReveal.new(ui.Root, self.Controllers.AudioController)

	Net.Event("RollResult").OnClientEvent:Connect(function(result)
		self:_onResult(result)
	end)

	self.Hud.RollButton.Activated:Connect(function()
		self:RequestRoll()
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.ButtonX then
			self:RequestRoll()
		end
	end)

	self.Hud.AutoButton.Activated:Connect(function()
		local passes = data:GetLive("Passes") or {}
		if not passes.AutoRoll then
			ui:PromptPass("AutoRoll")
			return
		end
		Net.Event("SetAutoRoll"):FireServer(not data:GetLive("AutoRoll"))
	end)

	self.Hud.TokenToggle.Activated:Connect(function()
		UIKit.ButtonClicked:Fire()
		local currency = data:Get("Currency") or {}
		if not useToken and (currency.RerollTokens or 0) < 1 then
			return
		end
		useToken = not useToken
		self:_renderInfo()
	end)

	data:ObserveLive("AutoRoll", function(enabled)
		self:_renderAuto(enabled == true)
	end)
	data:ObserveLive("RollCost", function()
		self:_renderInfo()
	end)
	data:Observe("Currency", function()
		self:_renderInfo()
	end)

	-- Roll button state + cooldown bar.
	local keyboard = UserInputService.KeyboardEnabled
	RunService.Heartbeat:Connect(function()
		local hud = self.Hud
		local remaining = math.max(0, readyAt - os.clock())
		hud.CooldownBar.Size = UDim2.fromScale(if remaining > 0 then 1 - remaining / cooldownTotal else 0, 0.08)
		if data:GetLive("AutoRoll") then
			hud.RollSubLabel.Text = "auto rolling"
		elseif awaiting or spinning then
			hud.RollSubLabel.Text = "rolling..."
		else
			hud.RollSubLabel.Text = if keyboard then "press R" else ""
		end
	end)

	self:_renderInfo()
	task.spawn(function()
		self:_runQueue()
	end)
end

return RollController
