-- The stations that make up the hub: where you sell, upgrade, hatch and
-- rebirth.
--
-- These used to be buttons in UI panels, which is the single biggest reason
-- the game didn't feel like anything in its genre. The shipped structure for a
-- Roblox simulator puts them in the *world* — the sell zone is "a large
-- glowing pad that, when stepped on, converts all held resources", the shop is
-- an NPC or proximity prompt, eggs are models you walk up to — and keeps the
-- UI for the backpack counter, the currency display and the Robux shop.
--
-- Doing it that way is not decoration. It is what gives the map a job: the
-- backpack fills, you walk back, and the walk passes the places that want your
-- money. A world you never need to cross is a world nobody looks at.
--
-- Layout: one STREET and one road. The quarry road south is lined with the four
-- things you do between loads — sell, pickaxes, eggs, upgrades — so the walk
-- home passes every one of them without a detour; the road north ends at the
-- rebirth altar, which is rare enough to deserve a trip of its own.
--
-- It started as a cross with a station on each spoke, on the wayfinding theory
-- that you should see all four from the middle. That theory lost to a stronger
-- one: what a player actually does is a lap, and every station off the lap is a
-- tax charged dozens of times an hour. The spokes were abandoned one at a time,
-- each for the same reason, and the honest description of the hub now is a high
-- street. All four are still visible from the plaza — they are simply in a row
-- instead of a circle.

export type StationKind = "Sell" | "Upgrades" | "Eggs" | "Rebirth" | "Pickaxes"

-- The shopkeeper standing in each stall.
--
-- Decoration with a job: an empty stall reads as scenery, a stall with someone
-- in it reads as a place that does something. Deliberately not interactive —
-- the client types the lines out in a bubble over their head when you walk up,
-- and they can be ignored completely. Nothing here has to be dismissed,
-- closed or clicked through before the player can use the prompt behind it,
-- because a dialogue box between a player and the thing they walked over to
-- buy is a tax, not flavour.
--
-- Names are short and language-neutral on purpose. This game is meant to ship
-- worldwide and to be translated, and a name that needs an accent, a regional
-- honorific or a cultural reference to land is a name most of the playerbase
-- reads as noise. Three or four letters, no diacritics, pronounceable in any
-- language that will ever load this place.
export type NpcDefinition = {
	Name: string,
	Lines: { string },
}

export type StationDefinition = {
	Id: string,
	Kind: StationKind,
	DisplayName: string,
	Subtitle: string,
	Position: Vector3, -- centre of the building, on the ground
	Facing: number, -- degrees of Y rotation; every station faces the plaza
	Color: Color3,
	Accent: Color3,
	Icon: string,
	Npc: NpcDefinition,
	-- Sell is laid out by hand: it stands beside the quarry road rather than at
	-- the end of a path of its own. See HubBuilder.buildQuarryRoad.
	NoPath: boolean?,
}

local StationConfig = {}

-- Distance from spawn to each station.
--
-- This was 34 and the hub felt like a box: a small plaza with four large
-- buildings looming at arm's length in every direction. Comfort in an open
-- hub comes from the landmarks being *far* and clearly visible, not near and
-- crowding — you want to see where you're going from the middle, not feel
-- walled in by it.
-- Pushed out with the plaza, which grew from a 26-stud radius to 40 so the
-- leaderboards could live inside it. Keeping the stations at 64 would have put
-- them 24 studs off the kerb — looming, which is the exact problem moving them
-- out to 64 solved in the first place.
--
-- Only Rebirth uses this now. The other four ended up on the quarry road, which
-- is what the hub actually turned out to be: one street where you earn and
-- spend, plus one long road north to the altar. The altar keeps its distance on
-- purpose — rebirthing is rare and deliberate, and the walk is the ceremony.
StationConfig.RING = 92

-- The sell station sits closer than the other three. It is the one building
-- the player crosses on every single trip home, so putting it at the same
-- distance as the others would add a walk to a journey they already make
-- dozens of times an hour.
StationConfig.SELL_RING = 66

