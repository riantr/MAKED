#!/usr/bin/env bash
# Stage the English pyroduct vocabulary into the vendored dependency.
#
# `.mooncakes/` is a gitignored dependency cache, not source. The English
# vocabulary therefore lives in `deps/` (tracked) and is copied in here on every
# build. `build.ps1` performs the same two copies for local Windows builds --
# keep the two in step.
#
# This exists because CI would otherwise not compile at all. `backend/loop.mbt`
# and `backend/api.mbt` call `@sm.en_label()` / `@sm.en_gloss()` and
# `@group.GroupState::en_designation()`, which are defined ONLY in
# deps/pyroduct-en.mbt and deps/pyroduct-group-en.mbt. A clean checkout that
# runs `moon update` without this step fails with:
#
#   Type @riantr/pyroduct/src.SubjectState has no method en_label.
#
# which is verified, not predicted: it is what a runner without this script
# produces. Local Windows builds never see it because build.ps1 already staged
# the files, which is exactly why the bug survived a green local gate.
#
# Run AFTER `moon install`, which is what populates `.mooncakes/`.
# `moon update` alone is NOT enough: it refreshes the registry index and
# rewrites the lockfile, but it does not download packages, so on a fresh
# checkout `.mooncakes/` does not exist when it returns. This was measured on a
# clean runner, not assumed -- the first tag push died here with
# ".mooncakes/riantr/pyroduct/src is missing".
set -euo pipefail

subject_src=".mooncakes/riantr/pyroduct/src"
group_src=".mooncakes/riantr/pyroduct/group"

for dir in "$subject_src" "$group_src"; do
  if [ ! -d "$dir" ]; then
    echo "::error::$dir is missing -- run 'moon install' before this script"
    exit 1
  fi
done

for file in deps/pyroduct-en.mbt deps/pyroduct-group-en.mbt; do
  if [ ! -f "$file" ]; then
    echo "::error::$file is missing from the checkout"
    exit 1
  fi
done

cp deps/pyroduct-en.mbt "$subject_src/en.mbt"
cp deps/pyroduct-group-en.mbt "$group_src/en.mbt"
echo "staged English pyroduct vocabulary into $subject_src and $group_src"
