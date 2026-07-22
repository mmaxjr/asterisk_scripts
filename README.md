#### Visão geral
Coleção de scripts e utilitários para monitoramento, diagnóstico, testes e automação em servidores **Asterisk (chan_sip)**. Fornece ferramentas para análise de logs, verificação de ramais, monitoramento de registros, detecção de brute‑force, sondagem RTP/OPTIONS, captura do console com análise por IA (Groq), testes de chamada automatizados e um menu centralizador para executar tudo.

---

### Estrutura dos arquivos e propósito de cada script
**Local sugerido**: `~/asterisk-tools/` com scripts em `~/asterisk-tools/tools/`.

| **Arquivo** | **Propósito resumido** |
|---|---|
| `ast_toolbox_menu.sh` | Menu interativo que lista e executa scripts em `tools/`, opções rápidas e start/stop de captura IA. |
| `ast_dynamic_menu.sh` | Menu dinâmico que descobre scripts em `tools/` e permite execução com argumentos. |
| `ast_log_analyze.sh` | Analisa `/var/log/asterisk/full`, gera resumo e CSV de eventos (DIALSTATUS, erros RTP, top ramais). |
| `ast_check_peers.sh` | Verifica ramais via `sip show peer`, coleta status, IP, porta, qualify, latency; gera CSV. |
| `ast_check_peers_enhanced.sh` | Versão avançada com sondagem ativa (OPTIONS/qualify) e medição RTT. |
| `ast_register_monitor.sh` | Checa `sip show registry` e envia alerta por e‑mail/webhook se houver falhas. |
| `ast_sip_bruteforce_detect.sh` | Escaneia logs por falhas de autenticação e registra IPs suspeitos; opção de bloqueio manual. |
| `ast_sip_bruteforce_f2b.conf` | Filtro de exemplo para **fail2ban** (colocar em `/etc/fail2ban/filter.d/`). |
| `ast_rtp_stats.sh` | Captura `rtp show channels` e `rtp show statistics` para resumo de jitter/packet loss. |
| `ast_options_probe.sh` | Envia sondagens OPTIONS para peers listados e mede RTT; gera CSV. |
| `ast_cdr_summary.py` | Resume CDRs (Master.csv): total de chamadas, duração média, DIALSTATUS por período. |
| `ast_health_http.py` | Pequeno HTTP server (Flask) que expõe `/health` com métricas básicas do Asterisk. |
| `ast_tail_rotate_safe.sh` | Tail seguro que detecta rotação de logs e reabre arquivo. |
| `ast_realtime_alert.sh` | `tail -F` do log e envio de alertas para webhook quando padrões críticos aparecem. |
| `analyze_cli_with_groq.py` | Captura `asterisk -rvvvvv...` em tempo real e envia janelas para IA (Groq) para análise. |
| `analyze_cli_with_groq_masked.py` | Versão com mascaramento automático de ramais/IPs antes do envio à IA. |
| `teste_ligacao_asterisk.sh` | Automatiza `console dial` para testar chamadas; captura trecho de log, analisa localmente e opcionalmente envia para IA (flag `--ia`). |
| `ast_toolbox_menu.sh` | Menu principal (já listado) para executar os utilitários e opções rápidas. |
| `systemd` unit examples | Exemplos de units para health HTTP e captura IA. |
| `logrotate` example | Configuração de rotação para logs gerados pelos scripts. |

---

### Pré requisitos gerais
- **Acesso**: usuário com permissão para executar `asterisk -rx` e ler `/var/log/asterisk/full`. Evite usar root quando possível; prefira usuário do serviço Asterisk.
- **Ferramentas**: `bash`, `awk`, `sed`, `grep`, `tail`, `timeout`, `curl`, `jq` (recomendado), `python3`.
- **Python libs**: `requests` (para envio a IA), `flask` (para `ast_health_http.py`) — instalar via `pip3 install requests flask`.
- **Mail**: `mailx` ou outro utilitário para envio de e‑mail (opcional).
- **Fail2ban**: recomendado para proteção SIP em vez de bloqueios ad‑hoc.
- **Rede**: acesso ao endpoint de IA (se usar `--ia`) e regras de firewall que permitam comunicação com troncos SIP e RTP.

---

