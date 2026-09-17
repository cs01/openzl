---
name: speckit-review-plan
description: 'SpecKit SDD pipeline: review `specs/<feature>/plan.md` with codebase-grounded claim verification.'
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:meta
  meta_preset_strategy: replace
user-invocable: true
disable-model-invocation: false
---



# Speckit Review Plan Skill

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

> **Critical Invariants**:
>
> 1. **Mode choice gate is MANDATORY** — Step 8 presents Fix now (Interactive), Fix now (Auto-resolve), Override, and Defer options when the gate is BLOCKED. Never skip presenting the choice unless a fast-path condition applies (--auto flag, gate PASSED, or AUTO_MODE from pipeline-state).
> 2. **Batch-write mandate** — Interactive resolution (via `/speckit-review-interactive`, dispatched from step 8) MUST use one Write call per file for applying edits, never sequential Edit calls.

## Pre-Execution Checks

**Workspace check (MANDATORY)**: Run `speckit run require-workspace.sh`. This resolves the workspace from any subdirectory and produces the same fixed message when there is no workspace above the current directory. On a non-zero exit, relay its stderr output to the user verbatim — do not paraphrase, reword, summarize, or translate it; do not prepend or append anything (no preface, heading, or attribution such as "require-workspace.sh failed:"); do not name the script, the command, the exit code, or any internal path — then halt. On exit 0, proceed silently to the next check.

**Model note**: This command dispatches adversarial agents that benefit from strong reasoning. Opus is recommended for the dispatched agents. The orchestration runs fine on any model.

## Outline

Before starting work, briefly tell the user what this stage does, why it matters, and that it typically takes a few minutes. Print the introduction in bold.

This command stress-tests your implementation plan with parallel adversarial agents — verifying architecture decisions, checking constitution compliance, and catching risks before task breakdown.

**Output discipline**: Suppress routine setup narration — step numbers, variable bindings (`ATTEMPT_ID`, `FR_COUNT`, etc.), script names, exit codes, internal calculations, wait-loop re-invocations, and state-machine transitions. Errors, warnings, interactive prompts, mandatory gate menus, progress milestones (panel size, reviewer completions), resume disclosures, and completion reports are not routine narration and must still be shown.

1. **Parse and strip flags**: Check `$ARGUMENTS` for `--auto` and `--skip-review` flags. If present, record which flags were found, then strip them as standalone leading tokens from `$ARGUMENTS` before proceeding. Do not strip flags embedded in the feature description text.

   After stripping, continue with the remaining `$ARGUMENTS` as the feature description.

2. **Setup**: Run `.specify/scripts/bash/check-prerequisites.sh --json --paths-only` from repo root and parse JSON for FEATURE_DIR, FEATURE_SPEC, IMPL_PLAN, SPECS_DIR, BRANCH.

3. **Validate spec exists**: Read FEATURE_SPEC. If the file does not exist, ERROR: "No spec found. Run `/speckit-specify` first."

4. **Gate type**: This is a **secondary gate** (post-plan review). Gate type is always `secondary`.

   **Prerequisite-chain note**: Every `write-review-gate-unified.sh` call in this file writes the `review` stage at `gate_type=secondary`, which participates in the pipeline-integrity prerequisite chain (it requires `plan`). **If any such call exits 4** (the `plan` prerequisite is unmet): Read and execute `.specify/templates/prerequisite-refusal-gate.md` instead of proceeding — this is a prerequisite-chain refusal, distinct from this command's own MUST-ADDRESS mode choice gate below.

4b. **Secondary gate skip guard**: Check if a secondary review already completed, **passed**, and is still valid:
   ```bash
   eval "$(speckit run read-plan-review-state.sh "$FEATURE_DIR/pipeline-state.jsonl")"
   ```
   This sets `STATE_UNREADABLE`, `LATEST_SECONDARY_REVIEW_SEQ`, `LATEST_PLAN_SEQ` and `PENDING_RECOMMENDATION`, plus `AUTO_MODE` and `SKIP_REVIEW` for step 4c. Do not re-read the history yourself in either step — the corrupt-history rule below is the reason this read is centralized.

   **If the call produced nothing, halt.** Confirm `STATE_UNREADABLE` is set to `true` or `false` before using any of the six values. If it is unset, the reader did not run — it is missing, or the run itself failed — and none of the six were assigned, so every branch below would compare against an empty value: the exact failure this step exists to remove, and with no `STATE_UNREADABLE` the disclosure would not fire either. Do not fall through to the branches. Halt with exactly:

     > The pipeline state reader is missing or failed to run. Re-run `speckit init` in this project to reinstall, then re-run the review.

     Never surface the raw shell error a missing script would otherwise produce.
   - If `LATEST_SECONDARY_REVIEW_SEQ > 0` AND `LATEST_SECONDARY_REVIEW_SEQ > LATEST_PLAN_SEQ` AND `PENDING_RECOMMENDATION != "pending"`: log "Secondary review already completed and passed (and plan unchanged). Skipping." and exit with success (0). Do not write gate files or pipeline state.
   - If `LATEST_SECONDARY_REVIEW_SEQ > 0` AND `LATEST_SECONDARY_REVIEW_SEQ <= LATEST_PLAN_SEQ`: log "Plan regenerated since last secondary review (plan seq {LATEST_PLAN_SEQ} > review seq {LATEST_SECONDARY_REVIEW_SEQ}). Re-running review." and proceed.
   - If `PENDING_RECOMMENDATION == "pending"`: log "A prior resolution session recommended re-running this review and that recommendation has not been discharged. Re-running review." and proceed, whatever the seq comparison says.
   - If `LATEST_SECONDARY_REVIEW_SEQ == 0`: proceed (no prior secondary review, or every prior one left the gate blocked).

   **The `passed` filter is load-bearing.** Without it a *blocked* secondary-gate entry satisfies the recency comparison and this stage exits reporting the review as already completed — leaving a blocked gate with no route back into the stage that owns it. A skip means "this work is already done"; a blocked gate means the opposite.

   **A corrupt history is not a partially usable one.** Every value above is the *latest* matching record, so one unparseable line is not a line that can simply be skipped: a truncated newest record silently promotes an older one, and the older one is wrong in the dangerous direction — a previous plan's `seq` makes a stale review look current, and a previous plan's `skip_review=true` re-arms a skip the newest record had cleared. Both skip a review that needed to run. That is why one bad line anywhere condemns the whole read rather than degrading it.

   **Error handling**: When `STATE_UNREADABLE` is true — any unparseable line in the history — every value above is already forced to its safe default, so the final branch fires and the review re-runs. Defaulting to a re-run is the safe direction: the cost is one repeated review, where the opposite default would skip a review that needed to happen. Say so rather than defaulting silently — log "Pipeline state unreadable — re-running the plan review." A missing or empty history is **not** this case: it is the ordinary state before anything has been recorded, yields the same defaults, and must not produce that message.

