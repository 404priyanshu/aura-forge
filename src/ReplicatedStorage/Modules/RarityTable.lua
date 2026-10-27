--!strict
--[[
	RarityTable — every rarity tier and every item (aura) in the game.

	TIERS (ordered common → rarest; order matters, index = rarity rank)
	  Chance        "1 in X" chance of rolling this tier at 1x luck (exact).
	                The FIRST tier is special: it gets whatever probability is
	                left over (≈1 in 1.5 with these numbers), so its Chance and
	                LuckExponent are not used.
	  LuckExponent  How strongly luck boosts this tier: chance =
	                (1 / Chance) * luck ^ LuckExponent. 1 = linear (2x luck =
	                twice as likely), 0.5 = square-root, 0 = luck never helps.
	                As rarer tiers grow, Common shrinks to make room.
	  RevealTime    Extra cinematic seconds for this tier's reveal (also added
	                to the server roll cooldown so animations never overlap).
	  Cinematic     Full-screen build-up before the reveal.
	  Shake         Screen-shake intensity (0 = none).
	  Particles     UI spark count on reveal.
	  Sound         Config.Audio.Sfx key played on reveal.
	  AuraRate      ParticleEmitter rate of the aura around the character.

	ITEMS
	  Name            Unique display name (also the save key — renaming an item
	                  orphans it in existing saves).
	  Rarity          Tier name.
	  Weight          Relative chance among items of the same tier.
	  LuckMultiplier  Luck bonus while equipped (1.10 = +10%, bonuses add up).
	  CoinMultiplier  Coin bonus while equipped (adds up the same way).
	  Color           Aura colour (UI + particles).
	  Value           Coins paid out instantly when pulled.
	  Model           Optional: name of an Attachment/Folder in
	                  ReplicatedStorage.AuraModels whose effects are cloned onto
	                  the character instead of the generated aura.
]]

export type Tier = {
	Name: string,
	Chance: number,
	Color: Color3,
	LuckExponent: number,
	RevealTime: number,
	Cinematic: boolean,
	Shake: number,
	Particles: number,
	Sound: string,
	AuraRate: number,
}

export type Item = {
	Name: string,
	Rarity: string,
	Weight: number,
	LuckMultiplier: number,
	CoinMultiplier: number,
	Color: Color3,
	Value: number,
	Model: string?,
}

local RarityTable = {}

RarityTable.Tiers = {
	{
		Name = "Common",
		Chance = 2,
		Color = Color3.fromRGB(190, 196, 210),
		LuckExponent = 0,
		RevealTime = 0,
		Cinematic = false,
		Shake = 0,
		Particles = 6,
		Sound = "RevealSmall",
		AuraRate = 4,
	},
	{
		Name = "Uncommon",
		Chance = 4,
		Color = Color3.fromRGB(90, 220, 120),
		LuckExponent = 0.5,
		RevealTime = 0,
		Cinematic = false,
		Shake = 0,
		Particles = 10,
		Sound = "RevealSmall",
		AuraRate = 6,
	},
	{
		Name = "Rare",
		Chance = 16,
		Color = Color3.fromRGB(70, 150, 255),
		LuckExponent = 1,
		RevealTime = 0,
		Cinematic = false,
		Shake = 0.15,
		Particles = 16,
		Sound = "RevealSmall",
		AuraRate = 10,
	},
	{
		Name = "Epic",
		Chance = 64,
		Color = Color3.fromRGB(170, 90, 255),
		LuckExponent = 1,
		RevealTime = 0.3,
		Cinematic = false,
		Shake = 0.3,
		Particles = 24,
		Sound = "Fanfare",
		AuraRate = 16,
	},
	{
		Name = "Legendary",
		Chance = 512,
		Color = Color3.fromRGB(255, 190, 40),
		LuckExponent = 1,
		RevealTime = 0.8,
		Cinematic = false,
		Shake = 0.55,
		Particles = 36,
		Sound = "Fanfare",
		AuraRate = 24,
	},
	{
		Name = "Mythic",
		Chance = 4096,
		Color = Color3.fromRGB(255, 70, 140),
		LuckExponent = 1,
		RevealTime = 1.6,
		Cinematic = true,
		Shake = 0.8,
		Particles = 48,
		Sound = "RevealBig",
		AuraRate = 34,
	},
	{
		Name = "Exotic",
		Chance = 32768,
		Color = Color3.fromRGB(0, 230, 210),
		LuckExponent = 1,
		RevealTime = 2.2,
		Cinematic = true,
		Shake = 1.1,
		Particles = 60,
		Sound = "RevealBig",
		AuraRate = 44,
	},
	{
		Name = "Divine",
		Chance = 262144,
		Color = Color3.fromRGB(255, 245, 190),
		LuckExponent = 1,
		RevealTime = 2.8,
		Cinematic = true,
		Shake = 1.4,
		Particles = 72,
		Sound = "RevealBig",
		AuraRate = 56,
	},
	{
		Name = "Celestial",
		Chance = 1048576,
		Color = Color3.fromRGB(120, 140, 255),
		LuckExponent = 1,
		RevealTime = 3.4,
		Cinematic = true,
		Shake = 1.8,
		Particles = 90,
		Sound = "RevealBig",
		AuraRate = 70,
	},
	{
		Name = "Secret",
		Chance = 10000000,
		Color = Color3.fromRGB(255, 40, 40),
		LuckExponent = 1,
		RevealTime = 4.5,
		Cinematic = true,
		Shake = 2.4,
		Particles = 120,
		Sound = "RevealBig",
		AuraRate = 90,
	},
} :: { Tier }

