# Research: Codec Contract Verification

Phase 0 output. Most questions were answered from the committed prototype
(`prove.sh`, `proofs/run.sh`, `src/openzl/shared/c_contracts.h`, `CONTRACTS.md`)
and from direct measurement of the tree. Measurements below were taken on
`contracts-annotations` at `a43411c` plus the uncommitted `divide_by` /
`float_deconstruct` annotations.

## Design Decisions

### D6 — What defines the coverage surface

**Decision**: every exported function reachable from a decode path, wherever it
is declared — not a filename glob.

**Why**: the spec says "31 decode kernel source files", but `decode_*kernel*.c`
matches **30** files / 6521 LOC today, and `bitpack` has no decode kernel `.c`
at all: `ZS_bitpackDecode8/16/32/64` and `ZS_bitpackDecode` are declared in
`common_bitpack_kernel.h` and defined in `common_bitpack_kernel.c` (1392 LOC, 85
asserts) — the target `CONTRACTS.md` already names as the highest-value one,
because `nbBits` reaches it straight off the wire through `DI_bitunpack`. A
glob-defined surface omits it by accident of naming.

**Mechanical definition** (what the enumerator implements):

1. every function declared in `src/openzl/codecs/*/decode_*kernel*.h`, plus
2. every function declared in `src/openzl/codecs/*/common_*kernel*.h` that is
   referenced from a `decode_*` translation unit in the same codec directory.

Rule 2 was validated against all three `common_*_kernel.h` files and a fourth
discovered by it:

| Header | Reached from | In scope |
|---|---|---|
| `bitpack/common_bitpack_kernel.h` | `decode_bitpack_binding.c` | yes |
| `bitSplit/common_bitSplit_kernel.h` | `decode_bitSplit_binding.c` | yes |
| `pivco_huffman/common_pivco_kernel.h` | `decode_pivco_binding.c`, `decode_pivco_kernel.c` | yes |
| `conversion/common_endianness_kernel.h` | `decode_conversion_binding.c` | yes — not previously enumerated anywhere |

**Alternatives rejected**: the strict `decode_*kernel*.c` glob is the reading the
spec's wording invites and is the foreseeable implementation mistake here — it
is cheaper, it matches the sentence, and it silently drops bitpack. Naming
bitpack as a one-off exception was also rejected: it fixes the known omission
and leaves the same accident available to `pivco` and `conversion`.

**Spec correction**: the spec's "31 decode kernel source files" (SC-001,
Summary, Design Decisions) is a measurement that no longer holds. The surface is
**34 headers across 31 codec directories**; the file count is not the unit of
coverage, the function is.

### D7 — Manifest is the single source of truth for the record and the suite

**Decision**: one tab-separated manifest, `proofs/cases.tsv`, holds every
coverage entry. `proofs/run.sh` iterates it instead of carrying hardcoded
`run_proof` calls; `CONTRACTS.md`'s coverage tables are generated from it into
marker-delimited regions; a completeness check diffs it against the enumerator.

**Why**: `CONTRACTS.md` and `proofs/run.sh` are independent hand-written lists
today, which is tolerable at 4 entries and a drift machine at ~110. More
importantly SC-001 ("no function is absent from the record") is only a
verifiable claim if something mechanically compares the record against an
enumeration of the surface — otherwise it is an assertion about a hand-written
document.

**Format is TSV, not JSON or YAML**: `proofs/run.sh` is POSIX `sh` and its only
stated dependencies are a C preprocessor and the CBMC tools. A JSON manifest
adds `jq` to the dependency list of the thing whose whole point is being
reproducible from the commands written beside it; TSV reads with
`while IFS="$(printf '\t')" read -r ...`. Markdown-table-as-source-of-truth was
considered and rejected in the same breath: parsing the record's own prose
formatting in `sh` couples the runner to how the document is laid out.

**Generation is partial, not whole-file**: the generator rewrites only the
regions between `<!-- BEGIN GENERATED: ... -->` / `<!-- END GENERATED -->`
markers. `CONTRACTS.md`'s value is its prose — the Legend, the Gotchas, the
Observations rationale — and a fully generated file would lose all of it. The
generator also has a `--check` mode that fails when the committed file is stale,
which is how staleness is caught without CI.

### D8 — Enumerator is Python 3, and must survive annotation

**Decision**: `proofs/enumerate.py`, Python 3 with no third-party imports.

**Why**: a prototype of this enumerator in `grep` produced wrong answers that
looked right. Declarations span multiple lines with nested parentheses in the
parameter list, and the repo already depends on `python3` (`make test-cli`,
`scripts/check_python_format.sh`).

**The failure mode that matters**, found while prototyping: a naive
`\)\s*;` pattern stops matching a declaration once contract clauses are inserted
between the closing parenthesis and the semicolon. The prototype reported **0**
functions for `zigzag`, `delta`, `divide_by` and `float_deconstruct` — the four
families that are already annotated. That bug shrinks the denominator as work
progresses, so SC-001 reaches 100% by deleting the surface. The enumerator's
acceptance test is therefore: run it against the annotated headers and confirm
every already-annotated function is still listed.

