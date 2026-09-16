-- Data-driven definition of every sound the game plays.
--
-- AssetId = 0 means "no audio picked yet", and Audio.Play treats those as a
-- silent no-op — exactly like GamepassConfig's unset ids render as "Em breve"
-- instead of throwing. The whole audio layer therefore ships working and
-- silent, and turning it on is only a matter of pasting ids here.
--
-- How to fill these in:
--   1. Creator Store -> Audio in Studio (or create.roblox.com/store/audio),
--      filtered to what you're allowed to use in an experience you own.
--   2. Copy the asset id and paste the bare number below.
--   3. Audio the account doesn't have rights to simply won't play in a
--      published place, so verify in a real play session, not just in Studio.
--
-- PitchVariation exists because Collect fires many times per second once a
-- player has pets — an identical sample at an identical pitch on repeat is
-- the fastest way to make people mute a game. A small random spread makes a
-- burst read as texture instead of a machine gun.

-- Spatial sounds play from a point in the world and fade with distance, so
-- they belong to the event rather than to the listener: everyone nearby hears
-- them, quieter the further away they are. Everything else is 2D — it plays
-- at full volume for the one person whose action caused it, and nobody else
-- hears it at all.
--
-- The distinction matters most for rebirth, which is genuinely two events at
-- once: a private "you levelled up" for the player, and a public "something
-- big happened over there" for everyone in earshot.

--------------------------------------------------------------------------
-- A HIERARQUIA. O volume é decidido pela FREQUÊNCIA, não pela importância.
--------------------------------------------------------------------------
--
-- É a mesma coisa vista de outro lado: um som que toca o tempo todo não pode
-- ser alto, senão os raros não têm para onde subir. O teto é fixo, então cada
-- decibel gasto num evento comum é um decibel que o evento raro não tem.
--
-- Quatro faixas, e todo som novo tem que declarar em qual entra:
--
--   0.08 - 0.20   CONSTANTE. Várias vezes por segundo ou por minuto. Golpe,
--                 coleta, notificação, toque em NPC. Textura, não aviso.
--   0.20 - 0.32   FREQUENTE. Alguns por minuto. Crítico, clique de UI,
--                 teleporte, venda. Percebido sem interromper.
--   0.32 - 0.45   EVENTO. Algumas vezes por sessão. Melhoria, veio rico,
--                 recompensa, ovo raro. Faz a pessoa olhar.
--   0.45 - 0.60   MARCO. Poucas vezes na vida do jogador, ou por hora.
--                 Renascimento, mundo novo, pet lendário.
--
-- Dois desvios foram corrigidos ao escrever isto, e os dois eram da mesma
-- forma: um som frequente ocupando a faixa de um raro.
--
--   * Crítico estava em 0.45, empatado com o renascimento. Um crítico acontece
--     dezenas de vezes por minuto e um renascimento poucas vezes por sessão —
--     com os dois no mesmo volume, o renascimento deixava de ser um marco.
--   * Clique de UI e teleporte estavam na faixa de evento, e acontecem a cada
--     poucos segundos.
--
-- O veio rico subiu, e por um motivo além da hierarquia: ele é espacial, então
-- perde volume com a distância. Para chegar ao ouvido como um evento ele tem
-- que sair da fonte mais alto que um som 2D da mesma faixa.

export type SoundDefinition = {
	AssetId: number,
	Volume: number,
	PitchVariation: number?, -- +/- fraction applied to PlaybackSpeed per play
	-- Base playback speed. Shifts the whole sample, so one recording can serve
	-- as a family of related cues instead of five separate uploads.
	Pitch: number?,
	Looped: boolean?,
	Spatial: boolean?, -- played at a world position via Audio.PlayAt
	RollOffMin: number?, -- studs of full volume before it starts fading
	RollOffMax: number?, -- studs at which it's inaudible
}

