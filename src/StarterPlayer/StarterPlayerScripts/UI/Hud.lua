--[[
	Hud — the always-on main interface.

	  top-left     currency pills, then the menu column
	  top-center   Luck Hour countdown chip
	  top-right    luck stat (tap for breakdown) + active boosts
	  bottom       equip slots, roll cost / token toggle, [Click] [ROLL] [Auto]

	Layout is authored in design pixels (Config.UI.DesignWidth/Height); the
	UIController scales the root so it fits phones through 4K monitors. The
	roll cluster sits bottom-center, away from the mobile thumbstick and jump
	button, with large touch targets.

	Behaviour is wired by controllers: RollController (roll/auto/token),
	CurrencyController (currency labels, click button, AFK chip),
	UIController (menu buttons → windows).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local Formulas = require(Modules.Formulas)
local Util = require(Modules.Util)
local UIKit = require(script.Parent.UIKit)

local Theme = UIKit.Theme
local Create = UIKit.Create

local Hud = {}
Hud.__index = Hud

local MENU = {
	{ Name = "Inventory", Icon = "🎒", Label = "Auras" },
	{ Name = "Shop", Icon = "🛒", Label = "Shop" },
	{ Name = "Quests", Icon = "📜", Label = "Quests" },
	{ Name = "Daily", Icon = "🎁", Label = "Rewards" },
	{ Name = "Settings", Icon = "⚙️", Label = "Settings" },
}

local function pill(parent: Instance, key: string, order: number)
	local currency = Config.Currencies[key]
	local frame = Create("Frame", {
		Name = key,
		Size = UDim2.fromOffset(190, 40),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.08,
		LayoutOrder = order,
		Corner = UDim.new(1, 0),
		Stroke = { Color = currency.Color, Thickness = 1.5, Transparency = 0.45 },
		Parent = parent,
	})
	Create("TextLabel", {
		Name = "Icon",
		Size = UDim2.fromOffset(40, 40),
		Text = currency.Icon,
		TextSize = 22,
		Parent = frame,
	})
	local label = Create("TextLabel", {
		Name = "Amount",
		Size = UDim2.new(1, -52, 1, 0),
		Position = UDim2.fromOffset(40, 0),
		Text = "0",
		TextSize = 22,
		FontFace = UIKit.Fonts.Heavy,
		TextColor3 = currency.Color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	UIKit.TextStroke(label, Color3.new(0, 0, 0), 1)
	return { Frame = frame, Label = label }
end

function Hud.new(root: Instance, ctx)
	local self = setmetatable({}, Hud)
	self.Ctx = ctx
	self.Currency = {}
	self.MenuButtons = {}
	self.Badges = {}

	local gui = Create("Frame", {
		Name = "HUD",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = root,
	})
	self.Frame = gui

	---------------------------------------------------------------------
	-- Currencies (top-left)
	---------------------------------------------------------------------
	local currencyColumn = Create("Frame", {
		Name = "Currencies",
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.fromOffset(190, 136),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.List(currencyColumn, { Padding = 8 })
	self.Currency.Coins = pill(currencyColumn, "Coins", 1)
	self.Currency.Gems = pill(currencyColumn, "Gems", 2)
	self.Currency.RerollTokens = pill(currencyColumn, "RerollTokens", 3)

	---------------------------------------------------------------------
	-- Menu column (left)
	---------------------------------------------------------------------
	local menu = Create("Frame", {
		Name = "Menu",
		Position = UDim2.fromOffset(16, 164),
		Size = UDim2.fromOffset(64, 330),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.List(menu, { Padding = 8 })
	for index, entry in MENU do
		local button = UIKit.Button({
			Name = entry.Name,
			Text = "",
			Size = UDim2.fromOffset(60, 58),
			Color = Theme.PanelLight,
			LayoutOrder = index,
			Corner = 14,
			Parent = menu,
		})
		Create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.fromOffset(0, 5),
			Text = entry.Icon,
			TextSize = 24,
			Parent = button,
		})
		Create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.new(0, 0, 1, -21),
			Text = entry.Label,
			TextSize = 12,
			TextColor3 = Theme.SubText,
			Parent = button,
		})
		local badge = Create("Frame", {
			Name = "Badge",
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.new(1, -4, 0, 4),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = Theme.Danger,
			Visible = false,
			Corner = UDim.new(1, 0),
			Stroke = { Color = Color3.new(1, 1, 1), Thickness = 1.5, Transparency = 0 },
			Parent = button,
		})
		self.MenuButtons[entry.Name] = button
		self.Badges[entry.Name] = badge
	end

	---------------------------------------------------------------------
	-- Luck Hour chip (top-center)
	---------------------------------------------------------------------
	local luckHour = Create("Frame", {
		Name = "LuckHour",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(330, 34),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		Corner = UDim.new(1, 0),
		Stroke = { Color = Theme.Stroke, Thickness = 1.5, Transparency = 0.3 },
		Parent = gui,
	})
	self.LuckHourStroke = luckHour:FindFirstChildOfClass("UIStroke")
	self.LuckHourLabel = Create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextSize = 17,
		Parent = luckHour,
	})
	self.LuckHourFrame = luckHour

	---------------------------------------------------------------------
	-- Luck panel (top-right)
	---------------------------------------------------------------------
	local luckPanel = Create("TextButton", {
		Name = "LuckPanel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12),
		Size = UDim2.fromOffset(200, 64),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.08,
		Text = "",
		Corner = 14,
		Stroke = { Color = Color3.fromRGB(90, 230, 120), Thickness = 1.5, Transparency = 0.4 },
		Parent = gui,
	})
	Create("TextLabel", {
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.fromOffset(12, 6),
		Text = "🍀 LUCK",
		TextSize = 15,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = luckPanel,
	})
	self.LuckLabel = Create("TextLabel", {
		Size = UDim2.new(1, -16, 0, 32),
		Position = UDim2.fromOffset(12, 26),
		Text = "x1.00",
		TextSize = 28,
		FontFace = UIKit.Fonts.Heavy,
		TextColor3 = Color3.fromRGB(120, 240, 150),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = luckPanel,
	})
	self.BreakdownFrame = Create("Frame", {
		Name = "Breakdown",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 1, 6),
		Size = UDim2.fromOffset(200, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		Visible = false,
		Corner = 12,
		Stroke = true,
		Padding = 10,
		Parent = luckPanel,
	})
	UIKit.List(self.BreakdownFrame, { Padding = 4 })
	luckPanel.Activated:Connect(function()
		self.BreakdownFrame.Visible = not self.BreakdownFrame.Visible
	end)
	luckPanel.MouseEnter:Connect(function()
		self.BreakdownFrame.Visible = true
	end)
	luckPanel.MouseLeave:Connect(function()
		self.BreakdownFrame.Visible = false
	end)

	self.BoostList = Create("Frame", {
		Name = "Boosts",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 84),
		Size = UDim2.fromOffset(200, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.List(self.BoostList, { Padding = 6, HAlign = Enum.HorizontalAlignment.Right })

	---------------------------------------------------------------------
	-- Bottom cluster
	---------------------------------------------------------------------
	local bottom = Create("Frame", {
		Name = "RollCluster",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.fromOffset(560, 196),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	self.Bottom = bottom

	self.AfkChip = Create("Frame", {
		Name = "AfkChip",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(260, 30),
		BackgroundColor3 = Color3.fromRGB(80, 60, 200),
		Visible = false,
		Corner = UDim.new(1, 0),
		Parent = bottom,
	})
	self.AfkLabel = Create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		Text = "💤 AFK",
		TextSize = 16,
		Parent = self.AfkChip,
	})

	self.EquipRow = Create("Frame", {
		Name = "EquipRow",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 36),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Parent = bottom,
	})
	UIKit.List(self.EquipRow, {
		Direction = Enum.FillDirection.Horizontal,
		Padding = 6,
		HAlign = Enum.HorizontalAlignment.Center,
	})

	local infoRow = Create("Frame", {
		Name = "InfoRow",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 76),
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Parent = bottom,
	})
	UIKit.List(infoRow, {
		Direction = Enum.FillDirection.Horizontal,
		Padding = 10,
		HAlign = Enum.HorizontalAlignment.Center,
		VAlign = Enum.VerticalAlignment.Center,
	})
	self.CostLabel = Create("TextLabel", {
		Name = "Cost",
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "Cost: 🪙 10",
		TextSize = 18,
		LayoutOrder = 1,
		Parent = infoRow,
	})
	UIKit.TextStroke(self.CostLabel, Color3.new(0, 0, 0), 1)
	self.TokenToggle = Create("TextButton", {
		Name = "TokenToggle",
		Size = UDim2.fromOffset(170, 28),
		Text = "🎟️ Use Token (0)",
		TextSize = 15,
		BackgroundColor3 = Theme.PanelLight,
		LayoutOrder = 2,
		Corner = UDim.new(1, 0),
		Stroke = { Color = Config.Currencies.RerollTokens.Color, Thickness = 1.5, Transparency = 0.5 },
		Parent = infoRow,
	})

	local buttons = Create("Frame", {
		Name = "Buttons",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 86),
		BackgroundTransparency = 1,
		Parent = bottom,
	})
	UIKit.List(buttons, {
		Direction = Enum.FillDirection.Horizontal,
		Padding = 14,
		HAlign = Enum.HorizontalAlignment.Center,
		VAlign = Enum.VerticalAlignment.Bottom,
	})

	self.ClickButton = UIKit.Button({
		Name = "Click",
		Text = "🪙\nEARN",
		Size = UDim2.fromOffset(120, 74),
		Color = Color3.fromRGB(214, 150, 30),
		TextSize = 20,
		LayoutOrder = 1,
		Corner = 18,
		Parent = buttons,
	})
	self.RollButton = UIKit.Button({
		Name = "Roll",
		Text = "ROLL",
		Size = UDim2.fromOffset(230, 86),
		Color = Theme.Accent,
		TextSize = 38,
		LayoutOrder = 2,
		Corner = 22,
		Parent = buttons,
	})
	self.RollSubLabel = Create("TextLabel", {
		Name = "Sub",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, 0, 0, 16),
		Text = "",
		TextSize = 13,
		TextColor3 = Color3.fromRGB(220, 220, 240),
		Parent = self.RollButton,
	})
	self.CooldownBar = Create("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(0, 0.08),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.4,
		Corner = 4,
		Parent = self.RollButton,
	})
	self.AutoButton = UIKit.Button({
		Name = "Auto",
		Text = "🔁\nAUTO",
		Size = UDim2.fromOffset(120, 74),
		Color = Theme.PanelLighter,
		TextSize = 20,
		LayoutOrder = 3,
		Corner = 18,
		Parent = buttons,
	})

	self:_bind()
	return self
