--[[
	InventoryService — equipping auras, the visible aura on the character and
	index (collection) completion rewards.

	Aura visuals: the highest-rarity equipped item is shown on the character.
	If the item has a Model and ReplicatedStorage.AuraModels.<Model> exists, its
	children are cloned into the HumanoidRootPart. Otherwise a particle aura is
	generated from the item colour and the tier's AuraRate.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local Formulas = require(Modules.Formulas)
local RarityTable = require(Modules.RarityTable)
local Util = require(Modules.Util)
local Net = require(Modules.Net)

local InventoryService = {}

local Services
local DataService

local AURA_FOLDER = "AuraFX"

local function getSlots(player: Player): number
	return DataService:GetLive(player, "EquipSlots")
		or Formulas.EquipSlots(Services.MonetizationService:OwnsPass(player, "ExtraSlots"))
end

---------------------------------------------------------------------------
-- Aura visuals
---------------------------------------------------------------------------
local function bestEquipped(data): RarityTable.Item?
	local best, bestTier = nil, 0
	for _, name in data.Equipped do
		local item = Formulas.GetItem(name)
		if item then
			local tier = Formulas.ItemTierIndex(item)
			if tier > bestTier then
				best, bestTier = item, tier
			end
		end
	end
	return best
end

local function buildGeneratedAura(item: RarityTable.Item, parent: Instance)
	local tierIndex = Formulas.ItemTierIndex(item)
	local tier = Formulas.GetTier(tierIndex)

	local attachment = Instance.new("Attachment")
	attachment.Name = "AuraAttachment"
	attachment.Parent = parent

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Aura"
	emitter.Color = ColorSequence.new(Util.Shade(item.Color, 0.35), item.Color)
	emitter.LightEmission = 0.8
	emitter.LightInfluence = 0
	emitter.Rate = tier.AuraRate
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Speed = NumberRange.new(1, 3 + tierIndex * 0.4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25 + tierIndex * 0.04),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Shape = Enum.ParticleEmitterShape.Sphere
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface

	local texture, sparkleTexture = Formulas.TierTextures(tierIndex)
	if texture then
		emitter.Texture = texture
		emitter.LightEmission = 1 -- the texture's black background becomes invisible
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-40, 40)
	end
	emitter.Parent = attachment

	-- Optional twinkle layer: small particles that pop in and out.
	if sparkleTexture then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "AuraSparkles"
		sparkles.Texture = sparkleTexture
		sparkles.Color = ColorSequence.new(Color3.new(1, 1, 1), item.Color)
		sparkles.LightEmission = 1
		sparkles.LightInfluence = 0
		sparkles.Rate = math.max(2, tier.AuraRate * 0.4)
		sparkles.Lifetime = NumberRange.new(0.4, 0.9)
		sparkles.Speed = NumberRange.new(0.5, 2)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Rotation = NumberRange.new(0, 360)
		sparkles.RotSpeed = NumberRange.new(-90, 90)
		sparkles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.2 + tierIndex * 0.03),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkles.Shape = Enum.ParticleEmitterShape.Sphere
		sparkles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		sparkles.Parent = attachment
	end

	if tierIndex >= 4 then
		local light = Instance.new("PointLight")
		light.Color = item.Color
		light.Range = 6 + tierIndex
		light.Brightness = 1 + tierIndex * 0.15
		light.Parent = attachment
	end
end

