# Implementation Plan: Codec Contract Verification

**Branch**: `contracts-annotations` | **Date**: 2026-09-11 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-codec-contract-verification/spec.md`

## Summary

Complete the decode-kernel contract surface that a committed prototype started:
write preconditions, frame conditions and loop invariants on every exported
function reachable from a decode path, and discharge each with CBMC or record a
terminal reason it cannot be discharged. The work turns two hand-written lists —
`CONTRACTS.md` and `proofs/run.sh`, workable at four entries and a drift machine
at roughly a hundred and ten — into one machine-readable manifest that drives
the suite, generates the record's tables, and is diffed against a mechanical
enumeration of the surface so that "no function is absent" is a checked claim
rather than an assertion. Research surfaced one live CI failure and two
consumer-visible effects of the vocabulary header that the plan fixes before
any new annotation lands.

## Technical Context

Everything derivable from `CONTRACTS.md`, `compile_flags.txt` and the CI
workflow is omitted. What follows is load-bearing and not obvious from those.

- **The format gate is red on this branch today.** `src/openzl/shared/c_contracts.h`
  is dirty under clang-format 21.1.2 — the version
  `.github/workflows/dev-ci.yml:246` pins, checking path `.` with only
  `datasets` excluded. The repo's `.clang-format` sets
  `IndentPPDirectives: AfterHash`; the vendored header carries upstream LLVM
  style with unindented directives. `.clang-format-ignore` contains only
  `*/json.hpp`. SC-005 cannot pass until this is addressed.
- **`clang-format` first on PATH here is 19.1.2; the pinned 21.1.2 is elsewhere**
  (`~/fbsource3/tools/third-party/clang-format/clang-format`). The eight
  already-annotated files were checked against 21 during research and are clean.
  The hazard is procedural, not present: a future annotation checked with 19
  reaches a gate running 21.
- **The coverage surface is not a filename glob.** `decode_*kernel*.c` matches 30
  files, not the spec's 31, and bitpack's decode kernel — the highest-value
  target — lives in `common_bitpack_kernel.c`. Scope is decode-*reachable*
  exported functions; see [research.md](research.md) D6.
- **A naive enumerator shrinks the denominator as work progresses.** A `grep`
  prototype reported zero functions for all four already-annotated families,
  because contract clauses sit between the closing parenthesis and the
  semicolon. SC-001 would then reach 100% by deleting the surface.
- **NEEDS CLARIFICATION — none.** All Phase 0 unknowns resolved; see the
  Resolved Unknowns table in [research.md](research.md).

## Constitution Review

Constitution compliance is evaluated by Plan Review (auto-triggered via `after_plan` hook). See `review/review-findings.md` for findings.

## Project Structure

### Documentation (this feature)

```text
specs/001-codec-contract-verification/
├── plan.md                     # This file
├── spec.md                     # Input
├── exploration.md              # Specify-stage design record
├── research.md                 # Phase 0 output
├── data-model.md               # Phase 1 output
├── contracts/
│   ├── cli.md                  # enumerate.py / render.py / run.sh / check_contract_format.sh
│   └── coverage-record.md      # CONTRACTS.md generated-region contract
└── tasks.md                    # /speckit-tasks output — NOT created here
```

There is no `quickstart.md`: this is not greenfield, and the quickstart already
exists as `CONTRACTS.md`'s **Running** section, which documents `CF`, the
`-DNDEBUG` rationale and the per-entry commands. Phase 1 extends that section
rather than duplicating it.

### Source Code (repository root)

```text
CONTRACTS.md                              # MODIFIED — prose retained, tables generated
.clang-format-ignore                      # MODIFIED — exempt the vendored vocabulary header
prove.sh                                  # UNCHANGED — the per-proof driver is correct as-is
proofs/
├── run.sh                                # MODIFIED — manifest-driven, tiered
├── try.sh                                # NEW (untracked today) — scratch driver, commit as-is
├── cases.tsv                             # NEW — the manifest, one row per in-scope function
├── enumerate.py                          # NEW — surface enumerator + completeness check
├── render.py                             # NEW — manifest → CONTRACTS.md generated regions
└── callsite/                             # NEW — US3 negative-compile demonstration
scripts/
└── check_contract_format.sh              # NEW — FR-014 gate at the pinned version
src/openzl/shared/c_contracts.h           # UNCHANGED — vendored; exempted, not reformatted
src/openzl/codecs/*/decode_*kernel*.h     # MODIFIED — 30 headers, clause-bearing declarations
src/openzl/codecs/*/decode_*kernel*.c     # MODIFIED — 30 files, loop contracts; asserts untouched
src/openzl/codecs/bitpack/common_bitpack_kernel.{h,c}       # MODIFIED — in scope per D6
src/openzl/codecs/bitSplit/common_bitSplit_kernel.{h,c}     # MODIFIED — in scope per D6
src/openzl/codecs/pivco_huffman/common_pivco_kernel.{h,c}   # MODIFIED — in scope per D6
src/openzl/codecs/conversion/common_endianness_kernel.h     # MODIFIED — in scope per D6
```

**Structure Decision**: new tooling lands in `proofs/`, beside the runner it
serves, except the format checker which goes in `scripts/` alongside the
existing `scripts/check_python_format.sh`. No file placement constraint was
found in any loaded context — there is no root `CLAUDE.md`, no scan profile and
no project-context file — and `proofs/` is the precedent the prototype already
set. The manifest lives at `proofs/cases.tsv` rather than in `specs/`, because
it is a permanent repository artifact that outlives this feature directory.

---

## Change Overview

| Area | Before | After |
|---|---|---|
| Format gate | The vocabulary header fails the pinned clang-format 21 check that CI runs over the whole tree | The vendored header is exempted the same way `json.hpp` already is, and a checker refuses to run at any version other than the pinned one |
| Coverage surface | Defined by a filename pattern, which silently omits bitpack — the kernel where wire bytes become bit widths | Defined by decode reachability, so bitpack, bitSplit, pivco and conversion kernels are all inside it |
| What the record covers | Four proven functions, a hand-written TODO list, and no statement about the other hundred-odd | Every in-scope function has a row: a discharged verdict, or a reason naming why it cannot be discharged |
| Keeping record and suite aligned | Two independent hand-written lists that can disagree without anyone noticing | One manifest drives both; a check fails when the record and the enumerated surface differ |
| Running the proofs | One command that runs everything, already 69 seconds at four entries | A fast tier by default, the full surface behind a flag, and a name filter for the clause you just edited |
| A codec author's feedback on misuse | A debug assert that compiles to nothing in release | A clang diagnostic at any call site where the violation folds, demonstrated by a committed negative-compile case |
| Release-build guarantees | Kernels trust their callers completely; the binding layer is the sole validation boundary | Each kernel's requirements are stated, proven over every input satisfying them, and checked at foldable call sites — the bindings' own obligations remain unproven and are named as the successor |

## Plan Flow

```text
Research (surface, gate, manifest shape) → Design (data model + CLI contracts)
       │
