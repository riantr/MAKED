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
  while [[ "$rest" =~ \`([A-Za-z0-9_./-]+\.(mbt|moon\.pkg|ps1|sh|mod|dsl|dot|md)|Dockerfile):([0-9]+)(-([0-9]+))?\` ]]; do
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

# --- the links the documents carry --------------------------------------------
#
# A document that links at a file that is not there sends the reader to
# nothing, and the reader cannot tell that the link is broken -- it looks
# exactly like a link that works. The references above check the pointers
# written as `file.ext:line`; this one checks the pointers written as
# markdown links.
#
# The links are read from every document the repository ships, apart from the
# README: the README has a gate of its own, and a fact is watched in one
# place only. The vendored dependency cache and the build output are pruned --
# they are not documents of this project, and a broken link in somebody else's
# cache is not this project's rot.
#
# A link is RELATIVE when it does not begin with a scheme, so a link to a
# page on the web is left alone. A fragment is dropped: `page.md#section`
# points at a place inside a file, and it is the file that has to be there.
#
# The link is resolved against the DIRECTORY OF THE DOCUMENT, which is where a
# reader's browser resolves it from. A document that was moved has to have its
# links moved with it, and that is the whole of this check.

doc_files() {
  find . \( -name '.mooncakes' -o -name '_build' -o -name '.git' -o -name 'node_modules' \) -prune -o \
    -type f \( -name '*.md' -o -name '*.txt' \) -print \
    | sed -E 's|^\./||' | LC_ALL=C sort
}

# The relative links the documents carry, as "document directory link".
doc_links() {
  local link_doc link_dir
  while IFS= read -r link_doc; do
    [ -n "$link_doc" ] || continue
    [ "$link_doc" = "README.md" ] && continue
    link_dir="$(dirname "$link_doc")"
    grep -oE '\]\([^)]+\)' "$link_doc" 2>/dev/null \
      | sed -E 's/^\]\(//; s/\)$//' \
      | sed -E 's/^[[:space:]]*([^[:space:]]*).*$/\1/' \
      | grep -vE '^#' \
      | grep -vE '^[a-zA-Z][a-zA-Z0-9+.-]*:' \
      | sed -E 's/#.*$//' \
      | grep -vE '^$' \
      | while IFS= read -r link_text; do
          printf '%s %s %s\n' "$link_doc" "$link_dir" "$link_text"
        done || true
  done <<< "$(doc_files)"
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
  fail "$(printf '%-22s these links point at files that are not there:%s' \
    'Document links' "$BROKEN_LINKS")"
else
  ok "Document links" "$LINK_COUNT"
fi

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

# --- the port the container publishes ------------------------------------------
#
# The port is one number in this project, and it is written in five places:
# the server's default, the Dockerfile's environment, the Dockerfile's EXPOSE
# line, the compose file's environment, and the mapping the compose file
# publishes. They all have to be the same one.
#
# The Dockerfile sets MAKED_PORT itself, so a container keeps working even
# when the server's default moves -- which is exactly why the drift is
# invisible. The reader is told to open one port and the container listens
# on another, and the symptom is a browser that waits and then says the
# connection was refused.
#
# The server's default is the source: it is the port the server listens on
# when nothing sets it, and every other number has to be that one.

code_default_port() {
  grep -ohE 'env_or\("MAKED_PORT", "[0-9]+"\)' cmd/server/main.mbt \
    | sed -E 's/.*"([0-9]+)".*/\1/' | head -1 || true
}

# The ports the Dockerfile writes: the one it sets, the one it exposes, and
# the mapping in the command its own header tells the reader to run.
dockerfile_ports() {
  grep -oE 'MAKED_PORT=[0-9]+' Dockerfile | sed -E 's/.*=//' || true
  grep -oE '^EXPOSE [0-9]+' Dockerfile | sed -E 's/^EXPOSE //' || true
  grep -oE '\-p [0-9]+:[0-9]+' Dockerfile | sed -E 's/\-p //' | tr ':' '\n' || true
}

# The ports the compose file writes: the one it sets and the two sides of
# the mapping it publishes.
compose_ports() {
  grep -oE 'MAKED_PORT: "[0-9]+"' docker-compose.yml | sed -E 's/.*: "//; s/"$//' || true
  grep -oE '"[0-9]+:[0-9]+"' docker-compose.yml | tr -d '"' | tr ':' '\n' || true
}

DEFAULT_PORT=$(code_default_port)
WRONG_PORT=""
while IFS= read -r port; do
  [ -n "$port" ] || continue
  if [ "$port" != "$DEFAULT_PORT" ]; then
    WRONG_PORT="$WRONG_PORT $port"
  fi
done <<< "$( { dockerfile_ports; compose_ports; } )"
if [ -z "$DEFAULT_PORT" ]; then
  fail "$(printf '%-22s the server does not name a default port' 'container port')"
elif [ -n "$WRONG_PORT" ]; then
  fail "$(printf '%-22s the server uses %s, and these ports are not it:%s' \
    'container port' "$DEFAULT_PORT" "$WRONG_PORT")"
else
  ok "container port" "$DEFAULT_PORT"
fi

# --- what the Dockerfile says about itself -------------------------------------
#
# The Dockerfile's header is a document like any other: it tells the reader
# how to run the image, and it states two things about the file that have
# to be true.
#
# The healthcheck asks the server a question, and the question has to be
# one the server answers. A healthcheck that asks for a route that is not
# there fails every time, and the container is reported unhealthy while the
# server inside it is working perfectly.
#
# The two stages have to be built on the same image, and the file says so:
# a binary built against a newer glibc than the runtime image has fails at
# start-up with a version error that reads like a corrupt download.

HEALTHCHECK_PATHS=$(grep -oE '/api/[a-z0-9/_-]+' Dockerfile | LC_ALL=C sort -u || true)
if [ -z "$HEALTHCHECK_PATHS" ]; then
  fail "$(printf '%-22s the Dockerfile asks the server nothing' 'healthcheck')"
else
  UNKNOWN_PATH=""
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if ! printf '%s\n' "$TREE_ENDPOINTS" | awk '{ print $2 }' | grep -qxF "$path"; then
      UNKNOWN_PATH="$UNKNOWN_PATH $path"
    fi
  done <<< "$HEALTHCHECK_PATHS"
  if [ -n "$UNKNOWN_PATH" ]; then
    fail "$(printf '%-22s the server does not serve:%s' 'healthcheck' "$UNKNOWN_PATH")"
  else
    ok "healthcheck" "$(printf '%s\n' "$HEALTHCHECK_PATHS" | tr '\n' ' ' | sed -e 's/ *$//')"
  fi
fi

BASE_IMAGES=$(grep -oE '^FROM [^ ]+' Dockerfile | sed -E 's/^FROM //' | LC_ALL=C sort -u || true)
if [ -z "$BASE_IMAGES" ]; then
  fail "$(printf '%-22s no base image could be derived from the Dockerfile' 'base image')"
elif [ "$(printf '%s\n' "$BASE_IMAGES" | grep -c .)" -gt 1 ]; then
  fail "$(printf '%-22s the stages are built on different images: [%s]' \
    'base image' "$(printf '%s\n' "$BASE_IMAGES" | tr '\n' ' ' | sed -e 's/ *$//')")"
else
  ok "base image" "$(printf '%s\n' "$BASE_IMAGES" | head -1)"
fi

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
#
# The marker is also how a document opts out of the count checks: the graphs
# that say they describe the past are the ones that are not counted against
# the tree. That is the right way round -- the document says what it is --
# but it means the marker has to be checked against something. A graph that
# claimed to be history and was not one of the seven would slip out of the
# count checks without anybody noticing, so the gate knows which documents
# are history, and the two sets have to be the same set.
#
# The documents are read once: the marker is looked for in each of them, and
# the answer is used for the header check and for the check that the two sets
# are the same set.

# The documents the gate knows as history.
PAST_DOCS="architecture/evolution.md
architecture/evolution.evidence.md
architecture/evolution.dot
architecture/evolution-summary.md
architecture/evolution-roadmap.md
architecture/current-vs-target.dot
architecture/migration-dependency.dot"

# The documents that carry the marker, as the tree says it. Every document
# in the architecture folder is a candidate: the marker is what makes one of
# them history.
marked_documents() {
  local file
  for file in architecture/*.md architecture/*.dot; do
    [ -e "$file" ] || continue
    if grep -qF 'This document describes the past.' "$file"; then
      printf '%s\n' "$file"
    fi
  done | LC_ALL=C sort -u
}

MARKED_DOCS=$(marked_documents)

check_past_header() {
  local doc="$1"
  # The marker has already been looked for: the answer is in MARKED_DOCS.
  not_in "$doc" "$MARKED_DOCS"
  if [ -z "$NOT_IN" ]; then
    ok "past header" "$doc"
  else
    fail "$(printf '%-22s %s does not say that it describes the past' \
      'past header' "$doc")"
  fi
}

while IFS= read -r doc; do
  [ -n "$doc" ] || continue
  check_past_header "$doc"
done <<< "$PAST_DOCS"

# The three graphs say it in their title as well, because a title is what a
# reader sees once the graph is rendered. A graph that keeps the marker in its
# source and loses it from its picture has lost it for half its readers,
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

# The graphs are the documents on the list that are graphs.
while IFS= read -r doc; do
  [ -n "$doc" ] || continue
  case "$doc" in
    *.dot) check_past_title "$doc" ;;
  esac
done <<< "$PAST_DOCS"

# Every document that carries the marker is one the gate knows as history. A
# document that is not on the list has slipped out of the count checks.
check_past_documents() {
  not_in "$MARKED_DOCS" "$PAST_DOCS"
  if [ -z "$NOT_IN" ]; then
    count_lines "$MARKED_DOCS"
    ok "past documents" "$COUNT_LINES"
    return
  fi
  fail "$(printf '%-22s the tree says [%s] describes the past, and the gate does not know it' \
    'past documents' "$NOT_IN")"
}

check_past_documents

# The number of documents that describe the past, as AGENTS.md states it. The
# word is read like any other count: "SEVEN of them describe the PAST" is a
# claim about the tree, and the tree has seven. It was four once, and the
# three graphs that joined the history were never counted.
check_word_count "agent guide past" "of them describe the PAST" \
  "$(printf '%s\n' "$MARKED_DOCS" | grep -c .)" "$AGENTS_DOC"

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

# The arguments each tool takes, as "tool argument" pairs.
#
# The tool says which schema it has, and the schema says which arguments it
# has, so the two are followed rather than copied. The schema functions come
# first in the file and the tool specs after, so one pass is enough: the
# schemas are collected as they are met, and the tool specs are answered from
# what was collected.
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

# The arguments AGENT.md's table gives each tool, as "tool argument" pairs.
# The arguments sit in the second column, and a tool that takes none says so
# with a dash rather than with an empty cell.
doc_tool_args() {
  grep -oE '^\| `maked_[a-z_]+` \| [^|]*\|' "$AGENT_DOC" \
    | sed -E 's/^\| `([^`]+)` \| ([^|]*)\|/\1|\2/' \
    | while IFS='|' read -r tool cell; do
        for arg in $(printf '%s' "$cell" | grep -oE '`[^`]+`' | tr -d '`'); do
          printf '%s %s\n' "$tool" "$arg"
        done
      done | LC_ALL=C sort -u
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

# The endpoints the discovery document lists, each with the tool that answers
# it, as "METHOD path tool".
#
# The tool follows the path in the source, so the two are read together
# rather than matched up afterwards. A table that sends a reader to the wrong
# tool for a path is a table that answers a different question than the one
# it names.
code_endpoint_mappings() {
  tr '\n' ' ' < backend/agent.mbt \
    | grep -oE '"method": "[A-Z]+", *"path": "[^"]+", *"tool": "maked_[a-z_]+"' \
    | sed -E 's/"method": "([A-Z]+)", *"path": "([^"]+)", *"tool": "(maked_[a-z_]+)"/\1 \2 \3/' \
    | LC_ALL=C sort -u || true
}

# The same endpoints as AGENT.md's table gives them, each with the tool it
# names.
doc_endpoint_mappings() {
  grep -oE '^\| `(GET|POST|PUT|DELETE|PATCH)` \| `/api/[^`]+` \| `maked_[a-z_]+`' "$AGENT_DOC" \
    | sed -E 's/^\| `([A-Z]+)` \| `([^`]+)` \| `(maked_[a-z_]+)`/\1 \2 \3/' \
    | LC_ALL=C sort -u || true
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

# The formats the discovery document pairs with the variables it names, as
# "variable format".
#
# The discovery document is what the server ANSWERS with, so a format it
# names wrongly is a format it tells an agent to write and then refuses.
code_file_formats() {
  tr '\n' ' ' < backend/agent.mbt \
    | grep -oE '"variable": "MAKED_[A-Z_]+", *"format": "[^"]+"' \
    | sed -E 's/"variable": "([^"]+)", *"format": "([^"]+)"/\1 \2/' \
    | LC_ALL=C sort -u || true
}

# The formats the backend actually accepts, paired with the variable that
# names the file, as "variable format".
#
# Each backend file owns ONE format constant and reads ONE environment
# variable, so the pair is read from the file that holds both: the model file
# declares the format a model is written in and is the file MAKED_MODEL names.
# A file that owns more than one of either is not paired -- the gate would
# rather say it cannot tell than guess.
backend_file_formats() {
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
# The files the discovery document names, each with the variable that names
# it, as "file variable".
#
# The file is what the document calls it -- "the machine", "the corpus" --
# and the variable is the one that points at it. Both are read from the
# discovery document, which is what the server answers with.
code_file_names() {
  tr '\n' ' ' < backend/agent.mbt \
    | grep -oE '"what": "[^"]+", *"variable": "MAKED_[A-Z_]+"' \
    | sed -E 's/"what": "([^"]+)", *"variable": "([^"]+)"/\1|\2/' \
    | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $1); print tolower($1), $2 }' \
    | LC_ALL=C sort -u || true
}

# The same files as AGENT.md's table gives them, each with the variable it
# names.
#
# The row is read as a pair: the first column names the file, and the
# variable in the second column is the one that points at it.
doc_file_names() {
  grep -oE '^\| [^|]+ \| `MAKED_[A-Z_]+` \|' "$AGENT_DOC" \
    | sed -E 's/^\| ([^|]+) \| `(MAKED_[A-Z_]+)` \|/\1|\2/' \
    | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $1); print tolower($1), $2 }' \
    | LC_ALL=C sort -u || true
}
# The entry point the discovery document names, and the one the document
# states. An agent that calls the wrong one gets nowhere, so the method the
# server tells it to call and the method AGENT.md tells it to call have to
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
  tr '\n' ' ' < "$AGENT_DOC" | tr -s ' ' \
    | grep -oE 'entry point is `[^`]+`' \
    | grep -oE '`[^`]+`' | tr -d '`' | head -1 || true
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
CODE_TOOL_ARGS=$(code_tool_args)
DOC_TOOL_ARGS=$(doc_tool_args)
CODE_ENDPOINTS=$(code_endpoints)
DOC_ENDPOINTS=$(doc_endpoints)
DOC_ENDPOINT_TOOLS=$(doc_endpoint_tools)
CODE_ENDPOINT_MAPPINGS=$(code_endpoint_mappings)
DOC_ENDPOINT_MAPPINGS=$(doc_endpoint_mappings)
CODE_FILE_VARS=$(code_file_vars)
CODE_ENV_READS=$(code_env_reads)
DOC_FILE_VARS=$(doc_file_vars)
CODE_ENTRY_POINT=$(code_entry_point)
DOC_ENTRY_POINT=$(doc_entry_point)

CODE_PROTOCOL=$(code_protocol)
DOC_PROTOCOLS=$(doc_protocols)

check_sets "agent tools" "$CODE_TOOLS" "$DOC_TOOLS"

# The arguments the document gives each tool have to be the arguments the
# tool takes. An agent that reads a table without an argument will not send
# it, and the answer it gets back is not the answer it asked for.
check_sets "agent arguments" "$CODE_TOOL_ARGS" "$DOC_TOOL_ARGS"

count_lines "$CODE_TOOLS"
check_word_count "agent tools (words)" "tools" "$COUNT_LINES" "$AGENT_DOC"

check_sets "agent files" "$CODE_FILE_VARS" "$DOC_FILE_VARS"

count_lines "$CODE_FILE_VARS"
check_word_count "agent files (words)" "files" "$COUNT_LINES" "$AGENT_DOC"

# The discovery document has to offer the variables the code reads.
check_sets "agent files (code)" "$CODE_FILE_VARS" "$CODE_ENV_READS"

# And the format it pairs with each of them has to be the one the loader
# accepts. The document is what the server answers with, so a format it
# names wrongly is a format it tells an agent to write and then refuses --
# and the variables being right does not make the formats right.
check_sets "agent file formats" "$(code_file_formats)" "$(backend_file_formats)"

# The document has to name the RIGHT variable for each file. The variables
# are checked as a set above, and a set does not say which file each one
# names: a table that gives the machine the corpus's variable still has the
# same four variables in it, and a reader who follows it points MAKED_MODEL
# at the wrong file.
check_sets "agent file names" "$(code_file_names)" "$(doc_file_names)"

# The entry point is what an agent calls first, and the server tells it one
# method while the document may tell it another. An agent that calls the
# wrong one gets nowhere.
if [ -z "$CODE_ENTRY_POINT" ]; then
  fail "$(printf '%-22s the tree does not name an entry point' 'agent entry point')"
elif [ -z "$DOC_ENTRY_POINT" ]; then
  fail "$(printf '%-22s the document does not state the entry point' 'agent entry point')"
elif [ "$CODE_ENTRY_POINT" != "$DOC_ENTRY_POINT" ]; then
  fail "$(printf '%-22s the tree says %s, the document says %s' \
    'agent entry point' "$CODE_ENTRY_POINT" "$DOC_ENTRY_POINT")"
else
  ok "agent entry point" "$CODE_ENTRY_POINT"
fi

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

# And the table has to point at the RIGHT tool for each path. The endpoint
# list and the tool names are checked on their own above, and neither of them
# says which tool answers which path -- so a table that sends a reader to the
# wrong tool passes both of them.
check_sets "endpoint mapping" "$CODE_ENDPOINT_MAPPINGS" "$DOC_ENDPOINT_MAPPINGS"

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
# The path the agent's server speaks HTTP on. The code hands the path to the
# server, and the document has to name the same one: an agent that posts to a
# path the server does not serve gets nothing back.
#
# The claim is found by its own shape -- the sentence that says the server
# speaks HTTP, and the path at the end of it -- so a path named somewhere
# else in the document is not read as a claim about this one.
code_agent_path() {
  grep -oE 'run_http\([^)]*path="[^"]+"' cmd/mcp/main.mbt \
    | sed -E 's/.*path="([^"]+)".*/\1/' | head -1 || true
}

doc_agent_path() {
  tr '\n' ' ' < "$AGENT_DOC" | tr -s ' ' \
    | grep -oE 'speaks HTTP[^.]*at `[^`]+`' \
    | grep -oE '`[^`]+`' | tr -d '`' | head -1 || true
}

CODE_AGENT_PATH=$(code_agent_path)
DOC_AGENT_PATH=$(doc_agent_path)
if [ -z "$CODE_AGENT_PATH" ]; then
  fail "$(printf '%-22s the tree does not name the path the agent server serves' 'agent server path')"
elif [ -z "$DOC_AGENT_PATH" ]; then
  fail "$(printf '%-22s the document does not state the path' 'agent server path')"
elif [ "$CODE_AGENT_PATH" != "$DOC_AGENT_PATH" ]; then
  fail "$(printf '%-22s the tree says %s, the document says %s' \
    'agent server path' "$CODE_AGENT_PATH" "$DOC_AGENT_PATH")"
else
  ok "agent server path" "$CODE_AGENT_PATH"
fi

# --- the language switch the guide states ---------------------------------------
#
# AGENT.md tells an agent which language codes it may send, and the code is
# the source of the answer: Lang::code() gives the code each language
# answers to, and lang_from_query() says what an absent parameter means.
# Nothing compared the two, so a guide that named a code the server does
# not recognise would have been no more wrong than a README that did.
#
# The sentence is found by its own shape -- the words that introduce the
# codes -- and the codes are the quoted ones in it. The last one is the
# default's, because that is where the sentence puts it.

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

# The codes the guide states.
doc_lang_codes() {
  tr '\n' ' ' < "$AGENT_DOC" | tr -s ' ' \
    | grep -oE 'is the language to answer in[^.]*\.' \
    | grep -oE '`"[a-z]+"`' | tr -d '`"' | tr '\n' ' ' | sed -e 's/ *$//'
}

CODE_LANG_PAIRS=$(code_lang_pairs)
CODE_LANG_DEFAULT=$(code_lang_default)
DOC_LANG_CODES=$(doc_lang_codes)
CODE_LANG_CODES_LIST=$(printf '%s\n' "$CODE_LANG_PAIRS" | awk '{ print $2 }' \
  | LC_ALL=C sort -u | tr '\n' ' ' | sed -e 's/ *$//')
DOC_LANG_CODES_LIST=$(printf '%s\n' "$DOC_LANG_CODES" | sed -E 's/[[:space:]]+[^[:space:]]+$//' \
  | tr ' ' '\n' | LC_ALL=C sort -u | tr '\n' ' ' | sed -e 's/ *$//')
DOC_LANG_DEFAULT_CODE=$(printf '%s\n' "$DOC_LANG_CODES" | awk '{ print $NF }')
CODE_LANG_DEFAULT_CODE=$(lang_code_of "$CODE_LANG_DEFAULT" "$CODE_LANG_PAIRS")

if [ -z "$CODE_LANG_CODES_LIST" ]; then
  fail "$(printf '%-22s no language could be derived from the code' 'agent language switch')"
elif [ -z "$DOC_LANG_CODES" ]; then
  fail "$(printf '%-22s the document does not state the language codes' 'agent language switch')"
elif [ "$DOC_LANG_CODES_LIST" != "$CODE_LANG_CODES_LIST" ]; then
  fail "$(printf '%-22s the tree says [%s], the document says [%s]' \
    'agent language switch' "$CODE_LANG_CODES_LIST" "$DOC_LANG_CODES_LIST")"
elif [ "$DOC_LANG_DEFAULT_CODE" != "$CODE_LANG_DEFAULT_CODE" ]; then
  fail "$(printf '%-22s an absent parameter means [%s], the document says [%s]' \
    'agent language switch' "$CODE_LANG_DEFAULT_CODE" "$DOC_LANG_DEFAULT_CODE")"
else
  ok "agent language switch" "$CODE_LANG_CODES_LIST"
fi
# --- the protocol fields the guide states ---------------------------------------
#
# AGENT.md tells an agent how to wire itself up, and the fields every
# request's `params._meta` has to carry are the contract: an agent that
# spells one of them differently has every request it makes refused. The
# guide states them and MAKED's own discovery document states them, and
# nothing compared the two -- so a guide that spelled a field name
# differently would have gone unnoticed, and every request an agent made
# with it would have been refused.
#
# The discovery document is the source, because the discovery document is
# what the server ANSWERS with. Its note is where the protocol fields are
# written down, so that is where they are read from.
#
# The fields are found by the namespace they live in, which is specific
# enough to be read out of the whole guide: a name in another namespace is
# the name of something else.

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
  grep -oE '`io\.modelcontextprotocol/[A-Za-z]+`' "$AGENT_DOC" \
    | tr -d '`' \
    | LC_ALL=C sort -u
}

CODE_PROTOCOL_FIELDS=$(code_protocol_fields)
DOC_PROTOCOL_FIELDS=$(doc_protocol_fields)

if [ -z "$CODE_PROTOCOL_FIELDS" ] || [ -z "$DOC_PROTOCOL_FIELDS" ]; then
  fail "$(printf '%-22s the protocol fields could not be found on both sides' 'agent protocol fields')"
else
  check_sets "agent protocol fields" "$CODE_PROTOCOL_FIELDS" "$DOC_PROTOCOL_FIELDS"
fi

# --- the export formats the guide shows ----------------------------------------
#
# The guide shows the export URL an agent can call, and the format value in it
# has to be one the server answers. An export that asks for a format the
# handler does not know comes back as a 400 with "unknown_format", and an
# agent that copied the line finds that out the hard way.
#
# The tree is the handler, and the comparison is one way: the handler knows
# more formats than the guide shows.

code_export_formats() {
  awk '
    /app\.get\("\/api\/sessions\/:id\/export"/ { inside = 1 }
    inside && /^  \}\)$/ { exit }
    inside { print }
  ' backend/api.mbt | grep -oE 'Some\("[a-z]+"\)' | grep -oE '"[a-z]+"' | tr -d '"' \
    | LC_ALL=C sort -u
}

doc_export_formats() {
  grep -oE 'format=[a-z]+' "$AGENT_DOC" | sed -E 's/^format=//' \
    | LC_ALL=C sort -u
}

CODE_EXPORT_FORMATS=$(code_export_formats)
DOC_EXPORT_FORMATS=$(doc_export_formats)

not_in "$DOC_EXPORT_FORMATS" "$CODE_EXPORT_FORMATS"
EXPORT_FORMATS_MISSING="$NOT_IN"

if [ -z "$EXPORT_FORMATS_MISSING" ]; then
  count_lines "$DOC_EXPORT_FORMATS"
  ok "agent export formats" "$COUNT_LINES"
else
  fail "$(printf '%-22s the guide asks for [%s], and the server does not answer it' \
    'agent export formats' "$EXPORT_FORMATS_MISSING")"
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

# --- the release archive, as the note describes it ----------------------------
#
# The note that ships inside the archive is the first thing a reader of a
# release sees. It says what is in the archive: the executable, the browser
# files, the example machines under models/, the tables and the corpora under
# research/, and the folder under research/notes/ that one of those corpora
# names. A reader who unpacks the archive and finds no models/ has been told
# a lie by the note, and nothing checked it.
#
# The tree's answer is the release workflow: it is what puts the archive
# together, so what it stages under stage/maked is what the archive has.
#
# The corpus is the other side of the same promise. A corpus the tree ships
# that names a folder is a corpus that reads nothing unless the archive
# carries that folder -- the release workflow says so in its own words.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

ARCHIVE_BAD=0
ARCHIVE_CHECKED=0
ARCHIVE_PATHS=""
ARCHIVE_NOTE_DIRS=""
ARCHIVE_CORPUS_DIRS=""

# The paths the release workflow puts in the archive.
#
# Every path it stages lives under stage/maked, and the workflow writes them
# with a slash and with a backslash, so both are read.
code_archive_paths() {
  local path
  ARCHIVE_PATHS=""
  for path in $(grep -ohE 'stage[/\\]maked[/\\][A-Za-z0-9_.-]+([/\\][A-Za-z0-9_.-]+)*' \
      .github/workflows/publish.yml 2>/dev/null | tr '\\' '/'); do
    ARCHIVE_PATHS="$ARCHIVE_PATHS ${path#stage/maked/}"
  done
  # the list is built with a space in front of every name
  ARCHIVE_PATHS="${ARCHIVE_PATHS# }"
  ARCHIVE_PATHS="${ARCHIVE_PATHS% }"
}

# The directories the note names.
#
# A directory is written with a slash at the end, and a link is not a
# directory: the note's own URLs end with a slash too.
doc_note_dirs() {
  local text="$1" token
  ARCHIVE_NOTE_DIRS=""
  for token in $text; do
    case "$token" in
      *://*) continue ;;
    esac
    token="${token%%[.,;:!?)]*}"
    case "$token" in
      */) ;;
      *) continue ;;
    esac
    token="${token%/}"
    [ -n "$token" ] || continue
    ARCHIVE_NOTE_DIRS="$ARCHIVE_NOTE_DIRS $token"
  done
}

# The folders the corpora name.
#
# A corpus is a yaml file that says it is one, and a corpus that names a
# folder reads that folder.
code_corpus_dirs() {
  local file path
  ARCHIVE_CORPUS_DIRS=""
  for file in research/*.yaml; do
    [ -f "$file" ] || continue
    grep -qF 'maked.corpus.v1' "$file" 2>/dev/null || continue
    path=$(grep -oE '^ *path: *[^ "]+' "$file" 2>/dev/null | head -1 \
      | sed -E 's/^ *path: *//')
    [ -n "$path" ] || continue
    path="${path#./}"
    [ -n "$path" ] || continue
    ARCHIVE_CORPUS_DIRS="$ARCHIVE_CORPUS_DIRS $path"
  done
  # the list is built with a space in front of every name
  ARCHIVE_CORPUS_DIRS="${ARCHIVE_CORPUS_DIRS# }"
  ARCHIVE_CORPUS_DIRS="${ARCHIVE_CORPUS_DIRS% }"
}

# Does the archive have this path?
archive_has() {
  local name="$1" path
  for path in $ARCHIVE_PATHS; do
    [ "$path" = "$name" ] && return 0
    case "$path" in
      "$name"/*) return 0 ;;
    esac
  done
  return 1
}

# The archive, checked against what the note and the corpora say.
check_archive_claims() {
  local dir
  code_archive_paths
  doc_note_dirs "$(< "$RUN_NOTE")"
  code_corpus_dirs
  for dir in $ARCHIVE_NOTE_DIRS; do
    ARCHIVE_CHECKED=$((ARCHIVE_CHECKED + 1))
    if ! archive_has "$dir"; then
      fail "$(printf '%-22s the note says the archive has %s, and the release workflow does not stage it' \
        'release archive' "$dir")"
      ARCHIVE_BAD=1
    fi
  done
  for dir in $ARCHIVE_CORPUS_DIRS; do
    ARCHIVE_CHECKED=$((ARCHIVE_CHECKED + 1))
    if ! archive_has "$dir"; then
      fail "$(printf '%-22s the corpus names %s, and the release workflow does not stage it' \
        'release archive' "$dir")"
      ARCHIVE_BAD=1
    fi
  done
}

check_archive_claims

if [ "$ARCHIVE_BAD" -eq 0 ]; then
  ok "release archive" "$ARCHIVE_CHECKED claims"
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
# --- the pipeline and the batteries: how the project is built and verified ----
#
# The README is the package's front page, and the contributor's guide is
# AGENTS.md. The claims about the pipeline, the hook and the batteries
# belong to the contributor, so they live in the contributor's guide and the
# gate watches them there. A fact is watched in one place only, and the
# place moved with the claim.
#
# The job names come from the CI workflow. The COUNT is a count in words as
# well as a count in a list: a job that is renamed leaves the count right
# and the name wrong, and a reader watching the pipeline for "Build (js)" is
# watching for a job that is not there.
#
# The carriage returns go first: a file edited on Windows is the same file,
# and a gate that reads it differently depending on the line endings is a
# gate that lies.

code_job_names() {
  tr -d '\r' < .github/workflows/ci.yml | awk '
    /^jobs:/ { inside = 1; next }
    inside && /^    name: / { print substr($0, 11) }
  ' | LC_ALL=C sort -u
}

doc_job_names() {
  tr -d '\r' < "$AGENTS_DOC" | awk '
    /jobs, all of which have to be green/ { grab = 2 }
    grab > 0 {
      line = $0
      while (match(line, /\*\*[^*]+\*\*/)) {
        print substr(line, RSTART + 2, RLENGTH - 4)
        line = substr(line, RSTART + RLENGTH)
      }
      grab--
    }
  ' | LC_ALL=C sort -u
}

job_count() {
  tr -d '\r' < .github/workflows/ci.yml | awk '
    /^jobs:/ { inside = 1; next }
    inside && /^  [A-Za-z0-9_-]+:/ { n++ }
    END { print n + 0 }
  '
}

check_word_count "agent guide jobs" "jobs" "$(job_count)" "$AGENTS_DOC"

# The deployment evidence says how many jobs the CI workflow runs, and the
# count is the tree's: the job keys of .github/workflows/ci.yml. The agent
# guide's own count was watched; the deployment evidence's was not. The
# measurement that found the gap: the document said "seven jobs" where the
# workflow has six, and every gate still said that every claim in the
# documents matches the tree.
check_word_count "deploy jobs" "jobs" "$(job_count)" "$DEPLOY"

check_sets "CI jobs" "$(code_job_names)" "$(doc_job_names)"

# The hook the guide names, and the note beside it. A hook the guide does
# not mention is a hook a reader never finds.

tree_hooks() {
  find .githooks -maxdepth 1 -type f -print 2>/dev/null \
    | sed -E 's|^\./||; s|^\.githooks/||' | LC_ALL=C sort -u
}

doc_hooks() {
  tr -d '\r' < "$AGENTS_DOC" | grep -oE '\.githooks/[A-Za-z0-9_.-]+' \
    | sed -E 's|^\.githooks/||' | LC_ALL=C sort -u || true
}

check_sets "Git hooks" "$(tree_hooks)" "$(doc_hooks)"

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

# --- the paths the build writes, and the health check the image declares ------
#
# The deployment document says where the build puts its output, and it used to
# name a path the build never produces: the server is written under
# _build/native/release/build/cmd/server/, not under _build/native/release/cmd/.
# A reader who went looking for the file the document named would find
# nothing, and nothing in the document would say why.
#
# The tree is the scripts. They are the things that copy a file and run a
# file, so they are the things that name the paths -- and a path a script
# names is a path the build writes. The gate scripts are left out of the
# scan: they read the tree, they do not build from it, and a gate that named
# a path would be legitimising the very path it is here to catch.
#
# The comparison is one way. A document does not have to list every file the
# build writes, but every path it does list has to be one the tree writes.

tree_build_outputs() {
  grep -rhoaE '_build/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*' \
    --exclude='check-*.sh' --exclude='check-*.ps1' \
    build.ps1 Dockerfile tools .github 2>/dev/null \
    | LC_ALL=C sort -u || true
}

doc_build_outputs() {
  grep -ohaE '_build/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*' \
    "$DEPLOY_MD" "$DEPLOY" "$AGENT_DOC" "$AGENTS_DOC" 2>/dev/null \
    | LC_ALL=C sort -u || true
}

# Every path the document states has to be a path the tree builds.
check_build_outputs() {
  local label="$1" stated="$2" built="$3" missing
  not_in "$stated" "$built"; missing=$NOT_IN
  if [ -z "$missing" ]; then
    count_lines "$stated"
    ok "$label" "$COUNT_LINES"
    return
  fi
  fail "$(printf '%-22s the document states [%s], and the tree builds no such path' \
    "$label" "$missing")"
}

TREE_BUILD_OUTPUTS=$(tree_build_outputs)
DOC_BUILD_OUTPUTS=$(doc_build_outputs)

check_build_outputs "Build outputs" "$DOC_BUILD_OUTPUTS" "$TREE_BUILD_OUTPUTS"

# --- the health check the image declares -------------------------------------
#
# The deployment document listed "No health check endpoint" as a gap. The image
# declares one: the Dockerfile's HEALTHCHECK polls GET /api/status, and the
# server serves that route. The gap was not a gap, and a document that says
# there is no way to monitor liveness sends a reader looking for one.
#
# The tree is the Dockerfile, because the health check is what the image
# declares, and the document has to state the same endpoint.
#
# The document's health claim is read from the sentences that talk about the
# health check and not from the whole document: a path named in an unrelated
# sentence is not the health check, and reading it as one would let a document
# pass by naming the right path in the wrong place. The sentences are cut on
# the full stop, so a sentence that wraps across two lines is still one
# sentence.
#
# The absence claim is checked separately, because a document can state the
# right endpoint and still go on saying there is no way to monitor liveness.

code_health_paths() {
  grep -A3 '^HEALTHCHECK' Dockerfile 2>/dev/null \
    | grep -oaE 'https?://[^"[:space:]]+' \
    | sed -E 's#^https?://[^/]+##' \
    | LC_ALL=C sort -u || true
}

doc_health_paths() {
  tr '\n' ' ' < "$DEPLOY_MD" | tr -s ' ' \
    | sed -E 's/\. /.\n/g' \
    | grep -i 'health' \
    | grep -oaE '/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*' \
    | sed -E 's/\.+$//' \
    | LC_ALL=C sort -u || true
}

# The endpoint the image health-checks has to be one the document states.
check_health_paths() {
  local label="$1" code="$2" doc="$3" missing
  not_in "$code" "$doc"; missing=$NOT_IN
  if [ -z "$missing" ]; then
    count_lines "$code"
    ok "$label" "$COUNT_LINES"
    return
  fi
  join_lines "$doc"; local doc_text="$JOIN_LINES"
  fail "$(printf '%-22s the image health-checks [%s], the document states [%s]' \
    "$label" "$missing" "$doc_text")"
}

CODE_HEALTH_PATHS=$(code_health_paths)
DOC_HEALTH_PATHS=$(doc_health_paths)

if [ -z "$CODE_HEALTH_PATHS" ]; then
  fail "$(printf '%-22s the image declares no health check to compare the document with' \
    'Health check')"
else
  check_health_paths "Health check" "$CODE_HEALTH_PATHS" "$DOC_HEALTH_PATHS"
fi

# The gaps table must not keep a row that denies a health check. The row is
# found by its own shape -- a table row whose first cell denies something and
# names the health check -- so a sentence about the health check elsewhere in
# the document is not read as one.
doc_health_gaps() {
  grep -icE '^\|[^|]*\bno\b[^|]*health' "$DEPLOY_MD" || true
}

DOC_HEALTH_GAPS=$(doc_health_gaps)

if [ "$DOC_HEALTH_GAPS" = "0" ]; then
  ok "Health check gap" "$DOC_HEALTH_GAPS"
else
  fail "$(printf '%-22s the document lists %s gap row(s) that deny a health check' \
    'Health check gap' "$DOC_HEALTH_GAPS")"
fi

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

# --- the packages the project has ---------------------------------------------
#
# The dependency documents say how many packages the project is made of, and
# the list they wrote down is the one the project started with: the agent's
# server (cmd/mcp) was added after they were written, and the documents still
# say the project has five packages. A reader planning a change would not
# know the package exists.
#
# The tree is the manifests. Every moon.pkg is a package, the module's own
# one included -- the documents count it, so the tree is counted the same way.
#
# The COUNT and the LIST are checked, and they are checked in each document
# separately. The count is what a reader takes away; the list is what a reader
# reads to find a package. A document can state the right count and the wrong
# list, and the other way round, so neither check can stand in for the other.

tree_project_packages() {
  {
    find . -maxdepth 1 -name moon.pkg -type f -print
    find backend frontend cmd -name moon.pkg -type f -print 2>/dev/null
  } | sed -E 's|^\./||; s|/moon\.pkg$||; s|^moon\.pkg$|root|' \
    | LC_ALL=C sort -u
}

# The list the evidence document states: the names after "project packages: ".
doc_project_packages() {
  grep -oE 'project packages: [^|]+' "$EVIDENCE" \
    | sed -E 's/^project packages: //' \
    | tr ',' '\n' | sed -E 's/[[:space:]]+//g' | grep -v '^$' \
    | LC_ALL=C sort -u
}

# The packages the dependency table names: the first cell of every row of the
# internal dependencies table.
doc_dependency_packages() {
  awk '
    /^\|[[:space:]]*Package[[:space:]]*\|/ { inside = 1; next }
    inside && /^\|/ {
      cell = $0
      sub(/^\|[[:space:]]*/, "", cell)
      sub(/[[:space:]]*\|.*$/, "", cell)
      gsub(/`/, "", cell)
      sub(/\/$/, "", cell)
      sub(/^root moon\.pkg$/, "root", cell)
      print cell
    }
    inside && !/^\|/ { exit }
  ' "$DEPS_MD" | grep -E '^[a-z]+(/[a-z]+)?$' | LC_ALL=C sort -u
}

TREE_PROJECT_PACKAGES=$(tree_project_packages)
count_lines "$TREE_PROJECT_PACKAGES"
TREE_PROJECT_PACKAGE_COUNT=$COUNT_LINES

check_word_count "dependency package count" "packages" \
  "$TREE_PROJECT_PACKAGE_COUNT" "$DEPS_MD"
check_word_count "project package count" "project packages" \
  "$TREE_PROJECT_PACKAGE_COUNT" "$EVIDENCE"

check_sets "dependency package list" "$TREE_PROJECT_PACKAGES" \
  "$(doc_dependency_packages)"
check_sets "project package list" "$TREE_PROJECT_PACKAGES" \
  "$(doc_project_packages)"

# --- the edges inside the project ----------------------------------------------
#
# The dependency document says which package depends on which, and it says it
# in three places: the diagram, the internal dependencies table, and the
# coupling assessment. The tree says it too, in the manifests: a package that
# imports another one of the project's packages depends on it.
#
# The edges rotted the same way the package list did -- the agent's server was
# added and the document did not say so -- and a reader planning a change
# would not know that the agent's server reads the pages and the database.
#
# The tree's edge is a pair of package names, and each of the three places is
# read into that shape, because the three do not spell it the same way.
#
# Every place is read. A document that says the right thing in the table and
# the wrong thing in the diagram has a wrong diagram.

tree_internal_edges() {
  local pkg dep
  for pkg in $(find backend frontend cmd -name moon.pkg -type f 2>/dev/null \
    | sed -E 's|/moon\.pkg$||'); do
    for dep in $(grep -oE '"riantr/MAKED/[a-z]+(/[a-z]+)?"' "$pkg/moon.pkg" 2>/dev/null \
      | sed -E 's|"riantr/MAKED/||; s|"||'); do
      printf '%s %s\n' "$pkg" "$dep"
    done
  done | LC_ALL=C sort -u
}

# The edges the internal dependencies table states: the package in the first
# cell and the package it depends on in the second.
doc_table_edges() {
  awk '
    /^\|[[:space:]]*Package[[:space:]]*\|/ { inside = 1; next }
    inside && /^\|/ {
      first = $0
      sub(/^\|[[:space:]]*/, "", first)
      sub(/[[:space:]]*\|.*$/, "", first)
      gsub(/`/, "", first)
      sub(/\/$/, "", first)
      sub(/^root moon\.pkg$/, "root", first)
      rest = $0
      sub(/^\|[^|]*\|/, "", rest)
      second = rest
      sub(/^[[:space:]]*/, "", second)
      sub(/[[:space:]]*\|.*$/, "", second)
      gsub(/`/, "", second)
      if (first ~ /^[a-z]+(\/[a-z]+)?$/ && second ~ /^[a-z]+(\/[a-z]+)?$/) {
        print first " " second
      }
    }
    inside && !/^\|/ { exit }
  ' "$DEPS_MD" | LC_ALL=C sort -u
}

# The edges the diagram states: a line inside a fenced block that starts with
# a package name and names the package it depends on after the arrow. The
# fence is what keeps the prose out: a sentence that starts with a word and
# carries two more words looks exactly like an edge to a pattern.
doc_diagram_edges() {
  awk '
    /^```$/ { inside = !inside; next }
    inside { print }
  ' "$DEPS_MD" | grep -oE '^[a-z]+(/[a-z]+)? +[^ ]+ +[a-z]+(/[a-z]+)?' \
    | sed -E 's/ +[^ ]+ +/ /' | LC_ALL=C sort -u
}

TREE_INTERNAL_EDGES=$(tree_internal_edges)

check_sets "package dependencies" "$TREE_INTERNAL_EDGES" "$(doc_table_edges)"
check_sets "dependency diagram" "$TREE_INTERNAL_EDGES" "$(doc_diagram_edges)"

# --- the logo's tests ----------------------------------------------------------
#
# The blast radius of the mark says how many tests pin it. It said six, and
# there are four: the test blocks that name node_xy, node_percent or nodes.
# A count that is wrong here is a count that sends a reader looking for six
# tests and finding four.
#
# The tests are counted as BLOCKS, not as assertions and not as lines: a block
# starts at a test declaration and ends at the brace that closes it. The
# file's own header names the same three functions, so a reader that counted
# by name alone would count the comment as well.

CODE_LOGO_TESTS=0
code_logo_tests() {
  local file="frontend/frontend_test.mbt"
  local line body="" inside=0 count=0
  while IFS= read -r line; do
    if [ "$inside" -eq 0 ]; then
      case "$line" in
        'test "'*) inside=1; body="$line" ;;
      esac
      continue
    fi
    body="$body
$line"
    if [ "$line" = "}" ]; then
      case "$body" in
        *node_xy*|*node_percent*|*nodes\(\)*) count=$((count + 1)) ;;
      esac
      inside=0
      body=""
    fi
  done < "$file"
  CODE_LOGO_TESTS="$count"
}

code_logo_tests
check_claim_number "logo tests" 'node_xy, node_percent, nodes tests \(([0-9]+) tests\)' \
  "$CODE_LOGO_TESTS" "$DEPS_MD"

# --- the ring's geometry --------------------------------------------------------
#
# The evidence document states the ring's geometry in one cell: how many nodes
# the ring has, how far the ring reaches, and how big the square the mark is
# drawn in. All three are the tree's -- the logo file holds them as
# constants, and the test file pins them as literals -- and a reader who took
# the numbers and drew the mark would draw a different one.
#
# The viewBox is written the way a viewBox is written, "200x200", so the
# tree's single VIEW constant is what both halves of that have to be.

# The nodes the mark draws: the tuples in nodes().
code_logo_nodes() {
  grep -cE '^[[:space:]]*\("[A-Z]", "#[0-9a-fA-F]+"' frontend/logo.mbt || true
}

# The value of a constant in the logo file.
code_logo_const() {
  local name="$1"
  grep -oE "const $name : Int32 = [0-9]+" frontend/logo.mbt | head -1 \
    | grep -oE '[0-9]+$' || true
}

CODE_LOGO_NODES=$(code_logo_nodes)
CODE_LOGO_RADIUS=$(code_logo_const RING_R)
CODE_LOGO_VIEW=$(code_logo_const VIEW)

check_claim_number "logo nodes" '([0-9]+) nodes clockwise from top' \
  "$CODE_LOGO_NODES" "$EVIDENCE"
check_claim_number "ring radius" 'radius ([0-9]+), viewBox' \
  "$CODE_LOGO_RADIUS" "$EVIDENCE"
check_claim_number "logo viewBox" 'viewBox ([0-9]+x[0-9]+)' \
  "${CODE_LOGO_VIEW}x${CODE_LOGO_VIEW}" "$EVIDENCE"

# --- the keys the page carries ------------------------------------------------
#
# The change impact table says which key the backend writes and which key the
# frontend reads, one row per key, and those two columns are the contract
# between the two halves of the project: a key the backend stopped writing is
# a field the frontend silently reads as its fallback, and a key the frontend
# stopped reading is a field nobody sees.
#
# The tree is the contract. The backend's keys are the ones Page::to_json
# writes, and the frontend's keys are the ones page_from_json reads. The
# document has to state the same two sets, because the table is where a
# reader looks to see what a change to the page shape will move.
#
# The two columns are read separately, because they are two claims: the
# backend's keys and the frontend's keys are the same set today, and a
# document that says so in one column and not in the other is wrong in one of
# them.

code_page_json_keys() {
  awk '
    /pub fn Page::to_json/ { inside = 1 }
    inside && /^  \}/ { exit }
    inside { print }
  ' backend/pages.mbt | grep -oE '"[a-z_]+":' | tr -d '":' | LC_ALL=C sort -u
}

code_page_decoder_keys() {
  awk '
    /fn page_from_json/ { inside = 1 }
    inside && /^  \}/ { exit }
    inside { print }
  ' frontend/page.mbt | grep -oE 'get_(string|bool|int)\(json, "[a-z_]+"' \
    | grep -oE '"[a-z_]+"' | tr -d '"' | LC_ALL=C sort -u
}

# The keys the change impact table says the backend writes: the second cell
# of every row of that table.
doc_page_json_keys() {
  awk -F'|' '
    /^\|[[:space:]]*Backend function[[:space:]]*\|/ { inside = 1; next }
    inside && /^\|/ {
      cell = $3
      gsub(/[[:space:]"`]/, "", cell)
      if (cell ~ /^[a-z_]+$/) print cell
    }
    inside && !/^\|/ { exit }
  ' "$DEPS" | LC_ALL=C sort -u
}

# The keys the same table says the frontend reads: the quoted key inside the
# consumer in the third cell.
doc_page_decoder_keys() {
  awk -F'|' '
    /^\|[[:space:]]*Backend function[[:space:]]*\|/ { inside = 1; next }
    inside && /^\|/ {
      cell = $4
      if (match(cell, /"[a-z_]+"/)) print substr(cell, RSTART + 1, RLENGTH - 2)
    }
    inside && !/^\|/ { exit }
  ' "$DEPS" | LC_ALL=C sort -u
}

check_sets "page json keys" "$(code_page_json_keys)" "$(doc_page_json_keys)"
check_sets "page decoder keys" "$(code_page_decoder_keys)" "$(doc_page_decoder_keys)"

# --- the order the chain runs in ----------------------------------------------
#
# A request to the server meets three things before it reaches a handler: the
# static file middleware, the SPA fallback middleware and the route module.
# The order they meet is not the order they are written in. moonback appends
# every middleware to one list, chains that list in declaration order with the
# first registered outermost, and hands the router to the chain as the
# handler -- so the chain runs
#
#   static_files -> spa_fallback -> routes
#
# while the code registers them the other way round: the routes first, then
# the two middlewares. The documents had the registration order and called it
# the runtime order, which sent a reader looking for the router before the
# static files -- the opposite of what happens.
#
# The rule was read from moonback 0.8.9: module.mbt appends each middleware to
# the app's list, middleware.mbt chains that list in declaration order and
# compose() puts the current middleware in front, and app.mbt gives the chain
# the router as the handler. The pin is watched, so a different moonback
# cannot change the answer without the rule being read again.

CHAIN_RULE_MOONBACK="0.8.9"
CHAIN_ORDER=""
CHAIN_MOONBACK_PIN=""
CHAIN_FLOWS="architecture/flows.md"

# The parts of the chain, in the order the tree runs them.
#
# The registrations are read in the order the file writes them. A middleware
# registered with add_middleware is one of the chain, in the order it was
# registered; the module registered with use_ is the route module, and the
# router is the last thing a request meets. The word used for each is the
# tree's: the function it was built from, when the file builds it from one.
code_chain_order() {
  local file="cmd/server/main.mbt"
  local kind name func middlewares="" route=""
  while read -r kind name; do
    [ -n "$name" ] || continue
    func=$(grep -oE "let $name = @[A-Za-z_.]+\.[a-z_]+\(" "$file" | head -1 \
      | sed -E 's/^.*\.([a-z_]+)\($/\1/')
    [ -n "$func" ] || func="$name"
    if [ "$kind" = "use_" ]; then
      route="$func"
    else
      middlewares="$middlewares $func"
    fi
  done < <(grep -oE 'ctx\.(use_|add_middleware)\([a-z_]+\)' "$file" \
    | sed -E 's/ctx\.(use_|add_middleware)\(([a-z_]+)\)/\1 \2/')
  CHAIN_ORDER="$(printf '%s' "$middlewares $route" | sed -e 's/^ *//' -e 's/ *$//')"
}

# The version of moonback the project pins.
code_moonback_pin() {
  local line
  CHAIN_MOONBACK_PIN=""
  while IFS= read -r line; do
    case "$line" in
      *'"moonbitlang/moonback@'*)
        CHAIN_MOONBACK_PIN="${line#*@}"
        CHAIN_MOONBACK_PIN="${CHAIN_MOONBACK_PIN%%\"*}"
        return
        ;;
    esac
  done < moon.mod
}

# The parts a text names, in the order the text names them.
#
# Each part is placed where the text first says it, and the parts are then
# read in that order. A text that names them in the wrong order comes out in
# the wrong order, and a text that says one part twice keeps it where it
# first said it.
DOC_CHAIN_ORDER=""
doc_chain_order() {
  local text="$1" name prefix
  DOC_CHAIN_ORDER=""
  {
    for name in $CHAIN_ORDER; do
      case "$text" in
        *"$name"*)
          prefix="${text%%"$name"*}"
          printf '%010d %s\n' "${#prefix}" "$name"
          ;;
      esac
    done
  } | sort -n | cut -d' ' -f2- | tr '\n' ' ' | sed -e 's/ *$//'
}

# The chain the flow document traces: the numbered list under the line that
# says the chain runs outermost first.
#
# The list is the run of items numbered 1, 2, 3 in a row. The next list in the
# document starts at 1 again, so the run ends where the numbering stops
# counting up -- which is how the reader knows it has read one list and not
# two.
DOC_FLOW_CHAIN=""
doc_flow_chain() {
  local line inside=0 want=1 num
  DOC_FLOW_CHAIN=""
  while IFS= read -r line; do
    if [ "$inside" -eq 0 ]; then
      case "$line" in
        *"moonback middleware chain (outermost first)"*) inside=1 ;;
      esac
      continue
    fi
    if [[ "$line" =~ ^[[:space:]]+([0-9]+)\. ]]; then
      num="${BASH_REMATCH[1]}"
      if [ "$num" -ne "$want" ]; then break; fi
      want=$((want + 1))
      DOC_FLOW_CHAIN="$DOC_FLOW_CHAIN$line
"
      continue
    fi
    # a line under the item above, or the answer going back to the browser
    case "$line" in
      [[:space:]]*) continue ;;
      *) break ;;
    esac
  done < "$CHAIN_FLOWS"
}

# Every place that states the order must state the tree's order.
#
# A table cell that names every part of the chain states the order they run
# in, so it has to state the tree's. The flow document says it in a list
# rather than a table, so that list is read as well.
check_chain_order() {
  local label="middleware order"
  local bad=0
  local doc line cell name all order
  for doc in "$EVIDENCE" "architecture/flows.evidence.md" "$DEPLOY"; do
    while IFS= read -r line; do
      case "$line" in "|"*) ;; *) continue ;; esac
      cell="${line#|}"
      cell="${cell%%|*}"
      all=1
      for name in $CHAIN_ORDER; do
        case "$cell" in *"$name"*) ;; *) all=0 ;; esac
      done
      [ "$all" -eq 1 ] || continue
      order="$(doc_chain_order "$cell")"
      if [ "$order" != "$CHAIN_ORDER" ]; then
        fail "$(printf '%-22s %s states [%s], the tree runs [%s]' \
          "$label" "$(basename "$doc")" "$order" "$CHAIN_ORDER")"
        bad=1
      fi
    done < "$doc"
  done
  doc_flow_chain
  order="$(doc_chain_order "$DOC_FLOW_CHAIN")"
  if [ "$order" != "$CHAIN_ORDER" ]; then
    fail "$(printf '%-22s %s states [%s], the tree runs [%s]' \
      "$label" "$(basename "$CHAIN_FLOWS")" "$order" "$CHAIN_ORDER")"
    bad=1
  fi
  if [ "$bad" -eq 0 ]; then
    ok "$label" "$CHAIN_ORDER"
  fi
}

code_chain_order
code_moonback_pin

if [ "$CHAIN_MOONBACK_PIN" = "$CHAIN_RULE_MOONBACK" ]; then
  ok "chain rule" "moonback $CHAIN_MOONBACK_PIN"
else
  fail "$(printf '%-22s the chain rule was read from moonback %s and moon.mod now pins %s -- read the rule again' \
    "chain rule" "$CHAIN_RULE_MOONBACK" "$CHAIN_MOONBACK_PIN")"
fi

check_chain_order

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
  "$ROUTES" "$FLOWS_MD"
check_claim_number "flow seed pages" 'seed_pages\(\)[^0-9]+([0-9]+) pages via UPSERT' \
  "$(count_seed_pages_only)" "$FLOWS_MD"
check_claim_number "flow page bodies" '\(([0-9]+) pages, hardcoded HTML bodies\)' \
  "$(count_seed_pages_only)" "$FLOWS_MD"
check_claim_number "flow page columns" 'bind\(([0-9]+) params\)' \
  "$(count_page_columns)" "$FLOWS_MD"

# --- architecture/flows.md: the statements the flow prepares --------------------
#
# The flow document shows the reader the statements the server runs: which SQL
# it prepares, and which parameters it binds to it. The number of those
# parameters is checked above -- "bind(12 params)" is the count of the
# columns. The index each parameter is bound at, and the SQL itself, were
# not: a flow that prepared a statement the tree never prepares, or that
# bound the third parameter of a statement that has one parameter, sent the
# reader to code that is not there.
#
# The tree is the backend's own functions. Each one that prepares a statement
# has a body, and the body holds the SQL it prepares and the indices it
# binds. The document names a statement by the pieces of its SQL -- it writes
# "SELECT ... WHERE slug = ?" -- and the tree's function that holds every one
# of those pieces is the statement the document means.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

FLOW_SQL_BAD=0
FLOW_SQL_CHECKED=0

# The functions of the tree that prepare a statement: the name, the
# parameters they bind and the body they hold.
#
# A function is the line that declares it and the lines up to the next
# declaration. The body is those lines joined with spaces, so that a piece of
# SQL can be looked for in it. The test files are not the code the server
# runs, so they are not read.
code_statement_functions() {
  awk '
    /^[[:space:]]*(pub[[:space:]]*(\([A-Za-z_][A-Za-z0-9_]*\)[[:space:]]*)?)?(async[[:space:]]+)?fn[[:space:]]/ {
      if (name != "" && body ~ /prepare\(/) printf "%s\037%s\037%s\n", name, indices, body
      name = ""
      indices = ""
      body = ""
      if (match($0, /fn[[:space:]]/)) {
        name = substr($0, RSTART + RLENGTH)
        sub(/[^A-Za-z0-9_:].*$/, "", name)
      }
      next
    }
    {
      body = body " " $0
      rest = $0
      while (match(rest, /bind\(index=[0-9]+/)) {
        indices = indices " " substr(rest, RSTART + 11, RLENGTH - 11)
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
    END {
      if (name != "" && body ~ /prepare\(/) printf "%s\037%s\037%s\n", name, indices, body
    }
  ' backend/*.mbt cmd/*/*.mbt
}

FLOW_STATEMENT_FUNCTIONS="$(code_statement_functions)"

# The pieces of the SQL a claim states: the document writes "SELECT ... WHERE
# slug = ?", and the pieces between the ellipses are the ones the tree has to
# hold. A piece is kept whole: it is a piece of SQL, not a word.
flow_sql_fragments() {
  local sql="$1" rest="$1" piece
  FLOW_SQL_FRAGMENTS=()
  while [ -n "$rest" ]; do
    piece="${rest%%...*}"
    if [ "$piece" = "$rest" ]; then
      rest=""
    else
      rest="${rest#*...}"
    fi
    # the spaces around the piece are not part of it
    piece="${piece#"${piece%%[![:space:]]*}"}"
    piece="${piece%"${piece##*[![:space:]]}"}"
    [ -n "$piece" ] || continue
    FLOW_SQL_FRAGMENTS+=("$piece")
  done
}

# The statements the flow document states, checked against the tree.
check_flow_sql() {
  local line n=0 stmt='' stmt_indices='' sql fragment name indices body
  local found
  while IFS= read -r line; do
    n=$((n + 1))
    if [[ "$line" =~ prepare[[:space:]]+(SELECT|INSERT|UPDATE|DELETE|PRAGMA|CREATE|WITH)[[:space:]] ]]; then
      sql="${line#*prepare }"
      flow_sql_fragments "$sql"
      stmt=''
      stmt_indices=''
      found=''
      while IFS=$'\037' read -r name indices body; do
        [ -n "$name" ] || continue
        found=1
        for fragment in "${FLOW_SQL_FRAGMENTS[@]}"; do
          if [[ "$body" != *"$fragment"* ]]; then
            found=''
            break
          fi
        done
        [ -n "$found" ] || continue
        stmt="$name"
        stmt_indices="$indices"
        break
      done <<< "$FLOW_STATEMENT_FUNCTIONS"
      FLOW_SQL_CHECKED=$((FLOW_SQL_CHECKED + 1))
      if [ -z "$stmt" ]; then
        fail "$(printf '%-22s %s line %s prepares SQL the tree does not have: %s' \
          'flow sql' "$FLOWS_MD" "$n" "$sql")"
        FLOW_SQL_BAD=1
      fi
      continue
    fi
    if [[ "$line" =~ bind\(([0-9]+),[[:space:]]*\"([^\"]*)\"\) ]]; then
      local index="${BASH_REMATCH[1]}" value="${BASH_REMATCH[2]}"
      FLOW_SQL_CHECKED=$((FLOW_SQL_CHECKED + 1))
      if [ -z "$stmt" ]; then
        fail "$(printf '%-22s %s line %s binds a parameter of a statement it does not prepare' \
          'flow sql' "$FLOWS_MD" "$n")"
        FLOW_SQL_BAD=1
        continue
      fi
      if [[ " $stmt_indices " != *" $index "* ]]; then
        fail "$(printf '%-22s %s line %s binds parameter %s, and the tree binds %s' \
          'flow sql' "$FLOWS_MD" "$n" "$index" "${stmt_indices# }")"
        FLOW_SQL_BAD=1
      fi
      if ! grep -qF "\"$value\"" backend/*.mbt cmd/*/*.mbt 2>/dev/null; then
        fail "$(printf '%-22s %s line %s binds a value the tree does not have: %s' \
          'flow sql' "$FLOWS_MD" "$n" "$value")"
        FLOW_SQL_BAD=1
      fi
    fi
  done < "$FLOWS_MD"
}

check_flow_sql

if [ "$FLOW_SQL_BAD" -eq 0 ]; then
  ok "flow sql" "$FLOW_SQL_CHECKED claims"
fi

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

# --- the keys the bootstrap carries -------------------------------------------
#
# The server writes four keys into the body of GET /api/bootstrap, and the
# flow document shows that body to the reader. It showed three of them and
# called the last one "session", which is not a key at all, and left out
# entry_domains -- so a reader planning a change to the payload was planning
# it against a shape the server never sends.
#
# The place is found by its own shape: a line that shows a JSON object
# literal -- a brace, a quoted name with a colon, a closing brace -- and that
# names more than one of the tree's keys. The client asking for a page names
# one key and is not the payload; the list of SQLite columns names two and
# shows no literal.

TREE_BOOTSTRAP_KEYS=""

# The keys the server writes into the bootstrap body.
code_bootstrap_keys() {
  awk '
    /app\.get\("\/api\/bootstrap"/ { inroute = 1 }
    inroute && /let body : Json = \{/ { inside = 1 }
    inside && /^[[:space:]]*\}$/ { exit }
    inside { print }
  ' backend/api.mbt | grep -oE '"[a-z_]+":' | tr -d '":' | LC_ALL=C sort -u \
    | tr '\n' ' ' | sed -e 's/^ *//' -e 's/ *$//'
}

# The keys a place states: the quoted names that carry a colon, which is the
# shape a JSON object literal has.
DOC_BOOTSTRAP_KEYS=""
doc_bootstrap_keys() {
  local text="$1"
  DOC_BOOTSTRAP_KEYS=$(printf '%s' "$text" | grep -oE '"[a-z_]+":' \
    | tr -d '":' | LC_ALL=C sort -u | tr '\n' ' ' | sed -e 's/^ *//' -e 's/ *$//')
}

# Every place that states the payload must state the tree's keys, and a
# document that stops stating the payload altogether is a document that has
# lost the claim.
check_bootstrap_keys() {
  local label="bootstrap keys"
  local bad=0
  local doc line count name names missing extra found
  for doc in "$FLOWS_MD" "architecture/flows.evidence.md"; do
    found=0
    while IFS= read -r line; do
      # the shape: a JSON object literal
      [[ "$line" =~ \{.*\"[a-z_]+\":.*\} ]] || continue
      # and more than one of the tree's keys
      count=0
      for name in $TREE_BOOTSTRAP_KEYS; do
        case "$line" in *"$name"*) count=$((count + 1)) ;; esac
      done
      [ "$count" -ge 2 ] || continue
      found=1
      doc_bootstrap_keys "$line"
      names="$DOC_BOOTSTRAP_KEYS"
      missing=""
      extra=""
      for name in $TREE_BOOTSTRAP_KEYS; do
        case " $names " in *" $name "*) ;; *) missing="$missing $name" ;; esac
      done
      for name in $names; do
        case " $TREE_BOOTSTRAP_KEYS " in *" $name "*) ;; *) extra="$extra $name" ;; esac
      done
      if [ -n "$missing" ] || [ -n "$extra" ]; then
        fail "$(printf '%-22s %s states [%s], the tree writes [%s]' \
          "$label" "$(basename "$doc")" "$names" "$TREE_BOOTSTRAP_KEYS")"
        bad=1
      fi
    done < "$doc"
    if [ "$found" -eq 0 ]; then
      fail "$(printf '%-22s %s does not state the bootstrap payload' \
        "$label" "$(basename "$doc")")"
      bad=1
    fi
  done
  if [ "$bad" -eq 0 ]; then
    ok "$label" "$TREE_BOOTSTRAP_KEYS"
  fi
}

TREE_BOOTSTRAP_KEYS="$(code_bootstrap_keys)"
check_bootstrap_keys

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

# The graphs that describe the present. A graph that says it describes the
# past is history, and history keeps the numbers it had: the past is
# allowed to be the past.
current_graphs() {
  local file
  for file in $(printf '%s\n' architecture/*.dot | LC_ALL=C sort); do
    [ -e "$file" ] || continue
    if ! grep -qF 'This document describes the past.' "$file"; then
      printf '%s\n' "$file"
    fi
  done
}

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
  for file in $(current_graphs); do
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

check_graph_routes "$(graph_route_claims)" "$ROUTES"

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

# The import blocks of the manifests, without their comments. They are read
# ONCE and kept, because a fork is a tenth of a second on this machine and
# there are six files in here.
MANIFEST_BLOCKS=$(
  for file in moon.mod backend/moon.pkg frontend/moon.pkg \
              cmd/server/moon.pkg cmd/web/moon.pkg cmd/mcp/moon.pkg; do
    awk '
      /^import \{/ { inside = 1; next }
      inside && /^\}/ { inside = 0; next }
      inside { print }
    ' "$file"
  done
)

# The external imports the tree declares. The core packages and the
# project's own packages are left out: they are not dependencies on anything
# outside the tree.
tree_imports() {
  printf '%s\n' "$MANIFEST_BLOCKS" \
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
  printf '%s\n' "$MANIFEST_BLOCKS" \
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

# The tree's families are read once and kept: three checks ask for them,
# and a fork is a tenth of a second on this machine.
API_FAMILIES=$(tree_api_families)

check_sets "contract endpoints" "$API_FAMILIES" \
  "$(graph_api_families "$DEPENDENCIES_DOT")"
check_sets "topology endpoints" "$API_FAMILIES" \
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

# --- architecture/flows.dot: the flow graph traces what the server does ------
#
# The flow graph traces five paths through the server, and it counts as it
# goes: eight pages are seeded, and it names the routes it walks. Those are
# the tree's numbers, and the flow document beside it already says them --
# but the graph is a document too, and it was not being checked.
#
# The count checks skip the graphs that say they describe the past: history
# is allowed to be history, and only the present has to be right.

FLOWS_DOT="architecture/flows.dot"

# The page counts a graph states.
graph_page_claims() {
  grep -oE '[0-9]+ [Pp]ages?' "$1" | grep -oE '[0-9]+' | LC_ALL=C sort -u
}

# Every page count the graph states is the tree's count.
check_graph_pages() {
  local label="$1" file="$2" expected="$3" claims number bad=""
  claims=$(graph_page_claims "$file")
  while IFS= read -r number; do
    [ -n "$number" ] || continue
    if [ "$number" != "$expected" ]; then
      bad="$bad $number"
    fi
  done <<< "$claims"
  if [ -z "$claims" ]; then
    fail "$(printf '%-22s the graph does not state the page count' "$label")"
    return
  fi
  if [ -n "$bad" ]; then
    fail "$(printf '%-22s the tree has %s, the graph says [%s]' \
      "$label" "$expected" "$(printf '%s' "$bad" | sed -e 's/^ *//')")"
    return
  fi
  ok "$label" "$expected"
}

check_graph_pages "flow graph pages" "$FLOWS_DOT" "$(count_seed_pages_only)"

# Every family the flow graph names is a family the server serves.
check_graph_families_live() {
  local label="$1" named="$2" actual="$3" line missing=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if ! printf '%s\n' "$actual" | grep -qxF "$line"; then
      missing="$missing $line"
    fi
  done <<< "$named"
  if [ -n "$missing" ]; then
    fail "$(printf '%-22s the graph names [%s], which the server does not serve' \
      "$label" "$(printf '%s' "$missing" | sed -e 's/^ *//')")"
    return
  fi
  count_lines "$named"
  ok "$label" "$COUNT_LINES"
}

check_graph_families_live "flow graph endpoints" \
  "$(graph_api_families "$FLOWS_DOT")" "$API_FAMILIES"

# The component graph says in words how many public pages there are.
check_word_count "component graph pages" "public pages" "$PAGE_COUNT" \
  "$SYSTEM_MODEL_DOT"

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
#
# All five sections are read in ONE pass: a pass is a process, and a process
# on this machine costs a tenth of a second.
MODEL_SHAPE=$(awk '
  /^[a-z_]+:/ { section = $0; sub(/:$/, "", section); next }
  section != "" && /^  - / { count[section]++ }
  END {
    print count["domains"] + 0, count["positions"] + 0, count["slots"] + 0,
          count["rules"] + 0, count["outcomes"] + 0
  }
' "$MODEL_YAML")
read -r MODEL_DOMAINS MODEL_POSITIONS MODEL_SLOTS MODEL_RULES MODEL_OUTCOMES \
  <<< "$MODEL_SHAPE"

# The number the header states next to a phrase. The header is the comment
# at the top of the file, so only the comments are read.
model_claim() {
  grep -E '^[[:space:]]*#' "$MODEL_YAML" \
    | grep -oE "[0-9]+ $1" | grep -oE '[0-9]+' | head -1 || true
}

check_model_claim() {
  local label="$1" phrase="$2" actual="$3"
  check_stated "$label" "$actual" "$(model_claim "$phrase")" "the machine file"
}

check_model_claim "model domains" "domains" "$MODEL_DOMAINS"
check_model_claim "model positions" "positions" "$MODEL_POSITIONS"
check_model_claim "model slots" "slots" "$MODEL_SLOTS"
check_model_claim "model rules" "rules" "$MODEL_RULES"
check_model_claim "model outcomes" "outcomes" "$MODEL_OUTCOMES"

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

# --- research/product-iteration.yaml: the table says which machine it fits ---
#
# The mapping table says which machine it is for. Its header names the
# machine, the slots, and the built-in model it is NOT for -- and none of
# that was checked, so a table that had drifted away from its machine still
# looked right in the header.
#
# Four claims are checked:
#
#   - the files the header points at are there
#   - the slots the table's rules drive are the machine's slots
#   - the slots the header names are the machine's slots
#   - the built-in model's slots have other names
#
# The machine is the one the table's header names, and the machine file's
# own name says how it is read: a .yaml file is YAML and everything else is
# JSON. The built-in model's slots are MAKED's own names for pyroduct's
# slots, and they are read from the one function that maps them.

RESEARCH_TABLE="research/product-iteration.yaml"

# The files the table's header points at: the machine it fits and the
# table itself. They are named the way a reader names them.
research_named_files() {
  grep -E '^[[:space:]]*#' "$RESEARCH_TABLE" \
    | grep -oE 'MAKED_(MODEL|RESEARCH)=[A-Za-z0-9_./-]+' \
    | sed -E 's/^MAKED_[A-Z_]+=//' \
    | LC_ALL=C sort -u
}

# The machine the table fits, as the header names it.
research_named_model() {
  grep -E '^[[:space:]]*#' "$RESEARCH_TABLE" \
    | grep -oE 'MAKED_MODEL=[A-Za-z0-9_./-]+' \
    | sed -E 's/^MAKED_MODEL=//' \
    | head -1
}

# The slots the header names. The header lists them on one line, so the
# list is read from that line and split on the commas.
research_header_slots() {
  grep -E '^[[:space:]]*#[[:space:]]+slots:' "$RESEARCH_TABLE" \
    | sed -E 's/^[[:space:]]*#[[:space:]]+slots:[[:space:]]*//' \
    | tr ',' '\n' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | LC_ALL=C sort -u
}

# The slots the table's rules drive. The fallback drives one too.
research_table_slots() {
  grep -E '^[[:space:]]+slot:[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*$' \
    "$RESEARCH_TABLE" \
    | sed -E 's/^[[:space:]]+slot:[[:space:]]*//; s/[[:space:]]+$//' \
    | LC_ALL=C sort -u
}

# The slots a machine file defines. The file's name says how it is read.
machine_slot_ids() {
  case "$1" in
    *.yaml|*.yml) machine_yaml_slot_ids "$1" ;;
    *) machine_json_slot_ids "$1" ;;
  esac
}

# The slots a JSON machine file defines. The block is found by its key and
# ends at the bracket that closes it, and the indentation of the closing
# bracket says which one that is: a bracket inside a string would not do.
machine_json_slot_ids() {
  [ -n "$1" ] && [ -f "$1" ] || return 0
  awk '
    !in_slots {
      if (match($0, /^[[:space:]]*"slots"[[:space:]]*:[[:space:]]*\[/)) {
        in_slots = 1
        open_indent = match($0, /[^ ]/) - 1
      }
      next
    }
    match($0, /^[[:space:]]*\],?[[:space:]]*$/) {
      close_indent = match($0, /[^ ]/) - 1
      if (close_indent <= open_indent) { in_slots = 0 }
      next
    }
    match($0, /"id"[[:space:]]*:[[:space:]]*"[^"]+"/) {
      value = substr($0, RSTART, RLENGTH)
      sub(/^"id"[[:space:]]*:[[:space:]]*"/, "", value)
      sub(/"$/, "", value)
      print value
    }
  ' "$1" | LC_ALL=C sort -u
}

# The slots a YAML machine file defines. The section runs from its key to
# the next key at the left margin.
machine_yaml_slot_ids() {
  [ -n "$1" ] && [ -f "$1" ] || return 0
  awk '
    match($0, /^slots:[[:space:]]*$/) { in_slots = 1; next }
    in_slots && match($0, /^[^[:space:]#]/) { in_slots = 0 }
    in_slots && match($0, /^[[:space:]]*-[[:space:]]+id:[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*$/) {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]+id:[[:space:]]*/, "", line)
      sub(/[[:space:]]+$/, "", line)
      print line
    }
  ' "$1" | LC_ALL=C sort -u
}

# The built-in model's slots: MAKED's own names for pyroduct's slots, and
# they are written down in the one function that maps them.
builtin_model_slots() {
  awk '
    match($0, /^pub fn slot_id_of/) { inside = 1; next }
    inside && match($0, /^}/) { inside = 0 }
    inside && match($0, /=>/) {
      line = $0
      if (match(line, /"[^"]+"/)) {
        print substr(line, RSTART + 1, RLENGTH - 2)
      }
    }
  ' backend/model.mbt | LC_ALL=C sort -u
}

# The members of one set that are also in the other. The comparison is by
# membership, so the order the two sets are written in says nothing.
IN_COMMON=""
in_common() {
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
    if [ "$found" -eq 1 ]; then
      if [ -z "$out" ]; then out="$line"; else out="$out $line"; fi
    fi
  done <<< "$source"
  IN_COMMON="$out"
}

# The files the header points at have to be there. A pointer to nothing
# sends the reader to nothing.
check_research_files() {
  local named="$1" file missing=""
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    if [ ! -f "$file" ]; then
      missing="$missing $file"
    fi
  done <<< "$named"
  if [ -n "$missing" ]; then
    fail "$(printf '%-22s the table names [%s], which are not there' \
      'research files' "$(printf '%s' "$missing" | sed -e 's/^ *//')")"
    return
  fi
  count_lines "$named"
  ok "research files" "$COUNT_LINES"
}

RESEARCH_FILES=$(research_named_files)
RESEARCH_MODEL=$(research_named_model)
RESEARCH_HEADER_SLOTS=$(research_header_slots)
RESEARCH_TABLE_SLOTS=$(research_table_slots)
RESEARCH_MACHINE_SLOTS=$(machine_slot_ids "$RESEARCH_MODEL")
BUILTIN_MODEL_SLOTS=$(builtin_model_slots)

check_research_files "$RESEARCH_FILES"

# The slots the table drives are the machine's slots. The tree says the
# machine's slots; the table says the slots it drives.
check_sets "research slots" "$RESEARCH_MACHINE_SLOTS" "$RESEARCH_TABLE_SLOTS"

# The slots the header names are the machine's slots too. The header is
# prose, and prose rots.
check_sets "research header slots" "$RESEARCH_MACHINE_SLOTS" "$RESEARCH_HEADER_SLOTS"

# The table must not fit the built-in model either: the header says the
# built-in model's slots have other names, and this is where that is
# checked. A name the two models share is a name the header is wrong about.
in_common "$RESEARCH_TABLE_SLOTS" "$BUILTIN_MODEL_SLOTS"
if [ -z "$IN_COMMON" ]; then
  count_lines "$BUILTIN_MODEL_SLOTS"
  ok "research builtin slots" "$COUNT_LINES"
else
  fail "$(printf '%-22s the table and the built-in model share [%s]' \
    'research builtin slots' "$(printf '%s' "$IN_COMMON" | sed -e 's/^ *//')")"
fi

# --- the log ------------------------------------------------------------------
#
# The request log is the one line the logging middleware writes after the
# handler returns. The tree writes it with eprintln, and eprintln writes to
# stderr; println writes to stdout. A document that says the log goes to
# stdout sends the reader to a stream the server never writes to.
#
# Four facts come out of the tree:
#
#   LOG_STREAM      the stream the request log goes to
#   LOG_PRINT_LINE  the line the request log is written on
#   LOG_ADD_LINE    the line the app adds the middleware on
#   LOG_DEF_LINE    the line the middleware is defined on
#
# The documents are checked against all four. The stream is checked in every
# claim that names one. The line is checked in every row that cites the file
# the log is written in.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

# A line the tree does not have is 0, in this twin and in the PowerShell one.
# Both twins print the same lines, so both print the same 0.
LOG_STREAM=""
LOG_PRINT_LINE=0
LOG_ADD_LINE=0
LOG_DEF_LINE=0

code_log_lines() {
  local file="backend/maked_app.mbt"
  local n=0 line
  while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in
      *'add_middleware(logging_middleware())'*)
        [ "$LOG_ADD_LINE" -ne 0 ] || LOG_ADD_LINE="$n"
        ;;
    esac
    case "$line" in
      *'fn logging_middleware()'*)
        [ "$LOG_DEF_LINE" -ne 0 ] || LOG_DEF_LINE="$n"
        ;;
    esac
    case "$line" in
      *'req.verb()'*)
        case "$line" in
          *eprintln\(*)
            [ "$LOG_PRINT_LINE" -ne 0 ] || { LOG_PRINT_LINE="$n"; LOG_STREAM="stderr"; }
            ;;
          *println\(*)
            [ "$LOG_PRINT_LINE" -ne 0 ] || { LOG_PRINT_LINE="$n"; LOG_STREAM="stdout"; }
            ;;
        esac
        ;;
    esac
  done < "$file"
}

# The design documents: every markdown file and every graph.
ARCH_DOCS=()
while IFS= read -r f; do
  ARCH_DOCS+=("$f")
done < <(printf '%s\n' architecture/*.md architecture/*.dot | LC_ALL=C sort)

# The stream a claim names, if it names one.
#
# The tree's words for the log are the call that writes it (eprintln, or
# println) and the streams those calls write to (stderr, or stdout). A claim
# that names one of them names the stream the log goes to. eprintln writes to
# stderr, so it is taken out before the streams are read.
#
# A claim that names BOTH streams is a claim that tells them apart, and it is
# left alone: a sentence about the start-up banner on stdout and the request
# log on stderr is two true things.
#
# DOC_STREAM holds the answer: stdout, stderr, or nothing.
DOC_STREAM=""
doc_claim_stream() {
  local claim="$1" rest out=0 err=0
  DOC_STREAM=""
  case "$claim" in
    *stdout*|*stderr*|*println*) ;;
    *) return ;;
  esac
  rest="${claim//eprintln/}"
  case "$rest" in *stdout*) out=1 ;; esac
  case "$rest" in *println*) out=1 ;; esac
  case "$claim" in *stderr*) err=1 ;; esac
  case "$claim" in *eprintln*) err=1 ;; esac
  if [ "$out" -eq 1 ] && [ "$err" -eq 0 ]; then
    DOC_STREAM="stdout"
  elif [ "$err" -eq 1 ] && [ "$out" -eq 0 ]; then
    DOC_STREAM="stderr"
  fi
}

# The numbers a row cites, and whether one of them is the line asked for.
#
# A citation is a line, a range of lines, or a few of both: "65", "11-29",
# "16, 61". A row that cites the file the log is written in has to cite the
# line the log is written on.
CITATION_COVERS=0
citation_covers() {
  local text="$1" target="$2" a b
  CITATION_COVERS=0
  while [[ "$text" =~ ([0-9]+)(-([0-9]+))? ]]; do
    a="${BASH_REMATCH[1]}"
    b="${BASH_REMATCH[3]}"
    [ -n "$b" ] || b="$a"
    if [ "$a" -le "$target" ] && [ "$target" -le "$b" ]; then
      CITATION_COVERS=1
      return
    fi
    text="${text#*"${BASH_REMATCH[0]}"}"
  done
}

LOG_BAD_STREAM=0
LOG_BAD_SITE=0

# One claim, checked against the tree.
log_claim_check() {
  local doc="$1" line="$2" claim="$3" cited
  # the stream the claim names
  doc_claim_stream "$claim"
  if [ -n "$DOC_STREAM" ] && [ "$DOC_STREAM" != "$LOG_STREAM" ]; then
    fail "$(printf '%-22s %s line %s says the log goes to %s, the tree writes it to %s' \
      'log stream' "$doc" "$line" "$DOC_STREAM" "$LOG_STREAM")"
    LOG_BAD_STREAM=1
  fi
  # the line the claim points at: only a table row carries a citation
  case "$claim" in
    \|*) ;;
    *) return ;;
  esac
  case "$claim" in
    *'backend/maked_app.mbt:'*) ;;
    *) return ;;
  esac
  cited="${claim#*backend/maked_app.mbt:}"
  cited="${cited%%\`*}"
  cited="${cited%%|*}"
  cited="${cited// /}"
  # the claim states where the log is written
  case "${claim,,}" in
    *print*)
      citation_covers "$cited" "$LOG_PRINT_LINE"
      if [ "$CITATION_COVERS" -eq 0 ]; then
        fail "$(printf '%-22s %s line %s cites [%s], the tree writes the request log on line %s' \
          'log site' "$doc" "$line" "$cited" "$LOG_PRINT_LINE")"
        LOG_BAD_SITE=1
      fi
      ;;
  esac
  # the claim states where the middleware lives: the line the app adds it on,
  # the line it is defined on, or the line it writes the log on
  case "${claim,,}" in
    *logging_middleware*|*'logging middleware'*)
      citation_covers "$cited" "$LOG_ADD_LINE"
      if [ "$CITATION_COVERS" -eq 0 ]; then
        citation_covers "$cited" "$LOG_DEF_LINE"
      fi
      if [ "$CITATION_COVERS" -eq 0 ]; then
        citation_covers "$cited" "$LOG_PRINT_LINE"
      fi
      if [ "$CITATION_COVERS" -eq 0 ]; then
        fail "$(printf '%-22s %s line %s cites [%s], the tree has the middleware on lines %s, %s and %s' \
          'log site' "$doc" "$line" "$cited" "$LOG_ADD_LINE" "$LOG_DEF_LINE" "$LOG_PRINT_LINE")"
        LOG_BAD_SITE=1
      fi
      ;;
  esac
}

# The claims a document makes.
#
# A claim is a paragraph: the run of lines a reader reads as one sentence. A
# table row is a claim of its own, because a table says one thing per row. A
# graph says one thing per line, because a graph has no paragraphs.
#
# DOC_CLAIMS holds them, one per line, as "line<TAB>text".
DOC_CLAIMS=""
doc_claims() {
  local file="$1" line claim="" claim_line=0 n=0 dot=0
  DOC_CLAIMS=""
  case "$file" in *.dot) dot=1 ;; esac
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if [ "$dot" -eq 1 ]; then
      DOC_CLAIMS="$DOC_CLAIMS$n"$'\t'"$line"$'\n'
      continue
    fi
    case "$line" in
      \|*)
        if [ -n "$claim" ]; then
          DOC_CLAIMS="$DOC_CLAIMS$claim_line"$'\t'"$claim"$'\n'
          claim=""
        fi
        DOC_CLAIMS="$DOC_CLAIMS$n"$'\t'"$line"$'\n'
        continue
        ;;
    esac
    # a line with nothing on it ends the paragraph
    if [ -z "${line//[[:space:]]/}" ]; then
      if [ -n "$claim" ]; then
        DOC_CLAIMS="$DOC_CLAIMS$claim_line"$'\t'"$claim"$'\n'
        claim=""
      fi
      continue
    fi
    if [ -n "$claim" ]; then
      claim="$claim $line"
    else
      claim="$line"
      claim_line="$n"
    fi
  done < "$file"
  if [ -n "$claim" ]; then
    DOC_CLAIMS="$DOC_CLAIMS$claim_line"$'\t'"$claim"$'\n'
  fi
}

# Every claim the design documents make, checked against the tree.
#
# A document that describes the past is a record of the past: its claims are
# about the tree as it was, so they are not checked against the tree as it is.
check_log_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      log_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

code_log_lines

if [ -z "$LOG_STREAM" ] || [ "$LOG_PRINT_LINE" -eq 0 ]; then
  fail "$(printf '%-22s the tree does not write a request log, or it does not write it the way this gate reads it' \
    'log stream')"
  LOG_BAD_STREAM=1
  LOG_BAD_SITE=1
else
  check_log_claims
fi

if [ "$LOG_BAD_STREAM" -eq 0 ]; then
  ok "log stream" "$LOG_STREAM"
fi
if [ "$LOG_BAD_SITE" -eq 0 ]; then
  ok "log site" "maked_app.mbt:$LOG_PRINT_LINE"
fi

# --- the environment variables -------------------------------------------------
#
# The server reads four environment variables, and it reads all four in one
# file: cmd/server/main.mbt. A row that points at that file and names the
# variables is stating the set the server reads, and a partial set is a set
# that is wrong: a reader who sets MAKED_PORT and MAKED_DB because the
# document listed them is left guessing about MAKED_HOST.
#
# The names come out of the tree. An env_or call names the variable it reads
# and the line it reads it on.
#
# The shorthand MAKED_PORT/HOST/DB/DIST is expanded into the four names it
# stands for, so a row that uses it is read like any other.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

ENV_VARS=""
code_env_vars() {
  local file="cmd/server/main.mbt"
  local n=0 line rest name
  ENV_VARS=""
  while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in
      *'env_or("'*) ;;
      *) continue ;;
    esac
    rest="${line#*env_or(\"}"
    name="${rest%%\"*}"
    ENV_VARS="$ENV_VARS $name"
  done < "$file"
}

# The lines the tree mentions a variable on.
#
# A variable is mentioned where it is read, and where the server talks about
# it -- the warning it prints when the host is not the default, for one. A row
# that points at the file has to point at a line the variable is on.
ENV_VAR_MENTIONS=""
env_var_mentions() {
  local name="$1" file="cmd/server/main.mbt"
  local n=0 line
  ENV_VAR_MENTIONS=""
  while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in
      *"$name"*) ENV_VAR_MENTIONS="$ENV_VAR_MENTIONS $n" ;;
    esac
  done < "$file"
}

# The environment variables a claim names.
#
# The names are the tree's: MAKED_ and then capitals. A shorthand list --
# MAKED_PORT/HOST/DB/DIST -- is expanded into the names it stands for, one
# name at a time, because the prefix carries over.
#
# DOC_VARS holds the answer.
DOC_VARS=""
doc_claim_vars() {
  local text="$1" rest name word
  DOC_VARS=""
  while [ -n "$text" ]; do
    case "$text" in
      *MAKED_[A-Z_]*) ;;
      *) break ;;
    esac
    rest="${text#*MAKED_}"
    name="MAKED_${rest%%[!A-Z_]*}"
    text="${rest#"${name#MAKED_}"}"
    DOC_VARS="$DOC_VARS $name"
    while :; do
      case "$text" in
        /*)
          text="${text#/}"
          word="${text%%[!A-Z_]*}"
          text="${text#"$word"}"
          DOC_VARS="$DOC_VARS MAKED_$word"
          ;;
        *) break ;;
      esac
    done
  done
}

# A list without its leading or trailing space.
#
# TRIMMED holds the answer.
TRIMMED=""
trim() {
  local text="$1"
  while :; do
    case "$text" in
      " "*) text="${text# }" ;;
      *) break ;;
    esac
  done
  while :; do
    case "$text" in
      *" ") text="${text% }" ;;
      *) break ;;
    esac
  done
  TRIMMED="$text"
}

# The variables of the server that a claim names.
#
# DOC_SERVER_VARS holds them, and DOC_OTHER_VARS holds the ones the claim
# names that the server does not read.
DOC_SERVER_VARS=""
DOC_OTHER_VARS=""
doc_server_vars() {
  local claim="$1" name
  DOC_SERVER_VARS=""
  DOC_OTHER_VARS=""
  doc_claim_vars "$claim"
  for name in $DOC_VARS; do
    case " $ENV_VARS " in
      *" $name "*) DOC_SERVER_VARS="$DOC_SERVER_VARS $name" ;;
      *) DOC_OTHER_VARS="$DOC_OTHER_VARS $name" ;;
    esac
  done
  trim "$DOC_SERVER_VARS"; DOC_SERVER_VARS="$TRIMMED"
  trim "$DOC_OTHER_VARS"; DOC_OTHER_VARS="$TRIMMED"
}

ENV_BAD_VARS=0
ENV_BAD_SITE=0

# One claim, checked against the tree.
env_claim_check() {
  local doc="$1" line="$2" claim="$3" cited name count=0 total=0
  local cites=0 target covered
  # the claim has to be about the environment variables at all: it points at
  # the file the server reads them in, or it names the function that reads
  # them
  case "$claim" in
    *'cmd/server/main.mbt:'*) cites=1 ;;
    *env_or*) cites=1 ;;
    *) return ;;
  esac
  doc_server_vars "$claim"
  # a claim that points at the server's file must not name a variable the
  # server does not read
  case "$claim" in
    *'cmd/server/main.mbt:'*)
      if [ -n "$DOC_OTHER_VARS" ]; then
        fail "$(printf '%-22s %s line %s names [%s], and the server does not read them' \
          'env vars' "$doc" "$line" "$DOC_OTHER_VARS")"
        ENV_BAD_VARS=1
      fi
      ;;
  esac
  for name in $DOC_SERVER_VARS; do
    count=$((count + 1))
  done
  for name in $ENV_VARS; do
    total=$((total + 1))
  done
  # a claim that names two or more of them is stating the set
  if [ "$count" -ge 2 ] && [ "$count" -ne "$total" ]; then
    trim "$ENV_VARS"
    fail "$(printf '%-22s %s line %s names [%s], the server reads [%s]' \
      'env vars' "$doc" "$line" "$DOC_SERVER_VARS" "$TRIMMED")"
    ENV_BAD_VARS=1
  fi
  # the claim has to point at a line the variable is on
  case "$claim" in
    *'cmd/server/main.mbt:'*) ;;
    *) return ;;
  esac
  cited="${claim#*cmd/server/main.mbt:}"
  cited="${cited%%\`*}"
  cited="${cited%%|*}"
  cited="${cited// /}"
  for name in $DOC_SERVER_VARS; do
    env_var_mentions "$name"
    covered=0
    for target in $ENV_VAR_MENTIONS; do
      citation_covers "$cited" "$target"
      if [ "$CITATION_COVERS" -eq 1 ]; then
        covered=1
        break
      fi
    done
    if [ "$covered" -eq 0 ]; then
      trim "$ENV_VAR_MENTIONS"
      fail "$(printf '%-22s %s line %s cites [%s], the tree mentions %s on lines %s' \
        'env var site' "$doc" "$line" "$cited" "$name" "$TRIMMED")"
      ENV_BAD_SITE=1
    fi
  done
}

# Every claim the design documents make, checked against the environment.
check_env_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      env_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

code_env_vars

if [ -z "$ENV_VARS" ]; then
  fail "$(printf '%-22s the tree does not read any environment variable, or it does not read them the way this gate reads them' \
    'env vars')"
  ENV_BAD_VARS=1
  ENV_BAD_SITE=1
else
  check_env_claims
fi

if [ "$ENV_BAD_VARS" -eq 0 ]; then
  trim "$ENV_VARS"
  ok "env vars" "$TRIMMED"
fi
if [ "$ENV_BAD_SITE" -eq 0 ]; then
  ok "env var site" "cmd/server/main.mbt"
fi

# --- who stages the browser bundle ---------------------------------------------
#
# The browser bundle is one file: frontend/dist/main.js. The tree stages it in
# three places -- the build script, the CI workflow and the image -- and a
# document that says one of them is the only one sends a contributor to a
# place where the bundle is not, and states a fact about the build that is
# wrong.
#
# The tree's answer is read from the tree's build scripts: a file that copies
# the bundle the tree builds (web.js) to the path the server serves. The
# release workflow copies the bundle into the release archive instead, and
# that path is a longer one, so it is not one of them.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

STAGE_FILES=""
STAGE_NAMES=""
STAGE_CANDIDATES=""
code_stage_files() {
  local file base candidates="" names=""
  STAGE_FILES=""
  STAGE_NAMES=""
  STAGE_CANDIDATES=""
  for file in $(grep -rl --exclude='check-*.sh' --exclude='check-*.ps1' \
      -e 'web\.js' build.ps1 Dockerfile tools .github 2>/dev/null | LC_ALL=C sort -u); do
    base="${file##*/}"
    candidates="$candidates$base"$'\n'
    if grep -qE '[^A-Za-z0-9_/]frontend/dist/main\.js' "$file" 2>/dev/null; then
      STAGE_FILES="$STAGE_FILES $file"
      names="$names$base"$'\n'
    fi
  done
  STAGE_CANDIDATES=$(printf '%s' "$candidates" | LC_ALL=C sort -u | tr '\n' ' ')
  STAGE_NAMES=$(printf '%s' "$names" | LC_ALL=C sort -u | tr '\n' ' ')
  trim "$STAGE_CANDIDATES"; STAGE_CANDIDATES="$TRIMMED"
  trim "$STAGE_NAMES"; STAGE_NAMES="$TRIMMED"
}

# The staging files a claim names.
#
# A document names a file by its name: "ci.yml", not the whole path. The
# names are read from the candidates -- every build file that knows about the
# bundle -- so that a document naming a place the tree does not stage it is
# caught as well as one naming too few.
DOC_STAGE_FILES=""
doc_claim_stage_files() {
  local claim="$1" base
  DOC_STAGE_FILES=""
  for base in $STAGE_CANDIDATES; do
    case "$claim" in
      *"$base"*) DOC_STAGE_FILES="$DOC_STAGE_FILES $base" ;;
    esac
  done
  trim "$DOC_STAGE_FILES"; DOC_STAGE_FILES="$TRIMMED"
}

STAGE_BAD=0

# One claim, checked against the tree.
stage_claim_check() {
  local doc="$1" line="$2" claim="$3" file count=0 total=0
  # the claim has to be about the place the bundle is staged
  case "$claim" in
    *'frontend/dist/main.js'*) ;;
    *) return ;;
  esac
  doc_claim_stage_files "$claim"
  for file in $DOC_STAGE_FILES; do count=$((count + 1)); done
  for file in $STAGE_FILES; do total=$((total + 1)); done
  # a claim that names one of them is naming the places, and it has to name
  # all of them
  if [ "$count" -gt 0 ] && [ "$count" -ne "$total" ]; then
    fail "$(printf '%-22s %s line %s names [%s], the tree stages the bundle in [%s]' \
      'bundle staging' "$doc" "$line" "$DOC_STAGE_FILES" "$STAGE_NAMES")"
    STAGE_BAD=1
  fi
}

# The documents that name the bundle, and the tree's places that stage it.
check_stage_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}" "$AGENTS_DOC"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      stage_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

code_stage_files

if [ -z "$STAGE_FILES" ]; then
  fail "$(printf '%-22s the tree does not stage the browser bundle, or it does not stage it the way this gate reads it' \
    'bundle staging')"
  STAGE_BAD=1
else
  check_stage_claims
fi

if [ "$STAGE_BAD" -eq 0 ]; then
  ok "bundle staging" "$STAGE_NAMES"
fi

# --- the files the site ships ------------------------------------------------
#
# The site is the files the server serves: the ones the tree keeps under the
# dist directory, and the bundle the build stages there. Four documents say
# what those files are -- the evidence table, the deployment document, the
# deployment graph and the model -- and all four were free to be wrong:
# nothing read the tree to see what the site actually ships.
#
# A document states the list when it puts two or more of the files side by
# side: "index.html, main.js, styles.css". The files it looks for are the
# kinds the site ships -- html, js, css -- because the kinds come from the
# tree: a wider shape reads "build.ps1, ci.yml" in a sentence about the build
# as a list of the site's files. Two files a sentence mentions one after the
# other are a story, and a story is left alone. The table that lists the
# site's files is read as well: a table that names one of the files has to
# name all of them.
#
# The files the tree keeps are read with git, so a build that has run does not
# change the answer. The file the build stages is read out of the places that
# stage it.

BUNDLE_FILES=""
BUNDLE_KINDS=""
BUNDLE_BAD=0
BUNDLE_LISTS=0
BUNDLE_ROWS=""

# The files the site ships.
tree_bundle_files() {
  local out="" file name
  out=$(git ls-files frontend/dist 2>/dev/null | sed -e 's|.*/||' || true)
  for file in $STAGE_FILES; do
    for name in $(grep -ohE 'frontend/dist/[A-Za-z0-9_.-]+' "$file" 2>/dev/null || true); do
      out="$out
${name##*/}"
    done
  done
  printf '%s\n' "$out" | grep -v '^$' | LC_ALL=C sort -u
}

# The kinds of file the bundle holds: the extensions of its files.
tree_bundle_kinds() {
  local name
  for name in $BUNDLE_FILES; do
    case "$name" in
      *.*) printf '%s\n' "${name##*.}" ;;
    esac
  done | LC_ALL=C sort -u | tr '\n' ' '
}

# Is this name a file of the bundle's kind?
bundle_kind_name() {
  local name="$1" kind
  for kind in $BUNDLE_KINDS; do
    case "$name" in
      *".$kind") return 0 ;;
    esac
  done
  return 1
}

# A list of files, checked against the files the site ships.
bundle_list_check() {
  local doc="$1" line="$2" run="$3" name seen="" count=0 total=0
  [ -n "$run" ] || return
  for name in $run; do
    case " $seen " in
      *" $name "*) continue ;;
    esac
    if [ -z "$seen" ]; then seen="$name"; else seen="$seen $name"; fi
    count=$((count + 1))
  done
  # One name is not a list: a sentence that mentions one file is a story.
  [ "$count" -ge 2 ] || return
  for name in $seen; do
    case " $BUNDLE_FILES " in
      *" $name "*) ;;
      *)
        fail "$(printf '%-22s %s line %s names [%s], and the site ships no such file' \
          'bundle files' "$doc" "$line" "$name")"
        BUNDLE_BAD=1
        return
        ;;
    esac
  done
  for name in $BUNDLE_FILES; do total=$((total + 1)); done
  if [ "$count" -ne "$total" ]; then
    fail "$(printf '%-22s %s line %s states [%s], the site ships [%s]' \
      'bundle files' "$doc" "$line" "$seen" "$BUNDLE_FILES")"
    BUNDLE_BAD=1
    return
  fi
  BUNDLE_LISTS=$((BUNDLE_LISTS + 1))
}

# Does the claim name a file of the bundle's kind at all? A claim that does
# not cannot be stating a list, and the collapse below is not free.
bundle_claim_maybe() {
  local claim="$1" kind
  for kind in $BUNDLE_KINDS; do
    case "$claim" in
      *".$kind"*) return 0 ;;
    esac
  done
  return 1
}

# One claim, checked against the files the site ships.
bundle_claim_check() {
  local doc="$1" line="$2" claim="$3" text token run=""
  bundle_claim_maybe "$claim" || return
  # The claim is collapsed: every character that is not a letter, a digit, a
  # dot, an underscore or a dash becomes a space, so the names that sit side
  # by side in the collapsed claim are the ones that sat side by side in the
  # claim itself. The graphs write their line breaks as "\n", and that escape
  # would glue itself to the name behind it.
  text="${claim//\\n/ }"
  text="${text//[^A-Za-z0-9_.-]/ }"
  local -a tokens=()
  read -ra tokens <<< "$text"
  for token in "${tokens[@]}"; do
    if bundle_kind_name "$token"; then
      run="$run $token"
      continue
    fi
    bundle_list_check "$doc" "$line" "$run"
    run=""
  done
  bundle_list_check "$doc" "$line" "$run"
}

# The rows of the table that lists the site's files.
#
# A row whose first cell is a file under the dist directory is a row of that
# table, and a table that names one of the files the site ships has to name
# all of them: a table one file short sends a reader looking for a file the
# site does not have.
doc_bundle_rows() {
  local file="$1" name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    case " $BUNDLE_ROWS " in
      *" $name "*) continue ;;
    esac
    if [ -z "$BUNDLE_ROWS" ]; then BUNDLE_ROWS="$name"; else BUNDLE_ROWS="$BUNDLE_ROWS $name"; fi
  done <<< "$(grep -oE '^\| `frontend/dist/[A-Za-z0-9_.-]+`' "$file" 2>/dev/null \
    | sed -e 's|.*/||' -e 's|`||' || true)"
}

BUNDLE_FILES=$(tree_bundle_files | tr '\n' ' ')
trim "$BUNDLE_FILES"; BUNDLE_FILES="$TRIMMED"
BUNDLE_KINDS=$(tree_bundle_kinds)

if [ -z "$BUNDLE_FILES" ]; then
  fail "$(printf '%-22s the tree ships no files, or it does not say so the way this gate reads it' \
    'bundle files')"
  BUNDLE_BAD=1
else
  for doc in "${ARCH_DOCS[@]}" "$SYSTEM_MODEL_DSL"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      bundle_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
    doc_bundle_rows "$doc"
  done

  # every file the table names is a file the site ships
  for name in $BUNDLE_ROWS; do
    case " $BUNDLE_FILES " in
      *" $name "*) ;;
      *)
        fail "$(printf '%-22s the documents list [%s], and the site ships no such file' \
          'bundle files' "$name")"
        BUNDLE_BAD=1
        ;;
    esac
  done
  # and the table names them all
  bundle_rows_count=0
  for name in $BUNDLE_ROWS; do bundle_rows_count=$((bundle_rows_count + 1)); done
  bundle_files_count=0
  for name in $BUNDLE_FILES; do bundle_files_count=$((bundle_files_count + 1)); done
  if [ "$bundle_rows_count" -ne "$bundle_files_count" ]; then
    fail "$(printf '%-22s the documents list [%s], the site ships [%s]' \
      'bundle files' "$BUNDLE_ROWS" "$BUNDLE_FILES")"
    BUNDLE_BAD=1
  fi
fi

if [ "$BUNDLE_BAD" -eq 0 ]; then
  ok "bundle files" "$BUNDLE_LISTS lists"
fi

# --- where each asset of the site comes from ----------------------------------
#
# The static assets table says where the three files of the site come from: two
# of them are written by hand and the third is built by the build script, the CI
# workflow and the image. Nothing read the tree to see whether that was true:
# the table could have called the bundle hand-written, or the shell generated,
# and no gate would have said a word.
#
# Git is the oracle for the first half. A file of the dist directory that git
# tracks is source the tree keeps, and a file git does not track is a file the
# build makes. The document has to say the same thing about every row.
#
# How a cell says it is read from the tree's own vocabulary: the scripts that
# stage the bundle, and the build output root they copy out of. A cell that
# names one of those is saying the file is built; a cell that names none of
# them is saying the file is source. A cell that says a file is built also has
# to point at the build output it comes from, and that output has to be one the
# tree builds.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

ASSET_BAD=0
ASSET_CHECKED=0
ASSET_DIST=""
ASSET_TRACKED=""
ASSET_CELL_NATURE=""
ASSET_TREE_NATURE=""
ASSET_BUILD_OUTPUTS=""
ASSET_ROWS=""
ASSET_TICK='`'

# The dist directory: the default of MAKED_DIST. The server serves that
# directory, so it is the directory the site lives in.
tree_dist_dir() {
  local line
  ASSET_DIST=""
  while IFS= read -r line; do
    case "$line" in
      MAKED_DIST\ *) ASSET_DIST="${line#MAKED_DIST }"; return ;;
    esac
  done <<< "$CODE_SETTINGS"
}

# The files of the dist directory git keeps: the source of the site.
#
# Git is asked, not the file system, so a build that has run does not change
# the answer.
tree_asset_tracked() {
  ASSET_TRACKED=""
  [ -n "$ASSET_DIST" ] || return
  ASSET_TRACKED=$(git ls-files "$ASSET_DIST" 2>/dev/null | LC_ALL=C sort -u || true)
}

# What the tree has: source, or built.
tree_asset_nature() {
  local name="$1"
  ASSET_TREE_NATURE="built"
  if printf '%s\n' "$ASSET_TRACKED" | grep -qxF "$ASSET_DIST/$name"; then
    ASSET_TREE_NATURE="source"
  fi
}

# What the document's cell says: built, or source.
#
# The vocabulary is the tree's: the scripts that stage the bundle, and the
# build output root they copy out of. A cell that names one of those is saying
# the file is built. A cell that names none of them is saying the file is
# source. The words are the ones that say a file is made rather than written.
asset_cell_nature() {
  local cell="$1" low name lowname
  ASSET_CELL_NATURE="source"
  low="${cell,,}"
  for name in $STAGE_NAMES; do
    lowname="${name,,}"
    case "$low" in
      *"$lowname"*) ASSET_CELL_NATURE="built"; return ;;
    esac
  done
  case "$low" in
    *generated*|*copied*|*produced*|*compiled*|*staged*|*'_build/'*)
      ASSET_CELL_NATURE="built"
      return
      ;;
  esac
}

# The first two cells of a table row.
#
# A row is a line that starts with a pipe. The cells are what is between the
# pipes, and the pipes are not part of the cell.
ROW_C1=""
ROW_C2=""
ROW_C3=""
ROW_C4=""
row_cells() {
  local line="$1" rest
  ROW_C1=""
  ROW_C2=""
  ROW_C3=""
  ROW_C4=""
  rest="${line#\|}"
  ROW_C1="${rest%%|*}"
  rest="${rest#*\|}"
  case "$rest" in
    *'|'*) ROW_C2="${rest%%|*}" ;;
    *) ROW_C2="$rest" ;;
  esac
  rest="${rest#*\|}"
  case "$rest" in
    *'|'*) ROW_C3="${rest%%|*}" ;;
    *) ROW_C3="$rest" ;;
  esac
  rest="${rest#*\|}"
  case "$rest" in
    *'|'*) ROW_C4="${rest%%|*}" ;;
    *) ROW_C4="$rest" ;;
  esac
  trim "$ROW_C1"; ROW_C1="$TRIMMED"
  trim "$ROW_C2"; ROW_C2="$TRIMMED"
  trim "$ROW_C3"; ROW_C3="$TRIMMED"
  trim "$ROW_C4"; ROW_C4="$TRIMMED"
}

# The rows of the table that gives the site's files their source.
#
# The table is the one whose header names a file and a source. The rows are the
# lines after it whose first cell is a file of the dist directory. The third
# cell -- the purpose -- is carried along: the gates that read this table do
# not all read the same column of it.
asset_rows() {
  local file="$1" line in_table=0 n=0 first
  ASSET_ROWS=""
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    case "$line" in
      '|'*) ;;
      *) in_table=0; continue ;;
    esac
    row_cells "$line"
    if [ "$in_table" -eq 0 ]; then
      if [ "$ROW_C1" = "File" ] && [ "$ROW_C2" = "Source" ]; then
        in_table=1
      fi
      continue
    fi
    first="${ROW_C1//$ASSET_TICK/}"
    case "$first" in
      "$ASSET_DIST"/*) ;;
      *) continue ;;
    esac
    ASSET_ROWS="$ASSET_ROWS$n"$'\t'"$first"$'\t'"$ROW_C2"$'\t'"$ROW_C3"$'\n'
  done < "$file"
}

# One row, checked against the tree.
asset_row_check() {
  local doc="$1" line="$2" file="$3" cell="$4" name tree nature path found=0
  name="${file##*/}"
  ASSET_CHECKED=$((ASSET_CHECKED + 1))
  tree_asset_nature "$name"
  tree="$ASSET_TREE_NATURE"
  asset_cell_nature "$cell"
  nature="$ASSET_CELL_NATURE"
  if [ "$nature" != "$tree" ]; then
    fail "$(printf '%-22s %s line %s says [%s] is %s, the tree has it as %s' \
      'asset source' "$doc" "$line" "$name" "$nature" "$tree")"
    ASSET_BAD=1
    return
  fi
  # a file the build makes has to say which build output it comes from
  [ "$nature" = "built" ] || return
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    found=1
    case " $ASSET_BUILD_OUTPUTS " in
      *" $path "*) ;;
      *)
        fail "$(printf '%-22s %s line %s states [%s], and the tree builds no such path' \
          'asset source' "$doc" "$line" "$path")"
        ASSET_BAD=1
        return
        ;;
    esac
  done <<< "$(printf '%s' "$cell" | grep -oE '_build/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*' || true)"
  if [ "$found" -eq 0 ]; then
    fail "$(printf '%-22s %s line %s says [%s] is built, and names no build output' \
      'asset source' "$doc" "$line" "$name")"
    ASSET_BAD=1
  fi
}

tree_dist_dir
tree_asset_tracked
join_lines "$TREE_BUILD_OUTPUTS"; ASSET_BUILD_OUTPUTS="$JOIN_LINES"

if [ -z "$ASSET_DIST" ]; then
  fail "$(printf '%-22s the tree does not say where the site lives' \
    'asset source')"
  ASSET_BAD=1
else
  for doc in "${ARCH_DOCS[@]}" "$AGENTS_DOC"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    asset_rows "$doc"
    while IFS=$'\t' read -r line file cell purpose; do
      [ -n "$file" ] || continue
      asset_row_check "$doc" "$line" "$file" "$cell"
    done <<< "$ASSET_ROWS"
  done
  if [ "$ASSET_CHECKED" -eq 0 ]; then
    fail "$(printf '%-22s no document says where the files of the site come from' \
      'asset source')"
    ASSET_BAD=1
  fi
fi

if [ "$ASSET_BAD" -eq 0 ]; then
  ok "asset source" "$ASSET_CHECKED rows"
fi

# --- the components the deployment document puts on the machine ----------------
#
# The runtime topology table says what each component is and where it lives: the
# server is a process, the database is a file at a path, the static files are a
# directory at a path. Nothing read the tree to see whether that was true: the
# table could have called the database a directory, or put it at a path the
# server does not read, and no gate would have said a word.
#
# The tree says both things.
#
# A path the tree has is a DIRECTORY when the tree has files under it -- git
# does not track an empty directory, so a path with files under it is a
# directory the tree fills -- and a FILE otherwise.
#
# A path the tree has is a path the server reads (the default of one of its
# settings) or a path the tree keeps (a file git tracks). The table may only
# put a component at such a path.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

COMPONENT_BAD=0
COMPONENT_CHECKED=0
COMPONENT_PATHS=""
COMPONENT_FILES=""
COMPONENT_KIND=""
COMPONENT_ROWS=""
COMPONENT_TICK='`'

# The defaults the server reads: the paths it is pointed at.
code_setting_paths() {
  local line name value
  COMPONENT_PATHS=""
  while IFS= read -r line; do
    name="${line%% *}"
    value="${line#* }"
    [ "$name" != "$value" ] || continue
    COMPONENT_PATHS="$COMPONENT_PATHS $value"
  done <<< "$CODE_SETTINGS"
  trim "$COMPONENT_PATHS"; COMPONENT_PATHS="$TRIMMED"
}

# The files the tree keeps.
tree_component_files() {
  COMPONENT_FILES=$(git ls-files 2>/dev/null | LC_ALL=C sort -u || true)
}

# Does the tree have this path? A path the server reads, or a file it keeps.
component_has_path() {
  local path="$1" value line
  for value in $COMPONENT_PATHS; do
    if [ "$value" = "$path" ]; then return 0; fi
  done
  while IFS= read -r line; do
    if [ "$line" = "$path" ]; then return 0; fi
  done <<< "$COMPONENT_FILES"
  return 1
}

# What the tree has: a directory, or a file.
component_kind() {
  local path="$1"
  COMPONENT_KIND="file"
  case "$COMPONENT_FILES" in
    *"
$path/"*) COMPONENT_KIND="directory" ;;
  esac
}

# The rows of the table that puts the components on the machine.
#
# The table is the one whose header names a component and a location. The rows
# are the lines after it.
COMPONENT_ROWS=""
component_rows() {
  local file="$1" line in_table=0 n=0
  COMPONENT_ROWS=""
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    case "$line" in
      '|'*) ;;
      *) in_table=0; continue ;;
    esac
    row_cells "$line"
    if [ "$in_table" -eq 0 ]; then
      if [ "$ROW_C1" = "Component" ] && [ "$ROW_C3" = "Location" ]; then
        in_table=1
      fi
      continue
    fi
    case "$ROW_C1" in
      ''|'---'*) continue ;;
    esac
    COMPONENT_ROWS="$COMPONENT_ROWS$n"$'\t'"$ROW_C1"$'\t'"$ROW_C2"$'\t'"$ROW_C3"$'\n'
  done < "$file"
}

# One row, checked against the tree.
component_row_check() {
  local doc="$1" line="$2" name="$3" type="$4" location="$5" path kind low
  COMPONENT_CHECKED=$((COMPONENT_CHECKED + 1))
  low="${type,,}"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    # a trailing slash is how a document writes a directory
    path="${path%/}"
    if ! component_has_path "$path"; then
      fail "$(printf '%-22s %s line %s puts [%s] at [%s], and the tree has no such path' \
        'deploy component' "$doc" "$line" "$name" "$path")"
      COMPONENT_BAD=1
      continue
    fi
    component_kind "$path"
    kind="$COMPONENT_KIND"
    case "$low" in
      "$kind"*) ;;
      *)
        fail "$(printf '%-22s %s line %s says [%s] is a %s, the tree has it as a %s' \
          'deploy component' "$doc" "$line" "$name" "$low" "$kind")"
        COMPONENT_BAD=1
        ;;
    esac
  done <<< "$(printf '%s' "$location" | grep -oE '`[^`]+`' | tr -d '`' || true)"
}

code_setting_paths
tree_component_files

for doc in "${ARCH_DOCS[@]}" "$AGENTS_DOC"; do
  not_in "$doc" "$MARKED_DOCS"
  [ -n "$NOT_IN" ] || continue
  component_rows "$doc"
  while IFS=$'\t' read -r line name type location; do
    [ -n "$name" ] || continue
    component_row_check "$doc" "$line" "$name" "$type" "$location"
  done <<< "$COMPONENT_ROWS"
done

if [ "$COMPONENT_CHECKED" -eq 0 ]; then
  fail "$(printf '%-22s no document says where the components live' \
    'deploy component')"
  COMPONENT_BAD=1
fi

if [ "$COMPONENT_BAD" -eq 0 ]; then
  ok "deploy component" "$COMPONENT_CHECKED rows"
fi

# --- the technologies the model gives its containers ---------------------------
#
# The model says what each of its containers is built from: a native binary on
# moonback and sqlite3, a js bundle on rabbita, a sqlite3 file, a native
# binary that speaks MCP. Those are the tree's libraries, and nothing checks
# them: the model could name a library the tree has never heard of, and every
# document would go on saying what it always said.
#
# The libraries are the tree's: the dependencies the module declares in
# moon.mod, by their package name.
#
# A technology says which libraries it is made of. A list of them is a list of
# names side by side ("moonback + sqlite3"), and every name in that list has
# to be a library the tree depends on. A technology that says it in a sentence
# instead ("MCP over stdio or HTTP") has to name a library the tree depends
# on.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

DSL_TECH_BAD=0
DSL_TECH_CHECKED=0
DSL_TECH_LIBS=""

# The libraries the module depends on: the package name of every dependency.
code_module_libraries() {
  local line module name
  DSL_TECH_LIBS=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    module="${line%%@*}"
    name="${module##*/}"
    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    DSL_TECH_LIBS="$DSL_TECH_LIBS $name"
  done < <(sed -nE 's/^ *"([^"]+)@([^"]+)".*/\1/p' moon.mod)
  trim "$DSL_TECH_LIBS"; DSL_TECH_LIBS="$TRIMMED"
}

# Is this name one the tree depends on?
#
# The comparison is on the case: the model writes MCP and the dependency is
# called mcp, and they are the same library.
dsl_library_known() {
  local name="$1" lib
  local low="${name,,}"
  for lib in $DSL_TECH_LIBS; do
    if [ "$low" = "${lib,,}" ]; then
      return 0
    fi
  done
  return 1
}

# Does this text name a library the tree depends on?
dsl_names_library() {
  local text="$1" lib
  local low="${text,,}"
  for lib in $DSL_TECH_LIBS; do
    if [[ "$low" =~ ([^A-Za-z0-9_]|^)${lib,,}([^A-Za-z0-9_]|$) ]]; then
      return 0
    fi
  done
  return 1
}

# One technology, checked against the libraries the tree depends on.
dsl_technology_check() {
  local line="$1" tech="$2" body piece bad=""
  # the brackets, if there are any
  body=""
  case "$tech" in
    *"("*")"*) body="${tech#*\(}"; body="${body%\)*}" ;;
  esac
  [ -n "$body" ] || body="$tech"
  DSL_TECH_CHECKED=$((DSL_TECH_CHECKED + 1))
  case "$body" in
    *+*)
      # a list of libraries
      local rest="$body"
      while [ -n "$rest" ]; do
        piece="${rest%%+*}"
        if [ "$piece" = "$rest" ]; then rest=""; else rest="${rest#*+}"; fi
        trim "$piece"; piece="$TRIMMED"
        [ -n "$piece" ] || continue
        if ! dsl_library_known "$piece"; then
          bad="$bad $piece"
        fi
      done
      if [ -n "$bad" ]; then
        trim "$bad"; bad="$TRIMMED"
        fail "$(printf '%-22s %s line %s names the library [%s], the tree does not depend on it' \
          'dsl technologies' "$SYSTEM_MODEL_DSL" "$line" "$bad")"
        DSL_TECH_BAD=1
      fi
      ;;
    *)
      # a sentence: it has to name a library the tree depends on
      if ! dsl_names_library "$body"; then
        fail "$(printf '%-22s %s line %s names no library the tree depends on' \
          'dsl technologies' "$SYSTEM_MODEL_DSL" "$line")"
        DSL_TECH_BAD=1
      fi
      ;;
  esac
}

# Every container the model gives, checked against the libraries.
check_dsl_technologies() {
  local line tech n=0
  local re='= container "[^"]*" "[^"]*" "([^"]*)"'
  while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in
      *"= container "*) ;;
      *) continue ;;
    esac
    if [[ "$line" =~ $re ]]; then
      tech="${BASH_REMATCH[1]}"
      dsl_technology_check "$n" "$tech"
    fi
  done < "$SYSTEM_MODEL_DSL"
}

code_module_libraries
check_dsl_technologies

if [ "$DSL_TECH_BAD" -eq 0 ]; then
  ok "dsl technologies" "$DSL_TECH_CHECKED containers"
fi

# --- the mechanisms the model gives its relationships ---------------------------
#
# The model says how each of its relationships is carried: HTTP for the
# browser, stdio or HTTP for the agent, in process for the agent's server
# talking to the backend, SQLite FFI for the database. Those are the tree's
# mechanisms, and nothing checked them: the model could say the database is a
# Postgres FFI, or that the agent speaks SMTP, and every document would go on
# saying what it always said.
#
# The tree's mechanisms come from the tree:
#
#   - the SQL library is the one the storage layer opens -- a @sqlite3
#     connection. A file of that library is reached by a native call and not
#     over a network, so the mechanism for that edge is the library itself.
#   - the MCP server offers the transports its own source offers: stdio, and
#     HTTP when it is given a port.
#   - the server the browser talks to speaks HTTP: it listens on a socket and
#     prints http:// URLs.
#   - the MCP server reaches the backend in its own process: it calls the
#     backend's package and makes no network call at all.
#
# A protocol names mechanisms in words. The words it names have to be the ones
# the tree has for that edge, and a protocol for an edge the tree crosses has
# to name one of them. A protocol that names a path has to name a route the
# tree serves.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

DSL_PROTO_BAD=0
DSL_PROTO_CHECKED=0

# The words that name a mechanism. A word in a protocol is a claim about a
# mechanism only when it is one of these; the rest of a protocol is prose.
#
# The secure ones are not here: the edge gate reads the denials and the
# channel gate reads the claims that the channel is secure, and this gate is
# about the other mechanisms.
MECHANISM_WORDS="http stdio fs file sqlite sqlite3 tcp udp ftp smtp imap pop3 ssh websocket grpc amqp mqtt redis kafka postgres postgresql mysql mariadb mongo mongodb memcached elasticsearch duckdb oracle ldap pipe socket unix rpc ipc"

# The libraries each container of the model is made of, and the container
# that is only the SQL library, and the container that speaks MCP.
#
# A technology says which libraries it is made of: a list of them is a list
# of names side by side ("moonback + sqlite3"), and a technology that says it
# in a sentence names one.
code_dsl_containers() {
  local line tech body piece name libs rest
  local re='=[[:space:]]+container[[:space:]]+"[^"]*"[[:space:]]+"[^"]*"[[:space:]]+"([^"]*)"'
  while IFS= read -r line; do
    case "$line" in
      *"= container "*) ;;
      *) continue ;;
    esac
    [[ "$line" =~ $re ]] || continue
    tech="${BASH_REMATCH[1]}"
    name="${line%%= container*}"
    name="${name#"${name%%[![:space:]]*}"}"
    name="${name%"${name##*[![:space:]]}"}"
    body=""
    case "$tech" in
      *"("*")"*) body="${tech#*\(}"; body="${body%\)*}" ;;
    esac
    [ -n "$body" ] || body="$tech"
    libs=""
    case "$body" in
      *+*)
        rest="$body"
        while [ -n "$rest" ]; do
          piece="${rest%%+*}"
          if [ "$piece" = "$rest" ]; then rest=""; else rest="${rest#*+}"; fi
          trim "$piece"; piece="$TRIMMED"
          [ -n "$piece" ] || continue
          dsl_library_known "$piece" && libs="$libs $piece"
        done
        ;;
      *)
        for piece in $DSL_TECH_LIBS; do
          if [[ "${body,,}" =~ (^|[^A-Za-z0-9_])${piece,,}([^A-Za-z0-9_]|$) ]]; then
            libs="$libs $piece"
          fi
        done
        ;;
    esac
    trim "$libs"; libs="$TRIMMED"
    printf '%s\037%s\n' "$name" "$libs"
  done < "$SYSTEM_MODEL_DSL"
}

# The library the storage layer opens: the tree's SQL one.
code_sql_library() {
  local lib
  for lib in $DSL_TECH_LIBS; do
    if grep -q "@$lib\.Connection" backend/database.mbt 2>/dev/null; then
      echo "$lib"
      return
    fi
  done
}

# The library the MCP server uses: the tree's MCP one.
code_mcp_library() {
  local lib
  for lib in $DSL_TECH_LIBS; do
    if grep -q "@$lib\." cmd/mcp/main.mbt 2>/dev/null; then
      echo "$lib"
      return
    fi
  done
}

# The transports the MCP server offers: the ones its own source names.
code_mcp_transports() {
  local word
  for word in stdio http; do
    if grep -qi "$word" cmd/mcp/main.mbt 2>/dev/null; then
      echo "$word"
    fi
  done
}

# The transports the server the browser talks to speaks.
code_server_transports() {
  local word
  for word in http; do
    if grep -qi "$word" cmd/server/main.mbt 2>/dev/null; then
      echo "$word"
    fi
  done
}

# The mechanisms a protocol names, in the order it names them.
#
# Only the words that name a mechanism are mechanisms; the rest of a protocol
# is prose ("static files", "in process", "GET"). A word is read in its
# parts, so that "HTTP/1.1" names HTTP.
dsl_protocol_mechanisms() {
  local protocol="$1" word part low
  DSL_PROTO_MECHANISMS=""
  for word in $protocol; do
    for part in $(printf '%s' "$word" | tr -c 'A-Za-z0-9' ' '); do
      low="${part,,}"
      [ -n "$low" ] || continue
      case " $MECHANISM_WORDS " in
        *" $low "*) ;;
        *) continue ;;
      esac
      case " $DSL_PROTO_MECHANISMS " in
        *" $low "*) continue ;;
      esac
      DSL_PROTO_MECHANISMS="$DSL_PROTO_MECHANISMS $low"
    done
  done
}

# Does the tree serve this path, with this method?
#
# The tree's endpoints are "METHOD path". The space inside one of them is
# turned into a bar first, so that each endpoint is a word of its own and a
# path is never split in two.
tree_serves_path() {
  local want_path="$1" want_method="$2" endpoint emethod epath
  for endpoint in $(printf '%s\n' "$TREE_ENDPOINTS" | sed 's/ /|/'); do
    emethod="${endpoint%%|*}"
    epath="${endpoint#*|}"
    [ "$epath" = "$want_path" ] || continue
    if [ -z "$want_method" ] || [ "$emethod" = "$want_method" ]; then
      return 0
    fi
  done
  return 1
}

# The relationships the model gives, checked against the tree.
check_dsl_protocols() {
  local line n=0 from to desc protocol named allowed ok
  local re='([[:alnum:]_]+)[[:space:]]*->[[:space:]]*([[:alnum:]_]+)[[:space:]]+"([^"]*)"[[:space:]]+"([^"]*)"'
  local sql_lib mcp_lib sql_container mcp_container
  local src_libs dst_libs path method word mechanism
  local entry name libs
  sql_lib="$(code_sql_library)"
  mcp_lib="$(code_mcp_library)"
  sql_container=''
  mcp_container=''
  while IFS=$'\037' read -r name libs; do
    [ -n "$name" ] || continue
    if [ -n "$sql_lib" ] && [ "$libs" = "$sql_lib" ]; then sql_container="$name"; fi
    if [ -n "$mcp_lib" ]; then
      case " $libs " in
        *" $mcp_lib "*) mcp_container="$name" ;;
      esac
    fi
  done <<< "$(code_dsl_containers)"
  while IFS= read -r line; do
    n=$((n + 1))
    [[ "$line" =~ $re ]] || continue
    from="${BASH_REMATCH[1]}"
    to="${BASH_REMATCH[2]}"
    protocol="${BASH_REMATCH[4]}"
    DSL_PROTO_CHECKED=$((DSL_PROTO_CHECKED + 1))
    # the libraries the two ends are made of
    src_libs=''
    dst_libs=''
    while IFS=$'\037' read -r name libs; do
      [ -n "$name" ] || continue
      [ "$name" = "$from" ] && src_libs="$libs"
      [ "$name" = "$to" ] && dst_libs="$libs"
    done <<< "$(code_dsl_containers)"
    # the mechanisms the tree has for that edge
    allowed=''
    if [ -n "$sql_lib" ] && [ "$dst_libs" = "$sql_lib" ]; then
      # the file of the SQL library is reached by a native call
      allowed="${sql_lib%%[0-9]*}"
    elif [ -n "$mcp_lib" ] && [ "$dst_libs" = "$mcp_lib" ]; then
      allowed="$(code_mcp_transports | tr '\n' ' ')"
    elif [ -n "$mcp_container" ] && [ "$from" = "$mcp_container" ]; then
      # the MCP server reaches the backend in its own process
      allowed=''
    else
      allowed="$(code_server_transports | tr '\n' ' ')"
    fi
    dsl_protocol_mechanisms "$protocol"
    named="$DSL_PROTO_MECHANISMS"
    trim "$named"; named="$TRIMMED"
    trim "$allowed"; allowed="$TRIMMED"
    ok=1
    for mechanism in $named; do
      case " $allowed " in
        *" $mechanism "*) ;;
        *) ok=0 ;;
      esac
    done
    if [ "$ok" -eq 1 ] && [ -n "$allowed" ] && [ -z "$named" ]; then
      ok=0
    fi
    if [ "$ok" -eq 0 ]; then
      fail "$(printf '%-22s %s line %s names [%s], and the tree carries that edge by [%s]' \
        'dsl protocols' "$SYSTEM_MODEL_DSL" "$n" "$named" "$allowed")"
      DSL_PROTO_BAD=1
      continue
    fi
    # a path in the protocol is a route the tree has to serve
    path=''
    method=''
    for word in $protocol; do
      word="${word%%[.,;:!?)]*}"
      case "$word" in
        /*) path="$word" ;;
        GET|POST|PUT|DELETE|PATCH|HEAD) [ -n "$method" ] || method="$word" ;;
      esac
    done
    if [ -n "$path" ] && ! tree_serves_path "$path" "$method"; then
      fail "$(printf '%-22s %s line %s names the route %s, and the tree serves no such route' \
        'dsl protocols' "$SYSTEM_MODEL_DSL" "$n" "$path")"
      DSL_PROTO_BAD=1
    fi
  done < "$SYSTEM_MODEL_DSL"
}

check_dsl_protocols

if [ "$DSL_PROTO_BAD" -eq 0 ]; then
  ok "dsl protocols" "$DSL_PROTO_CHECKED relationships"
fi

# --- the node colours ----------------------------------------------------------
#
# The mark draws five nodes, and the tree names the colour each one keeps in
# the logo file's own comment: the sentence that starts "Each node keeps the
# colour" and ends at the first full stop. The colours are a human gloss --
# the tree pins the hexes, not the words -- so the words are read out of the
# tree and compared with the words the documents use.
#
# A claim is a colour claim when it talks about colours at all. A claim that
# does not is left alone: "A page is served" is not a claim about the colour
# of a node, and reading it as one would be reading a word as a thing.
#
# A claim that names two or more of the colours is stating the list, and the
# list has to be the tree's list: one colour too few leaves a reader guessing
# what the last node looks like. A claim that names one of them is stating
# that one, and it only has to be true.
#
# A claim that points at the logo file has to point at a line the tree names
# the colours on.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

# The letters the mark draws, out of the tuples in nodes().
CODE_LETTERS=""
# The sentence the tree names the colours in.
CODE_COLOR_SENTENCE=""
# The colours the tree states: "M indigo", "D green", and so on.
CODE_COLOR_PAIRS=()
CODE_NODE_COLORS=""
CODE_COLOR_SET=""
CODE_COLOR_WORDS=""
# The lines the tree names the colours on.
CODE_COLOR_LINES=""

# A pair is a node letter, a space, and a word. The letter has to be one of
# the tree's, and it has to stand on its own: the letter in the middle of a
# longer word is part of that word, not a node. The pattern is built from the
# tree's letters once they are known.
PAIR_RE=""
# A claim that talks about colours says so in so many words.
COLOR_TRIGGER_RE='([^A-Za-z0-9_])(colou?rs?)([^A-Za-z0-9_]|$)'

code_node_colors() {
  local letter pair word line n=0 rest
  CODE_LETTERS=""
  CODE_COLOR_SENTENCE=""
  CODE_COLOR_PAIRS=()
  CODE_NODE_COLORS=""
  CODE_COLOR_SET=""
  CODE_COLOR_WORDS=""
  CODE_COLOR_LINES=""
  # the letters the mark draws
  while IFS= read -r letter; do
    [ -n "$letter" ] || continue
    if [ -z "$CODE_LETTERS" ]; then CODE_LETTERS="$letter"; else CODE_LETTERS="$CODE_LETTERS $letter"; fi
  done < <(grep -oE '\("[A-Z]",' frontend/logo.mbt | grep -oE '[A-Z]' || true)
  [ -n "$CODE_LETTERS" ] || return
  # the sentence the tree names the colours in
  CODE_COLOR_SENTENCE=$(tr '\n' ' ' < frontend/logo.mbt \
    | grep -oE 'Each node keeps the colour[^.]*\.' | head -1 || true)
  [ -n "$CODE_COLOR_SENTENCE" ] || return
  # the pairs it states
  PAIR_RE="([^A-Za-z0-9_])([${CODE_LETTERS// /}]) ([a-z]+)"
  rest=" $CODE_COLOR_SENTENCE"
  while [[ "$rest" =~ $PAIR_RE ]]; do
    pair="${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
    CODE_COLOR_PAIRS+=("$pair")
    if [ -z "$CODE_NODE_COLORS" ]; then CODE_NODE_COLORS="$pair"; else CODE_NODE_COLORS="$CODE_NODE_COLORS $pair"; fi
    if [ -z "$CODE_COLOR_SET" ]; then CODE_COLOR_SET="$pair"; else CODE_COLOR_SET="$CODE_COLOR_SET"$'\n'"$pair"; fi
    word="${pair#* }"
    if [ -z "$CODE_COLOR_WORDS" ]; then CODE_COLOR_WORDS="$word"; else CODE_COLOR_WORDS="$CODE_COLOR_WORDS $word"; fi
    rest="${rest#*"${BASH_REMATCH[0]}"}"
  done
  # the lines the tree names them on
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    for pair in "${CODE_COLOR_PAIRS[@]}"; do
      case "$line" in
        *"$pair"*)
          CODE_COLOR_LINES="$CODE_COLOR_LINES $n"
          break
          ;;
      esac
    done
  done < frontend/logo.mbt
  trim "$CODE_COLOR_LINES"; CODE_COLOR_LINES="$TRIMMED"
}

# The colours a claim states.
DOC_NODE_COLORS=""
DOC_COLOR_SET=""
DOC_COLOR_COUNT=0
doc_claim_colors() {
  local claim="$1" pair rest
  DOC_NODE_COLORS=""
  DOC_COLOR_SET=""
  DOC_COLOR_COUNT=0
  [ -n "$PAIR_RE" ] || return
  rest=" $claim"
  while [[ "$rest" =~ $PAIR_RE ]]; do
    pair="${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
    if [ -z "$DOC_NODE_COLORS" ]; then DOC_NODE_COLORS="$pair"; else DOC_NODE_COLORS="$DOC_NODE_COLORS $pair"; fi
    if [ -z "$DOC_COLOR_SET" ]; then DOC_COLOR_SET="$pair"; else DOC_COLOR_SET="$DOC_COLOR_SET"$'\n'"$pair"; fi
    DOC_COLOR_COUNT=$((DOC_COLOR_COUNT + 1))
    rest="${rest#*"${BASH_REMATCH[0]}"}"
  done
}

COLOR_BAD_WORDS=0
COLOR_BAD_SITE=0

# One claim, checked against the tree.
color_claim_check() {
  local doc="$1" line="$2" claim="$3" cited target lower
  # the claim has to be about the colours at all
  lower="${claim,,}"
  [[ " $lower" =~ $COLOR_TRIGGER_RE ]] || return
  doc_claim_colors "$claim"
  [ "$DOC_COLOR_COUNT" -gt 0 ] || return
  # every colour the claim states has to be one the tree states
  not_in "$DOC_COLOR_SET" "$CODE_COLOR_SET"
  if [ -n "$NOT_IN" ]; then
    join_lines "$NOT_IN"; local stated="$JOIN_LINES"
    fail "$(printf '%-22s %s line %s states [%s], the tree says [%s]' \
      'node colors' "$doc" "$line" "$stated" "$CODE_NODE_COLORS")"
    COLOR_BAD_WORDS=1
    return
  fi
  # a claim that names two or more of them is stating the list, and the list
  # has to be the whole list
  if [ "$DOC_COLOR_COUNT" -ge 2 ] && [ "$DOC_COLOR_COUNT" -ne "${#CODE_COLOR_PAIRS[@]}" ]; then
    fail "$(printf '%-22s %s line %s states [%s], the tree says [%s]' \
      'node colors' "$doc" "$line" "$DOC_NODE_COLORS" "$CODE_NODE_COLORS")"
    COLOR_BAD_WORDS=1
    return
  fi
  # and the pointer has to land on a line the tree names the colours on
  case "$claim" in
    *'frontend/logo.mbt:'*) ;;
    *) return ;;
  esac
  cited="${claim#*frontend/logo.mbt:}"
  cited="${cited%%\`*}"
  cited="${cited%%|*}"
  cited="${cited// /}"
  for target in $CODE_COLOR_LINES; do
    citation_covers "$cited" "$target"
    if [ "$CITATION_COVERS" -eq 0 ]; then
      fail "$(printf '%-22s %s line %s cites [%s], the tree names the colours on lines %s' \
        'node color site' "$doc" "$line" "$cited" "$CODE_COLOR_LINES")"
      COLOR_BAD_SITE=1
      return
    fi
  done
}

# Every claim the design documents make, checked against the colours.
check_color_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}" "$AGENTS_DOC"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      color_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

code_node_colors

if [ -z "$CODE_NODE_COLORS" ]; then
  fail "$(printf '%-22s the tree does not name the node colours, or it does not name them the way this gate reads them' \
    'node colors')"
  COLOR_BAD_WORDS=1
  COLOR_BAD_SITE=1
else
  check_color_claims
fi

if [ "$COLOR_BAD_WORDS" -eq 0 ]; then
  ok "node colors" "$CODE_NODE_COLORS"
fi
if [ "$COLOR_BAD_SITE" -eq 0 ]; then
  ok "node color site" "logo.mbt:$CODE_COLOR_LINES"
fi

# --- the pointers reach the code they name -------------------------------------
#
# A row that cites a file and names a function of that file is pointing at
# that function. A citation that lands outside it points at something else,
# and the reader who follows it lands in the wrong place -- usually at a
# neighbour that looks close enough to be believed.
#
# A function's block runs from the line that defines it to the line before the
# next definition, because that is the range a reader thinks of as "the
# function". A row that names more than one function of the file is about the
# relationship between them, and the pointer may be to either, so such a row
# is left alone.
#
# The history fallback is the one name the tree says NOT to use, and it says
# so in a comment. A document that says the same has to point at that
# comment.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

# The definitions of the file being read: the lines that define a function,
# in file order, and the number of lines in the file.
DEF_LINES=()
DEF_NAMES=()
DEF_FILE=""
DEF_COUNT=0

code_definitions() {
  local file="$1" out line name
  if [ "$DEF_FILE" = "$file" ]; then return; fi
  DEF_FILE="$file"
  DEF_LINES=()
  DEF_NAMES=()
  DEF_COUNT=0
  out=$(awk '
    /^[ \t]*(pub(\([a-z]+\))?[ \t]+)?(async[ \t]+)?fn[ \t]+[A-Za-z_]/ {
      tmp = $0
      sub(/^[ \t]*(pub(\([a-z]+\))?[ \t]+)?(async[ \t]+)?fn[ \t]+/, "", tmp)
      split(tmp, parts, /[ \t(]/)
      printf "%d\t%s\n", NR, parts[1]
    }
    END { printf "#\t%d\n", NR }
  ' "$file" || true)
  while IFS=$'\t' read -r line name; do
    [ -n "$name" ] || continue
    if [ "$line" = "#" ]; then
      DEF_COUNT="$name"
      continue
    fi
    DEF_LINES+=("$line")
    DEF_NAMES+=("$name")
  done <<< "$out"
}

# The block a function occupies.
DEF_START=0
DEF_END=0
def_range() {
  local name="$1" i
  DEF_START=0
  DEF_END=0
  for i in "${!DEF_NAMES[@]}"; do
    if [ "${DEF_NAMES[$i]}" = "$name" ]; then
      DEF_START="${DEF_LINES[$i]}"
      if [ $((i + 1)) -lt "${#DEF_NAMES[@]}" ]; then
        DEF_END=$(( ${DEF_LINES[$((i + 1))]} - 1 ))
      else
        DEF_END="$DEF_COUNT"
      fi
      return
    fi
  done
}

# The source a claim cites: the file and the lines it cites.
CITE_RE='`([A-Za-z0-9_./-]+\.mbt):([0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*)`'
CITE_FILE=""
CITE_SPEC=""
CITE_TEXT=""
cite_source() {
  local claim="$1"
  CITE_FILE=""
  CITE_SPEC=""
  CITE_TEXT=""
  [[ "$claim" =~ $CITE_RE ]] || return
  CITE_FILE="${BASH_REMATCH[1]}"
  CITE_SPEC="${BASH_REMATCH[2]}"
  CITE_TEXT="${claim//"${BASH_REMATCH[0]}"/}"
}

# The words a claim is made of.
#
# A name that carries a dot is one name: "main.js" is a file, and the
# function "main" is not it.
CLAIM_TOKENS=""
TOKEN_RE='([A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)?(\.[A-Za-z_][A-Za-z0-9_]*)*)'
claim_tokens() {
  local text="$1" rest="$1"
  CLAIM_TOKENS=""
  while [[ "$rest" =~ $TOKEN_RE ]]; do
    if [ -z "$CLAIM_TOKENS" ]; then
      CLAIM_TOKENS="${BASH_REMATCH[1]}"
    else
      CLAIM_TOKENS="$CLAIM_TOKENS ${BASH_REMATCH[1]}"
    fi
    rest="${rest#*"${BASH_REMATCH[0]}"}"
  done
}

# The lines the tree mentions the history fallback on.
HISTORY_LINES=""
code_history_lines() {
  HISTORY_LINES=$(grep -nF 'history_fallback' backend/maked_app.mbt \
    | cut -d: -f1 | tr '\n' ' ' || true)
  trim "$HISTORY_LINES"; HISTORY_LINES="$TRIMMED"
}

POINTER_BAD=0
FALLBACK_BAD=0
POINTER_CHECKED=0

# One claim, checked against the tree.
pointer_claim_check() {
  local doc="$1" line="$2" claim="$3" fn count=0 named="" part a b covered target
  cite_source "$claim"
  [ -n "$CITE_FILE" ] || return
  [ -f "$CITE_FILE" ] || return
  POINTER_CHECKED=$((POINTER_CHECKED + 1))
  claim_tokens "$CITE_TEXT"
  code_definitions "$CITE_FILE"
  # the functions of that file the claim names
  for fn in "${DEF_NAMES[@]}"; do
    case " $CLAIM_TOKENS " in
      *" $fn "*)
        count=$((count + 1))
        named="$fn"
        ;;
    esac
  done
  # the claim that says the history fallback is not used points at that note
  case " $CLAIM_TOKENS " in
    *' history_fallback '*)
      code_history_lines
      covered=0
      for target in $HISTORY_LINES; do
        citation_covers "$CITE_SPEC" "$target"
        if [ "$CITATION_COVERS" -eq 1 ]; then
          covered=1
          break
        fi
      done
      if [ "$covered" -eq 0 ]; then
        fail "$(printf '%-22s %s line %s cites [%s:%s], but the tree says it on lines %s' \
          'fallback site' "$doc" "$line" "$CITE_FILE" "$CITE_SPEC" "$HISTORY_LINES")"
        FALLBACK_BAD=1
      fi
      ;;
  esac
  # a claim that names one function of the file has to point inside it
  [ "$count" -eq 1 ] || return
  def_range "$named"
  [ "$DEF_START" -gt 0 ] || return
  covered=0
  for part in ${CITE_SPEC//,/ }; do
    case "$part" in
      *-*) a="${part%-*}"; b="${part#*-}" ;;
      *) a="$part"; b="$part" ;;
    esac
    if [ "$a" -le "$DEF_END" ] && [ "$DEF_START" -le "$b" ]; then
      covered=1
      break
    fi
  done
  if [ "$covered" -eq 0 ]; then
    fail "$(printf '%-22s %s line %s cites [%s:%s], but %s is on lines %s-%s' \
      'code pointer' "$doc" "$line" "$CITE_FILE" "$CITE_SPEC" "$named" "$DEF_START" "$DEF_END")"
    POINTER_BAD=1
  fi
}

# Every claim the design documents make, checked against the code they cite.
check_pointer_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      pointer_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

code_history_lines
check_pointer_claims

if [ "$POINTER_BAD" -eq 0 ]; then
  ok "code pointer" "$POINTER_CHECKED pointers"
fi
if [ "$FALLBACK_BAD" -eq 0 ]; then
  ok "fallback site" "maked_app.mbt:$HISTORY_LINES"
fi

# --- the names the tree has ----------------------------------------------------
#
# A document that puts a name in backticks is telling the reader where to
# look: "the body is inserted with `Attrs::inner_html`" points into the code,
# and a reader who searches the tree for it has to find it. A name the tree
# does not have is a name nobody can follow, and it is usually a name that
# was renamed or removed and the document never heard.
#
# The names are the tree's own: every tracked file that is not a document. A
# document is not part of the vocabulary, because a name that only the
# documents use is exactly the name that is not in the code. The gates
# themselves are not part of it either: a name a gate mentions is not a name
# the tree has.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

# The names the tree has.
declare -A TREE_NAME
TREE_NAME_COUNT=0

# A name in the tree: a word, with an optional type qualifier.
NAME_RE='([A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)?)'
# The name a piece of backticked text starts with.
NAME_FIRST_RE='^([A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)?)'
# A piece of backticked text.
TICK_RE='`([^`]+)`'

code_tree_names() {
  local files out name file
  TREE_NAME_COUNT=0
  files=$(git ls-files 2>/dev/null \
    | grep -vE '^(architecture/|README\.md|AGENTS\.md|AGENT\.md)' \
    | grep -vE '\.(md|dot)$' \
    | grep -vE '^tools/check-docs\.(sh|ps1)$' || true)
  [ -n "$files" ] || return
  # A file that is gone is not a file the tree has: the names it held are not
  # names to look for. The list is filtered BEFORE the names are read, because
  # a reader that stops at the first file it cannot open loses every name that
  # came after it -- and the PowerShell twin, which skips the file it cannot
  # open, kept them.
  local -a present=()
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    [ -f "$file" ] || continue
    present+=("$file")
  done <<< "$files"
  [ "${#present[@]}" -gt 0 ] || return
  out=$(LC_ALL=C grep -hoE "$NAME_RE" "${present[@]}" | LC_ALL=C sort -u || true)
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    TREE_NAME["$name"]=1
  done <<< "$out"
  TREE_NAME_COUNT="${#TREE_NAME[@]}"
}

CODE_NAMES_BAD=0

# One claim, checked against the names the tree has.
code_name_claim_check() {
  local doc="$1" line="$2" claim="$3" rest tick name
  cite_source "$claim"
  [ -n "$CITE_FILE" ] || return
  rest="$CITE_TEXT"
  while [[ "$rest" =~ $TICK_RE ]]; do
    tick="${BASH_REMATCH[1]}"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    tick="${tick#"${tick%%[![:space:]]*}"}"
    [[ "$tick" =~ $NAME_FIRST_RE ]] || continue
    name="${BASH_REMATCH[1]}"
    if [ -z "${TREE_NAME["$name"]+yes}" ]; then
      fail "$(printf '%-22s %s line %s names [%s], and the tree has no such name' \
        'code names' "$doc" "$line" "$name")"
      CODE_NAMES_BAD=1
    fi
  done
}

# Every claim the design documents make, checked against the names.
check_name_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      code_name_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

code_tree_names
check_name_claims

if [ "$CODE_NAMES_BAD" -eq 0 ]; then
  ok "code names" "$TREE_NAME_COUNT names"
fi

# --- the defaults the variables fall back to ----------------------------------
#
# A variable the server reads has a default, and the default is the tree's:
# env_or("MAKED_PORT", "8080") pins the name and the value together. A
# document that says "MAKED_PORT (default 8080)" is stating that value, and a
# document that says 8081 is sending a reader to a port the server will not
# listen on.
#
# The default a claim states is the one that follows the variable: the text
# between a variable and the next variable is the text about that variable.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

# The defaults the tree pins: "MAKED_PORT=8080", and so on.
ENV_DEFAULTS=""
code_env_defaults() {
  local line rest name value
  ENV_DEFAULTS=""
  while IFS= read -r line; do
    case "$line" in
      *'env_or("'*) ;;
      *) continue ;;
    esac
    rest="${line#*env_or(\"}"
    name="${rest%%\"*}"
    rest="${rest#*\"}"
    case "$rest" in
      *', "'*) ;;
      *) continue ;;
    esac
    rest="${rest#*, \"}"
    value="${rest%%\"*}"
    ENV_DEFAULTS="$ENV_DEFAULTS $name=$value"
  done < cmd/server/main.mbt
}

# The default a claim states after a variable.
DOC_DEFAULT=""
DEFAULT_RE='default[[:space:]]+([^[:space:]),]+)'
doc_default_after() {
  local claim="$1" var="$2" rest
  DOC_DEFAULT=""
  rest="${claim#*"$var"}"
  # the text about this variable runs to the next one
  rest="${rest%%MAKED_*}"
  if [[ "$rest" =~ $DEFAULT_RE ]]; then
    DOC_DEFAULT="${BASH_REMATCH[1]}"
  fi
}

ENV_DEFAULT_BAD=0

# One claim, checked against the defaults the tree pins.
env_default_claim_check() {
  local doc="$1" line="$2" claim="$3" var tree pair
  doc_claim_vars "$claim"
  [ -n "$DOC_VARS" ] || return
  for var in $DOC_VARS; do
    doc_default_after "$claim" "$var"
    [ -n "$DOC_DEFAULT" ] || continue
    tree=""
    for pair in $ENV_DEFAULTS; do
      if [ "${pair%%=*}" = "$var" ]; then
        tree="${pair#*=}"
        break
      fi
    done
    [ -n "$tree" ] || continue
    if [ "$DOC_DEFAULT" != "$tree" ]; then
      fail "$(printf '%-22s %s line %s says %s falls back to [%s], the tree falls back to [%s]' \
        'env default' "$doc" "$line" "$var" "$DOC_DEFAULT" "$tree")"
      ENV_DEFAULT_BAD=1
    fi
  done
}

# Every claim the design documents make, checked against the defaults.
check_env_default_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      env_default_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

code_env_defaults
check_env_default_claims

if [ "$ENV_DEFAULT_BAD" -eq 0 ]; then
  trim "$ENV_DEFAULTS"
  ok "env default" "$TRIMMED"
fi

# --- the calls the tree makes ---------------------------------------------------
#
# A claim that names a call the tree makes -- "@fs.read_file" -- is pointing
# at that call, and a pointer that lands on another line points at something
# else. The call has to be on a line the citation reaches.
#
# A claim that says a package has no HTTP client code is making a promise
# about that package's network behaviour, and the tree has to keep it: the
# package's own source has to have no client call in it.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

# The packages the tree has.
CODE_PKGS=""
code_packages() {
  CODE_PKGS=$(git ls-files 2>/dev/null | grep -E '(^|/)moon\.pkg$' \
    | sed -E 's|/moon\.pkg$||' | grep -vE '^moon\.pkg$' | tr '\n' ' ' || true)
  trim "$CODE_PKGS"; CODE_PKGS="$TRIMMED"
}

# The lines the cited file makes a call on.
CALL_LINES=""
call_lines() {
  local file="$1" call="$2"
  CALL_LINES=$(grep -nF "$call" "$file" 2>/dev/null | cut -d: -f1 | tr '\n' ' ' || true)
  trim "$CALL_LINES"; CALL_LINES="$TRIMMED"
}

# The client calls a package makes, in the package's own source.
PKG_CALLS=""
package_client_calls() {
  local pkg="$1" file
  PKG_CALLS=""
  for file in "$pkg"/*.mbt; do
    [ -f "$file" ] || continue
    case "$file" in
      *_test.mbt) continue ;;
    esac
    if grep -qE '@http\.(get|post|put|delete|head|patch)\(' "$file"; then
      PKG_CALLS="$PKG_CALLS $file"
    fi
  done
  trim "$PKG_CALLS"; PKG_CALLS="$TRIMMED"
}

CALL_BAD=0
HTTP_BAD=0
CALL_CHECKED=0

# One claim, checked against the calls the tree makes.
call_claim_check() {
  local doc="$1" line="$2" claim="$3" rest tick call target covered
  cite_source "$claim"
  [ -n "$CITE_FILE" ] || return
  [ -f "$CITE_FILE" ] || return
  rest="$CITE_TEXT"
  while [[ "$rest" =~ $TICK_RE ]]; do
    tick="${BASH_REMATCH[1]}"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    case "$tick" in
      @*) ;;
      *) continue ;;
    esac
    call="${tick%%(*}"
    call="${call%% *}"
    CALL_CHECKED=$((CALL_CHECKED + 1))
    call_lines "$CITE_FILE" "$call"
    if [ -z "$CALL_LINES" ]; then
      fail "$(printf '%-22s %s line %s names [%s], and %s never says it' \
        'call site' "$doc" "$line" "$call" "$CITE_FILE")"
      CALL_BAD=1
      continue
    fi
    covered=0
    for target in $CALL_LINES; do
      citation_covers "$CITE_SPEC" "$target"
      if [ "$CITATION_COVERS" -eq 1 ]; then
        covered=1
        break
      fi
    done
    if [ "$covered" -eq 0 ]; then
      fail "$(printf '%-22s %s line %s cites [%s:%s], but [%s] is on lines %s' \
        'call site' "$doc" "$line" "$CITE_FILE" "$CITE_SPEC" "$call" "$CALL_LINES")"
      CALL_BAD=1
    fi
  done
}

# One claim, checked against the client calls the packages make.
http_claim_check() {
  local doc="$1" line="$2" claim="$3" lower rest word pkg
  lower="${claim,,}"
  case "$lower" in
    *'no http client'*) ;;
    *) return ;;
  esac
  rest="${lower#*no http client}"
  pkg=""
  for word in $rest; do
    word="${word%%[.,;)]*}"
    case " $CODE_PKGS " in
      *" $word "*)
        pkg="$word"
        break
        ;;
    esac
  done
  [ -n "$pkg" ] || return
  package_client_calls "$pkg"
  if [ -n "$PKG_CALLS" ]; then
    fail "$(printf '%-22s %s line %s says %s has no HTTP client code, but %s calls one' \
      'http client' "$doc" "$line" "$pkg" "$PKG_CALLS")"
    HTTP_BAD=1
  fi
}

# Every claim the design documents make, checked against the calls.
check_call_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      call_claim_check "$doc" "$line" "$claim"
      http_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

code_packages
check_call_claims

if [ "$CALL_BAD" -eq 0 ]; then
  ok "call site" "$CALL_CHECKED calls"
fi
if [ "$HTTP_BAD" -eq 0 ]; then
  ok "http client" "$CODE_PKGS"
fi

# --- the targets a package supports --------------------------------------------
#
# A claim that says a package is "<target>-only" is making a promise about the
# platforms that package runs on, and the package's own moon.pkg says which
# platforms those are. The two have to agree: a document that says the frontend
# is js-only while the tree says "js+native" is a document that costs a reader
# an afternoon.
#
# A claim that says a package is a "<target> executable" says the same thing
# about a package that has to be run, and the manifest has to say it is one.
#
# A claim that says what a package is built with has to name a target that
# package declares.
#
# A claim that cites a manifest has to cite the line the tree declares the
# targets on, and it has to be that package's own manifest.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

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

# Is a target one of the ones a package declares?
PKG_HAS_TARGET=0
pkg_has_target() {
  local want="$1" part
  PKG_HAS_TARGET=0
  for part in ${PKG_TARGET//+/ }; do
    if [ "$part" = "$want" ]; then
      PKG_HAS_TARGET=1
      return
    fi
  done
}

# The line a package declares its targets on.
PKG_TARGET_LINE=""
pkg_target_line() {
  local pkg="$1" file
  PKG_TARGET_LINE=""
  file="$pkg/moon.pkg"
  [ -f "$file" ] || return
  PKG_TARGET_LINE=$(grep -nE 'supported_targets[[:space:]]*=' "$file" 2>/dev/null | head -1 | cut -d: -f1)
}

# Is a package an executable? The manifest says so.
PKG_EXECUTABLE=0
pkg_is_executable() {
  local pkg="$1" file
  PKG_EXECUTABLE=0
  file="$pkg/moon.pkg"
  [ -f "$file" ] || return
  if grep -qE 'pkgtype\(kind:[[:space:]]*"executable"\)' "$file"; then
    PKG_EXECUTABLE=1
  fi
}

# The manifest a claim cites.
PKG_CITE_RE='`([A-Za-z0-9_./-]+/moon\.pkg):([0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*)`'
# The module manifest a claim cites.
MOD_CITE_RE='`moon\.mod:([0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*)`'

TARGET_BAD=0
TARGET_SITE_BAD=0
MODULE_BAD=0
TARGET_CHECKED=0
TARGET_SITE_CHECKED=0
MODULE_CHECKED=0

# The site of a target claim: the manifest it cites, and the line it cites.
target_site_check() {
  local doc="$1" line="$2" pkg="$3" cfile="$4" cspec="$5" target_line
  [ -n "$cfile" ] || return
  TARGET_SITE_CHECKED=$((TARGET_SITE_CHECKED + 1))
  if [ "$cfile" != "$pkg/moon.pkg" ]; then
    fail "$(printf '%-22s %s line %s is about %s, but cites %s' \
      'target site' "$doc" "$line" "$pkg" "$cfile")"
    TARGET_SITE_BAD=1
    return
  fi
  pkg_target_line "$pkg"
  target_line="$PKG_TARGET_LINE"
  if [ -z "$target_line" ]; then
    fail "$(printf '%-22s %s line %s cites %s, but the tree declares no targets there' \
      'target site' "$doc" "$line" "$cfile")"
    TARGET_SITE_BAD=1
    return
  fi
  citation_covers "$cspec" "$target_line"
  if [ "$CITATION_COVERS" -ne 1 ]; then
    fail "$(printf '%-22s %s line %s cites %s:%s, but the targets are declared on line %s' \
      'target site' "$doc" "$line" "$cfile" "$cspec" "$target_line")"
    TARGET_SITE_BAD=1
  fi
}

# One claim, checked against the targets the tree declares.
target_claim_check() {
  local doc="$1" line="$2" claim="$3" lower scan pkg t re token cfile cspec rest
  lower="${claim,,}"

  # The manifest the claim cites, if it cites exactly one.
  cfile=""
  cspec=""
  if [[ "$claim" =~ $PKG_CITE_RE ]]; then
    cfile="${BASH_REMATCH[1]}"
    cspec="${BASH_REMATCH[2]}"
    rest="${claim#*"${BASH_REMATCH[0]}"}"
    if [[ "$rest" =~ $PKG_CITE_RE ]]; then
      cfile=""
      cspec=""
    fi
  fi

  for pkg in $CODE_PKGS; do
    # "<pkg> is <target>-only": the package supports that target and nothing else.
    re="(^|[^A-Za-z0-9_/.-])${pkg} is ([A-Za-z_+-]+)-only"
    scan="$lower"
    while [[ "$scan" =~ $re ]]; do
      t="${BASH_REMATCH[2]}"
      scan="${scan#*"${BASH_REMATCH[0]}"}"
      pkg_target "$pkg"
      TARGET_CHECKED=$((TARGET_CHECKED + 1))
      if [ "$PKG_TARGET" != "$t" ]; then
        fail "$(printf '%-22s %s line %s says %s is %s-only, but the tree says %s' \
          'supported target' "$doc" "$line" "$pkg" "$t" "$PKG_TARGET")"
        TARGET_BAD=1
      fi
      target_site_check "$doc" "$line" "$pkg" "$cfile" "$cspec"
    done

    # "<pkg> is a <target> executable": the manifest has to say it is one.
    re="(^|[^A-Za-z0-9_/.-])${pkg} is ([A-Za-z_+-]+) executable"
    scan="$lower"
    while [[ "$scan" =~ $re ]]; do
      t="${BASH_REMATCH[2]}"
      scan="${scan#*"${BASH_REMATCH[0]}"}"
      pkg_target "$pkg"
      pkg_has_target "$t"
      TARGET_CHECKED=$((TARGET_CHECKED + 1))
      if [ "$PKG_HAS_TARGET" -ne 1 ]; then
        fail "$(printf '%-22s %s line %s says %s is a %s executable, but the tree says %s' \
          'supported target' "$doc" "$line" "$pkg" "$t" "$PKG_TARGET")"
        TARGET_BAD=1
      fi
      pkg_is_executable "$pkg"
      if [ "$PKG_EXECUTABLE" -ne 1 ]; then
        fail "$(printf '%-22s %s line %s says %s is an executable, but %s/moon.pkg does not say so' \
          'supported target' "$doc" "$line" "$pkg" "$pkg")"
        TARGET_BAD=1
      fi
      target_site_check "$doc" "$line" "$pkg" "$cfile" "$cspec"
    done
  done

  # "built with `--target <target>`": the target has to be one the package declares.
  scan="$lower"
  while [[ "$scan" =~ $TICK_RE ]]; do
    token="${BASH_REMATCH[1]}"
    scan="${scan#*"${BASH_REMATCH[0]}"}"
    case "$token" in
      '--target '*) t="${token#--target }" ;;
      *) continue ;;
    esac
    case "$t" in
      native|js|wasm|wasm-gc|all) ;;
      *) continue ;;
    esac
    [ -n "$cfile" ] || continue
    pkg="${cfile%/moon.pkg}"
    pkg_target "$pkg"
    pkg_has_target "$t"
    TARGET_CHECKED=$((TARGET_CHECKED + 1))
    if [ "$PKG_HAS_TARGET" -ne 1 ]; then
      fail "$(printf '%-22s %s line %s says %s is built with --target %s, but the tree says %s' \
        'supported target' "$doc" "$line" "$pkg" "$t" "$PKG_TARGET")"
      TARGET_BAD=1
    fi
    target_site_check "$doc" "$line" "$pkg" "$cfile" "$cspec"
  done
}

# The targets the module declares, and the line it declares them on.
#
# A line the tree does not have is 0, in this twin and in the PowerShell one.
MODULE_TARGETS=""
MODULE_TARGET_LINE=0
module_targets() {
  local file="moon.mod"
  MODULE_TARGETS=""
  MODULE_TARGET_LINE=0
  [ -f "$file" ] || return
  MODULE_TARGET_LINE=$(grep -nE 'supported_targets[[:space:]]*=' "$file" 2>/dev/null | head -1 | cut -d: -f1)
  [ -n "$MODULE_TARGET_LINE" ] || MODULE_TARGET_LINE=0
  MODULE_TARGETS=$(grep -oE 'supported_targets[[:space:]]*=[[:space:]]*"[^"]*"' "$file" 2>/dev/null \
    | head -1 | sed -E 's/.*"([^"]*)".*/\1/')
}

# Two target lists, compared as sets.
target_set_equal() {
  local a b
  a=$(printf '%s\n' ${1//+/ })
  b=$(printf '%s\n' ${2//+/ })
  not_in "$a" "$b"
  [ -z "$NOT_IN" ] || return 1
  not_in "$b" "$a"
  [ -z "$NOT_IN" ]
}

# One claim, checked against the targets the module declares.
module_claim_check() {
  local doc="$1" line="$2" claim="$3" scan token parts p ok modspec
  scan="$claim"
  while [[ "$scan" =~ $TICK_RE ]]; do
    token="${BASH_REMATCH[1]}"
    scan="${scan#*"${BASH_REMATCH[0]}"}"
    case "$token" in
      *+*) ;;
      *) continue ;;
    esac
    parts="${token//+/ }"
    ok=1
    for p in $parts; do
      case "$p" in
        native|js|wasm|wasm-gc|all) ;;
        *) ok=0 ;;
      esac
    done
    [ "$ok" -eq 1 ] || continue
    MODULE_CHECKED=$((MODULE_CHECKED + 1))
    if ! target_set_equal "$token" "$MODULE_TARGETS"; then
      fail "$(printf '%-22s %s line %s says the module targets %s, but the tree says %s' \
        'module targets' "$doc" "$line" "$token" "$MODULE_TARGETS")"
      MODULE_BAD=1
    fi
    if [[ "$claim" =~ $MOD_CITE_RE ]]; then
      modspec="${BASH_REMATCH[1]}"
      citation_covers "$modspec" "$MODULE_TARGET_LINE"
      if [ "$CITATION_COVERS" -ne 1 ]; then
        fail "$(printf '%-22s %s line %s cites moon.mod:%s, but the targets are declared on line %s' \
          'module targets' "$doc" "$line" "$modspec" "$MODULE_TARGET_LINE")"
        MODULE_BAD=1
      fi
    fi
  done
}

# Every claim the design documents make, checked against the targets.
check_target_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      target_claim_check "$doc" "$line" "$claim"
      module_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

code_pkg_targets
module_targets
check_target_claims

if [ "$TARGET_BAD" -eq 0 ]; then
  ok "supported target" "$TARGET_CHECKED claims"
fi
if [ "$TARGET_SITE_BAD" -eq 0 ]; then
  ok "target site" "$TARGET_SITE_CHECKED citations"
fi
if [ "$MODULE_BAD" -eq 0 ]; then
  ok "module targets" "$MODULE_CHECKED claims"
fi

# --- the calls that leave the machine -----------------------------------------
#
# A claim that says the tree makes no external network call is making a
# promise about the network: nothing goes out to a host the reader does not
# know about. The tree has to keep that promise, or the document has to stop
# making it. A claim that says how many external calls there are has to say
# the number the tree has.
#
# A call leaves the machine when the URL it fetches can be an address that is
# not the machine's own. A call that fetches a path -- "/api/pages" -- talks to
# a server that is already running. A call that fetches a name -- "url" -- can
# be anything, so the package that makes it decides: a package that names an
# address that is not the machine's own (not a loopback address, and not an XML
# namespace, which is a name and not an address) can reach out.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

# The addresses a package names.
PKG_HOSTS=""
pkg_hosts() {
  local pkg="$1" file url ns hosts=""
  for file in "$pkg"/*.mbt; do
    [ -f "$file" ] || continue
    case "$file" in
      *_test.mbt) continue ;;
    esac
    ns=$(grep -oE 'xmlns="https?://[^"]*"' "$file" 2>/dev/null \
      | sed -E 's/^xmlns="//; s/"$//' || true)
    for url in $(grep -oE '"https?://[^"]*"' "$file" 2>/dev/null | tr -d '"' || true); do
      not_in "$url" "$ns"
      [ -n "$NOT_IN" ] || continue
      case "$url" in
        *127.0.0.1*|*localhost*) continue ;;
      esac
      hosts="$hosts $url"
    done
  done
  trim "$hosts"; PKG_HOSTS="$TRIMMED"
}

# Does this call leave the machine?
CALL_LEAVES=0
call_leaves() {
  local line="$1" token
  token="${line#*@http.}"
  token="${token#*\(}"
  token="${token%% *}"
  token="${token%%[),]*}"
  case "$token" in
    '"/'*) CALL_LEAVES=0; return ;;
    '"http://'*|'"https://'*) CALL_LEAVES=1; return ;;
    '"'*) CALL_LEAVES=0; return ;;
  esac
  if [ -n "$PKG_HOSTS" ]; then CALL_LEAVES=1; else CALL_LEAVES=0; fi
}

# The calls that leave the machine, and the packages that make them.
OUTBOUND_PKGS=""
OUTBOUND_CALLS=0
outbound_calls() {
  local pkg file line
  OUTBOUND_PKGS=""
  OUTBOUND_CALLS=0
  for pkg in $CODE_PKGS; do
    pkg_hosts "$pkg"
    for file in "$pkg"/*.mbt; do
      [ -f "$file" ] || continue
      case "$file" in
        *_test.mbt) continue ;;
      esac
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        call_leaves "$line"
        [ "$CALL_LEAVES" -eq 1 ] || continue
        OUTBOUND_CALLS=$((OUTBOUND_CALLS + 1))
        case " $OUTBOUND_PKGS " in
          *" $pkg "*) ;;
          *) OUTBOUND_PKGS="$OUTBOUND_PKGS $pkg" ;;
        esac
      done <<< "$(grep -E '@http\.(get|post|put|delete|head|patch)\(' "$file" 2>/dev/null || true)"
    done
  done
  trim "$OUTBOUND_PKGS"; OUTBOUND_PKGS="$TRIMMED"
}

# A claim that denies an external call, and a claim that makes one.
NO_EXTERNAL_RE='(no (external|outbound|remote)[a-z ]*(call|connection|request)|not call any external)'
HAS_EXTERNAL_RE='(external|outbound)[a-z ]*(call|connection|request)'
# The number a claim states next to the call phrase.
COUNT_EXTERNAL_RE='(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve) (outbound|external)[a-z ]*(call|connection|request)'

EXTERNAL_BAD=0
EXTERNAL_CHECKED=0

# One claim, checked against the calls the tree makes.
external_claim_check() {
  local doc="$1" line="$2" claim="$3" lower word stated
  lower="${claim,,}"
  if [[ "$lower" =~ $NO_EXTERNAL_RE ]]; then
    EXTERNAL_CHECKED=$((EXTERNAL_CHECKED + 1))
    if [ -n "$OUTBOUND_PKGS" ]; then
      fail "$(printf '%-22s %s line %s says there are no external network calls, but %s reaches out' \
        'external call' "$doc" "$line" "$OUTBOUND_PKGS")"
      EXTERNAL_BAD=1
    fi
    return
  fi
  if [[ "$lower" =~ $HAS_EXTERNAL_RE ]]; then
    EXTERNAL_CHECKED=$((EXTERNAL_CHECKED + 1))
    if [ -z "$OUTBOUND_PKGS" ]; then
      fail "$(printf '%-22s %s line %s says there is an external network call, but no package reaches out' \
        'external call' "$doc" "$line")"
      EXTERNAL_BAD=1
      return
    fi
    if [[ "$lower" =~ $COUNT_EXTERNAL_RE ]]; then
      word="${BASH_REMATCH[1]}"
      stated="$(word_number "$word")"
      if [ "$stated" != "$OUTBOUND_CALLS" ]; then
        fail "$(printf '%-22s %s line %s says %s outbound calls, but the tree has %s' \
          'external call' "$doc" "$line" "$word" "$OUTBOUND_CALLS")"
        EXTERNAL_BAD=1
      fi
    fi
  fi
}

# Every claim the design documents make, checked against the outbound calls.
check_external_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      external_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

outbound_calls
check_external_claims

if [ "$EXTERNAL_BAD" -eq 0 ]; then
  ok "external call" "$OUTBOUND_CALLS calls in $OUTBOUND_PKGS"
fi

# --- the protocols the deployment table gives its boundaries --------------------
#
# The deployment document has a table of the boundaries the server has, and the
# last column of each row says how the boundary is crossed: HTTP for the
# browser, an in-process FFI call for the database, an in-process file read
# for the filesystem, HTTP for the corpus feed. Those are the tree's
# mechanisms, and nothing checked them: the table could say the corpus feed
# is FTP, or the file reads go over HTTP, and every document would go on
# saying what it always said.
#
# The tree's mechanisms come from the tree:
#
#   - the database is the SQL library the storage layer opens -- a @sqlite3
#     connection -- and a file of it is reached by a native call.
#   - the filesystem is read with @fs, in the server's own process.
#   - the network is HTTP: the server listens on a socket and prints http://
#     URLs, and the one outbound call the tree makes is an @http.get.
#
# A row's boundary says what is on the other side of it, and the mechanism
# the tree uses for that thing is the one the protocol cell has to name. A
# cell that names a mechanism the tree does not use for that boundary is
# wrong, and a cell that names no mechanism at all does not say how the
# boundary is crossed.
#
# The cell may also say HOW the crossing happens, and that is a claim about
# the process as much as about the mechanism: the database and the
# filesystem are reached inside the server's own process -- a native call and
# a file read -- while the network is not. So a cell that says the crossing
# is in process may only sit on a boundary the tree reaches in process.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

DEPLOY_PROTO_BAD=0
DEPLOY_PROTO_CHECKED=0

# The mechanisms the tree uses, by the thing they reach.
#
# The SQL library is the one the storage layer opens. A document may name it
# with or without the version digits -- the tree opens a sqlite3, and the
# document says SQLite -- so both names are mechanisms.
#
# The filesystem is read with @fs, so the package is a mechanism, and so are
# the words the names of those reads are made of: the tree calls read_file, so
# "file" is one of them.
#
# The network is what the server speaks.
code_deploy_sql_mechanisms() {
  local lib stripped
  lib="$(code_sql_library)"
  [ -n "$lib" ] || return
  echo "$lib"
  stripped="${lib%%[0-9]*}"
  [ "$stripped" = "$lib" ] || echo "$stripped"
}

code_deploy_file_mechanisms() {
  local pkg file name part low out="" used=0
  for pkg in $CODE_PKGS; do
    for file in "$pkg"/*.mbt; do
      [ -f "$file" ] || continue
      case "$file" in
        *_test.mbt) continue ;;
      esac
      while IFS= read -r name; do
        [ -n "$name" ] || continue
        used=1
        name="${name#@fs.}"
        for part in $(printf '%s' "$name" | tr -c 'A-Za-z0-9' ' '); do
          low="${part,,}"
          [ -n "$low" ] || continue
          case " $MECHANISM_WORDS " in
            *" $low "*) ;;
            *) continue ;;
          esac
          case " $out " in
            *" $low "*) ;;
            *) out="$out $low" ;;
          esac
        done
      done <<< "$(grep -oE '@fs\.[a-zA-Z_]+' "$file" 2>/dev/null || true)"
    done
  done
  [ "$used" -eq 1 ] || return
  trim "$out"; out="$TRIMMED"
  case " $out " in
    *" fs "*) ;;
    *) out="fs $out" ;;
  esac
  trim "$out"; out="$TRIMMED"
  echo "$out"
}

# The mechanisms a protocol cell names, in the order it names them.
deploy_protocol_mechanisms() {
  local protocol="$1" word part low
  DEPLOY_PROTO_MECHANISMS=""
  for word in $protocol; do
    for part in $(printf '%s' "$word" | tr -c 'A-Za-z0-9' ' '); do
      low="${part,,}"
      [ -n "$low" ] || continue
      case " $MECHANISM_WORDS " in
        *" $low "*) ;;
        *) continue ;;
      esac
      case " $DEPLOY_PROTO_MECHANISMS " in
        *" $low "*) continue ;;
      esac
      DEPLOY_PROTO_MECHANISMS="$DEPLOY_PROTO_MECHANISMS $low"
    done
  done
}

# The boundaries the deployment document states, checked against the tree.
check_deploy_protocols() {
  local line n=0 subject row protocol named allowed kind low ok inproc word
  local sql_words file_words
  local in_table=0
  sql_words="$(code_deploy_sql_mechanisms | tr '\n' ' ')"
  trim "$sql_words"; sql_words="$TRIMMED"
  file_words="$(code_deploy_file_mechanisms | tr '\n' ' ')"
  trim "$file_words"; file_words="$TRIMMED"
  while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in
      "| Boundary |"*) in_table=1; continue ;;
      "|---"*) continue ;;
    esac
    [ "$in_table" -eq 1 ] || continue
    case "$line" in
      "| "*) ;;
      *) in_table=0; continue ;;
    esac
    # the boundary is the first cell, the protocol is the last one
    row="$line"
    trim "$row"; row="$TRIMMED"
    case "$row" in
      *"|") row="${row%|}" ;;
    esac
    subject="${row#*|}"
    subject="${subject%%|*}"
    trim "$subject"; subject="$TRIMMED"
    protocol="${row##*|}"
    trim "$protocol"; protocol="$TRIMMED"
    DEPLOY_PROTO_CHECKED=$((DEPLOY_PROTO_CHECKED + 1))
    # the thing on the other side of the boundary, and the mechanism the tree
    # uses to reach it
    kind='net'
    low="${subject,,}"
    for word in $sql_words; do
      [ -n "$word" ] || continue
      if [[ "$low" == *"${word}"* ]]; then kind='sql'; break; fi
    done
    if [ "$kind" = 'net' ]; then
      for word in $file_words; do
        [ -n "$word" ] || continue
        if [[ "$low" == *"${word}"* ]]; then kind='file'; break; fi
      done
    fi
    case "$kind" in
      sql) allowed="$(code_deploy_sql_mechanisms | tr '\n' ' ')" ;;
      file) allowed="$(code_deploy_file_mechanisms | tr '\n' ' ')" ;;
      *) allowed="$(code_server_transports | tr '\n' ' ')" ;;
    esac
    trim "$allowed"; allowed="$TRIMMED"
    deploy_protocol_mechanisms "$protocol"
    named="$DEPLOY_PROTO_MECHANISMS"
    trim "$named"; named="$TRIMMED"
    ok=1
    for word in $named; do
      case " $allowed " in
        *" $word "*) ;;
        *) ok=0 ;;
      esac
    done
    if [ "$ok" -eq 1 ] && [ -z "$named" ]; then
      ok=0
    fi
    if [ "$ok" -eq 0 ]; then
      fail "$(printf '%-22s %s line %s says the boundary [%s] is crossed by [%s], and the tree crosses it by [%s]' \
        'deploy protocols' "$DEPLOY_MD" "$n" "$subject" "$named" "$allowed")"
      DEPLOY_PROTO_BAD=1
    fi
    # a cell that says the boundary is crossed in process may only be on a
    # boundary the tree reaches inside its own process
    inproc=0
    case "${protocol,,}" in
      *in-process*|*"in process"*) inproc=1 ;;
    esac
    if [ "$inproc" -eq 1 ] && [ "$kind" = 'net' ]; then
      fail "$(printf '%-22s %s line %s says the boundary [%s] is crossed in process, but the tree reaches it over the network' \
        'deploy protocols' "$DEPLOY_MD" "$n" "$subject")"
      DEPLOY_PROTO_BAD=1
    fi
  done < "$DEPLOY_MD"
}

check_deploy_protocols

if [ "$DEPLOY_PROTO_BAD" -eq 0 ]; then
  ok "deploy protocols" "$DEPLOY_PROTO_CHECKED boundaries"
fi

# --- the formats the boundaries carry -----------------------------------------
#
# The network table says what crosses each boundary. For the boundary the
# browser is on it says which formats cross: HTML, JS, CSS and JSON. Nothing
# read the tree to see whether that was true: the table could have said YAML,
# and no gate would have said a word.
#
# The tree's formats are the kinds of the files the site ships and the content
# types the backend answers with. A document does not have to name every format
# the tree serves -- a site may add an asset -- but every format it names has
# to be one the tree serves.
#
# A cell lists formats when what is in its brackets is a list of bare words. The
# other rows of the table are not format lists: the database row names the
# operations of a prepared statement and the filesystem row names files. The
# corpus row is skipped as well, because what crosses it is the feed's own
# format and not the tree's.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

DEPLOY_FORMAT_BAD=0
DEPLOY_FORMAT_CHECKED=0
DEPLOY_FORMAT_FORMATS=""
DEPLOY_FORMAT_LIST=""
DEPLOY_FORMAT_ROWS=""

# The content types the backend answers with.
code_content_types() {
  local file kind
  for file in backend/*.mbt; do
    [ -f "$file" ] || continue
    case "$file" in *_test.mbt) continue ;; esac
    for kind in $(grep -ohE '"(application|text)/[a-z]+' "$file" 2>/dev/null \
        | tr -d '"' | sed -E 's|.*/||' || true); do
      printf '%s\n' "$kind"
    done
  done | LC_ALL=C sort -u
}

# The formats the tree serves.
#
# The set is built here and not with sorted_set: that helper is defined later
# in this file, and a gate that calls a helper above its definition fails on
# the shell that reads the script top to bottom.
tree_served_formats() {
  local out="" kind
  for kind in $BUNDLE_KINDS $(code_content_types); do
    out="$out $kind"
  done
  printf '%s\n' $out | LC_ALL=C sort -u | tr '\n' ' ' | sed -e 's/ *$//'
}

# The word the tree calls its corpus by: the corpus sources are the tree's own
# reading of a feed.
code_corpus_word() {
  local file base
  for file in backend/corpus_sources.mbt backend/corpus.mbt; do
    [ -f "$file" ] || continue
    base="${file##*/}"
    base="${base%%.*}"
    base="${base%%_*}"
    printf '%s\n' "$base"
    return
  done
}

# The formats a crossing cell lists.
#
# The list is the text in the brackets, cut on the commas. It is a list of
# formats when every piece of it is a bare word: a piece with a space or a dot
# in it is a sentence or a file name, and not a format.
deploy_crossing_formats() {
  local cell="$1" body token
  DEPLOY_FORMAT_LIST=""
  case "$cell" in
    *'('*')'*) ;;
    *) return ;;
  esac
  body="${cell#*\(}"
  body="${body%%\)*}"
  local -a parts=()
  IFS=',' read -ra parts <<< "$body"
  for token in "${parts[@]}"; do
    trim "$token"; token="$TRIMMED"
    if [ -z "$token" ]; then DEPLOY_FORMAT_LIST=""; return; fi
    case "$token" in
      *[!A-Za-z0-9+-]*) DEPLOY_FORMAT_LIST=""; return ;;
    esac
    case " $DEPLOY_FORMAT_LIST " in
      *" $token "*) ;;
      *) DEPLOY_FORMAT_LIST="$DEPLOY_FORMAT_LIST $token" ;;
    esac
  done
  trim "$DEPLOY_FORMAT_LIST"; DEPLOY_FORMAT_LIST="$TRIMMED"
}

# The rows of the network table.
DEPLOY_FORMAT_ROWS=""
deploy_format_rows() {
  local file="$1" line in_table=0 n=0
  DEPLOY_FORMAT_ROWS=""
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    case "$line" in
      '|---'*) continue ;;
      '| '*) ;;
      *) in_table=0; continue ;;
    esac
    row_cells "$line"
    if [ "$in_table" -eq 0 ]; then
      if [ "$ROW_C1" = "Boundary" ] && [ "$ROW_C2" = "What crosses it" ]; then
        in_table=1
      fi
      continue
    fi
    case "$ROW_C1" in
      ''|'---'*) continue ;;
    esac
    DEPLOY_FORMAT_ROWS="$DEPLOY_FORMAT_ROWS$n"$'\t'"$ROW_C1"$'\t'"$ROW_C2"$'\n'
  done < "$file"
}

# One row, checked against the formats the tree serves.
deploy_format_row_check() {
  local doc="$1" line="$2" subject="$3" crossing="$4" corpus word
  # what crosses the corpus boundary is the feed's own format
  corpus="$(code_corpus_word)"
  if [ -n "$corpus" ]; then
    case "${subject,,}" in
      *"$corpus"*) return ;;
    esac
  fi
  deploy_crossing_formats "$crossing"
  [ -n "$DEPLOY_FORMAT_LIST" ] || return
  DEPLOY_FORMAT_CHECKED=$((DEPLOY_FORMAT_CHECKED + 1))
  for word in $DEPLOY_FORMAT_LIST; do
    case " $DEPLOY_FORMAT_FORMATS " in
      *" ${word,,} "*) ;;
      *)
        fail "$(printf '%-22s %s line %s states [%s], and the tree serves no such format' \
          'deploy format' "$doc" "$line" "$word")"
        DEPLOY_FORMAT_BAD=1
        ;;
    esac
  done
}

DEPLOY_FORMAT_FORMATS=$(tree_served_formats)
DEPLOY_SQL_WORDS=$(code_deploy_sql_mechanisms | tr '\n' ' ')
trim "$DEPLOY_SQL_WORDS"; DEPLOY_SQL_WORDS="$TRIMMED"
DEPLOY_FILE_WORDS=$(code_deploy_file_mechanisms | tr '\n' ' ')
trim "$DEPLOY_FILE_WORDS"; DEPLOY_FILE_WORDS="$TRIMMED"

deploy_format_rows "$DEPLOY_MD"
while IFS=$'\t' read -r line subject crossing; do
  [ -n "$subject" ] || continue
  # only the boundaries the tree reaches over the network carry the tree's
  # formats; the database and the filesystem are reached in process
  kind='net'
  low="${subject,,}"
  for word in $DEPLOY_SQL_WORDS; do
    [ -n "$word" ] || continue
    if [[ "$low" == *"${word}"* ]]; then kind='sql'; break; fi
  done
  if [ "$kind" = 'net' ]; then
    for word in $DEPLOY_FILE_WORDS; do
      [ -n "$word" ] || continue
      if [[ "$low" == *"${word}"* ]]; then kind='file'; break; fi
    done
  fi
  [ "$kind" = 'net' ] || continue
  deploy_format_row_check "$DEPLOY_MD" "$line" "$subject" "$crossing"
done <<< "$DEPLOY_FORMAT_ROWS"

if [ "$DEPLOY_FORMAT_CHECKED" -eq 0 ]; then
  fail "$(printf '%-22s no document says which formats the boundaries carry' \
    'deploy format')"
  DEPLOY_FORMAT_BAD=1
fi

if [ "$DEPLOY_FORMAT_BAD" -eq 0 ]; then
  ok "deploy format" "$DEPLOY_FORMAT_CHECKED crossings"
fi

# --- the port the deployment document states ------------------------------------
#
# The deployment document says what port the server listens on, and it says it
# in more than one place: the topology diagram, the components table and the
# run notes. The tree's port is the default of MAKED_PORT, and the document
# has to agree with it in every place it speaks -- a document that says 8080
# in the table and 9090 in the diagram sends the reader to a port that is
# neither.
#
# A port is a number of four digits or more. A number that is a line of a file
# is not a port, so the citations are taken out before the numbers are read.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

DEPLOY_PORT_BAD=0
DEPLOY_PORT_PLACES=0
DEPLOY_PORT_WRONG=""

# The port the tree listens on: the default of MAKED_PORT.
TREE_PORT=""
tree_port() {
  local line
  TREE_PORT=""
  while IFS= read -r line; do
    case "$line" in
      MAKED_PORT\ *) TREE_PORT="${line#MAKED_PORT }"; return ;;
    esac
  done <<< "$CODE_SETTINGS"
}

# The ports the deployment document states.
DOC_PORTS=""
doc_ports() {
  DOC_PORTS=""
  sed -E 's/[A-Za-z0-9_.-]+\.[A-Za-z0-9]+:[0-9]+//g' "$DEPLOY_MD" \
    | grep -oE '[0-9]{4,}' || true
}

tree_port
if [ -n "$TREE_PORT" ]; then
  DOC_PORTS="$(doc_ports)"
  while IFS= read -r port; do
    [ -n "$port" ] || continue
    DEPLOY_PORT_PLACES=$((DEPLOY_PORT_PLACES + 1))
    if [ "$port" != "$TREE_PORT" ]; then
      case " $DEPLOY_PORT_WRONG " in
        *" $port "*) ;;
        *) DEPLOY_PORT_WRONG="$DEPLOY_PORT_WRONG $port" ;;
      esac
    fi
  done <<< "$DOC_PORTS"
  for wrong in $DEPLOY_PORT_WRONG; do
    fail "$(printf '%-22s %s states the port %s, and the tree listens on %s' \
      'deploy port' "$DEPLOY_MD" "$wrong" "$TREE_PORT")"
    DEPLOY_PORT_BAD=1
  done
fi

if [ "$DEPLOY_PORT_BAD" -eq 0 ]; then
  ok "deploy port" "$DEPLOY_PORT_PLACES places"
fi

# --- the SPA fallback the deployment document describes -----------------------
#
# The deployment diagram says which paths the SPA fallback answers, and the
# static assets table says which of the site's files is the shell it answers
# with. Neither was read against the tree: the diagram said the fallback
# answers "/*.html", and the tree refuses every path whose last segment names
# a file -- a missing stylesheet or script has to 404, not come back as HTML
# that the browser will try to execute.
#
# The tree says both things.
#
# The rule about the paths: the fallback answers a request whose last path
# segment has NO dot. The rule is read out of the tree -- the predicate that
# decides has to refuse a segment that contains a dot -- so a tree that stopped
# refusing them would make the document right again.
#
# The file: the fallback reads ONE file out of the dist directory it is given,
# and that file is the shell. The document has to call the same file the shell.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

DEPLOY_SPA_BAD=0
DEPLOY_SPA_CHECKED=0
DEPLOY_SPA_SHELL=""
DEPLOY_SPA_REFUSES=0
DEPLOY_SPA_PATTERN=""
DEPLOY_SPA_NAMED=0

# The file the fallback reads: the one file it builds out of the dist
# directory it is given.
code_spa_shell() {
  local name
  DEPLOY_SPA_SHELL=""
  tree_dist_dir
  [ -n "$ASSET_DIST" ] || return
  name=$(grep -oE '=[[:blank:]]*dist[[:blank:]]*\+[[:blank:]]*"/[^"]+"' backend/maked_app.mbt 2>/dev/null \
    | head -1 | grep -oE '"/[^"]+"' | tr -d '"' || true)
  [ -n "$name" ] || return
  DEPLOY_SPA_SHELL="$ASSET_DIST$name"
}

# Does the tree refuse a path whose last segment names a file?
#
# The predicate that decides is the one that has to refuse it, and it refuses
# it by negating the check for a dot in the last segment.
code_spa_refuses_dotted() {
  DEPLOY_SPA_REFUSES=0
  if grep -qE "!.*contains_char\([[:blank:]]*'\.'[[:blank:]]*\)" backend/maked_app.mbt 2>/dev/null; then
    DEPLOY_SPA_REFUSES=1
  fi
}

# The path pattern the diagram gives the SPA fallback.
#
# The diagram is a box drawing: the name of a middleware and the pattern it
# answers sit in the same column, on neighbouring rows. The cells of the row
# that names the fallback are cut out first, and the pattern is the cell of
# that same number in the next row -- the box characters line the two rows up
# column by column.
#
# The box character is written as its bytes, so that this script stays ASCII.
BOX_CHAR=$(printf '\xe2\x94\x82')
BOX_CELLS=()

# The cells of a box-drawn row: the pieces between the box characters.
row_box_cells() {
  local line="$1" rest="$1" i=0 head
  BOX_CELLS=()
  while :; do
    case "$rest" in
      *"$BOX_CHAR"*) ;;
      *) break ;;
    esac
    head="${rest%%"$BOX_CHAR"*}"
    BOX_CELLS[$i]="$head"
    i=$((i + 1))
    rest="${rest#*"$BOX_CHAR"}"
  done
  BOX_CELLS[$i]="$rest"
}

deploy_spa_pattern() {
  DEPLOY_SPA_PATTERN=""
  local line label_line="" label_len=0 found=0 i idx=-1
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$found" -eq 1 ]; then
      if [ "${#line}" -eq "$label_len" ]; then
        row_box_cells "$line"
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#BOX_CELLS[@]}" ]; then
          trim "${BOX_CELLS[$idx]}"; DEPLOY_SPA_PATTERN="$TRIMMED"
        fi
      fi
      return
    fi
    case "$line" in
      *fallback*"$BOX_CHAR"*) ;;
      *) continue ;;
    esac
    label_line="$line"
    label_len=${#label_line}
    row_box_cells "$label_line"
    i=0
    while [ "$i" -lt "${#BOX_CELLS[@]}" ]; do
      case "${BOX_CELLS[$i]}" in
        *fallback*) idx=$i; break ;;
      esac
      i=$((i + 1))
    done
    found=1
  done < "$DEPLOY_MD"
}

# The pattern the document gives, checked against the rule the tree has.
deploy_spa_pattern_check() {
  local pattern="$1" last
  [ -n "$pattern" ] || return
  DEPLOY_SPA_CHECKED=$((DEPLOY_SPA_CHECKED + 1))
  [ "$DEPLOY_SPA_REFUSES" -eq 1 ] || return
  last="${pattern##*/}"
  case "$last" in
    *.*)
      fail "$(printf '%-22s %s says the SPA fallback answers [%s], and the tree refuses every path whose last segment names a file' \
        'deploy spa' "$DEPLOY_MD" "$pattern")"
      DEPLOY_SPA_BAD=1
      ;;
  esac
}

# The file the document calls the shell, checked against the file the tree
# reads.
deploy_spa_shell_check() {
  local doc="$1" line="$2" file="$3" purpose="$4" low
  low="${purpose,,}"
  case "$low" in
    *shell*) ;;
    *) return ;;
  esac
  DEPLOY_SPA_CHECKED=$((DEPLOY_SPA_CHECKED + 1))
  DEPLOY_SPA_NAMED=1
  if [ "$file" != "$DEPLOY_SPA_SHELL" ]; then
    fail "$(printf '%-22s %s line %s calls [%s] the shell, and the tree reads the shell from [%s]' \
      'deploy spa' "$doc" "$line" "$file" "$DEPLOY_SPA_SHELL")"
    DEPLOY_SPA_BAD=1
  fi
}

code_spa_shell
code_spa_refuses_dotted
deploy_spa_pattern
deploy_spa_pattern_check "$DEPLOY_SPA_PATTERN"

DEPLOY_SPA_NAMED=0
for doc in "${ARCH_DOCS[@]}" "$AGENTS_DOC"; do
  not_in "$doc" "$MARKED_DOCS"
  [ -n "$NOT_IN" ] || continue
  asset_rows "$doc"
  while IFS=$'\t' read -r line file cell purpose; do
    [ -n "$file" ] || continue
    deploy_spa_shell_check "$doc" "$line" "$file" "$purpose"
  done <<< "$ASSET_ROWS"
done

# the tree reads the shell from one file, and a document has to say which
if [ "$DEPLOY_SPA_NAMED" -eq 0 ] && [ -n "$DEPLOY_SPA_SHELL" ]; then
  fail "$(printf '%-22s the tree reads the shell from [%s], and no document says so' \
    'deploy spa' "$DEPLOY_SPA_SHELL")"
  DEPLOY_SPA_BAD=1
fi

if [ "$DEPLOY_SPA_CHECKED" -eq 0 ]; then
  fail "$(printf '%-22s no document says what the SPA fallback answers' \
    'deploy spa')"
  DEPLOY_SPA_BAD=1
fi

if [ "$DEPLOY_SPA_BAD" -eq 0 ]; then
  ok "deploy spa" "$DEPLOY_SPA_CHECKED claims"
fi

# --- the CORS the tree does not have ------------------------------------------
#
# A claim that says the tree has no CORS is making a promise to the browser:
# the page and the API are the same origin, so the browser is never asked for
# cross-origin permission. The tree has to keep that promise.
#
# CORS is two things in the tree: a header, and a middleware. A header that
# allows an origin is an Access-Control header, and a middleware is an import
# of a package whose path names CORS. Neither may appear while a document
# says there is none.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

# The places the tree would have to change to grow a CORS.
CORS_PLACES=""
cors_places() {
  local file places=""
  for file in $(git ls-files '*.mbt' 2>/dev/null); do
    case "$file" in
      *_test.mbt) continue ;;
    esac
    if grep -qiF 'access-control' "$file"; then
      places="$places $file"
    fi
  done
  for file in $(git ls-files '*moon.pkg' 2>/dev/null); do
    if grep -qiE '"[^"]*cors[^"]*"' "$file"; then
      places="$places $file"
    fi
  done
  trim "$places"; CORS_PLACES="$TRIMMED"
}

# A claim that denies CORS, and a claim that makes one.
NO_CORS_RE='no cors([^a-z]|$)'
HAS_CORS_RE='([^a-z])cors([^a-z]|$)'

CORS_BAD=0
CORS_CHECKED=0

# One claim, checked against the CORS the tree has.
cors_claim_check() {
  local doc="$1" line="$2" claim="$3" lower
  lower="${claim,,}"
  if [[ ! "$lower" =~ $HAS_CORS_RE ]]; then
    return
  fi
  CORS_CHECKED=$((CORS_CHECKED + 1))
  if [[ "$lower" =~ $NO_CORS_RE ]]; then
    if [ -n "$CORS_PLACES" ]; then
      fail "$(printf '%-22s %s line %s says there is no CORS, but %s has one' \
        'cors' "$doc" "$line" "$CORS_PLACES")"
      CORS_BAD=1
    fi
    return
  fi
  if [ -z "$CORS_PLACES" ]; then
    fail "$(printf '%-22s %s line %s says there is CORS, but the tree has none' \
      'cors' "$doc" "$line")"
    CORS_BAD=1
  fi
}

# Every claim the design documents make, checked against the CORS.
check_cors_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      cors_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

cors_places
check_cors_claims

if [ "$CORS_BAD" -eq 0 ]; then
  ok "cors" "$CORS_CHECKED claims"
fi

# --- the metrics the tree computes --------------------------------------------
#
# A claim that says the tree has no metrics is making a claim about the tree:
# the runs are not measured. The tree does measure them -- the four measures of
# a run live in `backend/metrics.mbt` and ride in the session payload -- so a
# document that says there are none is wrong about a thing a reader can see
# in the API.
#
# A claim that says the tree has metrics has to be true too.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

# The metrics the tree has: a tracked source file that names them.
METRIC_FILES=""
metric_files() {
  local file files=""
  for file in $(git ls-files '*.mbt' 2>/dev/null | grep -iE 'metric' || true); do
    case "$file" in
      *_test.mbt) continue ;;
    esac
    files="$files $file"
  done
  trim "$files"; METRIC_FILES="$TRIMMED"
}

# A claim that denies metrics, and a claim that makes them.
NO_METRIC_RE='no metrics?([^a-z]|$)'
HAS_METRIC_RE='([^a-z])metrics?([^a-z]|$)'

METRIC_BAD=0
METRIC_CHECKED=0

# One claim, checked against the metrics the tree has.
metric_claim_check() {
  local doc="$1" line="$2" claim="$3" lower
  lower="${claim,,}"
  if [[ ! "$lower" =~ $HAS_METRIC_RE ]]; then
    return
  fi
  METRIC_CHECKED=$((METRIC_CHECKED + 1))
  if [[ "$lower" =~ $NO_METRIC_RE ]]; then
    if [ -n "$METRIC_FILES" ]; then
      fail "$(printf '%-22s %s line %s says there are no metrics, but %s computes them' \
        'metrics' "$doc" "$line" "$METRIC_FILES")"
      METRIC_BAD=1
    fi
    return
  fi
  if [ -z "$METRIC_FILES" ]; then
    fail "$(printf '%-22s %s line %s says the tree has metrics, but it has none' \
      'metrics' "$doc" "$line")"
    METRIC_BAD=1
  fi
}

# Every claim the design documents make, checked against the metrics.
check_metric_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      metric_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

metric_files
check_metric_claims

if [ "$METRIC_BAD" -eq 0 ]; then
  ok "metrics" "$METRIC_CHECKED claims"
fi

# --- the impact tables' callers -----------------------------------------------
#
# A row that names an affected file and the symbols in it is saying: if this
# symbol changes, this file breaks. That is only true if the file uses the
# symbol. A file that does not use it is not affected by it, and a reader who
# trusts the table will look in the wrong place.
#
# The row has to name a source file of the tree to be checked at all: a row
# whose first cell is a directory, an environment variable or a symbol is
# saying something else.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

# The source files the tree has.
IMPACT_SOURCES=""
impact_sources() {
  IMPACT_SOURCES=$(git ls-files '*.mbt' '*.ps1' 2>/dev/null | tr '\n' ' ' || true)
  trim "$IMPACT_SOURCES"; IMPACT_SOURCES="$TRIMMED"
}

IMPACT_BAD=0
IMPACT_CHECKED=0

# One row, checked against the file it names.
impact_claim_check() {
  local doc="$1" line="$2" claim="$3" rest first path token symbol last
  case "$claim" in
    \|*) ;;
    *) return ;;
  esac
  # the first cell of the row
  rest="${claim#*|}"
  first="${rest%%|*}"
  trim "$first"; first="$TRIMMED"
  case "$first" in
    '`'*'`') ;;
    *) return ;;
  esac
  path="${first:1:${#first}-2}"
  case "$path" in
    *.mbt|*.ps1) ;;
    *) return ;;
  esac
  case " $IMPACT_SOURCES " in
    *" $path "*) ;;
    *) return ;;
  esac
  [ -f "$path" ] || return
  # every symbol the row names, in the cells after the first
  rest="${rest#*|}"
  while [[ "$rest" =~ $TICK_RE ]]; do
    token="${BASH_REMATCH[1]}"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    symbol="${token%%(*}"
    symbol="${symbol%% *}"
    last="${symbol##*::}"
    last="${last##*.}"
    [ -n "$last" ] || continue
    IMPACT_CHECKED=$((IMPACT_CHECKED + 1))
    if ! grep -qF "$last" "$path"; then
      fail "$(printf '%-22s %s line %s says %s breaks on %s, but %s does not use it' \
        'impact caller' "$doc" "$line" "$path" "$symbol" "$path")"
      IMPACT_BAD=1
    fi
  done
}

# Every claim the design documents make, checked against the impact tables.
check_impact_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      impact_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

impact_sources
check_impact_claims

if [ "$IMPACT_BAD" -eq 0 ]; then
  ok "impact caller" "$IMPACT_CHECKED symbols"
fi

# --- the edge the tree does not have ------------------------------------------
#
# A claim that says the deployment needs no reverse proxy and no TLS is making
# a promise about the edge: the browser reaches the server over plain HTTP,
# with nothing in between and nothing to terminate. The tree has to keep that
# promise -- a proxy config or a certificate in the tree would mean the
# deployment is not the one the documents describe.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

# The places the tree would have to change to grow an edge.
PROXY_PLACES=""
TLS_PLACES=""
edge_places() {
  local file
  PROXY_PLACES=""
  TLS_PLACES=""
  for file in $(git ls-files 2>/dev/null); do
    case "$file" in
      *nginx*|*Caddyfile*|*caddyfile*|*traefik*|*haproxy*|*.htaccess)
        PROXY_PLACES="$PROXY_PLACES $file"
        ;;
    esac
    case "$file" in
      *.pem|*.crt|*.cer|*.key|*.pfx|*.p12)
        TLS_PLACES="$TLS_PLACES $file"
        ;;
    esac
  done
  trim "$PROXY_PLACES"; PROXY_PLACES="$TRIMMED"
  trim "$TLS_PLACES"; TLS_PLACES="$TRIMMED"
}

# A claim that denies a reverse proxy, and a claim that denies TLS.
NO_PROXY_RE='no [a-z, ]{0,60}reverse proxy'
NO_TLS_RE='no [a-z, ]{0,60}tls'

PROXY_BAD=0
TLS_BAD=0
PROXY_CHECKED=0
TLS_CHECKED=0

# One claim, checked against the edge the tree has.
edge_claim_check() {
  local doc="$1" line="$2" claim="$3" lower
  lower="${claim,,}"
  if [[ "$lower" =~ $NO_PROXY_RE ]]; then
    PROXY_CHECKED=$((PROXY_CHECKED + 1))
    if [ -n "$PROXY_PLACES" ]; then
      fail "$(printf '%-22s %s line %s says there is no reverse proxy, but %s is one' \
        'proxy' "$doc" "$line" "$PROXY_PLACES")"
      PROXY_BAD=1
    fi
  fi
  if [[ "$lower" =~ $NO_TLS_RE ]]; then
    TLS_CHECKED=$((TLS_CHECKED + 1))
    if [ -n "$TLS_PLACES" ]; then
      fail "$(printf '%-22s %s line %s says there is no TLS, but %s is a certificate' \
        'tls' "$doc" "$line" "$TLS_PLACES")"
      TLS_BAD=1
    fi
  fi
}

# Every claim the design documents make, checked against the edge.
check_edge_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      edge_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

edge_places
check_edge_claims

if [ "$PROXY_BAD" -eq 0 ]; then
  ok "proxy" "$PROXY_CHECKED claims"
fi
if [ "$TLS_BAD" -eq 0 ]; then
  ok "tls" "$TLS_CHECKED claims"
fi

# --- the channel the documents say is secure ----------------------------------
#
# The edge gate above reads the denials: a document that says there is no TLS
# has to be right about there being no TLS. This is the other side of it. A
# document that says the channel IS secure -- that the browser reaches the
# server over HTTPS, that the agent speaks to it over TLS -- is making the
# opposite promise, and that promise needs a certificate to keep it. The tree
# has none.
#
# The word is a channel, not a link: "https://mooncakes.io" is a URL that a
# reader clicks, and "HTTPS" is the protocol the server is reached with. A
# claim that denies TLS is not this gate's business: the gate above owns the
# denials.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

TLS_CHANNEL_BAD=0
TLS_CHANNEL_CHECKED=0

# A claim that says the channel is secure.
#
# The trailing class leaves out the colon as well as the word characters, so
# that "https://" -- a link -- is not a channel.
SECURE_CHANNEL_RE='([^A-Za-z0-9_]|^)(https|tls|ssl)([^A-Za-z0-9_:]|$)'

# One claim, checked against the certificates the tree has.
tls_channel_claim_check() {
  local doc="$1" line="$2" claim="$3" lower
  lower="${claim,,}"
  # a claim that does not talk about the channel's security is not this gate's
  # business
  [[ "$lower" =~ $SECURE_CHANNEL_RE ]] || return
  TLS_CHANNEL_CHECKED=$((TLS_CHANNEL_CHECKED + 1))
  # a denial is the edge gate's business
  if [[ "$lower" =~ $NO_TLS_RE ]]; then
    return
  fi
  if [ -z "$TLS_PLACES" ]; then
    fail "$(printf '%-22s %s line %s says the channel is secure, and the tree has no certificate' \
      'tls channel' "$doc" "$line")"
    TLS_CHANNEL_BAD=1
  fi
}

# Every claim the documents make, checked against the certificates the tree has.
check_tls_channel_claims() {
  local doc line claim n=0
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      tls_channel_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
  # the model is read a line at a time, the way a graph is
  while IFS= read -r line; do
    n=$((n + 1))
    [ -n "$line" ] || continue
    tls_channel_claim_check "$SYSTEM_MODEL_DSL" "$n" "$line"
  done < "$SYSTEM_MODEL_DSL"
}

check_tls_channel_claims

if [ "$TLS_CHANNEL_BAD" -eq 0 ]; then
  ok "tls channel" "$TLS_CHANNEL_CHECKED claims"
fi

# --- the coupling the table states -------------------------------------------
#
# A coupling row that counts the calls says how tightly two packages are
# tied together: "Eight function calls: install_from_environment, ...". The
# count and the list are a claim about the tree, and the tree can be asked.
#
# A call into a package is one of three things: a qualified call
# (@maked.create_app), a method on a value that package returned
# (app.to_module), or a method chained straight onto one
# (@maked.current_corpus().describe). A method on some other receiver
# (ctx.add_middleware, which is moonback's) is not a call into that package
# -- so the tree says eight where a naive reading of the names says nine.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

COUPLING_BAD=0
COUPLING_CHECKED=0

# Every match of a pattern in a text, one per line, in MATCHES.
MATCHES=""
all_matches() {
  local text="$1" pattern="$2" index="${3:-1}" rest
  MATCHES=""
  rest="$text"
  while [[ "$rest" =~ $pattern ]]; do
    MATCHES="$MATCHES${BASH_REMATCH[$index]}"$'\n'
    rest="${rest#*"${BASH_REMATCH[0]}"}"
  done
}

# A set of names, sorted and without repeats, in SORTED_SET.
SORTED_SET=""
sorted_set() {
  local out
  out=$(printf '%s\n' $1 | LC_ALL=C sort -u | tr '\n' ' ' || true)
  trim "$out"; SORTED_SET="$TRIMMED"
}

# The public functions a package has.
PUB_NAMES=""
pub_names() {
  local pkg="$1" file line name
  PUB_NAMES=""
  for file in $(git ls-files "$pkg" 2>/dev/null); do
    case "$file" in *_test.mbt) continue ;; esac
    while IFS= read -r line; do
      if [[ "$line" =~ ^[[:space:]]*pub[[:space:]]+(async[[:space:]]+)?fn[[:space:]]+([A-Za-z_][A-Za-z0-9_]*::)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\( ]]; then
        name="${BASH_REMATCH[3]}"
        case " $PUB_NAMES " in
          *" $name "*) continue ;;
        esac
        PUB_NAMES="$PUB_NAMES $name"
      fi
    done < "$file"
  done
  trim "$PUB_NAMES"; PUB_NAMES="$TRIMMED"
}

# The name a package is called by in another package's source.
PKG_ALIAS=""
pkg_alias() {
  local caller="$1" callee="$2" line
  PKG_ALIAS=""
  [ -f "$caller/moon.pkg" ] || return
  while IFS= read -r line; do
    if [[ "$line" =~ [\"][^\"]*/${callee}[\"]([[:space:]]+@([A-Za-z_][A-Za-z0-9_]*))? ]]; then
      if [ -n "${BASH_REMATCH[2]}" ]; then
        PKG_ALIAS="${BASH_REMATCH[2]}"
      else
        PKG_ALIAS="${callee##*/}"
      fi
      return
    fi
  done < "$caller/moon.pkg"
}

# The functions of one package that another package calls.
CALLED_NAMES=""
called_names() {
  local caller="$1" alias="$2" file line var vars name
  CALLED_NAMES=""
  for file in $(git ls-files "$caller" 2>/dev/null); do
    case "$file" in *_test.mbt) continue ;; esac
    vars=""
    while IFS= read -r line; do
      all_matches "$line" "let[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*@${alias}\."
      while IFS= read -r var; do
        [ -n "$var" ] || continue
        vars="$vars $var"
      done <<< "$MATCHES"
    done < "$file"
    while IFS= read -r line; do
      all_matches "$line" "@${alias}\.([A-Za-z_][A-Za-z0-9_]*)"
      while IFS= read -r name; do
        [ -n "$name" ] || continue
        case " $PUB_NAMES " in
          *" $name "*) CALLED_NAMES="$CALLED_NAMES $name" ;;
        esac
      done <<< "$MATCHES"
      for var in $vars; do
        all_matches "$line" "(^|[^A-Za-z0-9_])${var}\.([A-Za-z_][A-Za-z0-9_]*)" 2
        while IFS= read -r name; do
          [ -n "$name" ] || continue
          case " $PUB_NAMES " in
            *" $name "*) CALLED_NAMES="$CALLED_NAMES $name" ;;
          esac
        done <<< "$MATCHES"
      done
      all_matches "$line" "@${alias}\.[A-Za-z_][A-Za-z0-9_]*\([^()]*\)\.([A-Za-z_][A-Za-z0-9_]*)"
      while IFS= read -r name; do
        [ -n "$name" ] || continue
        case " $PUB_NAMES " in
          *" $name "*) CALLED_NAMES="$CALLED_NAMES $name" ;;
        esac
      done <<< "$MATCHES"
    done < "$file"
  done
}

# One coupling row, checked against the calls the tree makes.
coupling_claim_check() {
  local doc="$1" line="$2" claim="$3"
  local rest first second word list caller callee alias count tree_count name
  local tree_calls doc_symbols
  case "$claim" in
    \|*) ;;
    *) return ;;
  esac
  rest="${claim#*|}"
  first="${rest%%|*}"
  second="${rest#*|}"
  second="${second%%|*}"
  trim "$first"; first="$TRIMMED"
  trim "$second"; second="$TRIMMED"
  # the row has to name two packages
  set -- $first
  if [ $# -ne 3 ]; then
    return
  fi
  caller="$1"; callee="$3"
  case " $CODE_PKGS " in
    *" $caller "*) ;;
    *) return ;;
  esac
  case " $CODE_PKGS " in
    *" $callee "*) ;;
    *) return ;;
  esac
  # the cell has to state a count of calls
  if [[ ! "$second" =~ ([A-Za-z]+)[[:space:]]+function[[:space:]]+calls?: ]]; then
    return
  fi
  word="${BASH_REMATCH[1]}"
  list="${second#*:}"
  # the count, in words or in digits
  count=$(word_number "$(printf '%s' "$word" | tr 'A-Z' 'a-z')")
  if [ -z "$count" ]; then
    if [[ "$word" =~ ^[0-9]+$ ]]; then
      count="$word"
    fi
  fi
  if [ -z "$count" ]; then
    return
  fi
  # the symbols the row names
  doc_symbols=""
  for name in $(printf '%s' "$list" | tr ',' ' '); do
    name="${name//()/}"
    name="${name%.}"
    trim "$name"; name="$TRIMMED"
    [ -n "$name" ] || continue
    case " $doc_symbols " in
      *" $name "*) continue ;;
    esac
    doc_symbols="$doc_symbols $name"
  done
  trim "$doc_symbols"; doc_symbols="$TRIMMED"
  # the calls the tree makes
  pub_names "$callee"
  pkg_alias "$caller" "$callee"
  alias="$PKG_ALIAS"
  if [ -z "$alias" ]; then
    return
  fi
  called_names "$caller" "$alias"
  sorted_set "$CALLED_NAMES"
  tree_calls="$SORTED_SET"
  tree_count=0
  for name in $tree_calls; do
    tree_count=$((tree_count + 1))
  done
  # the symbols the row names, one by one
  for name in $doc_symbols; do
    COUPLING_CHECKED=$((COUPLING_CHECKED + 1))
    case " $tree_calls " in
      *" $name "*) ;;
      *)
        fail "$(printf '%-22s %s line %s names %s, but %s does not call it' \
          'coupling calls' "$doc" "$line" "$name" "$caller")"
        COUPLING_BAD=1
        ;;
    esac
  done
  # the calls the tree makes that the row does not name
  for name in $tree_calls; do
    case " $doc_symbols " in
      *" $name "*) ;;
      *)
        fail "$(printf '%-22s %s line %s does not name %s, but %s calls it' \
          'coupling calls' "$doc" "$line" "$name" "$caller")"
        COUPLING_BAD=1
        ;;
    esac
  done
  # and the count the row states
  if [ "$tree_count" != "$count" ]; then
    fail "$(printf '%-22s %s line %s says %s calls into %s, but the tree has %s' \
      'coupling calls' "$doc" "$line" "$word" "$callee" "$tree_count")"
    COUPLING_BAD=1
  fi
}

# Every coupling row, checked against the calls the tree makes.
check_coupling_claims() {
  local doc line claim
  code_packages
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      coupling_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

check_coupling_claims

if [ "$COUPLING_BAD" -eq 0 ]; then
  ok "coupling calls" "$COUPLING_CHECKED calls"
fi

# --- the cycles the graph does not have ---------------------------------------
#
# The dependency document says the package graph has no cycles: the packages
# depend strictly downward, so no package depends on one that depends on it.
# That is a claim about the tree, and the tree can be checked for it: the
# internal edges are known, and a cycle is an edge whose far end can reach
# its near end again.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

CYCLE_BAD=0
CYCLE_CHECKED=0

# The packages a package can reach.
REACHABLE=""
reachable() {
  local from="$1" edges="$2" line a b node seen next todo
  REACHABLE=""
  seen=" $from"
  todo="$from"
  while [ -n "$todo" ]; do
    next=""
    for node in $todo; do
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        a="${line%% *}"; b="${line##* }"
        [ "$a" = "$node" ] || continue
        case "$seen" in
          *" $b "*) continue ;;
        esac
        seen="$seen$b "
        next="$next $b"
        REACHABLE="$REACHABLE $b"
      done <<< "$edges"
    done
    todo="$next"
  done
  trim "$REACHABLE"; REACHABLE="$TRIMMED"
}

# The cycles the tree's package graph has.
TREE_CYCLES=""
tree_cycles() {
  local edges="$1" line a b
  TREE_CYCLES=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    a="${line%% *}"; b="${line##* }"
    reachable "$b" "$edges"
    case " $REACHABLE " in
      *" $a "*) TREE_CYCLES="$TREE_CYCLES $a -> $b" ;;
    esac
  done <<< "$edges"
  trim "$TREE_CYCLES"; TREE_CYCLES="$TRIMMED"
}

# A claim that says the graph has no cycles.
NO_CYCLE_RE='no cycles'

# One claim, checked against the cycles the tree has.
cycle_claim_check() {
  local doc="$1" line="$2" claim="$3" lower
  lower="${claim,,}"
  if [[ ! "$lower" =~ $NO_CYCLE_RE ]]; then
    return
  fi
  CYCLE_CHECKED=$((CYCLE_CHECKED + 1))
  if [ -n "$TREE_CYCLES" ]; then
    fail "$(printf '%-22s %s line %s says there are no cycles, but the tree has one: %s' \
      'cycles' "$doc" "$line" "$TREE_CYCLES")"
    CYCLE_BAD=1
  fi
}

# Every claim, checked against the cycles the tree has.
check_cycle_claims() {
  local doc line claim
  tree_cycles "$TREE_INTERNAL_EDGES"
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      cycle_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

check_cycle_claims

if [ "$CYCLE_BAD" -eq 0 ]; then
  ok "cycles" "$CYCLE_CHECKED claims"
fi

# --- the gaps the evidence has to support -------------------------------------
#
# The deployment evidence has a table of gaps, and a gap is a claim that
# something is NOT there: no systemd unit, no exported metrics, no backup
# strategy. The evidence cell has to be true of the tree, or the gap is not
# a gap.
#
# Two shapes of evidence are read. A search that comes back empty ("`find`
# for *.service returns nothing") is true when the tree has no file that
# matches the pattern. A denial of a thing ("No cron, no WAL config") is
# true when the tree has no such thing: the imports, when the denial names
# imports, and the product's own source otherwise.
#
# The scope comes from the evidence, and the evidence gives it. The frontend
# has a variable called `stats`, so "no stats" would be a sentence about a
# library, not about that variable -- and the evidence cell that says it
# also says "imports", so the gate looks in the imports.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

ABSENCE_BAD=0
ABSENCE_CHECKED=0

# The tracked files that match a pattern.
FILES_MATCHING=""
files_matching() {
  local pattern="$1" file
  FILES_MATCHING=""
  for file in $(git ls-files 2>/dev/null); do
    case "$file" in
      $pattern) FILES_MATCHING="$FILES_MATCHING $file" ;;
    esac
  done
  trim "$FILES_MATCHING"; FILES_MATCHING="$TRIMMED"
}

# The import paths that carry a word.
IMPORTS_WITH=""
imports_with() {
  local word="$1" path whole=0
  IMPORTS_WITH=""
  if [[ "$word" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    whole=1
  fi
  for path in $(tree_imports); do
    if [ "$whole" -eq 1 ]; then
      if [[ "$path" =~ (^|[^A-Za-z0-9_])${word}([^A-Za-z0-9_]|$) ]]; then
        IMPORTS_WITH="$IMPORTS_WITH $path"
      fi
    else
      case "$path" in
        *"$word"*) IMPORTS_WITH="$IMPORTS_WITH $path" ;;
      esac
    fi
  done
  trim "$IMPORTS_WITH"; IMPORTS_WITH="$TRIMMED"
}

# The files of the product's own source that carry a word. The tests are
# left out: a claim about what the server does is not a claim about what
# the tests say.
#
# A plain word is looked for as a whole word, so "wal" does not find
# "walked". A path is looked for as it is: "/metrics" is not a word.
SOURCE_WITH=""
source_with() {
  local word="$1" file line whole=0 hit=0
  SOURCE_WITH=""
  if [[ "$word" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    whole=1
  fi
  for file in $(git ls-files '*.mbt' 2>/dev/null); do
    case "$file" in
      *_test.mbt) continue ;;
    esac
    hit=0
    while IFS= read -r line; do
      if [ "$whole" -eq 1 ]; then
        if [[ "$line" =~ (^|[^A-Za-z0-9_])${word}([^A-Za-z0-9_]|$) ]]; then
          hit=1
          break
        fi
      else
        case "$line" in
          *"$word"*) hit=1; break ;;
        esac
      fi
    done < "$file"
    if [ "$hit" -eq 1 ]; then
      SOURCE_WITH="$SOURCE_WITH $file"
    fi
  done
  trim "$SOURCE_WITH"; SOURCE_WITH="$TRIMMED"
}

# One gap row, checked against the tree.
absence_claim_check() {
  local doc="$1" line="$2" claim="$3"
  local rest gap evidence lower after word phrase hits scope
  case "$claim" in
    \|*) ;;
    *) return ;;
  esac
  rest="${claim#*|}"
  gap="${rest%%|*}"
  rest="${rest#*|}"
  evidence="${rest%%|*}"
  trim "$gap"; gap="$TRIMMED"
  trim "$evidence"; evidence="$TRIMMED"
  # a gap is a row that says something is not there
  case "$gap" in
    "No "*|"no "*) ;;
    *) return ;;
  esac
  # a search that comes back empty
  if [[ "$evidence" =~ for[[:space:]]+([^[:space:]]+)[[:space:]]+returns[[:space:]]+nothing ]]; then
    ABSENCE_CHECKED=$((ABSENCE_CHECKED + 1))
    files_matching "${BASH_REMATCH[1]}"
    if [ -n "$FILES_MATCHING" ]; then
      fail "$(printf '%-22s %s line %s says nothing matches %s, but %s does' \
        'absence evidence' "$doc" "$line" "${BASH_REMATCH[1]}" "$FILES_MATCHING")"
      ABSENCE_BAD=1
    fi
    return
  fi
  # a denial of a thing, one at a time. The word keeps its case: "WAL" is
  # the SQLite mode, and "wal" is a part of "walked".
  lower="${evidence,,}"
  orig="$evidence"
  while :; do
    case "$lower" in
      *no\ *) ;;
      *) break ;;
    esac
    rest="${lower#*no }"
    len=$(( ${#lower} - ${#rest} ))
    after="${orig:$len}"
    word="${after%% *}"
    word="${word//\`/}"
    word="${word%%,*}"
    word="${word%%;*}"
    word="${word%%.*}"
    phrase="$after"
    rest_phrase="${after,,}"
    case "$rest_phrase" in
      *no\ *)
        tail_phrase="${rest_phrase#*no }"
        plen=$(( ${#rest_phrase} - ${#tail_phrase} ))
        phrase="${after:0:$plen}"
        ;;
    esac
    if [ -n "$word" ]; then
      ABSENCE_CHECKED=$((ABSENCE_CHECKED + 1))
      scope="source"
      case "$phrase" in
        *import*) scope="imports" ;;
      esac
      if [ "$scope" = "imports" ]; then
        imports_with "$word"
        hits="$IMPORTS_WITH"
      else
        source_with "$word"
        hits="$SOURCE_WITH"
      fi
      if [ -n "$hits" ]; then
        fail "$(printf '%-22s %s line %s says there is no %s, but %s has it' \
          'absence evidence' "$doc" "$line" "$word" "$hits")"
        ABSENCE_BAD=1
      fi
    fi
    lower="$rest"
    orig="$after"
  done
}

# Every gap row, checked against the tree.
check_absence_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      absence_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

check_absence_claims

if [ "$ABSENCE_BAD" -eq 0 ]; then
  ok "absence evidence" "$ABSENCE_CHECKED claims"
fi

# --- the edges the packages do not share ---------------------------------------
#
# The dependency document says the backend and the frontend share no direct
# dependency: they talk through the JSON contract at runtime, not through an
# import. That is a claim about the tree's edges, and the tree's edges are
# known.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

SHARED_BAD=0
SHARED_CHECKED=0

# A claim that names two packages and says they share no dependency.
NO_SHARED_RE='([a-z]+) and ([a-z]+) share no direct dependency'

# One claim, checked against the edges the tree has.
shared_claim_check() {
  local doc="$1" line="$2" claim="$3" lower first second l a b edge
  lower="${claim,,}"
  if [[ ! "$lower" =~ $NO_SHARED_RE ]]; then
    return
  fi
  first="${BASH_REMATCH[1]}"
  second="${BASH_REMATCH[2]}"
  # both have to be packages of the tree
  case " $CODE_PKGS " in
    *" $first "*) ;;
    *) return ;;
  esac
  case " $CODE_PKGS " in
    *" $second "*) ;;
    *) return ;;
  esac
  SHARED_CHECKED=$((SHARED_CHECKED + 1))
  # and the tree has to have no edge between them, either way
  edge=""
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    a="${l%% *}"; b="${l##* }"
    if [ "$a" = "$first" ] && [ "$b" = "$second" ]; then
      edge="$l"
      break
    fi
    if [ "$a" = "$second" ] && [ "$b" = "$first" ]; then
      edge="$l"
      break
    fi
  done <<< "$TREE_INTERNAL_EDGES"
  if [ -n "$edge" ]; then
    fail "$(printf '%-22s %s line %s says %s and %s share no direct dependency, but the tree has the edge %s' \
      'shared edge' "$doc" "$line" "$first" "$second" "$edge")"
    SHARED_BAD=1
  fi
}

# Every claim, checked against the edges the tree has.
check_shared_claims() {
  local doc line claim
  code_packages
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      shared_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

check_shared_claims

if [ "$SHARED_BAD" -eq 0 ]; then
  ok "shared edge" "$SHARED_CHECKED claims"
fi

# --- the counts the summary repeats --------------------------------------------
#
# The summary repeats three numbers: the tests, the mutation anchors and the
# integration checks. The tests are checked already; the other two were not,
# so they could go stale in the summary while the README and the tree stayed
# right.
#
# The anchors are counted in the tree: every mutation has one `old =` line,
# so the anchors in the three suites are the mutations they anchor. The
# integration checks cannot be counted from the script -- some of its
# assertions sit in loops, and only a run knows how many it made -- so the
# number is read where the tree keeps it: the README's own table, which the
# integration suite checks on every run.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

# The anchors in one mutation suite. An anchor is one `old =` line.
count_anchors() {
  local suite="$1"
  grep -cE '^[ \t]*old[ \t]*=' "$suite" || true
}

ALL_ANCHORS=$(( $(count_anchors tools/mutate-backend.ps1) \
              + $(count_anchors tools/mutate-frontend.ps1) \
              + $(count_anchors tools/mutate-loop.ps1) ))

# The integration checks the README states.
doc_number '\|[[:space:]]*Integration checks[[:space:]]*\|[[:space:]]*([0-9]+)[[:space:]]*\|' "README.md"
README_INTEGRATION="$DOC_NUMBER"

if [ -z "$README_INTEGRATION" ]; then
  fail "$(printf '%-22s could not be read from the README' 'summary integration')"
else
  check_claim_number "summary anchors" '([0-9]+) mutation anchors' \
    "$ALL_ANCHORS" "$SUMMARY"
  check_claim_number "summary integration" '([0-9]+) integration[[:space:]]+checks' \
    "$README_INTEGRATION" "$SUMMARY"
fi

# --- the external column the table states -------------------------------------
#
# The dependency table has a column that says what each package leans on
# outside the project. It is a claim about the tree's manifests: the package
# imports exactly these, and nothing else.
#
# The document writes the paths the way a reader writes them -- "moonback"
# for "moonbitlang/moonback", "core (debug, env, json)" for the core
# packages -- so the comparison is made on the last segment of each path,
# which is the part both sides spell the same way.
#
# The test-only imports are left out: the column says what a package needs
# to run, and a test block is not what it needs to run.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

EXTERNAL_BAD=0
EXTERNAL_CHECKED=0

# The external imports of a package, the test block left out.
PKG_EXTERNAL=""
pkg_external() {
  local pkg="$1" line inside=0 test=0 block="" path
  PKG_EXTERNAL=""
  [ -f "$pkg/moon.pkg" ] || return
  while IFS= read -r line; do
    if [ "$inside" -eq 0 ]; then
      case "$line" in
        "import {"*) inside=1; block=""; test=0 ;;
      esac
      continue
    fi
    case "$line" in
      *"}"*)
        inside=0
        case "$line" in
          *'for "test"'*) test=1 ;;
        esac
        if [ "$test" -eq 0 ]; then
          all_matches "$block" '"([^"]+)"'
          while IFS= read -r path; do
            [ -n "$path" ] || continue
            case "$path" in
              riantr/MAKED*) continue ;;
            esac
            PKG_EXTERNAL="$PKG_EXTERNAL ${path##*/}"
          done <<< "$MATCHES"
        fi
        ;;
      *) block="$block $line" ;;
    esac
  done < "$pkg/moon.pkg"
  trim "$PKG_EXTERNAL"; PKG_EXTERNAL="$TRIMMED"
}

# The last segments a column names. A group -- "core (debug, env, json)" --
# is read as the paths it stands for.
EXTERNAL_NAMED=""
external_named() {
  local cell="$1" out="" item="" depth=0 ch i base member
  local items=""
  for ((i = 0; i < ${#cell}; i++)); do
    ch="${cell:i:1}"
    case "$ch" in
      "(") depth=$((depth + 1)) ;;
      ")") depth=$((depth - 1)) ;;
    esac
    if [ "$ch" = "," ] && [ "$depth" -eq 0 ]; then
      items="$items$item"$'\n'
      item=""
    else
      item="$item$ch"
    fi
  done
  items="$items$item"$'\n'
  while IFS= read -r item; do
    trim "$item"; item="$TRIMMED"
    [ -n "$item" ] || continue
    case "$item" in
      "(none)"|"(empty)") continue ;;
    esac
    if [[ "$item" =~ ^([^[:space:]]+)[[:space:]]+\((.*)\)$ ]]; then
      base="${BASH_REMATCH[1]}"
      for member in ${BASH_REMATCH[2]//,/ }; do
        out="$out ${member##*/}"
      done
    else
      out="$out ${item##*/}"
    fi
  done <<< "$items"
  trim "$out"; EXTERNAL_NAMED="$TRIMMED"
}

# The rows of the internal dependencies table: the line, the package and the
# external cell.
DOC_EXTERNAL_ROWS=""
doc_external_rows() {
  awk '
    /^\|[[:space:]]*Package[[:space:]]*\|/ { inside = 1; next }
    inside && /^\|/ {
      n = split($0, cells, "[|]")
      pkg = cells[2]
      ext = cells[4]
      gsub(/`/, "", pkg)
      gsub(/[ \t]/, "", pkg)
      gsub(/^[ \t]+|[ \t]+$/, "", ext)
      if (pkg ~ /^[-\t]+$/) { next }
      if (pkg == "") { next }
      if (ext == "") { next }
      print NR "\t" pkg "\t" ext
    }
    inside && !/^\|/ { exit }
  ' "$DEPS_MD"
}

# One row, checked against the package's own manifest.
external_column_check() {
  local doc="$1" line="$2" pkg="$3" cell="$4"
  local named tree name
  external_named "$cell"
  sorted_set "$EXTERNAL_NAMED"
  named="$SORTED_SET"
  case "$pkg" in
    root*) pkg="." ;;
  esac
  pkg_external "$pkg"
  sorted_set "$PKG_EXTERNAL"
  tree="$SORTED_SET"
  EXTERNAL_CHECKED=$((EXTERNAL_CHECKED + 1))
  for name in $named; do
    case " $tree " in
      *" $name "*) ;;
      *)
        fail "$(printf '%-22s %s line %s says %s depends on %s, but the tree does not' \
          'external column' "$doc" "$line" "$pkg" "$name")"
        EXTERNAL_BAD=1
        ;;
    esac
  done
  for name in $tree; do
    case " $named " in
      *" $name "*) ;;
      *)
        fail "$(printf '%-22s %s line %s leaves %s out of %s, but the tree imports it' \
          'external column' "$doc" "$line" "$name" "$pkg")"
        EXTERNAL_BAD=1
        ;;
    esac
  done
}

# Every row, checked against the package's own manifest.
check_external_columns() {
  local row line pkg cell
  DOC_EXTERNAL_ROWS=$(doc_external_rows)
  while IFS=$'\t' read -r line pkg cell; do
    [ -n "$line" ] || continue
    external_column_check "$DEPS_MD" "$line" "$pkg" "$cell"
  done <<< "$DOC_EXTERNAL_ROWS"
}

check_external_columns

if [ "$EXTERNAL_BAD" -eq 0 ]; then
  ok "external column" "$EXTERNAL_CHECKED packages"
fi

# --- the size a claim gives a file ---------------------------------------------
#
# The summary sizes the framework layer: the backend's `App` is ~150 lines.
# That is a number about the tree -- the file the type is defined in -- and
# the tree can be counted.
#
# A "~" is a tolerance, not an exact figure: the claim is about the size of
# the thing, not about a line. The gate accepts the stated number when the
# file is within a tenth of it, and says so plainly when it is not.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

SIZE_BAD=0
SIZE_CHECKED=0

# A claim that sizes a type's file.
SIZE_RE='`([A-Za-z_][A-Za-z0-9_]*)` is ~([0-9]+) lines'

# The files that define a type.
TYPE_FILES=""
type_files() {
  local name="$1" file
  TYPE_FILES=""
  for file in $(git ls-files '*.mbt' 2>/dev/null); do
    case "$file" in *_test.mbt) continue ;; esac
    if grep -qE "^[[:space:]]*pub struct ${name}([^A-Za-z0-9_]|$)" "$file" 2>/dev/null; then
      TYPE_FILES="$TYPE_FILES $file"
    fi
  done
  trim "$TYPE_FILES"; TYPE_FILES="$TRIMMED"
}

# One claim, checked against the file the type is defined in.
size_claim_check() {
  local doc="$1" line="$2" claim="$3" name stated file count diff found=0
  if [[ ! "$claim" =~ $SIZE_RE ]]; then
    return
  fi
  name="${BASH_REMATCH[1]}"
  stated="${BASH_REMATCH[2]}"
  type_files "$name"
  for file in $TYPE_FILES; do
    found=$((found + 1))
  done
  if [ "$found" -eq 0 ]; then
    fail "$(printf '%-22s %s line %s sizes %s, but the tree has no such type' \
      'file size' "$doc" "$line" "$name")"
    SIZE_BAD=1
    return
  fi
  if [ "$found" -gt 1 ]; then
    return
  fi
  file="$TYPE_FILES"
  file_line_count "$file"
  count="$FILE_LINE_COUNT"
  SIZE_CHECKED=$((SIZE_CHECKED + 1))
  diff=$(( count - stated ))
  if [ "$diff" -lt 0 ]; then
    diff=$(( -diff ))
  fi
  if [ "$diff" -gt $(( stated / 10 )) ]; then
    fail "$(printf '%-22s %s line %s says %s is ~%s lines, but %s has %s' \
      'file size' "$doc" "$line" "$name" "$stated" "$file" "$count")"
    SIZE_BAD=1
  fi
}

# Every claim, checked against the file the type is defined in.
check_size_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      size_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

check_size_claims

if [ "$SIZE_BAD" -eq 0 ]; then
  ok "file size" "$SIZE_CHECKED claims"
fi

# --- the packages that use each dependency -----------------------------------
#
# The dependency table has a column that says who uses each dependency. It
# is a claim about the tree's manifests: the packages whose import block
# names the dependency, and no others.
#
# The comparison is on the MODULE, not on the path. A package that imports
# "moonbitlang/async/fs" imports the module "moonbitlang/async", and the
# table names modules. So the first two segments of an import path are what
# is compared.
#
# The test imports count: a package that imports a dependency for its tests
# still uses it.
#
# The cell is a set, not a list: the order the packages are written in says
# nothing, so the two are compared by membership.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

USED_BY_BAD=0
USED_BY_CHECKED=0

# Every package the tree has, the root one included.
ALL_PKGS=""
all_packages() {
  local rel
  ALL_PKGS=""
  for rel in $(git ls-files 2>/dev/null | grep -E '(^|/)moon\.pkg$'); do
    case "$rel" in
      moon.pkg) ALL_PKGS="$ALL_PKGS root" ;;
      *) ALL_PKGS="$ALL_PKGS ${rel%/moon.pkg}" ;;
    esac
  done
  trim "$ALL_PKGS"; ALL_PKGS="$TRIMMED"
}

# The module roots a package imports, the test imports included.
PKG_ROOTS=""
pkg_roots() {
  local pkg="$1" file line inside=0 block="" path root first rest
  PKG_ROOTS=""
  case "$pkg" in
    root) file="moon.pkg" ;;
    *) file="$pkg/moon.pkg" ;;
  esac
  [ -f "$file" ] || return
  while IFS= read -r line; do
    if [ "$inside" -eq 0 ]; then
      case "$line" in
        "import {"*) inside=1; block="" ;;
      esac
      continue
    fi
    case "$line" in
      *"}"*)
        inside=0
        all_matches "$block" '"([^"]+)"'
        while IFS= read -r path; do
          [ -n "$path" ] || continue
          case "$path" in
            riantr/MAKED*) continue ;;
            */*) ;;
            *) continue ;;
          esac
          # The first two segments of the path: the module it belongs to.
          # "moonbitlang/async/fs" is the module "moonbitlang/async".
          first="${path%%/*}"
          rest="${path#*/}"
          root="$first/${rest%%/*}"
          PKG_ROOTS="$PKG_ROOTS $root"
        done <<< "$MATCHES"
        ;;
      *) block="$block $line" ;;
    esac
  done < "$file"
  trim "$PKG_ROOTS"; PKG_ROOTS="$TRIMMED"
}

# The packages that import a dependency.
DEP_USERS=""
dep_users() {
  local dep="$1" pkg root
  DEP_USERS=""
  for pkg in $ALL_PKGS; do
    pkg_roots "$pkg"
    for root in $PKG_ROOTS; do
      if [ "$root" != "$dep" ]; then
        continue
      fi
      case " $DEP_USERS " in
        *" $pkg "*) ;;
        *) DEP_USERS="$DEP_USERS $pkg" ;;
      esac
    done
  done
  trim "$DEP_USERS"; DEP_USERS="$TRIMMED"
}

# The packages a cell names.
USED_BY_NAMED=""
used_by_named() {
  local cell="$1" rest item out=""
  USED_BY_NAMED=""
  rest="$cell"
  while [ -n "$rest" ]; do
    case "$rest" in
      *,*) item="${rest%%,*}"; rest="${rest#*,}" ;;
      *) item="$rest"; rest="" ;;
    esac
    trim "$item"; item="$TRIMMED"
    [ -n "$item" ] || continue
    out="$out $item"
  done
  trim "$out"; USED_BY_NAMED="$TRIMMED"
}

# The rows of the dependency table: the line, the dependency and the cell
# that says who uses it.
DOC_USED_BY_ROWS=""
doc_used_by_rows() {
  awk '
    /^\|[[:space:]]*Dependency[[:space:]]*\|[[:space:]]*Version[[:space:]]*\|[[:space:]]*Used by[[:space:]]*\|/ { inside = 1; next }
    inside && /^\|/ {
      n = split($0, cells, "[|]")
      dep = cells[2]
      used = cells[4]
      gsub(/`/, "", dep)
      gsub(/[ \t]/, "", dep)
      gsub(/^[ \t]+|[ \t]+$/, "", used)
      if (dep ~ /^[-\t]+$/) { next }
      if (dep == "") { next }
      if (used == "") { next }
      print NR "\t" dep "\t" used
    }
    inside && !/^\|/ { exit }
  ' "$EVIDENCE"
}

# One row, checked against the tree.
used_by_check() {
  local doc="$1" line="$2" dep="$3" cell="$4"
  local named tree name
  dep_users "$dep"
  sorted_set "$DEP_USERS"; tree="$SORTED_SET"
  USED_BY_CHECKED=$((USED_BY_CHECKED + 1))
  if [ "$cell" = "(transitive)" ]; then
    for name in $tree; do
      fail "$(printf '%-22s %s line %s says %s is transitive, but the tree imports it in %s' \
        'used by' "$doc" "$line" "$dep" "$name")"
      USED_BY_BAD=1
    done
    return
  fi
  used_by_named "$cell"
  sorted_set "$USED_BY_NAMED"; named="$SORTED_SET"
  for name in $named; do
    case " $tree " in
      *" $name "*) ;;
      *)
        fail "$(printf '%-22s %s line %s says %s is used by %s, but the tree does not import it there' \
          'used by' "$doc" "$line" "$dep" "$name")"
        USED_BY_BAD=1
        ;;
    esac
  done
  for name in $tree; do
    case " $named " in
      *" $name "*) ;;
      *)
        fail "$(printf '%-22s %s line %s leaves %s out of %s, but the tree imports it there' \
          'used by' "$doc" "$line" "$name" "$dep")"
        USED_BY_BAD=1
        ;;
    esac
  done
}

# Every row, checked against the tree.
check_used_by() {
  local row line dep cell
  all_packages
  DOC_USED_BY_ROWS=$(doc_used_by_rows)
  while IFS=$'\t' read -r line dep cell; do
    [ -n "$line" ] || continue
    used_by_check "$EVIDENCE" "$line" "$dep" "$cell"
  done <<< "$DOC_USED_BY_ROWS"
}

check_used_by

if [ "$USED_BY_BAD" -eq 0 ]; then
  ok "used by" "$USED_BY_CHECKED rows"
fi

# --- the edges the graphs draw -----------------------------------------------
#
# Two graphs draw the tree's external dependencies: the dependency graph
# (architecture/dependencies.dot) and the component graph
# (architecture/system-model.dot). Each draws an edge into a node that stands
# for an external MoonBit package, and the edge is a claim: the thing on the
# tail of the edge depends on the package on the head of it.
#
# Nothing read the tree to see whether that was true. The measurement that
# found the gap: the component graph drew an edge from the assembly to
# moonbitlang/x, and the whole gate suite still said that every claim in the
# documents matches the tree. The module pins moonbitlang/x; no package
# imports it.
#
# The dependency a node names is the first line of its label with the version
# taken off. The two graphs name it the two ways -- the dependency graph says
# "moonbitlang/x@0.5.6" and the component graph says "x@0.5.6" -- and the
# tree knows both.
#
# Who owns the claim depends on what the tail of the edge is:
#
#   - the manifest node names moon.mod, so the claim is the module's: the
#     module's own import block.
#   - a node that names a package ("backend/") owns it for that package: the
#     package's own import block.
#   - a node that names modules (backend/maked_app.mbt) is a layer of the
#     tree rather than a package, so the claim is the tree's: some package
#     has to import the dependency.
#
# The claim holds when the owner imports the dependency itself, or something
# under it, or -- when the graph names the dependency the short way -- the
# module it belongs to.

GRAPH_EDGE_BAD=0
GRAPH_EDGE_CHECKED=0
GRAPH_EDGE_GRAPHS="$DEPENDENCIES_DOT $SYSTEM_MODEL_DOT"

# The graph writes the lines of a label with a backslash and an n.
DOT_NL='\n'

# The import paths a manifest declares, the version taken off.
manifest_paths() {
  local file="$1" line inside=0 block="" path
  MANIFEST_PATHS=""
  [ -f "$file" ] || return
  while IFS= read -r line; do
    if [ "$inside" -eq 0 ]; then
      case "$line" in
        "import {"*) inside=1; block="" ;;
      esac
      continue
    fi
    case "$line" in
      *"}"*)
        inside=0
        all_matches "$block" '"([^"]+)"'
        while IFS= read -r path; do
          [ -n "$path" ] || continue
          # the version is a number; anything else after an @ is not one
          if [[ "$path" =~ @[0-9][0-9.]*$ ]]; then
            path="${path%@*}"
          fi
          MANIFEST_PATHS="$MANIFEST_PATHS $path"
        done <<< "$MATCHES"
        ;;
      *) block="$block $line" ;;
    esac
  done < "$file"
  trim "$MANIFEST_PATHS"; MANIFEST_PATHS="$TRIMMED"
}

# The import paths of every package the tree has.
tree_pkg_paths() {
  local pkg
  TREE_PKG_PATHS=""
  for pkg in $(tree_packages); do
    manifest_paths "${pkg}moon.pkg"
    TREE_PKG_PATHS="$TREE_PKG_PATHS $MANIFEST_PATHS"
  done
  trim "$TREE_PKG_PATHS"; TREE_PKG_PATHS="$TRIMMED"
}

# The first line of every node's label, with the node's id.
dot_nodes() {
  awk '
    {
      line = $0
      if (pending != "") {
        if (line ~ /label="/) {
          lbl = line; sub(/^.*label="/, "", lbl); sub(/".*$/, "", lbl)
          print pending "\t" lbl
          pending = ""
        } else if (line ~ /\]/) {
          pending = ""
        }
        next
      }
      if (line ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\[/) {
        id = line
        sub(/^[[:space:]]*/, "", id)
        sub(/[[:space:]]*\[.*$/, "", id)
        if (id == "node" || id == "edge" || id == "graph" || id == "digraph" || id == "subgraph") next
        if (line ~ /label="/) {
          lbl = line; sub(/^.*label="/, "", lbl); sub(/".*$/, "", lbl)
          print id "\t" lbl
        } else {
          pending = id
        }
      }
    }
  ' "$1"
}

# The ids of the nodes the graph defines.
dot_node_ids() {
  awk '
    {
      if ($0 ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\[/) {
        id = $0
        sub(/^[[:space:]]*/, "", id)
        sub(/[[:space:]]*\[.*$/, "", id)
        if (id == "node" || id == "edge" || id == "graph" || id == "digraph" || id == "subgraph") next
        print id
      }
    }
  ' "$1"
}

# The nodes the graph draws in its external subgraph.
dot_external() {
  sed -n '/subgraph cluster_external {/,/^[[:space:]]*}/p' "$1" \
    | sed -n 's/^[[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\)[[:space:]]*\[.*label=".*/\1/p'
}

# The edges of the graph.
dot_edges() {
  sed -n 's/^[[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\)[[:space:]]*->[[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\).*/\1\t\2/p' "$1"
}

# The first line of a label.
#
# The graph writes the lines of a label with a backslash and an n. The
# pattern has to be quoted: unquoted, a backslash in a glob escapes the
# character after it, so the pattern would match the letter n and not the
# two characters the graph writes.
label_head() {
  printf '%s' "${1%%"$DOT_NL"*}"
}

# The dependency a node names: the first line, with the version taken off.
dep_name() {
  local head="$1"
  if [[ "$head" =~ ^(.+)@[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "$head"
  fi
}

# The import paths of the owner of a claim: the module, a package, or the tree.
owner_paths() {
  local head="$1"
  case "$head" in
    moon.mod) manifest_paths "moon.mod"; printf '%s' "$MANIFEST_PATHS" ;;
    */) manifest_paths "${head}moon.pkg"; printf '%s' "$MANIFEST_PATHS" ;;
    *) printf '%s' "$TREE_PKG_PATHS" ;;
  esac
}

# Does the owner import the dependency?
owner_imports() {
  local paths="$1" dep="$2" p last
  for p in $paths; do
    [ -n "$p" ] || continue
    if [ "$p" = "$dep" ]; then return 0; fi
    case "$p" in
      "$dep"/*) return 0 ;;
    esac
    # the graph names the dependency the short way: the last segment of the
    # module it belongs to
    case "$dep" in
      */*) continue ;;
    esac
    last="${p#*/}"
    last="${last%%/*}"
    if [ "$last" = "$dep" ]; then return 0; fi
  done
  return 1
}

tree_pkg_paths

for file in $GRAPH_EDGE_GRAPHS; do
  [ -f "$file" ] || continue
  nodes="$(dot_nodes "$file")"
  external="$(dot_external "$file" | tr '\n' ' ')"
  while IFS=$'\t' read -r tail head; do
    [ -n "$tail" ] || continue
    [ -n "$head" ] || continue
    # only an edge into an external node is a claim about a dependency
    case " $external " in
      *" $head "*) ;;
      *) continue ;;
    esac
    head_label="$(printf '%s\n' "$nodes" | awk -F'\t' -v n="$head" '$1==n {print $2; exit}')"
    tail_label="$(printf '%s\n' "$nodes" | awk -F'\t' -v n="$tail" '$1==n {print $2; exit}')"
    [ -n "$head_label" ] || continue
    [ -n "$tail_label" ] || continue
    dep="$(dep_name "$(label_head "$head_label")")"
    owner="$(label_head "$tail_label")"
    paths="$(owner_paths "$owner")"
    GRAPH_EDGE_CHECKED=$((GRAPH_EDGE_CHECKED + 1))
    if owner_imports "$paths" "$dep"; then
      continue
    fi
    fail "$(printf '%-22s %s draws an edge from %s to %s, and the tree does not import %s' \
      'graph edge' "$file" "$tail" "$head" "$dep")"
    GRAPH_EDGE_BAD=1
  done <<< "$(dot_edges "$file")"
done

if [ "$GRAPH_EDGE_BAD" -eq 0 ]; then
  ok "graph edge" "$GRAPH_EDGE_CHECKED edges"
fi

# --- the nodes the graphs draw -----------------------------------------------
#
# Every edge in a graph names two nodes. A graph that draws an edge to a node
# it never defines draws a node nobody asked for: the picture shows a name
# with no label, outside every cluster, and the reader cannot tell what it is
# supposed to be.

GRAPH_NODE_BAD=0
GRAPH_NODE_CHECKED=0

for file in $GRAPH_EDGE_GRAPHS; do
  [ -f "$file" ] || continue
  defined="$(dot_node_ids "$file" | tr '\n' ' ')"
  while IFS=$'\t' read -r tail head; do
    [ -n "$tail" ] || continue
    [ -n "$head" ] || continue
    GRAPH_NODE_CHECKED=$((GRAPH_NODE_CHECKED + 1))
    missing=""
    case " $defined " in
      *" $tail "*) ;;
      *) missing="$tail" ;;
    esac
    if [ -z "$missing" ]; then
      case " $defined " in
        *" $head "*) ;;
        *) missing="$head" ;;
      esac
    fi
    [ -n "$missing" ] || continue
    fail "$(printf '%-22s %s draws an edge from %s to %s, and the graph does not define %s' \
      'graph node' "$file" "$tail" "$head" "$missing")"
    GRAPH_NODE_BAD=1
  done <<< "$(dot_edges "$file")"
done

if [ "$GRAPH_NODE_BAD" -eq 0 ]; then
  ok "graph node" "$GRAPH_NODE_CHECKED edges"
fi

# --- the import blocks the dependency evidence states --------------------------
#
# The dependency evidence states, for every package of the tree, the import
# block that package declares. Two claims are in each row: the package is one
# the tree has, and the list beside it is the package's own imports.
#
# Nothing read the table to see whether that was true. The measurement that
# found the gap: the table left cmd/mcp out altogether, and the row it had for
# cmd/server named one import fewer than that package imports -- and the
# whole gate suite still said that every claim in the documents matches the
# tree.
#
# The names the table uses are the tree's own, written short. A package of
# this module is named by its own directory; a package from the registry is
# named by its repository, and by the last segment when the import goes
# deeper than the repository: moonbitlang/async/fs is "async/fs", and
# moonbitlang/moonback/middlewares/unstable_static is
# "moonback/unstable_static". The alias an import is bound under is written
# in brackets, the way the table already writes it.

IMPORT_BLOCK_BAD=0
IMPORT_BLOCK_CHECKED=0

# The name of this module, out of moon.mod.
MODULE_NAME=$(sed -nE 's/^name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' moon.mod 2>/dev/null | head -1)

# The import blocks of a manifest: the kind of the block, a tab, the path, a
# tab, the alias. A block is the main one, unless the manifest marks it
# `for "test"`.
manifest_import_blocks() {
  awk '
    { lines[NR] = $0 }
    END {
      inside = 0
      for (i = 1; i <= NR; i++) {
        line = lines[i]
        if (!inside) {
          if (line ~ /^[[:space:]]*import[[:space:]]*\{/) { inside = 1; block = "" }
          continue
        }
        if (line ~ /\}/) {
          kind = "main"
          if (line ~ /for[[:space:]]+"test"/) kind = "test"
          else if (i < NR && lines[i+1] ~ /for[[:space:]]*"test"/) kind = "test"
          rest = block
          while (match(rest, /"[^"]+"([ \t]*@[A-Za-z_][A-Za-z0-9_]*)?/)) {
            item = substr(rest, RSTART, RLENGTH)
            rest = substr(rest, RSTART + RLENGTH)
            path = item
            alias = ""
            if (match(item, /[ \t]+@[A-Za-z_][A-Za-z0-9_]*$/)) {
              alias = substr(item, RSTART, RLENGTH)
              sub(/^[ \t]+/, "", alias)
              path = substr(item, 1, RSTART - 1)
            }
            gsub(/^"|"$/, "", path)
            gsub(/@[0-9][0-9.]*$/, "", path)
            print kind "\t" path "\t" alias
          }
          inside = 0
          block = ""
          continue
        }
        block = block " " line
      }
    }
  ' "$1"
}

# The name the table gives an import path.
short_import() {
  local path="$1" rest last
  case "$path" in
    "$MODULE_NAME"/*) printf '%s' "${path#"$MODULE_NAME"/}"; return ;;
  esac
  rest="${path#*/}"
  if [ "$rest" = "$path" ]; then printf '%s' "$path"; return; fi
  last="${rest##*/}"
  case "$rest" in
    */*) printf '%s/%s' "${rest%%/*}" "$last" ;;
    *) printf '%s' "$rest" ;;
  esac
}

# The names of the imports a manifest declares in the blocks of one kind,
# written the way the table writes them.
manifest_names() {
  local file="$1" kind="$2" out="" k path alias name
  while IFS=$'\t' read -r k path alias; do
    [ "$k" = "$kind" ] || continue
    [ -n "$path" ] || continue
    name="$(short_import "$path")"
    if [ -n "$alias" ]; then
      out="$out $name($alias)"
    else
      out="$out $name"
    fi
  done < <(manifest_import_blocks "$file")
  unique_names "$out"
}

# A list of names without duplicates, in the order they are first named.
unique_names() {
  local out="" item
  local -a items=()
  read -ra items <<< "$1"
  for item in "${items[@]}"; do
    [ -n "$item" ] || continue
    case " $out " in
      *" $item "*) continue ;;
    esac
    out="$out $item"
  done
  out="${out# }"
  printf '%s' "$out"
}

# Do two lists of names name the same set?
sets_equal() {
  local a="$1" b="$2" x
  local -a ai=() bi=()
  read -ra ai <<< "$a"
  read -ra bi <<< "$b"
  [ "${#ai[@]}" -eq "${#bi[@]}" ] || return 1
  for x in "${ai[@]}"; do
    case " $b " in
      *" $x "*) ;;
      *) return 1 ;;
    esac
  done
  for x in "${bi[@]}"; do
    case " $a " in
      *" $x "*) ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# A list of names as a sentence lists them.
join_names() {
  local out="" item
  local -a items=()
  read -ra items <<< "$1"
  for item in "${items[@]}"; do
    [ -n "$item" ] || continue
    if [ -z "$out" ]; then out="$item"; else out="$out, $item"; fi
  done
  printf '%s' "$out"
}

# The rows of the table the dependency evidence states: the package, a tab,
# and the import block beside it.
deps_table_rows() {
  awk '
    /^## Package dependencies/ { inside = 1; next }
    inside && /^## / { inside = 0 }
    inside && /^\|/ {
      n = split($0, c, "|")
      if (n < 4) next
      pkg = c[2]; imp = c[3]
      gsub(/^[ \t]+|[ \t]+$/, "", pkg)
      gsub(/^[ \t]+|[ \t]+$/, "", imp)
      if (pkg == "Package" || pkg ~ /^-/) next
      print pkg "\t" imp
    }
  ' "$DEPS"
}

# The names a cell of the table lists, written the way the table writes them.
CELL_ALIAS_RE='^(.*)[[:space:]]*\(@([^)]*)\)$'
cell_names() {
  local out="" item name alias
  local -a items=()
  IFS=',' read -ra items <<< "$1"
  for item in "${items[@]}"; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [ -n "$item" ] || continue
    name="$item"
    alias=""
    if [[ "$item" =~ $CELL_ALIAS_RE ]]; then
      name="${BASH_REMATCH[1]}"
      # the greedy match leaves the space in front of the bracket behind
      name="${name%"${name##*[![:space:]]}"}"
      alias="@${BASH_REMATCH[2]}"
    fi
    if [ -n "$alias" ]; then
      out="$out $name($alias)"
    else
      out="$out $name"
    fi
  done
  unique_names "$out"
}

DEP_ROWS="$(deps_table_rows)"
TREE_PKGS="$(tree_packages | tr '\n' ' ')"

for pkg in $TREE_PKGS; do
  main_names="$(manifest_names "${pkg}moon.pkg" main)"
  test_names="$(manifest_names "${pkg}moon.pkg" test)"
  doc_main=""
  doc_test=""
  while IFS=$'\t' read -r row_pkg row_cell; do
    [ -n "$row_pkg" ] || continue
    if [ "$row_pkg" = "$pkg" ]; then doc_main="$row_cell"; fi
    if [ "$row_pkg" = "$pkg (test only)" ]; then doc_test="$row_cell"; fi
  done <<< "$DEP_ROWS"

  IMPORT_BLOCK_CHECKED=$((IMPORT_BLOCK_CHECKED + 1))
  if [ -z "$doc_main" ]; then
    fail "$(printf '%-22s %s has no row for the package %s' 'import block' "$DEPS" "$pkg")"
    IMPORT_BLOCK_BAD=1
  else
    doc_names="$(cell_names "$doc_main")"
    if ! sets_equal "$main_names" "$doc_names"; then
      fail "$(printf '%-22s %s says %s imports [%s], and the tree imports [%s]' \
        'import block' "$DEPS" "$pkg" "$(join_names "$doc_names")" "$(join_names "$main_names")")"
      IMPORT_BLOCK_BAD=1
    fi
  fi

  if [ -n "$test_names" ] || [ -n "$doc_test" ]; then
    IMPORT_BLOCK_CHECKED=$((IMPORT_BLOCK_CHECKED + 1))
    if [ -z "$doc_test" ]; then
      fail "$(printf '%-22s %s has no row for the test-only imports of %s' 'import block' "$DEPS" "$pkg")"
      IMPORT_BLOCK_BAD=1
    else
      doc_names="$(cell_names "$doc_test")"
      if ! sets_equal "$test_names" "$doc_names"; then
        fail "$(printf '%-22s %s says the test-only imports of %s are [%s], and the tree says [%s]' \
          'import block' "$DEPS" "$pkg" "$(join_names "$doc_names")" "$(join_names "$test_names")")"
        IMPORT_BLOCK_BAD=1
      fi
    fi
  fi
done

# A row for a package the tree does not have is a claim about a package that
# is not there.
while IFS=$'\t' read -r row_pkg row_cell; do
  [ -n "$row_pkg" ] || continue
  base="${row_pkg%% (test only)*}"
  case " $TREE_PKGS " in
    *" $base "*) ;;
    *)
      fail "$(printf '%-22s %s has a row for %s, and the tree has no such package' \
        'import block' "$DEPS" "$row_pkg")"
      IMPORT_BLOCK_BAD=1
      ;;
  esac
done <<< "$DEP_ROWS"

if [ "$IMPORT_BLOCK_BAD" -eq 0 ]; then
  ok "import block" "$IMPORT_BLOCK_CHECKED rows"
fi

# --- the order the ring's domains are in ---------------------------------------
#
# The ring is a ring, and the ORDER is the claim: Model before Data before
# Experience. The README states its order in two places and the README's own
# gate watches them. The order the architecture documents state was watched by
# nothing. The measurement that found the gap: architecture/system-model.md
# stated the ring as (Model, Attack, Knowledge, Experience, Data), the tree
# says Model, Data, Experience, Attack, Knowledge, and every gate still said
# that every claim in the documents matches the tree.
#
# The tree's ring is the tuples of backend/pages.mbt, in the order they are
# written. A document is read for the RUNS it writes of those titles -- a run
# is two or more of the tree's own titles side by side -- and every run has to
# be a contiguous part of the ring: "Model Data" is the ring's first two, and
# "Data Model" is not the ring at all. A document that names one domain says
# nothing about the order, so a run of one is not a claim.

RING_ORDER_BAD=0
RING_ORDER_CHECKED=0

# The documents that state the ring. The README is not in the list: the
# README's own gate watches its order, and a claim is watched once.
RING_ORDER_DOCS="$AGENT_DOC architecture/system-model.md architecture/system-model.summary.md \
architecture/system-model.evidence.md architecture/dependencies.md \
architecture/dependencies.evidence.md architecture/deployment.md \
architecture/deployment.evidence.md architecture/flows.md architecture/flows.evidence.md"

# The titles of the ring's domains, out of the tree.
ring_titles() {
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

# The runs of the tree's titles a document writes, one per line, the titles of
# each run in the order the document writes them.
doc_ring_runs() {
  local file="$1" alt="$2"
  [ -f "$file" ] || return 0
  tr '\n' ' ' < "$file" | tr -s ' ' \
    | grep -oE "$alt([^A-Za-z0-9]+$alt)*" \
    | while IFS= read -r match; do
        [ -n "$match" ] || continue
        printf '%s\n' "$(printf '%s' "$match" | grep -oE "$alt" | tr '\n' ' ' | sed -e 's/ *$//')"
      done
}

# Is a run of titles a contiguous part of the ring?
run_in_ring() {
  local run="$1" titles="$2" n i j ok
  local -a r=() t=()
  read -ra r <<< "$run"
  read -ra t <<< "$titles"
  n=${#r[@]}
  [ "$n" -gt 0 ] || return 1
  for ((i = 0; i + n <= ${#t[@]}; i++)); do
    ok=1
    for ((j = 0; j < n; j++)); do
      if [ "${t[i+j]}" != "${r[j]}" ]; then ok=0; break; fi
    done
    if [ "$ok" -eq 1 ]; then return 0; fi
  done
  return 1
}

RING_TITLES=$(ring_titles)
RING_ALT=$(ring_title_alternation "$RING_TITLES")

for doc in $RING_ORDER_DOCS; do
  [ -f "$doc" ] || continue
  # a document that describes the past is history: it is not corrected
  case " $MARKED_DOCS " in
    *" $doc "*) continue ;;
  esac
  seen=""
  while IFS= read -r run; do
    [ -n "$run" ] || continue
    # one title is not an order: a run of two or more holds a space
    case "$run" in
      *" "*) ;;
      *) continue ;;
    esac
    case " $seen " in
      *" $run "*) continue ;;
    esac
    seen="$seen $run"
    RING_ORDER_CHECKED=$((RING_ORDER_CHECKED + 1))
    if ! run_in_ring "$run" "$RING_TITLES"; then
      fail "$(printf '%-22s %s writes the ring as [%s], and the tree says [%s]' \
        'ring order' "$doc" "$run" "$RING_TITLES")"
      RING_ORDER_BAD=1
    fi
  done <<< "$(doc_ring_runs "$doc" "$RING_ALT")"
done

if [ "$RING_ORDER_BAD" -eq 0 ]; then
  ok "ring order" "$RING_ORDER_CHECKED runs"
fi

# --- the test counts the evidence states ---------------------------------------
#
# The evidence table says, for each test file it names, how many tests that
# file holds. Two gates watch two of those files by name; every other row is
# watched by nothing. The measurement that found the gap: a row was added for
# backend/session_test.mbt saying 99 tests, and the file has 19, and the whole
# gate suite still said that every claim in the documents matches the tree.
#
# The count is the tree's own: a test is a `test "name" {` block, or an
# `async test "name" {` one, and both shapes exist in this tree. The table
# names fewer files than the tree has -- it is an evidence table, not an
# inventory -- so the claim is about the files it does name.

TEST_COUNT_BAD=0
TEST_COUNT_CHECKED=0

# The rows of the Tests table the evidence states: the file, a tab, and the
# number of tests the row says it holds.
evidence_test_rows() {
  awk '
    /^## Tests/ { inside = 1; next }
    inside && /^## / { inside = 0 }
    inside && /^\|/ {
      n = split($0, c, "|")
      if (n < 4) next
      file = c[2]; what = c[3]
      gsub(/^[ \t]+|[ \t]+$/, "", file)
      gsub(/^[ \t]+|[ \t]+$/, "", what)
      if (file == "Test file" || file ~ /^-/) next
      # the file is written in brackets
      gsub(/^`|`$/, "", file)
      if (what !~ /^[0-9]+ tests/) next
      count = what
      sub(/ tests.*$/, "", count)
      print file "\t" count
    }
  ' "$EVIDENCE"
}

# The number of tests a file holds.
#
# The blanks are [[:blank:]] here and [ \t] in the PowerShell twin, because a
# .NET \s would match a newline and a POSIX [ \t] would match the letter t.
# The two patterns are the same one, written in the two dialects.
test_count() {
  grep -cE '^([[:blank:]])*(async[[:blank:]]+)?test[[:blank:]]+"[^"]*"[[:blank:]]*\{' "$1" 2>/dev/null || true
}

while IFS=$'\t' read -r file count; do
  [ -n "$file" ] || continue
  TEST_COUNT_CHECKED=$((TEST_COUNT_CHECKED + 1))
  if [ ! -f "$file" ]; then
    fail "$(printf '%-22s %s names the test file %s, and the tree does not have it' \
      'test count' "$EVIDENCE" "$file")"
    TEST_COUNT_BAD=1
    continue
  fi
  actual="$(test_count "$file")"
  if [ "$actual" != "$count" ]; then
    fail "$(printf '%-22s %s says %s holds %s tests, and the tree has %s' \
      'test count' "$EVIDENCE" "$file" "$count" "$actual")"
    TEST_COUNT_BAD=1
  fi
done <<< "$(evidence_test_rows)"

if [ "$TEST_COUNT_BAD" -eq 0 ]; then
  ok "test count" "$TEST_COUNT_CHECKED rows"
fi

# --- the platforms the release builds ------------------------------------------
#
# The deployment evidence says which platforms the release is built for, and
# how many. Both are claims about the release workflow's matrix: the targets it
# names are the platforms, and the number of them is the number of the matrix.
#
# Nothing read them. The measurement that found the gap: the document said
# "Four platforms" where the matrix has three, and every gate still said that
# every claim in the documents matches the tree.

RELEASE_PLATFORM_BAD=0
RELEASE_PLATFORM_CHECKED=0

# The targets the release workflow's matrix names.
code_release_targets() {
  tr -d '\r' < .github/workflows/publish.yml 2>/dev/null \
    | sed -nE 's/^[[:blank:]]+target:[[:blank:]]+([A-Za-z0-9_.-]+)[[:blank:]]*$/\1/p'
}

# The cell of the deployment evidence that states the platforms. A table cell
# ends at the bar that separates it from the next one, so the cells are cut out
# of the row, and the cell that names platforms is the one that says how many.
doc_release_platform_cell() {
  tr '|' '\n' < "$DEPLOY" \
    | grep -Ei '(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)[ ]+platforms' \
    | head -1
}

# The count the cell gives the platforms, as a number.
doc_release_platform_count() {
  local cell="$1" word
  word=$(printf '%s' "$cell" \
    | grep -oEi '(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)[ ]+platforms' \
    | head -1 | cut -d' ' -f1 | tr 'A-Z' 'a-z')
  word_number "$word"
}

# The names the cell gives the platforms.
doc_release_platform_names() {
  local cell="$1" list="" item names=""
  list=$(printf '%s' "$cell" | sed -E 's/^[^:]*:[[:blank:]]*//')
  local -a items=()
  IFS=',' read -ra items <<< "$list"
  for item in "${items[@]}"; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [ -n "$item" ] || continue
    names="$names $item"
  done
  names="${names# }"
  printf '%s' "$names"
}

RELEASE_TARGETS="$(code_release_targets | tr '\n' ' ')"
RELEASE_TARGETS="${RELEASE_TARGETS% }"
RELEASE_TARGET_COUNT=0
for t in $RELEASE_TARGETS; do RELEASE_TARGET_COUNT=$((RELEASE_TARGET_COUNT + 1)); done

PLATFORM_CELL="$(doc_release_platform_cell)"
if [ -z "$PLATFORM_CELL" ]; then
  fail "$(printf '%-22s %s does not say which platforms the release is built for' \
    'release platforms' "$DEPLOY")"
  RELEASE_PLATFORM_BAD=1
else
  RELEASE_PLATFORM_CHECKED=$((RELEASE_PLATFORM_CHECKED + 1))
  DOC_PLATFORM_COUNT="$(doc_release_platform_count "$PLATFORM_CELL")"
  DOC_PLATFORM_NAMES="$(doc_release_platform_names "$PLATFORM_CELL")"
  if [ -z "$DOC_PLATFORM_COUNT" ] || [ "$DOC_PLATFORM_COUNT" != "$RELEASE_TARGET_COUNT" ]; then
    fail "$(printf '%-22s %s says the release is built for %s platforms, and the matrix has %s' \
      'release platforms' "$DEPLOY" "${DOC_PLATFORM_COUNT:-?}" "$RELEASE_TARGET_COUNT")"
    RELEASE_PLATFORM_BAD=1
  fi
  missing=""
  extra=""
  for t in $RELEASE_TARGETS; do
    case " $DOC_PLATFORM_NAMES " in
      *" $t "*) ;;
      *) missing="$missing $t" ;;
    esac
  done
  for n in $DOC_PLATFORM_NAMES; do
    case " $RELEASE_TARGETS " in
      *" $n "*) ;;
      *) extra="$extra $n" ;;
    esac
  done
  missing="${missing# }"
  extra="${extra# }"
  if [ -n "$missing" ] || [ -n "$extra" ]; then
    fail "$(printf '%-22s %s names the platforms [%s], and the matrix names [%s]' \
      'release platforms' "$DEPLOY" "$DOC_PLATFORM_NAMES" "$RELEASE_TARGETS")"
    RELEASE_PLATFORM_BAD=1
  fi
fi

if [ "$RELEASE_PLATFORM_BAD" -eq 0 ]; then
  ok "release platforms" "$RELEASE_TARGET_COUNT platforms"
fi

# --- the type definitions the evidence points at --------------------------------
#
# The evidence tables say what a type IS, and point at the file and line that
# holds the type. A pointer to the line above the definition is a pointer to a
# comment: a reader who follows it finds a sentence about the type rather than
# the type.
#
# The measurement that found the gap: the row that says the Handler type is
# `async (Request) -> Response` pointed at backend/app.mbt:16, which is the
# comment above it. The type is defined on line 17. Nothing noticed, and the
# gate suite still said that every claim in the documents matches the tree.
#
# The names are the tree's own. A claim is about a type when it says so in the
# document's own words -- "Handler type is ...", "Page struct with ..." -- and
# the name in front of that word is the type it is about. The name may be
# anywhere in the claim: "Frontend Page struct mirrors backend shape" is
# about the Page struct too.
#
# The measurement that found the second gap: the row that says the frontend
# Page struct mirrors the backend shape pointed at frontend/page.mbt:16-30,
# and when that pointer was moved to :17-30 nothing noticed. The claim
# named the type and the gate did not look at the name.

TYPE_DEF_BAD=0
TYPE_DEF_CHECKED=0

# The definitions the tree has: the name, a tab, the file, a tab, the line.
code_definitions() {
  local f
  find backend frontend cmd -name '*.mbt' -type f 2>/dev/null | LC_ALL=C sort | \
  while IFS= read -r f; do
    awk -v file="$f" '
      {
        line = $0
        sub(/^[[:blank:]]+/, "", line)
        if (match(line, /^(pub(\(all\))?[[:blank:]]+)?(type|struct|enum)[[:blank:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
          head = substr(line, 1, RLENGTH)
          if (match(head, /(type|struct|enum)[[:blank:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
            name = substr(head, RSTART, RLENGTH)
            sub(/^(type|struct|enum)[[:blank:]]+/, "", name)
            print name "\t" file "\t" FNR
          }
        }
      }
    ' "$f"
  done
}

# The rows of the evidence tables that are about a type: the name of the type
# and the word "type" or "struct" after it.
#
# The name may be anywhere in the claim. "Frontend Page struct mirrors
# backend shape" is about the Page struct, and a gate that only looked at
# the first word of the claim would not see it at all.
evidence_type_rows() {
  awk -F'|' '
    {
      claim = $2
      src = $3
      gsub(/^[ \t]+|[ \t]+$/, "", claim)
      gsub(/^[ \t]+|[ \t]+$/, "", src)
      if (src !~ /:/) next
      # the source is written in brackets: `backend/app.mbt:16`
      gsub(/^`|`$/, "", src)
      rest = claim
      while (match(rest, /[A-Za-z_][A-Za-z0-9_]*[ \t]+(type|struct)[ \t]+/)) {
        # the match does not start at the beginning of the claim, so the text it
        # covers is taken from RSTART, not from the first character
        head = substr(rest, RSTART, RLENGTH)
        name = head
        sub(/[ \t]+(type|struct)[ \t]+$/, "", name)
        print name "\t" src
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
  ' "$1"
}

TYPE_DEFS="$(code_definitions)"

# The names the tree's types go by. A claim that says "Handler type is ..."
# is about a type, and a claim that says "a value type with a Body enum" is
# not: "value" is not one of the tree's type names, so the row says nothing
# about a type in the file it points at.
TYPE_NAMES=""
while IFS=$'\t' read -r d_name d_file d_line; do
  [ -n "$d_name" ] || continue
  case " $TYPE_NAMES " in
    *" $d_name "*) continue ;;
  esac
  TYPE_NAMES="$TYPE_NAMES $d_name"
done <<< "$TYPE_DEFS"

for doc in "$EVIDENCE" "$DEPS" "$DEPLOY" architecture/flows.evidence.md; do
  [ -f "$doc" ] || continue
  # a document that describes the past is history: it is not corrected
  not_in "$doc" "$MARKED_DOCS"
  [ -n "$NOT_IN" ] || continue
  while IFS=$'\t' read -r name src; do
    [ -n "$name" ] || continue
    [ -n "$src" ] || continue
    # the source names the file and the line, or the range of lines
    src_file="${src%%:*}"
    src_lines="${src#*:}"
    # the type is looked up in the file the document points at: the tree has
    # a Page in the backend and a Page in the frontend, and the document may
    # be about either one
    def_line=""
    while IFS=$'\t' read -r d_name d_file d_line; do
      if [ "$d_name" = "$name" ] && [ "$d_file" = "$src_file" ]; then
        def_line="$d_line"
        break
      fi
    done <<< "$TYPE_DEFS"
    if [ -z "$def_line" ]; then
      # a name the tree does not give to any type is not a type name at all
      case " $TYPE_NAMES " in
        *" $name "*) ;;
        *) continue ;;
      esac
      fail "$(printf '%-22s %s says the %s type is at %s, and that file defines no such type' \
        'type definition' "$doc" "$name" "$src_file")"
      TYPE_DEF_BAD=1
      continue
    fi
    TYPE_DEF_CHECKED=$((TYPE_DEF_CHECKED + 1))
    case "$src_lines" in
      *-*)
        first="${src_lines%%-*}"
        last="${src_lines##*-}"
        ;;
      *)
        first="$src_lines"
        last="$src_lines"
        ;;
    esac
    if [ "$def_line" -lt "$first" ] || [ "$def_line" -gt "$last" ]; then
      fail "$(printf '%-22s %s points the %s type at %s, and the tree defines it on line %s' \
        'type definition' "$doc" "$name" "$src_lines" "$def_line")"
      TYPE_DEF_BAD=1
    fi
  done <<< "$(evidence_type_rows "$doc")"
done

if [ "$TYPE_DEF_BAD" -eq 0 ]; then
  ok "type definition" "$TYPE_DEF_CHECKED claims"
fi

# --- the gaps the documents say are gaps ---------------------------------------
#
# The summary has a section that says what the product does not have, and the
# other documents and the README say the same things in their own words. Each
# denial is a claim about the tree: the tree must not have the thing denied.
#
# A denial is found by its phrase, and the thing it denies is looked for by
# the words that name it. Those words are the tree's vocabulary, not the
# document's: a document says "no auth", and an authentication in the tree
# would be a login, a password, a credential or a bearer token.
#
# The search is on the CODE, not on the comments. A comment that says "there
# is no auth" is a denial, not an authentication, and a comment that says
# "tracking the corpus" is not analytics.
#
# A document that describes the past is a record of the past, so it is left
# alone: what the tree had then is not what the tree has now.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

GAPS_BAD=0
GAPS_CHECKED=0

# The files that are infrastructure as code.
IAC_FILES=""
iac_files() {
  local rel files=""
  for rel in $(git ls-files 2>/dev/null); do
    case "$rel" in
      *.tf|*.tfvars|*.bicep|*.hcl|ansible.cfg|playbook*.yml|Chart.yaml|\
      kustomization.yaml|Pulumi.yaml|serverless.yml|*.cfn|samconfig.toml|\
      appspec.yml|*.template.json)
        files="$files $rel"
        ;;
    esac
  done
  trim "$files"; IAC_FILES="$TRIMMED"
}

# The files that provision a hosted environment.
HOSTED_FILES=""
hosted_files() {
  local rel files=""
  for rel in $(git ls-files 2>/dev/null); do
    case "$rel" in
      fly.toml|railway.json|railway.toml|render.yaml|vercel.json|netlify.toml|\
      Procfile|heroku.yml|app.yaml|azure.yaml|cloudbuild.yaml|*.kubeconfig|\
      web.config|*.nomad|*.service|k8s/*|kubernetes/*|helm/*|cloudfoundry/*)
        files="$files $rel"
        ;;
    esac
  done
  trim "$files"; HOSTED_FILES="$TRIMMED"
}

# The code of a source file, without its comments. The quotes go first: a
# string that holds a "//" is a string, not a comment. The result is in
# CODE, because a subshell per line would be too slow.
CODE=""
code_of() {
  local line="$1" code
  code="${line//\"/}"
  code="${code%%//*}"
  CODE="$code"
}

# The source files whose code carries one of a list of words. The list is
# space separated, the search is a whole-word one, and it does not care
# about case. CODE_WORD_FILES holds the files, CODE_WORD_FILE the first
# one, and CODE_WORD_WORD the word that was found in it.
CODE_WORD_FILES=""
CODE_WORD_FILE=""
CODE_WORD_WORD=""
code_word_files() {
  local words="$1" file line code word hit
  CODE_WORD_FILES=""
  CODE_WORD_FILE=""
  CODE_WORD_WORD=""
  for file in $(git ls-files '*.mbt' 2>/dev/null); do
    case "$file" in *_test.mbt|*_wbtest.mbt) continue ;; esac
    hit=""
    while IFS= read -r line; do
      code_of "$line"
      code="$CODE"
      for word in $words; do
        if [[ "${code,,}" =~ (^|[^a-z0-9_])${word}([^a-z0-9_]|$) ]]; then
          hit="$word"
          break
        fi
      done
      [ -n "$hit" ] && break
    done < "$file"
    if [ -n "$hit" ]; then
      CODE_WORD_FILES="$CODE_WORD_FILES $file"
      if [ -z "$CODE_WORD_FILE" ]; then
        CODE_WORD_FILE="$file"
        CODE_WORD_WORD="$hit"
      fi
    fi
  done
  trim "$CODE_WORD_FILES"; CODE_WORD_FILES="$TRIMMED"
}

# The words that name the things the documents deny.
TRACING_WORDS="tracing tracer opentelemetry jaeger zipkin opentracing"
ALERTING_WORDS="alerting alert alertmanager pagerduty opsgenie"
ANALYTICS_WORDS="analytics telemetry tracking gtag googletagmanager matomo mixpanel posthog hotjar"
AUTH_WORDS="auth authorization authenticate bearer login logout password credential oauth jwt apikey api_key basic_auth session_token signin sign_in"

# The source files whose code names the /metrics path.
METRICS_FILES=""
metrics_files() {
  local file line code
  METRICS_FILES=""
  for file in $(git ls-files '*.mbt' 2>/dev/null); do
    case "$file" in *_test.mbt|*_wbtest.mbt) continue ;; esac
    while IFS= read -r line; do
      code_of "$line"
      code="$CODE"
      case "$code" in
        */metrics*) METRICS_FILES="$METRICS_FILES $file"; break ;;
      esac
    done < "$file"
  done
  trim "$METRICS_FILES"; METRICS_FILES="$TRIMMED"
}

# One claim, checked against the tree.
gap_claim_check() {
  local doc="$1" line="$2" claim="$3" lower
  lower="${claim,,}"

  if [[ "$lower" =~ no[[:space:]]+iac([^a-z]|$) ]]; then
    GAPS_CHECKED=$((GAPS_CHECKED + 1))
    if [ -n "$IAC_FILES" ]; then
      fail "$(printf '%-22s %s line %s says there is no IaC, but the tree has %s' \
        'gaps' "$doc" "$line" "$IAC_FILES")"
      GAPS_BAD=1
    fi
  fi

  if [[ "$lower" =~ no[[:space:]]+hosted[[:space:]]environment ]]; then
    GAPS_CHECKED=$((GAPS_CHECKED + 1))
    if [ -n "$HOSTED_FILES" ]; then
      fail "$(printf '%-22s %s line %s says there is no hosted environment, but the tree has %s' \
        'gaps' "$doc" "$line" "$HOSTED_FILES")"
      GAPS_BAD=1
    fi
  fi

  if [[ "$lower" =~ no[[:space:]]+[^[:space:]]*/metrics ]]; then
    GAPS_CHECKED=$((GAPS_CHECKED + 1))
    if [ -n "$METRICS_FILES" ]; then
      fail "$(printf '%-22s %s line %s says there is no /metrics endpoint, but %s serves one' \
        'gaps' "$doc" "$line" "$METRICS_FILES")"
      GAPS_BAD=1
    fi
  fi

  if [[ "$lower" =~ no[[:space:]]+tracing([^a-z]|$) ]]; then
    GAPS_CHECKED=$((GAPS_CHECKED + 1))
    code_word_files "$TRACING_WORDS"
    if [ -n "$CODE_WORD_FILES" ]; then
      fail "$(printf '%-22s %s line %s says there is no tracing, but %s has %s in it' \
        'gaps' "$doc" "$line" "$CODE_WORD_FILE" "$CODE_WORD_WORD")"
      GAPS_BAD=1
    fi
  fi

  if [[ "$lower" =~ no[[:space:]]+alerting([^a-z]|$) ]]; then
    GAPS_CHECKED=$((GAPS_CHECKED + 1))
    code_word_files "$ALERTING_WORDS"
    if [ -n "$CODE_WORD_FILES" ]; then
      fail "$(printf '%-22s %s line %s says there is no alerting, but %s has %s in it' \
        'gaps' "$doc" "$line" "$CODE_WORD_FILE" "$CODE_WORD_WORD")"
      GAPS_BAD=1
    fi
  fi

  if [[ "$lower" =~ no[[:space:]]+analytics([^a-z]|$) ]]; then
    GAPS_CHECKED=$((GAPS_CHECKED + 1))
    code_word_files "$ANALYTICS_WORDS"
    if [ -n "$CODE_WORD_FILES" ]; then
      fail "$(printf '%-22s %s line %s says there is no analytics, but %s has %s in it' \
        'gaps' "$doc" "$line" "$CODE_WORD_FILE" "$CODE_WORD_WORD")"
      GAPS_BAD=1
    fi
  fi

  if [[ "$lower" =~ no[[:space:]]+auth(entication)?([^a-z]|$) ]]; then
    GAPS_CHECKED=$((GAPS_CHECKED + 1))
    code_word_files "$AUTH_WORDS"
    if [ -n "$CODE_WORD_FILES" ]; then
      fail "$(printf '%-22s %s line %s says there is no auth, but %s has %s in it' \
        'gaps' "$doc" "$line" "$CODE_WORD_FILE" "$CODE_WORD_WORD")"
      GAPS_BAD=1
    fi
  fi
}

# Every claim the documents make, checked against the tree.
check_gap_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      gap_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
  # the README says the same things in its own words
  doc_claims "README.md"
  while IFS=$'\t' read -r line claim; do
    [ -n "$claim" ] || continue
    gap_claim_check "README.md" "$line" "$claim"
  done <<< "$DOC_CLAIMS"
}

iac_files
hosted_files
metrics_files
check_gap_claims

if [ "$GAPS_BAD" -eq 0 ]; then
  ok "gaps" "$GAPS_CHECKED denials"
fi

# --- the gaps the tables promise ------------------------------------------------
#
# The deployment document has a table of the gaps, and the deployment evidence
# has another one: the things the tree does not have yet. Every row of a table
# of gaps is a claim about the tree, and it is a claim in both directions. The
# thing the row names must not be in the tree, and the row must say so: a row
# that says the tree has no systemd unit is right only while the tree has no
# systemd unit, and a row that says the tree has one is right only while it
# has.
#
# The capabilities the rows name come from the tree:
#
#   - a systemd unit is a *.service file, and a supervisor is a supervisor
#     config or the word in the tree's own code.
#   - TLS is a certificate in the tree.
#   - exported metrics are a /metrics endpoint.
#   - tracing, alerting and a backup strategy are the words the tree would
#     use for them.
#   - structured logging is a log line that prints a JSON document.
#
# A table of gaps is found by its header: the first cell of the header row is
# "Gap". The gap cell of a row is the first cell of the row.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

GAPROW_BAD=0
GAPROW_CHECKED=0

# The capabilities a gap row can name.
GAP_CAPABILITIES="systemd
supervisor
tls
exported metrics
tracing
alerting
backup
structured logging"

# The source files whose code logs a JSON document.
STRUCTURED_LOG_FILES=""
structured_log_files() {
  local file line
  STRUCTURED_LOG_FILES=""
  for file in $(git ls-files '*.mbt' 2>/dev/null); do
    case "$file" in *_test.mbt|*_wbtest.mbt) continue ;; esac
    while IFS= read -r line; do
      case "$line" in
        *eprintln\(*|*println\(*) ;;
        *) continue ;;
      esac
      case "$line" in
        *'"{"'*|*@json*|*stringify*)
          STRUCTURED_LOG_FILES="$STRUCTURED_LOG_FILES $file"
          break
          ;;
      esac
    done < "$file"
  done
  trim "$STRUCTURED_LOG_FILES"; STRUCTURED_LOG_FILES="$TRIMMED"
}

# The places the tree would have the thing a capability names.
GAP_HITS=""
gap_capability_places() {
  local name="$1"
  GAP_HITS=""
  case "$name" in
    systemd)
      files_matching '*.service'
      GAP_HITS="$FILES_MATCHING"
      ;;
    supervisor)
      files_matching '*supervisor*'
      GAP_HITS="$FILES_MATCHING"
      code_word_files 'supervisor'
      [ -z "$CODE_WORD_FILES" ] || GAP_HITS="$GAP_HITS $CODE_WORD_FILES"
      ;;
    tls)
      edge_places
      GAP_HITS="$TLS_PLACES"
      ;;
    metrics)
      metrics_files
      GAP_HITS="$METRICS_FILES"
      ;;
    tracing)
      code_word_files "$TRACING_WORDS"
      GAP_HITS="$CODE_WORD_FILES"
      ;;
    alerting)
      code_word_files "$ALERTING_WORDS"
      GAP_HITS="$CODE_WORD_FILES"
      ;;
    backup)
      code_word_files 'backup'
      GAP_HITS="$CODE_WORD_FILES"
      ;;
    logging)
      structured_log_files
      GAP_HITS="$STRUCTURED_LOG_FILES"
      ;;
  esac
  trim "$GAP_HITS"; GAP_HITS="$TRIMMED"
}

# The name the tree knows a capability by.
gap_capability_name() {
  case "$1" in
    'exported metrics') echo "metrics" ;;
    'structured logging') echo "logging" ;;
    *) echo "$1" ;;
  esac
}

# Does the cell name this capability? A single word has to be a whole word;
# a phrase is a phrase.
gap_cell_has() {
  local cell="$1" phrase="$2" low="${2,,}"
  case "$phrase" in
    *' '*)
      case "${cell,,}" in
        *"$phrase"*) return 0 ;;
      esac
      return 1
      ;;
  esac
  if [[ "${cell,,}" =~ (^|[^a-z0-9_])${low}([^a-z0-9_]|$) ]]; then
    return 0
  fi
  return 1
}

# The gap cells of the tables whose first column is "Gap".
GAP_CELLS=""
gap_cells() {
  local doc line n=0 in_table=0 cell
  GAP_CELLS=""
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    n=0
    in_table=0
    while IFS= read -r line; do
      n=$((n + 1))
      case "$line" in
        "| Gap |"*) in_table=1; continue ;;
        "|---"*) continue ;;
      esac
      [ "$in_table" -eq 1 ] || continue
      case "$line" in
        "| "*) ;;
        *) in_table=0; continue ;;
      esac
      cell="${line#*|}"
      cell="${cell%%|*}"
      trim "$cell"; cell="$TRIMMED"
      [ -n "$cell" ] || continue
      GAP_CELLS="${GAP_CELLS}${doc}"$'\037'"${n}"$'\037'"${cell}"$'\n'
    done < "$doc"
  done
}

# The gap rows, checked against the tree.
check_gap_rows() {
  local doc line cell denied phrase name hits
  while IFS=$'\037' read -r doc line cell; do
    [ -n "$cell" ] || continue
    denied=0
    case "${cell,,}" in
      "no "*) denied=1 ;;
    esac
    while IFS= read -r phrase; do
      [ -n "$phrase" ] || continue
      gap_cell_has "$cell" "$phrase" || continue
      name="$(gap_capability_name "$phrase")"
      gap_capability_places "$name"
      hits="$GAP_HITS"
      GAPROW_CHECKED=$((GAPROW_CHECKED + 1))
      if [ -n "$hits" ] && [ "$denied" -eq 1 ]; then
        fail "$(printf '%-22s %s line %s says there is no %s, but the tree has %s' \
          'gap row' "$doc" "$line" "$phrase" "$hits")"
        GAPROW_BAD=1
      elif [ -z "$hits" ] && [ "$denied" -eq 0 ]; then
        fail "$(printf '%-22s %s line %s says the tree has %s, but it does not' \
          'gap row' "$doc" "$line" "$phrase")"
        GAPROW_BAD=1
      fi
    done <<< "$GAP_CAPABILITIES"
  done <<< "$GAP_CELLS"
}

gap_cells
check_gap_rows

if [ "$GAPROW_BAD" -eq 0 ]; then
  ok "gap row" "$GAPROW_CHECKED claims"
fi

# --- the requests the frontend makes at start-up -------------------------------
#
# The start-up is a chain: the init asks for the bootstrap, the answer asks
# for the loop status, and the second answer asks for nothing. A document
# that says "one request at start-up" is telling the reader that the page
# load is one round trip, and it is not.
#
# The chain is found in the tree. The init is the block that starts with
# "init=fn(emit) {" and ends with "},"; every answer is handled by the arm
# of the message it carries, and the arm after it is the one for the failure.
# The chain ends when an answer asks for nothing.
#
# A claim that names the start-up request is pointing at it, so the line it
# cites has to be the line the tree makes it on.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

STARTUP_BAD=0
STARTUP_CHECKED=0
STARTUP_COUNT=0
STARTUP_LINE=0
FRONTEND_APP="frontend/app.mbt"

# The count a claim states: a number, or the word a number is written with.
COUNT_RE='([0-9]+|one|two|three|four|five|six|seven|eight|nine|ten)([[:space:]]+http)?[[:space:]]+requests?'

# The lines of the frontend, with the spaces taken off.
APP_LINES=()
app_lines() {
  local line
  APP_LINES=()
  while IFS= read -r line; do
    trim "$line"
    APP_LINES+=("$TRIMMED")
  done < "$FRONTEND_APP"
}

# The requests in a run of lines, and the line the first one is on.
RANGE_COUNT=0
RANGE_FIRST=0
range_requests() {
  local from="$1" to="$2" i
  RANGE_COUNT=0
  RANGE_FIRST=0
  for ((i = from; i <= to; i++)); do
    case "${APP_LINES[$i]}" in
      *@http.*)
        if [ "$RANGE_FIRST" -eq 0 ]; then RANGE_FIRST=$((i + 1)); fi
        RANGE_COUNT=$((RANGE_COUNT + 1))
        ;;
    esac
  done
}

# The message a run of lines answers with.
BLOCK_MESSAGE=""
EMIT_RE='emit\.map\(fn\(result\) \{ ([A-Za-z_][A-Za-z0-9_]*)\(result\) \}\)'
block_message() {
  local from="$1" to="$2" i
  BLOCK_MESSAGE=""
  for ((i = from; i <= to; i++)); do
    if [[ "${APP_LINES[$i]}" =~ $EMIT_RE ]]; then
      BLOCK_MESSAGE="${BASH_REMATCH[1]}"
      return
    fi
  done
}

# The start-up chain: how many requests it makes, and the line the first one
# is on.
startup_chain() {
  local i start=-1 end=-1 msg next seen="" count=0 a b
  STARTUP_COUNT=0
  STARTUP_LINE=0
  for i in "${!APP_LINES[@]}"; do
    if [ "$start" -lt 0 ]; then
      case "${APP_LINES[$i]}" in
        "init=fn(emit) {"*) start=$i ;;
      esac
      continue
    fi
    if [ "${APP_LINES[$i]}" = "}," ]; then end=$i; break; fi
  done
  if [ "$start" -lt 0 ] || [ "$end" -lt 0 ]; then return; fi
  range_requests "$start" "$end"
  count=$RANGE_COUNT
  STARTUP_LINE=$RANGE_FIRST
  block_message "$start" "$end"
  msg="$BLOCK_MESSAGE"
  while [ -n "$msg" ]; do
    case " $seen " in
      *" $msg "*) break ;;
    esac
    seen="$seen $msg"
    a=-1
    b=-1
    for i in "${!APP_LINES[@]}"; do
      if [ "$a" -lt 0 ]; then
        case "${APP_LINES[$i]}" in
          "$msg(Ok("*) a=$i ;;
        esac
        continue
      fi
      case "${APP_LINES[$i]}" in
        "$msg(Err("*) b=$i; break ;;
      esac
    done
    if [ "$a" -lt 0 ] || [ "$b" -lt 0 ]; then break; fi
    range_requests "$a" "$b"
    count=$((count + RANGE_COUNT))
    block_message "$a" "$b"
    next="$BLOCK_MESSAGE"
    [ -n "$next" ] || break
    msg="$next"
  done
  STARTUP_COUNT=$count
}

# The number a word states.
number_value() {
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
    *) echo "$1" ;;
  esac
}

# One claim, checked against the start-up chain.
startup_claim_check() {
  local doc="$1" line="$2" claim="$3" lower n
  lower="${claim,,}"
  # the count the claim states
  if [[ "$lower" =~ start-?up ]] && [[ "$lower" =~ $COUNT_RE ]]; then
    n=$(number_value "${BASH_REMATCH[1]}")
    STARTUP_CHECKED=$((STARTUP_CHECKED + 1))
    if [ "$n" -ne "$STARTUP_COUNT" ]; then
      fail "$(printf '%-22s %s line %s says %s requests at start-up, but the tree makes %s' \
        'startup fetch' "$doc" "$line" "$n" "$STARTUP_COUNT")"
      STARTUP_BAD=1
    fi
    return
  fi
  # a claim that names the start-up request is pointing at it
  case "$claim" in
    *"/api/bootstrap"*) ;;
    *) return ;;
  esac
  case "$lower" in
    *startup*|*start-up*|*"start()"*) ;;
    *) return ;;
  esac
  cite_source "$claim"
  [ -n "$CITE_FILE" ] || return
  [ "$CITE_FILE" = "$FRONTEND_APP" ] || return
  STARTUP_CHECKED=$((STARTUP_CHECKED + 1))
  citation_covers "$CITE_SPEC" "$STARTUP_LINE"
  if [ "$CITATION_COVERS" -eq 0 ]; then
    fail "$(printf '%-22s %s line %s cites %s:%s, but the tree asks for the bootstrap on line %s' \
      'startup fetch' "$doc" "$line" "$CITE_FILE" "$CITE_SPEC" "$STARTUP_LINE")"
    STARTUP_BAD=1
  fi
}

# Every claim the documents make, checked against the start-up chain.
check_startup_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      startup_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

app_lines
startup_chain
check_startup_claims

if [ "$STARTUP_BAD" -eq 0 ]; then
  ok "startup fetch" "$STARTUP_CHECKED claims"
fi

# --- the blast radius a change has ---------------------------------------------
#
# The dependency document says, for each file, how far a change to it
# reaches. The **Blast radius** line names the packages; the table below it
# names the files. The two are one claim at two levels, and the line has to
# be the packages the table reaches.
#
# The package a file is in is its directory, when that directory is a
# package of the tree. A file that is in no package -- a mutation script, a
# tool -- names no package, so it does not widen the radius.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

BLAST_BAD=0
BLAST_CHECKED=0

# The sections of the dependency document: the line, the file, the blast
# radius it states and the files it lists.
BLAST_SECTIONS=""
blast_sections() {
  awk '
    function flush() {
      if (file != "") {
        printf "%d\t%s\t%s\t%s\n", line, file, stated, files
      }
      file = ""
      stated = ""
      files = ""
    }
    /^### If you change / {
      flush()
      file = $0
      sub(/^### If you change `/, "", file)
      sub(/`.*$/, "", file)
      line = NR
      next
    }
    /^\*\*Blast radius\*\*/ {
      stated = $0
      sub(/^\*\*Blast radius\*\*:[[:space:]]*/, "", stated)
      next
    }
    /^\|/ {
      if (file == "") { next }
      cell = $0
      sub(/^\|/, "", cell)
      sub(/\|.*$/, "", cell)
      gsub(/[ `]/, "", cell)
      if (cell == "" || cell == "Affected") { in_table = 1; next }
      if (cell ~ /^-+$/) { in_table = 1; next }
      if (in_table != 1) { next }
      files = files " " cell
      next
    }
    /^[[:space:]]*$/ { next }
    { in_table = 0 }
    END { flush() }
  ' "$DEPS_MD"
}

# The package a file is in, when it is in one.
FILE_PACKAGE=""
file_package() {
  local file="$1" dir
  FILE_PACKAGE=""
  case "$file" in
    */*) dir="${file%/*}" ;;
    *) return ;;
  esac
  case " $CODE_PKGS " in
    *" $dir "*) FILE_PACKAGE="$dir" ;;
  esac
}

# The packages the blast radius names. The note in brackets is not a
# package, and neither is the word "only".
STATED_PACKAGES=""
stated_packages() {
  local cell="$1" rest item out=""
  STATED_PACKAGES=""
  rest="$cell"
  case "$rest" in
    *\(*) rest="${rest%%(*}" ;;
  esac
  while [ -n "$rest" ]; do
    case "$rest" in
      *,*) item="${rest%%,*}"; rest="${rest#*,}" ;;
      *) item="$rest"; rest="" ;;
    esac
    trim "$item"; item="$TRIMMED"
    case "$item" in
      only) continue ;;
      *\ only) item="${item% only}" ;;
    esac
    [ -n "$item" ] || continue
    out="$out $item"
  done
  trim "$out"; STATED_PACKAGES="$TRIMMED"
}

# One section, checked against the files it lists.
blast_section_check() {
  local doc="$1" line="$2" file="$3" stated="$4" files="$5"
  local expected="" said name
  file_package "$file"
  expected="$FILE_PACKAGE"
  for name in $files; do
    file_package "$name"
    [ -n "$FILE_PACKAGE" ] || continue
    expected="$expected $FILE_PACKAGE"
  done
  sorted_set "$expected"; expected="$SORTED_SET"
  stated_packages "$stated"
  sorted_set "$STATED_PACKAGES"; said="$SORTED_SET"
  BLAST_CHECKED=$((BLAST_CHECKED + 1))
  if [ "$expected" != "$said" ]; then
    fail "$(printf '%-22s %s line %s says the blast radius of %s is [%s], but the files it lists reach [%s]' \
      'blast radius' "$doc" "$line" "$file" "$said" "$expected")"
    BLAST_BAD=1
  fi
}

# Every section, checked against the files it lists.
check_blast_sections() {
  local row line file stated files
  code_packages
  while IFS=$'\t' read -r line file stated files; do
    [ -n "$line" ] || continue
    blast_section_check "$DEPS_MD" "$line" "$file" "$stated" "$files"
  done <<< "$(blast_sections)"
}

check_blast_sections

if [ "$BLAST_BAD" -eq 0 ]; then
  ok "blast radius" "$BLAST_CHECKED sections"
fi

# --- the pages the client keeps in memory -------------------------------------
#
# The pages reach the client in one response -- the bootstrap -- and the model
# keeps them from there on: a route change is a lookup in the model, not a
# request. A document that says the pages are in memory is pointing at the
# line where they enter the model, so that is the line it has to cite.
#
# The other half is the tree. The client must not ask for the pages a second
# time. The search is on the CODE, not on the comments: the comment that
# explains why the bootstrap is used instead of /api/pages names the path
# without fetching it.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

PAGE_BAD=0
PAGE_CHECKED=0
PAGES_LINE=0
PAGES_COUNT=0
PAGES_FETCH_FILE=""
PAGES_FETCH_LINE=0

# A claim that says the pages are in memory, or that they are never fetched
# again.
PAGE_CLAIM_RE='page.*(in[[:space:]-]+memory|no[[:space:]]+second[[:space:]]+fetch|not[[:space:]]+a[[:space:]]+fetch)'

# The lines the tree loads the pages on.
pages_lines() {
  local line n=0
  PAGES_LINE=0
  PAGES_COUNT=0
  while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in
      *"pages: decode_pages("*)
        PAGES_COUNT=$((PAGES_COUNT + 1))
        if [ "$PAGES_COUNT" -eq 1 ]; then PAGES_LINE=$n; fi
        ;;
    esac
  done < "$FRONTEND_APP"
}

# The client file that asks for the pages, and the line it asks on.
pages_fetch() {
  local file line code n
  PAGES_FETCH_FILE=""
  PAGES_FETCH_LINE=0
  for file in $(git ls-files '*.mbt' 2>/dev/null); do
    case "$file" in
      frontend/*) ;;
      *) continue ;;
    esac
    case "$file" in *_test.mbt|*_wbtest.mbt) continue ;; esac
    n=0
    while IFS= read -r line; do
      n=$((n + 1))
      code_of "$line"
      code="$CODE"
      case "$code" in
        *"/api/pages"*)
          PAGES_FETCH_FILE="$file"
          PAGES_FETCH_LINE=$n
          return
          ;;
      esac
    done < "$file"
  done
}

# One claim, checked against the tree.
page_claim_check() {
  local doc="$1" line="$2" claim="$3" lower
  lower="${claim,,}"
  if [[ ! "$lower" =~ $PAGE_CLAIM_RE ]]; then return; fi
  PAGE_CHECKED=$((PAGE_CHECKED + 1))
  # the pages are loaded once
  if [ "$PAGES_COUNT" -ne 1 ]; then
    fail "$(printf '%-22s %s line %s says the pages are in memory, but the tree loads them on %s lines' \
      'page load' "$doc" "$line" "$PAGES_COUNT")"
    PAGE_BAD=1
  fi
  # the claim points at the line the pages enter the model on
  cite_source "$claim"
  if [ -n "$CITE_FILE" ]; then
    if [ "$CITE_FILE" != "$FRONTEND_APP" ]; then
      fail "$(printf '%-22s %s line %s cites %s, but the tree puts the pages in the model in %s' \
        'page load' "$doc" "$line" "$CITE_FILE" "$FRONTEND_APP")"
      PAGE_BAD=1
    else
      citation_covers "$CITE_SPEC" "$PAGES_LINE"
      if [ "$CITATION_COVERS" -eq 0 ]; then
        fail "$(printf '%-22s %s line %s cites %s:%s, but the tree puts the pages in the model on line %s' \
          'page load' "$doc" "$line" "$CITE_FILE" "$CITE_SPEC" "$PAGES_LINE")"
        PAGE_BAD=1
      fi
    fi
  fi
  # the client does not ask for the pages a second time
  if [ -n "$PAGES_FETCH_FILE" ]; then
    fail "$(printf '%-22s %s line %s says the pages are never fetched again, but %s fetches them on line %s' \
      'page load' "$doc" "$line" "$PAGES_FETCH_FILE" "$PAGES_FETCH_LINE")"
    PAGE_BAD=1
  fi
}

# Every claim the documents make, checked against the tree.
check_page_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      page_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

pages_lines
pages_fetch
check_page_claims

if [ "$PAGE_BAD" -eq 0 ]; then
  ok "page load" "$PAGE_CHECKED claims"
fi

# --- the literals a claim points at --------------------------------------------
#
# A claim that quotes a literal in backticks is pointing at it. When that
# literal occurs exactly once in the code of the file the claim cites, there
# is only one line it can mean, and the citation has to name that line.
#
# The search is on the CODE, not on the comments: a comment that names the
# literal is a mention of it, not the place it is used.
#
# A literal that occurs in the code more than once is left alone. A row that
# quotes "measure" cannot say which of the eight places it meant, and a gate
# that guesses is worse than no gate at all.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

LITERAL_BAD=0
LITERAL_CHECKED=0

# A backticked token.
LIT_RE='`([^`]+)`'

# The code of a line, with the comment cut away. The quotes stay: a literal
# the document quotes is compared as it is written.
CODE_TEXT=""
code_text() {
  CODE_TEXT="${1%%//*}"
}

# The code lines of a file, read once and kept: the file name is the key.
CODE_FILE=""
CODE_LINES=()
code_lines_of() {
  local file="$1" line
  if [ "$CODE_FILE" = "$file" ]; then return; fi
  CODE_FILE="$file"
  CODE_LINES=()
  [ -f "$file" ] || return
  while IFS= read -r line; do
    code_text "$line"
    CODE_LINES+=("$CODE_TEXT")
  done < "$file"
}

# The one code line of the file that is loaded where a literal occurs, or zero
# when the literal occurs nowhere, or in more than one place.
UNIQUE_LINE=0
unique_code_line() {
  local lit="$1" line i count=0
  UNIQUE_LINE=0
  for ((i = 0; i < ${#CODE_LINES[@]}; i++)); do
    line="${CODE_LINES[$i]}"
    case "$line" in
      *"$lit"*) count=$((count + 1)); UNIQUE_LINE=$((i + 1)) ;;
    esac
    if [ "$count" -gt 1 ]; then UNIQUE_LINE=0; return; fi
  done
  if [ "$count" -ne 1 ]; then UNIQUE_LINE=0; fi
}

# The citations of a claim: "file|spec" entries, each one ended by a ";".
CLAIM_CITES=""
claim_cites() {
  local claim="$1" rest="$1" tok
  CLAIM_CITES=""
  while [[ "$rest" =~ $LIT_RE ]]; do
    tok="${BASH_REMATCH[1]}"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    case "$tok" in
      *.mbt:[0-9]*) CLAIM_CITES="$CLAIM_CITES;${tok%%:*}|${tok#*:};" ;;
    esac
  done
}

# One claim, checked against the literals it quotes.
literal_claim_check() {
  local doc="$1" line="$2" claim="$3" c entry file spec rest tok
  claim_cites "$claim"
  [ -n "$CLAIM_CITES" ] || return
  c="$CLAIM_CITES"
  while [ -n "$c" ]; do
    entry="${c%%;*}"
    c="${c#*;}"
    [ -n "$entry" ] || continue
    file="${entry%%|*}"
    spec="${entry#*|}"
    code_lines_of "$file"
    [ "${#CODE_LINES[@]}" -gt 0 ] || continue
    rest="$claim"
    while [[ "$rest" =~ $LIT_RE ]]; do
      tok="${BASH_REMATCH[1]}"
      rest="${rest#*"${BASH_REMATCH[0]}"}"
      case "$tok" in
        *.mbt:[0-9]*) continue ;;
      esac
      unique_code_line "$tok"
      [ "$UNIQUE_LINE" -gt 0 ] || continue
      LITERAL_CHECKED=$((LITERAL_CHECKED + 1))
      citation_covers "$spec" "$UNIQUE_LINE"
      if [ "$CITATION_COVERS" -eq 0 ]; then
        fail "$(printf '%-22s %s line %s cites %s:%s, but %s is on line %s' \
          'literal pointer' "$doc" "$line" "$file" "$spec" "$tok" "$UNIQUE_LINE")"
        LITERAL_BAD=1
      fi
    done
  done
}

# Every claim the documents make, checked against the literals they quote.
check_literal_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      literal_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

check_literal_claims

if [ "$LITERAL_BAD" -eq 0 ]; then
  ok "literal pointer" "$LITERAL_CHECKED literals"
fi

# --- the pointers into the tree's build and deployment files --------------------
#
# A claim that quotes a literal and points at a line of the tree has to point
# at the line that holds the literal. The literal pointer gate above already
# does this for the MoonBit sources. The build and the deployment live in
# files that are not MoonBit: the Dockerfile, build.ps1, the workflows, the
# test scripts. Neither pointer gate looked there, because both of them filter
# their citations on "*.mbt:".
#
# The measurement that found the gap: the row that says the native build
# output is `_build/native/release/build/cmd/server/server` pointed at
# tools/contract-test.sh:100, and the row that says the js build output is
# `_build/js/release/build/cmd/web/web.js` pointed at build.ps1:26. When
# those pointers were moved one line off, and when the image's health check
# pointer was moved off the Dockerfile's HEALTHCHECK line, nothing in the
# suite noticed: every gate was green and the suite still said that every
# claim in the documents matches the tree.
#
# The rule is the literal pointer rule, applied to the other half of the
# tree. The literal has to be at the cited line, and it has to be a whole
# path: "server" is not inside "server.exe". A literal that names a file of
# the tree names that file rather than quoting what is in it, so it is left
# alone.

BUILD_PTR_BAD=0
BUILD_PTR_CHECKED=0

# The names of the files in the tree.
TREE_FILE_NAMES=""
tree_file_names() {
  local f
  TREE_FILE_NAMES=""
  for f in $(git ls-files 2>/dev/null); do
    TREE_FILE_NAMES="$TREE_FILE_NAMES ${f##*/}"
  done
  trim "$TREE_FILE_NAMES"; TREE_FILE_NAMES="$TRIMMED"
}

# The lines of a file where a literal sits as a whole path.
BUILD_LIT_LINES=()
build_literal_lines() {
  local lit="$1" file="$2" i line before after
  BUILD_LIT_LINES=()
  code_lines_of "$file"
  for ((i = 0; i < ${#CODE_LINES[@]}; i++)); do
    line="${CODE_LINES[$i]}"
    case "$line" in
      *"$lit"*) ;;
      *) continue ;;
    esac
    before="${line%%"$lit"*}"
    after="${line#*"$lit"}"
    case "$before" in
      *[A-Za-z0-9_./-]) continue ;;
    esac
    case "$after" in
      [A-Za-z0-9_./-]*) continue ;;
    esac
    BUILD_LIT_LINES+=("$((i + 1))")
  done
}

# One claim, checked against the tree's non-MoonBit files.
build_pointer_claim() {
  local doc="$1" line="$2" claim="$3"
  local rest="$3" tok file spec lit a covered i j
  local cites=() lits=()
  while [[ "$rest" =~ $LIT_RE ]]; do
    tok="${BASH_REMATCH[1]}"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    if [[ "$tok" =~ ^[A-Za-z0-9_./-]+:[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]]; then
      file="${tok%%:*}"
      spec="${tok#*:}"
      case "$file" in
        *.mbt) continue ;;
      esac
      [ -f "$file" ] || continue
      cites+=("$file" "$spec")
      continue
    fi
    lits+=("$tok")
  done
  [ "${#cites[@]}" -gt 0 ] || return
  [ "${#lits[@]}" -gt 0 ] || return
  for ((i = 0; i < ${#cites[@]}; i += 2)); do
    file="${cites[$i]}"
    spec="${cites[$((i + 1))]}"
    for ((j = 0; j < ${#lits[@]}; j++)); do
      lit="${lits[$j]}"
      case " $TREE_FILE_NAMES " in
        *" $lit "*) continue ;;
      esac
      build_literal_lines "$lit" "$file"
      [ "${#BUILD_LIT_LINES[@]}" -gt 0 ] || continue
      # a literal that sits in more than one place is left alone: the claim
      # does not say which place it meant
      [ "${#BUILD_LIT_LINES[@]}" -eq 1 ] || continue
      BUILD_PTR_CHECKED=$((BUILD_PTR_CHECKED + 1))
      covered=0
      for a in "${BUILD_LIT_LINES[@]}"; do
        citation_covers "$spec" "$a"
        if [ "$CITATION_COVERS" -eq 1 ]; then
          covered=1
          break
        fi
      done
      if [ "$covered" -eq 0 ]; then
        fail "$(printf '%-22s %s line %s cites %s:%s, but %s is on line %s' \
          'build pointer' "$doc" "$line" "$file" "$spec" "$lit" "${BUILD_LIT_LINES[0]}")"
        BUILD_PTR_BAD=1
      fi
    done
  done
}

tree_file_names
for doc in "${ARCH_DOCS[@]}"; do
  not_in "$doc" "$MARKED_DOCS"
  [ -n "$NOT_IN" ] || continue
  doc_claims "$doc"
  while IFS=$'\t' read -r line claim; do
    [ -n "$claim" ] || continue
    build_pointer_claim "$doc" "$line" "$claim"
  done <<< "$DOC_CLAIMS"
done

if [ "$BUILD_PTR_BAD" -eq 0 ]; then
  ok "build pointer" "$BUILD_PTR_CHECKED pointers"
fi

# --- the numbers the flow evidence states -------------------------------------
#
# The evidence table gives every step of the flow a source, and four of its
# numbers are claims about the tree: how many pages seed_pages() returns, how
# many domains the ring holds, how many fields the Page struct has, and the
# number a function falls back to when its input cannot be read. None of them
# was checked. The other documents state the same counts and are checked
# there -- this table was the one place a reader could be handed a number the
# tree does not have.
#
# The fallback is not a count, so it is checked where it lives: the row cites
# the lines of the function, and those lines have to hold the catch that falls
# back to the number the row names. A row that cites the wrong lines sends a
# reader to a catch that is not there.

FLOWS_EVIDENCE="architecture/flows.evidence.md"

check_claim_number "flow evidence pages" '([0-9]+) seeded pages' \
  "$(count_seed_pages_only)" "$FLOWS_EVIDENCE"

check_claim_number "flow evidence ring" '([0-9]+) ring' \
  "$(count_ring_domains)" "$FLOWS_EVIDENCE"

check_claim_number "flow evidence fields" 'all ([0-9]+) fields' \
  "$(count_page_fields)" "$FLOWS_EVIDENCE"

FALLBACK_VALUE_BAD=0
FALLBACK_VALUE_CHECKED=0
FALLBACK_VALUE_RE='defaults to ([0-9]+) on invalid input'

# The catch that falls back to a number, on the lines a claim cites.
cited_fallback_value() {
  local file="$1" spec="$2" number="$3" i re found=0
  re='catch[^0-9]*'"${number}"'([^0-9]|$)'
  code_lines_of "$file"
  for i in "${!CODE_LINES[@]}"; do
    citation_covers "$spec" "$((i + 1))"
    [ "$CITATION_COVERS" -eq 1 ] || continue
    if [[ "${CODE_LINES[$i]}" =~ $re ]]; then
      found=1
      break
    fi
  done
  [ "$found" -eq 1 ]
}

# One claim, checked against the fallback the tree has.
fallback_value_claim() {
  local doc="$1" line="$2" claim="$3" number
  [[ "$claim" =~ $FALLBACK_VALUE_RE ]] || return
  number="${BASH_REMATCH[1]}"
  cite_source "$claim"
  [ -n "$CITE_FILE" ] || return
  [ -f "$CITE_FILE" ] || return
  FALLBACK_VALUE_CHECKED=$((FALLBACK_VALUE_CHECKED + 1))
  if ! cited_fallback_value "$CITE_FILE" "$CITE_SPEC" "$number"; then
    fail "$(printf '%-22s %s line %s says the default is %s, but %s:%s has no fallback to it' \
      'fallback value' "$doc" "$line" "$number" "$CITE_FILE" "$CITE_SPEC")"
    FALLBACK_VALUE_BAD=1
  fi
}

for doc in "${ARCH_DOCS[@]}"; do
  not_in "$doc" "$MARKED_DOCS"
  [ -n "$NOT_IN" ] || continue
  doc_claims "$doc"
  while IFS=$'\t' read -r line claim; do
    [ -n "$claim" ] || continue
    fallback_value_claim "$doc" "$line" "$claim"
  done <<< "$DOC_CLAIMS"
done

if [ "$FALLBACK_VALUE_BAD" -eq 0 ]; then
  ok "fallback value" "$FALLBACK_VALUE_CHECKED claims"
fi

# --- the tables the schema has ------------------------------------------------
#
# The schema is a claim about the tree: the tables migrate() creates. The
# documents state it in two places -- the list in the flow, and the rows of
# the evidence table -- and both have to be the tree's list.
#
# The tables are read out of the code: every "CREATE TABLE IF NOT EXISTS
# <name>" in the database file is a table the server makes on every start.
#
# A claim that lists the tables has to list all of them: a list one table
# short sends a reader looking for a table that is not there. A name the
# schema states has to be a table the tree makes, and every table the tree
# makes has to be named somewhere.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

SCHEMA_BAD=0
SCHEMA_CHECKED=0
SCHEMA_TABLES=""
SCHEMA_NAMED=""

# A name that could be a table: lower case, no dots.
NAME_RE='^[a-z][a-z0-9_]*$'

# The tables the tree creates.
code_schema_tables() {
  local line name
  SCHEMA_TABLES=""
  while IFS= read -r line; do
    case "$line" in
      *"CREATE TABLE IF NOT EXISTS "*) ;;
      *) continue ;;
    esac
    name="${line#*CREATE TABLE IF NOT EXISTS }"
    name="${name%%(*}"
    trim "$name"; name="$TRIMMED"
    [[ "$name" =~ $NAME_RE ]] || continue
    SCHEMA_TABLES="$SCHEMA_TABLES $name"
  done < backend/database.mbt
  trim "$SCHEMA_TABLES"; SCHEMA_TABLES="$TRIMMED"
}

# The tables a claim lists after "CREATE TABLE IF NOT EXISTS (".
SCHEMA_LIST=""
schema_list() {
  local claim="$1" rest
  SCHEMA_LIST=""
  case "$claim" in
    *"CREATE TABLE IF NOT EXISTS ("*) ;;
    *) return ;;
  esac
  rest="${claim#*CREATE TABLE IF NOT EXISTS (}"
  rest="${rest%%)*}"
  SCHEMA_LIST="$rest"
}

# The table names a claim states: the lower case names it backticks.
SCHEMA_NAMES=""
schema_names() {
  local claim="$1" rest="$1" tok
  SCHEMA_NAMES=""
  while [[ "$rest" =~ $LIT_RE ]]; do
    tok="${BASH_REMATCH[1]}"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    if [[ "$tok" =~ $NAME_RE ]]; then
      SCHEMA_NAMES="$SCHEMA_NAMES $tok"
    fi
  done
}

# One claim, checked against the tables the tree creates.
schema_claim_check() {
  local doc="$1" line="$2" claim="$3" stated listed name
  # a claim that lists the tables the schema has
  schema_list "$claim"
  if [ -n "$SCHEMA_LIST" ]; then
    SCHEMA_CHECKED=$((SCHEMA_CHECKED + 1))
    stated="${SCHEMA_LIST//,/ }"
    for name in $stated; do
      SCHEMA_NAMED="$SCHEMA_NAMED $name"
    done
    sorted_set "$stated"; stated="$SORTED_SET"
    sorted_set "$SCHEMA_TABLES"; listed="$SORTED_SET"
    if [ "$stated" != "$listed" ]; then
      fail "$(printf '%-22s %s line %s says the schema has [%s], the tree creates [%s]' \
        'schema tables' "$doc" "$line" "$stated" "$listed")"
      SCHEMA_BAD=1
    fi
    return
  fi
  # a claim that states the schema
  case "${claim,,}" in
    *schema*) ;;
    *) return ;;
  esac
  schema_names "$claim"
  [ -n "$SCHEMA_NAMES" ] || return
  SCHEMA_CHECKED=$((SCHEMA_CHECKED + 1))
  for name in $SCHEMA_NAMES; do
    SCHEMA_NAMED="$SCHEMA_NAMED $name"
    case " $SCHEMA_TABLES " in
      *" $name "*) ;;
      *)
        fail "$(printf '%-22s %s line %s names the table %s, the tree has no such table' \
          'schema tables' "$doc" "$line" "$name")"
        SCHEMA_BAD=1
        ;;
    esac
  done
}

# Every claim the documents make, checked against the tables the tree creates.
check_schema_claims() {
  local doc line claim name missing=""
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      schema_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
  # every table the tree creates has to be named by a document
  for name in $SCHEMA_TABLES; do
    case " $SCHEMA_NAMED " in
      *" $name "*) ;;
      *) missing="$missing $name" ;;
    esac
  done
  if [ -n "$missing" ]; then
    trim "$missing"; missing="$TRIMMED"
    fail "$(printf '%-22s the tree creates [%s], and no document names it' \
      'schema tables' "$missing")"
    SCHEMA_BAD=1
  fi
}

code_schema_tables
check_schema_claims

if [ "$SCHEMA_BAD" -eq 0 ]; then
  ok "schema tables" "$SCHEMA_CHECKED claims"
fi

# --- the middleware the backend adds -------------------------------------------
#
# The backend has a chain of its own, and the documents say what is in it in
# three places: the evidence row that names the middleware, the flow that
# shows it being added, and the summary of the assembly.
#
# A claim that names one of the backend's middlewares is stating the chain,
# and the chain has to be the tree's: a middleware added to the backend
# makes every such claim one middleware short.
#
# The chain is read out of the code: every "add_middleware(<name>(" in the
# backend is a middleware the app puts in front of its handlers.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

BACKEND_BAD=0
BACKEND_CHECKED=0
BACKEND_CHAIN=""
BACKEND_LINE=0
BACKEND_FILE=""

# The middlewares the backend adds, in the order it adds them.
code_backend_chain() {
  local file line name n
  BACKEND_CHAIN=""
  BACKEND_LINE=0
  BACKEND_FILE=""
  for file in $(git ls-files 'backend/*.mbt' 2>/dev/null); do
    case "$file" in *_test.mbt|*_wbtest.mbt) continue ;; esac
    n=0
    while IFS= read -r line; do
      n=$((n + 1))
      case "$line" in
        *"add_middleware("*) ;;
        *) continue ;;
      esac
      name="${line#*add_middleware(}"
      name="${name%%(*}"
      trim "$name"; name="$TRIMMED"
      [[ "$name" =~ ^[a-z][a-z0-9_]*$ ]] || continue
      BACKEND_CHAIN="$BACKEND_CHAIN $name"
      if [ "$BACKEND_LINE" -eq 0 ]; then
        BACKEND_LINE=$n
        BACKEND_FILE="$file"
      fi
    done < "$file"
  done
  trim "$BACKEND_CHAIN"; BACKEND_CHAIN="$TRIMMED"
}

# The chain a claim names, in the order the claim names it.
#
# A middleware can be written with the underscore or with a space -- the
# documents use both -- so both are looked for, and the place the claim
# first says it is the place it counts.
BACKEND_NAMED=""
backend_named() {
  local claim="$1" name alt prefix pos p2 pairs=""
  BACKEND_NAMED=""
  for name in $BACKEND_CHAIN; do
    alt="${name//_/ }"
    pos=""
    case "$claim" in
      *"$name"*)
        prefix="${claim%%"$name"*}"
        pos="${#prefix}"
        ;;
    esac
    case "$claim" in
      *"$alt"*)
        prefix="${claim%%"$alt"*}"
        p2="${#prefix}"
        if [ -z "$pos" ] || [ "$p2" -lt "$pos" ]; then pos="$p2"; fi
        ;;
    esac
    [ -n "$pos" ] || continue
    pairs="$pairs$(printf '%010d %s\n' "$pos" "$name")"
  done
  # nothing named, nothing to sort: a fork per claim is a fork too many
  [ -n "$pairs" ] || return
  BACKEND_NAMED=$(printf '%s' "$pairs" | sort -n | cut -d' ' -f2- | tr '\n' ' ' | sed -e 's/ *$//')
}

# The middleware a claim says is the only one.
ONLY_MIDDLEWARE=""
ONLY_MIDDLEWARE_RE='([a-z][a-z0-9_]*)[[:space:]]+is[[:space:]]+the[[:space:]]+only[[:space:]]+middleware'
only_middleware() {
  local claim="$1"
  ONLY_MIDDLEWARE=""
  if [[ "$claim" =~ $ONLY_MIDDLEWARE_RE ]]; then
    ONLY_MIDDLEWARE="${BASH_REMATCH[1]}"
  fi
}

# One claim, checked against the chain the backend builds.
backend_claim_check() {
  local doc="$1" line="$2" claim="$3" named checked=0
  # a claim that says a middleware is the only one
  only_middleware "$claim"
  if [ -n "$ONLY_MIDDLEWARE" ]; then
    checked=1
    if [ "$BACKEND_CHAIN" != "$ONLY_MIDDLEWARE" ]; then
      fail "$(printf '%-22s %s line %s says %s is the only middleware, the tree adds [%s]' \
        'backend chain' "$doc" "$line" "$ONLY_MIDDLEWARE" "$BACKEND_CHAIN")"
      BACKEND_BAD=1
    fi
  fi
  # a claim that names one of the backend's middlewares
  backend_named "$claim"
  if [ -n "$BACKEND_NAMED" ]; then
    checked=1
    named="$BACKEND_NAMED"
    if [ "$named" != "$BACKEND_CHAIN" ]; then
      fail "$(printf '%-22s %s line %s names [%s], the tree adds [%s]' \
        'backend chain' "$doc" "$line" "$named" "$BACKEND_CHAIN")"
      BACKEND_BAD=1
    fi
  fi
  BACKEND_CHECKED=$((BACKEND_CHECKED + checked))
}

# Every claim the documents make, checked against the backend's chain.
check_backend_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      backend_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

code_backend_chain
check_backend_claims

if [ "$BACKEND_BAD" -eq 0 ]; then
  ok "backend chain" "$BACKEND_CHECKED claims"
fi

# --- the SQLite statement lifecycle ------------------------------------------
#
# The storage layer has a lifecycle of its own, and the documents state it in
# ten places: the risk note, the coupling table, the deployment topology and
# its graph, the dependency graph, the flow document, the flow evidence, the
# flow graph, and the model graph.
#
# The lifecycle is the tree's, and the tree states it twice:
#
#   * the storage layer's own header names the operations it promises -- that
#     prepare only compiles, that a statement has to be reset before it is
#     reused, that bind overwrites the bindings in place; and
#   * the code calls those operations on a prepared statement.
#
# The operations the header names AND the code calls are the lifecycle. The
# header names the public surface as well, and the public surface is not a
# lifecycle: it is the functions the storage layer publishes, and the gate
# reads those out of the code too.
#
# A claim that names more than half of the lifecycle is stating the lifecycle,
# and it has to state all of it: a claim that leaves one out sends a reader
# looking for a safeguard the list does not have.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

STMT_BAD=0
STMT_CHECKED=0
STMT_LIFECYCLE=""
STMT_VOCAB=""
STMT_THRESHOLD=0
STMT_DB="backend/database.mbt"
STMT_HEADER=""
STMT_PUBLIC=""
STMT_PREP_VARS=""
STMT_OTHER_VARS=""
STMT_VARS=""
STMT_OPS=""
STMT_NAMED=""

# The names the storage layer's header names.
#
# The header is the run of comment lines at the top of the file. A name in it
# is written between backticks, so the text is cut on the backticks and the
# pieces that are a single name are the names.
stmt_header_names() {
  local line text="" name
  STMT_HEADER=""
  while IFS= read -r line; do
    case "$line" in
      "///"*) ;;
      *) break ;;
    esac
    text="$text$line"$'\n'
  done < "$STMT_DB"
  while IFS= read -r name; do
    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    STMT_HEADER="$STMT_HEADER $name"
  done <<< "$(printf '%s' "$text" | grep -oE '`[^`]+`' | tr -d '`')"
  trim "$STMT_HEADER"; STMT_HEADER="$TRIMMED"
}

# The functions the storage layer publishes.
stmt_public_fns() {
  local line name
  STMT_PUBLIC=""
  while IFS= read -r line; do
    case "$line" in
      "pub fn "*"::"*) ;;
      *) continue ;;
    esac
    name="${line#*::}"
    name="${name%%(*}"
    trim "$name"; name="$TRIMMED"
    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    STMT_PUBLIC="$STMT_PUBLIC $name"
  done < "$STMT_DB"
  trim "$STMT_PUBLIC"; STMT_PUBLIC="$TRIMMED"
}

# The names a prepared statement is bound to.
#
# A name is a statement when it is bound by a prepare and never bound to
# anything else: the storage layer also has a "steps" that is a list of rows,
# and the calls on that one are not calls on a statement.
stmt_bindings() {
  local line name
  STMT_PREP_VARS=""
  STMT_OTHER_VARS=""
  while IFS= read -r line; do
    case "$line" in
      *"let "*) ;;
      *) continue ;;
    esac
    name="${line#*let }"
    case "$name" in
      [A-Za-z_]*" = "*) ;;
      *) continue ;;
    esac
    name="${name%% = *}"
    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    case "$line" in
      *".prepare("*) STMT_PREP_VARS="$STMT_PREP_VARS $name" ;;
      *) STMT_OTHER_VARS="$STMT_OTHER_VARS $name" ;;
    esac
  done < "$STMT_DB"
  STMT_VARS=""
  for name in $STMT_PREP_VARS; do
    case " $STMT_OTHER_VARS " in
      *" $name "*) continue ;;
    esac
    STMT_VARS="$STMT_VARS $name"
  done
  trim "$STMT_VARS"; STMT_VARS="$TRIMMED"
}

# The operations the code calls on a prepared statement.
stmt_ops() {
  local line name op rest
  STMT_OPS=""
  while IFS= read -r line; do
    for name in $STMT_VARS; do
      rest="$line"
      while [[ "$rest" =~ ([^A-Za-z0-9_]|^)${name}\.([a-z_][a-z0-9_]*)\( ]]; do
        op="${BASH_REMATCH[2]}"
        STMT_OPS="$STMT_OPS $op"
        rest="${rest#*"${BASH_REMATCH[0]}"}"
      done
    done
  done < "$STMT_DB"
  # the operation that makes the statement is one of them
  STMT_OPS="$STMT_OPS prepare"
}

# The lifecycle, and the words a claim may use to state it.
stmt_sets() {
  local name n=0
  stmt_header_names
  stmt_public_fns
  stmt_bindings
  stmt_ops
  STMT_LIFECYCLE=""
  STMT_VOCAB=""
  for name in $STMT_HEADER; do
    case " $STMT_PUBLIC " in
      *" $name "*) continue ;;
    esac
    STMT_VOCAB="$STMT_VOCAB $name"
    case " $STMT_OPS " in
      *" $name "*) STMT_LIFECYCLE="$STMT_LIFECYCLE $name" ;;
    esac
  done
  for name in $STMT_OPS; do
    case " $STMT_VOCAB " in
      *" $name "*) continue ;;
    esac
    STMT_VOCAB="$STMT_VOCAB $name"
  done
  sorted_set "$STMT_LIFECYCLE"; STMT_LIFECYCLE="$SORTED_SET"
  sorted_set "$STMT_VOCAB"; STMT_VOCAB="$SORTED_SET"
  # a claim that names more than half of the lifecycle is stating it
  for name in $STMT_LIFECYCLE; do n=$((n + 1)); done
  STMT_THRESHOLD=$((n / 2 + 1))
}

# The operations a claim names.
#
# A graph writes its line breaks as \n, \l and \r, and those are not letters:
# they are cut out of the claim before it is read, so that the operation
# after a break is still the operation.
stmt_named() {
  local claim="$1" op
  local low="${claim,,}"
  STMT_NAMED=""
  low="${low//\\n/ }"
  low="${low//\\l/ }"
  low="${low//\\r/ }"
  for op in $STMT_VOCAB; do
    if [[ "$low" =~ ([^A-Za-z0-9_]|^)${op}([^A-Za-z0-9_]|$) ]]; then
      STMT_NAMED="$STMT_NAMED $op"
    fi
  done
  trim "$STMT_NAMED"; STMT_NAMED="$TRIMMED"
}

# One claim, checked against the lifecycle the tree has.
stmt_claim_check() {
  local doc="$1" line="$2" claim="$3"
  local named life=0 op said tree
  stmt_named "$claim"
  named="$STMT_NAMED"
  [ -n "$named" ] || return
  for op in $STMT_LIFECYCLE; do
    case " $named " in
      *" $op "*) life=$((life + 1)) ;;
    esac
  done
  [ "$life" -ge "$STMT_THRESHOLD" ] || return
  STMT_CHECKED=$((STMT_CHECKED + 1))
  sorted_set "$named"; said="$SORTED_SET"
  tree="$STMT_LIFECYCLE"
  if [ "$said" != "$tree" ]; then
    fail "$(printf '%-22s %s line %s says the lifecycle is [%s], the tree'"'"'s is [%s]' \
      'stmt lifecycle' "$doc" "$line" "$said" "$tree")"
    STMT_BAD=1
  fi
}

# Every claim the documents make, checked against the lifecycle.
check_stmt_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      stmt_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

stmt_sets
check_stmt_claims

if [ "$STMT_BAD" -eq 0 ]; then
  ok "stmt lifecycle" "$STMT_CHECKED claims"
fi

# --- the names a claim quotes and the files it points at ------------------------
#
# A claim that points at a file and quotes a name is telling the reader that
# the name is in that file: "the body is inserted with `Attrs::inner_html`"
# points into the code, and a reader who follows the pointer has to find it
# there. A claim that quotes a name the file has never heard of is a pointer
# into the wrong place.
#
# The names are the tree's own. A name the tree does not have is not a name
# of the tree at all -- it is a word of prose, a route, a column -- and the
# claim that quotes it is left alone: the code names gate above is the one
# that says a quoted name has to be a name of the tree. The files that are
# pointed at have to know the name: a name of the tree, in files that say
# nothing about it, is a pointer into the wrong place.
#
# The names are read out of the claim cell and the files out of the pointers
# of the row, so that a file the row names is not mistaken for a name the
# row quotes.
#
# The measurement that found the gap: the row that lists the views of the
# frontend was pointed at a file that has no views in it, and every gate in
# the repository was green. The names were in plain words then, so no gate
# could read them; with the names quoted, this is the rule that notices.

CITED_NAME_BAD=0
CITED_NAME_CHECKED=0

# A pointer of any kind: a file and the lines of it.
CITE_ANY_RE='`([A-Za-z0-9_./@-]+):([0-9]+([,-][0-9]+)*)`'

# The files a claim points at.
CITED_FILES=""
cited_files() {
  local claim="$1" rest="$1" tok
  CITED_FILES=""
  while [[ "$rest" =~ $CITE_ANY_RE ]]; do
    tok="${BASH_REMATCH[1]}"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    CITED_FILES="$CITED_FILES ${tok%%:*}"
  done
}

# The claim cell of a row: the text between the first two bars.
CLAIM_CELL=""
claim_cell() {
  local row="$1" text
  text="${row#*|}"
  text="${text%%|*}"
  trim "$text"
  CLAIM_CELL="$TRIMMED"
}

# Whether a file says a name at all. The name is a plain word in the tree, so
# it is looked for as a word and not as a piece of a longer one: "param" is not
# inside "Request::param".
file_says_name() {
  local file="$1" name="$2"
  [ -f "$file" ] || return 1
  grep -qE "(^|[^A-Za-z0-9_])${name}([^A-Za-z0-9_]|\$)" "$file" 2>/dev/null
}

# One claim, checked against the names the files it points at know.
cited_name_claim_check() {
  local doc="$1" line="$2" row="$3" rest tok name files known file
  claim_cell "$row"
  cited_files "$row"
  [ -n "$CITED_FILES" ] || return
  files="$CITED_FILES"
  trim "$files"; files="$TRIMMED"
  rest="$CLAIM_CELL"
  while [[ "$rest" =~ $LIT_RE ]]; do
    tok="${BASH_REMATCH[1]}"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    name="${tok#@}"
    name="${name%%(*}"
    # a name the tree does not have is not a name of the tree
    if [ -z "${TREE_NAME["$name"]+yes}" ]; then
      continue
    fi
    CITED_NAME_CHECKED=$((CITED_NAME_CHECKED + 1))
    known=0
    for file in $files; do
      if file_says_name "$file" "$name"; then
        known=1
        break
      fi
    done
    if [ "$known" -eq 0 ]; then
      fail "$(printf '%-22s %s line %s names [%s] and points at [%s], and none of them says it' \
        'cited name' "$doc" "$line" "$name" "$files")"
      CITED_NAME_BAD=1
    fi
  done
}

# Every claim the design documents make, checked against the names they quote.
check_cited_name_claims() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      cited_name_claim_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

check_cited_name_claims

if [ "$CITED_NAME_BAD" -eq 0 ]; then
  ok "cited name" "$CITED_NAME_CHECKED names"
fi

# --- the symbols a blast radius says break -------------------------------------
#
# The dependency document says, for each file, which files a change to it
# reaches, and what breaks in them.  The impact caller gate above reads the
# same cell: it says the affected file has to USE the symbol the cell names.
#
# That gate is a substring test, and a substring test has two holes.  A file
# can hold the TEXT of a symbol that is no longer a symbol: the tree renames
# logo_mark to logo_mark_v2, the call site still says logo_mark, and the
# table is not corrected -- the text is still there.  And a row that names a
# file the tree does not have is skipped altogether, because the gate can
# only check the files it knows.
#
# This gate closes both.  A symbol the cell backticks has to be a symbol the
# tree DEFINES; it has to be one of the symbols of the row's own two files
# -- the file the section is about, or the file the row lists as affected;
# and the row's two files have to be files of the tree.
#
# The names are the tree's own: the functions, the types and the tables the
# tree defines.  A qualified name answers to its last segment, so `db.seed()`
# is the `seed` of `Database::seed`.  A token that is not a name -- the
# `?lang=` of a query string -- is not a claim about a symbol and is left
# alone.
#
# The bash twin says the same thing.  The two are twins: they print the same
# lines and they go red together.

BLAST_SYM_BAD=0
BLAST_SYM_CHECKED=0

# A name the tree can have: a plain name or a qualified one.
BLAST_SYM_RE='^[A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)?$'

# The name a token claims: no trailing (), no package or receiver prefix in
# front of the last dot.
BLAST_SYMBOL_NAME=""
blast_symbol_name() {
  local name="$1"
  trim "$name"; name="$TRIMMED"
  case "$name" in
    *\(\)) name="${name%\(\)}" ;;
  esac
  case "$name" in
    *.*) name="${name##*.}" ;;
  esac
  BLAST_SYMBOL_NAME="$name"
}

# The symbols the tree defines: the name, and the files that define it.
declare -A BLAST_SYMBOL=()

blast_symbol_add() {
  local name="$1" file="$2" tail list
  [ -n "$name" ] || return
  list="${BLAST_SYMBOL["$name"]:-}"
  case " $list " in
    *" $file "*) ;;
    *) BLAST_SYMBOL["$name"]="$list $file" ;;
  esac
  case "$name" in
    *::*)
      tail="${name##*::}"
      list="${BLAST_SYMBOL["$tail"]:-}"
      case " $list " in
        *" $file "*) ;;
        *) BLAST_SYMBOL["$tail"]="$list $file" ;;
      esac
      ;;
  esac
}

# The definitions a file holds: the names of its functions and of its types.
blast_symbol_defs() {
  awk '
    {
      line = $0
      sub(/^[[:blank:]]+/, "", line)
      if (match(line, /^(pub(\([a-z]+\))?[[:blank:]]+)?(async[[:blank:]]+)?fn[[:blank:]]+[A-Za-z_]/)) {
        tmp = line
        sub(/^[ \t]*(pub(\([a-z]+\))?[ \t]+)?(async[ \t]+)?fn[ \t]+/, "", tmp)
        split(tmp, parts, /[ \t(]/)
        print parts[1]
        next
      }
      if (match(line, /^(pub(\(all\))?[[:blank:]]+)?(type|struct|enum)[[:blank:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
        head = substr(line, 1, RLENGTH)
        if (match(head, /(type|struct|enum)[[:blank:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
          name = substr(head, RSTART, RLENGTH)
          sub(/^(type|struct|enum)[[:blank:]]+/, "", name)
          print name
        }
      }
    }
  ' "$1"
}

# The symbols the tree has, and the files that define them.
blast_symbols_load() {
  local file name
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    case "$file" in
      backend/*.mbt|frontend/*.mbt|cmd/*.mbt) ;;
      *) continue ;;
    esac
    [ -f "$file" ] || continue
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      blast_symbol_add "$name" "$file"
    done < <(blast_symbol_defs "$file")
  done < <(git ls-files 2>/dev/null || true)
  code_schema_tables
  for name in $SCHEMA_TABLES; do
    blast_symbol_add "$name" "backend/database.mbt"
  done
}

# The files a symbol is defined in, written the way a reader writes them.
blast_symbol_files_text() {
  local list="$1" out="" f
  for f in $list; do
    if [ -z "$out" ]; then out="$f"; else out="$out, $f"; fi
  done
  printf '%s' "$out"
}

# The rows of the blast tables: the section file, the affected file and the
# cell that says what breaks.  A section's blast table is the first table
# that follows its **Blast radius** line; the coupling table at the end of
# the document is not one.
blast_symbol_rows() {
  awk '
    /^### If you change / {
      file = $0
      sub(/^### If you change `/, "", file)
      sub(/`.*$/, "", file)
      radius = 0
      table = 0
      seen = 0
      next
    }
    /^\*\*Blast radius\*\*/ { radius = 1; next }
    /^\|/ {
      if (file == "" || radius == 0 || table == 2) next
      if (seen == 0) { seen = 1; table = 1; next }
      aff = $0
      sub(/^\|/, "", aff)
      sub(/\|.*$/, "", aff)
      gsub(/[ `]/, "", aff)
      if (aff == "") next
      if (aff ~ /^-+$/) next
      what = $0
      sub(/^\|[^|]*\|/, "", what)
      sub(/\|.*$/, "", what)
      printf "%d\t%s\t%s\t%s\n", NR, file, aff, what
      next
    }
    /^[[:space:]]*$/ { next }
    { table = 2; seen = 0 }
  ' "$DEPS_MD"
}

# One row of a blast table, checked against the tree.
blast_symbol_row_check() {
  local doc="$1" line="$2" section="$3" aff="$4" what="$5"
  local rest="$5" tok name files known
  if [ ! -f "$section" ]; then
    fail "$(printf '%-22s %s line %s is about %s, and the tree has no such file' \
      'blast symbol' "$doc" "$line" "$section")"
    BLAST_SYM_BAD=1
  fi
  if [ ! -f "$aff" ]; then
    fail "$(printf '%-22s %s line %s says %s breaks, and the tree has no such file' \
      'blast symbol' "$doc" "$line" "$aff")"
    BLAST_SYM_BAD=1
  fi
  rest="$what"
  while [[ "$rest" =~ $LIT_RE ]]; do
    tok="${BASH_REMATCH[1]}"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    blast_symbol_name "$tok"
    name="$BLAST_SYMBOL_NAME"
    [ -n "$name" ] || continue
    [[ "$name" =~ $BLAST_SYM_RE ]] || continue
    BLAST_SYM_CHECKED=$((BLAST_SYM_CHECKED + 1))
    files="${BLAST_SYMBOL["$name"]:-}"
    if [ -z "$files" ]; then
      fail "$(printf '%-22s %s line %s says [%s] breaks, and the tree defines no such symbol' \
        'blast symbol' "$doc" "$line" "$name")"
      BLAST_SYM_BAD=1
      continue
    fi
    known=0
    case " $files " in
      *" $section "*|*" $aff "*) known=1 ;;
    esac
    if [ "$known" -eq 0 ]; then
      fail "$(printf '%-22s %s line %s says [%s] breaks, and the tree defines it in %s' \
        'blast symbol' "$doc" "$line" "$name" "$(blast_symbol_files_text "$files")")"
      BLAST_SYM_BAD=1
    fi
  done
}

# Every row of every blast table, checked against the tree.
check_blast_symbols() {
  local line section aff what
  blast_symbols_load
  while IFS=$'\t' read -r line section aff what; do
    [ -n "$line" ] || continue
    blast_symbol_row_check "$DEPS_MD" "$line" "$section" "$aff" "$what"
  done <<< "$(blast_symbol_rows)"
}

check_blast_symbols

if [ "$BLAST_SYM_CHECKED" -eq 0 ]; then
  fail "$(printf '%-22s no blast table names a symbol at all' 'blast symbol')"
  BLAST_SYM_BAD=1
fi

if [ "$BLAST_SYM_BAD" -eq 0 ]; then
  ok "blast symbol" "$BLAST_SYM_CHECKED symbols"
fi

# --- the symbols a blast radius names in plain words ---------------------------
#
# The cell says what breaks in two ways: in backticks, and in plain words.
# "view() calls header, domain_cards, page_view, etc." -- the first is a
# symbol the gate above reads, and the second is prose with a name in it.  No
# gate read the plain words: the impact caller gate reads the backticked
# tokens of the row, and the blast symbol gate reads the backticked tokens
# of the cell.
#
# The filter is a SHAPE, not a vocabulary: a plain word that carries an
# underscore is a name the tree spells that way, and prose does not.  A plain
# word without an underscore -- header, navigation, nodes -- cannot be told
# apart from prose, and is left alone: a gate that needed a list of English
# words would be a gate that knew the answers.
#
# The rule: the tree has to define the name, and the row's affected file has
# to hold it.  A name the tree does not define is a claim about a tree that
# is not there; a name the affected file does not hold is a claim about a
# file that does not touch it.
#
# The bash twin says the same thing.  The two are twins: they print the same
# lines and they go red together.

BLAST_PLAIN_BAD=0
BLAST_PLAIN_CHECKED=0

# The plain words of a cell: the text between the backticked parts.
BLAST_PLAIN_TEXT=""
blast_plain_text() {
  local cell="$1"
  local -a parts=()
  local i out=""
  IFS='`' read -r -a parts <<< "$cell"
  for ((i = 0; i < ${#parts[@]}; i += 2)); do
    out="$out ${parts[i]}"
  done
  BLAST_PLAIN_TEXT="$out"
}

# One row of a blast table, checked against the tree.
blast_plain_row_check() {
  local doc="$1" line="$2" section="$3" aff="$4" what="$5"
  local word clean
  blast_plain_text "$what"
  for word in $BLAST_PLAIN_TEXT; do
    clean="${word//[^A-Za-z0-9_]/}"
    [[ "$clean" =~ ^[A-Za-z][A-Za-z0-9_]*_[A-Za-z0-9_]+$ ]] || continue
    BLAST_PLAIN_CHECKED=$((BLAST_PLAIN_CHECKED + 1))
    if [ -z "${BLAST_SYMBOL["$clean"]:-}" ]; then
      fail "$(printf '%-22s %s line %s says [%s] breaks, and the tree defines no such symbol' \
        'blast plain symbol' "$doc" "$line" "$clean")"
      BLAST_PLAIN_BAD=1
      continue
    fi
    if ! file_says_name "$aff" "$clean"; then
      fail "$(printf '%-22s %s line %s says [%s] breaks in %s, and that file does not hold it' \
        'blast plain symbol' "$doc" "$line" "$clean" "$aff")"
      BLAST_PLAIN_BAD=1
    fi
  done
}

# Every row of every blast table, checked against the tree.
check_blast_plain_symbols() {
  local line section aff what
  blast_symbols_load
  while IFS=$'\t' read -r line section aff what; do
    [ -n "$line" ] || continue
    blast_plain_row_check "$DEPS_MD" "$line" "$section" "$aff" "$what"
  done <<< "$(blast_symbol_rows)"
}

check_blast_plain_symbols

if [ "$BLAST_PLAIN_CHECKED" -eq 0 ]; then
  fail "$(printf '%-22s no blast table names a symbol in plain words' 'blast plain symbol')"
  BLAST_PLAIN_BAD=1
fi

if [ "$BLAST_PLAIN_BAD" -eq 0 ]; then
  ok "blast plain symbol" "$BLAST_PLAIN_CHECKED symbols"
fi

# --- the test a row points at -------------------------------------------------
#
# The dependency evidence says which test catches the removal of a safeguard,
# and it points at the test with a pointer of its own: "test:193-207".  That
# pointer is not a file:line, so every gate that follows a citation skipped
# it, and the name of the test is written in double quotes, which no gate
# reads either.  Nothing watched the claim: the tree could rename the test,
# move it, or end it two lines earlier, and the row would go on saying it.
#
# The rule: the tree has to have a test with that name, the row has to point
# at the line that test starts on, and the range has to end on the line the
# test's block ends on.  A test body is indented and the brace that closes
# the test is not, so a block ends at the first closing brace in column zero.
#
# The bash twin says the same thing.  The two are twins: they print the same
# lines and they go red together.

TEST_PTR_BAD=0
TEST_PTR_CHECKED=0

# A name in double quotes: the way this document writes a test's name.
DQUOTE_RE='\"([^\"]+)\"'

# The pointer of its own: test:193-207.
TEST_PTR_RE='(^|[^A-Za-z0-9_])test:([0-9]+)(-[0-9]+)?'

# The tests the tree has: the file, the line the test starts on, its name,
# and the line its block ends on.
TEST_DECLS=""
test_declarations() {
  local -a files=()
  local file
  TEST_DECLS=""
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    case "$file" in
      *.mbt) ;;
      *) continue ;;
    esac
    [ -f "$file" ] || continue
    files+=("$file")
  done < <(git ls-files '*.mbt' 2>/dev/null || true)
  [ "${#files[@]}" -gt 0 ] || return
  TEST_DECLS=$(awk '
    FNR == 1 { start = 0; name = "" }
    {
      if (start == 0) {
        if (match($0, /^[ \t]*(async[ \t]+)?test[ \t]+"[^"]*"/)) {
          head = substr($0, RSTART, RLENGTH)
          sub(/^[ \t]*(async[ \t]+)?test[ \t]+"/, "", head)
          sub(/"$/, "", head)
          name = head
          start = FNR
        }
        next
      }
      if ($0 ~ /^\}[[:blank:]]*$/) {
        printf "%s\t%d\t%s\t%d\n", FILENAME, start, name, FNR
        start = 0
        name = ""
      }
    }
  ' "${files[@]}")
}

# One row, checked against the test it points at.
test_pointer_check() {
  local doc="$1" line="$2" claim="$3"
  local rest="$3" tok name first last file decl_line decl_end
  local found=0 matched=0
  [[ "$claim" =~ $TEST_PTR_RE ]] || return
  first="${BASH_REMATCH[2]}"
  last="${BASH_REMATCH[3]}"
  last="${last#-}"
  [ -n "$last" ] || last="$first"
  rest="$claim"
  while [[ "$rest" =~ $DQUOTE_RE ]]; do
    tok="${BASH_REMATCH[1]}"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    name="$tok"
    TEST_PTR_CHECKED=$((TEST_PTR_CHECKED + 1))
    found=0
    matched=0
    file=""
    decl_line=""
    decl_end=""
    while IFS=$'\t' read -r dfile dline dname dend; do
      [ "$dname" = "$name" ] || continue
      if [ "$found" -eq 0 ]; then
        found=1
        file="$dfile"
        decl_line="$dline"
        decl_end="$dend"
      fi
      if [ "$dline" = "$first" ] && [ "$dend" = "$last" ]; then
        matched=1
        break
      fi
    done <<< "$TEST_DECLS"
    if [ "$found" -eq 0 ]; then
      fail "$(printf '%-22s %s line %s names the test [%s], and the tree has no test with that name' \
        'test pointer' "$doc" "$line" "$name")"
      TEST_PTR_BAD=1
    elif [ "$matched" -eq 0 ]; then
      fail "$(printf '%-22s %s line %s says the test [%s] is at test:%s-%s, and the tree has it at %s:%s-%s' \
        'test pointer' "$doc" "$line" "$name" "$first" "$last" "$file" "$decl_line" "$decl_end")"
      TEST_PTR_BAD=1
    fi
  done
}

# Every claim the documents make, checked against the tests they point at.
check_test_pointers() {
  local doc line claim
  test_declarations
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      test_pointer_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

check_test_pointers

if [ "$TEST_PTR_CHECKED" -eq 0 ]; then
  fail "$(printf '%-22s no document points at a test of the tree' 'test pointer')"
  TEST_PTR_BAD=1
fi

if [ "$TEST_PTR_BAD" -eq 0 ]; then
  ok "test pointer" "$TEST_PTR_CHECKED tests"
fi

# --- the string a row quotes in double quotes ---------------------------------
#
# The evidence documents quote JSON keys and config values in double quotes
# and point at the line that holds them:
#
#   | `Page::to_json()` | "slug" | `get_string(json, "slug", "")` |
#     `backend/pages.mbt:70`, `frontend/page.mbt:118` |
#
# The literal pointer gate reads BACKTICKED literals, so a string in double
# quotes is not read by it.  The key the backend produces at line 70 was not
# checked by anything: the backticked name of the function is not unique in
# the file, so the literal pointer gate passed it by.
#
# The rule: every line the row cites holds the string the row quotes, as a
# literal.  The row says the key is produced here and read there, and both
# lines hold it in double quotes.  The letters alone are not enough: the tree
# can hold the same letters as an identifier, and "slugX" holds the letters
# of "slug" without being the string "slug".
# A quoted sentence is a test's name and not a literal -- the test pointer
# gate reads that one -- so a string with a space in it is left alone.
#
# The bash twin says the same thing.  The two are twins: they print the same
# lines and they go red together.

QUOTED_BAD=0
QUOTED_CHECKED=0

# The lines a row cites: the file, a bar, the lines of it.
QUOTED_CITES=""
quoted_cites() {
  local claim="$1" rest="$1" tok spec
  QUOTED_CITES=""
  while [[ "$rest" =~ $CITE_ANY_RE ]]; do
    tok="${BASH_REMATCH[1]}"
    spec="${BASH_REMATCH[2]}"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    QUOTED_CITES="$QUOTED_CITES ${tok}|${spec}"
  done
}

# Whether the cited range holds the string: some line of the file holds it AS
# A LITERAL, and the citation covers that line.
#
# The string has to be there in double quotes.  The letters alone are not the
# string: the tree can hold the same letters as an identifier, and
# "slugX" holds the letters of "slug" without being the string "slug".
quoted_line_holds() {
  local file="$1" spec="$2" s="$3" i needle
  needle="\"$s\""
  code_lines_of "$file"
  [ "${#CODE_LINES[@]}" -gt 0 ] || return 1
  for ((i = 0; i < ${#CODE_LINES[@]}; i++)); do
    case "${CODE_LINES[i]}" in
      *"$needle"*) ;;
      *) continue ;;
    esac
    citation_covers "$spec" "$((i + 1))"
    [ "$CITATION_COVERS" -eq 1 ] && return 0
  done
  return 1
}

# One row, checked against the lines it cites.
quoted_literal_check() {
  local doc="$1" line="$2" claim="$3"
  local rest="$3" tok s cite file spec seen=""
  quoted_cites "$claim"
  [ -n "$QUOTED_CITES" ] || return
  rest="$claim"
  while [[ "$rest" =~ $DQUOTE_RE ]]; do
    tok="${BASH_REMATCH[1]}"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    s="$tok"
    case "$s" in
      *" "*) continue ;;
    esac
    # The same string twice in one row is one promise, not two.
    case " $seen " in
      *" $s "*) continue ;;
    esac
    seen="$seen $s"
    for cite in $QUOTED_CITES; do
      file="${cite%%|*}"
      spec="${cite#*|}"
      QUOTED_CHECKED=$((QUOTED_CHECKED + 1))
      if ! quoted_line_holds "$file" "$spec" "$s"; then
        fail "$(printf '%-22s %s line %s quotes [%s], and %s:%s does not hold it as a literal' \
          'quoted literal' "$doc" "$line" "$s" "$file" "$spec")"
        QUOTED_BAD=1
      fi
    done
  done
}

# Every claim the documents make, checked against the strings they quote.
check_quoted_literals() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      quoted_literal_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

check_quoted_literals

if [ "$QUOTED_CHECKED" -eq 0 ]; then
  fail "$(printf '%-22s no document quotes a string in double quotes' 'quoted literal')"
  QUOTED_BAD=1
fi

if [ "$QUOTED_BAD" -eq 0 ]; then
  ok "quoted literal" "$QUOTED_CHECKED quotes"
fi

# --- the pointer reaches the function a row names by its short name -----------
#
# The code pointer gate asks whether a citation reaches the function a claim
# names.  It finds that function by the name the tree gives it:
#
#   fn Database::exec(...)   -> the definition is named "Database::exec"
#
# A row that says `exec()` names the same function, and the documents write
# it that way.  The gate did not see those rows, because "exec" is not
# "Database::exec": a claim that names a function of the file has to name it
# the way the tree spells it, and the tree spells a method with its type.
#
# The measurement that found the gap: the row that says `exec()` always steps
# cites backend/database.mbt:73-98.  exec() is on lines 41-72.  A reader
# following the citation lands in the middle of Database::migrate and never
# finds the function the row is about, and every gate in the repository was
# green.
#
# The rule: a row that names a function of the cited file by its SHORT name,
# written the way a call is written -- exec() -- has to point inside that
# function.  The short name is a name only when it is written as a call: a
# word that happens to be the name of a function is a word, and the row that
# says "App with route table" is about the App, not about App::route.
#
# The bash twin says the same thing.  The two are twins: they print the same
# lines and they go red together.

CALL_PTR_BAD=0
CALL_PTR_CHECKED=0

# The functions of a file: the line each one starts on, and its name.
#
# The gate script has two functions called code_definitions: the one that
# finds the functions of a file, and the one that finds the types of the
# tree.  The second is defined later in the script, and a function defined
# later shadows the first, so a gate at the end of the script cannot use the
# name.  This one is the first of the two, under a name of its own.
FN_LINES=()
FN_NAMES=()
FN_FILE=""
FN_COUNT=0

fn_definitions() {
  local file="$1" out line name
  if [ "$FN_FILE" = "$file" ]; then return; fi
  FN_FILE="$file"
  FN_LINES=()
  FN_NAMES=()
  FN_COUNT=0
  out=$(awk '
    /^[ \t]*(pub(\([a-z]+\))?[ \t]+)?(async[ \t]+)?fn[ \t]+[A-Za-z_]/ {
      tmp = $0
      sub(/^[ \t]*(pub(\([a-z]+\))?[ \t]+)?(async[ \t]+)?fn[ \t]+/, "", tmp)
      split(tmp, parts, /[ \t(]/)
      printf "%d\t%s\n", NR, parts[1]
    }
    END { printf "#\t%d\n", NR }
  ' "$file" || true)
  while IFS=$'\t' read -r line name; do
    [ -n "$name" ] || continue
    if [ "$line" = "#" ]; then
      FN_COUNT="$name"
      continue
    fi
    FN_LINES+=("$line")
    FN_NAMES+=("$name")
  done <<< "$out"
}

# The block a function occupies: from the line that defines it to the line
# before the next definition.
FN_START=0
FN_END=0
fn_range() {
  local name="$1" i
  FN_START=0
  FN_END=0
  for i in "${!FN_NAMES[@]}"; do
    if [ "${FN_NAMES[$i]}" = "$name" ]; then
      FN_START="${FN_LINES[$i]}"
      if [ $((i + 1)) -lt "${#FN_NAMES[@]}" ]; then
        FN_END=$(( ${FN_LINES[$((i + 1))]} - 1 ))
      else
        FN_END="$FN_COUNT"
      fi
      return
    fi
  done
}

# A name written as a call: exec()
CALL_RE='([A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)?)\(\)'

# The names a claim writes as calls.
CLAIM_CALLS=""
claim_calls() {
  local text="$1" rest="$1"
  CLAIM_CALLS=""
  while [[ "$rest" =~ $CALL_RE ]]; do
    if [ -z "$CLAIM_CALLS" ]; then
      CLAIM_CALLS="${BASH_REMATCH[1]}"
    else
      CLAIM_CALLS="$CLAIM_CALLS ${BASH_REMATCH[1]}"
    fi
    rest="${rest#*"${BASH_REMATCH[0]}"}"
  done
}

# One row, checked against the function it names by its short name.
call_pointer_check() {
  local doc="$1" line="$2" claim="$3"
  local fn short count=0 named="" part a b covered
  cite_source "$claim"
  [ -n "$CITE_FILE" ] || return
  [ -f "$CITE_FILE" ] || return
  claim_calls "$CITE_TEXT"
  [ -n "$CLAIM_CALLS" ] || return
  fn_definitions "$CITE_FILE"
  # the functions of that file the claim names by their short name
  for fn in "${FN_NAMES[@]}"; do
    short="${fn##*::}"
    # a name with no type in front of it is the whole name, and the code
    # pointer gate reads that one
    [ "$short" != "$fn" ] || continue
    case " $CLAIM_CALLS " in
      *" $short "*)
        count=$((count + 1))
        named="$fn"
        ;;
    esac
  done
  # a row that names one function of the file has to point inside it
  [ "$count" -eq 1 ] || return
  fn_range "$named"
  [ "$FN_START" -gt 0 ] || return
  covered=0
  for part in ${CITE_SPEC//,/ }; do
    case "$part" in
      *-*) a="${part%-*}"; b="${part#*-}" ;;
      *) a="$part"; b="$part" ;;
    esac
    if [ "$a" -le "$FN_END" ] && [ "$FN_START" -le "$b" ]; then
      covered=1
      break
    fi
  done
  CALL_PTR_CHECKED=$((CALL_PTR_CHECKED + 1))
  if [ "$covered" -eq 0 ]; then
    fail "$(printf '%-22s %s line %s cites [%s:%s], but %s is on lines %s-%s' \
      'code pointer call' "$doc" "$line" "$CITE_FILE" "$CITE_SPEC" "$named" "$FN_START" "$FN_END")"
    CALL_PTR_BAD=1
  fi
}

# Every claim the documents make, checked against the functions they name by
# their short name.
check_call_pointers() {
  local doc line claim
  for doc in "${ARCH_DOCS[@]}"; do
    not_in "$doc" "$MARKED_DOCS"
    [ -n "$NOT_IN" ] || continue
    doc_claims "$doc"
    while IFS=$'\t' read -r line claim; do
      [ -n "$claim" ] || continue
      call_pointer_check "$doc" "$line" "$claim"
    done <<< "$DOC_CLAIMS"
  done
}

check_call_pointers

if [ "$CALL_PTR_CHECKED" -eq 0 ]; then
  fail "$(printf '%-22s no document names a function by its short name' 'code pointer call')"
  CALL_PTR_BAD=1
fi

if [ "$CALL_PTR_BAD" -eq 0 ]; then
  ok "code pointer call" "$CALL_PTR_CHECKED calls"
fi

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
