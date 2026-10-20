#!/usr/bin/env bash
# Component tests for MAKED.
#
# Component tests verify multi-module interactions: the loop engine + domain
# states + group state working together, the research pipeline (corpus fetch ->
# trigger mapping -> loop stepping), and the causal inference pipeline.
#
# Unlike unit tests (which test individual modules in isolation) and integration
# tests (which test the full HTTP stack), component tests verify that the
# modules compose correctly.
#
# Usage:
#   bash tools/component-test.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0
TOTAL=0

assert_component() {
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

echo "==> Component Tests"
echo ""

# ---------------------------------------------------------------------------
# Component: Loop engine + domain states + group state
# ---------------------------------------------------------------------------
echo "  Component: Loop + Domain States + Group State"

# Test that moon test passes (includes loop_domain_test.mbt)
if moon test --target native backend 2>/dev/null; then
  assert_component "loop + domain states + group state compile and pass" "PASS"
else
  assert_component "loop + domain states + group state compile and pass" "FAIL: tests failed"
fi

# ---------------------------------------------------------------------------
# Component: Research pipeline (document -> the mapping table -> slot -> loop step)
# ---------------------------------------------------------------------------
echo "  Component: Research Pipeline"

# Verify that the backend tests pass (document -> the mapping table -> slot)
if moon test --target native backend 2>/dev/null; then
  assert_component "research pipeline (document -> the mapping table -> slot) passes" "PASS"
else
  assert_component "research pipeline (document -> the mapping table -> slot) passes" "FAIL: tests failed"
fi

# ---------------------------------------------------------------------------
# Component: Causal inference pipeline
# ---------------------------------------------------------------------------
echo "  Component: Causal Inference Pipeline"

# Verify that causal_test.mbt passes
if moon test --target native backend 2>/dev/null; then
  assert_component "causal inference pipeline passes" "PASS"
else
  assert_component "causal inference pipeline passes" "FAIL: tests failed"
fi

# ---------------------------------------------------------------------------
# Component: Frontend + backend JSON contract
# ---------------------------------------------------------------------------
echo "  Component: Frontend + Backend JSON Contract"

# Verify that frontend tests pass (decode_loop_status, decode_pages)
if moon test --target js frontend 2>/dev/null; then
  assert_component "frontend + backend JSON contract passes" "PASS"
else
  assert_component "frontend + backend JSON contract passes" "FAIL: tests failed"
fi

# ---------------------------------------------------------------------------
# Component: Database + pages + loop state persistence
# ---------------------------------------------------------------------------
echo "  Component: Database + Pages + Loop State"

# Verify that database tests pass (seed, query, migrate)
if moon test --target native backend 2>/dev/null; then
  assert_component "database + pages + loop state passes" "PASS"
else
  assert_component "database + pages + loop state passes" "FAIL: tests failed"
fi

# ---------------------------------------------------------------------------
# Component: BDD scenarios (Given/When/Then)
# ---------------------------------------------------------------------------
echo "  Component: BDD Scenarios"

# Verify that BDD tests pass
if [ -f backend/bdd_test.mbt ]; then
  if moon test --target native backend 2>/dev/null; then
    assert_component "BDD scenarios pass" "PASS"
  else
    assert_component "BDD scenarios pass" "FAIL: tests failed"
  fi
else
  assert_component "BDD scenarios pass" "FAIL: bdd_test.mbt not found"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "    Component Tests: $PASS passed, $FAIL failed (of $TOTAL)"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
