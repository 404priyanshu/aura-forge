--!strict
--[[
	Net — every RemoteEvent the game uses, created by the server at startup
	inside ReplicatedStorage.Remotes (you do NOT need to create them by hand).

	  Net.Event("RollRequest")  -- server: creates if missing; client: waits for it
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Events = {
	-- data replication
	"DataRequest", -- C→S  ask for a full snapshot
	"DataInit", -- S→C  (data, live)
	"DataPatch", -- S→C  { Data = {...}, Live = {...} } changed top-level keys only

	-- rolling
	"RollRequest", -- C→S  (useToken: boolean)
	"RollResult", -- S→C  result payload or { Ok = false, Reason = string }
	"SetAutoRoll", -- C→S  (enabled: boolean)

	-- economy / inventory
	"Click", -- C→S
	"Equip", -- C→S  (itemName)
	"Unequip", -- C→S  (itemName)
	"EquipBest", -- C→S
	"ClaimIndex", -- C→S  (rarityName)
	"BuyGemItem", -- C→S  (gemShopId)

	-- quests / retention
	"ClaimQuest", -- C→S  (questId)
	"ClaimDaily", -- C→S
	"ClaimPlaytime", -- C→S  (index)
	"TutorialDone", -- C→S

	-- settings
	"UpdateSetting", -- C→S  (key, value)

	-- notifications
	"Notify", -- S→C  (kind, payload)
	"Announce", -- S→C  { Text, Color, Tier }
}

local FOLDER_NAME = "Remotes"
local isServer = RunService:IsServer()

local function getFolder(): Folder
	if isServer then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder :: Folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

-- Server only: create every remote up front so clients never wait forever.
function Net.Setup()
	assert(isServer, "Net.Setup is server-only")
	for _, name in Net.Events do
		Net.Event(name)
	end
end

function Net.Event(name: string): RemoteEvent
	assert(table.find(Net.Events, name), "Unknown remote: " .. name)
	local folder = getFolder()
	if isServer then
		local existing = folder:FindFirstChild(name)
		if existing then
			return existing :: RemoteEvent
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

return Net
