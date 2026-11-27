#!/bin/bash
# uso: test-correlation-run.sh <dir-binarios-con-ASan> <dir-salida>
# Etiquetas (label) sin consumir en <correlation>, CON trafico (servidor + cliente en -bg) y
# salida ordenada por SIGTERM, con ASan/LSan/UBSan.
# delete_correlation_map() destruye las acciones huerfanas al cargar; la accion del escenario
# no debe compartir memoria con esa copia (antes: heap-use-after-free en ~C_SetValueAction
# al destruir el escenario). test-correlation.sh no lo detecta porque nunca llega a destruirlo.
# Cualquier informe de ASan, LSan o UBSan es un fallo. Dura unos 20 s.
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
if pgrep -x seagull > /dev/null; then echo "RESULTADO: FALLO (hay un seagull vivo)"; exit 1; fi
if ss -ltn | grep -q ':3868 '; then echo "RESULTADO: FALLO (puerto 3868 ocupado)"; exit 1; fi
prepare_env "$OUT"
export LD_LIBRARY_PATH="$BIN"
BASE=$OUT/env/scenario/sar-saa.client.xml
S=$OUT/env/scenario/corr-orphan.client.xml
NERR=0

fallo() { echo "  FALLO: $1"; NERR=$((NERR + 1)); }

pid_de() { grep -oE 'PID [[][0-9]+[]]' "${1}" | grep -oE '[0-9]+' | head -1; }

parar() {
  local p="${1}" i
  kill -TERM "$p" 2>/dev/null
  for i in $(seq 40); do kill -0 "$p" 2>/dev/null || return 0; sleep 0.5; done
  kill -9 "$p" 2>/dev/null
  fallo "el proceso $p no termino con SIGTERM"
}

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

cd "$OUT/env/run" || exit 1
C="-dico ../config/base_cx.xml -bg -llevel EM"

"$BIN/seagull" -conf ../config/conf.server.xml -scen ../scenario/sar-saa.server.xml -log ../logs/s.log $C < /dev/null > ../logs/server.out 2>&1
SP=$(pid_de ../logs/server.out)
if [ -z "$SP" ]; then echo "RESULTADO: FALLO (el servidor no arranco)"; exit 1; fi
for i in $(seq 60); do ss -ltn | grep -q ':3868 ' && break; sleep 0.5; done
sleep 2

"$BIN/seagull" -conf ../config/conf.client.xml -scen ../scenario/corr-orphan.client.xml -log ../logs/c.log $C < /dev/null > ../logs/client.out 2>&1
CP=$(pid_de ../logs/client.out)
if [ -z "$CP" ]; then
  kill -9 "$SP" 2>/dev/null
  echo "RESULTADO: FALLO (el cliente no arranco)"; exit 1
fi
sleep 12

parar "$CP"
sleep 1
parar "$SP"

for f in client server; do
  if grep -q -E 'ERROR: (Address|Leak)Sanitizer|runtime error' "$OUT/env/logs/$f.out"; then
    fallo "$f: informe de ASan/LSan/UBSan (ver $OUT/env/logs/$f.out)"
  fi
done
grep -q -F 'PID [' "$OUT/env/logs/c.log" || fallo "el escenario no llego a iniciar (falta 'PID [')"
NCALL=$(awk -F';' 'NR > 1 { v = $11 } END { print v + 0 }' "$OUT/env/logs/client-stat.csv" 2>/dev/null)
if [ "${NCALL:-0}" -lt 1 ]; then
  fallo "el cliente no inicio ninguna llamada (la prueba no ejerce el set-value)"
fi

if [ "$NERR" -eq 0 ]; then echo "RESULTADO: OK"; else echo "RESULTADO: FALLO ($NERR)"; exit 1; fi
