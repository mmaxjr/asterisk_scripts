#!/usr/bin/env bash
# teste_ligacao_asterisk.sh
# Automatiza uma chamada de teste via "console dial" e analisa o log.
# Uso: sudo ./teste_ligacao_asterisk.sh --ramal 1220 --numero 40099063 --contexto teste --duracao 30

set -euo pipefail

# Defaults
RAMAL=""
NUMERO=""
CONTEXTO="teste"
DURACAO="${DURACAO:-30}"   # segundos para aguardar a chamada
LOG_FILE="${LOG_FILE:-/var/log/asterisk/full}"
TMPDIR=$(mktemp -d /tmp/ast_test.XXXX)
TAIL_PID=""
TAIL_OUT="$TMPDIR/ast_cli_tail.log"
REPORT="$TMPDIR/ast_test_report.txt"

usage() {
  cat <<EOF
Uso: $0 --ramal <ramal_origem> --numero <numero_destino> [--contexto <contexto>] [--duracao <segundos>]
Exemplo: sudo $0 --ramal 1220 --numero 40099063 --contexto teste --duracao 40
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
    -h|--help) usage;;
    *) echo "Parâmetro desconhecido: $1"; usage;;
  esac
done

if [ -z "$RAMAL" ] || [ -z "$NUMERO" ]; then
  echo "Erro: ramal e numero são obrigatórios."
  usage
fi

# função para cleanup
cleanup() {
  [ -n "$TAIL_PID" ] && kill "$TAIL_PID" 2>/dev/null || true
  # opcional: manter TMPDIR para inspeção; comentar a linha abaixo para preservar
  # rm -rf "$TMPDIR"
}
trap cleanup EXIT

echo "Iniciando teste de chamada"
echo "Ramal: $RAMAL  Número: $NUMERO  Contexto: $CONTEXTO  Duração espera: ${DURACAO}s"
echo "Logs serão capturados de: $LOG_FILE"
echo "Diretório temporário: $TMPDIR"
echo "" > "$REPORT"

# 1) inicia tail seguro do log (reabre em rotações)
# usa tail -F para acompanhar rotação; redireciona para arquivo temporário
tail -n0 -F "$LOG_FILE" > "$TAIL_OUT" 2>/dev/null &
TAIL_PID=$!
sleep 0.5

# 2) monta comando console dial conforme exemplo do usuário
# Formato: console dial 1220(RAMAL)40099063(Para onde vou ligar)@teste(contexto teste)
# Vamos usar labels simples para evitar caracteres problemáticos
ORIG_LABEL="RAMAL"
DEST_LABEL="DEST"
CONTEXT_LABEL="CTX"
DIAL_CMD="console dial ${RAMAL}(${ORIG_LABEL})${NUMERO}(${DEST_LABEL})@${CONTEXTO}(${CONTEXT_LABEL})"

echo "Executando comando Asterisk: $DIAL_CMD" | tee -a "$REPORT"
# 3) executa o comando via CLI e aguarda DURACAO segundos
# usamos timeout para garantir que não fique preso
if ! timeout "$((DURACAO+10))" bash -c "asterisk -rx \"$DIAL_CMD\"" 2>>"$REPORT"; then
  echo "Aviso: comando asterisk retornou com erro ou timeout." | tee -a "$REPORT"
fi

# 4) aguarda DURACAO segundos para coletar logs relacionados
echo "Aguardando $DURACAO segundos para coletar logs da chamada..." | tee -a "$REPORT"
sleep "$DURACAO"

# 5) interrompe o tail e coleta o trecho relevante do log
kill "$TAIL_PID" 2>/dev/null || true
sleep 0.2

# extrai apenas as linhas do período recente (últimos DURACAO+15 segundos)
# pega timestamp atual e converte para epoch; tenta extrair linhas por timestamp do log (formato comum "YYYY-MM-DD HH:MM:SS")
NOW_EPOCH=$(date +%s)
WINDOW=$((DURACAO + 30))
# fallback: se o log não tiver timestamps parseáveis, pega as últimas 1000 linhas
LOG_SNIPPET="$TMPDIR/log_snippet.log"

# tenta extrair por timestamp (formato ISO ou similar)
if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} ' "$TAIL_OUT" 2>/dev/null; then
  # converte cada linha timestamp para epoch e filtra
  awk -v now="$NOW_EPOCH" -v win="$WINDOW" '
    {
      ts = substr($0,1,19)
      gsub(/[-:]/," ",ts)
      # tenta parse simples YYYY MM DD HH MM SS
      if (match(ts, /^[0-9]{4} [0-9]{2} [0-9]{2} [0-9]{2} [0-9]{2} [0-9]{2}$/)) {
        cmd = "date -d \"" ts "\" +%s"
        cmd | getline t
        close(cmd)
        if (t+0 >= now-win) print $0
      } else {
        # se não parsear, imprime para fallback
        print $0
      }
    }' now="$NOW_EPOCH" "$TAIL_OUT" > "$LOG_SNIPPET" 2>/dev/null || tail -n 1000 "$TAIL_OUT" > "$LOG_SNIPPET"
else
  tail -n 1000 "$TAIL_OUT" > "$LOG_SNIPPET"
fi

# 6) análise simples de problemas
echo "" >> "$REPORT"
echo "=== Análise automática de problemas ===" >> "$REPORT"

# padrões a procurar
declare -a PATTERNS=(
  "DIALSTATUS=BUSY"
  "DIALSTATUS=CHANUNAVAIL"
  "DIALSTATUS=CONGESTION"
  "DIALSTATUS=NOANSWER"
  "DIALSTATUS=ANSWER"
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

# coleta ocorrências
FOUND=0
echo "Trechos relevantes encontrados:" >> "$REPORT"
for p in "${PATTERNS[@]}"; do
  # case-insensitive grep
  matches=$(grep -i -- "$p" "$LOG_SNIPPET" || true)
  if [ -n "$matches" ]; then
    FOUND=$((FOUND+1))
    echo "---- Padrão: $p ----" >> "$REPORT"
    echo "$matches" >> "$REPORT"
    echo "" >> "$REPORT"
  fi
done

# 7) resumo final
echo "=== Resumo ===" | tee -a "$REPORT"
if [ "$FOUND" -eq 0 ]; then
  echo "Nenhum problema óbvio detectado nos padrões verificados." | tee -a "$REPORT"
  # opcional: procurar por 'ANSWERED' para confirmar sucesso
  if grep -qi "Answered" "$LOG_SNIPPET" || grep -qi "DIALSTATUS=ANSWER" "$LOG_SNIPPET"; then
    echo "Indicação de chamada atendida encontrada." | tee -a "$REPORT"
  else
    echo "Nenhuma indicação clara de 'Answered' encontrada; verifique manualmente o trecho de log." | tee -a "$REPORT"
  fi
else
  echo "Foram encontradas ocorrências que podem indicar problemas. Verifique o relatório detalhado." | tee -a "$REPORT"
fi

# 8) salvar snippet e relatório no TMPDIR e exibir caminho
cp "$LOG_SNIPPET" "$TMPDIR/log_snippet_saved.log"
echo "" >> "$REPORT"
echo "Relatório completo salvo em: $REPORT" | tee -a "$REPORT"
echo "Trecho de log salvo em: $TMPDIR/log_snippet_saved.log" | tee -a "$REPORT"

# 9) exibe resumo curto para o usuário
echo ""
echo "=== Resultado rápido ==="
echo "Relatório: $REPORT"
echo "Trecho de log: $TMPDIR/log_snippet_saved.log"
echo "Para inspecionar manualmente, abra os arquivos acima."