function InventoryService:RefreshAura(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	-- Remove the previous aura (attachments sit directly under the root part).
	for _, child in root:GetChildren() do
		if child.Name == AURA_FOLDER or child:GetAttribute("AuraFX") then
			child:Destroy()
		end
	end

	local data = DataService:GetData(player)
	if not data then
		return
	end
	local item = bestEquipped(data)
	if not item then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = AURA_FOLDER

	local models = ReplicatedStorage:FindFirstChild("AuraModels")
	local custom = item.Model and models and models:FindFirstChild(item.Model)
	if custom then
		for _, child in custom:GetChildren() do
			child:Clone().Parent = folder
		end
		-- Attachments must live directly in the part to render; move them out of the folder.
		for _, child in folder:GetChildren() do
			if child:IsA("Attachment") then
				child.Parent = root
				child:SetAttribute("AuraFX", true)
			end
		end
	else
		buildGeneratedAura(item, root)
		local attachment = root:FindFirstChild("AuraAttachment")
		if attachment then
			attachment:SetAttribute("AuraFX", true)
		end
	end
	folder.Parent = root
end

local function refresh(player: Player)
	InventoryService:RefreshAura(player)
	Services.EconomyService:RecomputeStats(player)
end

---------------------------------------------------------------------------
-- Equip / unequip
---------------------------------------------------------------------------
local function sanitizeEquipped(player: Player)
	local slots = getSlots(player)
	DataService:Update(player, "Equipped", function(data)
		local clean = {}
		for _, name in data.Equipped do
			if
				#clean < slots
				and Formulas.GetItem(name)
				and (data.Inventory[name] or 0) > 0
				and not table.find(clean, name)
			then
				table.insert(clean, name)
			end
		end
		data.Equipped = clean
	end)
end

function InventoryService:Equip(player: Player, itemName: any)
	if not Util.IsShortString(itemName) or not Formulas.GetItem(itemName) then
		return
	end
	local data = DataService:GetData(player)
	if not data or (data.Inventory[itemName] or 0) <= 0 or table.find(data.Equipped, itemName) then
		return
	end
	if #data.Equipped >= getSlots(player) then
		Services.EventService:Toast(
			player,
			"All equip slots are full. Unequip something first.",
			Color3.fromRGB(255, 190, 60)
		)
		return
	end
	DataService:Update(player, "Equipped", function(d)
		table.insert(d.Equipped, itemName)
	end)
	refresh(player)
end

function InventoryService:Unequip(player: Player, itemName: any)
	if not Util.IsShortString(itemName) then
		return
	end
	local data = DataService:GetData(player)
	local index = data and table.find(data.Equipped, itemName)
	if not index then
		return
	end
	DataService:Update(player, "Equipped", function(d)
		table.remove(d.Equipped, index)
	end)
	refresh(player)
end

-- Equips the owned items with the best luck bonus (ties broken by rarity).
function InventoryService:EquipBest(player: Player)
	local data = DataService:GetData(player)
	if not data then
		return
	end
	local owned = {}
	for name, count in data.Inventory do
		local item = Formulas.GetItem(name)
		if item and count > 0 then
			table.insert(owned, item)
		end
	end
	table.sort(owned, function(a, b)
		if a.LuckMultiplier ~= b.LuckMultiplier then
			return a.LuckMultiplier > b.LuckMultiplier
		end
		return Formulas.ItemTierIndex(a) > Formulas.ItemTierIndex(b)
	end)
	local slots = getSlots(player)
	DataService:Update(player, "Equipped", function(d)
		local list = {}
		for i = 1, math.min(slots, #owned) do
			list[i] = owned[i].Name
		end
		d.Equipped = list
	end)
	refresh(player)
end

---------------------------------------------------------------------------
-- Index completion
---------------------------------------------------------------------------
function InventoryService:IsTierComplete(data, tierIndex: number): boolean
	for _, item in Formulas.ItemsInTier(tierIndex) do
		if (data.Inventory[item.Name] or 0) <= 0 then
			return false
		end
	end
	return true
end

function InventoryService:ClaimIndex(player: Player, rarityName: any)
	if not Util.IsShortString(rarityName) then
		return
	end
	local tierIndex = Formulas.TierIndex(rarityName)
	local reward = Config.Index.Rewards[rarityName]
	local data = DataService:GetData(player)
	if not tierIndex or not reward or not data or data.IndexClaims[rarityName] then
		return
	end
	if not self:IsTierComplete(data, tierIndex) then
		Services.EventService:Toast(player, `Collect every {rarityName} aura first!`, Color3.fromRGB(255, 190, 60))
		return
	end
	DataService:Update(player, "IndexClaims", function(d)
		d.IndexClaims[rarityName] = true
	end)
	local text = Services.EconomyService:GrantReward(player, reward, "Index")
	Services.EventService:Notify(player, "Popup", {
		Title = `{rarityName} Index complete!`,
		Text = `You received {text}.`,
		Color = Formulas.GetTier(tierIndex).Color,
	})
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function InventoryService:Init(services)
	Services = services
	DataService = services.DataService
end

function InventoryService:Start()
	Net.Event("Equip").OnServerEvent:Connect(function(player, name)
		self:Equip(player, name)
	end)
	Net.Event("Unequip").OnServerEvent:Connect(function(player, name)
		self:Unequip(player, name)
	end)
	Net.Event("EquipBest").OnServerEvent:Connect(function(player)
		self:EquipBest(player)
	end)
	Net.Event("ClaimIndex").OnServerEvent:Connect(function(player, rarityName)
		self:ClaimIndex(player, rarityName)
	end)

	-- Slots are only known after passes load.
	Services.MonetizationService.PlayerReady:Connect(function(player)
		sanitizeEquipped(player)
		refresh(player)
	end)

	local function onCharacter(player: Player, character: Model)
		character:WaitForChild("HumanoidRootPart", 10)
		if DataService:IsLoaded(player) then
			self:RefreshAura(player)
		end
	end

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
end

return InventoryService
