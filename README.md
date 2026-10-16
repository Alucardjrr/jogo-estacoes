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

## Fluxo (D-028, D-029)
- **`main` = produção.** Protegida (PR + check `tests`). Só o autor promove, com PR `dev` → `main` depois de testar.
- **`dev` = integração.** Branches `feat/...` entram por PR com CI verde + `qa-revisor` aprovado (+ `diretor` quando há decisão).
- Commits pequenos, 1 sistema por arquivo.
- Equipe de agentes em `.claude/agents/`: `diretor`, `designer`, `roteirista`, `balanceamento`, `qa-revisor`.

## Ambientes no jogo (D-029)
- **dev**: editor e builds de debug, ou feature tag `dev`. Ferramentas de debug ligadas (modificadores na tela, `--speed=N`).
- **prod**: builds de release, ou feature tag `prod` (que vence `dev`). Sem ferramentas de debug.
- Sem segredos no repositório (chaves Steamworks, tokens).
- Design, decisões e estado do projeto ficam fora do repo (ESTADO, DECISOES, BACKLOG, GDD).
