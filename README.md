# jogo-estacoes (nome de trabalho)

Jogo de sobrevivência e gerenciamento em que cada estação é uma ameaça diferente. Alvo: venda na Steam.

## Engine
- **Godot 4.7.2-stable**, build padrão (GDScript, sem .NET). Versão fixada: só atualizar em fronteira de fase, após checar compatibilidade da integração com a Steam.

## Estrutura
| Pasta | Conteúdo |
|---|---|
| `data/` | Números de balanceamento e textos (nada de número hardcoded no código) |
| `scenes/` | Cenas `.tscn` |
| `scripts/` | GDScript, 1 sistema por arquivo |
| `assets/` | Arte, áudio e fontes — origem e licença registradas em CREDITOS.md |

## Fluxo
- `main` protegida; trabalho em branches `feat/...`, commits pequenos.
- Sem segredos no repositório (chaves Steamworks, tokens).
- Design, decisões e estado do projeto ficam fora do repo (ESTADO, DECISOES, BACKLOG, GDD).
