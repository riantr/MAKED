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

# The collective's own numbers, as the server served them. The society section
# sets them and the end of the run reads them, after the server is gone: a
# number that nobody can ask any more is a number the document cannot be
# checked against. Minus one means "not served", which is a failure and not
# a count.
$script:collectivePositions = -1
$script:collectiveTransitions = -1

# The group's vocabulary, as the server served it: how many states the group
# machine has, and what they are called. The same reason as the collective's
# numbers: the group machine is the pyroduct package's, not this
# repository's, so the document can only be checked against it where it is.
# Minus one means "not served", which is a failure and not a count.
$script:groupStates = -1
$script:groupStateNames = @()

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
  $count = ArrayCount $Json $Field
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
    # The headers travel with the answer because a check may need to say what
    # the body claimed to be: a body that says it is UTF-8 and a body that is
    # Latin-1 are the same bytes and different words, and only the header says
    # which one the client got.
    return @{
      Status = [int]$response.StatusCode
      Body = $response.Content
      Headers = $response.Headers
    }
  } catch {
    $ex = $_.Exception
    if ($null -ne $ex.Response) {
      return @{
        Status = [int]$ex.Response.StatusCode
        Body = Read-ErrorBody $_
        Error = ""
        Headers = $null
      }
    }
    return @{ Status = 0; Body = ""; Error = $ex.Message; Headers = $null }
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

# How many entries a list field holds.
#
# This exists because `Field` cannot be used for the count: a function that
# returns an empty array hands the caller *nothing*, so an empty JSON list
# arrives as `$null` and an empty list is indistinguishable from a missing
# field. A check that says "there are no gaps" then passes for the wrong
# reason -- and a check that says "the gaps are reported" would pass for a
# field the server never sent at all.
#
# -1 means the field is not there. 0 means it is there and it is empty.
function ArrayCount {
  param($Json, [string]$Name)
  if ($null -eq $Json) { return -1 }
  $property = $Json.PSObject.Properties[$Name]
  if ($null -eq $property) { return -1 }
  return @($property.Value).Count
}

# The text of a tool's answer.
#
# A tool answers with the payload twice: as structured content and as text.
# The text is the payload as a JSON string, and it is the one an agent that
# only reads text can see, so it is the one checked here.
function ToolText {
  param($Answer)
  $content = Field (Field $Answer "result") "content"
  if ($null -eq $content) { return "" }
  $first = @($content) | Select-Object -First 1
  return (Field $first "text")
}

# --- the agent's server over stdio -------------------------------------------
#
# The agent that spawns MAKED as a subprocess talks to it over pipes, and the
# conversation is one JSON-RPC message per line. Two things about that are
# worth a test of their own.
#
# The first is that the *first* message has to be answered. A Windows client
# writes its stdin through .NET, and .NET writes a byte order mark in front of
# the first line. A mark in front of a JSON-RPC message is not JSON, so a
# server that does not drop it answers the first request with a parse error
# and every later one properly -- which reads like a server that only
# understands the second question.
#
# The second is that the answers have to come back *before* the next question
# is asked. The client is waiting, and a buffered answer that has not left
# the process looks like a server that has stopped answering.
function Invoke-StdioSession {
  param(
    [string]$Exe,
    [string]$DbPath,
    [string[]]$Lines,
    [int]$Expect,
    [int]$TimeoutSec = 30
  )
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  $psi.EnvironmentVariables["MAKED_DB"] = $DbPath
  $process = [System.Diagnostics.Process]::Start($psi)
  $errors = $process.StandardError.ReadToEndAsync()
  # The bytes go in raw. The writer that `StandardInput` hands out puts an
  # encoding preamble in front of its first line, and the bytes written here
  # land after it -- so the first message carries a byte order mark whether
  # we like it or not. One more is added on purpose: the server has to
  # answer a message with a mark in front of it, and how many marks are in
  # front of it is the client's business, not the server's.
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    $bytes = $utf8.GetBytes($Lines[$i] + "`n")
    if ($i -eq 0) {
      $mark = $utf8.GetBytes([string][char]0xFEFF)
      $marked = New-Object byte[] ($mark.Length + $bytes.Length)
      [Array]::Copy($mark, 0, $marked, 0, $mark.Length)
      [Array]::Copy($bytes, 0, $marked, $mark.Length, $bytes.Length)
      $bytes = $marked
    }
    $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
  }
  $process.StandardInput.BaseStream.Flush()
  # The answers are read one at a time, and the pipe is left open while they
  # come: a client that closes its end first is in a race the server should
  # not lose.
  $answers = New-Object System.Collections.Generic.List[string]
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $pending = $null
  while ($answers.Count -lt $Expect -and (Get-Date) -lt $deadline) {
    if ($null -eq $pending) { $pending = $process.StandardOutput.ReadLineAsync() }
    $done = [System.Threading.Tasks.Task]::WaitAny(@($pending), 1000)
    if ($done -eq 0) {
      $line = $pending.Result
      $pending = $null
      if ($null -ne $line) { $answers.Add($line) }
    }
  }
  try { $process.StandardInput.Close() } catch { }
  try { if (-not $process.HasExited) { $process.Kill() } } catch { }
  $err = ""
  try { $err = $errors.Result } catch { }
  return @{ Answers = $answers; Errors = $err }
}

