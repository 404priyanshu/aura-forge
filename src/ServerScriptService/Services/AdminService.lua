--[[
	AdminService — chat commands for whitelisted admins (Config.Admins).

	Type these in chat. [player] is optional (defaults to you); it accepts a
	partial name/display name, "me" or "all".

	  /givecoins <amount> [player]
	  /givegems <amount> [player]
	  /givetokens <amount> [player]
	  /setluck <multiplier> [player]     session-only luck multiplier (1 = off)
	  /givepotion <minutes> [player]     Luck Potion time
	  /givepass <PassKey> [player]       e.g. /givepass AutoRoll
	  /giveitem <item name>              gives you one of that aura
	  /luckhour [minutes]                start a Luck Hour on this server now
	  /resettutorial [player]            replay onboarding
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local Formulas = require(Modules.Formulas)
local RarityTable = require(Modules.RarityTable)
local Util = require(Modules.Util)

local AdminService = {}

local Services
local DataService

function AdminService:IsAdmin(player: Player): boolean
	if table.find(Config.Admins.UserIds, player.UserId) then
		return true
	end
	if Config.Admins.AllowInStudio and RunService:IsStudio() then
		return true
	end
	if Config.Admins.AllowGameCreator and game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId then
		return true
	end
	return false
end

local function findTargets(caller: Player, query: string?): { Player }
	if query == nil or query == "" or string.lower(query) == "me" then
		return { caller }
	end
	local lower = string.lower(query)
	if lower == "all" then
		return Players:GetPlayers()
	end
	for _, player in Players:GetPlayers() do
		if string.sub(string.lower(player.Name), 1, #lower) == lower or string.sub(string.lower(player.DisplayName), 1, #lower) == lower then
			return { player }
		end
	end
	return {}
end

local function findItem(query: string): RarityTable.Item?
	local lower = string.lower(query)
	for _, item in RarityTable.Items do
		if string.lower(item.Name) == lower then
			return item
		end
	end
	for _, item in RarityTable.Items do
		if string.sub(string.lower(item.Name), 1, #lower) == lower then
			return item
		end
	end
	return nil
end

local function reply(player: Player, text: string, ok: boolean?)
	Services.EventService:Toast(player, "[Admin] " .. text, if ok == false then Color3.fromRGB(255, 90, 100) else Color3.fromRGB(120, 200, 255))
end

local commands: { [string]: (caller: Player, args: { string }) -> () } = {}

local function amountCommand(apply: (target: Player, amount: number) -> (), label: string)
	return function(caller: Player, args: { string })
		local amount = tonumber(args[1])
		if not amount or not Util.IsFiniteNumber(amount, 0, 1e15) then
			reply(caller, `Usage: amount must be a number`, false)
			return
		end
		local targets = findTargets(caller, args[2])
		if #targets == 0 then
			reply(caller, `No player matches "{args[2]}"`, false)
			return
		end
		for _, target in targets do
			if DataService:IsLoaded(target) then
				apply(target, amount)
			end
		end
		reply(caller, `Gave {Util.Commas(amount)} {label} to {#targets} player(s)`)
	end
end

commands["/givecoins"] = amountCommand(function(target, amount)
	Services.EconomyService:AddCoins(target, amount, "Admin", true)
end, "coins")

commands["/givegems"] = amountCommand(function(target, amount)
	Services.EconomyService:AddGems(target, amount)
end, "gems")

commands["/givetokens"] = amountCommand(function(target, amount)
	Services.EconomyService:AddRerollTokens(target, amount)
end, "tokens")

commands["/givepotion"] = amountCommand(function(target, minutes)
	Services.EconomyService:AddBoost(target, "LuckPotion", minutes * 60)
end, "potion minutes")

commands["/setluck"] = function(caller, args)
	local multiplier = tonumber(args[1])
	if not multiplier or not Util.IsFiniteNumber(multiplier, 0.01, Config.Luck.MaxLuck) then
		reply(caller, "Usage: /setluck <multiplier> [player]", false)
		return
	end
	for _, target in findTargets(caller, args[2]) do
		DataService:SetLive(target, "AdminLuck", multiplier)
		Services.EconomyService:RecomputeStats(target)
	end
	reply(caller, `Admin luck set to x{multiplier}`)
end

commands["/givepass"] = function(caller, args)
	local passKey = args[1]
	if not passKey or not Config.Gamepasses[passKey] then
		local keys = {}
		for key in Config.Gamepasses do
			table.insert(keys, key)
		end
		reply(caller, "Usage: /givepass <" .. table.concat(keys, "|") .. "> [player]", false)
		return
	end
	for _, target in findTargets(caller, args[2]) do
		Services.MonetizationService:GrantPass(target, passKey, false)
	end
	reply(caller, `Granted {passKey}`)
end

commands["/giveitem"] = function(caller, args)
	local query = table.concat(args, " ")
	local item = if query ~= "" then findItem(query) else nil
	if not item then
		reply(caller, "Usage: /giveitem <item name>", false)
		return
	end
	local tierIndex = Formulas.ItemTierIndex(item)
	DataService:Update(caller, { "Inventory", "Stats" }, function(data)
		data.Inventory[item.Name] = (data.Inventory[item.Name] or 0) + 1
		if tierIndex > data.Stats.BestRarity then
			data.Stats.BestRarity = tierIndex
		end
	end)
	reply(caller, `Gave {item.Name} [{item.Rarity}]`)
end

commands["/luckhour"] = function(caller, args)
	local minutes = tonumber(args[1]) or Config.LuckHour.Duration / 60
	if not Util.IsFiniteNumber(minutes, 0.1, 24 * 60) then
		reply(caller, "Usage: /luckhour [minutes]", false)
		return
	end
	Services.EventService:StartLuckHour(minutes * 60)
	reply(caller, `Luck Hour started for {minutes} minutes`)
end

commands["/resettutorial"] = function(caller, args)
	for _, target in findTargets(caller, args[1]) do
		DataService:Update(target, "Tutorial", function(data)
			data.Tutorial.Completed = false
		end)
	end
	reply(caller, "Tutorial reset")
end

local function run(player: Player, message: string)
	if not AdminService:IsAdmin(player) then
		return
	end
	local args = string.split(message, " ")
	local name = string.lower(table.remove(args, 1) or "")
	local handler = commands[name]
	if not handler then
		return
	end
	-- Drop empty args produced by double spaces.
	local clean = {}
	for _, arg in args do
		if arg ~= "" then
			table.insert(clean, arg)
		end
	end
	local ok, err = pcall(handler, player, clean)
	if not ok then
		warn("[AdminService] command failed:", err)
		reply(player, "Command error: " .. tostring(err), false)
	end
end

function AdminService:Init(services)
	Services = services
	DataService = services.DataService
end

function AdminService:Start()
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		local folder = Instance.new("Folder")
		folder.Name = "AdminCommands"
		folder.Parent = TextChatService
		for name in commands do
			local command = Instance.new("TextChatCommand")
			command.Name = "Admin_" .. string.sub(name, 2)
			command.PrimaryAlias = name
			command.AutocompleteVisible = false
			command.Triggered:Connect(function(textSource: TextSource, text: string)
				local player = Players:GetPlayerByUserId(textSource.UserId)
				if player then
					run(player, text)
				end
			end)
			command.Parent = folder
		end
	else
		-- Legacy chat fallback.
		local function hook(player: Player)
			player.Chatted:Connect(function(message)
				if string.sub(message, 1, 1) == "/" then
					run(player, message)
				end
			end)
		end
		Players.PlayerAdded:Connect(hook)
		for _, player in Players:GetPlayers() do
			hook(player)
		end
	end
end

return AdminService
