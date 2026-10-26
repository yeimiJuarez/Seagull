# tests/lib.sh: rutas comunes. Uso desde otro script: . "$(dirname "$0")/lib.sh"
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)   # .../src/tests
SRC=$(cd "$HERE/.." && pwd)                          # .../src
ENV_TEMPLATE=$SRC/exe-env/diameter-env               # ejemplo del repo (no se modifica)
EXPECTED=$HERE/expected                              # referencia gnu++98 en texto
WORK=${SEAGULL_TEST_DIR:-$HOME/seagull-test}         # salidas y certificados, fuera del repo
CERTS=$WORK/tls-test

# prepare_env <dir-salida>: copia exe-env (sin modificarlo) y aplica los ajustes de prueba
prepare_env() {
  local out=$1 c
  rm -rf "$out"; mkdir -p "$out"
  cp -r "$ENV_TEMPLATE" "$out/env"; mkdir -p "$out/env/logs"
  c=$out/env/config
  sed -i 's|</configuration>|  <define entity="traffic-param" name="files-no-timestamp" value="true"></define>\n</configuration>|' "$c/conf.server.xml"
  sed -i -e 's|name="call-rate" value="1"|name="call-rate" value="10"|' \
         -e 's|name="max-send" value="200"|name="max-send" value="50"|' \
         -e 's|</configuration>|  <define entity="traffic-param" name="files-no-timestamp" value="true"></define>\n  <define entity="traffic-param" name="number-calls" value="100"></define>\n</configuration>|' "$c/conf.client.xml"
}