┌─ Foundation ────────────────────────────────────────────────────────┐
│ ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐     │
│ │ Step 1     │→ │ Step 2     │→ │ Step 3     │→ │ Step 4     │     │
│ │ format gate│  │ enumerator │  │ manifest   │  │ run.sh     │     │
│ └────────────┘  └────────────┘  └────────────┘  └─────┬──────┘     │
│                 ┌────────────┐  ┌────────────┐        │            │
│                 │ Step 6     │← │ Step 5     │◀───────┘            │
│                 │ seed+verify│  │ render.py  │                     │
│                 └────────────┘  └────────────┘                     │
└──────────────────────────────────────────────────────────────┬─────┘
                                                               │
┌─ Triage ────────────────────────────────────────────────────▼─────┐
│ ┌──────────────┐        ┌──────────────┐                          │
│ │ Step 7       │        │ Step 8       │                          │
│ │ classify all │        │ exposure     │                          │
│ │ rows by mode │        │ guards       │                          │
│ └──────────────┘        └──────────────┘                          │
└──────────────────────────────────────────────────────────────┬─────┘
                                                               │
┌─ Annotate & prove ──────────────────────────────────────────▼─────┐
│ ┌────────────┐   ┌────────────┐   ┌────────────┐                  │
│ │ Step 9     │ → │ Step 10    │ → │ Step 11    │─┐                │
│ │ in-flight  │   │ bitpack    │   │ batch A    │ │                │
│ └────────────┘   └────────────┘   │ Step 12    │ ├─┐              │
│                                   │ batch B    │ │ │              │
│                                   │ Step 13    │─┘ │              │
│                                   │ batch C    │   │              │
│                                   └────────────┘   │              │
└────────────────────────────────────────────────────┼──────────────┘
                                                     │
