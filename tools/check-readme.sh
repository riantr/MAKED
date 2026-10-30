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

# --- the project structure map -----------------------------------------------
#
# The map is a drawing of the tree, and it is read here once: the listing
# itself, and the entries of it that name test files.
#
# The drawing's own characters are not ASCII, so the map is read by the shape
# of its TEXT: the name of an entry is what follows the drawing, and the
# comment on it is what follows the hash.
LISTING=$(awk '
  /^## Project Structure/ { inside = 1; next }
  inside && /^```/ {
    if (inblock) { exit }
    inblock = 1
    next
  }
  inblock { print }
' "$README")

# The entries of the map that name test files: "scope<TAB>name<TAB>count".
#
# The scope is the name of the directory the map puts the entry in, and the
# count is the number of tests the entry claims.  An entry that claims no
# count has an empty count, and the gate says so.
#
# A glob is a name too: "*_test.mbt" names every file of that shape in the
# directory the entry sits in.
doc_test_entries() {
  awk '
    {
      line = $0
      # the name is the first word after the drawing
      sub(/^[^A-Za-z0-9_*]+/, "", line)
      if (line == "") next
      # the comment is what follows the hash
      hash = index(line, "#")
      if (hash > 0) {
        comment = substr(line, hash + 1)
        line = substr(line, 1, hash - 1)
      } else {
        comment = ""
      }
      sub(/[ \t]+$/, "", line)
      split(line, parts, /[ \t]+/)
      name = parts[1]
      if (name == "") next
      # a directory is the scope of the entries that follow it
      if (name ~ /\/$/) {
        sub(/\/$/, "", name)
        scope = name
        next
      }
      # only the entries that name test files are read
      if (name !~ /test\.mbt$/) next
      count = ""
      if (match(comment, /[0-9]+[ \t]+tests/)) {
        count = substr(comment, RSTART, RLENGTH)
        sub(/[ \t].*$/, "", count)
      }
      print scope "\t" name "\t" count
    }
  ' <<< "$LISTING"
}

# The tree's files of tests: "scope<TAB>name<TAB>count".
#
# A file of tests is a file whose name ends in "_test.mbt" or "_wbtest.mbt".
# The scope is the name of the directory the file is in -- the name, and not
# the path, because the map names its directories by their own name too.
code_test_files() {
  local files
  files=$(git ls-files 2>/dev/null | grep -E '(_test|_wbtest)\.mbt$')
  [ -n "$files" ] || return
  # The files are read by awk, so that awk can say which file a test block is
  # in.  The paths carry no spaces, so they are passed as they are.
  awk '
    FNR == 1 {
      if (NR > 1) print scope "\t" name "\t" n
      path = FILENAME
      name = path
      sub(/^.*\//, "", name)
      scope = ""
      if (path ~ /\//) {
        scope = path
        sub(/\/[^\/]*$/, "", scope)
        sub(/^.*\//, "", scope)
      }
      n = 0
    }
    /^[ \t]*(async[ \t]+)?test[ \t]+"[^"]*"[ \t]*\{/ { n++ }
    END { if (NR > 0) print scope "\t" name "\t" n }
  ' $files
}

# The total the map states for one directory.
#
# The map may name a directory's tests in more than one group -- the blackbox
# files and the whitebox ones -- and the total is the sum of the groups.
listing_scope_total() {
  local want="$1" testScope testName testStated total=0 found=0
  while IFS=$'\t' read -r testScope testName testStated; do
    [ "$testScope" = "$want" ] || continue
    [ -n "$testStated" ] || continue
    total=$((total + testStated))
    found=1
  done <<< "$DOC_TEST_ENTRIES"
  [ "$found" -eq 1 ] || return
  printf '%s' "$total"
}

DOC_TEST_ENTRIES=$(doc_test_entries)
CODE_TEST_FILES=$(code_test_files)

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
  "$(listing_scope_total backend)"

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
# The listing itself was read above, with the rest of the map: the count
# table's "Backend tests" row is checked against it, and the map's own groups
# of test files are checked below.
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

# --- the test files the map names --------------------------------------------
#
# The map is a map of the tree, and the files of tests are part of the tree.
# The map states how many tests each group of test files holds, and the group
# is the name it writes -- a glob for the blackbox files, a glob for the
# whitebox ones.
#
# Nothing watched that.  The measurement: the backend's group was given a
# second entry of its own that held no tests at all, the total the map states
# for the backend stayed the same, and not one gate went red.  The map can
# say anything at all about a group, and a file of tests can be missing from
# the map entirely -- and the two whitebox test files were.
#
# The claim is read by its own shape.  An entry of the map that names test
# files -- a name that ends in "test.mbt", a glob or not -- states how many
# tests those files hold, and the number is the tree's.  The files an entry
# covers are the tree's files of tests in the directory the map puts the entry
# in, whose name the entry's own name matches.
#
# The count table's row is checked against the map's total as well, so the two
# places the document states the backend's total keep agreeing.

TEST_FILES_BAD=0
TEST_FILES_CHECKED=0

# Does a name of the map cover the name of a file?  A glob covers every name
# it matches.
entry_covers() {
  local name="$1" base="$2" pattern
  if [ "$name" = "$base" ]; then
    return 0
  fi
  case "$name" in
    *\**) ;;
    *) return 1 ;;
  esac
  pattern=$(printf '%s' "$name" | sed -e 's/[^A-Za-z0-9_*]/\\&/g' -e 's/\*/.*/g')
  [[ "$base" =~ ^$pattern$ ]]
}

# One group of the map, checked against the files it covers.
check_test_group() {
  local testScope="$1" testName="$2" testStated="$3"
  local testDir testBase testHeld total=0
  while IFS=$'\t' read -r testDir testBase testHeld; do
    [ "$testDir" = "$testScope" ] || continue
    entry_covers "$testName" "$testBase" || continue
    total=$((total + testHeld))
  done <<< "$CODE_TEST_FILES"
  TEST_FILES_CHECKED=$((TEST_FILES_CHECKED + 1))
  if [ -z "$testStated" ]; then
    fail "$(printf '%-20s the map says nothing about how many tests %s holds' \
      'Test files' "$testName")"
    TEST_FILES_BAD=1
  elif [ "$testStated" != "$total" ]; then
    fail "$(printf '%-20s the map says %s holds %s tests, the tree has %s' \
      'Test files' "$testName" "$testStated" "$total")"
    TEST_FILES_BAD=1
  fi
}

# Every file of tests the map does not name.
check_test_file_named() {
  local testDir="$1" testBase="$2" testScope testName testStated covered=0
  while IFS=$'\t' read -r testScope testName testStated; do
    [ "$testScope" = "$testDir" ] || continue
    if entry_covers "$testName" "$testBase"; then
      covered=1
    fi
  done <<< "$DOC_TEST_ENTRIES"
  if [ "$covered" -eq 0 ]; then
    fail "$(printf '%-20s the map does not name %s/%s' \
      'Test files' "$testDir" "$testBase")"
    TEST_FILES_BAD=1
  fi
}

if [ -z "$DOC_TEST_ENTRIES" ]; then
  fail "$(printf '%-20s the map names no file of tests' 'Test files')"
  TEST_FILES_BAD=1
else
  while IFS=$'\t' read -r testScope testName testStated; do
    [ -n "$testName" ] || continue
    check_test_group "$testScope" "$testName" "$testStated"
  done <<< "$DOC_TEST_ENTRIES"
  while IFS=$'\t' read -r testDir testBase testHeld; do
    [ -n "$testBase" ] || continue
    check_test_file_named "$testDir" "$testBase"
  done <<< "$CODE_TEST_FILES"
fi

if [ "$TEST_FILES_BAD" -eq 0 ]; then
  printf '  ok      %-20s %s groups, all accounted for\n' 'Test files' "$TEST_FILES_CHECKED"
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

# --- the slots the examples agree on -----------------------------------------
#
# The README shows a machine and a mapping table, and a reader copies both.
# The server refuses a table that drives a slot the machine does not have --
# "a rule that names a slot the running machine does not have is refused at
# start-up" -- so the two examples have to fit each other, or the reader is
# refused by the very rule the document quotes.
#
# Nothing watched it.  The measurement: the example table's fallback was
# pointed at a slot that nothing in the document defines, and all four gate
# suites went on saying that every claim in the documents matches the tree.
#
# The claim is read by its own shape.  The machine is the fenced block that
# carries the model's format, and the slots it defines are the ids in its
# "slots" array.  The table is the fenced block that carries the mapping
# table's format, and the slots it drives are the ones its rules name -- the
# fallback's slot among them.
#
# The comparison is the one the docs pair already holds the shipped pair to:
# the example machine's slots and the example table's slots are the same set.
# The server refuses a table that drives a slot the machine does not have,
# and a slot the table never reaches is an example that does not fit itself
# -- so both halves have to name the same slots.

# The slots the example machine defines.
doc_example_slots() {
  awk '
    /^```/ {
      if (inblock) {
        inblock = 0; kind = ""; inslots = 0
        next
      }
      inblock = 1; kind = ""; inslots = 0
      next
    }
    inblock {
      if ($0 ~ /maked\.model\.v1/) kind = "model"
      if (kind != "model") next
      if ($0 ~ /"slots"/) { inslots = 1; next }
      if (inslots && $0 ~ /^\s*\]/) { inslots = 0; next }
      if (inslots && match($0, /"id": "[^"]+"/)) {
        s = substr($0, RSTART, RLENGTH)
        sub(/^"id": "/, "", s)
        sub(/"$/, "", s)
        print s
      }
    }
  ' "$README" | LC_ALL=C sort -u
}

# The slots the example table drives.
doc_example_table_slots() {
  awk '
    /^```/ {
      if (inblock) {
        inblock = 0; kind = ""
        next
      }
      inblock = 1; kind = ""
      next
    }
    inblock {
      if ($0 ~ /maked\.research\.v1/) kind = "research"
      if (kind != "research") next
      if (match($0, /slot: [A-Za-z0-9_]+/)) {
        s = substr($0, RSTART, RLENGTH)
        sub(/^slot: /, "", s)
        print s
      }
    }
  ' "$README" | LC_ALL=C sort -u
}

EXAMPLE_SLOTS=$(doc_example_slots)
EXAMPLE_TABLE_SLOTS=$(doc_example_table_slots)
EXAMPLE_SLOT_BAD=0
EXAMPLE_SLOT_CHECKED=0
if [ -z "$EXAMPLE_TABLE_SLOTS" ]; then
  fail "$(printf '%-20s the example table drives no slot at all' 'Example slots')"
  EXAMPLE_SLOT_BAD=1
elif ! same_members "$EXAMPLE_SLOTS" "$EXAMPLE_TABLE_SLOTS"; then
  fail "$(printf '%-20s the example machine says [%s], the example table says [%s]' \
    'Example slots' \
    "$(printf '%s\n' "$EXAMPLE_SLOTS" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$EXAMPLE_TABLE_SLOTS" | tr '\n' ' ' | sed -e 's/ *$//')")"
  EXAMPLE_SLOT_BAD=1
else
  EXAMPLE_SLOT_CHECKED=$(printf '%s\n' "$EXAMPLE_SLOTS" | grep -c . || true)
fi
if [ "$EXAMPLE_SLOT_BAD" -eq 0 ]; then
  printf '  ok      %-20s %s slots, the machine and the table agree\n' \
    'Example slots' "$EXAMPLE_SLOT_CHECKED"
fi

# --- the record the document shows ---------------------------------------------
#
# The workspace is the one part of the server a reader is meant to change, and the
# README shows a record going in. The server reads three fields and writes two
# of its own, and a record whose field names are wrong is the quietest failure
# in the project: the server does not refuse it, it stores an empty body and
# answers 201, and the reader is left with a record that lost what they wrote.
#
# Nothing watched it. The measurement: the document was given a record with a
# field the server does not read, and the server was given a field the
# document does not send, and all four gate suites went on saying that every
# claim in the documents matches the tree.
#
# The claim is read by its own shape. The tree's claim is the function that
# reads a submitted record, and the constants that say how long a title and a
# body may be. The document's claim is the block that posts a record, and the
# sentence that says what the server refuses.
#
# The comparison is by MEMBERSHIP: the order the fields are written in says
# nothing, and a message that differs between the twins is a message nobody
# can trust.

# The fields the server reads out of a submitted record.
code_entry_fields() {
  awk '
    /^pub fn Entry::from_json/ { inside = 1; next }
    inside && /^}/ { inside = 0 }
    inside {
      line = $0
      while (match(line, /json_string\(json, "[^"]+"\)/)) {
        s = substr(line, RSTART, RLENGTH)
        sub(/^json_string\(json, "/, "", s)
        sub(/"\).*$/, "", s)
        print s
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' backend/entries.mbt | LC_ALL=C sort -u
}

# The domain letters a record may carry.
code_entry_domains() {
  awk '
    /^pub fn entry_domains\(\)/ { inside = 1; next }
    inside && /^}/ { inside = 0 }
    inside {
      line = $0
      while (match(line, /"[A-Z]"/)) {
        print substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' backend/entries.mbt | LC_ALL=C sort -u
}

# The limits a title and a body are held to.
code_entry_limits() {
  awk '
    /^pub const MAX_ENTRY_[A-Z]+ : Int32 = / {
      name = $0
      sub(/^pub const MAX_ENTRY_/, "", name)
      sub(/ .*$/, "", name)
      n = $0
      sub(/.*= /, "", n)
      print tolower(name) " " n
    }
  ' backend/entries.mbt
}

# The block that posts a record: the fenced block that names the route.
doc_entry_block() {
  awk '
    /^```/ {
      if (inblock) {
        if (block ~ /\/api\/entries/) print block
        inblock = 0
        block = ""
      } else {
        inblock = 1
        block = ""
      }
      next
    }
    inblock { block = block $0 "\n" }
  ' "$README"
}

# The fields the document's record sends.
doc_entry_fields() {
  doc_entry_block \
    | grep -oE '"[a-z_]+":' \
    | sed -E 's/^"//; s/":$//' \
    | LC_ALL=C sort -u
}

# The domain the document's record carries.
doc_entry_domain() {
  doc_entry_block \
    | grep -oE '"domain": "[^"]*"' \
    | sed -E 's/^"domain": "//; s/"$//' \
    | head -1
}

# The limits the document says a record is refused over.
doc_entry_limits() {
  local title body
  title=$(grep -oE 'the title is longer than [0-9,]+' "$README" | head -1 | grep -oE '[0-9,]+$')
  body=$(grep -oE 'the body is longer than [0-9,]+' "$README" | head -1 | grep -oE '[0-9,]+$')
  printf 'title %s\n' "$(printf '%s' "$title" | tr -d ,)"
  printf 'body %s\n' "$(printf '%s' "$body" | tr -d ,)"
}

CODE_ENTRY_FIELDS=$(code_entry_fields)
CODE_ENTRY_DOMAINS=$(code_entry_domains)
CODE_ENTRY_LIMITS=$(code_entry_limits)
DOC_ENTRY_FIELDS=$(doc_entry_fields)
DOC_ENTRY_DOMAIN=$(doc_entry_domain)
DOC_ENTRY_LIMITS=$(doc_entry_limits)
ENTRY_RECORD_BAD=0
ENTRY_RECORD_CLAIMS=0
if [ -z "$CODE_ENTRY_FIELDS" ]; then
  fail "$(printf '%-20s no field could be derived from the server' 'Entry record')"
  ENTRY_RECORD_BAD=1
elif [ -z "$DOC_ENTRY_FIELDS" ]; then
  fail "$(printf '%-20s the document sends no record at all' 'Entry record')"
  ENTRY_RECORD_BAD=1
elif ! same_members "$CODE_ENTRY_FIELDS" "$DOC_ENTRY_FIELDS"; then
  fail "$(printf '%-20s the server reads [%s], the document sends [%s]' \
    'Entry record' \
    "$(printf '%s\n' "$CODE_ENTRY_FIELDS" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$DOC_ENTRY_FIELDS" | tr '\n' ' ' | sed -e 's/ *$//')")"
  ENTRY_RECORD_BAD=1
else
  ENTRY_RECORD_CLAIMS=$((ENTRY_RECORD_CLAIMS + 1))
fi
if [ "$ENTRY_RECORD_BAD" -eq 0 ]; then
  if [ -z "$DOC_ENTRY_DOMAIN" ]; then
    fail "$(printf '%-20s the document sends no domain at all' 'Entry record')"
    ENTRY_RECORD_BAD=1
  elif ! printf '%s\n' "$CODE_ENTRY_DOMAINS" | grep -qxF "$DOC_ENTRY_DOMAIN"; then
    fail "$(printf '%-20s the document sends the domain %s, which is not one of [%s]' \
      'Entry record' "$DOC_ENTRY_DOMAIN" \
      "$(printf '%s\n' "$CODE_ENTRY_DOMAINS" | tr '\n' ' ' | sed -e 's/ *$//')")"
    ENTRY_RECORD_BAD=1
  else
    ENTRY_RECORD_CLAIMS=$((ENTRY_RECORD_CLAIMS + 1))
  fi
fi
if [ "$ENTRY_RECORD_BAD" -eq 0 ]; then
  ENTRY_LIMIT_BAD=0
  while IFS=' ' read -r what limit; do
    [ -n "$what" ] || continue
    tree_limit=$(printf '%s\n' "$CODE_ENTRY_LIMITS" | grep "^$what " | head -1 | cut -d' ' -f2)
    doc_limit=$(printf '%s\n' "$DOC_ENTRY_LIMITS" | grep "^$what " | head -1 | cut -d' ' -f2)
    if [ -z "$tree_limit" ] || [ -z "$doc_limit" ]; then
      fail "$(printf '%-20s the %s limit is not stated on both sides' 'Entry record' "$what")"
      ENTRY_LIMIT_BAD=1
      break
    fi
    if [ "$tree_limit" != "$doc_limit" ]; then
      fail "$(printf '%-20s the %s limit is %s, the document says %s' \
        'Entry record' "$what" "$tree_limit" "$doc_limit")"
      ENTRY_LIMIT_BAD=1
      break
    fi
    ENTRY_RECORD_CLAIMS=$((ENTRY_RECORD_CLAIMS + 1))
  done <<< "$CODE_ENTRY_LIMITS"
  if [ "$ENTRY_LIMIT_BAD" -eq 1 ]; then
    ENTRY_RECORD_BAD=1
  fi
fi
if [ "$ENTRY_RECORD_BAD" -eq 0 ]; then
  printf '  ok      %-20s %s claims\n' 'Entry record' "$ENTRY_RECORD_CLAIMS"
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

# --- the commands the document names -------------------------------------------
#
# The README's first commands are the ones a reader runs before anything
# else: `moon run --release --target native cmd/server`, and the same for
# the agent's server. A command that names a package the tree does not have
# fails on the first try, with an error about a directory that is not there.
#
# The packages are the ones under cmd/ that carry a manifest of their own.
# The document may name fewer of them than there are -- the browser app is
# served by the same process as the API and has no command of its own -- but
# every package it names has to be there.

code_cmd_packages() {
  for dir in cmd/*/; do
    [ -f "${dir}moon.pkg" ] || continue
    printf '%s\n' "${dir%/}"
  done | LC_ALL=C sort -u
}

# The command packages the README names.
doc_cmd_packages() {
  grep -oE 'cmd/[a-z][a-z0-9_-]*' "$README" | LC_ALL=C sort -u || true
}

CODE_CMDS=$(code_cmd_packages)
DOC_CMDS=$(doc_cmd_packages)
if [ -z "$CODE_CMDS" ]; then
  fail "$(printf '%-20s no command package could be derived from the tree' 'Commands')"
elif [ -z "$DOC_CMDS" ]; then
  fail "$(printf '%-20s the document names no command' 'Commands')"
else
  MISSING_CMD=""
  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    if ! printf '%s\n' "$CODE_CMDS" | grep -qxF "$pkg"; then
      MISSING_CMD="$MISSING_CMD $pkg"
    fi
  done <<< "$DOC_CMDS"
  if [ -n "$MISSING_CMD" ]; then
    fail "$(printf '%-20s the document names commands the tree does not have:%s' \
      'Commands' "$MISSING_CMD")"
  else
    printf '  ok      %-20s %s\n' 'Commands' "$(printf '%s\n' "$DOC_CMDS" | grep -c .)"
  fi
fi

# --- the compile targets the document states ---------------------------------
#
# The first commands in the README are the ones a reader runs before anything
# else: `moon run --release --target native cmd/server`, and the same for the
# agent's server. A target the package does not declare fails on the first
# try, with an error from the toolchain -- and not a word from the document
# that sent them there.
#
# The claim is read by its own shape. The target is the argument of
# "--target", and the package is the path that follows it. A path that names a
# file is the package that holds the file. A command with no package after the
# target speaks for the module, and the module declares its own targets.
#
# The packages are the tree's own: a directory that carries a manifest. The
# targets are the five the toolchain knows.

# The targets each package of the tree declares: "pkg=targets".
PKG_TARGETS=""
code_pkg_targets() {
  local file pkg value
  PKG_TARGETS=""
  for file in $(git ls-files 2>/dev/null | grep -E '(^|/)moon\.pkg$'); do
    case "$file" in
      */*) pkg="${file%/moon.pkg}" ;;
      *) continue ;;
    esac
    value=$(grep -oE 'supported_targets[[:space:]]*=[[:space:]]*"[^"]*"' "$file" 2>/dev/null \
      | head -1 | sed -E 's/.*"([^"]*)".*/\1/')
    [ -n "$value" ] || continue
    PKG_TARGETS="$PKG_TARGETS $pkg=$value"
  done
}

