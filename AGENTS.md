# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

If your job here is to **drive** MAKED rather than to change it — to read
where the loop stands and take moves in it — read [AGENT.md](AGENT.md) instead.
It carries the seven tools, the discovery document at `GET /api/agent`, and the
Model Context Protocol details.

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

- **The README states numbers, and the numbers are checked.**
  `tools/check-readme.ps1` (and its bash twin `tools/check-readme.sh`) derives
  the test, mutation, anchor and gate counts from the tree and compares them
  with what `README.md` says. A number in the document that the tree does not
  agree with is a red gate, not a stale line: the document carried six of them
  for months, all wrong in the same direction, because nothing compared the two.
  The check is an invariant rather than a snapshot -- the number the document
  states IS the number the tree has -- so it keeps holding as tests are added
  and removed. Adding a test means updating the document too, and the gate
  says so if you forget. The integration-check count is the one number the
  gate cannot derive, because some of the suite's assertions sit in loops; the
  integration suite checks that one itself, at the end of a run. The gate also
  checks the project-structure LISTING: every source file has to be named in
  it, and a name has to appear as many times as the tree has files with that
  name. The listing is the map a reader navigates by, and it was missing
  eleven files -- among them the workspace, which is the thing the reader is
  supposed to bring their own work into.

- **A gate on the README does not make the other documents true.**
  `tools/check-docs.ps1` (and its bash twin) applies the same
  invariant to the other documents a reader is sent to: `architecture/`,
  `AGENT.md` and the note in the release archive. The route count, the
  column count, the field count, the seeded-page count, the dependency
  versions and the `file:line` references are all derived from the tree and
  compared with what the documents say. Those documents rotted the same way
  the README did, and further -- they claim things about the SHAPE of the
  system ("read-only content model", "no Dockerfile", "no CI"), and a shape
  claim is not a number a script can derive, so it has to be kept true by
  reading it.
  A `file:line` reference that is still in range but no longer says what the
  claim says is the dangerous kind: it looks verified. So the documents say
  what the claim IS next to the pointer, and the gate checks the mechanical
  half. FOUR of them describe the PAST -- `architecture/evolution.md`,
  `architecture/evolution.evidence.md`, `evolution-summary.md` and
  `architecture-evolution-roadmap.md` keep the reasoning for the migration
  slices -- and they carry a header saying so rather than being rewritten;
  rewriting them would destroy the reason the slices exist. The gate checks
  the header too, because a header is easy to lose in an edit and a claim
  that is history without saying so is a lie.
  The same gate checks the two documents a USER is handed rather than a
  developer: `AGENT.md` (the tools, the protocol version, the files and the
  endpoints, all derived from the discovery document the server answers with)
  and `packaging/RUN.txt` (every environment variable the server reads, with
  the default it has). A set is compared by MEMBERSHIP rather than by a
  sorted string, so the two twins cannot disagree about the answer by
  disagreeing about the order, and a count spelled out in words ("the seven
  tools") is mapped to a number and checked like any other.

- **The language of a surface is decided by who owns the words.** The machine's
  words -- the positions, the slots, the names of the five domains, the prose
  of the pages -- are the server's, and they come back in the language the
  request asked for. The client's own words -- the buttons, the empty states,
  the sentences it writes for itself -- are the client's. A table in the client
  that copies the machine's names is a copy nobody checks: the client used to
  carry the five domain names in both languages, and the way that was found
  was the pages needing Chinese and the client having no way to ask. Write a
  word once, where it belongs, and let the other side ask for it.

- **The bash gates are real now, and they run on the runner.** `ci.sh` holds
  seventeen gates; the GitHub workflow runs the five that a push is checked
  against (contract, component, SAST, DAST, dependency versions), and
  `ci.sh` runs all seventeen. The mutation batteries are the slow half and
  are local: they rewrite the source and re-run the suites 229 times, which
  is an hour of CI for a check a push does not change.

- **A gate that skips is a gate that does not run.** The DAST gate used to
  look for a server on `MAKED_PORT` and skip its live checks when it found
  none -- so the live path was covered by nothing, in CI and everywhere
  else. It now starts its own server, the way the contract gate does. When
  you add a check that needs something running, start the thing rather than
  skipping: a check that never runs is indistinguishable from a check that
  passes.

- **The runner is ubuntu, and `python` is not on it.** `python3` is. The
  bash gates resolve the interpreter once (`command -v python3 || command
  -v python`) and say so plainly when there is neither, because a gate that
  dies on a missing interpreter reports nothing about the thing it was
  meant to check.

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
