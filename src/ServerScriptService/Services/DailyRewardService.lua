--[[
	DailyRewardService — retention rewards.

	  * Daily login: 7-day escalating cycle (Config.Daily). Days are UTC calendar
	    days. Claiming on the next day continues the streak; skipping a day
	    resets it to day 1.
	  * Playtime rewards: one claim every Config.Playtime.Interval seconds of the
	    current server session, up to #Config.Playtime.Rewards.
	  * Onboarding: grants Config.Tutorial.CompletionReward when the client
	    finishes the 3-popup tutorial (once per account).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)
local Util = require(Modules.Util)
local Net = require(Modules.Net)

local DailyRewardService = {}

local Services
local DataService

local DAY = 86400

local sessionStart: { [Player]: number } = {} -- os.clock() at join
local sessionClaims: { [Player]: { boolean } } = {}

local function dayIndex(unix: number): number
	return unix // DAY
end

-- Returns: canClaim, the streak value after claiming, the reward-cycle day (1..7)
function DailyRewardService:GetDailyState(data, now: number): (boolean, number, number)
	local today = dayIndex(now)
	local last = data.Daily.LastClaim
	local cycle = #Config.Daily.Rewards
	if last > 0 and dayIndex(last) == today then
		return false, data.Daily.Streak, ((data.Daily.Streak - 1) % cycle) + 1
	end
	local continues = last > 0 and today - dayIndex(last) == 1
	local newStreak = if continues then data.Daily.Streak + 1 else 1
	return true, newStreak, ((newStreak - 1) % cycle) + 1
end

function DailyRewardService:ClaimDaily(player: Player)
	local data = DataService:GetData(player)
	if not data then
		return
	end
	local now = os.time()
	local canClaim, newStreak, cycleDay = self:GetDailyState(data, now)
	if not canClaim then
		Services.EventService:Toast(
			player,
			"Already claimed today — come back tomorrow!",
			Color3.fromRGB(255, 190, 60)
		)
		return
	end
	DataService:Update(player, "Daily", function(d)
		d.Daily.Streak = newStreak
		d.Daily.LastClaim = now
	end)
	local text = Services.EconomyService:GrantReward(player, Config.Daily.Rewards[cycleDay], "Daily")
	Services.EventService:Notify(player, "Popup", {
		Title = `Day {cycleDay} reward claimed!`,
		Text = `You received {text}.\nStreak: {newStreak} day{if newStreak == 1 then "" else "s"} 🔥`,
		Color = Color3.fromRGB(255, 190, 60),
	})
end

function DailyRewardService:ClaimPlaytime(player: Player, index: any)
	if not Util.IsFiniteNumber(index, 1, #Config.Playtime.Rewards) or index % 1 ~= 0 then
		return
	end
	local start = sessionStart[player]
	local claims = sessionClaims[player]
	if not start or not claims or claims[index] or not DataService:IsLoaded(player) then
		return
	end
	local elapsed = os.clock() - start
	if elapsed + 1 < index * Config.Playtime.Interval then -- 1s grace for clock drift
		return
	end
	claims[index] = true
	DataService:SetLive(player, "PlaytimeClaims", table.clone(claims))
	local text = Services.EconomyService:GrantReward(player, Config.Playtime.Rewards[index], "Playtime")
	Services.EventService:Toast(player, `⏱️ Playtime reward: {text}`, Color3.fromRGB(90, 200, 255))
end

function DailyRewardService:CompleteTutorial(player: Player)
	local data = DataService:GetData(player)
	if not data or data.Tutorial.Completed then
		return
	end
	DataService:Update(player, "Tutorial", function(d)
		d.Tutorial.Completed = true
	end)
	local text = Services.EconomyService:GrantReward(player, Config.Tutorial.CompletionReward, "Tutorial")
	Services.EventService:Toast(player, `🎁 Tutorial bonus: {text}`, Color3.fromRGB(190, 120, 255))
end

function DailyRewardService:Init(services)
	Services = services
	DataService = services.DataService
end

function DailyRewardService:Start()
	Net.Event("ClaimDaily").OnServerEvent:Connect(function(player)
		self:ClaimDaily(player)
	end)
	Net.Event("ClaimPlaytime").OnServerEvent:Connect(function(player, index)
		self:ClaimPlaytime(player, index)
	end)
	Net.Event("TutorialDone").OnServerEvent:Connect(function(player)
		self:CompleteTutorial(player)
	end)

	DataService.ProfileLoaded:Connect(function(player, data)
		sessionStart[player] = os.clock()
		sessionClaims[player] = table.create(#Config.Playtime.Rewards, false)
		-- Server time (shared clock) so the client can count down accurately.
		DataService:SetLive(player, "SessionStartedAt", Workspace:GetServerTimeNow())
		DataService:SetLive(player, "PlaytimeClaims", table.clone(sessionClaims[player]))

		local canClaim = self:GetDailyState(data, os.time())
		if canClaim then
			task.delay(4, function()
				if player.Parent then
					Services.EventService:Toast(
						player,
						"🎁 Your daily reward is ready!",
						Color3.fromRGB(255, 190, 60)
					)
				end
			end)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		sessionStart[player] = nil
		sessionClaims[player] = nil
	end)
end

return DailyRewardService
