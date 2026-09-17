# Review Plan — Synthesis

Read findings the adversarial panel already published to the attempt directory, synthesize them, and write results to disk. The panel itself is dispatched directly by `/speckit-review-plan` from `review-plan-panel-prompts.md` — this template no longer dispatches anything.

This file is read and executed by a subagent dispatched from `/speckit-review-plan`, after `review-wait.sh` has returned a terminal token for the reviewer wait. It is NOT a standalone command.

## Inputs

The dispatching command passes these via the Agent prompt:
- `FEATURE_DIR`: absolute path to the feature directory
- `FEATURE_SPEC`: absolute path to `spec.md`
- `IMPL_PLAN`: absolute path to `plan.md`
- `GATE_TYPE`: always `secondary` for this template
- `PENDING_RECOMMENDATION`: `pending` if a prior resolution session recommended re-running this review, `discharged`/`none` otherwise
- `ATTEMPT_ID`: the current review attempt's identity
- `ATTEMPT_DIR`: absolute path to the attempt directory
- `PANEL_SIZE`: the dispatched panel's designed size, read by the command from `manifest.json` — 1-4 agents depending on spec complexity×risk (base 1-3 plus CC when a constitution file exists) per `review-plan-panel-prompts.md`. Not `AGENTS_COMPLETED`, which is how many roster entries actually delivered.
- `AGGREGATE_PATH`: optional. When set, the path to the pre-aggregated finding document produced by `review-pre-aggregate.sh`. Synthesis reads this instead of individual per-reviewer finding files.
- `PRE_AGGREGATE`: optional. `true` when the dispatching command requested pre-aggregation (always true for plan review, never set for spec review). Used only to compute `pre_aggregation_status` below — distinguishes `failed` (requested but no usable `AGGREGATE_PATH`) from `skipped` (never requested).

## Precondition: Wait-Conclusion Marker

Before reading anything else, read `{ATTEMPT_DIR}/wait-concluded.json`. Refuse to run — do not read findings, do not write `review/review-findings.md`, do not touch `plan.md`, do not write a gate — when either is true:
- the file is absent, or
- its `attempt_id` does not equal `ATTEMPT_ID`.

Either condition means no bounded wait has concluded for this attempt, so synthesizing now would race a still-live panel. On refusal, write `{ATTEMPT_DIR}/synthesis.done.json` per Write Synthesis Marker below with `status: "error"`, `agents_completed: 0` (meaningless here — delivery was never evaluated), `panel_size: "$PANEL_SIZE"`, zero tier counts, `decision_point_count: 0`, and `gate_written: false`. Emit `review_pipeline_status: error` and stop.

## Read Findings from the Attempt Directory

Read `{ATTEMPT_DIR}/manifest.json` for the roster (`{prefix, role}` pairs), `panel_size`, and `quorum_required`. Read `FEATURE_SPEC` and `IMPL_PLAN` directly — synthesis needs its own copy for the classification steps below and for the in-memory composition Triage step 1c performs, independent of whatever the dispatched reviewers read.

For each roster entry, classify its delivery status against `{ATTEMPT_DIR}/{PREFIX}.done.json` and the finding files under `{ATTEMPT_DIR}/findings/{PREFIX}-*.md`, using this five-status vocabulary. The installed wait script's classification governs on any disagreement — this table restates it for readability, and a divergence between the two is a defect in this table, not a second rule:

| Status | Condition |
|---|---|
| `delivered` | marker present, `attempt_id` matches, `status: complete`, readable findings **==** `finding_count` |
| `delivered (count discrepancy)` | as above, readable findings **>** `finding_count` |
| `failed` | marker present, `attempt_id` matches, `status: failed` |
| `outstanding` | no matching marker, or readable findings **<** `finding_count`, with at least one file present for that prefix |
| `outstanding (no output)` | no matching marker and zero files of any kind for that prefix |

A marker whose `attempt_id` does not match the manifest's is ignored entirely. Read every readable finding file for a `delivered` or `delivered (count discrepancy)` row — a surplus finding is still synthesized, the discrepancy is only disclosed in the table. `AGENTS_COMPLETED` is the count of rows classified `delivered` or `delivered (count discrepancy)`. This delivery table, recomputed here from the markers, is what the header block below carries and is what a reader now consults for a missing role — it supersedes the retired per-run pipeline-state sidecar disclosure, which could name only one missing role at a time.

