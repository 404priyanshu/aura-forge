--!strict
--[[
	Config — THE single place for every tunable value in the game.

	Rebalance freely: nothing in here is logic. Prices, cooldowns, rewards, IDs,
	multipliers, timers and quest goals are all read from this table by the
	services and controllers.

	Rarity tiers and items live in RarityTable (same folder) because they are
	content rather than tuning, but their odds are also plain numbers.

	Units:
	  * Durations are in SECONDS unless the name says otherwise.
	  * "Multiplier" values multiply (2 = double). "Bonus" values add.
	  * An ID of 0 means "not configured yet"; the game hides/disables that
	    purchase instead of erroring. Replace with your real IDs before launch.
]]

local Config = {}

---------------------------------------------------------------------------
-- GAME IDENTITY
---------------------------------------------------------------------------
Config.GameName = "Aura Forge"

---------------------------------------------------------------------------
-- CURRENCIES
-- "Coins" is the roll currency (what the brief calls the "Rolls" currency).
-- Rename DisplayName/Icon freely; the data keys must stay "Coins"/"Gems".
---------------------------------------------------------------------------
Config.Currencies = {
	Coins = { DisplayName = "Coins", Icon = "🪙", Color = Color3.fromRGB(255, 206, 74) },
	Gems = { DisplayName = "Gems", Icon = "💎", Color = Color3.fromRGB(90, 220, 255) },
	RerollTokens = { DisplayName = "Lucky Tokens", Icon = "🎟️", Color = Color3.fromRGB(190, 120, 255) },
}

---------------------------------------------------------------------------
-- DATA / PERSISTENCE
---------------------------------------------------------------------------
Config.Data = {
	-- Changing StoreName starts EVERYONE fresh (new DataStore). Bump only on purpose.
	StoreName = "AuraForge_PlayerData_v1",
	-- When true, Studio play-tests use ProfileService's mock store (nothing is saved).
	UseMockInStudio = false,
	-- How often batched data changes are pushed to the owning client.
	ReplicationInterval = 0.2,
	-- Starting values for brand-new players.
	StartingCoins = 250,
	StartingGems = 10,
	StartingRerollTokens = 1,
}

---------------------------------------------------------------------------
-- ROLLING
---------------------------------------------------------------------------
Config.Roll = {
	-- Roll cost formula: BaseCost * (1 + TotalRolls / CostScaleEvery) ^ CostGrowth, capped at MaxCost.
	-- With the defaults: roll 0 = 10, roll 1,000 ≈ 23, roll 10,000 ≈ 50, roll 100,000 ≈ 110.
	BaseCost = 10,
	CostScaleEvery = 100,
	CostGrowth = 0.35,
	MaxCost = 2500,

	-- Minimum seconds between rolls (server-enforced). Fast Roll pass uses FastCooldown.
	Cooldown = 1.6,
	FastCooldown = 0.6,
	-- Network jitter allowance when validating the cooldown.
	CooldownTolerance = 0.12,

	-- Client spin animation length. Must stay a bit under the matching cooldown.
	AnimationTime = 1.35,
	FastAnimationTime = 0.45,
	-- Fast Roll also scales a tier's extra cinematic time (RarityTable RevealTime) by this.
	FastCinematicScale = 0.5,

	-- Pulls of this rarity or better are announced to the whole server.
	AnnounceMinRarity = "Mythic",
	-- Pulls of this rarity or better always get the full reveal, even with Quick Reveals on.
	AlwaysFullRevealRarity = "Epic",

	-- Luck multiplier applied to a roll paid with a Lucky Token (instead of coins).
	RerollTokenLuck = 2,
}

---------------------------------------------------------------------------
-- LUCK
-- Final luck = (BaseLuck + permanent bonus) * (1 + equipped bonuses)
--              * pass * potions * luck hour * admin override, capped at MaxLuck.
-- How luck bends the odds is controlled per tier by LuckExponent in RarityTable.
---------------------------------------------------------------------------
Config.Luck = {
	BaseLuck = 1,
	MaxLuck = 1000000,
	GamepassMultiplier = 2, -- "2x Luck" gamepass
	LuckHourMultiplier = 2,
}

