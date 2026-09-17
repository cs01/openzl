---
name: speckit-review-interactive
description: 'SpecKit internal: interactive resolution flow for `/speckit-review`.'
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:meta
  meta_preset_strategy: replace
user-invocable: true
disable-model-invocation: false
---



# Speckit Review Interactive Skill

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

## Validate Review Findings File

Read `{FEATURE_DIR}/review/review-findings.md` and validate structure:
- Check required sections exist: `### MUST-ADDRESS`, `### Summary`, `**Gate Status**`
- Parse finding counts from section headers (e.g., `### MUST-ADDRESS (5)`)
- Verify counts match the context variables from dispatch prompt. Record any per-tier discrepancy — do not error. Each round opener reports its own tier's discrepancy (see the round opener's count-mismatch variant, below); a tier that produces no round at all (its parsed count is zero) has no opener to carry the report, so its discrepancy is stated in the queue-level note instead.
- If file is malformed, truncated, or missing required sections → ERROR: "review findings file is malformed or incomplete. Re-run `/speckit-review` to regenerate." and exit

Parse all findings from MUST-ADDRESS, SHOULD-CONSIDER, and MINOR sections for interactive presentation.

> **MANDATORY: One Write call per file.** Do NOT use sequential Edit calls to apply findings one at a time — this creates excessive tool call noise and risks partial application if the session is interrupted mid-sequence. Instead, build the complete updated content in memory and emit a single Write call per target file. This is non-negotiable.

## Component 1: Presentation Ordering

Use the in-memory findings from validation (not re-parsed from file) — the agent count and finding metadata are already available.

Build the presentation queue:
1. Filter out PLAN-DEFERRED findings
2. Group remaining findings by severity tier: MUST-ADDRESS, SHOULD-CONSIDER, MINOR
3. Within each tier, sort by:
   - **Primary**: Agent count descending (synthesized findings with 2+ agents first)
   - **Secondary**: Original document order from `review/review-findings.md` (for same agent count)
4. Concatenate tiers in order: all MUST-ADDRESS, then all SHOULD-CONSIDER, then all MINOR

**Partition the queue into rounds.** One round per tier that has at least one finding after filtering — MUST-ADDRESS, then SHOULD-CONSIDER, then MINOR, in that order. A tier with zero findings after filtering produces no round at all: it is suppressed at partition time, and contributes nothing to the walk, the opener, or the beyond-round remainder breakdown. Fix each round's membership and row numbering (the table's `#` column) at partition time; never recompute or reorder them while walking findings. The intra-tier ordering established in step 3 above is preserved exactly within each round.

For every round, compute the count of findings beyond it, broken down by the tier(s) those findings belong to — this is what the round opener and the boundary prompt report as the findings remaining beyond the round.

**Group interacting findings within each round.** Once the rounds are fixed, dispatch a `general-purpose` Agent (`model: "sonnet"`) for each round to run `Resolution grouping`:

```
Read and execute `.specify/templates/resolution-grouping.md`.

ACCEPTED=<this round's findings, each with ID, tier, target artifact, evidence, recommendation>
TIER=<this round's tier>
CANDIDATE_SET=<the artifacts in scope at this gate: spec.md at a primary gate; spec.md,
plan.md, research.md and the files under contracts/ at a secondary gate>

Return GROUPS: for each group, its member finding IDs, the matched signal, and the
artifacts it spans.
```

Grouping runs once per round and never spans two — each round is one tier, and the procedure does not cross tiers.

Where a finding does not name its target artifact, infer it exactly as Component 5's group-by-target-file step does. That inference already exists; reusing it is what keeps the two from disagreeing about where a finding lands.

**If the agent reports the template is not present, stop.** Do not open a round, do not present a finding, and do not write any artifact. Tell the user in plain language that the interaction check could not be run and name the file that is absent, and do not record a passing gate.

**Theme group consumption.** Before walking a MUST-ADDRESS or SHOULD-CONSIDER round, read each of its findings' `**Theme Group**:` metadata line from `review/review-findings.md` — synthesis-time grouping, persisted as `{group-id} — "{theme-summary}"`. Findings sharing the same group id are already known to address the same underlying design question. A MINOR finding ordinarily never carries this line — it is batched (see the MINOR round exception below), not theme-grouped — **except** a MINOR finding escalated from auto-apply during reconciliation, which carries a `**Theme Group**:` line of its own and is excluded from the MINOR batch for that reason (see that exception's carve-out below). Read that carve-out's escalated findings the same way this paragraph reads a MUST-ADDRESS/SHOULD-CONSIDER round's theme groups — as its own coordinated group, walked through the ordinary per-group flow below, not through the batch.

Theme grouping (synthesis-time, conceptual relatedness) and resolution grouping (resolution-time, edit-region interaction, dispatched immediately above) are complementary — a finding can belong to both a theme group and a resolution group at once, for different reasons. Merge them for presentation: a round's presentation groups are the union of its resolution groups and its theme groups, so two findings sharing either signal are decided together. **Resolution grouping wins for edit composition** when the two disagree about which findings compose into one fix — Component 5 composes coordinated fixes strictly by resolution group. Theme grouping never changes what gets composed; it only changes what gets presented and decided together, and it supplies the group's heading (the theme summary) when a presentation group derives from a theme group rather than a resolution group.

Grouping does not change round membership, the table's `#` column, or the beyond-round counts — those are fixed above and stay fixed. It changes only how the round's findings are decided in Component 2: members of one group are presented together and decided under a single combined action prompt instead of one at a time. A finding that matched nothing forms a group of one and is walked exactly as it is without grouping.

If PLAN-DEFERRED findings were excluded (count non-zero), display a one-line summary before the first round opener — omit this line entirely when the excluded count is zero:
> **Note**: {N} PLAN-DEFERRED findings excluded from interactive resolution — will be incorporated during `/speckit-plan`

If a tier produced no round despite a non-zero count reported at dispatch (the discrepancy recorded during validation), state that discrepancy in this same queue-level note instead — no round opener exists for that tier to carry it.

**Empty queue**: if partitioning produces no rounds at all (every tier is empty or excluded), state that no round is opened, and proceed directly to Component 4 (end-of-loop handling). No gate transition is asserted in this case — an empty queue has nothing for a gate write to reflect either way.

## Component 2: Interactive Loop

For each round in the presentation queue:

