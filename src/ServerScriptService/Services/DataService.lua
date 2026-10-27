--[[
	DataService — loads/saves player data with ProfileService (session locked,
	auto-saved) and replicates it to the owning client.

	Replication model ("replica-lite"):
	  * On load the client receives the full Data table and the Live table.
	  * Services mutate data through DataService:Update(player, keys, fn); the
	    touched top-level keys are marked dirty and flushed to the client in one
	    batched DataPatch every Config.Data.ReplicationInterval seconds.
	  * "Live" is per-session, never-saved state computed by the server (final
	    luck, roll cost, owned passes...). Set it with DataService:SetLive.

	Public API
	  DataService.ProfileLoaded    Signal(player, data, isNewPlayer)
	  DataService.ProfileReleasing Signal(player, data)
	  :GetData(player) -> data?          (read-only use, or mutate inside :Update)
	  :GetProfile(player) -> profile?
	  :WaitForProfile(player, timeout?) -> profile?
	  :Update(player, keys, mutator?) -> boolean
	  :GetLive(player, key) / :SetLive(player, key, value)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local ProfileTemplate = require(Modules.ProfileTemplate)
local Signal = require(Modules.Signal)
local Net = require(Modules.Net)

local DataService = {}
DataService.ProfileLoaded = Signal.new()
DataService.ProfileReleasing = Signal.new()

local profileStore
local profiles: { [Player]: any } = {}
local live: { [Player]: { [string]: any } } = {}
local dirtyData: { [Player]: { [string]: boolean } } = {}
local dirtyLive: { [Player]: { [string]: boolean } } = {}

local dataInitRemote: RemoteEvent
local dataPatchRemote: RemoteEvent

local function loadProfileService()
	local packages = ServerScriptService:FindFirstChild("Packages")
	local module = packages and packages:FindFirstChild("ProfileService")
	if not module then
		error(
			"[DataService] ProfileService not found. Insert the ProfileService ModuleScript at "
				.. "ServerScriptService/Packages/ProfileService (see SETUP.md)."
		)
	end
	return require(module)
end

local function sendInit(player: Player)
	local profile = profiles[player]
	if profile then
		dataInitRemote:FireClient(player, profile.Data, live[player] or {})
	end
end

local function flush()
	for player, keys in dirtyData do
		local profile = profiles[player]
		local liveKeys = dirtyLive[player]
		if profile and player.Parent then
			local payload = { Data = {}, Live = {} }
			for key in keys do
				payload.Data[key] = profile.Data[key]
			end
			if liveKeys then
				for key in liveKeys do
					payload.Live[key] = live[player][key]
				end
				dirtyLive[player] = nil
			end
			dataPatchRemote:FireClient(player, payload)
		end
	end
	table.clear(dirtyData)

	for player, keys in dirtyLive do
		local liveTable = live[player]
		if liveTable and player.Parent then
			local payload = { Data = {}, Live = {} }
			for key in keys do
				payload.Live[key] = liveTable[key]
			end
			dataPatchRemote:FireClient(player, payload)
		end
	end
	table.clear(dirtyLive)
end

local function onPlayerAdded(player: Player)
	local profile = profileStore:LoadProfileAsync("Player_" .. player.UserId, "ForceLoad")
	if profile == nil then
		-- Another server kept the session lock / DataStores are down.
		player:Kick("We couldn't load your data. Please rejoin in a moment.")
		return
	end

	profile:AddUserId(player.UserId) -- GDPR compliance
	local fromVersion = ProfileTemplate.Migrate(profile.Data)
	profile:Reconcile()
	if fromVersion ~= ProfileTemplate.CurrentVersion then
		print(`[DataService] Migrated {player.Name} from v{fromVersion} to v{ProfileTemplate.CurrentVersion}`)
	end

	profile:ListenToRelease(function()
		profiles[player] = nil
		live[player] = nil
		dirtyData[player] = nil
		dirtyLive[player] = nil
		-- The profile may have been force-loaded by another server.
		player:Kick("Your data was opened on another server. Please rejoin.")
	end)

	if not player:IsDescendantOf(Players) then
		-- Player left while the profile was loading.
		profile:Release()
		return
	end

	local data = profile.Data
	local isNew = data.FirstJoin == 0
	if isNew then
		data.FirstJoin = os.time()
	end
	data.Stats.Joins += 1

	profiles[player] = profile
	live[player] = {}

	DataService.ProfileLoaded:Fire(player, data, isNew)
	sendInit(player)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		DataService.ProfileReleasing:Fire(player, profile.Data)
		profile.Data.LastOnline = os.time()
		profile:Release()
	end
	profiles[player] = nil
	live[player] = nil
	dirtyData[player] = nil
	dirtyLive[player] = nil
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function DataService:GetProfile(player: Player)
	local profile = profiles[player]
	if profile and profile:IsActive() then
		return profile
	end
	return nil
end

function DataService:GetData(player: Player)
	local profile = self:GetProfile(player)
	return profile and profile.Data
end

function DataService:IsLoaded(player: Player): boolean
	return self:GetProfile(player) ~= nil
end

-- Yields until the player's profile is loaded (or they leave / timeout passes).
function DataService:WaitForProfile(player: Player, timeout: number?)
	local deadline = os.clock() + (timeout or 30)
	while player.Parent and os.clock() < deadline do
		local profile = self:GetProfile(player)
		if profile then
			return profile
		end
		task.wait(0.1)
	end
	return self:GetProfile(player)
end

-- Runs mutator(data) (must not yield) and marks the given top-level keys for replication.
function DataService:Update(player: Player, keys: { string } | string, mutator: ((data: any) -> ())?): boolean
	local profile = self:GetProfile(player)
	if not profile then
		return false
	end
	if mutator then
		mutator(profile.Data)
	end
	local dirty = dirtyData[player]
	if not dirty then
		dirty = {}
		dirtyData[player] = dirty
	end
	if type(keys) == "string" then
		dirty[keys] = true
	else
		for _, key in keys do
			dirty[key] = true
		end
	end
	return true
end

function DataService:GetLive(player: Player, key: string): any
	local liveTable = live[player]
	return liveTable and liveTable[key]
end

function DataService:SetLive(player: Player, key: string, value: any)
	local liveTable = live[player]
	if not liveTable then
		return
	end
	if type(value) ~= "table" and liveTable[key] == value then
		return
	end
	liveTable[key] = value
	local dirty = dirtyLive[player]
	if not dirty then
		dirty = {}
		dirtyLive[player] = dirty
	end
	dirty[key] = true
end

function DataService:GetLoadedPlayers(): { Player }
	local list = {}
	for player, profile in profiles do
		if profile:IsActive() and player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function DataService:Init(services)
	self.Services = services

	local ProfileService = loadProfileService()
	profileStore = ProfileService.GetProfileStore(Config.Data.StoreName, ProfileTemplate.Template)
	if RunService:IsStudio() and Config.Data.UseMockInStudio then
		profileStore = profileStore.Mock
		warn("[DataService] Using ProfileService mock store in Studio — data will NOT save.")
	end

	dataInitRemote = Net.Event("DataInit")
	dataPatchRemote = Net.Event("DataPatch")
end

function DataService:Start()
	Net.Event("DataRequest").OnServerEvent:Connect(function(player)
		sendInit(player)
	end)

	-- Settings: only keys that exist in the template, with the template's type.
	Net.Event("UpdateSetting").OnServerEvent:Connect(function(player, key, value)
		if type(key) ~= "string" then
			return
		end
		local default = ProfileTemplate.Template.Settings[key]
		if default == nil or type(value) ~= type(default) then
			return
		end
		self:Update(player, "Settings", function(data)
			data.Settings[key] = value
		end)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(Config.Data.ReplicationInterval)
			flush()
		end
	end)
end

return DataService
