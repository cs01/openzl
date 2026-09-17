---
description: Shared agent prompt boilerplate for review command agents
---

INPUTS:
The dispatch prompt carries these as paths, not embedded content. Read each file yourself; nothing below is a substitute for reading it.

| Binding | Meaning |
|---|---|
| `ATTEMPT_ID` | The current attempt's identity. Stamped into your terminal marker. |
| `ATTEMPT_DIR` | Absolute path to the attempt directory. Already exists and is writable. |
| `PREFIX` | Your finding-ID prefix: `CR`, `CV`, `RK`, or `CC`. |
| `ROLE` | Your human-readable role name, echoed back in the marker. |
| `FEATURE_SPEC` | Path to `spec.md`. |
| `IMPL_PLAN` | Path to `plan.md`. Plan review only. |
| `CONSTITUTION` | Path to `.specify/memory/constitution.md`. Constitution Compliance only, and only when the file exists. |
| `ENRICHMENT` | Path to the project-context enrichment file, when it exists. Search-enabled roles only. |
| `EXPLORATION` | Path to `exploration.md`, when it exists. Correctness Reviewer only. |
| `FR_COUNT` | Number of distinct `FR-###` identifiers under the spec's `## Requirements` section (0 if absent). Used to compute your finding-budget share below. |
| `PANEL_SIZE` | Number of role briefs dispatched in this run. Used to compute your finding-budget share below. |

OUTPUT FORMAT — DURABLE DELIVERY CONTRACT:
Your response text is not read for findings or for delivery evidence — nothing you return as your final message is consulted. Everything you produce must land as files under `{ATTEMPT_DIR}`, in this order.

1. **Write a liveness file before anything else.** Your very first action, before reading `FEATURE_SPEC` or any other input, before beginning analysis:

   `touch {ATTEMPT_DIR}/{PREFIX}.alive`

   You write outside the workspace and outside any declared working directory. Under a non-bypass permission mode, a write to a path like this can raise a permission prompt — and on an unattended run there is nobody to answer it. Writing this file first turns that failure mode into a signal that arrives in seconds instead of a silent stall that costs the full wait ceiling. It is also what lets the wait step distinguish "working" from "produced nothing at all."

2. **Publish each finding as soon as it is complete — do not batch them for one write at the end.** For each finding:

   1. Write the finding body to `{ATTEMPT_DIR}/findings/{PREFIX}-{NNN}.md.tmp`.
   2. Rename it to `{ATTEMPT_DIR}/findings/{PREFIX}-{NNN}.md`.

   `{NNN}` is zero-padded starting at `001`, unique within your prefix. The rename target MUST be in the same directory as the temp file — stage the `.tmp` file directly under `findings/`, not under your own scratch path and then moved in. A rename across directories is not guaranteed atomic, and the failure this staging discipline prevents is a reader observing a half-written finding. If you are interrupted before finishing, the findings you already published stand — that is the point of publishing as you go rather than holding everything for a final write.

   The finding body format itself is unchanged:

   > ### {PREFIX}-{NNN}: {finding title}
   > **Severity**: {MUST-ADDRESS | SHOULD-CONSIDER | MINOR}
   > **Type**: {Spec gap | Inconsistency | Design gap | Test gap | Existing debt | Risk | Scope | Premise | Plan-deferred}
   > {description}
   > **Evidence**: {specific reference to spec/plan section}
   > **Recommendation**: {corrective action}

3. **Write exactly one terminal marker, and write it last** — only after every finding's rename above has returned:

   1. Write `{ATTEMPT_DIR}/{PREFIX}.done.json.tmp`.
   2. Rename it to `{ATTEMPT_DIR}/{PREFIX}.done.json`.

   > {
   >   "attempt_id": "{ATTEMPT_ID}",
   >   "prefix": "{PREFIX}",
   >   "role": "{ROLE}",
   >   "status": "complete",
   >   "finding_count": 7,
   >   "failure_reason": null
   > }

   `finding_count` is the number of finding files you wrote. This marker is the set-level commit point: a reader that sees it is guaranteed every finding it counts is already readable on disk. Writing it before your last finding's rename has returned produces a review that reads as delivered while that finding is still absent — do not write it early to save a step. If you found nothing, write the marker anyway with `finding_count: 0` and `status: "complete"`; that is a delivered review, distinct from a review that never concluded.