end

---------------------------------------------------------------------------
-- Data bindings for display-only elements
---------------------------------------------------------------------------
function Hud:SetBadge(name: string, visible: boolean)
	local badge = self.Badges[name]
	if badge and badge.Visible ~= visible then
		badge.Visible = visible
		if visible then
			UIKit.Pop(badge, 0.3)
		end
	end
end

function Hud:_renderEquipped()
	local data = self.Ctx.Data
	local equipped = data:Get("Equipped") or {}
	local slots = data:GetLive("EquipSlots") or Config.Equip.BaseSlots

	for _, child in self.EquipRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for slot = 1, slots do
		local name = equipped[slot]
		local item = name and Formulas.GetItem(name)
		local color = if item then Formulas.GetTier(Formulas.ItemTierIndex(item)).Color else Theme.Stroke
		local chip = Create("TextButton", {
			Name = "Slot" .. slot,
			Size = UDim2.fromOffset(if item then 0 else 34, 34),
			AutomaticSize = if item then Enum.AutomaticSize.X else Enum.AutomaticSize.None,
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.1,
			Text = if item then item.Name else "+",
			TextSize = 15,
			TextColor3 = if item then item.Color else Theme.SubText,
			LayoutOrder = slot,
			Corner = UDim.new(1, 0),
			Stroke = { Color = color, Thickness = 1.5, Transparency = 0.2 },
			Padding = { Left = 12, Right = 12 },
			Parent = self.EquipRow,
		})
		if item then
			UIKit.TextStroke(chip, Color3.new(0, 0, 0), 1)
		end
		chip.Activated:Connect(function()
			UIKit.ButtonClicked:Fire()
			self.Ctx.UI:OpenWindow("Inventory")
		end)
	end
