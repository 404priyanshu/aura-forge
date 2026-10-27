--[[
	InventoryWindow — the aura index.

	Every item in RarityTable is shown in a grid sorted by rarity. Unowned items
	are greyed out; owned ones show the count and can be tapped to equip /
	unequip. The strip at the top tracks each rarity's collection and lets the
	player claim the index-completion reward.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local Formulas = require(Modules.Formulas)
local RarityTable = require(Modules.RarityTable)
local Util = require(Modules.Util)
local Net = require(Modules.Net)
local UIKit = require(script.Parent.UIKit)

local Theme = UIKit.Theme
local Create = UIKit.Create

local InventoryWindow = {}
InventoryWindow.__index = InventoryWindow

local function percent(multiplier: number): string
	return string.format("+%d%%", math.floor((multiplier - 1) * 100 + 0.5))
end

function InventoryWindow.new(root: Instance, ctx)
	local self = setmetatable({}, InventoryWindow)
	self.Ctx = ctx
	self.Cells = {}
	self.TierChips = {}
	self.Filter = "All"

	local window = UIKit.Window(root, {
		Name = "InventoryWindow",
		Title = "Aura Index",
		Icon = "🎒",
		Size = UDim2.fromOffset(700, 500),
	})
	self.Window = window
	local content = window.Content

	-- Collection strip
	local strip = Create("ScrollingFrame", {
		Name = "Collection",
		Size = UDim2.new(1, 0, 0, 62),
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollBarThickness = 4,
		Parent = content,
	})
	UIKit.List(strip, { Direction = Enum.FillDirection.Horizontal, Padding = 6, VAlign = Enum.VerticalAlignment.Center })

	for index, tier in RarityTable.Tiers do
		local chip = Create("TextButton", {
			Name = tier.Name,
			Size = UDim2.fromOffset(108, 52),
			BackgroundColor3 = Theme.PanelLight,
			Text = "",
			LayoutOrder = index,
			Corner = 10,
			Stroke = { Color = tier.Color, Thickness = 1.5, Transparency = 0.4 },
			Parent = strip,
		})
		Create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, 4),
			Text = tier.Name,
			TextSize = 15,
			TextColor3 = tier.Color,
			Parent = chip,
		})
		local progress = Create("TextLabel", {
			Name = "Progress",
			Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.fromOffset(0, 26),
			Text = "0/0",
			TextSize = 14,
			TextColor3 = Theme.SubText,
			Parent = chip,
		})
		chip.Activated:Connect(function()
			UIKit.ButtonClicked:Fire()
			Net.Event("ClaimIndex"):FireServer(tier.Name)
		end)
		self.TierChips[tier.Name] = { Button = chip, Progress = progress, TierIndex = index }
	end

	-- Toolbar
	local toolbar = Create("Frame", {
		Name = "Toolbar",
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Parent = content,
	})
	local tabs = UIKit.Tabs(toolbar, {
		Names = { "All", "Owned" },
		Size = UDim2.new(0, 300, 1, 0),
		OnSelect = function(name)
			self.Filter = name
			self:Render()
		end,
	})
	self.EquippedLabel = Create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -150, 0, 0),
		Size = UDim2.fromOffset(160, 40),
		Text = "Equipped 0/3",
		TextSize = 16,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = toolbar,
	})
	UIKit.Button({
		Text = "Equip Best",
		Size = UDim2.fromOffset(136, 40),
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Color = Theme.Success,
		TextSize = 17,
		Parent = toolbar,
		OnClick = function()
			Net.Event("EquipBest"):FireServer()
		end,
	})

	-- Grid
	local grid = Create("ScrollingFrame", {
		Name = "Grid",
		Position = UDim2.fromOffset(0, 118),
		Size = UDim2.new(1, 0, 1, -118),
		Padding = { Top = 4, Bottom = 8, Left = 2, Right = 8 },
		Parent = content,
	})
	UIKit.Grid(grid, UDim2.fromOffset(118, 146), 8)
	self.Grid = grid

	for order, item in RarityTable.Items do
		self.Cells[item.Name] = self:_buildCell(item, order)
	end
	tabs.Select("All")

	local data = ctx.Data
	data:Observe("Inventory", function()
		self:Render()
	end)
	data:Observe("Equipped", function()
		self:Render()
	end)
	data:Observe("IndexClaims", function()
		self:Render()
	end)
	data:ObserveLive("EquipSlots", function()
		self:Render()
	end)

	return self
end

