--[[
	Notifications — toasts, server-wide announcement banners and a queued
	modal popup (purchase confirmations, offline earnings, rewards, tutorial).

	  notifications:Toast(text, color?)
	  notifications:Banner(text, color, tierIndex?)
	  notifications:Popup({ Title, Text, Color?, Button?, OnClose? })   -- queued, one at a time
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local Util = require(Modules.Util)
local UIKit = require(script.Parent.UIKit)

local Theme = UIKit.Theme
local Create = UIKit.Create

local Notifications = {}
Notifications.__index = Notifications

export type PopupSpec = {
	Title: string,
	Text: string,
	Color: Color3?,
	Button: string?,
	OnClose: (() -> ())?,
}

function Notifications.new(root: Instance)
	local self = setmetatable({}, Notifications)

	self.ToastList = Create("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 170),
		Size = UDim2.fromOffset(320, 300),
		BackgroundTransparency = 1,
		ZIndex = 36,
		Parent = root,
	})
	UIKit.List(self.ToastList, { Padding = 6, HAlign = Enum.HorizontalAlignment.Right })

	self.BannerHolder = Create("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 50),
		Size = UDim2.fromOffset(560, 56),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 36,
		Parent = root,
	})
	self.BannerQueue = {}
	self.ToastCounter = 0
	self.BannerBusy = false

	-- Popup (modal, above windows)
	self.PopupOverlay = Create("TextButton", {
		Name = "Popup",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		Visible = false,
		ZIndex = 40,
		Parent = root,
	})
	self.PopupFrame = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		Active = true,
		Corner = 18,
		Stroke = { Color = Theme.Accent, Thickness = 2, Transparency = 0.2 },
		Padding = 22,
		Parent = self.PopupOverlay,
	})
	UIKit.List(self.PopupFrame, { Padding = 14, HAlign = Enum.HorizontalAlignment.Center })
	self.PopupStroke = self.PopupFrame:FindFirstChildOfClass("UIStroke")
	self.PopupTitle = Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 34),
		Text = "",
		TextSize = 28,
		FontFace = UIKit.Fonts.Heavy,
		TextWrapped = true,
		LayoutOrder = 1,
		Parent = self.PopupFrame,
	})
	self.PopupBody = Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = "",
		TextSize = 19,
		FontFace = UIKit.Fonts.Regular,
		TextColor3 = Theme.Text,
		TextWrapped = true,
		LayoutOrder = 2,
		Parent = self.PopupFrame,
	})
	self.PopupButton = UIKit.Button({
		Text = "OK",
		Size = UDim2.fromOffset(200, 52),
		Color = Theme.Accent,
		LayoutOrder = 3,
		Parent = self.PopupFrame,
		OnClick = function()
			self:_closePopup()
		end,
	})
	self.PopupQueue = {}
	self.PopupCurrent = nil :: PopupSpec?

	return self
end

