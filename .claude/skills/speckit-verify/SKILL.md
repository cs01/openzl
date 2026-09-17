---
name: speckit-verify
description: 'SpecKit SDD pipeline: multi-agent verification of code against `specs/<feature>/spec.md`.'
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:meta
  meta_preset_strategy: replace
user-invocable: true
disable-model-invocation: false
---



# Speckit Verify Skill

# Multi-Agent Spec Verification

This command checks your implementation against its spec — dispatching parallel agents to verify completeness, correctness, consistency, and test coverage.

## User Input

```text
$ARGUMENTS
```

**Parse `--auto` flag**: Check `$ARGUMENTS` for a standalone leading `--auto` token — do not strip it if it appears embedded within feature-description text; only a leading token counts. If present, set `AUTO_MODE = true`; otherwise `AUTO_MODE = false`. Steps 1-5 (spec resolution, verification, triage, reporting) run identically either way. `AUTO_MODE` is consumed later, at the mode choice gate (Step 6b), where it fast-paths a blocked verification gate straight to auto-resolve dispatch instead of presenting the interactive choice, and at the completion report (Step 7), where it is passed to `render-gate-report.sh --auto-mode`.

## Pre-Execution Checks

**Workspace check (MANDATORY)**: Run `speckit run require-workspace.sh`. This resolves the workspace from any subdirectory and produces the same fixed message when there is no workspace above the current directory. On a non-zero exit, relay its stderr output to the user verbatim — do not paraphrase, reword, summarize, or translate it; do not prepend or append anything (no preface, heading, or attribution such as "require-workspace.sh failed:"); do not name the script, the command, the exit code, or any internal path — then halt. On exit 0, proceed silently to the next check.

**Pre-execution hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.before_verify` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue. Wait for all hooks to complete before continuing.

**Output discipline**: Suppress routine setup narration — step numbers, variable bindings, script names, exit codes, and state transitions. Errors, warnings, interactive prompts, mandatory gate menus, progress milestones (agent completions), and the verification report are not routine narration and must still be shown.

## Step 1: Spec Resolution

Before starting work, briefly tell the user what this stage does and why it matters. Print the introduction in bold.

Determine which spec or constitution to verify and set the verification mode:

1. **Parse arguments**:
   - Check if `--constitution` flag is present in `$ARGUMENTS`
   - Extract the positional path argument (if any) by removing `--constitution` from `$ARGUMENTS`
   - If `--constitution` flag is present:
     - If positional path is provided, use it as the target file path
     - If no positional path is provided, default to `.specify/memory/constitution.md`
   - If `--constitution` flag is absent:
     - If user provided a path argument, use it directly. If the path points to a directory, append `/spec.md`.
     - Otherwise, read `.specify/feature.json` and extract the `feature_directory` value. The spec path is `<feature_directory>/spec.md`.

2. **Auto-detect mode**:
   - If the resolved path ends with `constitution.md` OR is under `.specify/memory/`, set `MODE = constitution`
   - Otherwise, set `MODE = spec`

3. **Read the target file**:
   - Read the resolved file at the target path
   - If it does not exist, report the error with the resolved path and stop: "File not found: `<resolved_path>`. Verify the path is correct."
   - **Placeholder detection**: If `MODE = constitution` and the file contains the sentinel `<!-- speckit:constitution:placeholder -->`, the constitution is unconfigured. Skip constitution verification entirely and log: "Constitution is unconfigured (placeholder detected) — skipping constitution verification. Run `/speckit-constitution` to configure." Proceed to Step 8 (post-completion hook) without dispatching any agents.

4. **Store context**:
   - For `MODE = spec`: store the spec directory as `SPEC_DIR` and the full spec content as `SPEC_CONTENT`
   - For `MODE = constitution`: store the constitution directory as `CONSTITUTION_DIR` (parent directory of the file) and the full content as `CONSTITUTION_CONTENT`
   - **Either mode**: set `FEATURE_DIR = SPEC_DIR` (spec mode) or `FEATURE_DIR = CONSTITUTION_DIR` (constitution mode).

## Step 2: Extract Verification Targets

**If `MODE = spec`:**

**Precondition check (implementation completion) — run this first:**
- Read the most recent `implement` entry from `SPEC_DIR/pipeline-state.jsonl`, if the file exists (`jq -sr '[.[] | select(.stage == "implement")] | last'` — the same pattern `/speckit-implement` itself uses to check the `analyze` gate). If its `status` is `complete`, implementation is confirmed.
- Otherwise, check `tasks.md` in `SPEC_DIR`, if it exists: count lines matching `- [x] T` (checked). At least one checked task confirms `/speckit-implement` has run. Do not require zero unchecked tasks — Implement's own completion validation explicitly allows ending with tasks intentionally left unmarked and reported as outstanding (deferred, blocked, or out of scope), so a spec with a few deliberately-incomplete tasks is still implemented, not unimplemented. Zero checked tasks (or a missing `tasks.md`) means implementation was never started.
- If neither signal confirms implementation: halt and report — "No implementation found for this spec. `/speckit-verify` checks that `/speckit-implement`'s output satisfies `spec.md`; it does not run before implementation exists. Run `/speckit-implement`, then re-run `/speckit-verify`." Do not dispatch any agents.

From the spec, extract: requirements (FR-NNN items), key entities, success criteria, and scope boundaries (from Assumptions). Determine `CODE_FILES` from the first of these that yields any files:
1. **Generation Notes > Source Files** in spec.md, if present (brownfield specs only).
2. **`tasks.md`'s per-task file paths**, if `tasks.md` exists: union the `**File**:`/`**Files**:` field (or, for tasks with no dedicated field, the file path embedded in the task's description line) across every task. `/speckit-implement` already treats these fields as authoritative for parallel-dispatch conflict detection — they're a direct record of what implementation touched, not a guess.
3. `search_files` MCP tool, querying by feature name and key entities — only if neither of the above yields any files.

Store the result as `CODE_FILES`. This is a best-effort reading assignment for Agents 1 and 2, not a completion check — the precondition above already confirmed implementation exists, so an incomplete or empty `CODE_FILES` does not block verification. It only means Agents 1 and 2 must rely more on their own in-prompt `search_files` calls.

**Spec origin detection:**
- If the spec contains a `## Generation Notes` section, set `SPEC_ORIGIN = brownfield` (the spec was reverse-engineered from existing code by `/speckit-generate`)
- Otherwise set `SPEC_ORIGIN = greenfield` (the spec was authored before the code by `/speckit-specify`)
- Store for use in the Agent 2 prompt (Step 3-spec)

