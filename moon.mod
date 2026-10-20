// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "riantr/MAKED"

version = "0.1.7"

license = "Apache-2.0"

readme = "README.md"

repository = "https://github.com/riantr/MAKED.git"

keywords = [ "web", "rabbita", "moonback", "sqlite" ]

// MAKED_moonbit is a two-target project:
//   backend/ + cmd/server  -> native (moonback HTTP server + sqlite3)
//   frontend/ + cmd/web    -> js    (rabbita SPA, runs in the browser)
// The union is what the module declares; each package narrows it with its own
// `supported_targets` in its moon.pkg (native for backend, js for frontend).
//
// `preferred_target` exists for `moon publish`, not for ordinary builds. Publish
// does not check this tree: it zips the module, extracts it to a temporary
// directory and verifies THAT copy, and the check it runs defaults to the wasm
// backend. Without this line the release dies before it uploads anything with
//
//   Selected package(s) do not support target backend 'wasm'
//
// because wasm is not in the supported set. Setting it to "native" points the
// publish-time check at a target the project actually builds. Ordinary builds
// are unaffected -- they pass --target explicitly.

preferred_target = "native"

supported_targets = "js+native"

description = "MAKED on MoonBit: rabbita SPA frontend + a Flask-style micro-framework on moonback"

import {
  "moonbit-community/rabbita@0.16.5",
  "moonbit-community/sqlite3@0.2.3",
  "moonbit-community/yaml@0.0.8",
  "moonbitlang/async@0.22.5",
  "moonbitlang/moonback@0.8.9",
  "moonbitlang/pdflite@0.4.0",
  "moonbitlang/x@0.5.5",
  "riantr/moonbit_doubleML@0.163.9",
  "riantr/pyroduct@0.1.32",
  "colmugx/mcp@0.18.0",
}
