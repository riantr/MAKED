#!/usr/bin/env bash
# Contract tests for the MAKED API.
#
# Contract tests validate that API responses match their expected schemas.
# Unlike integration tests (which check status codes and basic field presence),
# contract tests verify the *shape* and *types* of every field in every response.
#
# This catches breaking changes to the API contract that would silently break
# the frontend (e.g., a field changing from string to number, or a required
# field being removed).
#
# Usage:
#   bash tools/contract-test.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PORT=${MAKED_PORT:-$(( 49200 + RANDOM % 1000 ))}
DB="_build/test-contract-$$.db"
SERVER_PID=""
PASS=0
FAIL=0
TOTAL=0

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -f "$DB"
}
trap cleanup EXIT

assert_contract() {
  local desc="$1" json="$2" check="$3"
  TOTAL=$((TOTAL + 1))
  local result
  result=$(echo "$json" | python -c "
import sys, json
try:
    d = json.load(sys.stdin)
    $check
    print('PASS')
except Exception as e:
    print(f'FAIL: {e}')
" 2>&1) || result="FAIL: python error"

  if [[ "$result" == "PASS" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS  $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL  $desc -- $result"
  fi
}

echo "==> Contract Tests"
echo "    Port: $PORT"
echo ""

# Build and start server
echo "    Building server..."
moon build --release --target native cmd/server 2>/dev/null
moon build --release --target js cmd/web 2>/dev/null
mkdir -p frontend/dist
cp _build/js/release/build/cmd/web/web.js frontend/dist/main.js 2>/dev/null || true

echo "    Starting server on port $PORT..."
MAKED_PORT="$PORT" MAKED_DB="$DB" moon run --release --target native cmd/server &
SERVER_PID=$!
sleep 2

if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  echo "    ERROR: Server failed to start"
  exit 1
fi

echo "    Server started (PID $SERVER_PID)"
echo ""

# ---------------------------------------------------------------------------
# Contract: GET /api/status
# ---------------------------------------------------------------------------
echo "  Contract: GET /api/status"
RESP=$(curl -s "http://localhost:$PORT/api/status")
assert_contract "status has string 'status'" "$RESP" \
  "assert isinstance(d['status'], str)"
assert_contract "status has string 'database'" "$RESP" \
  "assert isinstance(d['database'], str)"
assert_contract "status has int 'page_count'" "$RESP" \
  "assert isinstance(d['page_count'], int)"
assert_contract "status has array 'domains'" "$RESP" \
  "assert isinstance(d['domains'], list)"
assert_contract "status domains have 5 entries" "$RESP" \
  "assert len(d['domains']) == 5"
assert_contract "status domain has string 'slug'" "$RESP" \
  "assert isinstance(d['domains'][0]['slug'], str)"
assert_contract "status domain has string 'title'" "$RESP" \
  "assert isinstance(d['domains'][0]['title'], str)"
assert_contract "status domain has string 'letter'" "$RESP" \
  "assert isinstance(d['domains'][0]['letter'], str)"
assert_contract "status domain has string 'role'" "$RESP" \
  "assert isinstance(d['domains'][0]['role'], str)"

# ---------------------------------------------------------------------------
# Contract: GET /api/pages
# ---------------------------------------------------------------------------
echo "  Contract: GET /api/pages"
RESP=$(curl -s "http://localhost:$PORT/api/pages")
assert_contract "pages has array 'pages'" "$RESP" \
  "assert isinstance(d['pages'], list)"
assert_contract "pages has at least 8 entries" "$RESP" \
  "assert len(d['pages']) >= 8"
assert_contract "page has string 'slug'" "$RESP" \
  "assert isinstance(d['pages'][0]['slug'], str)"
assert_contract "page has string 'title'" "$RESP" \
  "assert isinstance(d['pages'][0]['title'], str)"
assert_contract "page has string 'letter'" "$RESP" \
  "assert isinstance(d['pages'][0]['letter'], str)"
assert_contract "page has string 'role'" "$RESP" \
  "assert isinstance(d['pages'][0]['role'], str)"
assert_contract "page has string 'summary'" "$RESP" \
  "assert isinstance(d['pages'][0]['summary'], str)"
assert_contract "page has string 'body'" "$RESP" \
  "assert isinstance(d['pages'][0]['body'], str)"
assert_contract "page has bool 'in_navigation'" "$RESP" \
  "assert isinstance(d['pages'][0]['in_navigation'], bool)"
assert_contract "page has int 'sort'" "$RESP" \
  "assert isinstance(d['pages'][0]['sort'], int)"

# ---------------------------------------------------------------------------
# Contract: GET /api/domains
# ---------------------------------------------------------------------------
echo "  Contract: GET /api/domains"
RESP=$(curl -s "http://localhost:$PORT/api/domains")
assert_contract "domains has array 'domains'" "$RESP" \
  "assert isinstance(d['domains'], list)"
assert_contract "domains has 5 entries" "$RESP" \
  "assert len(d['domains']) == 5"

# ---------------------------------------------------------------------------
# Contract: GET /api/loop/status
# ---------------------------------------------------------------------------
echo "  Contract: GET /api/loop/status"
RESP=$(curl -s "http://localhost:$PORT/api/loop/status")
assert_contract "loop status has string 'current_domain'" "$RESP" \
  "assert isinstance(d['current_domain'], str)"
assert_contract "loop status has string 'current_title'" "$RESP" \
  "assert isinstance(d['current_title'], str)"
assert_contract "loop status has string 'current_position'" "$RESP" \
  "assert isinstance(d['current_position'], str)"
assert_contract "loop status has string 'current_position_label'" "$RESP" \
  "assert isinstance(d['current_position_label'], str)"
assert_contract "loop status has string 'current_gloss'" "$RESP" \
  "assert isinstance(d['current_gloss'], str)"
assert_contract "loop status has string 'next_domain'" "$RESP" \
  "assert isinstance(d['next_domain'], str)"
assert_contract "loop status has string 'drive_slot'" "$RESP" \
  "assert isinstance(d['drive_slot'], str)"
assert_contract "loop status has int 'history_length'" "$RESP" \
  "assert isinstance(d['history_length'], int)"
assert_contract "loop status has array 'history'" "$RESP" \
  "assert isinstance(d['history'], list)"
assert_contract "loop status has array 'domain_states'" "$RESP" \
  "assert isinstance(d['domain_states'], list)"
assert_contract "loop status domain_states has 5 entries" "$RESP" \
  "assert len(d['domain_states']) == 5"
assert_contract "loop status has string 'group_state'" "$RESP" \
  "assert isinstance(d['group_state'], str)"
assert_contract "loop status has string 'group_state_gloss'" "$RESP" \
  "assert isinstance(d['group_state_gloss'], str)"

# ---------------------------------------------------------------------------
# Contract: GET /api/loop/slots
# ---------------------------------------------------------------------------
echo "  Contract: GET /api/loop/slots"
RESP=$(curl -s "http://localhost:$PORT/api/loop/slots")
assert_contract "slots has array 'slots'" "$RESP" \
  "assert isinstance(d['slots'], list)"
assert_contract "slots has 8 entries" "$RESP" \
  "assert len(d['slots']) == 8"
assert_contract "slot has string 'name'" "$RESP" \
  "assert isinstance(d['slots'][0]['name'], str)"
assert_contract "slot has string 'designation'" "$RESP" \
  "assert isinstance(d['slots'][0]['designation'], str)"
assert_contract "slot has string 'gloss'" "$RESP" \
  "assert isinstance(d['slots'][0]['gloss'], str)"
# `source` is deliberately absent: pyroduct's Slot::source() is the Chinese
# source quote, kept so a name can be traced back to the original text. There
# is no English form of it, so the English API does not pretend to carry one.
assert_contract "slot has no 'source' field" "$RESP" \
  "assert 'source' not in d['slots'][0]"

# ---------------------------------------------------------------------------
# Contract: POST /api/loop/step
# ---------------------------------------------------------------------------
echo "  Contract: POST /api/loop/step"
RESP=$(curl -s -X POST "http://localhost:$PORT/api/loop/step")
assert_contract "step response has string 'current_domain'" "$RESP" \
  "assert isinstance(d['current_domain'], str)"
assert_contract "step response has int 'history_length'" "$RESP" \
  "assert isinstance(d['history_length'], int)"
assert_contract "step response history_length >= 1" "$RESP" \
  "assert d['history_length'] >= 1"

# ---------------------------------------------------------------------------
# Contract: POST /api/loop/reset
# ---------------------------------------------------------------------------
echo "  Contract: POST /api/loop/reset"
RESP=$(curl -s -X POST "http://localhost:$PORT/api/loop/reset")
assert_contract "reset response has string 'current_domain'" "$RESP" \
  "assert isinstance(d['current_domain'], str)"
assert_contract "reset response current_domain is M" "$RESP" \
  "assert d['current_domain'] == 'M'"
assert_contract "reset response history_length is 0" "$RESP" \
  "assert d['history_length'] == 0"

# ---------------------------------------------------------------------------
# Contract: POST /api/loop/reset/:domain
# ---------------------------------------------------------------------------
echo "  Contract: POST /api/loop/reset/:domain"
RESP=$(curl -s -X POST "http://localhost:$PORT/api/loop/reset/D")
assert_contract "reset to D has current_domain D" "$RESP" \
  "assert d['current_domain'] == 'D'"
assert_contract "reset to D has history_length 0" "$RESP" \
  "assert d['history_length'] == 0"

RESP=$(curl -s -X POST "http://localhost:$PORT/api/loop/reset/attack")
assert_contract "reset to attack (english) has current_domain A" "$RESP" \
  "assert d['current_domain'] == 'A'"

RESP=$(curl -s -X POST "http://localhost:$PORT/api/loop/reset/invalid")
assert_contract "reset to invalid domain returns error" "$RESP" \
  "assert 'error' in d"

# ---------------------------------------------------------------------------
# Contract: GET /api/loop/mode
# ---------------------------------------------------------------------------
echo "  Contract: GET /api/loop/mode"
RESP=$(curl -s "http://localhost:$PORT/api/loop/mode")
assert_contract "mode response has string 'mode'" "$RESP" \
  "assert isinstance(d['mode'], str)"
assert_contract "mode response mode is structured or free" "$RESP" \
  "assert d['mode'] in ['structured', 'free']"
assert_contract "mode response has string 'designation'" "$RESP" \
  "assert isinstance(d['designation'], str)"
assert_contract "mode response has string 'gloss'" "$RESP" \
  "assert isinstance(d['gloss'], str)"

# ---------------------------------------------------------------------------
# Contract: POST /api/loop/mode/:mode
# ---------------------------------------------------------------------------
echo "  Contract: POST /api/loop/mode/:mode"
RESP=$(curl -s -X POST "http://localhost:$PORT/api/loop/mode/free")
assert_contract "set mode to free succeeds" "$RESP" \
  "assert d['mode'] == 'free'"
assert_contract "set mode response has mode_designation" "$RESP" \
  "assert isinstance(d['mode_designation'], str)"
assert_contract "set mode response has mode_gloss" "$RESP" \
  "assert isinstance(d['mode_gloss'], str)"

RESP=$(curl -s -X POST "http://localhost:$PORT/api/loop/mode/structured")
assert_contract "set mode to structured succeeds" "$RESP" \
  "assert d['mode'] == 'structured'"

RESP=$(curl -s -X POST "http://localhost:$PORT/api/loop/mode/invalid")
assert_contract "set invalid mode returns error" "$RESP" \
  "assert 'error' in d"

# ---------------------------------------------------------------------------
# Contract: mode fields in loop status
# ---------------------------------------------------------------------------
echo "  Contract: mode fields in loop status"
RESP=$(curl -s "http://localhost:$PORT/api/loop/status")
assert_contract "status has mode field" "$RESP" \
  "assert isinstance(d['mode'], str)"
assert_contract "status has mode_designation field" "$RESP" \
  "assert isinstance(d['mode_designation'], str)"
assert_contract "status has mode_gloss field" "$RESP" \
  "assert isinstance(d['mode_gloss'], str)"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "    Contract Tests: $PASS passed, $FAIL failed (of $TOTAL)"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