1. **Round opener**: emit the opener line(s) and the round's table as **one instruction block** — they must never render apart. This step executes once per round, never once per finding.

   Compute `THEME_COUNT` for this round: the number of distinct `**Theme Group**` ids carried by two or more of this round's findings (per Component 1's theme group consumption, above). A round where no finding carries a `**Theme Group**` line, or where every such line is unique to its own finding, has `THEME_COUNT = 0` — the round is treated as fully ungrouped.

   **Themed variant** (`THEME_COUNT` > 0) — theme count leads, finding count follows as context:
   ```
   > **{TIER} round** — {THEME_COUNT} themes ({round size} findings). {blocking statement}
   > {beyond-round count} findings remain beyond this round ({tier breakdown}).

   | # | ID | Summary |
   |---|-----|---------|
   | 1 | **{theme-summary}** ({member count} findings) | — |
   |   | └ {ID} | {restatement-or-title} |
   |   | └ {ID} | {restatement-or-title} |
   | 2 | {ID} | {restatement-or-title} |
   ```

   **Ungrouped variant** (`THEME_COUNT` == 0) — the prior, flat form; used whenever this round has no theme to lead with:
   ```
   > **{TIER} round** — {round size} findings. {blocking statement}
   > {beyond-round count} findings remain beyond this round ({tier breakdown}).

   | # | ID | Summary |
   |---|-----|---------|
   | 1 | {ID} | {restatement-or-title} |
   | … | … | … |
   ```

   - **Tier name**: use the findings-file severity label — `MUST-ADDRESS`, `SHOULD-CONSIDER`, or `MINOR` — never the gate report's plain-language tier names.
   - **Blocking statement**: `These findings block the gate.` for MUST-ADDRESS; `These findings do not block the gate.` for SHOULD-CONSIDER and MINOR.
   - **Round size**: the number of findings in this round, fixed at partition time. Reported as the parenthetical context figure in the themed variant, and as the primary figure in the ungrouped variant.
   - **Beyond-round remainder**: the count of findings beyond this round, broken down by tier. Omit this second line entirely on the last round — there is nothing beyond it.
   - **Table**: lists every finding in the round — no elision, no `…` in real output. There is no threshold below which the table is suppressed; it renders at every round size, including a round of one.
   - **Row `#`**: in the ungrouped variant, equals the round-scoped position the finding display step later reports for that finding. In the themed variant, `#` numbers each top-level row — a theme's primary row and an ordinary finding's row each consume one `#` value; a theme's sub-rows carry no `#` of their own, since they are not independently addressable round positions.
   - **`Summary` column**: resolves through the restatement-or-title rule stated under Display finding, below — the finding's `**Digest**:` value where present, its title where absent. A theme's primary row uses `—` here instead — no single finding's digest represents the whole group — and each sub-row's `Summary` cell carries its own member's restatement-or-title.
   - **Theme row grouping**: a theme's primary row groups the findings sharing its `**Theme Group**` id, with one `└ {ID}` sub-row per member, in the same round-table order Component 1 fixed. A finding that shares no `**Theme Group**` id with any other member of this round renders as an ordinary flat row, exactly as the ungrouped variant, even within an otherwise-themed round.

   **Count-mismatch variant** (applies to every tier, not only MUST-ADDRESS): if this tier's parsed round size disagrees with the count recorded from the dispatch prompt during validation, state both counts rather than presenting either as authoritative:
   ```
   > **{TIER} round** — {parsed count} findings parsed, but {dispatch count} were reported at dispatch.
   > Walking the {parsed count} that parsed. The discrepancy may indicate a malformed findings file.
   > {beyond-round count} findings remain beyond this round ({tier breakdown}).
   ```

   **All-fallback variant**: if every row in this round's table resolved to the title (no finding in the round carried a `**Digest**:` value), say so — this makes a producer-side field change visible rather than letting it silently degrade into titles across the whole round:
   ```
   > No condensed restatement was found for any finding in this round; titles are shown instead.
   ```

2. **Boundary prompt** — skipped on the first round. If this is not the first round, emit the prompt below. It fires at **every** round transition independent of gate status, after this round's opener and table (step 1 above) have already rendered, and never after the final round — that exit runs through Component 4 (end-of-loop handling) instead, with no boundary prompt. Exactly one boundary prompt per transition.

   Status line, exactly one of:
   - **Variant A (gate passed)**: `**Gate passed** — the remaining findings are optional.`
   - **Variant B (gate remains blocked)**: `**Gate remains blocked** — {N} MUST-ADDRESS findings are unresolved.`

   Then, identical in both variants:
   ```
   1. **Continue** — resolve this round's findings one at a time
   2. **Resolve all remaining** — apply fixes for all {N} remaining findings automatically ({tier breakdown}), single-pass, no re-review
   3. **Ask about the remaining findings** — answer a question, then return to this same prompt
   4. **Stop** — exit interactive resolution now
   ```

   Under variant B, replace option 4 with:
   ```
   4. **Stop** — exit interactive resolution now. A gate decision follows.
   ```

   Process the choice:
   - **Continue**: proceed into this round's findings (the inner loop, step 3 below).
   - **Resolve all remaining**: record decision "auto-resolve" for this round and every round beyond it — the whole remaining queue, not only the round about to start. Exit the outer loop immediately, evaluate Component 3's checkpoint once, then proceed to Component 4 with all recorded decisions.
   - **Ask about the remaining findings**: answer the question, then re-present this same prompt unchanged — this advances past no finding and records no decision.
   - **Stop**: exit the outer loop immediately with decisions collected so far. Proceed to Component 4 with partial resolution state.

   This prompt **reads** the checkpoint evaluation Component 3 settled — it never triggers the gate transition itself, and neither does Component 3. The gate file is written once, at the tail of Component 5, after every accepted fix has been composed and checked. Until then the status line reports what the decisions imply, not what is on disk.

**MINOR round exception.** When this round's tier is MINOR, first set aside any finding carrying a `**Theme Group**:` line (a reconciliation-escalated finding per the carve-out above) — walk each such group through the ordinary per-group flow (steps 3-6 below), exactly as a MUST-ADDRESS/SHOULD-CONSIDER themed group is walked. For every MINOR finding that carries no `**Theme Group**:` line, skip the per-group walk entirely and run this batch presentation instead. Theme grouping at synthesis is otherwise restricted to the MUST-ADDRESS and SHOULD-CONSIDER tiers, so the resolution grouping dispatched for this round above (the same per-round dispatch every tier gets) is the only interaction signal the ordinary (non-escalated) MINOR batch has, and it runs before this presentation, not after:

