#!/usr/bin/env bash
# Check the documents against the tree.
#
#   bash tools/check-docs.sh
#
# The README has a gate for its numbers (tools/check-readme.sh). This is the
# same invariant applied to the other documents a reader is sent to:
#
#   **the number the document states IS the number the tree has**
#
# The documents are:
#
#   architecture/      how the system is put together
#   AGENT.md           how to drive MAKED from another agent
#   packaging/RUN.txt  the note that ships inside the release archive
#
# They rotted the way the README did: four API endpoints when there are
# thirty-seven, eight columns when there are twelve, "no Dockerfile" when
# there is one, a hundred file:line references pointing at lines that had
# long since moved, and a table of tools that had drifted away from the
# tools the server actually has.
#
# Four kinds of claim are checked, and each is checked in the way that fits
# it.
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
# The SETS are compared by membership. The tools the discovery document
# declares, the files MAKED runs on, the HTTP endpoints it lists, the
# environment variables the server reads: a set with one entry too many and
# a set with one entry too few fail the same way, because both send a reader
# to something that is not there. The comparison is by membership and not by
# a sorted string, so the two twins cannot disagree about the answer by
# disagreeing about the order.
#
# The WORDS are counts too. "the seven tools" is a claim exactly as much as
# "37 API routes" is. A number word can be mapped to a number, so it is
# mapped and compared.
#
# It reads only. It never writes to the source tree.
#
# It also starts no processes it does not need. Every one of them costs a
# tenth of a second on Windows and a millisecond on Linux, and a gate that
# takes forty seconds on the machine that writes the documents is a gate
# people stop running. So the sets are compared in the shell, the line
# counts are cached per file, and each derived list is read once.
#
# Exit codes:
#   0  every claim in the documents matches the tree
#   1  a claim in the documents does not match the tree

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

AGENT_DOC="AGENT.md"
AGENTS_DOC="AGENTS.md"
RUN_NOTE="packaging/RUN.txt"

EVIDENCE="architecture/system-model.evidence.md"
DEPS="architecture/dependencies.evidence.md"
DEPS_MD="architecture/dependencies.md"
SUMMARY="architecture/system-model.summary.md"
DEPLOY="architecture/deployment.evidence.md"

# The documents are read into the shell once, and everything that asks a
# document a question asks the string. `$(< file)` is the shell's own read:
# no process, no fork.
EVIDENCE_TEXT=$(< "$EVIDENCE")
DEPS_TEXT=$(< "$DEPS")
DEPS_MD_TEXT=$(< "$DEPS_MD")
SUMMARY_TEXT=$(< "$SUMMARY")

FAILURES=0

fail() {
  echo "  $1"
  echo "*** FAIL ***"
  FAILURES=$((FAILURES + 1))
}

ok() {
  printf '  ok      %-22s %s\n' "$1" "$2"
}

# --- sets --------------------------------------------------------------------
#
# A set is a list of lines. Two sets are the same when they have the same
# members and the same size, and the order they are written in says nothing
# about it.
#
# The comparisons are done in the shell rather than by piping into grep.
# They are the same comparison, and they cost no processes.
#
# And they answer through a VARIABLE rather than through stdout. A command
# substitution is a fork, and a fork on this machine costs a tenth of a
# second; a gate that forks a hundred times takes a minute, and a gate that
# takes a minute is a gate people stop running.

# COUNT_LINES holds the answer of count_lines.
COUNT_LINES=0
count_lines() {
  local count=0 line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    count=$((count + 1))
  done <<< "$1"
  COUNT_LINES=$count
}

# JOIN_LINES holds the answer of join_lines.
JOIN_LINES=""
join_lines() {
  local line out=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ -z "$out" ]; then out="$line"; else out="$out $line"; fi
  done <<< "$1"
  JOIN_LINES="$out"
}

# NOT_IN holds the answer of not_in.
NOT_IN=""
not_in() {
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
  NOT_IN="$out"
}

# Two sets that have to be the same.
check_sets() {
  local label="$1" expected="$2" stated="$3"
  local na nb missing extra
  count_lines "$expected"; na=$COUNT_LINES
  count_lines "$stated"; nb=$COUNT_LINES
  not_in "$expected" "$stated"; missing=$NOT_IN
  not_in "$stated" "$expected"; extra=$NOT_IN
  if [ "$na" = "$nb" ] && [ -z "$missing" ] && [ -z "$extra" ]; then
    ok "$label" "$na"
    return
  fi
  join_lines "$expected"; local expected_text="$JOIN_LINES"
  join_lines "$stated"; local stated_text="$JOIN_LINES"
  fail "$(printf '%-22s the tree says [%s], the document says [%s]' \
    "$label" "$expected_text" "$stated_text")"
}

# Every member of the first set has to be a member of the second.
check_subset() {
  local label="$1" subset="$2" superset="$3"
  local missing
  not_in "$subset" "$superset"; missing=$NOT_IN
  if [ -z "$missing" ]; then
    count_lines "$subset"
    ok "$label" "$COUNT_LINES"
    return
  fi
  fail "$(printf '%-22s the document is missing [%s]' "$label" "$missing")"
}

# --- how the tree is counted ------------------------------------------------

# A route is one registration: app.get(...), app.post(...), and the rest.
# The count is the number of registrations, not the number of distinct
# paths, because a path registered for two verbs is two registrations and
# the handler behind them is two handlers.
count_routes() {
  grep -cE 'app\.(get|post|put|delete|patch)\(' backend/api.mbt || true
}

# The same routes as "METHOD path". The file is read as one line first,
# because one registration spreads its path over two lines, and a path that
# is on the next line is still a path.
tree_endpoints() {
  tr '\n' ' ' < backend/api.mbt \
    | grep -oE 'app\.(get|post|put|delete|patch)\( *"[^"]+"' \
    | sed -E 's/app\.(get|post|put|delete|patch)\( *"([^"]+)"/\1|\2/' \
    | awk -F'|' '{ print toupper($1), $2 }'
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
#
# The three counts are read in ONE pass, because a pass is a process and a
# process on this machine costs a tenth of a second.
seed_page_counts() {
  awk '
    /^ *\("[a-z]+", "[A-Z]/ { ring++ }
    /^ *"[a-z]+",$/ { list++ }
    /^ *slug: "/ { singles++ }
    END { print (ring + 0) " " (list + 0) " " (singles + 0) }
  ' backend/pages.mbt
}

# Every page the server seeds.
count_seed_pages() {
  local counts ring list singles
  counts=$(seed_page_counts)
  read -r ring list singles <<< "$counts"
  echo $((ring + list + singles))
}

# The pages seed_pages() returns: the ring domains and the other three. The
# index page and the not-found page are made on their own and seeded
# separately, so they are not part of this count.
count_seed_pages_only() {
  local counts ring list singles
  counts=$(seed_page_counts)
  read -r ring list singles <<< "$counts"
  echo $((ring + list))
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
#
# The answer lands in DOC_NUMBER rather than on stdout, so that asking a
# document seven questions does not fork seven times.
DOC_NUMBER=""
doc_number() {
  local pattern="$1" file="$2" text fragment
  case "$file" in
    "$EVIDENCE") text="$EVIDENCE_TEXT" ;;
    "$DEPS") text="$DEPS_TEXT" ;;
    "$DEPS_MD") text="$DEPS_MD_TEXT" ;;
    "$SUMMARY") text="$SUMMARY_TEXT" ;;
    *) text=$(< "$file") ;;
  esac
  DOC_NUMBER=""
  if [[ "$text" =~ $pattern ]]; then
    fragment="${BASH_REMATCH[0]}"
    if [[ "$fragment" =~ [0-9]+ ]]; then
      DOC_NUMBER="${BASH_REMATCH[0]}"
    fi
  fi
}

