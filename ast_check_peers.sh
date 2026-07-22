#!/usr/bin/env bash
# ast_check_peers.sh
SIP_CONF="/etc/asterisk/sip.conf"
OUT="${1:-/tmp/asterisk_peers_$(date +%Y%m%d_%H%M%S).csv}"
echo "timestamp,peer,status,ip,port,qualidade,latency,monitored,notes" > "$OUT"

# extrai peers de sip.conf ou fallback para peers no CLI
if [ -f "$SIP_CONF" ]; then
  peers=$(awk '/^

\[/{gsub(/[

\[\]

]/,""); print $0}' "$SIP_CONF" | sed 's/ //g')
else
  peers=$(asterisk -rx "sip show peers" 2>/dev/null | awk 'NR>1 {print $1}')
fi

for p in $peers; do
  # captura saída do sip show peer
  out=$(asterisk -rx "sip show peer $p" 2>/dev/null || true)
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  if [ -z "$out" ]; then
    echo "\"$ts\",\"$p\",\"NOTFOUND\",,, , ,\"no output\"" >> "$OUT"
    continue
  fi
  status=$(echo "$out" | awk -F': ' '/Status/ {print $2; exit}' | sed 's/,//g')
  ip=$(echo "$out" | awk -F': ' '/IP Address/ {print $2; exit}' | awk -F'/' '{print $1}')
  port=$(echo "$out" | awk -F': ' '/Port/ {print $2; exit}')
  latency=$(echo "$out" | awk -F': ' '/Latency/ {print $2; exit}')
  quality=$(echo "$out" | awk -F': ' '/Qualify/ {print $2; exit}')
  monitored=$(echo "$out" | grep -qi 'Monitored' && echo "yes" || echo "no")
  notes=$(echo "$out" | head -n 6 | tr '\n' ' ' | sed 's/"/""/g')
  echo "\"$ts\",\"$p\",\"$status\",\"$ip\",\"$port\",\"$quality\",\"$latency\",\"$monitored\",\"$notes\"" >> "$OUT"
done

echo "Relatório de peers salvo em $OUT"
