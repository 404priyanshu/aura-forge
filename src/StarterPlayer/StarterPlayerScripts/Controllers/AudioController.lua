--[[
	AudioController — background music playlist + one-shot SFX.

	Sound IDs live in Config.Audio. Empty IDs are skipped silently, so the game
	works before you pick audio. Music/SFX toggles come from the saved Settings.

	  AudioController:Play("Click", volumeScale?, pitch?)
]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules.Config)

local AudioController = {}

local musicGroup: SoundGroup
local sfxGroup: SoundGroup
local templates: { [string]: Sound } = {}
local musicSound: Sound
local sfxEnabled = true

local function makeGroup(name: string, volume: number): SoundGroup
	local group = Instance.new("SoundGroup")
	group.Name = name
	group.Volume = volume
	group.Parent = SoundService
	return group
end

function AudioController:Play(key: string, volumeScale: number?, pitch: number?)
	if not sfxEnabled then
		return
	end
	local template = templates[key]
	if not template then
		return
	end
	local sound = template:Clone()
	sound.Volume = template.Volume * (volumeScale or 1)
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(15, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

function AudioController:_startMusic()
	local playlist = Config.Audio.Music
	if #playlist == 0 then
		return
	end
	musicSound = Instance.new("Sound")
	musicSound.Name = "Music"
	musicSound.SoundGroup = musicGroup
	musicSound.Volume = 1
	musicSound.Parent = SoundService

	task.spawn(function()
		local index = math.random(1, #playlist)
		while true do
			musicSound.SoundId = playlist[index]
			musicSound.Looped = #playlist == 1
			musicSound:Play()
			if musicSound.Looped then
				return
			end
			musicSound.Ended:Wait()
			index = index % #playlist + 1
		end
	end)
end

function AudioController:Init(controllers)
	self.Controllers = controllers
	musicGroup = makeGroup("Music", Config.Audio.MusicVolume)
	sfxGroup = makeGroup("SFX", Config.Audio.SfxVolume)

	for key, id in Config.Audio.Sfx do
		if id ~= "" then
			local sound = Instance.new("Sound")
			sound.Name = key
			sound.SoundId = id
			sound.Volume = 1
			sound.SoundGroup = sfxGroup
			templates[key] = sound
		end
	end
end

function AudioController:Start()
	local data = self.Controllers.DataController
	local UIKit = require(script.Parent.Parent.UI.UIKit)

	UIKit.ButtonClicked:Connect(function()
		self:Play("Click", 0.7)
	end)

	data:Observe("Settings", function(settings)
		musicGroup.Volume = if settings.Music then Config.Audio.MusicVolume else 0
		sfxEnabled = settings.Sfx
		sfxGroup.Volume = if settings.Sfx then Config.Audio.SfxVolume else 0
	end)

	-- Preload so the first reveal isn't silent.
	local preload = {}
	for _, sound in templates do
		table.insert(preload, sound)
	end
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, preload)
	end)

	self:_startMusic()
end

return AudioController
