#!/usr/bin/env python3
# ast_log_analyzer.py
# Uso: python3 ast_log_analyzer.py /var/log/asterisk/full --out /tmp/report.json

import re, sys, json, argparse, csv
from collections import Counter, defaultdict
from datetime import datetime

parser = argparse.ArgumentParser()
parser.add_argument("logfile")
parser.add_argument("--out", default="/tmp/ast_report.json")
args = parser.parse_args()

dial_re = re.compile(r"DIALSTATUS=([A-Z_]+)")
reg_fail_re = re.compile(r"Registration from '?.*' failed|Request timed out|Failed to authenticate", re.I)
peer_re = re.compile(r"Peer '([^']+)'")
ip_re = re.compile(r"((?:\d{1,3}\.){3}\d{1,3})")

counts = Counter()
per_peer = defaultdict(Counter)
errors = []

with open(args.logfile, "r", errors="ignore") as f:
    for line in f:
        if dial_re.search(line):
            ds = dial_re.search(line).group(1)
            counts[f"dialstatus:{ds}"] += 1
            # tenta extrair caller/callee
            peers = peer_re.findall(line)
            for p in peers:
                per_peer[p]["dialstatus_"+ds] += 1
        if reg_fail_re.search(line):
            counts["register_fail"] += 1
            errors.append(line.strip())
        if re.search(r"RTP|rtp|Unable to create RTP|No such device|codec", line, re.I):
            counts["rtp_codec_issues"] += 1
            errors.append(line.strip())
        # detecta auth failures
        if re.search(r"authentication failed|failed to authenticate", line, re.I):
            counts["auth_fail"] += 1
            m = ip_re.search(line)
            if m:
                per_peer[m.group(1)]["auth_fail"] += 1

report = {
    "generated_at": datetime.utcnow().isoformat() + "Z",
    "counts": counts,
    "per_peer": {k: dict(v) for k,v in per_peer.items()},
    "sample_errors": errors[-200:]
}

with open(args.out, "w") as out:
    json.dump(report, out, indent=2, ensure_ascii=False)

# opcional: CSV resumo
with open(args.out + ".csv", "w", newline='') as csvf:
    w = csv.writer(csvf)
    w.writerow(["metric","value"])
    for k,v in counts.items():
        w.writerow([k,v])

print("Relatório salvo em", args.out)
