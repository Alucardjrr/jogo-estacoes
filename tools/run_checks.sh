#!/usr/bin/env bash
# Checagens automáticas do projeto (usadas pelo CI e localmente).
# Uso: GODOT=/caminho/do/godot tools/run_checks.sh
# Falha (exit != 0) se: o import gera erro, algum script não compila, o jogo gera erro ao iniciar,
# ou algum teste GUT falha.
set -uo pipefail

GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
LOGS="${CHECK_LOGS:-.check-logs}"
mkdir -p "$LOGS" && touch "$LOGS/.gdignore"  # Godot não importa os logs
ERRORS='SCRIPT ERROR|Parse Error|Failed to load script|Compile Error|ERROR:'
status=0

step() { echo; echo "=== $* ==="; }

step "1/4 Import"
# Num checkout limpo o 1º import reclama dos .translation (gerados por ele mesmo,
# ignorados no git). Por isso importa duas vezes e só o 2º log conta.
timeout 600 "$GODOT" --headless --import --path . >"$LOGS/import_1.log" 2>&1
timeout 600 "$GODOT" --headless --import --path . >"$LOGS/import.log" 2>&1
if grep -E "$ERRORS" "$LOGS/import.log"; then
	echo "FALHOU: erros no import (ver $LOGS/import.log)"; status=1
else
	echo "ok"
fi

step "2/4 Compilação de todos os scripts"
timeout 300 "$GODOT" --headless --path . res://tools/check_scripts.tscn >"$LOGS/compile.log" 2>&1
code=$?
if [ "$code" -ne 0 ] || grep -E "SCRIPT_CHECK_FAIL|Parse Error|Compile Error" "$LOGS/compile.log"; then
	grep -E "check_scripts:|SCRIPT_CHECK_FAIL|Parse Error|SCRIPT ERROR" "$LOGS/compile.log"
	echo "FALHOU: scripts que não compilam (ver $LOGS/compile.log)"; status=1
else
	grep "check_scripts:" "$LOGS/compile.log"; echo "ok"
fi

step "3/4 Inicialização do jogo (cena principal, 60 frames)"
timeout 120 "$GODOT" --headless --path . --quit-after 60 >"$LOGS/boot.log" 2>&1
if grep -E "$ERRORS" "$LOGS/boot.log"; then
	echo "FALHOU: erros ao iniciar o jogo (ver $LOGS/boot.log)"; status=1
else
	echo "ok"
fi

step "4/4 Testes GUT"
timeout 900 "$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gexit \
	-gjunit_xml_file="res://$LOGS/gut_results.xml" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tee "$LOGS/gut.log"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
	echo "FALHOU: testes"; status=1
fi

echo
[ "$status" -eq 0 ] && echo "TUDO OK" || echo "HÁ FALHAS"
exit "$status"
