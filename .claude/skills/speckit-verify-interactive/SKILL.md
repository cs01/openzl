---
name: speckit-verify-interactive
description: 'SpecKit internal: interactive resolution flow for `/speckit-verify`.'
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:meta
  meta_preset_strategy: replace
user-invocable: true
disable-model-invocation: false
---



# Speckit Verify Interactive Skill

## Workspace Check

**Workspace check (MANDATORY)**: Run `speckit run require-workspace.sh`. This resolves the workspace from any subdirectory and produces the same fixed message when there is no workspace above the current directory. On a non-zero exit, relay its stderr output to the user verbatim — do not paraphrase, reword, summarize, or translate it; do not prepend or append anything (no preface, heading, or attribution such as "require-workspace.sh failed:"); do not name the script, the command, the exit code, or any internal path — then halt. On exit 0, proceed silently to the next check.

## Context Loading

Parse the dispatch prompt for these variables:
- **FEATURE_DIR**: Feature directory path
- **SPEC_DIR**: Spec directory (spec mode) or constitution directory (constitution mode) — the dispatch contract reuses this one variable name for both cases; it is never called `CONSTITUTION_DIR` inside this skill
- **MODE**: `spec` or `constitution`
- **AGENTS_COMPLETED**: Number of agents that completed
- **MUST_ADDRESS_COUNT**: Count of MUST-ADDRESS findings
- **SHOULD_CONSIDER_COUNT**: Count of SHOULD-CONSIDER findings
- **MINOR_COUNT**: Count of MINOR findings
- **DISCOVERY_COUNT**: Count of DISCOVERY findings

Read the verification report:
- `MODE = spec`: read `{SPEC_DIR}/verification.md`
- `MODE = constitution`: read `{SPEC_DIR}/constitution-verification.md`

Validate structure:
- Check required sections exist: `### MUST-ADDRESS`, `### Summary`
- Parse finding counts from section headers (e.g., `### MUST-ADDRESS (5)`)
- Verify counts match the context variables from the dispatch prompt. Record any per-tier discrepancy — do not error. Each round opener reports its own tier's discrepancy (see the round opener's count-mismatch variant, below); a tier that produces no round at all (its parsed count is zero) has no opener to carry the report, so its discrepancy is stated in the queue-level note instead.
- If the file is malformed, truncated, or missing required sections → ERROR: "verification.md is malformed or incomplete. Re-run `/speckit-verify` to regenerate." (substitute `constitution-verification.md` in constitution mode) and exit

Parse all findings from MUST-ADDRESS, SHOULD-CONSIDER, MINOR, and DISCOVERY sections for interactive presentation.

> **MANDATORY: One Write call per file.** Do NOT use sequential Edit calls to apply findings one at a time — this creates excessive tool call noise and risks partial application if the session is interrupted mid-sequence. Instead, build the complete updated content in memory and emit a single Write call per target file. This is non-negotiable.

## Component 1: Presentation Ordering

Use the in-memory findings from validation (not re-parsed from file) — the agent count and finding metadata are already available.

Build the presentation queue:
1. Filter out DISCOVERY findings — these are informational only, never presented in the interactive loop, never touched by any action, and never form a round, a table row, or a boundary, however many there are.
2. Group remaining findings by severity tier: MUST-ADDRESS, SHOULD-CONSIDER, MINOR
3. Within each tier, sort by:
   - **Primary**: agent count descending, using the `**Related**:` annotation as the proxy — a finding carrying a `**Related**:` line was synthesized from 2+ sources by Step 4's cross-reference heuristic (its own ID plus the count of related IDs approximates the source count) and sorts before a finding with no `**Related**:` line
   - **Secondary**: original document order from the verification report (for findings with the same agent-count proxy)
4. Concatenate tiers in order: all MUST-ADDRESS, then all SHOULD-CONSIDER, then all MINOR

**Partition the queue into rounds.** One round per tier that has at least one finding after filtering — MUST-ADDRESS, then SHOULD-CONSIDER, then MINOR, in that order. A tier with zero findings after filtering produces no round at all: it is suppressed at partition time, and contributes nothing to the walk, the opener, or the beyond-round remainder breakdown. Fix each round's membership and row numbering (the table's `#` column) at partition time; never recompute or reorder them while walking findings. The intra-tier ordering established in step 3 above is preserved exactly within each round.

For every round, compute the count of findings beyond it, broken down by the tier(s) those findings belong to — this is what the round opener and the boundary prompt report as the findings remaining beyond the round.

**Group interacting findings within each round.** Once the rounds are fixed, dispatch a `general-purpose` Agent (`model: "sonnet"`) for each round to run `Resolution grouping`:

```
Read and execute `.specify/templates/resolution-grouping.md`.

ACCEPTED=<this round's findings, each with ID, tier, target artifact, evidence, recommendation>
TIER=<this round's tier>
CANDIDATE_SET=<this mode's declared artifacts: in spec mode, spec.md, plan.md, tasks.md
and the files under contracts/; in constitution mode, constitution.md alone>

Return GROUPS: for each group, its member finding IDs, the matched signal, and the
artifacts it spans.
```

Grouping runs once per round and never spans two — each round is one tier, and the procedure does not cross tiers.

Findings here carry an explicit route, so grouping takes each finding's target at its word rather than inferring it. Where a finding's route is `code`, the file it names is its target.

**If the agent reports the template is not present, stop.** Do not open a round, do not present a finding, and do not write any artifact. Tell the user in plain language that the interaction check could not be run and name the file that is absent, and do not record a passing gate.

Grouping does not change round membership, the table's `#` column, or the beyond-round counts — those are fixed above and stay fixed. It changes only how the round's findings are decided in Component 2: members of one group are presented together and decided under a single combined action prompt instead of one at a time. A finding that matched nothing forms a group of one and is walked exactly as it is without grouping.