StationConfig.Stations = {
	{
		Id = "Sell",
		Kind = "Sell",
		DisplayName = "VENDA",
		Subtitle = "Pise no pad para vender tudo",
		-- BESIDE the road south, not across it.
		--
		-- It used to sit dead centre at (0, 0, 44), directly between the plaza
		-- and the quarry — which meant the one place a new player has to find,
		-- the mine, was hidden behind a building from the only spot they ever
		-- start from. A stall on the route is good level design; a stall
		-- blocking the route is a wall with a sign on it.
		--
		-- Now it stands to one side with its pad reaching into the road, so the
		-- walk home still crosses it and the quarry is visible from the middle
		-- of the plaza.
		Position = Vector3.new(32, 0, StationConfig.SELL_RING),
		-- Facing -90 turns its front (local +Z) toward world -X, which is the
		-- road.
		Facing = -90,
		NoPath = true,
		Color = Color3.fromRGB(58, 170, 92),
		Accent = Color3.fromRGB(126, 232, 150),
		Icon = "💰",
		Npc = {
			Name = "Mona",
			-- Seven or eight lines each, and the client picks one at random per
			-- visit rather than cycling. Four was enough to notice the loop by
			-- the second trip home, and the trip home happens constantly.
			Lines = {
				"Pode despejar tudo no pad, eu conto depois!",
				"Mochila cheia parada não vale nada, viu?",
				"Cristal está em alta hoje. Traz mais.",
				"Cada renascimento seu aumenta o que eu te pago.",
				"Já vi gente carregar meia hora e esquecer de vender.",
				"Rubi eu pago cinco vezes o cristal. Pensa nisso.",
				"Não precisa fila. O pad atende todo mundo junto.",
				"Volta sempre. De preferência cheio.",
			},
		},
	},
	{
		Id = "Upgrades",
		Kind = "Upgrades",
		DisplayName = "MELHORIAS",
		Subtitle = "Mais dano, mochila e velocidade",
		-- Moved off the west spoke and onto the quarry road, opposite the sell
		-- pad, with the pickaxe shop as its neighbour.
		--
		-- It stood 92 studs due west, which is a walk in the opposite direction
		-- from everything a run is made of: you mine south, you sell south, and
		-- then you turned around and crossed the whole square to spend. Selling
		-- and spending are one errand and now they are one street.
		--
		-- The plaza loses its west road because of this. That is a real cost —
		-- the four roads lined up with four of the sixteen spokes — and it is
		-- worth paying: a road to nowhere reads worse than an asymmetric square.
		Position = Vector3.new(-34, 0, 52),
		Facing = 90,
		NoPath = true,
		Color = Color3.fromRGB(48, 126, 210),
		Accent = Color3.fromRGB(126, 194, 255),
		Icon = "⛏️",
		Npc = {
			Name = "Rex",
			Lines = {
				"Picareta boa não é luxo, é economia de tempo.",
				"Dano primeiro. Mochila quando cansar de voltar.",
				"Velocidade de golpe é o que ninguém compra cedo. Erro.",
				"Andar mais rápido também conta.",
				"Tudo que você compra aqui some no renascimento. É de propósito.",
				"Bônus de venda é caro e compensa tarde. Deixa pro fim.",
				"Golpe crítico vem da sorte, não da força bruta.",
				"Melhor uma picareta afiada que dez viagens.",
			},
		},
	},
	{
		Id = "Eggs",
		Kind = "Eggs",
		DisplayName = "CHOCADEIRA",
		Subtitle = "Choque ovos e ganhe pets",
		-- On the quarry road, east side, across from the pickaxe shop.
		--
		-- It stood 92 studs due east — perpendicular to everything a run is made
		-- of, about 113 studs off the route each way. That made hatching the one
		-- purchase in the game that is not on the street, and hatching is the
		-- purchase this game's identity rests on: pets are the differentiator,
		-- they orbit you and leave the orbit to strike, and the egg is the most
		-- replayed moment in the genre. Charging a fourteen-second detour for the
		-- best thing in the game is the most expensive toll here.
		--
		-- This is the same argument that moved Upgrades off the west spoke, and
		-- the same conclusion: selling and spending are one errand, so they are
		-- one street. The east road disappears with it, exactly as the west one
		-- did — a road to nowhere reads worse than an asymmetric square, and the
		-- project has already made that trade once.
		--
		-- z = 96 rather than 90 (which would mirror Pickaxes exactly) because the
		-- stalls are 24 deep: at 90 this one's front edge would land on the sell
		-- stall's back edge, and two faces on one plane strobe.
		Position = Vector3.new(34, 0, 96),
		-- Front (local +Z) turned toward world -X, which is the road.
		Facing = -90,
		NoPath = true,
		Color = Color3.fromRGB(226, 142, 52),
		Accent = Color3.fromRGB(255, 202, 120),
		Icon = "🥚",
		Npc = {
			Name = "Pip",
			Lines = {
				"Shhh... esse aqui está mexendo.",
				"Pet não é enfeite: eles batem junto com você.",
				"Junta cinco iguais que eu fundo num melhor.",
				"Sorte alta chocando ovo é outra coisa.",
				"Dourado vale cinco comuns. Arco-íris, vinte e cinco.",
				"Cada renascimento te dá mais um espaço de pet.",
				"Repetido não é lixo: é matéria-prima pra fusão.",
				"Já chocou hoje? Não custa tentar de novo.",
			},
		},
	},
	{
		-- The fifth stall, on the north-west diagonal.
		--
		-- The rack stood loose in the open beside the upgrades road first, and
		-- ten pickaxes on plinths in the middle of a field reads as clutter
		-- rather than as a shop — there was nothing to say the row was a place.
		-- Every other thing you buy in this game has a building, a keeper and a
		-- road; the most expensive purchase in the game had none of the three.
		--
		-- On the quarry road, across from the sell pad, beside the upgrade shop.
		--
		-- The diagonals were both wrong. North-west put it under the VIP deck;
		-- north-east put it a hundred and thirty studs from the shop it belongs
		-- next to and nowhere near the one route every player actually walks.
		--
		-- The route is the whole argument. A run ends at the sell pad, and the
		-- two things you spend the money on should be the next things you pass —
		-- not a separate errand on the far side of the square. So the road south
		-- becomes a street: selling on the east side, spending on the west.
		--
		-- NoPath for the same reason Sell has it — a radial road from here would
		-- cut across the quarry road at an angle.
		Id = "Pickaxes",
		Kind = "Pickaxes",
		DisplayName = "PICARETAS",
		Subtitle = "Cada uma bate mais forte que a anterior",
		Position = Vector3.new(-34, 0, 90),
		-- Front (local +Z) turned toward +X, which is the road.
		Facing = 90,
		NoPath = true,
		Color = Color3.fromRGB(168, 116, 58),
		Accent = Color3.fromRGB(240, 196, 118),
		Icon = "⛏️",
		Npc = {
			Name = "Brek",
			Lines = {
				"Picareta boa não é luxo, é ferramenta.",
				"Essa de pedra aí já dobra o que você tira.",
				"Renasceu? Então tem coisa nova na prateleira pra você.",
				"Olha o preço, olha o dano. Faz a conta.",
				"A de madeira serve. Serve pra começar.",
				"Já forjei picareta pra gente que virou lenda.",
				"Não vendo sorte. Vendo dano.",
				"Leva a próxima. Você volta mais rápido.",
			},
		},
	},
	{
		Id = "Rebirth",
		Kind = "Rebirth",
		DisplayName = "RENASCER",
		Subtitle = "Zere tudo por um multiplicador eterno",
		Position = Vector3.new(0, 0, -StationConfig.RING),
		Facing = 0,
		Color = Color3.fromRGB(150, 84, 222),
		Accent = Color3.fromRGB(212, 160, 255),
		Icon = "⭐",
		Npc = {
			Name = "Zia",
			Lines = {
				"Zerar tudo assusta. Depois você não para mais.",
				"Cada renascimento vale mais que o anterior.",
				"Dá pra comprar as outras ilhas sem renascer. Boa sorte.",
				"Perde o Cash, ganha o multiplicador. Pra sempre.",
				"O multiplicador é composto. Ele não soma, ele dobra sobre si.",
				"Quem não renasce paga o mesmo preço com o dobro do tempo.",
				"As melhorias somem. O multiplicador fica. Sempre valeu a pena.",
				"Não existe atalho. Existe alavanca.",
			},
		},
	},
} :: { StationDefinition }