┌─ Record & close ───────────────────────────────────▼──────────────┐
│ ┌────────────┐   ┌────────────┐   ┌──────────────────┐            │
│ │ Step 14    │ → │ Step 15    │ → │ Step 16          │            │
│ │ divergence │   │ call-site  │   │ prose + verify   │            │
│ └────────────┘   └────────────┘   └──────────────────┘            │
└───────────────────────────────────────────────────────────────────┘
```

## Phase 0: Outline & Research

Complete. See [research.md](research.md) — decisions D6–D14, findings F1–F5,
Resolved Unknowns table. No Premise Validation gates were extractable from the
spec's two-line verdict form; the full analysis in `exploration.md` states no
conditional prerequisites.

## Phase 1: Design & Contracts

Complete. [data-model.md](data-model.md) covers the four spec entities plus the
manifest's physical schema, validation rules and state machine.
[contracts/cli.md](contracts/cli.md) fixes the command surface and exit codes of
the three new tools and the modified runner;
[contracts/coverage-record.md](contracts/coverage-record.md) fixes the
generated-versus-authored boundary in `CONTRACTS.md`.

## Phase 2: Foundation

The spine. Nothing in later phases is trustworthy until the gate is green and
the record's completeness is mechanically checkable.

### Step 1 — Unblock the format gate

Add `src/openzl/shared/c_contracts.h` to `.clang-format-ignore`, following the
`*/json.hpp` precedent for a vendored file. Write
`scripts/check_contract_format.sh` per [contracts/cli.md](contracts/cli.md):
resolve a clang-format reporting major version 21 via `$CLANG_FORMAT`,
`clang-format-21`, then `clang-format`; exit 3 rather than 0 when none is found.

**Artifacts**: `.clang-format-ignore` (modified), `scripts/check_contract_format.sh`,
`proofs/try.sh` (commit the existing untracked scratch driver as-is).

**Verification**: `scripts/check_contract_format.sh` exits 0 over the eight
already-annotated files. Simulating CI — running the pinned formatter over the
tree the way `jidicula/clang-format-action` does with `check-path: '.'` and
`exclude-regex: '.*/datasets/.*'` — reports no diff. Running the script with
`CLANG_FORMAT=$(command -v clang-format)` (the 19.1.2 on PATH) exits 3, not 0.

### Step 2 — The surface enumerator

Write `proofs/enumerate.py` implementing D6's two-rule surface and the CLI in
[contracts/cli.md](contracts/cli.md). Python 3, standard library only, no build
required.

**Artifacts**: `proofs/enumerate.py`.

**Verification**: run against the four already-annotated headers
(`decode_zigzag_kernel.h`, `decode_delta_kernel.h`, `decode_divide_by_kernel.h`,
`decode_float_deconstruct_kernel.h`) and confirm every annotated function
appears — this is the D8 regression test and it must be written before the
enumerator is trusted for anything else. Confirm the output includes
`ZS_bitpackDecode8/16/32/64` and `ZS_bitpackDecode` from
`common_bitpack_kernel.h`, `ZL_bitSplit_outputEltWidth`, the decode-reachable
`common_pivco_kernel.h` symbols, and the `conversion/common_endianness_kernel.h`
symbol. Confirm it excludes `bitunpack`, `concat`, `dedup`, `interleave`, `lz4`,
`zstd` and `common`, which have no decode kernel header (F5). Confirm the
output also reports `entropy/common_huffman_kernel.h` as in scope under rule 2
(it is referenced from `decode_huffman_kernel.c`) but contributing zero
functions, since it declares only an enum.

### Step 3 — The manifest

Create `proofs/cases.tsv` with the nine-column schema from
[data-model.md](data-model.md), and backfill the four recorded entries with
their measured tiers from the research baseline: `ZL_zigzagDecode64` fast,
`ZL_zigzagDecode32` fast, `ZS_deltaDecode64_scalar` slow, `ZS_deltaDecode64`
slow with `flags = -r ZS_deltaDecode64_scalar`.

**Artifacts**: `proofs/cases.tsv`.

**Verification**: every row satisfies the data-model validation rules —
`mode = none` implies `expect = -` and `tier = -`; `expect = FAIL` implies
`reason_class = defect`. Four rows, four `PASS`.

### Step 4 — Manifest-driven runner

Rewrite `proofs/run.sh`'s dispatch to iterate `proofs/cases.tsv` instead of
carrying hardcoded `run_proof` calls, and add `--all`, `--filter PATTERN` and
`--tier`. Keep the report shape, the `SKIP` semantics, the `PROVE` and `BUDGET`
environment variables, and the exit-code-is-mismatch-count contract. Make the
annotation-absent guard fail closed on its own precondition — a missing guard
file is a hard error distinct from a present-but-unannotated file — and have
the summary line always print the manifest row count alongside any `SKIP`
message. Add no outer parallelism (D9).

**Artifacts**: `proofs/run.sh` (modified).

**Verification**: `./proofs/run.sh --all` reproduces the research baseline
exactly — 4 behaved as recorded, 0 did not, 0 skipped, exit 0. `./proofs/run.sh`
with no arguments runs only the two fast entries. `./proofs/run.sh --filter
deltaDecode64` runs the two delta entries regardless of tier. Temporarily
flipping one row's `expect` to `FAIL` makes the suite exit 1 and print the
`<-- RECORDED` marker; revert.

### Step 5 — The record generator

Write `proofs/render.py` per [contracts/cli.md](contracts/cli.md), and insert
the five marker pairs from
[contracts/coverage-record.md](contracts/coverage-record.md) into
`CONTRACTS.md`. Move the existing "Proven correct" table inside the `coverage`
markers; leave the Scope, Requirements, Running, Legend, Observations rationale,
Open questions and Gotchas prose outside them, byte-for-byte.

**Artifacts**: `proofs/render.py`, `CONTRACTS.md` (markers inserted).

**Verification**: `./proofs/render.py && git diff CONTRACTS.md` shows changes
only between markers. `./proofs/render.py --check` exits 0. Editing a word of
prose outside a marker and re-running `--check` still exits 0. Deleting a
closing marker makes `--check` exit 2.

### Step 6 — Seed every row and close the loop

Run the enumerator and append a `todo` reason row for every in-scope function
that has no row yet: `mode = none`, `expect = -`, `tier = -`,
`reason_class = todo`, `reach` left for Step 7. Regenerate the record.

This is the step that makes SC-001 true on day one (D12): the record is complete
immediately and stays complete as rows convert from reasons to verdicts.

**Artifacts**: `proofs/cases.tsv` (≈110 rows), `CONTRACTS.md` (regenerated).

**Verification (Phase 2 gate, sequential)**: `./proofs/enumerate.py --check`
exits 0. `./proofs/enumerate.py --strict` exits 3 — the `todo` rows are visible
and rejected by the final-acceptance mode, which is correct at this point.
`./proofs/render.py --check` exits 0. `./proofs/run.sh --all` still 4/4.
`scripts/check_contract_format.sh` exits 0. `make lib && make test` passes under
both `cc` and `clang`, unchanged from before the phase.

## Phase 3: Triage

Decide *how* each function will be approached before writing a single clause, so
the hard cases surface as design questions rather than as dead ends discovered
one at a time.

### Step 7 — Classify every row

For each `todo` row, assign `mode`, provisional `reason_class` and `reach`
without writing clauses. The classification questions, in order:

1. Does it take a framework handle, or a struct with internal pointers that
   `contract_fresh` cannot construct? → `mode = none`, `reason_class = framework`.
   `rolz`'s `ZS_RolzDTable2*` parameters are the expected population here; the
   spec's "zero kernels take a framework handle" measurement was about
   `ZL_Decoder`/`ZL_Input`/`ZL_Output` and does not cover this case.
2. Do pointer arguments alias into one object? → `mode = harness`, or
   `mode = none` with `reason_class = alias` if no harness is written.
   FR-004 conditions the harness-free guarantee on non-aliasing, so a harness
   here does not violate US1's independent test.
3. Is the only path vector intrinsics with a scalar leaf available? →
   `mode = enforce-r` on the dispatcher, plus a separate `mode = enforce` row for
   the leaf. No scalar leaf → `mode = none`, `reason_class = simd`.
4. Does it call a loop-bearing callee that would be inlined? →
   `mode = enforce-r` with the callee in `flags`. This is the recorded gotcha and
   the `ZS_deltaDecode64` shape.
5. Otherwise → `mode = enforce`, `expect = PASS`, `reason_class = todo` until
   proven.

`reach` is `decode` when a `decode_*_binding.c` reaches the function, and
`test-only` otherwise. The spec's edge case requires reachability recorded
beside the verdict so a reader does not over-credit a proof of unreachable code.

**Artifacts**: `proofs/cases.tsv` (every row classified), `CONTRACTS.md`
(regenerated).

**Verification**: no row has `reach` unset. Every row with `mode = enforce-r`
names a callee in `flags`. Every row with a terminal `reason_class` has a `note`
naming the specific barrier, not a category. `./proofs/enumerate.py --check`
exits 0.

### Step 8 — Exposure guards

Two consumer-visible effects found in research, neither of which is annotation
work but both of which constrain it.

**F2 — the `-Wgcc-compat` leak.** Under stock clang, `c_contracts.h` executes
`#pragma clang diagnostic ignored "-Wgcc-compat"` at file scope with no
push/pop, by design. Every TU including an annotated kernel header therefore has
that warning disabled from the include onward. Measure whether `-Wgcc-compat`
currently fires anywhere in the TUs that will include an annotated header: build
under clang with the `compile_flags.txt` warning set plus `-Wgcc-compat`, before
and after. Record the result. Adopt the include-placement policy that the
`c_contracts.h` include is the last include in an annotated header, minimising
the span, and document it beside the existing include-order gotcha.