---------------------------------------------------------------------------
-- EQUIPPING
---------------------------------------------------------------------------
Config.Equip = {
	BaseSlots = 3,
	ExtraSlotsFromPass = 2, -- "+2 Equip Slots" gamepass
}

---------------------------------------------------------------------------
-- CLICK-TO-EARN
---------------------------------------------------------------------------
Config.Click = {
	BaseReward = 2,
	-- Extra coins per click for every 1,000 lifetime rolls (rewards progression).
	BonusPer1000Rolls = 1,
	-- Anti-autoclicker: server accepts at most this many clicks per second (token bucket).
	MaxClicksPerSecond = 12,
	-- Burst allowance for the token bucket.
	MaxBurst = 16,
}

---------------------------------------------------------------------------
-- AFK ZONE
-- Created automatically if Workspace has no part named ZoneName.
-- Build your own part with that name to place it by hand (size/position are read from it).
---------------------------------------------------------------------------
Config.AFK = {
	ZoneName = "AFKZone",
	ZoneSize = Vector3.new(28, 12, 28),
	ZonePosition = Vector3.new(0, 6, 70),
	CoinsPerSecond = 4,
	-- Seconds a player must stand in the zone before earnings start (stops teleport hopping).
	WarmupSeconds = 5,
	-- Every GemInterval continuous seconds in the zone grants GemsPerInterval gems.
	GemInterval = 300,
	GemsPerInterval = 1,
}

---------------------------------------------------------------------------
-- OFFLINE EARNINGS (summary popup on join)
---------------------------------------------------------------------------
Config.Offline = {
	Enabled = true,
	CoinsPerSecond = 1, -- multiplied by VIP if owned
	MaxSeconds = 8 * 60 * 60,
	MinSeconds = 120, -- shorter absences award nothing (and show no popup)
}

---------------------------------------------------------------------------
-- VIP
---------------------------------------------------------------------------
Config.VIP = {
	CoinMultiplier = 1.25,
	ChatTag = "[VIP]",
	ChatTagColor = "#FFD54A",
}

---------------------------------------------------------------------------
-- GAMEPASSES  (replace Id = 0 with your real gamepass IDs)
---------------------------------------------------------------------------
export type PassInfo = { Id: number, Name: string, Description: string, Icon: string, Order: number }
Config.Gamepasses = {
	LuckX2 = { Id = 0, Name = "2x Luck", Description = "Permanently doubles your luck.", Icon = "🍀", Order = 1 },
	AutoRoll = { Id = 0, Name = "Auto Roll", Description = "Roll automatically, even while you grind.", Icon = "🔁", Order = 2 },
	FastRoll = { Id = 0, Name = "Fast Roll", Description = "Much faster roll animations & cooldown.", Icon = "⚡", Order = 3 },
	ExtraSlots = { Id = 0, Name = "+2 Equip Slots", Description = "Equip two more auras at once.", Icon = "🎒", Order = 4 },
	VIP = { Id = 0, Name = "VIP", Description = "Gold chat tag and 1.25x coins forever.", Icon = "👑", Order = 5 },
} :: { [string]: PassInfo }