# The targets the module declares.
MODULE_TARGETS=""
module_targets() {
  MODULE_TARGETS=$(grep -oE 'supported_targets[[:space:]]*=[[:space:]]*"[^"]*"' moon.mod 2>/dev/null \
    | head -1 | sed -E 's/.*"([^"]*)".*/\1/')
}

# The targets one package declares.
PKG_TARGET=""
pkg_target() {
  local want="$1" item name value
  PKG_TARGET=""
  for item in $PKG_TARGETS; do
    name="${item%%=*}"
    value="${item#*=}"
    if [ "$name" = "$want" ]; then
      PKG_TARGET="$value"
      return
    fi
  done
}

# Is a target one of the ones a set declares? The sets are written with a
# plus: "js+native" is two targets.
#
# "all" is the toolchain's own word for every target a scope supports, so a
# scope that declares one target declares "all" as well.
pkg_has_target() {
  local declared="$1" want="$2" part
  if [ "$want" = "all" ]; then
    [ -n "$declared" ] && return 0
    return 1
  fi
  for part in ${declared//+/ }; do
    if [ "$part" = "$want" ]; then
      return 0
    fi
  done
  return 1
}

# The package a path names: the path itself when it carries a manifest, and
# the directory that carries it when the path names a file.
PATH_PACKAGE=""
path_package() {
  local path="$1" dir
  PATH_PACKAGE=""
  [ -n "$path" ] || return
  dir="$path"
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if [ -f "$dir/moon.pkg" ]; then
      PATH_PACKAGE="$dir"
      return
    fi
    case "$dir" in
      */*) dir="${dir%/*}" ;;
      *) dir="" ;;
    esac
  done
}

# The claims the document makes about a target: "line target path", one for
# every "--target <target>" the document states. The path is the token that
# follows the target, and it is empty when the command names no package.
#
# A comment is not part of the command: "moon check --target native  #
# type-check the backend" states a target for the module, and the words after
# the "#" are a note about it.
doc_target_claims() {
  local lineno=0 line text rest target path
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    text="${line%%#*}"
    rest="$text"
    while [[ "$rest" == *"--target "* ]]; do
      rest="${rest#*--target }"
      target="${rest%%[[:space:]]*}"
      rest="${rest#"$target"}"
      case "$target" in
        wasm-gc|wasm|native|js|all) ;;
        *) continue ;;
      esac
      # The package is the next word, and only the path characters of it.
      rest="${rest#"${rest%%[![:space:]]*}"}"
      path="${rest%%[[:space:]]*}"
      if [[ "$path" =~ ^([A-Za-z0-9_./-]+) ]]; then
        path="${BASH_REMATCH[1]}"
      else
        path=""
      fi
      printf '%s\t%s\t%s\n' "$lineno" "$target" "$path"
    done
  done < "$README"
}

code_pkg_targets
module_targets

TARGET_CLAIMS=0
TARGET_BAD=0
while IFS=$'\t' read -r line target path; do
  [ -n "$target" ] || continue
  if [ -n "$path" ]; then
    path_package "$path"
    [ -n "$PATH_PACKAGE" ] || continue
    pkg_target "$PATH_PACKAGE"
    [ -n "$PKG_TARGET" ] || continue
    declared="$PKG_TARGET"
    scope="$PATH_PACKAGE"
  else
    [ -n "$MODULE_TARGETS" ] || continue
    declared="$MODULE_TARGETS"
    scope="the module"
  fi
  TARGET_CLAIMS=$((TARGET_CLAIMS + 1))
  if ! pkg_has_target "$declared" "$target"; then
    fail "$(printf '%-20s %s line %s says %s is built for %s, but the tree says %s' \
      'Compile target' "$README" "$line" "$scope" "$target" "$declared")"
    TARGET_BAD=1
  fi
done <<< "$(doc_target_claims)"

if [ -z "$PKG_TARGETS" ]; then
  fail "$(printf '%-20s no package target could be derived from the tree' 'Compile target')"
elif [ "$TARGET_CLAIMS" -eq 0 ]; then
  fail "$(printf '%-20s the document states no compile target at all' 'Compile target')"
elif [ "$TARGET_BAD" -eq 0 ]; then
  printf '  ok      %-20s %s claims\n' 'Compile target' "$TARGET_CLAIMS"
fi

# --- the platforms the document labels a package with ------------------------
#
# The README labels the packages with the platform they are built for: the
# backend package is native, the frontend package is js. A label the package
# does not carry sends a reader to the wrong platform.
#
# The claim is read by its own shape: a path that names a package, and a
# platform in parentheses on the same line. The path comes before the label,
# and it is a path -- it carries a slash.
#
# The platform qualifies one of two paths, and the two are read one at a
# time. A path that comes right before the parentheses qualifies them, as in
# "`riantr/MAKED/backend` (native". And a path in a line that has a comment
# qualifies a platform in that comment, as in "backend/   # the loop (native)".
#
# The paths are the tree's own, and a path may carry the module's name in
# front of it: "riantr/MAKED/backend" is the package "backend".

# The module's name, so that a path may carry it in front.
MODULE_NAME=""
module_name() {
  MODULE_NAME=$(grep -oE '^name[[:space:]]*=[[:space:]]*"[^"]*"' moon.mod 2>/dev/null \
    | head -1 | sed -E 's/.*"([^"]*)".*/\1/')
}

# The package a labelled path names: the module's name is taken off the front
# and a trailing slash off the end, and the rest is a path of the tree.
LABEL_PACKAGE=""
label_package() {
  local path="$1"
  LABEL_PACKAGE=""
  [ -n "$path" ] || return
  case "$path" in
    "$MODULE_NAME"/*) path="${path#"$MODULE_NAME"/}" ;;
  esac
  path="${path%/}"
  path_package "$path"
  LABEL_PACKAGE="$PATH_PACKAGE"
}

# The path a label names, in the text before it: the last word of that text,
# and the path at the end of that word.
#
# The path is the trailing run of path characters, because a graph writes it
# inside a quoted label: label="backend/ (native)".
LABEL_PATH=""
label_path() {
  local text="$1" word path
  LABEL_PATH=""
  if [[ "$text" =~ ^(.*[^[:space:]])?[[:space:]]*$ ]]; then
    text="${BASH_REMATCH[1]}"
  fi
  [ -n "$text" ] || return
  if [[ "$text" =~ ([^[:space:]]+)$ ]]; then
    word="${BASH_REMATCH[1]}"
  else
    return
  fi
  # The backticks are the tree's own quoting, and they are not part of the
  # path.
  word="${word//\`/}"
  if [[ "$word" =~ ([A-Za-z0-9_./-]+)$ ]]; then
    path="${BASH_REMATCH[1]}"
  else
    return
  fi
  case "$path" in
    */*) LABEL_PATH="$path" ;;
  esac
}