**F3 — public header exposure.** Only `include/openzl` and `cpp/include/openzl`
are installed (`CMakeLists.txt:287-308`); every annotated header is under
`src/openzl/`. Add a guard asserting no file under the installed include
directories includes `openzl/shared/c_contracts.h`, so a future header move
fails loudly rather than shipping an uninstallable dependency.

**Artifacts**: the guard (a check in `scripts/check_contract_format.sh` or a
sibling script), the measured `-Wgcc-compat` result recorded in `CONTRACTS.md`'s
Gotchas, the include-placement policy documented there.

**Verification**: the guard exits 0 today and exits non-zero when a
`c_contracts.h` include is temporarily added to a file under `include/openzl`.
The clang build with `-Wgcc-compat` produces the same warning set before and
after annotation, or the difference is recorded as a finding.

## Phase 4: Annotate & Prove

Risk-ordered. Each step's inner loop is the same: write clauses on the header
declaration, add loop contracts in the body, leave every `ZL_ASSERT` untouched
(FR-003b), iterate with `./proofs/try.sh`, then record the row and regenerate.
The `divide_by` annotations already in the working tree are the exemplar for
clause shape — a quantified value invariant promoted to
`contract_pre(contract_forall(...))` on the declaration, with the body's
`assert` byte-for-byte unchanged.