---------------------------------------------------------------------------
-- DEVELOPER PRODUCTS  (repeatable purchases; replace Id = 0)
--   Kind = "Boost"    → adds Duration seconds of Config.Boosts[Boost]
--   Kind = "Currency" → adds Amount of Currency (not affected by multipliers)
--   Kind = "Tokens"   → adds Amount Lucky Tokens (re-roll tokens)
---------------------------------------------------------------------------
export type ProductInfo = {
	Id: number,
	Name: string,
	Description: string,
	Icon: string,
	Order: number,
	Kind: string,
	Boost: string?,
	Duration: number?,
	Currency: string?,
	Amount: number?,
}
Config.DevProducts = {
	LuckPotion = {
		Id = 0,
		Name = "Luck Potion",
		Description = "2x luck for 10 minutes. Stacks duration.",
		Icon = "🧪",
		Order = 1,
		Kind = "Boost",
		Boost = "LuckPotion",
		Duration = 600,
	},
	CoinsSmall = {
		Id = 0,
		Name = "Coin Pouch",
		Description = "5,000 coins.",
		Icon = "🪙",
		Order = 2,
		Kind = "Currency",
		Currency = "Coins",
		Amount = 5000,
	},
	CoinsMedium = {
		Id = 0,
		Name = "Coin Chest",
		Description = "30,000 coins.",
		Icon = "💰",
		Order = 3,
		Kind = "Currency",
		Currency = "Coins",
		Amount = 30000,
	},
	CoinsLarge = {
		Id = 0,
		Name = "Coin Vault",
		Description = "150,000 coins.",
		Icon = "🏦",
		Order = 4,
		Kind = "Currency",
		Currency = "Coins",
		Amount = 150000,
	},
	RerollTokens = {
		Id = 0,
		Name = "Lucky Tokens x5",
		Description = "5 free rolls at 2x luck.",
		Icon = "🎟️",
		Order = 5,
		Kind = "Tokens",
		Amount = 5,
	},
} :: { [string]: ProductInfo }

-- ProcessReceipt idempotency: a global DataStore ledger of granted PurchaseIds
-- plus the per-profile purchase-id cache (see MonetizationService).
Config.Monetization = {
	LedgerStoreName = "AuraForge_ReceiptLedger_v1",
	ProfilePurchaseIdCache = 50,
}

---------------------------------------------------------------------------
-- BOOSTS (timed effects; time only counts down while the player is online)
---------------------------------------------------------------------------
export type BoostInfo = {
	DisplayName: string,
	Icon: string,
	LuckMultiplier: number?,
	CoinMultiplier: number?,
	MaxStackSeconds: number,
}
Config.Boosts = {
	LuckPotion = { DisplayName = "Luck Potion", Icon = "🧪", LuckMultiplier = 2, MaxStackSeconds = 6 * 3600 },
	LuckyBrew = { DisplayName = "Lucky Brew", Icon = "🍵", LuckMultiplier = 1.5, MaxStackSeconds = 2 * 3600 },
	CoinCharm = { DisplayName = "Coin Charm", Icon = "🧲", CoinMultiplier = 2, MaxStackSeconds = 2 * 3600 },
} :: { [string]: BoostInfo }

---------------------------------------------------------------------------
-- GEM SHOP (spend Gems in-game; no Robux)
---------------------------------------------------------------------------
export type GemShopItem = {
	Id: string,
	Name: string,
	Description: string,
	Icon: string,
	Price: number,
	Kind: string,
	Boost: string?,
	Duration: number?,
	Amount: number?,
}
Config.GemShop = {
	{
		Id = "LuckyBrew",
		Name = "Lucky Brew",
		Description = "1.5x luck for 5 minutes.",
		Icon = "🍵",
		Price = 20,
		Kind = "Boost",
		Boost = "LuckyBrew",
		Duration = 300,
	},
	{
		Id = "CoinCharm",
		Name = "Coin Charm",
		Description = "2x coins for 5 minutes.",
		Icon = "🧲",
		Price = 15,
		Kind = "Boost",
		Boost = "CoinCharm",
		Duration = 300,
	},
	{
		Id = "Token",
		Name = "Lucky Token",
		Description = "One free roll at 2x luck.",
		Icon = "🎟️",
		Price = 12,
		Kind = "Tokens",
		Amount = 1,
	},
} :: { GemShopItem }

---------------------------------------------------------------------------
-- REWARD TABLES
-- A reward is any combination of: Coins, Gems, RerollTokens,
-- Luck (PERMANENT additive luck bonus), Boost = { Id = "<Boosts key>", Duration = seconds }.
---------------------------------------------------------------------------
export type Reward = {
	Coins: number?,
	Gems: number?,
	RerollTokens: number?,
	Luck: number?,
	Boost: { Id: string, Duration: number }?,
}

