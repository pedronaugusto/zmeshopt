# The generated numbers, and what they do not say

Every count the documentation publishes comes from `ci/measurements.sh`.
`ci/check-docs.sh` rebuilds each `<!-- BEGIN GENERATED -->` block from the
command the marker names and fails if what is committed differs, and it
refuses any other multi-digit number in a top-level document unless
`tools/doc_numbers.txt` gives a reason why that number cannot go stale. The
healthy state of that file is empty.

## What a count does not prove

Matching extern counts prove presence, not correctness. The oracle
(`src/abi_check.zig`) and the behavioural tests hold correctness;
`ci/check-coverage.sh` holds the idiomatic layer's reach, one extern at a
time. Source lines measure volume, not surface.

## The number gate's blind spots

`ci/check-docs.sh` reads numbers with a regular expression, so it does not
see:

- a number spelled as a word;
- a single digit;
- a number joined to its neighbour by `-`, `.` or `/` — a date, a version, a
  byte width;
- a number inside `code`, where it is an identifier or a citation rather than
  a claim;
- a sentence that is wrong without containing a number at all.

It also scans only the Markdown files at the top level of the repository, so
the numbers in this directory are not gated. Prefer stating a gated number in
a top-level document and linking to it from here.