**Complexity detection:** Parse the `complexity` field from YAML frontmatter (`compact`, or any other value). If the `complexity` field is absent or has an unrecognized value, treat the spec as standard — no compact-specific behavior adjustments apply below.

If the spec has `complexity: compact` in its YAML frontmatter:
- If the Success Criteria section is absent from the spec, skip its extraction above and note "Compact spec — Success Criteria absent, verifying against FRs directly."
- If the Success Criteria section is present, extract and verify against it normally, noting "Compact spec — Success Criteria retained, verifying against FRs and Success Criteria."
- Apply the same section-presence logic to Key Entities: if absent, skip its extraction above and note it; if present, extract and verify against it normally.

**If `MODE = constitution`:**
Skip this step. Constitution verification does not require code file extraction.

## Step 3: Dispatch Verification Subagents

**If `MODE = constitution`**, proceed with Step 3-constitution (single validation agent).

**If `MODE = spec`**: dispatch all 4 agents in parallel (the Step 2 precondition check already guarantees implementation exists).

### Step 3-constitution: Constitution Validation

When verifying a constitution file, dispatch a single Constitution Validator agent using the Agent tool.

**Prompt to subagent:**

> You are verifying the consistency and quality of a project constitution. A constitution defines non-negotiable principles and conventions that govern spec writing, planning, and implementation.
>
> **Constitution content:**
> [Insert CONSTITUTION_CONTENT]
>
> **Your task:**
> 1. **Principle clarity** — Check that every MUST/SHOULD principle is unambiguous and testable. Flag any weasel words ("consider", "try to", "generally"), vague constraints, or principles that can't be mechanically checked. Severity: must-address for weasel words in MUST statements, should-consider for vague wording in SHOULD statements.
>
> 2. **Compliance validation** — Check if `.specify/` artifacts exist (specs, plans, tasks). For each that exists, verify it respects constitution principles. Example: if constitution mandates "all specs must have a Test Plan section", check that specs have it. Severity: must-address for violations of MUST principles, should-consider for violations of SHOULD principles.
>
> 3. **Version consistency** — Check that the constitution version (YAML frontmatter or inline) increments correctly according to its own versioning policy. If recent changes are substantive (new principles, removed principles), version should reflect it. Severity: minor for version staleness, must-address for missing version field.
>
> 4. **Coverage** — Check whether critical project conventions are captured. Read `CLAUDE.md` from the project root. If CLAUDE.md defines conventions (naming, testing, code style) that aren't reflected in the constitution, flag the gap. Severity: should-consider for missing conventions that affect spec/plan quality.
>
> Use the `search_files` MCP tool for scanning `.specify/` artifacts — never use `grep`, `find`, or `rg`.
>
> **Return format — one entry per finding:**
> ```
> - severity: must-address | should-consider | minor
>   category: principle_clarity | compliance_validation | version_consistency | coverage
>   violated_principle: "[the exact principle identifier and title this finding concerns,
>                          e.g. 'VI — Context-Window-Efficient Presets' — include whenever the
>                          finding is about a specific principle (this is virtually always true
>                          for compliance_validation and principle_clarity findings); omit only
>                          when the finding is not tied to any single principle]"
>   finding: "[description of the issue]"
>   suggestion: "[specific fix — reword principle X, add coverage check, increment version, etc.]"
> ```
>
> If no issues are found in a category, do not include it in the output. Only report problems.

After the subagent completes, parse findings and proceed to Step 4.

### Step 3-spec: Spec Verification (4 parallel agents)

**For spec mode:** Dispatch all 4 subagents **in parallel** using the Agent tool. Each subagent operates independently on a single dimension.

**Prepare agent prompts**: Read `.specify/templates/verify-doctrine.md` once. This file contains the shared LAYER ALLOCATION, REWRITE TEST, SPEC-WORTHINESS TEST, and ROUTING sections that MUST be appended verbatim to each of the 4 agent prompts below. If the file is missing, log a warning ("verify-doctrine.md not found — findings will not be routed; expect implementation-detail noise") and dispatch without it.

**Rules for all subagents:** use `search_files` MCP tool for code search (never `grep`/`find`/`rg`). Return findings as structured lists with severity tags (`must-address`, `should-consider`, `minor`) and a `route` field per the doctrine. Each finding must include the specific claim checked, what was found, and an actionable fix. If context overflows, return partial findings with a truncation note.

### Agent 1: Alignment (spec-to-code)

**Direction:** Spec claims → code confirmation

**Prompt to subagent:**

