# Adversarial Review Findings

**Feature**: Codec Contract Verification
**Attempt**: secondary-20260911T212711Z-1312
**Review Type**: Secondary
**Date**: 2026-09-11

| Reviewer | Status | Findings |
|---|---|---|
| Correctness Reviewer | delivered | 11 |
| Coverage Reviewer | delivered | 11 |
| Risk Reviewer | delivered | 10 |

**Agents Completed**: 3/3

---

### MUST-ADDRESS (9)

#### CR-001: `mode = harness` is a first-class manifest value with no defined authoring path, invocation, or CLI surface, and collides with the enumerator's set-equality rule
**Agent**: CR, CV · **Type**: Design gap
**Disposition**: [PRESENTED]

- `harness` is in the `mode` vocabulary and Step 7 rule 2 assigns it to any function whose pointer arguments alias, but nothing says how a harness row becomes a command: `prove.sh`'s `-H` form takes a hand-written entry point as its first argument, not the kernel function, while data-model.md requires `function` to be the enumerated kernel symbol — so the row's `function` cannot legally be the harness entry point.
- No step authors a harness, no file-plan location exists for one (`### Source Code` names a path for every other new artifact but not this one), and `contracts/cli.md` never mentions `-H` or how a `harness` row's `flags` column should be populated.
- As written, an implementer would put `-H` in `flags` and dispatch `prove.sh <kernelFn> <kernel.c> -H`, which runs CBMC on the kernel with unconstrained nondeterministic arguments and skips `prove.sh`'s own vacuity check — recording `PASS` while proving nothing. Step 7 also allows silently falling back to `mode = none, reason_class = alias` "if no harness is written," meaning the whole mode can go unexercised without anyone noticing.

> **Evidence**: plan.md Step 7 rule 2 and its Verification; data-model.md Coverage entry + validation rules; contracts/cli.md `--all`; `prove.sh` `-H` branch and its `[ "$HARNESS" = 0 ] || exit 0` vacuity guard; CONTRACTS.md Legend.

**Recommendation**: Either (a) drop `harness` from the mode vocabulary and make Step 7 rule 2 unconditionally produce `mode = none, reason_class = alias`; or (b) keep it and fully specify it — add a `proofs/harness/` location to the file plan, add `harness_fn`/`harness_source` columns or redefine `source`, exempt harness rows from the enumerator's set-equality rule, require `-H` in `flags` as a validation rule, name the harness-authoring step in Phase 4's inner loop, and require a non-`-H` companion check so a harness row cannot record a vacuous `PASS`.

**Digest**: `mode=harness` has no authoring step, file location, `-H` wiring, or vacuity guard — define it fully or drop it.

- [ ] Resolved

---

#### CR-002: The FR-014 gate's file-discovery rule silently skips every `.c` file that carries loop contracts
**Agent**: CR · **Type**: Inconsistency
**Disposition**: [PRESENTED]

- `scripts/check_contract_format.sh` with no arguments is defined as checking "every annotated file (those including `openzl/shared/c_contracts.h`)". Measured on this branch, that rule matches exactly five files, four of which are headers and one of which is the vocabulary header itself — none of the four already-annotated `.c` files match, because they reach the vocabulary only transitively through their own header.
- Step 1's verification ("exits 0 over the eight already-annotated files") is therefore not reachable as written, and Phase 4's per-step gate would exit 0 while checking nothing in the `.c` bodies — exactly where `contract_invariant`/`contract_decreases` sit inside `// clang-format off` fences that clang-format is already known to mishandle.

> **Evidence**: contracts/cli.md `scripts/check_contract_format.sh` section; plan.md Step 1 Verification and the Phase 4 preamble's per-step checks; `grep -rl c_contracts.h src/` returns 5 paths, 4 of them headers.

**Recommendation**: Redefine the no-argument discovery rule as "every file matching `contract_[a-z_]*(` under `src/openzl/codecs/` and `src/openzl/shared/`, minus `.clang-format-ignore`," which catches both headers and bodies without depending on include topology, and state the expected match count (8 today) in Step 1's verification.

**Digest**: format-gate discovery rule matches 4 headers, not the 4 `.c` bodies where the risky clauses live — redefine it.

- [ ] Resolved

---

#### CR-003: Header-defined `ZL_INLINE`/`ZL_FORCE_INLINE` functions are enumerated as coverage rows but are not "exported functions" and have no defined `source`
**Agent**: CR · **Type**: Design gap
**Disposition**: [PRESENTED]

- D6 rule 1 enumerates every function *declared* in an in-scope header, including internal-linkage inline functions defined in the header itself (14 in `decode_rolz_kernel.h`, 5 in `common_pivco_kernel.h`, plus others) — these are internal helpers, not exported symbols, so counting them inflates the SC-001 denominator by roughly 21 rows against FR-007/SC-001's "every exported function" wording.
- data-model.md defines `source` as "the `.c` or `.h` holding the definition," so these rows get a bare header; whether `prove.sh`'s `cc -E` + `goto-cc` pipeline yields a goto program containing an internal-linkage inline function from a header alone is undemonstrated, and the plan's four existing exemplars are all externally-linked `.c`-defined functions.

> **Evidence**: research.md D6 rule 1; data-model.md Coverage entry `source` field; plan.md Step 2 Verification (requires the conversion and pivco symbols to be enumerated); `decode_rolz_kernel.h` lines 60, 90, 106, 128, 152.

**Recommendation**: Add a linkage-filter clause to D6 — either exclude `ZL_INLINE`/`ZL_FORCE_INLINE`/`static` declarations (recording them as an auditable excluded set with a count), or include them and set `source` to a `.c` in the same directory that includes the header, demonstrated end-to-end before Step 11 depends on it. Add one inline-defined function to Step 2's D8 regression test either way.

**Digest**: header-only inline functions get coverage rows with no real `source`/linkage rule — add the filter clause to D6.

- [ ] Resolved

---

#### CV-001: FR-001a/FR-001b/FR-002 have no verification step, and reason rows are planned to carry no clauses at all
**Agent**: CV · **Type**: Spec gap
**Disposition**: [PRESENTED]

