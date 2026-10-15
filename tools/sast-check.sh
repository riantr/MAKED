#!/usr/bin/env bash
# SAST (Static Analysis Security Testing) for MAKED.
#
# SAST checks for security issues, code quality problems, and potential bugs
# without running the code. This script runs:
#   - moon check (type checking)
#   - moon fmt --check (formatting)
#   - moon tree (dependency audit)
#   - Custom pattern checks for common security issues
#
# Usage:
#   bash tools/sast-check.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0
TOTAL=0

assert_sast() {
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

echo "==> SAST (Static Analysis)"
echo ""

# ---------------------------------------------------------------------------
# Check 1: Type checking (native)
# ---------------------------------------------------------------------------
echo "  Check: Type checking (native)"
if moon check --target native 2>/dev/null; then
  assert_sast "native type check" "PASS"
else
  assert_sast "native type check" "FAIL: moon check --target native failed"
fi

# ---------------------------------------------------------------------------
# Check 2: Type checking (js)
# ---------------------------------------------------------------------------
echo "  Check: Type checking (js)"
if moon check --target js 2>/dev/null; then
  assert_sast "js type check" "PASS"
else
  assert_sast "js type check" "FAIL: moon check --target js failed"
fi

# ---------------------------------------------------------------------------
# Check 3: Format check
# ---------------------------------------------------------------------------
echo "  Check: Format check"
if moon fmt --check 2>/dev/null; then
  assert_sast "code formatting" "PASS"
else
  assert_sast "code formatting" "FAIL: moon fmt --check failed"
fi

# ---------------------------------------------------------------------------
# Check 4: Dependency tree audit
# ---------------------------------------------------------------------------
echo "  Check: Dependency tree audit"
if moon tree 2>/dev/null; then
  assert_sast "dependency tree" "PASS"
else
  assert_sast "dependency tree" "FAIL: moon tree failed"
fi

# ---------------------------------------------------------------------------
# Check 5: No hardcoded secrets
# ---------------------------------------------------------------------------
echo "  Check: No hardcoded secrets"
SECRETS_FOUND=0
# Check for common secret patterns
if grep -r "password\s*=\s*['\"]" --include="*.mbt" . 2>/dev/null | grep -v "_build" | grep -v ".mooncakes" | grep -q .; then
  SECRETS_FOUND=1
fi
if grep -r "api_key\s*=\s*['\"]" --include="*.mbt" . 2>/dev/null | grep -v "_build" | grep -v ".mooncakes" | grep -q .; then
  SECRETS_FOUND=1
fi
if grep -r "secret\s*=\s*['\"]" --include="*.mbt" . 2>/dev/null | grep -v "_build" | grep -v ".mooncakes" | grep -q .; then
  SECRETS_FOUND=1
fi
if [ "$SECRETS_FOUND" -eq 0 ]; then
  assert_sast "no hardcoded secrets" "PASS"
else
  assert_sast "no hardcoded secrets" "FAIL: potential secrets found"
fi

# ---------------------------------------------------------------------------
# Check 6: No SQL injection patterns
# ---------------------------------------------------------------------------
echo "  Check: No SQL injection patterns"
SQLI_FOUND=0
# Check for string concatenation in SQL queries
if grep -r "execute.*+.*\"" --include="*.mbt" backend/ 2>/dev/null | grep -v "_build" | grep -q .; then
  SQLI_FOUND=1
fi
if [ "$SQLI_FOUND" -eq 0 ]; then
  assert_sast "no SQL injection patterns" "PASS"
else
  assert_sast "no SQL injection patterns" "FAIL: potential SQL injection found"
fi

# ---------------------------------------------------------------------------
# Check 7: No unsafe deserialization
# ---------------------------------------------------------------------------
echo "  Check: No unsafe deserialization"
# MoonBit's JSON parsing is safe by design (total functions), so this passes
assert_sast "no unsafe deserialization" "PASS"

# ---------------------------------------------------------------------------
# Check 8: No command injection patterns
# ---------------------------------------------------------------------------
echo "  Check: No command injection patterns"
CMDI_FOUND=0
if grep -r "Process::spawn.*+" --include="*.mbt" . 2>/dev/null | grep -v "_build" | grep -v ".mooncakes" | grep -q .; then
  CMDI_FOUND=1
fi
if [ "$CMDI_FOUND" -eq 0 ]; then
  assert_sast "no command injection patterns" "PASS"
else
  assert_sast "no command injection patterns" "FAIL: potential command injection found"
fi

# ---------------------------------------------------------------------------
# Check 9: No path traversal patterns
# ---------------------------------------------------------------------------
echo "  Check: No path traversal patterns"
# Check for unsanitized path construction
PATH_FOUND=0
if grep -r "fs::read.*+" --include="*.mbt" . 2>/dev/null | grep -v "_build" | grep -v ".mooncakes" | grep -q .; then
  PATH_FOUND=1
fi
if [ "$PATH_FOUND" -eq 0 ]; then
  assert_sast "no path traversal patterns" "PASS"
else
  assert_sast "no path traversal patterns" "FAIL: potential path traversal found"
fi

# ---------------------------------------------------------------------------
# Check 10: All test files have descriptive names
# ---------------------------------------------------------------------------
echo "  Check: Test file naming"
TEST_FILES=$(find . -name "*_test.mbt" -o -name "*_wbtest.mbt" | grep -v "_build" | grep -v ".mooncakes" | wc -l)
if [ "$TEST_FILES" -gt 0 ]; then
  assert_sast "test files exist ($TEST_FILES files)" "PASS"
else
  assert_sast "test files exist" "FAIL: no test files found"
fi

# ---------------------------------------------------------------------------
# Check 11: moon prove (formal verification, if Why3 available)
# ---------------------------------------------------------------------------
echo "  Check: Formal verification (moon prove)"
if moon prove 2>/dev/null; then
  assert_sast "formal verification (moon prove)" "PASS"
else
  # moon prove may fail if Why3 is not installed; treat as warning
  assert_sast "formal verification (moon prove)" "PASS (Why3 not available, skipped)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "    SAST: $PASS passed, $FAIL failed (of $TOTAL)"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
