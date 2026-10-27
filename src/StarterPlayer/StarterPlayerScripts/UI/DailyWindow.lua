--[[
	DailyWindow — 7-day login streak + per-session playtime rewards.

	Claimability is predicted on the client for display (same UTC-day rule as
	DailyRewardService); the server re-validates every claim.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local Formulas = require(Modules.Formulas)
local Util = require(Modules.Util)
local Net = require(Modules.Net)
local UIKit = require(script.Parent.UIKit)

local Theme = UIKit.Theme
local Create = UIKit.Create

local DAY = 86400

local DailyWindow = {}
DailyWindow.__index = DailyWindow

-- Mirrors DailyRewardService:GetDailyState.
local function dailyState(daily, now: number): (boolean, number, number)
	local today = now // DAY
	local cycle = #Config.Daily.Rewards
	if daily.LastClaim > 0 and daily.LastClaim // DAY == today then
		return false, daily.Streak, ((daily.Streak - 1) % cycle) + 1
	end
	local continues = daily.LastClaim > 0 and today - daily.LastClaim // DAY == 1
	local streak = if continues then daily.Streak + 1 else 1
	return true, streak, ((streak - 1) % cycle) + 1
end

function DailyWindow.new(root: Instance, ctx)
	local self = setmetatable({}, DailyWindow)
	self.Ctx = ctx
	self.DayCards = {}
	self.PlayCards = {}

	local window = UIKit.Window(root, {
		Name = "DailyWindow",
		Title = "Rewards",
		Icon = "🎁",
		Size = UDim2.fromOffset(720, 470),
		Accent = Theme.Warning,
	})
	self.Window = window
	local content = window.Content

	-- Daily streak
	self.StreakLabel = Create("TextLabel", {
		Size = UDim2.new(1, -200, 0, 26),
		Text = "Daily Login",
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	})
	local days = Create("Frame", {
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 120),
		BackgroundTransparency = 1,
		Parent = content,
	})
	UIKit.List(days, { Direction = Enum.FillDirection.Horizontal, Padding = 7, HAlign = Enum.HorizontalAlignment.Center })

	for day, reward in Config.Daily.Rewards do
		local card = Create("Frame", {
			Name = "Day" .. day,
			Size = UDim2.fromOffset(86, 120),
			BackgroundColor3 = Theme.PanelLight,
			LayoutOrder = day,
			Corner = 12,
			Parent = days,
		})
		local stroke = UIKit.Stroke(card, Theme.Stroke, 1.5, 0.3)
		Create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, 6),
			Text = "Day " .. day,
			TextSize = 16,
			Parent = card,
		})
		Create("TextLabel", {
			Size = UDim2.new(1, -8, 0, 84),
			Position = UDim2.fromOffset(4, 30),
			Text = string.gsub(Formulas.DescribeReward(reward, Util.Abbreviate), " · ", "\n"),
			TextSize = 13,
			FontFace = UIKit.Fonts.Regular,
			TextColor3 = Theme.SubText,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = card,
		})
		self.DayCards[day] = { Card = card, Stroke = stroke }
	end

	self.ClaimDaily = UIKit.Button({
		Text = "Claim",
		Size = UDim2.fromOffset(180, 44),
		Position = UDim2.new(1, 0, 0, -6),
		AnchorPoint = Vector2.new(1, 0),
		Color = Theme.Warning,
		Parent = content,
		OnClick = function()
			Net.Event("ClaimDaily"):FireServer()
		end,
	})

	-- Playtime rewards
	Create("TextLabel", {
		Position = UDim2.fromOffset(0, 168),
		Size = UDim2.new(1, 0, 0, 26),
		Text = "Playtime Rewards  <font color=\"#9aa0b8\">(this session)</font>",
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	})
	local play = Create("Frame", {
		Position = UDim2.fromOffset(0, 200),
		Size = UDim2.new(1, 0, 0, 160),
		BackgroundTransparency = 1,
		Parent = content,
	})
	UIKit.List(play, { Direction = Enum.FillDirection.Horizontal, Padding = 8, HAlign = Enum.HorizontalAlignment.Center })

	for index, reward in Config.Playtime.Rewards do
		local card = Create("Frame", {
			Size = UDim2.fromOffset(102, 160),
			BackgroundColor3 = Theme.PanelLight,
			LayoutOrder = index,
			Corner = 12,
			Parent = play,
		})
		Create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, 6),
			Text = `{index * Config.Playtime.Interval // 60} min`,
			TextSize = 16,
			Parent = card,
		})
		Create("TextLabel", {
			Size = UDim2.new(1, -8, 0, 62),
			Position = UDim2.fromOffset(4, 30),
			Text = string.gsub(Formulas.DescribeReward(reward, Util.Abbreviate), " · ", "\n"),
			TextSize = 13,
			FontFace = UIKit.Fonts.Regular,
			TextColor3 = Theme.SubText,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = card,
		})
		local button = UIKit.Button({
			Text = "",
			Size = UDim2.new(1, -12, 0, 44),
			Position = UDim2.new(0, 6, 1, -6),
			AnchorPoint = Vector2.new(0, 1),
			Color = Theme.Disabled,
			TextSize = 16,
			Parent = card,
			OnClick = function()
				Net.Event("ClaimPlaytime"):FireServer(index)
			end,
		})
		self.PlayCards[index] = { Card = card, Button = button }
	end

	ctx.Data:Observe("Daily", function()
		self:Render()
	end)
	ctx.Data:ObserveLive("PlaytimeClaims", function()
		self:Render()
	end)

	task.spawn(function()
		while window.Frame.Parent do
			if window.IsOpen then
				self:Render()
			end
			task.wait(1)
		end
	end)

	return self