-- Where the starter crystals live: directly south of the plaza, at the end of
-- the one road that is not blocked by a building. The player's whole first
-- loop is a straight line — mine, walk north, cross the sell pad, reach the
-- plaza. Far enough that a full backpack is a real trip, close enough that the
-- first one is about five seconds of walking.
StationConfig.MiningFieldCenter = Vector3.new(0, 0, 138)
StationConfig.MiningFieldRadius = 34

-- The starter outcrop: a handful of crystals on the lawn just outside the
-- plaza kerb, framing the mouth of the quarry road.
--
-- This exists for the first sixty seconds and nothing else. Measured against
-- the real layout, a new player used to spawn in the middle of a 40-stud
-- plaza and walk 104 studs — five seconds of nothing — before they could hit
-- anything, and the first Cash landed around forty seconds in. In this genre
-- that is the number that decides whether they stay: the verb has to happen
-- almost immediately.
--
-- Two steps outside the kerb puts the first swing at about two and a half
-- seconds and the first payout near eleven. The full quarry stays where it is
-- and becomes a promotion — "now go to the real one" — instead of a toll gate
-- on the way in.
--
-- Deliberately OUTSIDE the plaza, not in it. The rule that keeps the square
-- empty is a level-design rule, not a tidiness one: the plaza is the decision
-- point of the map, and anything standing in it blocks a sightline to one of
-- the four stations.
StationConfig.StarterPatchCenter = Vector3.new(0, 0, 54)

