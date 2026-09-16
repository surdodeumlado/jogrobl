-- Prints, once at server start, everything that is still waiting on an id
-- from the Roblox site: gamepasses, developer products and sounds.
--
-- These can't be filled in from code — a gamepass id only exists after it's
-- created on the creator dashboard under the account that owns the
-- experience. What code *can* do is refuse to let them be forgotten: an
-- unconfigured gamepass is invisible in the shop (it renders as "Em breve"),
-- and an unconfigured sound is silent, so without this audit the failure mode
-- is a game that looks finished and quietly earns nothing.
--
-- This is a startup report, not a validation gate: it never stops the server,
-- because shipping a test session with placeholder ids is a completely normal
-- thing to do while building.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GamepassConfig = require(ReplicatedStorage.Shared.GamepassConfig)
local DeveloperProductConfig = require(ReplicatedStorage.Shared.DeveloperProductConfig)
local SoundConfig = require(ReplicatedStorage.Shared.SoundConfig)

local ConfigAudit = {}

local function collectUnset(entries, idField: string): { string }
	local missing = {}
	for key, definition in entries do
		if definition[idField] == 0 then
			table.insert(missing, key)
		end
	end
	table.sort(missing)
	return missing
end

function ConfigAudit.Start()
	local gamepasses = collectUnset(GamepassConfig, "AssetId")
	local products = collectUnset(DeveloperProductConfig, "ProductId")
	local sounds = collectUnset(SoundConfig.Sounds, "AssetId")

	if #gamepasses == 0 and #products == 0 and #sounds == 0 then
		print("[ConfigAudit] Todos os ids estão configurados.")
		return
	end

	warn("[ConfigAudit] Itens ainda sem id real — não rendem Robux nem tocam som até serem preenchidos:")

	if #gamepasses > 0 then
		warn(
			`  Gamepasses (crie em create.roblox.com -> sua experiência -> Monetização -> Passes, cole em GamepassConfig.AssetId): {table.concat(
				gamepasses,
				", "
			)}`
		)
	end

	if #products > 0 then
		warn(
			`  Developer Products (mesma página -> Produtos do Desenvolvedor, cole em DeveloperProductConfig.ProductId): {table.concat(
				products,
				", "
			)}`
		)
	end

	if #sounds > 0 then
		warn(
			`  Sons (Creator Store -> Áudio, cole em SoundConfig.Sounds.AssetId): {table.concat(sounds, ", ")}`
		)
	end
end

return ConfigAudit
