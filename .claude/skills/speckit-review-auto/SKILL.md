---
name: speckit-review-auto
description: 'SpecKit internal: auto-resolve convergence loop for `/speckit-review`.'
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:meta
  meta_preset_strategy: replace
user-invocable: true
disable-model-invocation: false
---



# Speckit Review Auto Skill

## Workspace Check

**Workspace check (MANDATORY)**: Run `speckit run require-workspace.sh`. This resolves the workspace from any subdirectory and produces the same fixed message when there is no workspace above the current directory. On a non-zero exit, relay its stderr output to the user verbatim — do not paraphrase, reword, summarize, or translate it; do not prepend or append anything (no preface, heading, or attribution such as "require-workspace.sh failed:"); do not name the script, the command, the exit code, or any internal path — then halt. On exit 0, proceed silently to the next check.

## Context Loading

Parse the dispatch prompt for these variables:
- **FEATURE_DIR**: Feature directory path
- **FEATURE_SPEC**: Path to spec.md
- **GATE_TYPE**: `primary` or `secondary`
- **AGENTS_COMPLETED**: Number of agents that completed
- **MUST_ADDRESS_COUNT**: Count of MUST-ADDRESS findings
- **SHOULD_CONSIDER_COUNT**: Count of SHOULD-CONSIDER findings
- **MINOR_COUNT**: Count of MINOR findings
- **DISPATCH_ORIGIN**: `autonomous` when the dispatching stage reached this loop from its own unattended fast path, `interactive` when a user chose it from that stage's gate menu
- **PANEL_SIZE**: The number of agents in the dispatching stage's own full review panel. "Full Adversarial Pass" below supersedes this value for its own dispatch with the size its own freshly-minted attempt manifest records, since risk-based panel sizing must be re-resolved against the artifact's current frontmatter, not carried forward as a literal
- **ATTEMPT_ID**, **ATTEMPT_DIR**: Not parsed from the dispatch prompt like the rest of this list — minted locally by "Full Adversarial Pass"'s own `review-attempt.sh init --gate-type full-pass` call, declared here for the same reason `PANEL_SIZE` is: every downstream reference to them needs one place stating where they come from

Read `{FEATURE_DIR}/review/review-findings.md` to reconstruct synthesis state. Parse all findings from the MUST-ADDRESS, SHOULD-CONSIDER, and MINOR sections. Note: Plan-deferred findings are in a separate section and are NOT auto-fixed.

**These three sections hold only findings synthesis has already triaged as `PRESENTED`.** Synthesis classifies every finding as `AUTO_APPLY`, `DISCARD`, or `PRESENTED` before this file ever runs; `AUTO_APPLY` findings are fixed and `DISCARD` findings are dropped during synthesis itself. The `### Auto-Applied` and `### Discarded` sections of `review/review-findings.md` record those outcomes and are never parsed by this file — nothing here needs to skip or filter them. Findings this loop's own re-validation loop generates under `### RE-VALIDATION (Round N)` are a separate case: triage runs once, during the original synthesis pass, so re-validation findings are never subject to it — they enter this loop's resolution queue directly.

`DISPATCH_ORIGIN` changes nothing this loop does to the artifacts. On either value the gate stays blocked when the loop gives up, and this loop never records an override. It is carried so the dispatching stage can tell, after this loop returns, whether a human is waiting on a menu.

## Section Order

This file runs its sections in exactly this order, and the order is load-bearing:

1. the convergence loop,
2. the Plan Staleness Check,
3. re-validation,
4. the gate write,
5. the best-effort SHOULD-CONSIDER and MINOR pass.

The best-effort pass runs **after** the gate is written, never before it. A recorded gate is a statement about an artifact that was validated; a best-effort edit is unvalidated by construction, so an artifact holding one has moved past the state the gate describes. Writing the gate first is what keeps the recorded verdict true of the thing it was computed over.

## Progress Reporting — MANDATORY

The convergence loop dispatches a single targeted agent on every iteration and the full adversarial panel once, when an iteration's fixes are all confirmed — the single-agent dispatch is fast; the full-panel dispatch can exceed seven minutes. Every `LOG:` line below is **user-facing output, not pseudocode commentary**: emit it to the user at the moment the pseudocode reaches it. Do not batch these to the end of the run and do not wait for the loop to exit.

- **Before entering the loop**, state how many MUST-ADDRESS findings will be attempted, that each iteration's claimed fixes are checked by a single targeted agent, that the full adversarial panel runs once after those rounds converge, and that the loop may run for several minutes.
- **When a multi-minute dispatch begins**, say so before it starts — not only when it returns. This applies to the full adversarial pass and to every re-validation round.
- **At every iteration boundary and every re-validation round boundary**, report the MUST-ADDRESS count before and after.
- **When the loop exits** — whichever give-up exit fired: iteration exhaustion, the non-convergent stop, the `GATE_BLOCKED`-forced block, the re-validation cap, the full-pass-findings case, or the discard exit — state which findings remain unresolved and what state the artifacts were left in.

**No `auto_mode` suppression.** Unlike the plan orientation, this output is a record rather than a prompt: in an autonomous run the transcript is the only account of what the loop did to the artifacts. Emit it in every mode.

## Compose, Check, Write

Every path in this file that turns an accepted finding into a change on disk runs this body — the convergence loop, the best-effort pass, and the re-validation loop's inline fix application. None of them may write an artifact any other way.

Fixes are never applied per finding. They are composed in memory per artifact, the composed result is read back and checked, and only then is the artifact written. Editing per finding gives no point at which the combined result exists to be read: two fixes that each make sense alone can compose into an artifact that contradicts itself, and nothing notices.

1. **Group interacting findings before planning any fix.** Dispatch a `general-purpose` Agent (`model: "sonnet"`) to run `Resolution grouping`:

   ```
   Read and execute `.specify/templates/resolution-grouping.md`.

   ACCEPTED=<the findings this pass will resolve, each with ID, tier, target artifact, evidence, recommendation>
   TIER=<the tier this pass is resolving>
   CANDIDATE_SET=<the artifacts this gate may write: spec.md at a primary gate; spec.md,
   plan.md, research.md and the files under contracts/ at a secondary gate>

   Return GROUPS: for each group, its member finding IDs, the matched signal, and the
   artifacts it spans.
   ```

   Findings whose fixes touch the same region, or the same rule stated in two places, are then resolved as one coordinated fix instead of as independent patches racing each other into the same artifact.
   **If the agent reports the template is not present, stop.** Do not compose and do not write any artifact; report in plain language that the interaction check could not be run and name the file that is absent, and do not record a passing gate. Nobody is watching this run, so a silent degradation to ungrouped resolution would leave no trace that the interaction step was skipped.
