---
name: speckit-analyze
description: 'SpecKit SDD pipeline: cross-artifact consistency analysis across `specs/<feature>/` spec, plan, and tasks.'
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:meta
  meta_preset_strategy: replace
  meta_preset_upstream: speckit.analyze
user-invocable: true
disable-model-invocation: false
---



# Speckit Analyze Skill

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Workspace check (MANDATORY)**: Run `speckit run require-workspace.sh`. This resolves the workspace from any subdirectory and produces the same fixed message when there is no workspace above the current directory. On a non-zero exit, relay its stderr output to the user verbatim — do not paraphrase, reword, summarize, or translate it; do not prepend or append anything (no preface, heading, or attribution such as "require-workspace.sh failed:"); do not name the script, the command, the exit code, or any internal path — then halt. On exit 0, proceed silently to the next check.

**Pre-execution hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.before_analyze` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue. Wait for all hooks to complete before continuing.

**Model note**: Sonnet is sufficient for analyze — this is structural cross-artifact scanning, not creative reasoning or adversarial attack.

## Goal

This command checks your spec, plan, and tasks for internal consistency — catching gaps, contradictions, and constitution violations before you start implementing.

Identify inconsistencies, duplications, ambiguities, and underspecified items across the three core artifacts (`spec.md`, `plan.md`, `tasks.md`) before implementation. This command MUST run only after `/speckit-tasks` has successfully produced a complete `tasks.md`.

## Operating Constraints

**READ-ONLY by default**: Output a structured analysis report and offer remediation options. The command does not modify artifact files unless the user explicitly selects "Apply all recommended fixes" in the Remediation step.

Two exemptions to the read-only constraint:
1. This command's own pipeline-state outcome record, which every run writes in the outcome-reporting step.
2. When the user selects "Apply all recommended fixes," the command applies remediation edits to spec.md, plan.md, and/or tasks.md using the same Compose, Check, Write discipline as Review's auto-resolve, with holistic reconciliation.

**Constitution Authority**: The project constitution (`.specify/memory/constitution.md`) is **non-negotiable** within this analysis scope. Constitution conflicts are automatically CRITICAL and require adjustment of the spec, plan, or tasks—not dilution, reinterpretation, or silent ignoring of the principle. If a principle itself needs to change, that must occur in a separate, explicit constitution update outside `/speckit-analyze`.

**Auto mode**: Under `--auto`, skip the Remediation step's interactive menu and default to "Skip" — do not apply fixes or prompt. The Row 2 gate menu is also skipped under `--auto`: default to "Defer" (exit cleanly, leaving the gate blocked).

## Execution Steps

Before starting work, briefly tell the user what this stage does, why it matters, and that it typically takes a few minutes. Print the introduction in bold.

### 1. Initialize Analysis Context

Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` once from repo root and parse JSON for FEATURE_DIR and AVAILABLE_DOCS. Derive absolute paths:

- SPEC = FEATURE_DIR/spec.md
- PLAN = FEATURE_DIR/plan.md
- TASKS = FEATURE_DIR/tasks.md

`AVAILABLE_DOCS` lists optional docs only (e.g., `research.md`, `data-model.md`) — `spec.md`/`plan.md`/`tasks.md` are mandatory and already validated by the script, so their absence from that list does not mean they're missing.

Abort with an error message if any required file is missing (instruct the user to run missing prerequisite command).
For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

### 2. Load Artifacts (Progressive Disclosure)

Load only the minimal necessary context from each artifact.

**From spec.md:**

- Overview/Context
- Functional Requirements
- Success Criteria (measurable outcomes — e.g., performance, security, availability, user success, business impact)
- User Stories
- Edge Cases (if present)

**From plan.md:**

- Architecture/stack choices
- Data Model references
- Phases
- Technical constraints

**From tasks.md:**

- Task IDs
- Descriptions
- Phase grouping
- Parallel markers [P]
- Referenced file paths

**From constitution:**

