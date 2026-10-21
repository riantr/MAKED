#!/usr/bin/env bash
# Integration tests for the MAKED API.
#
# Starts the server on a random port, exercises every API endpoint, and
# validates the response shape and status codes. Exits 0 only when every
# assertion passes -- this script is the integration safety net that unit
# tests cannot provide (the full HTTP round-trip through moonback's router).
#
# Usage:
#   bash tools/integration-test.sh          # build + test
#   MAKED_SKIP_BUILD=1 bash tools/integration-test.sh  # test only (server already built)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PORT=${MAKED_PORT:-$(( 49100 + RANDOM % 1000 ))}
DB="_build/test-integration-$$.db"
SERVER_PID=""
PASS=0
FAIL=0
TOTAL=0

# The interpreter, whichever name this machine gives it.
#
# `python` is not on the PATH of a current ubuntu runner -- `python3` is --
# and a gate that dies on a missing interpreter says nothing about the thing
# it was meant to check.
PYTHON="$(command -v python3 || command -v python || true)"
if [ -z "$PYTHON" ]; then
  echo "  ERROR  no python on this machine, so the integration checks cannot run"
  exit 1
fi

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -f "$DB"
}
trap cleanup EXIT

assert_status() {
  local desc="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
    echo "  PASS  $desc (HTTP $actual)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL  $desc (expected HTTP $expected, got HTTP $actual)"
  fi
}

assert_json_field() {
  local desc="$1" json="$2" pyexpr="$3" expected="$4"
  TOTAL=$((TOTAL + 1))
  local actual
  actual=$(echo "$json" | "$PYTHON" -c "import sys,json; d=json.load(sys.stdin); print($pyexpr)" 2>/dev/null) || actual="__ERROR__"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
    echo "  PASS  $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL  $desc (expected '$expected', got '$actual')"
  fi
}

assert_json_array_length() {
  local desc="$1" json="$2" field="$3" expected="$4"
  TOTAL=$((TOTAL + 1))
  local actual
  actual=$(echo "$json" | "$PYTHON" -c "import sys,json; d=json.load(sys.stdin); print(len($field))" 2>/dev/null) || actual="-1"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
    echo "  PASS  $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL  $desc (expected length $expected, got $actual)"
  fi
}

assert_json_has_field() {
  local desc="$1" json="$2" field="$3"
  TOTAL=$((TOTAL + 1))
  local has
  has=$(echo "$json" | "$PYTHON" -c "import sys,json; d=json.load(sys.stdin); print('yes' if '$field' in d else 'no')" 2>/dev/null) || has="no"
  if [ "$has" = "yes" ]; then
    PASS=$((PASS + 1))
    echo "  PASS  $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL  $desc (field '$field' not found)"
  fi
}

assert_json_field_not_empty() {
  local desc="$1" json="$2" field="$3"
  TOTAL=$((TOTAL + 1))
  local actual
  actual=$(echo "$json" | "$PYTHON" -c "import sys,json; d=json.load(sys.stdin); v=d.get('$field',''); print('nonempty' if v else 'empty')" 2>/dev/null) || actual="error"
  if [ "$actual" = "nonempty" ]; then
    PASS=$((PASS + 1))
    echo "  PASS  $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL  $desc (field '$field' is empty or missing)"
  fi
}

# ── Build ──────────────────────────────────────────────────────────────
if [ -z "${MAKED_SKIP_BUILD:-}" ]; then
  echo "==> building server"
  moon build --target native cmd/server 2>/dev/null
fi

# ── Start server ───────────────────────────────────────────────────────
echo "==> starting server on port $PORT"
MAKED_PORT="$PORT" MAKED_DB="$DB" moon run --target native cmd/server 2>/dev/null &
SERVER_PID=$!

# Wait for server to be ready (up to 10 seconds).
for i in $(seq 1 20); do
  if curl -sf "http://127.0.0.1:$PORT/api/status" >/dev/null 2>&1; then
    break
  fi
  if [ "$i" = "20" ]; then
    echo "FAIL: server did not start within 10 seconds"
    exit 1
  fi
  sleep 0.5
done

echo "==> running integration tests"
echo ""

# ── GET /api/status ────────────────────────────────────────────────────
echo "── GET /api/status"
RESP=$(curl -sf -w "\n%{http_code}" "http://127.0.0.1:$PORT/api/status")
BODY=$(echo "$RESP" | sed '$d')
CODE=$(echo "$RESP" | tail -1)
assert_status "GET /api/status returns 200" "200" "$CODE"
assert_json_field "status is 'ok'" "$BODY" "d['status']" "ok"
assert_json_has_field "has page_count" "$BODY" "page_count"
assert_json_has_field "has domains" "$BODY" "domains"
# ── GET /api/pages ─────────────────────────────────────────────────────
echo ""
echo "── GET /api/pages"
RESP=$(curl -sf -w "\n%{http_code}" "http://127.0.0.1:$PORT/api/pages")
BODY=$(echo "$RESP" | sed '$d')
CODE=$(echo "$RESP" | tail -1)
assert_status "GET /api/pages returns 200" "200" "$CODE"
# Pages include 5 domains + utility pages; the exact count depends on seed data.
assert_json_field "pages array has at least 5 entries" "$BODY" "len(d['pages']) >= 5" "True"

