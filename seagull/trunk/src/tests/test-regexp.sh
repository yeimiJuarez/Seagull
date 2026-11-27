#!/bin/bash
# uso: test-regexp.sh <dir-binarios-con-ASan> <dir-salida>
# <regexp> dentro de <store> en la carga del escenario, con ASan/LSan/UBSan:
#   regexp valida (una y dos acciones)  -> el escenario carga y no se pierde el T_ActionRegExpStr
#   regexp invalida (a(b)               -> escenario rechazado, sin fugas (C_RegExp y T_ActionRegExpStr)
# Cualquier informe de ASan, LSan o UBSan es un fallo. No necesita servidor.
. "$(dirname "${0}")/lib.sh"
: "${LSAN_OPTIONS:=suppressions=$HERE/lsan.supp}"
export LSAN_OPTIONS
BIN=$(realpath "${1}" 2>/dev/null); OUT=$(realpath -m "${2}" 2>/dev/null)
if [ ! -x "$BIN/seagull" ] || [ -z "$OUT" ]; then
  echo "uso: $(basename "${0}") <dir-binarios-con-ASan> <dir-salida>"; exit 1
fi
if ! ldd "$BIN/seagull" | grep -q libasan; then
  echo "RESULTADO: FALLO (el binario no tiene ASan; la prueba no seria valida)"; exit 1
fi
prepare_env "$OUT"
export LD_LIBRARY_PATH="$BIN"
BASE=$OUT/env/scenario/sar-saa.client.xml
NERR=0

fallo() { echo "  FALLO: $1"; NERR=$((NERR + 1)); }

if [ ! -f "$BASE" ]; then echo "RESULTADO: FALLO (no existe $BASE)"; exit 1; fi

# caso <nombre> <ok|neg> <store1> [store2]
caso() {
  local n="${1}" modo="${2}" a="${3}" b="${4:-}" s rc
  s=$OUT/env/scenario/${n}.client.xml
  sed "s|<stop-timer></stop-timer>|<stop-timer></stop-timer>${a}${b}|" "$BASE" > "$s"
  if ! grep -q -F 'regexp' "$s"; then fallo "$n: no se pudo insertar la regexp en el escenario"; return; fi
  ( cd "$OUT/env/run" && timeout -k 5 -s TERM 20 "$BIN/seagull" -conf ../config/conf.client.xml -scen ../scenario/${n}.client.xml -log ../logs/${n}.log -dico ../config/base_cx.xml -llevel ET < /dev/null > ../logs/${n}.out 2>&1 )
  rc=$?
  if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then fallo "$n: el cliente no termino solo (rc=$rc)"; fi
  if grep -q -E 'ERROR: (Address|Leak)Sanitizer|runtime error' "$OUT/env/logs/${n}.out"; then
    fallo "$n: informe de ASan/LSan/UBSan (ver $OUT/env/logs/${n}.out)"
  fi
  if [ "$modo" = neg ]; then
    grep -q -F 'Bad regular expression' "$OUT/env/logs/${n}.log" || fallo "$n: falta el mensaje 'Bad regular expression'"
    grep -q -F 'Traffic scenario error' "$OUT/env/logs/${n}.log" || fallo "$n: el escenario invalido no fue rechazado"
  else
    if grep -q -F '|E|' "$OUT/env/logs/${n}.log"; then fallo "$n: errores de carga (ver $OUT/env/logs/${n}.log)"; fi
    grep -q -F 'PID [' "$OUT/env/logs/${n}.log" || fallo "$n: el escenario valido no llego a iniciar (falta 'PID [')"
  fi
}

OK1='<store name="rx1" entity="Session-Id"><regexp expr="[0-9]+" nbexpr="1" subexpr="0"></regexp></store>'
OK2='<store name="rx2" entity="Session-Id"><regexp expr="[a-z]+" nbexpr="1" subexpr="0"></regexp></store>'
BAD='<store name="rx1" entity="Session-Id"><regexp expr="a(b" nbexpr="1" subexpr="0"></regexp></store>'

caso rx-ok  ok  "$OK1"
caso rx-two ok  "$OK1" "$OK2"
caso rx-bad neg "$BAD"

if [ "$NERR" -eq 0 ]; then echo "RESULTADO: OK"; else echo "RESULTADO: FALLO ($NERR)"; exit 1; fi
