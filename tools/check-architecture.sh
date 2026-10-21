#!/usr/bin/env bash
# Check the architecture documents against the tree.
#
#   bash tools/check-architecture.sh
#
# The README has a gate for its numbers (tools/check-readme.sh). The
# architecture documents make the same kind of claim -- a count, a shape, a
# file and line to look at -- and they rotted the same way: four API
# endpoints when there are thirty-seven, eight columns when there are
# twelve, "no Dockerfile" when there is one, and a hundred file:line
# references pointing at lines that had long since moved.
#
# So the invariant is the same one, applied to the other documents:
#
#   **the number the document states IS the number the tree has**
#
# It is an invariant rather than a snapshot, so it keeps holding as the tree
# changes. A document that says 37 routes and a tree that has 37 routes is
# not a coincidence that has to be re-established; a document that says 37
# routes and a tree that has 38 is a red gate.
#
# Two kinds of claim are checked, and they are checked differently.
#
# The COUNTS are derived from the tree and compared with what the documents
# say. The route count comes from counting the route registrations; the
# column count from counting the columns of the `pages` table; the field
# count from counting the fields of the `Page` struct; the page count from
# counting what is seeded.
#
# The REFERENCES are checked for existence and for range. A reference to a
# file that is not there is a broken pointer. A reference to a line past the
# end of the file is a broken pointer too. A reference to a line that is
# still IN RANGE but no longer says what the claim says it says is the
# dangerous one -- it looks verified -- and no script can catch that; it is
# why the documents carry the claim in words next to the pointer.
#
# It reads only. It never writes to the source tree.
#
# Exit codes:
#   0  every claim in the documents matches the tree
#   1  a claim in the documents does not match the tree

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DOCS="architecture"

FAILURES=0

fail() {
  echo "  $1"
  echo "*** FAIL ***"
  FAILURES=$((FAILURES + 1))
}

ok() {
  printf '  ok      %-22s %s\n' "$1" "$2"
}

# --- how the tree is counted ------------------------------------------------

# A route is one registration: app.get(...), app.post(...), and the rest.
# The count is the number of registrations, not the number of distinct
# paths, because a path registered for two verbs is two registrations and
# the handler behind them is two handlers.
count_routes() {
  grep -cE 'app\.(get|post|put|delete|patch)\(' backend/api.mbt || true
}

# The columns of the `pages` table. The CREATE TABLE statement is a block of
# #| lines -- MoonBit's string literal for the SQL -- and every line that
# names a column says TEXT or INTEGER. Counting those lines counts the
# columns.
count_page_columns() {
  awk '
    /CREATE TABLE IF NOT EXISTS pages/ { inside = 1; next }
    inside && /^\s*#\|/ {
      if ($0 ~ /TEXT|INTEGER/) n++
      next
    }
    inside { exit }
    END { print n + 0 }
  ' backend/database.mbt
}

# The fields of the `Page` struct. It is the only `struct Page` in the file
# and it ends at the first closing brace at the start of a line.
count_page_fields() {
  awk '
    /^pub\(all\) struct Page \{/ { inside = 1; next }
    inside && /^\}/ { exit }
    inside && /^[ \t]+[a-z_]+[ \t]*:/ { n++ }
    END { print n + 0 }
  ' backend/pages.mbt
}

# The pages the server serves. Three places produce one:
#
#   - the ring domains, one tuple each
#   - the list of the other three seeded pages, one tuple each
#   - the index page and the not-found page, one constructor each
#
# The three counts are added because the three shapes are three lists, and a
# counter that read only one of them would be wrong by the other two.
count_seed_pages() {
  local ring list singles
  ring=$(grep -cE '^ *\("[a-z]+", "[A-Z]' backend/pages.mbt || true)
  # The list of the other pages: a tuple that starts with a bare slug in
  # quotes on its own line. The capitalised title on the next line is not a
  # slug, so the pattern asks for a lower-case word.
  list=$(grep -cE '^ *"([a-z]+)",$' backend/pages.mbt || true)
  # The two constructors that make a page on their own.
  singles=$(grep -cE '^ *slug: "' backend/pages.mbt || true)
  echo $((ring + list + singles))
}

# --- what the documents say -------------------------------------------------

# A number the documents state.
#
# The pattern matches the whole FRAGMENT the number sits in, and the number
# is then the only run of digits in that fragment. Two things follow from
# that, and both are why it is written this way.
#
# The fragment is matched with grep -oE rather than sed's s///. A greedy
# leading `.*` eats INTO the number: "37 API routes" leaves "7" for the
# capture group, because the engine tries the longest `.*` first and "7" is
# the longest prefix that still leaves a digit before " API routes". A gate
# that reads 7 where the document says 37 is a gate that cannot be trusted.
#
# The context around the number carries no digits of its own. That is what
# makes "the only run of digits in the fragment" the right answer, and it is
# why a pattern like "mutate-backend.ps1 # 143 mutations" is not safe here:
# the "1" of "ps1" would be a digit run of its own.
doc_number() {
  grep -oE "$1" "$2" | head -1 | grep -oE '[0-9]+' | head -1
}

check_count() {
  local label="$1" actual="$2" expected="$3"
  if [ -z "$actual" ] || [ "$actual" -lt 0 ]; then
    fail "$(printf '%-22s could not be derived from the tree' "$label")"
    return
  fi
  if [ -z "$expected" ]; then
    fail "$(printf '%-22s no document states it' "$label")"
    return
  fi
  if [ "$expected" != "$actual" ]; then
    fail "$(printf '%-22s the tree has %s, the document says %s' \
      "$label" "$actual" "$expected")"
    return
  fi
  ok "$label" "$actual"
}