DISCOVERY findings are handled by their own one-line summary at the end of Component 5, not here — see that component. They are filtered out before grouping runs, so they never appear in a group. If a tier produced no round despite a non-zero count reported at dispatch (the discrepancy recorded during validation), state that discrepancy in a queue-level note before the first round opener — no round opener exists for that tier to carry it.

**Empty queue**: if partitioning produces no rounds at all (every tier is empty), state that no round is opened, and proceed directly to Component 4 (end-of-loop handling). No gate transition is asserted in this case — an empty queue has nothing for a gate write to reflect either way.

## Component 2: Interactive Loop

For each round in the presentation queue:

1. **Round opener**: emit the opener line(s) and the round's table as **one instruction block** — they must never render apart. This step executes once per round, never once per finding.

   ```
   > **{TIER} round** — {round size} findings. {blocking statement}
   > {beyond-round count} findings remain beyond this round ({tier breakdown}).

   | # | ID | Summary |
   |---|-----|---------|
   | 1 | V-NNN | {restatement-or-title} |
   | … | … | … |
   ```

   - **Tier name**: use the findings-file severity label — `MUST-ADDRESS`, `SHOULD-CONSIDER`, or `MINOR` — never the gate report's plain-language tier names.
   - **Blocking statement**: `These findings block the gate.` for MUST-ADDRESS; `These findings do not block the gate.` for SHOULD-CONSIDER and MINOR.
   - **Round size**: the number of findings in this round, fixed at partition time.
   - **Beyond-round remainder**: the count of findings beyond this round, broken down by tier. Omit this second line entirely on the last round — there is nothing beyond it.
   - **Table**: lists every finding in the round — no elision, no `…` in real output. There is no threshold below which the table is suppressed; it renders at every round size, including a round of one.
   - **Row `#`**: equals the round-scoped position the finding display step later reports for that finding.
   - **`Summary` column**: resolves through the restatement-or-title rule stated under Display finding, below — the finding's `**Digest**:` value where present, its title where absent. Verify carries no `**Digest**:` producer today, so this rule currently always yields the title; the rule itself is what the preset text states, not that outcome, so no wording changes when a verify-side producer lands.

   **Count-mismatch variant** (applies to every tier, not only MUST-ADDRESS): if this tier's parsed round size disagrees with the count recorded from the dispatch prompt during validation, state both counts rather than presenting either as authoritative:
   ```
   > **{TIER} round** — {parsed count} findings parsed, but {dispatch count} were reported at dispatch.
   > Walking the {parsed count} that parsed. The discrepancy may indicate a malformed findings file.
   > {beyond-round count} findings remain beyond this round ({tier breakdown}).
   ```

   **No all-fallback notice at this gate.** Unlike the review flow, this file does not add a notice when every row in a round resolved to the title — at the verify gate, universal title substitution is the expected state today (verify has no `**Digest**:` producer yet), not a signal of a producer-side defect. This omission is deliberate, not a dropped branch.