# The claims the document makes about a platform: "line package platform".
doc_platform_claims() {
  local lineno=0 line scan match platform prefix path
  local re='\((wasm-gc|wasm|native|js|all)([^A-Za-z0-9_-]|$)'
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    scan="$line"
    while [[ "$scan" =~ $re ]]; do
      match="${BASH_REMATCH[0]}"
      platform="${BASH_REMATCH[1]}"
      prefix="${scan%%"$match"*}"
      if [[ "$prefix" == *"#"* ]]; then
        # The label is in a comment, and the path is the one before it.
        label_path "${prefix%%#*}"
      else
        label_path "$prefix"
      fi
      path="$LABEL_PATH"
      if [ -n "$path" ]; then
        label_package "$path"
        if [ -n "$LABEL_PACKAGE" ]; then
          printf '%s\t%s\t%s\n' "$lineno" "$LABEL_PACKAGE" "$platform"
        fi
      fi
      scan="${scan#*"$match"}"
    done
  done < "$README"
}

module_name

PLATFORM_CLAIMS=0
PLATFORM_BAD=0
while IFS=$'\t' read -r line pkg platform; do
  [ -n "$platform" ] || continue
  pkg_target "$pkg"
  [ -n "$PKG_TARGET" ] || continue
  PLATFORM_CLAIMS=$((PLATFORM_CLAIMS + 1))
  if ! pkg_has_target "$PKG_TARGET" "$platform"; then
    fail "$(printf '%-20s %s line %s labels %s as %s, but the tree says %s' \
      'Package platform' "$README" "$line" "$pkg" "$platform" "$PKG_TARGET")"
    PLATFORM_BAD=1
  fi
done <<< "$(doc_platform_claims)"

if [ "$PLATFORM_CLAIMS" -eq 0 ]; then
  fail "$(printf '%-20s the document labels no package with a platform' 'Package platform')"
elif [ "$PLATFORM_BAD" -eq 0 ]; then
  printf '  ok      %-20s %s claims\n' 'Package platform' "$PLATFORM_CLAIMS"
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

# --- the method a document names next to a path --------------------------------
#
# The README names a method and a path together in its prose -- "GET
# /api/loop/status" -- and the gate above holds the PATH.  The METHOD was not
# held at all: a README that said "POST /api/model" would have gone unnoticed,
# and a reader writing a client against the document would have posted to a
# route the server only answers with a GET.
#
# The tree is the source: the routes the server registers, and the method each
# one is registered under.  A path can be registered under more than one method
# -- /api/entries is a GET and a POST -- so the method is part of the route and
# not a decoration on the path.
#
# The claim is found by its own shape: a method, and a path that starts with
# /api/.  The path may carry a query ("?lang=zh"), a concrete value where the
# tree has a parameter ("/api/pages/model"), or a star that names a family
# ("/api/loop/*").  Each of those is a claim about a route, and each of them is
# held to the tree.
#
# The comparison is one way: the document names the routes a reader is meant to
# call, and the server may serve more.
#
# The gate prints the SET the document names and not its size: a count cannot
# see two twins reading two different sets of the same size.

# The methods the document names next to a path, as "METHOD path".
#
# The URL of a command is not part of the claim -- "POST
# http://127.0.0.1:8080/api/entries" is a claim about the method and the path,
# and the host it names is the reader's, not the server's -- so the host is
# taken off before the claim is read.
doc_api_methods() {
  grep -oE '(GET|POST|PUT|DELETE|PATCH)(\|(GET|POST|PUT|DELETE|PATCH))*[[:space:]]+(https?://[^/[:space:]`"\\]*)?/api/[A-Za-z0-9_:/.~*-]+' "$README" \
    | sed -E -e 's#https?://[^/[:space:]`"\\]*##' -e 's/[[:space:]]+/ /' -e 's/\.$//' \
    | awk '{
        n = split($1, ms, /\|/);
        path = $2;
        for (i = 1; i <= n; i++) if (ms[i] != "") print ms[i], path;
      }' \
    | LC_ALL=C sort -u
}

# The methods the tree serves at a path.  A path that ends in a star names a
# family, and a family is served by the routes under it.
api_methods_at() {
  local path="$1" route rmethod rpath
  local family=0 prefix="$path"
  case "$path" in
    *'*') family=1; prefix="${path%\*}"; prefix="${prefix%/}" ;;
    */) family=1; prefix="${prefix%/}" ;;
  esac
  while IFS= read -r route; do
    [ -n "$route" ] || continue
    rmethod="${route%% *}"
    rpath="${route#* }"
    if [ "$family" -eq 1 ]; then
      case "$rpath" in
        "$prefix"|"$prefix"/*) printf '%s\n' "$rmethod" ;;
      esac
    elif [[ "$path" =~ ^$(build_route_pattern "$route")$ ]]; then
      printf '%s\n' "$rmethod"
    fi
  done <<< "$TREE_ROUTES" | LC_ALL=C sort -u
}

DOC_API_METHODS=$(doc_api_methods)

API_METHODS_BAD=0
if [ -z "$DOC_API_METHODS" ]; then
  fail "$(printf '%-20s the document names no method next to a path' 'API methods')"
  API_METHODS_BAD=1
else
  while IFS= read -r claim; do
    [ -n "$claim" ] || continue
    method="${claim%% *}"
    path="${claim#* }"
    if ! api_methods_at "$path" | grep -qxF "$method"; then
      fail "$(printf '%-20s the document names [%s], and the tree serves that path with [%s]' \
        'API methods' "$claim" \
        "$(api_methods_at "$path" | tr '\n' ' ' | sed -e 's/ *$//' | sed -e 's/^$/nothing/')")"
      API_METHODS_BAD=1
    fi
  done <<< "$DOC_API_METHODS"
fi

if [ "$API_METHODS_BAD" -eq 0 ]; then
  printf '  ok      %-20s %s\n' 'API methods' \
    "$(printf '%s\n' "$DOC_API_METHODS" | tr '\n' ' ' | sed -e 's/ *$//')"
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

# --- what the release carries -------------------------------------------------
#
# The README says the agent's server is not in the published release
# artifacts: the release carries the web server and the browser bundle, and
# the agent's server is built from the repository.  The release workflow is
# what decides whether that server is shipped, so the workflow and the
# document have to say the same thing.
#
# The guide (AGENT.md) states the same claim and the docs pair watches that
# copy.  A claim stated in two places is a claim in two places, and the copy
# the other suite happens to read is not the copy this suite reads.
#
# The document's side is the negation, not the phrase.  A sentence that says
# the server IS in the release carries the same words as one that says it is
# not, and only the negation tells the two apart; a rule that looked for the
# phrase alone would read a document that says the opposite as a document that
# says nothing, and let the claim through.
RELEASE_BUILDS_MCP=$(grep -cE 'cmd/mcp' .github/workflows/publish.yml || true)
RELEASE_CLAIM_NOT=$(grep -oE 'not[^.]{0,8}in the published release artifacts' "$README" | grep -c . || true)
if [ "$RELEASE_BUILDS_MCP" -gt 0 ] && [ "$RELEASE_CLAIM_NOT" -gt 0 ]; then
  fail "$(printf '%-20s the document says the agent server is not released, and the release workflow builds it' \
    'Release claim')"
elif [ "$RELEASE_BUILDS_MCP" -eq 0 ] && [ "$RELEASE_CLAIM_NOT" -eq 0 ]; then
  fail "$(printf '%-20s the release workflow does not build the agent server, and the document does not say so' \
    'Release claim')"
else
  printf '  ok      %-20s %s\n' 'Release claim' 'not in the release'
fi

# --- the container image ------------------------------------------------------
#
# The README's `docker run` names the image the release publishes, and the
# publish workflow is what pushes it. The two have to be the same image: a
# reader who runs "docker run ghcr.io/riantr/maked:latest" against a
# registry that holds no such image gets a manifest error and no idea why.
#
# The workflow's tags are the source, and only the PATH of a tag is read.
# The workflow pushes the image under the release's own version and under
# "latest", so every tag it pushes is one a reader can ask for, and the
# tag in the document is not the thing that can be wrong. The path is: it
# has to be lower case, and it has to be the package the release pushed.

code_images() {
  awk '
    /ghcr\.io\// {
      line = $0
      gsub(/^[ \t]+/, "", line)
      gsub(/[ \t]+$/, "", line)
      sub(/:.*$/, "", line)
      print line
    }
  ' .github/workflows/publish.yml | LC_ALL=C sort -u
}

# The images the README names.
doc_images() {
  grep -oE 'ghcr\.io/[a-z0-9/_.-]+' "$README" | LC_ALL=C sort -u || true
}

CODE_IMAGES=$(code_images)
DOC_IMAGES=$(doc_images)
if [ -z "$CODE_IMAGES" ]; then
  fail "$(printf '%-20s no image could be derived from the workflow' 'Container image')"
elif [ -z "$DOC_IMAGES" ]; then
  fail "$(printf '%-20s the document names no image' 'Container image')"
elif same_members "$CODE_IMAGES" "$DOC_IMAGES"; then
  printf '  ok      %-20s %s\n' 'Container image' "$(printf '%s\n' "$CODE_IMAGES" | grep -c .)"
else
  fail "$(printf '%-20s the workflow says [%s], the document says [%s]' \
    'Container image' \
    "$(printf '%s\n' "$CODE_IMAGES" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$DOC_IMAGES" | tr '\n' ' ' | sed -e 's/ *$//')")"
fi

# --- the volume the container command names -----------------------------------
#
# The README's `docker run` mounts a volume, and that volume is where the
# reader's records live: the database is written into it, and it is what
# survives the container being replaced. A volume the tree does not have is a
# container that starts with an empty directory -- and a reader who finds out
# on the next restart.
#
# The tree's volumes are the ones docker-compose.yml declares: the mapping
# "name:path" under the service. The document's volume is the "-v name:path"
# of its container command.
#
# The comparison is ONE-WAY: the compose file may mount more than the
# document names, and every volume the document names has to be one the
# compose file mounts.

# The volume mappings the compose file declares, as "name:path".
code_volumes() {
  awk '
    /^[[:space:]]*volumes:[[:space:]]*$/ { inlist = 1; next }
    inlist && /^[[:space:]]*-[[:space:]]*[A-Za-z0-9_.-]+:[A-Za-z0-9_./-]+[[:space:]]*$/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      sub(/[[:space:]]*$/, "", line)
      print line
      next
    }
    inlist && /^[^[:space:]]/ { inlist = 0 }
  ' docker-compose.yml | LC_ALL=C sort -u
}

# The volume mappings the document's container command names.
doc_volumes() {
  grep -oE '\-v [A-Za-z0-9_.-]+:[A-Za-z0-9_./-]+' "$README" \
    | sed -E 's/^-v //' | LC_ALL=C sort -u || true
}

CODE_VOLUMES=$(code_volumes)
DOC_VOLUMES=$(doc_volumes)
if [ -z "$CODE_VOLUMES" ]; then
  fail "$(printf '%-20s no volume could be derived from the compose file' 'Container volume')"
elif [ -z "$DOC_VOLUMES" ]; then
  fail "$(printf '%-20s the document names no volume' 'Container volume')"
else
  MISSING_VOL=""
  while IFS= read -r vol; do
    [ -n "$vol" ] || continue
    if ! printf '%s\n' "$CODE_VOLUMES" | grep -qxF "$vol"; then
      MISSING_VOL="$MISSING_VOL $vol"
    fi
  done <<< "$DOC_VOLUMES"
  if [ -n "$MISSING_VOL" ]; then
    fail "$(printf '%-20s these volumes the document names the tree does not mount:%s' \
      'Container volume' "$MISSING_VOL")"
  else
    printf '  ok      %-20s %s\n' 'Container volume' "$(printf '%s\n' "$DOC_VOLUMES" | grep -c .)"
  fi
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
# --- the path the agent's server speaks on -------------------------------------
#
# The agent's server is a second server: it speaks the Model Context Protocol
# over HTTP, and it does so on a path of its own. The README's curl for it
# names that path, and a path the server does not serve is a request that
# comes back as nothing.
#
# The path is the code's -- cmd/mcp hands it to the server -- and the port is
# the README's: the one it gives the agent's server. So the paths the README
# writes on that port are the agent server's paths, and they have to be the
# ones the code serves.
#
# The two sets are compared by MEMBERSHIP: the order they are written in says
# nothing about it, and a message that differs between the twins is a message
# nobody can trust.

code_agent_paths() {
  grep -oE 'run_http\([^)]*path="[^"]+"' cmd/mcp/main.mbt \
    | sed -E 's/.*path="([^"]+)".*/\1/' | LC_ALL=C sort -u
}

