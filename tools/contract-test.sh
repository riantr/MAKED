#!/usr/bin/env bash
# Contract tests for the MAKED API.
#
# Contract tests validate that API responses match their expected schemas.
# Unlike integration tests (which check status codes and basic field presence),
# contract tests verify the *shape* and *types* of every field in every response.
#
# This catches breaking changes to the API contract that would silently break
# the frontend (e.g., a field changing from string to number, or a required
# field being removed).
#
# Usage:
#   bash tools/contract-test.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PORT=${MAKED_PORT:-$(( 49200 + RANDOM % 1000 ))}
DB="_build/test-contract-$$.db"
LOG="_build/test-contract-$$.log"
SERVER_PID=""
PASS=0
FAIL=0
TOTAL=0

# The interpreter, whichever name this machine gives it.
#
# `python` is not on the PATH of a current ubuntu runner -- `python3` is --
# and a gate that dies on a missing interpreter says nothing about the thing
# it was meant to check: it says the interpreter is missing, and the checks
# that would have run do not run. So the name is resolved once, and a
# machine with neither is told so plainly instead of failing sixty times.
PYTHON="$(command -v python3 || command -v python || true)"
if [ -z "$PYTHON" ]; then
  echo "  ERROR  no python on this machine, so the contract checks cannot run"
  exit 1
fi

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -f "$DB" "$LOG"
}
trap cleanup EXIT

