--[[
	RollReveal — the animated result overlay. Bigger rarity = bigger show:

	  spin        names flicker past, slowing down (Fast Roll shortens it)
	  build-up    Cinematic tiers: screen darkens, "???" pulses, rays spin, rumble
	  reveal      flash, name pops in rarity colour, rays + UI sparks, camera
	              shake, 3D particle burst on the character, colour grading
	              tint, tier sound
	  hold        result stays up until the next roll (or a short timeout)

	Every number comes from the tier entry in RarityTable (Shake, Particles,
	RevealTime, Cinematic, Sound) so rebalancing never touches this file.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local Formulas = require(Modules.Formulas)
local RarityTable = require(Modules.RarityTable)
local Util = require(Modules.Util)
local UIKit = require(script.Parent.UIKit)

local Theme = UIKit.Theme
local Create = UIKit.Create

local player = Players.LocalPlayer
local random = Random.new()

local RAY_COUNT = 12

local RollReveal = {}
RollReveal.__index = RollReveal

export type PlayOptions = {
	Shake: boolean,
	OnSpinDone: (() -> ())?,
	ShouldSkipHold: (() -> boolean)?,
}

function RollReveal.new(root: Instance, audio)
	local self = setmetatable({}, RollReveal)
	self.Audio = audio
	self.ShakeId = 0

	local overlay = Create("Frame", {
		Name = "RollReveal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 35,
		Parent = root,
	})
	self.Overlay = overlay

	-- Everything that shakes lives in Stage.
	local stage = Create("Frame", {
		Name = "Stage",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = overlay,
	})
	self.Stage = stage

	local center = UDim2.fromScale(0.5, 0.4)

	-- Rays
	local rays = Create("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center,
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Parent = stage,
	})
	for i = 1, RAY_COUNT do
		Create("Frame", {
			Name = "Ray",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 26, 1, 0),
			Rotation = (i - 1) * (180 / RAY_COUNT),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.6,
			Gradient = {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Rotation = 90,
			},
			Parent = rays,
		})
	end
	self.Rays = rays

	-- Glow rings
	self.Rings = {}
	for i = 1, 3 do
		local ring = Create("Frame", {
			Name = "Ring" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = center,
			Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1,
			Corner = UDim.new(1, 0),
			Parent = stage,
		})
		table.insert(self.Rings, ring)
	end

	self.NewBadge = Create("TextLabel", {
		Name = "New",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.4, -46),
		Size = UDim2.fromOffset(96, 28),
		BackgroundColor3 = Theme.Danger,
		BackgroundTransparency = 0,
		Text = "NEW!",
		TextSize = 18,
		FontFace = UIKit.Fonts.Heavy,
		Visible = false,
		Corner = UDim.new(1, 0),
		Parent = stage,
	})

	self.NameLabel = Create("TextLabel", {
		Name = "ItemName",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center,
		Size = UDim2.new(1, -40, 0, 84),
		Text = "",
		TextSize = 68,
		FontFace = UIKit.Fonts.Heavy,
		Parent = stage,
	})
	self.NameStroke = UIKit.TextStroke(self.NameLabel, Color3.new(0, 0, 0), 3)

	self.TierLabel = Create("TextLabel", {
		Name = "Tier",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.4, 44),
		Size = UDim2.new(1, -40, 0, 38),
		Text = "",
		TextSize = 32,
		FontFace = UIKit.Fonts.Heavy,
		Parent = stage,
	})
	UIKit.TextStroke(self.TierLabel, Color3.new(0, 0, 0), 2)
	self.TierGradient = UIKit.Gradient(self.TierLabel, { Color = { Color3.new(1, 1, 1), Color3.new(1, 1, 1) }, Rotation = 0 })

	self.OddsLabel = Create("TextLabel", {
		Name = "Odds",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.4, 84),
		Size = UDim2.new(1, -40, 0, 26),
		Text = "",
		TextSize = 21,
		Parent = stage,
	})
	UIKit.TextStroke(self.OddsLabel, Color3.new(0, 0, 0), 1.5)

	self.SparkLayer = Create("Frame", {
		Name = "Sparks",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = stage,
	})

	self.Flash = Create("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = overlay,
	})

	-- Compact result pill (Quick Reveals / catching up on auto-roll backlog)
	self.Compact = Create("TextLabel", {
		Name = "CompactResult",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -220),
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		Text = "",
		TextSize = 18,
		Visible = false,
		Corner = UDim.new(1, 0),
		Padding = { Left = 18, Right = 18 },
		Parent = root,
	})
	self.CompactStroke = UIKit.Stroke(self.Compact, Theme.Stroke, 2, 0)

	self.ColorCorrection = Instance.new("ColorCorrectionEffect")
	self.ColorCorrection.Name = "RevealTint"
	self.ColorCorrection.Parent = Lighting

	return self
