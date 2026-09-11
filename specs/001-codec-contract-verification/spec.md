---
type: infrastructure
risk: medium
complexity: standard
owner: TBD
created: 2026-09-11
---

# Feature Specification: Codec Contract Verification

**Feature Branch**: `001-codec-contract-verification`

## Summary

OpenZL's decode kernels turn attacker-chosen bytes into indices and lengths.
Today the only statement of what each kernel requires of its caller is a
debug-only `ZL_ASSERT` — roughly 300 of them across the 31 decode kernel source
files — and under `NDEBUG` each folds to a statically dead expression whose
predicate is never evaluated. In release builds the kernels are unguarded and
the binding layer is the sole validation boundary.

This capability makes those requirements machine-checkable. Each decode kernel
function carries preconditions, frame conditions and loop invariants that a
model checker discharges exhaustively over every input the contract permits,
and that stock clang independently checks at call sites it can fold.

- **Extension, not greenfield.** A working prototype is committed: the
  annotation vocabulary, the proof runner, a recorded suite, and a coverage
  document already exist, with four kernel families annotated and four proofs
  recorded green. This spec defines completing the decode-kernel surface.
- **Exhaustive, not sampled.** The repository already fuzzes decode paths and
  runs ASAN/UBSAN in CI. Those find defects on inputs they happen to generate;
  a discharged contract covers every input satisfying it. The two are
  complementary, and this capability does not replace either.
- **Report, don't patch.** Confirmed defects get a reproduction command and a
  recorded expected verdict. Changing codec behavior is a separate decision.
- **Audit artifact, not a merge gate.** The toolchain floor is not present in
  CI images, and the repository's existing static-analysis precedent is
  non-blocking.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Annotate and prove a decode kernel (Priority: P1)

**Problem:** A decode kernel's preconditions exist only as prose in a header
comment and as asserts that do nothing in release builds. Nobody can establish
that the kernel is safe for all inputs, only that it survived the inputs
someone tried.

**Why this priority**: This is the capability. Everything else consumes what
this produces. A single kernel taken from prose to discharged proof delivers
value on its own — that kernel is now known safe for every input its contract
permits, independent of whether any other kernel is ever annotated.

**Independent Test**: Pick one unannotated decode kernel, write clauses for its
exported functions, and run the proof workflow. Fully tested by observing
either a discharged proof or a counterexample naming a concrete violated
property — with no hand-written entry point authored at any step.

**Acceptance Scenarios**:

1. **Given** a decode kernel whose pointer arguments do not alias, **When** its
   exported function carries preconditions describing buffer extents and
   element counts, **Then** the verification workflow constructs the entry
   point from those clauses alone and reports a verdict, without any
   hand-written harness existing for that function.
2. **Given** a kernel function containing a loop, **When** the loop carries an
   invariant, a frame and a decreases measure, **Then** the proof is discharged
   by induction and holds for every element count, not up to a bound.
3. **Given** a kernel whose loop lives in a callee that would be inlined,
   **When** the leaf carries its own contract and the caller is verified
   against that contract rather than the body, **Then** both levels discharge
   and the caller's own guards are checked rather than assumed.
4. **Given** a precondition that the current implementation does not satisfy,
   **When** the proof runs, **Then** it reports a counterexample identifying
   the specific property and source location rather than silently passing.
5. **Given** an annotated kernel, **When** it is compiled by the project's
   normal build with its standard warning set, **Then** the annotations have no
   effect on generated code and introduce no new warnings.

---

### User Story 2 - Read what is and is not proven (Priority: P2)

**Problem:** A reviewer asking "is this codec safe?" has no artifact to consult.
Coverage claims that omit the cases that could not be discharged are worse than
no claim, because they invite a conclusion the evidence does not support.

**Why this priority**: The proofs have no audience without this. It is P2 only
because it depends on US1 producing something to record.

**Independent Test**: Hand the coverage record to someone who has not run
anything and ask them to name a proven function, an unproven one and the reason
it is unproven. Fully tested if they can do all three from the document alone.

**Acceptance Scenarios**:

1. **Given** the coverage record, **When** a reader looks up any exported
   decode kernel function, **Then** they find either a discharged verdict or a
   stated reason it could not be discharged — never silence.
2. **Given** a recorded passing verdict, **When** the reader runs the command
   recorded beside it, **Then** they reproduce that verdict.
3. **Given** a confirmed defect, **When** it is recorded, **Then** its expected
   verdict is the failure itself, so a regression in the demonstration surfaces
   as a mismatch rather than as a pass.
4. **Given** a finding that is not a defect — an unstated precondition, a
   prose/contract divergence — **When** it is recorded, **Then** it is
   presented under a heading that does not imply a defect was found.
5. **Given** no defects have been found in a codec area, **When** the reader
   consults it, **Then** the record states the sample size rather than implying
   the area is clean.

---

### User Story 3 - Get warned at a violating call site (Priority: P3)