assert_contract() {
  local desc="$1" json="$2" check="$3"
  TOTAL=$((TOTAL + 1))
  local result
  result=$(echo "$json" | "$PYTHON" -c "
import sys, json
try:
    d = json.load(sys.stdin)
    $check
    print('PASS')
except Exception as e:
    print(f'FAIL: {e}')
" 2>&1) || result="FAIL: python error"

  if [[ "$result" == "PASS" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS  $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL  $desc -- $result"
  fi
}

echo "==> Contract Tests"
echo "    Port: $PORT"
echo ""

# Build and start server
echo "    Building server..."
moon build --release --target native cmd/server 2>/dev/null

# The built server, wherever the toolchain put it.
#
# The gate starts the binary itself rather than asking `moon run` to start
# it, and that is not a style choice. Two things depend on it:
#
#   - The process the gate holds is then the server, so the gate can stop
#     it. `moon run` is a wrapper: killing the wrapper does not necessarily
#     kill the server it started, and a server left running holds the
#     output pipe of the step that started it.
#   - The server's output goes to a log file, not to the step's own output.
#     A background process that keeps the step's output open is a step that
#     never finishes, and a gate that hangs is a gate that stops a pipeline
#     rather than reporting anything.
#
# The same two things are why every request below carries a timeout: a gate
# that waits forever on a request that never answers is the same hang with
# a different cause.
find_server() {
  for candidate in \
    "_build/native/release/build/cmd/server/server" \
    "_build/native/release/build/cmd/server/server.exe" \
    "_build/native/debug/build/cmd/server/server" \
    "_build/native/debug/build/cmd/server/server.exe"; do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

SERVER_BIN="$(find_server || true)"
if [ -z "$SERVER_BIN" ]; then
  echo "    ERROR: the server binary was not found after the build"
  exit 1
fi

echo "    Starting server on port $PORT..."
MAKED_PORT="$PORT" MAKED_DB="$DB" "$SERVER_BIN" > "$LOG" 2>&1 &
SERVER_PID=$!

# Wait for it to answer, up to half a minute. A fixed sleep is either too
# long on a fast machine or too short on a slow one, and a gate that gives
# up on a server that was about to start fails for a reason that has
# nothing to do with the contract.
READY=0
for _ in $(seq 1 30); do
  if curl -sf --max-time 2 "http://127.0.0.1:$PORT/api/status" > /dev/null 2>&1; then
    READY=1
    break
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    break
  fi
  sleep 1
done

if [ "$READY" -ne 1 ]; then
  echo "    ERROR: the server did not answer on port $PORT"
  echo "    --- what it said ---"
  cat "$LOG" 2>/dev/null | tail -20
  exit 1
fi

echo "    Server started (PID $SERVER_PID)"
echo ""

# ---------------------------------------------------------------------------
# Contract: GET /api/status
# ---------------------------------------------------------------------------
echo "  Contract: GET /api/status"
RESP=$(curl -s --max-time 10 "http://localhost:$PORT/api/status")
assert_contract "status has string 'status'" "$RESP" \
  "assert isinstance(d['status'], str)"
assert_contract "status has string 'database'" "$RESP" \
  "assert isinstance(d['database'], str)"
assert_contract "status has int 'page_count'" "$RESP" \
  "assert isinstance(d['page_count'], int)"
assert_contract "status has array 'domains'" "$RESP" \
  "assert isinstance(d['domains'], list)"
assert_contract "status domains have 5 entries" "$RESP" \
  "assert len(d['domains']) == 5"
assert_contract "status domain has string 'slug'" "$RESP" \
  "assert isinstance(d['domains'][0]['slug'], str)"
assert_contract "status domain has string 'title'" "$RESP" \
  "assert isinstance(d['domains'][0]['title'], str)"
assert_contract "status domain has string 'letter'" "$RESP" \
  "assert isinstance(d['domains'][0]['letter'], str)"
assert_contract "status domain has string 'role'" "$RESP" \
  "assert isinstance(d['domains'][0]['role'], str)"

# ---------------------------------------------------------------------------
# Contract: GET /api/pages
# ---------------------------------------------------------------------------
echo "  Contract: GET /api/pages"
RESP=$(curl -s --max-time 10 "http://localhost:$PORT/api/pages")
assert_contract "pages has array 'pages'" "$RESP" \
  "assert isinstance(d['pages'], list)"
assert_contract "pages has at least 8 entries" "$RESP" \
  "assert len(d['pages']) >= 8"
assert_contract "page has string 'slug'" "$RESP" \
  "assert isinstance(d['pages'][0]['slug'], str)"
assert_contract "page has string 'title'" "$RESP" \
  "assert isinstance(d['pages'][0]['title'], str)"
assert_contract "page has string 'letter'" "$RESP" \
  "assert isinstance(d['pages'][0]['letter'], str)"
assert_contract "page has string 'role'" "$RESP" \
  "assert isinstance(d['pages'][0]['role'], str)"
assert_contract "page has string 'summary'" "$RESP" \
  "assert isinstance(d['pages'][0]['summary'], str)"
assert_contract "page has string 'body'" "$RESP" \
  "assert isinstance(d['pages'][0]['body'], str)"
assert_contract "page has bool 'in_navigation'" "$RESP" \
  "assert isinstance(d['pages'][0]['in_navigation'], bool)"
assert_contract "page has int 'sort'" "$RESP" \
  "assert isinstance(d['pages'][0]['sort'], int)"

# ---------------------------------------------------------------------------
# Contract: GET /api/domains
# ---------------------------------------------------------------------------
echo "  Contract: GET /api/domains"
RESP=$(curl -s --max-time 10 "http://localhost:$PORT/api/domains")
assert_contract "domains has array 'domains'" "$RESP" \
  "assert isinstance(d['domains'], list)"
assert_contract "domains has 5 entries" "$RESP" \
  "assert len(d['domains']) == 5"

# ---------------------------------------------------------------------------
# Contract: GET /api/loop/status
# ---------------------------------------------------------------------------
echo "  Contract: GET /api/loop/status"
RESP=$(curl -s --max-time 10 "http://localhost:$PORT/api/loop/status")
assert_contract "loop status has string 'current_domain'" "$RESP" \
  "assert isinstance(d['current_domain'], str)"
assert_contract "loop status has string 'current_title'" "$RESP" \
  "assert isinstance(d['current_title'], str)"
assert_contract "loop status has string 'current_position'" "$RESP" \
  "assert isinstance(d['current_position'], str)"
assert_contract "loop status has string 'current_position_label'" "$RESP" \
  "assert isinstance(d['current_position_label'], str)"
assert_contract "loop status has string 'current_gloss'" "$RESP" \
  "assert isinstance(d['current_gloss'], str)"
assert_contract "loop status has string 'next_domain'" "$RESP" \
  "assert isinstance(d['next_domain'], str)"
assert_contract "loop status has string 'drive_slot'" "$RESP" \
  "assert isinstance(d['drive_slot'], str)"
assert_contract "loop status has int 'history_length'" "$RESP" \
  "assert isinstance(d['history_length'], int)"
assert_contract "loop status has array 'history'" "$RESP" \
  "assert isinstance(d['history'], list)"
assert_contract "loop status has array 'domain_states'" "$RESP" \
  "assert isinstance(d['domain_states'], list)"
assert_contract "loop status domain_states has 5 entries" "$RESP" \
  "assert len(d['domain_states']) == 5"
assert_contract "loop status has string 'group_state'" "$RESP" \
  "assert isinstance(d['group_state'], str)"
assert_contract "loop status has string 'group_state_gloss'" "$RESP" \
  "assert isinstance(d['group_state_gloss'], str)"

# ---------------------------------------------------------------------------
# Contract: GET /api/loop/slots
# ---------------------------------------------------------------------------
echo "  Contract: GET /api/loop/slots"
RESP=$(curl -s --max-time 10 "http://localhost:$PORT/api/loop/slots")
assert_contract "slots has array 'slots'" "$RESP" \
  "assert isinstance(d['slots'], list)"
assert_contract "slots has 8 entries" "$RESP" \
  "assert len(d['slots']) == 8"
assert_contract "slot has string 'name'" "$RESP" \
  "assert isinstance(d['slots'][0]['name'], str)"
assert_contract "slot has string 'designation'" "$RESP" \
  "assert isinstance(d['slots'][0]['designation'], str)"
assert_contract "slot has string 'gloss'" "$RESP" \
  "assert isinstance(d['slots'][0]['gloss'], str)"
# `source` is deliberately absent: pyroduct's Slot::source() is the Chinese
# source quote, kept so a name can be traced back to the original text. There
# is no English form of it, so the English API does not pretend to carry one.
assert_contract "slot has no 'source' field" "$RESP" \
  "assert 'source' not in d['slots'][0]"

# ---------------------------------------------------------------------------
# Contract: POST /api/loop/step
# ---------------------------------------------------------------------------
echo "  Contract: POST /api/loop/step"
RESP=$(curl -s --max-time 10 -X POST "http://localhost:$PORT/api/loop/step")
assert_contract "step response has string 'current_domain'" "$RESP" \
  "assert isinstance(d['current_domain'], str)"
assert_contract "step response has int 'history_length'" "$RESP" \
  "assert isinstance(d['history_length'], int)"
assert_contract "step response history_length >= 1" "$RESP" \
  "assert d['history_length'] >= 1"

# ---------------------------------------------------------------------------
# Contract: POST /api/loop/reset
# ---------------------------------------------------------------------------
echo "  Contract: POST /api/loop/reset"
RESP=$(curl -s --max-time 10 -X POST "http://localhost:$PORT/api/loop/reset")
assert_contract "reset response has string 'current_domain'" "$RESP" \
  "assert isinstance(d['current_domain'], str)"
assert_contract "reset response current_domain is M" "$RESP" \
  "assert d['current_domain'] == 'M'"
assert_contract "reset response history_length is 0" "$RESP" \
  "assert d['history_length'] == 0"

# ---------------------------------------------------------------------------
# Contract: POST /api/loop/reset/:domain
# ---------------------------------------------------------------------------
echo "  Contract: POST /api/loop/reset/:domain"
RESP=$(curl -s --max-time 10 -X POST "http://localhost:$PORT/api/loop/reset/D")
assert_contract "reset to D has current_domain D" "$RESP" \
  "assert d['current_domain'] == 'D'"
assert_contract "reset to D has history_length 0" "$RESP" \
  "assert d['history_length'] == 0"

RESP=$(curl -s --max-time 10 -X POST "http://localhost:$PORT/api/loop/reset/attack")
assert_contract "reset to attack (english) has current_domain A" "$RESP" \
  "assert d['current_domain'] == 'A'"

RESP=$(curl -s --max-time 10 -X POST "http://localhost:$PORT/api/loop/reset/invalid")
assert_contract "reset to invalid domain returns error" "$RESP" \
  "assert 'error' in d"

# ---------------------------------------------------------------------------
# Contract: GET /api/loop/mode
# ---------------------------------------------------------------------------
echo "  Contract: GET /api/loop/mode"
RESP=$(curl -s --max-time 10 "http://localhost:$PORT/api/loop/mode")
assert_contract "mode response has string 'mode'" "$RESP" \
  "assert isinstance(d['mode'], str)"
assert_contract "mode response mode is structured or free" "$RESP" \
  "assert d['mode'] in ['structured', 'free']"
assert_contract "mode response has string 'designation'" "$RESP" \
  "assert isinstance(d['designation'], str)"
assert_contract "mode response has string 'gloss'" "$RESP" \
  "assert isinstance(d['gloss'], str)"

# ---------------------------------------------------------------------------
# Contract: POST /api/loop/mode/:mode
# ---------------------------------------------------------------------------
echo "  Contract: POST /api/loop/mode/:mode"
RESP=$(curl -s --max-time 10 -X POST "http://localhost:$PORT/api/loop/mode/free")
assert_contract "set mode to free succeeds" "$RESP" \
  "assert d['mode'] == 'free'"
assert_contract "set mode response has mode_designation" "$RESP" \
  "assert isinstance(d['mode_designation'], str)"
assert_contract "set mode response has mode_gloss" "$RESP" \
  "assert isinstance(d['mode_gloss'], str)"

RESP=$(curl -s --max-time 10 -X POST "http://localhost:$PORT/api/loop/mode/structured")
assert_contract "set mode to structured succeeds" "$RESP" \
  "assert d['mode'] == 'structured'"

RESP=$(curl -s --max-time 10 -X POST "http://localhost:$PORT/api/loop/mode/invalid")
assert_contract "set invalid mode returns error" "$RESP" \
  "assert 'error' in d"

# ---------------------------------------------------------------------------
# Contract: mode fields in loop status
# ---------------------------------------------------------------------------
echo "  Contract: mode fields in loop status"
RESP=$(curl -s --max-time 10 "http://localhost:$PORT/api/loop/status")
assert_contract "status has mode field" "$RESP" \
  "assert isinstance(d['mode'], str)"
assert_contract "status has mode_designation field" "$RESP" \
  "assert isinstance(d['mode_designation'], str)"
assert_contract "status has mode_gloss field" "$RESP" \
  "assert isinstance(d['mode_gloss'], str)"

# ---------------------------------------------------------------------------
# Contract: every refusal carries a reason
# ---------------------------------------------------------------------------
#
# A refusal that carries no reason is a shrug: the reader is told that
# something did not happen and nothing else. The client cannot do better --
# the HTTP status code never reaches it, so the body is the only place a
# reason can come from -- which means a body without a reason is a refusal
# the reader cannot act on.
#
# The rule is checked over the source rather than over the responses
# because the responses are only a sample: the source holds every refusal
# the API can answer, including the ones this script does not happen to
# trigger. A gate that only watched the refusals it could provoke would let
# the next one through.
#
# The set of refusal kinds is printed rather than the number of refusals: a
# count is a claim about the size, and the kinds are the claim about what
# the rule covers. An empty set is a failure -- a rule that found nothing to
# look at is not a rule that passed.
echo "  Contract: every refusal carries a reason"
REFUSAL_REPORT="$("$PYTHON" - "$ROOT/backend/api.mbt" <<'PYEOF'
import re
import sys

path = sys.argv[1]
lines = open(path, encoding="utf-8").read().split("\n")

sites = []
for i, line in enumerate(lines):
    if not re.search(r"status=(400|404)", line):
        continue
    start = None
    for j in range(i, max(-1, i - 40), -1):
        if "let body : Json = {" in lines[j]:
            start = j
            break
    if start is None:
        sites.append((i + 1, "<no body literal>", True))
        continue
    depth = 0
    block = []
    for j in range(start, len(lines)):
        depth += lines[j].count("{") - lines[j].count("}")
        block.append(lines[j])
        if depth <= 0:
            break
    text = "\n".join(block)
    code = ""
    m = re.search(r'"error":\s*"([^"]+)"', text)
    if m:
        code = m.group(1)
    sites.append((i + 1, code, '"reason"' not in text))

kinds = []
for _, code, _ in sites:
    if code and code not in kinds:
        kinds.append(code)

bad = [(ln, code) for ln, code, missing in sites if missing]
if bad:
    print("FAIL " + ", ".join("line %d (%s)" % (ln, code) for ln, code in bad))
elif not sites:
    print("FAIL no refusal found, so the rule is watching nothing")
else:
    print("OK " + ", ".join(kinds))
PYEOF
)"
TOTAL=$((TOTAL + 1))
case "$REFUSAL_REPORT" in
  "OK "*)
    PASS=$((PASS + 1))
    echo "  PASS  every refusal carries a reason -- ${REFUSAL_REPORT#OK }"
    ;;
  *)
    FAIL=$((FAIL + 1))
    echo "  FAIL  every refusal carries a reason -- ${REFUSAL_REPORT#FAIL }"
    ;;
esac

# ---------------------------------------------------------------------------
# Contract: every refusal the agent gives is in the caller's language
# ---------------------------------------------------------------------------
#
# The agent's server is the product's second front door. The payloads it
# answers with are already in the language the caller asked in, and the
# refusal -- the one part that says what went wrong -- was not: nine of the
# eleven places the agent surface could refuse wrote their words out in
# English at the point of refusal.
#
# A refusal written at the point of refusal is a refusal that is English
# until somebody remembers to translate it, so the words live in one place
# instead: the vocabulary in the backend, and the agent's server asks for
# them there. This rule checks both halves of that: every refusal takes its
# words from the vocabulary, and every word in the vocabulary has an English
# reading and a Chinese one.
#
# The set of refusal kinds is printed rather than the number of refusals: a
# count is a claim about the size, and the kinds are the claim about what
# the rule covers. An empty set is a failure -- a rule that found nothing to
# look at is not a rule that passed.
echo "  Contract: every refusal the agent gives is in the caller's language"
AGENT_REFUSAL_REPORT="$("$PYTHON" - "$ROOT/cmd/mcp/main.mbt" "$ROOT/backend/agent.mbt" <<'PYEOF'
import re
import sys

mcp_path, agent_path = sys.argv[1], sys.argv[2]
mcp = open(mcp_path, encoding="utf-8").read()
agent = open(agent_path, encoding="utf-8").read()

# --- the vocabulary: every refusal word has both languages ------------------
helpers = {}
for m in re.finditer(r"pub fn (agent_refusal_\w+)\(", agent):
    name = m.group(1)
    start = agent.find("{", m.end())
    if start < 0:
        continue
    depth = 0
    end = start
    for j in range(start, len(agent)):
        depth += agent[j].count("{") - agent[j].count("}")
        if depth <= 0:
            end = j
            break
    body = agent[start : end + 1]
    helpers[name] = {
        "line": agent[: m.start()].count("\n") + 1,
        "bilingual": ("English" in body and "Chinese" in body),
    }

# --- the sites: every refusal takes its words from the vocabulary -----------
sites = []
for m in re.finditer(r"MCPError::\w+\(", mcp):
    open_at = m.end() - 1
    depth = 0
    j = open_at
    while j < len(mcp):
        if mcp[j] == "(":
            depth += 1
        elif mcp[j] == ")":
            depth -= 1
            if depth == 0:
                break
        j += 1
    expr = mcp[open_at + 1 : j]
    line = mcp[: m.start()].count("\n") + 1
    used = re.findall(r"agent_refusal_\w+", expr)
    sites.append({"line": line, "used": used, "expr": expr})

bad = []
for site in sites:
    if not site["used"]:
        bad.append("line %d (a refusal that writes its own words)" % site["line"])
        continue
    for name in site["used"]:
        if name not in helpers:
            bad.append("line %d (%s is not in the vocabulary)" % (site["line"], name))
        elif not helpers[name]["bilingual"]:
            bad.append(
                "line %d (%s has no Chinese reading)" % (site["line"], name)
            )

# --- the export refuses a format it does not write -------------------------
# The export used to answer Markdown for every format that was not "json",
# so an agent that asked for a format MAKED does not write was handed a
# document in a format it did not ask for and never found out.
export = re.search(r"pub fn agent_export\(", agent)
if export is None:
    bad.append("no agent_export to refuse with")
else:
    start = agent.find("{", export.end())
    depth = 0
    end = start
    for j in range(start, len(agent)):
        depth += agent[j].count("{") - agent[j].count("}")
        if depth <= 0:
            end = j
            break
    body = agent[start : end + 1]
    if "UnknownFormat" not in body:
        bad.append("the export guesses a format instead of refusing it")

kinds = []
for site in sites:
    for name in site["used"]:
        if name not in kinds:
            kinds.append(name)

if bad:
    print("FAIL " + "; ".join(bad))
elif not sites:
    print("FAIL no refusal found, so the rule is watching nothing")
elif not kinds:
    print("FAIL no refusal kind found, so the rule is watching nothing")
else:
    print("OK " + ", ".join(sorted(kinds)))
PYEOF
)"
TOTAL=$((TOTAL + 1))
case "$AGENT_REFUSAL_REPORT" in
  "OK "*)
    PASS=$((PASS + 1))
    echo "  PASS  every refusal the agent gives is in the caller's language -- ${AGENT_REFUSAL_REPORT#OK }"
    ;;
  *)
    FAIL=$((FAIL + 1))
    echo "  FAIL  every refusal the agent gives is in the caller's language -- ${AGENT_REFUSAL_REPORT#FAIL }"
    ;;