**Finding content source**: The delivery classification above is always computed from markers and on-disk file counts, never from `AGGREGATE_PATH` — that stays true regardless of the branch below. If `AGGREGATE_PATH` is set and the file exists, read it for finding content in place of the individual `findings/{PREFIX}-*.md` files. If `AGGREGATE_PATH` is not set, or the file does not exist, read the individual finding files as described above (backward compatible).

## Quorum Check

Compare `AGENTS_COMPLETED` against `quorum_required`, read from `manifest.json`. `review-attempt.sh init` computed it from the roster at dispatch time — the single definition site for the threshold — so this step reads the same value the wait script already emitted its own verdict against, rather than restating 4/5.

If quorum is **not** met:
1. Write the blocked gate and pipeline state together — this also records `panel_size` and `quorum_met: false` in `review/review-gate.json` so the dispatching preset can distinguish this outcome from a corrupted findings file:
   ```bash
   speckit run write-review-gate-unified.sh \
     --gate-type "secondary" \
     --status blocked \
     --must-address 0 \
     --should-consider 0 \
     --minor 0 \
     --agents-completed "$AGENTS_COMPLETED" \
     --panel-size "$PANEL_SIZE" \
     --quorum-met false \
     --attempt-id "$ATTEMPT_ID" \
     --partial
   ```
2. Log: "Insufficient agent responses ({N}/5). Re-run /speckit-review-plan."
3. Write `{ATTEMPT_DIR}/synthesis.done.json` per Write Synthesis Marker below with `status: "quorum_failed"`, zero tier counts, `decision_point_count: 0`, and `gate_written: true`.
4. Emit terminal status `review_pipeline_status: quorum_failed` and stop. Do not proceed to synthesis.

If quorum is met, proceed to synthesis.

## Synthesize Findings

**Deduplicate**: Collect all findings from the agents that returned. Two findings overlap if they reference the same spec/plan section AND describe the same corrective action. When findings overlap, merge into a single finding using the first originating agent's prefix. List all originating agents in the Agent field. Use the highest severity. When in doubt, keep findings separate. If any originating finding carries a Violated Principle (i.e., came from the Constitution Compliance agent), carry that value forward into the merged finding — merging must never drop it.

**Classify by type**: Assign each finding a type from the taxonomy (Spec gap, Inconsistency, Design gap, Test gap, Existing debt, Risk, Scope, Premise). Use the type the originating agent assigned; when merging, use the most specific type.

**Organize by severity**: Group findings into MUST-ADDRESS, SHOULD-CONSIDER, MINOR sections.

**Renumber**: Assign sequential IDs within each agent prefix after deduplication.

**Count**: Record `must_address_count`, `should_consider_count`, `minor_count`, `total_findings`.

**Atomic FR check**: For any finding whose recommendation creates or modifies a functional requirement, apply the single-obligation test: could one half of the resulting FR pass verification while the other half fails? If yes, split the finding into separate findings — one per atomic obligation — each with its own recommendation. Renumber after splitting and update counts. This prevents compound FRs from being synthesized, presented to the user, and accepted without scrutiny.

Note: plan review has no Plan-deferred classification or boundary re-check — those apply only to spec review, where implementation-detail findings need to be routed to `/speckit-plan`. Findings synthesized here are already in the plan.

## Triage Findings

Before writing the gate file, triage the reconciled findings into three dispositions — findings that can be applied mechanically without review, findings that add no value and can be dropped, and findings that need a human decision.

**1a. Classify each finding**: Read `.specify/templates/triage-classifier-criteria.md` once and apply its criteria to each reconciled finding, in order, to determine its tentative disposition. The fragment defines the severity guard, the constitution guard, the behavioral-claim verification guard, the auto-apply-first evaluation ordering, the auto-apply criteria (a)-(g), the discard criteria (a)-(d), and the conservative bias rule (uncertain → `PRESENTED`; classifier error → `PRESENTED` with a `**Triage Advisories**:` line in the Summary section, see the Write review-findings.md format below).

**Fallback**: If `.specify/templates/triage-classifier-criteria.md` cannot be read, skip triage, route all findings to `PRESENTED`, and note the unavailability in Triage Advisories.

Output: every finding annotated with a tentative disposition — `AUTO_APPLY`, `DISCARD`, or `PRESENTED`.