2. **Boundary prompt** — skipped on the first round. If this is not the first round, emit the prompt below. It fires at **every** round transition independent of gate status, after this round's opener and table (step 1 above) have already rendered, and never after the final round — that exit runs through Component 4 (end-of-loop handling) instead, with no boundary prompt. Exactly one boundary prompt per transition.

   Status line, exactly one of:
   - **Variant A (gate passed)**: `**Gate passed** — the remaining findings are optional.`
   - **Variant B (gate remains blocked)**: `**Gate remains blocked** — {N} MUST-ADDRESS findings are unresolved.`

   Then, identical in both variants:
   ```
   1. **Continue** — resolve this round's findings one at a time
   2. **Resolve all remaining** — apply fixes for all {N} remaining findings automatically ({tier breakdown}), single-pass, no re-verification
   3. **Ask about the remaining findings** — answer a question, then return to this same prompt
   4. **Stop** — exit interactive resolution now
   ```

   Under variant B, replace option 4 with:
   ```
   4. **Stop** — exit interactive resolution now. A gate decision follows.
   ```

   Process the choice:
   - **Continue**: proceed into this round's findings (the inner loop, step 3 below).
   - **Resolve all remaining**: record decision "auto-resolve" for this round and every round beyond it — the whole remaining queue, not only the round about to start. Code-routed findings in this bulk pass **still require user confirmation** — option 2 waives the per-finding action menu, never the code-change confirmation requirement (see step 5's Auto-resolve remaining handling, below). Exit the outer loop immediately, evaluate Component 3's checkpoint once, then proceed to Component 4 with all recorded decisions.
   - **Ask about the remaining findings**: answer the question, then re-present this same prompt unchanged — this advances past no finding and records no decision.
   - **Stop**: exit the outer loop immediately with decisions collected so far. Proceed to Component 4 with partial resolution state.

   This prompt **reads** the checkpoint evaluation Component 3 settled — it never triggers the gate transition itself, and neither does Component 3. The gate file is written once, at the tail of Component 5, after every accepted fix has been composed and checked. Until then the status line reports what the decisions imply, not what is on disk.

For each group in this round, in the order its members appear in the round's table:

A **group of one** is the common case. It is displayed and decided exactly as steps 3 through 5 describe below, with no combined prompt and no visible difference from resolution without grouping. A group of two or more additionally takes the group variant stated in each of those steps.

3. **Display finding**:
   ```
   ### Finding {round position} of {round size} in {TIER} · {overall position} of {overall total}: V-NNN

   {restatement}

   **Severity**: {must-address | should-consider | minor} · **Route**: {route} · **Kind**: {kind} · **Agent**: {agent name}

   {description bullets — field mapping below}

   > **Evidence**: {evidence text}

   **Suggestion**: {suggestion}

   **Related**: V-NNN[, V-NNN...]  ← only when present
   ```

   - **Restatement-or-title rule**: read the finding's `**Digest**:` value, matched at column zero; where absent, substitute the finding's title. The restatement is the **first element of the finding body** — it renders immediately after the heading line, above severity, route, kind, agent, description bullets, evidence, suggestion, and related IDs.
   - **Additive guard**: the restatement is additive — it is prepended to the finding, not a replacement for any part of it. It does not authorise collapsing, omitting, summarising away, or deferring the description bullets, evidence, or suggestion. Every finding renders in full, every time. No action exists whose purpose is to reveal withheld content.

   **Description bullets by agent** (mirrors `speckit.verify.md` Step 5's mapping — do not renumber or relabel these):
   - Alignment: `**Spec claim**:` and `**Finding**:`
   - Coverage: `**Code location**:`, `**Behavior**:`, `**Worthiness**:`, `**Materiality**:`, `**Amends**:`
   - Freshness: `**Spec claim**:` and `**Change**:`
   - Cross-Artifact: `**Artifacts**:` and `**Contradiction**:`
   - Constitution Validator: `**Violated Principle**:` (first bullet, immediately after the Severity/Route/Kind/Agent line — omit entirely when the finding carried no `violated_principle`) and `**Finding**:`

   All finding content is shown by default — no progressive disclosure.

   **Group variant (two or more members)**: emit the group header below, then every member's finding block in round-table order, as **one instruction block**. No decision is prompted and none is recorded until every member has rendered — a decision taken on the first member while the rest are still unseen is the uncoordinated behaviour grouping exists to replace.

   ````
   ### Coordinated group — {group size} findings in {TIER}

   > These findings interact: {the matched signal, in plain language}.
   > Resolving them separately risks one fix undoing another, so they are decided together.
   > Routes in this group: {the distinct routes its members carry}.
   ````

   The per-member blocks are unchanged. Grouping changes what is decided together, never what is shown.

   **Constitution MUST escalation check** — evaluate for every finding (and every group member) before presenting the action prompt below:

   ```
   IS_CONSTITUTION_MUST = finding.severity == "MUST-ADDRESS" AND (
     finding.id starts with "CC-"
     OR finding.agent_name contains "Constitution Compliance"
     OR finding.agent_name contains "Constitution Validator"
   )
   ```

   Agent-name matching uses "contains" semantics, not exact-match. Ambiguous partial matches default to the standard (non-escalation) path. In verify contexts, findings from the Constitution Validator carry `V-NNN` IDs rather than `CC-` prefixes, so the agent-name condition is what fires here — not the ID-prefix condition. Both conditions are kept in the check for consistency with the shared dual-signal check and in case a future producer emits `CC-`-prefixed IDs into a verify report.

4. **Prompt for action**:
   ```
   Choose an action:
   1. **Accept** — Apply the recommended fix
   2. **Skip** — Leave this finding unresolved, move to next
   3. **Custom** — Provide your own direction for how to resolve
   4. **Auto-resolve remaining** — Fix all remaining findings automatically (single-pass, no re-verification)
   5. **Discuss** — Explore this finding before choosing an action
   6. **Quit** — Exit interactive mode now
   ```

   **Group variant (two or more members)**: present one combined prompt covering the whole group, instead of one prompt per member:
   ````
   Choose an action for this group of {group size}:
   1. **Accept all** — Apply one coordinated fix satisfying every finding in the group
   2. **Accept a subset** — Name the findings to fix; the rest are recorded as skipped
   3. **Skip all** — Leave every finding in the group unresolved
   4. **Custom** — Provide your own direction for resolving the group as a whole
   5. **Auto-resolve remaining** — Fix all remaining findings automatically (single-pass, no re-verification)
   6. **Discuss** — Explore this group before choosing an action
   7. **Quit** — Exit interactive mode now
   ````

   **Constitution MUST variant (`IS_CONSTITUTION_MUST`)**: augment — never replace — the 6-option prompt above with governance context and two additional options, for 8 total:
   ````
   ⚠️ **Constitution MUST finding** — {violated principle identifier}: {violated principle title}

   Choose an action:
   1. **Accept** — Apply the recommended fix
   2. **Skip** — Leave this finding unresolved, move to next
   3. **Custom** — Provide your own direction for how to resolve
   4. **Auto-resolve remaining** — Fix all remaining findings automatically (single-pass, no re-verification)
   5. **Discuss** — Explore this finding before choosing an action
   6. **Quit** — Exit interactive mode now
   7. **Override** — Acknowledge this constitution violation and proceed without fixing it
   8. **Defer** — Leave the gate blocked and exit; this finding stays unresolved
   ````
   The violated principle identifier and title are extracted from the finding's `**Violated Principle**:` bullet — the Constitution Validator's structured field rendered by the Display finding step above (identical field, same source, as `speckit.verify.md` Step 5's Constitution Validator bullet mapping). All 6 standard options above remain unchanged and behave exactly as described in step 5 below; Override and Defer are additive, never a replacement for them. This variant applies independent of the finding's `route` — a constitution MUST finding routed to `constitution.md` gets the same augmented prompt as one on any other route, and the route-specific Accept handling described in step 5 is otherwise unaffected.

   **Group variant, constitution member present**: when at least one member of the group is `IS_CONSTITUTION_MUST`, augment the group prompt the same way — governance context plus Override/Defer — and additionally disable "Accept all" and constrain "Accept a subset":
   ````
   ⚠️ **Constitution MUST finding in this group** — {violated principle identifier}: {violated principle title}

   Choose an action for this group of {group size}:
   1. **Accept a subset** — Name the findings to fix; the constitution member must be resolved individually (Accept/Override/Defer) and cannot be left out of the naming
   2. **Skip all** — Leave every non-constitution finding unresolved; the constitution member still requires Accept/Override/Defer
   3. **Custom** — Provide your own direction for resolving the group as a whole
   4. **Auto-resolve remaining** — Fix all remaining findings automatically (single-pass, no re-verification)
   5. **Discuss** — Explore this group before choosing an action
   6. **Quit** — Exit interactive mode now
   7. **Override** — Acknowledge the constitution violation and proceed without fixing it
   8. **Defer** — Leave the gate blocked and exit; the constitution finding stays unresolved
   ````
   "Accept all" is disabled here — a coordinated fix cannot silently resolve a constitution MUST finding without the user individually confirming it. "Accept a subset" cannot exclude the constitution member: naming a subset that omits it is not a valid answer to this prompt — the constitution member is always resolved individually via Accept, Override, or Defer, whether or not the rest of the group is accepted as a subset.

5. **Process user choice — route-specific Accept handling**:

   Findings routed to `spec.md`, `plan.md`, or `tasks.md`, and constitution findings routed to `constitution.md`, are handled identically: **Accept** records the recommended fix (from the finding's `**Suggestion**`) for batch application in Component 5. No code generation, no confirmation step — the same deferred-write pattern `speckit.review-interactive.md` uses for `spec.md`/`plan.md`.

   Findings routed to `code` require a distinct path — this is the key deviation from `speckit.review-interactive.md`, which never targets `code`:
   - **Accept** triggers context-aware code generation: draft the code change grounded in the spec's requirements (and the constitution, when relevant), using the finding's evidence and suggestion as the starting point — not a blind patch of the suggestion text.
   - Before recording the decision, **present the generated change to the user for explicit confirmation** — show a diff-like preview of what will change.
   - If the user **confirms**: record decision "accept" for this finding with the generated change attached, for batch application in Component 5.
   - If the user **rejects**: record decision "skip" for this finding. Do NOT re-prompt the 6-action menu for this finding — a rejected code generation is a skip. Move to the next finding.

   **Constitution mode has no code-routed findings** (verify.md's Step 5 guarantees every constitution finding routes to `constitution.md`) — the code-generation-and-confirmation branch above never fires when `MODE = constitution`.

   Full action semantics:
   - **Accept**: per route-specific handling above.
   - **Skip**: Record decision "skip" for this finding. Move to next finding.
   - **Custom**: Prompt user for custom direction. If the finding is routed to `spec.md`/`plan.md`/`tasks.md`/`constitution.md`: record decision "custom: {user direction}" for batch application. If the finding is routed to `code`: still apply the generate-then-confirm flow, but generate the change from the user's custom direction instead of the finding's suggestion; on confirm record "custom" with the generated change attached, on reject record "skip". If the direction is ambiguous or contradictory, ask the user to rephrase once. If still unclear after rephrase, record decision "skip" and move to next finding.
   - **Auto-resolve remaining**: Record decision "auto-resolve" for this finding and every remaining finding in the queue (from current position onward, spanning this round and every round beyond it). This is a single-pass bulk fix — do NOT re-dispatch verify agents and do NOT enter a convergence loop (that is `/speckit-verify-auto`'s job, not this skill's). Code-routed findings in this bulk pass STILL require user confirmation — auto-resolve remaining does not waive the code-change confirmation requirement, only the per-finding action menu. In practice: generate the code changes for every code-routed finding in the remaining batch, then present them for confirmation (together, or one at a time — agent judgment based on batch size) before proceeding. Exit the outer loop immediately, evaluate Component 3's checkpoint once, then proceed to Component 4 with all recorded decisions.
   - **Quit**: Exit the outer loop immediately with decisions collected so far. Proceed to Component 4 (end-of-loop handling) with partial resolution state.
   - **Discuss**: Engage in a brief conversation about this finding — clarify scope, explore alternatives, or ask questions about the evidence. After discussion, re-present the action choices for this same finding (do not advance to the next finding).
   - **Override** (`IS_CONSTITUTION_MUST` findings only): Record decision "override" for this finding. This is not a resolution the checkpoint counts as satisfied (see Component 3) — it is a sanctioned, explicit acknowledgment made at the moment the finding was seen. No fix is composed; skip bookkeeping applies (Component 5's checkbox stays unchecked). Accumulate this finding's ID, in walk order, into the in-memory `CONSTITUTION_OVERRIDE_IDS` list — the Component 5 tail issues one combined `record-gate-override.sh --cause constitution_must` call over everything accumulated there. Move to next finding.
   - **Defer** (`IS_CONSTITUTION_MUST` findings only): Record decision "defer" for this finding. No fix is composed; skip bookkeeping applies (Component 5's checkbox stays unchecked), identically to Skip. Unlike Override, this finding is not accumulated for an immediate override record — it carries into Component 4's end-of-loop handling as an unresolved constitution finding, where Case B's combined display and override choice can address it later. Move to next finding.

   **Group variant (two or more members)**: record every member's decision as **one unit**. Nothing is recorded until the choice covering the whole group has been made.
   - **Accept all**: record "accept" for every member. Component 5 composes one coordinated fix satisfying them together — not one independent patch per member. Unavailable when the group contains an `IS_CONSTITUTION_MUST` member — see the constitution group variant below.
   - **Accept a subset**: record "accept" for each named member and "skip" for each unnamed one. An unaccepted member is recorded as skipped, never folded into the coordinated fix on the grounds that it was adjacent to one that was accepted. Where the group contains an `IS_CONSTITUTION_MUST` member, that member cannot be one of the unnamed ones — see below.
   - **Skip all**: record "skip" for every member.
   - **Custom**: prompt for the direction once and record "custom: {user direction}" for every member, composed as one coordinated fix. The per-finding Custom option's ambiguity handling applies unchanged.
   - **Auto-resolve remaining**, **Discuss**, **Quit**: behave exactly as their per-finding counterparts above. Discuss re-presents this same group's combined prompt afterwards, never a per-member prompt.

   **Constitution group variant (at least one `IS_CONSTITUTION_MUST` member)**: the constitution member is never folded into a group-wide "Accept all"/"Accept a subset"/"Skip all" outcome — it is always resolved individually, via its own Accept, Override, or Defer:
   - **Accept a subset**: name the non-constitution members to accept (the rest of those are recorded "skip"), and separately resolve the constitution member via Accept, Override, or Defer. All three land in the same recorded unit for this group.
   - **Skip all**: record "skip" for every non-constitution member; separately resolve the constitution member via Accept, Override, or Defer — "Skip all" cannot silently carry the constitution member to "skip" without that individual resolution.
   - **Override** (constitution member only): record decision "override" for that member exactly as the per-finding Override option does, including the `CONSTITUTION_OVERRIDE_IDS` accumulation. The rest of the group's decisions (from Accept a subset, Skip all, or Custom) are recorded alongside it in the same unit.
   - **Defer** (constitution member only): record decision "defer" for that member exactly as the per-finding Defer option does. The rest of the group's decisions are recorded alongside it in the same unit.
   - **Custom**: prompt once; the direction can address the whole group including the constitution member, composed as one coordinated fix, exactly as the non-constitution Custom variant — a coordinated Custom fix is a form of Accept for the constitution member, not a bypass of the individual-resolution requirement.

   **A mixed group does not waive the code confirmation.** Where a group spans a code-routed member and a markdown-routed one, the code-routed member keeps the generate-then-confirm flow described above: generate the change, present it for explicit confirmation, and record "accept" only on confirm. Deciding the group as one unit changes when the decision is recorded, never whether the user saw the code. If the user rejects the generated code change, record "skip" for that member and keep the rest of the group's decisions — the coordinated fix then covers the members that remain, exactly as a subset acceptance does.

6. **Continue to next group**: After recording the group's decisions, move to the next group in this round and repeat from step 3 (the finding display) — not step 1.

After the final round's findings are all processed: proceed to Component 4 (end-of-loop handling). No boundary prompt fires here — the loop's own end is not a round transition.

## Component 3: Gate-Passed Checkpoint

The checkpoint is evaluated at two points:
- **Once per group**, after that group's decisions are recorded, where at least one member's decision is "accept" or "custom". Never once per member: a group's decisions are recorded as one unit, and evaluating mid-group would read a partial record. A group of one is a group, so a single ungrouped finding evaluates the checkpoint exactly once.
- **Once**, immediately after a bulk "auto-resolve" recording (whether triggered by the per-finding action in step 5 or by the boundary prompt's "Resolve all remaining" in step 2) — evaluated after all remaining decisions are recorded and before exiting the loop, never once per synthesised decision.

At each evaluation point, check:
- Are all MUST-ADDRESS findings in the queue now resolved (decision ∈ {accept, custom, auto-resolve})?

**"Override" and "Defer" are not in that set.** Both are decisions a user can make about a constitution MUST finding, and both leave the finding unresolved for this checkpoint's purposes — Override is a sanctioned acknowledgment, not a fix reaching disk, and Defer is explicitly deferred. A queue containing an unresolved "override" or "defer" decision on its last remaining MUST-ADDRESS finding evaluates to `ALL_BLOCKING_RESOLVED = false`, the same as an unresolved "skip".

If YES: set `ALL_BLOCKING_RESOLVED = true`.

If NO: set `ALL_BLOCKING_RESOLVED = false` and continue looping through the queue.

**This component evaluates; it does not write the gate and does not announce a transition.** A decision to accept a fix is not the same event as that fix reaching disk in a coherent artifact. The fixes are composed and checked in Component 5, and any one of them can still be discarded there — so a gate written here could report `passed` over an artifact that was never written. The write happens once, at the tail of Component 5, after every check outcome has settled; `ALL_BLOCKING_RESOLVED` is what that write reads.

This checkpoint never presents a prompt of its own — the boundary prompt (Component 2, step 2) carries the user-facing status line and options for whatever happens next, in both the passed and blocked cases. It reads `ALL_BLOCKING_RESOLVED` as a status line about the decisions taken so far.

## Component 4: End-of-Loop Handling

When the outer loop exits — all rounds processed, or one of the four exits was taken (per-finding Quit, per-finding Auto-resolve remaining, boundary Stop, boundary Resolve all remaining):

**Case A**: All MUST-ADDRESS findings are resolved (decision ∈ {accept, custom, auto-resolve}):
- Record the case and continue to Component 5. **Do not announce a gate transition here** — the accepted fixes have not been composed or checked yet, and one that fails the check will be discarded, leaving the gate blocked. Announcing a pass here would claim a transition this component did not perform and cannot retract.
- The gate write for this case is the all-resolved branch at the Component 5 tail. That is the site that both performs the transition and announces it, and it is where the next step is recommended once the outcome is known: for spec mode, `/pre-review` or creating a diff for submission (per `speckit.verify.md`'s completion-report guidance); for constitution mode, nothing further needed — the constitution is verified.

**Case B**: Unresolved MUST-ADDRESS findings remain (some decision = "skip" or "defer"):
- Display summary of unresolved findings. **When the unresolved set includes at least one constitution finding** (decision = "defer", or "skip" chosen on an `IS_CONSTITUTION_MUST` finding), use the combined ⚠️ display below — it distinguishes constitution findings from every other unresolved finding in one instruction block, never two separate displays:
  ```
  ⚠️ **Gate remains blocked** — {N} MUST-ADDRESS findings are unresolved.

  Constitution MUST findings ({M}):
  - {V-NNN}: {title}

  Other findings ({N-M}):
  - {V-NNN}: {title}
  - [etc.]
  ```
  **When no constitution finding is in the unresolved set**, use the plain display unchanged:
  ```
  **Gate remains blocked** — {N} MUST-ADDRESS findings were skipped:
  - {V-NNN}: {title}
  - {V-NNN}: {title}
  - [etc.]
  ```
- Offer override choice:
  ```
  Options:
  1. **Fix now** — Re-run `/speckit-verify` to start a fresh verification
  2. **Override** — Acknowledge risk and proceed to next step. Unresolved verification findings may leave spec-code mismatches unaddressed.
  3. **Defer** — Leave the gate blocked and exit. To unblock, resolve the findings and re-run `/speckit-verify` (or `/speckit-verify --constitution` in constitution mode).
  ```

**Record the choice only — perform nothing here.** Whichever option the user picks, note the decision and continue to Component 5. Do not write the gate, do not append an override record, and do not announce an override yet.

Component 5 rebuilds the verification report in memory from content read at Component 1 and emits one Write call per file, so an append here would be silently discarded. Writing the gate here would be worse: it would flip the gate to `passed` before the record exists, leaving an orphaned passing gate if the record is then refused. Announcing success here would claim an override that has not happened and cannot be retracted if the record script refuses.

All four exits — per-finding Quit, per-finding Auto-resolve remaining, boundary Stop, boundary Resolve all remaining — converge here, before Component 5's batch write. Decisions are non-durable until that batch write, so any exit that bypassed this component would discard every decision recorded in the session.

## Component 5: Batch Edit Phase

After the interactive loop completes and end-of-loop handling is done, apply all collected decisions as batched edits.

**MANDATORY: One Write call per file.** Do NOT use sequential Edit calls to apply findings one at a time — this creates excessive tool call noise and risks partial application if the session is interrupted mid-sequence. Instead, build the complete updated content in memory and emit a single Write call per target file. This is non-negotiable.

1. **Collect all "accept" and "custom" and "auto-resolve" decisions** across all findings.
2. **Group by target file**, then order the groups: `spec.md` → `plan.md` → `tasks.md` → code files (alphabetical within code files) → `constitution.md` (constitution mode only ever targets this one file — nothing else is in scope).
3. **Compose each target file in memory — do not write yet**:
   - Read the current file content (one Read call). **Retain that pre-fix content** for the rest of this component: the check needs it to tell a defect these fixes introduced from one the file already had.
   - **Compose one coordinated fix per group** whose members were accepted together, satisfying every accepted member of that group at once, and apply it to every file that group spans or to none of them. Compose ungrouped findings — and groups of one — independently, as before.
   - Apply all fixes sequentially in memory. For code-routed fixes, generate each change seeing the results of prior fixes already applied to the same file (sequential context)
   - Apply fixes marked "accept"/"auto-resolve" using the recorded fix (recommendation, or generated-and-confirmed code change)
   - Apply fixes marked "custom" using the user-provided direction (or the generated-and-confirmed code change derived from it)
   - Note which regions each fix wrote and which findings contributed to this file. For a source file, that region list is what confines the check to code this run actually touched — an inert branch that was already there is not this run's defect.
4. **Holistic reconciliation pass**: after composing the file's full new content — before the Write call — dispatch a `general-purpose` Agent (`model: "opus"`) to run the pass:

   ```
   Read and execute `.specify/templates/holistic-reconciliation.md`.

   COMPOSED=<map: file path → candidate content after all fixes applied>
   BASELINES=<map: file path → pre-fix content>
   WRITTEN_REGIONS=<map: file path → spans this run wrote>
   CONTRIBUTING=<map: file path → finding IDs>
   CANDIDATE_SET=<this mode's declared artifacts — same set bound for grouping in
   Component 1: in spec mode, spec.md, plan.md, tasks.md and the files under contracts/;
   in constitution mode, constitution.md alone; for a code-routed fix, the files this run
   already wrote plus the files the contributing finding's own evidence cites, never a
   repository-wide search for callers or similarly-named files>
   USER_PRESENT=true
   GROUPS=<groups from Component 1>

   For each file, report: defects found (quoted, classified, attributed), then outcome
   (clean / repaired / unrepairable).
   ```

   A human is present in this session, so bind its user-present input to true. Pass the groups formed in Component 1 as the pass's groups input, so a coordinated fix is one repair unit rather than several.

   **The check is agent judgment performed by reading the composed content, and a mechanical parse alongside it is permitted**: for a code-routed change, running a parser or syntax checker over the composed file in addition to reading it is encouraged, not forbidden. The mechanical result never substitutes for the read.

   **Bind the candidate set to this mode's declared artifacts** — the same set bound for grouping in Component 1. For a code-routed fix the set is the files this run already wrote plus the files the contributing finding's own evidence cites — never a repository-wide search for callers or similarly-named files. This binding is what lets the check reach a rule a fix here changed that a counterpart still states in its superseded form; without it that class cannot fire, because a counterpart receives no fix of its own and comparing it against its own pre-fix content finds nothing.

   **Constitution mode has a single-artifact candidate set**, so the cross-artifact reach is inert there. That is a correct outcome, not a skipped check — report the pass as having run with no counterpart in scope.

   **If the agent reports the template is not present, stop.** Do not write any file, tell the user in plain language that the consistency check could not be run and name the file that is absent, and do not record a passing gate. Writing without the check is precisely the unchecked write the check exists to prevent, so this branch fails closed.

5. **Act on each file's outcome, then write**:
   - **Clean or repaired**: state every defect found before stating the outcome, name any accepted fix a repair altered or removed, then emit one Write call with the composed content for that file. A repair is bounded at a single re-compose, and it may not resolve a defect by dropping an accepted fix.
   - **Unrepairable**: present the surviving defect to the user, quoting the composed content that carries it, and offer accepting the combined result as it stands, resolving a subset of the contributing fixes, or discarding all changes for that file. This applies even when the decisions originated from "Auto-resolve remaining" — a human is present in this dispatched session (unlike `/speckit-verify-auto`, which runs unattended and instead discards conflicting fixes and reports them as unresolved).
     - **Accept**: write the file as composed and record `COMPOSITION_DEFECT_ACCEPTED = true` together with the accepted defect as a single line of text. The gate write at the tail turns this into an override record.
     - **Subset**: compose the named subset and check it once. This does not consume a further repair attempt. If the subset also fails, fall through to accept-or-discard for this file rather than prompting a third time.
     - **Discard**: do not write the file. Leave its contributing findings unresolved, set `ALL_BLOCKING_RESOLVED = false` if any of them was blocking, and name them in the summary below. Where the discarded fix was a coordinated one, discard it from every file it spans — half a coordinated fix on disk is the contradiction this check exists to prevent. Every other file that group spans whose own check passed is recomposed without the withdrawn fix and still written, so its unrelated fixes land; only the file that failed its own check loses everything.

   **A divergence this path carries.** A code-routed fix keeps its generate-then-confirm requirement. The user already confirmed the generated change before it was recorded, and this pass does not waive that: a composition the check repairs, or a subset the user selects, still consists of changes the user saw and approved. Where a repair would alter a confirmed code change, name what it altered rather than treating the earlier confirmation as covering it.

6. **Update the verification report checkboxes** — bookkeeping, so it happens only after every composed file above has an outcome:
   - For each finding whose fix was written (decision = "accept" or "custom" or "auto-resolve", and its file was not discarded): change `- [ ] Resolved` to `- [x] Resolved`
   - For findings with decision = "skip", "override", or "defer", and for findings whose file's fixes were discarded: leave `- [ ] Resolved` unchanged — an override or a defer is a sanctioned decision about the finding, not a fix reaching disk, so no checkbox reflects it
   - (`verification.md` in spec mode, `constitution-verification.md` in constitution mode)
   - Updating a checkbox before the outcomes settle would record a finding resolved while its file went unwritten — the report and the artifact then disagree, and the next round reads the finding as already fixed.

After all writes complete, display the check's results — each file's defects before its outcome, then the run-level summary — followed by:
```
**Edits applied**:
- spec.md: {N} findings resolved
- plan.md: {N} findings resolved  ← if applicable
- tasks.md: {N} findings resolved  ← if applicable
- {code file}: {N} findings resolved  ← one line per code file, if applicable
- constitution.md: {N} findings resolved  ← constitution mode only
- verification.md: {N} findings marked - [x] Resolved
[Include a line per file whose fixes were discarded, naming the findings left unresolved]
```

Resolution is now complete. Display the one-line DISCOVERY summary here (skip this line entirely if `DISCOVERY_COUNT` is 0):
> {DISCOVERY_COUNT} discovery notes logged to verification.md (no action needed): {short labels}

(Substitute `constitution-verification.md` in constitution mode. Constitution mode's `DISCOVERY_COUNT` is typically 0 per verify.md Step 5, since the Constitution Validator agent does not emit `route: discovery` findings — the summary line is skipped in that case.)

### Gate write (Component 5 tail)

**If any `write-review-gate-unified.sh` call in the four branches below exits 4** (the `implement` prerequisite is unmet — unexpected here, since this skill only runs after a prior verify write already succeeded, but possible if history changed underneath this session): Read and execute `.specify/templates/prerequisite-refusal-gate.md` instead of treating it as an ordinary write failure. A human is present in this session, so present the three-way choice normally rather than following the unattended-run branch.

**This is the only place in this skill that writes the gate.** Component 3 evaluates and does not write; Component 4 records a choice and does not write. Every path through this skill converges here, after every composed file has an outcome and the bookkeeping writes are done. Exactly one of the four branches below performs the gate write, and the branch that performs it announces it — no other section may announce a gate transition, because no other section performs one.

That three-way separation — evaluate in Component 3, choose in Component 4, write here — replaces the previous two-writer arrangement, in which Component 3's checkpoint and the override sequence were the only callers of the gate-write helper. Under that arrangement a partial accept-then-quit session left real edits on disk with no gate write at all, because Case A performed no write of its own.

`--resolved` is passed on any branch where at least one finding this session had decision "accept"/"custom"/"auto-resolve" and its file was written — that is, where Component 5 actually applied an edit. It records that the `spec.md`/`plan.md`/`tasks.md` edits now on disk are this run's own sanctioned output, which `sapling-commit.sh`'s `after_verify` branch reads to decide whether to widen its commit scope beyond `verification.md`/`pipeline-state.jsonl`/`verify-gate.json`. A session that wrote nothing omits it, so the commit scope stays narrow.

**Record first, write second.** Where a branch needs an override record, the record script runs before the gate rewrite, and the gate is rewritten only on exit 0. Writing the gate first would leave an orphaned passing gate if the record is then refused. Interactive resolution is only ever dispatched from a synthesized finding set, so quorum was met by construction. In constitution mode pass `--mode constitution` so the record lands in `constitution-verification.md` — without it the record appends to a `verification.md` that constitution mode never reads, and the append silently creates that file.

**Records are not branches.** A run can produce both kinds of record — a user can accept a composition defect *and* skip a blocking finding. They are different decisions about different subjects, and both are recorded. Where a run satisfies Branch 2 and Branch 3 together, emit **both** records — Branch 2's first — and then perform a single gate write carrying the true unresolved count. Selecting one branch and dropping the other record silently loses one of the two decisions from the audit trail. A constitution override record (below) is a third, independent record under the same rule — a run can carry any combination of the three.

**Constitution override record (independent of the branch below).** If `CONSTITUTION_OVERRIDE_IDS` is non-empty — at least one finding was recorded "override" during the walk (Component 2, step 5) — record it once here, before evaluating the branches below. Because an "override" decision is never in `{accept, custom, auto-resolve}`, a non-empty `CONSTITUTION_OVERRIDE_IDS` always means Component 4 reached Case B for the rest of the queue; this record still fires independent of whether Branch 2's composition-check override also fires:

```bash
speckit run record-gate-override.sh \
  --stage verify \
  --mode "$MODE" \
  --quorum-met true \
  --cause constitution_must \
  --finding-ids "<CONSTITUTION_OVERRIDE_IDS, comma-separated>"
```

- **On exit 0**: proceed to whichever branch below applies to the rest of the queue. In addition to that branch's own gate write and announcement, write:
  ```bash
  speckit run write-pipeline-state.sh verify override=true constitution_override=true cause=constitution_must
  ```
  This pipeline-state entry is additional to the branch's own write — it never substitutes for it.
- **On exit 3**: report the refusal — including when it is the duplicate-record refusal, which names its cause — and do **not** proceed to any branch below or rewrite the gate. A sanctioned override with no durable record must not be followed by a gate transition that assumes it was recorded.
- **On any other non-zero exit**: report that the override record could not be written, state the script's message, and do **not** proceed to any branch below or rewrite the gate.

**Skip this call entirely when `CONSTITUTION_OVERRIDE_IDS` is empty.** No finding was overridden during the walk, so there is nothing to record here — proceed directly to the branches below. This is unrelated to Case B's own end-of-loop "Override" choice (Branch 3), which records a separate, later decision about findings that reached the end of the loop still unresolved — see that branch's constitution handling below.

**Branch 1 — `ALL_BLOCKING_RESOLVED` is true, no blocking-tier discard occurred, and no composition defect was accepted.** This is the all-resolved path, and the write is unconditional on it:

```bash
speckit run write-review-gate-unified.sh \
  --stage verify \
  --gate-type "verify" \
  --status passed \
  --must-address 0 \
  --should-consider "$SHOULD_CONSIDER_COUNT" \
  --minor "$MINOR_COUNT" \
  --agents-completed "$AGENTS_COMPLETED" \
  --resolved
```

Then display "Gate updated: BLOCKED → PASSED" and recommend the next step per `speckit.verify.md`'s completion-report guidance.

**Branch 2 — `COMPOSITION_DEFECT_ACCEPTED` is true.** Record the accepted defect, then pass the gate as an override. `--subject` carries the defect as a single line; the script rejects an embedded newline:

```bash
speckit run record-gate-override.sh \
  --stage verify \
  --mode "$MODE" \
  --quorum-met true \
  --cause check-failure \
  --subject "<the accepted composition defect, one line>"
```

- **On exit 0**: rewrite the gate with the same invocation as branch 1 plus `--override`:
  ```bash
  speckit run write-review-gate-unified.sh \
    --stage verify \
    --gate-type "verify" \
    --status passed \
    --must-address 0 \
    --should-consider "$SHOULD_CONSIDER_COUNT" \
    --minor "$MINOR_COUNT" \
    --agents-completed "$AGENTS_COMPLETED" \
    --override \
    --resolved
  ```
  Then display "Gate overridden: BLOCKED → PASSED (user accepted a composition defect the consistency check could not repair)", state the accepted defect, and recommend the next step.
- **On exit 3**: report the refusal — including when it is the duplicate-record refusal, which names its cause — and do **not** rewrite the gate.
- **On any other non-zero exit**: report that the override record could not be written, state the script's message, and do **not** rewrite the gate. `--subject` is agent-authored prose and an embedded newline is a usage error rather than a refusal, so collapse the defect to one line before passing it.

This branch is reachable whether or not any finding was skipped, so it does not sit inside Case B. A session in which every finding was accepted and one composition failed its check reaches it on the Case A path.

**Both records, one write.** A run that accepts a composition defect *and* skips a blocking finding satisfies this branch and Branch 3 at once. Emit both records — this branch's first — then perform a single gate write. `--must-address 0` is correct on an overridden gate: the user waived the findings deliberately, and the override records enumerate every one of them, so the count is not the audit trail.

**Branch 3 — blocking findings remain and Component 4 Case B's recorded choice was "Override".** Record the unresolved set, then pass the gate as an override.

**When the unresolved set includes at least one constitution finding** (decision = "defer", or "skip" chosen on an `IS_CONSTITUTION_MUST` finding — the same set named in Case B's combined ⚠️ display), record it first, as its own record, before the call below:

```bash
speckit run record-gate-override.sh \
  --stage verify \
  --mode "$MODE" \
  --quorum-met true \
  --cause constitution_must \
  --finding-ids "<the unresolved constitution finding IDs, comma-separated>"
```

Handle its exit code exactly as the standalone constitution override record above: **on exit 0**, continue to the call below; **on exit 3 or any other non-zero exit**, report the failure and do **not** proceed to the call below or rewrite the gate.

Then, unchanged, the existing call for the rest of the unresolved set:

```bash
speckit run record-gate-override.sh \
  --stage verify \
  --mode "$MODE" \
  --quorum-met true
```

- **On exit 0**: rewrite the gate, omitting `--resolved` if this session applied no edit:

  ```bash
  speckit run write-review-gate-unified.sh \
    --stage verify \
    --gate-type "verify" \
    --status passed \
    --must-address 0 \
    --should-consider "$SHOULD_CONSIDER_COUNT" \
    --minor "$MINOR_COUNT" \
    --agents-completed "$AGENTS_COMPLETED" \
    --override \
    [--resolved, only if this session applied at least one edit]
  ```

  Then display "Gate overridden: BLOCKED → PASSED (user acknowledged {N} unresolved findings)" and recommend the next step. **When the constitution record above was also written this run**, additionally write:
  ```bash
  speckit run write-pipeline-state.sh verify override=true constitution_override=true cause=constitution_must
  ```
- **On exit 3**: report "override refused — gate unchanged" and do **not** rewrite the gate.

Run it only on the recorded "Override" choice. Running it on a "Re-run `/speckit-verify`" choice would fabricate a record for a decision the user never made, after which the idempotence guard would refuse the genuine one.

**Branch 4 — blocking findings remain and the recorded choice was "Fix now" or "Defer", or a blocking-tier discard occurred.** Touch the gate so `sapling-commit.sh` can see this session's edits are sanctioned, without changing its `blocked` status. Pass the count of findings still unresolved — those the user skipped plus those whose fixes the check discarded — as `--must-address`, so the count is not left stale at its pre-loop value:

```bash
speckit run write-review-gate-unified.sh \
  --stage verify \
  --gate-type "verify" \
  --status blocked \
  --must-address "<count of findings still unresolved>" \
  --should-consider "$SHOULD_CONSIDER_COUNT" \
  --minor "$MINOR_COUNT" \
  --agents-completed "$AGENTS_COMPLETED" \
  --resolved
```

**Skip this call when nothing was written.** If no fix reached disk this session — every finding skipped, or every composition discarded — the gate already reflects an untouched, narrow-scope commit and needs no touch.