esac

# ---------------------------------------------------------------------------
# Contract: every note the product answers with is in the reader's language
# ---------------------------------------------------------------------------
#
# A note is the softer half of a refusal. Nothing was refused, but something
# still needs saying: the corpus could not be read, the table was written
# back, the collective has no drive slots. The panel shows those sentences,
# and the panel is in the reader's language.
#
# Seven of the eleven notes in the tree were English whatever the request
# asked for, in a project that has a Chinese interface and a `lang` argument
# on every route that can say anything. The refusals were given a reason in
# the reader's language; the notes were left as they were found.
#
# The words a note uses live in one place, the same way the words a refusal
# uses do, and this rule checks that every note comes from that vocabulary
# and that every word in the vocabulary has an English reading and a Chinese
# one.
#
# The vocabulary is read from the DEFINITIONS, not from the places that call
# them. A vocabulary is a claim about what the product can say, and a word
# that is defined but not yet called is still a word the product could say.
# Reading the vocabulary from the call sites instead means the rule only
# knows about the words some route happens to use today, and a word whose
# Chinese reading was removed is invisible to the rule exactly when nobody
# is calling it.
#
# The value of a note is read whole, across as many lines as it takes. A
# note is often an if/else with a branch per fact -- the corpus could not be
# read, the corpus held nothing, there is nothing to say -- and those
# branches are the note. A rule that stops at the first branch sees one
# branch of a note and calls the rest of it checked.
#
# Brackets inside a sentence are not brackets in the code, so the scan
# steps over string literals and comments: a note that names a path is not
# a note whose value ends at the comma inside the path.
#
# The discovery document is the one exception, and it is named: it is a
# protocol map -- one document, one language -- and not an answer to a
# request that asked for a language.
#
# The set of note kinds is printed rather than the number of notes: a count
# is a claim about the size, and the kinds are the claim about what the rule
# covers. An empty set is a failure -- a rule that found nothing to look at
# is not a rule that passed.
echo "  Contract: every note the product answers with is in the reader's language"
NOTE_REPORT="$("$PYTHON" - "$ROOT/backend/api.mbt" "$ROOT/backend/agent.mbt" <<'PYEOF'
import re
import sys