local SoundConfig: { [string]: SoundDefinition } = {
	-- One click per letter of NPC dialogue, Undertale-style.
	--
	-- Volume is 0.08, which looks absurd next to everything else here and is
	-- correct: this fires thirty-odd times a second while a line types itself
	-- out. At any normal level it stops being a texture and becomes a machine
	-- gun. The pitch wobble keeps a long sentence from sounding mechanical.
	NpcTap = {
		AssetId = 3623733749,
		Volume = 0.08,
		PitchVariation = 0.08,
	},
	-- Every button in the HUD, through one hook.
	--
	-- Widgets.button routes all of them through Theme.pressJuice, and Audio.Start
	-- hangs this sound off that — so there is no Play call per button and a rail
	-- icon, a shop row and a claim button cannot end up with different clicks.
	UiClick = {
		AssetId = 88442833509532,
		Volume = 0.26,
		-- The same sample at the same pitch, pressed as often as a HUD button is
		-- pressed, stops reading as feedback and starts reading as a rattle.
		PitchVariation = 0.04,
	},
	-- The single most repeated sound in the game: it fires on every swing that
	-- lands, several times a second. Whatever goes here has to be very short
	-- and very quiet, or it becomes the whole soundtrack.
	Hit = {
		AssetId = 87668602821268,
		Volume = 0.16,
		PitchVariation = 0.15,
	},
	-- Fires on maybe one swing in twelve, so it can afford to be louder and
	-- more distinctive than the ordinary hit. The contrast is the reward.
	Crit = {
		AssetId = 3581383408,
		Volume = 0.28,
	},
	Collect = {
		AssetId = 134602992766192,
		-- Quieter than everything else on purpose: this is the only sound that
		-- fires continuously (every pickup, and pets pick up several times a
		-- second), so it has to sit under the mix rather than on top of it.
		Volume = 0.18,
		PitchVariation = 0.12,
	},
	Sell = {
		AssetId = 134810204798705,
		Volume = 0.3,
	},
	-- Upgrade, Reward and ErrorBuzz share the notification recording at three
	-- pitches.
	--
	-- All three sat at AssetId 0 — silent — for the whole of development, and
	-- silence on a purchase is worse than a sound that is merely adequate. A
	-- single sample shifted up, further up and down does not read as three
	-- copies of one noise; it reads as a family, which is what a UI sound set is
	-- supposed to be. Replace any of them with its own upload and nothing else
	-- has to change.
	Upgrade = {
		AssetId = 106553517979212,
		Volume = 0.34,
		Pitch = 1.18,
	},
	-- Personal half of the rebirth: the "you levelled up" chime, 2D, heard
	-- only by the player who rebirthed.
	Rebirth = {
		AssetId = 114390175182916,
		Volume = 0.52,
	},
	-- Public half: heard by everyone near the player who rebirthed, fading
	-- with distance. Kept well under the personal chime so that standing next
	-- to a serial rebirther is atmosphere, not an assault.
	RebirthWorld = {
		AssetId = 123714125705157,
		Volume = 0.35,
		Spatial = true,
		RollOffMin = 12,
		RollOffMax = 110,
	},
	-- Claiming Cash you have earned but not yet taken: a quest reward, a daily,
	-- a playtime gift, an objective payout.
	--
	-- The SELL recording, not the notification blip it used to borrow. Every one
	-- of these is the same event as stepping on the sell pad — a pile of Cash
	-- arriving because you asked for it — and a player should not have to learn
	-- two cues for one feeling. It was a pitched-up UI ping, which said
	-- "something happened" rather than "you got paid".
	--
	-- A touch brighter than Sell itself so the two are siblings and not clones:
	-- selling is a transaction, a reward is a bonus.
	Reward = {
		AssetId = 134810204798705,
		Volume = 0.45,
		Pitch = 1.12,
	},
	-- Every toast, every new objective, and the moment the bag fills.
	--
	-- One sound for all of them on purpose. A notification is the game asking
	-- you to look at the HUD, and a player learns one cue far faster than four
	-- — the point is "something changed up there", not which subsystem changed
	-- it. Quiet, because it fires often: the bag fills several times a minute
	-- once the loop is running.
	-- Unlocking a world for the first time. Once per world, ever.
	--
	-- This is the "I found something" sound, and what makes it work is scarcity:
	-- it played on every arrival before, which meant a player heard the fanfare
	-- for discovery on the fortieth trip back from the same island. A cue that
	-- fires on a routine action stops meaning the thing it was chosen for.
	--
	-- Four times in a player's whole life, one per gated world. Louder than
	-- anything else here and with no pitch variation — the one thing it has to
	-- do is mark a moment.
	NewWorld = {
		AssetId = 134085405153726,
		Volume = 0.55,
	},
	-- Um veio rico nascendo, tocado NO LUGAR dele.
	--
	-- Espacial de propósito, e é a coisa mais importante sobre este som: um veio
	-- rico é estado compartilhado do servidor, todos na ilha veem o mesmo
	-- cristal dourado, e um som que vem de uma direção faz duas pessoas olharem
	-- para o mesmo ponto. Um 2D faria cada um ouvir um aviso particular.
	--
	-- ID PRÓPRIO PENDENTE. Zero = não configurado, e Audio.Play trata isso como
	-- silêncio — o efeito visual (o anel dourado) toca de qualquer forma.
	--
	-- Estava dividindo o id com NewWorld, e isso era errado de um jeito que não
	-- aparece lendo o config: são dois eventos de peso completamente diferente
	-- com o mesmo timbre. Um mundo novo acontece um punhado de vezes na vida do
	-- jogador; um veio rico, várias vezes por sessão. Reusar o timbre gasta o
	-- marco para pagar o evento — que é exatamente o erro que a hierarquia de
	-- volumes acima existe para não cometer.
	--
	-- O que procurar na Creator Store: algo CURTO (menos de um segundo),
	-- metálico ou cristalino, sem cauda longa. Ele toca no ponto onde o veio
	-- nasce e tem que dizer "olha ali" sem competir com a picareta batendo.
	-- ConfigAudit lista este id como pendente no boot até ser preenchido.
	RichVein = {
		AssetId = 0,
		Volume = 0.42,
		Spatial = true,
	},
	-- Arriving anywhere by pad, including coming home.
	--
	-- The routine half of what used to be one sound. Quieter, because this one
	-- happens constantly: every trip out and every trip back.
	Teleport = {
		AssetId = 74715602103425,
		Volume = 0.22,
	},
	Notify = {
		AssetId = 106553517979212,
		-- Quiet. A notification competes with nothing — it only has to be
		-- noticed, and at 0.35 it was louder than the pickaxe hitting the rock,
		-- which is the sound the player is actually there for.
		Volume = 0.12,
		-- The same sample at the same pitch, several times a minute, stops
		-- registering as information and starts registering as a rattle. The
		-- collect blip already carries variation for exactly this reason.
		PitchVariation = 0.09,
	},
	-- Down rather than up. A refusal that rises sounds like a reward, which is
	-- the one thing it must never be mistaken for.
	ErrorBuzz = {
		AssetId = 106553517979212,
		Volume = 0.3,
		Pitch = 0.62,
	},
	-- One per rarity so a Legendary hatch doesn't sound like the 40th Gatinho.
	-- This is the single most replayed moment in the genre; it's worth three
	-- samples rather than one.
	--
	-- All three USED to be the Legendary fanfare at three pitches, on the theory
	-- that a pitch ladder reads as a family. It does not, and the difference
	-- matters here more than anywhere: a fanfare played quieter and lower is
	-- still a fanfare, so every common pet arrived announcing itself as a prize.
	-- Once the fortieth Gatinho has had the same celebration as the dragon, the
	-- celebration means nothing — which throws away the whole point of having
	-- rarities.
	--
	-- Common now borrows the short notification blip instead, pitched up bright.
	-- It is a "got one" and not a "LOOK WHAT YOU GOT", which is the actual
	-- distinction. A common hatch deserves its own real upload eventually; this
	-- is one id away from being right rather than one design away.
	EggCommon = {
		AssetId = 106553517979212,
		Volume = 0.3,
		Pitch = 1.28,
	},
	-- Rare gets the level-up chime, NOT the fanfare.
	--
	-- The fanfare at a lower pitch was still the fanfare — and the golden egg is
	-- 70% Rare, so in practice every single pull from it announced a jackpot.
	-- Two recordings cannot cover three rarities: pitching one of them is a
	-- variation, not a different event, and the ear hears the sample.
	--
	-- This borrows the rebirth chime, up a little so it is not mistaken for an
	-- actual rebirth. It reads as "nice one" between the common "got one" and
	-- the legendary "LOOK AT THIS", which is exactly the ladder that was
	-- missing. A real third upload would still be better than a borrowed one.
	EggRare = {
		AssetId = 114390175182916,
		Volume = 0.4,
		Pitch = 1.15,
	},
	-- The fanfare, and nothing else in the game, ever.
	--
	-- One pull in a hundred from the basic egg and one in twenty from the
	-- golden. That scarcity IS the sound: a celebration that fires on every
	-- hatch is not a celebration, it is the hatch noise.
	EggLegendary = {
		AssetId = 136357088509992,
		Volume = 0.6,
	},
	Music = {
		AssetId = 1848354536,
		Volume = 0.12, -- deliberately low; background music people notice is background music people turn off
		Looped = true,
	},
}

-- Maps a PetConfig rarity to its reveal sound key.
local RARITY_SOUNDS: { [string]: string } = {
	Common = "EggCommon",
	Rare = "EggRare",
	Legendary = "EggLegendary",
}

local module = {
	Sounds = SoundConfig,
	RaritySounds = RARITY_SOUNDS,
}

return module
