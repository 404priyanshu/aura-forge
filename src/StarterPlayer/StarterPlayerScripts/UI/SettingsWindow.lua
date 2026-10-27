--[[
	SettingsWindow — toggles saved in the player's profile (so they survive
	rejoining and work across devices). Changes apply instantly on the client
	and are sent to the server, which validates key + type before saving.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local Util = require(Modules.Util)
local Net = require(Modules.Net)
local UIKit = require(script.Parent.UIKit)

local Theme = UIKit.Theme
local Create = UIKit.Create

local SettingsWindow = {}
SettingsWindow.__index = SettingsWindow

local OPTIONS = {
	{ Key = "Music", Text = "Music", Description = "Background music" },
	{ Key = "Sfx", Text = "Sound Effects", Description = "Clicks, rolls and reveals" },
	{ Key = "ScreenShake", Text = "Screen Shake", Description = "Camera shake on rare pulls" },
	{
		Key = "QuickReveals",
		Text = "Quick Reveals",
		Description = "Skip the full reveal for pulls below " .. Config.Roll.AlwaysFullRevealRarity,
	},
}

function SettingsWindow.new(root: Instance, ctx)
	local self = setmetatable({}, SettingsWindow)
	self.Ctx = ctx
	self.Toggles = {}

	local window = UIKit.Window(root, {
		Name = "SettingsWindow",
		Title = "Settings",
		Icon = "⚙️",
		Size = UDim2.fromOffset(520, 470),
	})
	self.Window = window

	local list = Create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		Padding = { Right = 8, Bottom = 8 },
		Parent = window.Content,
	})
	UIKit.List(list, { Padding = 8 })

	for index, option in OPTIONS do
		self.Toggles[option.Key] = UIKit.Toggle(list, {
			Text = option.Text,
			Description = option.Description,
			Value = true,
			LayoutOrder = index,
			OnChanged = function(value)
				-- Apply locally right away; the server patch confirms it.
				local settings = ctx.Data:Get("Settings")
				if settings then
					settings[option.Key] = value
					ctx.Data.Changed:Fire("Settings", settings)
				end
				Net.Event("UpdateSetting"):FireServer(option.Key, value)
			end,
		})
	end

	self.StatsLabel = Create("TextLabel", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = "",
		TextSize = 15,
		FontFace = UIKit.Fonts.Regular,
		TextColor3 = Theme.SubText,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 100,
		Parent = list,
	})

	ctx.Data:Observe("Settings", function(settings)
		for key, toggle in self.Toggles do
			if settings[key] ~= nil then
				toggle.Set(settings[key])
			end
		end
	end)
	ctx.Data:Observe("Stats", function(stats)
		self.StatsLabel.Text = string.format(
			"Total rolls: %s   ·   Playtime: %s   ·   Clicks: %s\nCoins earned: %s   ·   Permanent luck bonus: +%.2f",
			Util.Commas(stats.TotalRolls),
			Util.Duration(stats.Playtime),
			Util.Commas(stats.Clicks),
			Util.Abbreviate(stats.CoinsEarned),
			stats.Luck
		)
	end)

	return self
end

return SettingsWindow
