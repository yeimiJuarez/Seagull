#!/bin/bash
# uso: test-errorpaths.sh <dir-binarios-con-ASan> <dir-salida>
# Rutas de error de fill-size / fill-pattern (set-value) en la carga del escenario, con ASan/LSan/UBSan:
#   fill-size no numerico, mayor que SET_VALUE_MAX_SIZE o negativo -> escenario rechazado
#   fill-pattern hexadecimal invalido                               -> escenario rechazado
#   limite valido (250) y patron no hexadecimal                     -> el escenario carga
# Un escenario rechazado no debe filtrar memoria (add_actions/add_command liberan lo asignado).
# Cualquier informe de ASan, LSan o UBSan es un fallo. No necesita servidor: la carga falla antes de conectar.
# Opcional: DISPLAY_SCEN_STAT=true|false fija display-scenario-stat en conf.client.xml (como test-cdata.sh).
# Los casos ok solo comprueban que la carga acepta el valor (sin servidor el cliente termina con un Fatal de teclado);
# la ausencia de fugas en la ruta valida la cubre FILL_PATTERN=1 en validate-all.sh.
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
if [ -n "${DISPLAY_SCEN_STAT:-}" ]; then
  C="$OUT/env/config/conf.client.xml"
  L='  <define entity="traffic-param" name="display-scenario-stat" value="'"$DISPLAY_SCEN_STAT"'"></define>'
  grep -v -F 'name="display-scenario-stat"' "$C" | awk -v l="$L" 'index($0,"</configuration>"){print l} {print}' > "$C.new" && mv "$C.new" "$C"
fi
export LD_LIBRARY_PATH="$BIN"
BASE=$OUT/env/scenario/sar-saa.client.xml
NERR=0

fallo() { echo "  FALLO: $1"; NERR=$((NERR + 1)); }

if [ ! -f "$BASE" ]; then echo "RESULTADO: FALLO (no existe $BASE)"; exit 1; fi

# caso <nombre> <fill-size> <fill-pattern> <neg|ok> [mensaje esperado]
caso() {
  local n=$1 fs=$2 fp=$3 modo=$4 msg=${5:-} s rc t=20
  s=$OUT/env/scenario/$n.client.xml
  sed 's|<set-value name="Session-Id"|<set-value fill-size="'"$fs"'" fill-pattern="'"$fp"'" name="Session-Id"|' "$BASE" > "$s"
  if [ "$(grep -c -F "fill-size=\"$fs\"" "$s")" != 1 ]; then
    fallo "$n: no se pudo aplicar fill-size/fill-pattern al escenario base"; return
  fi
  [ "$modo" = ok ] && t=8
  ( cd "$OUT/env/run" && timeout -k 5 -s TERM "$t" "$BIN/seagull" -conf ../config/conf.client.xml -scen ../scenario/$n.client.xml -log ../logs/$n.log -dico ../config/base_cx.xml -llevel ET < /dev/null > ../logs/$n.out 2>&1 )
  rc=$?
  if grep -q -E 'ERROR: (Address|Leak)Sanitizer|runtime error' "$OUT/env/logs/$n.out"; then
    fallo "$n: informe de ASan/LSan/UBSan (ver $OUT/env/logs/$n.out)"
  fi
  if [ "$modo" = neg ]; then
    if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then fallo "$n: el cliente no termino solo (rc=$rc)"; fi
    grep -q -F 'Traffic scenario error' "$OUT/env/logs/$n.log" || fallo "$n: el escenario invalido no fue rechazado"
    if [ -n "$msg" ]; then
      grep -q -F "$msg" "$OUT/env/logs/$n.log" || fallo "$n: falta el mensaje '$msg'"
    fi
  else
    if grep -q -E 'Traffic scenario error|bad format|greater than the maximum|Bad buffer size' "$OUT/env/logs/$n.log"; then
      fallo "$n: el escenario valido fue rechazado (ver $OUT/env/logs/$n.log)"
    fi
    grep -q -F 'PID [' "$OUT/env/logs/$n.log" || fallo "$n: el escenario valido no llego a iniciar (falta 'PID [')"
  fi
}

caso ep-abc        abc 0x2d2d neg 'bad format, [abc] not a number'
caso ep-251        251 0x2d2d neg 'greater than the maximum [250]'
caso ep-neg1       -1  0x2d2d neg
caso ep-hex-impar  5   0x2d2  neg 'Bad buffer size for hexadecimal buffer'
caso ep-hex-malo   5   0xZZ   neg 'Bad buffer size for hexadecimal buffer'
caso ep-ok-250     250 0x2d2d ok
caso ep-ok-string  40  xy     ok

if [ "$NERR" -eq 0 ]; then echo "RESULTADO: OK"; else echo "RESULTADO: FALLO ($NERR)"; exit 1; fi