2. **Plan the fixes without applying them.** For each finding being resolved in this pass, determine its target artifact and the change it requires. For a group of two or more, plan one coordinated change satisfying every member together, rather than one change per member. Do not edit anything yet.
3. **Compose per artifact.** For each target artifact that received at least one fix, build its full new content in memory from its pre-fix content plus every fix routed to it. Compose a coordinated fix once per group and apply it to every artifact that group spans, or to none of them. Retain that pre-fix content for the rest of this pass — the check needs it to tell a defect this pass introduced from one the artifact already had. Note which regions each fix wrote, which findings contributed to each artifact, and which groups span it.
4. **Run the `Holistic reconciliation pass`** by dispatching a `general-purpose` Agent (`model: "opus"`):

   ```
   Read and execute `.specify/templates/holistic-reconciliation.md`.

   COMPOSED=<map: artifact path → candidate content after all fixes applied>
   BASELINES=<map: artifact path → pre-fix content>
   WRITTEN_REGIONS=<map: artifact path → spans this run wrote>
   CONTRIBUTING=<map: artifact path → finding IDs>
   CANDIDATE_SET=<this gate's declared artifacts — same set bound for grouping in step 1>
   USER_PRESENT=false
   GROUPS=<groups from step 1>

   For each artifact, report: defects found (quoted, classified, attributed), then outcome
   (clean / repaired / unrepairable).
   ```

   This path is unattended by construction, so bind its user-present input to false. Pass the groups formed above as its groups input, so a coordinated fix is one repair unit rather than several.
   **Bind the candidate set to this gate's declared artifacts** — the same set bound for grouping in step 1. This is what lets the check reach a rule a fix in this pass changed that a counterpart artifact still states in its superseded form. Without it that class cannot fire at all: a counterpart receives no fix of its own, so comparing it against its own pre-fix content finds nothing.
   **If the agent reports the template is not present, stop.** Do not write any artifact, report in plain language that the consistency check could not be run and name the file that is absent, and do not record a passing gate. Writing without the check is precisely the unchecked write the check exists to prevent, so this branch fails closed.
5. **On a clean or repaired outcome**: state every defect found before stating the outcome, name any accepted fix a repair altered or removed, then write the artifact and mark each contributing finding resolved in `review/review-findings.md`. Set `RUN_ARTIFACTS_WRITTEN = true` the first time any pass in this run reaches this point, and never clear it afterwards.
6. **On an unrepairable outcome**: discard every fix for that artifact in this pass and do not write it. Leave the contributing findings unresolved with their checkboxes unchecked, name them in this pass's reporting, and set `GATE_BLOCKED = true` where at least one contributing finding is of a blocking tier — a discard whose contributing findings are all of an optional tier leaves the gate condition untouched, because nothing was written and the gate does not rest on those fixes. Where the discarded fix was a coordinated one, discard it from every artifact it spans — half a coordinated fix on disk is the contradiction this check exists to prevent. Every other artifact that group spans whose own check passed is recomposed without the withdrawn fix and still written, so its unrelated fixes land.
7. **Order the bookkeeping after every outcome.** Findings-file checkbox updates and log appends happen only once every composed artifact in this pass has an outcome. Emitting a checkbox update earlier means a discard skips the artifact write while the findings file already records the finding resolved — leaving the file and the artifact disagreeing, and the next round reading the finding as already fixed.
8. **Record the outcomes durably.** Append the defects found, the repairs applied, and the discards to `{FEATURE_DIR}/auto-resolution-log.md` as well as emitting them to the user. Nobody is watching this run, so the log is the only surviving account of what the check decided.

`GATE_BLOCKED` is run-scoped and sticky. Once any pass sets it, it stays set: no later assignment of a finding count clears it, and the gate for this run may not be recorded as passed. A discarded fix leaves its finding unresolved, and if a later validation round fails to resurface that finding, a recount alone would show zero blocking findings and pass the gate over work that was thrown away.

**Retention is scoped to the run, not to the pass.** Every give-up exit — including convergence exhaustion — retains every fix that reached disk, whether or not that fix's own iteration ultimately converged. The retention guarantee is scoped to the run, not to any single pass: nothing this loop does, on any exit, discards a change that a consistency check already accepted. `RUN_ARTIFACTS_WRITTEN` is what records that this happened — it is set the first time step 5 above writes anything and is never cleared, unlike the per-iteration `ARTIFACTS_WRITTEN` counter, which is re-zeroed at the top of every iteration.

## Constitution MUST Compliance Re-check

`IS_CONSTITUTION_MUST` identifies a governance-sensitive finding — the same dual-signal check the interactive review and verify presets use, so a finding classified as constitution-critical reads identically whether a human or this loop resolves it:

```
IS_CONSTITUTION_MUST = finding.severity == "MUST-ADDRESS" AND (
  finding.id starts with "CC-"
  OR finding.agent_name contains "Constitution Compliance"
  OR finding.agent_name contains "Constitution Validator"
)
```

Agent-name matching uses **contains** semantics, not exact-match. Where the match is ambiguous, default to the standard, non-escalation path rather than guessing.

**Constitution fixes stay inside the shared body — no per-finding bypass.** A constitution MUST finding is composed and checked through the same "Compose, Check, Write" body and the same `Holistic reconciliation pass` as every other MUST-ADDRESS finding this iteration. Nothing in this section pulls a constitution finding out for an independent, per-finding disk write — doing so would bypass holistic reconciliation, use the wrong validation mechanism, and create an asymmetry between what review and verify do with the same class of finding. The only changes this section makes to the shared body's flow are the ordering below and one additional gate before the write.

**Constitution findings are composed and checked first within an iteration.** When an iteration's MUST-ADDRESS findings include one or more `IS_CONSTITUTION_MUST` findings, compose and check them first, as their own sub-batch, through one invocation of "Compose, Check, Write" — then compose and check the remaining MUST-ADDRESS findings through a second invocation of the same body. This is two sequential invocations of one shared body, not a finding extracted from it. When no constitution MUST finding is present this iteration, run the body once, over the full set, exactly as before.

**The re-check gates the write — nothing reaches disk until it passes.** For the constitution sub-batch's invocation, after the `Holistic reconciliation pass` (step 4) returns a clean or repaired outcome for an artifact, run this re-check on the composed candidate content — the content step 5 is about to write — before step 5 runs:

Dispatch a `general-purpose` Agent (`model: "opus"`):

Prompt:
"""
You are checking whether a candidate artifact — composed but not yet written — complies with the project constitution.

**Input**:
- The full candidate content of the artifact: {composed candidate content}
- The full constitution: {constitution content from `.specify/memory/constitution.md`}

**Report**:
- `PASS` if the candidate complies with every constitution principle.
- Otherwise, itemize each violation: principle identifier, title, and a one-sentence description.
"""

**Success and failure, per constitution finding.**
- **Success**: the violation this finding's fix targeted is no longer present in the re-check's output, AND no new violation was introduced by the fix.
- **Pre-existing violations do not count as a re-check failure.** A violation the re-check reports that was already present in the artifact before this iteration's fix is pre-existing — it does not fail the re-check. Only a violation absent before the fix and present after (the fix "worsened" compliance) counts as failure.

**On failure**: add the finding's ID to `PROPAGATED_CONSTITUTION`, set `GATE_BLOCKED = true` — the existing sticky, run-scoped flag `Compose, Check, Write` already defines; this reuses it rather than introducing a parallel flag — exclude the finding from every subsequent iteration's MUST-ADDRESS set, and discard its fix from the composed candidate before step 5 writes anything. "Discard" means exactly that: the fix never reaches the artifact. There is no partial write and no revert-from-disk to perform, because the write has not happened yet at the point this check runs.

A `GATE_BLOCKED` set here suppresses the Full Adversarial Pass exactly as any other `GATE_BLOCKED=true` does, through the same gate-blocked branch of the loop's five outcomes below — no parallel suppression mechanism exists for a constitution-triggered block.

**RV-prefixed findings are exempt from this check, on purpose.** A finding with the `RV-` prefix and agent name "Re-Validation" never satisfies `IS_CONSTITUTION_MUST`, even when its content concerns constitution compliance — it is a fix-introduction artifact from the re-validation loop and gets the same one-fix-attempt treatment as any other re-validation finding, regardless of category. No special-case logic routes it into this check.

