---
name: speckit-verify-auto
description: 'SpecKit internal: auto-resolve convergence loop for `/speckit-verify`.'
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:meta
  meta_preset_strategy: replace
user-invocable: true
disable-model-invocation: false
---



# Speckit Verify Auto Skill

## Workspace Check

**Workspace check (MANDATORY)**: Run `speckit run require-workspace.sh`. This resolves the workspace from any subdirectory and produces the same fixed message when there is no workspace above the current directory. On a non-zero exit, relay its stderr output to the user verbatim — do not paraphrase, reword, summarize, or translate it; do not prepend or append anything (no preface, heading, or attribution such as "require-workspace.sh failed:"); do not name the script, the command, the exit code, or any internal path — then halt. On exit 0, proceed silently to the next check.

## Context Loading

Parse the dispatch prompt for these variables:
- **FEATURE_DIR**: Feature directory path
- **SPEC_DIR**: Spec directory (spec mode) or constitution directory (constitution mode) — the dispatch contract always names this variable `SPEC_DIR` regardless of mode
- **MODE**: `spec` or `constitution`
- **AGENTS_COMPLETED**: Number of agents that completed
- **MUST_ADDRESS_COUNT**: Count of MUST-ADDRESS findings
- **SHOULD_CONSIDER_COUNT**: Count of SHOULD-CONSIDER findings
- **MINOR_COUNT**: Count of MINOR findings
- **DISCOVERY_COUNT**: Count of DISCOVERY findings

Read `{SPEC_DIR}/verification.md` (`MODE = spec`) or `{SPEC_DIR}/constitution-verification.md` (`MODE = constitution`) to reconstruct synthesis state. Parse all findings from the MUST-ADDRESS, SHOULD-CONSIDER, and MINOR sections. **Do NOT parse or touch DISCOVERY findings** — they carry no checkbox, require no action, and are never part of the auto-fix loop.

## Progress Reporting — MANDATORY

The convergence loop re-dispatches the verify agents (4 in spec mode, 1 in constitution mode) on every iteration, and each dispatch can take minutes. Every `LOG:` line below is **user-facing output, not pseudocode commentary**: emit it to the user at the moment the pseudocode reaches it. Do not batch these to the end of the run and do not wait for the loop to exit.

- **Before entering the loop**, state how many MUST-ADDRESS findings will be attempted, that the verify agents will be re-dispatched to validate each round, and that the loop may run for several minutes. If `AGENTS_COMPLETED` is less than the full agent panel (4 in spec mode, 1 in constitution mode) — indicating the originating verification was `partial` — additionally warn that convergence may not be achievable, since the agents that failed originally may fail again on re-dispatch.
- **When a multi-minute dispatch begins**, say so before it starts — not only when it returns. This applies to every convergence re-dispatch.
- **At every iteration boundary**, report the MUST-ADDRESS count before and after.
- **When the loop exits** — whether by reaching zero or by iteration exhaustion — state which findings remain unresolved and what state the artifacts were left in.

**No `auto_mode` suppression.** This skill is only ever reached through an already-unattended dispatch — auto-resolve is itself the auto path — so there is no "quiet mode" to suppress into. Progress is emitted unconditionally as the audit record of what the loop did to the artifacts.

## Convergence Loop

**Relationship to `speckit.review-auto.md`**: this loop does NOT snapshot `spec.md`/`plan.md` and does NOT roll back on failure. Neither does review-auto — the two loops now share the same retention policy, and every fix that reaches disk and clears every check this loop runs over it stays there whichever way either loop ends. What differs between them is scope: verify's findings can route to `code` across many files, where review's are confined to `spec.md`, `plan.md` and `contracts/`. See "Partial Fix Retention" below for what retention means on this path.

Execute a 3-iteration auto-fix loop:

````
ITERATION = 0
MAX_ITERATIONS = 3
GATE_BLOCKED = false
PROPAGATED_CONSTITUTION = []

LOG: "Auto-resolving {MUST_ADDRESS_COUNT} MUST-ADDRESS findings across up to {MAX_ITERATIONS} iterations. Each iteration re-dispatches the verify agents to validate the fixes, so this may run for several minutes."