Each step also ends with the same three checks: `scripts/check_contract_format.sh`
clean at the pinned version, no new diagnostics in a `make lib` under both `cc`
and `clang` — or, when a new diagnostic does appear, it is triaged rather than
silenced: a `diagnose_if` precondition violation at a real call site becomes a
`defect`-or-`observation` row in `CONTRACTS.md` and the clause is not weakened;
any other new diagnostic is fixed (FR-012b) — and `./proofs/enumerate.py --check`
still exit 0.

### Step 9 — Close the in-flight work

The four families already in progress, plus the TODO rows the existing record
already lists.

- `divide_by` — annotations are in the working tree and unproven. Prove all five
  functions. The `ZS_divideByDecode16` signed-overflow finding from the spec's
  premise validation is expected to reproduce: C integer promotion makes the
  guarded multiply `(signed int) * (signed int)`, so violating the release-inert
  `USHRT_MAX` guard is signed overflow, not the benign unsigned wrap the guard's
  form implies. If it reproduces, record `expect = FAIL`,
  `reason_class = defect`, with the reproduction command — do not change the
  codec (FR-015).
- `float_deconstruct` — annotations are in the working tree and unproven. Prove
  all three exported functions and their scalar leaves.
- `zigzag` — `ZL_zigzagDecode8/16` and `ZL_zigzagDecode` are annotated but not in
  the suite. Add rows and prove.
