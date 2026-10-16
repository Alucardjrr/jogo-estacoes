extends SceneTree
## Runner de balanceamento (D-031). Roda estratégias de mão de obra em N sementes.
## Uso:
##   godot --headless --path . -s tools/balance_runner.gd -- [opções]
## Opções:
##   --seeds=10            sementes (1..N)
##   --years=3             anos por partida
##   --data=res://data/balance   pasta de dados (copie e altere fora do repo para testar números)
##   --fixed=9/18/3        uma distribuição fixa água/roça/cuidado
##   --plan=seca:27/0/3,janela_1:6/15/9,chuvas:0/21/9,janela_2:6/21/3
##   --builds=cisterna,silo   ordem de obras (somada a --fixed/--plan)
##   --search              busca exaustiva da melhor distribuição fixa (passo 3)
## Distribuição a/r/c aceita 5 números: água/roça/cuidado/obras/saque.
## Sem --fixed/--plan/--search: roda o conjunto padrão de estratégias de referência.

const Run := preload("res://tools/balance/balance_run.gd")

const REFERENCE := {
	"linha de base (dados)": {},
	"melhor fixa (6/21/3)": {"fixed": {"water": 6, "farm": 21, "care": 3}},
	"por estação": {"by_season": {
		"seca": {"water": 27, "farm": 0, "care": 3}, "janela_1": {"water": 6, "farm": 15, "care": 9},
		"chuvas": {"water": 0, "farm": 21, "care": 9}, "janela_2": {"water": 6, "farm": 21, "care": 3}}},
	"plano da seca o ano todo": {"fixed": {"water": 27, "farm": 0, "care": 3}},
	"plano das chuvas o ano todo": {"fixed": {"water": 0, "farm": 21, "care": 9}},
	"constrói no ano 1 e aproveita": {
		"builds": ["cisterna", "silo", "abrigo", "canteiro", "cisterna", "silo", "abrigo"],
		"by_year": {
			1: {"seca": {"water": 27, "farm": 0, "care": 3, "build": 0, "salvage": 0},
				"janela_1": {"water": 6, "farm": 12, "care": 6, "build": 2, "salvage": 4},
				"chuvas": {"water": 0, "farm": 21, "care": 9, "build": 0, "salvage": 0},
				"janela_2": {"water": 6, "farm": 18, "care": 3, "build": 3, "salvage": 0}},
			2: {"seca": {"water": 21, "farm": 0, "care": 9, "build": 0, "salvage": 0},
				"janela_1": {"water": 21, "farm": 6, "care": 3, "build": 0, "salvage": 0},
				"chuvas": {"water": 0, "farm": 21, "care": 6, "build": 3, "salvage": 0},
				"janela_2": {"water": 6, "farm": 21, "care": 0, "build": 3, "salvage": 0}}}},
}


func _init() -> void:
	var opt := {"seeds": 10, "years": 3, "data": DataRegistry.DEFAULT_DIR}
	var strategies := {}
	var search := false
	var builds: Array = []
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"seeds", "years":
				opt[kv[0]] = maxi(1, kv[1].to_int())
			"data":
				opt.data = kv[1]
			"fixed":
				var t := _triple(kv[1] if kv.size() > 1 else "")
				if t.is_empty():
					_fail("--fixed precisa ser água/roça/cuidado, ex.: --fixed=9/18/3")
					return
				strategies["fixa " + kv[1]] = {"fixed": t}
			"plan":
				var plan := {}
				for part in (kv[1] if kv.size() > 1 else "").split(","):
					var p := part.split(":")
					var t := _triple(p[1]) if p.size() == 2 else {}
					if t.is_empty():
						_fail("--plan precisa ser estação:a/r/c separados por vírgula")
						return
					plan[p[0]] = t
				strategies["plano"] = {"by_season": plan}
			"search":
				search = true
			"builds":
				builds = Array((kv[1] if kv.size() > 1 else "").split(",", false))
	if search:
		_search(opt)
		if _failed:
			return
	else:
		if strategies.is_empty():
			strategies = REFERENCE
		elif not builds.is_empty():
			for name in strategies:
				strategies[name].builds = builds
		print("sementes=%d anos=%d dados=%s" % [opt.seeds, opt.years, opt.data])
		print("%-30s %8s %6s %7s %7s  %s" % ["estratégia", "pop.média", "pior", "mortes", "saídas", "pop. fim de cada ano"])
		for name in strategies:
			var r: Dictionary = Run.summary(strategies[name], opt.seeds, opt.years, opt.data)
			if r.has("error"):
				printerr(r.error)
				quit(1)
				return
			print("%-30s %8.1f %6d %7.1f %7.1f  %s" % [name, r.mean, r.worst, r.deaths, r.left,
				" / ".join(r.by_year.map(func(v: float) -> String: return "%.1f" % v))])
	quit()


func _search(opt: Dictionary) -> void:
	var best := []
	for w in range(0, 31, 3):
		for f in range(0, 31 - w, 3):
			var alloc := {"water": w, "farm": f, "care": 30 - w - f}
			var r: Dictionary = Run.summary({"fixed": alloc}, opt.seeds, opt.years, opt.data)
			if r.has("error"):
				_fail(r.error)
				return
			best.append([r.mean, "%d/%d/%d" % [w, f, 30 - w - f]])
	best.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("melhores distribuições fixas (pop. média final):")
	for i in mini(5, best.size()):
		print("  %s  %.1f" % [best[i][1], best[i][0]])


var _failed := false


func _fail(message: String) -> void:
	printerr(message)
	_failed = true
	quit(1)


## "9/18/3" → {water, farm, care}; formato inválido → {}.
static func _triple(text: String) -> Dictionary:
	var p := text.split("/")
	if p.size() != 3 and p.size() != 5:
		return {}
	for x in p:
		if not x.is_valid_int() or x.to_int() < 0:
			return {}
	var out := {"water": p[0].to_int(), "farm": p[1].to_int(), "care": p[2].to_int()}
	if p.size() == 5:
		out.build = p[3].to_int()
		out.salvage = p[4].to_int()
	return out
