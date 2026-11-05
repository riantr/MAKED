#!/usr/bin/env bash
# Dependency version checker for MAKED on MoonBit.
#
# Checks whether any dependency in moon.mod has a newer version available.
#
# Two modes:
#
#   bash tools/dep-check.sh            # a warning: the run carries on
#   bash tools/dep-check.sh --strict   # a failure: the run stops
#
# The strict mode is the RELEASE's.  A release is the one thing that puts a
# build in front of users, and a build that ships a dependency the registry
# has already moved past is a build nobody chose.  The ordinary CI keeps the
# warning mode: a push should not go red because somebody published a new
# version of a dependency an hour ago, but a release should.
#
# `moon update` refreshes the registry index before the check, so the versions
# below are the ones the registry has NOW rather than the ones it had the last
# time this machine looked.
#
# IT DOES NOT CHANGE THE PINNED VERSION.  That is `moon add --upgrade`, and
# the difference is the whole point of this script: an exit code of zero from
# `moon update` says the index was refreshed, not that anything was upgraded.
# The upgrade is a change to the tree, and a change to the tree has to go
# through the gates like any other.
#
# Usage:
#   bash tools/dep-check.sh [--strict]

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

STRICT=0
case "${1:-}" in
  --strict) STRICT=1 ;;
  "") ;;
  *)
    echo "unknown option: $1 (the only one is --strict)" >&2
    exit 2
    ;;
esac

OUTDATED=0
CHECKED=0
UNQUERIED=0

echo "Checking dependency versions..."
echo ""

# The registry index is refreshed first.  A refresh that fails is not a
# reason to stop: the queries below ask the registry directly, so a stale
# index costs nothing but a line of output.
echo "Refreshing the registry index..."
if ! moon update; then
  echo "  (the registry index could not be refreshed; the queries below still ask the registry)"
fi
echo ""

# The interpreter, whichever name this machine gives it.
#
# `python` is not on the PATH of a current ubuntu runner -- `python3` is --
# and a query that dies on a missing interpreter reports "could not query
# latest version" for every dependency, which reads like a registry problem
# and is really a missing program.
PYTHON="$(command -v python3 || command -v python || true)"
if [ -z "$PYTHON" ]; then
  echo "  ERROR  no python on this machine, so the versions cannot be checked"
  exit 1
fi

# Parse moon.mod for dependencies in the import block
# Format: "user/package@version"
while IFS= read -r line; do
  # Skip comments and empty lines
  [[ "$line" =~ ^[[:space:]]*//.* ]] && continue
  [[ -z "${line// /}" ]] && continue

  # Extract package@version
  if [[ "$line" =~ \"([^\"]+)\" ]]; then
    dep="${BASH_REMATCH[1]}"
    # Parse package name and version
    if [[ "$dep" =~ ^(.+)@(.+)$ ]]; then
      pkg="${BASH_REMATCH[1]}"
      current="${BASH_REMATCH[2]}"

      # Query latest version
      CHECKED=$((CHECKED + 1))
      latest=$(moon view "$pkg" --json 2>/dev/null | "$PYTHON" -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d['result']['latest_version'])
except:
    print('')
" 2>/dev/null || echo "")

      if [ -n "$latest" ]; then
        if [ "$current" != "$latest" ]; then
          echo "  OUTDATED: $pkg"
          echo "    current: $current"
          echo "    latest:  $latest"
          echo "    update:  moon add --upgrade $pkg@$latest"
          echo ""
          OUTDATED=$((OUTDATED + 1))
        else
          echo "  OK: $pkg@$current"
        fi
      else
        echo "  SKIP: $pkg (the version could not be queried)"
        UNQUERIED=$((UNQUERIED + 1))
      fi
    fi
  fi
done < <(sed -n '/^import {/,/^}/p' moon.mod)

echo ""
echo "========================================"
echo "Dependency Check: $CHECKED checked, $OUTDATED outdated, $UNQUERIED unqueried"
echo "========================================"

if [ "$OUTDATED" -gt 0 ]; then
  echo ""
  echo "To update a dependency:"
  echo "  moon add --upgrade <package>@<latest-version>"
  echo ""
  echo "Then run the gates again with the new dependency: the upgrade is a"
  echo "change to the tree, and it has to be checked like any other."
fi

# The strict mode.
#
# A release must ship the dependencies it names, and it must be able to say
# that they are the current ones.  So the strict mode fails on BOTH counts:
# a dependency that has moved, and a dependency whose version could not be
# read.  "Could not be queried" is not "is current" -- and a release that
# cannot check its dependencies should not ship.
if [ "$STRICT" -eq 1 ]; then
  STRICT_FAILURE=0
  if [ "$OUTDATED" -gt 0 ]; then
    echo "::error::a release must ship the dependencies it names, and one of them has moved"
    STRICT_FAILURE=1
  fi
  if [ "$UNQUERIED" -gt 0 ]; then
    echo "::error::the version of $UNQUERIED dependenc(y|ies) could not be queried, so a release cannot claim they are current"
    STRICT_FAILURE=1
  fi
  # ONE exit, and it is the last thing in the strict block.  Two exits, one per
  # reason, would make "the strict mode fails" a claim about two places at
  # once -- and a claim about two places cannot be turned red by changing one
  # of them, which is what a rule has to be able to do.
  if [ "$STRICT_FAILURE" -eq 1 ]; then
    exit 1
  fi
fi

# Without --strict this is a warning gate, not a blocking gate: the run
# carries on and says what it found.
exit 0
