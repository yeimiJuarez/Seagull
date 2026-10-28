#!/bin/bash
# uso: run-diameter-tls.sh <dir-binarios> <dir-salida> [clave] [passwd]   (PROBE=1 prueba s_client)
. "$(dirname "${0}")/lib.sh"
BIN=$(realpath "$1"); OUT=$(realpath -m "$2")
KEY=${3:-key.pem}; PASS=${4:-seagull123}
T=$CERTS
if [ ! -d "$BIN" ] || [ -z "$OUT" ] || [ ! -f "$T/cert.pem" ] || [ ! -f "$T/$KEY" ]; then
  echo "uso: $0 <dir-binarios> <dir-salida> [clave] [passwd]"; exit 1
fi
WAIT_PORT=${WAIT_PORT:-60}; SETTLE=${SETTLE:-5}; CLIENT_MAX=${CLIENT_MAX:-180}; DRAIN=${DRAIN:-12}
if pgrep -x seagull >/dev/null || ss -ltn | grep -q ':3868 '; then
  echo "Hay un seagull vivo o el puerto 3868 esta ocupado. Ejecuta: pkill seagull"; exit 1
fi
rm -rf "$OUT"; mkdir -p "$OUT"
cp -r "$ENV_TEMPLATE" "$OUT/env"
mkdir -p "$OUT/env/logs"
cd "$OUT/env/config" || exit 1
for f in conf.server-tls.xml conf.client-tls.xml; do
  sed -i -e "s|cert_chain_file=xxx;|cert_chain_file=$T/cert.pem;|" \
         -e "s|private_key_file=yyy;|private_key_file=$T/$KEY;|" \
         -e "s|passwd=zzz\"|passwd=$PASS\"|" \
         -e 's|</configuration>|  <define entity="traffic-param" name="files-no-timestamp" value="true"></define>\n</configuration>|' "$f"
done
sed -i -e '/name="number-calls"/d' -e 's|name="call-rate" value="1"|name="call-rate" value="10"|' \
       -e 's|name="max-send" value="200"|name="max-send" value="50"|' \
       -e 's|</configuration>|  <define entity="traffic-param" name="number-calls" value="100"></define>\n</configuration>|' conf.client-tls.xml
echo "--- conf cliente tras los ajustes:"
grep -h 'init-args\|call-rate\|max-send\|number-calls\|no-timestamp\|log-stat-file' conf.client-tls.xml

cd "$OUT/env/run" || exit 1
export LD_LIBRARY_PATH="$BIN"
COMMON="-dico ../config/base_cx.xml -bg -llevel ET"
getpid() { sed -n 's/.*PID \[\([0-9]*\)\].*/\1/p' "$1"; }

SECONDS=0
"$BIN/seagull" -conf ../config/conf.server-tls.xml -scen ../scenario/sar-saa.server.xml \
  -log ../logs/sar-saa.server-tls.log $COMMON < /dev/null > ../logs/server.out 2>&1
SPID=$(getpid ../logs/server.out)
kill -0 "$SPID" 2>/dev/null || { echo "No se pudo obtener el PID del servidor"; cat ../logs/server.out; exit 1; }
OPEN=0
for i in $(seq $((WAIT_PORT * 2))); do ss -ltn | grep -q ':3868 ' && { OPEN=1; break; }; sleep 0.5; done
[ $OPEN -eq 1 ] || { echo "El puerto 3868 no se abrio en ${WAIT_PORT}s"; kill "$SPID"; exit 1; }
echo "puerto abierto a los ${SECONDS}s"; sleep "$SETTLE"
if [ -n "$PROBE" ]; then
  echo "--- sondeo TLS con openssl s_client:"
  echo | timeout 5 openssl s_client -connect 127.0.0.1:3868 2>&1 | grep -E 'Protocol|Cipher|error'
fi

START=$SECONDS
"$BIN/seagull" -conf ../config/conf.client-tls.xml -scen ../scenario/sar-saa.client.xml \
  -log ../logs/sar-saa.client-tls.log $COMMON < /dev/null > ../logs/client.out 2>&1
CPID=$(getpid ../logs/client.out)
kill -0 "$CPID" 2>/dev/null || { echo "No se pudo obtener el PID del cliente"; kill "$SPID"; exit 1; }
for i in $(seq $((CLIENT_MAX * 2))); do kill -0 "$CPID" 2>/dev/null || break; sleep 0.5; done
if kill -0 "$CPID" 2>/dev/null; then
  echo "El cliente NO termino solo en ${CLIENT_MAX}s; se detiene"; kill "$CPID"; sleep 1; kill -9 "$CPID" 2>/dev/null
else
  echo "el cliente termino solo tras $((SECONDS - START))s"
fi
sleep "$DRAIN"
kill "$SPID" 2>/dev/null
for i in $(seq 20); do kill -0 "$SPID" 2>/dev/null || break; sleep 0.5; done
kill -9 "$SPID" 2>/dev/null

echo "--- logs generados:"; ls "$OUT/env/logs"
echo "--- errores en los logs (E/T):"; grep -hE '\|(E|T)\|' "$OUT"/env/logs/*.log
echo "--- SAR enviados por el cliente (esperado 100): $("$HERE/resumen.sh" "$OUT" client | cut -d';' -f10)"
for lado in client server; do
  if diff -q "$EXPECTED/$lado.txt" <("$HERE/resumen.sh" "$OUT" $lado) >/dev/null 2>&1; then
    echo "  $lado: IGUAL a la referencia TCP"
  else
    echo "  $lado: DIFERENTE (o falta el CSV)"
  fi
done
pgrep -x seagull >/dev/null && echo "AVISO: queda algun seagull vivo" || echo "limpio"
