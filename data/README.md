# data/

Números de balanceamento e textos. Nada de número de jogo no código (D-004).
JSON não aceita comentário: os campos ficam documentados aqui. Todo arquivo é
validado ao carregar (`scripts/sim/data_registry.gd`); chave faltando, chave
desconhecida, tipo errado ou valor fora da faixa recusa o carregamento inteiro
e a tela de debug mostra o motivo.

Unidade de recurso: **1 = consumo diário de 1 pessoa**. Taxas `*_rate` são
frações por dia (0,004 = 0,4% do estoque por dia).

## balance/sim.json — relógio
| Campo | Tipo | Faixa | O que é |
|---|---|---|---|
| `seconds_per_day` | número | 0,05–60 | Segundos reais por dia em 1× |
| `speeds` | lista de inteiros | crescente, 1–10 | Velocidades disponíveis |
| `max_days_per_frame` | inteiro | 1–100 | Teto de dias simulados num frame (evita rajada após travamento) |
| `default_seed` | inteiro | 0–2147483647 | Semente do RNG quando nenhuma é passada |

## balance/calendar.json — calendário (D-022)
| Campo | Tipo | Faixa | O que é |
|---|---|---|---|
| `days_per_month` | inteiro | 1–365 | Dias por mês |
| `months_per_year` | inteiro | 1–24 | Meses por ano |
| `seasons[]` | lista | ≥ 1 | Estações na ordem do ano |
| `seasons[].id` | texto | `a-z0-9_` | Id único; texto em `SEASON_<ID>` |
| `seasons[].months` | inteiro | 1–24 | Duração; a soma precisa dar `months_per_year` |
| `seasons[].severe` | bool | — | Severa = sofre escalada anual |

## balance/season.json — estações (D-025, D-027)
| Campo | Tipo | Faixa | O que é |
|---|---|---|---|
| `intensity_per_year` | número | 0–1 | Escalada: intensidade = 1 + isto × (ano − 1), só nas severas |
| `intensity_max` | número | 1–5 | Teto da intensidade |
| `transition_days` | inteiro par | 0 – estação mais curta | Dias de mistura centrados na virada (metade de cada lado); 0 = brusco |
| `seasons.<id>` | objeto | um por estação do calendário | Taxas da estação |
| `.water_inflow` / `.food_inflow` | número | 0–100000 | Entrada natural por dia |
| `.water_loss_rate` / `.food_loss_rate` | número | 0–1 | Perda por dia (evaporação, estrago) |
| `.health_drift` | número | −10 a 10 | Variação diária de saúde (doença das chuvas) |
| `.gather_mult` | número | 0–10 | Rendimento de "buscar água" na estação (D-031) |
| `.farm_mult` | número | 0–10 | Rendimento da roça na estação (D-031) |
| `.escalation` | objeto | expoentes −3 a 3 | Grandeza × intensidade^expoente. Negativo = piora diminuindo |

## balance/resources.json — estoques (D-025)
| Campo | Tipo | Faixa | O que é |
|---|---|---|---|
| `resources.water` / `.food` | objeto | os dois obrigatórios | Um por recurso |
| `.initial` | número | 0–1000000, ≤ `capacity` | Estoque inicial |
| `.capacity` | número | 1–1000000 | Teto; excesso é perdido |
| `.per_capita_daily` | número | 0–100 | Consumo por pessoa por dia |

## balance/population.json — população (D-026)
| Campo | Tipo | Faixa | O que é |
|---|---|---|---|
| `families[]` | lista | ≥ 1 | `{id, size}`; id único, size 1–50 |
| `health_initial` / `health_max` | número | 0–1000 / 1–1000; inicial ≤ máximo | Saúde da colônia |
| `health_recovery_per_day` | número | 0–100 | Ganho de saúde em dia sem falta |
| `water_shortage_health` / `food_shortage_health` | número | 0–100 | Perda de saúde com 100% de falta (proporcional ao déficit) |
| `death_health_threshold` | número | 0–1000, ≤ `health_max` | Abaixo disso começam as mortes |
| `death_rate_max` | número | 0–1 | Chance diária por pessoa com saúde 0 |
| `departure_shortage_days` | inteiro | 1–1000 | Dias seguidos com falta até uma família ir embora |