RarityTable.Items = {
	-- Common
	{ Name = "Dust", Rarity = "Common", Weight = 50, LuckMultiplier = 1.00, CoinMultiplier = 1.00, Color = Color3.fromRGB(200, 190, 170), Value = 2 },
	{ Name = "Ember", Rarity = "Common", Weight = 30, LuckMultiplier = 1.01, CoinMultiplier = 1.00, Color = Color3.fromRGB(255, 140, 80), Value = 2 },
	{ Name = "Breeze", Rarity = "Common", Weight = 20, LuckMultiplier = 1.00, CoinMultiplier = 1.01, Color = Color3.fromRGB(190, 240, 255), Value = 3 },
	-- Uncommon
	{ Name = "Moss", Rarity = "Uncommon", Weight = 45, LuckMultiplier = 1.02, CoinMultiplier = 1.02, Color = Color3.fromRGB(110, 200, 90), Value = 5 },
	{ Name = "Frostbite", Rarity = "Uncommon", Weight = 35, LuckMultiplier = 1.03, CoinMultiplier = 1.00, Color = Color3.fromRGB(150, 220, 255), Value = 6 },
	{ Name = "Static", Rarity = "Uncommon", Weight = 20, LuckMultiplier = 1.02, CoinMultiplier = 1.03, Color = Color3.fromRGB(255, 250, 120), Value = 8 },
	-- Rare
	{ Name = "Tidecaller", Rarity = "Rare", Weight = 40, LuckMultiplier = 1.05, CoinMultiplier = 1.04, Color = Color3.fromRGB(40, 140, 255), Value = 25 },
	{ Name = "Sunflare", Rarity = "Rare", Weight = 35, LuckMultiplier = 1.04, CoinMultiplier = 1.06, Color = Color3.fromRGB(255, 170, 40), Value = 30 },
	{ Name = "Nightshade", Rarity = "Rare", Weight = 25, LuckMultiplier = 1.07, CoinMultiplier = 1.03, Color = Color3.fromRGB(120, 60, 200), Value = 35 },
	-- Epic
	{ Name = "Thunderveil", Rarity = "Epic", Weight = 40, LuckMultiplier = 1.10, CoinMultiplier = 1.08, Color = Color3.fromRGB(140, 160, 255), Value = 120 },
	{ Name = "Prism", Rarity = "Epic", Weight = 35, LuckMultiplier = 1.12, CoinMultiplier = 1.06, Color = Color3.fromRGB(255, 120, 230), Value = 140 },
	{ Name = "Venom Bloom", Rarity = "Epic", Weight = 25, LuckMultiplier = 1.08, CoinMultiplier = 1.12, Color = Color3.fromRGB(120, 255, 90), Value = 160 },
	-- Legendary
	{ Name = "Solar Crown", Rarity = "Legendary", Weight = 40, LuckMultiplier = 1.20, CoinMultiplier = 1.15, Color = Color3.fromRGB(255, 200, 60), Value = 1500 },
	{ Name = "Abyssal", Rarity = "Legendary", Weight = 35, LuckMultiplier = 1.25, CoinMultiplier = 1.10, Color = Color3.fromRGB(30, 60, 160), Value = 1800 },
	{ Name = "Starforged", Rarity = "Legendary", Weight = 25, LuckMultiplier = 1.22, CoinMultiplier = 1.20, Color = Color3.fromRGB(255, 255, 220), Value = 2200 },
	-- Mythic
	{ Name = "Chronoshard", Rarity = "Mythic", Weight = 55, LuckMultiplier = 1.35, CoinMultiplier = 1.25, Color = Color3.fromRGB(80, 255, 230), Value = 15000 },
	{ Name = "Phoenix Wing", Rarity = "Mythic", Weight = 45, LuckMultiplier = 1.40, CoinMultiplier = 1.30, Color = Color3.fromRGB(255, 90, 40), Value = 18000 },
	-- Exotic
	{ Name = "Void Lotus", Rarity = "Exotic", Weight = 55, LuckMultiplier = 1.50, CoinMultiplier = 1.40, Color = Color3.fromRGB(140, 0, 255), Value = 100000 },
	{ Name = "Aurora Prime", Rarity = "Exotic", Weight = 45, LuckMultiplier = 1.60, CoinMultiplier = 1.35, Color = Color3.fromRGB(60, 255, 170), Value = 120000 },
	-- Divine
	{ Name = "Seraphim", Rarity = "Divine", Weight = 55, LuckMultiplier = 1.75, CoinMultiplier = 1.50, Color = Color3.fromRGB(255, 250, 210), Value = 750000 },
	{ Name = "Genesis", Rarity = "Divine", Weight = 45, LuckMultiplier = 1.85, CoinMultiplier = 1.55, Color = Color3.fromRGB(255, 220, 120), Value = 900000 },
	-- Celestial
	{ Name = "Event Horizon", Rarity = "Celestial", Weight = 55, LuckMultiplier = 2.00, CoinMultiplier = 1.75, Color = Color3.fromRGB(20, 20, 40), Value = 3000000 },
	{ Name = "Astral Throne", Rarity = "Celestial", Weight = 45, LuckMultiplier = 2.20, CoinMultiplier = 1.80, Color = Color3.fromRGB(150, 170, 255), Value = 3500000 },
	-- Secret
	{ Name = "The Last Light", Rarity = "Secret", Weight = 100, LuckMultiplier = 3.00, CoinMultiplier = 2.50, Color = Color3.fromRGB(255, 255, 255), Value = 25000000 },
} :: { Item }

return RarityTable
