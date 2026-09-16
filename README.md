# jogrobl

Um simulador de mineração/pets para Roblox, escrito em Luau e sincronizado com o
Studio via [Rojo](https://rojo.space/). O código vive fora do arquivo `.rbxlx` —
o place é um artefato de build, não a fonte.

O loop: **minerar → vender → melhorar → renascer**, com pets, ovos, missões,
zonas, recompensas diárias e monetização já implementados. Vinte e cinco mundos,
cada um com minério, picareta, ovo, cidade e área VIP próprios.

## Começando

O toolchain está fixado em `rokit.toml` e as dependências em `wally.toml`. Depois
de clonar:

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

## Estrutura

| Pasta | Vai para | O que é |
|---|---|---|
| `src/server/` | `ServerScriptService.Server` | toda a lógica autoritativa — economia, dados, gamepasses |
| `src/client/` | `StarterPlayerScripts.Client` | UI e captura de input |
| `src/shared/` | `ReplicatedStorage.Shared` | configuração lida pelos dois lados |

`default.project.json` é a árvore do projeto e também declara as instâncias
fixas do place (iluminação, spawn, placares, RemoteEvents). Mudança em padrão de
mundo ou remote novo vai ali, não em script.

A regra que sustenta o resto: **o client nunca calcula valor de economia**, só
manda intenção por RemoteEvent, e o servidor revalida tudo antes de cobrar ou
conceder.

`CLAUDE.md` tem a arquitetura em detalhe, as decisões de design e de
monetização, e o que nunca fazer.
