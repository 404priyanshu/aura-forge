--[[
	QuestsWindow — one row per Config.Quests entry with a progress bar,
	reward preview and claim button. Repeatable quests show their level.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local Formulas = require(Modules.Formulas)
local Util = require(Modules.Util)
local Net = require(Modules.Net)
local UIKit = require(script.Parent.UIKit)

local Theme = UIKit.Theme
local Create = UIKit.Create

local QuestsWindow = {}
QuestsWindow.__index = QuestsWindow

local function formatProgress(quest: Config.QuestInfo, value: number): string
	if quest.Type == "Playtime" or quest.Type == "AfkTime" then
		return Util.Duration(value)
	end
	return Util.Abbreviate(value)
end

function QuestsWindow.new(root: Instance, ctx)
	local self = setmetatable({}, QuestsWindow)
	self.Ctx = ctx
	self.Rows = {}

	local window = UIKit.Window(root, {
		Name = "QuestsWindow",
		Title = "Quests",
		Icon = "📜",
		Size = UDim2.fromOffset(620, 500),
		Accent = Theme.Success,
	})
	self.Window = window

	local list = Create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		Padding = { Top = 2, Bottom = 8, Right = 8 },
		Parent = window.Content,
	})
	UIKit.List(list, { Padding = 8 })

	for index, quest in Config.Quests do
		self.Rows[quest.Id] = self:_buildRow(list, quest, index)
	end

	ctx.Data:Observe("Quests", function()
		self:Render()
	end)

	return self
end

function QuestsWindow:_buildRow(parent: Instance, quest: Config.QuestInfo, order: number)
	local row = Create("Frame", {
		Name = quest.Id,
		Size = UDim2.new(1, 0, 0, 84),
		BackgroundColor3 = Theme.PanelLight,
		LayoutOrder = order,
		Corner = 12,
		Parent = parent,
	})
	local title = Create("TextLabel", {
		Size = UDim2.new(1, -170, 0, 24),
		Position = UDim2.fromOffset(14, 8),
		Text = "",
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	local reward = Create("TextLabel", {
		Size = UDim2.new(1, -170, 0, 18),
		Position = UDim2.fromOffset(14, 32),
		Text = "",
		TextSize = 14,
		FontFace = UIKit.Fonts.Regular,
		TextColor3 = Theme.Warning,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	local bar = UIKit.ProgressBar(row, {
		Size = UDim2.new(1, -170, 0, 18),
		Position = UDim2.fromOffset(14, 56),
		Color = Theme.Success,
	})
	local claim = UIKit.Button({
		Text = "Claim",
		Size = UDim2.fromOffset(136, 52),
		Position = UDim2.new(1, -14, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = Theme.Success,
		TextSize = 20,
		Parent = row,
		OnClick = function()
			Net.Event("ClaimQuest"):FireServer(quest.Id)
		end,
	})
	return { Row = row, Title = title, Reward = reward, Bar = bar, Claim = claim, Quest = quest }
end

function QuestsWindow:Render()
	local states = self.Ctx.Data:Get("Quests") or {}
	for id, row in self.Rows do
		local quest = row.Quest
		local state = states[id] or { Progress = 0, Level = 0, Done = false }
		local goal = Formulas.QuestGoal(quest, state.Level)
		local levelText = if quest.Repeatable and state.Level > 0 then `  <font color="#9aa0b8">Lv.{state.Level + 1}</font>` else ""
		row.Title.Text = Formulas.QuestTitle(quest, state.Level, Util.Duration) .. levelText
		row.Reward.Text = "🎁 " .. Formulas.DescribeReward(Formulas.QuestReward(quest, state.Level), Util.Abbreviate)

		if state.Done then
			row.Bar.Set(1, "Completed")
			row.Claim.Text = "Done"
			row.Claim.BackgroundColor3 = Theme.Disabled
			row.Claim.Active = false
		else
			local ready = state.Progress >= goal
			row.Bar.Set(state.Progress / goal, `{formatProgress(quest, state.Progress)} / {formatProgress(quest, goal)}`)
			row.Claim.Text = if ready then "Claim!" else "In progress"
			row.Claim.TextSize = if ready then 20 else 15
			row.Claim.BackgroundColor3 = if ready then Theme.Success else Theme.Disabled
			row.Claim.Active = ready
		end
	end
end

function QuestsWindow:HasClaimable(): boolean
	local states = self.Ctx.Data:Get("Quests") or {}
	for _, quest in Config.Quests do
		local state = states[quest.Id]
		if state and not state.Done and state.Progress >= Formulas.QuestGoal(quest, state.Level) then
			return true
		end
	end
	return false
end

return QuestsWindow
