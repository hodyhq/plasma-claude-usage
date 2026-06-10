#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Hody
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Aggregates today's Claude Code token usage per model from the local
# JSONL transcripts in ~/.claude/projects/. Prints one JSON object:
#   {"date": "YYYY-MM-DD", "models": {"<model-id>": {"input": n, "output": n,
#    "cacheRead": n, "cacheWrite": n}}}
#
# Only files modified since local midnight are scanned, entries are
# deduplicated on (message.id, requestId) the same way ccusage does.

import glob
import json
import os
from datetime import datetime

base = os.path.join(
    os.path.expanduser(os.environ.get("CLAUDE_CONFIG_DIR", "~/.claude")),
    "projects",
)

midnight = datetime.now().astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
cutoff = midnight.timestamp()

models = {}
seen = set()

for path in glob.glob(os.path.join(base, "*", "*.jsonl")):
    try:
        if os.path.getmtime(path) < cutoff:
            continue
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                if '"usage"' not in line:
                    continue
                try:
                    rec = json.loads(line)
                except (ValueError, TypeError):
                    continue
                msg = rec.get("message") or {}
                usage = msg.get("usage") or {}
                model = msg.get("model") or ""
                if not usage or not model or model == "<synthetic>":
                    continue
                ts = rec.get("timestamp") or ""
                try:
                    t = datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
                except ValueError:
                    continue
                if t < cutoff:
                    continue
                key = (msg.get("id"), rec.get("requestId"))
                if key[0] and key in seen:
                    continue
                seen.add(key)
                agg = models.setdefault(
                    model, {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
                )
                agg["input"] += usage.get("input_tokens") or 0
                agg["output"] += usage.get("output_tokens") or 0
                agg["cacheRead"] += usage.get("cache_read_input_tokens") or 0
                agg["cacheWrite"] += usage.get("cache_creation_input_tokens") or 0
    except OSError:
        continue

print(json.dumps({"date": midnight.strftime("%Y-%m-%d"), "models": models}))
