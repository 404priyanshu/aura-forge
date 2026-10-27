--[[
	UIController — owns the ScreenGui and every screen.

	  * Builds the HUD, windows (Inventory, Shop, Quests, Daily, Settings) and
	    the notification layer in Init, so other controllers can bind to them
	    in Start.
	  * Responsive: everything is authored at Config.UI.DesignWidth x
	    DesignHeight and scaled with a UIScale to fit the safe area of any
	    screen (phones get a minimum scale so touch targets stay big).
	  * Handles server notifications/announcements, the first-time tutorial,
	    "red dot" badges for claimable rewards and the VIP chat tag.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local Util = require(Modules.Util)
local Net = require(Modules.Net)

local UI = script.Parent.Parent:WaitForChild("UI")
local UIKit = require(UI.UIKit)
local Hud = require(UI.Hud)
local Notifications = require(UI.Notifications)
local InventoryWindow = require(UI.InventoryWindow)
local ShopWindow = require(UI.ShopWindow)
local QuestsWindow = require(UI.QuestsWindow)
local DailyWindow = require(UI.DailyWindow)
local SettingsWindow = require(UI.SettingsWindow)

local Theme = UIKit.Theme
local player = Players.LocalPlayer

local UIController = {}
UIController.Windows = {}

function UIController:_updateScale()
	local size = self.ScreenGui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local cfg = Config.UI
	local scale = math.min(size.X / cfg.DesignWidth, size.Y / cfg.DesignHeight)
	local isTouchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local minScale = if isTouchOnly then math.max(cfg.MinScale, 0.62) else cfg.MinScale
	scale = math.clamp(scale, minScale, cfg.MaxScale)
	self.Scale.Scale = scale
	-- Root is sized 1/scale so after scaling it exactly fills the screen.
	self.Root.Size = UDim2.fromScale(1 / scale, 1 / scale)
	self.CurrentScale = scale
end

-- Converts an absolute screen position into the root's (design-pixel) space.
function UIController:ToRootSpace(absolute: Vector2): Vector2
	return (absolute - self.Root.AbsolutePosition) / (self.CurrentScale or 1)
end

function UIController:OpenWindow(name: string)
	local target = self.Windows[name]
	if not target then
		return
	end
	if target.Window.IsOpen then
		target.Window:Close()
		return
	end
	for otherName, other in self.Windows do
		if otherName ~= name then
			other.Window:Close()
		end
	end
	target.Window:Open()
end

function UIController:CloseAll()
	for _, entry in self.Windows do
		entry.Window:Close()
	end
end

function UIController:PromptPass(passKey: string)
	local pass = Config.Gamepasses[passKey]
	if pass then
		self.Notifications:Toast(`{pass.Icon} {pass.Name} is a gamepass — opening the shop.`, Theme.Accent)
	end
	self:OpenWindow("Shop")
	self.Windows.Shop:PromptPass(passKey)
end

---------------------------------------------------------------------------
-- Server messages
---------------------------------------------------------------------------
function UIController:_onNotify(kind: string, payload)
	local audio = self.Controllers.AudioController
	if kind == "Toast" then
		self.Notifications:Toast(payload.Text, payload.Color)
	elseif kind == "QuestReady" then
		self.Notifications:Toast("📜 " .. payload.Text, Theme.Success)
		audio:Play("Claim")
	elseif kind == "Popup" then
		self.Notifications:Popup({ Title = payload.Title, Text = payload.Text, Color = payload.Color })
		audio:Play("Claim")
	elseif kind == "Purchase" then
		self.Notifications:Popup({
			Title = payload.Title or "Purchase complete!",
			Text = payload.Text,
			Color = Theme.Success,
			Button = "Let's go!",
		})
		audio:Play("Purchase")
	elseif kind == "Offline" then
		local capped = if payload.Capped
			then `\n<font color="#9aa0b8">(earnings cap at {Util.Duration(Config.Offline.MaxSeconds)})</font>`
			else ""
		self.Notifications:Popup({
			Title = "Welcome back!",
			Text = `You were away for {Util.Duration(payload.Away)} and earned\n<font color="#ffce4a"><b>{Config.Currencies.Coins.Icon} {Util.Commas(
				payload.Amount
			)} coins</b></font>{capped}`,
			Color = Config.Currencies.Coins.Color,
			Button = "Collect",
		})
		audio:Play("Claim")
	end
end

function UIController:_runTutorial()
	if self.TutorialRunning then
		return
	end
	self.TutorialRunning = true
	local pages = Config.Tutorial.Pages
	for index, page in pages do
		local isLast = index == #pages
		self.Notifications:Popup({
			Title = page.Title,
			Text = page.Body .. `\n\n<font color="#9aa0b8">{index} / {#pages}</font>`,
			Color = Theme.Accent,
			Button = if isLast then "Start rolling!" else "Next",
			OnClose = if isLast
				then function()
					self.TutorialRunning = false
					Net.Event("TutorialDone"):FireServer()
					UIKit.Pop(self.Hud.RollButton, 0.6)
				end
				else nil,
		})
	end
end

local function installVipChatTag()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		return
	end
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local properties = Instance.new("TextChatMessageProperties")
		local source = message.TextSource
		if source then
			local speaker = Players:GetPlayerByUserId(source.UserId)
			if speaker and speaker:GetAttribute("VIP") then
				properties.PrefixText =
					`<font color="{Config.VIP.ChatTagColor}">{Config.VIP.ChatTag}</font> {message.PrefixText}`
			end
		end
		return properties
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function UIController:Init(controllers)
	self.Controllers = controllers

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AuraForgeUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = player:WaitForChild("PlayerGui")
	self.ScreenGui = screenGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = screenGui
	self.Root = root

	local scale = Instance.new("UIScale")
	scale.Parent = root
	self.Scale = scale
	self:_updateScale()
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_updateScale()
	end)

	local ctx = { Data = controllers.DataController, UI = self }

	self.Hud = Hud.new(root, ctx)
	self.Notifications = Notifications.new(root)
	self.Windows.Inventory = InventoryWindow.new(root, ctx)
	self.Windows.Shop = ShopWindow.new(root, ctx)
	self.Windows.Quests = QuestsWindow.new(root, ctx)
	self.Windows.Daily = DailyWindow.new(root, ctx)
	self.Windows.Settings = SettingsWindow.new(root, ctx)

	-- Loading cover until the first data snapshot arrives.
	self.Loading = UIKit.Create("Frame", {
		Name = "Loading",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background,
		ZIndex = 50,
		Active = true,
		Parent = root,
	})
	UIKit.Gradient(self.Loading, { Color = { Color3.fromRGB(30, 22, 60), Theme.Background }, Rotation = 90 })
	self.LoadingLabel = UIKit.Create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(600, 80),
		Text = `✨ {Config.GameName}\n<font size="20" color="#9aa0b8">Loading your auras...</font>`,
		TextSize = 44,
		FontFace = UIKit.Fonts.Heavy,
		Parent = self.Loading,
	})