# ── GET /api/pages/:slug ───────────────────────────────────────────────
echo ""
echo "── GET /api/pages/:slug"
RESP=$(curl -sf -w "\n%{http_code}" "http://127.0.0.1:$PORT/api/pages/model")
BODY=$(echo "$RESP" | sed '$d')
CODE=$(echo "$RESP" | tail -1)
assert_status "GET /api/pages/model returns 200" "200" "$CODE"
assert_json_field "page slug is 'model'" "$BODY" "d['slug']" "model"
assert_json_field "page letter is 'M'" "$BODY" "d['letter']" "M"

# Known-missing slug returns 404.
HTTP_CODE=$(curl -s -o /tmp/maked_404.json -w "%{http_code}" "http://127.0.0.1:$PORT/api/pages/nonexistent")
BODY=$(cat /tmp/maked_404.json 2>/dev/null)
assert_status "GET /api/pages/nonexistent returns 404" "404" "$HTTP_CODE"
assert_json_field "error is 'not_found'" "$BODY" "d.get('error','')" "not_found"

# ── GET /api/domains ───────────────────────────────────────────────────
echo ""
echo "── GET /api/domains"
RESP=$(curl -sf -w "\n%{http_code}" "http://127.0.0.1:$PORT/api/domains")
BODY=$(echo "$RESP" | sed '$d')
CODE=$(echo "$RESP" | tail -1)
assert_status "GET /api/domains returns 200" "200" "$CODE"
assert_json_array_length "domains array has 5 entries" "$BODY" "d['domains']" "5"

# ── GET /api/loop/status ───────────────────────────────────────────────
echo ""
echo "── GET /api/loop/status"
RESP=$(curl -sf -w "\n%{http_code}" "http://127.0.0.1:$PORT/api/loop/status")
BODY=$(echo "$RESP" | sed '$d')
CODE=$(echo "$RESP" | tail -1)
assert_status "GET /api/loop/status returns 200" "200" "$CODE"
assert_json_field "current_domain is 'M'" "$BODY" "d['current_domain']" "M"
assert_json_field "next_domain is 'D'" "$BODY" "d['next_domain']" "D"
assert_json_field_not_empty "drive_slot is non-empty" "$BODY" "drive_slot"
assert_json_has_field "has current_position" "$BODY" "current_position"
assert_json_has_field "has current_gloss" "$BODY" "current_gloss"
assert_json_has_field "has history" "$BODY" "history"

# ── GET /api/loop/slots ────────────────────────────────────────────────
echo ""
echo "── GET /api/loop/slots"
RESP=$(curl -sf -w "\n%{http_code}" "http://127.0.0.1:$PORT/api/loop/slots")
BODY=$(echo "$RESP" | sed '$d')
CODE=$(echo "$RESP" | tail -1)
assert_status "GET /api/loop/slots returns 200" "200" "$CODE"
assert_json_array_length "slots array has 8 entries" "$BODY" "d['slots']" "8"

# Each slot has the expected fields.
assert_json_field "first slot name is 'occasion'" "$BODY" "d['slots'][0]['name']" "occasion"
assert_json_field "first slot has non-empty designation" "$BODY" "bool(d['slots'][0].get('designation',''))" "True"
assert_json_field "last slot name is 'unveil'" "$BODY" "d['slots'][7]['name']" "unveil"

# ── POST /api/loop/step (default drive) ────────────────────────────────
echo ""
echo "── POST /api/loop/step"
RESP=$(curl -sf -w "\n%{http_code}" -X POST "http://127.0.0.1:$PORT/api/loop/step")
BODY=$(echo "$RESP" | sed '$d')
CODE=$(echo "$RESP" | tail -1)
assert_status "POST /api/loop/step returns 200" "200" "$CODE"
assert_json_field "history_length is 1 after step" "$BODY" "d['history_length']" "1"
assert_json_field "first history entry domain is 'M'" "$BODY" "d['history'][0]['domain']" "M"

# ── POST /api/loop/reset ──────────────────────────────────────────────
echo ""
echo "── POST /api/loop/reset"
RESP=$(curl -sf -w "\n%{http_code}" -X POST "http://127.0.0.1:$PORT/api/loop/reset")
BODY=$(echo "$RESP" | sed '$d')
CODE=$(echo "$RESP" | tail -1)
assert_status "POST /api/loop/reset returns 200" "200" "$CODE"
assert_json_field "current_domain is 'M' after reset" "$BODY" "d['current_domain']" "M"
assert_json_field "history_length is 0 after reset" "$BODY" "d['history_length']" "0"