end

function Hud:_renderBreakdown(breakdown)
	for _, child in self.BreakdownFrame:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for index, line in breakdown or {} do
		Create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 18),
			Text = `<font color="#{Theme.SubText:ToHex()}">{line.Label}</font>  {line.Value}`,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = index,
			Parent = self.BreakdownFrame,
		})
	end
end

function Hud:_renderBoosts()
	local boosts = self.Ctx.Data:Get("Boosts") or {}
	local seen = {}
	for boostId, remaining in boosts do
		local info = Config.Boosts[boostId]
		if info and remaining > 0 then
			seen[boostId] = true
			local chip = self.BoostList:FindFirstChild(boostId)
			if not chip then
				chip = Create("TextLabel", {
					Name = boostId,
					Size = UDim2.fromOffset(200, 30),
					BackgroundColor3 = Theme.Panel,
					BackgroundTransparency = 0.1,
					TextSize = 15,
					Corner = UDim.new(1, 0),
					Stroke = { Color = Theme.Accent, Thickness = 1, Transparency = 0.4 },
					Parent = self.BoostList,
				})
				UIKit.Pop(chip)
			end
			local multiplier = info.LuckMultiplier or info.CoinMultiplier or 1
			local kind = if info.LuckMultiplier then "luck" else "coins"
			chip.Text = `{info.Icon} x{multiplier} {kind} · {Util.Clock(remaining)}`
		end
	end
	for _, chip in self.BoostList:GetChildren() do
		if chip:IsA("TextLabel") and not seen[chip.Name] then
			chip:Destroy()
		end
	end
