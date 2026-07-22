#!/usr/bin/env bash
# ast_toolbox_menu.sh
# Menu interativo para executar ferramentas Asterisk.
# Coloque seus scripts em ./tools (ou informe outro diretório como argumento).
# Uso: sudo ./ast_toolbox_menu.sh [TOOLS_DIR]
set -euo pipefail

TOOLS_DIR="${1:-./tools}"
LOG_DIR="${LOG_DIR:-/var/log/asterisk}"
AI_LOG="${AI_LOG:-$LOG_DIR/ai_cli.log}"
REPORTS_DIR="${REPORTS_DIR:-$TOOLS_DIR/reports}"

mkdir -p "$TOOLS_DIR" "$REPORTS_DIR" "$LOG_DIR"

# helper: mostra cabeçalho
print_header() {
  echo "========================================"
  echo " Asterisk Toolbox - Menu"
  echo " Diretório de ferramentas: $TOOLS_DIR"
  echo " Reports: $REPORTS_DIR"
  echo "========================================"
}

# helper: lista scripts e tenta extrair uma descrição da primeira linha comentada
list_tools() {
  mapfile -t files < <(ls -1 "$TOOLS_DIR" 2>/dev/null | grep -E '\.sh$|\.py$' || true)
  if [ ${#files[@]} -eq 0 ]; then
    echo "Nenhum script encontrado em $TOOLS_DIR."
    echo "Coloque scripts .sh ou .py no diretório e reabra o menu."
    return 1
  fi
  for i in "${!files[@]}"; do
    file="$TOOLS_DIR/${files[$i]}"
    # tenta extrair comentário de descrição (primeira linha que começa com #)
    desc=$(grep -m1 -E '^#' "$file" 2>/dev/null | sed 's/^#\s*//; s/\r$//' || true)
    printf "%2d) %s\t- %s\n" $((i+1)) "${files[$i]}" "${desc:-sem descrição}"
  done
  echo " q) Sair"
}

# executa script com prompt para argumentos
run_script() {
  local selfile="$1"
  echo "Executando: $selfile"
  read -p "Passar argumentos? (enter para nenhum): " args
  if [[ "$selfile" == *.py ]]; then
    python3 "$selfile" $args
  else
    bash "$selfile" $args
  fi
}

# opções rápidas predefinidas
run_quick_all() {
  echo "Executando checks principais em sequência..."
  # adapta nomes conforme seus scripts presentes
  [ -x "$TOOLS_DIR/ast_log_analyze.sh" ] && bash "$TOOLS_DIR/ast_log_analyze.sh" "/var/log/asterisk/full" "$REPORTS_DIR" || true
  [ -x "$TOOLS_DIR/ast_check_peers.sh" ] && bash "$TOOLS_DIR/ast_check_peers.sh" "/tmp/peers_$(date +%s).csv" || true
  [ -x "$TOOLS_DIR/ast_register_monitor.sh" ] && bash "$TOOLS_DIR/ast_register_monitor.sh" || true
  [ -x "$TOOLS_DIR/ast_sip_bruteforce_detect.sh" ] && bash "$TOOLS_DIR/ast_sip_bruteforce_detect.sh" 30 10 || true
  echo "Execução concluída. Verifique $REPORTS_DIR e /tmp para saídas."
}

# iniciar captura CLI+IA em background
start_ai_capture_bg() {
  if [ -z "${GROQ_ENDPOINT:-}" ] || [ -z "${GROQ_API_KEY:-}" ]; then
    echo "Variáveis GROQ_ENDPOINT e GROQ_API_KEY não definidas. Exporte-as antes de rodar."
    return
  fi
  if [ -x "$TOOLS_DIR/analyze_cli_with_groq_masked.py" ]; then
    nohup python3 "$TOOLS_DIR/analyze_cli_with_groq_masked.py" > "$AI_LOG" 2>&1 &
    echo "Captura CLI+IA iniciada em background. Logs: $AI_LOG"
  else
    echo "Script analyze_cli_with_groq_masked.py não encontrado ou não executável."
  fi
}

# loop principal
while true; do
  print_header
  if ! list_tools; then
    echo "Pressione Enter para criar diretório tools e sair."
    read -r _
    exit 0
  fi
  echo ""
  echo "Opções rápidas:"
  echo " a) Executar todos os checks principais"
  echo " b) Iniciar captura CLI+IA em background"
  echo ""
  read -p "Escolha uma opção (número / a / b / q): " choice
  case "$choice" in
    q|Q) echo "Saindo."; exit 0;;
    a|A) run_quick_all;;
    b|B) start_ai_capture_bg;;
    *)
      if [[ "$choice" =~ ^[0-9]+$ ]]; then
        idx=$((choice-1))
        mapfile -t files < <(ls -1 "$TOOLS_DIR" | grep -E '\.sh$|\.py$' || true)
        if [ $idx -ge 0 ] && [ $idx -lt ${#files[@]} ]; then
          run_script "$TOOLS_DIR/${files[$idx]}"
        else
          echo "Opção inválida."
        fi
      else
        echo "Opção inválida."
      fi
      ;;
  esac
  echo -e "\nPressione Enter para voltar ao menu..."
  read -r _
done
