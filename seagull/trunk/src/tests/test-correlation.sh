#!/bin/bash
# uso: test-correlation.sh <dir-binarios-con-ASan> <dir-salida>
# Escenario con etiquetas (label) que nadie consume en <correlation> (a1 y b1, ambas con <action> o sin ella),
# con ASan/LSan/UBSan. Tras analizar la correlacion, delete_correlation_map() vacia los mapas de acciones
# pendientes: debe liberar las acciones de TODAS las entradas y no vaciar el mapa dentro del propio bucle
# (antes: heap-use-after-free al avanzar el iterador sobre un nodo ya liberado).
# Cualquier informe de ASan, LSan o UBSan es un fallo. No necesita servidor: solo se prueba la carga.
# El cliente termina con un Fatal de teclado (stdin no es un terminal); basta con que llegue a iniciar (PID [).
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
S=$OUT/env/scenario/corr-orphan.client.xml
NERR=0

fallo() { echo "  FALLO: $1"; NERR=$((NERR + 1)); }

if [ ! -f "$BASE" ]; then echo "RESULTADO: FALLO (no existe $BASE)"; exit 1; fi

# etiqueta el primer send y el primer receive de <traffic> e inserta una <correlation> sin <command>
awk '
/<traffic>/ && !intr {
  print "<correlation>"
  print "  <channel name=\"channel-1\">"
  print "    <retrieve>"
  print "      <search-in-map name=\"Session-Id\"></search-in-map>"
  print "    </retrieve>"
  print "  </channel>"
  print "</correlation>"
  print ""
  intr = 1
}
intr && !s && sub(/<send channel="channel-1">/, "<send channel=\"channel-1\" label=\"a1\">") { s = 1 }
intr && !r && sub(/<receive channel="channel-1">/, "<receive channel=\"channel-1\" label=\"b1\">") { r = 1 }
{ print }
' "$BASE" > "$S"
if [ "$(grep -c -F 'label="' "$S")" != 2 ] || ! grep -q -F '<correlation>' "$S"; then
  echo "RESULTADO: FALLO (no se pudo generar el escenario de prueba)"; exit 1
fi

( cd "$OUT/env/run" && timeout -k 5 -s TERM 20 "$BIN/seagull" -conf ../config/conf.client.xml -scen ../scenario/corr-orphan.client.xml -log ../logs/corr-orphan.log -dico ../config/base_cx.xml -llevel ET < /dev/null > ../logs/corr-orphan.out 2>&1 )
rc=$?
if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then fallo "corr-orphan: el cliente no termino solo (rc=$rc)"; fi
if grep -q -E 'ERROR: (Address|Leak)Sanitizer|runtime error' "$OUT/env/logs/corr-orphan.out"; then
  fallo "corr-orphan: informe de ASan/LSan/UBSan (ver $OUT/env/logs/corr-orphan.out)"
fi
if grep -q -F '|E|' "$OUT/env/logs/corr-orphan.log"; then
  fallo "corr-orphan: errores de carga (ver $OUT/env/logs/corr-orphan.log)"
fi
grep -q -F 'PID [' "$OUT/env/logs/corr-orphan.log" || fallo "corr-orphan: el escenario no llego a iniciar (falta 'PID [')"

if [ "$NERR" -eq 0 ]; then echo "RESULTADO: OK"; else echo "RESULTADO: FALLO ($NERR)"; exit 1; fi