4. **If you cannot finish, write a failed marker instead of leaving nothing.** Same file, same rename discipline, with `status: "failed"`, a `failure_reason` string, and `finding_count` set to however many findings you did manage to publish before the failure. This concludes you immediately rather than costing the wait its full ceiling waiting on a marker that will never arrive.

What you MUST NOT do:
- Return findings as your response text. The response is not read for delivery evidence and is not read for content.
- Write anywhere outside `{ATTEMPT_DIR}`. In particular, never into the feature directory — those artifacts are committed, and per-reviewer output must never be.
- Rename a finding into `findings/` from outside that directory.
- Write a marker whose `attempt_id` differs from the one you were given.
- Write more than one marker.

SEVERITY CRITERIA:
- MUST-ADDRESS: Must clear both gates below, in order.

  Gate 1 (pre-filter): Would following the spec/plan as written produce code that crashes, corrupts data, silently does the wrong thing at runtime, omits a stated requirement, or contains a contradiction/impossibility the implementer cannot resolve without guessing (e.g., two steps that assume mutually exclusive approaches)? If no, it cannot be MUST-ADDRESS — stop here and grade it SHOULD-CONSIDER or MINOR instead. These fail Gate 1:
  - Design *choices* the plan author made deliberately (e.g., duplication vs. extraction)
  - Spec wording inconsistencies that need a text fix, not a design change
  - Risk documentation requests ("state the rollback story")
  - Implementation details the implementer would naturally resolve (symbol visibility, test file naming)
  - Rare edge cases that can be explicitly accepted as known gaps
  - Sequencing or ordering issues with trivial fixes

  Exception: "Implementation details the implementer would naturally resolve" does not fail Gate 1 when following the plan's recommendation as written would produce code that compiles but silently fails at runtime (dead handler, unreachable branch, no-op guard). Silent runtime failure clears Gate 1, regardless of whether the fix is an implementation detail.

  Gate 2 (only evaluate once Gate 1 clears): Blocks correctness, breaks a stated requirement, or will cause implementation failure. The plan, as written, would produce incorrect code, a crash, data corruption, or a silent requirement violation that the implementer cannot reasonably self-correct.

- SHOULD-CONSIDER: Production risk, tech debt seed, or design improvement
- MINOR: Cosmetic, documentation, or low-impact suggestion

SPEC-LEVEL FINDING CAP:
Spec-level MUST-ADDRESS cap: `min(max(FR_COUNT, 3), 10)` — no spec needs more than 10 genuinely blocking findings; specs with fewer than 3 FRs (or no `## Requirements` section) still get a floor of 3 so the budget never collapses to zero. Spec-level SHOULD-CONSIDER cap: `max(FR_COUNT, 3) × 1.5` — non-blocking findings have lower attention cost, so this cap is looser.

Your per-agent MUST-ADDRESS share is `ceil(spec-level MUST-ADDRESS cap / PANEL_SIZE)`. Your per-agent SHOULD-CONSIDER share is `ceil(spec-level SHOULD-CONSIDER cap / PANEL_SIZE)`. Example: a 5-FR spec reviewed by a 3-agent panel gets a MUST-ADDRESS cap of 5, so each agent's share is 2.

