--[[
	ShopWindow — gamepasses, developer products (Robux) and the gem shop.

	Robux prices are fetched live with GetProductInfo, so you only set IDs in
	Config. Items whose ID is still 0 show "Not set up" instead of prompting.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local Net = require(Modules.Net)
local UIKit = require(script.Parent.UIKit)

local Theme = UIKit.Theme
local Create = UIKit.Create

local ROBUX = utf8.char(0xE002)
local player = Players.LocalPlayer

local ShopWindow = {}
ShopWindow.__index = ShopWindow

local function sortedEntries(map)
	local list = {}
	for key, entry in map do
		table.insert(list, { Key = key, Entry = entry })
	end
	table.sort(list, function(a, b)
		return a.Entry.Order < b.Entry.Order
	end)
	return list
end

function ShopWindow.new(root: Instance, ctx)
	local self = setmetatable({}, ShopWindow)
	self.Ctx = ctx
	self.PassButtons = {}
	self.Pages = {}

	local window = UIKit.Window(root, {
		Name = "ShopWindow",
		Title = "Shop",
		Icon = "🛒",
		Size = UDim2.fromOffset(700, 500),
		Accent = Theme.Warning,
	})
	self.Window = window
	local content = window.Content

	local pagesHolder = Create("Frame", {
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 1, -50),
		BackgroundTransparency = 1,
		Parent = content,
	})

	local function makePage(name: string)
		local page = Create("ScrollingFrame", {
			Name = name,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Padding = { Top = 4, Bottom = 8, Left = 2, Right = 8 },
			Parent = pagesHolder,
		})
		UIKit.Grid(page, UDim2.fromOffset(200, 196), 10)
		self.Pages[name] = page
		return page
	end

	local passPage = makePage("Gamepasses")
	local productPage = makePage("Robux Items")
	local gemPage = makePage("Gem Shop")

	for index, row in sortedEntries(Config.Gamepasses) do
		local button = self:_card(passPage, row.Entry, index, function()
			self:_buyPass(row.Key, row.Entry)
		end)
		self.PassButtons[row.Key] = button
		self:_loadPrice(button, row.Entry.Id, Enum.InfoType.GamePass)
	end

	for index, row in sortedEntries(Config.DevProducts) do
		local button = self:_card(productPage, row.Entry, index, function()
			self:_buyProduct(row.Entry)
		end)
		self:_loadPrice(button, row.Entry.Id, Enum.InfoType.Product)
	end

	for index, entry in Config.GemShop do
		local button = self:_card(gemPage, entry, index, function()
			Net.Event("BuyGemItem"):FireServer(entry.Id)
		end)
		button.Text = `{Config.Currencies.Gems.Icon} {entry.Price}`
		button.BackgroundColor3 = Color3.fromRGB(30, 150, 200)
	end

	local tabs = UIKit.Tabs(content, {
		Names = { "Gamepasses", "Robux Items", "Gem Shop" },
		OnSelect = function(name)
			for pageName, page in self.Pages do
				page.Visible = pageName == name
			end
		end,
	})
	tabs.Select("Gamepasses")

	ctx.Data:ObserveLive("Passes", function()
		self:_renderOwned()
	end)

	return self
end

function ShopWindow:_card(parent: Instance, entry, order: number, onBuy: () -> ()): TextButton
	local card = Create("Frame", {
		Name = entry.Name,
		BackgroundColor3 = Theme.PanelLight,
		LayoutOrder = order,
		Corner = 14,
		Stroke = { Color = Theme.Stroke, Thickness = 1, Transparency = 0.3 },
		Parent = parent,
	})
	UIKit.Gradient(card, { Color = { Color3.new(1, 1, 1), Color3.fromRGB(210, 210, 225) }, Rotation = 90 })
	Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 44),
		Position = UDim2.fromOffset(0, 8),
		Text = entry.Icon,
		TextSize = 36,
		Parent = card,
	})
	Create("TextLabel", {
		Size = UDim2.new(1, -16, 0, 24),
		Position = UDim2.fromOffset(8, 54),
		Text = entry.Name,
		TextSize = 19,
		FontFace = UIKit.Fonts.Heavy,
		Parent = card,
	})
	Create("TextLabel", {
		Size = UDim2.new(1, -20, 0, 52),
		Position = UDim2.fromOffset(10, 80),
		Text = entry.Description,
		TextSize = 14,
		FontFace = UIKit.Fonts.Regular,
		TextColor3 = Theme.SubText,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	return UIKit.Button({
		Name = "Buy",
		Text = "…",
		Size = UDim2.new(1, -20, 0, 44),
		Position = UDim2.new(0, 10, 1, -10),
		AnchorPoint = Vector2.new(0, 1),
		Color = Theme.Success,
		TextSize = 19,
		Parent = card,
		OnClick = onBuy,
	})
end

function ShopWindow:_loadPrice(button: TextButton, id: number, infoType: Enum.InfoType)
	if id == 0 then
		button.Text = "Not set up"
		button.BackgroundColor3 = Theme.Disabled
		return
	end
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id, infoType)
		if ok and info and info.PriceInRobux then
			if button:GetAttribute("Owned") then
				return
			end
			button.Text = `{ROBUX} {info.PriceInRobux}`
		else
			button.Text = "Buy"
		end
	end)
end

function ShopWindow:_renderOwned()
	local passes = self.Ctx.Data:GetLive("Passes") or {}
	for key, button in self.PassButtons do
		if passes[key] then
			button:SetAttribute("Owned", true)
			button.Text = "✅ Owned"
			button.BackgroundColor3 = Theme.Disabled
		end
	end
end

function ShopWindow:_buyPass(key: string, pass)
	local passes = self.Ctx.Data:GetLive("Passes") or {}
	if passes[key] then
		return
	end
	if pass.Id == 0 then
		self.Ctx.UI.Notifications:Toast(`{pass.Name} has no gamepass ID yet (Config.Gamepasses).`, Theme.Warning)
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, pass.Id)
end

function ShopWindow:_buyProduct(product)
	if product.Id == 0 then
		self.Ctx.UI.Notifications:Toast(`{product.Name} has no product ID yet (Config.DevProducts).`, Theme.Warning)
		return
	end
	MarketplaceService:PromptProductPurchase(player, product.Id)
end

-- Opens the shop on the gamepass tab (used when a locked feature is pressed).
function ShopWindow:PromptPass(key: string)
	local pass = Config.Gamepasses[key]
	if pass then
		self:_buyPass(key, pass)
	end
end

return ShopWindow
