# Build both halves and stage the browser bundle where the server looks for it.
#
# `moon build --target js` emits a single self-contained main.js with no
# import/export statements, so it needs no bundler -- but the filename and
# location are chosen by moon, not by us, hence the copy.

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSCommandPath)

$moon = if ($env:MOON) { $env:MOON } else { 'moon' }

Write-Host '==> building the browser bundle'
& $moon build --release --target js cmd/web
if ($LASTEXITCODE -ne 0) { throw "js build failed ($LASTEXITCODE)" }

$built = '_build/js/release/build/cmd/web/web.js'
if (-not (Test-Path $built)) { throw "expected $built to exist" }
Copy-Item $built 'frontend/dist/main.js' -Force
Write-Host "    staged frontend/dist/main.js ($((Get-Item 'frontend/dist/main.js').Length) bytes)"

Write-Host '==> type-checking the backend'
& $moon check --target native
if ($LASTEXITCODE -ne 0) { throw "native check failed ($LASTEXITCODE)" }

# The storage layer carries three SQLite behaviours that fail silently rather
# than loudly, so the tests are run on every build rather than only on demand.
Write-Host '==> testing the backend'
& $moon test --target native backend
if ($LASTEXITCODE -ne 0) { throw "backend tests failed ($LASTEXITCODE)" }

Write-Host '==> building the server'
& $moon build --release --target native cmd/server
if ($LASTEXITCODE -ne 0) { throw "native build failed ($LASTEXITCODE)" }

Write-Host ''
Write-Host 'ready:  moon run --release --target native cmd/server'