### Instalação e permissões
1. **Criar diretório**:
   ```bash
   mkdir -p ~/asterisk-tools/tools
   cd ~/asterisk-tools
   ```
2. **Copiar scripts** para `tools/`.
3. **Permissões**:
   ```bash
   chmod 700 tools/*.sh
   chmod 700 tools/*.py
   chmod 700 ast_toolbox_menu.sh
   ```
4. **Dependências Python**:
   ```bash
   pip3 install requests flask
   apt install jq mailx -y   # Debian/Ubuntu
   ```
5. **Variáveis de ambiente** (se usar IA):
   ```bash
   export GROQ_ENDPOINT="https://seu-endpoint-groq/v1/infer"
   export GROQ_API_KEY="SUA_CHAVE_SECRETA"
   export ALERT_EMAIL="ops@empresa.local"
   ```

---

### Documentação detalhada por script

#### ast_log_analyze.sh
- **Propósito**: gerar resumo de níveis de log, contagem por `DIALSTATUS`, top ramais, CSV com chamadas e amostras de erros RTP/codec.
- **Entrada**: `/var/log/asterisk/full` (padrão) ou arquivo passado como primeiro argumento.
- **Saída**: `summary_YYYYMMDD_HHMMSS.txt` e `calls_YYYYMMDD_HHMMSS.csv` em diretório de saída (padrão `/tmp/ast_reports` ou argumento).
- **Uso**:
  ```bash
  sudo ./ast_log_analyze.sh /var/log/asterisk/full /tmp/ast_reports
  ```
- **Observações**: lidar com rotação de logs; scripts que leem logs devem usar `tail -F` para real‑time.

#### ast_check_peers.sh
- **Propósito**: listar peers de `sip.conf` (ou `sip show peers`) e coletar `Status`, `IP Address`, `Port`, `Qualify`, `Latency`, `Monitored`.
- **Saída**: CSV `timestamp,peer,status,ip,port,qualify,latency,monitored,notes`.
- **Uso**:
  ```bash
  sudo ./ast_check_peers.sh /tmp/peers_report.csv
  ```
- **Atenção**: saída do `sip show peer` varia por versão; ajuste `awk`/`grep` se necessário.

#### ast_check_peers_enhanced.sh
- **Propósito**: além de `sip show peer`, realiza sondagem ativa (OPTIONS/qualify) e mede RTT aproximado.
- **Uso**:
  ```bash
  sudo ./ast_check_peers_enhanced.sh
  ```
- **Observação**: algumas ações podem gerar tráfego SIP; execute em janela controlada.

#### ast_register_monitor.sh
- **Propósito**: checar `sip show registry` e enviar alerta por e‑mail se troncos estiverem DOWN.
- **Configuração**: exportar `ALERT_EMAIL`.
- **Cron**: recomendado rodar a cada 5 minutos.
- **Uso**:
  ```bash
  export ALERT_EMAIL="ops@empresa.local"
  sudo ./ast_register_monitor.sh
  ```

#### ast_sip_bruteforce_detect.sh
- **Propósito**: identificar IPs com muitas tentativas de autenticação falhas e registrar para análise; exemplo de bloqueio via `iptables` (opcional).
- **Parâmetros**: `THRESHOLD` (tentativas), `WINDOW_MIN` (janela).
- **Uso**:
  ```bash
  sudo ./ast_sip_bruteforce_detect.sh 30 10
  ```
- **Recomendação**: prefira integrar com **fail2ban** em vez de bloqueios automáticos.

#### ast_sip_bruteforce_f2b.conf
- **Propósito**: filtro para fail2ban. Colocar em `/etc/fail2ban/filter.d/asterisk.conf` e criar jail em `/etc/fail2ban/jail.d/asterisk.local`.
- **Parâmetros sugeridos**: `maxretry=5`, `bantime=3600`, `findtime=600`.

#### ast_rtp_stats.sh
- **Propósito**: coletar `rtp show channels` e `rtp show statistics` para análise de jitter, packet loss e streams ativos.
- **Uso**:
  ```bash
  sudo ./ast_rtp_stats.sh
  ```

#### ast_options_probe.sh
- **Propósito**: enviar sondagens OPTIONS para uma lista de peers e medir RTT; útil para detectar reachability e latência.
- **Entrada**: arquivo `peers_list.txt` com um peer por linha.
- **Saída**: CSV com `peer,ip,port,rtt_ms,status`.
- **Uso**:
  ```bash
  sudo ./ast_options_probe.sh /etc/asterisk/peers_list.txt
  ```

