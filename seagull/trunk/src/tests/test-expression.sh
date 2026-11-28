#!/bin/bash
# uso: test-expression.sh <dir-binarios-con-ASan> <dir-salida>
# Atributo format de set-value (add_expression) en la carga del escenario, con ASan/LSan/UBSan:
#   formato valido, formato largo (fragmentos de mas de 100 caracteres) -> el escenario carga
#   referencia $(nombre) inexistente                                    -> escenario rechazado, sin fugas
#   "$" solo (sin fragmentos)                                           -> carga, sin fuga
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

# caso <nombre> <ok|neg> <formato>
caso() {
  local n="${1}" modo="${2}" f="${3}" s rc
  s=$OUT/env/scenario/${n}.client.xml
  sed 's|format=".;1096298391;$(session-counter)"|format="'"${f}"'"|' "$BASE" > "$s"
  if ! grep -q -F "format=\"${f}\"" "$s"; then fallo "$n: no se pudo insertar el formato"; return; fi
  ( cd "$OUT/env/run" && timeout -k 5 -s TERM 20 "$BIN/seagull" -conf ../config/conf.client.xml -scen ../scenario/${n}.client.xml -log ../logs/${n}.log -dico ../config/base_cx.xml -llevel ET < /dev/null > ../logs/${n}.out 2>&1 )
  rc=$?
  if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then fallo "$n: el cliente no termino solo (rc=$rc)"; fi
  if grep -q -E 'ERROR: (Address|Leak)Sanitizer|runtime error' "$OUT/env/logs/${n}.out"; then
    fallo "$n: informe de ASan/LSan/UBSan (ver $OUT/env/logs/${n}.out)"
  fi
  if [ "$modo" = neg ]; then
    grep -q -F 'Unable to find definition for' "$OUT/env/logs/${n}.log" || fallo "$n: falta el mensaje 'Unable to find definition for'"
    grep -q -F 'Format error for' "$OUT/env/logs/${n}.log" || fallo "$n: el formato invalido no fue rechazado"
  else
    if grep -q -F '|E|' "$OUT/env/logs/${n}.log"; then fallo "$n: errores de carga (ver $OUT/env/logs/${n}.log)"; fi
    grep -q -F 'PID [' "$OUT/env/logs/${n}.log" || fallo "$n: el escenario valido no llego a iniciar (falta 'PID [')"
  fi
}

LARGO=$(printf 'a%.0s' $(seq 150))
NOMBRE=$(printf 'x%.0s' $(seq 150))

caso ex-ok      ok  '.;1096298391;$(session-counter)'
caso ex-dollar  ok  '$'
caso ex-long    ok  "$LARGO"
caso ex-long2   ok  "${LARGO}"'$(session-counter)'
caso ex-bad     neg '.;1096298391;$(inexistente)'
caso ex-bad2    neg 'a$(session-counter)b$(nope)'
caso ex-badlong neg '$('"$NOMBRE"')'

if [ "$NERR" -eq 0 ]; then echo "RESULTADO: OK"; else echo "RESULTADO: FALLO ($NERR)"; exit 1; fi

