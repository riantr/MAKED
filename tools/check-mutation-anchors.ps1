# Check every mutation anchor in the three mutation suites against the
# current source.
#
#   .\tools\check-mutation-anchors.ps1
#
# Green tests are not evidence, and a mutation that never applied is not a
# failed mutation -- it is nothing at all. When a source file moves, the
# anchor that pointed at it stops matching, the file is left unchanged, the
# suite stays green, and the mutation is reported as a survivor: a claim
# about the tests when the truth is that the mutation never happened. The
# bash gate inside `ci.sh` hit this for five of its ten anchors, and the
# PowerShell suites hit it for eleven more when the loop state started
# carrying its own model.
#
# The suites themselves now report a missing anchor as an ERROR, so the rot
# is visible -- but only after the suite has run, and a full run of the three
# suites takes half an hour. This script asks the same question in a second:
# does every anchor still occur in the file it names?
#
# It reads only. It never writes to the source tree, so it is safe to run at
# any time -- including while a mutation suite is running, though the answer
# is then only true between mutations.

Set-Location (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

$ErrorActionPreference = 'Continue'
$enc = New-Object System.Text.UTF8Encoding($false)

$scripts = @(
  'tools\mutate-backend.ps1',
  'tools\mutate-frontend.ps1',
  'tools\mutate-loop.ps1'
)

# Expand \u{XXXX} into the character it names.
#
# An anchor in a mutation suite is pure ASCII, because the suites are read by
# Windows PowerShell as ANSI: a Chinese literal in one is mojibake before the
# script has run, and an anchor made of one never matches the UTF-8 source it
# is looking for. A character is named by its code point instead, and both the
# suites and this checker expand it the same way -- so an anchor written this
# way is still checked, rather than being an anchor nobody can see.
function Expand-CodePoints($text) {
  $out = ''
  $i = 0
  while ($i -lt $text.Length) {
    if ($text[$i] -eq '\' -and
        $i + 2 -lt $text.Length -and
        $text[$i + 1] -eq 'u' -and
        $text[$i + 2] -eq '{') {
      $end = $text.IndexOf('}', $i + 3)
      if ($end -gt 0) {
        $hex = $text.Substring($i + 3, $end - $i - 3)
        $out += [char][Convert]::ToInt32($hex, 16)
        $i = $end + 1
        continue
      }
    }
    $out += $text[$i]
    $i++
  }
  $out
}

# One mutation's anchor, in the two forms the suites use:
#
#   old  = 'single quoted'
#   old  = @'
#   ...a here string, which may span lines...
#   '@
#
# and the third form that is easy to miss: a single-quoted string that
# itself spans several lines.
function Get-Anchors($text) {
  $anchors = @()
  $lines = $text -split "`n"
  $name = $null
  $file = $null
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i].TrimEnd("`r")
    # `name` and `file` are quoted with single quotes almost everywhere, but a
    # name that contains an apostrophe cannot be: PowerShell would end the
    # string. Those are written with double quotes instead -- and the checker
    # only read the single-quoted form, so those mutations were reported with
    # a blank label. The anchor was still checked; what was lost was the
    # ability to say WHICH one was dead.
    if ($line -match "^\s*name\s*=\s*'(.*)'\s*$") { $name = $Matches[1] }
    if ($line -match '^\s*name\s*=\s*"(.*)"\s*$') { $name = $Matches[1] }
    if ($line -match "^\s*file\s*=\s*'(.*)'\s*$") { $file = $Matches[1] }
    if ($line -match '^\s*file\s*=\s*"(.*)"\s*$') { $file = $Matches[1] }
    if ($line -match "^\s*old\s*=\s*@'") {
      $buf = @()
      $i++
      while ($i -lt $lines.Count -and $lines[$i].TrimEnd("`r") -ne "'@") {
        $buf += $lines[$i]
        $i++
      }
      $anchors += ,@($name, $file, ($buf -join "`n"))
      $name = $null
      continue
    }
    if ($line -match "^\s*old\s*=\s*'(.*)$") {
      $first = $Matches[1]
      $buf = @()
      if ($first -match "^(.*)'\s*$") {
        $buf += $Matches[1]
      } else {
        # A single-quoted string that spans lines.
        $buf += $first
        $i++
        while ($i -lt $lines.Count) {
          $l = $lines[$i].TrimEnd("`r")
          if ($l -match "^(.*)'\s*$") {
            $buf += $Matches[1]
            break
          }
          $buf += $l
          $i++
        }
      }
      $anchors += ,@($name, $file, ($buf -join "`n"))
      $name = $null
    }
    # The fourth form: a double-quoted anchor, used when the anchor itself
    # contains a quote. The quotes inside it are escaped as a backtick and a
    # quote. This form was not read at all, which meant an anchor written
    # this way was never checked -- and an anchor that is never checked is
    # an anchor that rots without anybody being told.
    if ($line -match '^\s*old\s*=\s*"(.*)$') {
      $buf = @()
      $rest = $Matches[1]
      if ($rest -match '^(.*)"\s*$') {
        $buf += (($Matches[1]) -replace '`"', '"')
      } else {
        $buf += ($rest -replace '`"', '"')
        $i++
        while ($i -lt $lines.Count) {
          $l = $lines[$i].TrimEnd("`r")
          if ($l -match '^(.*)"\s*$') {
            $buf += (($Matches[1]) -replace '`"', '"')
            break
          }
          $buf += ($l -replace '`"', '"')
          $i++
        }
      }
      $anchors += ,@($name, $file, ($buf -join "`n"))
      $name = $null
    }
  }
  $anchors
}

$dead = 0
$total = 0
foreach ($s in $scripts) {
  $path = Join-Path $PWD $s
  if (-not (Test-Path $path)) {
    Write-Output ("=== {0} === MISSING" -f $s)
    $dead++
    continue
  }
  $text = [System.IO.File]::ReadAllText($path)
  Write-Output ("=== {0} ===" -f $s)
  foreach ($a in (Get-Anchors $text)) {
    $total++
    $name = $a[0]
    $file = $a[1]
    $anchor = $a[2]
    if (-not $file) {
      Write-Output ("  SKIP    {0}  (no file)" -f $name)
      continue
    }
    $full = Join-Path $PWD $file
    if (-not (Test-Path $full)) {
      Write-Output ("  DEAD    {0}  ({1} does not exist)" -f $name, $file)
      $dead++
      continue
    }
    $src = [System.IO.File]::ReadAllText($full)
    $anchor = Expand-CodePoints $anchor
    if ($src.Contains($anchor)) {
      Write-Output ("  ok      {0}" -f $name)
    } else {
      Write-Output ("  DEAD    {0}  ({1})" -f $name, $file)
      Write-Output ("          anchor: {0}" -f $anchor.Replace("`n", "\n"))
      $dead++
    }
  }
}

Write-Output ""
Write-Output ("anchors: {0}   dead: {1}" -f $total, $dead)
if ($dead -gt 0) {
  Write-Output ""
  Write-Output "A dead anchor is a guard that cannot fail. Repoint it at the code that"
  Write-Output "carries the behaviour now, and prove the new anchor by breaking it."
  exit 1
}