#### ast_cdr_summary.py
- **Propósito**: resumir CDRs do `Master.csv` por período (dias), com totais e duração média.
- **Uso**:
  ```bash
  python3 ast_cdr_summary.py /var/log/asterisk/cdr-csv/Master.csv 7
  ```

#### ast_health_http.py
- **Propósito**: expor endpoint `/health` com métricas básicas (peers total, registered trunks, uptime).
- **Dependência**: Flask.
- **Uso**:
  ```bash
  python3 ast_health_http.py
  ```
- **Systemd**: criar unit para rodar como serviço (exemplo abaixo).

#### ast_tail_rotate_safe.sh
- **Propósito**: `tail -F` com checagem de inode para detectar rotação de logs e reabrir arquivo.
- **Uso**:
  ```bash
  sudo ./ast_tail_rotate_safe.sh /var/log/asterisk/full
  ```

#### ast_realtime_alert.sh
- **Propósito**: monitor em tempo real que envia alertas para webhook quando padrões críticos aparecem.
- **Configuração**: exportar `AST_WEBHOOK_URL`.
- **Uso**:
  ```bash
  export AST_WEBHOOK_URL="https://hooks.slack.com/services/..."
  sudo ./ast_realtime_alert.sh
  ```

#### analyze_cli_with_groq.py
- **Propósito**: captura `asterisk -rvvvvv...` em tempo real, agrega janelas e envia para endpoint de IA (Groq) para detecção de anomalias.
- **Requisitos**: `GROQ_ENDPOINT`, `GROQ_API_KEY`, `requests`.
- **Comportamento**: agrupa janelas (padrão 30s), limita linhas, grava alertas em `/var/log/asterisk/ai_alerts.log`.
- **Uso**:
  ```bash
  export GROQ_ENDPOINT="..."
  export GROQ_API_KEY="..."
  sudo python3 analyze_cli_with_groq.py
  ```

#### analyze_cli_with_groq_masked.py
- **Propósito**: mesma função do anterior com mascaramento automático de ramais e IPs antes do envio.
- **Configuração**: `MASK_PHONE`, `MASK_IP` variáveis internas; usa `jq` para montar payload se disponível.
- **Uso**:
  ```bash
  sudo python3 analyze_cli_with_groq_masked.py
  ```

#### teste_ligacao_asterisk.sh
- **Propósito**: automatiza `console dial` para realizar uma chamada de teste, captura trecho de log, analisa localmente por padrões de erro e opcionalmente envia o trecho para IA (flag `--ia`).
- **Opções**:
  - `--ramal <origem>` **(obrigatório)**
  - `--numero <destino>` **(obrigatório)**
  - `--contexto <contexto>` (padrão `teste`)
  - `--duracao <segundos>` (padrão `30`)
  - `--ia` envia trecho para IA (requer `GROQ_ENDPOINT` e `GROQ_API_KEY`)
- **Saídas**:
  - relatório em `TMPDIR/ast_test_report.txt`
  - trecho de log em `TMPDIR/log_snippet_saved.log`
  - resposta IA em `TMPDIR/groq_response.json` (se `--ia`)
- **Uso**:
  ```bash
  sudo ./teste_ligacao_asterisk.sh --ramal 1220 --numero 40099063 --contexto teste --duracao 40 --ia
  ```
- **Mascaramento**: aplica substituição de ramais e IPs antes do envio à IA; ajuste regex conforme ambiente.
- **Recomendações**: testar sem `--ia` primeiro; revisar arquivos temporários após execução.

---

### Variáveis de ambiente importantes
- **GROQ_ENDPOINT** — endpoint HTTP do provedor IA.
- **GROQ_API_KEY** — chave de API para autenticação.
- **ALERT_EMAIL** — e‑mail para alertas do monitor de registros.
- **AST_WEBHOOK_URL** — webhook para alertas em tempo real.
- **REPORTS_DIR** — diretório para relatórios (padrão `tools/reports`).
- **LOG_DIR** — diretório de logs (padrão `/var/log/asterisk`).

---

