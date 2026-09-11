# Exploration Record: Codec Contract Verification

## Design Decisions — Full Analysis

Five questions were explored interactively. Each is recorded with the
alternatives considered and why the chosen option won.

### D1 — Coverage target

| Option | Considered | Outcome |
|---|---|---|
| **Decode kernels only** (31 files, 6672 LOC) | The untrusted-input surface, and the only layer where CBMC can build every argument from the contract without a hand-written harness | **CHOSEN** |
| Decode kernels + decode bindings (65 files) | Closes the chain from wire bytes to kernel arguments, but every binding needs stubs for `ZL_Decoder` / `ZL_Input` / `ZL_Output` — a categorically harder kind of work | Rejected for this spec; recorded as Out of Scope follow-up |
| All codec kernels, encode + decode (65 files) | Encode kernels see trusted input, so the security argument is much weaker; round-trip pairing is a correctness argument, not a safety one | Rejected |
| Risk-prioritized subset | Time-boxed rather than exhaustive; would leave coverage permanently ambiguous | Rejected |

**Rationale**: the decode kernels are simultaneously the highest-risk layer and
the lowest-friction one. A measurement taken during exploration established the
decisive fact: **zero** of the 31 decode kernels take a framework handle, so
`contract_fresh` can construct every argument and CBMC generates the entry point
from the contract itself. This is what makes the "no harness" constraint
achievable at all.

### D2 — Acceptance bar per kernel

| Option | Considered | Outcome |
|---|---|---|
| **Green proof, or a recorded reason** | A kernel is covered when every exported function either proves PASS or carries a row naming why it cannot (SIMD path, aliasing, solver timeout) | **CHOSEN** |
| Green proof only | Produces a cleaner headline number by silently dropping the hardest cases — exactly the cases most worth knowing about | Rejected |
| Annotated is enough | Fastest coverage growth and clang still warns at call sites, but proves nothing; would make the coverage figure misleading | Rejected |

**Rationale**: the value of the artifact is that a reader can trust it. A suite
whose coverage number is inflated by omission is worse than a smaller honest
one. This directly echoes a correction made earlier in the session, where a
table headed "Undefined behavior discovered" containing non-UB rows was split
apart specifically because it invited a wrong conclusion.

### D3 — Consumer and cadence

| Option | Considered | Outcome |
|---|---|---|
| **On-demand audit artifact** | `proofs/run.sh` plus `CONTRACTS.md`, run by hand. No merge gate | **CHOSEN** |
| CI gate on every change | Strongest anti-rot guarantee, but needs CBMC 6+ in the CI image and a runtime budget growing with every kernel; buys flakiness before it buys safety | Rejected |
| Weekly CI, non-blocking | Catches rot within a week without putting CBMC on the critical path | Rejected for now; noted as a natural later step |
| Clang warnings gate, proofs on demand | Cheapest continuous signal, weakest guarantee | Partially subsumed — the clang warnings arrive anyway via US3 |

**Rationale**: CBMC 6.11 is a local build at
`/data/users/cssmith/git/cbmc/build/bin`, not something CI images carry. Gating
merges on a toolchain that is not reproducibly present in CI produces spurious
failures, which trains people to bypass the gate.

### D4 — Promotion of release-inert asserts

| Option | Considered | Outcome |
|---|---|---|
| **Promote to `contract_pre`, keep the assert** | Assert keeps working in debug, clause gets proven for all inputs, clang warns at foldable call sites, nothing is deleted so no behavior changes | **CHOSEN** |
| Promote and replace | Less duplication, but loses the debug-build runtime check for anything the proof does not yet cover | Rejected |
| Annotate signatures only (extents and widths) | Much smaller change, but skips exactly the class of invariant that produced the one confirmed finding so far | Rejected |

**Rationale**: `ZL_ASSERT(P)` under `NDEBUG` expands to `(0 && (P))` — the
predicate is never evaluated and nothing aborts. Verified during exploration by
preprocessing. There are roughly 300 such assertions across the 31 decode
kernels, and in release builds every one is inert. Keeping the assert alongside
the clause means the change is purely additive.

### D5 — Deliverable when a proof surfaces a defect

| Option | Considered | Outcome |
|---|---|---|
| **Report only** | Row in `CONTRACTS.md` with a copy-pastable repro; suite records FAIL as the expected verdict so the demonstration cannot silently stop working | **CHOSEN** |
| Report and fix | Stronger end state, but couples verification scope to codec-behavior changes needing codec-owner review | Rejected |
| Report, fix memory-safety only | Splits the difference but requires a severity judgement per finding, which is the codec owner's call | Rejected |

**Rationale**: finding and fixing are different decisions with different
reviewers. Recording FAIL as the *expected* verdict is the mechanism that keeps
a known defect from quietly disappearing — a regression in the demonstration
shows up as a mismatch rather than a pass.

### Scope checkpoint

Three user stories were identified. The user elected to keep all three.