**1b. Pass 1 reconciliation — auto-apply candidates against each other**: Compare every `AUTO_APPLY` candidate's recommendation against every other candidate's recommendation:
- Same artifact and overlapping target region → potential contradiction.
- Contradictory actions on the same element (one adds what another removes, or similar) → pull both candidates to `PRESENTED` and annotate them `[ESCALATED: reconciliation conflict]`.
- A candidate whose edit target cannot be found in the plan → pull it to `PRESENTED` (same annotation).

When two or more candidates are escalated together by this pass, emit a shared `**Theme Group**: {group-id} — "{escalation reason}"` line on each so the interactive queue presents them as one coordinated decision instead of independently — including when the escalated pair is MINOR tier, in which case they are excluded from step 1e's batch (below) and presented as their own group instead.

Output: the surviving `AUTO_APPLY` set after pull-back.

**1c. Pass 2 reconciliation — holistic read-back**: Build an in-memory copy of the plan with the surviving auto-applied fixes applied. Dispatch a separate `Agent(model: "sonnet")` to read and execute `.specify/templates/holistic-reconciliation.md` with these bindings:
- `COMPOSED` = the staged plan content (one artifact: plan.md)
- `BASELINES` = the pre-triage plan content
- `WRITTEN_REGIONS` = the regions the auto-applied fixes wrote
- `CONTRIBUTING` = the finding IDs of the surviving auto-apply candidates
- `CANDIDATE_SET` = plan.md only (stale-counterpart detection is inert with a single-member set)
- `USER_PRESENT` = false
- `GROUPS` = omitted (per `holistic-reconciliation.md`, an omitted `GROUPS` treats the whole composed artifact — the staged plan — as one repair unit; an `unrepairable` outcome here escalates every surviving candidate, not just the offending one)

Any candidate whose fix the reconciliation pass discards, or that contributes to an `unrepairable` outcome, is pulled to `PRESENTED` and annotated `[ESCALATED: reconciliation conflict]`. When two or more candidates are escalated together by this pass, emit a shared `**Theme Group**:` line on each, exactly as pass 1 does.

Output: the final `AUTO_APPLY` set and the modified in-memory plan content. Classify each surviving `AUTO_APPLY` finding as `Semantic` or `Additive` per `.specify/templates/triage-classifier-criteria.md`'s auto-applied fix classification, and record the result on the finding as `**Classification**:` for the Auto-Applied section below.

**1d. Theme grouping for presented findings**: Theme grouping applies only to `PRESENTED` findings in the MUST-ADDRESS and SHOULD-CONSIDER tiers — MINOR findings are batched instead (1e), not theme-grouped.

Within each of those two tiers, dispatch a separate `Agent(model: "sonnet")` with all of that tier's presented findings. The agent:
- pre-filters candidates by location proximity — findings referencing the same plan section or the same requirement are candidates for grouping
- applies semantic judgment to the candidates — confirms they address the same underlying design question before grouping them
- leaves a candidate ungrouped when it's unclear whether it truly shares the theme (conservative bias)
- never groups a single finding by itself — a "group" of one is presented as an individual finding
- returns each group with a one-sentence theme summary

Persist each grouped finding's group membership inline using `**Theme Group**: {group-id} — "{theme-summary}"` on its own metadata line.

**1e. MINOR batching**: Batch every surviving MINOR-tier `PRESENTED` finding into a single end-of-queue decision point, with an option to expand the batch into individual findings. Resolution grouping among the batch's constituent findings does not run here — it runs later, at resolution time, in `speckit.review-interactive.md`'s step 6b. Escalated MINOR findings carrying a `**Theme Group**:` line from 1b/1c are excluded from this batch — they are presented as their own coordinated group instead.

**1f. Compute triage output**: Recompute `MUST_ADDRESS_COUNT`, `SHOULD_CONSIDER_COUNT`, and `MINOR_COUNT` from `PRESENTED` findings only (a finding pulled back by escalation counts in its tier). These post-triage counts supersede the pre-triage counts from Synthesize Findings for every downstream use — gate writing, terminal status, and the completion report.
- If the presented set is empty (`MUST_ADDRESS_COUNT + SHOULD_CONSIDER_COUNT + MINOR_COUNT == 0`) and at least one finding was auto-applied: set `TRIAGE_TERMINAL_STATUS = all_auto_applied`. The eventual confirmation to the user — skipped when every auto-applied finding's `**Classification**` is `Additive` (see the dispatching command's All-Auto-Applied Confirmation step) — must mention both the auto-applied count and the discarded count when it does run.
- If the presented set is empty and nothing was auto-applied (everything was discarded): proceed with a passed gate. When the total finding count is 20 or more, record a `**Triage Advisories**:` line in the Summary section noting the volume discarded — no confirmation is required since no artifact was modified. Set `TRIAGE_TERMINAL_STATUS = ok` on this branch as well.
- Otherwise: `TRIAGE_TERMINAL_STATUS = ok` (the normal interactive-queue path).