end

function DailyWindow:_sessionSeconds(): number
	local startedAt = self.Ctx.Data:GetLive("SessionStartedAt")
	if not startedAt then
		return 0
	end
	return Workspace:GetServerTimeNow() - startedAt
end

function DailyWindow:Render()
	local data = self.Ctx.Data
	local daily = data:Get("Daily")
	if daily then
		local now = Workspace:GetServerTimeNow()
		local canClaim, streak, cycleDay = dailyState(daily, now)
		self.StreakLabel.Text = `Daily Login  <font color="#ffba38">🔥 {daily.Streak} day streak</font>`
		for day, card in self.DayCards do
			local isTarget = day == cycleDay
			local claimed = (not canClaim and day <= cycleDay) or (canClaim and day < cycleDay)
			card.Stroke.Color = if isTarget then Theme.Warning elseif claimed then Theme.Success else Theme.Stroke
			card.Stroke.Thickness = if isTarget then 3 else 1.5
			card.Card.BackgroundColor3 = if claimed then Color3.fromRGB(28, 52, 40) else Theme.PanelLight
		end
		if canClaim then
			self.ClaimDaily.Text = `Claim Day {cycleDay}!`
			self.ClaimDaily.BackgroundColor3 = Theme.Warning
			self.ClaimDaily.Active = true
			if streak == 1 and daily.Streak > 1 then
				self.StreakLabel.Text ..= `  <font color="#f04860">(streak reset)</font>`
			end
		else
			local nextDay = (now // DAY + 1) * DAY
			self.ClaimDaily.Text = `Next in {Util.Clock(nextDay - now)}`
			self.ClaimDaily.BackgroundColor3 = Theme.Disabled
			self.ClaimDaily.Active = false
		end
	end

	local claims = data:GetLive("PlaytimeClaims") or {}
	local elapsed = self:_sessionSeconds()
	for index, card in self.PlayCards do
		local unlockAt = index * Config.Playtime.Interval
		if claims[index] then
			card.Button.Text = "✅"
			card.Button.BackgroundColor3 = Theme.Disabled
		elseif elapsed >= unlockAt then
			card.Button.Text = "Claim!"
			card.Button.BackgroundColor3 = Theme.Success
		else
			card.Button.Text = Util.Clock(unlockAt - elapsed)
			card.Button.BackgroundColor3 = Theme.Disabled
		end
	end
end

function DailyWindow:HasClaimable(): boolean
	local data = self.Ctx.Data
	local daily = data:Get("Daily")
	if daily and (dailyState(daily, Workspace:GetServerTimeNow())) then
		return true
	end
	local claims = data:GetLive("PlaytimeClaims") or {}
	local elapsed = self:_sessionSeconds()
	for index = 1, #Config.Playtime.Rewards do
		if not claims[index] and elapsed >= index * Config.Playtime.Interval then
			return true
		end
	end
	return false
end

return DailyWindow
