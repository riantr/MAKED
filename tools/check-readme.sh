#!/usr/bin/env bash
# Check the claims in README.md against the tree.
#
#   bash tools/check-readme.sh
#
# The bash twin of tools/check-readme.ps1, and it exists for the same
# reason the other bash twins exist: the CI runner is ubuntu and carries
# bash, so a gate written only in PowerShell is a gate that does not run
# where the build runs.
#
# The two are kept in step deliberately. Both implement one invariant:
# **what the document states IS what the tree has**. The expected value is
# read from the document under audit, the actual value is derived from the
# tree, and the two are compared. A number in the document that the tree
# does not agree with is a lie in a document people use to judge the project.
#
# There are four kinds of claim here now, and each is checked in the way
# that fits it:
#
# The NUMBERS -- the test, mutation, anchor and gate counts -- are read out
# of the document and compared with counts derived from the tree.
#
# The COUNTS IN WORDS -- "seven tools", "ten pages", "Six jobs" -- are read
# the same way, because a count written as a word is a count like any other,
# and a gate that only reads digits lets the words rot.
#
# The LISTING -- the project structure -- has to name every source file, and
# a name has to appear as many times as the tree has files with that name.
#
# The VARIABLES -- the environment variables the server reads, and the
# defaults they have -- are derived from the code and compared with the
# table the document states, because that table is the first thing a reader
# copies from.
#
# It reads only. It never writes to the source tree.
#
# It also starts no processes it does not need. Every one of them costs a
# tenth of a second on Windows and a millisecond on Linux, and a gate that
# takes a minute on the machine that writes the document is a gate that
# people stop running. So the tree is walked once, the counts are made in
# the shell, and the comparisons answer through variables.
#
# Exit codes:
#   0  every claim in the document matches the tree
#   1  a claim in the document does not match the tree

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
#
# The files are read in ONE pass. A grep per file is a fork per file, and
# the whole tree is twenty-six of them.
count_test_blocks() {
  local dir="$1"
  cat "$dir"/*.mbt 2>/dev/null \
    | grep -cE '^[ \t]*(async[ \t]+)?test[ \t]+"[^"]*"[ \t]*\{' \
    | head -1 || true
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

# A claim the document states in ONE place: the expected value from the tree,
# the stated value from the document, and the two compared.
check_claim() {
  local label="$1" expected="$2" stated="$3"
  if [ -z "$stated" ]; then
    fail "$(printf '%-20s the document does not state it' "$label")"
    return
  fi
  if [ "$stated" != "$expected" ]; then
    fail "$(printf '%-20s the tree has %s, the document says %s' \
      "$label" "$expected" "$stated")"
    return
  fi
  printf '  ok      %-20s %s\n' "$label" "$expected"
}

# The mutation accounting: how many mutations there are, and what became of
# them. The headline says that every one of them has to be accounted for --
# all but one killed by the tests, and the one that was not deliberately
# equivalent.
#
# The three suites' counts are derived above. The total is their sum, the
# expected-equivalent mutations are the ones the suites mark as such, and
# the killed ones are the rest. A mutation the harness does not kill and
# does not expect to survive is a survivor, and a survivor is a failure the
# suite reports -- so the two numbers have to add up to the total.
EQUIVALENT_MUTATIONS=$(grep -hcE '^[[:space:]]*equivalent = \$true[[:space:]]*$' \
  tools/mutate-backend.ps1 tools/mutate-frontend.ps1 tools/mutate-loop.ps1 \
  | awk '{ n += $1 } END { print n + 0 }')
TOTAL_MUTATIONS=$((BACKEND_MUTATIONS + FRONTEND_MUTATIONS + LOOP_MUTATIONS))
KILLED_MUTATIONS=$((TOTAL_MUTATIONS - EQUIVALENT_MUTATIONS))

check_claim "Mutation total" "$TOTAL_MUTATIONS" \
  "$(doc_number '\*\*([0-9]+) mutations\*\*')"

# The number is read with a character in front of it that is not a digit, so
# that the capture cannot start in the middle of the number and take the
# last digit of it. The PowerShell twin uses the same pattern.
check_claim "Mutation killed" "$KILLED_MUTATIONS" \
  "$(doc_number '[^0-9]([0-9]+) killed by the tests')"

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

# --- the project-structure listing ------------------------------------------
#
# Every source file has to be named in the listing, because the listing is
# the map a reader navigates by. A file that is in the tree and not in the
# listing is a file the reader cannot find: the listing carried eleven of
# them, including the workspace -- the thing the reader is supposed to bring
# their own work into -- and the ring logo.
#
# The listing is a fenced block, and only that block is searched. The
# document mentions file names in prose as well -- in the tools table, in
# the discussion of a gate -- and a mention there is not a place in the map.
#
# The test files are the exception: they are listed by their GLOB
# (`*_test.mbt`), which is a complete statement about them. So the source
# files are the ones checked one by one.
LISTING=$(awk '
  /^## Project Structure/ { inside = 1; next }
  inside && /^```/ {
    if (inblock) { exit }
    inblock = 1
    next
  }
  inblock { print }
' "$README")

if [ -z "$LISTING" ]; then
  fail "$(printf '%-20s the document has no project-structure listing' 'Structure listing')"
else
  # The names are collected and DEDUPED before they are counted, because a
  # name that appears in two directories -- `main.mbt` is in three -- is one
  # entry in the listing. The PowerShell twin does the same, and two twins
  # that count the same thing differently are worse than one twin.
  #
  # But a NAME alone is not enough to say a file is listed: `entries.mbt` is
  # in both the backend and the frontend, and a listing that named only the
  # backend's would still contain the string "entries.mbt". So the name has
  # to appear at least as many times in the listing as the tree has files
  # with that name. That is what makes the check about the FILES rather
  # than about the strings.
  #
  # The directories are searched RECURSIVELY and the list does not name a
  # directory inside another one it already names: `research` covers
  # `research/notes`, and naming both would count the note twice and ask
  # the listing for it twice.
  #
  # The tree is walked ONCE and the counts are made in the shell. A find per
  # name per directory is a fork per name per directory, and a fork on this
  # machine costs a tenth of a second -- which made this gate take a minute
  # to say yes to a document that was already right.
  TREE_FILES=$(for dir in backend frontend cmd models research tools; do
    [ -d "$dir" ] || continue
    find "$dir" -type f \( -name '*.mbt' -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' -o -name '*.md' \) \
      ! -name '*test*'
  done)

  # How many files in the tree carry this name. The answer lands in a
  # variable: a command substitution is a fork, and a fork per name is a
  # hundred forks for a document with thirty-seven names in it.
  COUNT_FILES_NAMED=0
  count_files_named() {
    local list="$1" needle="$2" count=0 file
    while IFS= read -r file; do
      [ -n "$file" ] || continue
      if [ "${file##*/}" = "$needle" ]; then
        count=$((count + 1))
      fi
    done <<< "$list"
    COUNT_FILES_NAMED=$count
  }

  # How many lines of the listing name it. The count is of LINES, so the
  # twins agree.
  COUNT_LINES_NAMING=0
  count_lines_naming() {
    local text="$1" needle="$2" count=0 line
    while IFS= read -r line; do
      case "$line" in
        *"$needle"*) count=$((count + 1)) ;;
      esac
    done <<< "$text"
    COUNT_LINES_NAMING=$count
  }

  MISSING=""
  COUNT=0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    COUNT=$((COUNT + 1))
    count_files_named "$TREE_FILES" "$name"
    local_tree="$COUNT_FILES_NAMED"
    count_lines_naming "$LISTING" "$name"
    local_listing="$COUNT_LINES_NAMING"
    if [ "$local_listing" -lt "$local_tree" ]; then
      MISSING="$MISSING $name"
    fi
  done <<< "$(printf '%s\n' "$TREE_FILES" | sed 's|.*/||' | LC_ALL=C sort -u)"
  if [ -n "$MISSING" ]; then
    fail "$(printf '%-20s the listing does not name some files:%s' 'Structure listing' "$MISSING")"
  else
    printf '  ok      %-20s %s files, all named\n' 'Structure listing' "$COUNT"
  fi
fi

