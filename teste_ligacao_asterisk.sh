#!/usr/bin/env bash
# teste_ligacao_asterisk.sh
# Automatiza uma chamada de teste via "console dial", captura log, analisa localmente
# e opcionalmente envia trecho para IA (Groq) com --ia.
# Uso:
# sudo ./teste_ligacao_asterisk.sh --ramal 1220 --numero 40099063 --contexto teste --duracao 30 [--ia]
# Requisitos: asterisk CLI acessível, curl, jq (opcional, para formatar resposta)

set -euo pipefail

# Defaults
RAMAL=""
NUMERO=""
CONTEXTO="teste"
DURACAO=30
LOG_FILE="/var/log/asterisk/full"
USE_IA=0
TMPDIR=$(mktemp -d /tmp/ast_test.XXXX)
TAIL_PID=""
TAIL_OUT="$TMPDIR/ast_cli_tail.log"
REPORT="$TMPDIR/ast_test_report.txt"
MASK_PHONE=1
MASK_IP=1
GROQ_ENDPOINT="${GROQ_ENDPOINT:-}"
GROQ_API_KEY="${GROQ_API_KEY:-}"

usage() {
  cat <<EOF
Uso: $0 --ramal <ramal_origem> --numero <numero_destino> [--contexto <contexto>] [--duracao <segundos>] [--ia]
Exemplo: sudo $0 --ramal 1220 --numero 40099063 --contexto teste --duracao 40 --ia
EOF
  exit 1
}

# parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ramal) RAMAL="$2"; shift 2;;
    --numero) NUMERO="$2"; shift 2;;
    --contexto) CONTEXTO="$2"; shift 2;;
    --duracao) DURACAO="$2"; shift 2;;
    --log) LOG_FILE="$2"; shift 2;;
    --ia) USE_IA=1; shift 1;;
    -h|--help) usage;;
    *) echo "Parâmetro desconhecido: $1"; usage;;
  esac
done

if [ -z "$RAMAL" ] || [ -z "$NUMERO" ]; then
  echo "Erro: --ramal e --numero são obrigatórios."
  usage
fi

cleanup() {
  [ -n "$TAIL_PID" ] && kill "$TAIL_PID" 2>/dev/null || true
  # manter TMPDIR para inspeção; remova manualmente quando não precisar
}
trap cleanup EXIT

echo "Iniciando teste de chamada"
echo "Ramal: $RAMAL  Número: $NUMERO  Contexto: $CONTEXTO  Duração espera: ${DURACAO}s"
echo "Logs serão capturados de: $LOG_FILE"
echo "Diretório temporário: $TMPDIR"
echo "" > "$REPORT"

# 1) inicia tail seguro do log
if [ ! -f "$LOG_FILE" ]; then
  echo "Arquivo de log não encontrado: $LOG_FILE" | tee -a "$REPORT"
  exit 1
fi
tail -n0 -F "$LOG_FILE" > "$TAIL_OUT" 2>/dev/null &
TAIL_PID=$!
sleep 0.5

# 2) monta comando console dial (ajuste se sua sintaxe for diferente)
ORIG_LABEL="RAMAL"
DEST_LABEL="DEST"
DIAL_CMD="console dial ${RAMAL}(${ORIG_LABEL})${NUMERO}(${DEST_LABEL})@${CONTEXTO}(CTX)"

echo "Executando comando Asterisk: $DIAL_CMD" | tee -a "$REPORT"

# 3) executa o comando via CLI e aguarda DURACAO segundos
if ! timeout "$((DURACAO+15))" bash -c "asterisk -rx \"$DIAL_CMD\"" 2>>"$REPORT"; then
  echo "Aviso: comando asterisk retornou com erro ou timeout." | tee -a "$REPORT"
fi

# 4) aguarda DURACAO segundos para coletar logs relacionados
echo "Aguardando $DURACAO segundos para coletar logs da chamada..." | tee -a "$REPORT"
sleep "$DURACAO"

# 5) interrompe o tail e coleta o trecho relevante do log
kill "$TAIL_PID" 2>/dev/null || true
sleep 0.2

NOW_EPOCH=$(date +%s)
WINDOW=$((DURACAO + 30))
LOG_SNIPPET="$TMPDIR/log_snippet.log"

# tenta extrair por timestamp ISO "YYYY-MM-DD HH:MM:SS"
if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} ' "$TAIL_OUT" 2>/dev/null; then
  awk -v now="$NOW_EPOCH" -v win="$WINDOW" '
    {
      ts = substr($0,1,19)
      gsub(/[-:]/," ",ts)
      if (match(ts, /^[0-9]{4} [0-9]{2} [0-9]{2} [0-9]{2} [0-9]{2} [0-9]{2}$/)) {
        cmd = "date -d \"" ts "\" +%s"
        cmd | getline t
        close(cmd)
        if (t+0 >= now-win) print $0
      } else {
        print $0
      }
    }' "$TAIL_OUT" > "$LOG_SNIPPET" 2>/dev/null || tail -n 1000 "$TAIL_OUT" > "$LOG_SNIPPET"
else
  tail -n 1000 "$TAIL_OUT" > "$LOG_SNIPPET"
fi

# 6) análise local de problemas
echo "" >> "$REPORT"
echo "=== Análise automática de problemas (local) ===" >> "$REPORT"

PATTERNS=(
  "DIALSTATUS=BUSY"
  "DIALSTATUS=CHANUNAVAIL"
  "DIALSTATUS=CONGESTION"
  "DIALSTATUS=NOANSWER"
  "DIALSTATUS=FAILED"
  "Busy here"
  "is busy"
  "CONGESTION"
  "No answer"
  "Call failed"
  "Authentication for user"
  "Failed to authenticate"
  "Request timed out"
  "Unable to create RTP"
  "jitter"
  "packet loss"
  "Hangup"
  "Answered"
)

