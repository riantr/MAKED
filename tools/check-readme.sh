#!/usr/bin/env bash
# Check the numbers in README.md against the tree.
#
#   bash tools/check-readme.sh
#
# The bash twin of tools/check-readme.ps1, and it exists for the same
# reason the other bash twins exist: the CI runner is ubuntu and carries
# bash, so a gate written only in PowerShell is a gate that does not run
# where the build runs.
#
# The two are kept in step deliberately. Both implement one invariant:
# **the number the document states IS the number the tree has**. The
# expected value is read from the document under audit, the actual value
# is derived from the tree, and the two are compared. A number in the
# document that the tree does not agree with is a lie in a document people
# use to judge the project.
#
# It reads only. It never writes to the source tree.
#
# Exit codes:
#   0  every number in the document matches the tree
#   1  a number in the document does not match the tree

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

README="README.md"
if [ ! -f "$README" ]; then
  echo "README.md is missing -- there is nothing to check."
  exit 1
fi

FAILURES=0

fail() {
  echo "  $1"
  echo "*** FAIL ***"
  FAILURES=$((FAILURES + 1))
}

# --- how the tree is counted ------------------------------------------------

# A MoonBit test is a `test "name" {` block or an `async test "name" {`
# one. Both shapes exist in this tree, and a counter that reads only the
# first one undercounts by the number of async tests -- which is how the
# stale 389 was produced in the first place.
count_test_blocks() {
  local dir="$1"
  local count=0
  local f
  for f in "$dir"/*.mbt; do
    [ -e "$f" ] || continue
    count=$((count + $(grep -cE '^[ \t]*(async[ \t]+)?test[ \t]+"[^"]*"[ \t]*\{' "$f" || true)))
  done
  echo "$count"
}

# A mutation is one `@{ name = ...; file = ...; old = ...; new = ... }`
# block in a mutation suite. The `name =` line identifies one, and there is
# exactly one per block.
count_mutations() {
  grep -cE '^[ \t]*name[ \t]*=' "$1" || true
}

# An anchor is one `old =` line. Every mutation has exactly one, so the
# anchors in a suite and the mutations in it are the same number.
count_anchors() {
  grep -cE '^[ \t]*old[ \t]*=' "$1" || true
}

# The CI gates are the `gate "name"` calls in ci.sh's default case. The
# other two cases (--quick, --unit-only) run fewer, so the default arm is
# the one counted: the README says "CI gates", and the full run is the
# full run.
count_ci_gates() {
  awk '
    /^[ \t]*\*\)[ \t]*$/ { in_default = 1; next }
    in_default && /^[ \t]*esac[ \t]*$/ { exit }
    in_default && /^[ \t]*gate[ \t]+"/ { n++ }
    END { print n + 0 }
  ' ci.sh
}

# --- what the document says ------------------------------------------------

# The count table in "Development Status" and the comment on the file in
# "Project Structure". Two places, one number, and both are checked.
#
# The pattern carries the number in a capture group, and it is extracted
# with sed rather than by grepping the digits out of the matched text.
# Grepping the digits out is wrong: a matched fragment like
# "mutate-backend.ps1 # 143 mutations" carries the 1 of "ps1" as well, and
# a gate that reads 1 and 143 is a gate that cannot be trusted.
doc_number() {
  sed -nE "s/.*${1}.*/\\1/p" "$README" | head -1
}

BACKEND_TESTS=$(count_test_blocks backend)
FRONTEND_TESTS=$(count_test_blocks frontend)
BACKEND_MUTATIONS=$(count_mutations tools/mutate-backend.ps1)
FRONTEND_MUTATIONS=$(count_mutations tools/mutate-frontend.ps1)
LOOP_MUTATIONS=$(count_mutations tools/mutate-loop.ps1)
ALL_ANCHORS=$(($(count_anchors tools/mutate-backend.ps1) \
              + $(count_anchors tools/mutate-frontend.ps1) \
              + $(count_anchors tools/mutate-loop.ps1)))
CI_GATES=$(count_ci_gates)

check() {
  local label="$1" actual="$2" table="$3" tree="$4"
  if [ -z "$actual" ] || [ "$actual" -lt 0 ]; then
    fail "$(printf '%-20s could not be derived from the tree' "$label")"
    return
  fi
  if [ -z "$table" ]; then
    fail "$(printf '%-20s the count table has no row for it' "$label")"
    return
  fi
  if [ -z "$tree" ]; then
    fail "$(printf '%-20s the project structure has no count for it' "$label")"
    return
  fi
  if [ "$table" != "$actual" ] || [ "$tree" != "$actual" ]; then
    fail "$(printf '%-20s the tree has %s, the table says %s, the structure says %s' \
      "$label" "$actual" "$table" "$tree")"
    return
  fi
  printf '  ok      %-20s %s\n' "$label" "$actual"
}