# --- the variable table -----------------------------------------------------
#
# The README tells a reader which environment variables the server reads and
# what each one defaults to. That is a claim about the code, and it is the
# one a reader acts on first: it is the table they copy from.
#
# The variables are derived from the code -- the server's own settings, the
# files the backend reads, and the port the agent's server speaks on -- and
# the table has to list exactly those, with the default the code has. A
# variable the code reads and the table does not name is a setting nobody
# can turn; a default the table states and the code does not have is a
# setting that does something else.
#
# A variable with no default in the code is written `*(unset)*` in the
# document, because that is what it is: the code falls back to the built-in
# one, and the document says so.

code_variables() {
  # The settings, with their defaults. An empty default is an unset one.
  grep -ohE 'env_or\("MAKED_[A-Z_]+", "[^"]*"\)' cmd/server/main.mbt cmd/mcp/main.mbt \
    | sed -E -e 's/env_or\("([A-Z_]+)", ""\)/\1 unset/' \
              -e 's/env_or\("([A-Z_]+)", "([^"]*)"\)/\1 \2/' || true
  # The files the backend reads. They have no default: unset means the
  # built-in one.
  grep -ohE 'get_env_var\("MAKED_[A-Z_]+"\)' backend/*.mbt \
    | sed -E 's/get_env_var\("([A-Z_]+)"\)/\1 unset/' || true
}

# The same, as the README's table states them. The cell is trimmed, the
# backticks are dropped and `*(unset)*` becomes `unset`, so that the two
# sides are compared as plain text.
doc_variables() {
  grep -oE '^\|[[:space:]]*`MAKED_[A-Z_]+`[[:space:]]*\|[[:space:]]*[^|]*\|' "$README" \
    | sed -E 's/^\|[[:space:]]*`(MAKED_[A-Z_]+)`[[:space:]]*\|[[:space:]]*([^|]*)\|$/\1|\2/' \
    | awk -F'|' '{
        d = $2
        gsub(/^[ \t]+/, "", d)
        gsub(/[ \t]+$/, "", d)
        gsub(/`/, "", d)
        if (d == "*(unset)*") d = "unset"
        print $1 " " d
      }' || true
}

# The files the README's own example commands point at. A reader copies
# those commands; a path that is not there is a command that fails on the
# first try.
doc_example_paths() {
  grep -oE 'MAKED_(MODEL|RESEARCH|SOCIETY|CORPUS)=[^ \\]+' "$README" \
    | sed -E 's/^MAKED_[A-Z_]+=//' | LC_ALL=C sort -u || true
}

# Two lists compared by MEMBERSHIP: the same members and the same size.
# Comparing sorted strings would make the twins disagree the moment one of
# them sorted differently, and a message that differs between the twins is a
# message nobody can trust.
same_members() {
  local a="$1" b="$2" line candidate found na nb
  na=$(printf '%s\n' "$a" | grep -c . || true)
  nb=$(printf '%s\n' "$b" | grep -c . || true)
  if [ "$na" != "$nb" ]; then
    return 1
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    found=0
    while IFS= read -r candidate; do
      [ -n "$candidate" ] || continue
      if [ "$candidate" = "$line" ]; then
        found=1
        break
      fi
    done <<< "$b"
    if [ "$found" -eq 0 ]; then
      return 1
    fi
  done <<< "$a"
  return 0
}

CODE_VARIABLES=$(code_variables | LC_ALL=C sort -u)
DOC_VARIABLES=$(doc_variables | LC_ALL=C sort -u)

if [ -z "$CODE_VARIABLES" ]; then
  fail "$(printf '%-20s no environment variable could be derived from the code' 'Variables')"
elif same_members "$CODE_VARIABLES" "$DOC_VARIABLES"; then
  printf '  ok      %-20s %s\n' 'Variables' "$(printf '%s\n' "$CODE_VARIABLES" | grep -c .)"
else
  fail "$(printf '%-20s the tree says [%s], the table says [%s]' \
    'Variables' \
    "$(printf '%s\n' "$CODE_VARIABLES" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$DOC_VARIABLES" | tr '\n' ' ' | sed -e 's/ *$//')")"
fi

MISSING_PATHS=""
EXAMPLE_PATHS=$(doc_example_paths)
while IFS= read -r path; do
  [ -n "$path" ] || continue
  if [ ! -f "$path" ]; then
    MISSING_PATHS="$MISSING_PATHS $path"
  fi
done <<< "$EXAMPLE_PATHS"
if [ -n "$MISSING_PATHS" ]; then
  fail "$(printf '%-20s the example commands name files that are not there:%s' \
    'Example paths' "$MISSING_PATHS")"
else
  printf '  ok      %-20s %s\n' 'Example paths' "$(printf '%s\n' "$EXAMPLE_PATHS" | grep -c . || true)"
fi

# --- the links the document carries -------------------------------------------
#
# A link that points at a file that is not there sends the reader to nothing,
# and the reader cannot tell that the link is broken -- it looks exactly like
# a link that works. The example paths above are the paths a reader copies
# into a shell; these are the paths a reader clicks.
#
# A link is RELATIVE when it does not begin with a scheme, so a link to a
# page on the web is left alone. A fragment is dropped: `page.md#section`
# points at a place inside a file, and it is the file that has to be there.
#
# The link is resolved against the directory the document is in, which is
# where a reader's browser resolves it from.

doc_links() {
  local link_dir
  link_dir="$(dirname "$README")"
  grep -oE '\]\([^)]+\)' "$README" \
    | sed -E 's/^\]\(//; s/\)$//' \
    | sed -E 's/^[[:space:]]*([^[:space:]]*).*$/\1/' \
    | grep -vE '^#' \
    | grep -vE '^[a-zA-Z][a-zA-Z0-9+.-]*:' \
    | sed -E 's/#.*$//' \
    | grep -vE '^$' \
    | while IFS= read -r link_text; do
        printf '%s %s %s\n' "$README" "$link_dir" "$link_text"
      done || true
}

BROKEN_LINKS=""
LINK_COUNT=0
while IFS=' ' read -r LINK_DOC LINK_DIR LINK_TEXT; do
  [ -n "$LINK_TEXT" ] || continue
  LINK_COUNT=$((LINK_COUNT + 1))
  if [ ! -e "$LINK_DIR/$LINK_TEXT" ]; then
    BROKEN_LINKS="$BROKEN_LINKS $LINK_DOC -> $LINK_TEXT"
  fi
done <<< "$(doc_links)"
if [ -n "$BROKEN_LINKS" ]; then
  fail "$(printf '%-20s these links point at files that are not there:%s' \
    'Document links' "$BROKEN_LINKS")"
else
  printf '  ok      %-20s %s\n' 'Document links' "$LINK_COUNT"
fi

# --- the API map ------------------------------------------------------------
#
# The README carries a table of every route the server registers, and that
# table is the map a reader navigates by. A route the table does not name is
# a route nobody can find, and a row the server does not serve is a promise
# the server does not keep.
#
# The routes are derived from the registrations in backend/api.mbt -- the
# same derivation the documents gate uses -- and the two sets are compared.
#
# The README's OTHER mentions of a path are checked as well. A path in
# prose carries a concrete value where the route has a parameter, as in
# /api/loop/reset/knowledge, and it has to resolve to a route that takes a
# parameter there.

tree_routes() {
  tr '\n' ' ' < backend/api.mbt \
    | grep -oE 'app\.(get|post|put|delete|patch)\( *"[^"]+"' \
    | sed -E 's/app\.(get|post|put|delete|patch)\( *"([^"]+)"/\1|\2/' \
    | awk -F'|' '{ print toupper($1), $2 }' \
    | LC_ALL=C sort -u
}

# The README's API table, as "METHOD path".
doc_api_table() {
  grep -oE '^\|[[:space:]]*`(GET|POST|PUT|DELETE|PATCH)`[[:space:]]*\|[[:space:]]*`/api/[^`]+`' "$README" \
    | sed -E 's/^\|[[:space:]]*`([A-Z]+)`[[:space:]]*\|[[:space:]]*`([^`]+)`/\1 \2/' \
    | LC_ALL=C sort -u
}

# Every path the README mentions, wherever it mentions it.
doc_api_paths() {
  grep -oE '/api/[A-Za-z0-9/:_.-]*' "$README" \
    | sed -E -e 's/[.,)]+$//' -e 's/\?.*$//' \
    | LC_ALL=C sort -u
}

TREE_ROUTES=$(tree_routes)
DOC_API_TABLE=$(doc_api_table)

if [ -z "$TREE_ROUTES" ]; then
  fail "$(printf '%-20s no route could be derived from the code' 'API routes')"
elif same_members "$TREE_ROUTES" "$DOC_API_TABLE"; then
  printf '  ok      %-20s %s\n' 'API routes' "$(printf '%s\n' "$TREE_ROUTES" | grep -c .)"
else
  fail "$(printf '%-20s the tree has [%s], the table has [%s]' \
    'API routes' \
    "$(printf '%s\n' "$TREE_ROUTES" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$DOC_API_TABLE" | tr '\n' ' ' | sed -e 's/ *$//')")"
fi

# The routes as patterns, so that a concrete value in a path can match the
# parameter of a route. A parameter becomes "any segment but the slash".
#
# The pattern is built segment by segment, because a replacement cannot
# contain the character that separates the parts of a substitution -- and
# "any segment but the slash" is full of slashes.
build_route_pattern() {
  local route="$1" segment pattern="" path
  local -a segments
  path="${route#* }"
  IFS='/' read -r -a segments <<< "$path"
  for segment in "${segments[@]}"; do
    case "$segment" in
      "") ;;
      :*) pattern="$pattern/[^/]+" ;;
      *) pattern="$pattern/$segment" ;;
    esac
  done
  printf '%s' "$pattern"
}

ROUTE_PATTERNS=""
while IFS= read -r route; do
  [ -n "$route" ] || continue
  ROUTE_PATTERNS="$ROUTE_PATTERNS$(build_route_pattern "$route")
"
done <<< "$TREE_ROUTES"

UNRESOLVED=""
while IFS= read -r path; do
  [ -n "$path" ] || continue
  matched=0
  while IFS= read -r pattern; do
    [ -n "$pattern" ] || continue
    if [[ "$path" =~ ^$pattern$ ]]; then
      matched=1
      break
    fi
  done <<< "$ROUTE_PATTERNS"
  if [ "$matched" -eq 0 ]; then
    UNRESOLVED="$UNRESOLVED $path"
  fi
done <<< "$(doc_api_paths)"
if [ -n "$UNRESOLVED" ]; then
  fail "$(printf '%-20s the document names paths the server does not serve:%s' \
    'API paths' "$UNRESOLVED")"
else
  printf '  ok      %-20s %s\n' 'API paths' "$(doc_api_paths | grep -c . || true)"
fi

# The entry point the discovery document names, and the one the document
# states. An agent that calls the wrong one gets nowhere, so the method the
# server tells it to call and the method the README tells it to call have to
# be the same.
code_entry_point() {
  grep -oE '"entry_point": "[^"]+"' backend/agent.mbt \
    | sed -E 's/.*: "([^"]+)"/\1/' | head -1 || true
}

# The entry point the document states. The sentence is found by its own
# shape -- "entry point is" -- so a method named in some other part of the
# document is not read as a claim about this one. The lines are joined
# first, because the sentence can wrap.
doc_entry_point() {
  tr '\n' ' ' < "$README" | tr -s ' ' \
    | grep -oE 'entry point is `[^`]+`' \
    | grep -oE '`[^`]+`' | tr -d '`' | head -1 || true
}
# --- the protocol version ---------------------------------------------------
#
# The README states which version of the Model Context Protocol MAKED speaks,
# in a sentence and in three example commands. All of them have to be the
# version the server answers to: an agent that reads a version the server
# does not speak cannot call it.

code_protocol() {
  grep -oE '"mcp": "[0-9]{4}-[0-9]{2}-[0-9]{2}"' backend/agent.mbt \
    | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true
}

doc_protocols() {
  grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$README" | LC_ALL=C sort -u || true
}

ENTRY_POINT=$(code_entry_point)
DOC_ENTRY_POINT=$(doc_entry_point)
if [ -z "$ENTRY_POINT" ]; then
  fail "$(printf '%-20s the tree does not name an entry point' 'Entry point')"
elif [ -z "$DOC_ENTRY_POINT" ]; then
  fail "$(printf '%-20s the document does not state the entry point' 'Entry point')"
elif [ "$ENTRY_POINT" != "$DOC_ENTRY_POINT" ]; then
  fail "$(printf '%-20s the tree says %s, the document says %s' \
    'Entry point' "$ENTRY_POINT" "$DOC_ENTRY_POINT")"
else
  printf '  ok      %-20s %s\n' 'Entry point' "$ENTRY_POINT"
fi

PROTOCOL=$(code_protocol)
if [ -z "$PROTOCOL" ]; then
  fail "$(printf '%-20s the tree does not name a protocol version' 'Protocol version')"
else
  WRONG=""
  while IFS= read -r stated; do
    [ -n "$stated" ] || continue
    if [ "$stated" != "$PROTOCOL" ]; then
      WRONG="$WRONG $stated"
    fi
  done <<< "$(doc_protocols)"
  if [ -n "$WRONG" ]; then
    fail "$(printf '%-20s the document names [%s], the tree names %s' \
      'Protocol version' "$(printf '%s' "$WRONG" | sed -e 's/^ *//')" "$PROTOCOL")"
  else
    printf '  ok      %-20s %s\n' 'Protocol version' "$PROTOCOL"
  fi
fi

# --- the versions the document names ---------------------------------------
#
# The README names the versions of the libraries MAKED is built on, with a
# link to each one, and it names its own version. A library version the
# manifest does not pin is a version the reader would install, and it is not
# the one this project runs; a version of MAKED's own that is not the
# manifest's is a version that was never published.
#
# The module path decides which of the two it is: a path under the module's
# own name is MAKED, and anything else is a library.

doc_versions() {
  grep -oE '[A-Za-z_][A-Za-z0-9_./-]*@[0-9]+\.[0-9]+\.[0-9]+' "$README" \
    | sed -E 's#^mooncakes\.io/docs/##' \
    | LC_ALL=C sort -u || true
}

MODULE_NAME=$(sed -nE 's/^name = "([^"]+)"/\1/p' moon.mod)
MODULE_VERSION=$(sed -nE 's/^version = "([^"]+)"/\1/p' moon.mod)
DEPENDENCY_PINS=$(sed -nE 's/^ *"([^"]+)@([^"]+)".*/\1 \2/p' moon.mod)

WRONG_VERSION=""
while IFS= read -r stated; do
  [ -n "$stated" ] || continue
  module="${stated%%@*}"
  version="${stated##*@}"
  case "$module" in
    "$MODULE_NAME"|"$MODULE_NAME"/*)
      if [ "$version" != "$MODULE_VERSION" ]; then
        WRONG_VERSION="$WRONG_VERSION $stated"
      fi
      ;;
    *)
      if ! printf '%s\n' "$DEPENDENCY_PINS" | grep -qxF "$module $version"; then
        WRONG_VERSION="$WRONG_VERSION $stated"
      fi
      ;;
  esac
done <<< "$(doc_versions)"
if [ -n "$WRONG_VERSION" ]; then
  fail "$(printf '%-20s the document names versions the manifest does not pin:%s' \
    'Referenced versions' "$WRONG_VERSION")"
else
  printf '  ok      %-20s %s\n' 'Referenced versions' "$(doc_versions | grep -c . || true)"
fi

# --- the release the document names ------------------------------------------
#
# The README tells a reader which release they are looking at, and it says so
# twice: once at the top of the document and once at the foot of it. The
# number it prints there is the module's own version -- the one in moon.mod --
# and it is written with a leading "v", the way a release is named everywhere
# else.
#
# The "referenced versions" check above reads the versions the document names
# in the `name@version` form, so the mooncakes link and the package pin are
# covered by it. The bare `v0.1.7` is not: a release name is not a reference
# to a module, and a README that names a release the module never had is a
# README a reader cannot install from.
#
# The claim is found by its own shape -- the words "current release" -- so a
# library version mentioned somewhere else in the document is not read as a
# claim about MAKED's own release. Every line that makes the claim has to
# name the module's version, so the two lines that make it agree with each
# other as well as with the tree.

doc_release_versions() {
  grep -iE 'current release' "$README" \
    | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?' \
    | sed -E 's/^v//' | LC_ALL=C sort -u || true
}

DOC_RELEASE_VERSIONS=$(doc_release_versions)
if [ -z "$DOC_RELEASE_VERSIONS" ]; then
  fail "$(printf '%-20s the document does not name the current release' 'Release version')"
else
  WRONG_RELEASE=""
  while IFS= read -r stated; do
    [ -n "$stated" ] || continue
    if [ "$stated" != "$MODULE_VERSION" ]; then
      WRONG_RELEASE="$WRONG_RELEASE $stated"
    fi
  done <<< "$DOC_RELEASE_VERSIONS"
  if [ -n "$WRONG_RELEASE" ]; then
    fail "$(printf '%-20s the document names [%s], the module has %s' \
      'Release version' "$(printf '%s' "$WRONG_RELEASE" | sed -e 's/^ *//')" "$MODULE_VERSION")"
  else
    printf '  ok      %-20s %s\n' 'Release version' "$MODULE_VERSION"
  fi
fi

# --- the assets the release carries -------------------------------------------
#
# The README's table of the ready-to-run builds names three files, and the
# release workflow is what builds them. The names have to be the same: a
# reader who downloads "maked-0.1.7-linux-x86_64.tar.gz" from a release
# that carried "maked-0.1.7-linux-amd64.tar.gz" is a reader with a 404.
#
# The workflow's matrix is the source: each entry says which platform the
# binary is for and how it is archived, and the asset is the two of them
# with the version in the middle. The matrix is read as pairs -- a target
# and the archive that goes with it -- because a target without its
# archive is not an asset.

code_release_assets() {
  awk '
    function flush() {
      if (target != "" && archive != "") {
        printf "maked-<version>-%s.%s\n", target, archive
      }
      target = ""
      archive = ""
    }
    /^[ \t]*- os:/ { flush(); next }
    /^[ \t]*target:/ { target = $2; next }
    /^[ \t]*archive:/ { archive = $2; next }
    END { flush() }
  ' .github/workflows/publish.yml | LC_ALL=C sort -u
}

# The assets the README's table names.
doc_release_assets() {
  grep -oE 'maked-<version>[a-z0-9._-]+' "$README" | LC_ALL=C sort -u || true
}

CODE_ASSETS=$(code_release_assets)
DOC_ASSETS=$(doc_release_assets)
if [ -z "$CODE_ASSETS" ]; then
  fail "$(printf '%-20s no asset could be derived from the workflow' 'Release assets')"
elif same_members "$CODE_ASSETS" "$DOC_ASSETS"; then
  printf '  ok      %-20s %s\n' 'Release assets' "$(printf '%s\n' "$CODE_ASSETS" | grep -c .)"
else
  fail "$(printf '%-20s the workflow says [%s], the document says [%s]' \
    'Release assets' \
    "$(printf '%s\n' "$CODE_ASSETS" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$DOC_ASSETS" | tr '\n' ' ' | sed -e 's/ *$//')")"
fi

# --- the license the document names -------------------------------------------
#
# The README says which license the project is under, and the manifest says
# the same thing in the form the registry reads. The two have to be the same
# license: a reader who reads the README and assumes a license that is not
# the one the package carries is wrong about the thing they most need to be
# right about.
#
# The LICENSE file is the text of that license, and it has to name it. A
# LICENSE file that carries somebody else's license is a project that says
# one thing and ships another.
#
# The claim is found by its own shape -- the "## License" heading and the
# "<id> License" that follows it -- so a license named in some other part of
# the document is not read as a claim about this one.

code_license() {
  sed -nE 's/^license = "([^"]+)"/\1/p' moon.mod
}

doc_license() {
  awk '
    /^## License/ { inside = 1; next }
    inside && /^#/ { exit }
    inside { print }
  ' "$README" \
    | grep -oE '[A-Za-z0-9.+-]+ License' \
    | sed -E 's/ License$//' | head -1 || true
}

# Whether the LICENSE file names the license, as a WORD. "limitations" is
# not the MIT license, even though it carries the letters.
license_file_names() {
  local id="$1" name text
  case "$id" in
    *-*) name="${id%%-*}" ;;
    *)   name="$id" ;;
  esac
  name="$(printf '%s' "$name" | tr 'A-Z' 'a-z')"
  text="$(tr 'A-Z' 'a-z' < LICENSE)"
  printf '%s' "$text" | grep -qw -- "$name" > /dev/null 2>&1
}

