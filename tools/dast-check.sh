#!/usr/bin/env bash
# DAST (Dynamic Analysis Security Testing) for MAKED.
#
# Static DAST checks that don't require a running server, plus live tests
# against a real server.
#
# Usage:
#   bash tools/dast-check.sh
#   MAKED_PORT=8080 bash tools/dast-check.sh   # use a server that is already running
#
# The live tests used to be optional in a way that meant they never ran: the
# gate only looked at a server when MAKED_PORT named one, and nothing in the
# project ever set it, so every run -- on this machine and in CI alike --
# reported "SKIP Live tests" and the live path was covered by nothing at
# all. A check that never runs is not a check, so the gate now starts its own
# server when it has not been given one, the way the contract gate does, and
# stops it again afterwards. A server that is already answering on the given
# port is used as it is and left alone.

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

# ---------------------------------------------------------------------------
# The server the live checks talk to
# ---------------------------------------------------------------------------
PORT="${MAKED_PORT:-}"
SERVER_PID=""
DB=""

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  if [ -n "$DB" ]; then
    rm -f "$DB"
  fi
}
trap cleanup EXIT

# Whether something answers on the port.
server_answers() {
  curl -s --max-time 2 "http://localhost:$1/api/status" > /dev/null 2>&1
}

# How many pages the server says it holds.
#
# The count is compared before and after the injection attempt rather than
# against a number written here: what matters is that the table is still
# there, not how many rows it holds today. A gate that hard-codes the count
# fails the day the site grows a page, and a gate that stops failing is a
# gate nobody reads.
count_pages() {
  local n
  n=$(curl -s --max-time 5 "http://localhost:$1/api/pages" 2>/dev/null \
    | grep -o '"slug"' | wc -l | tr -d ' ') || n=0
  echo "$n"
}

# The HTTP status of a request, or 000 when the request never landed.
status_of() {
  local method="$1"
  local url="$2"
  curl -s -o /dev/null -w "%{http_code}" --max-time 5 -X "$method" "$url" \
    2>/dev/null || echo "000"
}

# The HTTP status of a request that carries a body.
status_of_with_body() {
  local method="$1"
  local url="$2"
  local body="$3"
  curl -s -o /dev/null -w "%{http_code}" --max-time 5 -X "$method" \
    -H "Content-Type: application/json" --data "$body" "$url" 2>/dev/null \
    || echo "000"
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
# Live DAST checks
# ---------------------------------------------------------------------------
#
# These are the checks that only a running server can answer: whether a
# request that should be refused is refused, and whether the data is still
# there afterwards.
if [ -z "$PORT" ] || ! server_answers "$PORT"; then
  if [ -z "$PORT" ]; then
    PORT=$(( 49200 + RANDOM % 1000 ))
  fi
  echo ""
  echo "  Starting a server for the live checks (port $PORT)..."
  DB="_build/test-dast-$$.db"
  if moon build --release --target native cmd/server > /dev/null 2>&1; then
    MAKED_PORT="$PORT" MAKED_DB="$DB" moon run --release --target native cmd/server &
    SERVER_PID=$!
    # The server needs a moment to bind the port; thirty tries is a minute,
    # which is longer than any start-up here takes and shorter than a build.
    for _ in $(seq 1 30); do
      if server_answers "$PORT"; then
        break
      fi
      sleep 1
    done
  else
    echo "    the server did not build, so the live checks cannot run"
  fi
fi

echo ""
echo "  Live DAST checks (port $PORT)"

if server_answers "$PORT"; then
  assert_dast "server is responding" "PASS"

  STATUS=$(status_of GET "http://localhost:$PORT/api/nonexistent")
  if [ "$STATUS" = "404" ]; then
    assert_dast "API 404 returns proper status" "PASS"
  else
    assert_dast "API 404 returns proper status" "FAIL: got $STATUS"
  fi

  # The slug goes into a prepared statement as a bound parameter, so the
  # injection cannot reach the parser. The request has to be refused, and the
  # pages have to still be there afterwards: a refusal that dropped the table
  # on its way out would pass the first check and destroy the site.
  BEFORE=$(count_pages "$PORT")
  STATUS=$(status_of GET \
    "http://localhost:$PORT/api/pages/%27%3B%20DROP%20TABLE%20pages%3B%20--")
  AFTER=$(count_pages "$PORT")
  if [ "$STATUS" = "404" ] || [ "$STATUS" = "400" ]; then
    assert_dast "SQL injection attempt rejected" "PASS"
  else
    assert_dast "SQL injection attempt rejected" "FAIL: got $STATUS"
  fi
  if [ "$BEFORE" != "0" ] && [ "$BEFORE" = "$AFTER" ]; then
    assert_dast "the pages survived the injection attempt" "PASS"
  else
    assert_dast "the pages survived the injection attempt" \
      "FAIL: $BEFORE pages before, $AFTER after"
  fi

  # A path in a slug must not reach the filesystem. The page is addressed by
  # slug, so the answer is "no such page" -- and never the file.
  STATUS=$(status_of GET "http://localhost:$PORT/api/pages/..%2F..%2Fetc%2Fpasswd")
  if [ "$STATUS" = "404" ] || [ "$STATUS" = "400" ]; then
    assert_dast "path traversal in a slug rejected" "PASS"
  else
    assert_dast "path traversal in a slug rejected" "FAIL: got $STATUS"
  fi

  # A body that is not JSON is refused with a reason rather than taken as an
  # empty one and written down.
  STATUS=$(status_of_with_body POST "http://localhost:$PORT/api/entries" \
    "not json at all")
  if [ "$STATUS" = "400" ]; then
    assert_dast "a malformed body is refused" "PASS"
  else
    assert_dast "a malformed body is refused" "FAIL: got $STATUS"
  fi

  # An id that is not a number names no row, so the answer must be a refusal
  # and not a "deleted".
  STATUS=$(status_of DELETE "http://localhost:$PORT/api/entries/not-a-number")
  if [ "$STATUS" = "400" ]; then
    assert_dast "a delete with a bad id is refused" "PASS"
  else
    assert_dast "a delete with a bad id is refused" "FAIL: got $STATUS"
  fi
else
  assert_dast "server is responding" "FAIL: no server on port $PORT"
  assert_dast "the live checks could run" "FAIL: there was no server to ask"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "    DAST: $PASS passed, $FAIL failed (of $TOTAL)"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
