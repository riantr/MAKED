#!/usr/bin/env bash
# DAST (Dynamic Analysis Security Testing) for MAKED.
#
# Static DAST checks that don't require a running server, plus optional live
# tests when MAKED_PORT is set and a server is already running.
#
# Usage:
#   bash tools/dast-check.sh
#   MAKED_PORT=8080 bash tools/dast-check.sh   # with live tests

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0
TOTAL=0

assert_dast() {
  local desc="$1"
  local result="$2"
  TOTAL=$((TOTAL + 1))
  if [ "$result" = "PASS" ]; then
    PASS=$((PASS + 1))
    echo "  PASS  $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL  $desc -- $result"
  fi
}

echo "==> DAST (Dynamic Analysis)"
echo ""

# ---------------------------------------------------------------------------
# Static DAST checks (no server required)
# ---------------------------------------------------------------------------
echo "  Static DAST checks"

# Check 1: Type check passes (lighter than full production build)
if moon check --target native 2>/dev/null; then
  assert_dast "type check passes" "PASS"
else
  assert_dast "type check passes" "FAIL"
fi

# Check 2: No dynamic code execution patterns (not legitimate exec/eval function names)
if grep -rn "dynamic_eval\|unsafe_exec\|code_eval" --include="*.mbt" backend/ cmd/ 2>/dev/null | grep -v "_build" | grep -v ".mooncakes" | grep -q .; then
  assert_dast "no dynamic code execution" "FAIL: dynamic eval/exec found"
else
  assert_dast "no dynamic code execution" "PASS"
fi

# Check 3: No hardcoded external IP addresses (localhost is OK)
if grep -rE "https?://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" --include="*.mbt" . 2>/dev/null | grep -v "_build" | grep -v ".mooncakes" | grep -v "127.0.0.1" | grep -v "0.0.0.0" | grep -q .; then
  assert_dast "no hardcoded external IPs" "FAIL: hardcoded IPs found"
else
  assert_dast "no hardcoded external IPs" "PASS"
fi

# Check 4: No internal filesystem paths in source
if grep -rE "C:\\\\|/home/|/Users/" --include="*.mbt" backend/ cmd/ 2>/dev/null | grep -v "_build" | grep -v ".mooncakes" | grep -q .; then
  assert_dast "no internal paths in errors" "FAIL: internal paths found"
else
  assert_dast "no internal paths in errors" "PASS"
fi

# Check 5: No unsafe file operations on user input
if grep -rn "fs::remove\|fs::rename" --include="*.mbt" backend/ 2>/dev/null | grep -v "_build" | grep -v ".mooncakes" | grep -q .; then
  assert_dast "no unsafe file operations" "FAIL: unsafe file ops found"
else
  assert_dast "no unsafe file operations" "PASS"
fi

# ---------------------------------------------------------------------------
# Optional live DAST checks (if server is running)
# ---------------------------------------------------------------------------
PORT="${MAKED_PORT:-}"
if [ -n "$PORT" ]; then
  echo ""
  echo "  Live DAST checks (port $PORT)"

  if curl -s --max-time 3 "http://localhost:$PORT/api/status" > /dev/null 2>&1; then
    assert_dast "server is responding" "PASS"

    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:$PORT/api/nonexistent")
    if [ "$STATUS" = "404" ]; then
      assert_dast "API 404 returns proper status" "PASS"
    else
      assert_dast "API 404 returns proper status" "FAIL: got $STATUS"
    fi

    STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
      "http://localhost:$PORT/api/pages/%27%3B%20DROP%20TABLE%20pages%3B%20--")
    if [ "$STATUS" = "404" ] || [ "$STATUS" = "400" ]; then
      assert_dast "SQL injection attempt rejected" "PASS"
    else
      assert_dast "SQL injection attempt rejected" "FAIL: got $STATUS"
    fi
  else
    echo "  SKIP  server not responding on port $PORT"
  fi
else
  echo ""
  echo "  SKIP  Live tests (set MAKED_PORT env var and start server to enable)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "    DAST: $PASS passed, $FAIL failed (of $TOTAL)"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