4c. **Read plan metadata**: `AUTO_MODE` and `SKIP_REVIEW` were already read from the most recent plan entry by step 4b's call. Use those values — do not re-read the history here.
   - If `SKIP_REVIEW` is true: proceed to skip-review fast path (step 5) as if `--skip-review` flag was passed

   **Error handling**: When `STATE_UNREADABLE` is true, both values are `false` — attended mode, review not skipped. That is the conservative reading, and it matters most here: `skip_review` is the one field where inheriting a stale value turns the review off entirely. Step 4b has already reported the unreadable history; do not repeat the message.

5. **Skip-review fast path** If `--skip-review` was passed:
   - Write gate file and pipeline state with status passed, all counts at 0 using the unified helper:
     ```bash
     speckit run write-review-gate-unified.sh \
       --gate-type "secondary" \
       --status passed \
       --must-address 0 \
       --should-consider 0 \
       --minor 0 \
       --agents-completed 0 \
       --panel-size 0 \
       --quorum-met true
     ```
   - Log warning: "Review skipped via --skip-review — proceeding without adversarial review."
   - Skip to step 8 (completion report)

6. **Dispatch the review panel directly**:

   **6a. Archive primary review artifacts.** Before anything else in this step, preserve the primary review's artifacts so this stage's own writes never clobber them. This used to run inside the synthesis subagent, but synthesis now runs only after the wait concludes — too late to guard the read that follows here, so it moves to the front of this step, ahead of attempt init.

   - If `review/review-findings.md` does not exist in FEATURE_DIR, skip the rest of this substep — there is nothing to archive.
   - Otherwise, read `review/review-gate.json` and check its `gate_type` field. Only proceed with archival if `gate_type == "primary"`. If `gate_type == "secondary"` (from a prior plan review re-run), skip archival — the real primary artifacts are already preserved in `review/review-findings-primary.md`.
   - Also skip archival if `review/review-findings-primary.md` already exists (primary artifacts already archived from a prior run).
   - If archival proceeds: copy `review/review-findings.md` to `review/review-findings-primary.md` and `review/review-gate.json` to `review/review-gate-primary.json`.
   - **FAIL-SAFE**: If either copy fails, halt before minting or resuming an attempt and before dispatching anything — plan review must not proceed without a preserved primary record — with: "Failed to archive primary review artifacts. Cannot proceed with plan review — primary review artifacts must be preserved."

   **6b. Resolve attendedness.** Set `ATTENDED` to `false` when the `--auto` flag was detected (step 1), or when this command was itself invoked by dispatch — from the mandatory `after_plan` hook (its default wiring: no responder is attached to a hook-dispatched run), from `/speckit-review`'s auto-routing, from `/speckit-autopilot`, or from any extension hook — regardless of any other flag. Otherwise (a direct, user-typed `/speckit-review-plan` invocation with no `--auto`), set it to `true`. This value governs the ceiling behavior in step 7; it is independent of `AUTO_MODE`, which only governs synthesis's own auto-apply restriction.

   **6c. Script resolution.** Before dispatching anything, confirm `.specify/scripts/bash/review-attempt.sh` and `.specify/scripts/bash/review-wait.sh` are present. If either is absent, halt with exactly:

     > The reviewer templates appear to be out of date relative to the review command — no reviewer produced any output. Re-run `speckit init` in this project to reinstall, then re-run the review.

     Never surface the raw shell error a missing script would otherwise produce.

   **6d. Report outstanding attempts.** Run `speckit run review-attempt.sh outstanding` and surface its output to the user, if any, before proceeding — a prior attempt still in flight is context worth having before minting or resuming another.

   **6e. Pre-dispatch snapshot.** Before attempt init, read and retain `plan.md`'s current content as `PLAN_SNAPSHOT`. This is the revert mechanism for the `all_auto_applied` rejection path in step 8 below: synthesis writes auto-applied fixes directly to `plan.md` rather than returning them through a response channel, so reverting requires the pre-dispatch content captured here. **Capture it on every run, including a successful `resume` below** — nothing writes a snapshot into the attempt directory, so a run that skipped this step would reach step 8's reject path with nothing to write back, leaving the auto-applied edits on disk while the report and `review/review-findings.md` both record the revert as done. On a resumed attempt this captures the artifact as it stands at resume time, which is the correct revert target for edits this run makes.

   **6f. Resolve the panel roster.** Read `.specify/templates/review-plan-panel-prompts.md` for its Panel Composition rule and its four role briefs (CC, CR, CV, RK), in the order listed there. That rule points to the sizing table and FR_COUNT-based complexity-derivation algorithm in `.specify/templates/review-spec-panel-prompts.md`'s own Panel Composition section — apply both exactly as spec review does, for the base panel (CR, CV, RK) only:

   - Parse `spec.md`'s `risk` (default `medium` if absent/unrecognized) frontmatter, and its `complexity` frontmatter if present (mirror `speckit.clarify.md` step 3's `risk`-parsing pattern for absent/unrecognized values) — an absent or unrecognized `complexity` value falls through to the `FR_COUNT`-based derivation below, not a hardcoded default.
   - Count `FR_COUNT` — the number of distinct `FR-###` identifiers under `spec.md`'s `## Requirements` section (0 if the section is absent), counting base identifiers only and deduplicating lettered variants (`FR-###a`/`FR-###b` count once toward their shared base). Do this now, not at dispatch time (6h) — the sizing lookup below needs it whenever `complexity` was absent from frontmatter.
   - If `complexity` was absent from frontmatter, derive it from `FR_COUNT`: `complex` when `FR_COUNT > 10`, `standard` otherwise. If frontmatter explicitly set a `complexity` value, honor it regardless of `FR_COUNT`.
   - Look up `BASE_PANEL_SIZE` (1-3) from the sizing table for this `(complexity, risk)` pair.
   - Select the first `BASE_PANEL_SIZE` roles from the table's own dispatch-priority order — Correctness first, Coverage second, Risk third: CR alone at size 1, CR+CV at size 2, CR+CV+RK at size 3.
   - Set `PREMISE_BRIEF` to `true` when `risk == high` or `complexity == complex` (every sizing-table row marked "Premise brief in CR"), else `false`.
   - Set `BROADENED_BRIEF` to `true` only when `BASE_PANEL_SIZE == 1` (the compact/low row, where CR is dispatched alone), else `false`. `PREMISE_BRIEF` and `BROADENED_BRIEF` are mutually exclusive — no sizing-table row sets both.

   If `.specify/memory/constitution.md` exists and does not contain the sentinel `<!-- speckit:constitution:placeholder -->`, add CC to the roster: `PANEL_SIZE` is `BASE_PANEL_SIZE + 1`. Otherwise CC is not dispatched and `PANEL_SIZE` equals `BASE_PANEL_SIZE`. Plan review panels range from 1-4 agents, per `review-plan-panel-prompts.md`'s own Panel Composition rule.

   Build a `prefix:role` pair for each role selected above, in the templates' own listed order (CC first when included, then the selected base-panel roles in CR, CV, RK order), joined by commas — this is the `--roster` value 6g passes to `init`. Do not hardcode the pairs here; re-deriving them from the templates on every run is what keeps this command from drifting out of sync with a future edit to either template.

   If `complexity` (post-derivation) is `compact`, print before dispatch: "Compact spec detected — review panel will skip flagging legitimately-omitted sections." This is the only user-visible signal for the panel's compact-awareness — the per-role suppression instructions inside the dispatched prompts are otherwise invisible to the user.

   **6g. Mint or resume the attempt.** Try `speckit run review-attempt.sh resume --gate-type secondary` first. On exit 0, **skip 6h (dispatch) entirely** — a second panel would overwrite the resumed attempt's findings and clobber its markers. Two cases resume, and `RESUME_OUTSTANDING` on stdout distinguishes them: a non-empty value lists the reviewers still in flight; an empty value means every reviewer already delivered and the wait in step 7 will return immediately, resuming straight to synthesis. Disclose which case applies before continuing — "Resuming attempt {ATTEMPT_ID}: {N} reviewers still in flight" or "Resuming attempt {ATTEMPT_ID}: all {PANEL_SIZE} reviewers already delivered — proceeding to synthesis". Without this the recovery of a complete panel is indistinguishable from an ordinary run. On exit 1 (no resumable attempt), fall through to:
     ```bash
     speckit run review-attempt.sh init \
       --gate-type secondary \
       --roster "<the comma-joined pairs from 6f>" \
       --attended "$ATTENDED"
     ```
     On **exit 3**, fail fast: report the infrastructure error verbatim from stderr, do not dispatch anything, and never later describe this outcome as zero reviewer coverage — it is a location failure, not a review result. Capture `ATTEMPT_ID`, `ATTEMPT_DIR`, `PANEL_SIZE`, `QUORUM_REQUIRED`, `DEADLINE_EPOCH` from either call's stdout; `resume` additionally emits `RESUME_OUTSTANDING`, which `init` does not.

   **6h. Dispatch — skipped entirely when 6g's `resume` succeeded.** `FR_COUNT` and `PANEL_SIZE` are already on hand from 6f and 6g respectively — `PANEL_SIZE` varies with the sizing-table lookup and the constitution check (1-4), not a fixed value. For each role brief in the resolved panel, compose its prompt per `review-plan-panel-prompts.md`'s own instructions — including its conditional search-instruction append — filling the bindings `review-agent-prompt-base.md`'s own INPUTS table declares (`ATTEMPT_ID`, `ATTEMPT_DIR`, `PREFIX`, `ROLE`, `FEATURE_SPEC`, `IMPL_PLAN`, `CONSTITUTION` when it exists, `ENRICHMENT` when it exists, `EXPLORATION` when it exists, `FR_COUNT`, `PANEL_SIZE`). When CR is in the resolved panel, dispatch it with the premise brief when 6f's `PREMISE_BRIEF` is `true`, or with the broadened sole-agent brief when `BROADENED_BRIEF` is `true` — the two never both apply. Emit "Adversarial pipeline running — this typically takes 5-8 minutes", then send **all** `Agent(general-purpose)` calls for the resolved panel **in one message**. Do not wait on their return value — delivery is tracked on disk, not through the response channel; proceed immediately to step 7.

