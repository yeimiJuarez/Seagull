#!/bin/bash
# uso: run-diameter.sh <dir-binarios> <dir-salida>
. "$(dirname "${0}")/lib.sh"
BIN=$(realpath "$1"); OUT=$(realpath -m "$2")
[ -d "$BIN" ] && [ -n "$OUT" ] || { echo "uso: $0 <dir-binarios> <dir-salida>"; exit 1; }
WAIT_PORT=${WAIT_PORT:-60}; SETTLE=${SETTLE:-5}; CLIENT_MAX=${CLIENT_MAX:-180}; DRAIN=${DRAIN:-12}
if pgrep -x seagull >/dev/null || ss -ltn | grep -q ':3868 '; then
  echo "Hay un seagull vivo o el puerto 3868 está ocupado. Ejecuta: pkill seagull"; exit 1
fi
rm -rf "$OUT"; mkdir -p "$OUT"
prepare_env "$OUT"
cd "$OUT/env/run" || exit 1
export LD_LIBRARY_PATH="$BIN"
COMMON="-dico ../config/base_cx.xml -bg -llevel ET"
getpid() { sed -n 's/.*PID \[\([0-9]*\)\].*/\1/p' "$1"; }

SECONDS=0
"$BIN/seagull" -conf ../config/conf.server.xml -scen ../scenario/sar-saa.server.xml \
  -log ../logs/sar-saa.server.log $COMMON < /dev/null > ../logs/server.out 2>&1
SPID=$(getpid ../logs/server.out)
kill -0 "$SPID" 2>/dev/null || { echo "No se pudo obtener el PID del servidor"; exit 1; }
echo "servidor PID $SPID"
OPEN=0
for i in $(seq $((WAIT_PORT * 2))); do ss -ltn | grep -q ':3868 ' && { OPEN=1; break; }; sleep 0.5; done
[ $OPEN -eq 1 ] || { echo "El puerto 3868 no se abrió en ${WAIT_PORT}s"; kill "$SPID"; exit 1; }
echo "puerto abierto a los ${SECONDS}s; margen ${SETTLE}s"; sleep "$SETTLE"

START=$SECONDS
"$BIN/seagull" -conf ../config/conf.client.xml -scen ../scenario/sar-saa.client.xml \
  -log ../logs/sar-saa.client.log $COMMON < /dev/null > ../logs/client.out 2>&1
CPID=$(getpid ../logs/client.out)
kill -0 "$CPID" 2>/dev/null || { echo "No se pudo obtener el PID del cliente"; kill "$SPID"; exit 1; }
echo "cliente PID $CPID"
for i in $(seq $((CLIENT_MAX * 2))); do kill -0 "$CPID" 2>/dev/null || break; sleep 0.5; done
if kill -0 "$CPID" 2>/dev/null; then
  echo "El cliente NO terminó solo en ${CLIENT_MAX}s; se detiene a la fuerza"; kill "$CPID"; sleep 1; kill -9 "$CPID" 2>/dev/null
else
  echo "el cliente terminó solo tras $((SECONDS - START))s"
fi
echo "esperando ${DRAIN}s para la última fila de estadísticas"; sleep "$DRAIN"
kill "$SPID" 2>/dev/null
for i in $(seq 20); do kill -0 "$SPID" 2>/dev/null || break; sleep 0.5; done
kill -9 "$SPID" 2>/dev/null
pgrep -x seagull >/dev/null && echo "AVISO: queda algún seagull vivo" || echo "limpio"