> You are verifying that a specification accurately describes the codebase. Read the spec below, then search the codebase to confirm each claim.
>
> **Spec content:**
> [Insert SPEC_CONTENT]
>
> The spec may contain a `## Summary` section. This is orientation context — do not use it as the source of truth for findings. Base your analysis on the detailed requirements.
>
> **Source files to start from:**
> [Insert CODE_FILES]
>
> **Your task:**
> 1. For each functional requirement (FR-NNN), search the codebase for the implementing code. Confirm the code does what the spec claims.
>    **Compound-FR decomposition (apply before verifying each FR):**
>    - **Detect**: Apply the single-obligation test: could one half of this requirement pass verification while the other half fails? If yes, the FR is compound.
>    - **Decompose**: Split the compound FR into independent sub-obligations labeled FR-NNNa, FR-NNNb, etc.
>    - **Verify separately**: Search the codebase for evidence of each sub-obligation independently — do not let evidence for one sub-obligation satisfy the other.
>    - **Annotate provenance**: Tag the result: `"FR-NNN was compound — verified as FR-NNNa [status] / FR-NNNb [status]; consider splitting in spec.md"`.
>    - **Report independently**: Report each sub-obligation's pass/fail status separately in the findings below — a passing sub-obligation MUST NOT mask a failing one.
> 2. For each key entity, verify the data model matches the spec's description (attributes, relationships, constraints).
> 3. For each success criterion, check whether the code achieves or enforces it.
>
> If the spec has `complexity: compact` in its YAML frontmatter:
> - If the spec has no Success Criteria section, skip "For each success criterion, check..." — compact specs may legitimately omit Success Criteria.
> - If the spec has no Key Entities section, skip "For each key entity, verify..." — compact specs may legitimately omit Key Entities.
> - If either section IS present, verify against it normally.
> - Use the Verification Notes section as per-FR verification guidance if present.
>
> 4. Classify every discrepancy into exactly one of two kinds — do not merge them:
>    - **SPEC-DEFECT** (`route: spec.md`) — the spec states something factually wrong about the intended behavior: wrong name, wrong value, wrong direction, wrong condition, an inverted trigger, a contradicted constraint. The spec text is the thing to change. Quote it.
>    - **IMPLEMENTATION-GAP** (`route: code`) — the spec correctly states a required, user-observable behavior and the code does not deliver it. The code is the thing to change. Never resolve this by softening or deleting the requirement.
>
>    If a requirement is met in substance but by different internals than you expected, that is not a finding. The spec does not owe the code a description of its mechanics.
>
>    **Severity rule:** IMPLEMENTATION-GAP is always `must-address` — the spec requires a behavior the code does not deliver. SPEC-DEFECT defaults to `should-consider` unless the wrong claim would mislead someone building or testing against the spec, in which case `must-address`.
>
> 5. **Implementation depth for qualitative FRs (MANDATORY — do not skip).** When an FR requires improving the quality of human-readable output — stage explainers, user-facing prompts, error messages — apply the **removal test** to every qualitative FR independently:
>    - Identify the specific text added to implement the FR.
>    - Determine whether that text is in an **output instruction** (a step that tells the agent what to display/print/report to the user) or in **context** (a description, goal, heading, comment, or annotation the agent reads as background).
>    - If the text is in context only: removing it would not change any step's output instructions, so the user sees no difference. This is form-over-substance. Flag as IMPLEMENTATION-GAP.
>
>    **Concrete examples of this anti-pattern:**
>    - *Stage explainer*: A spec requires "every stage MUST open with a natural-language explainer." The implementation adds `"This command checks your spec for consistency"` to the preset's description/goal section. That sentence is context the agent reads — not a step instruction telling the agent to display an explainer. A passing implementation adds a step: `"Before beginning, display to the user: [explainer covering purpose and value]."`
>    - *Subagent dispatch*: A spec requires "subagents MUST report ambiguity rather than prompting the user." The implementation adds a comment or section heading noting that subagents must not prompt. No subagent dispatch instruction was changed. A passing implementation adds to the subagent prompt: `"If you encounter ambiguity, do not ask the user — report the ambiguity and your assumptions in your output."`
>    - *Convergence checkpoint*: A spec requires "convergence checkpoints MUST disclose explored/remaining areas." The implementation adds a convergence-management paragraph saying "recommend proceeding after 8-10 questions." No explored/remaining tally is rendered. A passing implementation adds to the checkpoint step: `"Display: 'Explored ~N of ~M areas. Remaining: [list]. Proceed or explore further?'"`
>
>    In each case: the text exists in the file, but removing it would not change the agent's behavioral instructions or the user's experience. The output paths are unchanged.
>
> Use the `search_files` MCP tool for all code search — never use `grep`, `find`, or `rg`.
>
> **Return format — one entry per finding:**
> ```
> - severity: must-address | should-consider | minor
>   route: spec.md | code | discovery | none
>   kind: SPEC-DEFECT | IMPLEMENTATION-GAP
>   net_lines: [lines the artifact gains or loses if applied — 0 for a swap]
>   spec_claim: "[exact quoted text or FR-NNN reference from spec]"
>   finding: "[what the code actually does or doesn't do]"
>   suggestion: "[for SPEC-DEFECT: the corrected spec sentence, written at WHAT level,
>                 as a full replacement for the quoted text.
>                 for IMPLEMENTATION-GAP: the behavior the code must add.]"
> ```
>
> If you find no issues for a requirement, do not include it in the output. Only report discrepancies.
>
> {Append full content from `.specify/templates/verify-doctrine.md` here}

### Agent 2: Coverage (code-to-spec)

**Direction:** Code behaviors → spec completeness

**Prompt to subagent:**

> You are checking whether a specification fully covers the codebase it describes. Read the code first, then check whether the spec captures all significant behaviors.
>
> **Source files to read:**
> [Insert CODE_FILES]
>
> **Spec content:**
> [Insert SPEC_CONTENT]
>
> The spec may contain a `## Summary` section. This is orientation context — do not use it as the source of truth for findings. Base your analysis on the detailed requirements.
>
> **Spec origin:** [Insert SPEC_ORIGIN]
>
> **Your task:**
> 1. If no source files were listed above, use `search_files` with the spec's requirements and key entities to locate the implementation yourself before proceeding — an empty list means the discovery heuristic missed it, not that nothing was implemented. Then read each source file. Identify significant behaviors: validation rules, error handling, branching logic, integration points, configuration-driven behavior.
> 2. For each behavior found in code, apply the **spec-worthiness test** (tests (a)–(e) in the Verification Doctrine below) before considering it a gap. A behavior that passes none of the tests is `route: discovery` — record it so the knowledge is not lost, but do not propose a spec change for it.
> 3. Before proposing ANY new requirement, apply the rewrite test from the Verification Doctrine below. If the requirement text you drafted would have to change when someone refactors the internals without changing behavior, it is HOW — downgrade it to `route: discovery`.
> 4. New requirements are the exception, not the default output of this agent. A well-written lean spec that omits internal mechanics is CORRECT, not incomplete. Silence about internals is a feature.
> 5. **Spec origin weighting**: if `SPEC_ORIGIN = brownfield`, the spec exists to describe already-shipped behavior — apply tests (a) and (b) generously, since documenting observable behavior is that spec's purpose. The rewrite test still applies without exception: reverse-engineered specs describe behavior, never mechanics. If `SPEC_ORIGIN = greenfield`, apply all tests strictly.
> 6. **Producer/consumer contract check.** For any behavior from step 1 that writes a shared format, schema, or artifact — a file section, a config field, an event payload, a structured log line — search for every other file in the codebase that reads or parses that same artifact, and verify its parsing or validation assumptions still hold against the current format. A break here is `route: code`, `severity: must-address` — never a spec gap, since the spec's WHAT-level claim can be fully satisfied while two pieces of code still disagree with each other. Name both sides (the producer's actual format and the consumer's actual assumption) in the finding.
> 7. **Compact specs.** If the spec has `complexity: compact` in its YAML frontmatter, do not flag the absence of Success Criteria or Key Entities sections as coverage gaps — these are legitimately omitted in compact specs when Success Criteria are omitted because all requirements are directly testable, and Key Entities are omitted because the feature has no data model. If either section IS present, verify coverage normally. Accept the Verification Notes section as an alternative source of verification criteria.
>
> Use the `search_files` MCP tool for all code search — never use `grep`, `find`, or `rg`.
>
> **Return format — one entry per finding:**
> ```
> - severity: must-address | should-consider | minor
>   route: spec.md | code | discovery | none
>   net_lines: [lines the artifact gains or loses if applied — 0 for a swap]
>   code_location: "[file:line or file + function/method name]"
>   behavior: "[description of what the code does]"
>   worthiness: "[which test (a)-(e) it passes, or 'none — internal mechanics']"
>   materiality: "[what a reader would build, test, or decide differently once applied]"
>   amends: "[the existing requirement this corrects, or the requirements you checked
>             before concluding a new one is needed]"
>   suggestion: "[for route: spec.md — the exact WHAT-level sentence to add or amend,
>                 containing no identifier names.
>                 for route: discovery — a one-line note for the record.]"
> ```
>
> If the spec has complete coverage of a file, do not include it in the output. Only report gaps.
>
> {Append full content from `.specify/templates/verify-doctrine.md` here}