function InventoryWindow:_buildCell(item: RarityTable.Item, order: number)
	local tierIndex = Formulas.ItemTierIndex(item)
	local tier = Formulas.GetTier(tierIndex)
	local baseChance = Formulas.ItemProbability(item.Name, Config.Luck.BaseLuck)

	local cell = Create("TextButton", {
		Name = item.Name,
		BackgroundColor3 = Theme.PanelLight,
		Text = "",
		LayoutOrder = order,
		Corner = 12,
		Parent = self.Grid,
	})
	local stroke = UIKit.Stroke(cell, tier.Color, 1.5, 0.5)

	local swatch = Create("Frame", {
		Name = "Swatch",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = item.Color,
		Corner = UDim.new(1, 0),
		Stroke = { Color = Util.Shade(item.Color, 0.5), Thickness = 2, Transparency = 0.2 },
		Parent = cell,
	})
	UIKit.Gradient(swatch, { Color = { Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 170) }, Rotation = 45 })

	local nameLabel = Create("TextLabel", {
		Size = UDim2.new(1, -8, 0, 20),
		Position = UDim2.fromOffset(4, 58),
		Text = item.Name,
		TextSize = 15,
		TextScaled = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = cell,
	})
	Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, 78),
		Text = tier.Name,
		TextSize = 13,
		TextColor3 = tier.Color,
		Parent = cell,
	})
	Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, 94),
		Text = Util.Odds(baseChance),
		TextSize = 13,
		FontFace = UIKit.Fonts.Regular,
		TextColor3 = Theme.SubText,
		Parent = cell,
	})
	Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, 110),
		Text = `🍀{percent(item.LuckMultiplier)} 🪙{percent(item.CoinMultiplier)}`,
		TextSize = 12,
		FontFace = UIKit.Fonts.Regular,
		TextColor3 = Theme.SubText,
		Parent = cell,
	})
	local count = Create("TextLabel", {
		Name = "Count",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 4),
		Size = UDim2.fromOffset(50, 18),
		Text = "",
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = cell,
	})
	local equipped = Create("TextLabel", {
		Name = "Equipped",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -12, 0, 16),
		BackgroundColor3 = Theme.Success,
		BackgroundTransparency = 0,
		Text = "EQUIPPED",
		TextSize = 11,
		Visible = false,
		Corner = 6,
		Parent = cell,
	})
	local locked = Create("Frame", {
		Name = "Locked",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		ZIndex = 5,
		Corner = 12,
		Parent = cell,
	})
	Create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 20),
		Size = UDim2.fromOffset(30, 30),
		Text = "🔒",
		TextSize = 22,
		ZIndex = 6,
		Parent = locked,
	})

	cell.Activated:Connect(function()
		local data = self.Ctx.Data
		local inventory = data:Get("Inventory") or {}
		if (inventory[item.Name] or 0) <= 0 then
			return
		end
		UIKit.ButtonClicked:Fire()
		local isEquipped = table.find(data:Get("Equipped") or {}, item.Name) ~= nil
		Net.Event(if isEquipped then "Unequip" else "Equip"):FireServer(item.Name)
		UIKit.Pop(cell, 0.9)
	end)

	return {
		Cell = cell,
		Stroke = stroke,
		Name = nameLabel,
		Count = count,
		Equipped = equipped,
		Locked = locked,
	}
end

function InventoryWindow:Render()
	local data = self.Ctx.Data
	local inventory = data:Get("Inventory") or {}
	local equipped = data:Get("Equipped") or {}
	local claims = data:Get("IndexClaims") or {}
	local slots = data:GetLive("EquipSlots") or Config.Equip.BaseSlots

	self.EquippedLabel.Text = `Equipped {#equipped}/{slots}`

	for name, cell in self.Cells do
		local owned = (inventory[name] or 0) > 0
		local isEquipped = table.find(equipped, name) ~= nil
		cell.Cell.Visible = owned or self.Filter == "All"
		cell.Locked.Visible = not owned
		cell.Count.Text = if owned then "x" .. Util.Abbreviate(inventory[name]) else ""
		cell.Equipped.Visible = isEquipped
		cell.Stroke.Thickness = if isEquipped then 3 else 1.5
		cell.Stroke.Transparency = if isEquipped then 0 else 0.5
	end

	for tierName, chip in self.TierChips do
		local items = Formulas.ItemsInTier(chip.TierIndex)
		local ownedCount = 0
		for _, item in items do
			if (inventory[item.Name] or 0) > 0 then
				ownedCount += 1
			end
		end
		local complete = ownedCount == #items
		local hasReward = Config.Index.Rewards[tierName] ~= nil
		if claims[tierName] then
			chip.Progress.Text = "✅ Claimed"
			chip.Progress.TextColor3 = Theme.Success
		elseif complete and hasReward then
			chip.Progress.Text = "🎁 CLAIM!"
			chip.Progress.TextColor3 = Theme.Warning
		else
			chip.Progress.Text = `{ownedCount}/{#items}`
			chip.Progress.TextColor3 = Theme.SubText
		end
	end
end

-- True when any completed tier still has an unclaimed reward (for the HUD badge).
function InventoryWindow:HasClaimable(): boolean
	local data = self.Ctx.Data
	local inventory = data:Get("Inventory") or {}
	local claims = data:Get("IndexClaims") or {}
	for tierName, chip in self.TierChips do
		if not claims[tierName] and Config.Index.Rewards[tierName] then
			local complete = true
			for _, item in Formulas.ItemsInTier(chip.TierIndex) do
				if (inventory[item.Name] or 0) <= 0 then
					complete = false
					break
				end
			end
			if complete then
				return true
			end
		end
	end
	return false
end

return InventoryWindow