### Exemplos de systemd units
**Health HTTP**
```
[Unit]
Description=Asterisk Health HTTP
After=network.target

[Service]
Type=simple
User=asterisk
Group=asterisk
WorkingDirectory=/opt/asterisk-tools
ExecStart=/usr/bin/python3 /opt/asterisk-tools/tools/ast_health_http.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**AI capture**
```
[Unit]
Description=Asterisk CLI AI Capture
After=network.target

[Service]
Type=simple
User=asterisk
Group=asterisk
WorkingDirectory=/opt/asterisk-tools
ExecStart=/usr/bin/python3 /opt/asterisk-tools/tools/analyze_cli_with_groq_masked.py
Restart=on-failure
RestartSec=30
Environment=GROQ_ENDPOINT=https://... GROQ_API_KEY=...
```

---

### Exemplo de logrotate para relatórios e logs gerados
Colocar em `/etc/logrotate.d/asterisk-tools`:
```
/var/log/asterisk/ai_alerts.log /var/log/asterisk/*.log {
    daily
    rotate 14
    compress
    missingok
    notifempty
    create 0640 asterisk asterisk
    sharedscripts
    postrotate
        systemctl reload rsyslog >/dev/null 2>&1 || true
    endscript
}
```

---

### Segurança e boas práticas operacionais
- **Permissões**: scripts com acesso ao CLI e logs devem ter permissões restritas (`chmod 700`) e pertencer a usuário apropriado.
- **Mascaramento**: sempre mascarar ramais, IPs e credenciais antes de enviar logs a terceiros.
- **Proteção SIP**: habilitar TLS/SRTP, usar fail2ban, limitar tentativas e aplicar rate limiting no firewall.
- **Auditoria**: registrar decisões automáticas (bloqueios, alertas) em logs separados para revisão humana.
- **Testes**: validar scripts em ambiente de homologação antes de produção.
- **Rotina**: agendar checks regulares via cron ou systemd timers; evitar sondagens contínuas que gerem tráfego desnecessário.

---

### Troubleshooting comum
- **`asterisk -rx` sem saída**: verifique permissões do usuário; tente `sudo -u asterisk asterisk -rx ...`.
- **Logs não aparecem no snippet**: confirme formato de timestamp no log; ajuste parsing no script.
- **Envio IA falha**: verifique `GROQ_ENDPOINT`, `GROQ_API_KEY`, conectividade de rede e limites do provedor.
- **Falsos positivos de brute‑force**: revisar janelas e thresholds; prefira fail2ban com filtros bem definidos.
- **Problemas com `sip show peer` parsing**: saída varia por versão; adapte `awk`/`grep` conforme seu Asterisk.

---

### FAQ rápido
- **Posso usar PJSIP?** — Sim. Scripts que usam `sip show ...` precisam ser adaptados para `pjsip show endpoint`, `pjsip show registrations`. Posso gerar versões PJSIP.
- **Posso enviar alertas para Slack?** — Sim. Substitua envio por `mailx` por `curl` para webhook Slack/Teams.
- **Os scripts bloqueiam IPs automaticamente?** — Alguns exemplos mostram bloqueio; por segurança, prefira registrar e usar fail2ban para bloqueios automáticos.

---

### Checklist de implantação
1. Testar cada script em homologação.  
2. Configurar variáveis de ambiente seguras (não em arquivos públicos).  
3. Habilitar fail2ban e regras de firewall.  
4. Configurar logrotate para logs gerados.  
5. Criar systemd units para serviços persistentes (health, captura IA).  
6. Revisar e remover arquivos temporários após análise.

---

### Changelog resumido
- **v1.0** — Conjunto inicial: análise de logs, verificação de peers, monitor de registros, brute‑force detect, menu interativo.  
- **v1.1** — Adicionados scripts RTP/OPTIONS, CDR summary, health HTTP.  
- **v1.2** — Adicionada captura CLI + integração IA (Groq) com versão mascarada.  
- **v1.3** — `teste_ligacao_asterisk.sh` com opção `--ia`, mascaramento e relatório detalhado.

---

### Próximos passos que posso entregar
- Adaptação completa para **PJSIP**.  
- Integração com **Slack/Teams** para alertas.  
- `systemd` units e timers prontos para deploy.  
- Integração com **Vault** para gerenciar `GROQ_API_KEY`.  
- Transformar saídas em métricas Prometheus.