### Agent 3: Freshness (temporal)

**Direction:** Recent changes → spec staleness

**Prompt to subagent:**

> You are checking whether recent code changes have made a specification stale. Compare recent modifications to the code against what the spec claims.
>
> **Source files:**
> [Insert CODE_FILES]
>
> **Spec content:**
> [Insert SPEC_CONTENT]
>
> The spec may contain a `## Summary` section. This is orientation context — do not use it as the source of truth for findings. Base your analysis on the detailed requirements.
>
> **Your task:**
> 1. If no source files were listed above, use `search_files` with the spec's requirements and key entities to locate the implementation yourself before proceeding — an empty list means the discovery heuristic missed it, not that nothing was implemented. Then, for each source file, run `sl log <file> -T "{node|short} {date|isodate} {desc|firstline}\n" -l 10` to get recent changes.
> 2. For files modified recently (within the last 30 days), read the current version and identify what changed.
> 3. Cross-reference recent changes against spec claims to determine semantic consistency:
>    - **CONTRADICTS**: Recent change removes, alters, or contradicts functionality the spec describes → Flag as staleness (must-address or should-consider)
>    - **IMPLEMENTS**: Recent change adds functionality the spec requires → Do NOT flag (this is post-implementation verification or backlog implementation, not staleness)
>    - **REFACTOR**: Recent change alters internals without changing observable behavior the spec describes → `route: discovery`, severity `minor`. Do NOT update the spec. Specs do not track refactors.
>    - **UNRELATED**: Recent change touches code outside spec scope → Ignore
>
> **Critical**: Do NOT use temporal ordering (spec created date vs. change date) to determine staleness. Specs may sit in a backlog for days/weeks/months before implementation. Only semantic contradictions indicate staleness.
>
> Use the `search_files` MCP tool for code search and `sl log` for history — never use `grep`, `find`, or `rg`.
>
> **Return format — one entry per finding:**
> ```
> - severity: must-address | should-consider | minor
>   route: spec.md | code | discovery | none
>   net_lines: [lines the artifact gains or loses if applied — 0 for a swap]
>   spec_claim: "[text or FR-NNN that may be stale]"
>   change: "[commit hash, date, description of what changed]"
>   suggestion: "[the corrected WHAT-level spec sentence — describe the new behavior,
>                 not the new implementation]"
> ```
>
> If no recent changes contradict the spec, return an empty findings list with a note that the spec appears fresh (or if recent changes implement the spec, note "Recent changes implement spec requirements — no staleness detected").
>
> {Append full content from `.specify/templates/verify-doctrine.md` here}

### Agent 4: Cross-Artifact (lateral)

**Direction:** Consistency across spec ecosystem artifacts

**Prompt to subagent:**

> You are checking consistency across the spec ecosystem artifacts for a feature. These artifacts must not contradict each other.
>
> **Spec directory:**
> [Insert SPEC_DIR]
>
> **Your task:**
> 1. Read `spec.md` in the spec directory.
> 2. Read `plan.md` in the spec directory, if it exists.
> 3. Read `tasks.md` in the spec directory, if it exists.
> 4. Read `.specify/memory/constitution.md` from the project root, if it exists.
> 5. Read `CLAUDE.md` from the project root for project conventions.
>
> Do not read source code files or compare any artifact against the current implementation — you were not given a code file list, and none of the checks below are code comparisons. Implementation-vs-spec checking belongs to the Alignment and Coverage agents.
>
> `/speckit-verify` only ever runs after `/speckit-implement` has executed every task in `tasks.md`. `plan.md` and `tasks.md` are therefore never edit targets for this agent — correcting them now would not change anything that already shipped. Never emit `route: plan.md` or `route: tasks.md`.
>
> For each pair of artifacts that exist, check:
> - **spec.md vs plan.md** — does the plan implement all spec requirements? Does the plan reference requirements that don't exist in the spec? A contradiction here is `route: spec.md` if `spec.md` is what's wrong; otherwise `route: none` — informational only.
> - **spec.md vs tasks.md** — are all spec requirements covered by at least one task? For orphaned tasks with no spec backing: an orphan task is `route: none` (unplanned scope, informational only), NOT grounds for adding a requirement to spec.md. Only propose a new requirement if the orphan task delivers behavior that passes the spec-worthiness test in the Verification Doctrine below — and say which test it passes.
> - **plan.md vs tasks.md** — do tasks align with the plan's proposed approach? Are there contradictions in ordering or dependencies? Always `route: none` — both describe work that is already done.
> - **spec.md vs constitution.md** — does the spec respect project principles? Are there violations of stated constraints?
> - **spec.md vs CLAUDE.md** — does the spec follow project conventions (naming, patterns, anti-patterns)?
> - **CLAUDE.md vs constitution.md** — does `CLAUDE.md`'s current content violate any constitution principle that governs documentation (for example, a principle restricting what `CLAUDE.md` should contain — mechanism walkthroughs, internal requirement/task-ID citations, or a file index standing in for real search)? This is `route: none` — informational only. `CLAUDE.md` is not an artifact this agent may target for a fix (it never reads or compares against the current implementation), but the drift must still surface in the report for a human to resolve manually.
>
> If the spec has `complexity: compact` in its YAML frontmatter, do not flag absent Success Criteria or Key Entities as cross-artifact inconsistencies — these sections are legitimately omitted in compact specs.
>
> **Return format — one entry per finding:**
> ```
> - severity: must-address | should-consider | minor
>   route: spec.md | discovery | none
>   net_lines: [lines the artifact gains or loses if applied — 0 for a swap]
>   artifacts: "[artifact A] vs [artifact B]"
>   contradiction: "[what conflicts or is missing]"
>   suggestion: "[update artifact X to align with Y, add missing reference, etc.]"
> ```
>
> If only `spec.md` exists (no plan, tasks, or constitution), note that cross-artifact verification is limited and report only CLAUDE.md consistency findings.
>
> {Append full content from `.specify/templates/verify-doctrine.md` here}

