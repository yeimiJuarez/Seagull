# Diameter Gx (3GPP TS 29.212)

Soporte Gx agregado durante la modernizacion. No existe en el RPM original
seagull-diameter-protocol 1.8.2 de HP.

## Archivos

| Archivo | Descripcion |
|---|---|
| `config/base_gx.xml` | Diccionario Gx (Auth-Application-Id 16777238, Vendor 3GPP 10415) |
| `scenario/gx-ccr-cca.server.xml` | PCRF simulado: CEA, CCA-I con politica, CCA-T, DWA |
| `scenario/gx-ccr-cca.client.xml` | PCEF simulado: CER, CCR-I, CCR-T, DWA |
| `run/start_server_gx.ksh` / `run/start_client_gx.ksh` | Arranque interactivo |

## Flujo

```
PCEF (cliente)                 PCRF (servidor)
   | CER ------------------------> |
   | <------------------------ CEA |
   | CCR-I (Request-Type 1) -----> |
   | <------ CCA-I + Charging-Rule |
   | CCR-T (Request-Type 3) -----> |   Destination-Host = Origin-Host del CCA-I
   | <---------------------- CCA-T |
   | DWR <-> DWA  (<default>)      |
```

## AVPs principales

| AVP | Codigo | Vendor | Mensaje | Valor de prueba |
|---|---|---|---|---|
| Session-Id | 263 | - | CCR/CCA | `client.gx.example.com;1;N` |
| Auth-Application-Id | 258 | - | CER/CCR/CCA | 16777238 (Gx) |
| Destination-Host | 293 | - | CCR-T | Origin-Host del CCA-I |
| CC-Request-Type | 416 | - | CCR/CCA | 1 INITIAL, 3 TERMINATION |
| CC-Request-Number | 415 | - | CCR/CCA | 0, 1 |
| Termination-Cause | 295 | - | CCR-T | 1 DIAMETER_LOGOUT |
| Subscription-Id (Type 450 / Data 444) | 443 | - | CCR-I | E.164 y IMSI |
| Framed-IP-Address | 8 | - | CCR-I | 10.0.0.5 |
| Called-Station-Id | 30 | - | CCR-I | `internet.test` |
| Bearer-Operation | 1021 | 10415 | CCR-I | 1 ESTABLISHMENT |
| IP-CAN-Type | 1027 | 10415 | CCR-I | 5 3GPP-EPS |
| RAT-Type | 1032 | 10415 | CCR-I | 1004 EUTRAN |
| AN-GW-Address | 1050 | 10415 | CCR-I | IP del cliente |
| QoS-Information (APN-AMBR UL 1041 / DL 1040) | 1016 | 10415 | CCR-I/CCA-I | 50-100 Mbps |
| Default-EPS-Bearer-QoS (QCI 1028, ARP 1034) | 1049 | 10415 | CCR-I/CCA-I | QCI 9, Priority 10 |
| Event-Trigger | 1006 | 10415 | CCA-I | 1 QOS_CHANGE |
| Charging-Rule-Install (Rule-Name 1005) | 1001 | 10415 | CCA-I | `rule_default_test` |
| Supported-Features (629 / 630) | 628 | 10415 | CCR-I/CCA-I | List-ID 1, List 2 |
| 3GPP-SGSN-MCC-MNC | 18 | 10415 | CCR-I | 00101 |

## Prueba en loopback

Los archivos usan 127.0.0.1:3868 por defecto. Desde `run/`:

```
./start_server_gx.ksh      # terminal 1
./start_client_gx.ksh      # terminal 2
```

En ejecuciones automatizadas (`</dev/null`) agregue `-bg`; sin terminal,
Seagull aborta con `Fatal: Keyboard saved configuration failure`.

## Prueba entre VMs

1. `config/conf.server.xml`: `open-args="mode=server;source=<IP-servidor>:<puerto>"`
2. `config/conf.client.xml`: `open-args="mode=client;dest=<IP-servidor>:<puerto>"`
3. AVPs de tipo Address en los escenarios (`Host-IP-Address`, `AN-GW-Address`).
   Formato: `0x0001` (AddressType IPv4) + IPv4 en hexadecimal:
   ```
   printf '0x0001%02x%02x%02x%02x\n' 192 168 63 131    # -> 0x0001c0a83f83
   ```
   `Framed-IP-Address` es OctetString: solo 4 bytes, sin el prefijo `0x0001`.
4. Abrir el puerto en el firewall del servidor:
   ```
   sudo firewall-cmd --add-port=<puerto>/tcp
   ```

## Validacion

- Usar `TrafficSuccessfulCall(C)` del CSV de estadisticas.
- Los `<receive>` no validan Result-Code; para confirmarlo, capture el trafico:
  ```
  tshark -r gx.pcap -Y diameter -T fields -e diameter.cmd.code \
    -e diameter.flags.request -e diameter.CC-Request-Type -e diameter.Result-Code | sort | uniq -c
  ```

| Prueba | Resultado |
|---|---|
| Loopback, build C++23 | 20/20, 0 fallos, Result-Code 2001 en las 40 respuestas |
| Entre VMs AlmaLinux 10.2 (version previa) | 100/100, Result-Code 2001 |

## Limitaciones conocidas

- DWR/DWA solo validado sintacticamente (el servidor Seagull no envia DWR).
- No hay CCR-U ni RAR/RAA.
- El temporizador del cliente mide solo CCR-I/CCA-I.