doc_agent_paths() {
  local port
  for port in $(doc_mcp_ports | LC_ALL=C sort -u); do
    grep -oE "http://127\.0\.0\.1:${port}/[A-Za-z0-9_./-]*" "$README" \
      | sed -E "s#^http://127\.0\.0\.1:${port}##"
  done | LC_ALL=C sort -u
}

CODE_AGENT_PATHS=$(code_agent_paths)
DOC_AGENT_PATHS=$(doc_agent_paths)
CODE_AGENT_TEXT=$(printf '%s\n' "$CODE_AGENT_PATHS" | tr '\n' ' ' | sed -e 's/ *$//')
DOC_AGENT_TEXT=$(printf '%s\n' "$DOC_AGENT_PATHS" | tr '\n' ' ' | sed -e 's/ *$//')
if [ -z "$CODE_AGENT_PATHS" ]; then
  fail "$(printf '%-20s no path could be derived from the server' 'Agent path')"
elif [ -z "$DOC_AGENT_PATHS" ]; then
  fail "$(printf '%-20s the document names no path for the agent server' 'Agent path')"
elif same_members "$CODE_AGENT_PATHS" "$DOC_AGENT_PATHS"; then
  printf '  ok      %-20s %s\n' 'Agent path' "$CODE_AGENT_TEXT"
else
  fail "$(printf '%-20s the tree says [%s], the document says [%s]' \
    'Agent path' "$CODE_AGENT_TEXT" "$DOC_AGENT_TEXT")"
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

# The extensions the local corpus reader accepts.  The function that decides
# it is the one place the code says what a local corpus may hold, so the set
# is read from that function and not from the file around it.
code_corpus_extensions() {
  awk '
    match($0, /^fn is_readable_extension/) { inside = 1; next }
    inside && match($0, /^}/) { inside = 0 }
    inside {
      line = $0
      while (match(line, /"\.[a-zA-Z0-9]+"/)) {
        print substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' backend/corpus_sources.mbt | LC_ALL=C sort -u
}

# The sets of file types the document attaches to the corpus.  A claim is a
# list item or a paragraph, and every claim that mentions the corpus and names
# file types has to name the tree's whole set: a claim that names three of
# the five types is a claim that tells a reader something the tree does not.
doc_corpus_extension_sets() {
  awk '
    function flush(   line, ext, out, seen) {
      if (block == "") return
      out = ""
      seen = " "
      if (tolower(block) ~ /corpus/) {
        line = block
        while (match(line, /`\.[a-zA-Z0-9]+`/)) {
          ext = substr(line, RSTART + 1, RLENGTH - 2)
          if (index(seen, " " ext " ") == 0) {
            out = out ext " "
            seen = seen ext " "
          }
          line = substr(line, RSTART + RLENGTH)
        }
      }
      block = ""
      sub(/ +$/, "", out)
      if (out != "") print out
    }
    /^[[:space:]]*$/ { flush(); next }
    { line = $0 }
    line ~ /^[[:space:]]*- / || line ~ /^#/ { flush() }
    { block = block line "\n" }
    END { flush() }
  ' "$README"
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

# The names the discovery document gives the files, each with the variable
# that names it, as "name variable".
#
# The document is what the server ANSWERS with, so the name it gives a file is
# the name the server gives it.  A document that calls the society vocabulary
# something else calls it something the server does not.
code_file_names() {
  tr '\n' ' ' < backend/agent.mbt \
    | grep -oE '"what": "[^"]+", *"variable": "MAKED_[A-Z_]+"' \
    | sed -E 's/"what": "([^"]+)", *"variable": "(MAKED_[A-Z_]+)"/\1|\2/' \
    | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $1); print tolower($1), $2 }' \
    | LC_ALL=C sort -u || true
}

# The same names, as README.md's table gives them.
#
# The row is read as a pair: the first column names the file, and the
# variable in the third column is the one that points at it.  The table has a
# format column between them, and the format is checked on its own above.
doc_file_names() {
  grep -oE '^\| [^|]+ \| [^|]+ \| `MAKED_[A-Z_]+` \|' "$README" \
    | sed -E 's/^\| ([^|]+) \| [^|]+ \| `(MAKED_[A-Z_]+)` \|/\1|\2/' \
    | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $1); print tolower($1), $2 }' \
    | LC_ALL=C sort -u || true
}

CODE_FILE_NAMES=$(code_file_names)
DOC_FILE_NAMES=$(doc_file_names)
if [ -z "$CODE_FILE_NAMES" ]; then
  fail "$(printf '%-20s no file name could be derived from the discovery document' 'File names')"
elif same_members "$CODE_FILE_NAMES" "$DOC_FILE_NAMES"; then
  printf '  ok      %-20s %s\n' 'File names' "$(printf '%s\n' "$CODE_FILE_NAMES" | grep -c .)"
else
  fail "$(printf '%-20s the tree says [%s], the table says [%s]' \
    'File names' \
    "$(printf '%s\n' "$CODE_FILE_NAMES" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$DOC_FILE_NAMES" | tr '\n' ' ' | sed -e 's/ *$//')")"
fi

# --- the extensions that are read as YAML --------------------------------------
#
# A data file is read as YAML when its name ends in one of two extensions, and
# as JSON otherwise. One function decides it -- is_yaml_path -- and both the
# reader and the writer ask that function, so the tree has one rule. The README
# states the rule in one sentence: a `.yaml` or `.yml` file is read as YAML, and
# every other file is read as JSON.
#
# Nothing compared them. The measurement: the tree was made to stop accepting
# the .yml extension, and the README was made to stop naming it, and all four
# gate suites went on saying that every claim in the documents matches the
# tree. A reader who was told a .yml file is read as JSON would write one, and
# the server would read it as YAML -- or, the other way round, would read it as
# JSON and refuse it, with a message about syntax.
#
# The document's extensions are read from the clause that states the rule and
# not from the whole document: the document names other extensions elsewhere
# -- the corpus takes .txt and .pdf -- and those are other claims.
#
# The two sets are compared in lower case: the tree matches a name without
# regard to its case, so a document that writes `.YAML` is saying the same
# thing as one that writes `.yaml`, and the comparison must not fail a
# document for the case of a letter.