---------------------------------------------------------------------------
-- QUESTS
-- Type: "Rolls" | "ObtainRarity" (needs Rarity) | "Playtime" (seconds) |
--       "Clicks" | "EarnCoins" | "AfkTime" (seconds)
-- Repeatable quests restart after claiming with Goal * GoalScale^level and
-- Reward * RewardScale^level (Luck rewards never scale). MaxLevel caps repeats.
---------------------------------------------------------------------------
export type QuestInfo = {
	Id: string,
	Title: string,
	Type: string,
	Goal: number,
	Rarity: string?,
	Reward: Reward,
	Repeatable: boolean,
	GoalScale: number?,
	RewardScale: number?,
	MaxLevel: number?,
}
Config.Quests = {
	{
		Id = "Roll100",
		Title = "Roll %d times",
		Type = "Rolls",
		Goal = 100,
		Reward = { Coins = 1500, Gems = 5 },
		Repeatable = true,
		GoalScale = 2.5,
		RewardScale = 2.2,
		MaxLevel = 12,
	},
	{
		Id = "ObtainRare",
		Title = "Obtain %d Rare (or better)",
		Type = "ObtainRarity",
		Rarity = "Rare",
		Goal = 1,
		Reward = { Coins = 600, Gems = 3 },
		Repeatable = true,
		GoalScale = 3,
		RewardScale = 2.5,
		MaxLevel = 8,
	},
	{
		Id = "ObtainLegendary",
		Title = "Obtain a Legendary",
		Type = "ObtainRarity",
		Rarity = "Legendary",
		Goal = 1,
		Reward = { Gems = 30, Luck = 0.05 },
		Repeatable = false,
	},
	{
		Id = "ObtainMythic",
		Title = "Obtain a Mythic",
		Type = "ObtainRarity",
		Rarity = "Mythic",
		Goal = 1,
		Reward = { Gems = 100, Luck = 0.15 },
		Repeatable = false,
	},
	{
		Id = "Play30",
		Title = "Play for %t",
		Type = "Playtime",
		Goal = 30 * 60,
		Reward = { Coins = 3000, RerollTokens = 2 },
		Repeatable = true,
		GoalScale = 2,
		RewardScale = 2,
		MaxLevel = 6,
	},
	{
		Id = "Click500",
		Title = "Click %d times",
		Type = "Clicks",
		Goal = 500,
		Reward = { Coins = 1000 },
		Repeatable = true,
		GoalScale = 2,
		RewardScale = 2.2,
		MaxLevel = 10,
	},
	{
		Id = "Earn10k",
		Title = "Earn %d coins",
		Type = "EarnCoins",
		Goal = 10000,
		Reward = { Gems = 10 },
		Repeatable = true,
		GoalScale = 3,
		RewardScale = 1.8,
		MaxLevel = 10,
	},
	{
		Id = "Afk15",
		Title = "Spend %t in the AFK zone",
		Type = "AfkTime",
		Goal = 15 * 60,
		Reward = { Coins = 2500, Boost = { Id = "CoinCharm", Duration = 300 } },
		Repeatable = true,
		GoalScale = 2,
		RewardScale = 1.5,
		MaxLevel = 5,
	},
} :: { QuestInfo }

---------------------------------------------------------------------------
-- DAILY LOGIN REWARDS (7-day cycle; missing a UTC day resets the streak to day 1)
---------------------------------------------------------------------------
Config.Daily = {
	Rewards = {
		{ Coins = 500 },
		{ Coins = 1000 },
		{ Coins = 1500, Gems = 5 },
		{ Coins = 2500, RerollTokens = 1 },
		{ Coins = 4000, Gems = 10 },
		{ Coins = 6000, RerollTokens = 3 },
		{ Coins = 10000, Gems = 25, Boost = { Id = "LuckPotion", Duration = 600 } },
	} :: { Reward },
}