Prepare the triage summary for the findings file and the completion report: auto-applied fixes (ID + one-line description), discarded findings (ID + one-line reason), and the count of decision points remaining in the interactive queue. Compute this decision-point count as actual queue entries, not a raw finding sum: one per MUST-ADDRESS theme group or ungrouped MUST-ADDRESS finding, one per SHOULD-CONSIDER theme group or ungrouped SHOULD-CONSIDER finding, plus one if any MINOR finding survived triage. Carry this value (`DECISION_POINT_COUNT`) to the completion report rather than letting the dispatching command re-derive it from tier counts.

**1g. Update gate writing**: The Write Gate File and Pipeline State section below is now conditional on `TRIAGE_TERMINAL_STATUS`:
- When `TRIAGE_TERMINAL_STATUS == all_auto_applied`: skip that section's gate write entirely — the dispatching command writes the gate itself, after presenting the confirmation.
- Otherwise: run that section as usual, and pass `--auto-applied` to `write-review-gate-unified.sh` when at least one finding was auto-applied.

Disk-write order after triage is fixed: `review/review-findings.md` is written first (below), then the plan artifact (if any finding was auto-applied), then the gate file — never the reverse, so a crash between writes never leaves a gate with no matching findings file or audit trail.

## Write review-findings.md

Create the `review/` subdirectory under FEATURE_DIR if it does not exist (`mkdir -p`), then write to `FEATURE_DIR/review/review-findings.md` using this format:

```markdown
# Adversarial Review Findings

**Feature**: {feature name from branch/directory}
**Attempt**: {attempt_id}
**Review Type**: Secondary
**Date**: {ISO date}

| Reviewer | Status | Findings |
|---|---|---|
| {role} | {delivered \| delivered (count discrepancy) \| failed \| outstanding \| outstanding (no output)} | {N, or "—" for outstanding (no output)} |

**Agents Completed**: {N}/{PANEL_SIZE}

---

### MUST-ADDRESS ({count})

#### {ID}: {title}
**Agent**: {agent name(s)} · **Type**: {type}
**Violated Principle**: {principle identifier and title, e.g. "VI — Context-Window-Efficient Presets" — mandatory for Constitution Compliance findings, omit this line entirely for findings from any other agent}
**Disposition**: [PRESENTED] (also valid here: `[ESCALATED: reconciliation conflict]` — a finding pulled back from auto-apply)
{**Theme Group**: {group-id} — "{theme-summary}" — present only when this finding is a member of a theme group (2+ members)}

- {description point 1 — one key concern per bullet}
- {description point 2 — keep each bullet to 1-2 sentences max}

> **Evidence**: {specific spec/plan section reference}

**Recommendation**: {corrective action}

**Digest**: {≤160 chars — issue → recommended change}

- [ ] Resolved

---

### SHOULD-CONSIDER ({count})

#### {ID}: {title}
**Agent**: {agent name(s)} · **Type**: {type}
**Violated Principle**: {principle identifier and title, e.g. "VI — Context-Window-Efficient Presets" — mandatory for Constitution Compliance findings, omit this line entirely for findings from any other agent}
**Disposition**: [PRESENTED] (also valid here: `[ESCALATED: reconciliation conflict]` — a finding pulled back from auto-apply)
{**Theme Group**: {group-id} — "{theme-summary}" — present only when this finding is a member of a theme group (2+ members)}

- {description point 1 — one key concern per bullet}
- {description point 2 — keep each bullet to 1-2 sentences max}

> **Evidence**: {specific spec/plan section reference}

**Recommendation**: {corrective action}

**Digest**: {≤160 chars — issue → recommended change}

- [ ] Resolved

---

### MINOR ({count})

#### {ID}: {title}
**Agent**: {agent name(s)} · **Type**: {type}
**Violated Principle**: {principle identifier and title, e.g. "VI — Context-Window-Efficient Presets" — mandatory for Constitution Compliance findings, omit this line entirely for findings from any other agent}
**Disposition**: [PRESENTED] (also valid here: `[ESCALATED: reconciliation conflict]` — a finding pulled back from auto-apply)

- {description point 1 — one key concern per bullet}
- {description point 2 — keep each bullet to 1-2 sentences max}

> **Evidence**: {specific spec/plan section reference}

**Recommendation**: {corrective action}

**Digest**: {≤160 chars — issue → recommended change}

- [ ] Resolved

---

### Auto-Applied ({count})

#### {ID}: {title}
**Agent**: {agent name(s)} · **Type**: {type}
**Severity**: {SHOULD-CONSIDER | MINOR — matches the target section's heading label exactly; never MUST-ADDRESS, per the severity guard}
**Disposition**: [AUTO-APPLIED]
**Classification**: {Semantic | Additive — per .specify/templates/triage-classifier-criteria.md's auto-applied fix classification}

- {description point 1 — one key concern per bullet}
- {description point 2 — keep each bullet to 1-2 sentences max}

> **Evidence**: {specific spec/plan section reference}

**Recommendation**: {the fix that was applied}

**Digest**: {≤160 chars — issue → recommended change}

- [x] Resolved

---

### Discarded ({count})

#### {ID}: {title}
**Agent**: {agent name(s)} · **Type**: {type}
**Severity**: {SHOULD-CONSIDER | MINOR — matches the target section's heading label exactly}
**Disposition**: [DISCARDED: {one-line reason}]

---

### Summary

#### By Severity
| Severity | Count |
|----------|-------|
| MUST-ADDRESS | {N} |
| SHOULD-CONSIDER | {N} |
| MINOR | {N} |
| **Total** | **{N}** |

(Severity breakdown covers `PRESENTED` findings only — auto-applied and discarded findings are counted separately below.)

#### By Type
| Type | Count | MUST | SHOULD | MINOR |
|------|-------|------|--------|-------|
| Spec gap | {N} | {N} | {N} | {N} |
| Inconsistency | {N} | {N} | {N} | {N} |
| Design gap | {N} | {N} | {N} | {N} |
| Test gap | {N} | {N} | {N} | {N} |
| Existing debt | {N} | {N} | {N} | {N} |
| Risk | {N} | {N} | {N} | {N} |
| Scope | {N} | {N} | {N} | {N} |
| Premise | {N} | {N} | {N} | {N} |
(Omit rows with zero findings.)

(Like By Severity, By Type covers `PRESENTED` findings only — an auto-applied or discarded finding's type is not counted here until and unless it is restored to a severity section.)

#### By Triage Disposition
| Disposition | Count |
|-------------|-------|
| Auto-Applied | {N} |
| Discarded | {N} |
| Presented | {N} |
| Escalated | {N} |
| **Total** | **{N}** |

(Escalated is a subset of Presented — an escalated finding is counted in both rows — and is excluded from Total, which sums only Auto-Applied + Discarded + Presented.)

{**Triage Advisories**: {one line per advisory that fired — classifier-error and/or large-discard-set — omitted entirely when neither occurred}}

**Gate Status**: {PASSED | BLOCKED}
```

