#!/usr/bin/env bash
#
# zmeshopt -- no build artefact is tracked.
#
# `zig fetch` drops the packages it fetches into ./zig-pkg beside the project,
# and a build leaves .zig-cache/ and zig-out/ behind. None of them belong in
# the history: they carry absolute paths from the machine that produced them,
# they bloat every clone, and a fetched package is a second copy of somebody
# else's repository.
#
# On 2026-09-03, 333 such files reached a public main in this family, swept in
# by a blanket `git add -A`. .gitignore had the hole and nothing refused the
# commit; the only reason it surfaced was that the executable-bit gate
# enumerates TRACKED .sh files, so the fetched CI scripts showed up as
# violations of a different rule.
#
# .gitignore keeps them from being added by accident. This refuses them
# outright, so the accident cannot survive a commit.

set -euo pipefail
cd "$(dirname "$0")/.."

tracked=$(git ls-files |
  grep -Ei '(^|/)(\.zig-cache|zig-out|zig-pkg)/|\.(o|obj|a|lib|so|dylib|dll|bak)$' || true)

if [ -n "$tracked" ]; then
  printf 'these build artefacts are tracked, and must not be:\n'
  printf '%s\n' "$tracked" | sed 's/^/  /'
  printf 'fix with: git rm -r --cached <path>, then cover it in .gitignore\n'
  exit 1
fi

printf 'OK  no build artefact is tracked\n'
