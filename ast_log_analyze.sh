#!/usr/bin/env bash
# ast_log_analyze.sh
LOG="${1:-/var/log/asterisk/full}"
OUT_DIR="${2:-/tmp/ast_log_report}"
mkdir -p "$OUT_DIR"
TS=$(date +"%Y%m%d_%H%M%S")
SUMMARY="$OUT_DIR/summary_$TS.txt"
CSV_CALLS="$OUT_DIR/calls_$TS.csv"

echo "Gerando relatório a partir de $LOG ..."
echo "Relatório: $SUMMARY"
echo "CSV de chamadas: $CSV_CALLS"

# 1) Contagem geral de níveis de log
echo "=== Contagem por nível (WARNING/ERROR/NOTICE/DEBUG) ===" > "$SUMMARY"
egrep -i "WARNING|ERROR|NOTICE|DEBUG" "$LOG" | awk '{print $3}' | sort | uniq -c | sort -rn >> "$SUMMARY"

# 2) Contagem por DIALSTATUS
echo -e "\n=== DIALSTATUS counts ===" >> "$SUMMARY"
grep -oP "DIALSTATUS=\K[A-Z_]+" "$LOG" | sort | uniq -c | sort -rn >> "$SUMMARY"

# 3) Top 50 ramais com mais eventos (extrai números entre colchetes ou 'to <ext>')
echo -e "\n=== Top 50 ramais mencionados ===" >> "$SUMMARY"
grep -oP "

\[?([0-9]{2,6})\]

?" "$LOG" | grep -E "^[0-9]{2,6}$" | sort | uniq -c | sort -rn | head -n 50 >> "$SUMMARY"

# 4) CSV de chamadas: timestamp,caller,callee,dialstatus,reason
echo "timestamp,caller,callee,dialstatus,reason" > "$CSV_CALLS"
# tenta extrair linhas com DIALSTATUS
grep "DIALSTATUS=" "$LOG" | while read -r line; do
  ts=$(echo "$line" | awk '{print $1" "$2}')
  caller=$(echo "$line" | grep -oP "from '?\K[0-9]{2,6}(?='?)" || echo "")
  callee=$(echo "$line" | grep -oP "to '?\K[0-9]{2,6}(?='?)" || echo "")
  ds=$(echo "$line" | grep -oP "DIALSTATUS=\K[A-Z_]+" || echo "")
  reason=$(echo "$line" | sed -n '1p' | sed 's/"/""/g')
  echo "\"$ts\",\"$caller\",\"$callee\",\"$ds\",\"$reason\"" >> "$CSV_CALLS"
done

# 5) Erros de codec / RTP
echo -e "\n=== Erros de codec / RTP ===" >> "$SUMMARY"
egrep -i "codec|RTP|rtp|No such device|Unable to create RTP" "$LOG" | tail -n 200 >> "$SUMMARY"

echo "Relatórios gerados em $OUT_DIR"
