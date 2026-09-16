# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

This is a Roblox place built with [Rojo](https://rojo.space/), managed via [Rokit](https://github.com/rojo-rbx/rokit). Code is written in Luau and lives outside the `.rbxlx` place file, then synced into Roblox Studio. The full MVP loop is implemented (collect → sell → upgrade → rebirth, plus pets, eggs, quests, zones, daily/playtime rewards, codes and monetization).

## Commands

Toolchain (Rojo 7.7.0, Wally) is pinned in `rokit.toml` and installed via Rokit:

```bash
rokit install
```

Install/update Wally packages (ProfileService lands in `ServerPackages/`, mapped by Rojo to `ServerScriptService.ServerPackages`) — required once after clone and after any `wally.toml` change:

```bash
wally install
```

Build the place file from source:

```bash
rojo build -o "jogrobl.rbxlx"
```

Serve for live sync with Roblox Studio (requires the Rojo Studio plugin installed and connected):

```bash
rojo serve
```

Type-check every Luau file (this is the only automated check in the project — there is no test runner):

```bash
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau src
```

`globalTypes.d.luau` is the Roblox API definition file, not checked in — fetch it from
`https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau`. Without `--definitions` every Roblox global reports as an error and the output is useless.

## Architecture

`default.project.json` defines the Rojo project tree, mapping source directories to Roblox service locations:

- `src/shared` → `ReplicatedStorage.Shared` — code accessible from both server and client (modules use `return function() ... end` / `return {}` style, e.g. `Hello.luau`)
- `src/server` → `ServerScriptService.Server` — server-only scripts (`init.server.luau` runs on the server)
- `src/client` → `StarterPlayer.StarterPlayerScripts.Client` — client-only scripts (`init.client.luau` runs on each client)

`default.project.json` also declares non-script instances baked into the place (the island and plaza, spawn, resource nodes, zone pads and the Zone 2 portal, the VIP room, the leaderboard boards, the `Lighting` stack, `SoundService`) and every `RemoteEvent` under `ReplicatedStorage.Remotes` — changes to world defaults or new remotes belong there, not in scripts.

The `Lighting` stack (Atmosphere + Bloom + ColorCorrection + SunRays, ShadowMap, ClockTime 14) is tuned for the bright cartoon look this genre uses, and it is by far the cheapest thing in the project per unit of visual improvement. Treat its values as a set: raising Brightness without also touching Ambient/ExposureCompensation just blows out the whites.

### Server modules (`src/server`)

`init.server.luau` calls `Start()` on each. Requiring is what wires modules together; `Start()` only connects listeners and kicks off loops. Two ordering constraints are load-bearing and commented inline (VipAreaService before GamepassService; PetService before RewardService).

- `PlayerDataManager` — ProfileService session-locked saves. Everything else reads/writes `GetProfile(player).Data`; nothing else touches DataStores.
- `PlayerStateService` — the single fan-out point: leaderstats, character stats, and the `ProfileUpdated` snapshot. Every service calls `Refresh(player)` right after mutating a profile. Modules that both mutate profiles *and* own a slice of the snapshot register via `RegisterSnapshotProvider` instead of being required here — that's what keeps PetService/RewardService out of a require cycle.
- `EconomyService` — the only module allowed to mutate Cash/Inventory/Rebirths/CashMultiplier.
- `ResourceNodeService` — owns node availability. Both walking into a node and pet auto-collection go through `TryCollect`, so neither can take a node the other already took.
- `PetService` — owns `EquippedPets` and all pet collection. Publishes equipped state as a `Player` attribute (comma-joined ids) rather than a remote.
- `HubBuilder` — builds the whole lobby from parts: plaza, four paths, the four station buildings, the mining field's crystal formations and the scenery. No meshes, no asset ids.
- `StationService` — binds what HubBuilder built: the sell pad's Touched, and the shop/egg/altar proximity prompts. Decides nothing; delegates to EconomyService/EggService.
- `ObjectiveService` — pays out the guided opening (`ObjectiveConfig`) and records that the welcome screen was seen.
- `WorldBuilder` — builds every gated zone island (geometry, nodes, pads) from `ZoneConfig` at startup. This is the one deliberate exception to "world defaults live in the project file": the zones are four copies of one structure whose differences are numbers `ZoneConfig` already holds, and authoring them by hand means writing each position twice with nothing keeping the copies equal. That is literally the bug that shipped once — a plaza widened in the project file silently buried the Zone 2 pad. The hub stays authored, because it is a one-off hand-laid space.
- `UnlockService` — grants the feature unlocks in `UnlockConfig` on a slow loop. Deliberately not called from `Refresh`: granting an unlock is itself a profile change that needs a refresh, so that would recurse, and a beat of delay makes the unlock read as a reward arriving rather than as part of the sale that triggered it.
- `LeaderboardService` — cross-server top-10 boards on OrderedDataStore, rendered onto parts in `Workspace.Leaderboards`. Writes once a minute per player and reads once a minute per board: DataStore budget is per-server and shared with ProfileService's saves, which matter more than a fast board.
- `ChampionDisplay` — the avatar of whoever is #1 on each board, standing on a podium beside it. Started by `LeaderboardService`, not by `init.server.luau`, because it is that module's presentation layer and has nothing to do before there are boards. The split is deliberate: `LeaderboardService` owns data, this owns a statue, and the only thing crossing between them is `Show(boardId, userId, name)` — so a failed avatar fetch can never make a board go blank. It builds the body and stops; the dance is `ChampionDance`'s job on the client, for a reason that is not a preference (see below).
- `ConfigAudit` — startup report of every id still set to `0`. Runs last so it isn't buried in startup noise.
- `EggService` (owns `Pets`), `UpgradeService` (owns `Upgrades`), `QuestService`, `RewardService`, `CodeService`, `CharacterService`, `ZoneService`, `VipAreaService`, `GamepassService`, `DeveloperProductService`, `Notifier`.

### Client modules (`src/client`)

- `Theme` — design tokens and styling primitives. `Widgets` — components built on them. `UI` — assembles the HUD and returns the instances to update. All three are pure view: no remotes, no game state.
- `init.client.luau` — the only file that touches remotes or MarketplaceService.
- `PetRenderer` — draws every player's pets locally from the replicated attribute. Deliberately client-side: nothing about a pet's drawn position is authoritative (the collect radius is measured from the player), so replicating dozens of per-frame CFrames would buy nothing.
- `Tutorial` — derives the current FTUE hint from the profile snapshot. No step counter, no persistence, nothing to dismiss.
- `Audio` — plays SFX and music locally. Client-side because most sounds are feedback for the person who caused it. Each sound gets a pool of voices so repeats overlap instead of cutting each other off (one instance per sound turned the pickup blip into a stutter once pets started collecting). Sounds marked `Spatial` play from a world position via `PlayAt` and are heard by everyone nearby — rebirth is deliberately both: a private 2D chime for the player plus a spatial boom for the server. Sounds with `AssetId = 0` are skipped, so the game runs silent-but-correct.
- `RebirthEffect` — the white aura burst, drawn locally on every client when any player rebirths. Built entirely from neon parts and tweens, no particles or textures, so it can't break from a moderated asset.
- `WorldFx` — floating "+N" popups at the point of collection, and the idle bob on resource nodes. The bob only moves nodes a fraction of a stud on purpose: the server's Touched hitbox uses its own copy, so any client-side movement is a lie about where the pickup really is. Popups are capped at 14 on screen and excess ones are dropped rather than queued.
- `ChampionDance` — puts the dance on the champion dummies `ChampionDisplay` built. Client-side because **an unpublished place refuses every animation id** (every fetch goes out as `serverplaceid=0`), and the only way round that is `KeyframeSequenceProvider:RegisterKeyframeSequence` on keyframes already sitting in the place — which returns an id local to whoever registered it. Registered on the server, the champion would dance to an empty room. Candidates in `AssetConfig.DANCE_ANIMATIONS` are tried first and *all* of them are reported (length, and whether they loaded) so the choice between supplied ids comes from one playtest rather than a guess; the place-local keyframes are the fallback, found by a name containing "danc" so it can't pick up `Mining Anim`. An animation authored for the wrong rig loads, reports a duration, plays and moves nothing — that is why the rig is checked and why the dummies are forced to R15.
- `HudDiagnostic` — dumps the HUD's real absolute geometry to the output as a stand-in for a screenshot. Gated behind `Constants.HUD_DIAGNOSTIC`, off by default. Turn it on when a layout looks wrong: it flags zero-sized, off-screen, edge-clipped and parent-overflowing elements, which is how the rail was found to be 352px tall inside a 282px viewport.

Any client-side arithmetic on costs, requirements or odds is a display preview only; the server recomputes all of it before charging or granting.

Naming convention: `init.server.luau` / `init.client.luau` at a directory root become the entry-point script for that directory when synced by Rojo; other `.luau` files in `src/shared` are ModuleScripts.

The built `jogrobl.rbxlx`, Studio lock files, and `sourcemap.json` are gitignored — treat them as generated artifacts, never edit them directly.

## Visão geral do jogo

- Gênero: Simulator/Tycoon idle híbrido (mesma categoria de Grow a Garden, Pet/Mining Simulator) no Roblox, escrito em Luau.
- Sync: Rojo (`rojo serve` + plugin no Studio). Nunca editar scripts direto pelo Script Editor do Studio — toda edição acontece nos arquivos desta pasta.
- Objetivo: MVP jogável e testável no Studio, focado em validar o game loop antes de investir em arte/conteúdo.

## Game loop principal

1. Jogador coleta um recurso (clique manual ou hitbox de coleta).
2. Vende o inventário acumulado por moeda ("Cash").
3. Usa o Cash para comprar upgrades que aumentam taxa/valor de coleta.
4. Ao atingir um teto de Cash, pode fazer "Rebirth": reseta o progresso e ganha um multiplicador permanente de Cash.
5. Cada rebirth acelera a progressão seguinte — esse é o gancho central de retenção diária.

## Estrutura de pastas (Rojo)

- `src/server/` → toda lógica autoritativa (economia, dados, gamepasses, developer products). O client NUNCA calcula valores de economia, só envia intenção via RemoteEvent.
- `src/client/` → UI e captura de input.
- `src/shared/` → ModuleScripts de configuração compartilhados (ItemsConfig, Constants, tipos).

## Convenções de código obrigatórias

- Toda alteração de moeda/inventário roda validada no servidor.
- Usar uma lib de proteção de DataStore com session-locking (ProfileService ou DataStore2) — nunca DataStoreService puro sem isso.
- Debounce obrigatório em qualquer RemoteEvent disparado por clique do jogador.
- PascalCase para nomes de Script/ModuleScript, camelCase para variáveis locais.
- Comentar o "porquê" de decisões não óbvias, não o "o quê" (o código já diz o quê).

## Estratégia de monetização (regra de negócio, não mude sem perguntar)

- Gamepasses = 60-70% da superfície de monetização: upgrades permanentes, preço entre 49 e 199 Robux (ex: 2x Cash, 2x Luck, Auto-Sell, VIP Area).
- Developer Products = 30-40%: pacotes de moeda consumíveis, "revive", chaves.
- Nunca vender vantagem que trave o progresso de quem não paga — vender conveniência, velocidade e cosméticos, nunca vitória.
- O sistema de Rebirth é o funil de conversão principal: o motivo de compra mais comum deve ser "acelerar o próximo rebirth".

## Regra estrutural: o que é mundo e o que é UI

A divisão que o gênero usa, e que este projeto errou por completo na primeira versão:

- **Mundo:** spawn, zonas atrás de portões, áreas de coleta, **pad de venda** (pisa e vende), **chocadeira** (ovos em pedestais com ProximityPrompt), **loja de melhorias** (prompt), **altar de rebirth** (prompt).
- **UI:** contador de mochila, moeda, objetivo atual, índice de pets, missões, recompensas, loja de Robux.

Vender, chocar e renascer eram botões de HUD. Isso deixava o mapa sem função — e um mapa sem função é o lobby vazio que o jogo tinha. **Não devolva nenhuma dessas ações para a UI.** Se uma ação nova precisar de lugar, ela ganha uma estação (`StationConfig`), não um botão.

O que segura tudo isso de pé é a **mochila com limite** (`Constants.BASE_BACKPACK` + upgrade `Backpack`): ela enche, obriga a viagem de volta, e a viagem passa pelas lojas. Sem o limite, não existe motivo para sair da pedra em que você está.

## Loop central: minerar

O verbo do jogo é **golpear**. Cada nó tem vida (`ItemsConfig.NodeHealth`); o jogador segura o clique, `Mining` (client) escolhe o alvo vivo mais próximo dentro de `MINE_RANGE` e pede golpes no ritmo do próprio `SwingInterval`; `ResourceNodeService` (server) revalida **tudo** — nó registrado, distância real, intervalo que os upgrades daquele jogador realmente compraram, dano — e só então aplica. Quando a vida zera, o nó paga e some.

Isso existe porque o jogo antes não tinha verbo: andar em cima de uma esfera não é uma ação, não tem resistência e não tem escalada — um nó no minuto 1 era idêntico a um nó na hora 5. Com vida, todo upgrade de Dano vira algo que se sente.

Três consequências de design que vieram de graça e não devem ser desfeitas:

- **Pets batem junto** por uma fração do dano do jogador (`PET_DAMAGE_SHARE`), então escalam com os mesmos upgrades em vez de virarem renda paralela irrelevante.
- **O chefe de servidor é um nó** com vida enorme e ledger de dano por jogador. Não reimplementa nada de mineração — é `BossService` só somando quem bateu e dividindo o prêmio. É a camada social do jogo.
- **Uma propriedade, um dono.** A vida do nó viaja como atributo (replica de graça, todos veem a mesma pedra rachar); o CFrame do nó pertence a `Mining` (recuo do golpe) e a mais ninguém — dois sistemas escrevendo a mesma propriedade por frame significa que o último ganha e o efeito some.

## Pets: tiers e fusão

Pets são identificados em todo lugar pela chave `"petId:tier"` — nunca por um petId solto. `PetConfig.Key` e `PetConfig.Parse` são os únicos lugares onde esse formato existe; não escreva a concatenação à mão.

`Pets` no perfil virou **contagem de espécies descobertas** (alimenta o índice). O inventário real é `PetTiers`. `PlayerDataManager.migrate` traz perfis antigos para essa forma — é idempotente e roda em todo load.

Fundir 5 de um tier gera 1 do próximo. **Empate no bônus bruto, ganho puro em slots** (5×1 = 1×5), porque slots são o recurso escasso. Por isso o bônus de Cash conta *cada cópia*, não uma por espécie: se duplicatas não valessem nada, fundir seria imposto em vez de escolha — e era exatamente esse o problema, com o próprio config admitindo que duplicatas não faziam nada.

`DamageMultiplier` sobe mais devagar que `BonusMultiplier` de propósito: pets causam uma fração do dano do jogador, e 25x em seis slots tornaria a picareta irrelevante.

## Cosméticos

Skins de picareta (`SkinConfig`), construídas com cor e material de partes — sem asset. A posse é **re-derivada do perfil** a cada checagem (rebirths ou gamepass), nunca concedida e guardada: nada para sincronizar, e quem compra o passe no meio da sessão recebe na hora.

Quase todas são ganhas por rebirth. Isso segue a regra do projeto — vender conveniência e cosmético, nunca progresso — e dá a escada de status de graça; a paga é um atalho que não concede vantagem nenhuma.

## Razão variável: a variância é o produto

O loop tinha recompensa fixa — todo cristal dava exatamente 1 drop por exatamente o mesmo dano. A teoria de compulsion loop é direta sobre isso: pagamento fixo é a versão fraca, e o que transforma um grind em algo que se quer repetir é *cada resposta ter uma chance* de recompensa.

Duas escalas de tempo, de propósito:

- **Críticos** (`CRIT_*`) — vários por minuto, então a expectativa mora dentro de cada golpe. Rolados no servidor, escalam com Sorte.
- **Veios ricos** (`RICH_*`) — surgem a cada poucos minutos, são dourados e visíveis de longe, então a expectativa também mora em *olhar em volta*. São estado de servidor compartilhado: um veio que só você vê é um bônus privado, um que todos veem é algo que as pessoas apontam e disputam.

Sorte (`EconomyService.GetLuck`) é a fonte única para ambos e para os ovos. Não duplique essa fórmula — foi o que fez a Sorte ser um stat invisível por metade do desenvolvimento.

**Ao rebalancear, simule antes.** Uma simulação do início revelou 44 segundos segurando o clique até a primeira venda e a árvore de upgrades esgotada antes do primeiro rebirth; nenhum dos dois aparecia lendo os configs.

## Estrutura de progressão

Duas escadas, e as duas existem porque um idle só continua interessante enquanto novas camadas se abrem:

**Zonas** (`ZoneConfig`) — 5 ilhas, cada uma com tema visual próprio, um recurso próprio valendo ~3x a anterior, e um portão de Rebirths (0 / 1 / 3 / 6 / 10). O salto de valor por tier tem que ser grande o bastante para que ir adiante ganhe de continuar moendo onde já se está; senão o jogador acampa na área inicial e nunca vê o conteúdo.

**Recursos liberados** (`UnlockConfig`) — o jogo começa só com coletar e vender. Melhorias, missões, ovos, pets, recompensas e loja aparecem um a um conforme marcos são batidos. A loja é a última de propósito. O HUD sempre mostra qual é o próximo e o quanto falta.

Ao mexer no balanceamento, mexa nas duas juntas: destravar tudo cedo demais devolve o jogo ao estado em que ele parecia sem graça, e espaçar demais deixa o jogador sem nada novo por minutos.

## Roadmap do MVP — status

Concluído:

1. ✅ PlayerDataManager (ProfileService, session-locking)
2. ✅ EconomyService (coletar, vender, multiplicadores, rebirth)
3. ✅ RemoteEvents com validação 100% server-side e debounce por jogador
4. ✅ GamepassService (PromptGamePassPurchaseFinished + concessão de efeito)
5. ✅ ProcessReceipt idempotente para Developer Products
6. ✅ leaderstats (Cash, Rebirths)
7. ✅ UI completa: HUD, painéis de pets/melhorias/ovos/missões/recompensas/loja

Além do escopo original, já implementado: pets ativos (companheiros que orbitam e coletam), índice de pets, ovos, missões diárias, zonas por rebirth, área VIP, FTUE derivado do snapshot, sequência diária de 7 dias, presentes por tempo de sessão e códigos promocionais.

Também concluído: leaderboard global (`LeaderboardService`, OrderedDataStore, placares físicos em `Workspace.Leaderboards`) e a camada de áudio (`SoundConfig` + `Audio`).

Monetização: **completa**. Os 4 gamepasses e os 5 Developer Products têm ids reais.

Áudio: 6 dos 11 sons configurados (coleta, venda, clique, rebirth pessoal, rebirth do mundo, ovo lendário, música). Continuam mudos por falta de id: `Upgrade`, `Reward`, `ErrorBuzz`, `EggCommon`, `EggRare` — todos opcionais.

Qualquer id ainda em `0` é tratado como "não configurado": o botão da loja vira "Em breve" e não é clicável (prompt com id 0 dá erro), e o som simplesmente não toca. `ConfigAudit` lista os pendentes no output ao subir o servidor.

Único item de código pendente antes de publicar: nenhum.

Próximos candidatos de retenção, na ordem em que fazem sentido dado o tamanho da base: evento coletivo de servidor (D7–D30, exige servidor populado) e só depois trading (D30+, exige economia com itens raros e validação anti-dupe/scam).

## Autonomia de design e monetização

O Claude **pode decidir sozinho** sobre balanceamento, ritmo, monetização e UX,
guiado pelos padrões de game design e faturamento do Roblox — retenção D1/D7,
desenho do core loop, estrutura de FTUE, cadência de recompensa, preço e
posicionamento de gamepass/produto. Não precisa perguntar antes; decide, aplica,
explica o porquê em uma linha, e o usuário corrige se ficar ruim.

Isso **não** afrouxa as regras duras logo abaixo, que continuam invioláveis, nem
os limites de preço em Robux — esses são decisão do usuário.

Referências que orientam essas decisões (levantadas em pesquisa de campo):

- **Os primeiros cinco minutos decidem o D1.** O jogador pergunta "isso é
  divertido?" e uma tela de instruções não responde. Cortar explicação, mostrar
  o jogo, dar um momento real antes do primeiro minuto.
- **Retenção antes de monetização.** Com D7 abaixo de ~15%, hora gasta em
  gamepass é hora que devia ter ido para o loop.
- **Lançar com 2-3 gamepasses**, medir duas semanas, expandir pelo que vender.
- **Cliffhangers seguram o retorno:** progresso incompleto perto de um marco,
  sequência diária, algo cozinhando enquanto você está offline.
- **Performance é o terceiro fator de D1**, junto com loop e FTUE. O censo do
  `WorldAudit` existe para isso — alvo abaixo de 8.000 peças no Workspace.
- **Cosmético e conveniência batem pay-to-win no longo prazo.**

Quando uma decisão dessas for tomada, o porquê vai no comentário do código, não
só na conversa — o próximo a ler o arquivo precisa dele mais do que o usuário.

**Ao rebalancear, simular antes.** Já foi assim que apareceram os 44 segundos
até a primeira venda, os 23 minutos até o primeiro rebirth, e o 8º rebirth
colapsando para 90 segundos. Nenhum dos três era visível lendo os configs.

## O que nunca fazer

- Nunca confiar em valores vindos do client sem revalidar no servidor.
- Nunca preço acima de 199 Robux em item de massa (só cosméticos raros/VIP podem fugir disso).
- Nunca travar progresso atrás de paywall obrigatório — free-to-progress sempre, pagar só acelera.
