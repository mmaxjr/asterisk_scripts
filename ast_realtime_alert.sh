#!/usr/bin/env bash
# ast_realtime_alert.sh
LOG="/var/log/asterisk/full"
WEBHOOK="${AST_WEBHOOK_URL:-}"
PATTERNS=("authentication failed" "Failed to authenticate" "Unable to create RTP" "Request timed out" "DIALSTATUS=CHANUNAVAIL")
if [ -z "$WEBHOOK" ]; then
  echo "Defina AST_WEBHOOK_URL no ambiente."
  exit 1
fi

tail -n0 -F "$LOG" | while read -r line; do
  for p in "${PATTERNS[@]}"; do
    if echo "$line" | grep -qi "$p"; then
      payload="{\"text\":\"[Asterisk] $(hostname) - $(date +'%Y-%m-%d %H:%M:%S') - $(echo $line | sed 's/\"/\\\"/g')\"}"
      curl -s -X POST -H 'Content-Type: application/json' -d "$payload" "$WEBHOOK" >/dev/null 2>&1
      break
    fi
  done
done
