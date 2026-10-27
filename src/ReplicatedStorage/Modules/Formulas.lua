--!strict
--[[
	Formulas — the game's math, shared so the server (authoritative) and the
	client (display only) always agree: roll odds with luck, the weighted roll
	itself, roll cost, luck/coin multiplier stacking, quest scaling.

	Change NUMBERS in Config / RarityTable; change this file only to change the
	SHAPE of a formula.
]]

local Config = require(script.Parent.Config)
local RarityTable = require(script.Parent.RarityTable)

type Item = RarityTable.Item
type Tier = RarityTable.Tier

local Formulas = {}

---------------------------------------------------------------------------
-- Lookups (built once)
---------------------------------------------------------------------------
local tierIndexByName: { [string]: number } = {}
local itemsByName: { [string]: Item } = {}
local itemsByTier: { [number]: { Item } } = {}
local tierWeightTotals: { [number]: number } = {}

for index, tier in RarityTable.Tiers do
	tierIndexByName[tier.Name] = index
	itemsByTier[index] = {}
	tierWeightTotals[index] = 0
end

for _, item in RarityTable.Items do
	local tierIndex = tierIndexByName[item.Rarity]
	assert(tierIndex, `RarityTable item "{item.Name}" has unknown rarity "{item.Rarity}"`)
	assert(itemsByName[item.Name] == nil, `RarityTable has duplicate item name "{item.Name}"`)
	itemsByName[item.Name] = item
	table.insert(itemsByTier[tierIndex], item)
	tierWeightTotals[tierIndex] += item.Weight
end