Formatting rules for findings:
- **The delivery table sits in the header block**, immediately after `**Date**` and above `**Agents Completed**` — evidence before the figure, per the wait script's own output-ordering rule. One row per roster entry from `manifest.json`, in roster order. The Findings column carries the readable finding count for a `delivered` row; the readable count followed by the marker's claim — `N (marker claimed M)`, the same two-part form the wait script's own table emits — for a `delivered (count discrepancy)` row; the marker's `finding_count` for `failed`; and `—` for both `outstanding` variants. A bare count on a discrepancy row would leave the discrepancy disclosed nowhere that survives the run, since the wait script's rendering of it goes only to transient stdout. This table is the sole degraded-coverage disclosure now — it replaces the retired single-role header line, which could only ever name one absent role.
- **Descriptions use bullet points**, not prose paragraphs. Each bullet captures one distinct concern in 1-2 sentences.
- **Metadata is compact**: Agent and Type share a single line, separated by `·`.
- **Violated Principle is a separate line, immediately below Agent/Type**, mandatory for findings from the Constitution Compliance agent (or any merged finding that includes it among originating agents) and omitted entirely for findings from every other agent. It carries the principle identifier and title verbatim from the agent's finding, so downstream tooling can extract it without parsing the description.
- **Disposition is a separate line**, immediately below Agent/Type (and below Violated Principle, when present) on findings in severity sections; immediately below **Severity** on findings in `### Auto-Applied`/`### Discarded` (see the next bullet) — on every finding in every section, including Auto-Applied and Discarded, where it is otherwise implicit from section placement. Valid values: `[PRESENTED]`, `[AUTO-APPLIED]`, `[DISCARDED: <reason>]`, `[ESCALATED: reconciliation conflict]`.
- **Severity is a separate line, immediately below Agent/Type**, on every finding in the `### Auto-Applied` and `### Discarded` sections only (Disposition then follows immediately below Severity in these two sections, per the bullet above). These findings no longer live under a severity heading, so the tier must be recorded explicitly: it is what lets the `all_auto_applied` rejection path in `speckit.review-plan.md` restore an auto-applied finding to its correct original severity section.
- **An Auto-Applied finding carries every field a severity-section finding has** (description, Evidence, Recommendation, Digest, Resolved checkbox), not a stripped-down summary — restoring it to a severity section on rejection (the `all_auto_applied` reject path in `speckit.review-plan.md`) must reuse this content unchanged, not reconstitute it from a one-line description that doesn't exist.
- **Theme Group is a separate line**, immediately below Disposition, present on MUST-ADDRESS/SHOULD-CONSIDER findings that are members of a theme group (1d), and on MINOR findings escalated together per 1b/1c (exempted from the flat MINOR batch in that case, per 1e). A MINOR finding that was never an auto-apply candidate, or was discarded rather than escalated, never carries this line — it is batched (1e), not theme-grouped.
- **Section ordering is fixed**: `### MUST-ADDRESS` → `### SHOULD-CONSIDER` → `### MINOR` → `### Auto-Applied` → `### Discarded` → `### Summary`. Plan review has no Plan-deferred section — that classification applies only to spec review.
- **Omit `### SHOULD-CONSIDER`/`### MINOR` when their count is zero after triage** — the same convention the Summary table already uses for zero-count type rows, extended to these two severity sections. An omitted section is not an error; it means triage moved every finding in that tier elsewhere. **`### MUST-ADDRESS` is never omitted, even at zero count** — always emit it (as `### MUST-ADDRESS (0)` with no finding blocks when empty) — `speckit.review-interactive.md`'s file validation hard-requires this heading to exist.
- **Evidence uses a blockquote** (`>`) to visually separate it from the description.
- **Horizontal rules** (`---`) separate individual findings for visual breathing room.
- **Digest is a condensed restatement**, not a quotation — one line carrying both the issue and the recommended change, ≤160 characters. It is what the blocked-gate report shows in place of the full finding.
- **Gate Status is derived here, not deferred**: `BLOCKED` when post-triage `MUST_ADDRESS_COUNT > 0`, otherwise `PASSED`. Compute it directly from the triage output — it must not wait on the Write Gate File and Pipeline State section, which runs after this one and is skipped entirely on the `all_auto_applied` path.
- **Triage Advisories is a conditional line** in `### Summary`, immediately above `**Gate Status**`, present only when the classifier hit an error on a finding (1a) or the all-discarded soft advisory fired (1f) — one line per advisory, omitted entirely when neither occurred. This is what `speckit.review-plan.md` step 7 reads to surface these advisories in the completion report.

If no findings at all — zero findings across every tier, with nothing auto-applied or discarded — write: "No findings — spec/plan passed adversarial review." with gate status PASSED, omitting the section structure (including `### MUST-ADDRESS`) entirely. The never-omit rule above exists solely so `speckit.review-interactive.md`'s validation always finds the heading it hard-requires; a gate that always passes on this path never dispatches interactive resolution, so that consumer never reads this file and the rule doesn't apply here. **The header block (Feature/Attempt/Review Type/Date/delivery table/Agents Completed) is still written** — only the section structure below it is omitted; the dispatching command's degraded-quorum disclosure check still needs it even when there are no findings to report.

## Write Plan Artifact

If any finding was auto-applied, write the modified plan content from Triage step 1c to `plan.md` on disk now — after `review/review-findings.md` (above) and before the gate file (below), so a crash between writes never leaves a gate with no matching findings file or audit trail.

## Write Gate File and Pipeline State

**Skip this entire section when `TRIAGE_TERMINAL_STATUS == all_auto_applied`.** The dispatching command writes the gate itself after presenting the auto-applied/discarded confirmation — writing it here would race that write. Proceed straight to Write Synthesis Marker.