# A number spelled out in words. "the seven tools" is a claim exactly as
# much as "37 API routes" is, and a word can be mapped to a number.
#
# The map is the twelve words a count below a hundred is written with. A
# count outside that range is a sentence the gate cannot read, and the gate
# says so rather than passing it.
word_number() {
  case "$1" in
    one) echo 1 ;;
    two) echo 2 ;;
    three) echo 3 ;;
    four) echo 4 ;;
    five) echo 5 ;;
    six) echo 6 ;;
    seven) echo 7 ;;
    eight) echo 8 ;;
    nine) echo 9 ;;
    ten) echo 10 ;;
    eleven) echo 11 ;;
    twelve) echo 12 ;;
    *) echo "" ;;
  esac
}

# A count the document spells out in words. Every "<word> <noun>" in the
# document has to be the count the tree has.
check_word_count() {
  local label="$1" noun="$2" expected="$3" doc="$4"
  local words word number bad
  # The document is flattened first, because a phrase the editor wrapped is
  # one phrase to a reader and two to a matcher. The match is
  # case-insensitive, because a count at the start of a sentence is
  # capitalised and the count is the same count. The word that is read is
  # the FIRST one, because the pattern puts the number before the noun and
  # the noun may be more than one word long.
  words=$(tr '\n' ' ' < "$doc" | tr -s ' ' \
    | grep -oEi "\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve) $noun\b" \
    | grep -oiE '^[a-z]+' | tr 'A-Z' 'a-z' | LC_ALL=C sort -u || true)
  if [ -z "$words" ]; then
    fail "$(printf '%-22s the document does not state the count in words' "$label")"
    return
  fi
  bad=""
  for word in $words; do
    number=$(word_number "$word")
    if [ -z "$number" ] || [ "$number" != "$expected" ]; then
      bad="$bad $word"
    fi
  done
  if [ -n "$bad" ]; then
    fail "$(printf '%-22s the document says [%s], the tree has %s' \
      "$label" "$(printf '%s' "$bad" | sed -e 's/^ *//')" "$expected")"
    return
  fi
  ok "$label" "$expected"
}

