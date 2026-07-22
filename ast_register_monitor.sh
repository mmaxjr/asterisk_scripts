#!/usr/bin/env bash
# ast_register_monitor.sh
ALERT_EMAIL="ops@empresa.local"
TMP="/tmp/ast_reg_check.$$"
asterisk -rx "sip show registry" > "$TMP"
DOWN=$(grep -i "Request timed out|Unregistered|Failed" "$TMP" || true)

if [ -n "$DOWN" ]; then
  body="Atenção: problemas detectados em SIP registry on $(hostname) at $(date)\n\n$(cat $TMP)"
  echo -e "$body" | mailx -s "ALERTA: SIP registry DOWN on $(hostname)" "$ALERT_EMAIL"
  echo "Alerta enviado para $ALERT_EMAIL"
else
  echo "Todos os registros OK: $(date)"
fi

rm -f "$TMP"