## Targeted Validation

Every iteration of the convergence loop runs this body instead of re-reviewing the whole artifact. Its input is the set of findings that iteration's `Compose, Check, Write` pass actually wrote a fix for — never the full finding list, and never the artifact as a whole.

Dispatch a **single** agent with `model: "opus"` and `subagent_type: "general-purpose"`:

Prompt:
"""
You are checking whether a specific set of claimed fixes actually resolved the findings they were written for. You are NOT reviewing the artifact as a whole and you are NOT looking for new issues.

**Input**:
- The claimed fixes: {for each, the finding's original text, the artifact it was written to, and the region that changed}
- The current content of each artifact that changed: {content}

**For each claimed fix, report exactly one of**:
- `CONFIRMED` — the change resolves the finding as stated.
- `NOT_FIXED` — the change does not resolve the finding; the finding still applies to the current content.
- `INDETERMINATE` — you cannot tell from what you were given. Use this when the evidence is ambiguous, when the fix's effect depends on another finding's fix you were not shown, or when the finding as stated is too broad to adjudicate against this region alone.

Report `INDETERMINATE` rather than guessing. A wrong `NOT_FIXED` reads downstream as proof that this loop cannot make progress.

**Output format**: one line per claimed fix — `{finding ID}: {CONFIRMED|NOT_FIXED|INDETERMINATE} — {one sentence of evidence}`.
"""

`CONFIRMED_THIS_ITERATION` is the count of claimed fixes reported `CONFIRMED`. Only `CONFIRMED` decrements `OUTSTANDING_MUST_ADDRESS_COUNT`; `NOT_FIXED` and `INDETERMINATE` both leave it where it is.

The three-way split does not change **when** the loop stops — an iteration that confirms nothing stops the loop whether its non-confirmations were all `NOT_FIXED`, all `INDETERMINATE`, or a mix. What it changes is what the triage says: a `NOT_FIXED` finding is one this loop actively disproved a fix for, an `INDETERMINATE` one is a judgment call a single narrowly-scoped agent could not make. Reporting both as a flat "unresolved" would hand the user a verdict the run never earned.

Targeted validation can only confirm or fail to confirm the fixes it was given. It cannot surface findings elsewhere in the artifact, so it can never raise `OUTSTANDING_MUST_ADDRESS_COUNT` — the only failure mode is zero reduction.

## Full Adversarial Pass

The assurance pass behind every passing verdict. It is a distinct dispatch, not a relabelled final iteration: it writes its findings to the attempt directory and applies no fixes.

It has two trigger points, and both run this same body:
- the convergence loop's terminal iteration, when every claimed fix was confirmed and `OUTSTANDING_MUST_ADDRESS_COUNT` reached 0 — slug `terminal-iteration`;
- re-validation, when re-validation applied at least one edit of its own — slug `post-re-validation`.

**Script resolution.** Before minting anything, confirm `.specify/scripts/bash/review-attempt.sh` and `.specify/scripts/bash/review-wait.sh` are present. If either is absent, halt with exactly:

> The reviewer templates appear to be out of date relative to the review command — no reviewer produced any output. Re-run `speckit init` in this project to reinstall, then re-run the review.

Never surface the raw shell error a missing script would otherwise produce. This pass is a hard precondition for a passing gate under `--auto`, so a stale install must fail with the adopter-facing remedy here just as it does on the two review commands' own entry paths.

**Attempt.** Mint an attempt for this pass, distinct from any attempt the dispatching review command holds:

```bash
speckit run review-attempt.sh init \
  --gate-type full-pass \
  --roster "<the comma-joined pairs the Panel step below resolves>" \
  --attended false
```

`--gate-type full-pass` keeps this attempt from ever being a `resume` candidate for the review that dispatched this loop. Capture `ATTEMPT_ID`, `ATTEMPT_DIR`, `PANEL_SIZE`, `QUORUM_REQUIRED`, `DEADLINE_EPOCH` from stdout — `PANEL_SIZE` here supersedes the value Context Loading declared: the freshly-minted manifest is the authority for this pass's own dispatch, not the literal the dispatching stage passed in. On exit 3, report the infrastructure error verbatim from stderr and Run "Give-Up Exit" — this pass cannot proceed without a location to write into.