- Load `.specify/memory/constitution.md` — resolved against the **workspace root**, not as a bare relative path — for use in Detection Pass D (step 4D). Derive that root from the absolute `FEATURE_DIR` the Initialize Analysis Context step already parsed, by removing its trailing `specs/<feature>` segment; the result is the directory holding `.specify/`. (`check-prerequisites.sh` emits `FEATURE_DIR` and `AVAILABLE_DOCS` only — it does not report the root directly, so derive it rather than expecting a field.) Anchor the load to that root rather than to the current directory: a bare path resolves differently depending on the directory the session started in, which would make a wrong-directory invocation indistinguishable from a genuinely deleted file. If no workspace root was resolved at all, that is the missing-workspace condition the Pre-Execution Checks already cover — report it as that, and never as an absent constitution. Validate loading only:
  1. **Existence**: File exists at the resolved path and parses as valid markdown
  2. **Placeholder detection**: If the file contains the sentinel `<!-- speckit:constitution:placeholder -->`, it is an unconfigured placeholder. Report an INFO-level finding: "Constitution not configured — constitution compliance checks skipped. Run `/speckit-constitution` to configure." Skip the Constitution Alignment pass (step 4D) entirely. Do NOT report this as CRITICAL — CRITICAL is reserved for true absence of a constitution that should exist.
  3. **Logging**: If the file is absent or unreadable at the resolved path, report as a CRITICAL finding — do not silently skip. A path that could not be resolved at all is the missing-workspace condition above, not this one.

- **Carry the load outcome forward.** Record which of three outcomes this load produced — *unconfigured placeholder*, *resolved but absent or unreadable*, or *loaded* — and save it for use in the outcome-reporting step (Provide Next Actions), which computes the run's recorded outcome from it. That step consumes the placeholder and could-not-load outcomes directly; neither is re-derived there.

### 3. Build Semantic Models

Create internal representations (do not include raw artifacts in output):