- FR-001a, FR-001b and FR-002 are unconditional annotation requirements, but no tool or plan step checks clause *presence* — `enumerate.py` compares only the manifest row set against the enumerated surface, and Step 16's final-acceptance table has no row for FR-001a/b, FR-002 or FR-003a.
- Step 7 classifies terminal-reason rows "without writing clauses," and Phase 4's annotation loop only runs over rows entering proof — so a `framework`-class or `simd`-class function ends the feature with zero annotations, silently substituting "provability" for "annotation" without the plan ever saying so. This also shrinks FR-013/US3: a reason row is also a call site that gets no compiler feedback, unstated as a consequence.

> **Evidence**: spec.md FR-001a/FR-001b/FR-002 (unconditional); plan.md Step 7, Phase 4 preamble, Step 16 final-acceptance table; data-model.md Coverage entry (no clause-presence column or rule).

**Recommendation**: Require clauses on every in-scope function regardless of provability — add a `clauses` column to `proofs/cases.tsv`, have `enumerate.py` detect `contract_pre`/`contract_assigns` on the declaration, and add a Step 16 acceptance row for it — or, as a cheaper alternative, narrow FR-001a/b and FR-002 in the spec to "every function with `mode != none`" and record the un-annotated count in the `scope` region.

**Digest**: FR-001a/b/FR-002 (clause presence) are never verified, and terminal-reason rows get zero clauses — pick and state a policy.

- [ ] Resolved

---

#### CV-002: Every new file the plan adds lands on an enforced CI format gate the plan never checks
**Agent**: CV · **Type**: Design gap
**Disposition**: [PRESENTED]

- `proofs/enumerate.py` and `proofs/render.py` are Python, and CI's `test-python-format` job runs `ruff==0.15.0` via `make check-python-format` over everything `scripts/check_python_format.sh` doesn't prune — `proofs/` is not pruned, so both new scripts are gated by `ruff format --check` at a pinned version the plan never mentions.
- `proofs/callsite/*.c` (Step 15) is a C file under the tree-wide clang-format 21 `check-path: '.'` gate, and it is deliberately a file that fails to compile cleanly — easy to forget to format. Neither new script gets a `Makefile` target, though CI invokes format checks by target, not by path, so nothing discovers `scripts/check_contract_format.sh` either.

> **Evidence**: `.github/workflows/dev-ci.yml` `test-python-format`/`test-quality` jobs; `scripts/check_python_format.sh` prune list; `Makefile:217-223`; plan.md Step 2/5/15 verification blocks; research.md "Verification commands" table (no ruff row).

**Recommendation**: Add `make check-python-format` to Steps 2 and 5's per-step verification and to Step 16's acceptance table; add a clang-format check of `proofs/callsite/` to Step 15; register a `check-contract-format` Makefile target beside `check-python-format`.

**Digest**: new `.py`/`.c` files hit CI's ruff/clang-format gates unchecked by any plan step — wire them into verification.

- [ ] Resolved

---

#### CV-003: FR-012b/SC-005 are verified against two local compilers, but the gate is an eight-compiler `-Werror` matrix
**Agent**: CV · **Type**: Test gap
**Disposition**: [PRESENTED]

- FR-012b requires no new diagnostics "in the project's existing builds under their standard warning configuration." The plan discharges this with `make lib` under `cc` and `clang` locally, repeated at every Phase 4 step and Step 16.
- `dev-ci.yml` actually builds `make all V=1` across gcc-11..14 and clang-15..18, plus a `-Werror`+`NDEBUG` build and two `-std=gnu11 -Werror` builds — under `-Werror` any new diagnostic is a hard failure. `make lib` also skips the test/CLI/tools/benchmark/C++ trees, where call sites of annotated kernels (and their `diagnose_if` evaluation) actually live, and the plan checks only whichever local `clang` happens to be on PATH against a CI matrix spanning clang 15-18.

> **Evidence**: `.github/workflows/dev-ci.yml` `build-compilers`/`build-basic`/`build-standards` matrices; plan.md Phase 4 preamble and Step 16 acceptance table (SC-005 row); `c_contracts.h:38-39` (`__has_attribute(diagnose_if)` guard).

**Recommendation**: Change the SC-005 acceptance row to `make all MOREFLAGS=-Werror` under at least clang-15, clang-18 and one GCC from the CI matrix, keeping the cheap two-compiler `make lib` check only as the per-step smoke test. If older compilers aren't installable locally, record that as a residual risk and add a one-off CI dry run before Step 16 closes.

**Digest**: FR-012b/SC-005 checked with `make lib` on 2 compilers vs. CI's 8-compiler `-Werror` matrix over more trees — raise the bar.

- [ ] Resolved

---

#### RK-001: Step 9 records the `divide_by` finding as a confirmed defect, but the promoted precondition makes the proof pass and the binding already prevents the condition in release
**Agent**: RK · **Type**: Premise
**Disposition**: [PRESENTED]

