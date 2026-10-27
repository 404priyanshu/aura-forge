--[[
	Server bootstrapper (Script).

	Requires every ModuleScript in ServerScriptService/Services, calls Init on
	all of them (wire-up only, no yielding work), then Start on all of them.
	Each service receives the shared `services` table in Init, so services
	reference each other through it instead of requiring each other directly
	(no circular requires).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net"))

-- Order matters for Start(): data first, then systems that depend on it.
local LOAD_ORDER = {
	"DataService",
	"EventService",
	"MonetizationService",
	"EconomyService",
	"InventoryService",
	"RollService",
	"QuestService",
	"DailyRewardService",
	"AdminService",
}

Net.Setup()

local servicesFolder = script.Parent:WaitForChild("Services")
local services = {}

for _, name in LOAD_ORDER do
	local module = servicesFolder:WaitForChild(name, 5)
	assert(module, `[Server] Missing service module {name}`)
	services[name] = require(module)
end

-- Pick up any extra services you add without editing LOAD_ORDER.
for _, module in servicesFolder:GetChildren() do
	if module:IsA("ModuleScript") and not services[module.Name] then
		services[module.Name] = require(module)
		table.insert(LOAD_ORDER, module.Name)
	end
end

for _, name in LOAD_ORDER do
	local service = services[name]
	if type(service.Init) == "function" then
		service:Init(services)
	end
end

-- DataService starts LAST: it begins loading profiles, so every other service
-- must already be listening to ProfileLoaded.
local startOrder = table.clone(LOAD_ORDER)
table.remove(startOrder, table.find(startOrder, "DataService"))
table.insert(startOrder, "DataService")

for _, name in startOrder do
	local service = services[name]
	if type(service.Start) == "function" then
		local ok, err = pcall(service.Start, service)
		if not ok then
			warn(`[Server] {name}:Start failed: {err}`)
		end
	end
end

print(`[Server] {#LOAD_ORDER} services started`)