7. **Wait for the panel and synthesize.**

   **Ceiling Presentation** (referenced by the protocol hand-off below whenever the wait ends in `ceiling_reached` and `ATTENDED` is `true`): present all five elements —
   1. Continue waiting
   2. Proceed with partial findings
   3. Abort
   4. A freeform response accepting a user-supplied wait duration
   5. An option to discuss the situation before choosing

   This prompt is itself bounded: state its own interval, and if no answer arrives within it, say so and fall through to the unattended rule (the script's own quorum verdict decides).

   **Hand off**: Read and execute `.specify/templates/review-wait-protocol.md`, using `ATTEMPT_ID`, `ATTEMPT_DIR`, `PANEL_SIZE`, `QUORUM_REQUIRED`, `GATE_TYPE=secondary`, `ATTENDED`, `SYNTHESIS_TEMPLATE=.specify/templates/review-plan-synthesis.md`, and the dispatch bindings `FEATURE_DIR`, `FEATURE_SPEC`, `IMPL_PLAN`, `AUTO_MODE` already established above, plus this gate's own `PENDING_RECOMMENDATION` (computed in step 4b), plus `SYNTHESIS_MODEL=sonnet`, `PRE_AGGREGATE=true`, `CONDITIONAL_CEILING_THRESHOLD=30`. The protocol's synthesis dispatch illustrates only `FEATURE_SPEC`; forward `IMPL_PLAN` and `PENDING_RECOMMENDATION` alongside it — `review-plan-synthesis.md`'s own Inputs section requires both beyond what the protocol's boilerplate shows. The protocol template owns the wait-token branch table, the extension re-entry loop, outcome classification, the four terminal-record categories, and cleanup ordering — including reading the Ceiling Presentation above whenever it needs to ask the user something.

   **If the protocol hand-off reaches a terminal record** (an aborted, infrastructure-failed, or ceiling-blocked-without-quorum review): its own disclosure of the retained attempt directory is the completion report for this run. Skip step 8 entirely and continue at step 9.

   **Otherwise**, `synthesis.done.json` carries a normal conclusion (`ok`, `all_auto_applied`, or `quorum_failed`). Continue to step 8.

8. **Completion report and mode choice**:

    Derive dispatch variables from `{ATTEMPT_DIR}/synthesis.done.json`: `MUST_ADDRESS_COUNT`, `SHOULD_CONSIDER_COUNT`, `MINOR_COUNT`, `DECISION_POINT_COUNT`, `AGENTS_COMPLETED`, `PANEL_SIZE`. Set `QUORUM_MET` to `false` only when `synthesis.done.json`'s `status` is `quorum_failed`; `true` otherwise (both `ok` and `all_auto_applied` are only reached after quorum was met).

    **On the `--skip-review` path no attempt exists**: skip the `synthesis.done.json` read entirely and fix every count above at `0`, `AGENTS_COMPLETED` and `PANEL_SIZE` at `0`, `QUORUM_MET` at `true`, and the render call's `--coverage` at `0/0`. The override sequence below forwards `--attempt-id` only when an attempt exists. Without this branch none of them are bound on that path, and `render-gate-report.sh` rejects an empty `--coverage` as a usage error.

    **All-Auto-Applied Confirmation** — runs only when `synthesis.done.json`'s `status` was `all_auto_applied`. Every other terminal status skips this block entirely and continues at the Context tip below.

    Read the triage disposition data from `review/review-findings.md`'s `### Auto-Applied` and `### Discarded` sections and its triage disposition sub-table: `AUTO_APPLIED_COUNT` (N) and `DISCARDED_COUNT` (M). Also read each Auto-Applied finding's `**Classification**:` field and set `ANY_SEMANTIC` to `true` if any reads `Semantic` or is absent/malformed (conservative default — treat as `Semantic`, per `.specify/templates/triage-classifier-criteria.md`), `false` only when every one reads `Additive`.

    - **In `--auto` mode** (the `--auto` flag was detected in step 1, or `AUTO_MODE` is true from step 4c): skip the confirmation prompt below and go straight to the confirm branch.
    - **Otherwise, when `ANY_SEMANTIC` is `false`**: skip the confirmation prompt and go straight to the confirm branch — every auto-applied fix was additive-only, so nothing changed a requirement, constraint, or decision that needs a human sign-off. Note in the Report block's triage summary below that the batch was auto-confirmed as additive-only.
    - **Otherwise**, present: "{N} fixes auto-applied, {M} findings discarded, gate passing — confirm?" and wait for the user's choice.

    **On confirm**:
    ```bash
    PARTIAL_FLAG=()
    [[ "$AGENTS_COMPLETED" -lt "$PANEL_SIZE" ]] && PARTIAL_FLAG=(--partial)
    speckit run write-review-gate-unified.sh \
      --gate-type "secondary" \
      --status passed \
      --must-address 0 \
      --should-consider 0 \
      --minor 0 \
      --agents-completed "$AGENTS_COMPLETED" \
      --panel-size "$PANEL_SIZE" \
      --quorum-met true \
      --attempt-id "$ATTEMPT_ID" \
      --auto-applied \
      "${PARTIAL_FLAG[@]}"
    ```
    Validate that `plan.md` differs from `PLAN_SNAPSHOT` — an auto-applied run that changed nothing indicates a template defect worth flagging in the report, though it does not block this flow. Then run `speckit run review-attempt.sh cleanup --attempt-dir "$ATTEMPT_DIR" --gate-file "$FEATURE_DIR/review/review-gate.json"` — the gate just landed, so the deferred cleanup from the protocol template's Cleanup section runs now. Continue at the Context tip below to report the passed gate; `should_consider_count` and `minor_count` are both 0 on this path since every finding was either auto-applied or discarded.

    **On reject**:
    1. Write `PLAN_SNAPSHOT` back to `plan.md`, reverting the auto-applied fixes.
    2. Rewrite `review/review-findings.md`. For each finding currently in `### Auto-Applied`:
       a. **Determine the target severity section** from the finding's `**Severity**:` line — `### SHOULD-CONSIDER` or `### MINOR` only, never `### MUST-ADDRESS` (auto-applied findings are never that severity). If the `**Severity**:` line is absent or malformed, default to `### SHOULD-CONSIDER` — the same conservative bias the classifier itself uses.
       b. **(Re)create the target section if it was omitted** — zero-count `### SHOULD-CONSIDER`/`### MINOR` on this `all_auto_applied` path — in the fixed section order, before inserting into it.
       c. **Rewrite the finding in place and append it** at the end of the target section, followed by the `---` horizontal-rule separator the format places after every finding (including the last one in a section, immediately before the next `###` heading) — never a leading separator, which would duplicate the trailing one the section's existing last finding (or the freshly (re)created section's own heading) already has. The finding keeps its full content — description, Evidence, Recommendation, Digest — unchanged. Exactly four things change: `**Disposition**:` from `[AUTO-APPLIED]` to `[PRESENTED]`; the now-redundant `**Severity**:` line is dropped (severity is already implicit from section placement for `[PRESENTED]` findings); the now-redundant `**Classification**:` line is dropped (it is confirmation-path metadata that has no meaning for a `[PRESENTED]` finding); the `- [x] Resolved` checkbox reverts to `- [ ] Resolved` (unresolved again, pending human review).
       d. **Update the `### Summary` section's three tables** for this finding: its target section's own `### {TIER} ({count})` header count; the `#### By Severity` counts; and its `#### By Type` row (creating the row if this is the first presented finding of that type — both `By Severity` and `By Type` cover `PRESENTED` findings only, so a restored finding enters both for the first time here).

       After every finding has been moved: update the `#### By Triage Disposition` sub-table (Auto-Applied count drops by the number restored, Presented count rises by the same), and remove the `### Auto-Applied` section entirely.
    3. Set `$SHOULD_CONSIDER_COUNT`/`$MINOR_COUNT` by parsing the updated `### SHOULD-CONSIDER ({count})`/`### MINOR ({count})` header counts from the just-rewritten `review/review-findings.md` — that is the "recomputed post-restoration counts" this step's gate write needs. Treat an absent header (the section was never recreated because nothing restored into it) as a count of `0`. Then rewrite the gate — auto-applied findings are never MUST-ADDRESS severity, so the restored set can only raise `SHOULD_CONSIDER_COUNT`/`MINOR_COUNT` and the status stays `passed`:
       ```bash
       PARTIAL_FLAG=()
       [[ "$AGENTS_COMPLETED" -lt "$PANEL_SIZE" ]] && PARTIAL_FLAG=(--partial)
       speckit run write-review-gate-unified.sh \
         --gate-type "secondary" \
         --status passed \
         --must-address 0 \
         --should-consider "$SHOULD_CONSIDER_COUNT" \
         --minor "$MINOR_COUNT" \
         --agents-completed "$AGENTS_COMPLETED" \
         --panel-size "$PANEL_SIZE" \
         --quorum-met true \
         --attempt-id "$ATTEMPT_ID" \
         "${PARTIAL_FLAG[@]}"
       ```
       No `--auto-applied` here — the plan was reverted, so no auto-applied edits remain in the working copy.
    4. **Do not run `review-attempt.sh cleanup`.** A rejected confirmation retains the attempt directory — disclose its absolute path (`$ATTEMPT_DIR`) in the report below, exactly as a terminal-record path does; the per-reviewer artifacts remain the only durable record of what the panel found before triage rewrote it.
    5. Dispatch to `/speckit-review-interactive` with the restored finding set:
       a. **Dispatch**, using the same dispatch shape as the Mode choice below, with `DISPATCH_ORIGIN=interactive` (reject is only reachable via explicit user choice at the confirmation prompt above — `--auto` mode always takes the confirm branch instead, per its skip-confirmation rule) and `$AGENTS_COMPLETED` set to the value derived above.
       b. **Route to substep 8b afterward**, not to the Context tip/Report block below, which describes the non-delegated confirm branch only — this is a delegated-skill dispatch exactly like the Mode choice's own "Fix now (Interactive)" option. `/speckit-review-interactive` emits no stop heading, so 8b runs substep **a**, finds none, and skips straight to **d** then **e** — the point of routing through 8b at all is that step 9's post-completion hook must fire on this path exactly as it does after any other delegated dispatch, not that 8b has a menu or gate re-read to perform here.

    > **Context tip:** Review findings are saved to review/review-findings.md and review/review-gate.json. Consider /clear before /speckit-tasks to free context for task generation.

    Report:
    - Gate type: secondary
    - Gate status (passed/blocked)
    - Finding counts by severity
    - Path to `review/review-findings.md`
    - **Coverage** — when `AGENTS_COMPLETED < PANEL_SIZE`, state "{AGENTS_COMPLETED}/{PANEL_SIZE} reviewers delivered findings" here in this Report block **on every terminal path this step reaches, including a passed gate and `--auto` mode** — `render-gate-report.sh` below early-returns on both, so this block is the one surface with no early return that can carry the figure.
    - **Triage summary** — skip this on the `quorum_failed` path (`review/review-findings.md` is not written there); on every other terminal status reached here, including `ok` and `all_auto_applied`, read `review/review-findings.md`'s `### Auto-Applied` and `### Discarded` sections (when present) and report: each auto-applied fix (ID + one-line description + its `Semantic`/`Additive` classification), each discarded finding (ID + one-line reason), and the count of decision points remaining in the interactive queue (`DECISION_POINT_COUNT`, read from `synthesis.done.json`). On the `all_auto_applied` path, also state whether the confirmation prompt was shown or skipped (skipped in `--auto` mode or when `ANY_SEMANTIC` was `false`). Also surface any classifier-error advisory or large-discard-set advisory noted in the `### Summary` section. The `all_auto_applied` path already covers its own confirmation prompt above — this bullet is what surfaces the same triage data on every other path.
    - Then render the gate report and emit its stdout verbatim:

      ```bash
      speckit run render-gate-report.sh \
        --gate-type "secondary" \
        --must-address "${MUST_ADDRESS_COUNT:-0}" \
        --quorum-met "$QUORUM_MET" \
        --auto-mode <true if the `--auto` flag was detected (step 1) OR `AUTO_MODE` is true (step 4c), else false> \
        --coverage "$AGENTS_COMPLETED/$PANEL_SIZE"
      ```

      On the quorum-failure path pass the literals `--quorum-met false --must-address 0`: `MUST_ADDRESS_COUNT` is never assigned on that branch, and an empty required flag is a usage error that would suppress the no-verdict explanation on the one path it exists for. Do not repurpose the `agents_completed` count written one line away — it is the real count and is nonzero in the common failure cases.

      **Fallback**: if the script is missing or exits non-zero, report the finding counts and the path to `review/review-findings.md`, then **continue to the mode choice below**. Never skip the choice because the report could not be rendered.

    - If blocked:

      **Mode choice**

      **MANDATORY GATE — DO NOT SKIP.** You MUST present the four options below and wait for the user's choice before dispatching to auto-resolve, interactive resolution, or the override path. Jumping directly to any of them without presenting this choice is a protocol violation — even if you believe you know which option the user would prefer.

      If the gate is BLOCKED (MUST-ADDRESS count > 0):
      - Display finding counts by severity
      - Present four options:
        1. **Fix now (Interactive)** — Review and resolve findings round by round, grouped by severity tier
        2. **Fix now (Auto-resolve)** — Fix all findings automatically with recommended actions
        3. **Override** — Proceed despite findings. Unresolved review findings may propagate to plan and implementation, requiring later rework.
        4. **Defer** — Leave the gate blocked and exit. To unblock, resolve the findings and re-run `/speckit-review`.

      Offer option 3 **only when a synthesized finding set exists**. If the gate report emitted the no-verdict block, offer re-running the review instead — no passing gate may be written on that path.

      **Fast-path conditions** (the ONLY cases where the mode choice above may be skipped):
      - If `--auto` flag was detected (step 1) OR `AUTO_MODE` is true (from pipeline-state, step 4c) → dispatch to `/speckit-review-auto`
      - If gate PASSED (MUST-ADDRESS count = 0) → skip to passed report

      Wait for user choice, then:
      - If "Fix now (Interactive)" or equivalent → dispatch to `/speckit-review-interactive`
      - If "Fix now (Auto-resolve)" or equivalent → dispatch to `/speckit-review-auto`
      - If "Override" or equivalent → run the override sequence below
      - If "Defer" → exit cleanly with guidance to resolve findings and re-run

      **Override sequence**

      Run the record script **first**, and rewrite the gate only if it succeeds. An orphaned override record is inert; an orphaned passing gate is not.

      ```bash
      speckit run record-gate-override.sh \
        --quorum-met true
      ```

      - On exit 0: emit the script's confirmation line, then rewrite the gate. `write-review-gate-unified.sh` validates its six required flags and exits via `usage()` on any empty value. Pass the gate-type **literal**; `GATE_TYPE` is not a variable in this preset. `--override` marks the write as originating from an override, so the gate file and the pipeline-state entry both record it — without it a genuine override is reported as a clean pass. `--panel-size` is read from the existing `review/review-gate.json` (written by synthesis) and forwarded unchanged — the override doesn't change the panel that ran. Likewise read `auto_applied`, `attempt_id`, and `partial` from the existing `review/review-gate.json` before rewriting: append `--auto-applied` when `auto_applied` is `true`, `--attempt-id "$ATTEMPT_ID"` always, and `--partial` when the existing gate's `partial` field is `true` — an override rewrite must not silently drop any field the existing gate carried. This is an in-attempt gate rewrite; an unforwarded `attempt_id` makes the gate read as "not yet written" to this command's own outcome check.

        ```bash
        speckit run write-review-gate-unified.sh \
          --gate-type "secondary" \
          --status passed \
          --must-address 0 \
          --should-consider "$SHOULD_CONSIDER_COUNT" \
          --minor "$MINOR_COUNT" \
          --agents-completed "$AGENTS_COMPLETED" \
          --panel-size "$PANEL_SIZE" \
          --quorum-met true \
          --attempt-id "$ATTEMPT_ID" \
          --override
          # Append --auto-applied when the existing review/review-gate.json's auto_applied field is true
          # Append --partial when the existing review/review-gate.json's partial field is true
        ```

        Then write the cross-cutting override annotation: `speckit run write-pipeline-state.sh review status=passed override=true`
        Then run `speckit run review-attempt.sh cleanup --attempt-dir "$ATTEMPT_DIR" --gate-file "$FEATURE_DIR/review/review-gate.json"` — the gate now passes and is durable, so the attempt directory's per-reviewer artifacts are no longer the only record.
        Then display "Gate overridden: BLOCKED → PASSED" and recommend `/speckit-tasks`.
      - On exit 3: report "override refused — gate unchanged" and do **not** rewrite the gate.

      **Dispatch to delegated skills**:

      When dispatching to auto-resolve or interactive skills, include these context variables in the Skill() prompt:

      ```
      Skill("speckit-review-auto", """
      FEATURE_DIR={FEATURE_DIR}
      FEATURE_SPEC={FEATURE_SPEC}
      GATE_TYPE=secondary
      AGENTS_COMPLETED={N}
      MUST_ADDRESS_COUNT={N}
      SHOULD_CONSIDER_COUNT={N}
      MINOR_COUNT={N}
      DISPATCH_ORIGIN={autonomous|interactive}
      PANEL_SIZE={PANEL_SIZE}

      Auto-resolve all MUST-ADDRESS findings in {FEATURE_DIR}/review/review-findings.md by applying recommended fixes to spec/plan/contracts. Once the gate has been written, attempt best-effort fixes for SHOULD-CONSIDER and MINOR findings.
      """)
      ```

      `DISPATCH_ORIGIN` is `autonomous` when this dispatch came from the fast-path condition above (`--auto` or `AUTO_MODE`) and `interactive` when the user chose "Fix now (Auto-resolve)" from the mode choice. Both paths reach the same call; only this field distinguishes them, and substep 8b below reads it to decide whether a human is waiting on a menu.

      `PANEL_SIZE` is the value derived from `synthesis.done.json` in step 8 — the designed size of this stage's own review panel.

      or

      ```
      Skill("speckit-review-interactive", """
      FEATURE_DIR={FEATURE_DIR}
      FEATURE_SPEC={FEATURE_SPEC}
      GATE_TYPE=secondary
      AGENTS_COMPLETED={N}
      MUST_ADDRESS_COUNT={N}
      SHOULD_CONSIDER_COUNT={N}
      MINOR_COUNT={N}

      Interactive resolution: present findings grouped into per-tier rounds (MUST-ADDRESS first, then SHOULD-CONSIDER, then MINOR), each round opening with a table of its findings, collect user decisions, then batch-apply edits.
      """)
      ```

      **Re-validation trigger**: After auto-resolve is dispatched (via `/speckit-review-auto`), re-validation will be triggered after auto-resolve for plan review.

    ➡️ **Successor obligation**: once the gate is passed or overridden, the next stage is `/speckit-tasks`. Always name it as the recommended next step — do not substitute an ordering of your own, and do not recommend jumping ahead to a later stage.

    - If passed:
      - If `should_consider_count == 0` AND `minor_count == 0`: "Review passed with no findings. Proceed to `/speckit-tasks`."
      - If `should_consider_count > 0`: Surface the SHOULD-CONSIDER findings so the user can decide whether to address them before proceeding. Display a summary table:

        ```
        Review passed (no MUST-ADDRESS). {should_consider_count} SHOULD-CONSIDER findings worth reviewing:

        | ID | Finding | Type |
        |----|---------|------|
        | {id} | {title} | {type} |
        | ... | ... | ... |

        These don't block the pipeline but may improve plan quality. See `review/review-findings.md` for details and recommendations.
        Proceed to `/speckit-tasks` when ready.
        ```

      - If only MINOR findings exist (no SHOULD-CONSIDER): "Review passed. {minor_count} MINOR findings logged to `review/review-findings.md`. Proceed to `/speckit-tasks`."

    **CRITICAL — After delegation or passed report**: Regardless of which path was taken (auto-resolve, interactive, proceed-without-resolving, passed fast-path, or skip-review), you MUST run substep 8b and then step 9 immediately after step 8. The delegated skills (`/speckit-review-auto`, `/speckit-review-interactive`) handle finding resolution only — they do NOT run post-completion hooks. Step 9 is YOUR responsibility and must not be skipped, and no branch of substep 8b may exit before reaching it.