MODULE_LICENSE=$(code_license)
DOC_LICENSE=$(doc_license)
if [ -z "$MODULE_LICENSE" ]; then
  fail "$(printf '%-20s the manifest does not declare a license' 'License')"
elif [ -z "$DOC_LICENSE" ]; then
  fail "$(printf '%-20s the document does not state the license' 'License')"
elif [ "$DOC_LICENSE" != "$MODULE_LICENSE" ]; then
  fail "$(printf '%-20s the manifest says %s, the document says %s' \
    'License' "$MODULE_LICENSE" "$DOC_LICENSE")"
else
  printf '  ok      %-20s %s\n' 'License' "$MODULE_LICENSE"
fi

if [ ! -f "LICENSE" ]; then
  fail "$(printf '%-20s LICENSE is not there' 'License file')"
elif license_file_names "$MODULE_LICENSE"; then
  printf '  ok      %-20s %s\n' 'License file' "$MODULE_LICENSE"
else
  fail "$(printf '%-20s the LICENSE file does not name %s' 'License file' "$MODULE_LICENSE")"
fi

# --- the ports the document names ----------------------------------------------
#
# The README tells the reader which port to open, and it says so in seven
# places: the URL after `docker compose up`, the URL after the server is
# started, the URL in two curl commands, and the mapping in the `docker run`
# command. Those are the ports the reader types, and they have to be the
# port the server actually listens on.
#
# The agent's server is a different server, and its port is the one the
# README itself sets: MAKED_MCP_PORT=8735. So a port the README writes is
# allowed when it is the server's default port or the port the README sets
# for the agent's server -- and for nothing else.
#
# The server's default port comes from the code, the same place the
# environment-variable table gets it from.