---------------------------------------------------------------------------
-- Toasts
---------------------------------------------------------------------------
function Notifications:Toast(text: string, color: Color3?)
	local accent = color or Theme.Accent
	self.ToastCounter += 1
	local toast = Create("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(320, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.05,
		LayoutOrder = self.ToastCounter,
		Corner = 12,
		Stroke = { Color = accent, Thickness = 1.5, Transparency = 0.35 },
		Padding = { Top = 9, Bottom = 9, Left = 16, Right = 12 },
		Parent = self.ToastList,
	})
	Create("Frame", {
		Size = UDim2.new(0, 4, 1, 0),
		Position = UDim2.fromOffset(-10, 0),
		BackgroundColor3 = accent,
		Corner = 2,
		Parent = toast,
	})
	local label = Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text,
		TextSize = 16,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = toast,
	})
	UIKit.Pop(toast, 0.7)

	-- Keep at most 5 on screen.
	local toasts = {}
	for _, child in self.ToastList:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #toasts > 5 do
		local oldest = table.remove(toasts, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	task.delay(Config.UI.ToastDuration, function()
		if toast.Parent then
			UIKit.Tween(toast, 0.3, { BackgroundTransparency = 1 })
			UIKit.Tween(label, 0.3, { TextTransparency = 1 })
			task.wait(0.3)
			toast:Destroy()
		end
	end)
end

---------------------------------------------------------------------------
-- Announcement banner (queued)
---------------------------------------------------------------------------
function Notifications:Banner(text: string, color: Color3, tierIndex: number?)
	table.insert(self.BannerQueue, { Text = text, Color = color, Tier = tierIndex })
	if not self.BannerBusy then
		task.spawn(function()
			self:_runBanners()
		end)
	end
end

function Notifications:_runBanners()
	self.BannerBusy = true
	while #self.BannerQueue > 0 do
		local entry = table.remove(self.BannerQueue, 1)
		local banner = Create("Frame", {
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromScale(0, -1.1),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Gradient = {
				Color = { Util.Shade(entry.Color, -0.55), Util.Shade(entry.Color, -0.25), Util.Shade(entry.Color, -0.55) },
				Rotation = 0,
			},
			Corner = 14,
			Stroke = { Color = entry.Color, Thickness = 2, Transparency = 0 },
			Parent = self.BannerHolder,
		})
		local label = Create("TextLabel", {
			Size = UDim2.new(1, -24, 1, 0),
			Position = UDim2.fromOffset(12, 0),
			Text = entry.Text,
			TextSize = 20,
			FontFace = UIKit.Fonts.Heavy,
			TextWrapped = true,
			Parent = banner,
		})
		UIKit.TextStroke(label, Color3.new(0, 0, 0), 1.5)

		UIKit.Tween(banner, 0.4, { Position = UDim2.fromScale(0, 0) }, Enum.EasingStyle.Back)
		-- Shimmer for very rare pulls.
		if entry.Tier and entry.Tier >= 6 then
			local gradient = banner:FindFirstChildOfClass("UIGradient")
			if gradient then
				task.spawn(function()
					local t = 0
					while banner.Parent do
						t += task.wait()
						gradient.Offset = Vector2.new(math.sin(t * 2) * 0.3, 0)
					end
				end)
			end
		end
		task.wait(Config.UI.AnnouncementDuration)
		UIKit.Tween(banner, 0.3, { Position = UDim2.fromScale(0, -1.1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.wait(0.3)
		banner:Destroy()
	end
	self.BannerBusy = false
end

---------------------------------------------------------------------------
-- Popup (queued modal)
---------------------------------------------------------------------------
function Notifications:Popup(spec: PopupSpec)
	table.insert(self.PopupQueue, spec)
	if not self.PopupCurrent then
		self:_showNextPopup()
	end
end

function Notifications:IsPopupOpen(): boolean
	return self.PopupCurrent ~= nil
end

function Notifications:_showNextPopup()
	local spec = table.remove(self.PopupQueue, 1)
	self.PopupCurrent = spec
	if not spec then
		UIKit.Tween(self.PopupOverlay, 0.15, { BackgroundTransparency = 1 })
		task.delay(0.15, function()
			if not self.PopupCurrent then
				self.PopupOverlay.Visible = false
			end
		end)
		return
	end
	local color = spec.Color or Theme.Accent
	self.PopupTitle.Text = spec.Title
	self.PopupTitle.TextColor3 = Util.Shade(color, 0.35)
	self.PopupBody.Text = spec.Text
	self.PopupButton.Text = spec.Button or "Awesome!"
	self.PopupButton.BackgroundColor3 = color
	if self.PopupStroke then
		self.PopupStroke.Color = color
	end
	self.PopupOverlay.Visible = true
	UIKit.Tween(self.PopupOverlay, 0.2, { BackgroundTransparency = 0.4 })
	UIKit.Pop(self.PopupFrame, 0.8)
end

function Notifications:_closePopup()
	local spec = self.PopupCurrent
	if spec and spec.OnClose then
		task.spawn(spec.OnClose)
	end
	self:_showNextPopup()
end

return Notifications
