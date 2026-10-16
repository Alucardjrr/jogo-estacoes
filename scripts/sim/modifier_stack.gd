class_name ModifierStack
extends RefCounted
## Pilha de modificadores (D-020). Sistemas publicam (Season, depois Social),
## sistemas leem (Resources, depois Population). Refeita a cada tick: quem
## publica limpa só o que é seu com clear_source() e publica de novo.
##
## Valor final de uma chave: (base + soma dos "add") × produto dos "mul".
## Matematicamente a ordem não importa; em float pode variar no último dígito,
## por isso a ordem de publicação é a ordem fixa do tick (determinismo).

var _entries: Array[Dictionary] = []  # {key, source, add, mul}
## Chaves válidas. Vazio = aceita qualquer chave (testes isolados). A Simulation
## registra as chaves dos sistemas; chave fora da lista vai para `warnings`
## (uma vez por chave) em vez de virar 0 silencioso.
var _known: Dictionary = {}
var warnings: PackedStringArray = []


func register_keys(keys: PackedStringArray) -> void:
	for k in keys:
		_known[k] = true


func add(key: String, source: String, amount: float) -> void:
	_check(key)
	_entries.append({"key": key, "source": source, "add": amount, "mul": 1.0})


func mul(key: String, source: String, factor: float) -> void:
	_check(key)
	_entries.append({"key": key, "source": source, "add": 0.0, "mul": factor})


func clear_source(source: String) -> void:
	_entries = _entries.filter(func(e: Dictionary) -> bool: return e.source != source)


func value(key: String, base: float = 0.0) -> float:
	_check(key)
	var total_add := 0.0
	var total_mul := 1.0
	for e in _entries:
		if e.key == key:
			total_add += e.add
			total_mul *= e.mul
	return (base + total_add) * total_mul


## Cópia para a tela de debug / snapshot (ninguém altera a pilha por aqui).
func entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


func _check(key: String) -> void:
	if _known.is_empty() or _known.has(key):
		return
	var msg := "modificador desconhecido: '%s'" % key
	if not warnings.has(msg):
		warnings.append(msg)
		push_warning("[sim] " + msg)
