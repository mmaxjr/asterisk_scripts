#!/usr/bin/env bash
# ast_sip_bruteforce_detect.sh
LOG="/var/log/asterisk/full"
THRESHOLD="${1:-30}"   # tentativas no período
WINDOW_MIN="${2:-10}"  # janela em minutos
BLOCK_TIME="${3:-3600}" # tempo de bloqueio em segundos
TMP="/tmp/ast_sip_fail.$$"

# extrai tentativas de auth falhas (ex.: "Authentication for user ... failed" ou "Registration from '...' failed")
grep -iE "authentication failed|failed to authenticate|Registration from" "$LOG" | \
  awk -v window="$WINDOW_MIN" -v now="$(date +%s)" '
    {
      # tenta extrair IP
      match($0, /([0-9]{1,3}\.){3}[0-9]{1,3}/)
      ip = (RSTART ? substr($0, RSTART, RLENGTH) : "")
      # tenta extrair timestamp do log (assume formato "YYYY-MM-DD HH:MM:SS" ou "Mon DD HH:MM:SS")
      print ip
    }' | grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}" | sort | uniq -c | sort -rn > "$TMP"

echo "IPs com tentativas recentes (mais frequentes primeiro):"
cat "$TMP"

# aplica bloqueio para IPs acima do threshold
awk -v thr="$THRESHOLD" -v bt="$BLOCK_TIME" '{ if ($1+0 > thr) print $2 }' "$TMP" | while read -r ip; do
  if [ -n "$ip" ]; then
    # verifica se já bloqueado
    if ! iptables -C INPUT -s "$ip" -j DROP 2>/dev/null; then
      iptables -I INPUT -s "$ip" -j DROP
      echo "$(date): Bloqueado $ip por suspeita de brute-force" >> /var/log/asterisk/blocked_sip.log
      # opcional: agendar desbloqueio (requer atd/cron) - aqui apenas registra
    fi
  fi
done

rm -f "$TMP"