- `delta` — `ZS_deltaDecode8/16/32` and their `_scalar` leaves dispatch through
  SSSE3; use `enforce-r` onto the scalar leaf per Step 7's rule 3.
  `ZS_deltaDecode` reads `first` through `ZL_readLE*`, so the proof needs
  `openzl/shared/mem.h` reachable from the entry point.

**Artifacts**: the four families' headers and `.c` files, `proofs/cases.tsv`,
`CONTRACTS.md`.

**Verification**: `./proofs/run.sh --all` matches every recorded verdict,
including the `FAIL` if the `divide_by` finding reproduces. The existing four
entries are unaffected.

### Step 10 — bitpack

`ZS_bitpackDecode8/16/32/64` and `ZS_bitpackDecode` in
`common_bitpack_kernel.{h,c}` — 1392 LOC, 85 asserts, and the single
highest-value target because `nbBits` reaches it straight off the wire through
`DI_bitunpack`. Separated from the other batches because it is one kernel whose
outcome is worth knowing on its own, whatever happens to the rest.

The record's open question on this kernel — whether
`ZL_ERR_IF_GT(nbBits, 8 * eltWidth)` is sufficient for every `eltWidth`/`nbElts`
the frame can encode — becomes answerable here. Answer it in the row's note, or
record why it remains open.

**Artifacts**: `common_bitpack_kernel.{h,c}`, `proofs/cases.tsv`, `CONTRACTS.md`.

**Verification**: each of the five functions has a discharged verdict or a
terminal reason. The open question is either answered or restated with what the
proof did establish.

### Step 11 — Batch A: fixed-width families

`transpose`, `range_pack`, `constant`, `sentinel`, `splitN`, `splitByStruct`,
`tokenize2to1`, `tokenize4to2`, `quantize`, `partition`, `merge_sorted`,
`bitSplit`, `conversion`'s endianness kernel.

`range_pack` needs specific handling: ten macro-generated static leaves, each
with a loop, needing an `enforce-r` per width pair. The record's open question
about it — that an unsupported `srcWidth`/`dstWidth` pair falls through to
`ZL_ASSERT_FAIL`, a no-op under `NDEBUG`, leaving the caller committing an
uninitialised output — is a candidate defect. Whether any unsupported pair is
reachable from a crafted frame is a binding-layer question and stays out of
scope, but the kernel-level behaviour is provable here and belongs in the row's
note either way.