# The protocol map: one document, one language, and not an answer to a
# request that asked for a language.
PROTOCOL_FUNCTIONS = {"agent_discovery"}

OPENERS = "([{"
CLOSERS = ")]}"


def text_spans(text):
    """The text's spans: code, strings and comments, with their offsets.

    A string literal is one span, so the quotes and the brackets inside a
    sentence are the sentence's own and not the code's.
    """
    out = []
    i = 0
    n = len(text)
    seg = 0
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\" and j + 1 < n:
                    j += 2
                    continue
                if text[j] == '"':
                    j += 1
                    break
                j += 1
            out.append(("code", seg, i))
            out.append(("string", i, j))
            i = j
            seg = j
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            if j < 0:
                j = n
            out.append(("code", seg, i))
            out.append(("comment", i, j))
            i = j
            seg = j
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(("code", seg, i))
            out.append(("comment", i, j))
            i = j
            seg = j
            continue
        i += 1
    out.append(("code", seg, n))
    return out


def mask(text, sp):
    """The text with its strings and comments blanked, same length.

    The length is kept so that an offset in the masked text is the same
    offset in the text.
    """
    out = list(text)
    for kind, s, e in sp:
        if kind == "code":
            continue
        for k in range(s, e):
            if out[k] != "\n":
                out[k] = " "
    return "".join(out)


