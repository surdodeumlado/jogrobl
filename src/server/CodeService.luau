-- Redeems promo codes. One redemption per code per player, forever
-- (RedeemedCodes on the profile), so a code is worth the same whether a
-- player finds it on day one or day thirty.
--
-- Codes are normalized before lookup — uppercased and stripped of
-- surrounding whitespace — because players paste them out of videos and
-- articles with stray spaces and random capitalization, and "wrong" is an
-- awful thing to tell someone who typed the right code.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local PlayerStateService = require(script.Parent.PlayerStateService)
local Notifier = require(script.Parent.Notifier)
local CodeConfig = require(ReplicatedStorage.Shared.CodeConfig)

local CodeService = {}

-- Long enough for any real code, short enough that a modified client can't
-- make the server do string work on a megabyte of junk.
local MAX_CODE_LENGTH = 32

local function normalize(rawCode: string): string
	return string.upper((string.gsub(rawCode, "%s", "")))
end

function CodeService.Redeem(player: Player, rawCode: string): boolean
	if #rawCode > MAX_CODE_LENGTH then
		return false
	end

	local profile = PlayerDataManager.GetProfile(player)
	if profile == nil then
		return false
	end

	local code = normalize(rawCode)
	local definition = CodeConfig[code]
	if definition == nil then
		Notifier.Send(player, "error", "Código inválido")
		return false
	end

	if profile.Data.RedeemedCodes[code] == true then
		Notifier.Send(player, "error", "Você já resgatou esse código")
		return false
	end

	profile.Data.RedeemedCodes[code] = true
	profile.Data.Cash += definition.Cash

	PlayerStateService.Refresh(player)
	Notifier.Send(player, "success", `Código resgatado! +{definition.Cash} Cash`)

	return true
end

return CodeService
