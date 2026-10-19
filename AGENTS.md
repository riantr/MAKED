# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module
  metadata.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

## Tooling

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. See $moonbit-agent-guide for details.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package. If nothing in `.mbti` changes, this means your
  change does not bring the visible changes to the external package users, it is
  typically a safe refactoring.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Run `moon test` to check tests pass. MoonBit supports snapshot testing; when
  changes affect outputs, run `moon test --update` to refresh snapshots.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. For snapshot tests that record
  structured debugging output, derive `Debug` and use `debug_inspect`, rather
  than deriving `Show` for debugging. For solid, well-defined results (e.g.
  scientific computations), prefer assertion tests. You can use
  `moon coverage analyze > uncovered.log` to see which parts of your code are
  not covered by tests.

## Build and verify

- **`.\build.ps1` is the only thing that stages the browser bundle.**
  `moon build --release --target js cmd/web` writes
  `_build/js/release/build/cmd/web/web.js`; the server serves `frontend/dist/`,
  and only `build.ps1` copies one to the other. Verifying the UI in a browser
  after a bare `moon build` tests the *previous* bundle, with no error anywhere
  to say so. It reports success and leaves `frontend/dist/main.js` untouched.

- **Stop the server before building.** A running release server holds
  `_build/native/release/build/cmd/server/server.exe` open, and the link step
  fails with `LNK1104`. Check for strays with
  `Get-Process -Name 'server','moon'` and `Stop-Process -Id <pid> -Force`;
  cancelling the task that launched it does not kill the child process.

- **Run the mutation suites alone.** `tools/mutate-loop.ps1`,
  `tools/mutate-backend.ps1` and `tools/mutate-frontend.ps1` mutate source and
  re-run the tests, so no other `moon` command may be in flight. Their exit code
  is meaningless -- it is the last `moon test` propagating through PowerShell --
  so read the `survivors:` line, not `$LASTEXITCODE`.

- Read the endpoint with `Invoke-WebRequest` before suspecting the backend. A
  loop panel stuck on "Loading loop status..." while the server answers 200 is
  a client-side fault, and the browser's own network/console capture is not
  populated in this project's provider.

- **Keep source files LF.** `git checkout` on this machine rewrites `.mbt` files
  to CRLF, and the mutation scripts match their anchors against LF text. A
  CRLF file does not fail a test -- it reports `anchor not present ... mutation
  never applied` and is counted as a **survivor**, which looks exactly like a
  real coverage hole. After any `git checkout`, convert back before running the
  mutation suites:

  ```powershell
  $p = "<abs path>"; $t = [System.IO.File]::ReadAllText($p)
  [System.IO.File]::WriteAllText($p, $t.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
  ```
