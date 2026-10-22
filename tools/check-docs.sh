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