**Alternatives rejected**: driving the enumeration off `nm` on built objects
would be exact, but it requires a build, cannot see header-declared inline
functions, and reports mangled internal leaves the record does not want.

### D9 — Tiered suite, no outer parallelism

**Decision**: `proofs/run.sh` gains a `tier` filter. Default runs the `fast`
tier; `--all` runs every dispatchable case; `--filter PATTERN` runs matching
function names. Each case keeps its own standalone `prove.sh` command in the
record, unchanged.

**Why**: `ZS_deltaDecode64_scalar` alone is 34s against a 180s default budget,
and the surface is ~110 functions. A single sequential full run is an hour-plus
job, which is fine for an audit artifact run deliberately and useless as the
command someone runs after editing one clause.

**No `-j`**: `prove.sh` already races every installed solver (`sat`, `z3`,
`bitwuzla`, `cvc5`) in parallel per proof and kills the losers. An outer job
pool contends with that race for the same cores, which turns `TIMEOUT` from a
budget into a source of nondeterministic failures — the exact flakiness D3
rejected CI gating to avoid.

**Tier assignment**: a case is `slow` when its recorded elapsed time exceeds
20s. The boundary is recorded in the manifest, not inferred at runtime, so the
default run's contents are reviewable.

**Baseline measured** during this research phase: `./proofs/run.sh` is green,
4 behaved as recorded, 0 did not — `ZL_zigzagDecode64` 2s, `ZL_zigzagDecode32`
3s, `ZS_deltaDecode64_scalar` 35s, `ZS_deltaDecode64` 29s, 69s wall clock. Three
of the four existing cases are already `slow` by the threshold above. Extrapolated
naively to ~110 functions this is well past half an hour, which is what the tier
split exists to keep off the everyday command.

### D10 — `c_contracts.h` is exempted from the format gate, not reformatted

**Decision**: add `src/openzl/shared/c_contracts.h` to `.clang-format-ignore`.

**Why**: this is a **live CI failure**, not a hypothetical. CI pins
`clang-format-version: '21'` with `check-path: '.'` and
`exclude-regex: '.*/datasets/.*'` (`.github/workflows/dev-ci.yml:239-248`).
Measured against clang-format 21.1.2, the vendored header is dirty: the repo's
`.clang-format` sets `IndentPPDirectives: AfterHash`, and the header is carried
verbatim in upstream LLVM style with unindented directives. The eight annotated
kernel files are clean; `c_contracts.h` alone is not.

Reformatting it forks the vendored copy from
`https://github.com/cs01/c-contracts` and makes every future re-vendor a manual
merge. `.clang-format-ignore` already carries exactly this precedent for a
vendored file (`*/json.hpp`).

### D11 — The pinned formatter is resolved by version, not by path

**Decision**: `scripts/check_contract_format.sh` resolves a clang-format whose
`--version` reports 21, trying `$CLANG_FORMAT`, then `clang-format-21`, then
`clang-format`; it refuses loudly rather than silently using a different
version.

**Why**: the spec's assumption that "the pinned version is now available
locally" is true but fragile in the way that matters — `clang-format` first on
PATH here is **19.1.2**, and 21.1.2 lives at
`~/fbsource3/tools/third-party/clang-format/clang-format`. Checking with 19 and
shipping to a gate running 21 is precisely the failure FR-014 names. Hardcoding
that path into a repository script is not an option: it is a machine-specific
path in an open-source tree. Resolving by reported version is portable and fails
closed.

### D12 — Coverage completeness is reached before the proofs are

**Decision**: the manifest carries a `reason_class` column with a closed
vocabulary, including a transient `todo` value. Every function gets a row as
soon as the enumerator finds it. Final acceptance rejects `todo`.

**Why**: SC-001 is about the *record* being complete, which is achievable on day
one and then stays true as rows convert from a reason to a verdict. Without a
transient class, the record cannot be complete until the last proof lands, so
the completeness check has nothing to enforce during the work. Without rejecting
`todo` at acceptance, "not attempted" becomes a permanent reason and D2's
acceptance bar — a green proof or a reason it *cannot* be discharged — quietly
degrades into "a green proof or nothing yet".

### D13 — Cadence mechanism, revisited

Exploration flagged D3 for mechanism review. **Unchanged: on-demand only.**
`proofs/run.sh` stays the single entry point; no workflow file is added. The
weekly non-blocking option stays a recorded later step rather than part of this
plan, because it needs CBMC 6+ in a CI image and the full-surface runtime is
measured in tens of minutes at minimum.

### D14 — Assert-promotion mechanism, revisited

Exploration flagged D4 for mechanism review. **Unchanged, and now exemplified.**
FR-003b settles the policy; the in-flight `divide_by` diff settles the shape: the
value invariant is promoted to a header-level
`contract_pre(contract_forall(i, 0, inputLength, ...))` while the loop body's
`assert` is left byte-for-byte alone. Under stock clang `contract_forall`
degrades to `1`, so the promoted quantified clause costs nothing at call sites
and carries its weight only under CBMC.

