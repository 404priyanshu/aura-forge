--[[
	EconomyService — currencies, rewards, multipliers and the grind loops.

	  * Click-to-earn (token-bucket rate limited)
	  * AFK zone (server checks the character is inside the zone part every second)
	  * Playtime tracking, timed boost countdown, offline earnings on join
	  * RecomputeStats: the single place that turns data + passes + events into
	    the player's final Luck / CoinMultiplier / RollCost / Slots (Live state)
	  * GrantReward: shared by quests, daily, playtime, index, tutorial, admin
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local Formulas = require(Modules.Formulas)
local Signal = require(Modules.Signal)
local Util = require(Modules.Util)
local Net = require(Modules.Net)

local EconomyService = {}
EconomyService.Clicked = Signal.new() -- (player)
EconomyService.CoinsEarned = Signal.new() -- (player, amount, source)
EconomyService.PlaytimeTick = Signal.new() -- (player, seconds)
EconomyService.AfkTick = Signal.new() -- (player, seconds)

local Services
local DataService

local clickBuckets: { [Player]: { Tokens: number, Last: number, Strikes: number } } = {}
local afkSeconds: { [Player]: number } = {} -- continuous seconds inside the zone
local offlineFrom: { [Player]: number } = {}
local afkZone: BasePart

---------------------------------------------------------------------------
-- Currency primitives
---------------------------------------------------------------------------

-- Adds coins. Unless `raw`, the player's coin multiplier is applied. Returns the amount added.
function EconomyService:AddCoins(player: Player, amount: number, source: string, raw: boolean?): number
	local multiplier = if raw then 1 else (DataService:GetLive(player, "CoinMultiplier") or 1)
	local gained = math.floor(amount * multiplier)
	if gained <= 0 then
		return 0
	end
	local ok = DataService:Update(player, { "Currency", "Stats" }, function(data)
		data.Currency.Coins += gained
		data.Stats.CoinsEarned += gained
	end)
	if not ok then
		return 0
	end
	self.CoinsEarned:Fire(player, gained, source)
	return gained
end

function EconomyService:SpendCoins(player: Player, amount: number): boolean
	local data = DataService:GetData(player)
	if not data or amount < 0 or data.Currency.Coins < amount then
		return false
	end
	return DataService:Update(player, "Currency", function(d)
		d.Currency.Coins -= amount
	end)
end

function EconomyService:AddGems(player: Player, amount: number): number
	local gained = math.floor(amount)
	if gained <= 0 then
		return 0
	end
	DataService:Update(player, "Currency", function(data)
		data.Currency.Gems += gained
	end)
	return gained
end

function EconomyService:SpendGems(player: Player, amount: number): boolean
	local data = DataService:GetData(player)
	if not data or amount < 0 or data.Currency.Gems < amount then
		return false
	end
	return DataService:Update(player, "Currency", function(d)
		d.Currency.Gems -= amount
	end)
end

function EconomyService:AddRerollTokens(player: Player, amount: number)
	DataService:Update(player, "Currency", function(data)
		data.Currency.RerollTokens = math.max(0, data.Currency.RerollTokens + math.floor(amount))
	end)
end

function EconomyService:AddBoost(player: Player, boostId: string, seconds: number): boolean
	local boost = Config.Boosts[boostId]
	if not boost or seconds <= 0 then
		return false
	end
	local ok = DataService:Update(player, "Boosts", function(data)
		local current = data.Boosts[boostId] or 0
		data.Boosts[boostId] = math.min(current + seconds, boost.MaxStackSeconds)
	end)
	if ok then
		self:RecomputeStats(player)
	end
	return ok
end

-- Grants any Config.Reward. Coins in rewards are flat (no multiplier).
function EconomyService:GrantReward(player: Player, reward: Config.Reward, source: string): string
	if reward.Coins then
		self:AddCoins(player, reward.Coins, source, true)
	end
	if reward.Gems then
		self:AddGems(player, reward.Gems)
	end
	if reward.RerollTokens then
		self:AddRerollTokens(player, reward.RerollTokens)
	end
	if reward.Luck then
		DataService:Update(player, "Stats", function(data)
			data.Stats.Luck += reward.Luck
		end)
	end
	if reward.Boost then
		self:AddBoost(player, reward.Boost.Id, reward.Boost.Duration)
	end
	self:RecomputeStats(player)
	return Formulas.DescribeReward(reward, Util.Commas)
end

---------------------------------------------------------------------------
-- Derived stats (Live)
---------------------------------------------------------------------------
function EconomyService:RecomputeStats(player: Player)
	local data = DataService:GetData(player)
	if not data then
		return
	end
	local passes = Services.MonetizationService:GetOwnedPasses(player)

	local luck, breakdown = Formulas.ComputeLuck({
		BonusLuck = data.Stats.Luck,
		Equipped = data.Equipped,
		HasLuckPass = passes.LuckX2 == true,
		Boosts = data.Boosts,
		LuckHour = Services.EventService:IsLuckHour(),
		AdminLuck = DataService:GetLive(player, "AdminLuck"),
	})
	local coinMultiplier = Formulas.ComputeCoinMultiplier({
		Equipped = data.Equipped,
		IsVIP = passes.VIP == true,
		Boosts = data.Boosts,
	})

	DataService:SetLive(player, "Luck", luck)
	DataService:SetLive(player, "LuckBreakdown", breakdown)
	DataService:SetLive(player, "CoinMultiplier", coinMultiplier)
	DataService:SetLive(player, "RollCost", Formulas.RollCost(data.Stats.TotalRolls))
	DataService:SetLive(player, "RollCooldown", Formulas.RollCooldown(passes.FastRoll == true))
	DataService:SetLive(player, "FastRoll", passes.FastRoll == true)
	DataService:SetLive(player, "EquipSlots", Formulas.EquipSlots(passes.ExtraSlots == true))
	DataService:SetLive(player, "ClickReward", Formulas.ClickReward(data.Stats.TotalRolls))
	DataService:SetLive(player, "Passes", table.clone(passes))
end

---------------------------------------------------------------------------
-- Click to earn
---------------------------------------------------------------------------
local function onClick(player: Player)
	local data = DataService:GetData(player)
	if not data then
		return
	end

	local now = os.clock()
	local bucket = clickBuckets[player]
	if not bucket then
		bucket = { Tokens = Config.Click.MaxBurst, Last = now, Strikes = 0 }
		clickBuckets[player] = bucket
	end
	bucket.Tokens = math.min(Config.Click.MaxBurst, bucket.Tokens + (now - bucket.Last) * Config.Click.MaxClicksPerSecond)
	bucket.Last = now
	if bucket.Tokens < 1 then
		bucket.Strikes += 1
		if bucket.Strikes == 200 then
			warn(`[EconomyService] {player.Name} is clicking faster than allowed (autoclicker?)`)
		end
		return
	end
	bucket.Tokens -= 1

	DataService:Update(player, "Stats", function(d)
		d.Stats.Clicks += 1
	end)
	EconomyService:AddCoins(player, Formulas.ClickReward(data.Stats.TotalRolls), "Click")
	EconomyService.Clicked:Fire(player)
end

---------------------------------------------------------------------------
-- AFK zone
---------------------------------------------------------------------------
local function buildAfkZone(): BasePart
	local existing = Workspace:FindFirstChild(Config.AFK.ZoneName)
	if existing and existing:IsA("BasePart") then
		existing.Anchored = true
		existing.CanCollide = false
		return existing
	end

	local zone = Instance.new("Part")
	zone.Name = Config.AFK.ZoneName
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.CastShadow = false
	zone.Size = Config.AFK.ZoneSize
	zone.Position = Config.AFK.ZonePosition
	zone.Material = Enum.Material.ForceField
	zone.Color = Color3.fromRGB(110, 90, 255)
	zone.Transparency = 0.2

	local pad = Instance.new("Part")
	pad.Name = "AFKPad"
	pad.Anchored = true
	pad.Size = Vector3.new(Config.AFK.ZoneSize.X, 0.4, Config.AFK.ZoneSize.Z)
	pad.Position = Config.AFK.ZonePosition - Vector3.new(0, Config.AFK.ZoneSize.Y / 2 - 0.2, 0)
	pad.Material = Enum.Material.Neon
	pad.Color = Color3.fromRGB(80, 60, 200)
	pad.Parent = zone

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(140, 120, 255)
	light.Range = 24
	light.Brightness = 2
	light.Parent = pad

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(260, 70)
	billboard.StudsOffset = Vector3.new(0, Config.AFK.ZoneSize.Y / 2 + 3, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 150
	billboard.Parent = zone

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Heavy)
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.Text = `💤 AFK ZONE\n+{Config.AFK.CoinsPerSecond} coins/sec`
	label.Parent = billboard

	zone.Parent = Workspace
	return zone
end

function EconomyService:IsInAfkZone(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local relative = afkZone.CFrame:PointToObjectSpace((root :: BasePart).Position)
	local half = afkZone.Size / 2
	return math.abs(relative.X) <= half.X and math.abs(relative.Z) <= half.Z and relative.Y >= -half.Y - 1 and relative.Y <= half.Y + 4
end

---------------------------------------------------------------------------
-- 1 Hz tick: playtime, AFK income, boost countdown, LastOnline
---------------------------------------------------------------------------
local function tickPlayer(player: Player, now: number)
	local data = DataService:GetData(player)
	if not data then
		return
	end

	data.Stats.Playtime += 1
	data.LastOnline = now
	EconomyService.PlaytimeTick:Fire(player, 1)

	-- AFK zone
	if EconomyService:IsInAfkZone(player) then
		local seconds = (afkSeconds[player] or 0) + 1
		afkSeconds[player] = seconds
		player:SetAttribute("InAFKZone", seconds >= Config.AFK.WarmupSeconds)
		if seconds >= Config.AFK.WarmupSeconds then
			EconomyService:AddCoins(player, Config.AFK.CoinsPerSecond, "AFK")
			data.Stats.AfkTime += 1
			EconomyService.AfkTick:Fire(player, 1)
			if (seconds - Config.AFK.WarmupSeconds) > 0 and (seconds - Config.AFK.WarmupSeconds) % Config.AFK.GemInterval == 0 then
				EconomyService:AddGems(player, Config.AFK.GemsPerInterval)
				Services.EventService:Toast(player, `💎 +{Config.AFK.GemsPerInterval} Gem for staying AFK!`, Config.Currencies.Gems.Color)
			end
		end
	else
		afkSeconds[player] = 0
		player:SetAttribute("InAFKZone", false)
	end

	-- Boost countdown (only while online)
	local expired = {}
	for boostId, remaining in data.Boosts do
		if remaining <= 1 then
			table.insert(expired, boostId)
		else
			data.Boosts[boostId] = remaining - 1
		end
	end
	for _, boostId in expired do
		data.Boosts[boostId] = nil
		local boost = Config.Boosts[boostId]
		Services.EventService:Toast(player, `{boost and boost.DisplayName or boostId} has worn off.`)
	end

	DataService:Update(player, { "Stats", "Boosts" })
	if #expired > 0 then
		EconomyService:RecomputeStats(player)
	end
end

---------------------------------------------------------------------------
-- Offline earnings
---------------------------------------------------------------------------
local function grantOfflineEarnings(player: Player)
	local lastOnline = offlineFrom[player]
	offlineFrom[player] = nil
	if not Config.Offline.Enabled or not lastOnline or lastOnline <= 0 then
		return
	end
	local away = os.time() - lastOnline
	if away < Config.Offline.MinSeconds then
		return
	end
	local counted = math.min(away, Config.Offline.MaxSeconds)
	local passes = Services.MonetizationService:GetOwnedPasses(player)
	local multiplier = if passes.VIP then Config.VIP.CoinMultiplier else 1
	local amount = math.floor(counted * Config.Offline.CoinsPerSecond * multiplier)
	if amount <= 0 then
		return
	end
	EconomyService:AddCoins(player, amount, "Offline", true)
	Services.EventService:Notify(player, "Offline", {
		Seconds = counted,
		Away = away,
		Capped = away > Config.Offline.MaxSeconds,
		Amount = amount,
	})
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function EconomyService:Init(services)
	Services = services
	DataService = services.DataService
end

function EconomyService:Start()
	afkZone = buildAfkZone()

	Net.Event("Click").OnServerEvent:Connect(onClick)

	DataService.ProfileLoaded:Connect(function(player, data)
		-- Capture before the tick loop overwrites LastOnline.
		offlineFrom[player] = data.LastOnline
	end)

	Services.MonetizationService.PlayerReady:Connect(function(player)
		self:RecomputeStats(player)
		grantOfflineEarnings(player)
	end)

	Services.EventService.LuckHourChanged:Connect(function()
		for _, player in DataService:GetLoadedPlayers() do
			self:RecomputeStats(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		clickBuckets[player] = nil
		afkSeconds[player] = nil
		offlineFrom[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for _, player in DataService:GetLoadedPlayers() do
				local ok, err = pcall(tickPlayer, player, now)
				if not ok then
					warn("[EconomyService] tick error:", err)
				end
			end
		end
	end)
end

return EconomyService