**Artifacts**: those codecs' headers and `.c` files, their `proofs/cases.tsv`
rows, `CONTRACTS.md`.

### Step 12 — Batch B: variable-length and string families

`flatpack`, `prefix`, `mux_lengths`, `sparse_num`, `parse_int`,
`dispatch_by_tag`, `dispatchN_byTag`, `dispatch_string`, `tokenize`,
`tokenizeVarto4`.

These take length arrays or offsets rather than a single element count, so the
extent preconditions are quantified over an input array rather than stated from
a scalar. Expect a higher proportion of `enforce-r` and a higher proportion of
terminal reasons than Batch A.

**Artifacts**: those codecs' headers and `.c` files, their `proofs/cases.tsv`
rows, `CONTRACTS.md`.

### Step 13 — Batch C: the hard families

`lz`, `rolz`, `entropy`'s huffman kernel, `pivco_huffman`.

These are expected to produce a high proportion of terminal reason rows —
`rolz`'s table structs are the `framework` class from Step 7's rule 1, and `lz`
at 29.6 KB is the largest decode kernel in the tree. The acceptance bar here is
D2's: a discharged proof, or a reason naming the specific barrier. A batch that
produces mostly reason rows has succeeded, provided each reason is terminal and
specific.

**Artifacts**: those codecs' headers and `.c` files, their `proofs/cases.tsv`
rows, `CONTRACTS.md`.

**Verification (Phase 4 gate, sequential)**: `./proofs/run.sh --all` matches
every recorded verdict. `./proofs/enumerate.py --check` exits 0. No row outside
Step 16's remit still carries `reason_class = todo`.

## Phase 5: Record & Close

### Step 14 — Prose/contract divergence sweep

Read each annotated codec's `src/openzl/codecs/*/spec.md` — about twenty wire-
format specifications — against the clauses now written on that codec's kernel.
Where a contract and the prose safety claim disagree, record the divergence as
an observation. Do not silently prefer either statement (spec edge case).

**Artifacts**: `CONTRACTS.md` Observations entries.

**Verification**: every annotated codec with a `spec.md` has been read, and the
sweep's coverage is stated — how many specs were read — so a reader knows the
denominator.

### Step 15 — The call-site demonstration

US3 and FR-013 already work in the committed code but nothing demonstrates it.
Add `proofs/callsite/`: a small `.c` that calls an annotated kernel with a
constant-foldable argument violating a precondition, and a check script
asserting that stock clang emits the diagnostic naming that precondition, and
that gcc emits nothing. Keep it out of `make all` — it is a negative-compile
case, not a build target.

**Artifacts**: `proofs/callsite/*`, referenced from `CONTRACTS.md`'s Running
section.

**Verification**: the script exits 0 under clang with the diagnostic present,
exits 0 under gcc with no diagnostic (FR-012a/FR-012b), and exits non-zero if
the precondition is weakened so the diagnostic stops firing.

### Step 16 — The written record

This step produces prose, and the bar is that a reviewer who has run nothing can
use it. Auditing for missing rows is Step 6's job and is already mechanical;
this is a writing task.

For every finding — defect or observation — write four things: where, what, why
it is or is not a bug, and the basis. The existing `decode_zigzag_kernel.h` row
is the exemplar for depth:

> **Where**: `decode_zigzag_kernel.h`. **What**: `ZL_zigzagDecode64` does not
> verify without `contract_pre (nbElts <= SIZE_MAX / 8)`; nothing in the
> signature stops `nbElts * 8` from wrapping, and `r_ok(src, <wrapped>)` then
> permits `src + i` to leave the object. **Why it is not a bug**: not reachable
> from any real caller — no object is that large; the header already required it
> in prose. **Basis**: remove the clause and re-run the command — `arithmetic
> overflow on signed *` at `src[i]`, FAIL 2s.

