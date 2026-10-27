--[[
	DataController — the client's live, read-only mirror of its player data.

	  DataController:Get("Currency")        -- saved data (top-level key)
	  DataController:GetLive("Luck")        -- server-computed session values
	  DataController:Observe("Currency", fn) -- fn(value) now (if loaded) and on every change
	  DataController:ObserveLive("Luck", fn)
	  DataController.Changed                -- Signal(key, value); live keys are "Live.<key>"

	The server is authoritative: never mutate these tables, fire a remote instead.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Signal = require(Modules.Signal)
local Net = require(Modules.Net)

local DataController = {}
DataController.Data = nil :: { [string]: any }?
DataController.Live = {} :: { [string]: any }
DataController.Loaded = false
DataController.Changed = Signal.new()
DataController.LoadedSignal = Signal.new()

function DataController:Get(key: string): any
	return self.Data and self.Data[key]
end

function DataController:GetLive(key: string): any
	return self.Live[key]
end

function DataController:Observe(key: string, fn: (any) -> ())
	if self.Data and self.Data[key] ~= nil then
		task.spawn(fn, self.Data[key])
	end
	return self.Changed:Connect(function(changedKey, value)
		if changedKey == key then
			fn(value)
		end
	end)
end

function DataController:ObserveLive(key: string, fn: (any) -> ())
	if self.Live[key] ~= nil then
		task.spawn(fn, self.Live[key])
	end
	local liveKey = "Live." .. key
	return self.Changed:Connect(function(changedKey, value)
		if changedKey == liveKey then
			fn(value)
		end
	end)
end

function DataController:WaitForData()
	while not self.Loaded do
		self.LoadedSignal:Wait()
	end
	return self.Data
end

function DataController:Init()
	Net.Event("DataInit").OnClientEvent:Connect(function(data, live)
		local firstLoad = not self.Loaded
		self.Data = data
		self.Live = live or {}
		self.Loaded = true
		if firstLoad then
			self.LoadedSignal:Fire()
		end
		for key, value in data do
			self.Changed:Fire(key, value)
		end
		for key, value in self.Live do
			self.Changed:Fire("Live." .. key, value)
		end
	end)

	Net.Event("DataPatch").OnClientEvent:Connect(function(patch)
		if not self.Loaded then
			return -- the full snapshot (already queued) will include this
		end
		if patch.Data then
			for key, value in patch.Data do
				self.Data[key] = value
				self.Changed:Fire(key, value)
			end
		end
		if patch.Live then
			for key, value in patch.Live do
				self.Live[key] = value
				self.Changed:Fire("Live." .. key, value)
			end
		end
	end)
end

function DataController:Start()
	Net.Event("DataRequest"):FireServer()
	-- Retry in case the first request raced the server loading the profile.
	task.spawn(function()
		for _ = 1, 10 do
			task.wait(3)
			if self.Loaded then
				return
			end
			Net.Event("DataRequest"):FireServer()
		end
	end)
end

return DataController
