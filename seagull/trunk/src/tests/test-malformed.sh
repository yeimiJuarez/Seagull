#!/bin/bash
# uso: test-malformed.sh <dir-binarios-con-ASan> <dir-salida>
# CDATA Diameter con longitudes incoherentes (ASan/LSan/UBSan), sin servidor:
#   longitud de mensaje menor que la cabecera (20)  -> debe rechazarse, sin lectura fuera del buffer
#   longitud de AVP menor que su cabecera (8)       -> debe rechazarse, sin allocation gigante
#   controles: longitudes enormes                   -> rechazo limpio
# Un mensaje valido no debe producir informes de sanitizers.
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

# caso <nombre> <longitud-mensaje-hex6> <longitud-avp-hex6> <ok|err>
caso() {
  local n=$1 hex
  hex="01${2}""80000101""00000000""00000001""00000001""00000108""40${3}""73656167756c6c00""${5:-}"
  mk "$n" "<CDATA value=\"$hex\"></CDATA>"
  run "$n"
  if [ "$4" = err ]; then
    grep -q -F 'Error while decoding direct data buffer' "$OUT/env/logs/$n.log" || fallo "$n: el buffer malformado no fue rechazado"
  fi
  if grep -q -F 'Unrecognized buffer header' "$OUT/env/logs/$n.log"; then
    fallo "$n: arnes vacuo (el comando no esta en el diccionario)"
  fi
  if [ "${4}" = ok ]; then
    grep -q -F 'PID [' "$OUT/env/logs/$n.log" || fallo "$n: el buffer valido no fue aceptado"
  fi
}

caso_hex() {
  local n="${1}" hex="${2}" modo="${3}"
  mk "$n" "<CDATA value=\"$hex\"></CDATA>"
  run "$n"
  if grep -q -F 'Unrecognized buffer header' "$OUT/env/logs/$n.log"; then
    fallo "$n: arnes vacuo (el comando no esta en el diccionario)"
  fi
  if [ "$modo" = err ]; then
    grep -q -F 'Error while decoding direct data buffer' "$OUT/env/logs/$n.log" || fallo "$n: el buffer malformado no fue rechazado"
  else
    grep -q -F 'PID [' "$OUT/env/logs/$n.log" || fallo "$n: el buffer valido no fue aceptado"
  fi
}

caso mal-ok          000024 00000f ok
caso mal-msglen-16   000010 00000f err
caso mal-msglen-0    000000 00000f err
caso mal-avplen-4    000024 000004 err
caso mal-avplen-0    000024 000000 err
caso mal-avplen-huge 000024 00ffff err
caso mal-msglen-huge 00ffff 00000f err
caso mal-trailing 000027 00000f err 000001
caso_hex mal-grouped-ok 01000038800001010000000000000001000000010000010440000024000001084000000f73656167756c6c000000010a4000000c0000000b ok
caso_hex mal-grouped-a  01000034800001010000000000000001000000010000010440000020000001084000000f73656167756c6c000000010a40000004 err
caso_hex mal-grouped-b  01000038800001010000000000000001000000010000010440000024000001084000000f73656167756c6c000000010a4000000400000000 err

if [ "$NERR" -eq 0 ]; then echo "RESULTADO: OK"; else echo "RESULTADO: FALLO ($NERR)"; exit 1; fi

