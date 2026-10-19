#!/usr/bin/env bash
# Mutation testing for MAKED.
#
# Mutation testing verifies that the test suite can detect bugs by introducing
# small changes (mutations) to the source code and checking if tests fail.
# A mutation that doesn't cause a test failure is "survived" -- meaning the
# test suite has a gap.
#
# This script performs simple mutations on backend source files and checks
# if the test suite catches them.
#
# Usage:
#   bash tools/mutation-test.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0
KILLED=0
SURVIVED=0
TOTAL=0

# backend/loop.mbt used to key slot_from_designation on a hand-written copy of
# pyroduct's designation table. It no longer copies it: the parser reads the
# designations back out of pyroduct, so the only thing left to break is the
# lookup itself. The mutation below makes the parser compare against the gloss
# instead of the designation, which is the shape of the bug it used to have --
# the table was consulted, but not the right column of it. The anchor keeps
# sed away from the `|` alternation metacharacter in the match arms.

mutate_and_test() {
  local desc="$1"
  local file="$2"
  local pattern="$3"
  local replacement="$4"

  TOTAL=$((TOTAL + 1))

  # Create backup
  cp "$file" "${file}.bak"

  # Apply mutation
  sed -i.bak2 "s/$pattern/$replacement/g" "$file" 2>/dev/null || {
    # If sed fails, try a different approach
    cp "${file}.bak" "$file"
    echo "  SKIP  $desc (mutation not applicable)"
    rm -f "${file}.bak" "${file}.bak2"
    return 0
  }

  # Run tests
  if moon test --target native backend 2>/dev/null; then
    # Tests passed -- mutation survived (BAD)
    SURVIVED=$((SURVIVED + 1))
    FAIL=$((FAIL + 1))
    echo "  SURVIVED  $desc (tests did not catch mutation)"
  else
    # Tests failed -- mutation killed (GOOD)
    KILLED=$((KILLED + 1))
    PASS=$((PASS + 1))
    echo "  KILLED  $desc (tests caught mutation)"
  fi

  # Restore original
  cp "${file}.bak" "$file"
  rm -f "${file}.bak" "${file}.bak2"
}

echo "==> Mutation Tests"
echo ""

# ---------------------------------------------------------------------------
# Mutation 1: Change ring order
# ---------------------------------------------------------------------------
echo "  Mutation: Ring order"
mutate_and_test \
  "ring order M->D changed to M->E" \
  "backend/loop.mbt" \
  "Model => Data" \
  "Model => Experience"

# ---------------------------------------------------------------------------
# Mutation 2: Change slot mapping
# ---------------------------------------------------------------------------
echo "  Mutation: Slot mapping"
mutate_and_test \
  "Model slot_to_next changed from CoBeing to Feedback" \
  "backend/loop.mbt" \
  "Model => @sm.CoBeing" \
  "Model => @sm.Feedback"

# ---------------------------------------------------------------------------
# Mutation 3: Change position mapping
# ---------------------------------------------------------------------------
echo "  Mutation: Position mapping"
mutate_and_test \
  "Model position changed from Standing to Encounter" \
  "backend/loop.mbt" \
  "Model => @sm.Standing" \
  "Model => @sm.Encounter"

# ---------------------------------------------------------------------------
# Mutation 4: Change slot designation parsing
# ---------------------------------------------------------------------------
echo "  Mutation: Slot designation parsing"
mutate_and_test \
  "slot_from_designation consults the gloss instead of the designation" \
  "backend/loop.mbt" \
  "slot.en_designation().to_lower() == needle" \
  "slot.en_gloss().to_lower() == needle"

# ---------------------------------------------------------------------------
# Mutation 5: Change paper_to_trigger priority
# ---------------------------------------------------------------------------
echo "  Mutation: Paper trigger mapping"
mutate_and_test \
  "paper_to_trigger SOTA changed to return Sting" \
  "backend/research.mbt" \
  "return @sm.AbsorbGlory" \
  "return @sm.Sting"

# ---------------------------------------------------------------------------
# Mutation 6: Change causal threshold
# ---------------------------------------------------------------------------
echo "  Mutation: Causal threshold"
mutate_and_test \
  "estimate_causal_effect threshold changed from 10 to 5" \
  "backend/causal.mbt" \
  "if n < 10" \
  "if n < 5"

# ---------------------------------------------------------------------------
# Mutation 7: Change page slug
# ---------------------------------------------------------------------------
echo "  Mutation: Page slug"
mutate_and_test \
  "home_page slug changed from 'index' to 'home'" \
  "backend/pages.mbt" \
  'slug: "index"' \
  'slug: "home"'

# ---------------------------------------------------------------------------
# Mutation 8: Change response status
# ---------------------------------------------------------------------------
echo "  Mutation: Response status"
mutate_and_test \
  "Response::text default status changed from 200 to 201" \
  "backend/response.mbt" \
  "status: 200" \
  "status: 201"

# ---------------------------------------------------------------------------
# Mutation 9: Change domain letter
# ---------------------------------------------------------------------------
echo "  Mutation: Domain letter"
mutate_and_test \
  "Model letter changed from 'M' to 'X'" \
  "backend/loop.mbt" \
  'Model => "M"' \
  'Model => "X"'

# ---------------------------------------------------------------------------
# Mutation 10: Change group state logic
# ---------------------------------------------------------------------------
echo "  Mutation: Group state logic"
mutate_and_test \
  "compute_group_state threshold changed from 2 to 1" \
  "backend/loop.mbt" \
  "if moved_count <= 2" \
  "if moved_count <= 1"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "    Mutation Tests: $KILLED killed, $SURVIVED survived (of $TOTAL)"
echo "    Mutation Score: $(( KILLED * 100 / (TOTAL > 0 ? TOTAL : 1) ))%"
if [ "$SURVIVED" -gt 0 ]; then
  echo ""
  echo "    WARNING: $SURVIVED mutations survived. Consider adding tests."
fi
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