EVIDENCE="architecture/system-model.evidence.md"
DEPS="architecture/dependencies.evidence.md"
DEPS_MD="architecture/dependencies.md"
SUMMARY="architecture/system-model.summary.md"
DEPLOY="architecture/deployment.evidence.md"

# --- the counts -------------------------------------------------------------

check_count "API routes" \
  "$(count_routes)" \
  "$(doc_number '[0-9]+ API routes' "$EVIDENCE")"

check_count "pages columns" \
  "$(count_page_columns)" \
  "$(doc_number 'pages` table with [0-9]+ columns' "$EVIDENCE")"

check_count "Page fields" \
  "$(count_page_fields)" \
  "$(doc_number 'Page struct with [0-9]+ fields' "$EVIDENCE")"

check_count "seed pages" \
  "$(count_seed_pages)" \
  "$(doc_number '[|] [0-9]+ seed pages' "$EVIDENCE")"

check_count "frontend tests" \
  "$(grep -cE '^[ \t]*(async[ \t]+)?test[ \t]+"[^"]*"[ \t]*\{' frontend/frontend_test.mbt || true)" \
  "$(doc_number 'frontend/frontend_test\.mbt` [|] [0-9]+ tests' "$EVIDENCE")"

check_count "backend tests" \
  "$(grep -cE '^[ \t]*(async[ \t]+)?test[ \t]+"[^"]*"[ \t]*\{' backend/database_test.mbt || true)" \
  "$(doc_number 'backend/database_test\.mbt` [|] [0-9]+ tests' "$EVIDENCE")"

# The summary states the two suites together.
check_count "tests (summary)" \
  "$(cat backend/*.mbt frontend/*.mbt | grep -cE '^[ \t]*(async[ \t]+)?test[ \t]+"[^"]*"[ \t]*\{' || true)" \
  "$(doc_number '[0-9]+ tests across backend and frontend' "$SUMMARY")"

# --- the dependency versions ------------------------------------------------
#
# The version each dependency is pinned to is stated in three documents, and
# it is stated in moon.mod. All four have to agree: a document that names a
# version the manifest does not pin is a document that sends a reader to a
# version that is not the one this project uses.
#
# The version is read out of moon.mod's import block, and the documents are
# asked whether they state the same one.

check_dependency_versions() {
  local module="$1" version="$2" label="$3"
  local bad=0
  local doc
  for doc in "$DEPS" "$DEPS_MD" "$EVIDENCE"; do
    if ! grep -qF "$module@$version" "$doc" 2>/dev/null \
       && ! grep -qE "\| $module \| $version \|" "$doc" 2>/dev/null; then
      fail "$(printf '%-22s %s does not state %s' "$label" "$doc" "$version")"
      bad=1
    fi
  done
  if [ "$bad" -eq 0 ]; then
    ok "$label" "$module@$version"
  fi
}

while read -r module version; do
  [ -n "$module" ] || continue
  check_dependency_versions "$module" "$version" "dep ${module##*/}"
done < <(sed -nE 's/^ *"([^"]+)@([^"]+)".*/\1 \2/p' moon.mod)

# --- the references ---------------------------------------------------------
#
# Every `file.ext:line` or `file.ext:line-line` in the architecture
# documents has to point at a file that exists and a line that is in it. A
# pointer to a line past the end of the file is a pointer to nothing.
#
# This catches the mechanical half of the rot. It cannot catch a reference
# that is in range but has drifted -- that is why the documents say what the
# claim IS next to the pointer, and why a reader who finds one wrong can put
# it back.

check_references() {
  local doc="$1"
  local text
  text=$(cat "$doc")
  local refs
  refs=$(printf '%s\n' "$text" | grep -oE '`[A-Za-z0-9_./-]+\.(mbt|moon\.pkg|ps1|sh|mod|dsl|dot|md):[0-9]+(-[0-9]+)?`' | tr -d '`' | sort -u)
  local bad=0
  local ref file line last
  for ref in $refs; do
    file="${ref%%:*}"
    line="${ref##*:}"
    last="${line##*-}"
    if [ ! -f "$file" ]; then
      fail "$(printf '%-22s %s names a file that is not there' "$doc" "$file")"
      bad=1
      continue
    fi
    local count
    count=$(wc -l < "$file")
    if [ "$last" -gt "$count" ]; then
      fail "$(printf '%-22s %s points past the end of the file (%s lines)' \
        "$doc" "$ref" "$count")"
      bad=1
    fi
  done
  if [ "$bad" -eq 0 ]; then
    ok "references $(basename "$doc")" "$(printf '%s\n' "$refs" | grep -c . )"
  fi
}

for doc in "$EVIDENCE" "$DEPS" "$DEPLOY" "architecture/flows.evidence.md"; do
  check_references "$doc"
done

# --- the facts that are not counts -----------------------------------------
#
# The deployment document used to claim there was no Dockerfile, no compose
# file and no CI. Those are not numbers; they are the presence or absence of
# a file, and they are checked the same way -- by looking.

check_exists() {
  local label="$1" path="$2"
  if [ -e "$path" ]; then
    ok "$label" "$path"
  else
    fail "$(printf '%-22s %s is not there' "$label" "$path")"
  fi
}

check_exists "Dockerfile" "Dockerfile"
check_exists "compose file" "docker-compose.yml"
check_exists "CI workflow" ".github/workflows/ci.yml"
check_exists "publish workflow" ".github/workflows/publish.yml"

echo ""
if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES claim(s) in the architecture documents do not match the tree."
  echo "*** FAIL ***"
  echo ""
  echo "The documents state a claim and the tree has another. Fix the documents,"
  echo "or fix the tree -- but make the two agree before saying anything about"
  echo "either of them."
  exit 1
fi
echo "Every claim in the architecture documents matches the tree."
exit 0