check "Backend tests" "$BACKEND_TESTS" \
  "$(doc_number '\|[[:space:]]*Backend tests[[:space:]]*\|[[:space:]]*([0-9]+)[[:space:]]*\|')" \
  "$(doc_number '\*_test\.mbt[[:space:]]+#[[:space:]]*([0-9]+)[[:space:]]*tests')"

check "Frontend tests" "$FRONTEND_TESTS" \
  "$(doc_number '\|[[:space:]]*Frontend tests[[:space:]]*\|[[:space:]]*([0-9]+)[[:space:]]*\|')" \
  "$(doc_number 'frontend_test\.mbt[[:space:]]+#[[:space:]]*([0-9]+)[[:space:]]*tests')"

check "Backend mutations" "$BACKEND_MUTATIONS" \
  "$(doc_number '\|[[:space:]]*Backend mutations[[:space:]]*\|[[:space:]]*([0-9]+)[[:space:]]*\|')" \
  "$(doc_number 'mutate-backend\.ps1[[:space:]]+#[[:space:]]*([0-9]+)[[:space:]]*mutations')"

check "Frontend mutations" "$FRONTEND_MUTATIONS" \
  "$(doc_number '\|[[:space:]]*Frontend mutations[[:space:]]*\|[[:space:]]*([0-9]+)[[:space:]]*\|')" \
  "$(doc_number 'mutate-frontend\.ps1[[:space:]]+#[[:space:]]*([0-9]+)[[:space:]]*mutations')"

check "Loop mutations" "$LOOP_MUTATIONS" \
  "$(doc_number '\|[[:space:]]*Loop mutations[[:space:]]*\|[[:space:]]*([0-9]+)[[:space:]]*\|')" \
  "$(doc_number 'mutate-loop\.ps1[[:space:]]+#[[:space:]]*([0-9]+)[[:space:]]*mutations')"

check "Mutation anchors" "$ALL_ANCHORS" \
  "$(doc_number '\|[[:space:]]*Mutation anchors[[:space:]]*\|[[:space:]]*([0-9]+)[[:space:]]*\|')" \
  "$(doc_number 'check-mutation-anchors\.ps1[[:space:]]+#[[:space:]]*([0-9]+)[[:space:]]*anchors')"

check "CI gates" "$CI_GATES" \
  "$(doc_number '\|[[:space:]]*CI gates[[:space:]]*\|[[:space:]]*([0-9]+)[[:space:]]*\|')" \
  "$(doc_number 'ci\.sh[[:space:]]+#[[:space:]]*([0-9]+)[[:space:]]*gates')"

# The integration-check count is checked by the integration suite itself,
# because only a run knows how many checks it made -- some of its
# assertions sit in loops, so the number cannot be derived from the
# script's text. What is checked here is that the two places the document
# states it agree with each other.
INTEGRATION_TABLE=$(doc_number '\|[[:space:]]*Integration checks[[:space:]]*\|[[:space:]]*([0-9]+)[[:space:]]*\|')
INTEGRATION_TREE=$(doc_number 'integration-test\.ps1[[:space:]]+#[[:space:]]*([0-9]+)[[:space:]]*checks')
if [ -z "$INTEGRATION_TABLE" ] || [ -z "$INTEGRATION_TREE" ]; then
  fail "$(printf '%-20s the document does not state it in both places' 'Integration checks')"
elif [ "$INTEGRATION_TABLE" != "$INTEGRATION_TREE" ]; then
  fail "$(printf '%-20s the table says %s and the structure says %s' \
    'Integration checks' "$INTEGRATION_TABLE" "$INTEGRATION_TREE")"
else
  printf '  ok      %-20s %s (the suite checks it at the end of a run)\n' \
    'Integration checks' "$INTEGRATION_TABLE"
fi

echo ""
if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES number(s) in README.md do not match the tree."
  echo "*** FAIL ***"
  echo ""
  echo "The document states a number and the tree has another. Fix the document,"
  echo "or fix the tree -- but make the two agree before saying anything about"
  echo "either of them."
  exit 1
fi
echo "Every number in README.md matches the tree."
exit 0