# --- build and start --------------------------------------------------------
$exe = $null
if (-not $SkipBuild) {
  Write-Host "==> building the server"
  & moon build --release --target native cmd/server 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: the server did not build"; exit 1 }
  Write-Host "==> building the agent's server"
  & moon build --release --target native cmd/mcp 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: the agent's server did not build"; exit 1 }
}
foreach ($candidate in @(
    "_build/native/release/build/cmd/server/server.exe",
    "_build/native/release/build/cmd/server/server",
    "_build/native/debug/build/cmd/server/server.exe",
    "_build/native/debug/build/cmd/server/server")) {
  if ($null -eq $exe -and (Test-Path $candidate)) { $exe = (Resolve-Path $candidate).Path }
}
if ($null -eq $exe) { Write-Host "FAIL: no server binary found -- run without -SkipBuild"; exit 1 }
$mcpExe = $null
foreach ($candidate in @(
    "_build/native/release/build/cmd/mcp/mcp.exe",
    "_build/native/release/build/cmd/mcp/mcp",
    "_build/native/debug/build/cmd/mcp/mcp.exe",
    "_build/native/debug/build/cmd/mcp/mcp")) {
  if ($null -eq $mcpExe -and (Test-Path $candidate)) { $mcpExe = (Resolve-Path $candidate).Path }
}

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
  # The page list holds every page the server seeded: the five domain
  # pages, the three utility pages, the index, and the 404 page. The
  # assertion used to say "nine seeded pages" and accept anything at or
  # above nine, which was two mistakes: seed_pages() returns eight (five
  # domains and three utility pages), and the server holds ten rows once
  # the index and the 404 page are in the same table. The count is exact
  # now, because a loose one cannot tell a server that serves what it
  # seeded from a server that serves something else.
  Assert-True "the page list holds all ten seeded pages" (@(Field $pages "pages").Count -eq 10)

  Write-Host ""
  Write-Host "-- GET /api/pages/:slug"
  $model = Get-Json "/api/pages/model"
  Assert-Field "the model page is 'model'" $model "slug" "model"
  Assert-Field "the model page is the letter M" $model "letter" "M"
  $missing = Invoke-Api -Method GET -Path "/api/pages/nonexistent"
  Assert-Status "a page that is not there is a 404" 404 $missing
  Assert-Field "and it says which one" ($missing.Body | ConvertFrom-Json) "error" "not_found"

  Write-Host ""
  Write-Host "-- the pages in the other language"
  #
  # The pages were the last surface that stayed in English in a Chinese
  # interface, and the only one that also described a program that is not this
  # one: they said four of the five applications were empty scaffolds. They
  # now say what they say in the language the request asked for, and the
  # Chinese is written Chinese rather than the English with a Chinese title
  # over it.
  #
  # The expected words are code points rather than characters. This file is
  # read by Windows PowerShell as ANSI, and a non-ASCII literal in it comes
  # out mangled -- which would make the assertion compare mojibake with
  # mojibake and pass.
  $zhModel = [string]([char]0x6A21) + [char]0x578B
  $zhFormulator = [string]([char]0x6A21) + [char]0x578B + [char]0x6784 + [char]0x5EFA + [char]0x8005
  $zhTable = [string]([char]0x8FC1) + [char]0x79FB + [char]0x8868
  $chinesePages = Invoke-Api -Method GET -Path "/api/pages?lang=zh"
  Assert-Status "the page list answers in Chinese" 200 $chinesePages
  $zhPageList = $chinesePages.Body | ConvertFrom-Json
  $zhModelPage = @($zhPageList.pages) | Where-Object { $_.slug -eq "model" }
  Assert-Field "the model page is named in Chinese" $zhModelPage "title" $zhModel
  Assert-Field "and its role is in Chinese too" $zhModelPage "role" $zhFormulator
  Assert-Contains "and its prose is in Chinese" $zhModelPage.body $zhTable
  Assert-True "and no English furniture is left in the prose" `
    (-not $zhModelPage.body.Contains("transition table")) `
    ("it said '{0}'" -f $zhModelPage.body)
  Assert-True "and it does not still claim the applications are empty" `
    (-not $zhModelPage.body.Contains("scaffold")) `
    ("it said '{0}'" -f $zhModelPage.body)
  # The English page is still English: a reader who asks for nothing must get
  # what a reader who asks for nothing always got.
  Assert-Contains "and the English page still says it in English" $model.body "transition table"
  $zhOne = Get-Json "/api/pages/model?lang=zh"
  Assert-Field "one page answers in Chinese as well" $zhOne "title" $zhModel
  $zhBoot = Get-Json "/api/bootstrap?lang=zh"
  $zhBootModel = @((Field $zhBoot "pages")) | Where-Object { $_.slug -eq "model" }
  Assert-Field "and the bootstrap carries the Chinese pages" $zhBootModel "title" $zhModel
  $zhDomains = Get-Json "/api/domains?lang=zh"
  Assert-Field "and the domain list names the domains in Chinese" `
    (@(Field $zhDomains "domains"))[0] "title" $zhModel

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

  # The group's vocabulary travels with the status, so that the number of
  # group states is something a reader -- or the document check at the end of
  # this run -- can ask for, instead of a number only the document knows.
  Assert-HasField "the status carries the group's vocabulary" $loop "group_states"
  # The nulls are filtered out on purpose: a missing field arrives as a null,
  # and a null counted as a state is a state the vocabulary does not have.
  # How many states there are is not checked here -- that number belongs to
  # the document check, which compares it with what the document says.
  $groupVocabulary = @($loop.group_states | Where-Object { $null -ne $_ })
  # Kept for the document check at the end of the run, after the server is
  # gone: a number that nobody can ask any more is a number the document
  # cannot be checked against.
  $script:groupStates = $groupVocabulary.Count
  $script:groupStateNames = @($groupVocabulary | ForEach-Object { $_.name })

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

  # The document in the other language. The export is the one thing the
  # reader takes away, so a document that stayed in English would be the
  # last English surface a reader meets -- and a reader who turned the page
  # into Chinese would be handed an English document at the very end.
  #
  # The expectations are written as code points, because this file is read
  # by Windows PowerShell as ANSI: a Chinese literal in here is mojibake
  # before the script has run, and the assertion would compare mojibake
  # with Chinese and fail against a server that was right all along.
  $zhHuiHua = [string]([char]0x4F1A) + [char]0x8BDD
  $zhTimeline = [string]([char]0x65F6) + [char]0x95F4 + [char]0x7EBF
  $zhWhy = [string]([char]0x539F) + [char]0x56E0
  $zhPosition = [string]([char]0x4F4D) + [char]0x7F6E
  $zhNewGround = [string]([char]0x65B0) + [char]0x589E + [char]0x5730 + [char]0x76D8
  # The full-width colon. The document is Chinese, and a Chinese document
  # writes a full-width colon; an ASCII one in the middle of it would be a
  # piece of English furniture the size of a single character.
  $zhColon = [string]([char]0xFF1A)
  $chinese = Invoke-Api -Method GET -Path "/api/sessions/$sessionId/export?format=md&lang=zh"
  Assert-Status "the Chinese export is a 200" 200 $chinese
  Assert-Contains "and it is named in Chinese" $chinese.Body ("# MAKED " + $zhHuiHua + $zhColon)
  Assert-Contains "and it has a Chinese timeline" $chinese.Body ("## " + $zhTimeline)
  Assert-Contains "and the steps say why in Chinese" $chinese.Body ("**" + $zhWhy + $zhColon + "**")
  Assert-Contains "and the positions are named in Chinese" $chinese.Body ("**" + $zhPosition + $zhColon + "**")
  Assert-Contains "and its measures are in Chinese" $chinese.Body $zhNewGround
  Assert-True "and no English furniture is left" (-not $chinese.Body.Contains("## Timeline"))
  $chineseJson = Get-Json "/api/sessions/$sessionId/export?format=json&lang=zh"
  Assert-Field "the Chinese json export says what it is" $chineseJson "format" "maked.session.v1"
  $chineseMeasures = Field $chineseJson "metrics"
  Assert-Contains "and its measures are in Chinese too" (@(Field $chineseMeasures "metrics"))[0].label $zhNewGround

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

  # The Society layer: the collective, read over real HTTP.
  #
  # The machine is pyroduct's and the words are the vocabulary file's, and
  # this is where the two are checked against each other over the wire: the
  # machine has thirteen positions and twenty-eight moves, and a payload
  # that says so is a payload the panel can render.
  #
  # The refusal is the part worth the most attention. A move that does not
  # exist has to come back with the reason *and* with the machine: a body
  # that carried only the reason would leave the panel with nothing to show
  # but the reason, and a collective that goes blank when it refuses a move
  # is the exact failure this project exists to remove.
  function Test-Society {
    param([int]$SocietyPort)
    $response = Invoke-Api -Method GET -Path "/api/society"
    Assert-Status "the society endpoint answers" 200 $response
    $body = $response.Body | ConvertFrom-Json
    Assert-FieldNotEmpty "and the collective is standing somewhere" $body "state"
    Assert-FieldNotEmpty "and the position has a name" $body "state_label"
    Assert-FieldNotEmpty "and the position has a gloss" $body "state_gloss"
    Assert-FieldNotEmpty "and the phase is named" $body "phase"
    Assert-ArrayLength "and the machine's thirteen positions are served" $body "positions" 13
    Assert-ArrayLength "and the machine's twenty-eight moves are served" $body "transitions" 28
    Assert-True "and the moves from here are served" `
      (@(Field $body "moves").Count -gt 0)
    Assert-HasField "and the gaps are reported at all" $body "gaps"
    Assert-ArrayLength "and the built-in vocabulary has no gaps" $body "gaps" 0
    Assert-Field "and no move has been taken yet" $body "kind" ""

    # The counts the collective really has, kept for the check at the end of
    # the run. The document states them in two places, and the truth is here.
    $script:collectivePositions = @($body.positions).Count
    $script:collectiveTransitions = @($body.transitions).Count

    # The collective in the other language.
    #
    # The vocabulary file is the reader's own words and it is written in
    # English; the Chinese is pyroduct's. A reader who asks for Chinese must
    # get the machine's own names rather than the file's, and a reader who
    # asks for nothing must get the file's.
    $chinese = Invoke-Api -Method GET -Path "/api/society?lang=zh"
    Assert-Status "the society endpoint answers in Chinese" 200 $chinese
    $zh = $chinese.Body | ConvertFrom-Json
    # The expected words are written as code points rather than as characters.
    #
    # This file is read by Windows PowerShell as ANSI, and a non-ASCII
    # literal in it comes out mangled -- which would make the assertion
    # compare mojibake with mojibake and pass. The code points are the same
    # characters, and they cannot be misread.
    $zhWorld = [string]([char]0x4E16) + [char]0x754C
    $zhLifeworld = [string]([char]0x751F) + [char]0x6D3B + [char]0x4E16 + [char]0x754C
    Assert-Field "and the collective is named in the table's own Chinese" `
      $zh "state_label" $zhWorld
    Assert-Contains "and the gloss is Chinese as well" `
      (Field $zh "state_gloss") $zhLifeworld
    $zhMoves = @(Field $zh "moves")
    Assert-True "and the moves from here are served in Chinese" `
      ($zhMoves.Count -gt 0)
    Assert-True "and the first move is not the English one" `
      ($zhMoves[0].trigger_label -ne "Raise a validity claim")
    Assert-Field "and the English is still the English" `
      $body "state_label" "Lifeworld"

    $moved = Post-Json "/api/society/step" @{ trigger = "RaiseClaims" }
    Assert-Status "a move for the collective is accepted" 200 $moved
    $after = $moved.Body | ConvertFrom-Json
    Assert-Field "and the collective moved" $after "kind" "moved"
    Assert-Field "and it moved from where it stood" $after "from" "World"
    Assert-FieldNotEmpty "and the place it came from has a name" $after "from_label"
    Assert-FieldNotEmpty "and it is standing somewhere new" $after "state_label"
    Assert-True "and the moves from the new place are served" `
      (@(Field $after "moves").Count -gt 0)
    Assert-ArrayLength "and the machine is still there" $after "positions" 13

    $refused = Post-Json "/api/society/step" @{ trigger = "NotAMove" }
    Assert-Status "a move that does not exist is answered, not thrown" 200 $refused
    $block = $refused.Body | ConvertFrom-Json
    Assert-Field "and the answer says the collective did not move" $block "kind" "block"
    Assert-FieldNotEmpty "and the answer says why" $block "reason"
    Assert-Contains "and the reason names the move that was asked for" `
      (Field $block "reason") "NotAMove"
    Assert-ArrayLength "and the machine is still there after a refusal" $block "positions" 13
    Assert-True "and the moves from here are still served" `
      (@(Field $block "moves").Count -gt 0)
    Assert-FieldNotEmpty "and the collective is still standing somewhere" $block "state_label"

    # The shipped vocabulary, run as a file.
    #
    # The built-in words and the file have to agree: a reader who unpacks the
    # binary and points MAKED_SOCIETY at the file it shipped with must see
    # the same panel. A file that does not parse, or that names a position
    # the machine does not have, is refused at startup -- and a refusal at
    # startup is a server that does not start.
    $vocabularyFile = Join-Path $repo "research/society.yaml"
    Assert-True "the example vocabulary ships with the repository" (Test-Path $vocabularyFile)
    if (-not (Test-Path $vocabularyFile)) { return }
    $copy = Join-Path $tempDir ("maked_integration_society_{0}.yaml" -f $SocietyPort)
    Copy-Item $vocabularyFile $copy -Force
    $societyArgs = @{
      FilePath               = $exe
      PassThru               = $true
      RedirectStandardOutput = (Join-Path $tempDir ("maked_integration_society_{0}_out.log" -f $SocietyPort))
      RedirectStandardError  = (Join-Path $tempDir ("maked_integration_society_{0}_err.log" -f $SocietyPort))
    }
    if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
      $societyArgs["WindowStyle"] = "Hidden"
    }
    $savedSociety = $env:MAKED_SOCIETY
    $savedPort = $env:MAKED_PORT
    $savedDb = $env:MAKED_DB
    $savedBase = $script:base
    $env:MAKED_SOCIETY = $copy
    $env:MAKED_PORT = "$SocietyPort"
    $env:MAKED_DB = (Join-Path $tempDir ("maked_integration_society_{0}.db" -f $SocietyPort))
    $script:base = "http://127.0.0.1:$SocietyPort"
    $societyServer = Start-Process @societyArgs
    try {
      $societyReady = $false
      for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 250
        $probe = Invoke-Api -Method GET -Path "/api/status" -TimeoutSec 2
        if ($probe.Status -eq 200) { $societyReady = $true; break }
      }
      Assert-True "the server starts with a vocabulary file" $societyReady
      if ($societyReady) {
        $own = Get-Json "/api/society"
        Assert-Field "and the file it came from is remembered" $own "path" $copy
        Assert-Field "and the collective is still at the lifeworld" $own "state_label" "Lifeworld"
        Assert-ArrayLength "and the machine is the same machine" $own "positions" 13
        Assert-ArrayLength "and the shipped vocabulary has no gaps" $own "gaps" 0
      }
    } finally {
      if ($null -ne $societyServer -and -not $societyServer.HasExited) {
        Stop-Process -Id $societyServer.Id -Force -ErrorAction SilentlyContinue
      }
      $env:MAKED_SOCIETY = $savedSociety
      $env:MAKED_PORT = $savedPort
      $env:MAKED_DB = $savedDb
      $script:base = $savedBase
    }
  }

  # The other language, over real HTTP.
  #
  # The unit tests say the model carries a Chinese vocabulary and that the
  # sentences are written in Chinese rather than translated. What they cannot
  # say is that the server *honours* the language: that is a question about
  # the route, and the route exists only in a running process.
  #
  # The check is that the same machine says two different things in two
  # languages, and that the Chinese one is Chinese and not the English with a
  # different content type. A server that ignored `?lang=` would answer both
  # requests identically, which is the failure this is here to catch.
  function Test-ChineseSurface {
    param([int]$ChinesePort)
    $english = Invoke-Api -Method GET -Path "/api/loop/status"
    Assert-Status "the loop status answers" 200 $english
    $englishBody = $english.Body | ConvertFrom-Json
    $chinese = Invoke-Api -Method GET -Path "/api/loop/status?lang=zh"
    Assert-Status "the loop status answers in Chinese" 200 $chinese
    $chineseBody = $chinese.Body | ConvertFrom-Json

    # The body has to say what it is written in. A client that defaults to
    # Latin-1 -- Windows PowerShell's own `Invoke-WebRequest` is one -- turns
    # every Chinese name into mojibake without the charset, and the check
    # below would be checking mojibake rather than Chinese.
    Assert-True "and the response says what it is written in" `
      ("$($chinese.Headers['Content-Type'])" -like "*charset=utf-8*") `
      ("the content type was '{0}'" -f $chinese.Headers['Content-Type'])

    $englishPosition = Field $englishBody "current_position"
    $chinesePosition = Field $chineseBody "current_position"
    Assert-FieldNotEmpty "the position is named in English" $englishBody "current_position"
    Assert-FieldNotEmpty "the position is named in Chinese" $chineseBody "current_position"
    Assert-True "and the two are not the same word" `
      ("$englishPosition" -ne "$chinesePosition") `
      ("both said '{0}'" -f $englishPosition)
    Assert-True "and the Chinese one really is Chinese" `
      ("$chinesePosition" -match "[\u4e00-\u9fff]") `
      ("'{0}' has no Chinese in it" -f $chinesePosition)
    Assert-True "and the English one really is English" `
      ("$englishPosition" -notmatch "[\u4e00-\u9fff]") `
      ("'{0}' has Chinese in it" -f $englishPosition)

    # The gloss is the position's own sentence, and it travels in the reader's
    # language too.
    $chineseGloss = Field $chineseBody "current_gloss"
    Assert-True "and the gloss is Chinese as well" `
      ("$chineseGloss" -match "[\u4e00-\u9fff]") `
      ("'{0}' has no Chinese in it" -f $chineseGloss)

    # The slots come with the status, and they are named in the reader's
    # language too.
    $englishSlots = @(Field $englishBody "slots")
    $chineseSlots = @(Field $chineseBody "slots")
    Assert-True "the eight slots are served in both languages" `
      ($englishSlots.Count -eq 8 -and $chineseSlots.Count -eq 8) `
      ("English had {0}, Chinese had {1}" -f $englishSlots.Count, $chineseSlots.Count)
    if ($englishSlots.Count -gt 0 -and $chineseSlots.Count -gt 0) {
      $firstEnglish = Field $englishSlots[0] "designation"
      $firstChinese = Field $chineseSlots[0] "designation"
      Assert-True "and the slot names differ" `
        ("$firstEnglish" -ne "$firstChinese") `
        ("both said '{0}'" -f $firstEnglish)
      Assert-True "and the Chinese slot name really is Chinese" `
        ("$firstChinese" -match "[\u4e00-\u9fff]") `
        ("'{0}' has no Chinese in it" -f $firstChinese)
    }

    # The group state is named in the reader's language as well, and it is a
    # fixed vocabulary, so it is a lookup rather than a translation.
    $englishGroup = Field $englishBody "group_state"
    $chineseGroup = Field $chineseBody "group_state"
    Assert-FieldNotEmpty "the group is named in English" $englishBody "group_state"
    Assert-True "and the group is named in Chinese too" `
      ("$chineseGroup" -match "[\u4e00-\u9fff]") `
      ("'{0}' has no Chinese in it" -f $chineseGroup)

    # The model carries both languages as data, so a client can choose for
    # itself rather than asking the server to choose for it.
    $model = Invoke-Api -Method GET -Path "/api/model"
    Assert-Status "the model answers" 200 $model
    $modelBody = $model.Body | ConvertFrom-Json
    $positions = @(Field $modelBody "positions")
    Assert-True "the model carries its thirty-four positions" `
      ($positions.Count -eq 34) ("it carried {0}" -f $positions.Count)
    $chineseNames = 0
    foreach ($position in $positions) {
      if ("$(Field $position 'label_zh')" -ne "") { $chineseNames += 1 }
    }
    Assert-True "and every position carries a Chinese name" `
      ($chineseNames -eq 34) ("{0} of them did" -f $chineseNames)
    $edges = @(Field $modelBody "edges")
    Assert-True "and the model carries the edge names" `
      ($edges.Count -gt 40) ("it carried {0}" -f $edges.Count)

    # A step taken in Chinese is answered in Chinese, and the sentence that
    # says what the step did is the one that matters.
    $step = Post-Json "/api/loop/step?lang=zh" @{}
    Assert-Status "a step is taken" 200 $step
    $stepBody = $step.Body | ConvertFrom-Json
    $sessionState = Field $stepBody "session_state"
    $path = @(Field $sessionState "path")
    Assert-True "and the step is on the path" ($path.Count -gt 0)
    if ($path.Count -gt 0) {
      $narration = Field $path[0] "narration"
      Assert-True "and the step says what it did, in Chinese" `
        ("$narration" -match "[\u4e00-\u9fff]") `
        ("'{0}' has no Chinese in it" -f $narration)
      $englishNarration = Field $path[0] "position_before"
      Assert-True "and the position it left is named in Chinese" `
        ("$englishNarration" -match "[\u4e00-\u9fff]") `
        ("'{0}' has no Chinese in it" -f $englishNarration)
    }

    # An unknown language is not an error: it is the English the caller would
    # have got anyway.
    $unknown = Invoke-Api -Method GET -Path "/api/loop/status?lang=xx"
    Assert-Status "an unknown language is answered, not refused" 200 $unknown
    $unknownBody = $unknown.Body | ConvertFrom-Json
    Assert-Field "and it is the English" $unknownBody "current_position" $englishPosition
  }

  # The agent's server: the loop as tools, over the Model Context Protocol.
  #
  # This is the check that the agent's server is not a program that starts.
  # The two transports are checked separately because they fail separately: a
  # server that answers over stdio and not over HTTP is half a server, and
  # one that answers over HTTP and not over stdio is the half that an agent
  # which spawns the server as a subprocess will get.
  #
  # The protocol version is 2026-07-28, and it is asked for on every message:
  # that revision has no handshake, so the version travels in the message
  # rather than in a negotiation that happens once.
  function Test-AgentServer {
    param([int]$AgentPort)
    if ($null -eq $mcpExe) {
      Assert-True "the agent's server binary was found" $false "run the test without -SkipBuild"
      return
    }
    $meta = '{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}'
    $discover = '{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{"_meta":' + $meta + '}}'
    $list = '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{"_meta":' + $meta + '}}'
    $status = '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"_meta":' + $meta + ',"name":"maked_status","arguments":{}}}'
    $step = '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"_meta":' + $meta + ',"name":"maked_step","arguments":{}}}'
    $badSlot = '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"_meta":' + $meta + ',"name":"maked_step","arguments":{"slot":"no-such-slot"}}}'

    # --- over stdio ---------------------------------------------------------
    $stdioDb = Join-Path $tempDir ("maked_integration_agent_stdio_{0}.db" -f $AgentPort)
    if (Test-Path $stdioDb) { Remove-Item $stdioDb -Force }
    $session = Invoke-StdioSession -Exe $mcpExe -DbPath $stdioDb `
      -Lines @($discover, $list, $status, $step, $badSlot) -Expect 5
    Assert-True "the agent's server answers every question over stdio" `
      ($session.Answers.Count -eq 5) `
      ("expected 5 answers, got {0} -- stderr: {1}" -f $session.Answers.Count, (Limit $session.Errors))
    if ($session.Answers.Count -lt 5) { return }

    $answers = @()
    foreach ($line in $session.Answers) {
      try { $answers += ($line | ConvertFrom-Json) } catch { $answers += $null }
    }
    # The first answer is the one that carries the byte order mark, so it is
    # the one that says whether the mark is survived.
    Assert-True "the first question is answered" ($null -ne $answers[0]) `
      ("the first answer was not JSON: {0}" -f (Limit $session.Answers[0]))
    if ($null -ne $answers[0]) {
      Assert-Field "and it is the discovery document" (Field $answers[0] "result") "supportedVersions" "2026-07-28"
    }
    Assert-ArrayLength "and the loop is offered as seven tools" (Field $answers[1] "result") "tools" 7
    $names = @()
    foreach ($tool in @(Field (Field $answers[1] "result") "tools")) { $names += (Field $tool "name") }
    foreach ($wanted in @("maked_status", "maked_options", "maked_step", "maked_model", "maked_society", "maked_sessions", "maked_export")) {
      Assert-True ("and the '{0}' tool is there" -f $wanted) ($names -contains $wanted)
    }
    $where = ToolText $answers[2]
    Assert-Contains "and the status says where the loop stands" $where '"domain"'
    Assert-Contains "and it says it in words" $where 'position_label'
    $happened = ToolText $answers[3]
    Assert-Contains "and a step says what it did" $happened 'what_happened'
    Assert-True "and a step that names no slot is refused with a reason" `
      ($null -ne (Field $answers[4] "error")) `
      ("expected an error for a slot that does not exist, got: {0}" -f (Limit $session.Answers[4]))
    if ($null -ne (Field $answers[4] "error")) {
      Assert-Contains "and the refusal names the slot that was asked for" `
        (Field (Field $answers[4] "error") "message") "no-such-slot"
    }

    # --- over HTTP ----------------------------------------------------------
    $httpDb = Join-Path $tempDir ("maked_integration_agent_http_{0}.db" -f $AgentPort)
    if (Test-Path $httpDb) { Remove-Item $httpDb -Force }
    $savedMcpPort = $env:MAKED_MCP_PORT
    $savedDb = $env:MAKED_DB
    $env:MAKED_MCP_PORT = "$AgentPort"
    $env:MAKED_DB = $httpDb
    $mcpArgs = @{
      FilePath               = $mcpExe
      PassThru               = $true
      RedirectStandardOutput = (Join-Path $tempDir "maked_integration_mcp_out.log")
      RedirectStandardError  = (Join-Path $tempDir "maked_integration_mcp_err.log")
    }
    if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
      $mcpArgs["WindowStyle"] = "Hidden"
    }
    $mcpServer = Start-Process @mcpArgs
    try {
      $httpArgs = @{
        Uri             = "http://127.0.0.1:$AgentPort/mcp"
        Method          = "POST"
        Body            = $list
        ContentType     = "application/json"
        Headers         = @{
          "MCP-Protocol-Version" = "2026-07-28"
          "Mcp-Method"            = "tools/list"
          "Accept"               = "application/json, text/event-stream"
        }
        UseBasicParsing = $true
        TimeoutSec      = 20
      }
      $httpBody = $null
      $ready = $false
      for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 250
        try {
          $probe = Invoke-WebRequest @httpArgs -ErrorAction Stop
          if ([int]$probe.StatusCode -eq 200) { $httpBody = $probe.Content; $ready = $true; break }
        } catch { }
      }
      Assert-True "the agent's server answers over HTTP" $ready
      if ($ready) {
        $httpJson = $null
        try { $httpJson = $httpBody | ConvertFrom-Json } catch { }
        Assert-True "and the answer is a JSON-RPC result" ($null -ne (Field $httpJson "result")) `
          ("the answer was not a result: {0}" -f (Limit $httpBody))
        if ($null -ne (Field $httpJson "result")) {
          Assert-ArrayLength "and the same seven tools are offered" (Field $httpJson "result") "tools" 7
        }
      }
    } finally {
      if ($null -ne $mcpServer -and -not $mcpServer.HasExited) {
        Stop-Process -Id $mcpServer.Id -Force -ErrorAction SilentlyContinue
      }
      $env:MAKED_MCP_PORT = $savedMcpPort
      $env:MAKED_DB = $savedDb
    }
  }

  # --- the discovery document ----------------------------------------------
  #
  # The document at /api/agent is what an agent that does not speak the
  # Model Context Protocol reads. It offers the same seven tools the
  # protocol offers, and it lists the plain HTTP endpoints that ask the
  # same questions.
  #
  # Both of those are checked against the running server rather than
  # against the code: two lists of tools are two lists of tools, and the one
  # that drifts is the one nobody is looking at. A tool the protocol
  # offers and the document does not, an endpoint the document names and
  # the server does not serve, and a tool the instructions file forgets to
  # mention are all failures that no unit test can see.
  function Test-AgentDiscovery {
    param([int]$DiscoveryPort)

    $document = Get-Json "/api/agent"
    Assert-True "the discovery document answers" ($null -ne $document)
    if ($null -eq $document) { return }
    Assert-Field "and it says what it is" $document "format" "maked.agent.v1"
    Assert-FieldNotEmpty "and it carries the version" $document "version"
    Assert-FieldNotEmpty "and it says what MAKED is" $document "summary"
    Assert-FieldNotEmpty "and it carries the instructions" $document "instructions"
    Assert-True "and it says which protocol version it speaks" `
      ((Field (Field $document "protocol") "mcp") -eq "2026-07-28")

    $tools = @(Field $document "tools")
    Assert-ArrayLength "and the loop is offered as seven tools" $document "tools" 7
    $documentNames = @()
    foreach ($tool in $tools) {
      $documentNames += (Field $tool "name")
      Assert-True ("and the '{0}' tool says what it is for" -f (Field $tool "name")) `
        ((Field $tool "description") -ne "")
      Assert-True ("and the '{0}' tool carries an argument schema" -f (Field $tool "name")) `
        ($null -ne (Field $tool "inputSchema"))
    }

    # The protocol's own list, from the agent's server, so the two are
    # compared rather than both assumed.
    if ($null -ne $mcpExe) {
      $meta = '{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}'
      $list = '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":' + $meta + '}}'
      $db = Join-Path $tempDir ("maked_integration_discovery_{0}.db" -f $DiscoveryPort)
      if (Test-Path $db) { Remove-Item $db -Force }
      $session = Invoke-StdioSession -Exe $mcpExe -DbPath $db -Lines @($list) -Expect 1
      Assert-True "the agent's server answers over stdio" `
        ($session.Answers.Count -eq 1) `
        ("expected 1 answer, got {0}" -f $session.Answers.Count)
      if ($session.Answers.Count -ge 1) {
        $answer = $null
        try { $answer = $session.Answers[0] | ConvertFrom-Json } catch { }
        $protocolNames = @()
        foreach ($tool in @(Field (Field $answer "result") "tools")) { $protocolNames += (Field $tool "name") }
        Assert-True "and it offers seven tools too" ($protocolNames.Count -eq 7) `
          ("the protocol offered {0} tools" -f $protocolNames.Count)
        foreach ($name in $protocolNames) {
          Assert-True ("and the document offers the '{0}' tool the protocol offers" -f $name) `
            ($documentNames -contains $name)
        }
        foreach ($name in $documentNames) {
          Assert-True ("and the protocol offers the '{0}' tool the document offers" -f $name) `
            ($protocolNames -contains $name)
        }
      }
    }

    # Every endpoint the document names is an endpoint the server serves.
    # A 404 is the answer to "there is no such route"; anything else is
    # the route being there.
    $sessionId = 1
    $sessions = Get-Json "/api/sessions"
    if ($null -ne $sessions) {
      $list = @(Field $sessions "sessions")
      if ($list.Count -gt 0) { $sessionId = [int64](Field $list[0] "id") }
    }
    $endpoints = @(Field $document "http")
    Assert-True "and it lists the plain HTTP endpoints" ($endpoints.Count -ge 9)
    foreach ($endpoint in $endpoints) {
      $path = [string](Field $endpoint "path")
      $method = [string](Field $endpoint "method")
      # The paths carry placeholders where the caller supplies an id.
      $path = $path.Replace(":slot", "act").Replace(":id", "$sessionId")
      $response = Invoke-Api -Method $method -Path $path -Body "{}"
      Assert-True ("and the server serves {0} {1}" -f $method, $path) `
        ($response.Status -ne 404) `
        ("the server answered {0}" -f $response.Status)
    }

    # The instructions file an agent reads in the repository has to name
    # the same tools. It is a file, so it can fall behind the code without
    # anything failing -- which is exactly why it is checked here.
    $instructionsFile = Join-Path $repo "AGENT.md"
    Assert-True "the agent's instructions file ships with the repository" `
      (Test-Path $instructionsFile)
    if (Test-Path $instructionsFile) {
      $text = Get-Content $instructionsFile -Raw
      foreach ($name in $documentNames) {
        Assert-Contains ("and the instructions file names the '{0}' tool" -f $name) $text $name
      }
      Assert-Contains "and the instructions file names the discovery document" $text "/api/agent"
    }
  }

  # --- a file that cannot be read --------------------------------------------
  #
  # A server that starts with half a machine answers every request
  # confidently and wrongly, which is the worst thing a server can do. So a
  # file that cannot be read stops the server before it serves anything,
  # and the reason is on stderr where the operator will see it.
  #
  # This is checked here rather than in the backend tests for one reason: the
  # start-up reads the environment, the environment is process-wide, and the
  # backend tests run side by side in one process. A server of its own is
  # the only place where "the environment named a file" can be checked
  # without changing what the other tests are running.
  function Test-RefusesBrokenFiles {
    param([int]$RefusePort)

    $cases = @(
      @{ Name = "the machine"; Var = "MAKED_MODEL"; File = "broken_model.json"; Text = "this is not a machine" },
      @{ Name = "the mapping table"; Var = "MAKED_RESEARCH"; File = "broken_table.yaml"; Text = "[unclosed" },
      @{ Name = "the society vocabulary"; Var = "MAKED_SOCIETY"; File = "broken_society.yaml"; Text = "[unclosed" },
      @{ Name = "the corpus"; Var = "MAKED_CORPUS"; File = "broken_corpus.yaml"; Text = "[unclosed" }
    )
    $vars = @("MAKED_MODEL", "MAKED_RESEARCH", "MAKED_SOCIETY", "MAKED_CORPUS")
    $saved = @{}
    foreach ($name in $vars) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
    $savedPort = $env:MAKED_PORT
    $savedDb = $env:MAKED_DB
    try {
      $port = $RefusePort
      foreach ($case in $cases) {
        foreach ($name in $vars) {
          [Environment]::SetEnvironmentVariable($name, $null)
        }
        $broken = Join-Path $tempDir $case.File
        # Written as bytes: `Set-Content -Encoding UTF8` writes a byte order
        # mark on PowerShell 5, and a mark in front of the file is a mark in
        # front of the file the server reads.
        [System.IO.File]::WriteAllText($broken, $case.Text, (New-Object System.Text.UTF8Encoding($false)))
        [Environment]::SetEnvironmentVariable($case.Var, $broken)
        $env:MAKED_PORT = "$port"
        $env:MAKED_DB = (Join-Path $tempDir ("maked_integration_refuse_{0}.db" -f $port))
        $errLog = Join-Path $tempDir ("maked_integration_refuse_{0}_err.log" -f $port)
        $args = @{
          FilePath               = $exe
          PassThru               = $true
          RedirectStandardOutput = (Join-Path $tempDir ("maked_integration_refuse_{0}_out.log" -f $port))
          RedirectStandardError  = $errLog
        }
        if ($IsWindows -or $PSVersionTable.PSVersion.Major -lt 6) {
          $args["WindowStyle"] = "Hidden"
        }
        $server = Start-Process @args
        $exited = $false
        for ($i = 0; $i -lt 60; $i++) {
          Start-Sleep -Milliseconds 250
          if ($server.HasExited) { $exited = $true; break }
        }
        if (-not $exited) {
          Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
        }
        Assert-True ("the server refuses to start with {0} it could not read" -f $case.Name) $exited
        $said = ""
        if (Test-Path $errLog) { $said = (Get-Content $errLog -Raw) }
        Assert-Contains ("and it says why {0} could not be read" -f $case.Name) $said "will not start"
        Assert-Contains ("and it names the file it could not read" -f $case.Name) $said $case.File
        $port = $port + 1
      }
    } finally {
      foreach ($name in $vars) {
        [Environment]::SetEnvironmentVariable($name, $saved[$name])
      }
      $env:MAKED_PORT = $savedPort
      $env:MAKED_DB = $savedDb
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

  Write-Host ""
  Write-Host "-- the collective"
  Test-Society ($Port + 6)

  Write-Host ""
  Write-Host "-- the other language"
  Test-ChineseSurface ($Port + 6)

  Write-Host ""
  Write-Host "-- the agent's server"
  Test-AgentServer ($Port + 7)

  Write-Host ""
  Write-Host "-- the discovery document"
  Test-AgentDiscovery ($Port + 9)

  Write-Host ""
  Write-Host "-- a file that cannot be read"
  Test-RefusesBrokenFiles ($Port + 8)
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

# The README states how many checks this suite runs. Only a run knows how
# many it made -- some of the assertions sit in loops, so the number cannot
# be derived from this script's text -- so the suite checks the document
# against what it just did.
#
# A stale count in the document is not a small thing: the number is the
# one a reader uses to judge how much of the server was exercised, and a
# number that is wrong in the document is wrong everywhere the document is
# read. The other counts in the README are checked by
# `tools/check-readme.ps1`, which can derive them from the tree; this one
# is checked here, because this is where the truth is.
#
# The path is derived the way the script derives its own root rather than
# written with a backslash: the suite runs on the CI runner, which is
# ubuntu, and a backslash is a character there rather than a separator.
$readmePath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'README.md'
if (Test-Path $readmePath) {
  $readme = [System.IO.File]::ReadAllText($readmePath, [System.Text.Encoding]::UTF8)
  $m = [regex]::Match($readme, '(?m)^\|\s*Integration checks\s*\|\s*(\d+)\s*\|')
  if (-not $m.Success) {
    Write-Host ""
    Write-Host "*** FAIL ***"
    Write-Host "README.md has no row for the integration checks."
    exit 1
  }
  $stated = [int]$m.Groups[1].Value
  if ($stated -ne $script:passed) {
    Write-Host ""
    Write-Host "*** FAIL ***"
    Write-Host ("README.md says the suite runs {0} checks; it ran {1}." -f $stated, $script:passed)
    Write-Host "Update the README, or find out why the count moved."
    exit 1
  }
  Write-Host ""
  Write-Host ("README.md's count ({0} checks) matches this run." -f $stated)

  # The README's headline states the shape of the machine: thirty-four
  # positions, eight slots, two hundred and seventy-two rules, and the
  # number of those rules that have no way out. Nothing in the tree can be
  # asked that question -- the machine is the pyroduct package's, and the
  # package is not this repository -- so the document is checked here,
  # against the model the server just served.
  #
  # Every place the document states the shape has to state the same one. A
  # headline number that has drifted is the first thing a reader sees, and
  # the second thing they do is find out whether the project notices.
  $modelPositions = @($model.positions).Count
  $modelSlots = @($model.slots).Count
  $modelRules = @($model.rules).Count
  $modelBlocked = @($model.rules | Where-Object { $_.outcome.kind -eq 'block' }).Count
  $shapeProblems = @()
  $shapeClaims = 0
  $blockedClaims = 0

  # "34 positions x 8 slots x 272 rules". The multiplication sign is written
  # as an escape, because this file is ASCII and the document is not.
  foreach ($claim in [regex]::Matches($readme, '([0-9]+) positions \u00D7 ([0-9]+) slots \u00D7 ([0-9]+) rules')) {
    $shapeClaims += 1
    $p = [int]$claim.Groups[1].Value
    $s = [int]$claim.Groups[2].Value
    $r = [int]$claim.Groups[3].Value
    if ($p -ne $modelPositions -or $s -ne $modelSlots -or $r -ne $modelRules) {
      $shapeProblems += ("the document says {0} positions, {1} slots and {2} rules; the machine has {3}, {4} and {5}" -f $p, $s, $r, $modelPositions, $modelSlots, $modelRules)
    }
  }

  # "of which 228 have no way out".
  foreach ($claim in [regex]::Matches($readme, '([0-9]+) have no way out')) {
    $blockedClaims += 1
    $n = [int]$claim.Groups[1].Value
    if ($n -ne $modelBlocked) {
      $shapeProblems += ("the document says {0} rules have no way out; the machine has {1}" -f $n, $modelBlocked)
    }
  }

  # "of the 272 position/slot pairs, 228 are Block".
  foreach ($claim in [regex]::Matches($readme, 'of the ([0-9]+) position/slot pairs, ([0-9]+) are')) {
    $blockedClaims += 1
    $pairs = [int]$claim.Groups[1].Value
    $blocked = [int]$claim.Groups[2].Value
    if ($pairs -ne $modelRules) {
      $shapeProblems += ("the document says {0} position/slot pairs; the machine has {1}" -f $pairs, $modelRules)
    }
    if ($blocked -ne $modelBlocked) {
      $shapeProblems += ("the document says {0} of the pairs are blocked; the machine has {1}" -f $blocked, $modelBlocked)
    }
  }

  # The slot vocabulary is stated in words, in the table of routes.
  $slotWords = @{
    'one' = 1; 'two' = 2; 'three' = 3; 'four' = 4; 'five' = 5; 'six' = 6
    'seven' = 7; 'eight' = 8; 'nine' = 9; 'ten' = 10; 'eleven' = 11; 'twelve' = 12
  }
  foreach ($claim in [regex]::Matches($readme, 'the ([a-z]+)-slot vocabulary')) {
    $w = $claim.Groups[1].Value
    if (-not $slotWords.ContainsKey($w)) {
      $shapeProblems += ("the document says a '{0}-slot vocabulary', which is not a number" -f $w)
    } elseif ($slotWords[$w] -ne $modelSlots) {
      $shapeProblems += ("the document says a {0}-slot vocabulary; the machine has {1} slots" -f $w, $modelSlots)
    }
  }

  if ($shapeClaims -eq 0 -or $blockedClaims -eq 0) {
    $shapeProblems += "the document no longer states the shape of the machine"
  }

  if ($shapeProblems.Count -gt 0) {
    Write-Host ""
    Write-Host "*** FAIL ***"
    Write-Host "README.md does not state the machine's shape as it is:"
    foreach ($problem in $shapeProblems) { Write-Host ("  " + $problem) }
    Write-Host "Update the README, or find out why the machine moved."
    exit 1
  }
  Write-Host ""
  Write-Host ("README.md's shape ({0} positions, {1} slots, {2} rules, {3} of them blocked) matches the machine." -f $modelPositions, $modelSlots, $modelRules, $modelBlocked)

  # The collective's shape: the positions and the transitions of the collective
  # the server served.
  #
  # The words for the collective are a file in this repository, so the README
  # gate checks the document against the file; the number of transitions is the
  # machine's, and the machine is the pyroduct package's -- not this
  # repository. So that number is checked here, where the collective is.
  #
  # The number of phases is the file's and is checked by the README gate
  # against the file; this check does not repeat it. The point of a check is
  # to be the one place a fact is watched, and a fact watched twice is a fact
  # watched in two places that can disagree about what to do.
  $collectiveProblems = @()
  $collectiveClaims = 0

  # "13 positions x 8 phases x 28 transitions", the row of the three layers.
  # The multiplication sign is written as an escape, because this file is
  # ASCII and the document is not.
  foreach ($claim in [regex]::Matches($readme, '([0-9]+) positions \u00D7 ([0-9]+) phases \u00D7 ([0-9]+) transitions')) {
    $collectiveClaims += 1
    $p = [int]$claim.Groups[1].Value
    $t = [int]$claim.Groups[3].Value
    if ($p -ne $script:collectivePositions) {
      $collectiveProblems += ("the document says {0} positions; the collective has {1}" -f $p, $script:collectivePositions)
    }
    if ($t -ne $script:collectiveTransitions) {
      $collectiveProblems += ("the document says {0} transitions; the collective has {1}" -f $t, $script:collectiveTransitions)
    }
  }

  # "with its 13 positions, 28 transitions and 8 phases", the feature bullet.
  foreach ($claim in [regex]::Matches($readme, 'with its ([0-9]+) positions, ([0-9]+) transitions')) {
    $collectiveClaims += 1
    $p = [int]$claim.Groups[1].Value
    $t = [int]$claim.Groups[2].Value
    if ($p -ne $script:collectivePositions) {
      $collectiveProblems += ("the document says {0} positions; the collective has {1}" -f $p, $script:collectivePositions)
    }
    if ($t -ne $script:collectiveTransitions) {
      $collectiveProblems += ("the document says {0} transitions; the collective has {1}" -f $t, $script:collectiveTransitions)
    }
  }

  if ($collectiveClaims -eq 0) {
    $collectiveProblems += "the document no longer states the collective's shape"
  }

  if ($collectiveProblems.Count -gt 0) {
    Write-Host ""
    Write-Host "*** FAIL ***"
    Write-Host "README.md does not state the collective's shape as it is:"
    foreach ($problem in $collectiveProblems) { Write-Host ("  " + $problem) }
    Write-Host "Update the README, or find out why the collective moved."
    exit 1
  }
  Write-Host ""
  Write-Host ("README.md's collective ({0} positions, {1} transitions) matches the one the server served." -f $script:collectivePositions, $script:collectiveTransitions)

  # The group's shape: how many states the group machine has.
  #
  # The row of the three layers says how many group states there are, and the
  # machine that has them is the pyroduct package's -- not this repository. So
  # the number is checked here, where the vocabulary is, the same way the
  # collective's transitions are.
  #
  # The row also names the states the loop can land in. A name the vocabulary
  # does not have is a name about nowhere, and that is checked here too: the
  # names are the document's, the vocabulary is the server's.
  #
  # The em dash and the arrow are written as escapes, because this file is
  # ASCII and the document is not.
  $groupProblems = @()
  $groupClaims = 0
  $groupRow = [regex]::Match($readme, '\|\s*\*\*Group\*\*\s*\|(?<body>[^\|]*)\|')
  if (-not $groupRow.Success) {
    $groupProblems += "the document no longer has a row for the group"
  } else {
    $groupBody = $groupRow.Groups['body'].Value
    if ($script:groupStates -lt 1) {
      $groupProblems += "the server did not serve the group's vocabulary"
    }
    # "(20 states)".
    $groupCount = [regex]::Match($groupBody, '\((?<n>[0-9]+) states\)')
    if (-not $groupCount.Success) {
      $groupProblems += "the document no longer states how many group states there are"
    } else {
      $groupClaims += 1
      $n = [int]$groupCount.Groups['n'].Value
      if ($n -ne $script:groupStates) {
        $groupProblems += ("the document says {0} group states; the vocabulary the server served has {1}" -f $n, $script:groupStates)
      }
    }
    # "Scattered -> Converging -> ...", the states the row names.
    $groupNamed = [regex]::Match($groupBody, '\u2014\s*(?<names>[^\(]+)\(')
    if (-not $groupNamed.Success) {
      $groupProblems += "the document no longer names the group states"
    } else {
      $groupClaims += 1
      $named = @($groupNamed.Groups['names'].Value -split '\u2192' |
        ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
      foreach ($name in $named) {
        if ($script:groupStateNames -cnotcontains $name) {
          $groupProblems += ("the document names the group state '{0}', which the vocabulary does not have" -f $name)
        }
      }
    }
  }

  if ($groupClaims -eq 0) {
    $groupProblems += "the document no longer states the group's shape"
  }

  if ($groupProblems.Count -gt 0) {
    Write-Host ""
    Write-Host "*** FAIL ***"
    Write-Host "README.md does not state the group's shape as it is:"
    foreach ($problem in $groupProblems) { Write-Host ("  " + $problem) }
    Write-Host "Update the README, or find out why the group moved."
    exit 1
  }
  Write-Host ""
  Write-Host ("README.md's group ({0} states, named as the vocabulary names them) matches the one the server served." -f $script:groupStates)
}
exit 0
