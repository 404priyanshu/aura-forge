--!strict
-- Util — formatting and table helpers shared by server and client.

local Util = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qd", "Qn", "Sx", "Sp", "Oc", "No", "Dc" }

-- "2.50" → "2.5", "3.00" → "3", "100" → "100" (only trims after a decimal point)
local function trimZeros(text: string): string
	if not string.find(text, ".", 1, true) then
		return text
	end
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

-- 1234 → "1.23K", 15300000 → "15.3M". Values under 1,000 are shown whole.
function Util.Abbreviate(value: number): string
	if value ~= value then
		return "0"
	end
	local negative = value < 0
	local n = math.abs(value)
	if n < 1000 then
		local text = tostring(math.floor(n))
		return if negative then "-" .. text else text
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / 10 ^ (tier * 3)
	local text
	if scaled >= 100 then
		text = string.format("%d", math.floor(scaled))
	elseif scaled >= 10 then
		text = string.format("%.1f", math.floor(scaled * 10) / 10)
	else
		text = string.format("%.2f", math.floor(scaled * 100) / 100)
	end
	text = trimZeros(text) .. SUFFIXES[tier + 1]
	return if negative then "-" .. text else text
end

-- 1234567 → "1,234,567"
function Util.Commas(value: number): string
	local text = tostring(math.floor(math.abs(value)))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	formatted = string.gsub(formatted, "^,", "")
	return if value < 0 then "-" .. formatted else formatted
end

-- 75 → "1:15", 3725 → "1:02:05"
function Util.Clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = s // 3600
	local m = (s % 3600) // 60
	local sec = s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, sec)
	end
	return string.format("%d:%02d", m, sec)
end

-- 5400 → "1h 30m", 90 → "1m 30s", 45 → "45s"
function Util.Duration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = s // 3600
	local m = (s % 3600) // 60
	local sec = s % 60
	if h > 0 then
		return if m > 0 then string.format("%dh %dm", h, m) else string.format("%dh", h)
	elseif m > 0 then
		return if sec > 0 then string.format("%dm %ds", m, sec) else string.format("%dm", m)
	end
	return string.format("%ds", sec)
end

-- probability 0.25 → "1 in 4"; 1/4096 → "1 in 4,096"; very rare → "1 in 10M"
function Util.Odds(probability: number): string
	if probability <= 0 then
		return "1 in ∞"
	end
	local oneIn = 1 / probability
	if oneIn < 10 then
		return "1 in " .. trimZeros(string.format("%.2f", oneIn))
	elseif oneIn < 1000000 then
		return "1 in " .. Util.Commas(math.floor(oneIn + 0.5))
	end
	return "1 in " .. Util.Abbreviate(oneIn)
end

function Util.DeepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[Util.DeepCopy(k)] = Util.DeepCopy(v)
	end
	return copy :: any
end

function Util.Color3ToHex(color: Color3): string
	return "#" .. color:ToHex()
end

-- Brightens (amount > 0) or darkens (amount < 0) a colour by lerping to white/black.
function Util.Shade(color: Color3, amount: number): Color3
	if amount >= 0 then
		return color:Lerp(Color3.new(1, 1, 1), amount)
	end
	return color:Lerp(Color3.new(0, 0, 0), -amount)
end

-- Validates that a remote argument is a finite number within [min, max].
function Util.IsFiniteNumber(value: any, min: number?, max: number?): boolean
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	if min and value < min then
		return false
	end
	if max and value > max then
		return false
	end
	return true
end

-- Validates that a remote argument is a reasonably short string.
function Util.IsShortString(value: any, maxLength: number?): boolean
	return type(value) == "string" and #value > 0 and #value <= (maxLength or 64)
end

return Util