FINDING BUDGET:
Target your per-agent MUST-ADDRESS share and per-agent SHOULD-CONSIDER share, both computed above. If you exceed your MUST-ADDRESS share, pause and re-evaluate each excess finding against the negative-example list above — over-grading is the most common calibration failure. Downgrade any that fail Gate 1. If genuine findings remain above your share, include them all — do not suppress real issues to hit a number. When MUST-ADDRESS findings exceed your share, rank-order them by impact: the top N (your share) are the primary blocking set; additional findings are tagged `[OVERFLOW]` in their title (e.g., `### {PREFIX}-NNN: Missing rollback path [OVERFLOW]`) and presented after the primary set. This gives the user a prioritized view without hiding material findings. The budget is a calibration prompt, not a hard cap.

SPEC/PLAN BOUNDARY:
The spec describes WHAT the feature does and WHY — capabilities, behaviors, user outcomes. The plan describes HOW — file paths, schemas, data structures, method signatures, concrete implementations. If your finding recommends adding implementation details to the spec, classify it as `Plan-deferred` — the finding is valid but belongs in plan.md, not spec.md. The plan step reads review/review-findings.md and will incorporate Plan-deferred findings.

Examples of implementation details that MUST be Plan-deferred (not added to the spec):
- Artifact format templates (markdown heading structure, YAML frontmatter schema, table layouts)
- Specific test method names, test assertion content, or test file enumerations
- File-by-file change lists (File Plan sections listing specific paths and modifications)
- Configuration schemas, CLI flag parsing details, or output format specifications
- Specific function/class/variable names or API surface details

The spec should say "the artifact MUST contain X, Y, Z" (WHAT). The plan decides the markdown structure, heading hierarchy, and field layout (HOW). Similarly, the spec should say "tests MUST cover subagent dispatch and artifact production" (WHAT). The plan decides which test files, method names, and assertions (HOW).

TYPE TAXONOMY:
- Spec gap: Missing requirement, section, edge case, or acceptance scenario
- Inconsistency: Internal contradictions or cross-artifact mismatches
- Design gap: Missing or ambiguous design decision or contract
- Test gap: Missing test planning or untestable criteria
- Existing debt: Pre-existing bugs in referenced files
- Risk: Failure modes, blast radius, or missing safeguards
- Scope: Overscoped requirement or boundary ambiguity
- Premise: Weak evidence or inadequate existing-solution evaluation
- Plan-deferred: Valid finding whose fix requires implementation details that belong in plan.md, not spec.md

ADVERSARIAL SELF-CHECK:
Before concluding PASS on any evaluation dimension, construct the strongest possible argument for a violation. Filter for plausibility: the counterargument must be backed by artifact-grounded evidence (spec text, plan content, referenced file state), not hypotheticals. If a plausible counterargument exists, report it as minimum SHOULD-CONSIDER severity with both the PASS argument and the counterargument visible in the finding description. Caveat: For agents whose role is inherently adversarial (Correctness Reviewer), this instruction is redundant — apply it only to agents performing compliance or gap checks.

RECOMMENDATION SPECIFICITY:
For MINOR findings, name one specific corrective action — not a menu of alternatives. If two
valid fixes exist, pick the better one and note the alternative in the description, not the
recommendation. SHOULD-CONSIDER and MUST-ADDRESS findings with legitimate alternatives present
both with tradeoff assessment (unchanged behavior for those tiers).

## Codebase Search Instructions

Appended only to search-enabled agents' composed prompts (Correctness Reviewer, Coverage Reviewer) — never to Constitution Compliance's or Risk Reviewer's.

You have access to codebase search tools. Use them to ground your analysis in actual code.

**Search budget**: Target 10 minutes maximum for all searches combined. If approaching the limit, proceed with text-only analysis for remaining findings and note which findings lack codebase verification. This budget is prompt guidance, not a mechanically enforced timeout.

**Evidence format**: When referencing codebase evidence, use project-relative paths (not absolute checkout paths):
> **Evidence**: [description]. Source: `path/to/file` line N — [relevant context].

**Fallback**: If search is unavailable or returns no results, proceed with text-only analysis and note:
> **Note**: Codebase search [timed out | was unavailable | returned no results]. Analysis is text-only.
