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
# There are three kinds of claim here now, and each is checked in the way
# that fits it:
#
# The NUMBERS -- the test, mutation, anchor and gate counts -- are read out
# of the document and compared with counts derived from the tree.
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