def line_starts(text):
    starts = [0]
    for i, ch in enumerate(text):
        if ch == "\n":
            starts.append(i + 1)
    return starts


def line_of(starts, offset):
    """The line an offset is on."""
    lo, hi = 0, len(starts) - 1
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if starts[mid] <= offset:
            lo = mid
        else:
            hi = mid - 1
    return lo + 1


def function_ranges(masked):
    """Every named function's body range in the masked text."""
    out = []
    for m in re.finditer(r"\bfn\s+(\w+)\s*\(", masked):
        depth = 0
        j = m.end() - 1
        while j < len(masked):
            if masked[j] == "(":
                depth += 1
            elif masked[j] == ")":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        b = masked.find("{", j)
        if b < 0:
            continue
        depth = 0
        k = b
        while k < len(masked):
            if masked[k] == "{":
                depth += 1
            elif masked[k] == "}":
                depth -= 1
                if depth == 0:
                    break
            k += 1
        out.append((m.group(1), b, k))
    return out


def enclosing(ranges, offset):
    """The innermost function whose body holds the offset."""
    best = "<none>"
    best_at = -1
    for name, b, k in ranges:
        if b <= offset <= k and b > best_at:
            best = name
            best_at = b
    return best


def key_colon(masked, end):
    """The colon of the key, when the string that ends at `end` is one."""
    j = end
    while j < len(masked) and masked[j] in " \t":
        j += 1
    if j < len(masked) and masked[j] == ":":
        return j
    return None


