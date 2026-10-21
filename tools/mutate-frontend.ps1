# Mutation check for the frontend tests.
#
# Green tests are not evidence. Each entry deliberately breaks one behaviour
# and asserts the suite goes red. A mutation that survives means the test it
# targeted does not actually reach the code.
#
#   .\tools\mutate-frontend.ps1
#
# Run from anywhere; the repo root is derived from this script's own path.
#
# Files are patched and restored byte-exactly (UTF-8, no BOM, LF preserved) so
# the repo is unchanged whichever way this script exits.
#
# Two traps this script already hit, both of which look like a weak test and
# are not:
#
#   - An anchor that does not occur in the file. `String::Replace` then does
#     nothing, the suite stays green, and the mutation is reported as
#     SURVIVED. Anchors are therefore checked and a miss is an ERROR.
#   - A single-quoted PowerShell string containing `` `" ``. The backtick is
#     literal there, so the anchor silently never matches. Quote anchors that
#     contain `"` with double quotes instead.

Set-Location (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

# `moon` writes diagnostics to stderr; under 'Stop' PowerShell turns every one
# of them into a terminating error before the exit code is ever read.
$ErrorActionPreference = 'Continue'
$enc = New-Object System.Text.UTF8Encoding($false)

# --- mutations ------------------------------------------------------------
# name; file; old text; new text
$mutations = @(
  @{
    name = 'slug_of stops stripping the leading slash'
    file = 'frontend/app.mbt'
    old  = 'let s = if path.has_prefix("/") { path[1:].to_owned() } else { path }'
    new  = 'let s = path'
  },
  @{
    name = 'slug_of collapses unknown paths into the index'
    file = 'frontend/app.mbt'
    old  = '  if s == "" || s == "index" {
    "index"
  } else {
    s
  }'
    new  = '  "index"'
  },
  @{
    name = 'navigation sorts descending'
    file = 'frontend/page.mbt'
    old  = 'sorted.sort_by(fn(a, b) { a.sort.compare(b.sort) })'
    new  = 'sorted.sort_by(fn(a, b) { b.sort.compare(a.sort) })'
  },
  @{
    name = 'navigation keeps non-nav pages'
    file = 'frontend/page.mbt'
    old  = 'let items = pages.filter(fn(p) { p.in_navigation })'
    new  = 'let items = pages'
  },
  @{
    name = 'find_page returns the first page instead of the match'
    file = 'frontend/page.mbt'
    old  = '    if page.slug == slug {
      return Some(page)
    }'
    new  = '    return Some(page)'
  },
  @{
    name = 'decode_pages raises shape instead of falling back'
    file = 'frontend/page.mbt'
    old  = '    Some(Array(items)) => items.map(fn(item) { page_from_json(item) })
    _ => []'
    new  = '    Some(Array(items)) => items.map(fn(item) { page_from_json(item) })
    _ => panic'
  },
  @{
    name = 'decode_pages defaults in_navigation to true'
    file = 'frontend/page.mbt'
    old  = '    in_navigation: get_bool(json, "in_navigation", false),'
    new  = '    in_navigation: get_bool(json, "in_navigation", true),'
  },
  @{
    name = 'ring order tidied into spelling order'
    file = 'frontend/logo.mbt'
    old  = "    (`"M`", `"#2c3e9e`"),
    (`"D`", `"#27ae60`"),
    (`"E`", `"#e74c3c`"),
    (`"A`", `"#f1c40f`"),
    (`"K`", `"#7f8c8d`"),"
    new  = "    (`"M`", `"#2c3e9e`"),
    (`"A`", `"#f1c40f`"),
    (`"K`", `"#7f8c8d`"),
    (`"E`", `"#e74c3c`"),
    (`"D`", `"#27ae60`"),"
  },
  @{
    name = 'ring starts at the bottom and turns anticlockwise'
    file = 'frontend/logo.mbt'
    old  = 'let degrees = -90.0 + 72.0 * i.to_double()'
    new  = 'let degrees = 90.0 - 72.0 * i.to_double()'
  },
  @{
    name = 'ring radius shrinks by 4'
    file = 'frontend/logo.mbt'
    old  = 'const RING_R : Int32 = 68'
    new  = 'const RING_R : Int32 = 64'
  },
  @{
    name = 'ring centre moves off the middle of the viewBox'
    file = 'frontend/logo.mbt'
    old  = 'const CY : Int32 = 100'
    new  = 'const CY : Int32 = 96'
  },
  @{
    name = 'percentages forget the 100x scale'
    file = 'frontend/logo.mbt'
    old  = "(x.to_double() * 100.0 / VIEW.to_double()).to_string() + `"%`","
    new  = "(x.to_double() / VIEW.to_double()).to_string() + `"%`","
  },
  @{
    name = 'percentages divide by the node radius instead of the viewBox'
    file = 'frontend/logo.mbt'
    old  = "(x.to_double() * 100.0 / VIEW.to_double()).to_string() + `"%`","
    new  = "(x.to_double() * 100.0 / NODE_R.to_double()).to_string() + `"%`","
  },
  @{
    name = 'vertical percentage ignores the offset and measures from the top edge only'
    file = 'frontend/logo.mbt'
    old  = "(y.to_double() * 100.0 / VIEW.to_double()).to_string() + `"%`","
    new  = "(y.to_double() * 100.0 / (VIEW.to_double() * 2.0)).to_string() + `"%`","
  },
  @{
    name = 'ring starts half a turn late'
    file = 'frontend/logo.mbt'
    old  = 'let degrees = -90.0 + 72.0 * i.to_double()'
    new  = 'let degrees = 90.0 + 72.0 * i.to_double()'
  },
  # A session id arrives as a *string*, because the backend holds it as an
  # `Int64` and MoonBit encodes an `Int64` as a string. A decoder that read
  # only the number would report zero for every session, and the page would
  # show an empty list rather than a wrong one.
  @{
    name = 'the session id is decoded as a number'
    file = 'frontend/session.mbt'
    old  = "    id: get_id(json, `"id`"),
    name: get_string(json, `"name`", `"`"),"
    new  = "    id: 0,
    name: get_string(json, `"name`", `"`"),"
  },
  # The reason a step was possible is written by the server. A client that
  # dropped it would show the timeline with no explanation on any of it.
  @{
    name = 'the reason a step was possible is not decoded'
    file = 'frontend/session.mbt'
    old  = '    why: get_string(json, "why", ""),'
    new  = '    why: "",'
  },
  # A delete takes two presses. A client that deleted on the first would
  # throw away a history on a single mistaken click.
  @{
    name = 'a session is deleted on the first click'
    file = 'frontend/app.mbt'
    old  = '      if model.session_delete_pending == id {'
    new  = '      if true {'
  },
  # The way out of a position the table declined to decide is a button per
  # candidate. A button that carries no candidate is a dead button with the
  # right words on it.
  @{
    name = 'the way out sends no candidate'
    file = 'frontend/views.mbt'
    old  = '                on_click=emit(TargetStepClicked(open.name, target)),'
    new  = '                on_click=emit(TargetStepClicked(open.name, "")),'
  },
  # The server reads the successor out of one field of the request. A request
  # that leaves it out is refused with a 400, so the button stops working while
  # still looking like it works.
  @{
    name = 'the request drops the chosen successor'
    file = 'frontend/app.mbt'
    old  = '  ("/api/loop/step/" + slot + lang_query(lang), { "target": target })'
    new  = '  ("/api/loop/step/" + slot + lang_query(lang), { "target": "" })'
  },
  # The candidates are the table's own. A client that decodes none of them
  # draws a way out with no way in it.
  @{
    name = 'the candidates are never decoded'
    file = 'frontend/loop_state.mbt'
    old  = '            String(s) => last = Some(s)'
    new  = '            String(s) => last = None'
  },
  # The way out is found by the outcome's *kind*. A client that matches the
  # word "Undecided" works until somebody renames the model -- and renaming a
  # model is exactly what a model file is for.
  @{
    name = 'the way out is found by the label again'
    file = 'frontend/loop_state.mbt'
    old  = '    if slot.outcome_kind == "open" && slot.targets.length() > 0 {'
    new  = '    if slot.outcome == "Undecided" && slot.targets.length() > 0 {'
  },
  # The kind travels beside the label, so a client never has to recognise a
  # sentence to know what happened.
  @{
    name = 'the outcome kind is never decoded'
    file = 'frontend/loop_state.mbt'
    old  = '    outcome_kind: get_string(json, "outcome_kind", ""),'
    new  = '    outcome_kind: "",'
  },
  # --- the causal panel -------------------------------------------------
  # The panel used to read the estimate with the string accessor over a JSON
  # number, and so showed the fallback "0.0" for every estimate the server
  # ever made. These break the panel in the ways it can be broken.
  @{
    name = 'the estimate is read as a whole number'
    file = 'frontend/causal.mbt'
    old  = '    theta: get_double(json, "theta", 0.0),'
    new  = '    theta: get_int(json, "theta", 0).to_double(),'
  },
  @{
    name = 'a refusal is read as an estimate'
    file = 'frontend/causal.mbt'
    old  = '    refused: refusal != "",'
    new  = '    refused: false,'
  },
  @{
    name = 'the controlled variables are never read'
    file = 'frontend/causal.mbt'
    old  = '    confounders: get_strings(json, "confounders"),'
    new  = '    confounders: [],'
  },
  @{
    name = 'a group that does not overlap is reported as close'
    file = 'frontend/causal.mbt'
    old  = '  if row.separated {'
    new  = '  if false {'
  },
  @{
    name = 'the balance verdict loses the case where the groups agree'
    file = 'frontend/causal.mbt'
    old  = '  } else if row.balanced {'
    new  = '  } else if false {'
  },
  @{
    name = 'the estimate is not rounded for reading'
    file = 'frontend/causal.mbt'
    old  = '  let scaled = (n * 10000.0).round()'
    new  = '  let scaled = (n * 10000.0)'
  },
  @{
    name = 'the sensitivity interval is not read'
    file = 'frontend/causal.mbt'
    old  = '    sensitivity_lower: get_double(sub(json, "sensitivity"), "lower", 0.0),'
    new  = '    sensitivity_lower: 0.0,'
  },
  @{
    name = 'the overlap is not read'
    file = 'frontend/causal.mbt'
    old  = '    overlaps: get_bool(sub(json, "overlap"), "overlaps", false),'
    new  = '    overlaps: true,'
  },
  # The Society panel. The collective is the third layer, and it has the same
  # failure the rest of MAKED has: a panel that reads the wrong field shows a
  # fallback and looks fine doing it. These mutations are the ways the panel
  # can quietly stop knowing where the collective is.
  @{
    name = 'the collective''s position is never read'
    file = 'frontend/society.mbt'
    old  = '    state: get_string(json, "state", ""),'
    new  = '    state: "",'
  },
  @{
    name = 'the collective''s name falls back to nothing'
    file = 'frontend/society.mbt'
    old  = '    get_string(json, id_key, "")'
    new  = '    ""'
  },
  @{
    name = 'what the last move did is never read'
    file = 'frontend/society.mbt'
    old  = '    kind: get_string(json, "kind", ""),'
    new  = '    kind: "",'
  },
  @{
    name = 'the reason a move did not happen is never read'
    file = 'frontend/society.mbt'
    old  = '    reason: get_string(json, "reason", ""),'
    new  = '    reason: "",'
  },
  @{
    name = 'where the collective came from is never read'
    file = 'frontend/society.mbt'
    old  = '    from_label: labelled_or(json, "from_label", "from"),'
    new  = '    from_label: "",'
  },
  @{
    name = 'the moves from here are never read'
    file = 'frontend/society.mbt'
    old  = '    moves: society_moves(json),'
    new  = '    moves: [],'
  },
  @{
    name = 'the positions are never read'
    file = 'frontend/society.mbt'
    old  = '    positions: society_positions(json),'
    new  = '    positions: [],'
  },
  @{
    name = 'the transitions are never read'
    file = 'frontend/society.mbt'
    old  = '    transitions: society_transitions(json),'
    new  = '    transitions: [],'
  },
  @{
    name = 'the gaps in the vocabulary are never read'
    file = 'frontend/society.mbt'
    old  = '    gaps: get_strings(json, "gaps"),'
    new  = '    gaps: [],'
  },
  @{
    name = 'the outcome sentence drops where the move came from'
    file = 'frontend/society.mbt'
    old  = '        collective_moved_from(c, summary.from_label, summary.state_label)'
    new  = '        collective_moved_to(c, summary.state_label)'
  },
  @{
    name = 'the move button carries the label instead of the name'
    file = 'frontend/society.mbt'
    old  = 'on_click=emit(SocietyStepClicked(edge.trigger)),'
    new  = 'on_click=emit(SocietyStepClicked(edge.trigger_label)),'
  },
  @{
    name = 'the request names no move at all'
    file = 'frontend/app.mbt'
    old  = '("/api/society/step" + lang_query(lang), { "trigger": trigger })'
    new  = '("/api/society/step" + lang_query(lang), { "trigger": "" })'
  },
  @{
    name = 'the move goes to an endpoint that does not exist'
    file = 'frontend/app.mbt'
    old  = '("/api/society/step" + lang_query(lang), { "trigger": trigger })'
    new  = '("/api/society/read" + lang_query(lang), { "trigger": trigger })'
  },
  # --- the language ---------------------------------------------------------
  #
  # The frontend carries its own language and its own table of words, because
  # the backend's `Lang` is in another package and another target. These
  # mutations are about the two ways that can go wrong: the table can be the
  # English one in a Chinese interface, and a sentence with a hole in it can
  # come out in the wrong language.
  @{
    name = 'the Chinese words of the shell are the English ones'
    file = 'frontend/i18n.mbt'
    old  = '        nav: nav_zh(),'
    new  = '        nav: nav_en(),'
  },
  @{
    name = 'the Chinese words of the loop are the English ones'
    file = 'frontend/i18n.mbt'
    old  = '        loop_panel: loop_zh(),'
    new  = '        loop_panel: loop_en(),'
  },
  @{
    name = 'the Chinese words of the corpus are the English ones'
    file = 'frontend/i18n.mbt'
    old  = '        research: research_zh(),'
    new  = '        research: research_en(),'
  },
  @{
    name = 'the Chinese words of the sessions are the English ones'
    file = 'frontend/i18n.mbt'
    old  = '        sessions: sessions_zh(),'
    new  = '        sessions: sessions_en(),'
  },
  @{
    name = 'the Chinese words of the workspace are the English ones'
    file = 'frontend/i18n.mbt'
    old  = '        workspace: workspace_zh(),'
    new  = '        workspace: workspace_en(),'
  },
  @{
    name = 'the Chinese words of the failures are the English ones'
    file = 'frontend/i18n.mbt'
    old  = '        status: status_zh(),'
    new  = '        status: status_en(),'
  },
  @{
    name = 'the Chinese words of the causal panel are the English ones'
    file = 'frontend/i18n.mbt'
    old  = '        causal: causal_zh(),'
    new  = '        causal: causal_en(),'
  },
  @{
    name = 'the Chinese words of the collective are the English ones'
    file = 'frontend/i18n.mbt'
    old  = '        society: society_zh(),'
    new  = '        society: society_en(),'
  },
  @{
    name = 'a sentence with a hole in it ignores the language'
    file = 'frontend/i18n.mbt'
    old  = '        lang,
        nav: nav_zh(),'
    new  = '        lang: UiLang::english(),
        nav: nav_zh(),'
  },
  @{
    name = 'the language switch does not switch'
    file = 'frontend/i18n.mbt'
    old  = '    English => Chinese'
    new  = '    English => English'
  },
  @{
    name = 'the language is read as English'
    file = 'frontend/i18n.mbt'
    old  = 'if tag == "zh" ||'
    new  = 'if tag == "zz" ||'
  },
  @{
    name = 'the request does not carry the language'
    file = 'frontend/i18n.mbt'
    old  = '  "?lang=" + lang.code()'
    new  = '  "?lang="'
  },
  @{
    # The client used to hold its own table of the five domain names, in both
    # languages, and keep it in step with the machine by hand -- so this
    # mutation was about the table's fallback. The table is gone: the server
    # holds both languages of a page now and sends the one that was asked for,
    # and the client asks and is told. What the client still owns is the
    # reading of the server's answer, and that is what is guarded here.
    name = 'the page title is read from the wrong field'
    file = 'frontend/page.mbt'
    old  = '    title: get_string(json, "title", ""),'
    new  = '    title: get_string(json, "summary", ""),'
  },
  @{
    name = 'the page body is read from the wrong field'
    file = 'frontend/page.mbt'
    old  = '    body: get_string(json, "body", ""),'
    new  = '    body: get_string(json, "summary", ""),'
  },
  @{
    name = 'the interface starts in Chinese'
    file = 'frontend/app.mbt'
    old  = '    lang: UiLang::English,'
    new  = '    lang: UiLang::Chinese,'
  },
  @{
    name = 'the step request does not carry the language'
    file = 'frontend/app.mbt'
    old  = '@http.post("/api/loop/step" + lang_query(model.lang))'
    new  = '@http.post("/api/loop/step")'
  },
  @{
    name = 'the language switch does not ask the server'
    file = 'frontend/app.mbt'
    old  = '@http.get("/api/bootstrap" + lang_query(lang))'
    new  = '@http.get("/api/bootstrap")'
  },
  @{
    name = 'the header switch is not wired to the update'
    file = 'frontend/views.mbt'
    old  = 'on_click=emit(LangToggled),'
    new  = 'on_click=emit(ResetClicked),'
  },
  @{
    name = 'the society request does not carry the language'
    file = 'frontend/app.mbt'
    old  = '  "/api/society" + lang_query(lang)'
    new  = '  "/api/society"'
  },
  @{
    name = 'the collective request does not carry the language'
    file = 'frontend/app.mbt'
    old  = '("/api/society/step" + lang_query(lang), { "trigger": trigger })'
    new  = '("/api/society/step", { "trigger": trigger })'
  },
  # The document the reader takes away is in the language the page is in, and
  # the link that takes it away is what says so: a link that left the
  # language off would hand a reader who had turned the page into Chinese an
  # English document, with the download working perfectly.
  @{
    name = 'the export link does not carry the language'
    file = 'frontend/app.mbt'
    old  = '  "/export?format=" +
  format +
  lang_param(lang)'
    new  = '  "/export?format=" +
  format'
  }
)

# --- run ------------------------------------------------------------------
$survivors = @()
foreach ($m in $mutations) {
  $full = Join-Path $PWD $m.file
  $original = [System.IO.File]::ReadAllText($full)
  try {
    # A silent no-op Replace reports a mutation that never happened as a
    # surviving test, which reads as a test weakness and is not one. Make an
    # unmatched anchor an error instead.
    if (-not $original.Contains($m.old)) {
      throw "anchor not present in $($m.file) -- mutation never applied"
    }
    [System.IO.File]::WriteAllText($full, $original.Replace($m.old, $m.new), $enc)
    $out = & moon test --target js frontend 2>&1 | Out-String
    $killed = ($LASTEXITCODE -ne 0) -or ($out -match 'failed: [1-9]')
    if ($killed) {
      Write-Output ("KILLED   {0}" -f $m.name)
    } else {
      Write-Output ("SURVIVED {0}" -f $m.name)
      $survivors += $m.name
    }
  } catch {
    Write-Output ("ERROR    {0} :: {1}" -f $m.name, $_.Exception.Message)
    $survivors += $m.name
  } finally {
    [System.IO.File]::WriteAllText($full, $original, $enc)
  }
}

Write-Output ""
Write-Output ("survivors: {0}" -f $survivors.Count)