A row reading "unstated precondition found" is not acceptable output; it has the
shape of a finding and none of the content. Every terminal reason row gets the
same treatment: the note names the specific barrier — which intrinsic, which
callee, which budget — not its category.

Then: sweep every remaining `todo`, converting each to a verdict or a terminal
reason. Update `CONTRACTS.md`'s Scope table to the measured surface (30 decode
kernel `.c`, 34 in-scope headers, the enumerated function count) and correct the
"31 files" figure the spec inherited. Regenerate.

**Artifacts**: `CONTRACTS.md` (final), `proofs/cases.tsv` (final).

**Verification (final acceptance, sequential)**:

| Check | Command | Expect |
|---|---|---|
| SC-001 completeness | `./proofs/enumerate.py --strict` | exit 0 — no function absent, no `todo` remains |
| Record freshness | `./proofs/render.py --check` | exit 0 |
| SC-003 / SC-004 recorded verdicts | `./proofs/run.sh --all` | 0 mismatches; every `expect = FAIL` still fails |
| SC-003 spot reproduction | Pick three rows at random; run each row's own command verbatim from a clean shell | each reproduces its recorded verdict |
| SC-005 format gate | `scripts/check_contract_format.sh` | exit 0 at clang-format 21 |
| SC-005 no new diagnostics | `make lib` under `cc` and under `clang` with the `compile_flags.txt` warning set | warning set identical to the pre-feature baseline, except a new diagnostic already recorded as a defect-or-observation row per the Diagnostic triage check |
| FR-013 call-site | `proofs/callsite/` check script | diagnostic present under clang, absent under gcc |
| Behaviour unchanged | `make test` | passes, unchanged |
| SC-002 readability | Hand the record to someone who has run nothing; ask them to name a proven function, an unproven one, and why | all three answerable from the document alone |
| SC-006 no overstated claim | Every "none found" statement in the record | accompanied by a generated sample size |
| Diagnostic triage | Review any new-diagnostic row recorded during Phase 4 per the per-step check above | each is a `defect`-or-`observation` row in `CONTRACTS.md`, not a weakened clause |

---

## Task Dependencies

> *This section is consumed by downstream pipeline stages (`/speckit-tasks`, `/speckit-implement`) and is not part of the review surface.*

| Group | Steps | Can Parallelize | Notes |
|-------|-------|-----------------|-------|
| 1 | Step 1 | No | Unblocks the gate everything else is verified against; touches `.clang-format-ignore` and creates `scripts/check_contract_format.sh` |
| 2 | Step 2 | No | Creates `proofs/enumerate.py`; Step 3's manifest content is derived from its output |
| 3 | Step 3 | No | Creates `proofs/cases.tsv`, the schema Steps 4 and 5 both read |
| 4 | Steps 4, 5 | Yes | `run.sh` and `render.py` touch different files and neither calls the other; both read the manifest schema Step 3 defined |
| 5 | Step 6 | No | Seeds rows from Step 2's enumerator and regenerates via Step 5's `render.py`; Phase 2 gate |
| 6 | Steps 7, 8 | Yes | Step 7 writes `proofs/cases.tsv`; Step 8 writes the guard script and `CONTRACTS.md` Gotchas prose. Disjoint files, no symbol coupling |
| 7 | Step 9 | No | Closes in-flight work and establishes the clause exemplar the later batches follow |
| 8 | Step 10 | No | bitpack, isolated deliberately |
| 9 | Steps 11, 12, 13 | Yes | Disjoint kernel file sets. Each appends only its own rows to `proofs/cases.tsv`; `./proofs/enumerate.py --check` at the group boundary catches any collision. Do not regenerate `CONTRACTS.md` concurrently — regenerate once at the boundary |
| 10 | Steps 14, 15 | Yes | Step 14 writes Observations prose; Step 15 creates `proofs/callsite/`. Different files, no dependency |
| 11 | Step 16 | No | Final acceptance; depends on every prior group |
