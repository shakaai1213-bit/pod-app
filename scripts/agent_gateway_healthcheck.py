#!/usr/bin/env python3
"""
agent_gateway_healthcheck.py — Verify all 9 AgentInfo.team gateways respond.

Pod M1 verification step per pod-M1-chat-1to1.md DDS.
Reads tokens from Sources/Presentation/Features/DirectChat/AgentSecrets.swift
(gitignored) so we never duplicate them — single source of truth.

Sends a tiny test message to each agent's gateway via the OpenAI-compatible
/v1/chat/completions endpoint, reports pass/fail/latency/response excerpt.

Usage:
    python3 scripts/agent_gateway_healthcheck.py
    python3 scripts/agent_gateway_healthcheck.py --agent maui   # just one
    python3 scripts/agent_gateway_healthcheck.py --timeout 10   # tighter bound

Exit codes:
    0 — all 9 responded
    1 — one or more failed
    2 — setup error (AgentSecrets.swift missing, etc.)

Owner: Maui 🪝 | Pod M1 verification | 2026-05-07
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

POD_APP_ROOT = Path(__file__).resolve().parent.parent
SECRETS_FILE = POD_APP_ROOT / "Sources/Presentation/Features/DirectChat/AgentSecrets.swift"
MODELS_FILE = POD_APP_ROOT / "Sources/Presentation/Features/DirectChat/AgentChatModels.swift"

# These match the constants in AgentChatModels.swift — keep in sync if URLs change.
SHAKA_MAC_GATEWAY = "https://shakas-mac-mini.tail82d30d.ts.net"
CHIEF_MAC_GATEWAY = "https://chiefs-mac-mini.tail82d30d.ts.net"

# Maps agent_id → which token (shaka_mac vs chief_mac).
# Mirrors AgentInfo.team in AgentChatModels.swift.
AGENTS = [
    ("aurora",  SHAKA_MAC_GATEWAY, "shaka_mac"),
    ("maui",    SHAKA_MAC_GATEWAY, "shaka_mac"),
    ("aloha",   SHAKA_MAC_GATEWAY, "shaka_mac"),
    ("luna",    CHIEF_MAC_GATEWAY, "chief_mac"),
    ("chief",   CHIEF_MAC_GATEWAY, "chief_mac"),
    ("coral",   SHAKA_MAC_GATEWAY, "shaka_mac"),
    ("rooster", CHIEF_MAC_GATEWAY, "chief_mac"),
    ("reef",    CHIEF_MAC_GATEWAY, "chief_mac"),
    ("shaka",   SHAKA_MAC_GATEWAY, "shaka_mac"),
]

TEST_PROMPT = "Reply with exactly one word: pong"


def load_tokens() -> dict[str, str]:
    """Parse AgentSecrets.swift for the two static let token strings."""
    if not SECRETS_FILE.exists():
        print(f"❌ AgentSecrets.swift missing at {SECRETS_FILE}", file=sys.stderr)
        print("   Copy AgentSecrets.swift.template → AgentSecrets.swift and fill values.", file=sys.stderr)
        sys.exit(2)
    src = SECRETS_FILE.read_text()
    tokens = {}
    for label, var in [("shaka_mac", "shakaMacGatewayToken"), ("chief_mac", "chiefMacGatewayToken")]:
        m = re.search(rf'static let {var}\s*=\s*"([^"]+)"', src)
        if not m:
            print(f"❌ Could not parse {var} from AgentSecrets.swift", file=sys.stderr)
            sys.exit(2)
        if m.group(1).startswith("REPLACE_ME"):
            print(f"❌ {var} still has REPLACE_ME placeholder — fill it in", file=sys.stderr)
            sys.exit(2)
        tokens[label] = m.group(1)
    return tokens


def check_agent(agent_id: str, base_url: str, token: str, timeout: float) -> dict:
    """POST a tiny test message; return result dict with pass/fail + latency + excerpt."""
    payload = json.dumps({
        "model": f"openclaw/{agent_id}",
        "messages": [
            {"role": "system", "content": f"You are {agent_id} — gateway healthcheck. Reply briefly."},
            {"role": "user", "content": TEST_PROMPT},
        ],
        "max_tokens": 30,
        "temperature": 0.0,
        "stream": False,
    }).encode()

    url = f"{base_url}/v1/chat/completions"
    req = urllib.request.Request(url, data=payload, headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {token}",
    })

    start = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = json.loads(resp.read())
        latency_ms = int((time.monotonic() - start) * 1000)
        # OpenAI-compat response shape
        try:
            content = body["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError):
            return {"agent": agent_id, "ok": False, "latency_ms": latency_ms,
                    "error": f"malformed response: {json.dumps(body)[:120]}"}
        excerpt = content.strip().replace("\n", " ")[:80]
        return {"agent": agent_id, "ok": True, "latency_ms": latency_ms,
                "http": resp.status, "excerpt": excerpt}
    except urllib.error.HTTPError as e:
        latency_ms = int((time.monotonic() - start) * 1000)
        return {"agent": agent_id, "ok": False, "latency_ms": latency_ms,
                "error": f"HTTP {e.code} {e.reason}"}
    except urllib.error.URLError as e:
        latency_ms = int((time.monotonic() - start) * 1000)
        return {"agent": agent_id, "ok": False, "latency_ms": latency_ms,
                "error": f"URL error: {e.reason}"}
    except Exception as e:
        latency_ms = int((time.monotonic() - start) * 1000)
        return {"agent": agent_id, "ok": False, "latency_ms": latency_ms,
                "error": f"{type(e).__name__}: {e}"}


def main() -> int:
    ap = argparse.ArgumentParser(description="Pod M1 — verify all 9 agent gateways respond")
    ap.add_argument("--agent", help="Just check one agent (id, e.g. 'maui')")
    ap.add_argument("--timeout", type=float, default=30.0, help="Per-agent HTTP timeout in seconds")
    ap.add_argument("--json", action="store_true", help="Emit machine-readable JSON only")
    args = ap.parse_args()

    tokens = load_tokens()
    targets = AGENTS if not args.agent else [a for a in AGENTS if a[0] == args.agent]
    if not targets:
        print(f"❌ unknown agent: {args.agent} (valid: {', '.join(a[0] for a in AGENTS)})", file=sys.stderr)
        return 2

    if not args.json:
        print(f"Pod M1 gateway healthcheck — {len(targets)} agent(s)")
        print(f"Test prompt: {TEST_PROMPT!r}")
        print(f"Timeout: {args.timeout}s\n")
        print(f"{'agent':<10} {'tier':<10} {'status':<8} {'latency':<10} {'detail'}")
        print("-" * 100)

    results = []
    pass_n = 0
    for agent_id, base_url, token_label in targets:
        r = check_agent(agent_id, base_url, tokens[token_label], args.timeout)
        results.append(r)
        if r["ok"]:
            pass_n += 1
            if not args.json:
                print(f"{agent_id:<10} {token_label:<10} {'✅ PASS':<8} "
                      f"{r['latency_ms']:>6}ms   '{r.get('excerpt','')}'")
        else:
            if not args.json:
                print(f"{agent_id:<10} {token_label:<10} {'❌ FAIL':<8} "
                      f"{r['latency_ms']:>6}ms   {r.get('error','?')}")

    if args.json:
        print(json.dumps({"results": results, "pass": pass_n, "total": len(results)}, indent=2))
    else:
        print("-" * 100)
        verdict = "✅ ALL GREEN" if pass_n == len(results) else f"❌ {len(results) - pass_n}/{len(results)} FAILED"
        print(f"\n{verdict} — {pass_n}/{len(results)} agents responded")

    return 0 if pass_n == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
