--[[
	UIKit — helpers that keep every screen consistent (dark theme, rounded
	corners, subtle strokes, gradient accents, springy buttons).

	  UIKit.Create(className, props, children?)
	      props may also contain: Corner = radius, Stroke = true | {Color, Thickness, Transparency},
	      Gradient = {Color, Rotation, Transparency}, Padding = px | {Top,Bottom,Left,Right},
	      Children = {...}, and event handlers (Activated = function() end).
	  UIKit.Corner / Stroke / Gradient / Padding / List / Grid / Tween / Pop
	  UIKit.Button(props)      -- themed button with hover/press animation + click sound hook
	  UIKit.Window(parent, opts) -- modal panel with header, close button, open/close tweens
	  UIKit.ProgressBar(parent, props), UIKit.Toggle(parent, props), UIKit.Tabs(parent, props)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Signal = require(Modules.Signal)
local Util = require(Modules.Util)

local UIKit = {}

local FAMILY = "rbxasset://fonts/families/BuilderSans.json"

UIKit.Fonts = {
	Regular = Font.new(FAMILY, Enum.FontWeight.Medium),
	Bold = Font.new(FAMILY, Enum.FontWeight.Bold),
	Heavy = Font.new(FAMILY, Enum.FontWeight.Heavy),
}

UIKit.Theme = {
	Background = Color3.fromRGB(12, 13, 20),
	Panel = Color3.fromRGB(22, 24, 34),
	PanelLight = Color3.fromRGB(32, 35, 49),
	PanelLighter = Color3.fromRGB(44, 48, 66),
	Stroke = Color3.fromRGB(62, 66, 92),
	Text = Color3.fromRGB(238, 240, 250),
	SubText = Color3.fromRGB(150, 156, 182),
	Accent = Color3.fromRGB(124, 92, 255),
	Accent2 = Color3.fromRGB(0, 196, 255),
	Success = Color3.fromRGB(56, 200, 112),
	Warning = Color3.fromRGB(255, 186, 56),
	Danger = Color3.fromRGB(240, 72, 96),
	Disabled = Color3.fromRGB(70, 74, 92),
}

-- Fired on every themed button click (AudioController plays the click sound).
UIKit.ButtonClicked = Signal.new()

local Theme = UIKit.Theme

---------------------------------------------------------------------------
-- Decorators
---------------------------------------------------------------------------
function UIKit.Corner(instance: Instance, radius: (number | UDim)?): UICorner
	local corner = Instance.new("UICorner")
	if typeof(radius) == "UDim" then
		corner.CornerRadius = radius
	else
		corner.CornerRadius = UDim.new(0, (radius :: number?) or 10)
	end
	corner.Parent = instance
	return corner
end

function UIKit.Stroke(instance: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color or Theme.Stroke
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0.2
	stroke.Parent = instance
	return stroke
end

function UIKit.TextStroke(instance: Instance, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Color = color or Color3.new(0, 0, 0)
	stroke.Thickness = thickness or 1.5
	stroke.Transparency = 0.35
	stroke.Parent = instance
	return stroke
end

type GradientSpec = { Color: (ColorSequence | { Color3 })?, Rotation: number?, Transparency: NumberSequence? }

function UIKit.Gradient(instance: Instance, spec: GradientSpec): UIGradient
	local gradient = Instance.new("UIGradient")
	local color = spec.Color
	if typeof(color) == "ColorSequence" then
		gradient.Color = color
	elseif type(color) == "table" then
		local keypoints = {}
		for i, c in color do
			table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / math.max(1, #color - 1), c))
		end
		gradient.Color = ColorSequence.new(keypoints)
	end
	if spec.Transparency then
		gradient.Transparency = spec.Transparency
	end
	gradient.Rotation = spec.Rotation or 90
	gradient.Parent = instance
	return gradient
end

function UIKit.Padding(instance: Instance, padding: number | { [string]: number }): UIPadding
	local pad = Instance.new("UIPadding")
	if type(padding) == "number" then
		local p = UDim.new(0, padding)
		pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight = p, p, p, p
	else
		pad.PaddingTop = UDim.new(0, padding.Top or 0)
		pad.PaddingBottom = UDim.new(0, padding.Bottom or 0)
		pad.PaddingLeft = UDim.new(0, padding.Left or 0)
		pad.PaddingRight = UDim.new(0, padding.Right or 0)
	end
	pad.Parent = instance
	return pad
end

type ListSpec = {
	Direction: Enum.FillDirection?,
	Padding: number?,
	HAlign: Enum.HorizontalAlignment?,
	VAlign: Enum.VerticalAlignment?,
	Wraps: boolean?,
}

function UIKit.List(instance: Instance, spec: ListSpec?): UIListLayout
	local s: ListSpec = spec or {}
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.FillDirection = s.Direction or Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, s.Padding or 8)
	layout.HorizontalAlignment = s.HAlign or Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = s.VAlign or Enum.VerticalAlignment.Top
	layout.Wraps = s.Wraps == true
	layout.Parent = instance
	return layout
end

function UIKit.Grid(instance: Instance, cellSize: UDim2, padding: number?): UIGridLayout
	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.CellSize = cellSize
	grid.CellPadding = UDim2.fromOffset(padding or 8, padding or 8)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = instance
	return grid
end

---------------------------------------------------------------------------
-- Create
---------------------------------------------------------------------------
local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }

function UIKit.Create(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance: any = Instance.new(className)

	-- Theme defaults (props below override them).
	if instance:IsA("GuiObject") then
		instance.BorderSizePixel = 0
		instance.BackgroundColor3 = Theme.Panel
	end
	if TEXT_CLASSES[className] then
		instance.FontFace = UIKit.Fonts.Bold
		instance.TextColor3 = Theme.Text
		instance.TextSize = 18
		instance.RichText = true
		if className == "TextLabel" then
			instance.BackgroundTransparency = 1
		end
	end
	if className == "TextButton" or className == "ImageButton" then
		instance.AutoButtonColor = false
	end
	if className == "ImageLabel" then
		instance.BackgroundTransparency = 1
	end
	if className == "ScrollingFrame" then
		instance.BackgroundTransparency = 1
		instance.ScrollBarThickness = 5
		instance.ScrollBarImageColor3 = Theme.Stroke
		instance.CanvasSize = UDim2.new()
		instance.AutomaticCanvasSize = Enum.AutomaticSize.Y
		instance.ScrollingDirection = Enum.ScrollingDirection.Y
	end

	local parent: Instance? = nil
	local properties: { [string]: any } = props or {}
	for key, value in properties do
		if key == "Parent" then
			parent = value
		elseif key == "Corner" then
			UIKit.Corner(instance, value)
		elseif key == "Stroke" then
			if type(value) == "table" then
				UIKit.Stroke(instance, value.Color, value.Thickness, value.Transparency)
			else
				UIKit.Stroke(instance)
			end
		elseif key == "Gradient" then
			UIKit.Gradient(instance, value)
		elseif key == "Padding" then
			UIKit.Padding(instance, value)
		elseif key == "Children" then
			for _, child in value do
				child.Parent = instance
			end
		elseif type(value) == "function" then
			instance[key]:Connect(value)
		else
			instance[key] = value
		end
	end

	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

---------------------------------------------------------------------------
-- Animation
---------------------------------------------------------------------------
function UIKit.Tween(
	instance: Instance,
	duration: number,
	goals: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goals
	)
	tween:Play()
	return tween
end

-- Returns (creating if needed) a UIScale used for pop/press animations.
function UIKit.GetScale(instance: Instance): UIScale
	local scale = instance:FindFirstChild("AnimScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "AnimScale"
		scale.Parent = instance
	end
	return scale :: UIScale
end

function UIKit.Pop(instance: Instance, from: number?)
	local scale = UIKit.GetScale(instance)
	scale.Scale = from or 0.85
	UIKit.Tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

---------------------------------------------------------------------------
-- Components
---------------------------------------------------------------------------
export type ButtonProps = {
	Name: string?,
	Text: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Color: Color3?,
	TextColor: Color3?,
	TextSize: number?,
	LayoutOrder: number?,
	Corner: number?,
	Parent: Instance?,
	OnClick: (() -> ())?,
}

function UIKit.Button(props: ButtonProps): TextButton
	local color = props.Color or Theme.Accent
	local button: TextButton = UIKit.Create("TextButton", {
		Name = props.Name or "Button",
		Size = props.Size or UDim2.fromOffset(160, 48),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = color,
		Text = props.Text or "",
		TextSize = props.TextSize or 20,
		FontFace = UIKit.Fonts.Heavy,
		TextColor3 = props.TextColor or Theme.Text,
		LayoutOrder = props.LayoutOrder or 0,
		Corner = props.Corner or 12,
	})
	-- Light-to-dark sheen (white multiply keeps text readable).
	UIKit.Gradient(button, { Color = { Color3.new(1, 1, 1), Color3.fromRGB(196, 196, 206) }, Rotation = 90 })
	UIKit.Stroke(button, Util.Shade(color, 0.35), 1.5, 0.35)
	UIKit.TextStroke(button, Color3.new(0, 0, 0), 1)

	local scale = UIKit.GetScale(button)
	button.MouseEnter:Connect(function()
		UIKit.Tween(scale, 0.12, { Scale = 1.04 })
	end)
	button.MouseLeave:Connect(function()
		UIKit.Tween(scale, 0.12, { Scale = 1 })
	end)
	button.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			UIKit.Tween(scale, 0.08, { Scale = 0.93 })
		end
	end)
	button.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			UIKit.Tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end)
	button.Activated:Connect(function()
		UIKit.ButtonClicked:Fire()
		if props.OnClick then
			props.OnClick()
		end
	end)

	if props.Parent then
		button.Parent = props.Parent
	end
	return button
end

export type Window = {
	Overlay: TextButton,
	Frame: Frame,
	Content: Frame,
	IsOpen: boolean,
	Opened: any,
	Closed: any,
	Open: (self: Window) -> (),
	Close: (self: Window) -> (),
}

-- Modal window. Clicking the dimmed backdrop or the X closes it.
function UIKit.Window(
	parent: Instance,
	opts: { Name: string, Title: string, Icon: string?, Size: UDim2?, Accent: Color3? }
): Window
	local accent = opts.Accent or Theme.Accent

	local overlay: TextButton = UIKit.Create("TextButton", {
		Name = opts.Name,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		Visible = false,
		ZIndex = 20,
		Parent = parent,
	})

	local frame: Frame = UIKit.Create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = opts.Size or UDim2.fromOffset(640, 460),
		BackgroundColor3 = Theme.Panel,
		Active = true,
		Corner = 18,
		Stroke = { Color = Theme.Stroke, Thickness = 1.5, Transparency = 0.1 },
		Parent = overlay,
	})

	-- Accent bar along the top edge.
	UIKit.Create("Frame", {
		Name = "Accent",
		Size = UDim2.new(1, -36, 0, 3),
		Position = UDim2.fromOffset(18, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Gradient = { Color = { accent, Theme.Accent2 }, Rotation = 0 },
		Corner = 2,
		Parent = frame,
	})

	UIKit.Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -90, 0, 40),
		Position = UDim2.fromOffset(20, 12),
		Text = (if opts.Icon then opts.Icon .. "  " else "") .. opts.Title,
		TextSize = 28,
		FontFace = UIKit.Fonts.Heavy,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})

	local content: Frame = UIKit.Create("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(0, 60),
		Size = UDim2.new(1, 0, 1, -60),
		BackgroundTransparency = 1,
		Padding = { Top = 4, Bottom = 16, Left = 18, Right = 18 },
		Parent = frame,
	})

	local window = {
		Overlay = overlay,
		Frame = frame,
		Content = content,
		IsOpen = false,
		Opened = Signal.new(),
		Closed = Signal.new(),
	} :: any

	local scale = UIKit.GetScale(frame)

	function window:Open()
		if self.IsOpen then
			return
		end
		self.IsOpen = true
		overlay.Visible = true
		scale.Scale = 0.86
		UIKit.Tween(overlay, 0.2, { BackgroundTransparency = 0.45 })
		UIKit.Tween(scale, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
		self.Opened:Fire()
	end

	function window:Close()
		if not self.IsOpen then
			return
		end
		self.IsOpen = false
		UIKit.Tween(overlay, 0.15, { BackgroundTransparency = 1 })
		UIKit.Tween(scale, 0.15, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.15, function()
			if not self.IsOpen then
				overlay.Visible = false
			end
		end)
		self.Closed:Fire()
	end

	UIKit.Button({
		Name = "Close",
		Text = "✕",
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.new(1, -14, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
		Color = Theme.Danger,
		TextSize = 22,
		Parent = frame,
		OnClick = function()
			window:Close()
		end,
	})

	overlay.Activated:Connect(function()
		window:Close()
	end)

	return window
end

export type ProgressBar = { Frame: Frame, Fill: Frame, Label: TextLabel, Set: (alpha: number, text: string?) -> () }

function UIKit.ProgressBar(
	parent: Instance,
	props: { Size: UDim2?, Position: UDim2?, Color: Color3?, LayoutOrder: number? }
): ProgressBar
	local frame: Frame = UIKit.Create("Frame", {
		Name = "Progress",
		Size = props.Size or UDim2.new(1, 0, 0, 18),
		Position = props.Position or UDim2.new(),
		BackgroundColor3 = Theme.Background,
		LayoutOrder = props.LayoutOrder or 0,
		Corner = 9,
		Stroke = { Color = Theme.Stroke, Thickness = 1, Transparency = 0.4 },
		Parent = parent,
	})
	local fill: Frame = UIKit.Create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Gradient = { Color = { props.Color or Theme.Accent, Theme.Accent2 }, Rotation = 0 },
		Corner = 9,
		Parent = frame,
	})
	local label: TextLabel = UIKit.Create("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextSize = 13,
		ZIndex = 2,
		Parent = frame,
	})
	UIKit.TextStroke(label, Color3.new(0, 0, 0), 1)

	return {
		Frame = frame,
		Fill = fill,
		Label = label,
		Set = function(alpha: number, text: string?)
			UIKit.Tween(fill, 0.25, { Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1) })
			if text then
				label.Text = text
			end
		end,
	}