**Problem:** A codec author writing a new call into an annotated kernel gets no
feedback when they violate its documented requirements, because the requirement
is enforced only by a debug assert that may never run.

**Why this priority**: Lowest cost and broadest reach — it needs no model
checker, and every developer building the project benefits passively. P3
because it is a property of annotations US1 produces rather than separate work.

**Independent Test**: Write a call site that violates an annotated kernel's
precondition with a constant-foldable argument, compile with the project's
standard compiler, and observe a diagnostic. No verification toolchain
involved.

**Acceptance Scenarios**:

1. **Given** an annotated kernel function, **When** a caller passes an argument
   that provably violates a precondition and the compiler can fold it, **Then**
   the build emits a diagnostic naming the violated precondition.
2. **Given** the same annotations, **When** the project is built by a compiler
   without the required diagnostic support, **Then** the annotations expand to
   nothing and the build is unaffected.

---

### Edge Cases

- **A loop-bearing callee is inlined into the function under verification.**
  The verification tool aborts rather than reporting a verdict. Decided
  behavior: contract the leaf separately and verify the caller against the
  leaf's contract instead of its body. If the leaf cannot be contracted, the
  function gets a recorded reason row rather than being dropped.
- **A kernel's only implementation path uses vector intrinsics the tool cannot
  model.** Decided behavior: annotate and discharge the scalar leaf, and reach
  the dispatcher by contract replacement. Where no scalar path exists, record a
  reason row naming the intrinsic barrier.
- **A proof exceeds its time budget.** Decided behavior: record a reason row
  naming the budget and the mode attempted. A timeout is a recorded outcome,
  never an absent entry.
- **An annotation causes an existing call site to emit a new compiler
  diagnostic.** Decided behavior: this is a finding and is recorded as one. The
  clause is not weakened to silence the diagnostic, because the diagnostic is
  the capability working.
- **A kernel is reachable only from tests and benchmarks, not from the
  production decode path.** Decided behavior: annotate it, and record its
  reachability alongside the verdict so a reader does not over-credit a proof
  of unreachable code.
- **The formatting gate's tool version differs from the one used locally.**
  Decided behavior: the enforced gate wins. Annotation regions must be verified
  against the version CI pins, not the version on the author's machine.
- **A contract contradicts the prose safety claim in the codec's own format
  specification.** Decided behavior: record the divergence as a finding. Do not
  silently prefer either statement.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001a**: Each exported decode kernel function MUST carry preconditions
  describing the extent of every buffer it reads or writes.
- **FR-001b**: Each exported decode kernel function MUST carry preconditions
  describing the admissible range of every width and count parameter.
- **FR-002**: Each exported decode kernel function that writes memory MUST
  carry a frame condition bounding what it may modify.
- **FR-003a**: Value invariants currently guarded only by debug-build
  assertions MUST be expressible as preconditions.
- **FR-003b**: When such an invariant is promoted to a precondition, the
  existing assertion MUST be retained unchanged, so debug-build behavior is
  preserved.
- **FR-004**: The verification workflow MUST construct its entry point from a
  function's own contract for any function whose pointer arguments do not
  alias, without a hand-written entry point existing for that function.
- **FR-005a**: The verification workflow MUST support verifying a caller
  against a callee's contract rather than the callee's body.
- **FR-005b**: When a callee is replaced by its contract, the workflow MUST
  check that callee's preconditions at the call site.
- **FR-006**: Loops within a verified function MUST be discharged by induction
  from a stated invariant rather than unwound to a fixed bound.
- **FR-007**: The coverage record MUST contain an entry for every exported
  function of every decode kernel, stating either a discharged verdict or the
  reason it could not be discharged.
- **FR-008**: Each recorded verdict MUST be accompanied by a self-contained
  command that reproduces it.
- **FR-009a**: The recorded suite MUST store an expected verdict for every
  entry.
- **FR-009b**: The recorded suite MUST report any mismatch between an entry's
  expected and actual verdict as a failure, including where the expected
  verdict is itself a failure.
- **FR-010**: The coverage record MUST separate confirmed defects from
  observations that are not defects, under headings that do not conflate them.
- **FR-011**: Where no defect has been found in an area, the coverage record
  MUST state the size of the sample examined rather than asserting the area is
  clean.
- **FR-012a**: Annotations MUST have no effect on generated code.
- **FR-012b**: Annotations MUST introduce no new diagnostics in the project's
  existing builds under their standard warning configuration.
- **FR-013**: Annotations MUST cause a diagnostic at any call site where a
  compiler with the necessary support can prove a precondition violated.
- **FR-014**: Annotated source MUST satisfy the repository's enforced
  formatting gate as that gate is configured in continuous integration.
- **FR-015**: Confirmed defects MUST be reported without altering the behavior
  of the codec in which they were found.

### Key Entities

- **Contract clause**: A statement attached to a function or loop expressing a
  precondition, a frame condition, a postcondition, or a loop invariant.
  Carries a single obligation and is independently checkable.
