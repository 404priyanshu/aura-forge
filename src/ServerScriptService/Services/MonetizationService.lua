--[[
	MonetizationService — gamepasses, developer products and the gem shop.

	Gamepasses: ownership = saved flag (purchase / admin grant) OR
	UserOwnsGamePassAsync. Checked once on join, updated live by
	PromptGamePassPurchaseFinished. Fires PlayerReady once passes are known.

	Developer products (ProcessReceipt) are idempotent on two levels:
	  1. Global ledger DataStore keyed by PurchaseId — written only AFTER the
	     grant is confirmed saved, so a retried receipt is acknowledged instantly
	     even after the profile cache rolled over.
	  2. ProfileService's purchase-id MetaTag pattern — the PurchaseId is saved
	     in the SAME DataStore write as the reward, and we only return
	     PurchaseGranted once ProfileService confirms that write
	     (MetaTagsLatest). A crash before the save means Roblox retries the
	     receipt and nothing is lost or doubled.
]]

local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local Signal = require(Modules.Signal)
local Util = require(Modules.Util)
local Net = require(Modules.Net)

local MonetizationService = {}
MonetizationService.PlayerReady = Signal.new() -- (player) passes loaded, stats can be computed
MonetizationService.PassGranted = Signal.new() -- (player, passKey)

local Services
local DataService

local ownedPasses: { [Player]: { [string]: boolean } } = {}
local passKeyById: { [number]: string } = {}
local productKeyById: { [number]: string } = {}
local ledger: DataStore? = nil

local PURCHASE_IDS_TAG = "ProfilePurchaseIds"

---------------------------------------------------------------------------
-- Gamepasses
---------------------------------------------------------------------------
function MonetizationService:GetOwnedPasses(player: Player): { [string]: boolean }
	return ownedPasses[player] or {}
end

function MonetizationService:OwnsPass(player: Player, passKey: string): boolean
	local owned = ownedPasses[player]
	return owned ~= nil and owned[passKey] == true
end

local function applyPassEffects(player: Player)
	local owned = ownedPasses[player] or {}
	player:SetAttribute("VIP", owned.VIP == true)
	Services.EconomyService:RecomputeStats(player)
end

function MonetizationService:GrantPass(player: Player, passKey: string, fromPurchase: boolean?)
	local pass = Config.Gamepasses[passKey]
	if not pass then
		return
	end
	local owned = ownedPasses[player]
	if not owned then
		owned = {}
		ownedPasses[player] = owned
	end
	owned[passKey] = true
	DataService:Update(player, "Gamepasses", function(data)
		data.Gamepasses[passKey] = true
	end)
	applyPassEffects(player)
	self.PassGranted:Fire(player, passKey)

	if fromPurchase then
		Services.EventService:Notify(player, "Purchase", {
			Title = "Purchase complete!",
			Text = `{pass.Icon} {pass.Name} is now active. Thank you for your support!`,
		})
	end
end

local function loadPasses(player: Player, data)
	local owned = {}
	for passKey, pass in Config.Gamepasses do
		if data.Gamepasses[passKey] then
			owned[passKey] = true
		elseif pass.Id ~= 0 then
			local ok, result =
				pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
			if ok and result then
				owned[passKey] = true
			elseif not ok then
				warn(`[MonetizationService] Ownership check failed for {passKey}: {result}`)
			end
		end
	end
	if not player.Parent then
		return
	end
	ownedPasses[player] = owned
	DataService:Update(player, "Gamepasses", function(d)
		for passKey in owned do
			d.Gamepasses[passKey] = true
		end
	end)
	applyPassEffects(player)
	MonetizationService.PlayerReady:Fire(player)
end

---------------------------------------------------------------------------
-- Product effects
---------------------------------------------------------------------------
-- Applies a product/gem-shop entry. Returns a short description of what was granted.
function MonetizationService:ApplyGrant(player: Player, entry): string
	local economy = Services.EconomyService
	if entry.Kind == "Boost" then
		economy:AddBoost(player, entry.Boost, entry.Duration)
		local boost = Config.Boosts[entry.Boost]
		return `{boost and boost.DisplayName or entry.Boost} for {Util.Duration(entry.Duration)}`
	elseif entry.Kind == "Currency" then
		if entry.Currency == "Gems" then
			economy:AddGems(player, entry.Amount)
		else
			economy:AddCoins(player, entry.Amount, "Purchase", true)
		end
		local currency = Config.Currencies[entry.Currency]
		return `{Util.Commas(entry.Amount)} {currency and currency.DisplayName or entry.Currency}`
	elseif entry.Kind == "Tokens" then
		economy:AddRerollTokens(player, entry.Amount)
		return `{entry.Amount} {Config.Currencies.RerollTokens.DisplayName}`
	end
	warn(`[MonetizationService] Unknown grant kind {entry.Kind}`)
	return "?"
end