```
**{round size} minor fixes proposed** — accept all?

| # | ID | Summary |
|---|-----|---------|
| 1 | {ID} | {restatement-or-title} |
| … | … | … |

Members of the same resolution group are rendered as an indented sub-row block under a shared group label, immediately following the group's first member's row — this makes the coordinated-edit boundary visible before the user commits to "accept all," rather than only in the composed diff afterward. A finding with no group renders as an ordinary row.

1. **Accept all** — apply every fix in this batch, composing each resolution group's fixes together as one coordinated edit
2. **Expand** — break the batch into individual findings (and groups) for per-finding accept/reject
3. **Skip all** — leave every finding in this round unresolved
4. **Auto-resolve remaining** — fix all remaining findings automatically (single-pass, no re-review)
5. **Discuss** — explore this batch before choosing an action
6. **Quit** — exit interactive mode now
```

- **Accept all**: record decision "accept" for every finding in the round as one unit. Component 5 composes each resolution group's members together as one coordinated fix — exactly as the ordinary group-accept path does — and composes ungrouped members independently.
- **Expand**: proceed into the per-group walk (steps 3-6 below) for this round exactly as though this exception did not apply. Every resolution group formed above is preserved — expanding changes only how the round is presented, not which findings interact.
- **Skip all**: record decision "skip" for every finding in the round.
- **Auto-resolve remaining**, **Discuss**, **Quit**: behave exactly as their per-finding counterparts in steps 4-5 below, applied to the whole round at once. Discuss re-presents this same batch prompt afterwards, never a per-finding prompt.

For each group in this round, in the order its members appear in the round's table:

A **group of one** is the common case. It is displayed and decided exactly as steps 3 through 5 describe below, with no combined prompt and no visible difference from resolution without grouping. A group of two or more additionally takes the group variant stated in each of those steps.

3. **Display finding**:
   - **Always show** (the user needs problem, evidence, and recommendation to make an informed decision):
     ```
     ### Finding {round position} of {round size} in {TIER} · {overall position} of {overall total}

     **TLDR**: {restatement}

     **{ID}**
     **Severity**: {MUST-ADDRESS | SHOULD-CONSIDER | MINOR}
     **Type**: {type}
     **Agent(s)**: {agent names}

     {description bullets — the problem statement}

     > **Evidence**: {specific spec/plan section reference}

     **Recommendation**: {recommended fix}
     ```
   - **Restatement-or-title rule**: read the finding's `**Digest**:` value, matched at column zero; where absent, substitute the finding's title. The restatement is the **first element of the finding body** — it renders immediately after the heading line, above severity, type, agent list, description bullets, evidence, and recommendation.
   - **Additive guard**: the restatement is additive — it is prepended to the finding, not a replacement for any part of it. It does not authorise collapsing, omitting, summarising away, or deferring the description bullets, evidence, or recommendation. Every finding renders in full, every time. No action exists whose purpose is to reveal withheld content.
   - No progressive disclosure — all finding content is shown by default. The finding format in `review/review-findings.md` is already concise; hiding parts behind "expand" adds friction without value.

   **Group variant (two or more members)**: emit the group header below, then every member's finding block in round-table order, as **one instruction block**. No decision is prompted and none is recorded until every member has rendered — a decision taken on the first member while the rest are still unseen is the uncoordinated behaviour grouping exists to replace.

   ````
   ### Coordinated group — {group size} findings in {TIER}

   > These findings interact: {the matched signal, in plain language}.
   > Resolving them separately risks one fix undoing another, so they are decided together.
   ````

   **Theme-derived group heading**: when a presentation group derives from a theme group (see Component 1's theme group consumption) rather than from resolution grouping, use the theme summary as the heading and matched-signal line instead of the generic wording above:

   ````
   ### Coordinated group — {group size} findings in {TIER}: "{theme-summary}"

   > These findings share a theme: {theme-summary}.
   > Resolving them separately risks a fragmented decision on the same design question, so they are decided together.
   ````

   A group formed by both signals at once (resolution grouping and a theme group agree on the same members) uses the theme-derived heading — the theme summary is the more informative label for a human deciding the group.

   The per-member blocks are unchanged: same heading line, same restatement, same severity, type, agent list, description bullets, evidence and recommendation. Grouping changes what is decided together, never what is shown.

   **Constitution MUST detection.** Before presenting the action prompt (step 4 below), compute this for the finding just displayed — for a group, once per member:

   ```
   IS_CONSTITUTION_MUST = finding.severity == "MUST-ADDRESS" AND (
     finding.id starts with "CC-"
     OR finding.agent_name contains "Constitution Compliance"
     OR finding.agent_name contains "Constitution Validator"
     OR finding has a **Violated Principle**: field
   )
   ```

   Agent-name matching uses **contains** semantics, not exact-match — a merged or synthesized finding can carry a comma-separated agent list (e.g. "Assumption Auditor, Constitution Compliance"), and the substring must still be found inside it. Where the match is ambiguous — a partial or fuzzy match against these three signals that doesn't clearly satisfy any of them — default to the standard, non-escalation path rather than guessing.

4. **Prompt for action**:
   Present 6 options:
   ```
   Choose an action:
   1. **Accept** — Apply the recommended fix
   2. **Skip** — Leave this finding unresolved, move to next
   3. **Custom** — Provide your own direction for how to resolve
   4. **Auto-resolve remaining** — Fix all remaining findings automatically (single-pass, no re-review)
   5. **Discuss** — Explore this finding before choosing an action
   6. **Quit** — Exit interactive mode now
   ```

   **Constitution MUST variant (`IS_CONSTITUTION_MUST` true, single finding)**: augment the 6-option prompt above — do not replace it — with governance context and two additional options, for 8 total. The governance context names the principle identifier and title extracted from this finding's `**Violated Principle**:` field (rendered in step 3's finding display above):
   ````
   ⚠️ **Governance-sensitive finding** — this violates {principle identifier} — {principle title}.

   Choose an action:
   1. **Accept** — Apply the recommended fix
   2. **Skip** — Leave this finding unresolved, move to next
   3. **Custom** — Provide your own direction for how to resolve
   4. **Auto-resolve remaining** — Fix all remaining findings automatically (single-pass, no re-review)
   5. **Discuss** — Explore this finding before choosing an action
   6. **Quit** — Exit interactive mode now
   7. **Override** — Acknowledge the governance risk and record this as an overridden constitution finding. No fix is applied.
   8. **Defer** — Leave this finding unresolved and the gate blocked on it, and move to next. No override is recorded.
   ````

   **Group variant (two or more members)**: present one combined prompt covering the whole group, instead of one prompt per member:
   ````
   Choose an action for this group of {group size}:
   1. **Accept all** — Apply one coordinated fix satisfying every finding in the group
   2. **Accept a subset** — Name the findings to fix; the rest are recorded as skipped
   3. **Skip all** — Leave every finding in the group unresolved
   4. **Custom** — Provide your own direction for resolving the group as a whole
   5. **Auto-resolve remaining** — Fix all remaining findings automatically (single-pass, no re-review)
   6. **Discuss** — Explore this group before choosing an action
   7. **Quit** — Exit interactive mode now
   ````

   **Constitution MUST group variant (at least one member has `IS_CONSTITUTION_MUST` true)**: present the group together exactly as the group variant above, with two changes:
   - **"Accept all" is unavailable** — a single coordinated fix must not silently resolve a governance-sensitive finding on the group's behalf.
   - **"Accept a subset" must name the constitution member with one of Accept, Override, or Defer.** The subset-naming flow cannot omit it and let it fall into "the rest are recorded as skipped" — an unnamed constitution member is not a valid subset naming, and the user is asked to re-name the subset until it names the constitution member explicitly.
   ````
   ⚠️ **Governance-sensitive group** — includes constitution finding {ID}, which violates {principle identifier} — {principle title}.

   Choose an action for this group of {group size}:
   1. **Accept a subset** — Name the findings to fix; {ID} must be named with Accept, Override, or Defer
   2. **Skip all** — Leave every finding in the group unresolved ({ID} is recorded as Defer)
   3. **Custom** — Provide your own direction for resolving the group as a whole
   4. **Auto-resolve remaining** — Fix all remaining findings automatically (single-pass, no re-review)
   5. **Discuss** — Explore this group before choosing an action
   6. **Quit** — Exit interactive mode now
   ````

