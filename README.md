# OREBOUND

Um simulador de mineração para Roblox, escrito em Luau e sincronizado com o
Studio via [Rojo](https://rojo.space/). O código vive fora do arquivo `.rbxlx` —
o place é um artefato de build, não a fonte.

**O loop:** minerar → vender → melhorar → pegar pets → abrir mundos → renascer.

Vinte e cinco mundos, cada um com minério, picareta, ovo, cidade e área VIP
próprios. Cinquenta e uma espécies de pet com tiers e fusão. A mecânica que dá
identidade ao jogo é a **afinidade**: um pet mina 2,5x mais rápido no minério do
próprio mundo, então o melhor time depende de onde você está — o que transforma
duzentos pets numa coleção em vez de uma lista.

## Começando

O toolchain está fixado em `rokit.toml` e as dependências em `wally.toml`.
Depois de clonar:

```bash
rokit install     # Rojo, Wally
wally install     # ProfileService -> ServerPackages/
```

O luau-lsp precisa das definições da API do Roblox, que **não** estão no
repositório (quase um megabyte gerado, muda a cada release):

```bash
curl -o globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
```

## Comandos

```bash
rojo build -o "jogrobl.rbxlx"   # gera o place
rojo serve                      # sincroniza com o Studio (precisa do plugin)
```

Checagem de tipos — é a única verificação automatizada do projeto, não há suíte
de testes:

```bash
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau src
```

No lugar de testes unitários existem **auditorias que rodam no boot, só em
Studio**, e cada checagem delas corresponde a um defeito que o projeto
realmente teve:

| Auditoria | O que verifica |
|---|---|
| `EconomyAudit` | mundos que não pagam melhor que o anterior, preço inalcançável, tutorial que pede o que não pagou, teto de Robux |
| `WorldAudit` | faces coplanares (que piscam), objetos órfãos, censo de instâncias do **servidor** |
| `ConfigAudit` | qualquer id de asset ainda em `0` |

## Estrutura

| Pasta | Vai para | O que é |
|---|---|---|
| `src/server/` | `ServerScriptService.Server` | toda a lógica autoritativa — economia, dados, gamepasses |
| `src/client/` | `StarterPlayerScripts.Client` | UI e captura de input |
| `src/shared/` | `ReplicatedStorage.Shared` | configuração lida pelos dois lados |

`default.project.json` é a árvore do projeto e também declara as instâncias
fixas do place (iluminação, spawn, placares, RemoteEvents). Mudança em padrão de
mundo ou remote novo vai ali, não em script.

### As regras que sustentam o resto

- **O cliente nunca calcula valor de economia.** Ele manda intenção por
  RemoteEvent; o servidor revalida tudo antes de cobrar ou conceder. Toda
  aritmética no cliente é preview de exibição.
- **Um dono por propriedade.** A vida do nó viaja como atributo; o CFrame dele
  pertence ao `Mining` e a mais ninguém. Dois sistemas escrevendo a mesma
  propriedade por quadro significa que o último ganha e o efeito some.
- **Os mundos são construídos sob demanda.** As 24 ilhas de uma vez somavam
  36 mil instâncias e o cliente não conseguia entrar. Todo consumidor de
  geometria escuta `ChildAdded`/`DescendantAdded`, então uma ilha construída no
  minuto quarenta é ligada como uma do segundo um.
- **Atributo antes do pai.** Parentear é o que anuncia a peça; um atributo
  escrito depois chega tarde demais para quem estava escutando.

## Comandos de desenvolvimento

`DevService` expõe comandos de chat (`/ajuda` lista todos) para testar sem
jogar horas: `/tudo`, `/ir <mundo>`, `/censo`, `/veloz`.

Eles funcionam **apenas em Studio**. Em servidor publicado a lista `ALLOWED`
dentro do módulo está vazia e o serviço retorna antes de registrar qualquer
comando — nada é exposto a jogador nenhum. Para testar em produção, acrescente
o próprio UserId àquela lista; deixá-la vazia é o padrão seguro.

## Licença e assets

O código é deste repositório. Os modelos, sons e animações vêm da Creator Store
e **não** são redistribuídos aqui: o `AssetLoader` os busca por id em tempo de
execução, e cada um precisa estar no inventário do dono do place. Um asset
ausente nunca quebra o jogo — o consumidor cai na versão construída com peças.