# ── POST /api/loop/step/:slot (English names) ─────────────────────────
echo ""
echo "── POST /api/loop/step/:slot (English)"

# Reset first to known state.
curl -sf -X POST "http://127.0.0.1:$PORT/api/loop/reset" >/dev/null

# Step with 'act' slot from Standing -- this should produce a move.
RESP=$(curl -sf -w "\n%{http_code}" -X POST "http://127.0.0.1:$PORT/api/loop/step/act")
BODY=$(echo "$RESP" | sed '$d')
CODE=$(echo "$RESP" | tail -1)
assert_status "POST /api/loop/step/act returns 200" "200" "$CODE"
assert_json_field "history has 1 entry" "$BODY" "d['history_length']" "1"
assert_json_field_not_empty "slot field is present in history" "$BODY" "history"

# Step with 'cobeing' slot.
RESP=$(curl -sf -w "\n%{http_code}" -X POST "http://127.0.0.1:$PORT/api/loop/step/cobeing")
BODY=$(echo "$RESP" | sed '$d')
CODE=$(echo "$RESP" | tail -1)
assert_status "POST /api/loop/step/cobeing returns 200" "200" "$CODE"
assert_json_field "history has 2 entries" "$BODY" "d['history_length']" "2"

# Unknown slot returns 400.
HTTP_CODE=$(curl -s -o /tmp/maked_400.json -w "%{http_code}" -X POST "http://127.0.0.1:$PORT/api/loop/step/bogus")
BODY=$(cat /tmp/maked_400.json 2>/dev/null)
assert_status "POST /api/loop/step/bogus returns 400" "400" "$HTTP_CODE"
assert_json_field "error is 'unknown_slot'" "$BODY" "d.get('error','')" "unknown_slot"

# ── Full ring traversal ────────────────────────────────────────────────
echo ""
echo "── Full ring traversal"
curl -sf -X POST "http://127.0.0.1:$PORT/api/loop/reset" >/dev/null

# Try all 8 slots from each position until we find one that moves.
SLOTS=("occasion" "orientation" "antecedent" "act" "feedback" "hold" "cobeing" "unveil")
DOMAINS_TRAVERSED=0

for attempt in $(seq 1 20); do
  STATUS=$(curl -sf "http://127.0.0.1:$PORT/api/loop/status")
  CURRENT=$(echo "$STATUS" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin)['current_domain'])" 2>/dev/null)
  HISTORY_LEN=$(echo "$STATUS" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin)['history_length'])" 2>/dev/null)

  if [ "$HISTORY_LEN" -ge 5 ]; then
    break
  fi

  # Try each slot to find one that moves.
  for slot in "${SLOTS[@]}"; do
    BEFORE=$(curl -sf "http://127.0.0.1:$PORT/api/loop/status")
    BEFORE_DOMAIN=$(echo "$BEFORE" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin)['current_domain'])" 2>/dev/null)
    BEFORE_LEN=$(echo "$BEFORE" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin)['history_length'])" 2>/dev/null)

    curl -sf -X POST "http://127.0.0.1:$PORT/api/loop/step/$slot" >/dev/null 2>&1 || true

    AFTER=$(curl -sf "http://127.0.0.1:$PORT/api/loop/status")
    AFTER_DOMAIN=$(echo "$AFTER" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin)['current_domain'])" 2>/dev/null)
    AFTER_LEN=$(echo "$AFTER" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin)['history_length'])" 2>/dev/null)

    # If domain changed or history grew with a non-Block outcome, we made progress.
    if [ "$AFTER_LEN" -gt "$BEFORE_LEN" ]; then
      OUTCOME=$(echo "$AFTER" | "$PYTHON" -c "import sys,json; h=json.load(sys.stdin)['history']; print(h[-1]['outcome'] if h else '')" 2>/dev/null)
      if [ "$OUTCOME" != $'\xe6\x97\xa0\xe8\xb7\xaf' ]; then
        DOMAINS_TRAVERSED=$((DOMAINS_TRAVERSED + 1))
        break
      fi
    fi
  done

  if [ "$HISTORY_LEN" -ge 5 ]; then
    break
  fi
done

FINAL=$(curl -sf "http://127.0.0.1:$PORT/api/loop/status")
FINAL_LEN=$(echo "$FINAL" | "$PYTHON" -c "import sys,json; print(json.load(sys.stdin)['history_length'])" 2>/dev/null)

TOTAL=$((TOTAL + 1))
if [ "$DOMAINS_TRAVERSED" -ge 1 ]; then
  PASS=$((PASS + 1))
  echo "  PASS  traversed $DOMAINS_TRAVERSED non-Block steps (history: $FINAL_LEN entries)"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL  no non-Block steps found in 20 attempts"
fi

# ── Summary ────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  Total: $TOTAL  Passed: $PASS  Failed: $FAIL"
echo "════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
echo ""
echo "All integration tests passed."