code_default_port() {
  grep -ohE 'env_or\("MAKED_PORT", "[0-9]+"\)' cmd/server/main.mbt \
    | sed -E 's/.*"([0-9]+)".*/\1/' | head -1 || true
}

# The ports the README sets for the agent's server.
doc_mcp_ports() {
  grep -oE 'MAKED_MCP_PORT=[0-9]+' "$README" | sed -E 's/.*=//' || true
}

# Every port the README writes: the ones in its URLs and the two sides of
# the mapping in its docker command.
doc_ports() {
  grep -oE '127\.0\.0\.1:[0-9]+' "$README" | sed -E 's/.*://' || true
  grep -oE '\-p [0-9]+:[0-9]+' "$README" | sed -E 's/\-p //' | tr ':' '\n' || true
}

DEFAULT_PORT=$(code_default_port)
ALLOWED_PORTS=$( { printf '%s\n' "$DEFAULT_PORT"; doc_mcp_ports; } )
WRONG_PORT=""
while IFS= read -r port; do
  [ -n "$port" ] || continue
  if ! printf '%s\n' "$ALLOWED_PORTS" | grep -qxF "$port"; then
    WRONG_PORT="$WRONG_PORT $port"
  fi
done <<< "$(doc_ports)"
if [ -z "$DEFAULT_PORT" ]; then
  fail "$(printf '%-20s the server does not name a default port' 'Port')"
elif [ -n "$WRONG_PORT" ]; then
  fail "$(printf '%-20s these are not the ports the project uses:%s' \
    'Port' "$WRONG_PORT")"
else
  printf '  ok      %-20s %s\n' 'Port' "$DEFAULT_PORT"
fi