| Story | Coupling | Rough FRs |
|---|---|---|
| US1 — annotate and prove a kernel | Tightly coupled to US2 | ~6 |
| US2 — read what is and is not proven | Tightly coupled to US1 | ~4 |
| US3 — warned at a violating call site | Independently deferrable | ~2 |

US3 was offered for deferral and retained on the grounds that it costs ~2 FRs,
requires no proof infrastructure, and already works in the committed code — the
same clauses drive clang `diagnose_if` with zero CBMC involvement. Dropping it
would have understated the capability.

## Design Context for Planning

*Implementation-direction insights captured during specification exploration.
These are hints for /speckit-plan, not spec-level requirements. Plan may use,
challenge, or override them after its own research phase.*

Substantial implementation context already exists, because a working prototype
was built before this spec was written. The following are hints, not
requirements:

- **Toolchain is CBMC 6.11.0**, built locally at
  `/data/users/cssmith/git/cbmc/build/bin` per `.llms/rules/local-tools.md`.
  CBMC 5.x lacks the contracts support required; Ubuntu 24.04 ships 5.95.
- **Annotation vocabulary is c-contracts**, vendored from
  `https://github.com/cs01/c-contracts` and carried in-tree. The same header
  lowers to `__CPROVER_*` under CBMC, `diagnose_if` under stock clang, and
  nothing elsewhere — which is what makes US3 free.
- **A known CBMC interaction constrains the annotation shape**:
  `--apply-loop-contracts` leaves a synthetic `__in_loop_havoc_block__` bool in
  the function, and if a loop-bearing callee is then *inlined* under
  `--enforce-contract`, the enforce pass cannot size it and aborts with an
  invariant violation. `--dfcc <fn> --enforce-contract <fn>` is not a way around
  it (`pair.first != harness_id`). The working shape is to contract the leaf and
  replace the call in the caller.
- **clang-format 19 does not handle trailing contract clauses** even with
  `AttributeMacros` configured — it collapses them onto one line. Annotated
  regions need explicit fencing to satisfy the repo's format gate.
- **`[EXPLORATION-FLAGGED]`**: D3 (consumer and cadence) and D4 (promote vs.
  replace) both carry some delivery-mechanism character. They were asked because
  each changes an observable outcome — whether a merge can be blocked, and
  whether debug-build behavior changes — but the plan phase should revisit the
  *mechanism* of each rather than treating the answers as settled implementation.

## Complexity Assessment

**Classification**: standard
**Signal 1 — User journeys**: 3 (standard)
**Signal 2 — Cross-cutting scope**: multi-component — 31 kernel files across
many codec directories, plus new top-level tooling and a repo-wide
`.clang-format` change (standard)
**Tiebreaker**: not invoked — both signals agreed
**User override**: none

## Premise Validation — Full Analysis

### 1. Existing solutions check

Document evidence only; the codebase scan ran in parallel and its findings are
folded into the spec's requirements rather than this verdict.

- No root `CLAUDE.md`.
- `.specify/memory/constitution.md` carries the
  `speckit:constitution:placeholder` sentinel — unconfigured, skipped.
- No prior `specs/` directory.
- `doc/` contains only `assets/`, `mkdocs/` and a Doxyfile; no verification,
  safety, or threat-model documentation.
- 20 `spec.md` files exist under `src/openzl/codecs/*/`. These are wire-format
  specifications, not safety specifications.

**Conclusion**: no documented existing process achieves this goal.

### 2. Current workflow

Codec kernel correctness is established today by:

- Unit tests under `tests/unittest/transforms/`
- Round-trip tests under `tests/round_trip/`
- Debug-build `ZL_ASSERT` on kernel parameters

None of these establishes a property over *all* inputs. The assert path is the
de facto mechanism for stating a kernel's preconditions, and it has no runtime
effect in release builds.

### 3. Friction assessment

Quantified, not qualitative:

- ~300 assert-guarded invariants across 31 decode kernels, each inert under
  `NDEBUG`, each an unverified assumption on attacker-reachable code.
- Verified by preprocessing: `ZL_ASSERT(P)` under `NDEBUG` becomes `(0 && (P))`.
- The first handful of kernels annotated already produced one confirmed
  finding: in `ZS_divideByDecode16`, C integer promotion makes the guarded
  multiply `(signed int) * (signed int)`, so violating the release-inert
  `USHRT_MAX` guard is signed overflow — undefined behavior, not the benign
  unsigned wrap the guard's form implies.

This is genuine friction with a demonstrated hit rate, not convenience.

### 4. Disproportionality assessment (coarse filter)

Not disproportionate. The infrastructure cost is already sunk — `prove.sh`,
`c_contracts.h` and `proofs/run.sh` are committed and working. Marginal cost per
kernel is writing clauses plus a proof run measured in seconds to tens of
seconds. The coarse filter does not fire.

### Verdict

**proceed** — genuine, quantified friction on attacker-reachable code, with no
existing documented solution and a demonstrated finding rate in the first
sample.