8b. **Post-delegation report**: Run this substep after a delegated skill returns. If no skill was dispatched (gate passed, skip-review, override, or defer), skip it and continue to step 9.

    **a. Read the returned text for a stop heading.** The auto-resolve loop ends a run it could not finish by emitting exactly one of two headings in its completion report:

    - `### NON-CONVERGENT STOP` — an iteration confirmed none of the fixes it claimed. Auto-resolve has demonstrated it cannot make progress on these findings.
    - `### FULL-PASS FINDINGS` — the loop's targeted rounds converged, and the full adversarial pass then found MUST-ADDRESS findings of its own. Auto-resolve was not shown to fail here; one more pass surfaced something new.

    If neither heading is present, there is nothing to re-present in **b** or **c** — skip directly
    to **d**, which still runs regardless of which skill was dispatched.

    **b. Re-read the gate state from disk.** Before rendering anything, re-read `{FEATURE_DIR}/review/review-findings.md` and `{FEATURE_DIR}/review/review-gate.json` and take the counts from them. Do **not** reuse the counts derived in step 8 — the delegated run has been editing artifacts since, and presenting pre-dispatch counts would describe a state that no longer exists.

    **c. Re-present the gate menu, but only for an interactive dispatch.** When `DISPATCH_ORIGIN` was `autonomous`, render no menu: report the triage the delegated skill returned, leave the gate blocked, record no override, and continue to step 9. When `DISPATCH_ORIGIN` was `interactive`:

    - On `### NON-CONVERGENT STOP`, present a **three-option** menu — Fix now (Interactive), Override, Defer — omitting Fix now (Auto-resolve), with one sentence saying why: auto-resolve has just been tried on these findings and confirmed none of its own fixes, so offering it again would spend the same dispatches for the same result.
    - On `### FULL-PASS FINDINGS`, present a **three-option** menu — Fix now (Interactive), Override, Defer — omitting Fix now (Auto-resolve), with one sentence saying why: the targeted rounds converged, but the full adversarial pass surfaced new findings unrelated to the fixes — re-running auto-resolve would fix these, but the next full pass would surface more from the same pattern (fresh agents always find observations the prior panel missed). Interactive resolution lets you triage them directly.

    Handle the chosen option exactly as step 8 does, including the override sequence.

    **d. Surface any pending re-review recommendation.** A fresh read is needed here because a resolution session may have recorded a recommendation since step 4b ran. Use the same reader, so this read gets the same corrupt-history handling — but capture **only** the two values this substep needs, into names of their own:

    ```bash
    RECHECK=$(speckit run read-plan-review-state.sh "$FEATURE_DIR/pipeline-state.jsonl")
    RECHECK_UNREADABLE=$(printf '%s\n' "$RECHECK" | sed -n 's/^STATE_UNREADABLE=//p')
    RECHECK_RECOMMENDATION=$(printf '%s\n' "$RECHECK" | sed -n 's/^PENDING_RECOMMENDATION=//p')
    ```

    Do **not** `eval` the reader's output here. `eval` would reassign all six variables, including `AUTO_MODE`, `SKIP_REVIEW` and both seq values that step 4b resolved and the run has been acting on since — overwriting settled decisions with a late re-read for the sake of one field.

    If `RECHECK_UNREADABLE` is not `false`, or `RECHECK_RECOMMENDATION` is empty, say nothing here rather than guessing. Otherwise, if `RECHECK_RECOMMENDATION` is `pending`, surface the command it names **alongside** — never in place of — the Successor obligation's recommendation of `/speckit-tasks`, and say that it comes from a resolution session substantial enough to be worth re-reviewing.

    **e. Continue to step 9.** Every branch above ends here. The post-completion hook runs regardless of which menu was rendered or which option was chosen.

9. **Post-completion hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.after_review` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`) — if a mandatory hook's invocation fails or terminates abnormally, halt with "`<stage>` completed but the follow-up step failed — re-run `/<command>` to retry" (a hook returning a result, including a blocking one, is a successful dispatch, not a failure); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue. This step MUST execute after every review completion, including after auto-resolve delegation, interactive resolution, the proceed-without-resolving override, gate-passed fast path, skip-review fast path, and an aborted, infrastructure-failed, or ceiling-blocked review from step 7's protocol hand-off. Skipping this step causes sdd-commit and pipeline-state hooks to not fire, leaving artifacts uncommitted.

10. **➡️ Confirm next step (ALWAYS RUN — DO NOT OMIT)**: Now that the hook(s) in step 9 have finished executing, state in one line which command is next. If the gate is passed or overridden: `/speckit-tasks`, without repeating step 8's full report. Otherwise (deferred, or a terminal record left the gate blocked): state that the gate remains blocked and name `/speckit-review` as the command to re-run once the findings are addressed. This one-line confirmation must be the last thing shown to the user this turn.