5. **Process user choice**:
   - **Accept**: Record decision "accept" for this finding. Do NOT apply edits yet (see Component 5).
   - **Skip**: Record decision "skip" for this finding. Move to next finding.
   - **Custom**: Prompt user for custom direction. Record decision "custom: {user direction}" for this finding. If the direction is ambiguous or contradictory, ask the user to rephrase once. If still unclear after rephrase, record decision "skip" and move to next finding.
   - **Auto-resolve remaining**: Record decision "auto-resolve" for this finding and every remaining finding in the queue (from current position onward, spanning this round and every round beyond it). Exit the outer loop immediately, evaluate Component 3's checkpoint once, then proceed to Component 4 with all recorded decisions. This is a single-pass bulk fix — do NOT re-dispatch review agents or enter a convergence loop.
   - **Quit**: Exit the outer loop immediately with decisions collected so far. Proceed to Component 4 (end-of-loop handling) with partial resolution state.
   - **Discuss**: Engage in a brief conversation about this finding — clarify scope, explore alternatives, or ask questions about the evidence. After discussion, re-present the action choices for this same finding (do not advance to the next finding).

   **Constitution MUST variant (single finding)**:
   - **Override**: Record decision "override" for this finding. Accumulate its ID into `OVERRIDE_IDS` (in memory, for the batched call at the Component 5 tail) — do NOT invoke `record-gate-override.sh` here; the idempotence guard on `### Constitution Override` refuses a second call, and this finding walk can encounter several. Move to next finding.
   - **Defer**: Record decision "defer" for this finding — no fix, no override record, the gate stays blocked on it. Move to next finding.

   **Group variant (two or more members)**: record every member's decision as **one unit**. Nothing is recorded until the choice covering the whole group has been made.
   - **Accept all**: record "accept" for every member. Component 5 composes one coordinated fix satisfying them together — not one independent patch per member. Unavailable when the group contains an `IS_CONSTITUTION_MUST` member — see the constitution group variant in step 4.
   - **Accept a subset**: record "accept" for each named member and "skip" for each unnamed one. An unaccepted member is recorded as skipped, never folded into the coordinated fix on the grounds that it was adjacent to one that was accepted. When the group contains an `IS_CONSTITUTION_MUST` member, that member cannot be left unnamed: it must be named with "accept", "override", or "defer" (accumulating into `OVERRIDE_IDS` on "override", exactly as the single-finding case does), and the remaining named/unnamed members follow the standard subset rule above.
   - **Skip all**: record "skip" for every member; for a group containing an `IS_CONSTITUTION_MUST` member, record that member's decision as "defer" instead of "skip" — it still leaves the finding unresolved, but as a named governance decision rather than a silent skip.
   - **Custom**: prompt for the direction once and record "custom: {user direction}" for every member, composed as one coordinated fix. The per-finding Custom option's ambiguity handling applies unchanged — on a direction still unclear after one rephrase, record "skip" for every member.
   - **Auto-resolve remaining**, **Discuss**, **Quit**: behave exactly as their per-finding counterparts above. Discuss re-presents this same group's combined prompt afterwards, never a per-member prompt.

6. **Continue to next group**: After recording the group's decisions, move to the next group in this round and repeat from step 3 (the finding display) — not step 1.

After the final round's findings are all processed: proceed to Component 4 (end-of-loop handling). No boundary prompt fires here — the loop's own end is not a round transition.

## Component 3: Gate-Passed Checkpoint