- **Coverage entry**: One row per exported kernel function, recording the
  verification mode used, the verdict obtained, what the verdict establishes,
  and a reproduction command. An entry always exists; only its content varies.
- **Expected verdict**: The outcome an entry is recorded as producing. A
  mismatch against the actual outcome is a failure regardless of direction,
  which is what keeps a demonstrated defect from silently disappearing.
- **Finding**: An observation produced by the verification effort, classified
  as either a confirmed defect in the codec or a non-defect observation such as
  an unstated precondition or a divergence between a contract and the codec's
  prose specification.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Every exported function across all 31 decode kernel source files
  has a coverage entry — no function is absent from the record.
- **SC-002**: A reviewer who has run nothing can determine, for any decode
  kernel function, whether it is proven and if not why, using the coverage
  record alone.
- **SC-003**: Every recorded passing verdict is reproduced by running the
  single command recorded beside it.
- **SC-004**: Every confirmed defect has a reproduction command, and the suite
  fails if that defect stops reproducing.
- **SC-005**: The project's existing builds produce no new diagnostics as a
  result of the annotations, and the formatting gate passes at the version
  continuous integration pins.
- **SC-006**: No coverage claim in the record overstates its evidence — every
  "none found" statement is accompanied by the sample size it rests on.

## Assumptions

- Decode kernels are the scope. Encode kernels and the 34 decode bindings are
  out of scope for this spec; the bindings are named as the natural successor
  because they are where wire bytes become sizes, and they require modelling
  the framework handle types that kernels do not use.
- No decode kernel takes a framework handle. This was measured, holds today,
  and is the precondition for the harness-free constraint. A future kernel that
  breaks it would need a different approach.
- The verification toolchain is not present in continuous integration images
  and is not expected to be. This is why the capability is delivered as an
  on-demand artifact, consistent with the repository's existing non-blocking
  static-analysis precedent.
- Existing fuzzing and sanitizer coverage of decode paths remains in place.
  This capability is additive: it establishes properties over all inputs where
  those establish properties over sampled inputs.
- Debug-build assertion behavior must not change. Value invariants are promoted
  to preconditions alongside their assertions, never in place of them.
- The formatting gate runs a newer tool version than the one that was on the
  author's PATH during prototyping. The pinned version is now available
  locally and the existing annotations verify clean against it, but every
  subsequent annotation must be checked against the pinned version rather than
  whichever version happens to be first on PATH.
- The annotation vocabulary header lives outside the installed public header
  set. Any annotated header that becomes publicly installed would need that
  dependency resolved first.

## Design Decisions

*Full analysis: [exploration.md](exploration.md)*

- **Coverage target**: the 31 decode kernel source files — they are
  simultaneously the highest-risk layer and the only one where entry points can
  be derived from contracts without harnesses.
- **Acceptance bar**: a discharged proof or a recorded reason — a coverage
  number inflated by omitting hard cases is worse than a smaller honest one.
- **Consumer and cadence**: on-demand audit artifact — gating merges on a
  toolchain absent from CI images buys flakiness before it buys safety.
- **Assert promotion**: promote to precondition and keep the assertion — purely
  additive, so debug behavior is preserved and nothing is deleted.
- **On finding a defect**: report with a reproduction, do not patch — finding
  and fixing are different decisions with different reviewers.
- **Scope**: all three user stories retained — the call-site diagnostics cost
  roughly two requirements and already work, so deferring them would understate
  the capability.

## Premise Validation *(mandatory)*

**Verdict:** proceed — roughly 300 assert-guarded invariants across 31
attacker-reachable decode kernels have no release-build effect, with no
documented process establishing safety over all inputs and one confirmed
undefined-behavior finding already produced from the first sample.

*Full analysis: [exploration.md](exploration.md)*

## Testing Strategy

**Test Tiers**: unit

**Rationale**: The behavior under test is whether a stated property is
discharged for a given function, which is a per-function determination with no
cross-component interaction to exercise. Each entry is independently checkable
and independently meaningful, and the recorded-verdict comparison is itself the
assertion.

## Input Data

| Reference | What It Provides |
|-----------|-----------------|
| `CONTRACTS.md` | Existing coverage record, legend, tooling floor, recorded gotchas, and the successor targets this spec extends [test input] |
| `proofs/run.sh` | Existing recorded suite with four passing entries; the expected-verdict mechanism [test input] |
| `src/openzl/shared/c_contracts.h` | The annotation vocabulary and its three lowering targets |
| `src/openzl/codecs/*/decode_*kernel*.c` | The 31 files in scope |
| `src/openzl/codecs/*/spec.md` | ~20 prose format specifications; the source of prose/contract divergence findings |
| `.github/workflows/dev-ci.yml` | The formatting gate's pinned tool version and the existing sanitizer configuration |
| `.github/workflows/weekly-static-analysis.yml` | Precedent for non-blocking analysis cadence |
| `tests/zstrong/fuzz_decompress.cpp` | The incumbent sampled-input mechanism this capability complements |