**Panel.** Read `.specify/templates/review-spec-panel-prompts.md` when `GATE_TYPE` is `primary`, or `.specify/templates/review-plan-panel-prompts.md` when it is `secondary`, for its Panel Composition section — the sizing table and complexity-derivation rule live there (the plan template points back at the spec template's own sizing table for its base panel). Resolve the base panel identically for both gate types:

1. Parse the spec's `risk` frontmatter (default `medium` if absent or unrecognized).
2. Parse the spec's `complexity` frontmatter, if present.
3. Count `FR_COUNT` — the number of distinct base `FR-###` identifiers under the spec's `## Requirements` section (0 if the section is absent), matching `FR-\d+` and deduplicating suffixed variants (e.g. a lettered suffix like `FR-###a`/`FR-###b` counts once toward its shared base `FR-###`).
4. If `complexity` was absent in step 2, derive it from `FR_COUNT`: `complex` when `FR_COUNT > 10`, `standard` otherwise. If frontmatter explicitly set a complexity value, honor it regardless of `FR_COUNT`.
5. Look up the base panel size and role list from the sizing table, keyed on `complexity` × `risk`.
6. Select roles from the looked-up list in priority order — Correctness first, Coverage second, Risk third — up to the looked-up panel size.
7. If `risk` is `high` or `complexity` is `complex`: dispatch `CR` with its premise-brief flag set. Otherwise, if the looked-up panel size is 1: dispatch `CR` with its broadened-brief flag set instead.

For a `secondary` gate only, after the base panel above is resolved: add Constitution Compliance (CC) as a standalone agent when `.specify/memory/constitution.md` exists and does not contain `<!-- speckit:constitution:placeholder -->`. This can raise the panel to 4 agents; CC is never counted against or traded off with the base panel size above.

Build a `prefix:role` pair for each role in scope, in the template's own listed order, joined by commas — this is the `--roster` value the Attempt step above passes to `init`, and the set of roles dispatched below. Do not hardcode the pairs here; re-deriving them from the template on every run is what keeps this pass in sync with a future edit to the sizing table.

1. Announce the dispatch before it starts: `LOG: "Dispatching the full adversarial panel ({PANEL_SIZE} agents) over the final artifacts. This dispatch takes several minutes."`
2. For each role brief in scope, compose its prompt per the panel template's own instructions — including its conditional search-instruction append — filling the bindings `review-agent-prompt-base.md`'s own INPUTS table declares (`ATTEMPT_ID`, `ATTEMPT_DIR`, `PREFIX`, `ROLE`, `FEATURE_SPEC`, `IMPL_PLAN` when `GATE_TYPE` is `secondary`, `CONSTITUTION` when it exists, `ENRICHMENT` when it exists, `EXPLORATION` when it exists) — the same conditional bindings the dispatching review command's own panel dispatch resolves. Send all `Agent(general-purpose)` calls for the resolved panel **in one message**, using the same model tier the dispatching review command's own panel dispatch used. Do not wait on their return value — delivery is tracked on disk, exactly as the dispatching command's own panel is.
3. **Wait.** This loop is dispatched via `Skill()`, which has no responder attached — the wait below is **always unattended**, so the quorum verdict is what decides the ceiling outcome on this path; there is no attended branch to fall back to the way the dispatching review command has one.

   ```bash
   speckit run review-wait.sh --attempt-dir "$ATTEMPT_DIR" --expect reviewers
   ```

   Relay its stdout verbatim to the user before acting on the token. Every one of the six outcomes below resolves to a re-invocation or a step-4 continuation — none may fall through unhandled:

   | Token | Action |
   |---|---|
   | No token at all (killed invocation) | Re-invoke the same wait call unchanged. Absence is never an outcome. |
   | `in_progress` | Re-invoke the same wait call unchanged. Never proceed past this token. |
   | `no_artifacts` | Total contract break. `review-attempt.sh abandon --attempt-dir "$ATTEMPT_DIR" --reason infra-failure --coverage "0/$PANEL_SIZE"`; disclose the retained attempt directory; set `FULL_PASS_AGENTS_COMPLETED=0`; continue to step 4 with `status=partial`. |
   | `infra_error` | Same handling as `no_artifacts`. |
   | `all_delivered` | Continue to step 4 with `status=complete` and `FULL_PASS_AGENTS_COMPLETED=PANEL_SIZE`. |
   | `ceiling_reached` | Parse `FULL_PASS_AGENTS_COMPLETED` from the relayed stdout's `Coverage: N/M reviewers delivered.` line, exactly as the dispatching command's own ceiling handling does. `review-attempt.sh abandon --attempt-dir "$ATTEMPT_DIR" --reason ceiling --coverage "$FULL_PASS_AGENTS_COMPLETED/$PANEL_SIZE"`; disclose the retained attempt directory; continue to step 4 with `status=partial` **whatever the quorum verdict says** — this pass has no attended branch and no blocked-gate path of its own; the precondition in "Update Gate on Success" below is what a partial coverage figure here ultimately routes through. That is the quorum rule restated for this path: since this loop is always unattended, it is what decides the outcome here or it does not exist on this path at all. |

4. Immediately after the wait concludes, record that it ran:

```bash
speckit run write-pipeline-state.sh review-full-pass \
  gate_type="$GATE_TYPE" \
  status="<complete|partial>" \
  artifact_state="<terminal-iteration|post-re-validation>" \
  agents="$FULL_PASS_AGENTS_COMPLETED"
```

5. Set `FULL_PASS_MUST_ADDRESS` to the number of MUST-ADDRESS findings read from `{ATTEMPT_DIR}/findings/` among the reviewers that delivered, and append them to `review/review-findings.md` under a `### FULL ADVERSARIAL PASS` section.
6. **Clean up this pass's own attempt, unconditionally, before taking either branch below** — once a branch below runs "Give-Up Exit" it does not return here. This pass writes no gate of its own — the only gate in play is the *stage's*, and per "Gate identity" below it carries the dispatching review's own `attempt_id`, never this pass's. `--gate-file` can therefore never be satisfied here, so this pass writes its own completion marker into its attempt directory and substitutes it:

   ```bash
   jq -n --arg attempt_id "$ATTEMPT_ID" \
         --argjson agents_completed "$FULL_PASS_AGENTS_COMPLETED" \
         --argjson panel_size "$PANEL_SIZE" \
         '{attempt_id: $attempt_id, agents_completed: $agents_completed, panel_size: $panel_size}' \
         > "$ATTEMPT_DIR/full-pass.done.json"

   speckit run review-attempt.sh cleanup \
     --attempt-dir "$ATTEMPT_DIR" \
     --no-gate \
     --completion-marker "$ATTEMPT_DIR/full-pass.done.json"
   ```

   The marker carries the same three fields `--gate-file` would otherwise read: `attempt_id` for the attribution check, `agents_completed` and `panel_size` for the coverage refusal. On a `status=partial` run this call refuses (exit 4) on that coverage refusal and leaves the directory in place — already disclosed above — so every `--auto` run either removes its own full-pass attempt directory at full coverage or retains a disclosed one; neither leaks silently.
7. If `status == complete` and `FULL_PASS_MUST_ADDRESS == 0`, the pass is clean — continue with the section that triggered it.
8. If `FULL_PASS_MUST_ADDRESS > 0`, whatever `status` is, this run is over. Emit the heading `### FULL-PASS FINDINGS` followed by the pass's own finding list — read from disk, never from an agent's returned text — then Run "Give-Up Exit". Do not loop back into another convergence iteration: the targeted rounds already converged, and the iteration budget does not carry a retry for findings discovered after convergence.
9. If `status == partial` and `FULL_PASS_MUST_ADDRESS == 0`, continue with the section that triggered it exactly as step 7 does — the precondition in "Update Gate on Success" below is what refuses a passing gate on this path, not this step.

Write this record **before** the gate write that depends on it, not after. The gate write below reads it as a precondition, and a precondition checked against a record that has not been written yet is not a precondition.

**Gate identity.** The stage gate — written by "Give-Up Exit" or "Update Gate on Success" below — carries the **dispatching review command's** `attempt_id`, read fresh from the existing `review/review-gate.json` at write time, never this pass's own `ATTEMPT_ID` minted above. The dispatching command's own outcome check reads that gate's `attempt_id` against its own attempt; stamping this pass's id there instead would make the gate read as "not yet written" to the command that is waiting on it.

## Propagate Unresolved Constitution Findings

Runs once, immediately after the convergence loop exits and before Give-Up Exit's gate write. `PROPAGATED_CONSTITUTION` is non-empty only when the re-check above already set `GATE_BLOCKED = true`, so this section always runs ahead of a blocked gate, never ahead of a passing one — there is no ordering conflict with the Full Adversarial Pass, which a `GATE_BLOCKED=true` already suppresses.

If `PROPAGATED_CONSTITUTION` is empty, remove any prior instance of the section below from `review/review-findings.md` if one is present — a clean run means nothing remains propagated — and skip the rest of this section.

If `PROPAGATED_CONSTITUTION` is non-empty, append this section to `{FEATURE_DIR}/review/review-findings.md` — never to `plan.md`, which `/speckit-plan` regenerates and would silently discard the section — replacing any prior instance of the same heading rather than duplicating it:

```markdown
## ⚠️ Unresolved Constitution Compliance

The following constitution violations could not be resolved automatically. Each
received one fix attempt with a full compliance re-check. The violations persist
and require manual resolution.

| Finding | Principle | Auto-fix attempted | Why it persists |
|---------|-----------|-------------------|-----------------|
| {ID} | {principle identifier}: {title} | Yes | {re-check failure reason} |
```

**This section is informational only.** No downstream stage — `/speckit-tasks`, `/speckit-implement`, or any other — reads or acts on it. It exists so a human reviewing `review/review-findings.md` later sees what this run could not resolve; nothing in the pipeline treats its presence or absence as an input.

**Lifecycle**: replaced, never duplicated, on a rerun that still has unresolved constitution findings, and removed entirely the first time a run resolves everything — it is never left stale describing a state a later run has since fixed.

Then record the propagation in pipeline state:

```bash
speckit run write-pipeline-state.sh review-constitution-propagated \
  gate_type="$GATE_TYPE" \
  constitution_must_propagated=true \
  constitution_must_count="<len(PROPAGATED_CONSTITUTION)>"
```

## Give-Up Exit

Every exit that leaves this run without a passing verdict runs this body, in this order. There are six: convergence exhaustion, the non-convergent stop, the `GATE_BLOCKED`-forced block, the re-validation cap, the full-pass-findings case, and the discard exit. They differ in what brought them here and in nothing else — the same triage, the same disclosure, the same durable write.

**Constitution propagation runs first.** If `PROPAGATED_CONSTITUTION` is non-empty, run "Propagate Unresolved Constitution Findings" now, before step 1 below.

1. **Emit the triage first.** Before attempting any write, state:
   - every MUST-ADDRESS finding still outstanding, **separating findings the targeted agent reported `NOT_FIXED` from those it reported `INDETERMINATE`** — the first is a fix this loop disproved, the second is a question it could not answer, and a user triaging by hand needs to know which is which;
   - what each completed iteration attempted — reuse this run's per-iteration `LOG:` lines rather than re-deriving them;
   - the exact command to resume: `/speckit-review-plan` when `GATE_TYPE` is `secondary`, `/speckit-review-spec` when it is `primary`. That stage re-derives the finding set from a fresh full panel, so an `INDETERMINATE` verdict from this run is re-adjudicated rather than inherited.

2. **Disclose the artifact state, in the same words on every one of the six exits.** When `RUN_ARTIFACTS_WRITTEN` is true: the fixes this run wrote are retained on disk, they did not achieve a passing verdict, and `sl revert {list of artifact paths this run wrote}` discards them. When `RUN_ARTIFACTS_WRITTEN` is false: this run wrote nothing to disk, so there is nothing retained and nothing to discard — do not claim retained edits on this branch.

3. **Then write the gate.** Set `RESOLVED_FLAG` to `--resolved` when `RUN_ARTIFACTS_WRITTEN` is true and to the empty string otherwise. Also read `auto_applied`, `attempt_id` and `partial` from the existing `review/review-gate.json` — call the latter two `EXISTING_ATTEMPT_ID` and `EXISTING_PARTIAL`, never this file's own `ATTEMPT_ID` from "Full Adversarial Pass", which names a different attempt entirely. Set `AUTO_APPLIED_FLAG` to `--auto-applied` when `auto_applied` is `true`, and to the empty string otherwise — this loop never sets `auto_applied` itself, but a synthesis run upstream may have, and this write must not silently clear it. Also read `panel_size` and `quorum_met` from that same existing review gate as `EXISTING_PANEL_SIZE` and `EXISTING_QUORUM_MET`. Set `ATTEMPT_ID_ARGS` to `(--attempt-id "$EXISTING_ATTEMPT_ID")` when `EXISTING_ATTEMPT_ID` is non-empty, and to `()` otherwise; set `PARTIAL_ARGS` to `(--partial)` when `EXISTING_PARTIAL` is `true`, and to `()` otherwise; set `PANEL_SIZE_ARGS` to `(--panel-size "$EXISTING_PANEL_SIZE")` when `EXISTING_PANEL_SIZE` is non-empty, and to `()` otherwise; set `QUORUM_MET_ARGS` to `(--quorum-met "$EXISTING_QUORUM_MET")` when `EXISTING_QUORUM_MET` is non-empty, and to `()` otherwise. **Every one of these four is read from the existing gate, never from this loop's own variables** — `PANEL_SIZE` was superseded by "Full Adversarial Pass"'s freshly-minted manifest and now names *that* panel, so writing it into the dispatching review's gate would record the wrong panel's size. An unforwarded `attempt_id` makes the gate read as "not yet written" to the dispatching command's own outcome check; an unforwarded `panel_size` and `quorum_met` fall back to `write-review-gate.sh`'s `0`/`true` defaults, which makes `/speckit-autopilot`'s partial-coverage note render a negative reviewer count and lets `review-attempt.sh cleanup`'s coverage refusal pass on any value, deleting an attempt directory that partial coverage requires be retained. Then:

```bash
speckit run write-review-gate-unified.sh \
  --gate-type "$GATE_TYPE" \
  --status blocked \
  --must-address "$OUTSTANDING_MUST_ADDRESS_COUNT" \
  --should-consider "$SHOULD_CONSIDER_COUNT" \
  --minor "$MINOR_COUNT" \
  --agents-completed "$AGENTS_COMPLETED" \
  $RESOLVED_FLAG \
  $AUTO_APPLIED_FLAG \
  "${ATTEMPT_ID_ARGS[@]}" \
  "${PARTIAL_ARGS[@]}" \
  "${PANEL_SIZE_ARGS[@]}" \
  "${QUORUM_MET_ARGS[@]}"
```

   `--resolved` is what tells a later reader of `review/review-gate.json` alone that edits from this run are on disk, and it is what widens the commit scope to the artifacts this run wrote. It is conditioned on the run, not on which exit fired: a discard on the first iteration retains nothing and omits the flag, a discard on the second retains the first iteration's fixes and passes it.

4. **If that command exits 4** (the `plan` prerequisite is unmet — unexpected here, since this loop only runs after a prior gate write already succeeded, but possible if history changed underneath this run): Read and execute `.specify/templates/prerequisite-refusal-gate.md` before treating this as an ordinary write failure. This flow is unattended by construction, so follow that template's unattended-run guidance — halt with the diagnostic rather than presenting the three-way choice.

5. **If that command exits non-zero for any other reason, report and continue.** Say in plain language that the durable record of the retained edits could not be written, and name the reason if the script printed one. Do not treat it as blocking the exit: the artifacts and the triage above are already final, and swallowing the exit would lose the report this whole body exists to produce.

**Why the triage comes before the write.** The gate writer runs under `set -euo pipefail` and can fail on a malformed count or a missing prerequisite file. Emitting the triage first means a write failure degrades the durable record without also costing the user the only account of what the run did.

## Auto-Resolve Convergence Loop

Save in-memory snapshots of the spec and plan file content before entering the auto-fix loop. The snapshots are read by the Plan Staleness Check below; nothing in this file restores from them. Then execute a 3-iteration auto-fix loop:

```
SPEC_SNAPSHOT = <current spec file content>
PLAN_SNAPSHOT = <current plan file content, or null if primary gate>
ITERATION = 0
MAX_ITERATIONS = 3
GATE_BLOCKED = false
DISCARD_EXIT = false
NON_CONVERGENT_STOP = false
RUN_ARTIFACTS_WRITTEN = false
PROPAGATED_CONSTITUTION = []
OUTSTANDING_MUST_ADDRESS_COUNT = MUST_ADDRESS_COUNT

LOG: "Auto-resolving {MUST_ADDRESS_COUNT} MUST-ADDRESS findings across up to {MAX_ITERATIONS} iterations. Each iteration dispatches a single targeted agent to validate only the fixes this iteration claims; a full-panel pass runs once, after the targeted rounds converge."

LOOP (while ITERATION < MAX_ITERATIONS AND OUTSTANDING_MUST_ADDRESS_COUNT > 0):
  ITERATION += 1
  PREVIOUS_COUNT = OUTSTANDING_MUST_ADDRESS_COUNT
  ARTIFACTS_WRITTEN = 0
  LOG: "Iteration {ITERATION}/{MAX_ITERATIONS}: applying fixes for {PREVIOUS_COUNT} MUST-ADDRESS findings."

  When this iteration's MUST-ADDRESS findings include one or more `IS_CONSTITUTION_MUST`
  findings (see "Constitution MUST Compliance Re-check" above), compose and check them first,
  as their own sub-batch, then compose and check the remaining MUST-ADDRESS findings second —
  two sequential invocations of the same shared body, per that section. Otherwise run the body
  once, over the full set, exactly as before.

  Run "Compose, Check, Write" over this iteration's MUST-ADDRESS findings
  (constitution sub-batch first when one exists, per the paragraph above), targeting the spec,
  the plan and contracts as each finding requires. Set ARTIFACTS_WRITTEN to the number of
  artifacts that came out of either invocation with a clean or repaired outcome, and
  CLAIMED_FIXES to the findings whose fixes reached disk in this iteration — a constitution
  finding discarded by the re-check above is never added to CLAIMED_FIXES.

  If ARTIFACTS_WRITTEN == 0:
    DISCARD_EXIT = true
    LOG: "Iteration {ITERATION}: every fix composed this iteration was discarded by the consistency check. No artifact changed, so there is nothing new to validate. Unresolved: {list of finding IDs}. The gate will remain BLOCKED."
    Exit the loop.

  LOG: "Iteration {ITERATION}: dispatching a single targeted agent to check only the {count of CLAIMED_FIXES} fixes this iteration claims."
  Run "Targeted Validation" over CLAIMED_FIXES.
  OUTSTANDING_MUST_ADDRESS_COUNT -= CONFIRMED_THIS_ITERATION

  If CONFIRMED_THIS_ITERATION == 0:
    NON_CONVERGENT_STOP = true
    LOG: "Iteration {ITERATION}: Non-convergent auto-fix. The targeted agent confirmed none of the {count of CLAIMED_FIXES} fixes this iteration claimed ({count NOT_FIXED} not fixed, {count INDETERMINATE} indeterminate). Findings attempted: {list of finding IDs}."
    Exit the loop.

  LOG: "Iteration {ITERATION}: Reduced MUST-ADDRESS from {PREVIOUS_COUNT} to {OUTSTANDING_MUST_ADDRESS_COUNT}."
END LOOP

MUST_ADDRESS_COUNT = OUTSTANDING_MUST_ADDRESS_COUNT
# This assignment carries no authority over GATE_BLOCKED. A count that fell to
# zero because a discarded finding failed to resurface is not a resolved gate.
```

The loop has exactly five outcomes. Take the first that applies — the order matters, because a discard-only iteration never reaches the targeted dispatch and so has no confirmation count to judge:

```
If DISCARD_EXIT:
  LOG: "Auto-fix stopped after iteration {ITERATION}: every fix composed in that iteration was discarded by the consistency check. {OUTSTANDING_MUST_ADDRESS_COUNT} MUST-ADDRESS findings remain unresolved: {list of unresolved finding IDs}. Fixes that passed their own check in earlier iterations are retained on disk. The gate remains BLOCKED."
  Run "Give-Up Exit". Stop.

Else If NON_CONVERGENT_STOP:
  Emit the heading `### NON-CONVERGENT STOP`, then Run "Give-Up Exit". Stop.
  No further dispatch of any kind happens on this path — no further iteration, and no full adversarial pass.

Else If OUTSTANDING_MUST_ADDRESS_COUNT > 0:
  LOG: "Auto-fix exhausted ({MAX_ITERATIONS} iterations). {OUTSTANDING_MUST_ADDRESS_COUNT} MUST-ADDRESS findings remain unresolvable: {list of unresolved finding IDs}. Every fix that reached disk in this run is retained — nothing was rolled back. The gate remains BLOCKED."
  Run "Give-Up Exit". Stop.

Else If GATE_BLOCKED:
  LOG: "Auto-fix reached zero outstanding MUST-ADDRESS findings, but the consistency check discarded at least one fix of a blocking tier earlier in this run: {list of discarded finding IDs}. A zero count reached this way is not a resolved gate. The gate remains BLOCKED."
  Run "Give-Up Exit". Stop.

Else:
  LOG: "Auto-fix successful. All MUST-ADDRESS findings resolved in {ITERATION} iteration(s)."
  Run "Full Adversarial Pass" with artifact_state `terminal-iteration`.
  If it returned findings, that body has already exited this run. Otherwise continue below.
```

**Why the skipped re-dispatch exits rather than continuing.** An iteration in which every composed fix was discarded left every artifact unchanged. Re-dispatching over unchanged content spends several minutes to return the same findings for no new information, and burns an iteration of the loop's fixed budget on unchanged content. Exiting immediately is strictly better than looping to the cap: it reaches the same outcome — edits retained on disk, the gate blocked, both disclosed — without the wasted dispatches.

**IMPORTANT**: Plan-deferred findings are logged but NOT auto-fixed. They are preserved in `review/review-findings.md` for `/speckit-plan` to incorporate — do not edit the spec to address them. SHOULD-CONSIDER and MINOR findings are addressed in a best-effort pass after the gate is written (see below).

## Plan Staleness Check (Secondary Gate Only)

After the MUST-ADDRESS convergence loop completes successfully (`MUST_ADDRESS_COUNT = 0`) and `GATE_TYPE` is `secondary`, check whether spec changes have invalidated the plan:

```
If GATE_TYPE == "secondary" AND MUST_ADDRESS_COUNT == 0:
  PLAN_STALE = false

  Compare current spec content against SPEC_SNAPSHOT:
  - Extract changed/added/removed FRs (functional requirements)
  - Extract changed/removed Design Decisions
  - Extract changed mechanism descriptions (e.g., flag-based → pipeline-state-based)

  Read plan.md and research.md and check for references to removed/changed spec content:
  - Plan steps that reference removed FRs or flags
  - Design decisions in `research.md` (or a plan summary of them) that reference changed spec mechanisms
  - Plan File Plan entries that are missing newly-required files
  - Plan test descriptions that validate removed behavior

  If any plan sections reference removed/changed spec content:
    PLAN_STALE = true
    STALE_SECTIONS = [list of affected plan sections with brief description]
    LOG: "Plan staleness detected. {len(STALE_SECTIONS)} plan section(s) reference spec content that was changed or removed during auto-fix."
    For each section in STALE_SECTIONS:
      LOG: "  - {section}: {description of inconsistency}"
```

When `PLAN_STALE` is true:
- The gate still passes (the spec is correct)
- The completion report recommends `/speckit-plan` instead of `/speckit-tasks`
- The log explains which plan sections are inconsistent

**How this relates to the consistency check.** Both look at whether the plan still agrees with the spec, and they are not the same check.

- The consistency check runs **first**, inside each pass, before anything is written. Its reach is narrow and precise: a rule a fix in that pass actually changed, and the counterpart artifacts that still state it in the superseded form.
- This staleness check runs **after** the loop, over the whole run. Its reach is broad and structural: plan steps referencing requirements that no longer exist, File Plan entries missing newly-required files, tests validating removed behaviour. It catches consequences too diffuse to attribute to any one fix.
- **Where fixes were discarded, the non-passing gate wins.** If the consistency check discarded any fix this run, the gate stays blocked regardless of what this staleness check concludes. This check's outcome is pass-and-recommend-a-re-plan; it never converts a blocked gate into a passing one.

**Why this happens**: A secondary review runs AFTER the plan exists. When the review's auto-fix changes the spec (adding/removing FRs, changing mechanisms, updating Design Decisions), the plan — which was generated from the *pre-fix* spec — becomes inconsistent. The plan references requirements, flags, or mechanisms that no longer exist in the updated spec. Inline patching the plan is fragile because plan steps are tightly coupled — changing one step's mechanism often cascades to its tests, File Plan entries, and dependency graph. Re-running `/speckit-plan` regenerates the plan from the corrected spec, producing a consistent plan that incorporates both the auto-fix changes and any plan-deferred findings from the review.

## Post-Auto-Resolve Re-Validation (Plan Review Only)

After the convergence loop's full pass completes, check whether re-validation should trigger.

**Trigger conditions** — ALL must be true:
1. `GATE_TYPE` is `secondary` (plan review only — skip for primary)
2. The convergence loop completed successfully (`MUST_ADDRESS_COUNT = 0`)
3. Auto-resolve applied at least one edit during the convergence loop (if no edits were applied, the plan is unchanged — skip re-validation)

If any condition is false, skip to "Update Gate on Success".

### Re-Validation Loop (max 2 rounds)

```
RE_VALIDATION_ROUND = 0
MAX_RE_VALIDATION_ROUNDS = 2
RE_VALIDATION_EDITS = 0

LOG: "Auto-fix converged. Running up to {MAX_RE_VALIDATION_ROUNDS} re-validation rounds to check whether the edits introduced new issues."

LOOP (while RE_VALIDATION_ROUND < MAX_RE_VALIDATION_ROUNDS):
  RE_VALIDATION_ROUND += 1
  LOG: "Re-validation round {RE_VALIDATION_ROUND}/{MAX_RE_VALIDATION_ROUNDS}: dispatching the verification agent. This dispatch takes several minutes."

  Dispatch a single verification agent with model: "opus" and subagent_type: "general-purpose":

  Prompt:
  """
  You are a verification agent checking whether auto-resolve edits introduced new issues.

  **Input**:
  - The modified plan.md (after auto-resolve edits): {plan content}
  - The original spec.md: {spec content}
  - The constitution: {constitution content from .specify/memory/constitution.md, if available}

  **Check for**:
  1. **Introduced inconsistencies**: Do the edits contradict other parts of the plan? Are step dependencies still valid? Do line count estimates still add up?
  2. **Spec-plan alignment**: Do the edits maintain consistency with spec requirements? Are all FRs still addressed?
  3. **Constitution compliance**: Do the edits violate any constitution principle?

  **Do NOT check for**: The same issues the original review agents checked. You are looking for NEW issues introduced by the edits, not re-reviewing the entire plan.

  **Output format**: Use the same finding format as review agents:
  - Prefix: RV (Re-Validation)
  - Severity: MUST-ADDRESS, SHOULD-CONSIDER, MINOR
  - Include evidence and recommendation

  If you find no issues, write: "No findings. The plan passed re-validation."
  """

  Parse re-validation findings.

  Append findings to review/review-findings.md under a new section:

  ### RE-VALIDATION (Round {RE_VALIDATION_ROUND})

  #### RV-NNN: {title}
  **Agent**: Re-Validation · **Type**: {type}

  {description}

  > **Evidence**: {evidence}

  **Recommendation**: {recommendation}

  Count new MUST-ADDRESS findings from this round.

  If new MUST_ADDRESS_COUNT == 0:
    LOG: "Re-validation round {RE_VALIDATION_ROUND}: No new MUST-ADDRESS issues found. Plan is clean."
    Break out of loop.
  Else:
    LOG: "Re-validation round {RE_VALIDATION_ROUND}: Found {NEW_MUST_ADDRESS_COUNT} new MUST-ADDRESS issues."

    If RE_VALIDATION_ROUND < MAX_RE_VALIDATION_ROUNDS:
      Run "Compose, Check, Write" over the new MUST-ADDRESS findings (single pass, no
      convergence loop). This path writes the same artifacts the convergence loop writes,
      so it runs the same check before writing them.
      Add the number of artifacts it wrote to RE_VALIDATION_EDITS.
      Re-count remaining MUST-ADDRESS findings after fixes — update NEW_MUST_ADDRESS_COUNT to reflect actual remaining issues (some fixes may have silently failed, and any whose artifact was discarded by the check are still unresolved).
      Continue to next round.
    Else:
      LOG: "Re-validation iteration cap ({MAX_RE_VALIDATION_ROUNDS} rounds) reached. {NEW_MUST_ADDRESS_COUNT} MUST-ADDRESS findings remain unresolved: {list of remaining finding IDs}. Artifacts retain the auto-resolve edits — spec, plan and contracts were NOT rolled back. Manual triage recommended."
      Append to review/review-findings.md:

      ### RE-VALIDATION CAP REACHED

      ⚠️ Re-validation iteration cap (2 rounds) reached. The following issues remain unresolved:
      - {list of remaining MUST-ADDRESS findings}

      Artifacts retain auto-resolve edits. Manual triage recommended.

      Update MUST_ADDRESS_COUNT and OUTSTANDING_MUST_ADDRESS_COUNT with the remaining count.
      Run "Give-Up Exit". Stop.
END LOOP

If RE_VALIDATION_EDITS > 0:
  Run "Full Adversarial Pass" with artifact_state `post-re-validation`.
  If it returned findings, that body has already exited this run. Otherwise continue below.
```

**Why re-validation's own edits need their own pass.** The full pass that ran at the end of the convergence loop examined the artifact as it stood then. Re-validation may have written to it since. A passing gate has to be backed by a pass over the artifact state being certified, not over an earlier one — so an editing re-validation earns a second pass, and a non-editing one does not need it.

**Gate update**: After re-validation completes, if `MUST_ADDRESS_COUNT > 0` (re-validation found unresolvable issues), update the gate status to `blocked`. The "Update Gate on Success" section below will then write the correct status.

## Update Gate on Success

If MUST_ADDRESS_COUNT reaches 0 **and `GATE_BLOCKED` is false**, update the gate to `passed`.

**Precondition — a passing gate must be backed by a full pass.** Before writing, confirm the most recent `review-full-pass` entry in `{FEATURE_DIR}/pipeline-state.jsonl` for this run has `status=complete`. If no such entry exists, do not write a passing gate: the artifact has not been examined by a full adversarial panel in the state it is now in, and a passing verdict would be asserting an assurance that was never performed. Report that the full pass record is missing and Run "Give-Up Exit" instead. This is not only a defensive branch against the sections above running out of order — a full pass that reached its ceiling with partial coverage deliberately records `status=partial` here (see the ceiling-token table under "Full Adversarial Pass" above), and this precondition is what turns that into the blocked outcome it deserves rather than a passing one.

Set `RESOLVED_FLAG` to `--resolved` when `RUN_ARTIFACTS_WRITTEN` is true and to the empty string otherwise. Also read `auto_applied`, `attempt_id` and `partial` from the existing `review/review-gate.json` — call the latter two `EXISTING_ATTEMPT_ID` and `EXISTING_PARTIAL`, never this file's own `ATTEMPT_ID` from "Full Adversarial Pass". Set `AUTO_APPLIED_FLAG` to `--auto-applied` when `auto_applied` is `true`, and to the empty string otherwise — this loop never sets `auto_applied` itself, but a synthesis run upstream may have, and this write must not silently clear it. Also read `panel_size` and `quorum_met` from that same existing review gate as `EXISTING_PANEL_SIZE` and `EXISTING_QUORUM_MET`. Set `ATTEMPT_ID_ARGS`, `PARTIAL_ARGS`, `PANEL_SIZE_ARGS` and `QUORUM_MET_ARGS` exactly as the blocked-gate write above does — all four read from the existing gate, never from this loop's own variables, for the reasons stated there. Then:

```bash
speckit run write-review-gate-unified.sh \
  --gate-type "$GATE_TYPE" \
  --status passed \
  --must-address 0 \
  --should-consider "$SHOULD_CONSIDER_COUNT" \
  --minor "$MINOR_COUNT" \
  --agents-completed "$AGENTS_COMPLETED" \
  $RESOLVED_FLAG \
  $AUTO_APPLIED_FLAG \
  "${ATTEMPT_ID_ARGS[@]}" \
  "${PARTIAL_ARGS[@]}" \
  "${PANEL_SIZE_ARGS[@]}" \
  "${QUORUM_MET_ARGS[@]}"
```

A successful run's edits are this run's own output just as a blocked run's are, so they carry `--resolved` on the same condition — the flag records who wrote the files, not whether the gate passed.

**If this call exits 4** (the `plan` prerequisite is unmet — unexpected here, since this loop only runs after a prior gate write already succeeded, but possible if history changed underneath this run): Read and execute `.specify/templates/prerequisite-refusal-gate.md` before treating this as an ordinary write failure. This flow is unattended by construction, so follow that template's unattended-run guidance — halt with the diagnostic rather than presenting the three-way choice.

If `GATE_BLOCKED` is true, do **not** write a passing gate, whatever the count says. Report which findings were discarded by the consistency check and why the gate remains blocked. A zero count here does not mean the work was done — it can equally mean a discarded finding failed to resurface in the last validation round.

## Best-Effort SHOULD-CONSIDER and MINOR Pass

This pass runs **after** the gate above has been written, and only when that gate was written as passed. Everything it writes is unvalidated: no agent checks it, and the gate already on record describes the artifact as it stood before these edits.

```
If MUST_ADDRESS_COUNT == 0 AND GATE_BLOCKED == false AND (SHOULD_CONSIDER_COUNT > 0 OR MINOR_COUNT > 0):
  LOG: "Gate recorded. Attempting best-effort fixes for {SHOULD_CONSIDER_COUNT} SHOULD-CONSIDER and {MINOR_COUNT} MINOR findings. These edits are not validated and do not change the gate."

  Before applying the first edit, record that unvalidated edits may now be present:

  speckit run write-pipeline-state.sh review-post-gate \
    gate_type="$GATE_TYPE" status=pending

  Run "Compose, Check, Write" over the SHOULD-CONSIDER findings, then again over the MINOR
  findings. Decrement the corresponding count for each finding whose artifact was written.

  LOG: "Best-effort pass complete. Resolved {N} SHOULD-CONSIDER ({M} remain) and {P} MINOR ({Q} remain). These {N+P} fixes were not validated by any agent."

  speckit run write-pipeline-state.sh review-post-gate \
    gate_type="$GATE_TYPE" status=complete resolved_further="{N+P}"
```

The `pending` record is written before the first edit and the `complete` record after the last one, so a run interrupted midway leaves durable evidence that the artifact may hold unvalidated edits — a reader does not have to reconstruct that from the transcript.

**The gate is never revised from here.** A best-effort fix that cannot be applied cleanly is reported as failed and skipped; a best-effort fix that applies is reported as unvalidated. Neither outcome rewrites, reopens, or re-blocks the gate recorded above. The gate describes the state that was validated, and nothing this pass does was validated.

**No rollback**: Best-effort fixes, like every MUST-ADDRESS fix in this file, are not rolled back on failure — if a fix cannot be applied cleanly, skip it and move to the next finding.

**No re-validation**: Do not re-run review agents after best-effort fixes. These are improvements, not gate-blocking requirements. They are still composed, read back and checked before they are written — the check is not re-validation and is not waived here. A best-effort fix writes the same artifacts a blocking fix does, so an unchecked one can leave the spec self-contradictory just as easily.

## Auto-Resolution Log

Record all auto-fix actions in the completion report:

```markdown
## Auto-Resolution Log

- **Decision Point**: BLOCKED fix prompt
- **Auto-Resolved Value**: [Auto-fix attempted / N/A if gate passed]
- **Reasoning**: [If auto-fix attempted: "Auto-fixed MUST-ADDRESS findings in {N} iteration(s). Convergence: {convergent/non-convergent}. Final status: {all resolved/exhausted with {M} unresolved}" / If gate passed: "Gate passed, no auto-fix needed"]
- **Iteration Details** (if auto-fix attempted):
  - Iteration 1: Reduced MUST-ADDRESS from {X} to {Y}
  - Iteration 2: Non-convergent ({Y} → {Z}, did not reduce)
  - [etc., up to 3 iterations]
- **Full Adversarial Pass** (omit when the run never reached one): {artifact state examined}, {PANEL_SIZE} agents, {number of MUST-ADDRESS findings returned}
- **Consistency Check** (one entry per artifact that was composed, in every pass):
  - {artifact}: defects found — {each defect quoted and classified, or "none"}
  - {artifact}: outcome — {clean | repaired | discarded}{, and for a repair, what it changed and any accepted fix it altered or removed}
- **Discarded** (omit when nothing was discarded): {finding IDs left unresolved because their artifact failed the check}, gate forced to remain BLOCKED
- **Post-gate best-effort** (omit when the pass did not run): resolved {N} further SHOULD-CONSIDER/MINOR findings after the gate was recorded; these edits are unvalidated
```

The consistency-check entries state each artifact's defects **before** its outcome, and the discard summary after both — a verdict whose evidence is not visible first cannot be checked by whoever reads this log later.

After displaying the log in the completion report, append it to `auto-resolution-log.md` in the feature directory:

1. Check if `{FEATURE_DIR}/auto-resolution-log.md` exists
2. If not, create it with header: `# Auto-Resolution Audit Trail`
3. Append a new section with timestamp:
   ```markdown
   ## speckit.review — {ISO 8601 timestamp}

   {decision entries from auto-resolution log above}
   ```
4. If the review gate passed (no auto-fix attempted), still log the event for audit purposes

## Completion Report

Report:
- Auto-fix outcome (success, exhausted, or gate passed)
- The consistency check's results: for each artifact composed, the defects found before the outcome, then a run-level summary of how many artifacts were checked, written and discarded
- Final finding counts
- Any findings left unresolved because their artifact's fixes were discarded by the check
- Gate status (BLOCKED → PASSED, or remains BLOCKED — including when the counts reached zero but a discard forced it to stay blocked)
- **What the recorded counts describe.** State that the gate's recorded counts describe the artifact as it was validated at the moment the gate was written, and — when the best-effort pass ran — how many further SHOULD-CONSIDER/MINOR findings it resolved afterwards, and that those later edits are unvalidated and are not reflected in the gate.
- If `PLAN_STALE` is true: list the stale sections and note that the plan needs regeneration
- **➡️ Recommend next pipeline command:**
  - Primary gate → `/speckit-plan`
  - Secondary gate with `PLAN_STALE = false` → `/speckit-tasks`
  - Secondary gate with `PLAN_STALE = true` → `/speckit-plan` with explanation:
    > **Re-plan required.** The secondary review changed the spec in ways that invalidate the current plan. {N} plan section(s) reference removed or changed spec content. Run `/speckit-plan` to regenerate the plan from the corrected spec. The regenerated plan will also incorporate the {M} plan-deferred findings from this review.

**The two stop headings.** When this run stopped without a passing verdict, exactly one of two headings appears in this report, and the dispatching stage reads it to decide what to show the user next:

- `### NON-CONVERGENT STOP` — an iteration confirmed none of the fixes it claimed. Emitted only from that exit.
- `### FULL-PASS FINDINGS` — the targeted rounds converged and the full adversarial pass then found MUST-ADDRESS findings of its own. Emitted only from that exit.

Never emit both, and never emit either from any other exit. They are read as literal strings by the stage that dispatched this loop, so the wording above is fixed.