## balance/labor.json — mão de obra (D-031)
| Campo | Tipo | Faixa | O que é |
|---|---|---|---|
| `worker_share` | número | 0–1 | Fração da população que trabalha (arredonda para baixo) |
| `full_productivity_health` | número | > 0 | Saúde a partir da qual a produtividade é 100% |
| `min_productivity` | número | 0–1 | Produtividade com saúde 0 (linear até o limiar) |
| `water_per_worker` / `food_per_worker` | número | 0–1000 | Produção por trabalhador por dia, antes do multiplicador da estação |
| `care_health_per_share` | número | 0–1000 | Saúde/dia = isto × cuidadores ÷ pessoas |
| `care_health_max` | número | 0–100 | Teto do ganho de saúde pelo cuidado |
| `fatigue_threshold` | número | 0–0,99 | Fração da força buscando água a partir da qual há fadiga |
| `fatigue_health` | número | 0–100 | Perda de saúde/dia com 100% da força na água (proporcional ao excesso) |
| `initial_allocation` | objeto | `water`, `farm`, `care`, `build`, `salvage` inteiros ≥ 0 | Distribuição inicial (linha de base sem jogador: obras e saque em 0) |

## balance/buildings.json — prédios e ruínas (D-032)
| Campo | Tipo | Faixa | O que é |
|---|---|---|---|
| `work_points_per_worker` | número | 0–1000 | Pontos de obra por trabalhador de obras por dia (× produtividade) |
| `points_per_condition` | número | 0–1000 | Pontos para recuperar 1% de condição |
| `low_condition_threshold` / `low_condition_wear_mult` | número | 0–100 / 0–10 | Abaixo do limiar, o desgaste é multiplicado |
| `repair_cost_mult` | {estação: número} | todas as estações | Multiplicador do custo de reparo (janelas mais baratas) |
| `salvage_per_worker` | número | 0–1000 | Materiais por trabalhador de saque por dia, × fração restante das ruínas |
| `salvage_fatigue` | número | 0–100 | Saúde/dia perdida = isto × fração da força no saque × fração já esgotada |
| `max_queue` | inteiro | 1–100 | Tamanho máximo da fila de obras |
| `types.<id>` com `ruins: true` | objeto | `materials` | Ruínas: estoque finito de materiais |
| `types.<id>.cost_materials` / `.cost_points` | número | ≥ 0 / > 0 | Custo (materiais reservados ao começar a obra) |
| `types.<id>.wear` | {estação: número} | todas as estações | Condição perdida por dia (%) |
| `types.<id>.effects[]` | lista | — | `{key, add \| mul, seasons?, requires_water?}`; efeito × condição/100; `key` em `DataRegistry.BUILDING_EFFECT_KEYS` |

## Runner de balanceamento
`godot --headless --path . -s tools/balance_runner.gd -- --seeds=10 --years=3` roda as
estratégias de referência. Opções no cabeçalho de `tools/balance_runner.gd`
(`--fixed=`, `--plan=`, `--builds=`, `--search`, `--data=` para testar números em outra pasta).
Estratégias em código (`tools/balance/balance_run.gd`) aceitam também `by_year` (plano por ano).
`test/unit/test_balanceamento.gd` trava a curva de dificuldade e o critério D-013.

## text/*.csv — textos (D-024)
Formato do Godot: `keys,pt_BR,en`. Toda chave precisa das duas línguas e dos
mesmos marcadores `{x}`; os testes em `test/unit/test_traducoes.gd` garantem.