end

function Hud:_renderLuckHour()
	local now = Workspace:GetServerTimeNow()
	local active = ReplicatedStorage:GetAttribute("LuckHourActive")
	local endsAt = ReplicatedStorage:GetAttribute("LuckHourEndsAt") or 0
	local nextAt = ReplicatedStorage:GetAttribute("LuckHourNextAt") or 0
	local multiplier = ReplicatedStorage:GetAttribute("LuckHourMultiplier") or Config.LuckHour.Multiplier
	if active then
		self.LuckHourLabel.Text = `🍀 LUCK HOUR x{multiplier} · ends in {Util.Clock(endsAt - now)}`
		self.LuckHourLabel.TextColor3 = Color3.fromRGB(120, 255, 150)
		self.LuckHourFrame.BackgroundColor3 = Color3.fromRGB(20, 60, 36)
		if self.LuckHourStroke then
			self.LuckHourStroke.Color = Color3.fromRGB(90, 230, 120)
		end
	else
		self.LuckHourLabel.Text = `🍀 Next Luck Hour in {Util.Clock(nextAt - now)}`
		self.LuckHourLabel.TextColor3 = Theme.SubText
		self.LuckHourFrame.BackgroundColor3 = Theme.Panel
		if self.LuckHourStroke then
			self.LuckHourStroke.Color = Theme.Stroke
		end
	end
end

function Hud:_bind()
	local data = self.Ctx.Data

	data:ObserveLive("Luck", function(luck)
		self.LuckLabel.Text = "x" .. (if luck >= 1000 then Util.Abbreviate(luck) else string.format("%.2f", luck))
		UIKit.Pop(self.LuckLabel, 0.9)
	end)
	data:ObserveLive("LuckBreakdown", function(breakdown)
		self:_renderBreakdown(breakdown)
	end)
	data:Observe("Equipped", function()
		self:_renderEquipped()
	end)
	data:ObserveLive("EquipSlots", function()
		self:_renderEquipped()
	end)
	data:Observe("Boosts", function()
		self:_renderBoosts()
	end)

	task.spawn(function()
		while self.Frame.Parent do
			self:_renderLuckHour()
			task.wait(0.5)
		end
	end)
end

return Hud
