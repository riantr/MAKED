#!/usr/bin/env bash
# Dependency version checker for MAKED on MoonBit.
#
# Checks if any dependencies in moon.mod have newer versions available.
# This is a warning-only gate -- it does not fail the build, but reports
# outdated dependencies so they can be updated manually.
#
# Usage:
#   bash tools/dep-check.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUTDATED=0
CHECKED=0

echo "Checking dependency versions..."
echo ""

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
      latest=$(moon view "$pkg" --json 2>/dev/null | python -c "
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
          echo "    update:  moon add $pkg@$latest"
          echo ""
          OUTDATED=$((OUTDATED + 1))
        else
          echo "  OK: $pkg@$current"
        fi
      else
        echo "  SKIP: $pkg (could not query latest version)"
      fi
    fi
  fi
done < <(sed -n '/^import {/,/^}/p' moon.mod)

echo ""
echo "========================================"
echo "Dependency Check: $CHECKED checked, $OUTDATED outdated"
echo "========================================"

if [ "$OUTDATED" -gt 0 ]; then
  echo ""
  echo "To update a dependency:"
  echo "  moon add <package>@<latest-version>"
  echo ""
  echo "Then run tests to verify compatibility."
fi

# Always exit 0 -- this is a warning gate, not a blocking gate
exit 0