def value_after(text, skip_at, start):
    """The value that begins at `start`, whole.

    The value of a note is often an if/else with a branch per fact, and the
    branches are the note, so the value is read across as many lines as it
    takes: it ends at the comma that closes the field, not at the end of
    the first branch.

    Returns the code of the value -- with the string literals blanked, and
    the same length as the text they came from, so an offset in the code is
    an offset in the text -- and the strings the value carries.
    """
    depth = 0
    code = []
    strings = []
    i = start
    n = len(text)
    while i < n:
        skipped = skip_at.get(i)
        if skipped is not None:
            kind, end, content = skipped
            if kind == "string":
                strings.append((len(code), content))
            code.append(" " * (end - i))
            i = end
            continue
        c = text[i]
        if c in OPENERS:
            depth += 1
        elif c in CLOSERS:
            if depth == 0:
                break
            depth -= 1
        elif c == "," and depth == 0:
            break
        code.append(c)
        i += 1
    return "".join(code), strings


def call_spans(code, name):
    """The spans of every call to `name` in the code."""
    spans = []
    for m in re.finditer(r"\b" + re.escape(name) + r"\s*\(", code):
        depth = 0
        j = m.end() - 1
        while j < len(code):
            if code[j] == "(":
                depth += 1
            elif code[j] == ")":
                depth -= 1
                if depth == 0:
                    spans.append((m.start(), j))
                    break
            j += 1
    return spans


