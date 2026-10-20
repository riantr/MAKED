# End-to-end integration test for MAKED.
#
#   pwsh tools/integration-test.ps1
#
# Run from anywhere; the repo root is derived from this script's own path.
#
# Why this exists in PowerShell and not only in bash: the CI runners are
# ubuntu, and their images carry `pwsh`, so one script serves both this
# machine and the runner. The bash twin (`tools/integration-test.sh`) stays
# for the bash-only gates, but the safety net that matters most should not
# depend on which shell the machine happens to have.
#
# What it checks, and why each part exists:
#
#   - Every route, on its happy path and on its refusal path. A route that
#     answers 200 with a body nobody can read is a route that looks fine and
#     is useless.
#   - **The silent-failure class.** The worst bug this project ever had was
#     a batch of requests at start-up: every POST reached the server and
#     changed the state, and not one response came back. The screen froze
#     on stale data with nothing in the console. So the requests here are
#     fired *concurrently* and the assertions are on what the server ended
#     up with, not only on what came back: eight concurrent steps must
#     leave eight more steps in the history. A lost response and a lost
#     write are the same bug seen from two ends.
#   - **The client-side anti-pattern that caused it.** `@cmd.batch` is the
#     thing that turned two harmless GETs into a frozen page, and it is
#     exactly the kind of change that comes back later as a "small
#     optimisation". So the source is checked: no batching, and one request
#     at start-up.
#
# A failed assertion prints what was expected and what was found. The exit
# code is 0 when every check passed and 1 otherwise.

param(
  [int]$Port = 18188,
  [switch]$SkipBuild,
  [switch]$KeepDatabase
)