end

function UIController:Start()
	local data = self.Controllers.DataController

	for name, button in self.Hud.MenuButtons do
		button.Activated:Connect(function()
			self:OpenWindow(name)
		end)
	end

	Net.Event("Notify").OnClientEvent:Connect(function(kind, payload)
		self:_onNotify(kind, payload)
	end)
	Net.Event("Announce").OnClientEvent:Connect(function(payload)
		self.Notifications:Banner(payload.Text, payload.Color, payload.Tier)
		if payload.Tier then
			self.Controllers.AudioController:Play("Fanfare", 0.8)
		end
	end)

	installVipChatTag()

	-- Keyboard: Escape closes windows.
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Escape then
			self:CloseAll()
		end
	end)

	-- Hide loading screen once data is here.
	task.spawn(function()
		data:WaitForData()
		UIKit.Tween(self.Loading, 0.5, { BackgroundTransparency = 1 })
		UIKit.Tween(self.LoadingLabel, 0.5, { TextTransparency = 1 })
		task.wait(0.5)
		self.Loading:Destroy()
	end)

	data:Observe("Tutorial", function(tutorial)
		if not tutorial.Completed then
			self:_runTutorial()
		end
	end)

	-- Red-dot badges for anything claimable.
	task.spawn(function()
		while self.ScreenGui.Parent do
			if data.Loaded then
				self.Hud:SetBadge("Daily", self.Windows.Daily:HasClaimable())
				self.Hud:SetBadge("Quests", self.Windows.Quests:HasClaimable())
				self.Hud:SetBadge("Inventory", self.Windows.Inventory:HasClaimable())
			end
			task.wait(1)
		end
	end)
end

return UIController
