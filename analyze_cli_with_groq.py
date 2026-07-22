#!/usr/bin/env python3
# analyze_cli_with_groq.py
# Captura saída do Asterisk CLI em modo verbose e envia blocos para um endpoint de IA (Groq).
# Uso: export GROQ_API_KEY="sua_chave"; export GROQ_ENDPOINT="https://api.groq.ai/v1/infer"; sudo python3 analyze_cli_with_groq.py

import os
import subprocess
import time
import threading
import requests
import json
from collections import deque

# Config
WINDOW_SECONDS = int(os.getenv("AST_AI_WINDOW", "30"))   # janela de agregação
MAX_LINES = int(os.getenv("AST_AI_MAX_LINES", "1000"))   # máximo de linhas por payload
GROQ_ENDPOINT = os.getenv("GROQ_ENDPOINT")
GROQ_API_KEY = os.getenv("GROQ_API_KEY")
ALERT_THRESHOLD = float(os.getenv("AST_AI_THRESHOLD", "0.7"))  # score acima => alerta

if not GROQ_ENDPOINT or not GROQ_API_KEY:
    raise SystemExit("Defina GROQ_ENDPOINT e GROQ_API_KEY no ambiente antes de rodar.")

# fila thread-safe
buffer = deque()
lock = threading.Lock()

def read_asterisk_cli():
    # abre asterisk CLI em modo remoto (assume acesso)
    # -r conecta ao console remoto; -vvvv... nível de verbose
    cmd = ["asterisk", "-rvvvvvvvvvvv"]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    try:
        for line in p.stdout:
            with lock:
                buffer.append(line.rstrip("\n"))
                # limita tamanho
                while len(buffer) > MAX_LINES:
                    buffer.popleft()
    except KeyboardInterrupt:
        p.terminate()
        raise

def build_payload(lines):
    # constrói payload simples; inclua metadados se desejar
    return {
        "input": "\n".join(lines),
        "metadata": {
            "host": os.uname().nodename,
            "timestamp": int(time.time())
        }
    }

def call_groq(payload):
    headers = {
        "Authorization": f"Bearer {GROQ_API_KEY}",
        "Content-Type": "application/json"
    }
    try:
        resp = requests.post(GROQ_ENDPOINT, headers=headers, json=payload, timeout=15)
        resp.raise_for_status()
        return resp.json()
    except Exception as e:
        return {"error": str(e)}

def analyzer_loop():
    while True:
        time.sleep(WINDOW_SECONDS)
        with lock:
            if not buffer:
                continue
            # pega snapshot e limpa buffer
            snapshot = list(buffer)
            buffer.clear()
        # reduz payload se necessário
        if len(snapshot) > MAX_LINES:
            snapshot = snapshot[-MAX_LINES:]
        payload = build_payload(snapshot)
        result = call_groq(payload)
        # Exemplo de formato esperado do modelo:
        # { "anomaly_score": 0.82, "issues": ["SIP auth failures", "High jitter"], "recommendation": "Check NAT and QoS" }
        if "error" in result:
            print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Erro ao chamar Groq: {result['error']}")
            continue
        # parse seguro
        score = result.get("anomaly_score", 0.0)
        issues = result.get("issues", [])
        rec = result.get("recommendation", "")
        ts = time.strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{ts}] AI score: {score:.2f} issues: {issues}")
        if score >= ALERT_THRESHOLD:
            # ação: log local e opcional webhook/email (implemente conforme política)
            alert = {
                "time": ts,
                "score": score,
                "issues": issues,
                "recommendation": rec
            }
            # grava em arquivo de alertas
            with open("/var/log/asterisk/ai_alerts.log", "a") as f:
                f.write(json.dumps(alert, ensure_ascii=False) + "\n")
            print(f"[{ts}] ALERT: score {score:.2f} >= {ALERT_THRESHOLD}. Recomendações: {rec}")

if __name__ == "__main__":
    # threads: leitura e análise
    t_read = threading.Thread(target=read_asterisk_cli, daemon=True)
    t_read.start()
    try:
        analyzer_loop()
    except KeyboardInterrupt:
        print("Encerrando...")