## Step 4: Collect and Triage Results

**If `MODE = spec`:** As each of the 4 subagents completes, emit a progress update: "Verification: {Agent name} complete ({N} findings)." Wait for all 4 to complete. For each subagent:

1. **If it succeeded** — parse its findings list.
2. **If it failed** (timeout, context overflow, error) — record the failure. Do not crash. Continue with results from the other agents.

**If `MODE = constitution`:** Wait for the single Constitution Validator agent to complete. Parse its findings list. If it failed, record the failure.

Merge all findings and sort by severity:

| Severity | Meaning | Examples |
|----------|---------|----------|
| **must-address** | Spec-code contradiction, missing implementation, stale claim, cross-artifact conflict | Spec says X, code does Y. Spec requires Z but no implementation found. Recent commit changed behavior spec still claims. |
| **should-consider** | Ambiguous wording, partial coverage of a stated guarantee, unhandled edge case in a required behavior | Spec wording could mean two things. Spec states a universal that the code exempts some cases from. |
| **minor** | Style, formatting, minor omissions, and ALL `route: discovery` findings | Inconsistent naming between spec and code. Internal mechanics the spec correctly omits. |

**Partition by route.** Split merged findings into two groups:

- **Actionable** — findings routed to `spec.md` or `code`. These gate the verification status.
- **Discovery** — findings routed to `discovery` or `none`. These are recorded in the report but do NOT gate status and are never reported as must-address, regardless of the severity the agent assigned.

If an agent returned a finding without a `route` field, infer it: a finding that quotes wrong spec text is `spec.md`; a finding that only observes undocumented internals is `discovery`.

**Spec impact.** Sum `net_lines` across all `route: spec.md` findings — this is how much `spec.md` grows if every suggestion is applied. Report it in the Summary. If the total is positive and larger than the number of spec.md findings, at least one suggestion is adding prose rather than swapping it: re-read those suggestions and drop any that fail the materiality test in the doctrine before writing the report.

**Assign finding IDs.** Assign unique `V-NNN` IDs (`V-001`, `V-002`, ...) sequentially, in severity order, across every actionable finding. This applies to both `MODE = spec` (findings merged from all 4 agents) and `MODE = constitution` (findings from the single Constitution Validator agent) — every finding written to the report in Step 5 gets a `V-NNN` ID.

**Cross-reference findings (best-effort).** Group findings that describe the same underlying issue:
- **Primary heuristic**: findings whose `spec_claim` (or equivalent quoted-text field) references the same `FR-NNN`.
- **Secondary heuristic**: findings that target the same file or `code_location`.
- **Fallback**: if neither heuristic produces a match, fall back to textual similarity of the `spec_claim` field — this is agent judgment, not an exact algorithm.

