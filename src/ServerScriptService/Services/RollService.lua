--[[
	RollService — the server-authoritative gacha roll.

	The client only ASKS to roll. The server checks: data loaded, cooldown
	(base/Fast Roll + the previous pull's cinematic time), and that the player
	can pay (coins, or a Lucky Token). Then it rolls with the player's final luck
	(computed server-side by EconomyService), saves the result and tells the
	client what to animate.

	Auto Roll (gamepass) runs on the server: once enabled, a per-player loop rolls
	whenever the cooldown allows, and stops itself when the player is broke.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local Formulas = require(Modules.Formulas)
local Signal = require(Modules.Signal)
local Util = require(Modules.Util)
local Net = require(Modules.Net)

local RollService = {}
RollService.Rolled = Signal.new() -- (player, item, tierIndex, isNew)

local Services
local DataService
local resultRemote: RemoteEvent

local rng = Random.new()
local nextRollAt: { [Player]: number } = {}
local autoRolling: { [Player]: boolean } = {}
local autoThreads: { [Player]: thread } = {}

local announceTier = Formulas.TierIndex(Config.Roll.AnnounceMinRarity) or math.huge

-- Returns ok, reason. Never yields, so two requests can't interleave.
function RollService:TryRoll(player: Player, useToken: boolean, isAuto: boolean): (boolean, string?)
	local data = DataService:GetData(player)
	if not data then
		return false, "Loading"
	end

	local now = os.clock()
	if now < (nextRollAt[player] or 0) - Config.Roll.CooldownTolerance then
		return false, "Cooldown"
	end

	local cost = Formulas.RollCost(data.Stats.TotalRolls)
	if useToken then
		if data.Currency.RerollTokens < 1 then
			return false, "NoTokens"
		end
	elseif data.Currency.Coins < cost then
		return false, "NoCoins"
	end

	local luck = DataService:GetLive(player, "Luck")
	if luck == nil then
		Services.EconomyService:RecomputeStats(player)
		luck = DataService:GetLive(player, "Luck") or Config.Luck.BaseLuck
	end
	if useToken then
		luck = math.min(luck * Config.Roll.RerollTokenLuck, Config.Luck.MaxLuck)
	end

	local item, tierIndex = Formulas.Roll(luck, rng)
	local isNew = (data.Inventory[item.Name] or 0) == 0

	DataService:Update(player, { "Currency", "Inventory", "Stats" }, function(d)
		if useToken then
			d.Currency.RerollTokens -= 1
		else
			d.Currency.Coins -= cost
		end
		d.Inventory[item.Name] = (d.Inventory[item.Name] or 0) + 1
		d.Stats.TotalRolls += 1
		if tierIndex > d.Stats.BestRarity then
			d.Stats.BestRarity = tierIndex
		end
	end)

	local payout = Services.EconomyService:AddCoins(player, item.Value, "Roll", true)
	local fast = Services.MonetizationService:OwnsPass(player, "FastRoll")
	nextRollAt[player] = now + Formulas.RollCooldown(fast, tierIndex)

	local baseChance = Formulas.ItemProbability(item.Name, Config.Luck.BaseLuck)
	resultRemote:FireClient(player, {
		Ok = true,
		Item = item.Name,
		Tier = tierIndex,
		Luck = luck,
		BaseChance = baseChance,
		IsNew = isNew,
		Count = data.Inventory[item.Name],
		Payout = payout,
		UsedToken = useToken,
		Auto = isAuto,
		Fast = fast,
	})

	self.Rolled:Fire(player, item, tierIndex, isNew)

	if tierIndex >= announceTier then
		local tier = Formulas.GetTier(tierIndex)
		Services.EventService:Announce(
			`✨ {player.DisplayName} rolled {item.Name} [{tier.Name}] — {Util.Odds(baseChance)}!`,
			tier.Color,
			tierIndex
		)
	end

	Services.EconomyService:RecomputeStats(player)
	return true, nil
end

---------------------------------------------------------------------------
-- Auto roll
---------------------------------------------------------------------------
local function autoLoop(player: Player)
	while autoRolling[player] and player.Parent do
		local waitFor = (nextRollAt[player] or 0) - os.clock()
		if waitFor > 0 then
			task.wait(waitFor)
		else
			local ok, reason = RollService:TryRoll(player, false, true)
			if not ok then
				if reason == "NoCoins" then
					RollService:SetAutoRoll(player, false)
					Services.EventService:Toast(player, "Auto Roll stopped — not enough coins.", Color3.fromRGB(255, 190, 60))
					break
				elseif reason == "Loading" then
					break
				end
				task.wait(0.1)
			end
		end
	end
	autoThreads[player] = nil
end

function RollService:SetAutoRoll(player: Player, enabled: boolean)
	if enabled and not Services.MonetizationService:OwnsPass(player, "AutoRoll") then
		enabled = false
	end
	if enabled then
		autoRolling[player] = true
	else
		autoRolling[player] = nil
	end
	DataService:SetLive(player, "AutoRoll", enabled)
	if enabled and not autoThreads[player] then
		autoThreads[player] = task.spawn(autoLoop, player)
	end
end

function RollService:IsAutoRolling(player: Player): boolean
	return autoRolling[player] == true
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function RollService:Init(services)
	Services = services
	DataService = services.DataService
	resultRemote = Net.Event("RollResult")
end

function RollService:Start()
	Net.Event("RollRequest").OnServerEvent:Connect(function(player, useToken)
		local ok, reason = self:TryRoll(player, useToken == true, false)
		if not ok then
			resultRemote:FireClient(player, { Ok = false, Reason = reason })
		end
	end)

	Net.Event("SetAutoRoll").OnServerEvent:Connect(function(player, enabled)
		if type(enabled) ~= "boolean" or not DataService:IsLoaded(player) then
			return
		end
		self:SetAutoRoll(player, enabled)
	end)

	DataService.ProfileLoaded:Connect(function(player)
		DataService:SetLive(player, "AutoRoll", false)
	end)

	Players.PlayerRemoving:Connect(function(player)
		autoRolling[player] = nil
		nextRollAt[player] = nil
		-- autoLoop exits on its own once autoRolling is cleared.
	end)
end

return RollService