- Step 9 names the in-tree `divide_by` annotations as the clause-shape exemplar and, in the same bullet, says the `ZS_divideByDecode16` signed-overflow finding "is expected to reproduce" as `expect = FAIL, reason_class = defect`. With the promoted precondition present, CBMC assumes the guarded range and the multiply cannot overflow — the proof passes; `FAIL` only exists with the clause removed, which is an observation (per Step 16's own exemplar), not a defect.
- Worse, the condition is not attacker-reachable: `decode_divide_by_binding.c` validates it in the release build via `ZL_ERR_IF_EQ`/`ZL_ERR_IF_GT` before `ZS_divideByDecode` is ever called. Recording it under a defect heading violates FR-010/SC-006 in the one document whose purpose is not overstating evidence, and undercuts the spec's Premise Validation, which cites this as "one confirmed undefined-behavior finding" while `CONTRACTS.md` itself says "None."

> **Evidence**: plan.md Step 9 (`divide_by` bullet) and Step 16 exemplar; `decode_divide_by_binding.c` lines 34-70; working-tree `decode_divide_by_kernel.h` (`contract_pre(contract_forall(...))`); spec.md Premise Validation vs CONTRACTS.md.

**Recommendation**: Add a classification gate before any row may take `reason_class = defect`: check whether the decode binding establishes the promoted precondition in a release build, record the answer in the row's `note`, and rewrite the Step 9 `divide_by` bullet to the expected outcome — a `PASS` row plus an Observations entry — reserving `expect = FAIL` for a condition no caller establishes.

**Digest**: `divide_by`'s "confirmed defect" is release-unreachable and the promoted clause makes it pass — reclassify as observation, not defect.

- [ ] Resolved

---

#### RK-002: `BUDGET` bounds only the solver race, so `./proofs/run.sh --all` over ~110 functions has no wall-clock bound and the final-acceptance gate can hang indefinitely
**Agent**: RK · **Type**: Existing debt
**Disposition**: [PRESENTED]

- The plan keeps `prove.sh` "UNCHANGED" and `BUDGET` as the only time control, but `prove.sh` reads `TIMEOUT` (from `BUDGET`) in exactly one place — the polling loop waiting on the racing solvers. Preprocessing, `goto-cc`, and `goto-instrument --apply-loop-contracts` (which walks every loop in the program and is explicitly commented as able to "look like a hang") are all unbounded, and the mitigation for the last one (`--drop-unused-functions`) applies only in harness mode, not `enforce`/`enforce-r` — the mode nearly every row in this plan uses.
- The step-5 vacuity check, which runs on every proof that passes (the intended outcome of ~all rows), also has no timeout. `proofs/run.sh` wraps calls with `|| true` and no external `timeout(1)`, so a stuck phase stalls the whole suite with no output and no row — invisible at four entries, expected at ~110 on targets like `common_bitpack_kernel.c` (1392 LOC, 42 loop headers).

> **Evidence**: `prove.sh:174` (TIMEOUT loop), `prove.sh:83-88` (harness-only `--drop-unused-functions`), `prove.sh:229-236` (unbudgeted `--cover location`); plan.md Source Code table (`prove.sh # UNCHANGED`), Step 16 final-acceptance table; research.md D9.

**Recommendation**: Wrap the whole proof invocation in `proofs/run.sh` (not `prove.sh`) as `timeout "$((BUDGET + SLACK))" "$PROVE" ...`, mapping exit 124 to a recorded `TIMEOUT`/`ERROR` outcome so the suite always terminates and always emits a row. Add an explicit bound on the vacuity check, and note in Step 10 that bitpack's 42 loops may need `-r` onto its leaves for the same reason `range_pack` does.

**Digest**: `BUDGET` only bounds the solver race; preprocessing, loop-contract instrumentation and the vacuity check are unbounded — `--all` can hang.

- [ ] Resolved

---

#### RK-007: D6's rule 2 is ambiguous at the point the surface is defined, and its "same codec directory" qualifier drops the bitpack attacker path the rule exists to protect
**Agent**: RK · **Type**: Scope
**Disposition**: [PRESENTED]

- Rule 2's two readings disagree and both contradict something the plan states. At function granularity, `bitpack/`'s only `decode_*` TU references one of five bitpack functions — the same undercount research.md already flagged — failing Step 2's own acceptance test. At header granularity, the whole header (including four encode functions) comes into scope, contradicting the spec's "encode kernels are out of scope" assumption and Step 10's five-function artifact list.
- The "same codec directory" qualifier also drops `DI_bitunpack` (in `bitunpack/`, a directory F5 says produces no rows) calling `ZS_bitpackEncodeBound`/`ZS_bitpackEncode` with an off-the-wire `nbBits` — exactly the two functions `CONTRACTS.md`'s open safety question is about, and exactly what Step 10 promises to answer. D6 was written to stop a naming accident from dropping bitpack; the qualifier reintroduces the same accident one level down.

> **Evidence**: research.md D6 rule 2, F5; plan.md Step 2 Verification, Step 10; `decode_bitpack_binding.c:66`; `decode_bitunpack_binding.c:30,36`; `common_bitpack_kernel.h:24-116`; CONTRACTS.md Open questions row 1; spec.md Assumptions.

**Recommendation**: Restate rule 2 at header granularity, drop the same-directory qualifier — a `common_*kernel*.h` is in scope when any `decode_*` TU anywhere references it, and every function it declares gets a row — and add a carve-out sentence: encode-named functions reached from a decode path are in scope *because* they are decode-reachable, while encode-only functions get a `reach = encode-only` terminal row.

**Digest**: rule 2's granularity is ambiguous and its directory qualifier drops the exact bitpack encode-via-decode path the plan calls its highest-value target.

- [ ] Resolved

---

### SHOULD-CONSIDER (16)

#### CR-005: The `-Wgcc-compat` mitigation in Step 8 does not reduce the suppression span it is meant to reduce
**Agent**: CR · **Type**: Risk
**Disposition**: [PRESENTED]
**Theme Group**: group-B — "Step 8's two exposure guards each cover a narrower surface than the exposure risk they're meant to police"

- The underlying claim checks out — `c_contracts.h` disables `-Wgcc-compat` at file scope with no push/pop by design — but Step 8's mitigation ("last include in the header") does essentially nothing: the pragma fires once per TU at the *first* point the include chain reaches it, near the top of the consuming `.c` file, not the kernel header.
- The consumer set is also wider than the plan's file list: bindings, tests, benchmarks, and (once `common_bitpack_kernel.h` is annotated) `encode_bitpack_binding.c` and beyond all inherit the suppression, none of which appear in the plan's Source Code tree or its "TUs that will include an annotated header" measurement scope.

> **Evidence**: `c_contracts.h` stock-clang target block (inside the `C_CONTRACTS_H` guard); plan.md Step 8 F2 paragraph; research.md F2.

**Recommendation**: Replace the include-placement policy with a decisive measurement: build the whole library under clang with `-Wgcc-compat` added to the warning set and confirm the project-wide count is zero before any annotation lands; re-run at Step 16 rather than per-step. If non-zero, either scope the pragma with push/pop around only the macro definitions, or record the suppression as an accepted consumer-visible effect with the affected TU list.

**Digest**: Step 8's "last include" fix doesn't shrink the `-Wgcc-compat` suppression span, and the affected-TU list is wider than tracked — measure instead.

- [ ] Resolved

---

#### CR-006: The public-header exposure guard checks direct includes only, and the installed header set is three directories, not two
**Agent**: CR · **Type**: Design gap
**Disposition**: [PRESENTED]
**Theme Group**: group-B — "Step 8's two exposure guards each cover a narrower surface than the exposure risk they're meant to police"

- Step 8's F3 guard is "no file under the installed include directories includes `c_contracts.h`" — but the realistic exposure path is transitive (a future public header including an annotated *kernel* header, not `c_contracts.h` directly), which is already an established pattern (`zl_public_nodes.h` includes 39 codec headers). A direct-include grep exits 0 against exactly the arrangement that would break the install.
- `CMakeLists.txt` also installs three directories, not the two research.md and Step 8 state — the generated-headers directory is low-risk but the guard's list should be derived from the `install(DIRECTORY ...)` rules rather than hardcoded.

> **Evidence**: plan.md Step 8 F3 paragraph and Verification; research.md F3; `CMakeLists.txt` lines 293-307; `zl_public_nodes.h` lines 14-52.

**Recommendation**: Implement the guard as a transitive closure over `#include` edges from each installed header, deriving the directory list from `install(DIRECTORY ...)` lines rather than hardcoding two paths. Extend Step 8's verification to the transitive case (temporarily include an annotated codec header from a file under `include/openzl`).

**Digest**: exposure guard checks direct includes only and names 2 of 3 installed directories — make it transitive and derive the directory list.

- [ ] Resolved

---

#### CR-007: `expect = ERROR` is unreachable under the data model's own validation rules, and the vacuity failure has no manifest representation
**Agent**: CR · **Type**: Inconsistency
**Disposition**: [PRESENTED]
**Theme Group**: group-C — "The manifest's mode/expect/reason_class schema has no slot for certain real outcomes — ERROR, a vacuous pass, and timeout — leaving them unconstructible or stuck with no path back"

- data-model.md admits `ERROR` as an `expect` value, but its validation rules (`mode = none ⟺ expect = -`, `mode != none requires reason_class ∈ {-, defect}`) make an `ERROR` row unconstructible — the real producers (`prove.sh` exit codes 2-5, mapped by `proofs/run.sh`'s ERROR branch) are neither "proved" nor "expected FAIL."
- Exit 5 — `prove.sh`'s own "the one failure that looks exactly like success and stays that way forever" — has no representation anywhere in the manifest or reason vocabulary; a row could record `PASS` and render into the `coverage` region as a discharged verdict despite never being vacuity-checked, which is exactly what SC-006 exists to prevent.

> **Evidence**: data-model.md Coverage entry validation rules and Expected-verdict matrix; reason-class rows `inline-loop`/`timeout`; `prove.sh` exit codes 2-5 and its step-5 vacuity comment; `proofs/run.sh` ERROR branch.

**Recommendation**: Relax the validation rule to `mode != none requires reason_class ∈ {-, defect, tool-error}` and add `tool-error` to the closed vocabulary; state in Step 3/9-13's verification that a `PASS` is only recordable when `prove.sh` exits 0, and add a line to `contracts/coverage-record.md` that the `coverage` region must not generate "what it establishes" text for a row that wasn't vacuity-checked.

**Digest**: `expect = ERROR` can't be constructed under the model's own rules, and a vacuous-pass failure mode has no manifest slot at all.

- [ ] Resolved

---

#### CV-009: A timed-out proof becomes a row with no command and no way back; the timeout edge case is recorded but not re-attemptable
**Agent**: CV · **Type**: Design gap
**Disposition**: [PRESENTED]
**Theme Group**: group-C — "The manifest's mode/expect/reason_class schema has no slot for certain real outcomes — ERROR, a vacuous pass, and timeout — leaving them unconstructible or stuck with no path back"

- The spec's timeout edge case requires recording "the budget and the mode attempted," but the validation rules force `mode = none` on any reason row including `timeout` — so the row contradicts its own note (which claims a mode was attempted) and `render.py`'s `reasons` region renders `mode = none`.
- `contracts/coverage-record.md` scopes reproduction commands to rows with `expect != -`, so a timeout row carries no command — a reader cannot re-attempt it, raise `BUDGET`, and retry. This is the one reason class that is not terminal in substance, yet it's recorded in the one form that cannot be re-run; the state-machine diagram draws an arrow into "terminal reason" labelled `timeout` with no arrow out, and Step 7's classification questions have no timeout branch at all.

> **Evidence**: spec.md Edge Cases (timeout); data-model.md validation rules, reason-class table, state-transition diagram; contracts/coverage-record.md region scoping; plan.md Step 7.

**Recommendation**: Let a timeout row keep its attempted `mode`/`flags`/command, add `expect = TIMEOUT` to the verdict vocabulary, relax `mode = none ⟺ expect = -` to apply only to `{simd, alias, inline-loop, framework}`, and have `render.py` emit timeout rows into the `coverage` region tiered `slow` so `--all` doesn't re-pay the full budget every run by default.

**Digest**: a `timeout` row is forced to `mode=none` (contradicting its own note) and carries no reproducible command — give it a real verdict and a retry path.

- [ ] Resolved

---

#### CV-006: Step 5 moves only the "Proven correct" table into the generated regions, leaving three hand-written tables that the generator now duplicates
**Agent**: CV · **Type**: Design gap
**Disposition**: [ESCALATED: reconciliation conflict]
**Theme Group**: group-A — "Step 16 / CONTRACTS.md Scope-table handling has contradictory ownership across the plan's record-generation steps"

- `contracts/coverage-record.md` requires five generated regions, but Step 5 assigns only `coverage`. `CONTRACTS.md`'s `## TODO` table is exactly what the `reasons` region generates, yet no step deletes it — it survives as a hand-written list the manifest also renders, the precise "two lists that can disagree" problem the feature exists to eliminate (and its out-of-scope decode-bindings row can't simply be absorbed).
- `## Undefined behavior discovered`'s hand-written "**None.**" paragraph and the `defects` region both claim to own the same heading, with no statement of which survives. `## Scope`'s table is explicitly left as hand-written prose by Step 5, while Step 16 says to update it by hand and `coverage-record.md` assigns it a generated `scope` region — a direct three-way contradiction that re-opens the drift SC-001 exists to close.

> **Evidence**: plan.md Step 5 ("Move the existing 'Proven correct' table... leave the Scope... prose outside them"); `CONTRACTS.md:9,55,86`; contracts/coverage-record.md "Required generated regions"; plan.md Step 16.

**Recommendation**: Extend Step 5 to place all four existing tables into their matching regions (`Proven correct`→`coverage`, `TODO`→`reasons` with its out-of-scope row relocated to hand-authored Scope prose, UB table body→`defects`, Scope counts→`scope`), then delete Step 16's hand-update instruction and replace it with "regenerate."

**Digest**: Step 5 wires up only 1 of 4 tables the record contract requires as generated regions; the other 3 stay hand-written and now duplicate the generator.

- [ ] Resolved

---

#### CR-008: F5's justification for excluding `src/openzl/codecs/common/` is factually wrong — it holds decode-reachable kernel code, not bindings or library wrappers
**Agent**: CR · **Type**: Premise
**Disposition**: [ESCALATED: reconciliation conflict]
**Theme Group**: group-A — "Step 16 / CONTRACTS.md Scope-table handling has contradictory ownership across the plan's record-generation steps"

- research.md F5 states seven directories including `common` "have no decode kernel header... binding-only or wrap an external library." Six check out; `common/` does not — it holds bitstream readers and fast decode tables that huffman/rolz/lz decoders run on, consuming attacker-chosen bytes directly (`decode_rolz_kernel.h` takes `ZS_window const*`). Excluding it may still be the right call (it's a shared directory, not a per-codec one, and D6 rule 2 is directory-scoped), but that's a different reason than the one recorded.
- Step 16 repeats the same wrong reasoning when it writes the record's Scope statement "so their absence is deliberate rather than unexplained" — publishing an inaccurate justification in the one artifact whose value depends on being trustworthy.

> **Evidence**: research.md F5; plan.md Step 2 Verification (repeats the seven-directory list), Step 16; `ls src/openzl/codecs/common/`; `decode_rolz_kernel.h:163`.

**Recommendation**: Split F5 into two exclusions with accurate reasons — (a) the six binding-only/wrapper directories, (b) `common/` as a shared helper layer deliberately deferred because it isn't per-codec — and name (b) alongside the decode bindings as a successor-scope gap rather than in the "no decode kernel" bucket.

**Digest**: F5 says `common/` has "no decode kernel" — it does; the real exclusion reason is that it's shared, not per-codec. Correct the stated reason.

- [ ] Resolved

---

#### CV-007: FR-012a ("no effect on generated code") is never verified; Step 15 mislabels a diagnostic-absence check as covering it
**Agent**: CV · **Type**: Test gap
**Disposition**: [PRESENTED]
**Theme Group**: group-D — "Step 16's final acceptance table is credited with verifying FR-012a and FR-003a, neither of which any step actually measures"

- FR-012a (codegen) and FR-012b (diagnostics) are separate requirements. Step 15's verification — "exits 0 under gcc with no diagnostic (FR-012a/FR-012b)" — tests only diagnostic absence; a silent gcc is expected regardless of whether generated code changed, and no step anywhere compares object code before/after annotation. Step 16's acceptance table has no FR-012a row.
- FR-012a is also the requirement that underwrites the spec Summary's "annotations are inert, therefore safe to land broadly" framing, so leaving the project's strongest inertness claim unmeasured is a costly gap for a cheap check.

> **Evidence**: spec.md FR-012a vs FR-012b; plan.md Step 15 Verification, Step 16 acceptance table; data-model.md Contract-clause Lowering row; `c_contracts.h:38-39`.

**Recommendation**: Add an acceptance row comparing object-code (or `objdump -d`) of the annotated TUs at the pre-feature and final commits under identical flags, under both `cc` and `clang`; remove the FR-012a citation from Step 15, which doesn't test it.

**Digest**: FR-012a (codegen-identity) is cited as tested in Step 15 but only diagnostic-absence is checked — add a real object-code comparison.

- [ ] Resolved

---

#### CV-005: FR-003a's ~300 assert-guarded invariants have no enumeration, no promotion coverage measure, and no verification
**Agent**: CV · **Type**: Test gap
**Disposition**: [PRESENTED]
**Theme Group**: group-D — "Step 16's final acceptance table is credited with verifying FR-012a and FR-003a, neither of which any step actually measures"

- The spec's premise cites a counted population ("roughly 300 assert-guarded invariants"), and FR-003a makes them a requirement, but the plan tracks only the function denominator — no step enumerates asserts, so nobody can say at the end how many of the ~300 were promoted, judged non-promotable, or never looked at. FR-003a is unfalsifiable as planned.
- FR-003b ("leave every assert untouched") is stated in Phase 4's inner loop but has no mechanical check — a one-line `git diff` guard would make it verifiable for free and is absent.

> **Evidence**: spec.md FR-003a/FR-003b, Premise Validation; `CONTRACTS.md:71`; plan.md Phase 4 preamble, Step 16 acceptance table; data-model.md Coverage entry (no assert-related column).

**Recommendation**: Add a per-row `note` convention recording how many of a proved function's asserts were promoted (so the `samples` region can sum it), and an acceptance row asserting no `ZL_ASSERT` line changed outside reformatting, for FR-003b.

**Digest**: the spec's own counted premise (~300 asserts) has no enumeration or promotion-coverage measure anywhere in the plan.

- [ ] Resolved

---

#### CR-004: The spec's "no decode kernel takes a framework handle" assumption is narrower than the spec and exploration record claim
**Agent**: CR · **Type**: Inconsistency
**Disposition**: [PRESENTED]

- exploration.md D1 claims "zero of the 31 decode kernels take a framework handle," but `decode_rolz_kernel.h` declares functions taking `ZS_RolzDTable2*`/`ZS_rolzDTable*`/`ZS_window const*` — structs with internal pointers `contract_fresh` cannot construct. Plan Step 7 rule 1 correctly narrows this in practice (introducing the `framework` reason class), but spec.md's Assumptions, exploration.md D1, and CONTRACTS.md's Scope table are never corrected.
- A reader of the spec alone would conclude the harness-free property is universal, when the plan already expects a population where it isn't.

> **Evidence**: spec.md Assumptions bullet 2; exploration.md D1 Rationale; CONTRACTS.md Scope table row 3; plan.md Step 7 rule 1; `decode_rolz_kernel.h` lines 18, 24, 44, 51, 157, 163.

**Recommendation**: Amend the spec's assumption to the measured claim — "no decode kernel takes a `ZL_Decoder`/`ZL_Input`/`ZL_Output` handle" — and add that some kernels take codec-owned structs with internal pointers that `contract_fresh` also cannot construct, recorded as reason rows. Make the same correction in CONTRACTS.md's Scope table at Step 16.

**Digest**: "zero kernels take a framework handle" is false for rolz's table structs — the plan already accounts for it, but the spec/exploration text never gets corrected.

- [ ] Resolved

---

#### CR-009: Nothing owns the data model's validation rules, and Step 6 creates rows that violate one of them
**Agent**: CR · **Type**: Test gap
**Disposition**: [PRESENTED]

- data-model.md states nine validation rules over `proofs/cases.tsv`, but no tool checks any of them — `enumerate.py --check` compares only function *sets*, `render.py` renders/diffs generated regions, and `run.sh` dispatches without validating the row it read. A row that drifts to `mode = enforce, expect = -` is silently dropped from both generated regions while `enumerate.py --check` still exits 0, since the function name is still present — an FR-007 violation the plan's own final acceptance table cannot detect.
- Step 6 explicitly creates rows violating the "reach is always required" rule (`reach` "left for Step 7"), caught only by hand at Step 7.

> **Evidence**: data-model.md Coverage entry Validation rules; contracts/cli.md tool behaviors/exit codes; plan.md Step 3/6/7 Verification, Step 16 final acceptance table.

**Recommendation**: Add manifest schema validation to `enumerate.py --check` with a new exit code for a rule violation (rule + row printed), invoked at every gate already. Either make `reach` optional-until-triage in data-model.md, or have Step 6 write `reach = -` so the schema is true at every gate.

**Digest**: no tool checks the data model's own validation rules; a drifted row can silently vanish from the record while `--check` exits 0.

- [ ] Resolved

---

#### RK-003: `prove.sh` kills the loser subshell before reaping its solver, so ~110 sequential proofs can leave orphaned CBMC processes competing for the cores the next proof needs
**Agent**: RK · **Type**: Existing debt
**Disposition**: [PRESENTED]

- Each proof's cleanup does `kill "$subshell_pid"` then `pkill -P "$subshell_pid"` — backwards. Killing the subshell first reparents its `cbmc` child away, so the subsequent `pkill -P` matches nothing and the solver survives; the `EXIT` trap then deletes the workdir out from under it.
- Invisible at four entries; at ~110 run back-to-back via `--all`, each proof can leak up to three long-running solvers into the next proof's run — exactly the CPU contention D9's "no outer `-j`" reasoning tries to avoid, arriving from the previous proof instead of a job pool, and a direct threat to SC-003's reproducibility since it makes `TIMEOUT` nondeterministic.

> **Evidence**: `prove.sh:197-203` (kill/pkill order), `prove.sh:167-170` (`$!` is the subshell pid), `prove.sh:40` (EXIT trap); research.md D9; plan.md marks `prove.sh` UNCHANGED.

**Recommendation**: Swap the two lines (`pkill -P` first, then `kill`), add a `wait` after the loop, and relax the "UNCHANGED" designation for this two-line fix — or, if `prove.sh` must stay untouched, add a guard in `proofs/run.sh` (e.g. a pre-row check for a stray `cbmc`) and record that elapsed times are only valid on an otherwise idle machine.

**Digest**: `prove.sh`'s solver-race cleanup kills the wrong process first, leaking CBMC processes across ~110 sequential proofs.

- [ ] Resolved

---

#### RK-004: Steps 11-13 are marked parallelizable, but each step's own body lists `CONTRACTS.md` as an artifact and all three write `proofs/cases.tsv`; the stated mitigation lives in a section the plan declares out of scope
**Agent**: RK · **Type**: Risk
**Disposition**: [PRESENTED]

- Task Dependencies Group 9 marks Steps 11-13 parallelizable with a mitigation ("append-only cases.tsv, regenerate CONTRACTS.md once at the boundary") — but that section is explicitly prefaced "not part of the review surface," while each step's own body lists `CONTRACTS.md` as an artifact and Phase 4's preamble says "record the row and regenerate" per family. An implementer follows the step body, not the out-of-scope table.
- `render.py` is a whole-region rewrite, not an append — two concurrent runs are a lost-update race, and `enumerate.py --check` only detects set differences, not a torn append mid-line, which reports as an opaque parse failure with no indication of which step's work was lost.

> **Evidence**: plan.md Task Dependencies Group 9; Steps 11/12/13 Artifacts lines; Phase 4 preamble; contracts/cli.md render.py/enumerate.py exit codes.

**Recommendation**: Give each parallel step its own manifest shard (`proofs/cases.d/batch-a.tsv` etc.), concatenated by the runner/renderer, and restate in each step body that `CONTRACTS.md` is regenerated once at the group boundary — removing it from their individual Artifacts lines. Alternative: serialize the three steps and keep the single file.

**Digest**: Steps 11-13's parallelism mitigation lives in an out-of-scope section that contradicts what each step's own body instructs.

- [ ] Resolved

---

#### RK-005: ~110 seeded `todo` rows make the record "complete" from day one with a single end-of-project control, and nothing re-runs that control after the feature lands
**Agent**: RK · **Type**: Risk
**Disposition**: [PRESENTED]

- Step 6 seeds a `todo` row per enumerated function so SC-001 is satisfied immediately, but the only control preventing `todo` from becoming permanent is `enumerate.py --strict` at Step 16 — all-or-nothing at the very end, with no per-phase ratchet requiring the count to strictly decrease.
- Under schedule pressure, the cheapest way to make `--strict` exit 0 is relabeling stuck `todo` rows to a terminal class like `timeout`/`framework`, which the check accepts unconditionally with no tool enforcing the "specific barrier, not category" prose rule. Nothing runs `--check`/`--strict` in CI after merge either, even though both are pure-Python and need no CBMC — so SC-001 decays silently as new kernels are added.

> **Evidence**: plan.md Step 6, D12; Phase 4 gate wording; Step 16 ("sweep every remaining todo"); research.md D13; contracts/cli.md `--strict`.

**Recommendation**: Require the group-boundary check to record the remaining `todo` count and require it strictly lower than the previous boundary. Add `enumerate.py --check`/`render.py --check` (not the proofs) to the existing CI quality job, since they're pure-Python and need no CBMC.

**Digest**: the only control against `todo` rows becoming permanent terminal-reason rows is one all-or-nothing check at the very end of the project, never re-run after merge.

- [ ] Resolved

---

#### RK-006: FR-015 publishes a reproduction for an unpatched, attacker-reachable defect with no disclosure path, no owner routing, and a suite that turns red on whoever fixes it
**Agent**: RK · **Type**: Risk
**Disposition**: [PRESENTED]

- FR-015's "report, don't patch" split is defensible, but a committed `expect = FAIL` defect row with a self-contained reproduction command, in a repository published on GitHub, has none of the machinery that split normally requires — no security contact, embargo consideration, issue routing, or tracking ID.
- By design, the row is a trap for the eventual fixer: a defect that stops reproducing is a suite *failure* (FR-009b), so the contributor who fixes the bug breaks `./proofs/run.sh` with a confusing "RECORDED PASS" message, with no CONTRIBUTING-facing note explaining the obligation.

> **Evidence**: spec.md FR-015, "Report, don't patch"; plan.md Step 9 (`divide_by` bullet); data-model.md Expected-verdict matrix and "defect fixed elsewhere" transition; contracts/coverage-record.md Consumers table.

**Recommendation**: Add a Phase 5 step that, for any row reaching `reason_class = defect`, records a tracking reference in the row's `note`, notifies the codec owner before the row is pushed, and states the fixer's one-line instruction in `CONTRACTS.md`'s Running section and beside the row itself.

**Digest**: a committed, unpatched, attacker-reachable defect row has no disclosure path, no owner, and traps whoever eventually fixes it.

- [ ] Resolved

---

#### RK-008: The plan redefines the coverage surface but leaves the spec's 31-file measure standing, and annotating shared `common_*` kernels puts encode builds inside the blast radius
**Agent**: RK · **Type**: Scope
**Disposition**: [PRESENTED]

- The spec fixes the surface three times as "31 decode kernel source files"; the plan replaces it with decode-*reachable* exported functions, adding four `common_*` headers — well-argued and bounded, but Step 16 corrects only `CONTRACTS.md`, never `spec.md`, so SC-001 stays written against a surface the implementation no longer matches. The plan's own Source Code tree ("30 headers") also disagrees with research.md's "34 headers" for the same surface.
- `common_bitpack_kernel.c`/`common_pivco_kernel.h`/`common_endianness_kernel.h` are shared with encode paths (`encode_bitpack_binding.c`, `encode_bitunpack_binding.c`); annotating them extends F2's unpushed `-Wgcc-compat` suppression and any `diagnose_if` clause into encode TUs, which Step 8's measurement scope never explicitly names as included.

> **Evidence**: spec.md Summary/SC-001/Design Decisions; plan.md Source Code tree; research.md D6/F4; plan.md Step 8; `encode_bitpack_binding.c:112-120`; `encode_bitunpack_binding.c:63`.

**Recommendation**: Amend spec.md's "31 files" occurrences to the function-based surface as a co-evolution edit rather than deferring correction to `CONTRACTS.md` only; extend Step 8's `-Wgcc-compat` measurement explicitly to the encode TUs that compile the shared `common_*` kernels.

**Digest**: spec.md's "31 files" surface is never corrected to match the plan's redefinition, and shared `common_*` kernels pull encode builds into the blast radius unmeasured.

- [ ] Resolved

---

#### RK-009: the FR-014 control is unrunnable on any machine without a clang-format 21, is not wired into CI, and Step 1's exemption has no fallback if it is rejected or does not take effect
**Agent**: RK · **Type**: Risk
**Disposition**: [PRESENTED]

- `scripts/check_contract_format.sh` exits 3 for every contributor without clang-format 21 specifically — including this machine (19.1.2 on PATH, 21.1.2 only at a personal, uninstructed path) — making the plan's per-step check unperformable rather than inconvenient. CI's `test-quality` job doesn't invoke this script at all (it runs `jidicula/clang-format-action` with its own vendored formatter), so the script is author-side-only and the two are never reconciled.
- `.clang-format-ignore` handling is a clang-format 18+ feature whose behavior under the CI action's invocation style is an empirical question Step 1 does test — but there's no stated plan B if the exemption fails that simulation or is rejected in review, and the exemption is permanent and unbounded even though `c_contracts.h` is actively evolving, unlike the `*/json.hpp` precedent it follows.

> **Evidence**: plan.md Step 1, Task Dependencies Group 1; research.md D10/D11/F1; contracts/cli.md exit code 3; `.github/workflows/dev-ci.yml` `test-quality` job; `.clang-format-ignore`; local `clang-format --version` = 19.1.2.

**Recommendation**: Have the script print a concrete acquisition line on exit 3 and record it in CONTRACTS.md's Requirements table. Add a named fallback to Step 1: if the ignore-file route fails CI simulation or is rejected, wrap the offending region of `c_contracts.h` in `clang-format off`/`on` as a one-hunk deviation instead.

**Digest**: the FR-014 checker refuses to run without clang-format 21 (which most contributors lack), isn't wired into the real CI gate, and has no fallback plan.

- [ ] Resolved

---

### MINOR (1)

#### CR-011: `render.py --check` is specified two different ways across the two contract documents
**Agent**: CR · **Type**: Inconsistency
**Disposition**: [PRESENTED]

- `contracts/cli.md` defines `--check` as failing when "the committed file" differs from a fresh render — any hand-edited prose would trip it. `contracts/coverage-record.md` says the opposite: `--check` compares only the generated regions, so hand edits to prose never make the record report as stale. plan.md Step 5's verification depends on the second (correct) reading.
- Implemented from `cli.md`'s wording, `--check` would turn the record's hand-authored Legend/Gotchas/Observations — the parts Step 16 is entirely devoted to writing — into a source of false staleness at every Phase gate.

> **Evidence**: contracts/cli.md `render.py` flag table and exit code 1; contracts/coverage-record.md Region model section; plan.md Step 5 Verification.

**Recommendation**: Change `cli.md`'s `--check` row to "Render the generated regions to memory and compare them against the committed file's marker-delimited regions; exit 1 if any generated region differs. Bytes outside the markers are not compared," matching `coverage-record.md` and Step 5's already-correct usage.

**Digest**: `cli.md` and `coverage-record.md` define `render.py --check`'s scope oppositely; the plan relies on the narrower (correct) one — fix `cli.md`.

- [ ] Resolved

---

### Auto-Applied (4)

#### CR-010: There are five `common_*kernel*.h` files, not four, and Step 2's verification list only names four
**Agent**: CR, CV · **Type**: Inconsistency
**Severity**: MINOR
**Disposition**: [AUTO-APPLIED]
**Classification**: Additive

- research.md D6 says rule 2 "was validated against all three `common_*_kernel.h` files and a fourth discovered by it," and F4 records the in-scope count as 4. The tree has five: `bitpack`, `bitSplit`, `conversion`, `pivco_huffman`, and `entropy/common_huffman_kernel.h` — the fifth, referenced from `entropy/decode_huffman_kernel.c`, satisfies D6's rule 2 exactly but declares only an enum, so it contributes zero coverage rows.
- The outcome is benign, but Step 2's own verification enumerates only four headers to confirm, so an enumerator hardcoding the four named paths would pass Step 2's acceptance test while implementing something narrower than D6 states.

> **Evidence**: research.md D6 rule-2 validation table (four rows) and F4; plan.md Step 2 Verification (names four); `ls src/openzl/codecs/*/common_*kernel*.h` returns five; `entropy/decode_huffman_kernel.c:7` includes the fifth.

**Recommendation**: Applied — Step 2's Verification now also requires the enumerator's output to report `entropy/common_huffman_kernel.h` as in scope under rule 2, contributing zero functions, so the enumerator is confirmed to apply the rule rather than reproduce a hardcoded list. (The corresponding correction to research.md's rule-2 table is outside this synthesis's write scope and is not applied here.)

**Digest**: research.md/Step 2 name 4 `common_*kernel*.h` files; a 5th (zero-function) header satisfies the same rule — added to Step 2's verification.

- [x] Resolved

---

#### CV-004: Every Phase 4 step's diagnostic gate contradicts the spec's decided behavior for the "annotation causes a new call-site diagnostic" edge case
**Agent**: CV · **Type**: Inconsistency
**Severity**: SHOULD-CONSIDER
**Disposition**: [AUTO-APPLIED]
**Classification**: Semantic

- The spec's fourth edge case decides that a new diagnostic at a real call site "is a finding and is recorded as one. The clause is not weakened to silence the diagnostic." Every Phase 4 step's gate stated a flat pass/fail check — "no new diagnostics" — with no branch for a genuine true-positive diagnostic, pointing an implementer toward the exact reflex the spec forbids (weakening the clause to turn the check green) with nothing recording that it happened.
- Step 8 already had the right shape for its own one warning ("or the difference is recorded as a finding") but never generalized it to the Phase 4 gate that governs every other step.

> **Evidence**: spec.md Edge Cases, fourth bullet; plan.md Phase 4 preamble; plan.md Step 8 Verification (the un-generalized precedent); spec.md FR-012b vs FR-013.

**Recommendation**: Applied — the Phase 4 preamble's diagnostic check is now two-outcome: no new diagnostics, or a triaged one (a `diagnose_if` precondition violation becomes a `defect`-or-`observation` row in `CONTRACTS.md` without weakening the clause; any other new diagnostic is fixed). Added a matching "Diagnostic triage" row to Step 16's acceptance table. A holistic reconciliation pass found this created a residual contradiction with the pre-existing SC-005 acceptance row ("warning set identical to the pre-feature baseline," which admitted no carve-out for a triaged diagnostic) and repaired it by amending that row's Expect cell to explicitly except an already-triaged diagnostic.

**Digest**: Phase 4's per-step gate said "no new diagnostics," flatly contradicting the spec's own decided behavior for a real violating call site — made two-outcome.

- [x] Resolved

---

#### CV-008: `proofs/try.sh` is listed as existing "UNCHANGED" infrastructure but is untracked in git
**Agent**: CV · **Type**: Inconsistency
**Severity**: MINOR
**Disposition**: [AUTO-APPLIED]
**Classification**: Additive

- The plan's Source Code table lists `proofs/try.sh # UNCHANGED`, and every Phase 4 step's inner loop depends on it ("iterate with `./proofs/try.sh`"), but `git ls-files proofs/` shows it untracked — it appears as `?? proofs/try.sh` in the branch's status. Marking it UNCHANGED means no step commits it, so a fresh clone cannot follow Phase 4's inner loop.

> **Evidence**: plan.md Source Code table; plan.md Phase 4 preamble; `git ls-files proofs/ prove.sh CONTRACTS.md` (no `try.sh`); branch status `?? proofs/try.sh`.

**Recommendation**: Applied — changed the Source Code table entry to `proofs/try.sh # NEW (untracked today) — scratch driver, commit as-is`, and added committing it to Step 1's Artifacts line.

**Digest**: `proofs/try.sh` is marked "UNCHANGED" but is untracked in git — relabeled as new and added to Step 1's committed artifacts.

- [x] Resolved

---

#### RK-010: the annotation-absent guard the rewrite must preserve is fail-open and keyed to one hardcoded path, so at ~110 rows a moved file turns the whole suite green while proving nothing
**Agent**: RK · **Type**: Existing debt
**Severity**: SHOULD-CONSIDER
**Disposition**: [AUTO-APPLIED]
**Classification**: Semantic

- The existing guard uses `grep -qs`, which suppresses the missing-file error, so a renamed or mistyped path is indistinguishable from an unannotated checkout — one SKIP line, exit 0, which every gate in the plan reads as success. At four hand-written entries a silently skipped suite is obvious; at ~110 manifest-driven rows behind `--filter`/`--tier`, a reader who sees one SKIP line has no denominator to notice is missing.

> **Evidence**: `proofs/run.sh:66-69`; contracts/cli.md "MUST preserve the existing guard"; plan.md Step 4 and Step 16 final-acceptance table.

**Recommendation**: Applied — Step 4's body now requires the annotation-absent guard to fail closed on its own precondition (a missing guard file is a hard error distinct from a present-but-unannotated file) and requires the summary line to always print the manifest row count alongside any `SKIP` message.

**Digest**: the annotation-absent guard is fail-open on a hardcoded path — Step 4 now requires it fail closed and always report the row count.

- [x] Resolved

---

### Discarded (0)

---

### Summary

#### By Severity
| Severity | Count |
|----------|-------|
| MUST-ADDRESS | 9 |
| SHOULD-CONSIDER | 16 |
| MINOR | 1 |
| **Total** | **26** |

#### By Type
| Type | Count | MUST | SHOULD | MINOR |
|------|-------|------|--------|-------|
| Spec gap | 1 | 1 | 0 | 0 |
| Inconsistency | 4 | 1 | 2 | 1 |
| Design gap | 6 | 3 | 3 | 0 |
| Test gap | 4 | 1 | 3 | 0 |
| Existing debt | 2 | 1 | 1 | 0 |
| Risk | 5 | 0 | 5 | 0 |
| Scope | 2 | 1 | 1 | 0 |
| Premise | 2 | 1 | 1 | 0 |

#### By Triage Disposition
| Disposition | Count |
|-------------|-------|
| Auto-Applied | 4 |
| Discarded | 0 |
| Presented | 26 |
| Escalated | 2 |
| **Total** | **30** |

**Gate Status**: BLOCKED