end

---------------------------------------------------------------------------
-- Effects
---------------------------------------------------------------------------
function RollReveal:_shake(intensity: number, duration: number, cameraShake: boolean)
	if intensity <= 0 then
		return
	end
	self.ShakeId += 1
	local id = self.ShakeId
	local bindName = "RevealShake"
	local start = os.clock()
	pcall(RunService.UnbindFromRenderStep, RunService, bindName)
	RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 1, function()
		local elapsed = os.clock() - start
		if elapsed >= duration or id ~= self.ShakeId then
			self.Stage.Position = UDim2.new()
			RunService:UnbindFromRenderStep(bindName)
			return
		end
		local magnitude = intensity * (1 - elapsed / duration)
		self.Stage.Position = UDim2.fromOffset(random:NextNumber(-1, 1) * magnitude * 10, random:NextNumber(-1, 1) * magnitude * 10)
		local camera = Workspace.CurrentCamera
		if cameraShake and camera then
			camera.CFrame *= CFrame.Angles(
				math.rad(random:NextNumber(-1, 1) * magnitude * 1.2),
				math.rad(random:NextNumber(-1, 1) * magnitude * 1.2),
				math.rad(random:NextNumber(-1, 1) * magnitude * 0.6)
			)
		end
	end)
end

function RollReveal:_sparks(count: number, colors: { Color3 })
	for _ = 1, count do
		local size = random:NextInteger(6, 16)
		local spark = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.4),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = colors[random:NextInteger(1, #colors)],
			Corner = UDim.new(1, 0),
			Parent = self.SparkLayer,
		})
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(140, 480)
		local duration = random:NextNumber(0.6, 1.3)
		UIKit.Tween(spark, duration, {
			Position = UDim2.new(0.5, math.cos(angle) * distance, 0.4, math.sin(angle) * distance * 0.7),
			Size = UDim2.fromOffset(2, 2),
			BackgroundTransparency = 1,
		}, Enum.EasingStyle.Quart)
		task.delay(duration, function()
			spark:Destroy()
		end)
	end
end