end

export type Toggle = { Frame: Frame, Set: (value: boolean) -> () }

function UIKit.Toggle(
	parent: Instance,
	props: {
		Text: string,
		Description: string?,
		Value: boolean,
		LayoutOrder: number?,
		OnChanged: (boolean) -> (),
	}
): Toggle
	local row: Frame = UIKit.Create("Frame", {
		Name = props.Text,
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = Theme.PanelLight,
		LayoutOrder = props.LayoutOrder or 0,
		Corner = 12,
		Parent = parent,
	})
	UIKit.Create("TextLabel", {
		Size = UDim2.new(1, -110, 0, 26),
		Position = UDim2.fromOffset(16, if props.Description then 8 else 19),
		Text = props.Text,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	if props.Description then
		UIKit.Create("TextLabel", {
			Size = UDim2.new(1, -110, 0, 20),
			Position = UDim2.fromOffset(16, 34),
			Text = props.Description,
			TextSize = 14,
			FontFace = UIKit.Fonts.Regular,
			TextColor3 = Theme.SubText,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
	end

	local track: TextButton = UIKit.Create("TextButton", {
		Size = UDim2.fromOffset(68, 36),
		Position = UDim2.new(1, -16, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Text = "",
		BackgroundColor3 = Theme.Disabled,
		Corner = UDim.new(1, 0),
		Parent = row,
	})
	local knob: Frame = UIKit.Create("Frame", {
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.fromOffset(4, 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Corner = UDim.new(1, 0),
		Parent = track,
	})

	local value = props.Value
	local function render(animate: boolean)
		local goalPos = if value then UDim2.fromOffset(36, 4) else UDim2.fromOffset(4, 4)
		local goalColor = if value then Theme.Success else Theme.Disabled
		if animate then
			UIKit.Tween(knob, 0.18, { Position = goalPos })
			UIKit.Tween(track, 0.18, { BackgroundColor3 = goalColor })
		else
			knob.Position = goalPos
			track.BackgroundColor3 = goalColor
		end
	end
	render(false)

	track.Activated:Connect(function()
		value = not value
		render(true)
		UIKit.ButtonClicked:Fire()
		props.OnChanged(value)
	end)

	return {
		Frame = row,
		Set = function(newValue: boolean)
			if newValue ~= value then
				value = newValue
				render(true)
			end
		end,
	}
end

export type Tabs = { Bar: Frame, Select: (name: string) -> (), Selected: string }

-- Horizontal tab strip. onSelect(name) fires when a tab is picked.
function UIKit.Tabs(
	parent: Instance,
	props: { Names: { string }, Position: UDim2?, Size: UDim2?, OnSelect: (string) -> () }
): Tabs
	local bar: Frame = UIKit.Create("Frame", {
		Name = "Tabs",
		Size = props.Size or UDim2.new(1, 0, 0, 40),
		Position = props.Position or UDim2.new(),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UIKit.List(bar, { Direction = Enum.FillDirection.Horizontal, Padding = 8 })

	local buttons: { [string]: TextButton } = {}
	local tabs = { Bar = bar, Selected = "" } :: any

	function tabs.Select(name: string)
		tabs.Selected = name
		for tabName, button in buttons do
			local active = tabName == name
			UIKit.Tween(button, 0.15, {
				BackgroundColor3 = if active then Theme.Accent else Theme.PanelLight,
				TextColor3 = if active then Theme.Text else Theme.SubText,
			})
		end
		props.OnSelect(name)
	end

	for index, name in props.Names do
		local button: TextButton = UIKit.Create("TextButton", {
			Name = name,
			Size = UDim2.new(0, 140, 1, 0),
			Text = name,
			TextSize = 18,
			BackgroundColor3 = Theme.PanelLight,
			TextColor3 = Theme.SubText,
			LayoutOrder = index,
			Corner = 10,
			Parent = bar,
		})
		button.Activated:Connect(function()
			UIKit.ButtonClicked:Fire()
			tabs.Select(name)
		end)
		buttons[name] = button
	end

	return tabs
end

return UIKit