# --- the file formats and the corpus kinds -----------------------------------
#
# The README has a table of the files a reader can change, and every row names
# the format that file is written in. Those formats are the code's: a file
# written in another one is refused at start-up, so a reader who copied the
# wrong format out of the document finds out at the worst possible moment --
# when the server refuses to start and says the format is not one it knows.
#
# The corpus's sentence says which kinds a source can have, and the code
# decides that too: a kind the code does not know is a corpus the server
# refuses to read.
#
# Both are compared by MEMBERSHIP: the order the two sets are written in says
# nothing, and a message that differs between the twins is a message nobody
# can trust.

# The formats the code defines. Each is a constant in the backend, and the
# constant is what a file's "format" field is compared against.
code_formats() {
  grep -h -oE 'pub const [A-Z_]+_FORMAT : String = "[^"]+"' backend/*.mbt \
    | sed -E 's/.*= "([^"]+)"/\1/' \
    | LC_ALL=C sort -u
}

# The formats the document names, in the table of the files a reader can
# change. The rows are the ones that name the environment variable that points
# at the file, so a format mentioned in an example elsewhere in the document is
# not read as a claim about the table.
doc_formats() {
  grep -E '^\|.*MAKED_(MODEL|RESEARCH|SOCIETY|CORPUS)' "$README" \
    | grep -oE 'maked\.[a-z]+\.v[0-9]+' \
    | LC_ALL=C sort -u
}

# The formats the code declares, paired with the variable that names the file
# they are for, as "variable format".
#
# Each backend file owns ONE format constant and reads ONE environment
# variable, so the pair is read from the file that holds both: the model file
# declares the format a model is written in and is the file MAKED_MODEL names.
# A file that owns more than one of either is not paired -- the gate would
# rather say it cannot tell than guess.
code_file_formats() {
  for f in backend/*.mbt; do
    awk '
      match($0, /pub const [A-Z_]+_FORMAT : String = "[^"]+"/) {
        s = substr($0, RSTART, RLENGTH)
        sub(/.*= "/, "", s)
        sub(/"$/, "", s)
        formats[nf++] = s
      }
      match($0, /get_env_var\("MAKED_[A-Z_]+"\)/) {
        s = substr($0, RSTART, RLENGTH)
        sub(/.*\("/, "", s)
        sub(/"\)$/, "", s)
        vars[nv++] = s
      }
      END {
        if (nf == 1 && nv == 1) printf "%s %s\n", vars[0], formats[0]
      }
    ' "$f"
  done | LC_ALL=C sort -u
}

# The formats the document names, paired with the variable that names the
# file, as "variable format".
#
# The formats on their own are checked above, and a set of four formats does
# not say which file is written in which. A table that gives the machine the
# corpus's format still holds all four formats, and a reader who follows it
# writes a file the server refuses to read.
#
# The row is read as a pair: the variable names the file, and the format in
# the same row is the one that file has to be written in.
doc_file_formats() {
  grep -E '^\|.*MAKED_(MODEL|RESEARCH|SOCIETY|CORPUS)' "$README" \
    | awk '{
        variable = ""
        format = ""
        n = split($0, cells, "|")
        for (i = 1; i <= n; i++) {
          c = cells[i]
          if (match(c, /MAKED_(MODEL|RESEARCH|SOCIETY|CORPUS)/)) {
            variable = substr(c, RSTART, RLENGTH)
          }
          if (match(c, /maked\.[a-z]+\.v[0-9]+/)) {
            format = substr(c, RSTART, RLENGTH)
          }
        }
        if (variable != "" && format != "") printf "%s %s\n", variable, format
      }' \
    | LC_ALL=C sort -u
}
# The kinds the code accepts for a corpus, as they are written in a file. The
# function that renders a kind is the one place the code says what the words
# are.
code_corpus_kinds() {
  awk '
    match($0, /^pub fn corpus_kind_text/) { inside = 1; next }
    inside && match($0, /^}/) { inside = 0 }
    inside && match($0, /=>/) {
      line = $0
      if (match(line, /"[^"]+"/)) {
        print substr(line, RSTART + 1, RLENGTH - 2)
      }
    }
  ' backend/corpus.mbt | LC_ALL=C sort -u
}

# The kinds the document names, in the sentence that says what a kind can be.
doc_corpus_kinds() {
  grep -oE '`kind` is [^.]*' "$README" \
    | sed -E 's/^`kind` is //' \
    | grep -oE '`[^`]+`' \
    | sed -E 's/^`//; s/`$//' \
    | LC_ALL=C sort -u
}

CODE_FORMATS=$(code_formats)
DOC_FORMATS=$(doc_formats)
if [ -z "$CODE_FORMATS" ]; then
  fail "$(printf '%-20s no file format could be derived from the code' 'File formats')"
elif same_members "$CODE_FORMATS" "$DOC_FORMATS"; then
  printf '  ok      %-20s %s\n' 'File formats' "$(printf '%s\n' "$CODE_FORMATS" | grep -c .)"
else
  fail "$(printf '%-20s the tree says [%s], the table says [%s]' \
    'File formats' \
    "$(printf '%s\n' "$CODE_FORMATS" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$DOC_FORMATS" | tr '\n' ' ' | sed -e 's/ *$//')")"
fi

CODE_FILE_FORMATS=$(code_file_formats)
DOC_FILE_FORMATS=$(doc_file_formats)
if [ -z "$CODE_FILE_FORMATS" ]; then
  fail "$(printf '%-20s no file and format could be derived from the code' 'File pairings')"
elif same_members "$CODE_FILE_FORMATS" "$DOC_FILE_FORMATS"; then
  printf '  ok      %-20s %s\n' 'File pairings' "$(printf '%s\n' "$CODE_FILE_FORMATS" | grep -c .)"
else
  fail "$(printf '%-20s the tree says [%s], the table says [%s]' \
    'File pairings' \
    "$(printf '%s\n' "$CODE_FILE_FORMATS" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$DOC_FILE_FORMATS" | tr '\n' ' ' | sed -e 's/ *$//')")"
fi

# The names the CI workflow gives its jobs. A job is written as a key with a
# name under it, and the name is what the runner shows and what a reader
# looks for in the list of things that have to be green.
#
# The step names are written as "- name:", so the four spaces of a job's own
# name are what tells the two apart.
code_job_names() {
  awk '
    /^jobs:/ { inside = 1; next }
    inside && /^    name: / { print substr($0, 11) }
  ' .github/workflows/ci.yml | LC_ALL=C sort -u
}

# The names the README gives them, in the sentence that lists the jobs. The
# sentence is found by its own shape -- "jobs, all of which have to be
# green" -- so a job named in some other part of the document is not read as
# a claim about this list. The list runs onto the line below, so that line is
# read as well.
doc_job_names() {
  awk '
    /jobs, all of which have to be green/ { grab = 2 }
    grab > 0 {
      line = $0
      while (match(line, /\*\*[^*]+\*\*/)) {
        print substr(line, RSTART + 2, RLENGTH - 4)
        line = substr(line, RSTART + RLENGTH)
      }
      grab--
    }
  ' "$README" | LC_ALL=C sort -u
}

# The names of the CI jobs. The COUNT of them is checked as a word further
# down, and a count of six is not the same claim as the six names: a job
# that is renamed leaves the count right and the name wrong, and a reader
# watching the pipeline for "Build (js)" is watching for a job that is not
# there.
CODE_JOB_NAMES=$(code_job_names)
DOC_JOB_NAMES=$(doc_job_names)
if [ -z "$CODE_JOB_NAMES" ]; then
  fail "$(printf '%-20s no job name could be derived from the workflow' 'CI jobs')"
elif same_members "$CODE_JOB_NAMES" "$DOC_JOB_NAMES"; then
  printf '  ok      %-20s %s\n' 'CI jobs' "$(printf '%s\n' "$CODE_JOB_NAMES" | grep -c .)"
else
  fail "$(printf '%-20s the tree says [%s], the document says [%s]' \
    'CI jobs' \
    "$(printf '%s\n' "$CODE_JOB_NAMES" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$DOC_JOB_NAMES" | tr '\n' ' ' | sed -e 's/ *$//')")"
fi
CODE_CORPUS_KINDS=$(code_corpus_kinds)
DOC_CORPUS_KINDS=$(doc_corpus_kinds)
if [ -z "$CODE_CORPUS_KINDS" ]; then
  fail "$(printf '%-20s no corpus kind could be derived from the code' 'Corpus kinds')"