Otherwise, determine status and write using the unified helper:
```bash
# Determine status
STATUS="passed"
[[ "$MUST_ADDRESS_COUNT" -gt 0 ]] && STATUS="blocked"

# Determine partial coverage
PARTIAL_FLAG=()
[[ "$AGENTS_COMPLETED" -lt "$PANEL_SIZE" ]] && PARTIAL_FLAG=(--partial)

# Write gate file and pipeline state using unified helper
speckit run write-review-gate-unified.sh \
  --gate-type "secondary" \
  --status "$STATUS" \
  --must-address "$MUST_ADDRESS_COUNT" \
  --should-consider "$SHOULD_CONSIDER_COUNT" \
  --minor "$MINOR_COUNT" \
  --agents-completed "$AGENTS_COMPLETED" \
  --panel-size "$PANEL_SIZE" \
  --quorum-met true \
  --attempt-id "$ATTEMPT_ID" \
  "${PARTIAL_FLAG[@]}"
  # Append --auto-applied when at least one finding was auto-applied this run
```

**Discharge any pending re-review recommendation.** A prior interactive resolution session may have recorded that this review should be re-run. This stage has now re-run it, so that recommendation is spent — if `PENDING_RECOMMENDATION` (received as input) is `pending`, write:

```bash
speckit run write-pipeline-state.sh review-recommendation \
  gate_type=secondary status=discharged command="/speckit-review-plan"
```

Leaving it pending would resurface the same recommendation after the review it asked for has already happened.

## Write Synthesis Marker

The last thing this template writes on every path — `{ATTEMPT_DIR}/synthesis.done.json`, after the gate (when one was written this run):

```json
{
  "attempt_id": "{ATTEMPT_ID}",
  "status": "ok",
  "must_address_count": 0,
  "should_consider_count": 0,
  "minor_count": 0,
  "decision_point_count": 0,
  "agents_completed": 0,
  "panel_size": 0,
  "gate_written": true,
  "pre_aggregation_status": "skipped"
}
```

`status` carries the terminal outcome — `ok`, `all_auto_applied`, `quorum_failed`, or `error` — the same vocabulary the Terminal Status line below uses. The count fields use the post-triage values (`MUST_ADDRESS_COUNT`, `SHOULD_CONSIDER_COUNT`, `MINOR_COUNT`, `DECISION_POINT_COUNT`) on the `ok` path, and are `0` on every other path — `all_auto_applied`'s presented set is empty by definition, and `quorum_failed`/`error` never reach triage. `gate_written` is `false` only on `all_auto_applied` (the dispatching command writes it) and on the precondition-refusal `error` path; every other path writes `true`. This is the record the dispatching command's outcome check reads — never the prose line below, which a killed or malformed return cannot be distinguished from.

`pre_aggregation_status` is derived here from the two forwarded bindings — nothing upstream pre-computes it: `success` when `AGGREGATE_PATH` was set and its file existed (read for finding content per the Finding content source rule above), `failed` when `PRE_AGGREGATE` was `true` but `AGGREGATE_PATH` was absent or unreadable, and `skipped` when `PRE_AGGREGATE` was not set to `true` at all (always true for spec review, which never sets it). A `failed` value is a durable diagnostic signal — the dispatching command's completion report should surface it, since the run still proceeded correctly (on the individual-finding-files fallback) and nothing else on disk records that the aggregate step degraded.

## Terminal Status

Every exit path — success or failure — MUST end the response with this line, and nothing after it:

```
review_pipeline_status: <ok|quorum_failed|error|all_auto_applied>
```

| Value | When |
|-------|------|
| `ok` | Quorum met, synthesis complete, `review/review-findings.md` and `review/review-gate.json` written |
| `all_auto_applied` | All findings auto-applied or discarded, empty interactive queue. Dispatching command handles confirmation and gate writing. |
| `quorum_failed` | Insufficient agents returned; `review/review-gate.json` written with `quorum_met: false`, no `review/review-findings.md` |
| `error` | Unexpected failure (including primary-artifact archival failure or the wait-conclusion precondition); artifacts may be incomplete or absent |

The dispatching command's outcome check reads `synthesis.done.json`, not this line — a killed invocation can leave this line unemitted with no way to distinguish it from a hung one. This line remains for the human-legible transcript only.