The checkpoint is evaluated at two points:
- **Once per group**, after that group's decisions are recorded, where at least one member's decision is "accept" or "custom". Never once per member: a group's decisions are recorded as one unit, and evaluating mid-group would read a partial record. A group of one is a group, so a single ungrouped finding evaluates the checkpoint exactly once.
- **Once**, immediately after a bulk "auto-resolve" recording (whether triggered by the per-finding action in step 5 or by the boundary prompt's "Resolve all remaining" in step 2) — evaluated after all remaining decisions are recorded and before exiting the loop, never once per synthesised decision.

At each evaluation point, check:
- Are all MUST-ADDRESS findings in the queue now resolved (decision ∈ {accept, custom, auto-resolve})?

A constitution MUST finding decided "override" or "defer" is not in this set. Both leave the finding unresolved for this checkpoint, exactly as "skip" does — an override is an explicit governance decision, not a fix, and does not satisfy the predicate.

If YES: set `ALL_BLOCKING_RESOLVED = true`.

If NO: set `ALL_BLOCKING_RESOLVED = false` and continue looping through the queue.

**This component evaluates; it does not write the gate and does not announce a transition.** A decision to accept a fix is not the same event as that fix reaching disk in a coherent artifact. The fixes are composed and checked in Component 5, and any one of them can still be discarded there — so a gate written here could report `passed` over an artifact that was never written. The write happens once, at the tail of Component 5, after every check outcome has settled; `ALL_BLOCKING_RESOLVED` is what that write reads.

This checkpoint never presents a prompt of its own — the boundary prompt (Component 2, step 2) carries the user-facing status line and options for whatever happens next, in both the passed and blocked cases. It reads `ALL_BLOCKING_RESOLVED` as a status line about the decisions taken so far.

## Component 4: End-of-Loop Handling

When the outer loop exits — all rounds processed, or one of the four exits was taken (per-finding Quit, per-finding Auto-resolve remaining, boundary Stop, boundary Resolve all remaining):

**Case A**: All MUST-ADDRESS findings are resolved (decision ∈ {accept, custom, auto-resolve}):
- Record the case and continue to Component 5. **Do not announce a gate transition here** — the accepted fixes have not been composed or checked yet, and one that fails the check will be discarded, leaving the gate blocked. Announcing a pass here would claim a transition this component did not perform and cannot retract.
- The gate write for this case is the all-resolved branch at the Component 5 tail. That is the site that both performs the transition and announces it. Recommending the next pipeline command (`/speckit-plan` for primary gate, `/speckit-tasks` for secondary gate) happens there too, once the outcome is known.

**Case B**: Unresolved MUST-ADDRESS findings remain (some decision ∈ {skip, override, defer}):
- Display summary of unresolved findings. When any of them is a constitution MUST finding (decision "override" or "defer"), present ONE combined display — never two separate Case B prompts — that distinguishes the constitution findings from the ordinary skipped ones with ⚠️ framing:
  ```
  **Gate remains blocked** — {N} MUST-ADDRESS findings are unresolved:
  - {ID1}: {title}
  - {ID2}: {title}
  - [etc., ordinary skipped findings]

  ⚠️ **{K} constitution finding(s) also unresolved**:
  - {ID}: {title} — {principle identifier} — {principle title} ({"already overridden, pending record" | "deferred"})
  - [etc.]
  ```
  When no constitution finding is present, the ⚠️ block is omitted and the display is the plain skipped-findings summary as before.
- Offer override choice:
  ```
  Options:
  1. **Fix now** — Re-run `/speckit-review` to start a fresh review
  2. **Override** — Acknowledge risk and proceed to next step. Unresolved review findings may propagate to plan and implementation, requiring later rework.
  3. **Defer** — Leave the gate blocked and exit. To unblock, resolve the findings and re-run `/speckit-review`.
  ```
  This choice governs the ordinary skipped findings and any deferred constitution findings shown above. A constitution finding already decided "override" during the walk is not reopened by this choice — its record is emitted regardless, per the Component 5 tail's accumulated-override handling. If this choice is "Override" and deferred constitution findings were shown above, merge their IDs into `OVERRIDE_IDS` now — an in-memory bookkeeping update, not an execution of the record script — so the Component 5 tail's accumulated call covers them alongside any findings individually overridden earlier in the walk.

**Record the choice only — perform nothing here.** Whichever option the user picks, note the decision and continue to Component 5. Do not write the gate, do not append an override record, and do not announce an override yet.

Component 5 rebuilds `review/review-findings.md` in memory from content read at Component 1 and emits one Write call per file, so an append here would be silently discarded. Writing the gate here would be worse: it would flip the gate to `passed` before the record exists, leaving an orphaned passing gate if the record is then refused. Announcing success here would claim an override that has not happened and cannot be retracted if the record script refuses.

All four exits — per-finding Quit, per-finding Auto-resolve remaining, boundary Stop, boundary Resolve all remaining — converge here, before Component 5's batch write. Decisions are non-durable until that batch write, so any exit that bypassed this component would discard every decision recorded in the session.

## Component 5: Batch Edit Phase

After the interactive loop completes and end-of-loop handling is done, apply all collected decisions as batched edits.

**MANDATORY: One Write call per file.** Do NOT use sequential Edit calls to apply findings one at a time — this creates excessive tool call noise and risks partial application if the session is interrupted mid-sequence. Instead, build the complete updated content in memory and emit a single Write call per target file. This is non-negotiable.

1. **Collect all "accept" and "custom" and "auto-resolve" decisions** across all findings
2. **Group by target file**: spec.md, plan.md, contracts/, review/review-findings.md. This is the target inference Component 1's grouping step reuses — one inference, two consumers.
3. **Compose each target file in memory — do not write yet**:
   - Read the current file content (one Read call). **Retain that pre-fix content** for the rest of this component: the check needs it to tell a defect these fixes introduced from one the artifact already had.
   - **Compose one coordinated fix per group** whose members were accepted together, satisfying every accepted member of that group at once. Compose ungrouped findings — and groups of one — independently, as before.
   - In memory, apply all fixes for decisions marked "accept" or "auto-resolve" (use recommended fix from finding)
   - In memory, apply all fixes for decisions marked "custom" (use user-provided direction)
   - **Carry forward the `### Auto-Applied` and `### Discarded` sections and every finding's `**Theme Group**:` metadata line from the pre-fix content, unchanged**, when composing `review/review-findings.md` — this component owns checkbox updates and severity/type/disposition count tables, never removal of these sections or lines.
   - Note which regions each fix wrote, which findings contributed to this file, and which groups span it

4. **Run the `Holistic reconciliation pass`** by dispatching a `general-purpose` Agent (`model: "opus"`):

   ```
   Read and execute `.specify/templates/holistic-reconciliation.md`.

   COMPOSED=<map: artifact path → candidate content after all fixes applied>
   BASELINES=<map: artifact path → pre-fix content>
   WRITTEN_REGIONS=<map: artifact path → spans this run wrote>
   CONTRIBUTING=<map: artifact path → finding IDs>
   CANDIDATE_SET=<this gate's declared artifacts: spec.md at a primary gate; spec.md,
   plan.md, research.md and the files under contracts/ at a secondary gate>
   USER_PRESENT=true
   GROUPS=<groups from Component 1>

   For each artifact, report: defects found (quoted, classified, attributed), then outcome
   (clean / repaired / unrepairable).
   ```

   A human is present in this session, so bind its user-present input to true. Pass the groups formed in Component 1 as its groups input, so a coordinated fix is one repair unit rather than several.

   **Bind the candidate set to this gate's declared artifacts**. This is what lets the check reach a rule a fix here changed that a counterpart artifact still states in its superseded form — the class is inert without it, because a counterpart receives no fix of its own and so has nothing for the baseline comparison to catch.

   **If the agent reports the template is not present, stop.** Do not write any artifact, tell the user in plain language that the consistency check could not be run and name the file that is absent, and do not record a passing gate. Writing without the check is precisely the unchecked write the check exists to prevent, so this branch fails closed.

   **A divergence this path carries.** Nothing at this gate routes a fix to a source file — review findings target `spec.md`, `plan.md` and `contracts/` only. The check's no-effect rule is confined to regions this run wrote in a source file, so on this path that rule never fires. The other four detection classes all apply as written.

5. **Act on each artifact's outcome, then write**:
   - **Clean or repaired**: state every defect found before stating the outcome, name any accepted fix a repair altered or removed, then emit one Write call with the composed content for that file. Set `SESSION_ARTIFACTS_WRITTEN = true` the first time any Write call in this component succeeds, and never clear it — the gate write at the tail reads it to decide whether this session's edits need disclosing.
   - **Unrepairable**: present the surviving defect to the user, quoting the composed content that carries it, and offer the three choices the check defines — accept the composition as it stands, resolve a subset of the contributing fixes, or discard this file's fixes entirely.
     - **Accept**: write the file as composed and record `COMPOSITION_DEFECT_ACCEPTED = true` together with the accepted defect as a single line of text. The gate write at the tail turns this into an override record.
     - **Subset**: compose the named subset and check it once. This does not consume a further repair attempt. If the subset also fails, fall through to accept-or-discard for this file rather than prompting a third time.
     - **Discard**: do not write the file. Leave its contributing findings unresolved, set `ALL_BLOCKING_RESOLVED = false` if any of them was blocking, and name them in the summary below. Where the discarded fix was a coordinated one, discard it from every file it spans — half a coordinated fix on disk is the contradiction this check exists to prevent. Every other file that group spans whose own check passed is recomposed without the withdrawn fix and still written, so its unrelated fixes land; only the file that failed its own check loses everything.

6. **Update `review/review-findings.md` checkboxes** — bookkeeping, so it happens only after every composed artifact above has an outcome:
   - For each finding whose fix was written (decision = "accept" or "custom" or "auto-resolve", and its file was not discarded): change `- [ ] Resolved` to `- [x] Resolved`
   - For findings with decision = "skip", and for findings whose file's fixes were discarded: leave `- [ ] Resolved` unchanged
   - Updating a checkbox before the outcomes settle would record a finding resolved while its artifact went unwritten — the findings file and the artifact then disagree, and the next round reads the finding as already fixed.

**Artifact scope** (primary vs secondary gate):
- **Primary gate**: Fix spec.md only (+ review/review-findings.md = 2 Write calls max)
- **Secondary gate**: Fix spec.md, plan.md, and contracts/ (constrain to artifacts that exist)

**Multi-artifact findings**: If a finding affects multiple artifacts (e.g., inconsistency between spec and plan), "accept" applies all sub-fixes atomically across all affected artifacts. No artifact such a finding spans is written until every artifact it spans has produced a check outcome. The same holds for a coordinated group spanning several artifacts: apply it to every artifact it spans or to none, and write none of them until all of them have an outcome.

After all writes complete, display the check's results — each artifact's defects before its outcome, then the run-level summary — followed by:
```
**Edits applied**:
- spec.md: {N} findings resolved
- review/review-findings.md: {N} findings marked - [x] Resolved
[Include plan.md, contracts/ lines if secondary gate]
[Include a line per file whose fixes were discarded, naming the findings left unresolved]
```

### Substantiality signal (Component 5 tail)

A session that rewrites a block of instructions, with several findings' fixes landing in the same region, changes the artifact enough that the review which produced those findings no longer describes what is on disk. The cheapest honest response is to say so and let the user decide. A session of small isolated corrections does not warrant that, and a recommendation the user learns to ignore has stopped being a recommendation — so the bar is set to fire on the first class and stay silent on the second.

**Skip this computation entirely when the session applied no edits.** If `SESSION_ARTIFACTS_WRITTEN` is false, there is nothing to characterise; write no record and continue to the gate write.

Otherwise evaluate `SUBSTANTIALITY_SIGNAL` over the edits that reached disk — excluding anything discarded at the consistency check, since a discarded fix changed nothing. **Both** conditions must hold; neither alone is sufficient:

1. **Region convergence.** At least one group formed in Component 1 whose recorded match signal is **same-region only** has two or more members whose edits reached disk. Groups matched by the other signals are rule-based rather than positional and do not count here.
2. **Magnitude.** At least one edited artifact's diff for this session touches a **contiguous span of 8 or more lines**. This is what separates an instruction-block rewrite from a corrected count or a stale citation.

Requiring both is deliberate. A large edit with nothing converging on it is one self-contained change; three unrelated one-line corrections in three sections is an ordinary round. Only the combination — a substantial rewrite in exactly the place another accepted fix also landed — describes the class worth re-reviewing.

**Cross-tier region convergence is out of scope for this signal**, and deliberately so: grouping partitions by tier before it runs, so two findings in different tiers converging on one region are never in a group together. Detecting that would take a second, independent overlap computation, and two mechanisms disagreeing about what overlaps is worse than one that stays silent on a case this signal does not claim to cover.

**This signal is report-and-record only.** Nothing in this skill, and nothing that reads its record, dispatches a review as a result. It names a command; the user runs it or does not.

When the signal fires, the branch taken below writes, alongside its own next-command recommendation:

```bash
speckit run write-pipeline-state.sh review-recommendation \
  gate_type="$GATE_TYPE" \
  status=pending \
  command="<the dispatching review stage's own command>"
```

The command is `/speckit-review-spec` at a primary gate and `/speckit-review-plan` at a secondary gate. It is the whole payload — the value must stay a single line, so no prose accompanies it here; the reasoning goes in the report to the user, not in the record.

When the signal does not fire, write nothing. An absent record and a discharged one read the same way downstream, and neither surfaces anything.

### Gate write (Component 5 tail)

**When `$GATE_TYPE` is `secondary`, if any `write-review-gate-unified.sh` call in the four branches below exits 4** (the `plan` prerequisite is unmet): Read and execute `.specify/templates/prerequisite-refusal-gate.md` instead of treating it as an ordinary write failure. A primary-gate dispatch (`$GATE_TYPE` = `primary`) never participates in the prerequisite chain, so this note does not apply there.

**This is the only place in this skill that writes the gate.** Component 3 evaluates and does not write; Component 4 records a choice and does not write. Every path through this skill converges here, after every composed artifact has an outcome and the bookkeeping writes are done. Exactly one of the four branches below performs the gate write, and the branch that performs it announces it — no other section may announce a gate transition, because no other section performs one.

That three-way separation — evaluate in Component 3, choose in Component 4, write here — is what prevents two writers racing: a `blocked` touch landing after a `passed` override would leave the gate file and the pipeline-state entry telling the user opposite things.

**Record first, write second.** Where a branch needs an override record, the record script runs before the gate rewrite, and the gate is rewritten only on exit 0. Writing the gate first would leave an orphaned passing gate if the record is then refused. Interactive resolution is only ever dispatched from a synthesized finding set, so quorum was met by construction.

**Records are not branches.** A run can produce both kinds of record — a user can accept a composition defect *and* skip a blocking finding. They are different decisions about different subjects, and both are recorded. Where a run satisfies Branch 2 and Branch 3 together, emit **both** records — Branch 2's first — and then perform a single gate write carrying the true unresolved count. Selecting one branch and dropping the other record silently loses one of the two decisions from the audit trail.

**Five obligations every branch carries.** Whichever branch performs the write, it also does these five things, so that no path can satisfy one and silently drop the others:

1. **Disclose this session's edits.** Set `RESOLVED_FLAG` to `--resolved` when `SESSION_ARTIFACTS_WRITTEN` is true and to the empty string otherwise, and pass it on the gate write. This is what tells the commit hook that the `spec.md`/`plan.md`/`contracts/` changes in the working copy came from this session rather than from unrelated drift — it says who wrote the files, not whether the gate passed, so a passing branch carries it exactly as a blocked one does.
2. **Emit the re-review recommendation if the signal fired.** When `SUBSTANTIALITY_SIGNAL` fired, write the `review-recommendation` record shown above and surface the command it names in this branch's report — **alongside** the branch's own next-command recommendation, not instead of it.
3. **Discharge any pending recommendation from an earlier session.** Every branch here is a gate write for this `gate_type`. If the latest `review-recommendation` entry for this `gate_type` is `pending` and this session did **not** just fire the signal, write `status=discharged` with the same `command` value. Without this a user who overrides or defers after receiving a recommendation leaves it pending forever, and it resurfaces after the decision that answered it.
4. **Preserve any pre-existing `auto_applied` flag.** Before this branch's gate write, read `auto_applied` from the existing `review/review-gate.json` and set `AUTO_APPLIED_FLAG` to `--auto-applied` when it is `true`, and to the empty string otherwise, then pass it on the gate write alongside `$RESOLVED_FLAG`. This skill never sets `auto_applied` itself, but a plan-review synthesis run upstream may have — without re-reading and re-passing it here, this branch's write silently resets it to `false`, and `sapling-commit.sh` then excludes `plan.md` from its commit scope even though synthesis-phase auto-apply edits are still on disk.
5. **Preserve the existing `attempt_id`, `partial`, `panel_size` and `quorum_met` fields.** Before this branch's gate write, read all four from the existing `review/review-gate.json`. Set `ATTEMPT_ID_FLAG` to `--attempt-id "<value>"` when `attempt_id` is present and not `null`, and to the empty string otherwise; set `PARTIAL_FLAG` to `--partial` when `partial` is `true`, and to the empty string otherwise; set `PANEL_SIZE_FLAG` to `--panel-size "<value>"` when `panel_size` is present and not `null`, and to the empty string otherwise; set `QUORUM_MET_FLAG` to `--quorum-met "<value>"` when `quorum_met` is present and not `null`, and to the empty string otherwise. Pass all four on the gate write alongside `$RESOLVED_FLAG` and `$AUTO_APPLIED_FLAG`. This skill mints none of them — the synthesis step that produced the findings set this session is resolving wrote them onto the gate — so without re-reading and re-passing them here, this branch's write silently resets `attempt_id` to `null`, which the review command's own outcome check reads as "not yet written", and resets `panel_size` to `0` and `quorum_met` to `true`, which are `write-review-gate.sh`'s defaults rather than this review's actual coverage. A `panel_size` of `0` makes `/speckit-autopilot`'s partial-coverage note render a negative reviewer count, and makes `review-attempt.sh cleanup`'s coverage refusal pass on any value, deleting an attempt directory that partial coverage requires be retained.

**The accumulated constitution override becomes durable only through Branch 3.** `OVERRIDE_IDS` collects every constitution finding the walk decided "override" — one finding at a time in step 5, never invoking the record script per-finding, because the idempotence guard on `### Constitution Override` would refuse the second and later calls. `OVERRIDE_IDS` never has members when `ALL_BLOCKING_RESOLVED` is true — a finding decided "override" never satisfies that predicate — so it never fires alongside Branch 1. Its call site is Branch 3, below: a per-finding Override decision becomes a persisted record only when the overall gate actually transitions to an overridden pass. See Branch 3 and Branch 4 for what happens on each side of that.

**Branch 1 — `ALL_BLOCKING_RESOLVED` is true, no blocking-tier discard occurred, and no composition defect was accepted.** This is the all-resolved path, and the write is unconditional on it:

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
  $ATTEMPT_ID_FLAG \
  $PARTIAL_FLAG \
  $PANEL_SIZE_FLAG \
  $QUORUM_MET_FLAG
```

Then display "Gate updated: BLOCKED → PASSED" and recommend the next pipeline command (`/speckit-plan` for primary gate, `/speckit-tasks` for secondary gate).

**Branch 2 — `COMPOSITION_DEFECT_ACCEPTED` is true.** Record the accepted defect, then pass the gate as an override. `--subject` carries the defect as a single line; the script rejects an embedded newline:

```bash
speckit run record-gate-override.sh \
  --quorum-met true \
  --cause check-failure \
  --subject "<the accepted composition defect, one line>"
```

- **On exit 0**: rewrite the gate with the same invocation as branch 1 plus `--override`. `write-review-gate-unified.sh` validates all six required flags and exits via `usage()` on any empty value; `$GATE_TYPE` is a real dispatch-context variable in this preset. `--override` puts the override into both the gate file and the pipeline-state entry, so one decision class is recorded one way and no separate pipeline-state call is needed:

  ```bash
  speckit run write-review-gate-unified.sh \
    --gate-type "$GATE_TYPE" \
    --status passed \
    --must-address 0 \
    --should-consider "$SHOULD_CONSIDER_COUNT" \
    --minor "$MINOR_COUNT" \
    --agents-completed "$AGENTS_COMPLETED" \
    --override \
    $RESOLVED_FLAG \
    $AUTO_APPLIED_FLAG \
    $ATTEMPT_ID_FLAG \
    $PARTIAL_FLAG \
    $PANEL_SIZE_FLAG \
    $QUORUM_MET_FLAG
  ```

  Then display "Gate overridden: BLOCKED → PASSED (user accepted a composition defect the consistency check could not repair)", state the accepted defect, and recommend the next pipeline command.
- **On exit 3**: report the refusal — including when it is the duplicate-record refusal, which names its cause — and do **not** rewrite the gate.
- **On any other non-zero exit**: report that the override record could not be written, state the script's message, and do **not** rewrite the gate. `--subject` is agent-authored prose and an embedded newline is a usage error rather than a refusal, so collapse the defect to one line before passing it.

This branch is reachable whether or not any finding was skipped, so it does not sit inside Case B. A session in which every finding was accepted and one composition failed its check reaches it on the Case A path.

**Both records, one write.** A run that accepts a composition defect *and* skips a blocking finding satisfies this branch and Branch 3 at once. Emit both records — this branch's first — then perform a single gate write. `--must-address 0` is correct on an overridden gate: the user waived the findings deliberately, and the override records enumerate every one of them, so the count is not the audit trail.

**Branch 3 — blocking findings remain and Component 4 Case B's recorded choice was "Override".** When `OVERRIDE_IDS` is non-empty (a constitution finding was individually overridden during the walk, a deferred constitution finding was merged in at Case B, or both), issue this call FIRST — the first of two sequential records:

```bash
speckit run record-gate-override.sh \
  --quorum-met true \
  --cause constitution_must \
  --finding-ids "<OVERRIDE_IDS, comma-separated>"
```

- **On exit 0**: also run `speckit run write-pipeline-state.sh {stage} override=true constitution_override=true cause=constitution_must` — the unified gate writer's automatic pipeline-state entry below does not carry the `constitution_override`/`cause` markers, so this is what makes the constitution-specific override distinguishable in `pipeline-state.jsonl`. Then continue to the second record call below.
- **On exit 3 or any other non-zero exit**: report the refusal exactly as Branch 2 does and stop here — do not continue to the call below, and do not rewrite the gate. A genuine constitution-override failure must not be silently absorbed into the ordinary unresolved-findings override that follows.

When `OVERRIDE_IDS` is empty, skip the call above and start here. Record the (remaining) unresolved set — covering the rest under `--cause unresolved-findings` via its existing awk derivation, which also lists any constitution finding just recorded above (it is still unchecked in `review/review-findings.md`) — then pass the gate as an override:

```bash
speckit run record-gate-override.sh \
  --quorum-met true
```

- **On exit 0**: rewrite the gate:

  ```bash
  speckit run write-review-gate-unified.sh \
    --gate-type "$GATE_TYPE" \
    --status passed \
    --must-address 0 \
    --should-consider "$SHOULD_CONSIDER_COUNT" \
    --minor "$MINOR_COUNT" \
    --agents-completed "$AGENTS_COMPLETED" \
    --override \
    $RESOLVED_FLAG \
    $AUTO_APPLIED_FLAG \
    $ATTEMPT_ID_FLAG \
    $PARTIAL_FLAG \
    $PANEL_SIZE_FLAG \
    $QUORUM_MET_FLAG
  ```

  Then display "Gate overridden: BLOCKED → PASSED (user acknowledged {N} unresolved findings)" and recommend the next pipeline command.
- **On exit 3**: report "override refused — gate unchanged" and do **not** rewrite the gate.

Run it only on the recorded "Override" choice. Running it on a "Re-run `/speckit-review`" choice would fabricate a record for a decision the user never made, after which the idempotence guard would refuse the genuine one.

**Branch 4 — blocking findings remain and the recorded choice was "Fix now" or "Defer", or a blocking-tier discard occurred.** If `OVERRIDE_IDS` is non-empty here, do not call `record-gate-override.sh` — this branch's gate write stays at `blocked`, and a constitution override record is only durable when paired with the gate transition that justifies it (Branch 3). A per-finding "override" decision that lands here behaves like "defer" for this session: the finding stays unresolved and blocking, `review/review-findings.md` keeps its checkbox unchecked, and a future session must decide it again. Touch the gate so `sapling-commit.sh` can see this session's edits are sanctioned, without changing its `blocked` status. Pass the count of findings still unresolved — those the user skipped plus those whose fixes the check discarded — as `--must-address`, so the count is not left stale at its pre-loop value:

```bash
speckit run write-review-gate-unified.sh \
  --gate-type "$GATE_TYPE" \
  --status blocked \
  --must-address "<count of findings still unresolved>" \
  --should-consider "$SHOULD_CONSIDER_COUNT" \
  --minor "$MINOR_COUNT" \
  --agents-completed "$AGENTS_COMPLETED" \
  $RESOLVED_FLAG \
  $AUTO_APPLIED_FLAG \
  $ATTEMPT_ID_FLAG \
  $PARTIAL_FLAG \
  $PANEL_SIZE_FLAG \
  $QUORUM_MET_FLAG
```

**Skip this call when nothing was written.** If no fix reached disk this session — every finding skipped, or every composition discarded — the gate already reflects an untouched state and needs no touch. On that path `SESSION_ARTIFACTS_WRITTEN` is false, so the substantiality signal was skipped and there is no recommendation to emit either; a pending recommendation from an earlier session stays pending, correctly, because this session wrote no gate to discharge it against.