LOOP (while ITERATION < MAX_ITERATIONS AND MUST_ADDRESS_COUNT > 0):
  ITERATION += 1
  PREVIOUS_COUNT = MUST_ADDRESS_COUNT
  LOG: "Iteration {ITERATION}/{MAX_ITERATIONS}: applying fixes for {PREVIOUS_COUNT} MUST-ADDRESS findings."

  Compose, then check, then write. This runs for every target file this iteration touched,
  without regard to how many fixes it received or whether it is a markdown artifact or a
  source file.

  Identify this iteration's constitution MUST findings before grouping, using the same
  dual-signal check the interactive verify preset uses:

  ```
  IS_CONSTITUTION_MUST = finding.severity == "MUST-ADDRESS" AND (
    finding.id starts with "CC-"
    OR finding.agent_name contains "Constitution Compliance"
    OR finding.agent_name contains "Constitution Validator"
  )
  ```

  Agent-name matching uses "contains" semantics, not exact-match. An ambiguous partial match
  defaults to the standard (non-constitution) treatment. In constitution mode every finding
  comes from the single Constitution Validator agent, so `IS_CONSTITUTION_MUST` is true for
  every MUST-ADDRESS finding that mode's batch contains — this is the expected, correct
  outcome of the check, not a false-positive to be corrected.

  Order this iteration's MUST-ADDRESS findings so constitution MUST findings are planned and
  composed first, ahead of the rest of the batch. This is an ordering within the same
  Compose-Check-Write cycle, not a separate pass — a constitution finding's fix still lands in
  the same composed file alongside every other fix this iteration, going through the same
  `Holistic reconciliation pass` below rather than a standalone per-finding write. That keeps
  holistic reconciliation coverage over the whole batch, at the cost of one additional dispatch
  per iteration (the post-write compliance re-check described after the per-file write loop
  below), not one dispatch per constitution finding.

  **Known accepted gap.** This dual-signal check does not match RV-prefixed re-validation
  findings — those are emitted by a re-validation agent (name "Re-Validation", ID prefix `RV-`)
  that exists in `speckit.review-auto.md`'s own convergence loop, not in this file's. Verify-auto
  re-dispatches its own verify agent panel each iteration rather than running a separate
  re-validation pass, so no RV-prefixed finding is ever produced here — the gap does not arise
  in this file's flow, but the check's signal definition is shared across the auto-resolve
  presets and is documented here for that reason.

  Group interacting findings before planning any fix. Dispatch a `general-purpose` Agent
  (`model: "sonnet"`) to run `Resolution grouping`:

  ```
  Read and execute `.specify/templates/resolution-grouping.md`.

  ACCEPTED=<this iteration's MUST-ADDRESS findings, each with ID, tier, target artifact, evidence, recommendation>
  TIER=MUST-ADDRESS
  CANDIDATE_SET=<this mode's declared artifacts: in spec mode, spec.md, plan.md, tasks.md
  and the files under contracts/; in constitution mode, constitution.md alone>

  Return GROUPS: for each group, its member finding IDs, the matched signal, and the
  artifacts it spans.
  ```

  If the agent reports the template is not present, stop: do not compose and do not
  write any file, report in plain language that the interaction check could not be run
  and name the file that is absent, and do not record a passing gate. Nobody is watching
  this run, so degrading silently to ungrouped resolution would leave no trace that the
  step was skipped.

  Findings here carry an explicit route, so
  grouping takes each finding's target at its word rather than inferring it.

  For each MUST-ADDRESS finding, plan the change without applying it:
    - route: spec.md | plan.md | tasks.md | constitution.md → the finding's Suggestion, applied to that artifact
    - route: code → a context-aware code change grounded in the spec's requirements (and the
      constitution) that addresses the finding, generated WITHOUT user confirmation
      (this is the auto-mode deviation from `speckit.verify-interactive.md`, which requires user confirmation before applying code changes — auto mode is fully unattended)
    - for a group of two or more, plan one coordinated change satisfying every member
      together rather than one change per member

  For each target file with at least one fix this iteration:
    - Compose the file's full new content in memory, from its pre-fix content plus every fix
      routed to it. Compose a coordinated fix once per group and apply it to every file that
      group spans, or to none of them. Retain that pre-fix content for the rest of this
      iteration — the check needs it to tell a defect this iteration introduced from one it
      inherited. Note which regions each fix wrote, which findings contributed, and which
      groups span this file; for a source file, that region list is what confines the check
      to code this run actually touched.
    - Run the `Holistic reconciliation pass` by dispatching a `general-purpose` Agent
      (`model: "opus"`):

      ```
      Read and execute `.specify/templates/holistic-reconciliation.md`.

      COMPOSED=<map: file path → candidate content after all fixes applied>
      BASELINES=<map: file path → pre-fix content>
      WRITTEN_REGIONS=<map: file path → spans this run wrote>
      CONTRIBUTING=<map: file path → finding IDs>
      CANDIDATE_SET=<this mode's declared artifacts — same set bound for grouping above;
      for a code-routed fix, the files this run already wrote plus the files the contributing
      finding's own evidence cites, never a repository-wide search for callers or
      similarly-named files>
      USER_PRESENT=false
      GROUPS=<groups from the grouping step>

      For each file, report: defects found (quoted, classified, attributed), then outcome
      (clean / repaired / unrepairable).
      ```

      This path is unattended by construction, so bind its user-present input to false. Pass
      the groups formed above as its groups input, so a coordinated fix is one repair unit
      rather than several.
      Bind the candidate set to this mode's declared artifacts — the same set bound for
      grouping above. This binding is what lets the check reach a rule a fix here changed that
      a counterpart still states in its superseded form; without it that class cannot fire,
      because a counterpart receives no fix of its own and comparing it against its own pre-fix
      content finds nothing. In constitution mode the set has one member, so
      the cross-artifact reach is inert — a correct outcome, reported as a pass
      with no counterpart in scope, not as a skipped check.
      If the agent reports the template is not present, stop: do not write the
      file, report in plain language that the consistency check could not be run
      and name the file that is absent, and do not record a passing gate.
    - On a clean or repaired outcome: state every defect found before stating the outcome,
      name any accepted fix the repair altered or removed, then write the file and mark each
      contributing finding resolved in verification.md (or constitution-verification.md).
    - On an unrepairable outcome: discard every fix for this file this iteration and do not
      write it. Leave the contributing findings unresolved and their checkboxes unchecked,
      include them in this iteration's non-convergence reporting, and set GATE_BLOCKED = true
      where at least one contributing finding is of a blocking tier — the run-scoped condition
      that forces a non-passing gate regardless of any later recount, because a discarded
      finding that fails to resurface must not yield a passing gate. A discard whose
      contributing findings are all of an optional tier leaves the condition untouched:
      nothing was written, so nothing broken landed, and the gate does not rest on those
      fixes. The file's content is unchanged, so do not re-dispatch validation over it.
    - Where a discarded fix was a coordinated one, discard it from **every** file that group
      spans, including files whose own outcome was clean. Those other files still get written
      — their unrelated fixes land, and only the coordinated fix is withdrawn from them.
      Recompose each such file without the withdrawn group before writing it, and leave that
      group's findings unresolved everywhere. Writing a coordinated fix into one file and not
      the other is the split-artifact contradiction this check exists to prevent.

  Order the bookkeeping after every outcome. Findings-file checkbox updates and log appends
  happen only once every composed file this iteration has an outcome; earlier, a discard
  skips the file write while the checkbox already records the finding resolved, leaving the
  findings file and the artifact disagreeing and the next round reading it as already fixed.

  ARTIFACTS_WRITTEN = the number of files written this iteration.

  If ARTIFACTS_WRITTEN == 0:
    LOG: "Iteration {ITERATION}: every fix composed this iteration was discarded by the consistency check. No artifact changed, so there is nothing new to validate. Unresolved: {list of finding IDs}. The gate will remain BLOCKED."
    Exit the loop.

  If this iteration's batch included at least one `IS_CONSTITUTION_MUST` finding whose file was
  written this iteration:
    Dispatch exactly ONE post-write constitution compliance re-check for the whole iteration —
    never one per finding, even in constitution mode where every MUST-ADDRESS finding in the
    batch is `IS_CONSTITUTION_MUST`. Dispatch a `general-purpose` Agent (`model: "opus"`), framed
    with the Constitution Validator's identity — the same role `speckit.verify.md` gives that
    agent for constitution-mode dispatch — over:
      - the full content of every artifact this iteration wrote, as written to disk
      - the full content of `constitution.md`
    Prompt: report PASS if the written content complies with every constitution principle, or
    itemize each violation with its principle identifier, title, and description.

    **Success/failure criteria.** A constitution MUST finding's fix **succeeds** the re-check
    when the specific violation that finding named is no longer present in the re-check's output
    AND no violation appears that was absent before this iteration's fix. A violation already
    present before this iteration (inherited, not introduced by this iteration's fix) does NOT
    count as a failure for that finding — only a violation that **worsened** (absent before,
    present after) fails the re-check for the finding whose fix introduced it.

    For each constitution MUST finding this iteration attempted:
      - **On success**: leave its resolution exactly as the compose-check-write cycle above
        already recorded — checkbox `[x] Resolved`, counted toward this iteration's reduction
        of `MUST_ADDRESS_COUNT`.
      - **On failure**: add the finding to `PROPAGATED_CONSTITUTION`, set `GATE_BLOCKED = true`
        — the same run-scoped condition the discard branch above sets, which forces a
        non-passing gate regardless of any later recount — and exclude the finding from every
        subsequent iteration's batch (see the exclusion clause below). Discard the failed fix
        from disk: it never survives as a resolved fix, carries no partial resolution state, and
        gets no partial, surgical un-application in place. Scope that precisely — two different
        disk targets, two different treatments:
          - **The findings-tracking file** (`verification.md` or `constitution-verification.md`):
            revert the checkbox this finding's compose-check-write cycle set to `[x] Resolved`
            back to `- [ ] Resolved`. This is bookkeeping correction, not the artifact
            recomposition below.
          - **The artifact the fix targeted** (`spec.md`/`plan.md`/`tasks.md`/`constitution.md`/
            code): recompose it from its retained pre-fix content plus every other fix this
            iteration composed into it, excluding every constitution fix this re-check failed,
            then rewrite it — the same recompose-and-rewrite mechanism used above for discarding
            one member of a coordinated group (see "Where a discarded fix was a coordinated one"
            above). That file may carry other, unrelated fixes composed alongside this one;
            recomposing from the retained pre-fix content plus those other fixes — never by
            patching the written content in place — is what keeps them intact while removing only
            the failed fixes. Where more than one constitution fix targeting the same file failed
            this re-check, recompose that file once with all of them excluded, never once per
            failed finding — a second per-finding recompose would restore the fix the first one
            removed. Its content on disk after this step never carries the violation this
            re-check found.

    LOG: "Iteration {ITERATION}: constitution compliance re-check — {P} finding(s) confirmed
    resolved, {F} finding(s) still violate the constitution after their fix and are propagated
    for manual resolution."

  Re-read every modified artifact and re-compute SPEC_CONTENT and CODE_FILES — the same variables `speckit.verify.md`'s target-extraction logic computes — so the next re-dispatch sees current content, not stale in-memory copies.

  LOG: "Iteration {ITERATION}: re-dispatching the verify agents to validate. This dispatch takes several minutes."
  If MODE == "spec":
    Re-dispatch the SAME 4 agents `speckit.verify.md` uses for spec-mode dispatch (Alignment, Coverage, Freshness, Cross-Artifact) with the same prompts and doctrine-append pattern. Do NOT re-dispatch review agents — this is verify's own agent panel, not the adversarial review panel.
  Else (MODE == "constitution"):
    Re-dispatch the single Constitution Validator agent `speckit.verify.md` uses for constitution-mode dispatch.

  Parse the new findings; count new MUST-ADDRESS.
  Exclude any finding matching a member of `PROPAGATED_CONSTITUTION` from this count and from
  every subsequent iteration's batch — it already received its one fix attempt and failed the
  compliance re-check above, and the underlying violation will keep resurfacing in every
  re-dispatch since it was never durably resolved. Retrying it spends an iteration this run
  does not get back; `GATE_BLOCKED` already keeps the gate from passing regardless of whether
  this exclusion lets the count reach zero.
  NEW_MUST_ADDRESS_COUNT = count of MUST-ADDRESS findings from new validation

  If NEW_MUST_ADDRESS_COUNT >= PREVIOUS_COUNT:
    LOG: "Iteration {ITERATION}: Non-convergent auto-fix. MUST-ADDRESS count did not reduce ({PREVIOUS_COUNT} → {NEW_MUST_ADDRESS_COUNT}). Findings attempted: {list of finding IDs}."
  Else:
    LOG: "Iteration {ITERATION}: Reduced MUST-ADDRESS from {PREVIOUS_COUNT} to {NEW_MUST_ADDRESS_COUNT}."

  MUST_ADDRESS_COUNT = NEW_MUST_ADDRESS_COUNT
  # This assignment carries no authority over GATE_BLOCKED. A count that fell to
  # zero because a discarded finding failed to resurface is not a resolved gate.
END LOOP

If MUST_ADDRESS_COUNT > 0:
  LOG: "Auto-fix exhausted ({MAX_ITERATIONS} iterations). {MUST_ADDRESS_COUNT} MUST-ADDRESS findings remain unresolved: {list of remaining finding IDs}. Fixes are NOT rolled back — validated changes are retained. The gate remains BLOCKED."
Else:
  LOG: "Auto-fix successful. All MUST-ADDRESS findings resolved in {ITERATION} iteration(s)."
````

**Why the skipped re-dispatch exits rather than continuing.** An iteration in which every composed fix was discarded left every artifact unchanged. Re-dispatching over unchanged content spends several minutes to return the same findings, and produces no new count — leaving the blocking counter at its previous value reads to the loop as "the count did not reduce", burning iterations on nothing until the loop exhausts.

**A divergence this path carries.** Discarding a file's fixes discards *all* of them, including fixes unrelated to the defect that failed the check. That matches what this path already did with an incoherent file and is deliberately less retentive than the treatment a passing artifact gets, where every accepted fix is preserved. There is no user here to pick a subset, and guessing which fix caused the incoherence is exactly the judgement the check declined to make.

**The retention rule is deliberately asymmetric, and the two halves must not be reconciled.** In the *failing* file, everything goes — including unrelated fixes. In a *passing* file that a discarded coordinated fix also spanned, only that coordinated fix is withdrawn and the unrelated fixes still land. A reader meeting these side by side will be tempted to make them consistent in one direction or the other. Do not. The failing file is the one whose composed content the check could not vouch for, so nothing in it is trustworthy; a passing file's content was read and found sound apart from the group being withdrawn, so discarding its unrelated fixes would throw away verified work for no reason. Changing either half means deciding which of those two situations the other one actually resembles, which is a real decision and not a tidy-up.

**Constitution mode note**: in constitution mode, `route` is always `constitution.md` — there are no code-routed findings, so the code-confirmation-waiver distinction above never applies in this mode.

## Partial Fix Retention

On convergence failure (loop exhausted with `MUST_ADDRESS_COUNT > 0`), keep every fix applied through the last iteration — including the failed final iteration, since some of its fixes may have succeeded while others didn't and iteration re-validation is holistic per-round, not per-fix, so there is no cheap way to isolate which individual fix caused the non-convergence. Do NOT revert any artifact.

Produce a resolution summary documenting which findings were resolved during the loop and which remain — this is a current-state record alongside the original verification report, not a replacement for it.

Offer the user three follow-ups:
1. **Interactive resolution for the residuals** — recommend re-running `/speckit-verify`, which re-enters the mode-choice gate and can route to `/speckit-verify-interactive`.
2. **Override** — recommend the override path in `speckit.verify.md`'s mode choice gate.
3. **Manual revert via source control** (e.g. `sl`) — this is the user's responsibility; verify-auto does not perform reverts itself.

## Best-Effort Optional Pass

After the MUST-ADDRESS convergence loop exits with `MUST_ADDRESS_COUNT == 0` — do NOT run this pass if convergence failed and findings remain — attempt a single best-effort pass over SHOULD-CONSIDER, then MINOR findings:

```
If MUST_ADDRESS_COUNT == 0 AND (SHOULD_CONSIDER_COUNT > 0 OR MINOR_COUNT > 0):
  LOG: "All MUST-ADDRESS findings resolved. Attempting best-effort fixes for {SHOULD_CONSIDER_COUNT} SHOULD-CONSIDER and {MINOR_COUNT} MINOR findings. The gate is recorded once these are done."

  For each SHOULD-CONSIDER finding, then each MINOR finding:
    - Generate the fix per its route — including route: code, generated WITHOUT confirmation, same as MUST-ADDRESS fixes in auto mode

  Then compose, check and write exactly as the convergence loop above does: compose each
  target file from its pre-fix content plus every fix routed to it, dispatch the `Holistic
  reconciliation pass` Agent over the composed content with USER_PRESENT=false, carry the
  same missing-template stop, write only on a clean or repaired outcome, and discard a file's
  fixes on an unrepairable one. Mark each finding whose file was written as resolved
  in verification.md (or constitution-verification.md) and decrement the corresponding count.
  A discard in this pass does NOT set GATE_BLOCKED: every finding here is of an optional tier,
  nothing was written, and the gate does not rest on those fixes. Report them unresolved and
  leave the gate as the convergence loop left it.

  LOG: "Best-effort pass complete. Resolved {N} SHOULD-CONSIDER ({M} remain) and {P} MINOR ({Q} remain)."
```

A finding **fails** when the agent cannot produce a fix at all — this is a deliberately looser standard than the MUST-ADDRESS loop. **No re-validation**: unlike MUST-ADDRESS fixes, these are not sent back to the verify agents — once a fix is composed and passes the consistency check, it is written and no agent re-examines it. The consistency check itself is not waived here: a best-effort fix writes the same artifacts a blocking fix does, so an unchecked one can leave the spec or the code self-contradictory just as easily. **No rollback**: if a fix cannot be applied cleanly, skip it and move to the next finding.

## Constitution MUST Compliance Propagation

If `PROPAGATED_CONSTITUTION` is non-empty after the convergence loop exits, append the section
below to `verification.md` (or `constitution-verification.md` in constitution mode), replacing
any prior instance of this section — never duplicating it:

```markdown
## ⚠️ Unresolved Constitution Compliance

The following constitution violations could not be resolved automatically. Each
received one fix attempt with a full compliance re-check. The violations persist
and require manual resolution.

| Finding | Principle | Auto-fix attempted | Why it persists |
|---------|-----------|-------------------|-----------------|
| {ID} | {principle identifier}: {title} | Yes | {re-check failure reason} |
```

Remove the section entirely when `PROPAGATED_CONSTITUTION` is empty — this is a
replace-on-rerun, remove-on-resolution artifact, not an append-only log. It is purely
informational: no downstream stage reads or acts on this section, and its presence or
absence has no effect on gate status — `GATE_BLOCKED` already carries that.

Record the propagation in pipeline state:

```bash
speckit run write-pipeline-state.sh verify constitution_must_propagated=true constitution_must_count={N}
```

where `{N}` is the count of findings in `PROPAGATED_CONSTITUTION`. Skip this call when
`PROPAGATED_CONSTITUTION` is empty — there is nothing to record.

## Update Gate After Resolution

This skill is only ever dispatched when the gate was `blocked` (`speckit.verify.md`'s mode-choice gate never dispatches either resolution skill on a passed gate), so the loop above always runs at least one iteration and always has a chance to apply fixes to `spec.md`/`plan.md`/`tasks.md`/code. Write the gate exactly once after the loop exits, on both outcomes:

```bash
speckit run write-review-gate-unified.sh \
  --stage verify \
  --gate-type "verify" \
  --status <passed if MUST_ADDRESS_COUNT == 0 AND GATE_BLOCKED is false, else blocked> \
  --must-address "$MUST_ADDRESS_COUNT" \
  --should-consider "$SHOULD_CONSIDER_COUNT" \
  --minor "$MINOR_COUNT" \
  --agents-completed "$AGENTS_COMPLETED" \
  --resolved
```

**If this call exits 4** (the `implement` prerequisite is unmet — unexpected here, since this skill is only reached after a prior verify write already succeeded, but possible if history changed underneath this run): Read and execute `.specify/templates/prerequisite-refusal-gate.md` before treating this as an ordinary write failure. This flow is unattended by construction, so follow that template's unattended-run guidance — halt with the diagnostic rather than presenting the three-way choice.

If `GATE_BLOCKED` is true, write `blocked` whatever the count says, and report which findings were discarded by the consistency check and why the gate stays blocked. A zero count there does not mean the work was done — it can equally mean a discarded finding failed to resurface in the last validation round.

`--resolved` records that any `spec.md`/`plan.md`/`tasks.md` edits now on disk came from this run's own sanctioned auto-fix loop, not incidental drift — `sapling-commit.sh`'s `after_verify` branch reads this field to decide whether to widen its commit scope beyond `verification.md`/`pipeline-state.jsonl`/`verify-gate.json`. Call this on convergence (status `passed`, must-address `0`) **and** on exhaustion (status `blocked`, must-address the final count) — Partial Fix Retention below means exhaustion can still leave real, applied edits on disk that need the same commit-scope treatment as a clean convergence. This single call both updates the gate status and writes the pipeline-state entry for the resolution — `write-review-gate-unified.sh` writes pipeline-state internally.

## Auto-Resolution Log

Each convergence iteration discards previous iteration agent outputs after parsing findings — only the parsed finding list and current artifact content carry forward between iterations.

Record all auto-fix actions:

```markdown
## Auto-Resolution Log

- **Decision Point**: BLOCKED fix prompt
- **Auto-Resolved Value**: [Auto-fix attempted / N/A if gate passed]
- **Reasoning**: [If auto-fix attempted: "Auto-fixed MUST-ADDRESS findings in {N} iteration(s). Convergence: {convergent/non-convergent}. Final status: {all resolved/exhausted with {M} unresolved, fixes retained}" / If gate passed: "Gate passed, no auto-fix needed"]
- **Iteration Details** (if auto-fix attempted):
  - Iteration 1: Reduced MUST-ADDRESS from {X} to {Y}
  - Iteration 2: Non-convergent ({Y} → {Z}, did not reduce)
  - [etc., up to 3 iterations]
- **Best-Effort Pass**: Resolved {N} SHOULD-CONSIDER, {M} MINOR (or "not run — must-address unresolved")
- **Consistency Check** (one entry per file composed, in every pass):
  - {file}: defects found — {each defect quoted and classified, or "none"}
  - {file}: outcome — {clean | repaired | discarded}{, and for a repair, what it changed and any accepted fix it altered or removed}
- **Discarded** (omit when nothing was discarded): {finding IDs left unresolved because their file failed the check}, gate forced to remain BLOCKED
```

The consistency-check entries state each file's defects **before** its outcome, and the discard summary after both — a verdict whose evidence is not visible first cannot be checked by whoever reads this log later. Nobody watched this run, so the log is the only surviving account of what the check decided.

Append it to `{FEATURE_DIR}/auto-resolution-log.md`:

1. Check if `{FEATURE_DIR}/auto-resolution-log.md` exists.
2. If not, create it with header: `# Auto-Resolution Audit Trail`
3. Append a new section with timestamp:
   ```markdown
   ## speckit.verify — {ISO 8601 timestamp}

   {decision entries from auto-resolution log above}
   ```
4. If the gate passed with no auto-fix attempted (`MUST_ADDRESS_COUNT` started at 0), still log the event for audit purposes.

## Completion Report

Report:
- Auto-fix outcome (success, exhausted-with-retention, or gate passed immediately)
- The consistency check's results: for each file composed, the defects found before the outcome, then a run-level summary of how many files were checked, written and discarded
- Final finding counts
- Any findings left unresolved because their file's fixes were discarded by the check
- Gate status (BLOCKED → PASSED, or remains BLOCKED with fixes retained — including when the counts reached zero but a discard forced it to stay blocked)
- **➡️ Recommend next pipeline command:**
  - `MODE = spec`: gate passed → `/pre-review` or diff submission per `speckit.verify.md`'s completion-report guidance; gate still blocked → the three follow-ups from Partial Fix Retention above
  - `MODE = constitution`: gate passed → nothing further, constitution verified; gate still blocked → the three follow-ups from Partial Fix Retention above