FOUND=0
echo "Trechos relevantes encontrados:" >> "$REPORT"
for p in "${PATTERNS[@]}"; do
  matches=$(grep -i -- "$p" "$LOG_SNIPPET" || true)
  if [ -n "$matches" ]; then
    FOUND=$((FOUND+1))
    echo "---- Padrão: $p ----" >> "$REPORT"
    echo "$matches" >> "$REPORT"
    echo "" >> "$REPORT"
  fi
done

echo "=== Resumo local ===" >> "$REPORT"
if [ "$FOUND" -eq 0 ]; then
  echo "Nenhum problema óbvio detectado nos padrões verificados." >> "$REPORT"
  if grep -qi "Answered" "$LOG_SNIPPET" || grep -qi "DIALSTATUS=ANSWER" "$LOG_SNIPPET"; then
    echo "Indicação de chamada atendida encontrada." >> "$REPORT"
  else
    echo "Nenhuma indicação clara de 'Answered' encontrada; verifique manualmente o trecho de log." >> "$REPORT"
  fi
else
  echo "Ocorrências encontradas que podem indicar problemas. Verifique o relatório detalhado." >> "$REPORT"
fi

# 7) prepara payload para IA (mascaramento simples)
mask_content() {
  local infile="$1"
  local outfile="$2"
  # mascara ramais (2-6 dígitos) e IPs
  if [ "$MASK_PHONE" -eq 1 ]; then
    sed -E 's/\b[0-9]{2,6}\b/EXT_REDACTED/g' "$infile" > "$outfile.tmp" || cp "$infile" "$outfile.tmp"
  else
    cp "$infile" "$outfile.tmp"
  fi
  if [ "$MASK_IP" -eq 1 ]; then
    sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/IP_REDACTED/g' "$outfile.tmp" > "$outfile" || mv "$outfile.tmp" "$outfile"
  else
    mv "$outfile.tmp" "$outfile"
  fi
  # remove possíveis credenciais simples
  sed -i -E 's/(username=)[^&\s]+/\1REDACTED/Ig' "$outfile" || true
  sed -i -E 's/(password=)[^&\s]+/\1REDACTED/Ig' "$outfile" || true
}

if [ "$USE_IA" -eq 1 ]; then
  echo "" >> "$REPORT"
  echo "=== Envio para IA (Groq) solicitado ===" >> "$REPORT"
  if [ -z "$GROQ_ENDPOINT" ] || [ -z "$GROQ_API_KEY" ]; then
    echo "Erro: variáveis de ambiente GROQ_ENDPOINT e GROQ_API_KEY não definidas. Abortando envio IA." | tee -a "$REPORT"
  else
    MASKED="$TMPDIR/log_masked.log"
    mask_content "$LOG_SNIPPET" "$MASKED"
    # limita tamanho do payload (ex.: 8000 linhas ou 200KB)
    head -n 8000 "$MASKED" > "$TMPDIR/log_masked_trimmed.log" || cp "$MASKED" "$TMPDIR/log_masked_trimmed.log"
    # monta JSON (escape)
    PAYLOAD=$(jq -Rs --arg host "$(hostname)" --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      '{input: . , metadata: {host: $host, timestamp: $ts}}' < "$TMPDIR/log_masked_trimmed.log")
    # envia via curl
    RESP_FILE="$TMPDIR/groq_response.json"
    HTTP_STATUS=$(curl -sS -w "%{http_code}" -o "$RESP_FILE" \
      -X POST "$GROQ_ENDPOINT" \
      -H "Authorization: Bearer $GROQ_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" || echo "000")
    if [ "$HTTP_STATUS" = "000" ]; then
      echo "Erro de conexão ao enviar para IA. Verifique rede/endpoint." | tee -a "$REPORT"
      echo "Resposta bruta salva em: $RESP_FILE" >> "$REPORT"
    else
      echo "IA retornou HTTP status: $HTTP_STATUS" >> "$REPORT"
      # tenta extrair campos comuns: anomaly_score, issues, recommendation
      if command -v jq >/dev/null 2>&1; then
        SCORE=$(jq -r '.anomaly_score // .score // empty' "$RESP_FILE" 2>/dev/null || true)
        ISSUES=$(jq -r '.issues // empty' "$RESP_FILE" 2>/dev/null || true)
        REC=$(jq -r '.recommendation // .recommendations // empty' "$RESP_FILE" 2>/dev/null || true)
        echo "IA - anomaly_score: ${SCORE:-n/a}" >> "$REPORT"
        echo "IA - issues: ${ISSUES:-n/a}" >> "$REPORT"
        echo "IA - recommendation: ${REC:-n/a}" >> "$REPORT"
      else
        echo "jq não disponível; salvando resposta bruta." >> "$REPORT"
        echo "Resposta IA salva em: $RESP_FILE" >> "$REPORT"
      fi
    fi
  fi
fi

# 8) salvar snippet e relatório
cp "$LOG_SNIPPET" "$TMPDIR/log_snippet_saved.log"
echo "" >> "$REPORT"
echo "Relatório completo salvo em: $REPORT" | tee -a "$REPORT"
echo "Trecho de log salvo em: $TMPDIR/log_snippet_saved.log" | tee -a "$REPORT"

# 9) resumo para usuário
echo ""
echo "=== Resultado rápido ==="
echo "Relatório: $REPORT"
echo "Trecho de log: $TMPDIR/log_snippet_saved.log"
if [ "$USE_IA" -eq 1 ]; then
  echo "Resposta IA (se enviada): $TMPDIR/groq_response.json"
fi
echo "Arquivos temporários mantidos em $TMPDIR para inspeção."