## Findings that change the plan

### F1 — The branch is red on the format gate right now

`src/openzl/shared/c_contracts.h` fails clang-format 21.1.2 under the repo's
`.clang-format`, and is not excluded by `.clang-format-ignore` (which contains
only `*/json.hpp`). CI's clang-format job checks `.`. This is an existing
committed defect on `contracts-annotations`, introduced by `83615a2`, and it
blocks SC-005 independently of anything else in this plan. Fixed first, in
Phase 1.

### F2 — `c_contracts.h` leaks a diagnostic suppression into every including TU

Under stock clang the header does, at file scope with no push/pop:

```c
#pragma clang diagnostic ignored "-Wgcc-compat"
```

The comment explains why it is not pushed and popped (popping would re-enable
the warning before any annotated declaration compiles), but the consequence is
that every translation unit including an annotated kernel header has
`-Wgcc-compat` disabled from that include onward. The repo builds under clang in
CI. FR-012b says the annotations introduce no new diagnostics; it says nothing
about *removing* one, but silently disabling a warning across unrelated code in
a TU is a consumer-visible effect of a change the spec frames as inert. Plan
step: measure whether `-Wgcc-compat` currently fires anywhere in the affected
TUs, and place the include last among the annotated header's includes to
minimise the span.

### F3 — No annotated header is publicly installed, and nothing enforces that

Verified against `CMakeLists.txt:287-308`: only `include/openzl` and
`cpp/include/openzl` are installed. Every kernel header and `c_contracts.h` live
under `src/openzl/`, so the spec's assumption holds today. Nothing prevents a
future header from moving. Plan step: a cheap guard asserting no file under the
installed include directories includes `c_contracts.h`.

### F4 — Surface size

| Measure | Value | Method |
|---|---|---|
| `decode_*kernel*.c` | 30 files, 6521 LOC | `ls`, `wc -l` |
| Decode kernel headers | 30 | `ls src/openzl/codecs/*/decode_*kernel*.h` |
| `common_*kernel*.h` in scope | 4 | reachability rule above |
| Exported functions | ~110 (prototype counted 88 with the annotation blind spot of D8 active, and undercounted `common_bitpack_kernel.h` at 1 of 5) | prototype enumerator |

The exact number is an output of the enumerator, not an input to the plan. The
plan is sized for ~110 and does not depend on the precise figure.

### F5 — Codec directories with no decode kernel

`bitunpack`, `concat`, `dedup`, `interleave`, `lz4`, `zstd` and `common` have no
decode kernel header. They are binding-only or wrap an external library. They
produce no coverage rows and are named in the record's scope statement so their
absence is deliberate rather than unexplained.

## Verification commands

There is no root `CLAUDE.md` and no `.specify/memory/verification-commands.md`,
so the SpecKit fallback (`arc f` / `arc lint -a` / `arc unit`) would have
applied. It does not fit: this is an open-source CMake/Make repository with
GitHub Actions, not an fbcode target. The commands below are what CI actually
runs, and the plan uses them.

| Purpose | Command | Source |
|---|---|---|
| Format gate (pinned) | `scripts/check_contract_format.sh` — wraps clang-format 21 | `.github/workflows/dev-ci.yml:239` |
| Build + warning set | `make lib` with the `compile_flags.txt` warning set, under both `cc` and `clang` | `.github/workflows/dev-ci.yml` build matrix |
| Tests | `make test` | `Makefile:195` |
| Proofs (fast tier) | `./proofs/run.sh` | this plan |
| Proofs (full surface) | `./proofs/run.sh --all` | this plan |
| Coverage record freshness | `./proofs/render.py --check` | this plan |
| Coverage completeness | `./proofs/enumerate.py --check` | this plan |

## Resolved Unknowns

| Unknown | Resolution | Where |
|---|---|---|
| What counts as a decode kernel | Decode-reachable exported functions; `decode_*kernel*.h` plus decode-referenced `common_*kernel*.h` | D6 |
| Spec's "31 files" | Measures as 30 `.c` / 34 in-scope headers; file count is not the coverage unit | D6, F4 |
| Source of truth for record and suite | `proofs/cases.tsv`, TSV, marker-delimited generation into `CONTRACTS.md` | D7 |
| Enumerator implementation | Python 3, no deps, must list already-annotated functions | D8 |
| Full-suite runtime | Tiered with `--all` / `--filter`; no outer `-j` | D9 |
| Pinned formatter version | 21 (CI); 19.1.2 is first on PATH locally; resolve by reported version | D11, F1 |
| `c_contracts.h` format status | Dirty under 21; exempt via `.clang-format-ignore` | D10, F1 |
| Public header exposure | None today; guard added | F3 |
| Cadence | On-demand only, unchanged | D13 |
| Assert promotion shape | `contract_pre` + `contract_forall`, assert untouched | D14 |
| Repo verification commands | `make lib` / `make test` / clang-format 21; not `arc` | above |
