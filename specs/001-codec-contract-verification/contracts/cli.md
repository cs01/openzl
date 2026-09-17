# Contract: verification tool command surface

Three commands cross a boundary: they are invoked by hand, quoted verbatim in
`CONTRACTS.md`, and referenced by `tasks.md`. Their exit codes are the
acceptance signal for SC-001, SC-003 and SC-005, so they are specified here
rather than left to implementation.

The manifest schema these share is in
[`../data-model.md`](../data-model.md#coverage-entry).

## `proofs/enumerate.py`

Produces the in-scope function surface (D6) and compares it against the
manifest.

```
proofs/enumerate.py [--check] [--format tsv|list] [--strict]
```

| Flag | Effect |
|---|---|
| *(none)* | Print the enumerated surface to stdout, one `function<TAB>source` per line, sorted |
| `--check` | Compare the surface against `proofs/cases.tsv`; print both differences; exit non-zero on any |
| `--format list` | Function names only, no source column |
| `--strict` | Additionally fail when any row has `reason_class = todo` — the final-acceptance mode (D12) |

**Exit codes**

| Code | Means |
|---|---|
| 0 | Surface and manifest agree (and, under `--strict`, no `todo` remains) |
| 1 | A function is in the surface with no manifest row — SC-001 violated |
| 2 | A manifest row names a function not in the surface — the record has drifted |
| 3 | Under `--strict`, a `todo` row remains |
| 4 | Parse failure in a header or the manifest |

Codes 1 and 2 are distinct because they mean opposite things: 1 is unfinished
work, 2 is a stale record pointing at a function that moved or was deleted.

**Behavioural requirements**

- MUST list a function whose declaration carries contract clauses between the
  closing parenthesis and the semicolon. This is the D8 acceptance test: run
  against `decode_zigzag_kernel.h`, `decode_delta_kernel.h`,
  `decode_divide_by_kernel.h` and `decode_float_deconstruct_kernel.h` and
  confirm every annotated function is still present.
- MUST apply the rule-2 reachability test per codec directory, so
  `common_bitpack_kernel.h`, `common_bitSplit_kernel.h`,
  `common_pivco_kernel.h` and `conversion/common_endianness_kernel.h` are in
  scope.
- MUST NOT require a build, and MUST NOT import anything outside the Python 3
  standard library.

## `proofs/render.py`

Renders the manifest into `CONTRACTS.md`'s generated regions.

```
proofs/render.py [--check]
```

| Flag | Effect |
|---|---|
| *(none)* | Rewrite the marker-delimited regions of `CONTRACTS.md` in place; leave all other bytes untouched |
| `--check` | Render to memory and compare; exit non-zero if the committed file differs |

**Exit codes**

| Code | Means |
|---|---|
| 0 | Written, or (under `--check`) already current |
| 1 | Under `--check`, `CONTRACTS.md` is stale |
| 2 | A required marker pair is missing or unbalanced |
| 4 | Manifest parse failure |

**Behavioural requirements**

- MUST change only bytes between `<!-- BEGIN GENERATED: <id> -->` and
  `<!-- END GENERATED: <id> -->`. Prose outside the markers is hand-authored and
  is never rewritten.
- MUST emit, for each codec with at least one `expect = PASS` row and no
  `defect` row, the sample size behind the claim (FR-011, SC-006) computed from
  the manifest, never typed by hand.
- MUST emit a reproduction command for every row with `expect != -` (FR-008),
  self-contained enough to paste.

## `proofs/run.sh`

The recorded suite. Keeps its current report shape and exit semantics; gains
manifest dispatch and tiering.

```
proofs/run.sh [--all] [--filter PATTERN] [--tier fast|slow]
```

| Flag | Effect |
|---|---|
| *(none)* | Dispatch every manifest row with `tier = fast` |
| `--all` | Dispatch every row with `mode != none` |
| `--filter PATTERN` | Dispatch rows whose `function` matches `PATTERN`, ignoring tier |
| `--tier slow` | Dispatch only `slow` rows |

**Exit code** is the count of mismatches, unchanged from today: an entry whose
actual verdict differs from its `expect` in either direction. `SKIP` is reported
and never counted (FR-009b, and the existing runner's behaviour).

**Environment**, unchanged: `PROVE` overrides the `prove.sh` location; `BUDGET`
overrides the per-proof timeout, default 180s.

**Behavioural requirements**

- MUST NOT introduce outer parallelism. `prove.sh` already races solvers across
  cores per proof (D9).
- MUST skip, not fail, when `cbmc` or `prove.sh` is absent, preserving the
  existing "skipped = missing prerequisite, not a result" line.
- MUST preserve the existing guard that exits 0 with a `SKIP` message on a
  checkout that does not carry the annotations.

## `scripts/check_contract_format.sh`

The FR-014 gate, run against the version CI pins rather than the version on
PATH.

```
scripts/check_contract_format.sh [PATH ...]
```

With no arguments, checks every annotated file (those including
`openzl/shared/c_contracts.h`) plus the vocabulary header's exclusion.

**Formatter resolution order**: `$CLANG_FORMAT`, then `clang-format-21`, then
`clang-format`. Each candidate is accepted only if `--version` reports major
version 21.

**Exit codes**

| Code | Means |
|---|---|
| 0 | Every checked file is clean under clang-format 21 |
| 1 | At least one file is dirty; the diff is printed |
| 3 | No clang-format reporting major version 21 was found — refuses rather than checking with a different version (D11) |

Exit 3 is deliberately not 0. Silently passing because the right formatter is
absent is how the 19-versus-21 divergence reached the gate in the first place.