elif same_members "$CODE_CORPUS_KINDS" "$DOC_CORPUS_KINDS"; then
  printf '  ok      %-20s %s\n' 'Corpus kinds' "$(printf '%s\n' "$CODE_CORPUS_KINDS" | grep -c .)"
else
  fail "$(printf '%-20s the tree says [%s], the document says [%s]' \
    'Corpus kinds' \
    "$(printf '%s\n' "$CODE_CORPUS_KINDS" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$DOC_CORPUS_KINDS" | tr '\n' ' ' | sed -e 's/ *$//')")"
fi

# --- the tools the agent's server offers -------------------------------------
#
# The README has a table of the seven tools, and the arguments each one takes.
# Those are the discovery document's: it is what the server answers with, and
# a tool the document does not offer is a tool an agent cannot call.
#
# The arguments are read from the schema each tool uses. The tool says which
# schema it has, and the schema says which arguments it has, so the two are
# followed rather than copied.
#
# A tool that takes no arguments says so with a dash, and a tool that takes
# one says so with its name. The arguments are compared as PAIRS -- a tool
# and an argument -- so a table that drops one argument from one tool is
# caught, and a table that moves an argument to another tool is caught too.

# The tools the discovery document declares. The `name:` field is what makes
# a tool a tool.
code_tools() {
  grep -oE 'name: "maked_[a-z_]+"' backend/agent.mbt \
    | grep -oE 'maked_[a-z_]+' | LC_ALL=C sort -u || true
}

# The arguments each tool takes, as "tool argument" pairs.
#
# The schema functions come first in the file and the tool specs after, so
# one pass is enough: the schemas are collected as they are met, and the
# tool specs are answered from what was collected.
code_tool_args() {
  awk '
    match($0, /^fn agent_[a-z_]*\(\) -> Json \{/) {
      fn = $0
      sub(/^fn /, "", fn)
      sub(/\(\).*/, "", fn)
      inside = 1
      next
    }
    inside && match($0, /^}/) { inside = 0 }
    inside && match($0, /^      "[a-z_]+": \{$/) {
      key = $0
      sub(/^      "/, "", key)
      sub(/": \{$/, "", key)
      props[fn] = props[fn] (props[fn] == "" ? "" : " ") key
      next
    }
    match($0, /^      name: "maked_[a-z_]+",/) {
      tool = $0
      sub(/^      name: "/, "", tool)
      sub(/",$/, "", tool)
      next
    }
    match($0, /^      arguments: agent_[a-z_]*\(\),/) {
      fn = $0
      sub(/^      arguments: /, "", fn)
      sub(/\(\),$/, "", fn)
      args[tool] = fn
    }
    END {
      for (t in args) {
        n = split(props[args[t]], list, " ")
        for (i = 1; i <= n; i++) {
          if (list[i] != "") printf "%s %s\n", t, list[i]
        }
      }
    }
  ' backend/agent.mbt | LC_ALL=C sort -u
}

# The tools the README's table gives them. A tool row starts with the tool
# name in backticks.
doc_tools() {
  grep -oE '^\| `maked_[a-z_]+`' "$README" \
    | sed -E 's/^\| `([^`]+)`.*/\1/' | LC_ALL=C sort -u || true
}

# The arguments the README's table gives each tool, as "tool argument" pairs.
# The arguments sit in the second column, and a tool that takes none says so
# with a dash rather than with an empty cell.
doc_tool_args() {
  grep -oE '^\| `maked_[a-z_]+` \| [^|]*\|' "$README" \
    | sed -E 's/^\| `([^`]+)` \| ([^|]*)\|/\1|\2/' \
    | while IFS='|' read -r tool cell; do
        for arg in $(printf '%s' "$cell" | grep -oE '`[^`]+`' | tr -d '`'); do
          printf '%s %s\n' "$tool" "$arg"
        done
      done | LC_ALL=C sort -u
}

CODE_TOOLS=$(code_tools)
DOC_TOOLS=$(doc_tools)
if [ -z "$CODE_TOOLS" ]; then
  fail "$(printf '%-20s no tool could be derived from the discovery document' 'Agent tools')"
elif same_members "$CODE_TOOLS" "$DOC_TOOLS"; then
  printf '  ok      %-20s %s\n' 'Agent tools' "$(printf '%s\n' "$CODE_TOOLS" | grep -c .)"
else
  fail "$(printf '%-20s the tree says [%s], the table says [%s]' \
    'Agent tools' \
    "$(printf '%s\n' "$CODE_TOOLS" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$DOC_TOOLS" | tr '\n' ' ' | sed -e 's/ *$//')")"
fi

CODE_TOOL_ARGS=$(code_tool_args)
DOC_TOOL_ARGS=$(doc_tool_args)
if [ -z "$CODE_TOOL_ARGS" ]; then
  fail "$(printf '%-20s no tool argument could be derived from the discovery document' 'Agent arguments')"
elif same_members "$CODE_TOOL_ARGS" "$DOC_TOOL_ARGS"; then
  printf '  ok      %-20s %s\n' 'Agent arguments' "$(printf '%s\n' "$CODE_TOOL_ARGS" | grep -c .)"
else
  fail "$(printf '%-20s the tree says [%s], the table says [%s]' \
    'Agent arguments' \
    "$(printf '%s\n' "$CODE_TOOL_ARGS" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$DOC_TOOL_ARGS" | tr '\n' ' ' | sed -e 's/ *$//')")"
fi

# --- the counts the document spells out -------------------------------------
#
# The README says some of its counts in words -- "seven tools", "ten pages",
# "Six jobs" -- and a gate that reads only digits lets those rot. A count
# written as a word is a claim like any other: the tree has a number, the
# document has a word, and the two have to be the same number.
#
# The counts are derived from the tree:
#
#   the domains    the ring's domains, from backend/pages.mbt
#   the tools      the agent's server, from backend/agent.mbt
#   the files      the MAKED_* variables the backend reads
#   the pages      the pages the server seeds
#   the packages   the library packages -- the ones that are not executables
#   the platforms  the release matrix
#   the jobs       the jobs in the CI workflow
#   the suites     the mutation suites
#   the languages  the variants of the Lang enum
#   the example    the example machine that ships, section by section
#
# A word that is not a number -- "of tools", "own positions" -- is not a
# count, and it is passed over: the pattern is here to find the count, not to
# police the prose around it.

# The word and the number it stands for. The answer lands in a variable: a
# command substitution is a fork, and there are twenty words to look up.
WORD_NUMBER=0
word_number() {
  case "$1" in
    one)     WORD_NUMBER=1 ;;
    two)     WORD_NUMBER=2 ;;
    three)   WORD_NUMBER=3 ;;
    four)    WORD_NUMBER=4 ;;
    five)    WORD_NUMBER=5 ;;
    six)     WORD_NUMBER=6 ;;
    seven)   WORD_NUMBER=7 ;;
    eight)   WORD_NUMBER=8 ;;
    nine)    WORD_NUMBER=9 ;;
    ten)     WORD_NUMBER=10 ;;
    eleven)  WORD_NUMBER=11 ;;
    twelve)  WORD_NUMBER=12 ;;
    thirteen) WORD_NUMBER=13 ;;
    fourteen) WORD_NUMBER=14 ;;
    fifteen) WORD_NUMBER=15 ;;
    sixteen) WORD_NUMBER=16 ;;
    seventeen) WORD_NUMBER=17 ;;
    eighteen) WORD_NUMBER=18 ;;
    nineteen) WORD_NUMBER=19 ;;
    twenty)  WORD_NUMBER=20 ;;
    *)       WORD_NUMBER=0 ;;
  esac
}


