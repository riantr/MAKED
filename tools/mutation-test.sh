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
ERROR=0
TOTAL=0

# The machine used to be a set of five-variant enums in backend/loop.mbt, and
# the mutations below were anchored in that shape: "Model => Data",
# "Model => @sm.CoBeing", "Model => @sm.Standing". Those variants are gone --
# the domains are the model's now, written down in backend/model.mbt as data --
# so five of the ten anchors here matched nothing at all.
#
# Two traps this script already hit, both of which look like a weak test and
# are not:
#
#   - An anchor that does not occur in the file. `sed` succeeds when it
#     replaces nothing, so the suite stays green and the mutation is reported
#     as SURVIVED. That is the opposite of the truth: the mutation never
#     happened, and the guard was testing air. The anchor is checked first,
#     and a miss is an ERROR and a hard failure, not a survivor.
#   - A single-quoted pattern containing a backtick. The backtick is literal
#     there, so the anchor silently never matches. Quote anchors that contain
#     a backtick with double quotes instead.

mutate_and_test() {
  local desc="$1"
  local file="$2"
  local pattern="$3"
  local replacement="$4"

  TOTAL=$((TOTAL + 1))

  # The anchor has to be in the file. Without this check a dead anchor is
  # reported as a surviving mutation, and a gate that cries wolf is a gate
  # nobody reads.
  if ! grep -q -- "$pattern" "$file"; then
    ERROR=$((ERROR + 1))
    FAIL=$((FAIL + 1))
    echo "  ERROR    $desc (anchor not present in $file -- the mutation never applied)"
    return 0
  fi

  # Create backup
  cp "$file" "${file}.bak"

  # Apply mutation
  sed -i.bak2 "s/$pattern/$replacement/g" "$file"

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
# The ring is the model's own order, so this is where the order lives now.
# A ring that skipped a domain would leave one of the model's lenses unvisited
# and the reader would never be shown it.
echo "  Mutation: Ring order"
mutate_and_test \
  "the ring never leaves the first domain" \
  "backend/model.mbt" \
  'return self.domains\[i + 1\]' \
  'return self.domains[0]'

# ---------------------------------------------------------------------------
# Mutation 2: Change slot mapping
# ---------------------------------------------------------------------------
# The drive slot comes out of the table: a slot that moves, else a slot that
# holds, else nothing. Preferring the holding slot is the same mistake as
# picking a slot by meaning -- the position would stop moving.
echo "  Mutation: Slot mapping"
mutate_and_test \
  "the drive slot prefers a slot that holds over one that moves" \
  "backend/model.mbt" \
  'if moving.length() > 0 {' \
  'if false {'

# ---------------------------------------------------------------------------
# Mutation 3: Change position mapping
# ---------------------------------------------------------------------------
# A domain starts at its anchor, and the anchor is the model's. Ignoring it
# would leave every domain standing nowhere.
echo "  Mutation: Position mapping"
mutate_and_test \
  "a domain's anchor is ignored" \
  "backend/loop.mbt" \
  '  self.anchor' \
  '  ""'

# ---------------------------------------------------------------------------
# Mutation 4: Change slot designation parsing
# ---------------------------------------------------------------------------
# The parser must consult the model's designation column. It used to carry a
# hand-written copy of that table, and the copy went stale when pyroproduct
# renamed two of the eight -- the parser went on accepting the old words and
# rejecting the new ones, which is the whole bug. Reading the table out of the
# model is what makes that class of failure impossible, so the guard is that
# the lookup still goes through the designation.
echo "  Mutation: Slot designation parsing"
mutate_and_test \
  "slot_from_designation consults the gloss instead of the designation" \
  "backend/model.mbt" \
  'slot.designation.to_lower() == needle' \
  'slot.gloss.to_lower() == needle'

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
# The default status is 200, and a response that answered 201 to everything
# would still be a response -- the status code is what the client reads.
echo "  Mutation: Response status"
mutate_and_test \
  "Response::text default status changed from 200 to 201" \
  "backend/response.mbt" \
  "status~ : Int32 = 200" \
  "status~ : Int32 = 201"

# ---------------------------------------------------------------------------
# Mutation 9: Change domain letter
# ---------------------------------------------------------------------------
# The letters are not decoration: the ring is drawn with them and a domain is
# named by one in a URL.
echo "  Mutation: Domain letter"
mutate_and_test \
  "the model's first domain letter changed from 'M' to 'X'" \
  "backend/model.mbt" \
  'letter: "M",' \
  'letter: "X",'

# ---------------------------------------------------------------------------
# Mutation 10: Change group state logic
# ---------------------------------------------------------------------------
# The group layer counts the domains that have left their anchors. Moving the
# line between "converging" and "a common tongue" would make the group say
# something the run did not do.
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
echo "    Mutation Tests: $KILLED killed, $SURVIVED survived, $ERROR errors (of $TOTAL)"
echo "    Mutation Score: $(( KILLED * 100 / (TOTAL > 0 ? TOTAL : 1) ))%"
if [ "$SURVIVED" -gt 0 ]; then
  echo ""
  echo "    WARNING: $SURVIVED mutations survived. Consider adding tests."
fi
if [ "$ERROR" -gt 0 ]; then
  echo ""
  echo "    ERROR: $ERROR mutations never applied. Their anchors are stale --"
  echo "    a guard that cannot break is not a guard."
  # Exit 2, not 1: a surviving mutation is a gap in the tests and the caller
  # may treat it as advisory, but a dead anchor means the gate itself is
  # broken and nothing it reported can be believed.
  exit 2
fi
if [ "$SURVIVED" -gt 0 ]; then
  exit 1
fi
exit 0
