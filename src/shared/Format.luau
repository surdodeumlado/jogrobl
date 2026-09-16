-- Number/time formatting shared by the client HUD and the server-rendered
-- world leaderboards. It lives in Shared rather than in the client Theme
-- because both sides now display Cash values, and two implementations of
-- "how do we write 1,240,000" would drift apart the first time one is tuned.

local Format = {}

-- Abbreviates large values the way this genre does (1.2K, 3.4M). Players read
-- a raw 7-digit number as noise, and it overflows every fixed-width pill on a
-- phone. Below 10K the exact number still fits and still means something to a
-- new player counting their first few hundred Cash.
function Format.Abbreviate(value: number): string
	local absolute = math.abs(value)
	if absolute >= 1e12 then
		return string.format("%.2fT", value / 1e12)
	elseif absolute >= 1e9 then
		return string.format("%.2fB", value / 1e9)
	elseif absolute >= 1e6 then
		return string.format("%.2fM", value / 1e6)
	elseif absolute >= 1e4 then
		return string.format("%.1fK", value / 1e3)
	end
	return tostring(math.floor(value))
end

function Format.Duration(seconds: number): string
	local clamped = math.max(math.floor(seconds), 0)
	return string.format("%d:%02d", clamped // 60, clamped % 60)
end

return Format