-- The VIP terrace: which way it runs off the plaza, where the gate stands, and
-- how far the deck reaches.
--
-- Here rather than inside HubBuilder because two modules need the same answer
-- now. HubBuilder builds the ramp and the deck from these; VipAreaService uses
-- them to work out whether a player is standing somewhere they did not pay to
-- stand. Two copies of a boundary is how a gate ends up guarding a line the
-- enforcement does not know about.
StationConfig.Vip = {
	-- The one diagonal no road uses.
	Direction = Vector3.new(-1, 0, -1).Unit,
	GateDistance = 50,
	-- How high the ramp already is where it leaves the gate. It does not start
	-- on the floor, which is why it needs rails.
	RampFootY = 1.5,
	RampEnd = 82,
	DeckY = 14,
	DeckHalf = 21,
	-- Half the ramp's width including its rails. The guard needs this separately
	-- from the deck's: the lawn on either side of the ramp is ordinary hub, and
	-- a band as wide as the terrace would have swept it in.
	RampHalf = 12,
}

-- The deck's near edge has to land exactly where the ramp ends, or there is a
-- step to fall down. Derived rather than typed, so it cannot drift.
StationConfig.Vip.DeckDistance = StationConfig.Vip.RampEnd + StationConfig.Vip.DeckHalf - 1

-- The stretch of the diagonal the guard watches.
StationConfig.Vip.GuardFrom = StationConfig.Vip.GateDistance + 2
StationConfig.Vip.GuardTo = StationConfig.Vip.DeckDistance + StationConfig.Vip.DeckHalf + 4

-- How far above the VIP walking surface a player has to be to count as standing
-- ON it.
--
-- The test is against the SURFACE at that point, not against a flat height, and
-- getting that wrong is easy in both directions. A flat "higher than three
-- studs" sweeps up anyone who jumps on the lawn near the gate; a flat height
-- tall enough to survive a jump lets a trespasser walk half the ramp before
-- anything notices. Measured against the ramp's own slope, standing on it is
-- unambiguous — a character's root sits about three studs above its feet — and
-- the open ground UNDER the ramp and the terrace stays free, which it has to:
-- that is ordinary hub anyone may walk through.
StationConfig.Vip.GuardClearance = 1.5

-- The height of the VIP walking surface at a given distance along the diagonal:
-- up the slope of the ramp, then flat across the deck.
function StationConfig.VipSurfaceY(along: number): number
	local vip = StationConfig.Vip
	if along >= vip.RampEnd then
		return vip.DeckY
	end

	local progress = (along - vip.GateDistance) / (vip.RampEnd - vip.GateDistance)
	-- Plus half the ramp slab, because the number wanted is what you stand on,
	-- not where its centre is.
	return vip.RampFootY + (vip.DeckY - vip.RampFootY) * math.clamp(progress, 0, 1) + 0.8
end

-- Is this point on the paid side of the gate, standing on VIP ground?
function StationConfig.IsInsideVip(position: Vector3): boolean
	local vip = StationConfig.Vip

	local along = position:Dot(vip.Direction)
	if along < vip.GuardFrom or along > vip.GuardTo then
		return false
	end

	local across = Vector3.new(-vip.Direction.Z, 0, vip.Direction.X)
	local halfWidth = if along >= vip.RampEnd then vip.DeckHalf + 1 else vip.RampHalf
	if math.abs(position:Dot(across)) > halfWidth then
		return false
	end

	return position.Y > StationConfig.VipSurfaceY(along) + vip.GuardClearance
end

function StationConfig.Get(stationId: string): StationDefinition?
	for _, station in StationConfig.Stations do
		if station.Id == stationId then
			return station
		end
	end
	return nil
end

return StationConfig
