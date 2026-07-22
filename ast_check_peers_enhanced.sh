#!/usr/bin/env bash
# ast_check_peers_enhanced.sh
OUT="/tmp/ast_peers_enhanced_$(date +%Y%m%d_%H%M%S).csv"
SIP_CONF="/etc/asterisk/sip.conf"
echo "timestamp,peer,status,ip,port,qualify,options_rtt,notes" > "$OUT"

if [ -f "$SIP_CONF" ]; then
  peers=$(awk '/^

\[/{gsub(/[

\[\]

]/,""); print $0}' "$SIP_CONF" | sed 's/ //g')
else
  peers=$(asterisk -rx "sip show peers" 2>/dev/null | awk 'NR>1 {print $1}')
fi

for p in $peers; do
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  out=$(asterisk -rx "sip show peer $p" 2>/dev/null || true)
  if [ -z "$out" ]; then
    echo "\"$ts\",\"$p\",\"NOTFOUND\",,,," >> "$OUT"
    continue
  fi
  status=$(echo "$out" | awk -F': ' '/Status/ {print $2; exit}' | sed 's/,//g')
  ip=$(echo "$out" | awk -F': ' '/IP Address/ {print $2; exit}' | awk -F'/' '{print $1}')
  port=$(echo "$out" | awk -F': ' '/Port/ {print $2; exit}')
  qualify=$(echo "$out" | awk -F': ' '/Qualify/ {print $2; exit}')
  # tenta OPTIONS e mede RTT (usa timeout)
  start=$(date +%s%3N)
  asterisk -rx "sip send notify $p" >/dev/null 2>&1 || true
  end=$(date +%s%3N)
  rtt=$((end-start))
  notes=$(echo "$out" | head -n 4 | tr '\n' ' ' | sed 's/"/""/g')
  echo "\"$ts\",\"$p\",\"$status\",\"$ip\",\"$port\",\"$qualify\",\"${rtt}ms\",\"$notes\"" >> "$OUT"
done

echo "Relatório salvo em $OUT"
