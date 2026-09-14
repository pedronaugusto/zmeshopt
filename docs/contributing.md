# Contributing

- `libs/meshoptimizer` is vendored verbatim and must not be edited. Changes
  there are lost at the next re-vendor. If upstream needs fixing, fix it
  upstream; if zmeshopt needs to work around upstream, do it in `src/` and
  record it in [UPSTREAM.md](../UPSTREAM.md).
- Run `ci/run.sh` before pushing — or `ci/install-hooks.sh` once, and it runs
  itself. It is the same matrix CI runs.
- Comments state a contract, not a narrative. `ci/check-comments.sh` enforces
  two things and will fail a pull request over either: block length caps, and
  the register — documentation, not conversation. The cap never justifies
  dropping a fact: units, ownership, sizing rules, error conditions and
  aliasing guarantees come first; if a block cannot hold them, shorten the
  prose around them.
- New source files are added to the explicit lists in `build.zig`
  deliberately; there are no globs, so nothing starts compiling by accident.
- [BINDING.md](../BINDING.md) is the contract for how surface is shaped: the
  naming convention the ABI guard pairs on, the idiomatic layer's rules, and
  what a new binding has to carry.