# The ring's domains, and the names it gives them. One pass: the count and
# the names come out of the same reading of the file.
RING_SHAPE=$(awk '
  /^pub fn ring_domains\(\)/ { inside = 1; next }
  inside && /^}/ { exit }
  inside && /^[[:space:]]+\("[a-z]+",/ {
    n++
    name = $0
    sub(/^[[:space:]]*\("/, "", name)
    sub(/".*/, "", name)
    print "name " name
  }
  END { print "count " n + 0 }
' backend/pages.mbt)
DOMAIN_COUNT=0
DOMAIN_NAMES=""
while read -r kind value; do
  case "$kind" in
    count) DOMAIN_COUNT="$value" ;;
    name)  DOMAIN_NAMES="$DOMAIN_NAMES$value"$'\n' ;;
  esac
done <<< "$RING_SHAPE"

# The tools the agent's server offers.
TOOL_COUNT=$(grep -cE 'name: "maked_[a-z_]+"' backend/agent.mbt)

# The files the backend reads.
FILE_COUNT=$(awk '
  {
    line = $0
    while (match(line, /get_env_var\("MAKED_[A-Z_]+"\)/)) {
      name = substr(line, RSTART + 14, RLENGTH - 16)
      if (!(name in seen)) { seen[name] = 1; n++ }
      line = substr(line, RSTART + RLENGTH)
    }
  }
  END { print n + 0 }
' backend/*.mbt)

# The pages the server holds: the ring's pages, the utility pages, the index
# and the not-found page.
PAGE_SHAPE=$(awk '
  /^        "[a-z0-9-]+",[ \t]*$/ { static++ }
  /slug: "(index|404)"/ { fixed++ }
  END { print static + 0, fixed + 0 }
' backend/pages.mbt)
read -r STATIC_PAGES FIXED_PAGES <<< "$PAGE_SHAPE"
PAGE_COUNT=$((DOMAIN_COUNT + STATIC_PAGES + FIXED_PAGES))

# The library packages -- the ones that are not executables. The executables
# are applications; the packages are what a reader can depend on. The
# module's own manifest is not a package either.
MOON_PKGS=$(find . \( -path './_build' -o -path './.mooncakes' -o -path './.git' \) -prune \
  -o -name moon.pkg -type f -print | grep -v '^\./moon\.pkg$')
PACKAGE_COUNT=0
if [ -n "$MOON_PKGS" ]; then
  PACKAGE_COUNT=$(awk '
    FNR == 1 { if (name != "" && !seen) n++; name = FILENAME; seen = 0 }
    /pkgtype\(kind: "executable"\)/ { seen = 1 }
    END { if (name != "" && !seen) n++; print n + 0 }
  ' $MOON_PKGS)
fi

# The platforms a release is built for.
PLATFORM_COUNT=$(grep -cE '^[[:space:]]*- os: ' .github/workflows/publish.yml)

# The jobs in the CI workflow.
JOB_COUNT=$(awk '
  /^jobs:/ { inside = 1; next }
  inside && /^  [A-Za-z0-9_-]+:/ { n++ }
  END { print n + 0 }
' .github/workflows/ci.yml)

# The mutation suites.
SUITE_FILES=(tools/mutate-*.ps1)
SUITE_COUNT=${#SUITE_FILES[@]}

# The languages the backend answers in.
LANGUAGE_COUNT=$(awk '
  /^pub enum Lang \{/ { inside = 1; next }
  inside && /^}/ { exit }
  inside && !/^[[:space:]]*(\/\/|$)/ { n++ }
  END { print n + 0 }
' backend/i18n.mbt)

# The example machine that ships with the repository, section by section.
EXAMPLE_SHAPE=$(awk '
  /^  "[a-z]+": \[/ { section = $1; gsub(/[" :]/, "", section); next }
  /^    \{/ { count[section]++ }
  END { print count["domains"] + 0, count["positions"] + 0, count["slots"] + 0 }
' models/product-iteration.json)
read -r EXAMPLE_DOMAINS EXAMPLE_POSITIONS EXAMPLE_SLOTS <<< "$EXAMPLE_SHAPE"

# The claims, the counts the tree has, and the patterns that find the counts
# in the document.
#
# A pattern is the text before the number word and the text after it, with a
# bar between the two. The patterns are handed to ONE awk pass: walking the
# document with the shell's own matcher takes thirteen seconds on this
# machine, and a gate that takes that long is a gate that gets skipped.
#
# The claims are read back in the order they are written here, and the
# patterns of a claim are read in the order they are written too, so that the
# two twins see the words in the same order and print the same message.
CLAIM_SPECS=$(
  printf 'Domains\t%s\t|-domain ring\tthe | domains in ring order\tthe | domain in ring order\tThe | domains are\n' "$DOMAIN_COUNT"
  printf 'Tools\t%s\t| tool\n' "$TOOL_COUNT"
  printf 'Files\t%s\t| files MAKED runs on\t| file MAKED runs on\t### The | files\t### The | file\n' "$FILE_COUNT"
  printf 'Pages\t%s\tthe | pages the server holds\tthe | page the server holds\tthe | public pages\tthe | public page\n' "$PAGE_COUNT"
  printf 'Packages\t%s\tships | packages\tships | package\n' "$PACKAGE_COUNT"
  printf 'Platforms\t%s\tbuild for | platforms\tbuild for | platform\n' "$PLATFORM_COUNT"
  printf 'Jobs\t%s\t| jobs, all of which\t| job, all of which\n' "$JOB_COUNT"
  printf 'Suites\t%s\tacross the | suites\tacross the | suite\n' "$SUITE_COUNT"
  printf 'Languages\t%s\t| languages\t| language\n' "$LANGUAGE_COUNT"
  printf 'Example domains\t%s\t| domains,\n' "$EXAMPLE_DOMAINS"
  printf 'Example positions\t%s\t| positions,\n' "$EXAMPLE_POSITIONS"
  printf 'Example slots\t%s\t| slots\t| slot\n' "$EXAMPLE_SLOTS"
  printf 'Mutation equivalents\t%s\t| deliberately equivalent\n' "$EQUIVALENT_MUTATIONS"
)

# The document is read once, and every pattern is tried against every line.
# The number word is what the pattern's brackets hold, so the word is cut out
# of the text the pattern matched: the text before it and the text after it
# are the pattern's own two halves.
SCAN_RESULTS=$(awk -v specs="$CLAIM_SPECS" '
BEGIN {
  rows = split(specs, spec_lines, "\n")
  np = 0
  for (i = 1; i <= rows; i++) {
    fields = split(spec_lines[i], f, "\t")
    labels[i] = f[1]
    counts[i] = f[2]
    own = ""
    for (k = 3; k <= fields; k++) {
      np++
      split(f[k], ps, "|")
      pre[np] = ps[1]
      suf[np] = ps[2]
      re[np] = ps[1] "([A-Za-z]+)" ps[2]
      own = own " " np
    }
    owners[i] = own
  }
}
{ lines[NR] = $0 }
END {
  for (i = 1; i <= rows; i++) {
    list = split(owners[i], pl, " ")
    for (j = 1; j <= list; j++) {
      p = pl[j]
      for (ln = 1; ln <= NR; ln++) {
        rest = lines[ln]
        while (match(rest, re[p])) {
          text = substr(rest, RSTART, RLENGTH)
          word = substr(text, length(pre[p]) + 1, RLENGTH - length(pre[p]) - length(suf[p]))
          words[i] = words[i] word ","
          rest = substr(rest, RSTART + RLENGTH)
        }
      }
    }
  }
  for (i = 1; i <= rows; i++) print labels[i] "\t" counts[i] "\t" words[i]
}
' "$README")

# One claim: the label, the count the tree has, and the words the patterns
# found. Every number word has to be the tree's number, and at least one of
# them has to be there.
while IFS=$'\t' read -r label expected words; do
  [ -n "$label" ] || continue
  stated=""
  broken=""
  IFS=',' read -r -a claim_words <<< "$words"
  for word in "${claim_words[@]}"; do
    [ -n "$word" ] || continue
    word="${word,,}"
    word_number "$word"
    if [ "$WORD_NUMBER" -eq 0 ]; then
      continue
    fi
    if [ -z "$stated" ]; then
      stated="$word"
    fi
    if [ "$WORD_NUMBER" -ne "$expected" ] && [ -z "$broken" ]; then
      broken="$word"
    fi
  done
  if [ -n "$broken" ]; then
    fail "$(printf '%-20s %s: the tree has %s, the document says %s' \
      'Number words' "$label" "$expected" "$broken")"
  elif [ -z "$stated" ]; then
    fail "$(printf '%-20s %s: the document does not state the count' \
      'Number words' "$label")"
  else
    printf '  ok      %-20s %s: %s (%s)\n' 'Number words' "$label" "$stated" "$expected"
  fi
done <<< "$SCAN_RESULTS"

# The names the document gives the ring's domains, against the names the tree
# gives them. A count of five is not the same claim as the five names.
DOC_DOMAIN_NAMES=$(awk '
  {
    if (!match($0, /The [A-Za-z]+ domains are/)) next
    line = substr($0, RSTART + RLENGTH)
    sub(/\..*/, "", line)
    while (match(line, /`[a-z]+`/)) {
      print substr(line, RSTART + 1, RLENGTH - 2)
      line = substr(line, RSTART + RLENGTH)
    }
  }
' "$README" | LC_ALL=C sort -u)

if [ -z "$DOMAIN_NAMES" ] || [ -z "$DOC_DOMAIN_NAMES" ]; then
  fail "$(printf '%-20s the domain names could not be found on both sides' 'Domain names')"
elif same_members "$DOMAIN_NAMES" "$DOC_DOMAIN_NAMES"; then
  printf '  ok      %-20s %s\n' 'Domain names' \
    "$(printf '%s\n' "$DOC_DOMAIN_NAMES" | tr '\n' ' ' | sed -e 's/ *$//')"
else
  fail "$(printf '%-20s the tree names [%s], the document names [%s]' \
    'Domain names' \
    "$(printf '%s\n' "$DOMAIN_NAMES" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$DOC_DOMAIN_NAMES" | tr '\n' ' ' | sed -e 's/ *$//')")"
fi


# --- the collective's numbers ------------------------------------------------
#
# The collective is pyroduct's, but the words for it are a file in this
# repository: research/society.yaml names the thirteen positions, the eight
# phases and the eighteen triggers. The README states those numbers in three
# places -- the row of the three layers, the feature bullet, and the
# sentence about the vocabulary -- and every one of them has to be the
# file's.
#
# Each number is found in the sentence that states it, and not by the noun
# alone: "34 positions" is the subject machine's, and the collective's are
# thirteen. A pattern that looked for the noun would have caught the wrong
# number and called it right.
#
# The number of transitions is the machine's and not the file's, so that one
# is checked where the machine is: by the integration suite, which has the
# collective the server served.

# The entries in each section of the vocabulary. The carriage returns go
# first: a file edited on Windows is the same file, and a gate that reads it
# differently depending on the line endings is a gate that lies.
collective_counts() {
  tr -d '\r' < research/society.yaml | awk '
    /^[a-z_]+:[ \t]*$/ { section = $1; sub(/:$/, "", section); next }
    section != "" && /^[ \t]*- id:/ { count[section]++ }
    END {
      print "positions " (count["positions"] + 0)
      print "phases " (count["phases"] + 0)
      print "triggers " (count["triggers"] + 0)
    }
  '
}

# The document with its line breaks flattened. A sentence the editor wrapped
# is still one sentence to a matcher, and the two twins have to be looking at
# the same sentence -- so both of them flatten it the same way.
README_FLAT=$(tr '\n' ' ' < "$README")

# One of the collective's numbers: the count the vocabulary file has, and the
# sentences that state it. Every sentence has to state the file's number, and
# every sentence has to be there at all -- a sentence that is gone is a number
# that nothing checks any more.
#
# A sentence is named by where it is, and its pattern is the words around the
# number rather than the noun itself. The gap between the words and the number
# is anything that is not a digit: the multiplication sign in the row and the
# line break in the bullet are both gaps, and a matcher that understood only
# one byte of a sign would miss the sentence and call it unstated.
check_collective_claim() {
  local label="$1" expected="$2"
  shift 2
  local spec sentence pattern matched number matches places=0 unit problems=''
  for spec in "$@"; do
    sentence="${spec%%|*}"
    pattern="${spec#*|}"
    matches=0
    number=''
    while IFS= read -r matched; do
      [ -n "$matched" ] || continue
      matches=$((matches + 1))
      if [[ "$matched" =~ $pattern ]]; then
        number="${BASH_REMATCH[1]}"
      fi
    done <<< "$(printf '%s\n' "$README_FLAT" | grep -oE "$pattern" || true)"
    if [ "$matches" -eq 0 ]; then
      problems="${problems}the document does not state it in ${sentence}
"
    elif [ "$matches" -gt 1 ]; then
      problems="${problems}the document states it more than once in ${sentence}
"
    elif [ "$number" != "$expected" ]; then
      problems="${problems}the tree has ${expected}, the document says ${number} in ${sentence}
"
    fi
    places=$((places + 1))
  done
  if [ -n "$problems" ]; then
    while IFS= read -r problem; do
      [ -n "$problem" ] || continue
      fail "$(printf '%-20s %s: %s' 'Collective' "$label" "$problem")"
    done <<< "$problems"
    return
  fi
  unit="sentences"
  if [ "$places" -eq 1 ]; then
    unit="sentence"
  fi
  printf '  ok      %-20s %s: %s (stated in %s %s)\n' \
    'Collective' "$label" "$expected" "$places" "$unit"
}

COLLECTIVE_COUNTS=$(collective_counts)
COLLECTIVE_POSITIONS=0
COLLECTIVE_PHASES=0
COLLECTIVE_TRIGGERS=0
while read -r name number; do
  case "$name" in
    positions) COLLECTIVE_POSITIONS="$number" ;;
    phases)    COLLECTIVE_PHASES="$number" ;;
    triggers)  COLLECTIVE_TRIGGERS="$number" ;;
  esac
done <<< "$COLLECTIVE_COUNTS"

check_collective_claim "Positions" "$COLLECTIVE_POSITIONS" \
  'the row of the three layers|communicative whole[^0-9]+([0-9]+) positions' \
  'the feature bullet|Society layer, with its ([0-9]+) positions,' \
  'the vocabulary sentence|collective.s ([0-9]+) positions,'

check_collective_claim "Phases" "$COLLECTIVE_PHASES" \
  'the row of the three layers|communicative whole[^0-9]+[0-9]+ positions[^0-9]+([0-9]+) phases' \
  'the feature bullet|Society layer, with its [0-9]+ positions,[^0-9]+[0-9]+ transitions and ([0-9]+)[^0-9]+phases' \
  'the vocabulary sentence|collective.s [0-9]+ positions, ([0-9]+) phases'

check_collective_claim "Triggers" "$COLLECTIVE_TRIGGERS" \
  'the vocabulary sentence|collective.s [0-9]+ positions, [0-9]+ phases and ([0-9]+) triggers'

# --- the hooks ---------------------------------------------------------------
#
# The repository ships a git hook, and a hook the README does not mention is a
# hook a reader never finds. The files in .githooks are derived from the
# tree, the paths the README names are derived from the document, and the two
# sets have to be the same.

tree_hooks() {
  find .githooks -maxdepth 1 -type f -print 2>/dev/null \
    | sed -E 's|^\./||; s|^\.githooks/||' | LC_ALL=C sort -u
}

doc_hooks() {
  grep -oE '\.githooks/[A-Za-z0-9_.-]+' "$README" \
    | sed -E 's|^\.githooks/||' | LC_ALL=C sort -u || true
}

TREE_HOOKS=$(tree_hooks)
DOC_HOOKS=$(doc_hooks)

if [ -z "$TREE_HOOKS" ]; then
  fail "$(printf '%-20s the tree has no hooks to name' 'Git hooks')"
elif same_members "$TREE_HOOKS" "$DOC_HOOKS"; then
  printf '  ok      %-20s %s\n' 'Git hooks' "$(printf '%s\n' "$TREE_HOOKS" | grep -c .)"
else
  fail "$(printf '%-20s the tree has [%s], the document names [%s]' \
    'Git hooks' \
    "$(printf '%s\n' "$TREE_HOOKS" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$DOC_HOOKS" | tr '\n' ' ' | sed -e 's/ *$//')")"
fi

echo ""
if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES claim(s) in README.md do not match the tree."
  echo "*** FAIL ***"
  echo ""
  echo "The document states a claim and the tree has another. Fix the document,"
  echo "or fix the tree -- but make the two agree before saying anything about"
  echo "either of them."
  exit 1
fi
echo "Every claim in README.md matches the tree."
exit 0
