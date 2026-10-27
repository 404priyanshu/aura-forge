--[[
	QuestService — progress tracking and claiming for Config.Quests.

	Progress is driven by signals from other services (rolls, clicks, coins
	earned, playtime, AFK time). Saved per quest as { Progress, Level, Done }.
	Repeatable quests level up on claim (bigger goal, bigger reward).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local Formulas = require(Modules.Formulas)
local Util = require(Modules.Util)
local Net = require(Modules.Net)

local QuestService = {}

local Services
local DataService

local questsById: { [string]: Config.QuestInfo } = {}
local questsByType: { [string]: { Config.QuestInfo } } = {}

for _, quest in Config.Quests do
	assert(questsById[quest.Id] == nil, "Duplicate quest id " .. quest.Id)
	questsById[quest.Id] = quest
	questsByType[quest.Type] = questsByType[quest.Type] or {}
	table.insert(questsByType[quest.Type], quest)
	if quest.Type == "ObtainRarity" then
		assert(quest.Rarity and Formulas.TierIndex(quest.Rarity), `Quest {quest.Id} needs a valid Rarity`)
	end
end

local function ensureQuestState(data)
	for _, quest in Config.Quests do
		if type(data.Quests[quest.Id]) ~= "table" then
			data.Quests[quest.Id] = { Progress = 0, Level = 0, Done = false }
		end
	end
end

function QuestService:AddProgress(player: Player, questType: string, amount: number, tierIndex: number?)
	local list = questsByType[questType]
	if not list then
		return
	end
	local data = DataService:GetData(player)
	if not data then
		return
	end

	local changed = false
	for _, quest in list do
		if quest.Type == "ObtainRarity" then
			local required = Formulas.TierIndex(quest.Rarity :: string) :: number
			if not tierIndex or tierIndex < required then
				continue
			end
		end
		local state = data.Quests[quest.Id]
		if not state or state.Done then
			continue
		end
		local goal = Formulas.QuestGoal(quest, state.Level)
		if state.Progress >= goal then
			continue
		end
		state.Progress = math.min(goal, state.Progress + amount)
		changed = true
		if state.Progress >= goal then
			Services.EventService:Notify(player, "QuestReady", {
				Text = `Quest complete: {Formulas.QuestTitle(quest, state.Level, Util.Duration)}`,
			})
		end
	end

	if changed then
		DataService:Update(player, "Quests")
	end
end

function QuestService:Claim(player: Player, questId: any)
	if not Util.IsShortString(questId) then
		return
	end
	local quest = questsById[questId]
	local data = DataService:GetData(player)
	if not quest or not data then
		return
	end
	local state = data.Quests[quest.Id]
	if not state or state.Done then
		return
	end
	local goal = Formulas.QuestGoal(quest, state.Level)
	if state.Progress < goal then
		return
	end

	local reward = Formulas.QuestReward(quest, state.Level)
	DataService:Update(player, "Quests", function()
		local nextLevel = state.Level + 1
		if quest.Repeatable and (quest.MaxLevel == nil or nextLevel < quest.MaxLevel) then
			state.Level = nextLevel
			state.Progress = 0
		else
			state.Done = true
		end
	end)
	local text = Services.EconomyService:GrantReward(player, reward, "Quest")
	Services.EventService:Toast(player, `✅ Quest reward: {text}`, Color3.fromRGB(90, 230, 120))
end

function QuestService:Init(services)
	Services = services
	DataService = services.DataService
end

function QuestService:Start()
	DataService.ProfileLoaded:Connect(function(player)
		DataService:Update(player, "Quests", ensureQuestState)
	end)

	Net.Event("ClaimQuest").OnServerEvent:Connect(function(player, questId)
		self:Claim(player, questId)
	end)

	Services.RollService.Rolled:Connect(function(player, _item, tierIndex)
		self:AddProgress(player, "Rolls", 1)
		self:AddProgress(player, "ObtainRarity", 1, tierIndex)
	end)
	Services.EconomyService.Clicked:Connect(function(player)
		self:AddProgress(player, "Clicks", 1)
	end)
	Services.EconomyService.CoinsEarned:Connect(function(player, amount)
		self:AddProgress(player, "EarnCoins", amount)
	end)
	Services.EconomyService.PlaytimeTick:Connect(function(player, seconds)
		self:AddProgress(player, "Playtime", seconds)
	end)
	Services.EconomyService.AfkTick:Connect(function(player, seconds)
		self:AddProgress(player, "AfkTime", seconds)
	end)
end

return QuestService