- **Requirements inventory**: For each Functional Requirement (FR-###) and Success Criterion (SC-###), record a stable key. Use the explicit FR-/SC- identifier as the primary key when present, and optionally also derive an imperative-phrase slug for readability (e.g., "User can upload file" → `user-can-upload-file`). Include only Success Criteria items that require buildable work (e.g., load-testing infrastructure, security audit tooling), and exclude post-launch outcome metrics and business KPIs (e.g., "Reduce support tickets by 50%").
- **User story/action inventory**: Discrete user actions with acceptance criteria
- **Task coverage mapping**: Map each task to one or more requirements or stories (inference by keyword / explicit reference patterns like IDs or key phrases)
- **Constitution rule set**: Extract principle names and MUST/SHOULD normative statements

Parse the `complexity` field from the spec's YAML frontmatter (`standard`/`compact`), the same way step 3 of `/speckit-clarify` parses `risk`. If the `complexity` field is absent or contains an unrecognized value, treat the spec as standard.

If the spec has `complexity: compact` in its YAML frontmatter:
- If the Success Criteria section is absent: build the requirement inventory from FRs only. If present: include SC-### identifiers normally.
- Build the user story/action inventory from the single story — do not flag single-story specs as underspecified.
- Treat the Verification Notes section as the acceptance criteria alignment source (replacing full Given/When/Then scenarios) for Step 4C's underspecification check.
- Display: "Compact spec detected — requirement inventory built from FRs (Success Criteria included if present), Verification Notes treated as acceptance-criteria alignment, and underspecification flags skipped for legitimately omitted sections."

### 4. Detection Passes (Token-Efficient Analysis)

Focus on high-signal findings. Limit to 50 findings total; aggregate remainder in overflow summary.

#### A. Duplication Detection

- Identify near-duplicate requirements
- Mark lower-quality phrasing for consolidation

#### B. Ambiguity Detection

- Flag vague adjectives (fast, scalable, secure, intuitive, robust) lacking measurable criteria
- Flag unresolved placeholders (TODO, TKTK, ???, `<placeholder>`, etc.)

#### C. Underspecification

- Requirements with verbs but missing object or measurable outcome
- User stories missing acceptance criteria alignment
- Tasks referencing files or components not defined in spec/plan

For compact specs, do not flag absent Success Criteria or Key Entities sections as underspecification — these are legitimately omitted when the section is absent. If either section IS present, check it normally.

#### D. Constitution Alignment

- **Principle compliance**: Any spec requirement or plan element conflicting with a constitution MUST principle
- **Plan compliance**: Plan silently ignoring constitution constraints
- Missing mandated sections or quality gates from constitution

**Cross-Reference with Review Findings:**

Check for review findings: if `review/review-findings.md` exists in FEATURE_DIR, use it. Parse for CC-prefixed findings (hardcoded prefix `CC-###`). Compare Detection Pass D findings against CC agent findings and flag inconsistencies in the evidence table. If the review findings file is not found, log "WARNING: review findings file not found — skipping CC cross-reference". A missing input must be visible in the report, never silently skipped.

#### E. Coverage Gaps

- Requirements with zero associated tasks
- Tasks with no mapped requirement/story
- Success Criteria requiring buildable work (performance, security, availability) not reflected in tasks

#### F. Inconsistency

- Terminology drift (same concept named differently across files)
- Plan or tasks specify a different value for an external contract explicitly stated in a spec FR — CLI flag name, API parameter, schema field, output format, service contract. Classify as a **contradiction** (HIGH), not terminology drift (MEDIUM). Applies only when the spec makes a positive claim that the plan contradicts; spec silence about something the plan adds is not a contradiction.
- Data entities referenced in plan but absent in spec (or vice versa)
- Task ordering contradictions (e.g., integration tasks before foundational setup tasks without dependency note)
- Conflicting requirements (e.g., one requires Next.js while other specifies Vue)

### 5. Severity Assignment

Use this heuristic to prioritize findings:

- **CRITICAL**: Violates constitution MUST, missing core spec artifact, or requirement with zero coverage that blocks baseline functionality
- **HIGH**: Duplicate or conflicting requirement, ambiguous security/performance attribute, untestable acceptance criterion, or plan/tasks directly contradicting a spec FR's stated external contract (CLI flag name, API parameter, schema field, output format, service contract)
- **MEDIUM**: Terminology drift, missing non-functional task coverage, underspecified edge case
- **LOW**: Style/wording improvements, minor redundancy not affecting execution order

**Blocking Behavior:** Every run records its outcome to pipeline state in the outcome-reporting step, whatever it found — recording is unconditional. Blocking is narrower: it is reserved for CRITICAL constitution violations found by Detection Pass D, and for a constitution that could not be loaded at all. Findings at any other severity — including CRITICAL findings from passes other than D — are recorded for inspection but do not prevent progression to implementation.

### 6. Produce Analysis Report

Display parsed evidence BEFORE stating summary metrics. Metrics without visible evidence are unverifiable claims.

**Evidence tables (produce first):**

1. **Requirement Inventory**: List all FR-### IDs extracted from the spec, with their text
2. **Task Coverage Mapping**: Show which task IDs map to which requirements, as a table
3. **Constitution Violations**: Show a table of any constitution principle violations with line references from the offending artifact

**Then produce the findings report:**

| ID | Category | Severity | Location(s) | Summary | Recommendation |
|----|----------|----------|-------------|---------|----------------|
| A1 | Duplication | HIGH | spec.md:L120-134 | Two similar requirements ... | Merge phrasing; keep clearer version |

(Add one row per finding; generate stable IDs prefixed by category initial.)

**Coverage Summary Table:**

| Requirement Key | Has Task? | Task IDs | Notes |
|-----------------|-----------|----------|-------|

**Constitution Alignment Issues:** (if any)

**CC Cross-Reference Table:** (if review findings file exists)

| Analyze ID | CC ID | Status | Notes |
|------------|-------|--------|-------|

**Unmapped Tasks:** (if any)

**Summary Metrics (after evidence):**

- Total Requirements
- Total Tasks
- Coverage % (requirements with >=1 task)
- Ambiguity Count
- Duplication Count
- Critical Issues Count

### 7. Provide Next Actions

At end of report, determine a concise Next Actions block, but do not display the general guidance below yet unless this step exits early — the "Display next-step guidance" step at the end of this command displays it after the post-completion hook, so it is the last thing shown this turn.

➡️ **Successor obligation**: once the gate is passed or overridden, the next stage is `/speckit-implement`. Always name it as the recommended next step — do not substitute an ordering of your own, and do not recommend jumping ahead to a later stage.

#### Compute the outcome

Two inputs, both already settled: the constitution load outcome carried forward from the Load Artifacts step, and the severities assigned to this run's findings. Take the **first matching row**:

| Row | Condition | Record |
|-----|-----------|--------|
| 1 | The constitution resolved, but was absent or unreadable | `status=blocked reason=constitution_unavailable` |
| 2 | Detection Pass D found CRITICAL violations of a constitution principle | `status=blocked reason=critical_constitution_violation` |
| 3 | CRITICAL findings from any pass other than Detection Pass D | `status=passed caveat=non_constitution_critical` |
| 4 | HIGH findings, and no CRITICAL findings of either kind | `status=passed caveat=high_findings` |
| 5 | Only LOW/MEDIUM findings, or none at all | `status=passed caveat=clean` |

Match row 2 on **Detection Pass D's own output** — never on whether a finding's text mentions the constitution. The could-not-load case is reported as a CRITICAL finding too, so matching on the word would swallow row 1 and make it unreachable. Pass D runs only when the constitution loaded, so rows 1 and 2 can never both match.

Independently of the table: if the load outcome was the unconfigured placeholder, add `constitution=not_configured` to the record. It is a field, not a row, and never replaces the row's own marker — a run whose compliance check never ran still reports the severity tier its findings earned.

#### Write the outcome, before anything else in this step

Issue one call carrying the matched row's fields, `writer=analyze`, and the constitution-state field when it applies:

`speckit run write-pipeline-state.sh analyze <row fields> writer=analyze [constitution=not_configured]`

Do this **before** presenting the gate below, before any exit, and before the Next Actions block. Capture the script's stdout into a variable and never show it to the user — it names an absolute internal path and a raw schema field. Capture it, do not redirect it: no `>/dev/null`, no `2>&1`, no `2>/dev/null`. The confirmation below needs the captured text, and stderr must stay readable.

**Confirm the write and handle its failure.** This rule governs both this call and the Override call below:

- Read the `seq` out of the captured confirmation. Re-read `FEATURE_DIR/pipeline-state.jsonl` with the same query the implement gate uses — `jq -R 'fromjson? // empty' "$FEATURE_DIR/pipeline-state.jsonl" | jq -sr '[.[] | select(.stage == "analyze")] | last'` — and check that entry carries that same `seq` **and every field the record specifies**: `status`, `writer`, the row's `reason` or `caveat` — **both**, on the Override record, which carries a `reason` and a `caveat` together — and the constitution-state field when the run carries one.
  The parse is line-wise on purpose: `jq -s` alone aborts the entire read on one unparseable line, so a record that landed would read as missing.
- A non-zero exit, a missing `seq`, or any field that fails to match is a write failure. Checking `status` alone is not enough — a malformed argument leaves `status` correct while silently dropping the field it was meant to set, and a read not scoped to this run's `seq` can match a previous run's record and falsely confirm.
- On a **blocked** outcome (rows 1–2), halt now, before the gate below: a gate that cannot be recorded cannot be honoured, and a missing record reads as "proceed" downstream. On a **passed** outcome (rows 3–5), say so and continue — the worst case is a re-run.
- State any failure in your own words. Never pass the script's stderr through verbatim; every string it emits names an internal path, filename, or raw JSON.

#### Branch on the outcome

- **Row 2 only** — present graduated gate options now; this prompt is interactive and not deferred. Do not present these options until the outcome record above has been confirmed.
    ```
    CRITICAL constitution violations detected.

    Options:
    1. **Apply all fixes** — Apply the recommended remediations from this analysis, then re-evaluate the gate.
    2. **Fix now (manual)** — Resolve the violations yourself, then re-run `/speckit-analyze`.
    3. **Override** — Proceed despite violations. CRITICAL violations may remain unresolved, requiring later rework.
    4. **Defer** — Exit now. To unblock, resolve the CRITICAL violations and re-run `/speckit-analyze`.
    ```
    - If **Apply all fixes**: skip the Remediation step's option menu and proceed directly to the "#### If \"Apply all recommended fixes\"" section within the Remediation step. Do not exit the command here.
    - If **Fix now (manual)** or **Defer**: display this exit guidance now and stop.
    - If **Override**: write the superseding record — `speckit run write-pipeline-state.sh analyze status=passed override=true reason=critical_constitution_violation caveat=<value> writer=analyze` — where `<value>` is the marker rows 3–5 produce when re-evaluated over this run's findings **excluding** the constitution violations Pass D reported. Confirm it by the rule above, then display "Analyze gate overridden — proceeding with CRITICAL violations unresolved." and continue.
- **Row 1** — report the finding, display the row-1 Next Actions guidance below now, and stop. Present no gate menu here: a constitution that could not be read is not something this command asks the user to override.
- **Rows 3–5** — continue to the remaining steps.

**Terminal paths.** Three paths end the command inside this step: Fix now (manual)/Defer, row 1's exit, and the blocked-outcome halt on a failed write. Whenever the run leaves by any of them, the remaining steps of this command — remediation, the post-completion hook, and the next-step display — do not run. Apply all fixes and Override continue to subsequent steps.

#### Next Actions content

Hold the bullet matching this run's outcome, plus explicit command suggestions, for the final display step:

- **Row 1**: state both routes out in plain language — restore or configure the constitution and re-run `/speckit-analyze`, or proceed and override at `/speckit-implement`'s own gate. This is a statement of the two routes, not a menu to choose between.
- **Row 2**: the gate above governs; hold the guidance matching the branch the user took.
- **Row 3**: recommend resolving the CRITICAL non-constitution findings before `/speckit-implement`.
- **Row 4**: note that HIGH findings remain and recommend reviewing them before `/speckit-implement` — they do not block.
- **Row 5**: note that the user may proceed, with improvement suggestions.
- **Unconfigured constitution** (alongside whichever of rows 3–5 matched): note that compliance was not checked because the constitution is still a placeholder, and that `/speckit-constitution` configures it. This is non-blocking.
- Explicit command suggestions, e.g. "Run `/speckit-specify` with refinement", "Run `/speckit-plan` to adjust architecture", "Manually edit tasks.md to add coverage for 'performance-metrics'"

### 8. Remediation

Present the user with these options:

```
Options:
1. **Apply all recommended fixes** — Apply remediation edits to spec.md, plan.md, and/or tasks.md, then re-evaluate the gate.
2. **Suggest remediation only** — Show concrete remediation edits without applying them.
3. **Skip** — Proceed without remediation.
```

**Scope boundary:** Remediation — whether applied or suggested — is limited to edits within the three analyzed artifacts (spec.md, plan.md, tasks.md). Do NOT suggest or apply changes to code, CLAUDE.md, constitution, or other files outside the spec pipeline. If a finding requires changes beyond the three artifacts, recommend the appropriate command (e.g., `/speckit-specify` for spec rewrites, `/speckit-constitution` for principle changes).

#### If "Apply all recommended fixes"

Collect all findings from the analysis report that have actionable recommendations targeting one of the three artifacts (spec.md, plan.md, tasks.md). If no findings have actionable recommendations targeting those artifacts, report "No actionable fixes to apply — all findings either lack concrete edit recommendations or target files outside the spec pipeline." and fall back to "Suggest remediation only" behavior.

Apply fixes using the same Compose, Check, Write discipline Review uses:

**Group interacting findings.** Dispatch a `general-purpose` Agent (`model: "sonnet"`) to run `Resolution grouping`:

```
Read and execute `.specify/templates/resolution-grouping.md`.

ACCEPTED=<findings with actionable recommendations, each with ID, severity, target artifact, evidence, recommendation>
TIER=<all severities being resolved>
CANDIDATE_SET=<spec.md, plan.md, tasks.md — absolute paths>

Return GROUPS: for each group, its member finding IDs, the matched signal, and the
artifacts it spans.
```

If the template is absent, report in plain language and fall back to "Suggest remediation only" behavior.

**Plan the fixes without applying them.** For each finding, determine its target artifact and the change its recommendation requires. For a group of two or more, plan one coordinated change satisfying every member together.

**Compose per artifact.** For each target artifact that received at least one fix, build its full new content in memory from its pre-fix content plus every fix routed to it. Compose a coordinated fix once per group and apply it to every artifact that group spans, or to none of them. Retain pre-fix content for the reconciliation check.

**Run the holistic reconciliation pass.** Dispatch a `general-purpose` Agent (`model: "opus"`):

```
Read and execute `.specify/templates/holistic-reconciliation.md`.

COMPOSED=<map: artifact path → candidate content after all fixes applied>
BASELINES=<map: artifact path → pre-fix content>
WRITTEN_REGIONS=<map: artifact path → spans this run wrote>
CONTRIBUTING=<map: artifact path → finding IDs>
CANDIDATE_SET=<spec.md, plan.md, tasks.md — absolute paths>
USER_PRESENT=true
GROUPS=<groups from the resolution grouping above>

For each artifact, report: defects found (quoted, classified, attributed), then outcome
(clean / repaired / unrepairable).
```

If the template is absent, report in plain language and do not write any artifact.

**Write outcomes.**

Hold all writes until every artifact in a coordinated group has an outcome. Then:

- If **all** spanned artifacts in a group are clean or repaired: write them all to disk. Report any defects found and repairs made before stating the outcome.
- If **any** spanned artifact in a group is unrepairable: write none of that group's artifacts. Report which findings could not be applied and why.
- Artifacts that are not part of any coordinated group (standalone fixes) are written individually on a clean or repaired outcome.

**Re-evaluate the gate.**

When the prior outcome was blocked (Row 2 — CRITICAL constitution violations), check for unwritten Pass D fixes first, then run a scoped constitution re-check over on-disk content before deciding whether to unblock.

**Pre-check: unwritten Pass D fixes.** If any Pass D CRITICAL finding's fix was not written to disk — because reconciliation discarded it, because a coordinated group it belonged to was discarded, or because it had no actionable recommendation — the re-check is an automatic FAIL for that finding. Record it as STILL_PRESENT without dispatching the agent for it. If every Pass D finding falls into this case, skip the agent dispatch entirely and proceed directly to the FAIL branch below.

**Constitution re-check over on-disk content.** Dispatch a `general-purpose` Agent (`model: "opus"`):

```
You are checking whether the current on-disk artifacts comply with the project constitution.

**Input**:
- The current on-disk content of ALL three artifacts: {read spec.md, plan.md, tasks.md from disk now — not from composed in-memory content}
- The full constitution: {constitution content from .specify/memory/constitution.md}
- The original Pass D CRITICAL findings whose fixes were written: {list with IDs and descriptions}

**Check for**:
1. Whether the original CRITICAL constitution violations (Pass D findings) are resolved in the on-disk content.
2. Whether the applied fixes introduced any NEW constitution MUST violations.

**Report**:
- For each original Pass D finding: RESOLVED or STILL_PRESENT.
- Any new violations: principle identifier, title, one-sentence description.
- Final verdict: PASS (all original violations resolved, no new ones) or FAIL (with details).
```

Merge the agent's per-finding verdicts with the pre-check's automatic STILL_PRESENT verdicts. Branch on the combined result:

- If **PASS** (all Pass D CRITICAL findings — including any from the pre-check — resolved, no new violations introduced): write a new pipeline-state record: `speckit run write-pipeline-state.sh analyze status=passed caveat=fixes_applied writer=analyze`. Confirm the write by the same rule as the outcome-reporting step's write-confirmation protocol. If the write or its confirmation fails, do not display the unblocked message — report the failure and leave the gate blocked (the prior blocked record remains authoritative). On success, display: "Analyze gate unblocked — CRITICAL constitution violations resolved by applied fixes." Proceed to the post-completion hook.

- If **FAIL** (any original violation persists — whether caught by the pre-check or the agent — or a new violation was introduced): the gate remains blocked. Report which constitution violations persist or were introduced, and recommend manual resolution or re-running `/speckit-analyze` after manual fixes. Proceed to the post-completion hook.

If the prior outcome was already passed (Rows 3–5):

- No pipeline-state update needed. Report which findings were resolved. Proceed to the post-completion hook.

#### If "Suggest remediation only"

Display concrete remediation suggestions for the top findings. Do NOT apply them. Proceed to the post-completion hook.

#### If "Skip"

Proceed to the post-completion hook.

### 9. Post-completion hook

**Post-completion hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.after_analyze` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`) — if a mandatory hook's invocation fails or terminates abnormally, halt with "`<stage>` completed but the follow-up step failed — re-run `/<command>` to retry" (a hook returning a result, including a blocking one, is a successful dispatch, not a failure); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue.

### 10. Display next-step guidance

**Display next-step guidance (ALWAYS RUN, unless the Next Actions step above already ended the command by way of any of its terminal paths)**: Now that the post-completion hook above has finished executing, display the ➡️ **Successor obligation** line and Next Actions block computed in the "Provide Next Actions" step above. This is the only time it is shown, and it must be the last thing shown to the user this turn.

## Operating Principles

### Context Efficiency

- **Minimal high-signal tokens**: Focus on actionable findings, not exhaustive documentation
- **Progressive disclosure**: Load artifacts incrementally; don't dump all content into analysis
- **Token-efficient output**: Limit findings table to 50 rows; summarize overflow
- **Deterministic results**: Rerunning without changes should produce consistent IDs and counts

### Analysis Guidelines

- **Do not modify files by default** — the two exemptions are this command's own pipeline-state outcome record (every run writes one), and explicit user selection of "Apply all recommended fixes" in the Remediation step
- **NEVER hallucinate missing sections** (if absent, report them accurately)
- **Prioritize constitution violations** (these are always CRITICAL)
- **Use examples over exhaustive rules** (cite specific instances, not generic patterns)
- **Report zero issues gracefully** (emit success report with coverage statistics)

## Context

$ARGUMENTS
