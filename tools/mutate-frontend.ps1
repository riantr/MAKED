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