Set-Location (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

$ErrorActionPreference = 'Continue'
$repo = $PWD.Path

# --- assertions -------------------------------------------------------------
$script:passed = 0
$script:failed = 0

function Assert-True {
  param([string]$Desc, [bool]$Condition, [string]$Detail = "")
  if ($Condition) {
    Write-Host ("  PASS  {0}" -f $Desc)
    $script:passed += 1
  } else {
    Write-Host ("  FAIL  {0}" -f $Desc)
    if ($Detail -ne "") { Write-Host ("        {0}" -f $Detail) }
    $script:failed += 1
  }
}

function Assert-Status {
  param([string]$Desc, [int]$Expected, $Response)
  Assert-True $Desc ($Response.Status -eq $Expected) `
    ("expected HTTP {0}, got {1} -- body: {2}" -f $Expected, $Response.Status, (Limit $Response.Body))
}

function Assert-Field {
  param([string]$Desc, $Json, [string]$Field, $Expected)
  $actual = Field $Json $Field
  Assert-True $Desc ("$actual" -eq "$Expected") `
    ("expected '{0}' to be '{1}', got '{2}'" -f $Field, $Expected, $actual)
}

function Assert-FieldNotEmpty {
  param([string]$Desc, $Json, [string]$Field)
  $actual = Field $Json $Field
  Assert-True $Desc ("$actual" -ne "") `
    ("expected '{0}' to be present and not empty" -f $Field)
}

function Assert-ArrayLength {
  param([string]$Desc, $Json, [string]$Field, [int]$Expected)
  $actual = (Field $Json $Field)
  $count = if ($null -eq $actual) { -1 } else { @($actual).Count }
  Assert-True $Desc ($count -eq $Expected) `
    ("expected '{0}' to hold {1} entries, got {2}" -f $Field, $Expected, $count)
}

function Assert-HasField {
  param([string]$Desc, $Json, [string]$Field)
  $has = $false
  if ($null -ne $Json) {
    $has = $null -ne $Json.PSObject.Properties[$Field]
  }
  Assert-True $Desc $has ("expected the field '{0}' to be there" -f $Field)
}

function Assert-Contains {
  param([string]$Desc, [string]$Haystack, [string]$Needle)
  Assert-True $Desc ($Haystack -like "*$Needle*") `
    ("expected the text to contain '{0}'" -f $Needle)
}

function Limit {
  param([string]$Text)
  if ($null -eq $Text) { return "" }
  if ($Text.Length -gt 200) { return $Text.Substring(0, 200) + "..." }
  return $Text
}

# --- the code, without the prose around it ----------------------------------
function Remove-Comments {
  param([string]$Text)
  # The string literals are blanked out first, so that a "//" inside a string
  # is not mistaken for the start of a comment, and so that a string cannot
  # hide a use of the thing being looked for. Then the comments go.
  #
  # The blanking is done a line at a time, and that is not a detail. A
  # regex that runs over the whole file will happily match a quote in one
  # line with a quote three hundred lines later, and the "string" it
  # blanks out in between swallows the code the check is looking for. A
  # quoted phrase in a comment -- the natural way to write prose -- was
  # enough to do it, and the failure it caused was the check reporting
  # that the init block could not be found when it was sitting right
  # there. A line at a time, a stray quote can only affect its own line.
  $kept = foreach ($line in ($Text -split "`r?`n")) {
    $withoutStrings = [regex]::Replace($line, '"(?:[^"\\]|\\.)*"', '""')
    $withoutStrings -replace '//.*$', ''
  }
  return ($kept -join "`n")
}

# --- the two shapes of a failed request --------------------------------------
#
# Mocks of the two exception shapes, so that the reader can be held to both
# on whichever PowerShell the script happens to be running under. Without
# this, a reader that only knew one shape looked fine on the machine it was
# written on and read every error as an empty body on the other one.
function New-MockErrorRecord {
  param($Response)
  $exception = New-Object psobject
  $exception | Add-Member -MemberType NoteProperty -Name 'Response' -Value $Response
  $record = New-Object psobject
  $record | Add-Member -MemberType NoteProperty -Name 'Exception' -Value $exception
  $record | Add-Member -MemberType NoteProperty -Name 'ErrorDetails' -Value $null
  return $record
}

# PowerShell 7: the response is an HttpResponseMessage, the body is in
# Content, and there is no stream to read it from.
function New-MockMessageResponse {
  param([string]$Text)
  $content = New-Object psobject
  $content | Add-Member -MemberType NoteProperty -Name 'Text' -Value $Text
  $content | Add-Member -MemberType ScriptMethod -Name 'ReadAsStringAsync' -Value {
    Write-Output -NoEnumerate ([pscustomobject]@{ Result = $this.Text })
  }
  $response = New-Object psobject
  $response | Add-Member -MemberType NoteProperty -Name 'Content' -Value $content
  return $response
}

# Windows PowerShell: the response is an HttpWebResponse, and the body is a
# stream.
function New-MockWebResponse {
  param([string]$Text)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $stream = New-Object System.IO.MemoryStream(, $bytes)
  $response = New-Object psobject
  $response | Add-Member -MemberType NoteProperty -Name 'Stream' -Value $stream
  $response | Add-Member -MemberType ScriptMethod -Name 'GetResponseStream' -Value {
    return $this.Stream
  }
  return $response
}

# --- HTTP -------------------------------------------------------------------
$base = "http://127.0.0.1:$Port"

# --- the body of a response that carries a status code ----------------------
#
# A 4xx is the case this suite cares about most -- a refusal that arrives
# without its reason is the failure in a different costume -- and the two
# PowerShells do not agree on where the body of a failed request lives.
#
# Windows PowerShell throws a WebException whose Response is an
# HttpWebResponse, and its body is a stream. PowerShell 7 throws an
# HttpResponseException whose Response is an HttpResponseMessage, whose body
# is in Content and which has no stream at all. A reader that knows only the
# first shape reads every error on PowerShell 7 as an empty body -- which is
# exactly what happened: the CI runner reported seven empty error bodies
# while the server was sending them correctly all along.
function Read-ErrorBody {
  param($ErrorRecord)
  $response = $ErrorRecord.Exception.Response
  if ($null -ne $response) {
    $content = $response.PSObject.Properties['Content']
    if ($null -ne $content -and $null -ne $content.Value) {
      try { return [string]$content.Value.ReadAsStringAsync().Result } catch { }
    }
    try {
      $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
      $text = $reader.ReadToEnd()
      $reader.Close()
      return $text
    } catch { }
  }
  # Some versions put the body in the error record's own detail.
  if ($null -ne $ErrorRecord.ErrorDetails -and
      $null -ne $ErrorRecord.ErrorDetails.Message) {
    return [string]$ErrorRecord.ErrorDetails.Message
  }
  return ""
}

function Invoke-Api {
  param(
    [string]$Method = "GET",
    [string]$Path,
    [string]$Body = $null,
    [int]$TimeoutSec = 20
  )
  $params = @{
    Uri         = "$base$Path"
    Method      = $Method
    UseBasicParsing = $true
    TimeoutSec  = $TimeoutSec
  }
  # `[string]$Body = $null` is an *empty string*, not a null: PowerShell casts
  # $null to [string] as "". Testing `$null -ne $Body` therefore always adds a
  # body, and `Invoke-WebRequest` refuses a body on a GET -- "cannot send a
  # content-body with this predicate-type". So the emptiness is what is
  # tested, not the null.
  if (-not [string]::IsNullOrEmpty($Body)) {
    $params["Body"] = $Body
    $params["ContentType"] = "application/json"
  }
  # Where the parameter exists, a 4xx is asked not to throw: then the body is
  # where a body always is, in the response itself, and none of this depends
  # on which of the two exception shapes the PowerShell in use produces. The
  # parameter is looked up rather than assumed, because it is not in every
  # version of PowerShell 6.
  if ((Get-Command Invoke-WebRequest).Parameters.ContainsKey('SkipHttpErrorCheck')) {
    $params["SkipHttpErrorCheck"] = $true
  }
  try {
    $response = Invoke-WebRequest @params
    return @{ Status = [int]$response.StatusCode; Body = $response.Content }
  } catch {
    $ex = $_.Exception
    if ($null -ne $ex.Response) {
      return @{
        Status = [int]$ex.Response.StatusCode
        Body = Read-ErrorBody $_
        Error = ""
      }
    }
    return @{ Status = 0; Body = ""; Error = $ex.Message }
  }
}

function Get-Json {
  param([string]$Path)
  $response = Invoke-Api -Method GET -Path $Path
  if ($response.Status -eq 0) { return $null }
  try { return ($response.Body | ConvertFrom-Json) } catch { return $null }
}

function Post-Json {
  param([string]$Path, $Payload = $null)
  $body = if ($null -eq $Payload) { "{}" } else { ($Payload | ConvertTo-Json -Compress -Depth 6) }
  return Invoke-Api -Method POST -Path $Path -Body $body
}

function Put-Json {
  param([string]$Path, $Payload = $null)
  $body = if ($null -eq $Payload) { "{}" } else { ($Payload | ConvertTo-Json -Compress -Depth 6) }
  return Invoke-Api -Method PUT -Path $Path -Body $body
}

function Field {
  param($Json, [string]$Name)
  if ($null -eq $Json) { return $null }
  $property = $Json.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

# --- build and start --------------------------------------------------------
$exe = $null
if (-not $SkipBuild) {
  Write-Host "==> building the server"
  & moon build --release --target native cmd/server 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: the server did not build"; exit 1 }
}
foreach ($candidate in @(
    "_build/native/release/build/cmd/server/server.exe",
    "_build/native/release/build/cmd/server/server",
    "_build/native/debug/build/cmd/server/server.exe",
    "_build/native/debug/build/cmd/server/server")) {
  if ($null -eq $exe -and (Test-Path $candidate)) { $exe = (Resolve-Path $candidate).Path }
}
if ($null -eq $exe) { Write-Host "FAIL: no server binary found -- run without -SkipBuild"; exit 1 }

# The temporary directory is asked of the runtime rather than of the
# environment: PowerShell Core on a Linux runner has no TEMP at all, and
# `Join-Path $null` throws. One script, this machine and the runner.
$tempDir = if ([string]::IsNullOrEmpty($env:TEMP)) {
  [System.IO.Path]::GetTempPath()
} else {
  $env:TEMP
}
$tempDir = $tempDir.TrimEnd('/', '\')

$db = Join-Path $tempDir "maked_integration.db"
$dist = Join-Path $tempDir "maked_integration_dist"
if (Test-Path $db) { Remove-Item $db -Force }
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Path $dist | Out-Null
Copy-Item (Join-Path $repo "frontend/dist/index.html") $dist
Copy-Item (Join-Path $repo "frontend/dist/styles.css") $dist
if (Test-Path (Join-Path $repo "frontend/dist/main.js")) {
  Copy-Item (Join-Path $repo "frontend/dist/main.js") $dist
}

Write-Host "==> starting the server on port $Port"
$env:MAKED_PORT = "$Port"
$env:MAKED_DB = $db
$env:MAKED_DIST = $dist
$startArgs = @{
  FilePath               = $exe
  PassThru               = $true
  RedirectStandardOutput = (Join-Path $tempDir "maked_integration_out.log")
  RedirectStandardError  = (Join-Path $tempDir "maked_integration_err.log")
}
# `-WindowStyle` is Windows-only: on Linux it is not a parameter of
# Start-Process at all, and passing it stops the script with a message about
# the operating system. The window is hidden on Windows so that a test run
# does not flash a console at the person running it.
if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
  $startArgs["WindowStyle"] = "Hidden"
}
$server = Start-Process @startArgs

function Stop-Server {
  if ($null -ne $server -and -not $server.HasExited) {
    Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
  }
}

try {
  $ready = $false
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 250
    $probe = Invoke-Api -Method GET -Path "/api/status" -TimeoutSec 2
    if ($probe.Status -eq 200) { $ready = $true; break }
  }
  if (-not $ready) {
    Write-Host "FAIL: the server never answered on port $Port"
    Write-Host ("  binary: {0}" -f $exe)
    Write-Host ("  exited: {0}" -f $server.HasExited)
    if ($server.HasExited) {
      Write-Host ("  exit code: {0}" -f $server.ExitCode)
    }
    Write-Host ("  probe: {0}" -f (Limit $probe.Body))
    if ($probe.Error -ne "") { Write-Host ("  probe error: {0}" -f $probe.Error) }
    Write-Host "--- stdout ---"
    Get-Content (Join-Path $tempDir "maked_integration_out.log") -ErrorAction SilentlyContinue
    Write-Host "--- stderr ---"
    Get-Content (Join-Path $tempDir "maked_integration_err.log") -ErrorAction SilentlyContinue
    exit 1
  }

  Write-Host "==> running the integration tests"
  Write-Host ""

  # ── the reader, before it is relied on ───────────────────────────────────
  Write-Host "-- the reader for a failed request"
  # This comes first, and it is here rather than at the end because every
  # refusal below is read through it. A reader that cannot read an error
  # makes every refusal look like an empty one, and the suite would report
  # a server that was answering perfectly well.
  $mockBody = '{"error":"not_found"}'
  $ps7 = Read-ErrorBody (New-MockErrorRecord (New-MockMessageResponse $mockBody))
  Assert-True "the reader understands the PowerShell 7 shape" ($ps7 -like '*not_found*') `
    ("it returned: '{0}'" -f (Limit $ps7))
  $ps5 = Read-ErrorBody (New-MockErrorRecord (New-MockWebResponse $mockBody))
  Assert-True "and the Windows PowerShell shape" ($ps5 -like '*not_found*') `
    ("it returned: '{0}'" -f (Limit $ps5))
  $missing = Read-ErrorBody (New-MockErrorRecord $null)
  Assert-True "and it does not invent a body out of nothing" ($missing -eq "") `
    ("it returned: '{0}'" -f (Limit $missing))

  # ── the read paths ───────────────────────────────────────────────────────
  Write-Host "-- GET /api/status"
  $status = Get-Json "/api/status"
  Assert-True "GET /api/status returns 200" ($null -ne $status)
  Assert-Field "the status is 'ok'" $status "status" "ok"
  Assert-HasField "the page count is reported" $status "page_count"
  Assert-ArrayLength "the five domains are listed" $status "domains" 5

  Write-Host ""
  Write-Host "-- GET /api/pages"
  $pages = Get-Json "/api/pages"
  Assert-True "GET /api/pages returns a list" ($null -ne $pages)
  Assert-True "the page list holds the nine seeded pages" (@(Field $pages "pages").Count -ge 9)

  Write-Host ""
  Write-Host "-- GET /api/pages/:slug"
  $model = Get-Json "/api/pages/model"
  Assert-Field "the model page is 'model'" $model "slug" "model"
  Assert-Field "the model page is the letter M" $model "letter" "M"
  $missing = Invoke-Api -Method GET -Path "/api/pages/nonexistent"
  Assert-Status "a page that is not there is a 404" 404 $missing
  Assert-Field "and it says which one" ($missing.Body | ConvertFrom-Json) "error" "not_found"

  Write-Host ""
  Write-Host "-- GET /api/domains"
  $domains = Get-Json "/api/domains"
  Assert-ArrayLength "the five domains are listed in ring order" $domains "domains" 5

  Write-Host ""
  Write-Host "-- GET /api/bootstrap"
  $boot = Get-Json "/api/bootstrap"
  Assert-HasField "the pages come with it" $boot "pages"
  Assert-HasField "the workspace entries come with it" $boot "entries"
  Assert-HasField "the session state comes with it" $boot "session_state"
  $bootState = Field $boot "session_state"
  Assert-HasField "the session state carries the list" $bootState "sessions"
  Assert-HasField "the session state carries the path" $bootState "path"

  # ── the workspace ────────────────────────────────────────────────────────
  Write-Host ""
  Write-Host "-- the workspace"
  $created = Post-Json "/api/entries" @{ domain = "M"; title = "the model I use"; body = "a linear fit on 200 rows" }
  Assert-Status "creating a record is a 201" 201 $created
  $entry = (Field ($created.Body | ConvertFrom-Json) "entry")
  Assert-Field "the record keeps its domain" $entry "domain" "M"
  Assert-Field "the record keeps its title" $entry "title" "the model I use"
  $entryId = Field $entry "id"

  $refused = Post-Json "/api/entries" @{ domain = "Z"; title = "wrong domain" }
  Assert-Status "a record in a domain that is not one of the five is refused" 400 $refused
  $refusal = $refused.Body | ConvertFrom-Json
  Assert-Field "and the refusal says so" $refusal "error" "invalid_entry"
  Assert-FieldNotEmpty "and gives a reason" $refusal "reason"

  $blank = Post-Json "/api/entries" @{ domain = "M"; title = "   " }
  Assert-Status "a record with a blank title is refused" 400 $blank

  $list = Get-Json "/api/entries"
  Assert-True "the record is in the list" (@(Field $list "entries").Count -ge 1)

  $deleted = Invoke-Api -Method DELETE -Path "/api/entries/$entryId"
  Assert-Status "deleting a record is a 200" 200 $deleted
  $again = Invoke-Api -Method DELETE -Path "/api/entries/$entryId"
  Assert-Status "deleting it again is a 404" 404 $again

  # ── the loop ─────────────────────────────────────────────────────────────
  Write-Host ""
  Write-Host "-- the loop"
  $loop = Get-Json "/api/loop/status"
  Assert-HasField "the status names the current domain" $loop "current_domain"
  Assert-HasField "the status carries the open slots" $loop "open_slots"
  Assert-HasField "the status carries the eight-slot vocabulary" $loop "slots"
  Assert-ArrayLength "the vocabulary is eight slots long" $loop "slots" 8

  $step = Post-Json "/api/loop/step"
  Assert-Status "a step is a 200" 200 $step
  $afterStep = $step.Body | ConvertFrom-Json
  Assert-True "and the history grew" ((Field $afterStep "history_length") -ge 1)
  # The step's answer carries the session state as well as the loop status,
  # so that the panel's step count and its summary of the run are the ones
  # this step produced. They used to be the ones from start-up, and the count
  # stopped moving after the first click.
  Assert-HasField "and the session state comes with it" $afterStep "session_state"
  $stepState = Field $afterStep "session_state"
  Assert-HasField "and the path in it" $stepState "path"
  Assert-HasField "and the summary in it" $stepState "summary"

  $named = Post-Json "/api/loop/step/act"
  Assert-Status "a step by a named slot is a 200" 200 $named
  $unknown = Post-Json "/api/loop/step/not-a-slot"
  Assert-Status "a step by a slot that does not exist is a 400" 400 $unknown
  Assert-Field "and says which one" ($unknown.Body | ConvertFrom-Json) "error" "unknown_slot"

  $continuations = Get-Json "/api/loop/continuations?depth=2"
  Assert-HasField "the continuations are listed" $continuations "continuations"

  $mode = Post-Json "/api/loop/mode/free"
  Assert-Status "switching mode is a 200" 200 $mode
  Assert-Field "and the mode changed" ($mode.Body | ConvertFrom-Json) "mode" "free"
  $null = Post-Json "/api/loop/mode/structured"
  $badMode = Post-Json "/api/loop/mode/sideways"
  Assert-Status "an unknown mode is a 400" 400 $badMode

  $reset = Post-Json "/api/loop/reset"
  Assert-Status "a reset is a 200" 200 $reset
  Assert-Field "and the history is empty again" ($reset.Body | ConvertFrom-Json) "history_length" 0

  # ── the way out of a position the table declined to decide ───────────────
  # Six steps of the ring bring the cursor back to the model formulator, and
  # its drive slot there is the one the table will not choose from. The run
  # is stuck: the same step, over and over. The candidates the table offered
  # are the way out, and picking one is the reader answering the table's
  # question rather than the machine inventing an edge.
  for ($i = 0; $i -lt 6; $i++) {
    $null = Post-Json "/api/loop/step"
  }
  $wedged = Get-Json "/api/loop/status"
  Assert-True "the ring comes back to a position the table will not decide" ($wedged.undecided -eq $true)
  $offered = @($wedged.open_slots | Where-Object { $_.outcome -eq "Undecided" })
  Assert-True "and the table offers candidates there" ($offered.Count -ge 1)
  $candidates = @($offered[0].targets)
  Assert-True "and there is more than one of them" ($candidates.Count -ge 2)
  $slot = $offered[0].name
  $target = @($candidates[0])[0]

  # The outcome travels as a label *and* a kind. The label is what a reader
  # sees; the kind is what a client matches on, so a client never has to
  # recognise the word "Undecided" to know the model declined to choose --
  # which matters the moment somebody renames the model.
  Assert-Field "and the undecided branch says which kind of edge it is" $offered[0] "outcome_kind" "open"
  $wedgedKinds = @($wedged.open_slots | ForEach-Object { $_.outcome_kind })
  Assert-True "and every slot it offers says what kind of edge it is" `
    (@($wedgedKinds | Where-Object { -not $_ }).Count -eq 0)

  # A candidate can be named by the model's id as well as by the label the
  # panel shows. The two are different strings -- the id is a slug of the
  # label -- and the id is what /api/model hands out, so a client that read
  # it from there has to be able to post it back.
  $servedModel = (Invoke-Api -Method GET -Path "/api/model").Body | ConvertFrom-Json
  $targetId = ($servedModel.positions | Where-Object { $_.label -eq $target } | Select-Object -First 1).id
  Assert-True "and the model gives that candidate an id" ($null -ne $targetId)
  $byId = Post-Json "/api/loop/step/$slot" @{ target = $targetId }
  Assert-Status "a candidate named by its id is accepted" 200 $byId

  # Back to the same branch, to check the label on the button is accepted too.
  # Only one of the two spellings is ever on the button, and both have to work.
  $null = Post-Json "/api/loop/reset"
  for ($i = 0; $i -lt 6; $i++) {
    $null = Post-Json "/api/loop/step"
  }
  $wedged = Get-Json "/api/loop/status"
  $offered = @($wedged.open_slots | Where-Object { $_.outcome -eq "Undecided" })
  $candidates = @($offered[0].targets)
  $slot = $offered[0].name
  $target = @($candidates[0])[0]
  $before = "$($wedged.current_domain) $($wedged.current_position)"
  $chosen = Post-Json "/api/loop/step/$slot" @{ target = $target }
  Assert-Status "choosing one of the candidates is a 200" 200 $chosen
  $after = $chosen.Body | ConvertFrom-Json
  Assert-True "and the subject moved" ("$($after.current_domain) $($after.current_position)" -ne $before)
  Assert-Field "and the step was recorded as a move" ($after.history[-1]) "outcome" "Moved"
  # A target the table does not offer is refused, and the refusal names the
  # ones it does: a reader who asked for the wrong one can see the right one.
  $wrong = Post-Json "/api/loop/step/$slot" @{ target = "Nowhere" }
  Assert-Status "a target the table does not offer is a 400" 400 $wrong
  Assert-Field "and it says so" ($wrong.Body | ConvertFrom-Json) "error" "unknown_target"

  # ── the model ─────────────────────────────────────────────────────────────
  # The machine itself, as data. It is served so that it can be read, edited
  # and handed back, which is the whole point of writing it down: a model
  # nobody can get at is not a model anybody can change.
  Write-Host ""
  Write-Host "-- the model"
  $modelResponse = Invoke-Api -Method GET -Path "/api/model"
  Assert-Status "the model is served" 200 $modelResponse
  $model = $modelResponse.Body | ConvertFrom-Json
  Assert-Field "and it says which format it is" $model "format" "maked.model.v1"
  Assert-True "and it carries the five domains" (@($model.domains).Count -eq 5)
  Assert-True "and the thirty-four positions" (@($model.positions).Count -eq 34)
  Assert-True "and the eight slots" (@($model.slots).Count -eq 8)
  Assert-True "and a rule for every pair of them" (@($model.rules).Count -eq 272)
  # A model that names a position it does not define is not a model: it is a
  # rule about nowhere. The check is that every rule refers to a position
  # the model defines -- the same rule `Model::from_json` refuses a file
  # over, checked here on the bytes that are actually served.
  $positionIds = @($model.positions | ForEach-Object { $_.id })
  $slotIds = @($model.slots | ForEach-Object { $_.id })
  $dangling = 0
  foreach ($rule in $model.rules) {
    if ($positionIds -notcontains $rule.from) { $dangling++ }
    if ($slotIds -notcontains $rule.slot) { $dangling++ }
  }
  Assert-True "and every rule is about a position and a slot the model defines" ($dangling -eq 0) `
    ("$dangling rules name something the model does not define")
  # The ids are what a URL carries, so they have to survive being one.
  Assert-True "and the position ids are safe to put in a URL" `
    (@($model.positions | Where-Object { $_.id -match '[^a-z0-9-]' }).Count -eq 0)
  # The loop runs on this model, so the slots it offers are named by the
  # model's own ids -- the same names /api/model hands out, and the same names
  # the step endpoint takes.
  $liveStatus = Get-Json "/api/loop/status"
  $liveNames = @($liveStatus.open_slots | ForEach-Object { $_.name })
  $notModelIds = @($liveNames | Where-Object { $slotIds -notcontains $_ })
  Assert-True "and the slots the loop offers are named by the model's own ids" `
    ($notModelIds.Count -eq 0) `
    ("the loop offered $($notModelIds -join ', '), which the model does not define")
  # And the position the loop reports is one the model defines, named the way
  # the model names it.
  $livePosition = Field $liveStatus "current_position"
  $liveLabels = @($model.positions | ForEach-Object { $_.label })
  Assert-True "and the position it reports is one the model defines" `
    ($liveLabels -contains $livePosition) `
    ("the loop reported '$livePosition', which the model does not define")

  # ── the sessions ─────────────────────────────────────────────────────────
  Write-Host ""
  Write-Host "-- the sessions"
  $newSession = Post-Json "/api/sessions" @{ name = "Integration run" }
  Assert-Status "creating a session is a 201" 201 $newSession
  $sessionState = $newSession.Body | ConvertFrom-Json
  $session = Field $sessionState "session"
  Assert-Field "the session carries its name" $session "name" "Integration run"
  $sessionId = Field $session "id"

  $noName = Post-Json "/api/sessions" @{ name = "  " }
  Assert-Status "a session with no name is refused" 400 $noName
  Assert-Field "and says so" ($noName.Body | ConvertFrom-Json) "error" "invalid_name"

  $null = Post-Json "/api/loop/step"
  $null = Post-Json "/api/loop/step"
  $timeline = Get-Json "/api/sessions/$sessionId"
  Assert-ArrayLength "the timeline holds the two steps that were taken" $timeline "path" 2
  $firstStep = @(Field $timeline "path")[0]
  Assert-FieldNotEmpty "each step says why it was possible" $firstStep "why"
  Assert-HasField "each step records the slot" $firstStep "slot"
  Assert-HasField "each step records the position it started from" $firstStep "position_before"
  # The sentence is the step in a reader's words: what moved, through which
  # slot, and where the cursor went next. A step that carried only the
  # labels would be the machine talking to itself.
  Assert-FieldNotEmpty "each step carries the sentence that explains it" $firstStep "narration"
  Assert-Contains "and the sentence says where it moved from" (Field $firstStep "narration") (Field $firstStep "position_before")
  Assert-Contains "and where it moved to" (Field $firstStep "narration") (Field $firstStep "position_after")
  Assert-FieldNotEmpty "the session state carries a summary of the run" $timeline "summary"
  # And the measures: whether the run is still finding ground, how far it has
  # ranged, and whether it is doing better than it was at the start. A step
  # counter cannot answer any of those, and a run that has stopped finding
  # ground looks exactly like a productive one on a step count.
  $measures = Field $timeline "metrics"
  Assert-HasField "the session state carries the measures" $measures "metrics"
  $measureList = @(Field $measures "metrics")
  Assert-True "and there are measures to read" ($measureList.Count -eq 5)
  $ground = @($measureList | Where-Object { $_.key -eq "new_ground" })[0]
  Assert-FieldNotEmpty "the new ground measure has a reading" $ground "sentence"
  Assert-True "and the reading is about new ground" ([string]$ground.sentence).Contains("had not been on before")
  Assert-HasField "the drift measure says what it is out of" @($measureList | Where-Object { $_.key -eq "position_drift" })[0] "of"
  Assert-HasField "the measures carry the comparison" $measures "comparison"

  $replay = Post-Json "/api/sessions/$sessionId/replay" @{ step = (Field $firstStep "id") }
  Assert-Status "going back to a step is a 200" 200 $replay
  Assert-ArrayLength "and the timeline is shorter" ($replay.Body | ConvertFrom-Json) "path" 1

  $branch = Post-Json "/api/sessions/$sessionId/branch" @{ step = (Field $firstStep "id"); name = "The other road" }
  Assert-Status "forking a session is a 201" 201 $branch
  $branchState = $branch.Body | ConvertFrom-Json
  Assert-Field "the fork carries its name" (Field $branchState "session") "name" "The other road"
  Assert-Field "the fork remembers where it came from" (Field $branchState "session") "parent_id" $sessionId

  # The rename is asked of the *parent* session, which is not the active one
  # any more: the fork took over. So the answer has to name the session that
  # was renamed, and not the one that happens to be live -- a response that
  # answered with the active session would look correct and be about the
  # wrong session.
  $renamed = Post-Json "/api/sessions/$sessionId/rename" @{ name = "Renamed" }
  Assert-Status "renaming a session is a 200" 200 $renamed
  $renameState = $renamed.Body | ConvertFrom-Json
  Assert-Field "and the answer names the renamed session" (Field $renameState "renamed") "name" "Renamed"
  Assert-Field "and it is the right one" (Field $renameState "renamed") "id" $sessionId
  # The list still carries it, so a client that only reads the list sees the
  # new name too.
  $renamedInList = @(Field $renameState "sessions") | Where-Object { $_.id -eq $sessionId }
  Assert-Field "and the list carries the new name" @($renamedInList)[0] "name" "Renamed"

  $markdown = Invoke-Api -Method GET -Path "/api/sessions/$sessionId/export?format=md"
  Assert-Status "the markdown export is a 200" 200 $markdown
  Assert-Contains "and it names the session" $markdown.Body "MAKED session: Renamed"
  Assert-Contains "and it has a timeline" $markdown.Body "## Timeline"
  # The document the user takes away says the same thing the page said. A
  # export that dropped the sentences would be a list of labels again, which
  # is the thing P1.5 was for. The sentence compared here is the one the API
  # served for that step, so this checks the document against the server's own
  # wording rather than against a phrase the test invented.
  Assert-Contains "and it says what each step did" $markdown.Body (Field $firstStep "narration")
  Assert-Contains "and it opens with the run so far" $markdown.Body "## The run so far"
  # The document says what the run is worth, not only what it did: the
  # measures and the comparison are in it, because a reader who has the
  # document and not the page has nothing else to judge the run by.
  Assert-Contains "and it says how the run is doing" $markdown.Body "## How the run is doing"
  Assert-Contains "and it carries the comparison" $markdown.Body "cannot be compared yet"
  $exported = Get-Json "/api/sessions/$sessionId/export?format=json"
  Assert-Field "the json export says what it is" $exported "format" "maked.session.v1"
  Assert-HasField "and carries the path" $exported "path"
  # And the summary is there for a consumer that does not want to work it out
  # from the path. It must be a sentence, not an empty string.
  Assert-HasField "and carries the summary" $exported "summary"
  Assert-True "and the summary is not empty" (-not [string]::IsNullOrEmpty([string]$exported.summary))
  # The measures travel with it too: a consumer that has the export and not
  # the page has nothing else to judge the run by.
  $exportedMeasures = Field $exported "metrics"
  Assert-HasField "and carries the measures" $exportedMeasures "metrics"
  Assert-True "and the measures are there to read" (@(Field $exportedMeasures "metrics")).Count -eq 5

  $badFormat = Invoke-Api -Method GET -Path "/api/sessions/$sessionId/export?format=xml"
  Assert-Status "an export in an unknown format is a 400" 400 $badFormat

  $sessions = Get-Json "/api/sessions"
  Assert-True "the session list holds the sessions" (@(Field $sessions "sessions").Count -ge 2)

  $drop = Invoke-Api -Method DELETE -Path "/api/sessions/$sessionId"
  Assert-Status "deleting a session is a 200" 200 $drop
  $dropAgain = Invoke-Api -Method DELETE -Path "/api/sessions/$sessionId"
  Assert-Status "deleting it again is a 404" 404 $dropAgain

  # ── the silent-failure class ─────────────────────────────────────────────
  Write-Host ""
  Write-Host "-- the silent-failure class: requests that must all come back"
  if (-not ("System.Net.Http.HttpClient" -as [type])) {
    Add-Type -AssemblyName System.Net.Http
  }
  $client = New-Object System.Net.Http.HttpClient
  $client.Timeout = [TimeSpan]::FromSeconds(30)

  # Eight GETs at once. The old bug was two GETs in flight at start-up:
  # sometimes neither answer came back, and the screen sat on "Loading..."
  # with nothing in the console.
  $gets = @()
  for ($i = 0; $i -lt 8; $i++) {
    $gets += $client.GetAsync("$base/api/loop/status")
  }
  [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$gets)
  $answered = 0
  foreach ($task in $gets) {
    if ($task.Result.StatusCode.value__ -eq 200 -and $task.Result.Content.ReadAsStringAsync().Result.Length -gt 0) {
      $answered += 1
    }
  }
  Assert-True "eight concurrent GETs all came back with a body" ($answered -eq 8) `
    ("only {0} of 8 answered" -f $answered)

  # Eight POSTs at once. The stronger assertion is not that the responses
  # came back -- it is that the server ended up with all eight steps. A lost
  # response and a lost write are the same bug seen from two ends, and this
  # is the end that matters.
  #
  # Two counts are kept, because they are kept in two places. The loop's
  # history is in memory and the session's steps are on the disk, and a write
  # that is lost on the way to the disk is lost for good: the screen would
  # look right until the process ended, and then the walk would be gone.
  $activeId = Field (Get-Json "/api/sessions") "active_session_id"
  $pathBefore = @((Field (Get-Json "/api/sessions/$activeId") "path")).Count
  $before = Field (Get-Json "/api/loop/status") "history_length"
  $posts = @()
  for ($i = 0; $i -lt 8; $i++) {
    $content = New-Object System.Net.Http.StringContent("{}", [System.Text.Encoding]::UTF8, "application/json")
    $posts += $client.PostAsync("$base/api/loop/step", $content)
  }
  [System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]$posts)
  $postAnswered = 0
  foreach ($task in $posts) {
    if ($task.Result.StatusCode.value__ -eq 200 -and $task.Result.Content.ReadAsStringAsync().Result.Length -gt 0) {
      $postAnswered += 1
    }
  }
  Assert-True "eight concurrent POSTs all came back with a body" ($postAnswered -eq 8) `
    ("only {0} of 8 answered" -f $postAnswered)
  $after = Field (Get-Json "/api/loop/status") "history_length"
  Assert-True "and the server ended up with all eight of them" ($after -eq ($before + 8)) `
    ("the history went from {0} to {1}, not {2}" -f $before, $after, ($before + 8))
  $pathAfter = @((Field (Get-Json "/api/sessions/$activeId") "path")).Count
  Assert-True "and all eight of them were written down" ($pathAfter -eq ($pathBefore + 8)) `
    ("the timeline went from {0} steps to {1}, not {2}" -f $pathBefore, $pathAfter, ($pathBefore + 8))

  # A GET immediately followed by a POST: the shape the client actually uses
  # when it chains one request from the answer of another.
  $chainGet = Invoke-Api -Method GET -Path "/api/loop/status"
  $chainPost = Post-Json "/api/loop/step"
  Assert-Status "a GET followed by a POST: the GET answers" 200 $chainGet
  Assert-Status "a GET followed by a POST: the POST answers" 200 $chainPost

  # A refused POST has to bring its reason back, not just its status code.
  # A refusal that arrives as a 400 with an empty body is the "button is
  # broken but it does not say why" failure, in a different costume.
  $refusedPost = Post-Json "/api/entries" @{ domain = "Q"; title = "x" }
  Assert-Status "a refused POST answers with its status" 400 $refusedPost
  $refusedBody = $refusedPost.Body | ConvertFrom-Json
  Assert-FieldNotEmpty "and with the reason it was refused" $refusedBody "reason"

  # ── the client-side anti-pattern that caused it ──────────────────────────
  Write-Host ""
  Write-Host "-- the client must not batch its requests"
  $appSource = Get-Content (Join-Path $repo "frontend/app.mbt") -Raw
  # The check is about the code, not about the prose around it. A comment
  # that says "never with @cmd.batch" is the opposite of a violation, and a
  # plain substring search cannot tell the two apart -- it reads the comment
  # as the crime. So the comments are dropped before the search.
  $appCode = Remove-Comments $appSource
  Assert-True "the frontend does not use @cmd.batch" ($appCode -notmatch '@cmd\.batch') `
    "@cmd.batch is the thing that froze the page; issue requests one at a time"
  if ($appCode -match '(?s)init=fn\(emit\)\s*\{(.*?)\n\s*update~') {
    $initBlock = $Matches[1]
    $initRequests = ([regex]::Matches($initBlock, '@http\.(get|post|delete)')).Count
    Assert-True "the start-up issues exactly one request" ($initRequests -eq 1) `
      ("the start-up issues {0} requests" -f $initRequests)
  } else {
    Assert-True "the start-up issues exactly one request" $false "the init block could not be found"
  }

  # ── the static layer ─────────────────────────────────────────────────────
  Write-Host ""
  Write-Host "-- the static layer"
  $root = Invoke-Api -Method GET -Path "/"
  Assert-Status "the browser shell is served at /" 200 $root
  Assert-Contains "and it is HTML" $root.Body "<!DOCTYPE html>"
  $deep = Invoke-Api -Method GET -Path "/sessions"
  Assert-Status "a deep link is served the shell too" 200 $deep
  Assert-Contains "and it is HTML" $deep.Body "<!DOCTYPE html>"
  $apiMiss = Invoke-Api -Method GET -Path "/api/nonexistent"
  Assert-Status "an API path that is not a route is a 404" 404 $apiMiss
  Assert-Contains "and it is JSON, not the shell" $apiMiss.Body "not_found"
  $bundle = Invoke-Api -Method GET -Path "/main.js"
  Assert-Status "the browser bundle is served" 200 $bundle
  Assert-True "and it is not empty" ($bundle.Body.Length -gt 1000)
  # The bundle is a build artefact, and a stale one fails silently: the
  # server would answer every request correctly while the page in front of
  # the reader had no way out in it. The way out has to be in the bytes that
  # are actually served, not only in the source they were built from.
  Assert-Contains "and the way out is in the bundle that is served" $bundle.Body "maked-loop-target"
  Assert-Contains "and the endpoint its buttons post to is in it too" $bundle.Body "/api/loop/step/"

  # ── a model of your own ───────────────────────────────────────────────────
  # The point of the machine being data: point MAKED at a file and it runs
  # that machine, not the built-in one.
  #
  # A second server, on another port with MAKED_MODEL set, is the only
  # honest way to check that. The model is global to a process, so the
  # server already running cannot be the one that proves it -- and a check
  # that quietly tested the built-in model would pass whatever the file
  # said.
  #
  # The same machine is checked twice, once in each of the two syntaxes a
  # model file can be written in. A machine that reads as JSON and not as
  # YAML is half a machine, and the two files here are the same machine --
  # so every check below has to pass for both of them.
  function Test-OwnModel {
    param([string]$ModelFile, [string]$Label, [int]$ModelPort)

    Assert-True ("the {0} example model ships with the repository" -f $Label) `
      (Test-Path $ModelFile)
    if (-not (Test-Path $ModelFile)) { return }

    $modelArgs = @{
      FilePath               = $exe
      PassThru               = $true
      RedirectStandardOutput = (Join-Path $tempDir ("maked_integration_model_{0}_out.log" -f $ModelPort))
      RedirectStandardError  = (Join-Path $tempDir ("maked_integration_model_{0}_err.log" -f $ModelPort))
    }
    if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
      $modelArgs["WindowStyle"] = "Hidden"
    }
    $savedModel = $env:MAKED_MODEL
    $savedPort = $env:MAKED_PORT
    $savedDb = $env:MAKED_DB
    $savedBase = $script:base
    $env:MAKED_MODEL = $ModelFile
    $env:MAKED_PORT = "$ModelPort"
    $env:MAKED_DB = (Join-Path $tempDir ("maked_integration_model_{0}.db" -f $ModelPort))
    $script:base = "http://127.0.0.1:$ModelPort"
    $modelServer = Start-Process @modelArgs
    try {
      $modelReady = $false
      for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 250
        $probe = Invoke-Api -Method GET -Path "/api/status" -TimeoutSec 2
        if ($probe.Status -eq 200) { $modelReady = $true; break }
      }
      Assert-True ("the server starts with the {0} model file" -f $Label) $modelReady
      if ($modelReady) {
        $own = (Invoke-Api -Method GET -Path "/api/model").Body | ConvertFrom-Json
        Assert-Field ("and it is the model in the {0} file" -f $Label) $own "name" "Product iteration"
        Assert-True ("and it has that model's three domains" -f $Label) (@($own.domains).Count -eq 3)
        Assert-True ("and that model's seven positions" -f $Label) (@($own.positions).Count -eq 7)
        Assert-True ("and that model's four slots" -f $Label) (@($own.slots).Count -eq 4)
        # The loop runs on it: the first domain of the file, at its anchor.
        $ownStatus = Get-Json "/api/loop/status"
        Assert-Field ("and the loop starts in that model's first domain" -f $Label) $ownStatus "current_domain" "I"
        Assert-Field ("at that model's first position" -f $Label) $ownStatus "current_position" "Raw idea"
        # And the names a reader sees are the file's, not MAKED's.
        Assert-Field ("and the domain is the one the file names" -f $Label) $ownStatus "current_title" "Idea"
        # The lookahead is worked out from that model's rules.
        $ownContinuations = Get-Json "/api/loop/continuations?depth=2"
        Assert-True ("and the file's own continuations are offered" -f $Label) `
          (@($ownContinuations.continuations).Count -ge 1)
      }
    } finally {
      if ($null -ne $modelServer -and -not $modelServer.HasExited) {
        Stop-Process -Id $modelServer.Id -Force -ErrorAction SilentlyContinue
      }
      $env:MAKED_MODEL = $savedModel
      $env:MAKED_PORT = $savedPort
      $env:MAKED_DB = $savedDb
      $script:base = $savedBase
    }
  }

  Write-Host ""
  Write-Host "-- a model of your own"
  Test-OwnModel (Join-Path $repo "models/product-iteration.json") "JSON" ($Port + 1)
  Write-Host ""
  Write-Host "-- the same model, written in YAML"
  Test-OwnModel (Join-Path $repo "models/product-iteration.yaml") "YAML" ($Port + 2)

  # ── the mapping table ─────────────────────────────────────────────────────
  # The table that says what a document means is data, and the check is that
  # the server hands it over, takes a new one, and writes it back.
  Write-Host ""
  Write-Host "-- the mapping table"
  $builtinTable = Get-Json "/api/research/config"
  Assert-True "the built-in table is served" ($null -ne $builtinTable)
  Assert-HasField "and it has a table" $builtinTable "config"
  Assert-True "and the table has rules" (@((Field $builtinTable "config").mapping).Count -ge 1)
  Assert-HasField "and it has a fallback" (Field $builtinTable "config") "fallback"
  # The built-in table is not in a file, so it cannot be written back, and
  # saying so is better than accepting an edit and losing it.
  Assert-Field "and the built-in table has no file" $builtinTable "path" ""
  Assert-Field "and it says it cannot be written back" $builtinTable "writable" $false

  # A table that names a slot the running model does not have is a rule
  # about nowhere, and it is refused with the reason.
  $badTable = @'
{
  "format": "maked.research.v1",
  "mapping": [
    { "keywords": ["reproduce"], "label": "A reproduction", "slot": "not-a-slot" }
  ],
  "fallback": { "label": "Anything else", "slot": "act" }
}
'@
  $refused = Invoke-Api -Method PUT -Path "/api/research/config" -Body $badTable
  Assert-Status "a table naming a slot the model does not have is refused" 400 $refused
  Assert-Contains "and the reason says which slot" $refused.Body "not-a-slot"
  # The table that was running keeps running.
  $afterRefusal = Get-Json "/api/research/config"
  Assert-True "and the running table is unchanged" `
    ((Field $afterRefusal "config").mapping[0].slot -ne "not-a-slot")

  # ── a table of your own ────────────────────────────────────────────────────
  # A third server, with a model file and a table file, is the only honest
  # way to check that the table is read from the file: the table is global
  # to a process, and the server already running has the built-in one.
  #
  # The table file is a copy in the temp directory, because the check writes
  # back to it -- and the file in the repository is not a scratch pad.
  function Test-ResearchTable {
    param([string]$ModelFile, [string]$TableFile, [int]$TablePort)

    Assert-True "the example table ships with the repository" (Test-Path $TableFile)
    if (-not (Test-Path $TableFile)) { return }
    $copy = Join-Path $tempDir ("maked_integration_table_{0}.yaml" -f $TablePort)
    Copy-Item $TableFile $copy -Force

    $tableArgs = @{
      FilePath               = $exe
      PassThru               = $true
      RedirectStandardOutput = (Join-Path $tempDir ("maked_integration_table_{0}_out.log" -f $TablePort))
      RedirectStandardError  = (Join-Path $tempDir ("maked_integration_table_{0}_err.log" -f $TablePort))
    }
    if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
      $tableArgs["WindowStyle"] = "Hidden"
    }
    $savedModel = $env:MAKED_MODEL
    $savedResearch = $env:MAKED_RESEARCH
    $savedPort = $env:MAKED_PORT
    $savedDb = $env:MAKED_DB
    $savedBase = $script:base
    $env:MAKED_MODEL = $ModelFile
    $env:MAKED_RESEARCH = $copy
    $env:MAKED_PORT = "$TablePort"
    $env:MAKED_DB = (Join-Path $tempDir ("maked_integration_table_{0}.db" -f $TablePort))
    $script:base = "http://127.0.0.1:$TablePort"
    $tableServer = Start-Process @tableArgs
    try {
      $tableReady = $false
      for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 250
        $probe = Invoke-Api -Method GET -Path "/api/status" -TimeoutSec 2
        if ($probe.Status -eq 200) { $tableReady = $true; break }
      }
      Assert-True "the server starts with a table file" $tableReady
      if ($tableReady) {
        $own = Get-Json "/api/research/config"
        Assert-True "and the table is the one in the file" `
          ((Field $own "config").mapping[0].label -eq "A question worth asking")
        Assert-Field "and the file it came from is remembered" $own "path" $copy
        Assert-Field "and it can be written back" $own "writable" $true

        # A table of the reader's own replaces it, and the one that runs is
        # the one that was just put.
        $newTable = @'
{
  "format": "maked.research.v1",
  "mapping": [
    { "keywords": ["reproduce"], "label": "A reproduction", "slot": "build" }
  ],
  "fallback": { "label": "Anything else", "slot": "scope" }
}
'@
        $put = Invoke-Api -Method PUT -Path "/api/research/config" -Body $newTable
        Assert-Status "a new table is accepted" 200 $put
        $after = Get-Json "/api/research/config"
        Assert-Field "and the table that runs is the one that was put" `
          (Field $after "config").mapping[0].label "A reproduction"
        # And it was written back, so the edit survives the server stopping.
        $written = Get-Content $copy -Raw
        Assert-Contains "and it was written back to the file" $written "A reproduction"
        Assert-Contains "and in the syntax the file's name asks for" $written "maked.research.v1"
        # A YAML file written back as YAML, not as JSON: the braces would
        # say otherwise.
        Assert-True "and the file is still YAML" (-not $written.TrimStart().StartsWith("{"))
      }
    } finally {
      if ($null -ne $tableServer -and -not $tableServer.HasExited) {
        Stop-Process -Id $tableServer.Id -Force -ErrorAction SilentlyContinue
      }
      $env:MAKED_MODEL = $savedModel
      $env:MAKED_RESEARCH = $savedResearch
      $env:MAKED_PORT = $savedPort
      $env:MAKED_DB = $savedDb
      $script:base = $savedBase
    }
  }

  # --- a corpus of your own ---------------------------------------------------
  #
  # The corpus is the reader's own documents: a folder of notes, a Zotero
  # export, a PDF. The server is started with MAKED_CORPUS naming a corpus
  # file that points at such a folder, and the checks are that the documents
  # the server reads are those notes -- not the arxiv papers it would read
  # when there is no corpus. A server that quietly falls back to arxiv would
  # show a full panel of papers while the reader's own documents went
  # unread, and that is the failure this project exists to remove.
  function Test-ResearchCorpus {
    param([int]$CorpusPort)
    if (-not (Test-Path $exe)) { return }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $notesDir = Join-Path $tempDir ("maked_integration_notes_{0}" -f $CorpusPort)
    New-Item -ItemType Directory -Path $notesDir -Force | Out-Null
    $notePath = Join-Path $notesDir "launch.md"
    [System.IO.File]::WriteAllText(
      $notePath,
      "# What we learned`n`nWe fail at scale, and we propose a new method.`n",
      $utf8)
    $corpusPath = Join-Path $tempDir ("maked_integration_corpus_{0}.yaml" -f $CorpusPort)
    # Forward slashes, because the corpus file is YAML and a Windows path
    # full of backslashes is a path nobody can read in a file.
    $notesPath = $notesDir -replace '\\', '/'
    [System.IO.File]::WriteAllText(
      $corpusPath,
      ("format: maked.corpus.v1`nsource:`n  kind: local`n  path: {0}`n  max_results: 10`n" -f $notesPath),
      $utf8)

    $corpusArgs = @{
      FilePath               = $exe
      PassThru               = $true
      RedirectStandardOutput = (Join-Path $tempDir ("maked_integration_corpus_{0}_out.log" -f $CorpusPort))
      RedirectStandardError  = (Join-Path $tempDir ("maked_integration_corpus_{0}_err.log" -f $CorpusPort))
    }
    if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
      $corpusArgs["WindowStyle"] = "Hidden"
    }
    $savedCorpus = $env:MAKED_CORPUS
    $savedPort = $env:MAKED_PORT
    $savedDb = $env:MAKED_DB
    $savedBase = $script:base
    $env:MAKED_CORPUS = $corpusPath
    $env:MAKED_PORT = "$CorpusPort"
    $env:MAKED_DB = (Join-Path $tempDir ("maked_integration_corpus_{0}.db" -f $CorpusPort))
    $script:base = "http://127.0.0.1:$CorpusPort"
    $corpusServer = Start-Process @corpusArgs
    try {
      $corpusReady = $false
      for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 250
        $probe = Invoke-Api -Method GET -Path "/api/status" -TimeoutSec 2
        if ($probe.Status -eq 200) { $corpusReady = $true; break }
      }
      Assert-True "the server starts with a corpus file" $corpusReady
      if ($corpusReady) {
        $corpus = Get-Json "/api/research/corpus"
        Assert-True "and the corpus is the one in the file" `
          ((Field $corpus "corpus").source.kind -eq "local")
        Assert-Field "and the file it came from is remembered" $corpus "path" $corpusPath
        Assert-Field "and it can be written back" $corpus "writable" $true

        $documents = Get-Json "/api/research/documents"
        Assert-ArrayLength "and the documents are the reader's own" $documents "documents" 1
        Assert-True "and the first one is the note" `
          (((Field $documents "documents")[0]).title -eq "What we learned")
        Assert-True "and the corpus it came from is said out loud" `
          ((Field $documents "corpus").source -like "*maked_integration_notes*")

        # The document drives the loop: the built-in table's "fail" rule
        # fires on it, and the built-in model has the slot it names.
        $drive = Post-Json "/api/research/drive"
        Assert-Status "the corpus drives the loop" 200 $drive
        $driveJson = ConvertFrom-Json $drive.Body
        Assert-True "and the document was driven" `
          ((Field $driveJson "documents_driven") -ge 1)

        # A corpus of one document cannot support an estimate, and the
        # endpoint says so in words rather than reporting a zero. A zero
        # there reads as "no effect" rather than "not enough to say", and
        # the refusal is a 200: the request was fine, the corpus was not
        # big enough, and a person is owed the reason.
        $smallCausal = Get-Json "/api/research/causal"
        $smallBody = Field $smallCausal "causal"
        Assert-True "a corpus too small to estimate is refused" `
          ((Field $smallBody "refused") -ne "")
        Assert-True "and the reason says what was needed" `
          ((Field $smallBody "reason") -like "*10*")
        Assert-True "and there is no effect to read" `
          ($null -eq (Field $smallBody "theta"))

        # A corpus that names a source it cannot read is refused, with the
        # reason, and the corpus that was running keeps running.
        $bad = Put-Json "/api/research/corpus" `
          @{ format = "maked.corpus.v1"; source = @{ kind = "local" } }
        Assert-Status "a corpus with no path is refused" 400 $bad
        Assert-True "and the reason is given" `
          (((ConvertFrom-Json $bad.Body).reason) -like "*path*")
        $after = Get-Json "/api/research/corpus"
        Assert-True "and the corpus that was running still runs" `
          ((Field $after "corpus").source.kind -eq "local")

        # A new corpus is accepted, installed and written back.
        $newCorpus = @'
{
  "format": "maked.corpus.v1",
  "source": { "kind": "arxiv", "query": "all:snns", "max_results": 5 }
}
'@
        $put = Invoke-Api -Method PUT -Path "/api/research/corpus" -Body $newCorpus
        Assert-Status "a new corpus is accepted" 200 $put
        $after = Get-Json "/api/research/corpus"
        Assert-True "and the corpus that runs is the one that was put" `
          ((Field $after "corpus").source.kind -eq "arxiv")
        $written = Get-Content $corpusPath -Raw
        Assert-Contains "and it was written back to the file" $written "all:snns"
      }
    } finally {
      if ($null -ne $corpusServer -and -not $corpusServer.HasExited) {
        Stop-Process -Id $corpusServer.Id -Force -ErrorAction SilentlyContinue
      }
      $env:MAKED_CORPUS = $savedCorpus
      $env:MAKED_PORT = $savedPort
      $env:MAKED_DB = $savedDb
      $script:base = $savedBase
    }
  }

  # --- what the causal estimate rests on ---------------------------------
  #
  # A causal number is the first thing a reader argues with, and the first
  # question about it is "what did you control for?". These checks are over
  # real HTTP: the endpoint has to answer with the named treatment and
  # outcome, the named variables, the balance between the two groups, the
  # overlap and the sensitivity interval -- and not with a bare number.
  function Test-ResearchCausal {
    param([int]$CausalPort)
    if (-not (Test-Path $exe)) { return }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $notesDir = Join-Path $tempDir ("maked_integration_causal_{0}" -f $CausalPort)
    New-Item -ItemType Directory -Path $notesDir -Force | Out-Null
    # Sixteen notes, half of them claiming to be new. The two groups are
    # given the same title lengths and the same abstract lengths on purpose:
    # a corpus whose two groups can be told apart by nothing but the claim
    # is a corpus that can support an estimate, and a corpus whose groups
    # differ in every shape is refused -- which is a different check.
    for ($i = 0; $i -lt 16; $i++) {
      $target = 24 + ([int]($i / 2) % 2)
      if ($i % 2 -eq 0) {
        $raw = "A novel method for SNN $i"
        $body = "We propose a new method and introduce it here."
      } else {
        $raw = "A plain report on SNN $i"
        $body = "We measure a thing and report it plainly.."
      }
      $title = $raw.PadRight($target, ".")
      $text = $body.PadRight(46, ".")
      [System.IO.File]::WriteAllText(
        (Join-Path $notesDir ("note_{0}.md" -f $i)),
        ("# {0}`n`n{1}`n" -f $title, $text),
        $utf8)
    }
    $corpusPath = Join-Path $tempDir ("maked_integration_causal_{0}.yaml" -f $CausalPort)
    $notesPath = $notesDir -replace '\\', '/'
    [System.IO.File]::WriteAllText(
      $corpusPath,
      ("format: maked.corpus.v1`nsource:`n  kind: local`n  path: {0}`n  max_results: 20`n" -f $notesPath),
      $utf8)

    $causalArgs = @{
      FilePath               = $exe
      PassThru               = $true
      RedirectStandardOutput = (Join-Path $tempDir ("maked_integration_causal_{0}_out.log" -f $CausalPort))
      RedirectStandardError  = (Join-Path $tempDir ("maked_integration_causal_{0}_err.log" -f $CausalPort))
    }
    if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
      $causalArgs["WindowStyle"] = "Hidden"
    }
    $savedCorpus = $env:MAKED_CORPUS
    $savedPort = $env:MAKED_PORT
    $savedDb = $env:MAKED_DB
    $savedBase = $script:base
    $env:MAKED_CORPUS = $corpusPath
    $env:MAKED_PORT = "$CausalPort"
    $env:MAKED_DB = (Join-Path $tempDir ("maked_integration_causal_{0}.db" -f $CausalPort))
    $script:base = "http://127.0.0.1:$CausalPort"
    $causalServer = Start-Process @causalArgs
    try {
      $causalReady = $false
      for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 250
        $probe = Invoke-Api -Method GET -Path "/api/status" -TimeoutSec 2
        if ($probe.Status -eq 200) { $causalReady = $true; break }
      }
      Assert-True "the server starts with a corpus for the estimate" $causalReady
      if ($causalReady) {
        $causal = Get-Json "/api/research/causal"
        $body = Field $causal "causal"
        Assert-True "the causal endpoint answers with an estimate" ($null -ne $body)
        Assert-Field "and the treatment is named" $body "treatment" "claims to be new"
        Assert-Field "and the outcome is named" $body "outcome" "impact score"
        Assert-ArrayLength "and the controlled variables are named" $body "confounders" 4
        Assert-ArrayLength "and each one has a balance row" $body "balance" 4
        Assert-True "and the estimate was made" ((Field $body "refused") -eq "")
        Assert-True "and the effect is a number and not a string" `
          ((Field $body "theta") -isnot [string])
        Assert-True "and the standard error is a number and not a string" `
          ((Field $body "se") -isnot [string])
        Assert-FieldNotEmpty "and the overlap is reported" `
          (Field $body "overlap") "reading"
        Assert-FieldNotEmpty "and the sensitivity is reported" `
          (Field $body "sensitivity") "reading"
        Assert-True "and the corpus that was read is said out loud" `
          ((Field $causal "documents_analyzed") -eq 16)
      }
    } finally {
      if ($null -ne $causalServer -and -not $causalServer.HasExited) {
        Stop-Process -Id $causalServer.Id -Force -ErrorAction SilentlyContinue
      }
      $env:MAKED_CORPUS = $savedCorpus
      $env:MAKED_PORT = $savedPort
      $env:MAKED_DB = $savedDb
      $script:base = $savedBase
    }
  }

  Write-Host ""
  Write-Host "-- a table of your own"
  Test-ResearchTable (Join-Path $repo "models/product-iteration.json") `
    (Join-Path $repo "research/product-iteration.yaml") ($Port + 3)

  Write-Host ""
  Write-Host "-- a corpus of your own"
  Test-ResearchCorpus ($Port + 4)

  Write-Host ""
  Write-Host "-- what the causal estimate rests on"
  Test-ResearchCausal ($Port + 5)
} finally {
  Stop-Server
  Start-Sleep -Milliseconds 300
  if (-not $KeepDatabase) {
    if (Test-Path $db) { Remove-Item $db -Force -ErrorAction SilentlyContinue }
    if (Test-Path $dist) { Remove-Item $dist -Recurse -Force -ErrorAction SilentlyContinue }
  }
}

Write-Host ""
Write-Host ("checks: {0} passed, {1} failed" -f $script:passed, $script:failed)
if ($script:failed -gt 0) { exit 1 }
exit 0
