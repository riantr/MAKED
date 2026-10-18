# Build both halves and stage the browser bundle where the server looks for it.
#
# `moon build --target js` emits a single self-contained main.js with no
# import/export statements, so it needs no bundler -- but the filename and
# location are chosen by moon, not by us, hence the copy.

# 'Continue', not 'Stop': moon writes ordinary progress to stderr ("Finished.
# moon: no work to do", warning codes), and under 'Stop' PowerShell turns those
# into terminating errors -- so a cached build died before the first exit-code
# check. Every step below asserts $LASTEXITCODE explicitly, which is the check
# that actually decides whether the build passed.
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSCommandPath)

$moon = if ($env:MOON) { $env:MOON } else { 'moon' }

# `.mooncakes/` is gitignored -- it is a dependency cache, so an edit there is
# invisible to git, to CI, and to anyone who runs `moon update`. The English
# vocabulary therefore lives in `deps/pyroduct-en.mbt`, which is tracked, and
# is staged into the vendored package on every build. Edit the tracked file, not
# the copy.
Write-Host '==> staging the English pyroduct vocabulary'
$pyroduct_src = '.mooncakes/riantr/pyroduct/src'
$pyroduct_group_src = '.mooncakes/riantr/pyroduct/group'
if (-not (Test-Path $pyroduct_src)) { throw "expected $pyroduct_src to exist" }
if (-not (Test-Path $pyroduct_group_src)) { throw "expected $pyroduct_group_src to exist" }
Copy-Item 'deps/pyroduct-en.mbt' "$pyroduct_src/en.mbt" -Force
Copy-Item 'deps/pyroduct-group-en.mbt' "$pyroduct_group_src/en.mbt" -Force

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

# Same reasoning for the SPA: slug routing, the total `decode_pages` fallbacks
# and the ring geometry are all properties a refactor can break while the page
# still renders. Run on the js target because the package targets js only.
Write-Host '==> testing the frontend'
& $moon test --target js frontend
if ($LASTEXITCODE -ne 0) { throw "frontend tests failed ($LASTEXITCODE)" }

Write-Host '==> building the server'
& $moon build --release --target native cmd/server
if ($LASTEXITCODE -ne 0) { throw "native build failed ($LASTEXITCODE)" }

Write-Host ''
Write-Host 'ready:  moon run --release --target native cmd/server'