for index, tier in RarityTable.Tiers do
	assert(#itemsByTier[index] > 0, `Rarity tier "{tier.Name}" has no items`)
end

function Formulas.GetTier(index: number): Tier
	return RarityTable.Tiers[index]
end

function Formulas.TierIndex(rarityName: string): number?
	return tierIndexByName[rarityName]
end

function Formulas.GetItem(name: string): Item?
	return itemsByName[name]
end

function Formulas.ItemTierIndex(item: Item): number
	return tierIndexByName[item.Rarity]
end

function Formulas.ItemsInTier(index: number): { Item }
	return itemsByTier[index] or {}
end

function Formulas.TierCount(): number
	return #RarityTable.Tiers
end

---------------------------------------------------------------------------
-- Odds
---------------------------------------------------------------------------

-- Probability of each tier at the given luck.
-- Every tier above the first has chance (1 / Chance) * luck ^ LuckExponent, so at
-- 1x luck the odds are EXACTLY the "1 in Chance" written in RarityTable. The first
-- tier (Common) takes whatever probability is left, which is how luck "reduces"
-- commons. If luck pushes the rarer tiers past 100% combined, they're normalised
-- and Common drops to 0.
function Formulas.GetTierProbabilities(luck: number): { number }
	local safeLuck = math.max(luck, 0.01)
	local tiers = RarityTable.Tiers
	local weights = table.create(#tiers, 0)
	local rareTotal = 0
	for index = 2, #tiers do
		local tier = tiers[index]
		local weight = (1 / tier.Chance) * safeLuck ^ tier.LuckExponent
		weights[index] = weight
		rareTotal += weight
	end
	weights[1] = math.max(0, 1 - rareTotal)
	local total = weights[1] + rareTotal
	for index = 1, #weights do
		weights[index] /= total
	end
	return weights
end

-- Chance of pulling one specific item at the given luck (0..1).
function Formulas.ItemProbability(itemName: string, luck: number): number
	local item = itemsByName[itemName]
	if not item then
		return 0
	end
	local tierIndex = tierIndexByName[item.Rarity]
	local tierProbability = Formulas.GetTierProbabilities(luck)[tierIndex]
	return tierProbability * item.Weight / tierWeightTotals[tierIndex]
end

-- The weighted roll. Returns the item and its tier index.
function Formulas.Roll(luck: number, rng: Random): (Item, number)
	local probabilities = Formulas.GetTierProbabilities(luck)
	local pick = rng:NextNumber()
	local tierIndex = #probabilities
	local cumulative = 0
	for index, probability in probabilities do
		cumulative += probability
		if pick < cumulative then
			tierIndex = index
			break
		end
	end

	local pool = itemsByTier[tierIndex]
	local itemPick = rng:NextNumber() * tierWeightTotals[tierIndex]
	local running = 0
	for _, item in pool do
		running += item.Weight
		if itemPick < running then
			return item, tierIndex
		end
	end
	return pool[#pool], tierIndex
end

---------------------------------------------------------------------------
-- Economy
---------------------------------------------------------------------------
function Formulas.RollCost(totalRolls: number): number
	local roll = Config.Roll
	local cost = roll.BaseCost * (1 + totalRolls / roll.CostScaleEvery) ^ roll.CostGrowth
	return math.min(roll.MaxCost, math.floor(cost))
end

function Formulas.RollCooldown(hasFastRoll: boolean, tierIndex: number?): number
	local base = if hasFastRoll then Config.Roll.FastCooldown else Config.Roll.Cooldown
	if tierIndex then
		local extra = RarityTable.Tiers[tierIndex].RevealTime
		base += if hasFastRoll then extra * Config.Roll.FastCinematicScale else extra
	end
	return base
end

function Formulas.SpinTime(hasFastRoll: boolean, tierIndex: number): number
	local base = if hasFastRoll then Config.Roll.FastAnimationTime else Config.Roll.AnimationTime
	local extra = RarityTable.Tiers[tierIndex].RevealTime
	return base + (if hasFastRoll then extra * Config.Roll.FastCinematicScale else extra)
end

function Formulas.ClickReward(totalRolls: number): number
	return Config.Click.BaseReward + math.floor(totalRolls / 1000) * Config.Click.BonusPer1000Rolls
end

function Formulas.EquipSlots(hasExtraSlotsPass: boolean): number
	return Config.Equip.BaseSlots + (if hasExtraSlotsPass then Config.Equip.ExtraSlotsFromPass else 0)
end

export type LuckInput = {
	BonusLuck: number, -- permanent additive bonus (Stats.Luck)
	Equipped: { string },
	HasLuckPass: boolean,
	Boosts: { [string]: number },
	LuckHour: boolean,
	AdminLuck: number?,
}

-- Returns final luck plus a readable breakdown (shown in the HUD tooltip).
function Formulas.ComputeLuck(input: LuckInput): (number, { { Label: string, Value: string } })
	local breakdown = {}
	local luck = Config.Luck.BaseLuck + input.BonusLuck
	table.insert(breakdown, { Label = "Base", Value = string.format("%.2f", luck) })

	local equipBonus = 0
	for _, name in input.Equipped do
		local item = itemsByName[name]
		if item then
			equipBonus += item.LuckMultiplier - 1
		end
	end
	if equipBonus > 0 then
		luck *= 1 + equipBonus
		table.insert(
			breakdown,
			{ Label = "Equipped", Value = string.format("+%d%%", math.floor(equipBonus * 100 + 0.5)) }
		)
	end

	if input.HasLuckPass then
		luck *= Config.Luck.GamepassMultiplier
		table.insert(breakdown, { Label = "2x Luck Pass", Value = `x{Config.Luck.GamepassMultiplier}` })
	end

	for boostId, remaining in input.Boosts do
		local boost = Config.Boosts[boostId]
		if boost and boost.LuckMultiplier and remaining > 0 then
			luck *= boost.LuckMultiplier
			table.insert(breakdown, { Label = boost.DisplayName, Value = `x{boost.LuckMultiplier}` })
		end
	end

	if input.LuckHour then
		luck *= Config.LuckHour.Multiplier
		table.insert(breakdown, { Label = "Luck Hour", Value = `x{Config.LuckHour.Multiplier}` })
	end

	if input.AdminLuck and input.AdminLuck ~= 1 then
		luck *= input.AdminLuck
		table.insert(breakdown, { Label = "Admin", Value = `x{input.AdminLuck}` })
	end

	return math.clamp(luck, 0.01, Config.Luck.MaxLuck), breakdown
end

export type CoinInput = {
	Equipped: { string },
	IsVIP: boolean,
	Boosts: { [string]: number },
}

function Formulas.ComputeCoinMultiplier(input: CoinInput): number
	local bonus = 0
	for _, name in input.Equipped do
		local item = itemsByName[name]
		if item then
			bonus += item.CoinMultiplier - 1
		end
	end
	local multiplier = 1 + bonus
	if input.IsVIP then
		multiplier *= Config.VIP.CoinMultiplier
	end
	for boostId, remaining in input.Boosts do
		local boost = Config.Boosts[boostId]
		if boost and boost.CoinMultiplier and remaining > 0 then
			multiplier *= boost.CoinMultiplier
		end
	end
	return multiplier
end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------
function Formulas.QuestGoal(quest: Config.QuestInfo, level: number): number
	if not quest.Repeatable or level <= 0 then
		return quest.Goal
	end
	return math.ceil(quest.Goal * (quest.GoalScale or 2) ^ level)
end

function Formulas.QuestReward(quest: Config.QuestInfo, level: number): Config.Reward
	local scale = if quest.Repeatable and level > 0 then (quest.RewardScale or 2) ^ level else 1
	local base = quest.Reward
	return {
		Coins = if base.Coins then math.floor(base.Coins * scale) else nil,
		Gems = if base.Gems then math.floor(base.Gems * scale) else nil,
		RerollTokens = if base.RerollTokens then math.floor(base.RerollTokens * scale) else nil,
		Luck = base.Luck, -- permanent luck never scales
		Boost = base.Boost,
	}
end

-- "Roll %d times" → "Roll 250 times"; "%t" formats seconds as a duration.
function Formulas.QuestTitle(quest: Config.QuestInfo, level: number, formatDuration: (number) -> string): string
	local goal = Formulas.QuestGoal(quest, level)
	local title = string.gsub(quest.Title, "%%t", formatDuration(goal))
	title = string.gsub(title, "%%d", tostring(goal))
	return title
end

-- Human readable reward text: "1,500 Coins · 5 Gems"
function Formulas.DescribeReward(reward: Config.Reward, formatNumber: (number) -> string): string
	local parts = {}
	if reward.Coins then
		table.insert(parts, `{formatNumber(reward.Coins)} {Config.Currencies.Coins.DisplayName}`)
	end
	if reward.Gems then
		table.insert(parts, `{formatNumber(reward.Gems)} {Config.Currencies.Gems.DisplayName}`)
	end
	if reward.RerollTokens then
		table.insert(parts, `{formatNumber(reward.RerollTokens)} {Config.Currencies.RerollTokens.DisplayName}`)
	end
	if reward.Luck then
		table.insert(parts, `+{reward.Luck} Luck (permanent)`)
	end
	if reward.Boost then
		local boost = Config.Boosts[reward.Boost.Id]
		local name = if boost then boost.DisplayName else reward.Boost.Id
		table.insert(parts, `{name} ({math.floor(reward.Boost.Duration / 60)}m)`)
	end
	return table.concat(parts, " · ")
end

return Formulas