files = [(path, open(path, encoding="utf-8").read()) for path in sys.argv[1:]]

bad = []
kinds = []
sites = 0

# The vocabulary spans both doors: the words a note may be written from.
vocabulary = {}

for path, text in files:
    sp = text_spans(text)
    masked = mask(text, sp)
    starts = line_starts(text)
    ranges = function_ranges(masked)
    skip_at = {}
    for kind, s, e in sp:
        if kind != "code":
            content = text[s + 1 : e - 1] if kind == "string" else ""
            skip_at[s] = (kind, e, content)

    # --- the vocabulary: every note word has both readings -------------------
    for name, b, k in ranges:
        if not re.search(r"_(?:note|notice)$", name):
            continue
        body = masked[b : k + 1]
        vocabulary[name] = {
            "line": line_of(starts, b),
            "english": bool(re.search(r"\bEnglish\b\s*=>", body)),
            "chinese": bool(re.search(r"\bChinese\b\s*=>", body)),
        }

    # --- the sites: every note takes its words from the vocabulary ----------
    for kind, s, e in sp:
        if kind != "string":
            continue
        content = text[s + 1 : e - 1]
        if content not in ("note", "notice"):
            continue
        colon = key_colon(masked, e)
        if colon is None:
            continue
        fn = enclosing(ranges, s)
        if fn in PROTOCOL_FUNCTIONS:
            continue
        sites += 1
        line = line_of(starts, s)
        code, strings = value_after(text, skip_at, colon + 1)
        used = re.findall(r"\b(\w+_(?:note|notice))\s*\(", code)
        if not used:
            bad.append("line %d (%s: a note that writes its own words)" % (line, fn))
            continue
        for name in used:
            if name not in vocabulary:
                bad.append("line %d (%s is not in the vocabulary)" % (line, name))
        # The words of a note come from the vocabulary. A string passed to a
        # helper as its argument is the reader's own word -- a path, a
        # corpus -- and is not translated; a string written outside such a
        # call is a note that writes its own words.
        spans = []
        for name in used:
            spans.extend(call_spans(code, name))
        for offset, lit in strings:
            if not lit.strip():
                continue
            if any(a <= offset <= b for a, b in spans):
                continue
            bad.append("line %d (%s: a note that writes its own words)" % (line, fn))
            break

for name in sorted(vocabulary):
    if name not in kinds:
        kinds.append(name)
    if not vocabulary[name]["english"]:
        bad.append(
            "line %d (%s has no English reading)" % (vocabulary[name]["line"], name)
        )
    elif not vocabulary[name]["chinese"]:
        bad.append(
            "line %d (%s has no Chinese reading)" % (vocabulary[name]["line"], name)
        )

if bad:
    print("FAIL " + "; ".join(bad))
elif not sites:
    print("FAIL no note found, so the rule is watching nothing")
elif not kinds:
    print("FAIL no note kind found, so the rule is watching nothing")
else:
    print("OK " + ", ".join(sorted(kinds)))
PYEOF
)"
TOTAL=$((TOTAL + 1))
case "$NOTE_REPORT" in
  "OK "*)
    PASS=$((PASS + 1))
    echo "  PASS  every note the product answers with is in the reader's language -- ${NOTE_REPORT#OK }"
    ;;
  *)
    FAIL=$((FAIL + 1))
    echo "  FAIL  every note the product answers with is in the reader's language -- ${NOTE_REPORT#FAIL }"
    ;;
esac

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "    Contract Tests: $PASS passed, $FAIL failed (of $TOTAL)"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
