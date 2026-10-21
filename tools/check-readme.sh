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
