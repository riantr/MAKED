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

name = "riantr/maked_moonbit"

version = "0.1.3"

license = "Apache-2.0"

keywords = [ "web", "rabbita", "moonback", "sqlite" ]

// MAKED_moonbit is a two-target project:
//   backend/ + cmd/server  -> native (moonback HTTP server + sqlite3)
//   frontend/ + cmd/web    -> js    (rabbita SPA, runs in the browser)
// Neither target is "primary", so only the union is declared here and each
// package picks its own default via its own `preferred-target` in moon.pkg.

supported_targets = "js+native"

description = "MAKED on MoonBit: rabbita SPA frontend + a Flask-style micro-framework on moonback"

import {
  "moonbit-community/rabbita@0.16.4",
  "moonbit-community/sqlite3@0.2.3",
  "moonbitlang/async@0.22.4",
  "moonbitlang/moonback@0.8.6",
  "moonbitlang/x@0.5.5",
  "riantr/pyroduct@0.1.30",
  "riantr/moonbit_doubleML@0.162.0",
}
