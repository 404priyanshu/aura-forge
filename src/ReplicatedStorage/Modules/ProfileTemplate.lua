--!strict
--[[
	ProfileTemplate — shape of every player's saved data, plus versioned migrations.

	ProfileService:Reconcile() fills in any key that is missing from a save using
	this template, so ADDING a field needs no migration. Write a migration only
	when you RENAME, MOVE or CHANGE THE TYPE of an existing field:

	  1. Bump CURRENT_VERSION.
	  2. Add Migrations[oldVersion] = function(data) ... end  (mutates in place).

	Migrations run in order before Reconcile, so each one may assume the save is
	exactly at its version.
]]

local Config = require(script.Parent.Config)

local CURRENT_VERSION = 3

export type QuestState = { Progress: number, Level: number, Done: boolean }

export type PlayerData = {
	Version: number,
	Currency: { Coins: number, Gems: number, RerollTokens: number },
	Inventory: { [string]: number },
	Equipped: { string },
	Stats: {
		TotalRolls: number,
		Luck: number,
		Playtime: number,
		Clicks: number,
		CoinsEarned: number,
		AfkTime: number,
		BestRarity: number,
		Joins: number,
	},
	Gamepasses: { [string]: boolean },
	Purchases: { Products: { [string]: number }, RobuxSpent: number },
	Boosts: { [string]: number },
	Settings: { Music: boolean, Sfx: boolean, ScreenShake: boolean, QuickReveals: boolean },
	Daily: { Streak: number, LastClaim: number },
	Quests: { [string]: QuestState },
	IndexClaims: { [string]: boolean },
	Tutorial: { Completed: boolean },
	FirstJoin: number,
	LastOnline: number,
}

local Template: PlayerData = {
	Version = CURRENT_VERSION,

	Currency = {
		Coins = Config.Data.StartingCoins,
		Gems = Config.Data.StartingGems,
		RerollTokens = Config.Data.StartingRerollTokens,
	},

	-- [itemName] = owned count
	Inventory = {},
	-- list of equipped item names
	Equipped = {},

	Stats = {
		TotalRolls = 0,
		Luck = 0, -- permanent additive luck bonus (quests / index rewards)
		Playtime = 0, -- seconds, lifetime
		Clicks = 0,
		CoinsEarned = 0,
		AfkTime = 0, -- seconds, lifetime
		BestRarity = 0, -- highest tier index ever pulled
		Joins = 0,
	},

	-- [passKey] = true once owned (purchase flag / admin grant)
	Gamepasses = {},
	-- developer product purchase counters
	Purchases = {
		Products = {},
		RobuxSpent = 0,
	},

	-- [boostKey] = remaining seconds (only ticks down while online)
	Boosts = {},

	Settings = {
		Music = true,
		Sfx = true,
		ScreenShake = true,
		QuickReveals = false,
	},

	Daily = {
		Streak = 0,
		LastClaim = 0, -- unix seconds
	},

	-- [questId] = { Progress, Level, Done }
	Quests = {},
	-- [rarityName] = true when that tier's index reward was claimed
	IndexClaims = {},

	Tutorial = {
		Completed = false,
	},

	FirstJoin = 0,
	LastOnline = 0,
}

local Migrations: { [number]: (data: any) -> () } = {
	-- v1 → v2: currencies used to be flat top-level fields.
	[1] = function(data)
		data.Currency = data.Currency or {}
		if type(data.Coins) == "number" then
			data.Currency.Coins = (data.Currency.Coins or 0) + data.Coins
			data.Coins = nil
		end
		if type(data.Gems) == "number" then
			data.Currency.Gems = (data.Currency.Gems or 0) + data.Gems
			data.Gems = nil
		end
	end,

	-- v2 → v3: a single equipped aura (string) became a list; tokens moved into Currency.
	[2] = function(data)
		if type(data.Equipped) == "string" then
			data.Equipped = { data.Equipped }
		end
		if type(data.RerollTokens) == "number" then
			data.Currency = data.Currency or {}
			data.Currency.RerollTokens = (data.Currency.RerollTokens or 0) + data.RerollTokens
			data.RerollTokens = nil
		end
	end,
}

local ProfileTemplate = {}

ProfileTemplate.CurrentVersion = CURRENT_VERSION
ProfileTemplate.Template = Template
ProfileTemplate.Migrations = Migrations

-- Upgrades a loaded save in place. Saves with no Version field predate versioning (v1).
-- Returns the version the save started at.
function ProfileTemplate.Migrate(data: any): number
	local startVersion = if type(data.Version) == "number" then data.Version else 1
	-- A brand-new profile is a deep copy of Template and is already current.
	local version = startVersion
	while version < CURRENT_VERSION do
		local migrate = Migrations[version]
		if migrate then
			migrate(data)
		end
		version += 1
	end
	data.Version = CURRENT_VERSION
	return startVersion
end

return ProfileTemplate