function RollReveal:_burst3D(color: Color3, count: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "RevealBurst"
	attachment.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Util.Shade(color, 0.5), color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Lifetime = NumberRange.new(0.6, 1.4)
	emitter.Speed = NumberRange.new(12, 28)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 4
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(count)
	task.delay(2, function()
		attachment:Destroy()
	end)
end

function RollReveal:_spinRays(active: boolean)
	self.RaysActive = active
	if active and not self.RaysThread then
		self.RaysThread = task.spawn(function()
			while self.RaysActive do
				self.Rays.Rotation += task.wait() * 25
			end
			self.RaysThread = nil
		end)
	end
end

function RollReveal:_reset()
	self.NameLabel.Text = ""
	self.TierLabel.Text = ""
	self.OddsLabel.Text = ""
	self.NewBadge.Visible = false
	self.Rays.Size = UDim2.fromOffset(0, 0)
	for _, ring in self.Rings do
		ring.Size = UDim2.fromOffset(0, 0)
		ring.BackgroundTransparency = 1
	end
	self.NameLabel.TextTransparency = 0
	self.TierLabel.TextTransparency = 0
	self.OddsLabel.TextTransparency = 0
	self.Stage.Position = UDim2.new()
end

---------------------------------------------------------------------------
-- Compact result
---------------------------------------------------------------------------
function RollReveal:ShowCompact(result)
	local item = Formulas.GetItem(result.Item)
	local tier = Formulas.GetTier(result.Tier)
	if not item then
		return
	end
	self.Compact.Text = `{if result.IsNew then "🆕 " else ""}<font color="#{tier.Color:ToHex()}">{item.Name}</font>  ·  {tier.Name}  ·  {Util.Odds(result.BaseChance)}`
	self.CompactStroke.Color = tier.Color
	self.Compact.Visible = true
	UIKit.Pop(self.Compact, 0.85)
	self.CompactToken = (self.CompactToken or 0) + 1
	local token = self.CompactToken
	self.Audio:Play("RevealSmall", 0.6)
	task.delay(1.6, function()
		if self.CompactToken == token then
			self.Compact.Visible = false
		end
	end)
end

---------------------------------------------------------------------------
-- Full reveal (yields until finished)
---------------------------------------------------------------------------
function RollReveal:Play(result, options: PlayOptions)
	local item = Formulas.GetItem(result.Item)
	if not item then
		return
	end
	local tierIndex = result.Tier
	local tier = Formulas.GetTier(tierIndex)
	local fast = result.Fast == true

	self:_reset()
	self.Overlay.Visible = true
	self.Compact.Visible = false
	UIKit.Tween(self.Overlay, 0.15, { BackgroundTransparency = 0.6 })

	-- 1) Spin
	local spinTime = if fast then Config.Roll.FastAnimationTime else Config.Roll.AnimationTime
	local elapsed = 0
	while elapsed < spinTime do
		local decoy = RarityTable.Items[random:NextInteger(1, #RarityTable.Items)]
		local decoyTier = Formulas.GetTier(Formulas.ItemTierIndex(decoy))
		self.NameLabel.Text = decoy.Name
		self.NameLabel.TextColor3 = decoyTier.Color
		self.Audio:Play("Tick", 0.35, 0.9 + elapsed / spinTime * 0.5)
		local progress = elapsed / spinTime
		elapsed += task.wait(0.035 + 0.16 * progress * progress)
	end

	-- 2) Build-up for slow tiers
	local extra = tier.RevealTime * (if fast then Config.Roll.FastCinematicScale else 1)
	if extra > 0 then
		self.NameLabel.Text = if tier.Cinematic then "???" else "..."
		self.NameLabel.TextColor3 = tier.Color
		self.Audio:Play("Whoosh")
		if tier.Cinematic then
			UIKit.Tween(self.Overlay, extra * 0.5, { BackgroundTransparency = 0.08 })
			self.Rays.Size = UDim2.fromOffset(0, 0)
			for _, ray in self.Rays:GetChildren() do
				if ray:IsA("Frame") then
					ray.BackgroundColor3 = tier.Color
				end
			end
			UIKit.Tween(self.Rays, extra, { Size = UDim2.fromOffset(260, 260) })
			self:_spinRays(true)
			self:_shake(tier.Shake * 0.35, extra, options.Shake)
		end
		local pulses = math.max(1, math.floor(extra / 0.45))
		for i = 1, pulses do
			local ring = self.Rings[(i - 1) % #self.Rings + 1]
			ring.BackgroundColor3 = tier.Color
			ring.Size = UDim2.fromOffset(40, 40)
			ring.BackgroundTransparency = 0.3
			UIKit.Tween(ring, 0.5, { Size = UDim2.fromOffset(340, 340), BackgroundTransparency = 1 })
			UIKit.Pop(self.NameLabel, 0.8)
			task.wait(extra / pulses)
		end
	end

	-- 3) Reveal
	if options.OnSpinDone then
		options.OnSpinDone()
	end
	self.NameLabel.Text = item.Name
	self.NameLabel.TextColor3 = Util.Shade(item.Color, 0.15)
	self.NameStroke.Color = Util.Shade(tier.Color, -0.6)
	self.TierLabel.Text = tier.Name:upper()
	self.TierGradient.Color = ColorSequence.new(Util.Shade(tier.Color, 0.45), tier.Color)
	local luckText = if result.Luck and result.Luck > 1.001 then `  ·  🍀 x{string.format("%.2f", result.Luck)}` else ""
	local payoutText = if result.Payout and result.Payout > 0 then `  ·  +{Util.Abbreviate(result.Payout)} 🪙` else ""
	self.OddsLabel.Text = Util.Odds(result.BaseChance) .. luckText .. payoutText
	self.NewBadge.Visible = result.IsNew == true

	UIKit.Pop(self.NameLabel, if tierIndex >= 5 then 1.9 else 1.35)
	UIKit.Pop(self.TierLabel, 0.6)
	if result.IsNew then
		UIKit.Pop(self.NewBadge, 0.4)
	end

	if tierIndex >= 3 then
		self.Flash.BackgroundTransparency = if tierIndex >= 6 then 0 else 0.5
		UIKit.Tween(self.Flash, 0.6, { BackgroundTransparency = 1 })
	end
	if tierIndex >= 4 then
		for _, ray in self.Rays:GetChildren() do
			if ray:IsA("Frame") then
				ray.BackgroundColor3 = tier.Color
			end
		end
		UIKit.Tween(self.Rays, 0.5, { Size = UDim2.fromOffset(300 + tierIndex * 40, 300 + tierIndex * 40) }, Enum.EasingStyle.Back)
		self:_spinRays(true)
	end
	for i, ring in self.Rings do
		ring.BackgroundColor3 = tier.Color
		ring.Size = UDim2.fromOffset(60, 60)
		ring.BackgroundTransparency = 0.25
		UIKit.Tween(ring, 0.5 + i * 0.25, {
			Size = UDim2.fromOffset(260 + tierIndex * 50 * i, 260 + tierIndex * 50 * i),
			BackgroundTransparency = 1,
		})
	end

	self:_sparks(tier.Particles, { tier.Color, item.Color, Color3.new(1, 1, 1) })
	self:_burst3D(tier.Color, tier.Particles)
	self:_shake(tier.Shake, 0.35 + tier.Shake * 0.5, options.Shake)

	if tierIndex >= 5 then
		self.ColorCorrection.TintColor = tier.Color:Lerp(Color3.new(1, 1, 1), 0.55)
		self.ColorCorrection.Brightness = 0.12
		self.ColorCorrection.Saturation = 0.25
		UIKit.Tween(self.ColorCorrection, 1.8, {
			TintColor = Color3.new(1, 1, 1),
			Brightness = 0,
			Saturation = 0,
		})
	end

	self.Audio:Play(tier.Sound)
	if tierIndex >= 4 and tier.Sound ~= "Fanfare" then
		self.Audio:Play("Fanfare")
	end

	-- 4) Hold
	local hold = 0.7 + math.max(0, tierIndex - 3) * 0.45
	local minimumHold = if tierIndex >= 5 then 1.2 else 0.25
	local held = 0
	while held < hold do
		if held >= minimumHold and options.ShouldSkipHold and options.ShouldSkipHold() then
			break
		end
		held += task.wait()
	end

	-- 5) Out
	self:_spinRays(false)
	UIKit.Tween(self.Overlay, 0.2, { BackgroundTransparency = 1 })
	UIKit.Tween(self.NameLabel, 0.2, { TextTransparency = 1 })
	UIKit.Tween(self.TierLabel, 0.2, { TextTransparency = 1 })
	UIKit.Tween(self.OddsLabel, 0.2, { TextTransparency = 1 })
	UIKit.Tween(self.Rays, 0.2, { Size = UDim2.fromOffset(0, 0) })
	task.wait(0.2)
	self.Overlay.Visible = false
	self.NewBadge.Visible = false
end

return RollReveal