# The extensions the tree reads as YAML.
code_yaml_extensions() {
  awk '
    /^pub fn is_yaml_path\(/ { inside = 1; next }
    inside && /^}/ { inside = 0 }
    inside {
      line = $0
      while (match(line, /"\.[a-zA-Z0-9]+"/)) {
        print substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' backend/datafile.mbt | tr 'A-Z' 'a-z' | LC_ALL=C sort -u
}

# The extensions the document says are read as YAML: the ones named in the
# clause that states the rule. The clause is the paragraph that holds it, up
# to the words "read as YAML" -- the sentence is wrapped, and the extensions
# are named before the phrase that says what happens to them.
doc_yaml_extensions() {
  awk '
    /^[[:space:]]*$/ { block = ""; next }
    { block = block $0 " " }
    index($0, "read as YAML") > 0 && !found { head = block; found = 1 }
    END {
      if (!found) exit
      n = index(head, "read as YAML")
      if (n > 0) print substr(head, 1, n - 1)
    }
  ' "$README" | grep -oE '`\.[a-zA-Z0-9]+`' | tr -d '`' | tr 'A-Z' 'a-z' | LC_ALL=C sort -u
}

CODE_YAML_EXTENSIONS=$(code_yaml_extensions)
DOC_YAML_EXTENSIONS=$(doc_yaml_extensions)
if [ -z "$CODE_YAML_EXTENSIONS" ]; then
  fail "$(printf '%-20s no extension could be derived from the tree' 'YAML extensions')"
elif [ -z "$DOC_YAML_EXTENSIONS" ]; then
  fail "$(printf '%-20s the document does not state the rule' 'YAML extensions')"
elif same_members "$CODE_YAML_EXTENSIONS" "$DOC_YAML_EXTENSIONS"; then
  printf '  ok      %-20s %s\n' 'YAML extensions' \
    "$(printf '%s\n' "$CODE_YAML_EXTENSIONS" | tr '\n' ' ' | sed -e 's/ *$//')"
else
  fail "$(printf '%-20s the tree says [%s], the document says [%s]' \
    'YAML extensions' \
    "$(printf '%s\n' "$CODE_YAML_EXTENSIONS" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$DOC_YAML_EXTENSIONS" | tr '\n' ' ' | sed -e 's/ *$//')")"
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

# --- the file types a local corpus may hold -----------------------------------
#
# A local corpus is a folder of the reader's own files, and the reader reads
# the ones whose extension it knows.  The document says which files those are,
# and the code says the same thing in the function that decides it.  A reader
# who puts a Zotero export in the folder and is not told it is read has no way
# of knowing; a reader who is told a type is read and it is not has a folder
# that comes back empty.
#
# Nothing watched it.  The measurement: the document named fewer types than
# the reader takes, and the reader was given a type the document did not name,
# and all four gate suites went on saying that every claim in the documents
# matches the tree.
#
# The claim is read by its own shape.  The document's claim is every list
# item and every paragraph that mentions the corpus and names file types, and
# it quotes the extensions the way the tree writes them.  The tree's claim is
# the function that decides which files the reader reads.
#
# The comparison is the same one the corpus kinds are held to: the two sets
# are the same set.

CODE_CORPUS_EXTENSIONS=$(code_corpus_extensions)
DOC_CORPUS_SETS=$(doc_corpus_extension_sets)
CORPUS_FILES_BAD=0
if [ -z "$CODE_CORPUS_EXTENSIONS" ]; then
  fail "$(printf '%-20s no file type could be derived from the local reader' 'Corpus files')"
  CORPUS_FILES_BAD=1
elif [ -z "$DOC_CORPUS_SETS" ]; then
  fail "$(printf '%-20s the document names no file type for a local corpus' 'Corpus files')"
  CORPUS_FILES_BAD=1
else
  while IFS= read -r claim; do
    [ -n "$claim" ] || continue
    if ! same_members "$CODE_CORPUS_EXTENSIONS" "$(printf '%s\n' "$claim" | tr ' ' '\n')"; then
      fail "$(printf '%-20s the tree says [%s], the document says [%s]' \
        'Corpus files' \
        "$(printf '%s\n' "$CODE_CORPUS_EXTENSIONS" | tr '\n' ' ' | sed -e 's/ *$//')" \
        "$claim")"
      CORPUS_FILES_BAD=1
      break
    fi
  done <<< "$DOC_CORPUS_SETS"
fi
if [ "$CORPUS_FILES_BAD" -eq 0 ]; then
  printf '  ok      %-20s %s\n' 'Corpus files' "$(printf '%s\n' "$CODE_CORPUS_EXTENSIONS" | grep -c .)"
fi

# --- the keys a corpus file has ------------------------------------------------
#
# The README shows a corpus file of the reader's own, and the loader reads
# certain keys out of it.  The KINDS the file may name are watched; the KEYS
# the file is written with are not.  A key the loader no longer reads is a
# corpus file the reader wrote from the README that comes back empty, and
# nothing says so.
#
# Nothing watched it.  The measurement: the tree was made to call the corpus
# file's folder key something else -- everywhere the tree writes or reads it,
# so the tree stayed coherent -- and the README's own example was made to call
# it something the loader does not read, and all four gate suites went on
# saying that every claim in the documents matches the tree.
#
# The tree's keys are the ones the loader reads out of a corpus file.  The
# document's keys are the ones its own example is written with, and the
# example is found by the format string it carries, so that the block read is
# the corpus file's block and not some other example's.
#
# The comparison is ONE-WAY: the example is a LOCAL corpus, so it need not name
# the keys the other kinds use -- a document is free to show fewer keys than
# the loader reads.

code_corpus_keys() {
  awk '
    /pub fn CorpusConfig::from_json/ { inside = 1; next }
    inside && /^}/ { inside = 0; next }
    inside {
      if (match($0, /json_(string|field|array)\([^,]*,[[:space:]]*"[a-z_]+"\)/)) {
        k = substr($0, RSTART, RLENGTH)
        sub(/.*, "/, "", k)
        sub(/".*/, "", k)
        print k
      }
      if (match($0, /\.get\("[a-z_]+"\)/)) {
        k = substr($0, RSTART, RLENGTH)
        sub(/.*\("/, "", k)
        sub(/"\).*/, "", k)
        print k
      }
    }
  ' backend/corpus.mbt | LC_ALL=C sort -u
}

doc_corpus_keys() {
  awk '
    /^```/ {
      if (inside) {
        if (hit) { print block }
        inside = 0
        hit = 0
        block = ""
      } else {
        inside = 1
        block = ""
      }
      next
    }
    inside {
      block = block $0 "\n"
      if ($0 ~ /maked\.corpus\.v1/) { hit = 1 }
    }
  ' "$README" \
    | grep -oE '^[[:space:]]*[a-z_]+:' \
    | sed -E 's/^[[:space:]]*([a-z_]+):$/\1/' \
    | LC_ALL=C sort -u || true
}

CODE_CORPUS_KEYS=$(code_corpus_keys)
DOC_CORPUS_KEYS=$(doc_corpus_keys)
if [ -z "$CODE_CORPUS_KEYS" ]; then
  fail "$(printf '%-20s no corpus key could be derived from the loader' 'Corpus keys')"
elif [ -z "$DOC_CORPUS_KEYS" ]; then
  fail "$(printf '%-20s the document names no key for a corpus file' 'Corpus keys')"
else
  # The comparison is ONE-WAY, so it is made here: every key the document
  # names has to be one the loader reads, and the loader is free to read more
  # than the document shows.
  CORPUS_KEYS_UNREAD=""
  while IFS= read -r corpus_key; do
    [ -n "$corpus_key" ] || continue
    corpus_key_found=0
    while IFS= read -r corpus_candidate; do
      [ -n "$corpus_candidate" ] || continue
      if [ "$corpus_candidate" = "$corpus_key" ]; then
        corpus_key_found=1
        break
      fi
    done <<< "$CODE_CORPUS_KEYS"
    if [ "$corpus_key_found" -eq 0 ]; then
      if [ -z "$CORPUS_KEYS_UNREAD" ]; then
        CORPUS_KEYS_UNREAD="$corpus_key"
      else
        CORPUS_KEYS_UNREAD="$CORPUS_KEYS_UNREAD $corpus_key"
      fi
    fi
  done <<< "$DOC_CORPUS_KEYS"
  if [ -n "$CORPUS_KEYS_UNREAD" ]; then
    fail "$(printf '%-20s the example names keys the loader does not read [%s]' \
      'Corpus keys' "$CORPUS_KEYS_UNREAD")"
  else
    printf '  ok      %-20s %s\n' 'Corpus keys' \
      "$(printf '%s\n' "$DOC_CORPUS_KEYS" | tr '\n' ' ' | sed -e 's/ *$//')"
  fi
fi

# --- the keys a mapping table has ----------------------------------------------
#
# The README shows a mapping table of the reader's own, and the loader reads
# certain keys out of it.  The SLOTS the table drives are watched; the KEYS the
# table is written with are not.  A key the loader no longer reads is a
# mapping table the reader wrote from the README whose rules never fire, and
# nothing says so.
#
# This is the mapping table's claim, and not the corpus file's: the corpus
# file's keys are held by the gate above, and this one is a different file
# with a different loader.
#
# Nothing watched it.  The measurement: the tree was made to call the table's
# note key something else -- everywhere the tree writes or reads it, so the
# tree stayed coherent -- and the README's own table was made to call it
# something the loader does not read, and all four gate suites went on saying
# that every claim in the documents matches the tree.
#
# The tree's keys are the ones the loader reads out of a mapping table.  The
# document's keys are the ones its own example is written with, and the
# example is found by the format string it carries, so that the block read is
# the mapping table's block and not some other example's.
#
# A rule of the table is a LIST ITEM, so its key can sit behind a dash: a key
# is read the same way whether or not it is.
#
# The comparison is TWO-WAY: the example is the whole table, so a key the
# loader reads that the example does not show is a key the reader does not
# know about, and a key the example shows that the loader does not read is a
# key the reader wrote for nothing.

code_mapping_keys() {
  awk '
    /pub fn ResearchConfig::from_json/ { inside = 1; next }
    inside && /^}/ { inside = 0; next }
    inside {
      if (match($0, /json_(strings|string|field|array)\([^,]*,\s*"[a-z_]+"\)/)) {
        k = substr($0, RSTART, RLENGTH)
        sub(/.*, "/, "", k)
        sub(/".*/, "", k)
        print k
      }
      if (match($0, /\.get\("[a-z_]+"\)/)) {
        k = substr($0, RSTART, RLENGTH)
        sub(/.*\("/, "", k)
        sub(/"\).*/, "", k)
        print k
      }
    }
  ' backend/research_config.mbt | LC_ALL=C sort -u
}

doc_mapping_keys() {
  awk '
    /^```/ {
      if (inside) {
        if (hit) { print block }
        inside = 0
        hit = 0
        block = ""
      } else {
        inside = 1
        block = ""
      }
      next
    }
    inside {
      block = block $0 "\n"
      if ($0 ~ /maked\.research\.v1/) { hit = 1 }
    }
  ' "$README" \
    | grep -oE '^[[:space:]]*(-[[:space:]]+)?[a-z_]+:' \
    | sed -E 's/^[[:space:]]*(-[[:space:]]+)?([a-z_]+):$/\2/' \
    | LC_ALL=C sort -u || true
}

CODE_MAPPING_KEYS=$(code_mapping_keys)
DOC_MAPPING_KEYS=$(doc_mapping_keys)

if [ -z "$CODE_MAPPING_KEYS" ] || [ -z "$DOC_MAPPING_KEYS" ]; then
  fail "$(printf '%-20s the mapping table keys could not be found on both sides' \
    'Mapping keys')"
elif same_members "$CODE_MAPPING_KEYS" "$DOC_MAPPING_KEYS"; then
  printf '  ok      %-20s %s\n' 'Mapping keys' \
    "$(printf '%s\n' "$DOC_MAPPING_KEYS" | tr '\n' ' ' | sed -e 's/ *$//')"
else
  fail "$(printf '%-20s the tree says [%s], the document says [%s]' \
    'Mapping keys' \
    "$(printf '%s\n' "$CODE_MAPPING_KEYS" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$DOC_MAPPING_KEYS" | tr '\n' ' ' | sed -e 's/ *$//')")"
fi

# --- the keys a machine file has -----------------------------------------------
#
# The README shows a machine of the reader's own, and the loader reads certain
# keys out of it.  The SLOTS the machine drives are watched; the KEYS the
# machine is written with are not.  A key the loader no longer reads is a
# machine file the reader wrote from the README whose domain starts nowhere,
# and nothing says so.
#
# This is the machine file's claim, and not the mapping table's or the corpus
# file's: those are held by the gates before it, and this one is a different
# file with a different loader.
#
# Nothing watched it.  The measurement: the tree was made to call the machine
# file's anchor key something else -- everywhere the tree writes or reads it,
# so the tree stayed coherent -- and the README's own machine was made to call
# it something the loader does not read, and all four gate suites went on
# saying that every claim in the documents matches the tree.
#
# The tree's keys are the ones the loader reads out of a machine file, and the
# ones it writes back out again: the two are the same file, and a key the
# reader may write is a key the loader knows.  The document's keys are the
# ones its own example is written with, and the example is found by the format
# string it carries, so that the block read is the machine file's block and
# not some other example's.
#
# The comparison is ONE-WAY: the example is a SMALL machine, so it need not
# name the keys the loader reads for the parts a small machine does not have
# -- the Chinese names, the continuations, the outcome words, the edge names.

code_machine_keys() {
  awk '
    {
      line = $0
      while (match(line, /json_(strings|string|field|array)\([^,]*,[[:space:]]*"[a-z_]+"\)/)) {
        k = substr(line, RSTART, RLENGTH)
        sub(/.*, "/, "", k)
        sub(/".*/, "", k)
        print k
        line = substr(line, RSTART + RLENGTH)
      }
      line = $0
      while (match(line, /model_int\([^,]*,[[:space:]]*"[a-z_]+"\)/)) {
        k = substr(line, RSTART, RLENGTH)
        sub(/.*, "/, "", k)
        sub(/".*/, "", k)
        print k
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' backend/model.mbt | LC_ALL=C sort -u
}

doc_machine_keys() {
  awk '
    /^```/ {
      if (inside) {
        if (hit) { print block }
        inside = 0
        hit = 0
        block = ""
      } else {
        inside = 1
        block = ""
      }
      next
    }
    inside {
      block = block $0 "\n"
      if ($0 ~ /maked\.model\.v1/) { hit = 1 }
    }
  ' "$README" \
    | grep -oE '"[a-z_]+":' \
    | tr -d '":' \
    | LC_ALL=C sort -u || true
}

CODE_MACHINE_KEYS=$(code_machine_keys)
DOC_MACHINE_KEYS=$(doc_machine_keys)
if [ -z "$CODE_MACHINE_KEYS" ]; then
  fail "$(printf '%-20s no machine key could be derived from the loader' 'Machine keys')"
elif [ -z "$DOC_MACHINE_KEYS" ]; then
  fail "$(printf '%-20s the document names no key for a machine file' 'Machine keys')"
else
  # The comparison is ONE-WAY, so it is made here: every key the document
  # names has to be one the loader reads, and the loader is free to read more
  # than the document shows.
  MACHINE_KEYS_UNREAD=""
  while IFS= read -r machine_key; do
    [ -n "$machine_key" ] || continue
    machine_key_found=0
    while IFS= read -r machine_candidate; do
      [ -n "$machine_candidate" ] || continue
      if [ "$machine_candidate" = "$machine_key" ]; then
        machine_key_found=1
        break
      fi
    done <<< "$CODE_MACHINE_KEYS"
    if [ "$machine_key_found" -eq 0 ]; then
      if [ -z "$MACHINE_KEYS_UNREAD" ]; then
        MACHINE_KEYS_UNREAD="$machine_key"
      else
        MACHINE_KEYS_UNREAD="$MACHINE_KEYS_UNREAD $machine_key"
      fi
    fi
  done <<< "$DOC_MACHINE_KEYS"
  if [ -n "$MACHINE_KEYS_UNREAD" ]; then
    fail "$(printf '%-20s the example names keys the loader does not read [%s]' \
      'Machine keys' "$MACHINE_KEYS_UNREAD")"
  else
    printf '  ok      %-20s %s\n' 'Machine keys' \
      "$(printf '%s\n' "$DOC_MACHINE_KEYS" | tr '\n' ' ' | sed -e 's/ *$//')"
  fi
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

# --- the tools the document names as taking a language -------------------------
#
# The README names the tools that accept a language in a sentence, after the
# table that gives every tool its arguments.  Each name in that sentence is a
# claim about the server: it says the tool takes the language and answers in
# it.  A tool that takes no such argument refuses the call instead -- the
# request comes back as an error, and the caller has learned nothing.
#
# The table beside it is held to the tree already, tool by tool.  The sentence
# is a second place that says the same thing, and a place that says it is a
# place that can be wrong on its own.
#
# Nothing watched it.  The measurement: the sentence named a tool that takes
# no language, and the tool the sentence names stopped taking one -- with both
# tables changed to match the tree, so that the sentence was the only place
# left that said what the tool took -- and all four gate suites went on saying
# that every claim in the documents matches the tree.
#
# The comparison is ONE-WAY: the sentence is free to name fewer tools than the
# tree has, and the table is where the whole list is.

# The tools the tree's schemas give a language argument.
code_language_tools() {
  printf '%s\n' "$CODE_TOOL_ARGS" | awk '$2 == "lang" { print $1 }' | LC_ALL=C sort -u
}

# The sentence that names them, flattened so that a sentence the editor
# wrapped is still one sentence to a matcher.  The sentence is found by its
# opening -- the one that says the language is an argument -- and not by its
# closing words, so that a change of wording at the end of it does not take
# the check with it.
doc_language_tools() {
  tr '\n' ' ' < "$README" \
    | grep -oE 'takes the same switch as an argument:[^.]*' \
    | grep -oE 'maked_[a-z_]+' \
    | LC_ALL=C sort -u || true
}

# How many times the document says it.  A sentence that is gone is a claim
# that nothing checks any more, and a sentence that is said twice is two
# sentences that can drift apart.
doc_language_tool_sentences() {
  tr '\n' ' ' < "$README" \
    | grep -oE 'takes the same switch as an argument:[^.]*' \
    | grep -c . || true
}

CODE_LANGUAGE_TOOLS=$(code_language_tools)
DOC_LANGUAGE_TOOLS=$(doc_language_tools)
LANGUAGE_TOOL_SENTENCES=$(doc_language_tool_sentences)

LANGUAGE_TOOLS_UNNAMED=""
while IFS= read -r tool; do
  [ -n "$tool" ] || continue
  if ! printf '%s\n' "$CODE_LANGUAGE_TOOLS" | grep -qxF "$tool"; then
    LANGUAGE_TOOLS_UNNAMED="$LANGUAGE_TOOLS_UNNAMED $tool"
  fi
done <<< "$DOC_LANGUAGE_TOOLS"

if [ -z "$CODE_LANGUAGE_TOOLS" ]; then
  fail "$(printf '%-20s no tool could be derived that takes a language' \
    'Agent language tools')"
elif [ "$LANGUAGE_TOOL_SENTENCES" -eq 0 ]; then
  fail "$(printf '%-20s the document does not name the tools that take a language' \
    'Agent language tools')"
elif [ "$LANGUAGE_TOOL_SENTENCES" -gt 1 ]; then
  fail "$(printf '%-20s the document names the tools that take a language more than once' \
    'Agent language tools')"
elif [ -n "$LANGUAGE_TOOLS_UNNAMED" ]; then
  fail "$(printf '%-20s the document names tools that do not take a language:%s' \
    'Agent language tools' "$LANGUAGE_TOOLS_UNNAMED")"
else
  printf '  ok      %-20s %s\n' 'Agent language tools' \
    "$(printf '%s\n' "$DOC_LANGUAGE_TOOLS" | grep -c . || true)"
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

# The measures a session's report carries: the metric constructors the report
# builds for itself.
MEASURE_COUNT=$(awk '
  /let metrics : Array\[Metric\] = \[/ { inside = 1; next }
  inside && /^\s*\]/ { inside = 0 }
  inside {
    line = $0
    while (match(line, /_metric\(/)) {
      n++
      line = substr(line, RSTART + RLENGTH)
    }
  }
  END { print n + 0 }
' backend/metrics.mbt)

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
  printf 'Suites\t%s\tacross the | suites\tacross the | suite\n' "$SUITE_COUNT"
  printf 'Languages\t%s\t| languages\t| language\n' "$LANGUAGE_COUNT"
  printf 'Measures\t%s\tsession carries | measures\n' "$MEASURE_COUNT"
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

# --- the measure names ----------------------------------------------------------
#
# The README names the five measures a session carries, and the tree gives
# each one a label -- the word the reader sees on the screen. A measure the
# tree calls something else is a measure the reader cannot find by name, and a
# measure the README leaves out is a measure the reader is not told about.
#
# The COUNT was watched; the NAMES were not. The measurement: the tree was
# made to call a measure something else, and the README was made to call a
# measure something the tree does not, and all four gate suites went on
# saying that every claim in the documents matches the tree. A count of five
# is not the same claim as the five names.
#
# The tree's names are the labels the metrics are given. The document's
# names are the backticked names in the sentence that enumerates them, and
# that sentence wraps across two lines, so the whole document is read at
# once.

code_measure_labels() {
  grep -oE 'label: lang\.pick\("[^"]+"' backend/metrics.mbt \
    | sed -E 's/^label: lang\.pick\("//; s/"$//' \
    | LC_ALL=C sort -u
}

doc_measure_names() {
  tr '\n' ' ' < "$README" \
    | grep -oE 'Every session carries five measures:[^.]*' \
    | grep -oE '`[^`]+`' \
    | tr -d '`' \
    | LC_ALL=C sort -u
}

CODE_MEASURE_LABELS=$(code_measure_labels)
DOC_MEASURE_NAMES=$(doc_measure_names)

if [ -z "$CODE_MEASURE_LABELS" ] || [ -z "$DOC_MEASURE_NAMES" ]; then
  fail "$(printf '%-20s the measure names could not be found on both sides' 'Measure names')"
elif same_members "$CODE_MEASURE_LABELS" "$DOC_MEASURE_NAMES"; then
  printf '  ok      %-20s %s\n' 'Measure names' \
    "$(printf '%s\n' "$DOC_MEASURE_NAMES" | tr '\n' ' ' | sed -e 's/ *$//')"
else
  fail "$(printf '%-20s the tree names [%s], the document names [%s]' \
    'Measure names' \
    "$(printf '%s\n' "$CODE_MEASURE_LABELS" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$DOC_MEASURE_NAMES" | tr '\n' ' ' | sed -e 's/ *$//')")"
fi


# --- the protocol fields --------------------------------------------------------
#
# The README tells an agent how to wire itself up, and the fields every
# request's `params._meta` has to carry are the contract: an agent that
# spells one of them differently has every request it makes refused. The
# README states them and MAKED's own discovery document states them, and
# nothing compared the two -- so a README that spelled a field name
# differently would have gone unnoticed, and every request an agent made
# with it would have been refused.
#
# The discovery document is the source, because the discovery document is
# what the server ANSWERS with. Its note is where the protocol fields are
# written down, so that is where they are read from.
#
# The fields are found by the namespace they live in, which is specific
# enough to be read out of the whole document: a name in another namespace
# is the name of something else.

code_protocol_fields() {
  awk '
    /"protocol": \{/ { inside = 1; next }
    inside && /^[ \t]*\},/ { exit }
    inside { print }
  ' backend/agent.mbt \
    | grep -oE '`io\.modelcontextprotocol/[A-Za-z]+`' \
    | tr -d '`' \
    | LC_ALL=C sort -u
}

doc_protocol_fields() {
  grep -oE '`io\.modelcontextprotocol/[A-Za-z]+`' "$README" \
    | tr -d '`' \
    | LC_ALL=C sort -u
}

CODE_PROTOCOL_FIELDS=$(code_protocol_fields)
DOC_PROTOCOL_FIELDS=$(doc_protocol_fields)

if [ -z "$CODE_PROTOCOL_FIELDS" ] || [ -z "$DOC_PROTOCOL_FIELDS" ]; then
  fail "$(printf '%-20s the protocol fields could not be found on both sides' 'Protocol fields')"
elif same_members "$CODE_PROTOCOL_FIELDS" "$DOC_PROTOCOL_FIELDS"; then
  printf '  ok      %-20s %s\n' 'Protocol fields' "$(printf '%s\n' "$CODE_PROTOCOL_FIELDS" | grep -c .)"
else
  fail "$(printf '%-20s the tree names [%s], the document names [%s]' \
    'Protocol fields' \
    "$(printf '%s\n' "$CODE_PROTOCOL_FIELDS" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$DOC_PROTOCOL_FIELDS" | tr '\n' ' ' | sed -e 's/ *$//')")"
fi
# --- the protocol headers --------------------------------------------------------
#
# The README tells a reader what a request over HTTP has to carry: the
# protocol's own version header, and a header that names the method the body
# carries. Each name is a contract -- a request that spells one of them
# differently is a request the server does not recognise.
#
# Nothing compared them. The measurement: the tree's discovery note was made to
# name a header the README does not name, and the README was made to name a
# header the tree does not name, and so was the guide, and all four gate suites
# went on saying that every claim in the documents matches the tree.
#
# The discovery document is the source, because the discovery document is what
# the server ANSWERS with. Its note is where the headers are written down, so
# that is where they are read from -- the same place the protocol fields are
# read from, and for the same reason.
#
# The headers are found by the word that comes after them: a name in backticks
# that the word header follows, close by, is a header, and a name the word does
# not follow is the name of something else. The window stops at the next
# backtick, so one name can never be read as another.
#
# The name is written with its value, and only the name is compared: the
# document says `MCP-Protocol-Version: 2026-07-28`.
#
# The comparison is TWO-WAY: the document's list enumerates the headers, so a
# header it leaves out is a header a reader would not send, and a header it
# names that the tree does not is a header the server does not want.

code_protocol_headers() {
  awk '
    /"protocol": \{/ { inside = 1; next }
    inside && /^[ \t]*\},/ { exit }
    inside { print }
  ' backend/agent.mbt \
    | grep -oE '`([A-Za-z][A-Za-z0-9-]*)(:[^`]*)?`[^`]{0,20}header' \
    | sed -E 's/^`([^:`]*).*/\1/' \
    | LC_ALL=C sort -u
}

doc_protocol_headers() {
  grep -oE '`([A-Za-z][A-Za-z0-9-]*)(:[^`]*)?`[^`]{0,20}header' "$README" \
    | sed -E 's/^`([^:`]*).*/\1/' \
    | LC_ALL=C sort -u
}

CODE_PROTOCOL_HEADERS=$(code_protocol_headers)
DOC_PROTOCOL_HEADERS=$(doc_protocol_headers)

if [ -z "$CODE_PROTOCOL_HEADERS" ] || [ -z "$DOC_PROTOCOL_HEADERS" ]; then
  fail "$(printf '%-20s the protocol headers could not be found on both sides' 'Protocol headers')"
elif same_members "$CODE_PROTOCOL_HEADERS" "$DOC_PROTOCOL_HEADERS"; then
  printf '  ok      %-20s %s\n' 'Protocol headers' \
    "$(printf '%s\n' "$DOC_PROTOCOL_HEADERS" | tr '\n' ' ' | sed -e 's/ *$//')"
else
  fail "$(printf '%-20s the tree names [%s], the document names [%s]' \
    'Protocol headers' \
    "$(printf '%s\n' "$CODE_PROTOCOL_HEADERS" | tr '\n' ' ' | sed -e 's/ *$//')" \
    "$(printf '%s\n' "$DOC_PROTOCOL_HEADERS" | tr '\n' ' ' | sed -e 's/ *$//')")"
fi
# --- the status a refusal comes back with -------------------------------------
#
# The README's error handling says what a refusal looks like, and the one
# number in it is the status: a slot that does not exist comes back as `400`.
# Nothing compared that with the code, so a README that said `404` would have
# gone unnoticed -- and a reader writing a client against the document would
# have been reading the wrong status.
#
# The tree is the source. The branch that answers for a slot that does not
# exist is the one that names the slot, and the status it answers with is the
# status the document has to state. The naming of the slot is guarded by the
# integration suite, which asks the running server and reads the name back;
# the status is a number in the document, so it is checked here.
#
# The claim is found by its own shape -- the sentence about a slot that does
# not exist -- so a status code written anywhere else in the document is not
# read as this one. The sentence is read from the whole document at once,
# because it wraps across two lines.

code_refusal_status() {
  awk '
    /UnknownSlot\(name\) => \{/ { inside = 1; next }
    inside && match($0, /status=[0-9]+/) {
      print substr($0, RSTART + 7, RLENGTH - 7)
      exit
    }
    inside && /^[ \t]*\}/ { exit }
  ' backend/api.mbt
}

doc_refusal_status() {
  tr '\n' ' ' < "$README" | tr -s ' ' \
    | grep -oE 'slot that does not exist comes back as `[0-9]{3}`' \
    | grep -oE '[0-9]{3}' | head -1 || true
}

CODE_REFUSAL_STATUS=$(code_refusal_status)
DOC_REFUSAL_STATUS=$(doc_refusal_status)

if [ -z "$CODE_REFUSAL_STATUS" ]; then
  fail "$(printf '%-20s the tree does not say what a refusal answers with' 'Refusal status')"
else
  check_claim "Refusal status" "$CODE_REFUSAL_STATUS" "$DOC_REFUSAL_STATUS"
fi
# --- the paths the build writes ------------------------------------------------
#
# The README tells a reader how to start the MCP server, and the command it
# gives names a file under _build/. A path the build does not produce is a
# command that fails with "file not found" and nothing else, so the README's
# path has to be one the tree's scripts name.
#
# The tree is the scripts: build.ps1 stages the bundle, the Dockerfile finds
# both outputs, the integration suite runs the server and the MCP command. The
# gate scripts are left out -- they read the tree, they do not build from it.

tree_build_outputs() {
  grep -rhoaE '_build/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*' \
    --exclude='check-*.sh' --exclude='check-*.ps1' \
    build.ps1 Dockerfile tools .github 2>/dev/null \
    | LC_ALL=C sort -u || true
}

doc_build_outputs() {
  grep -ohaE '_build/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*' "$README" 2>/dev/null \
    | LC_ALL=C sort -u || true
}

# The members of the first list that are not in the second.
missing_from() {
  local source="$1" other="$2" line candidate found out=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    found=0
    while IFS= read -r candidate; do
      [ -n "$candidate" ] || continue
      if [ "$candidate" = "$line" ]; then
        found=1
        break
      fi
    done <<< "$other"
    if [ "$found" -eq 0 ]; then
      if [ -z "$out" ]; then out="$line"; else out="$out $line"; fi
    fi
  done <<< "$source"
  MISSING_FROM="$out"
}

TREE_BUILD_OUTPUTS=$(tree_build_outputs)
DOC_BUILD_OUTPUTS=$(doc_build_outputs)

missing_from "$DOC_BUILD_OUTPUTS" "$TREE_BUILD_OUTPUTS"

if [ -z "$MISSING_FROM" ]; then
  printf '  ok      %-20s %s\n' 'Build outputs' \
    "$(printf '%s\n' "$DOC_BUILD_OUTPUTS" | grep -c . || true)"
else
  fail "$(printf '%-20s the document states [%s], and the tree builds no such path' \
    'Build outputs' "$MISSING_FROM")"
fi
# --- the export formats the document uses --------------------------------------
#
# The README shows the export URL a reader can copy, and the format values in
# it have to be ones the server answers. An export that asks for a format the
# handler does not know comes back as a 400 with "unknown_format", and a
# reader who copied the line finds that out the hard way.
#
# The tree is the handler: the values it matches on are the values it answers.
#
# The document is TWO places, not one: the query values its examples write, and
# the formats the row that describes the route says it answers. The second
# place was not read, and nothing else held it either. The measurement that
# found it: the server was made to stop answering the markdown spelling -- so
# that the row's claim became false -- and the row was made to name a format
# the server does not answer, and all four gate suites went on saying that
# every claim in the documents matches the tree. The backend tests went on
# passing too: 433 of them, on a tree whose server no longer answered the
# format the row names.
#
# The comparison is one way, because the handler may know more formats than
# the document names -- an alias nobody writes is still an alias -- but every
# format the document names has to be one the server answers.
#
# The gate prints the SET the document names and not its size: a count cannot
# see two twins reading two different sets of the same size.

code_export_formats() {
  awk '
    /app\.get\("\/api\/sessions\/:id\/export"/ { inside = 1 }
    inside && /^  \}\)$/ { exit }
    inside { print }
  ' backend/api.mbt | grep -oE 'Some\("[a-z]+"\)' | grep -oE '"[a-z]+"' | tr -d '"' \
    | LC_ALL=C sort -u
}

# The formats the row that describes the export route names.  The row is found
# by the route it names, and the formats are read from the cell that describes
# it -- the method and the route are in the cells before it.
doc_export_row_formats() {
  grep -E '^\|.*api/sessions/:id/export.*\|' "$README" \
    | sed -E 's/^[^|]*\|[^|]*\|[^|]*\|//' | sed -E 's/\|.*$//' \
    | grep -oE '`[a-z]+`' | tr -d '`' | LC_ALL=C sort -u
}

# The document's formats: the query values its examples write, and the formats
# its row names.
doc_export_formats() {
  {
    grep -oE 'format=[a-z]+' "$README" | sed -E 's/^format=//'
    doc_export_row_formats
  } | LC_ALL=C sort -u
}

CODE_EXPORT_FORMATS=$(code_export_formats)
DOC_EXPORT_FORMATS=$(doc_export_formats)

missing_from "$DOC_EXPORT_FORMATS" "$CODE_EXPORT_FORMATS"

if [ -z "$MISSING_FROM" ]; then
  printf '  ok      %-20s %s\n' 'Export formats' \
    "$(printf '%s\n' "$DOC_EXPORT_FORMATS" | tr '\n' ' ' | sed -e 's/ *$//')"
else
  fail "$(printf '%-20s the document asks for [%s], and the server does not answer it' \
    'Export formats' "$MISSING_FROM")"
fi
# --- the ring's order ----------------------------------------------------------
#
# The ring is a ring, and the ORDER is the claim: Model before Data before
# Experience. The README states it in two vocabularies -- the lowercase ids
# in the sentence that names the five domains, and the titles in the
# headline that draws the ring -- and the set comparison above does not see
# an order at all: a ring written in a different order has the same five
# names in it.
#
# The tree's ring is the tuples, in the order they are written. The
# document's ids are read from the sentence that names the domains, in the
# order it writes them.
#
# The titles are the other half, and they are read in two ways. The WHOLE
# sequence has to be there: the document states the ring in titles, and a
# document that stopped doing so would be saying less than it says now.
# And every RUN of the tree's titles the document writes has to be a
# contiguous part of the ring -- "Model Data" is the ring's first two, and
# "Data Model" is not the ring at all. The runs are found with the tree's
# own titles, so a run of capitalised words that is not the ring (the
# group states, a table header) is not read as one.
#
# Every run is read, not just one of them: the ring is drawn in two places
# in the README, and a wrong drawing in one of them is a wrong drawing.

code_ring_ids() {
  grep -oE '\("[a-z]+", "[^"]+", "[A-Z]"' backend/pages.mbt \
    | sed -E 's/\("([a-z]+)".*/\1/' | tr '\n' ' ' | sed -e 's/ *$//'
}

code_ring_titles() {
  grep -oE '\("[a-z]+", "[^"]+", "[A-Z]"' backend/pages.mbt \
    | sed -E 's/\("[a-z]+", "([^"]+)".*/\1/' | tr '\n' ' ' | sed -e 's/ *$//'
}

# The tree's titles as an alternation, to find the runs with.
ring_title_alternation() {
  local titles="$1" out="" title
  for title in $titles; do
    if [ -z "$out" ]; then out="$title"; else out="$out|$title"; fi
  done
  printf '(%s)' "$out"
}

# The pattern the whole sequence is found by, built from the tree's titles:
# each title, separated by things that are not letters.
ring_title_pattern() {
  local titles="$1" first=1 pattern="" title
  for title in $titles; do
    if [ "$first" -eq 1 ]; then
      pattern="$title"
      first=0
    else
      pattern="$pattern[^A-Za-z0-9]+$title"
    fi
  done
  printf '%s' "$pattern"
}

# The ids the document states, in the order it states them.
doc_ring_ids() {
  awk '
    {
      if (!match($0, /The [A-Za-z]+ domains are/)) next
      line = substr($0, RSTART + RLENGTH)
      sub(/\..*/, "", line)
      while (match(line, /`[a-z]+`/)) {
        printf "%s ", substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$README" | sed -e 's/ *$//'
}

# The runs of the tree's titles the document writes, one per line.
doc_ring_runs() {
  local titles="$1" alt run
  alt=$(ring_title_alternation "$titles")
  [ -n "$alt" ] || return 0
  run="$alt([^A-Za-z0-9]+$alt)*"
  tr '\n' ' ' < "$README" | tr -s ' ' \
    | grep -oE "$run" \
    | while IFS= read -r match; do
        [ -n "$match" ] || continue
        printf '%s\n' "$(printf '%s' "$match" | grep -oE "$alt" | tr '\n' ' ' | sed -e 's/ *$//')"
      done | LC_ALL=C sort -u
}

CODE_RING_IDS=$(code_ring_ids)
CODE_RING_TITLES=$(code_ring_titles)
DOC_RING_IDS=$(doc_ring_ids)
RING_TITLE_PATTERN=$(ring_title_pattern "$CODE_RING_TITLES")
RING_TITLE_FOUND=$(tr '\n' ' ' < "$README" | tr -s ' ' \
  | grep -oE "$RING_TITLE_PATTERN" || true)
DOC_RING_RUNS=$(doc_ring_runs "$CODE_RING_TITLES")

if [ -z "$CODE_RING_IDS" ]; then
  fail "$(printf '%-20s no domain could be derived from the ring' 'Ring order')"
elif [ -z "$DOC_RING_IDS" ]; then
  fail "$(printf '%-20s the document does not state the domains in order' 'Ring order')"
elif [ "$CODE_RING_IDS" != "$DOC_RING_IDS" ]; then
  fail "$(printf '%-20s the tree says [%s], the document says [%s]' \
    'Ring order' "$CODE_RING_IDS" "$DOC_RING_IDS")"
elif [ -z "$RING_TITLE_FOUND" ]; then
  fail "$(printf '%-20s the tree says [%s], the document does not state them in that order' \
    'Ring order' "$CODE_RING_TITLES")"
else
  BAD_RUN=""
  while IFS= read -r run; do
    [ -n "$run" ] || continue
    case " $CODE_RING_TITLES " in
      *" $run "*) ;;
      *) BAD_RUN="$BAD_RUN$run " ;;
    esac
  done <<< "$DOC_RING_RUNS"
  if [ -n "$BAD_RUN" ]; then
    fail "$(printf '%-20s the tree says [%s], the document writes the ring as [%s]' \
      'Ring order' "$CODE_RING_TITLES" "$(printf '%s' "$BAD_RUN" | sed -e 's/ *$//')")"
  else
    printf '  ok      %-20s %s\n' 'Ring order' "$CODE_RING_IDS"
  fi
fi
# --- the language switch -------------------------------------------------------
#
# The server answers in two languages, and the parameter that asks for one is
# a claim about the code: the table says that `zh` asks for the Chinese and
# that an absent parameter means the English. Nothing compared the table
# with the code, so a document that said `cn` while the code answered to
# `zh` would have gone unnoticed -- and the reader would send a parameter
# the server does not recognise.
#
# The code is the source: Lang::code() gives the code each language answers
# to, and lang_from_query() says what an absent parameter means. The
# document's rows are found by their own shape -- a row whose second cell
# is one of the code's language names -- so a row that is not part of the
# table is not read as one.
#
# The row that says "no parameter" is the one whose parameter is written
# between ASTERISKS, the same convention the environment-variable table
# uses for "*(unset)*". A parameter that is a value is written in
# backticks. The asterisks are the signal, and they have to survive the
# reading: a marker that reads as a bare word ("absent") is a word the
# server would answer to in English, which is not what the row says.

code_lang_pairs() {
  awk '
    /^pub fn Lang::code\(/ { inside = 1; next }
    inside && /^}/ { exit }
    inside && match($0, /^[[:space:]]*[A-Z][A-Za-z]* => "[^"]+"/) {
      line = substr($0, RSTART, RLENGTH)
      sub(/^[[:space:]]*/, "", line)
      variant = line
      sub(/ =>.*$/, "", variant)
      code = line
      sub(/^.*=> "/, "", code)
      sub(/"$/, "", code)
      print variant " " code
    }
  ' backend/i18n.mbt
}

code_lang_default() {
  awk '
    /^pub fn lang_from_query\(/ { inside = 1; next }
    inside && match($0, /None => [A-Z][A-Za-z]*/) {
      line = substr($0, RSTART, RLENGTH)
      sub(/^None => /, "", line)
      print line
      exit
    }
  ' backend/i18n.mbt
}

# The code a language answers to.
lang_code_of() {
  local variant="$1" pairs="$2" pair
  while IFS= read -r pair; do
    [ -n "$pair" ] || continue
    if [ "${pair%% *}" = "$variant" ]; then
      printf '%s' "${pair##* }"
      return 0
    fi
  done <<< "$pairs"
  return 1
}

# The rows the document states: "parameter language", read from the rows
# whose second cell is one of the code's language names. The parameter cell
# keeps its asterisks, because they are what says "no parameter".
doc_lang_rows() {
  local pairs="$1" pair variant
  while IFS= read -r pair; do
    [ -n "$pair" ] || continue
    variant="${pair%% *}"
    grep -oE "^\|[^|]*\|[[:space:]]*$variant[[:space:]]*\|" "$README" \
      | sed -E "s/^\|([^|]*)\|.*/\1/" \
      | sed -E 's/`//g' \
      | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
      | while IFS= read -r param; do
          [ -n "$param" ] || continue
          printf '%s\t%s\n' "$param" "$variant"
        done
  done <<< "$pairs"
}

CODE_LANG_PAIRS=$(code_lang_pairs)
CODE_LANG_DEFAULT=$(code_lang_default)
DOC_LANG_ROWS=$(doc_lang_rows "$CODE_LANG_PAIRS")

LANG_PROBLEM=""
LANG_DEFAULT_STATED=0
while IFS=$'\t' read -r param variant; do
  [ -n "$param" ] || continue
  code=$(lang_code_of "$variant" "$CODE_LANG_PAIRS")
  if [ -z "$code" ]; then
    LANG_PROBLEM="the tree has no language named $variant"
  elif printf '%s' "$param" | grep -qF '*'; then
    LANG_DEFAULT_STATED=1
    if [ "$variant" != "$CODE_LANG_DEFAULT" ]; then
      LANG_PROBLEM="an absent parameter means $CODE_LANG_DEFAULT, the document says $variant"
    fi
  else
    if [ "$param" != "$code" ]; then
      LANG_PROBLEM="the tree asks for $variant with $code, the document says $param"
    fi
  fi
  [ -z "$LANG_PROBLEM" ] || break
done <<< "$DOC_LANG_ROWS"

if [ -z "$CODE_LANG_PAIRS" ]; then
  fail "$(printf '%-20s no language could be derived from the code' 'Language switch')"
elif [ -z "$DOC_LANG_ROWS" ]; then
  fail "$(printf '%-20s the document does not state the language switch' 'Language switch')"
elif [ "$LANG_DEFAULT_STATED" -eq 0 ]; then
  fail "$(printf '%-20s the document does not state what an absent parameter means' 'Language switch')"
elif [ -n "$LANG_PROBLEM" ]; then
  fail "$(printf '%-20s %s' 'Language switch' "$LANG_PROBLEM")"
else
  printf '  ok      %-20s %s\n' 'Language switch' \
    "$(printf '%s\n' "$CODE_LANG_PAIRS" | awk '{ print $2 }' | tr '\n' ' ' | sed -e 's/ *$//')"
fi

# --- the routes that answer in a language --------------------------------------
#
# The README shows a reader how to ask for the Chinese, with a block of
# requests that carry ?lang=. Every one of them is a claim about the server:
# it says the route answers in the language asked for. A route that does not
# take the parameter answers in English whatever the reader sends, so the
# example is wrong in the way that costs a reader the most -- it looks like it
# worked.
#
# Nothing watched it. The measurement: the document asked for a language on a
# route that does not take one, and the server stopped answering in a language
# on a route the document asked it in, and all four gate suites went on saying
# that every claim in the documents matches the tree.
#
# The claim is read by its own shape. The tree's claim is the route whose
# handler asks for the language the request named. The document's claim is the
# lines that show a method, a path and the parameter.
#
# The comparison is ONE-WAY: the document's block is an example, and an example
# is free to be shorter than the truth. What it may not do is name a route
# that does not take the parameter.

# The routes whose handler asks for the language the request named.
code_language_routes() {
  awk '
    function flush() {
      if (method != "" && path != "") {
        if (body ~ /lang_of\(req\)/) print method " " path
      }
      method = ""; path = ""; body = ""; expect = 0
    }
    {
      line = $0
      if (line ~ /^fn /) { flush(); next }
      if (line ~ /app\.(get|post|put|delete|patch)\(/) {
        flush()
        m = line
        if (match(m, /app\.(get|post|put|delete|patch)\(/)) {
          method = toupper(substr(m, RSTART + 4, RLENGTH - 5))
        }
        body = line
        path = ""
        if (match(line, /"\/api\/[^"]*"/)) {
          path = substr(line, RSTART + 1, RLENGTH - 2)
        } else {
          expect = 1
        }
        next
      }
      if (expect == 1) {
        if (match(line, /"\/api\/[^"]*"/)) {
          path = substr(line, RSTART + 1, RLENGTH - 2)
        }
        expect = 0
      }
      if (method != "") { body = body "\n" line }
    }
    END { flush() }
  ' backend/api.mbt | LC_ALL=C sort -u
}

# The requests the document shows asking for a language. The parameter need
# not be the first in the query -- the export shows ?format=md&lang=zh -- so
# the whole request is kept and the route is split off when it is matched.
doc_language_routes() {
  grep -oE '^(GET|POST|PUT|DELETE|PATCH)[[:space:]]+/api/[^?[:space:]]+\?[^[:space:]]*lang=' "$README" \
    | sed -E 's/[[:space:]]+/ /' \
    | LC_ALL=C sort -u
}

CODE_LANGUAGE_ROUTES=$(code_language_routes)
DOC_LANGUAGE_ROUTES=$(doc_language_routes)
LANGUAGE_PATTERNS=""
while IFS= read -r lang_route; do
  [ -n "$lang_route" ] || continue
  lang_method="${lang_route%% *}"
  lang_pattern="$(build_route_pattern "$lang_route")"
  LANGUAGE_PATTERNS="$LANGUAGE_PATTERNS$(printf '^%s %s$' "$lang_method" "$lang_pattern")"$'\n'
done <<< "$CODE_LANGUAGE_ROUTES"

LANGUAGE_UNASKED=""
while IFS= read -r asked; do
  [ -n "$asked" ] || continue
  lang_asked_route="${asked%%\?*}"
  matched=0
  while IFS= read -r pattern; do
    [ -n "$pattern" ] || continue
    if [[ "$lang_asked_route" =~ $pattern ]]; then
      matched=1
      break
    fi
  done <<< "$LANGUAGE_PATTERNS"
  if [ "$matched" -eq 0 ]; then
    LANGUAGE_UNASKED="$LANGUAGE_UNASKED $asked"
  fi
done <<< "$DOC_LANGUAGE_ROUTES"

if [ -z "$CODE_LANGUAGE_ROUTES" ]; then
  fail "$(printf '%-20s no route could be derived that answers in a language' 'Language routes')"
elif [ -z "$DOC_LANGUAGE_ROUTES" ]; then
  fail "$(printf '%-20s the document asks for no language at all' 'Language routes')"
elif [ -n "$LANGUAGE_UNASKED" ]; then
  fail "$(printf '%-20s the document asks for a language on routes that do not take one:%s' \
    'Language routes' "$LANGUAGE_UNASKED")"
else
  printf '  ok      %-20s %s\n' 'Language routes' \
    "$(printf '%s\n' "$DOC_LANGUAGE_ROUTES" | grep -c . || true)"
fi
# --- the routes the document says do not take a language ------------------------
#
# The document says of one route that it needs no parameter -- the model
# carries both vocabularies and a client can choose for itself.  Nothing held
# that copy to the tree: the server could have started answering in one
# language on that route, and the document would have gone on saying that it
# takes none.
#
# The claim is a NEGATION, and it is read as one.  The document's claim is a
# request in backticks and the words that deny a parameter right after it.
# The tree's claim is the routes whose handler asks for the language the
# request named, and those are the routes the gate above already derived.
#
# The whole document is flattened into one line first, because a document
# may write "does not" at the end of one line and "need it" at the start of
# the next.
#
# The comparison is ONE-WAY: the document may deny a language to fewer routes
# than there are.  What it may not do is deny one to a route that takes it.

# The routes the document says take no language.
doc_no_language_routes() {
  tr '\n\r' '  ' < "$README" \
    | grep -oE '`(GET|POST|PUT|DELETE|PATCH) /api/[^`?]+`[[:space:]]*(does not[[:space:]]+(need|take|require|accept)|(needs|takes|requires)[[:space:]]+no|without)' \
    | sed -E 's/^`([^`]*)`.*/\1/' \
    | LC_ALL=C sort -u || true
}

DOC_NO_LANGUAGE_ROUTES=$(doc_no_language_routes)

NO_LANGUAGE_WRONG=""
while IFS= read -r no_language_claim; do
  [ -n "$no_language_claim" ] || continue
  no_language_matched=0
  while IFS= read -r no_language_pattern; do
    [ -n "$no_language_pattern" ] || continue
    if [[ "$no_language_claim" =~ $no_language_pattern ]]; then
      no_language_matched=1
      break
    fi
  done <<< "$LANGUAGE_PATTERNS"
  if [ "$no_language_matched" -eq 1 ]; then
    NO_LANGUAGE_WRONG="$NO_LANGUAGE_WRONG $no_language_claim"
  fi
done <<< "$DOC_NO_LANGUAGE_ROUTES"

if [ -z "$CODE_LANGUAGE_ROUTES" ]; then
  fail "$(printf '%-20s no route could be derived that answers in a language' 'No language route')"
elif [ -z "$DOC_NO_LANGUAGE_ROUTES" ]; then
  fail "$(printf '%-20s the document says no route takes no language' 'No language route')"
elif [ -n "$NO_LANGUAGE_WRONG" ]; then
  fail "$(printf '%-20s the document says these routes take no language, and they do:%s' \
    'No language route' "$NO_LANGUAGE_WRONG")"
else
  printf '  ok      %-20s %s\n' 'No language route' \
    "$(printf '%s\n' "$DOC_NO_LANGUAGE_ROUTES" | tr '\n' ' ' | sed -e 's/ *$//')"
fi
# --- the ring's letters --------------------------------------------------------
#
# The ring has a letter for each domain -- M for Model, D for Data -- and the
# logo draws them, clockwise from the top. The backend defines them, the
# logo draws them, and the README states the order. Three places, one fact,
# and nothing compared them: a "tidying" that swapped two letters in the
# logo still renders five evenly spaced nodes that merely look wrong, and
# the document stays true of a ring that no longer exists.
#
# The letters are the third field of the ring's tuples, in the order the
# tuples are written, and the logo's nodes are the same letters in the same
# order. The document's sequence is found by its own shape -- the tree's
# letters, separated by things that are not letters -- so the domain NAMES
# ("Model -> Data -> Experience") are not read as the sequence, and a ring
# whose letters change makes the document's old sequence stop matching
# rather than being compared against the wrong thing.

code_ring_letters() {
  grep -oE '\("[a-z]+", "[^"]+", "[A-Z]"' backend/pages.mbt \
    | sed -E 's/.*"([A-Z])"$/\1/' | tr '\n' ' ' | sed -e 's/ *$//'
}

logo_ring_letters() {
  grep -oE '\("[A-Z]", "#[0-9a-fA-F]+"' frontend/logo.mbt \
    | sed -E 's/\("([A-Z])".*/\1/' | tr '\n' ' ' | sed -e 's/ *$//'
}

# The pattern the document's sequence is found by, built from the tree's
# letters: each letter, separated by things that are not letters.
ring_letter_pattern() {
  local letters="$1" first=1 pattern="" letter
  for letter in $letters; do
    if [ "$first" -eq 1 ]; then
      pattern="$letter"
      first=0
    else
      pattern="$pattern[^A-Za-z0-9]+$letter"
    fi
  done
  printf '%s' "$pattern"
}

# The sequences the document states, one per line.
doc_ring_letters() {
  local pattern
  pattern=$(ring_letter_pattern "$(code_ring_letters)")
  [ -n "$pattern" ] || return 0
  tr '\n' ' ' < "$README" | tr -s ' ' \
    | grep -oE "$pattern" \
    | while IFS= read -r sequence; do
        [ -n "$sequence" ] || continue
        printf '%s\n' "$(printf '%s' "$sequence" | grep -oE '[A-Z]' | tr '\n' ' ' | sed -e 's/ *$//')"
      done | LC_ALL=C sort -u
}

CODE_RING_LETTERS=$(code_ring_letters)
LOGO_RING_LETTERS=$(logo_ring_letters)
DOC_RING_LETTERS=$(doc_ring_letters)
DOC_RING_COUNT=$(printf '%s\n' "$DOC_RING_LETTERS" | grep -c . || true)
DOC_RING_FIRST=$(printf '%s\n' "$DOC_RING_LETTERS" | head -1)

if [ -z "$CODE_RING_LETTERS" ]; then
  fail "$(printf '%-20s no letter could be derived from the ring' 'Ring letters')"
elif [ "$CODE_RING_LETTERS" != "$LOGO_RING_LETTERS" ]; then
  fail "$(printf '%-20s the tree says [%s], the logo draws [%s]' \
    'Ring letters' "$CODE_RING_LETTERS" "$LOGO_RING_LETTERS")"
elif [ "$DOC_RING_COUNT" -eq 0 ]; then
  fail "$(printf '%-20s the document does not state the ring' 'Ring letters')"
elif [ "$DOC_RING_COUNT" -gt 1 ]; then
  fail "$(printf '%-20s the document states the ring more than once, and the statements differ' \
    'Ring letters')"
elif [ "$CODE_RING_LETTERS" != "$DOC_RING_FIRST" ]; then
  fail "$(printf '%-20s the tree says [%s], the document says [%s]' \
    'Ring letters' "$CODE_RING_LETTERS" "$DOC_RING_FIRST")"
else
  printf '  ok      %-20s %s\n' 'Ring letters' "$CODE_RING_LETTERS"
fi
# --- the letters a record may carry --------------------------------------------
#
# The ring has five letters, and the tree says which of them a record may carry
# in three places besides the ring itself: the list the server advertises, the
# set the server accepts, and the list the client falls back to. The README
# calls them "the ring's own letters", so each of them has to be the ring's.
#
# The gate "Ring letters" holds the ring to the logo and to the document. It
# does not hold the copies that decide what a record may carry: the "Entry
# record" gate asks only whether the document's example domain is a member of
# the server's list. A server that took a letter the ring does not have -- or
# refused one the ring has -- would have kept every gate green.
#
# The measurement that found the gap: one letter of the server's list, of the
# server's accepted set and of the client's fallback was each changed to a
# letter that is not the ring's, and all four gate suites went on saying that
# every claim in the documents matches the tree.
#
# The comparison is by MEMBERSHIP and not by order: the ring's order is the
# order the logo draws, and which letter a record may carry does not depend on
# where the letter sits in the ring.

# The letters the server accepts: the value of each arm of normalise_domain.
code_accepted_domains() {
  awk '
    /^fn normalise_domain\(/ { inside = 1; next }
    inside && /^}/ { inside = 0 }
    inside {
      line = $0
      while (match(line, /=>[ ]*"[A-Z]"/)) {
        s = substr(line, RSTART, RLENGTH)
        sub(/.*=>[ ]*"/, "", s)
        sub(/".*/, "", s)
        print s
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' backend/entries.mbt | LC_ALL=C sort -u
}

# The letters the client falls back to when the server sends no list.
code_client_domains() {
  awk '
    /^pub fn default_entry_domains\(\)/ { inside = 1; next }
    inside && /^}/ { inside = 0 }
    inside {
      line = $0
      while (match(line, /"[A-Z]"/)) {
        print substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' frontend/entries.mbt | LC_ALL=C sort -u
}

# The ring's letters as a set: the ring is an order, and what a record may
# carry is a membership.
ring_letter_set() {
  printf '%s\n' "$1" | tr ' ' '\n' | grep -E '^[A-Z]$' | LC_ALL=C sort -u || true
}

RING_LETTER_SET=$(ring_letter_set "$CODE_RING_LETTERS")
CODE_ACCEPTED_DOMAINS=$(code_accepted_domains)
CODE_CLIENT_DOMAINS=$(code_client_domains)

DOMAIN_LETTERS_WHERE=(
  "backend/entries.mbt entry_domains"
  "backend/entries.mbt normalise_domain"
  "frontend/entries.mbt default_entry_domains"
)
DOMAIN_LETTERS_SETS=(
  "$CODE_ENTRY_DOMAINS"
  "$CODE_ACCEPTED_DOMAINS"
  "$CODE_CLIENT_DOMAINS"
)

DOMAIN_LETTERS_BAD=0
if [ -z "$RING_LETTER_SET" ]; then
  fail "$(printf '%-20s no letter could be derived from the ring' 'Domain letters')"
  DOMAIN_LETTERS_BAD=1
else
  DOMAIN_LETTERS_INDEX=0
  while [ "$DOMAIN_LETTERS_INDEX" -lt 3 ]; do
    DOMAIN_LETTERS_WHERE_ONE="${DOMAIN_LETTERS_WHERE[$DOMAIN_LETTERS_INDEX]}"
    DOMAIN_LETTERS_SET_ONE="${DOMAIN_LETTERS_SETS[$DOMAIN_LETTERS_INDEX]}"
    if [ -z "$DOMAIN_LETTERS_SET_ONE" ]; then
      fail "$(printf '%-20s no letter could be derived from %s' \
        'Domain letters' "$DOMAIN_LETTERS_WHERE_ONE")"
      DOMAIN_LETTERS_BAD=1
    elif ! same_members "$RING_LETTER_SET" "$DOMAIN_LETTERS_SET_ONE"; then
      fail "$(printf '%-20s %s says [%s], the ring says [%s]' \
        'Domain letters' "$DOMAIN_LETTERS_WHERE_ONE" \
        "$(printf '%s\n' "$DOMAIN_LETTERS_SET_ONE" | tr '\n' ' ' | sed -e 's/ *$//')" \
        "$(printf '%s\n' "$RING_LETTER_SET" | tr '\n' ' ' | sed -e 's/ *$//')")"
      DOMAIN_LETTERS_BAD=1
    fi
    DOMAIN_LETTERS_INDEX=$((DOMAIN_LETTERS_INDEX + 1))
  done
fi

if [ "$DOMAIN_LETTERS_BAD" -eq 0 ]; then
  printf '  ok      %-20s %s\n' 'Domain letters' "$CODE_RING_LETTERS"
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