# A number the document states next to a phrase. Every place the document
# states it has to state the same number, and it has to state it at least
# once: a phrase that is gone is a number nothing checks any more.
check_claim_number() {
  local label="$1" pattern="$2" expected="$3" doc="$4"
  local text matched number stated=0 bad=''
  text=$(tr '\n' ' ' < "$doc" | tr -s ' ')
  while IFS= read -r matched; do
    [ -n "$matched" ] || continue
    if [[ "$matched" =~ $pattern ]]; then
      number="${BASH_REMATCH[1]}"
      stated=1
      if [ "$number" != "$expected" ]; then
        bad="${bad} ${number}"
      fi
    fi
  done <<< "$(printf '%s' "$text" | grep -oE "$pattern" || true)"
  if [ -n "$bad" ]; then
    fail "$(printf '%-22s the tree has %s, the document says [%s]' \
      "$label" "$expected" "${bad# }")"
    return
  fi
  if [ "$stated" -eq 0 ]; then
    fail "$(printf '%-22s the document does not state it' "$label")"
    return
  fi
  ok "$label" "$expected"
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

# --- the tree, read once ----------------------------------------------------
#
# Everything the checks compare against is derived HERE, once, and the
# checks below read the results. A derived list that is recomputed per
# check is a list that costs a process per check.

ROUTES=$(count_routes)
TREE_ENDPOINTS=$(tree_endpoints)

# --- the counts -------------------------------------------------------------

doc_number '[0-9]+ API routes' "$EVIDENCE"
check_count "API routes" \
  "$ROUTES" \
  "$DOC_NUMBER"

# The same routes, counted the second way. The count above is a count of
# LINES that carry a registration; this one is a count of the paths the
# registrations name. One registration spreads its path over two lines, so
# the two counts are the same number -- and if they are not, the path
# extraction above has broken, and every endpoint check built on it would
# pass against nothing.
count_lines "$TREE_ENDPOINTS"
check_count "route paths" \
  "$COUNT_LINES" \
  "$ROUTES"

doc_number 'pages` table with [0-9]+ columns' "$EVIDENCE"
check_count "pages columns" \
  "$(count_page_columns)" \
  "$DOC_NUMBER"

doc_number 'Page struct with [0-9]+ fields' "$EVIDENCE"
check_count "Page fields" \
  "$(count_page_fields)" \
  "$DOC_NUMBER"

doc_number '[|] [0-9]+ seed pages' "$EVIDENCE"
check_count "seed pages" \
  "$(count_seed_pages)" \
  "$DOC_NUMBER"

doc_number 'frontend/frontend_test\.mbt` [|] [0-9]+ tests' "$EVIDENCE"
check_count "frontend tests" \
  "$(grep -cE '^[ \t]*(async[ \t]+)?test[ \t]+"[^"]*"[ \t]*\{' frontend/frontend_test.mbt || true)" \
  "$DOC_NUMBER"

doc_number 'backend/database_test\.mbt` [|] [0-9]+ tests' "$EVIDENCE"
check_count "backend tests" \
  "$(grep -cE '^[ \t]*(async[ \t]+)?test[ \t]+"[^"]*"[ \t]*\{' backend/database_test.mbt || true)" \
  "$DOC_NUMBER"

# The summary states the two suites together.
doc_number '[0-9]+ tests across backend and frontend' "$SUMMARY"
check_count "tests (summary)" \
  "$(cat backend/*.mbt frontend/*.mbt | grep -cE '^[ \t]*(async[ \t]+)?test[ \t]+"[^"]*"[ \t]*\{' || true)" \
  "$DOC_NUMBER"

# --- the dependency versions ------------------------------------------------
#
# The version each dependency is pinned to is stated in three documents, and
# it is stated in moon.mod. All four have to agree: a document that names a
# version the manifest does not pin is a document that sends a reader to a
# version that is not the one this project uses.
#
# The version is read out of moon.mod's import block, and the documents are
# asked whether they state the same one. The three documents are read into
# the shell once, and the question is then asked of the strings -- the same
# question a grep would answer, without thirty processes.

DEPS_TEXT=$(cat "$DEPS")
DEPS_MD_TEXT=$(cat "$DEPS_MD")
EVIDENCE_TEXT=$(cat "$EVIDENCE")

check_dependency_versions() {
  local module="$1" version="$2" label="$3"
  local bad=0
  local index doc text
  # The pattern is held in a variable because a regex with spaces in it has
  # to be, and the dots are escaped because a version is a version and not
  # a pattern -- the PowerShell twin escapes them too.
  local module_re="${module//./\\.}"
  local version_re="${version//./\\.}"
  local table_form="\\| $module_re \\| $version_re \\|"
  for index in 0 1 2; do
    case "$index" in
      0) doc="$DEPS" ; text="$DEPS_TEXT" ;;
      1) doc="$DEPS_MD" ; text="$DEPS_MD_TEXT" ;;
      2) doc="$EVIDENCE" ; text="$EVIDENCE_TEXT" ;;
    esac
    if [[ "$text" != *"$module@$version"* ]] \
       && [[ ! "$text" =~ $table_form ]]; then
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
#
# The line count of a file is counted once and kept: a document with a
# hundred references to ten files should cost ten counts, not a hundred.
# And the count is asked for through a VARIABLE -- a command substitution
# per reference is a fork per reference, and that was the whole cost of
# this gate on a machine where a fork is expensive.
declare -A FILE_LINES
FILE_LINE_COUNT=0

file_line_count() {
  local file="$1"
  if [ -z "${FILE_LINES[$file]+counted}" ]; then
    local -a lines
    mapfile -t lines < "$file"
    FILE_LINES[$file]=${#lines[@]}
  fi
  FILE_LINE_COUNT="${FILE_LINES[$file]}"
}

check_references() {
  local doc="$1"
  local text rest file line last count
  local -a refs=()
  local -A seen=()
  text=$(< "$doc")
  rest="$text"
  # The references are collected in the order the document states them, and
  # a reference that appears twice is one reference. The PowerShell twin
  # walks the document the same way, so the two report in the same order.
  while [[ "$rest" =~ \`([A-Za-z0-9_./-]+\.(mbt|moon\.pkg|ps1|sh|mod|dsl|dot|md)):([0-9]+)(-([0-9]+))?\` ]]; do
    file="${BASH_REMATCH[1]}"
    line="${BASH_REMATCH[3]}"
    if [ -n "${BASH_REMATCH[4]}" ]; then
      last="${BASH_REMATCH[5]}"
      key="$file:$line${BASH_REMATCH[4]}"
    else
      last="$line"
      key="$file:$line"
    fi
    if [ -z "${seen[$key]+yes}" ]; then
      seen[$key]=1
      refs+=("$key")
    fi
    rest="${rest#*"${BASH_REMATCH[0]}"}"
  done
  local bad=0
  local ref
  for ref in "${refs[@]}"; do
    file="${ref%%:*}"
    line="${ref##*:}"
    last="${line##*-}"
    if [ ! -f "$file" ]; then
      fail "$(printf '%-22s %s names a file that is not there' "$doc" "$file")"
      bad=1
      continue
    fi
    file_line_count "$file"
    count="$FILE_LINE_COUNT"
    if [ "$last" -gt "$count" ]; then
      fail "$(printf '%-22s %s points past the end of the file (%s lines)' \
        "$doc" "$ref" "$count")"
      bad=1
    fi
  done
  if [ "$bad" -eq 0 ]; then
    ok "references $(basename "$doc")" "${#refs[@]}"
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

# --- the documents that describe the past -------------------------------------
#
# Seven documents were written to record the analysis that produced the
# migration slices, and every claim in them was true then and is false now.
# They are kept as they were written -- the reasoning is the point -- but a
# reader has to be TOLD, so each one carries a header that says so.
#
# Three of them are graphs, and a header in a graph is invisible once the
# graph is rendered, so each of those carries the marker twice: once in the
# source, where a reader opens the file, and once as the graph's own title,
# where a reader opens the picture.
#
# The gate checks the header, because a header is easy to lose in an edit,
# and a claim that is history without saying so is a lie.

check_past_header() {
  local doc="$1"
  if grep -qF 'This document describes the past.' "$doc"; then
    ok "past header" "$doc"
  else
    fail "$(printf '%-22s %s does not say that it describes the past' \
      'past header' "$doc")"
  fi
}

for doc in architecture/evolution.md architecture/evolution.evidence.md \
           architecture/evolution.dot evolution-summary.md \
           architecture-evolution-roadmap.md \
           current-vs-target-architecture.dot migration-dependency-graph.dot; do
  check_past_header "$doc"
done

# The three graphs say it in their title as well, because a title is what a
# reader sees once the graph is rendered. A graph that keeps the marker in
# its source and loses it from its picture has lost it for half its readers,
# and the source comment does not travel with the SVG.
check_past_title() {
  local doc="$1"
  if grep -qE 'label="This document describes the past\.' "$doc"; then
    ok "past title" "$doc"
  else
    fail "$(printf '%-22s %s does not say in its title that it describes the past' \
      'past title' "$doc")"
  fi
}

for doc in architecture/evolution.dot current-vs-target-architecture.dot \
           migration-dependency-graph.dot; do
  check_past_title "$doc"
done

# --- AGENT.md: the document for another agent -------------------------------
#
# The discovery document at `GET /api/agent` is what an agent reads, and
# AGENT.md is what a person reads before pointing an agent at it. Both carry
# the same facts -- the tools, the protocol, the files, the endpoints -- so
# the facts are derived ONCE, from the discovery document, and both are
# checked against them.
#
# The discovery document is the source rather than the tree because the
# discovery document is what the server ANSWERS with. A tool the server does
# not have is a tool the discovery document must not offer, and the check
# that the server has it is the handler switch in cmd/mcp/main.mbt.

# The tools the discovery document declares. The `name:` field is what makes
# a tool a tool; the `tool:` field of the endpoint list is a reference to
# one, and is not a declaration.
code_tools() {
  grep -oE 'name: "maked_[a-z_]+"' backend/agent.mbt \
    | grep -oE 'maked_[a-z_]+' | LC_ALL=C sort -u || true
}

# The same tools as AGENT.md's table gives them. A tool row starts with the
# tool name in backticks; the endpoint table's rows start with a verb, so
# they are never mistaken for tool rows.
doc_tools() {
  grep -oE '^\| `maked_[a-z_]+`' "$AGENT_DOC" \
    | sed -E 's/^\| `([^`]+)`.*/\1/' | LC_ALL=C sort -u || true
}

# The endpoints the discovery document lists, as "METHOD path".
code_endpoints() {
  tr '\n' ' ' < backend/agent.mbt \
    | grep -oE '"method": "[A-Z]+", *"path": "[^"]+"' \
    | sed -E 's/"method": "([A-Z]+)", *"path": "([^"]+)"/\1 \2/' | LC_ALL=C sort -u || true
}

# The same endpoints as AGENT.md's table gives them.
doc_endpoints() {
  grep -oE '^\| `(GET|POST|PUT|DELETE|PATCH)` \| `/api/[^`]+`' "$AGENT_DOC" \
    | sed -E 's/^\| `([A-Z]+)` \| `([^`]+)`/\1 \2/' | LC_ALL=C sort -u || true
}

# The tools AGENT.md's endpoint table points at.
doc_endpoint_tools() {
  grep -oE '^\| `(GET|POST|PUT|DELETE|PATCH)` \| `/api/[^`]+` \| `maked_[a-z_]+`' "$AGENT_DOC" \
    | grep -oE 'maked_[a-z_]+' | LC_ALL=C sort -u || true
}

# The variables that name the files MAKED runs on, from the discovery
# document.
code_file_vars() {
  grep -oE '"variable": "MAKED_[A-Z_]+"' backend/agent.mbt \
    | grep -oE 'MAKED_[A-Z_]+' | LC_ALL=C sort -u || true
}

# The same variables as the backend actually reads them. The discovery
# document has to offer what the code asks for: a file the code reads and
# the document does not name is a file nobody can point the code at.
code_env_reads() {
  grep -ohE 'get_env_var\("MAKED_[A-Z_]+"\)' backend/*.mbt \
    | grep -oE 'MAKED_[A-Z_]+' | LC_ALL=C sort -u || true
}

# The same variables as AGENT.md's table gives them. The SHAPE of the row is
# what identifies it -- the variable sits in the second column -- so the
# table is found by its shape and not by the heading above it, which is
# itself a claim the word check makes.
doc_file_vars() {
  grep -oE '^\| [^|]+ \| `MAKED_[A-Z_]+` \|' "$AGENT_DOC" \
    | grep -oE 'MAKED_[A-Z_]+' | LC_ALL=C sort -u || true
}

# The protocol version the discovery document names.
code_protocol() {
  grep -oE '"mcp": "[0-9]{4}-[0-9]{2}-[0-9]{2}"' backend/agent.mbt \
    | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true
}

# Every date-shaped version in AGENT.md. They all have to be the one the
# server speaks: an agent that reads a version the server does not answer
# to is an agent that cannot call it.
doc_protocols() {
  grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$AGENT_DOC" | LC_ALL=C sort -u || true
}

CODE_TOOLS=$(code_tools)
DOC_TOOLS=$(doc_tools)
CODE_ENDPOINTS=$(code_endpoints)
DOC_ENDPOINTS=$(doc_endpoints)
DOC_ENDPOINT_TOOLS=$(doc_endpoint_tools)
CODE_FILE_VARS=$(code_file_vars)
CODE_ENV_READS=$(code_env_reads)
DOC_FILE_VARS=$(doc_file_vars)
CODE_PROTOCOL=$(code_protocol)
DOC_PROTOCOLS=$(doc_protocols)

check_sets "agent tools" "$CODE_TOOLS" "$DOC_TOOLS"

count_lines "$CODE_TOOLS"
check_word_count "agent tools (words)" "tools" "$COUNT_LINES" "$AGENT_DOC"

check_sets "agent files" "$CODE_FILE_VARS" "$DOC_FILE_VARS"

count_lines "$CODE_FILE_VARS"
check_word_count "agent files (words)" "files" "$COUNT_LINES" "$AGENT_DOC"

# The discovery document has to offer the variables the code reads.
check_sets "agent files (code)" "$CODE_FILE_VARS" "$CODE_ENV_READS"

# Every protocol version the document states has to be the one the server
# speaks, and it has to state it at all.
if [ -z "$CODE_PROTOCOL" ]; then
  fail "$(printf '%-22s the tree does not name a protocol version' 'agent protocol')"
else
  not_in "$DOC_PROTOCOLS" "$CODE_PROTOCOL"; WRONG="$NOT_IN"
  not_in "$CODE_PROTOCOL" "$DOC_PROTOCOLS"; MISSING="$NOT_IN"
  if [ -n "$WRONG" ]; then
    fail "$(printf '%-22s the document names [%s], the tree names %s' \
      'agent protocol' "$WRONG" "$CODE_PROTOCOL")"
  elif [ -n "$MISSING" ]; then
    fail "$(printf '%-22s the document does not name %s' 'agent protocol' "$CODE_PROTOCOL")"
  else
    ok "agent protocol" "$CODE_PROTOCOL"
  fi
fi

check_sets "agent endpoints" "$CODE_ENDPOINTS" "$DOC_ENDPOINTS"

# Every endpoint the discovery document lists has to be a route the server
# really registers, with the same verb.
check_subset "agent endpoints live" "$CODE_ENDPOINTS" "$TREE_ENDPOINTS"

# The discovery endpoint itself is the way in, so it has to be a route.
check_subset "discovery route" "GET /api/agent" "$TREE_ENDPOINTS"

# Every tool the endpoint table points at has to be a tool the server has.
check_subset "endpoint tools" "$DOC_ENDPOINT_TOOLS" "$CODE_TOOLS"

# The agent's server is not in the published release, and the document says
# so. One of the two is a lie the moment the other changes, so the two are
# checked against each other: the release workflow is what decides whether
# the server is shipped, and the document has to say the same thing.
PUBLISH_MCP=$(grep -cE 'cmd/mcp' .github/workflows/publish.yml || true)
DOC_NOT_SHIPPED=$(grep -cF 'in the published release artifacts' "$AGENT_DOC" || true)
if [ "$PUBLISH_MCP" -gt 0 ] && [ "$DOC_NOT_SHIPPED" -gt 0 ]; then
  fail "$(printf '%-22s the document says the agent server is not released, and the release workflow builds it' \
    'release claim')"
elif [ "$PUBLISH_MCP" -eq 0 ] && [ "$DOC_NOT_SHIPPED" -eq 0 ]; then
  fail "$(printf '%-22s the release workflow does not build the agent server, and the document does not say so' \
    'release claim')"
else
  ok "release claim" "not in the release"
fi

# The port the agent's server speaks HTTP on is named by a variable, and the
# document has to name the same one the code reads.
if grep -qF 'MAKED_MCP_PORT' "$AGENT_DOC" && grep -qF 'MAKED_MCP_PORT' cmd/mcp/main.mbt; then
  ok "agent port variable" "MAKED_MCP_PORT"
else
  fail "$(printf '%-22s MAKED_MCP_PORT is not in both the document and the server' \
    'agent port variable')"
fi

# --- packaging/RUN.txt: the note in the archive -----------------------------
#
# The note is what a reader has after the toolchain is gone, so the variables
# it lists are the only ones they will find. A variable the server reads and
# the note does not name is a setting nobody can turn.

# The settings the server reads, with their defaults.
code_settings() {
  grep -oE 'env_or\("MAKED_[A-Z_]+", "[^"]*"\)' cmd/server/main.mbt \
    | sed -E 's/env_or\("([A-Z_]+)", "([^"]*)"\)/\1 \2/' | LC_ALL=C sort -u || true
}

# The same settings as the note gives them. The line has to END with the
# default, so a sentence that mentions a variable in passing is not read as
# a setting.
doc_settings() {
  grep -oE '^ *MAKED_[A-Z_]+ +[^()]*\(default [^)]*\)[[:space:]]*$' "$RUN_NOTE" \
    | sed -E 's/^ *([A-Z_]+) +[^()]*\(default ([^)]*)\)/\1 \2/' | LC_ALL=C sort -u || true
}

# The variables the note names that are not settings: the ones that name
# files. The settings are subtracted, so a variable mentioned in a sentence
# is not mistaken for a file.
doc_run_files() {
  local settings="$1"
  local names
  names=$(printf '%s\n' "$settings" | awk '{ print $1 }' | LC_ALL=C sort -u)
  grep -oE 'MAKED_[A-Z_]+' "$RUN_NOTE" | LC_ALL=C sort -u | while IFS= read -r variable; do
    [ -n "$variable" ] || continue
    if ! printf '%s\n' "$names" | grep -qxF "$variable"; then
      printf '%s\n' "$variable"
    fi
  done
}

CODE_SETTINGS=$(code_settings)
DOC_SETTINGS=$(doc_settings)

check_sets "run note settings" "$CODE_SETTINGS" "$DOC_SETTINGS"

check_sets "run note files" "$CODE_FILE_VARS" "$(doc_run_files "$CODE_SETTINGS")"

# The executable the note tells the reader to run is the one the release
# workflow packages.
if grep -qF 'stage/maked/server' .github/workflows/publish.yml \
   && grep -qF 'server.exe' "$RUN_NOTE" \
   && grep -qF './server' "$RUN_NOTE"; then
  ok "run note executable" "./server"
else
  fail "$(printf '%-22s the note and the release workflow disagree about the executable' \
    'run note executable')"
fi

# --- .githooks/README.md: the note beside the hook ---------------------------
#
# The hook and the note beside it have to agree. A note that names a command
# the hook does not run sends a reader to a gate that is not there, and a
# hook that runs a command the note does not name is a gate the reader does
# not know is there.

# The commands the hook runs: the lines that are neither blank nor a comment.
code_hook_commands() {
  grep -vE '^[[:space:]]*(#|$)' .githooks/pre-commit \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | LC_ALL=C sort -u || true
}

# The commands the note states, in the section that says what the hook runs.
doc_hook_commands() {
  awk '
    /^#+ What It Runs/ { inside = 1; next }
    inside && /^#/ { exit }
    inside {
      line = $0
      while (match(line, /`[^`]+`/)) {
        print substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' .githooks/README.md | LC_ALL=C sort -u || true
}

check_sets "hook commands" "$(code_hook_commands)" "$(doc_hook_commands)"

# --- AGENTS.md and ci.sh: the counts an agent reads before it touches the tree
#
# AGENTS.md is the first file an agent opens in this repository, and it tells
# that agent how the project is verified: how many gates there are, and how
# many of them a push is checked against. Those are counts, and a count in the
# first document an agent reads is the one that sends it down the wrong road.
#
# The gate count comes from ci.sh's own gate list -- the `gate "name"` calls
# in its full mode -- and the workflow count from the steps the CI workflow's
# gates job runs. ci.sh's own header states both, and so does AGENTS.md, and
# both have to state the tree's.
#
# The scripts the workflow runs also have to be a subset of the scripts a
# ci.sh gate runs. A step in the workflow that runs something ci.sh does not
# run is a check the local run does not have, and an agent that has run ci.sh
# believes it has run everything the pipeline runs.

# The gates in ci.sh's full run: the `gate "name"` calls in its default arm.
count_ci_gates() {
  awk '
    { lines[NR] = $0 }
    /^[ \t]*\*\)[ \t]*$/ { start = NR }
    END {
      if (start == 0) { print 0; exit }
      n = 0
      for (i = start; i <= NR; i++) {
        if (lines[i] ~ /^[ \t]*esac[ \t]*$/) break
        if (lines[i] ~ /^[ \t]*gate "/) n++
      }
      print n
    }
  ' ci.sh
}

# The scripts a ci.sh gate runs.
ci_scripts() {
  awk '
    {
      line = $0
      while (match(line, /bash tools\/[A-Za-z0-9_.-]+\.sh/)) {
        print substr(line, RSTART + 11, RLENGTH - 11)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' ci.sh | LC_ALL=C sort -u || true
}

# The scripts the CI workflow's gates job runs.
workflow_scripts() {
  awk '
    /^  gates:[ \t]*$/ { inside = 1; next }
    inside && /^  [A-Za-z0-9_-]+:[ \t]*$/ { exit }
    inside {
      line = $0
      while (match(line, /bash tools\/[A-Za-z0-9_.-]+\.sh/)) {
        print substr(line, RSTART + 11, RLENGTH - 11)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' .github/workflows/ci.yml | LC_ALL=C sort -u || true
}

# The number a document states next to a phrase. The document is flattened
# first, because a sentence the editor wrapped is one sentence to a reader
# and two to a matcher.
flat_number() {
  local text="$1" pattern="$2" fragment
  if [[ "$text" =~ $pattern ]]; then
    fragment="${BASH_REMATCH[0]}"
    if [[ "$fragment" =~ [0-9]+ ]]; then
      printf '%s\n' "${BASH_REMATCH[0]}"
    fi
  fi
}

# A number a document states, against the tree's.
check_stated() {
  local label="$1" actual="$2" stated="$3" document="$4"
  if [ -z "$stated" ]; then
    fail "$(printf '%-22s %s does not state it' "$label" "$document")"
    return
  fi
  if [ "$stated" != "$actual" ]; then
    fail "$(printf '%-22s the tree has %s, %s says %s' \
      "$label" "$actual" "$document" "$stated")"
    return
  fi
  ok "$label" "$actual"
}

# The scripts the workflow runs have to be a subset of the scripts a ci.sh
# gate runs. A step the local run does not have is a check the reader
# believes they have.
check_workflow_scripts() {
  local label="$1" subset="$2" superset="$3" missing
  not_in "$subset" "$superset"; missing=$NOT_IN
  if [ -z "$missing" ]; then
    count_lines "$subset"
    ok "$label" "$COUNT_LINES"
    return
  fi
  fail "$(printf '%-22s the workflow runs [%s], which ci.sh does not run' \
    "$label" "$missing")"
}

CI_GATES=$(count_ci_gates)
CI_SCRIPTS=$(ci_scripts)
WORKFLOW_SCRIPTS=$(workflow_scripts)
count_lines "$WORKFLOW_SCRIPTS"; WORKFLOW_GATES=$COUNT_LINES

CI_FLAT=$(tr '\n' ' ' < ci.sh | tr -s ' ')
AGENTS_FLAT=$(tr '\n' ' ' < AGENTS.md | tr -s ' ')

# The mutations the three suites carry: one `name =` line each.
count_mutations() {
  grep -cE '^[ \t]*name[ \t]*=' "$1" || true
}

# The mutations in all three suites together. This is the number the guide
# says the batteries re-run the suites.
mutation_total() {
  local total=0 suite count
  for suite in tools/mutate-backend.ps1 tools/mutate-frontend.ps1 tools/mutate-loop.ps1; do
    count=$(count_mutations "$suite")
    total=$((total + count))
  done
  printf '%s\n' "$total"
}

MUTATION_TOTAL=$(mutation_total)

# The tools the discovery document offers, as the guide spells the count out.
count_lines "$CODE_TOOLS"
check_word_count "agent guide tools" "tools" "$COUNT_LINES" "$AGENTS_DOC"

check_stated "agent guide mutations" "$MUTATION_TOTAL" \
  "$(flat_number "$AGENTS_FLAT" 're-run the suites ([0-9]+) times')" "AGENTS.md"

# --- architecture/deployment.md: the topology a reader deploys ----------------
#
# The deployment document states the variables the server reads, with their
# defaults, and points at the lines of the server that read them. Both are
# claims about the tree: a default the document states and the code does not
# have is a setting that does something else, and a pointer past the end of
# the file is a pointer to nothing.
#
# The defaults are the ones the code gives, and they are the same defaults
# the note in the release archive gives, so the two documents and the code
# all have to agree.

DEPLOY_MD="architecture/deployment.md"

# The settings the deployment document states: the variable and the default
# in the first two columns of its table.
doc_deploy_settings() {
  grep -oE '\| `MAKED_[A-Z_]+` \| `[^`]+` \|' "$DEPLOY_MD" \
    | sed -E 's/\| `([A-Z_]+)` \| `([^`]+)` \|/\1 \2/' | LC_ALL=C sort -u || true
}

check_sets "deployment settings" "$CODE_SETTINGS" "$(doc_deploy_settings)"

check_references "$DEPLOY_MD"

# --- architecture/system-model.md: the shape the system is drawn with -------
#
# The system model says how big the system is: how many domains it organises
# content around, and how many pages it serves. Both are counts, and both
# are the tree's.
#
# They are written in words, and a word is a count too. The match is
# case-insensitive, because a count at the start of a sentence is
# capitalised -- "Ten public pages" is the same claim as "ten public pages".

SYSTEM_MODEL_MD="architecture/system-model.md"

# The ring's domains: the tuples ring_domains() names.
count_ring_domains() {
  awk '
    /pub fn ring_domains\(\)/ { inside = 1 }
    inside && /^\}/ { exit }
    inside { n += gsub(/\("[a-z]+",/, "&") }
    END { print n + 0 }
  ' backend/pages.mbt
}

RING_DOMAINS=$(count_ring_domains)
PAGE_COUNT=$(count_seed_pages)

check_word_count "system model domains" "domains" "$RING_DOMAINS" "$SYSTEM_MODEL_MD"
check_word_count "system model ring domains" "ring domains" "$RING_DOMAINS" "$SYSTEM_MODEL_MD"
check_word_count "system model pages" "public pages" "$PAGE_COUNT" "$SYSTEM_MODEL_MD"

# The two entry points the model's table names have to be there.
check_exists "system model backend" "cmd/server/main.mbt"
check_exists "system model frontend" "cmd/web/main.mbt"

# --- architecture/flows.md: the paths the requests take ----------------------
#
# The flow document traces what happens on the way in and out, and it counts
# as it goes: the routes the API builds, the pages the seed makes, the
# columns a page row has. All three are the tree's, and a flow that says
# "registers 37 routes" when the server registers thirty-eight is a flow a
# reader cannot follow.
#
# The pages are counted two ways, because there are two different numbers
# about them: seed_pages() returns the ring domains and the other three, and
# the server seeds those plus an index page and a not-found page. The count
# the flow document states is the count of the function.

FLOWS_MD="architecture/flows.md"

check_claim_number "flow routes" 'registers ([0-9]+) routes' \
  "$(count_routes)" "$FLOWS_MD"
check_claim_number "flow seed pages" 'seed_pages\(\)[^0-9]+([0-9]+) pages via UPSERT' \
  "$(count_seed_pages_only)" "$FLOWS_MD"
check_claim_number "flow page bodies" '\(([0-9]+) pages, hardcoded HTML bodies\)' \
  "$(count_seed_pages_only)" "$FLOWS_MD"
check_claim_number "flow page columns" 'bind\(([0-9]+) params\)' \
  "$(count_page_columns)" "$FLOWS_MD"

check_stated "ci.sh header gates" "$CI_GATES" \
  "$(flat_number "$CI_FLAT" 'runs all ([0-9]+) of them')" "ci.sh's header"
check_stated "agent guide gates" "$CI_GATES" \
  "$(flat_number "$AGENTS_FLAT" 'holds ([0-9]+) gates')" "AGENTS.md"
check_stated "ci.sh header workflow" "$WORKFLOW_GATES" \
  "$(flat_number "$CI_FLAT" 'runs the ([0-9]+) of them that a push is checked against')" \
  "ci.sh's header"
check_stated "agent guide workflow" "$WORKFLOW_GATES" \
  "$(flat_number "$AGENTS_FLAT" 'runs the ([0-9]+) that a push is checked against')" \
  "AGENTS.md"

check_workflow_scripts "workflow scripts" "$WORKFLOW_SCRIPTS" "$CI_SCRIPTS"

# --- architecture/*.dot: the graphs against the tree --------------------------
#
# The graphs are pictures of the tree, and a picture rots the way a document
# rots. The component graph kept the seven backend modules the project
# started with and still said four API endpoints when the server registers
# thirty-seven; the flow graph still said four routes in the step that builds
# the API.
#
# Two claims are checked. The MODULES are the tree's: the component graph
# names every module the project has, and every module it names is one the
# project has. The COUNT is the tree's: every graph that says how many routes
# the API builds says the number the server registers.
#
# The escapes are read before the names are taken. A label in a DOT file
# separates its lines with a backslash and an n, and that n is a letter: a
# name that follows an escape would be read as part of it. So the escapes
# become spaces first, and the names are read out of what is left.

SYSTEM_MODEL_DOT="architecture/system-model.dot"

# The modules the tree has, as package/module. A test file is not a module:
# the graph shows what the system is made of, not what it is checked with.
tree_modules() {
  local pkg file base
  for pkg in backend frontend cmd/server cmd/web cmd/mcp; do
    for file in "$pkg"/*.mbt; do
      [ -e "$file" ] || continue
      base="${file##*/}"
      case "$base" in
        *_test.mbt|*_wbtest.mbt) continue ;;
      esac
      printf '%s/%s\n' "$pkg" "$base"
    done
  done | LC_ALL=C sort -u
}

# The modules the component graph names, the same way. The escapes go first:
# a backslash and an n is two characters, and the n is a letter the next name
# would be read as part of.
graph_modules() {
  sed 's/\\n/ /g' "$SYSTEM_MODEL_DOT" \
    | grep -oE '[A-Za-z0-9_]+(/[A-Za-z0-9_]+)*\.mbt' | LC_ALL=C sort -u || true
}

check_sets "component graph modules" "$(tree_modules)" "$(graph_modules)"

# The route counts the graphs state: the file, and the number it says.
graph_route_claims() {
  local file
  for file in $(printf '%s\n' architecture/*.dot | LC_ALL=C sort); do
    [ -e "$file" ] || continue
    grep -oE '[0-9]+ (JSON endpoints|routes)' "$file" | while IFS= read -r claim; do
      printf '%s %s\n' "$file" "$claim"
    done
  done
}

# Every graph that states a route count has to state the tree's.
check_graph_routes() {
  local claims="$1" actual="$2" line file rest number count=0 before="$FAILURES"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    count=$((count + 1))
    file="${line%% *}"
    rest="${line#* }"
    number="${rest%% *}"
    if [ "$number" != "$actual" ]; then
      fail "$(printf '%-22s the tree has %s, %s says %s' \
        'graph routes' "$actual" "$file" "$number")"
    fi
  done <<< "$claims"
  if [ "$count" -eq 0 ]; then
    fail "$(printf '%-22s no graph states the route count' 'graph routes')"
    return
  fi
  if [ "$FAILURES" -eq "$before" ]; then
    ok "graph routes" "$actual"
  fi
}

check_graph_routes "$(graph_route_claims)" "$(count_routes)"

# --- architecture/dependencies.dot: the dependency graph against the tree -----
#
# The dependency graph says what depends on what. It was a picture of the
# project on the first day: seven backend modules, a frontend of four, no
# agent's server, and none of the packages the tree actually leans on -- not
# the model the whole loop runs on, not the regression it reports, not the
# protocol the agent speaks.
#
# Three claims are checked. The PACKAGES are the tree's: every package the
# tree has is named, and every package named is one the tree has. The
# IMPORTS are the tree's: every external import path the tree declares is
# named, and every path named is one the tree declares. The PINS are the
# tree's: every version the graph states is the version the manifest pins.
#
# A claim is read off the FIRST line of a label, because that is where the
# import path is written. The lines under it say what the package is for,
# and a line that happens to mention a path is a sentence, not a claim.

DEPENDENCIES_DOT="architecture/dependencies.dot"

# The first line of every label in the graph.
graph_label_heads() {
  grep -oE 'label="[^"]*"' "$DEPENDENCIES_DOT" \
    | sed -E 's/^label="//; s/\\n.*$//; s/"$//'
}

# The packages the graph names: a first line that is a package name.
graph_packages() {
  graph_label_heads | grep -E '^[a-z]+(/[a-z]+)?/$' | LC_ALL=C sort -u
}

# The packages the tree has: the directories that hold a moon.pkg.
tree_packages() {
  find backend frontend cmd -name moon.pkg 2>/dev/null \
    | sed -E 's|/moon\.pkg$||; s|$|/|' | LC_ALL=C sort -u
}

check_sets "graph packages" "$(tree_packages)" "$(graph_packages)"

# The external imports the graph names: a first line that is an import path.
graph_imports() {
  graph_label_heads \
    | grep -E '^[A-Za-z][A-Za-z0-9_-]*(/[A-Za-z0-9_.-]+)+(@[0-9]+\.[0-9]+\.[0-9]+)?$' \
    | sed -E 's/@[0-9]+\.[0-9]+\.[0-9]+$//' | LC_ALL=C sort -u
}

# The import blocks of the manifests, without their comments.
manifest_blocks() {
  local file
  for file in moon.mod backend/moon.pkg frontend/moon.pkg \
              cmd/server/moon.pkg cmd/web/moon.pkg cmd/mcp/moon.pkg; do
    awk '
      /^import \{/ { inside = 1; next }
      inside && /^\}/ { inside = 0; next }
      inside { print }
    ' "$file"
  done
}

# The external imports the tree declares. The core packages and the
# project's own packages are left out: they are not dependencies on anything
# outside the tree.
tree_imports() {
  manifest_blocks \
    | grep -oE '"[A-Za-z][A-Za-z0-9_-]*/[A-Za-z0-9_./-]+(@[0-9][0-9.]*)?"' \
    | tr -d '"' | sed -E 's/@[0-9][0-9.]*$//' \
    | grep -vE '^moonbitlang/core/' | grep -vE '^riantr/MAKED(/|$)' \
    | LC_ALL=C sort -u
}

check_sets "graph imports" "$(tree_imports)" "$(graph_imports)"

# The versions the graph states: name@version.
graph_pins() {
  graph_label_heads | grep -oE '[A-Za-z0-9_-]+@[0-9]+\.[0-9]+\.[0-9]+' \
    | LC_ALL=C sort -u
}

# The versions the manifests pin: the last segment of the path, and the
# version.
tree_pins() {
  manifest_blocks \
    | grep -oE '"[A-Za-z][A-Za-z0-9_-]*/[A-Za-z0-9_./-]+@[0-9][0-9.]*"' \
    | tr -d '"' | awk -F'@' '{ n = split($1, parts, "/"); print parts[n] "@" $2 }' \
    | LC_ALL=C sort -u
}

check_sets "graph pins" "$(tree_pins)" "$(graph_pins)"

# --- the graphs and the model: the API they promise, the settings they name --
#
# The contract note in the dependency graph and the handler list in the
# deployment graph both say what the API looks like from the outside. Both
# had stopped saying /api/model, which the server has registered since the
# model became a file the reader brings.
#
# The deployment graph also names the variables the server reads, and the
# model DSL names a route and a number of domains. All three are the tree's.

DEPLOY_DOT="architecture/deployment.dot"
SYSTEM_MODEL_DSL="architecture/system-model.dsl"

# The API families the tree serves: the first two segments of every route.
tree_api_families() {
  tr '\n' ' ' < backend/api.mbt \
    | grep -oE 'app\.(get|post|put|delete|patch)\("/api/[^"]+"' \
    | grep -oE '"/api/[^"]+"' | tr -d '"' \
    | sed -E 's|^(/api/[^"/]+).*|\1|' | LC_ALL=C sort -u
}

# The API families a graph names.
graph_api_families() {
  grep -oE '/api/[a-z-]+' "$1" | LC_ALL=C sort -u
}

check_sets "contract endpoints" "$(tree_api_families)" \
  "$(graph_api_families "$DEPENDENCIES_DOT")"
check_sets "topology endpoints" "$(tree_api_families)" \
  "$(graph_api_families "$DEPLOY_DOT")"

# The variables the server reads.
code_variable_names() {
  printf '%s\n' "$CODE_SETTINGS" | awk '{ print $1 }' | LC_ALL=C sort -u
}

# The variables the deployment graph names.
graph_variables() {
  grep -oE 'MAKED_[A-Z_]+' "$DEPLOY_DOT" | LC_ALL=C sort -u
}

check_sets "topology variables" "$(code_variable_names)" "$(graph_variables)"

# Every route the server registers.
tree_routes() {
  tr '\n' ' ' < backend/api.mbt \
    | grep -oE 'app\.(get|post|put|delete|patch)\("/api/[^"]+"' \
    | grep -oE '"/api/[^"]+"' | tr -d '"' | LC_ALL=C sort -u
}

# The routes the model names.
dsl_routes() {
  grep -oE '/api/[A-Za-z0-9/:_.-]+' "$SYSTEM_MODEL_DSL" | LC_ALL=C sort -u
}

# Every route the model names has to be a route the server registers.
check_dsl_routes() {
  local named="$1" actual="$2" line missing=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if ! printf '%s\n' "$actual" | grep -qxF "$line"; then
      missing="$missing $line"
    fi
  done <<< "$named"
  if [ -n "$missing" ]; then
    fail "$(printf '%-22s the model names [%s], the server does not register them' \
      'dsl routes' "$(printf '%s' "$missing" | sed -e 's/^ *//')")"
    return
  fi
  count_lines "$named"
  ok "dsl routes" "$COUNT_LINES"
}

check_dsl_routes "$(dsl_routes)" "$(tree_routes)"

# The number of domains the model states, in words. The model writes it as
# "Five-domain", so the word is the one in front of the hyphen.
dsl_domain_words() {
  grep -oiE '\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)-domain' \
    "$SYSTEM_MODEL_DSL" | grep -oiE '^[a-z]+' | tr 'A-Z' 'a-z' | LC_ALL=C sort -u
}

check_dsl_domains() {
  local words="$1" expected="$2" word number bad=""
  for word in $words; do
    number=$(word_number "$word")
    if [ -z "$number" ] || [ "$number" != "$expected" ]; then
      bad="$bad $word"
    fi
  done
  if [ -z "$words" ]; then
    fail "$(printf '%-22s the model does not state the count in words' 'dsl domains')"
    return
  fi
  if [ -n "$bad" ]; then
    fail "$(printf '%-22s the model says [%s], the tree has %s' \
      'dsl domains' "$(printf '%s' "$bad" | sed -e 's/^ *//')" "$expected")"
    return
  fi
  ok "dsl domains" "$expected"
}

check_dsl_domains "$(dsl_domain_words)" "$RING_DOMAINS"

# --- models/product-iteration.yaml: the machine file states its own size -----
#
# The example machine says in its header how big it is: three domains, seven
# positions, four slots, twenty-eight rules. Those numbers were true when
# they were written, and nothing checked them, so the day the machine grew
# a slot the header would have kept saying four and the reader would have
# believed it.
#
# The numbers are now checked against the file they describe. The header
# says them in digits, because a header that a gate can read is a header
# that a gate can keep right.

MODEL_YAML="models/product-iteration.yaml"

# The number of entries in one section of the machine file. The sections are
# the top-level keys, and an entry is a line that starts with a dash.
model_section_count() {
  local section="$1"
  awk -v want="$section" '
    /^[a-z_]+:/ { inside = ($0 == want ":") ? 1 : 0; next }
    inside && /^  - / { n++ }
    END { print n + 0 }
  ' "$MODEL_YAML"
}

# The number the header states next to a phrase. The header is the comment
# at the top of the file, so only the comments are read.
model_claim() {
  grep -E '^[[:space:]]*#' "$MODEL_YAML" \
    | grep -oE "[0-9]+ $1" | grep -oE '[0-9]+' | head -1 || true
}

check_model_claim() {
  local label="$1" phrase="$2" section="$3"
  check_stated "$label" "$(model_section_count "$section")" \
    "$(model_claim "$phrase")" "the machine file"
}

check_model_claim "model domains" "domains" "domains"
check_model_claim "model positions" "positions" "positions"
check_model_claim "model slots" "slots" "slots"
check_model_claim "model rules" "rules" "rules"
check_model_claim "model outcomes" "outcomes" "outcomes"

# The files the header names. A header that points at a file that is not
# there sends the reader to nothing, and the file it names is the machine's
# twin -- the one the header says is the same machine.
model_named_files() {
  grep -E '^[[:space:]]*#' "$MODEL_YAML" \
    | grep -oE '[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+\.[A-Za-z0-9]+' \
    | LC_ALL=C sort -u
}

check_model_files() {
  local named="$1" file missing=""
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    if [ ! -f "$file" ]; then
      missing="$missing $file"
    fi
  done <<< "$named"
  if [ -n "$missing" ]; then
    fail "$(printf '%-22s the machine file names [%s], which are not there' \
      'model files' "$(printf '%s' "$missing" | sed -e 's/^ *//')")"
    return
  fi
  count_lines "$named"
  ok "model files" "$COUNT_LINES"
}

check_model_files "$(model_named_files)"

echo ""
if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES claim(s) in the documents do not match the tree."
  echo "*** FAIL ***"
  echo ""
  echo "The documents state a claim and the tree has another. Fix the documents,"
  echo "or fix the tree -- but make the two agree before saying anything about"
  echo "either of them."
  exit 1
fi
echo "Every claim in the documents matches the tree."
exit 0