For any group of 2 or more related findings, annotate each member with `**Related**: V-NNN[, V-NNN...]`, listing the *other* members of the group (never the finding's own ID). Cross-referencing MUST NOT collapse or merge findings — every finding in a group keeps its own `V-NNN` ID and remains a distinct, separately-actionable entry in the report.

**Partition into severity tiers.** Split findings into four tiers:
- **MUST-ADDRESS** — actionable findings, severity `must-address`
- **SHOULD-CONSIDER** — actionable findings, severity `should-consider`
- **MINOR** — actionable findings, severity `minor`
- **DISCOVERY** — the Discovery group from "Partition by route" above, regardless of the severity the originating agent assigned

Record `MUST_ADDRESS_COUNT`, `SHOULD_CONSIDER_COUNT`, `MINOR_COUNT`, and `DISCOVERY_COUNT` — the size of each tier. `MUST_ADDRESS_COUNT` is what gates the verification status (Step 5) and the verify gate (Step 6a). Also record `AGENTS_COMPLETED` — the count of agents that succeeded (out of 4 in spec mode, 1 in constitution mode), for use in the gate write (Step 6a) and dispatch (Step 6c) — and `AGENTS_FAILED` — the list of agent names that failed, for use in the Summary and frontmatter (Step 5).

Set `QUORUM_MET = true`, except in the all-agents-failed branch of Graceful Failure Handling below (zero findings could be parsed for this run) — there, set `QUORUM_MET = false`. This mirrors `render-gate-report.sh`'s semantics: `false` means no verdict was produced this run, not merely that the verdict was clean.

## Step 5: Write Verification Report

**This command is read-only with respect to `spec.md`.** You MUST NOT edit `spec.md` at any point during this run — not to fix a finding, not to reconcile wording, not to make the spec agree with the code. Verify reports; the human (or an explicit later step) applies the fix and commits it with an accurate message. Editing the spec and then reporting that spec and code agree makes a PASS indistinguishable from a completed reconciliation, and the report becomes unfalsifiable.

The same prohibition covers `## Clarifications` with special force: it is a transcript of answers a human gave, not spec prose. If the code contradicts a clarification answer, that is `route: code`, or a question for the human — never a rewrite of what they said.

Write the sections you would have edited as findings instead. A finding is the deliverable; an edit is not.

**Finding format (both modes).** Each actionable finding (MUST-ADDRESS/SHOULD-CONSIDER/MINOR) is an H4 heading `#### V-NNN: {short title}` followed by:
- `**Severity**: {must-address|should-consider|minor} · **Route**: {route} · **Kind**: {kind} · **Agent**: {agent name}`
- description bullets (agent-specific fields — see mapping below)
- `> **Evidence**: {quoted claim, code location, change description, or artifact pair, as applicable to the agent — include net_lines here for spec.md-routed findings}`
- `**Suggestion**: {suggestion}`
- `**Related**: V-NNN[, V-NNN...]` — only when Step 4's cross-reference heuristic found a match
- `- [ ] Resolved` — this exact unchecked-checkbox marker (checked form: `- [x] Resolved`). `record-gate-override.sh --stage verify` and the interactive resolution skill parse this literal marker; do not substitute emoji checkboxes or any other syntax.

DISCOVERY findings carry no checkbox and no resolution tracking — they are one bullet each: `` `file` — [behavior] ``, grouped by source file.

**`kind` field mapping:**

| Source | `kind` value | `route` |
|--------|-------------|---------|
| Agent 1 (Alignment) | its native `SPEC-DEFECT` or `IMPLEMENTATION-GAP` value | as returned |
| Agent 2 (Coverage) | `coverage-gap` | as returned |
| Agent 3 (Freshness) | `freshness` | as returned |
| Agent 4 (Cross-Artifact) | `cross-artifact` | as returned |
| Constitution Validator | its native `category` value (`principle_clarity`, `compliance_validation`, `version_consistency`, `coverage`) | `constitution.md` for every finding — constitution mode has no code-routed findings |

**Description bullets by agent:**
- Alignment: `**Spec claim**: {spec_claim}` and `**Finding**: {finding}`
- Coverage: `**Code location**: {code_location}` (project-relative path, not absolute), `**Behavior**: {behavior}`, `**Worthiness**: {worthiness}`, `**Materiality**: {materiality}`, `**Amends**: {amends}`
- Freshness: `**Spec claim**: {spec_claim}` and `**Change**: {change}`
- Cross-Artifact: `**Artifacts**: {artifacts}` and `**Contradiction**: {contradiction}`
- Constitution Validator: `**Violated Principle**: {violated_principle}` (first bullet, immediately after the Severity/Route/Kind/Agent line — omit this bullet entirely when the finding carried no `violated_principle`) and `**Finding**: {finding}`

**If `MODE = spec`:**

Write `verification.md` in `SPEC_DIR` with YAML frontmatter (`spec`, `verified`, `status`, `agents_completed`, `agents_failed`) followed by these sections in order:

1. `### Summary` — overall status (pass/fail/partial), actionable finding counts by severity (`MUST_ADDRESS_COUNT`/`SHOULD_CONSIDER_COUNT`/`MINOR_COUNT`), `DISCOVERY_COUNT` reported separately, spec impact (net lines `spec.md` gains if all suggestions are applied), which agents completed vs. failed, and the line **`spec.md`: not modified during this run** — state it explicitly, as evidence the verdict was reached by inspection rather than by editing. If `spec.md` *was* modified, say so and name every change: a PASS alongside unreported spec edits is a false negative, not a clean run.
2. `### MUST-ADDRESS ({MUST_ADDRESS_COUNT})` — findings per the format above, or "No MUST-ADDRESS findings."
3. `### SHOULD-CONSIDER ({SHOULD_CONSIDER_COUNT})` — or "No SHOULD-CONSIDER findings."
4. `### MINOR ({MINOR_COUNT})` — or "No MINOR findings."
5. `### DISCOVERY ({DISCOVERY_COUNT})` — **Implementation Discovery (non-spec)**: all `route: discovery` findings from any agent, grouped by source file, or "No implementation discovery notes." These are internal mechanics learned during verification, recorded so the knowledge is not lost. They are NOT spec defects and require no action.

**Status determination** (computed from actionable findings only — discovery findings never affect status):
- **pass** — zero actionable must-address findings and all 4 agents completed
- **fail** — one or more actionable must-address findings
- **partial** — any agent failed to complete (regardless of finding severity)

**If `MODE = constitution`:**

Write `constitution-verification.md` in `CONSTITUTION_DIR` with YAML frontmatter (`constitution`, `verified`, `status`, `agents_completed`, `agents_failed`) followed by the same section structure as spec mode: `### Summary`, `### MUST-ADDRESS ({count})`, `### SHOULD-CONSIDER ({count})`, `### MINOR ({count})`, `### DISCOVERY ({count})` (typically "No implementation discovery notes." — the Constitution Validator does not emit `route: discovery` findings). Apply the `kind`/`route` mapping above: every constitution finding routes to `constitution.md`.

**Handoff contract for interactive resolution**: the interactive resolution skill (`/speckit-verify-interactive`, created separately) treats every constitution finding as spec-artifact-routed — the same `route: spec.md`-style edit path it uses for spec-mode findings — but targets the constitution file specifically instead of `spec.md`. This section documents that handoff; it does not implement the interactive skill.

**Status determination:**
- **pass** — zero must-address findings and agent completed
- **fail** — one or more must-address findings
- **partial** — agent failed to complete (regardless of finding severity)

## Step 6: Verification Gate

### 6a. Write Gate File and Pipeline State

Determine `$STATUS` from Step 5's status determination:
- `STATUS = "passed"` when Step 5's status determination is `pass`.
- `STATUS = "passed"` when Step 5's status determination is `partial` **and** `MUST_ADDRESS_COUNT == 0` — a partial run with no must-address findings passes automatically. Note in the completion report (Step 7) that coverage is incomplete due to agent failures, naming which agents failed. Add `--partial` to the write call below, same as the blocked case — the gate's `partial` field must record the incomplete agent run regardless of the resulting status.
- `STATUS = "blocked"` when Step 5's status determination is `fail` **or** (`partial` **and** `MUST_ADDRESS_COUNT > 0`). A `partial` status with `MUST_ADDRESS_COUNT > 0` is still a blocked gate — an agent failing to complete does not excuse unresolved must-address findings. When `STATUS` is derived from a `partial` determination, add `--partial` to the write call below.

Write the verify gate (`verify-gate.json`) and pipeline state using the unified helper.

**MODE = spec**: `FEATURE_DIR` may be a non-active target (an explicit path argument resolved in Step 1, different from what `.specify/feature.json` points at). Export `SPECIFY_FEATURE_DIRECTORY="$FEATURE_DIR"` on this call and the other two gate-script calls below (Step 6b, Step 7) so they resolve to the directory Step 1 actually resolved, instead of independently re-resolving via `feature.json`/branch-prefix — which could silently pick the active feature instead. **MODE = constitution** keeps its existing behavior (leave the env var unset) — that path is a separate, already-scoped exception (see spec.md's Assumptions on constitution-mode verify).

```bash
SPECIFY_FEATURE_DIRECTORY="$([ "$MODE" = "spec" ] && echo "$FEATURE_DIR")" \
speckit run write-review-gate-unified.sh \
  --stage verify \
  --gate-type "verify" \
  --status "$STATUS" \
  --must-address "$MUST_ADDRESS_COUNT" \
  --should-consider "$SHOULD_CONSIDER_COUNT" \
  --minor "$MINOR_COUNT" \
  --agents-completed "$AGENTS_COMPLETED"
```

**If this call (or the override rewrite in 6b's override sequence, below) exits 4** (the `implement` prerequisite is unmet): Read and execute `.specify/templates/prerequisite-refusal-gate.md` instead of proceeding — this is a prerequisite-chain refusal, not a verification-findings gate, so it is distinct from the MUST-ADDRESS mode choice below.

### 6b. Mode Choice Gate

If `STATUS = "passed"`: skip step 6b and step 6c — proceed directly to Step 7.

If `STATUS = "blocked"`:

**MANDATORY GATE — DO NOT SKIP.** You MUST present the four options below and wait for the user's choice before dispatching to auto-resolve, interactive resolution, or the override path. Jumping directly to any of them without presenting this choice is a protocol violation — even if you believe you know which option the user would prefer. A `partial` status (Step 6a) with `MUST_ADDRESS_COUNT > 0` still presents this gate — an incomplete agent run is not a free pass.

- Display finding counts by severity: `MUST_ADDRESS_COUNT` MUST-ADDRESS, `SHOULD_CONSIDER_COUNT` SHOULD-CONSIDER, `MINOR_COUNT` MINOR. Mention `DISCOVERY_COUNT` separately as non-blocking.
- Present four options:
  1. **Fix now (Interactive)** — Review and resolve findings round by round, grouped by severity tier.
  2. **Fix now (Auto-resolve)** — Fix all findings automatically with recommended actions.
  3. **Override** — Proceed despite findings. Unresolved verification findings may leave spec-code mismatches unaddressed.
  4. **Defer** — Leave the gate blocked and exit. To unblock, resolve the findings and re-run `/speckit-verify` (or `/speckit-verify --constitution` in constitution mode).

**Fast-path conditions** (the ONLY case where the mode choice above may be skipped):
- If `AUTO_MODE = true` (parsed at the top of this command) → skip presenting the choice (skip step 6b's prompt) and dispatch directly to auto-resolve in step 6c.

Wait for user choice, then:
- "Fix now (Interactive)" or equivalent → continue with step 6c, dispatch to `/speckit-verify-interactive`
- "Fix now (Auto-resolve)" or equivalent → continue with step 6c, dispatch to `/speckit-verify-auto`
- "Override" or equivalent → run the override sequence below, then proceed to Step 7
- "Defer" → exit cleanly with guidance to resolve findings and re-run `/speckit-verify` (or `/speckit-verify --constitution`); skip step 6c's dispatch, but DO proceed to Step 7 and Step 8 (see the CRITICAL note at the end of Step 7)

**Override sequence.** Run the record script **first**, and rewrite the gate only if it succeeds. An orphaned override record is inert; an orphaned passing gate is not. Same `SPECIFY_FEATURE_DIRECTORY` pattern as Step 6a on both calls below.

```bash
SPECIFY_FEATURE_DIRECTORY="$([ "$MODE" = "spec" ] && echo "$FEATURE_DIR")" \
speckit run record-gate-override.sh \
  --stage verify \
  --quorum-met true
```

- On exit 0: emit the script's confirmation line, then rewrite the gate to passed:
  ```bash
  SPECIFY_FEATURE_DIRECTORY="$([ "$MODE" = "spec" ] && echo "$FEATURE_DIR")" \
  speckit run write-review-gate-unified.sh \
    --stage verify \
    --gate-type "verify" \
    --status passed \
    --must-address 0 \
    --should-consider "$SHOULD_CONSIDER_COUNT" \
    --minor "$MINOR_COUNT" \
    --agents-completed "$AGENTS_COMPLETED" \
    --override
  ```
  Then display "Gate overridden: BLOCKED → PASSED" and recommend the next step per Step 7's guidance.
- On exit 3: report "override refused — gate unchanged" and do **not** rewrite the gate.

### 6c. Dispatch to Delegated Skills

Dispatch only when the user chose Interactive or Auto-resolve in step 6b, or when the `AUTO_MODE` fast path fired.

Interactive:
```
Skill("speckit-verify-interactive", """
FEATURE_DIR={FEATURE_DIR}
SPEC_DIR={SPEC_DIR or CONSTITUTION_DIR, whichever is defined}
MODE={spec|constitution}
AGENTS_COMPLETED={N}
MUST_ADDRESS_COUNT={N}
SHOULD_CONSIDER_COUNT={N}
MINOR_COUNT={N}
DISCOVERY_COUNT={N}

Interactive resolution: present findings grouped into per-tier rounds (MUST-ADDRESS first, then SHOULD-CONSIDER, then MINOR), each round opening with a table of its findings, collect user decisions, then batch-apply edits by route.
""")
```

Auto-resolve:
```
Skill("speckit-verify-auto", """
FEATURE_DIR={FEATURE_DIR}
SPEC_DIR={SPEC_DIR or CONSTITUTION_DIR, whichever is defined}
MODE={spec|constitution}
AGENTS_COMPLETED={N}
MUST_ADDRESS_COUNT={N}
SHOULD_CONSIDER_COUNT={N}
MINOR_COUNT={N}
DISCOVERY_COUNT={N}

Auto-resolve all MUST-ADDRESS findings by applying each finding's suggestion to the artifact its `route` names. After MUST-ADDRESS findings are resolved, attempt best-effort fixes for SHOULD-CONSIDER and MINOR findings (no rollback on failure). Do NOT act on DISCOVERY findings — they require no action.
""")
```

After dispatch returns, proceed to Step 7.

## Step 7: Report to Caller

> **Context tip:** Verification results are saved to specs/<feature>/. Consider /clear before your next task.

Report to the user (or calling command):

**Artifact summary:**

| Artifact | Path |
|----------|------|
| Verification report | `specs/<feature>/verification.md` |

- **Gate status** — passed or blocked (Step 6a's `$STATUS`)
- **Status** — pass, fail, or partial
- **Finding counts** — actionable findings split as `N spec-defects / M implementation-gaps / K cross-artifact`, by severity; plus `D discovery notes` reported separately
- **Spec impact** — net lines `spec.md` gains if every suggestion is applied
- **Top findings** — list the 3 most important actionable must-address findings (if any)
- **Verification report path**:
  - `MODE = spec`: `SPEC_DIR/verification.md`
  - `MODE = constitution`: `CONSTITUTION_DIR/constitution-verification.md`

Then render the gate report and emit its stdout verbatim. Same `SPECIFY_FEATURE_DIRECTORY` pattern as Step 6a:

```bash
SPECIFY_FEATURE_DIRECTORY="$([ "$MODE" = "spec" ] && echo "$FEATURE_DIR")" \
speckit run render-gate-report.sh \
  --stage verify \
  --gate-type "verify" \
  --must-address "${MUST_ADDRESS_COUNT:-0}" \
  --quorum-met "$QUORUM_MET" \
  --auto-mode <true if AUTO_MODE was detected, else false>
```

**Fallback**: if the script is missing or exits non-zero, report the finding counts and the verification report path as above, then continue to the next-steps guidance below. Never let a rendering failure suppress the next-steps guidance.

➡️ **Successor obligation**: the next step depends on the mode you ran. While findings remain — in any mode — it is to apply them by `route` and re-run `/speckit-verify`; never present submission as an alternative to resolving must-address findings. On a pass: spec mode is the end of the pipeline and hands off to diff creation, and constitution mode is complete. Name the successor for the mode you actually ran, and do not generalise one mode's ending to another.

Do not display this obligation or the Next steps block below yet — Step 9 displays them once the post-completion hook finishes, so they are the last thing shown.

- **Next steps:**
  - **Applying findings** (spec mode): each finding names the artifact to change in its `route` field — apply it there. `route: code` to the code, `route: spec.md` to `spec.md`, `route: discovery` nowhere. Verify does not apply findings itself (Step 5): it is read-only with respect to `spec.md`, so a `route: spec.md` finding is applied after this command returns, as its own edit and its own commit. That keeps the record of what disagreed separate from the change that resolved it.
  - **For spec mode**:
    - If must-address findings: apply them by `route`, then re-run `/speckit-verify`
    - If should-consider only: review findings and apply them by `route` as appropriate
    - If pass: implementation is verified, proceed with `/pre-review` or create diff for submission
    - Always: discovery findings are recorded in the report only. **Do not add functional requirements for them** — a spec that omits internal mechanics is correct, not incomplete.
  - **For constitution mode:**
    - If must-address findings: update the constitution, then re-run `/speckit-verify --constitution`
    - If should-consider only: review findings and update constitution as appropriate
    - If pass: constitution is verified

**CRITICAL — After delegation or passed report**: Regardless of which path was taken (auto-resolve, interactive, proceed-without-resolving override, gate-passed fast path, defer, or the skip paths), you MUST proceed to Step 8 immediately. The delegated skills (`/speckit-verify-interactive`, `/speckit-verify-auto`) handle finding resolution only — they do NOT run post-completion hooks. Step 8 is YOUR responsibility and must not be skipped.

## Step 8: Post-Completion Hook (MANDATORY — DO NOT SKIP)

Run `speckit run dispatch-hooks.sh hooks.after_verify` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`) — if a mandatory hook's invocation fails or terminates abnormally, halt with "`<stage>` completed but the follow-up step failed — re-run `/<command>` to retry" (a hook returning a result, including a blocking one, is a successful dispatch, not a failure); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue. This step MUST execute after every verify completion path — including interactive/auto delegation, override, defer, and the gate-passed fast path.

## Step 9: Display Next-Step Guidance (ALWAYS RUN — DO NOT OMIT)

Now that the hook(s) in Step 8 have finished executing, display the ➡️ **Successor obligation** line and its mode-specific next-steps guidance from Step 7. This is the only time it is shown, and it must be the last thing shown to the user (or calling command) this turn.

## Graceful Failure Handling

This command must always complete, even if individual subagents fail. The calling command (`/speckit-generate`) depends on this returning a result.

**For `MODE = spec`:**
- **If 1-3 agents fail:** write `verification.md` with completed results. Set status to `partial`. List failed agents and failure reasons in the Summary section.
- **If all 4 agents fail:** write a minimal `verification.md` with status `partial`, zero findings, and all 4 agents listed as failed. Report the failure to the user with instructions to re-run.

**For `MODE = constitution`:**
- **If the agent fails:** write a minimal `constitution-verification.md` with status `partial`, zero findings, and the agent listed as failed. Report the failure to the user with instructions to re-run.

**For both modes:**
- **If file resolution fails** (file not found): report the error immediately and stop. Do not dispatch subagents.
- **If `MODE = spec` and no implementation exists** (Step 2's precondition check): report the error immediately and stop. Do not dispatch subagents.
- **Never throw an unhandled error** — catch failures at each step and degrade gracefully.