local function grantProduct(player: Player, productKey: string, receiptInfo)
	local product = Config.DevProducts[productKey]
	DataService:Update(player, "Purchases", function(data)
		data.Purchases.Products[productKey] = (data.Purchases.Products[productKey] or 0) + 1
		data.Purchases.RobuxSpent += receiptInfo.CurrencySpent or 0
	end)
	local granted = MonetizationService:ApplyGrant(player, product)
	Services.EventService:Notify(player, "Purchase", {
		Title = "Purchase complete!",
		Text = `{product.Icon} You received {granted}. Thank you!`,
	})
end

---------------------------------------------------------------------------
-- ProcessReceipt
---------------------------------------------------------------------------
local function purchaseIdCheckAsync(profile, purchaseId: string, grant: () -> ()): Enum.ProductPurchaseDecision
	if not profile:IsActive() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ids = profile:GetMetaTag(PURCHASE_IDS_TAG)
	if ids == nil then
		ids = {}
		profile:SetMetaTag(PURCHASE_IDS_TAG, ids)
	end

	if table.find(ids, purchaseId) == nil then
		while #ids >= Config.Monetization.ProfilePurchaseIdCache do
			table.remove(ids, 1)
		end
		table.insert(ids, purchaseId)
		task.spawn(grant)
	end

	-- Only acknowledge once the purchase id has actually been written to the DataStore.
	local result: Enum.ProductPurchaseDecision? = nil
	local function checkLatest()
		local saved = profile.MetaData.MetaTagsLatest[PURCHASE_IDS_TAG]
		if saved ~= nil and table.find(saved, purchaseId) ~= nil then
			result = Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	checkLatest()
	local connection = profile.MetaTagsUpdated:Connect(function()
		checkLatest()
		if result == nil and not profile:IsActive() then
			result = Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end)

	if result == nil and typeof(profile.Save) == "function" then
		profile:Save() -- speeds up confirmation instead of waiting for the next auto-save
	end

	while result == nil do
		task.wait()
	end
	connection:Disconnect()
	return result :: Enum.ProductPurchaseDecision
end

local function processReceipt(receiptInfo): Enum.ProductPurchaseDecision
	local purchaseId = tostring(receiptInfo.PurchaseId)

	-- 1) Global ledger fast path.
	if ledger then
		local ok, record = pcall(function()
			return (ledger :: DataStore):GetAsync(purchaseId)
		end)
		if ok and record ~= nil then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local productKey = productKeyById[receiptInfo.ProductId]
	if not productKey then
		warn(`[MonetizationService] Receipt for unknown product id {receiptInfo.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = DataService:WaitForProfile(player, 20)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 2) Atomic grant via the profile's purchase-id cache.
	local decision = purchaseIdCheckAsync(profile, purchaseId, function()
		grantProduct(player, productKey, receiptInfo)
	end)

	if decision == Enum.ProductPurchaseDecision.PurchaseGranted and ledger then
		task.spawn(function()
			local ok, err = pcall(function()
				(ledger :: DataStore):SetAsync(purchaseId, {
					UserId = receiptInfo.PlayerId,
					ProductId = receiptInfo.ProductId,
					Product = productKey,
					Time = os.time(),
				}, { receiptInfo.PlayerId })
			end)
			if not ok then
				warn("[MonetizationService] Ledger write failed (purchase is still safe):", err)
			end
		end)
	end

	return decision
end

---------------------------------------------------------------------------
-- Gem shop (spend gems in-game)
---------------------------------------------------------------------------
local function onBuyGemItem(player: Player, itemId: any)
	if not Util.IsShortString(itemId) then
		return
	end
	local entry
	for _, item in Config.GemShop do
		if item.Id == itemId then
			entry = item
			break
		end
	end
	if not entry or not DataService:IsLoaded(player) then
		return
	end
	if not Services.EconomyService:SpendGems(player, entry.Price) then
		Services.EventService:Toast(player, "Not enough Gems!", Color3.fromRGB(255, 90, 100))
		return
	end
	local granted = MonetizationService:ApplyGrant(player, entry)
	Services.EventService:Toast(player, `{entry.Icon} Bought {granted}`, Config.Currencies.Gems.Color)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function MonetizationService:Init(services)
	Services = services
	DataService = services.DataService

	for passKey, pass in Config.Gamepasses do
		if pass.Id ~= 0 then
			passKeyById[pass.Id] = passKey
		end
	end
	for productKey, product in Config.DevProducts do
		if product.Id ~= 0 then
			productKeyById[product.Id] = productKey
		end
	end

	local ok, store = pcall(DataStoreService.GetDataStore, DataStoreService, Config.Monetization.LedgerStoreName)
	if ok then
		ledger = store
	else
		warn("[MonetizationService] Receipt ledger unavailable (enable Studio API access):", store)
	end
end

function MonetizationService:Start()
	DataService.ProfileLoaded:Connect(loadPasses)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local passKey = passKeyById[passId]
		if passKey then
			self:GrantPass(player, passKey, true)
		end
	end)

	MarketplaceService.ProcessReceipt = processReceipt

	Net.Event("BuyGemItem").OnServerEvent:Connect(onBuyGemItem)

	Players.PlayerRemoving:Connect(function(player)
		ownedPasses[player] = nil
	end)
end

return MonetizationService