---------------------------------------------------------------------------
-- PLAYTIME REWARDS (per server session; one claim every Interval, up to MaxClaims)
---------------------------------------------------------------------------
Config.Playtime = {
	Interval = 10 * 60,
	Rewards = {
		{ Coins = 400 },
		{ Coins = 800 },
		{ Gems = 3 },
		{ Coins = 1600, RerollTokens = 1 },
		{ Gems = 6 },
		{ Coins = 4000, Boost = { Id = "LuckyBrew", Duration = 300 } },
	} :: { Reward },
}

---------------------------------------------------------------------------
-- LUCK HOUR (global event; schedule is UTC-aligned so every server agrees)
---------------------------------------------------------------------------
Config.LuckHour = {
	Interval = 2 * 60 * 60, -- starts every 2 hours
	Duration = 10 * 60, -- lasts 10 minutes
	Offset = 0, -- shift the schedule (seconds) if you want it to start at a different minute
	Multiplier = Config.Luck.LuckHourMultiplier,
}

---------------------------------------------------------------------------
-- INDEX COMPLETION (own every item of a rarity → claim once)
-- Keys are rarity names from RarityTable.
---------------------------------------------------------------------------
Config.Index = {
	Rewards = {
		Common = { Coins = 500 },
		Uncommon = { Coins = 1500 },
		Rare = { Coins = 5000, Gems = 10 },
		Epic = { Gems = 25, Luck = 0.05 },
		Legendary = { Gems = 75, Luck = 0.1 },
		Mythic = { Gems = 200, Luck = 0.25 },
		Exotic = { Gems = 500, Luck = 0.5 },
		Divine = { Gems = 1000, Luck = 1 },
		Celestial = { Gems = 2500, Luck = 2 },
		Secret = { Gems = 10000, Luck = 5 },
	} :: { [string]: Reward },
}

---------------------------------------------------------------------------
-- ONBOARDING (3 popups for first-time players)
---------------------------------------------------------------------------
Config.Tutorial = {
	Pages = {
		{
			Title = "Welcome to Aura Forge!",
			Body = "Press ROLL to pull an aura. Rarer auras are flashier, worth more coins and boost your luck.",
		},
		{
			Title = "Grind for coins",
			Body = "Rolls cost coins. Tap the coin button, stand in the glowing AFK zone, and finish quests to earn more.",
		},
		{
			Title = "Stack your luck",
			Body = "Equip your best auras, drink potions and catch the Luck Hour every 2 hours to hunt the 1-in-10,000,000 Secret!",
		},
	},
	CompletionReward = { RerollTokens = 2 } :: Reward,
}

---------------------------------------------------------------------------
-- ADMINS
---------------------------------------------------------------------------
Config.Admins = {
	UserIds = {
		-- 123456789,
	} :: { number },
	AllowGameCreator = true, -- the place owner (user-owned games) is always an admin
	AllowInStudio = true, -- everyone is admin in Studio play-tests
}

---------------------------------------------------------------------------
-- AUDIO
-- Paste asset IDs from the Creator Store (Audio → filter "Creator: Roblox" for
-- licensed tracks/SFX that work in every experience). Empty string = silent.
-- "rbxasset://sounds/..." entries are built into the Roblox client.
---------------------------------------------------------------------------
Config.Audio = {
	MusicVolume = 0.3,
	SfxVolume = 0.6,
	Music = {
		-- "rbxassetid://YOUR_MUSIC_ID",
	} :: { string },
	Sfx = {
		Click = "rbxasset://sounds/volume_slider.ogg",
		Tick = "rbxasset://sounds/volume_slider.ogg",
		Whoosh = "",
		RevealSmall = "",
		RevealBig = "rbxasset://sounds/impact_explosion_03.mp3",
		Fanfare = "",
		Purchase = "",
		Claim = "",
		Error = "",
	} :: { [string]: string },
}

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
Config.UI = {
	-- Design resolution the UI is authored at; UIScale fits it to every screen.
	DesignWidth = 1000,
	DesignHeight = 580,
	MinScale = 0.6,
	MaxScale = 1.35,
	ToastDuration = 3.5,
	AnnouncementDuration = 6,
}

return Config
