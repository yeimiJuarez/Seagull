#!/bin/bash
# uso: test-cdata.sh <dir-binarios-con-ASan> <dir-salida>
# Prueba el elemento CDATA de los escenarios (create_new_message), con ASan/LSan/UBSan:
#   value="zz"         -> error "Bad hexadecimal buffer", sin caida
#   CDATA sin value    -> error "value is mandatory for [CDATA]", sin caida
#   hexadecimal valido -> el buffer de CDATA no se filtra
# Cualquier informe de ASan, LSan o UBSan es un fallo: la ruta de error de carga no filtra memoria.
# Opcional: DISPLAY_SCEN_STAT=true|false fija display-scenario-stat en conf.client.xml
# (con true se crea C_ScenarioStats y, si el escenario es invalido, add_scenario() debe liberarlo).
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
  L='  <define entity="traffic-param" name="display-scenario-stat" value="'"$DISPLAY_SCEN_STAT"'"></define>'
  awk -v l="$L" 'index($0,"</configuration>"){print l} {print}' "$OUT/env/config/conf.client.xml" > "$OUT/env/config/conf.client.xml.new" && mv "$OUT/env/config/conf.client.xml.new" "$OUT/env/config/conf.client.xml"
fi
export LD_LIBRARY_PATH="$BIN"
HEXOK=0100002480000118000000000000000100000001000001084000000f73656167756c6c00
NERR=0

fallo() { echo "  FALLO: $1"; NERR=$((NERR + 1)); }

mk() {
  local f="$OUT/env/scenario/$1.client.xml"
  {
    echo '<?xml version="1.0" encoding="ISO-8859-1" ?>'
    echo '<scenario>'
    echo '<traffic>'
    echo '  <send channel="channel-1">'
    echo "    $2"
    echo '  </send>'
    echo '</traffic>'
    echo '</scenario>'
  } > "$f"
}

run() {
  ( cd "$OUT/env/run" && timeout -s TERM 20 "$BIN/seagull" -conf ../config/conf.client.xml -scen ../scenario/$1.client.xml -log ../logs/$1.log -dico ../config/base_cx.xml -llevel ET < /dev/null > ../logs/$1.out 2>&1 )
  if grep -q -E 'ERROR: (Address|Leak)Sanitizer|runtime error' "$OUT/env/logs/$1.out"; then
    fallo "$1: informe de ASan/LSan/UBSan (ver $OUT/env/logs/$1.out)"
  fi
}

mk cdata-bad  '<CDATA value="zz"></CDATA>'
mk cdata-nova '<CDATA></CDATA>'
mk cdata-ok   '<CDATA value="'"$HEXOK"'"></CDATA>'

run cdata-bad
grep -q -F 'Bad hexadecimal buffer [zz]' "$OUT/env/logs/cdata-bad.log" || fallo "cdata-bad: falta el mensaje 'Bad hexadecimal buffer [zz]'"

run cdata-nova
grep -q -F 'value is mandatory for [CDATA]' "$OUT/env/logs/cdata-nova.log" || fallo "cdata-nova: falta el mensaje 'value is mandatory for [CDATA]'"

run cdata-ok
if grep -q 'convert_hexa_char_to_bin' "$OUT/env/logs/cdata-ok.out"; then
  fallo "cdata-ok: fuga del buffer de CDATA (convert_hexa_char_to_bin en el informe de LSan)"
fi

if [ "$NERR" -eq 0 ]; then echo "RESULTADO: OK"; else echo "RESULTADO: FALLO ($NERR)"; exit 1; fi
