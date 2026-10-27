--[[
	Client bootstrapper (LocalScript in StarterPlayerScripts).

	Requires every controller, calls Init on all of them (UI is built here, no
	yielding work), then Start on all of them. Controllers reach each other
	through the shared `controllers` table passed to Init.
]]

local controllersFolder = script.Parent:WaitForChild("Controllers")

-- Order matters: data first, then audio and UI (others bind to the UI in Start).
local LOAD_ORDER = {
	"DataController",
	"AudioController",
	"UIController",
	"CurrencyController",
	"RollController",
}

local controllers = {}

for _, name in LOAD_ORDER do
	local module = controllersFolder:WaitForChild(name, 10)
	assert(module, `[Client] Missing controller {name}`)
	controllers[name] = require(module)
end

for _, module in controllersFolder:GetChildren() do
	if module:IsA("ModuleScript") and not controllers[module.Name] then
		controllers[module.Name] = require(module)
		table.insert(LOAD_ORDER, module.Name)
	end
end

for _, name in LOAD_ORDER do
	local controller = controllers[name]
	if type(controller.Init) == "function" then
		controller:Init(controllers)
	end
end

for _, name in LOAD_ORDER do
	local controller = controllers[name]
	if type(controller.Start) == "function" then
		local ok, err = pcall(controller.Start, controller)
		if not ok then
			warn(`[Client] {name}:Start failed: {err}`)
		end
	end
end
