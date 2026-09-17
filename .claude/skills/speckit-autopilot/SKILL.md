---
name: speckit-autopilot
description: 'SpecKit SDD pipeline: run all stages (`/speckit-specify` through `/speckit-verify`) autonomously with auto-commit hooks and review gates. Requires an initialized SpecKit project with `.specify/` directory.'
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:meta
  meta_preset_strategy: replace
user-invocable: true
disable-model-invocation: false
---



# Speckit Autopilot Skill

# SpecKit Autopilot

This command runs the full SpecKit pipeline end-to-end — from writing your spec through verifying the implementation. It detects where you left off and resumes automatically, choosing recommended answers at each decision point.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Arguments

Parse `$ARGUMENTS` for:
- `--from <step>` — start from a specific step: `specify`, `clarify`, `review-spec`, `plan`, `review-plan`, `review`, `tasks`, `implement`, `verify`. Overrides auto-detection. `--from review` resumes at the first incomplete review stage (auto-detect from pipeline-state.jsonl: if no primary review, start at spec review; if primary done but no secondary, start at plan review; **if a secondary review exists but its latest entry is `blocked`, start at plan review** — a blocked gate is unfinished work, and presence-only detection would otherwise read it as done and leave no route back into the stage that owns it). `--from review-spec` resumes at spec review. `--from review-plan` resumes at plan review.
- `--skip-review` — skip `/speckit-review` steps entirely.
- `--skip-clarify` — skip `/speckit-clarify`.
- Positional text — feature description (only needed when starting from `specify`).

## Step 1: Pre-Flight Checks

Before starting work, briefly tell the user what this stage does and why it matters. Print the introduction in bold.

**Output discipline**: Suppress routine setup narration — step numbers, variable bindings, and per-file existence-check details. Errors, warnings, interactive prompts, the detected pipeline state, the planned execution sequence, each dispatched stage's name as it begins, and each stage's completion status are not routine narration and must still be shown.

**Workspace check (MANDATORY)**: Run `speckit run require-workspace.sh`. This resolves the workspace from any subdirectory and produces the same fixed message when there is no workspace above the current directory. On a non-zero exit, relay its stderr output to the user verbatim — do not paraphrase, reword, summarize, or translate it; do not prepend or append anything (no preface, heading, or attribution such as "require-workspace.sh failed:"); do not name the script, the command, the exit code, or any internal path — then halt. On exit 0, proceed to the rest of this step.

Before starting the pipeline, check if project-context.md exists:

```bash
test -f .specify/memory/project-context.md
```

If it does NOT exist, suggest:
```
NOTE: project-context.md is missing. Run `/speckit-setup` to generate project context before running the pipeline. This is non-blocking — autopilot will continue regardless.
```

This is advisory only — proceed with the pipeline whether or not the user runs setup.

## Step 2: Detect Pipeline State

Record the current commit hash as the fold baseline before any pipeline steps execute:

```bash
BASELINE_COMMIT=$(sl log -r . -T '{node|short}')
```

This is the fold anchor — all commits created after this point are pipeline commits eligible for folding.

Run `.specify/scripts/bash/check-prerequisites.sh --json --paths-only` to get `FEATURE_DIR`. Then check which artifacts exist:

```
spec.md        → specify is done
plan.md        → plan is done
tasks.md       → tasks is done
review/review-findings.md → review has run (check review/review-gate.json for pass/block)
verification.md → verify is done
```

Build a state map and determine the next step. If `--from` was provided, use that instead of auto-detection. Print the detected state and planned sequence to the user before proceeding.

## Step 3: Execute Pipeline

Run each remaining step in sequence. The full pipeline order is:

```
specify → clarify → review-spec → plan → review-plan → tasks → [fold] → implement → verify
```

For each step, dispatch a subagent via the `Agent` tool with a self-contained prompt that invokes the stage's skill. The subagent handles skill invocation, hooks (pipeline-display, sdd-commit, pipeline-state-write), and artifact generation. The orchestrator coordinates stage sequencing, gate checking, and the review fix loop.

### 3a. Model Selection

Read `.specify/config.yml` and check for `autopilot.models`. This is a map of stage name to model (`opus`, `sonnet`, `haiku`). For each stage dispatch below, if a model is configured for that stage, pass it as the `model` parameter to the `Agent` tool. If the stage is not listed or `autopilot.models` is absent/commented-out, omit the `model` parameter (the subagent inherits the parent's model).

Example config:
```yaml
autopilot:
  models:
    specify: opus
    plan: opus
    tasks: sonnet
    implement: sonnet
```

### 3b. Stage Dispatch Pattern

For each stage, use foreground Agent dispatch (no `run_in_background`). If `autopilot.models` specifies a model for the current stage (per §3a), pass it as the `model` parameter to the Agent tool. Every dispatch prompt MUST instruct the subagent to execute the stage's `sdd-commit` hook without prompting — `dispatch-hooks.sh` reports these hooks as `optional: true` (prompted for interactive use), but autonomous mode treats them as mandatory so the working copy stays clean between stages:

**Specify subagent**:
```text
You are executing the specify stage of the SpecKit pipeline.

Run: Skill("speckit-specify", args: "<feature-description>")

The skill handles setup scripts, spec generation, and post-stage hooks (pipeline-display, sdd-commit, pipeline-state-write). Execute the sdd-commit hook without prompting even though the vended extensions.yml marks it optional — this is autonomous mode.
```

**Clarify subagent**:
```text
You are executing the clarify stage of the SpecKit pipeline.

Run: Skill("speckit-clarify")

For all clarification questions, choose the **recommended** answer. This is autonomous mode — do not ask the user for input.

The skill handles spec updates and post-stage hooks.
```

**Spec review subagent** (dispatched after clarify):
```text
You are executing the spec review stage of the SpecKit pipeline.

Run: Skill("speckit-review-spec", args: "--auto")

Pass --auto so the review skill delegates to review-auto's convergence loop for MUST-ADDRESS resolution and best-effort SHOULD-CONSIDER/MINOR fixes.

The skill handles agent dispatch, synthesis, gate writing, and post-stage hooks (pipeline-state-write).
```

**Plan review subagent** (dispatched after plan):
```text
You are executing the plan review stage of the SpecKit pipeline.

Run: Skill("speckit-review-plan", args: "--auto")

Pass --auto so the review skill delegates to review-auto's convergence loop for MUST-ADDRESS resolution, best-effort SHOULD-CONSIDER/MINOR fixes, and post-auto-resolve re-validation.

The skill handles agent dispatch, synthesis, gate writing, and post-stage hooks (pipeline-state-write).
```

**Plan subagent**:
```text
You are executing the plan stage of the SpecKit pipeline.

Run: Skill("speckit-plan")

The skill handles plan generation and post-stage hooks (pipeline-display, sdd-commit, pipeline-state-write). Execute the sdd-commit hook without prompting even though the vended extensions.yml marks it optional — this is autonomous mode.
```

**Tasks subagent**:
```text
You are executing the tasks stage of the SpecKit pipeline.

Run: Skill("speckit-tasks")

The skill handles task breakdown and post-stage hooks (pipeline-display, sdd-commit, pipeline-state-write). Execute the sdd-commit hook without prompting even though the vended extensions.yml marks it optional — this is autonomous mode.
```

**Implement subagent**:
```text
You are executing the implement stage of the SpecKit pipeline.

Run: Skill("speckit-implement")

The skill handles task execution, commit boundaries, and post-stage hooks (pipeline-display, pipeline-state-write). Implement does NOT have a sdd.commit hook in after_implement — the skill commits during execution.
```

**Verify subagent**:
```text
You are executing the verify stage of the SpecKit pipeline.

Run: Skill("speckit-verify", args: "--auto")

Pass --auto so verify delegates to verify-auto's convergence loop for MUST-ADDRESS resolution when the gate is blocked.

The skill handles verification report generation and post-stage hooks (pipeline-display, sdd-commit, pipeline-state-write). Execute the sdd-commit hook without prompting even though the vended extensions.yml marks it optional — this is autonomous mode.
```

### 3c. Dispatch and Completion Messages

Before each stage, log: "Dispatching <stage> subagent..."

After each stage, log: "<Stage> complete."

### 3d. Post-Stage Artifact Verification

After each stage subagent returns, verify the expected output artifact exists:

- specify → `{FEATURE_DIR}/spec.md`
- review → `{FEATURE_DIR}/review/review-gate.json`
- plan → `{FEATURE_DIR}/plan.md`
- tasks → `{FEATURE_DIR}/tasks.md`
- verify → `{FEATURE_DIR}/verification.md` and `{FEATURE_DIR}/verify-gate.json`
- clarify → no distinct artifact check (modifies existing `spec.md`)

If the expected artifact is missing, report an error and suggest resuming from the failed stage using `--from <stage>`.

### 3e. Handle Review Gates

After each review subagent returns (spec review and plan review), read `{FEATURE_DIR}/review/review-gate.json` to check status. Each review subagent passes `--auto`, which delegates to review-auto's convergence loop for MUST-ADDRESS resolution and best-effort SHOULD-CONSIDER fixes. The autopilot does not have its own fix loop — review-auto owns the entire fix cycle.

- After spec review: check the review gate for primary gate status
- After plan review: check the review gate for secondary gate status

**If `--skip-review` is active**: Create the `review/` subdirectory (`mkdir -p`) and write a synthetic "passed" `review/review-gate.json` before both primary and secondary review points:
```json
{"status": "passed", "severity_counts": {"MUST-ADDRESS": 0, "SHOULD-CONSIDER": 0, "MINOR": 0}}
```

**If the gate is PASSED**: Log remaining non-blocking findings from the review findings file and proceed to the next step.

**If the gate is BLOCKED**: Review-auto has already given up on this finding set — it stops as soon as an iteration confirms none of the fixes it claimed, which can be the first iteration, so a blocked gate here does not imply it spent its full iteration budget. Its report names which findings are still unresolved and which of those it actively disproved a fix for.

**Degraded-quorum disclosure (blocked plan review only).** Before rendering the menu below, when this branch was reached from a plan review (secondary gate): read the review gate file's `partial`, `agents_completed` and `panel_size` fields. If `partial` is `true`, emit before the menu: "Note: {panel_size - agents_completed} reviewer role(s) did not return for this review ({agents_completed}/{panel_size} completed); those roles may be under-covered. See the review findings file's delivery table for which roles, and consider re-running to confirm."

Present graduated gate options:
  ```
  Review gate BLOCKED after auto-resolve. {N} MUST-ADDRESS findings remain.

  Options:
  1. **Fix now** — Fix manually and resume with `--from review`.
  2. **Override** — Proceed despite unresolved findings. Unresolved review findings may propagate to plan and implementation, requiring later rework.
  3. **Defer** — Stop the pipeline. Resume later with `--from review` after resolving findings.
  ```
  - If **Fix now** or **Defer**: Stop the pipeline with appropriate guidance.
  - If **Override**: Write override: `speckit run write-pipeline-state.sh review status=passed override=true`. Proceed to next stage.

  Do not retry review — review-auto stopped because it had stopped making progress, not because it ran out of attempts, so a retry over the same findings reaches the same place. If the gate remains blocked, user intervention is required.

### 3f. Fold Pipeline Commits

After the **tasks** step completes (and before implement), offer to fold all pipeline commits into a single commit.

1. **Read config**: Read `.specify/config.yml` and check for `autopilot.fold_commits`. If the value is `true`, auto-fold without prompting. If `false`, absent, or the file is missing/malformed, prompt the user.

2. **Check prerequisites**:
   - If `BASELINE_COMMIT` is unknown (session was interrupted and resumed), skip fold: "Fold skipped — baseline commit unknown. Run `sl fold` manually if desired."
   - Count pipeline commits after `BASELINE_COMMIT`: `sl log -r '(BASELINE_COMMIT::.) - BASELINE_COMMIT' -T '{node|short}\n' | wc -l`. If ≤1, skip silently (no-op).
   - Verify clean working copy: `sl status`. If uncommitted spec changes exist, commit them via sdd-commit hook first. If non-spec changes exist, abort fold: "Fold aborted — uncommitted non-spec changes detected. Commit or revert them first."

3. **Prompt or auto-fold**:
   - Display the commit range: "Fold {N} pipeline commits (after {BASELINE_COMMIT}) into one?"
   - If auto-fold (config) or user accepts:
     ```bash
     sl fold --from "min((BASELINE_COMMIT::.) - BASELINE_COMMIT)" -m "[PREFIX] [<feature-name>] Pipeline: specify, clarify, review, plan, tasks"
     ```
     The step list in the title reflects which steps actually ran — omit skipped steps (e.g., if `--skip-clarify` was used, omit "clarify").
   - If user declines: leave all individual commits intact and proceed.

4. **Error handling**: If `sl fold` fails (non-linear history, merge conflicts), report the error and leave all commits untouched: "Fold failed: {error}. All pipeline commits preserved."

### 3g. Handle Verify Gate

After the verify subagent returns (dispatched with `--auto`, per §3b, so it already delegated to verify-auto for resolution when blocked), read `{FEATURE_DIR}/verify-gate.json` to check the gate status.

**If the gate is PASSED**: Log finding counts (any non-blocking should-consider/minor findings) and proceed to Step 4 completion.

**If the gate is BLOCKED**: verify-auto has already exhausted its convergence loop (3 iterations). It retains partial fixes rather than rolling them back on failure to converge — as review-auto now does too; what differs between the two loops is scope, not retention policy, since verify's fixes can reach code across many files where review's stay in `spec.md`, `plan.md` and `contracts/`. Present graduated gate options:
  ```
  Verify gate BLOCKED after auto-resolve. {N} MUST-ADDRESS findings remain (fixes applied so far were retained, not rolled back).

  Options:
  1. **Fix now** — Fix manually and resume with `--from verify`.
  2. **Override** — Proceed despite unresolved findings. Unresolved verification findings may leave spec-code mismatches unaddressed.
  3. **Defer** — Stop the pipeline. Resume later with `--from verify` after resolving findings.
  ```
  - If **Fix now** or **Defer**: Stop the pipeline with appropriate guidance.
  - If **Override**: Run the record script first, and rewrite the gate only if it succeeds:
    ```bash
    speckit run record-gate-override.sh \
      --stage verify \
      --quorum-met true
    ```
    On exit 0: rewrite the gate to passed, then proceed to Step 4 completion:
    ```bash
    speckit run write-review-gate-unified.sh \
      --stage verify \
      --gate-type "verify" \
      --status passed \
      --must-address 0 \
      --should-consider "$(jq -r '.should_consider_count' "$FEATURE_DIR/verify-gate.json")" \
      --minor "$(jq -r '.minor_count' "$FEATURE_DIR/verify-gate.json")" \
      --agents-completed "$(jq -r '.agents_completed' "$FEATURE_DIR/verify-gate.json")" \
      --override
    ```
    On exit 3: report "override refused — gate unchanged" and stop the pipeline (do not proceed to Step 4).

  Do not retry verify automatically — verify-auto has already exhausted its convergence loop (3 iterations). If the gate remains blocked, user intervention is required.

## Step 4: Completion

After the verify subagent completes:

1. **Degraded-quorum disclosure (completion table)**: Read `review/review-gate.json`'s `partial`, `agents_completed` and `panel_size` fields — this file already holds the plan review's final gate state, so no entry selection is needed. If `partial` is not `true`, treat the disclosure as discharged. Otherwise, append to the `review-plan` row's Details column: "Note: {panel_size - agents_completed} reviewer role(s) did not return for this review ({agents_completed}/{panel_size} completed); those roles may be under-covered. See the review findings file's delivery table for which roles, and consider re-running to confirm."
2. Print a summary table:
   ```
   | Step        | Status  | Details                                              |
   |-------------|---------|------------------------------------------------------|
   | specify     | Done    | spec.md created                                      |
   | clarify     | Skipped | --skip-clarify                                       |
   | review-spec | Passed  | 0 must-address, 5 should-consider, 2 minor remaining |
   | plan        | Done    | 6 implementation steps                               |
   | review-plan | Passed  | 3 must-address → fixed in 2 rounds                   |
   | tasks       | Done    | 38 tasks across 4 phases                             |
   | fold        | Done    | 8 commits → 1                                        |
   | implement   | Done    | 356 tests pass, 0 failures                           |
   | verify      | Passed  | 0 must-address                                       |
   ```
3. Report total commits created and any remaining action items (including remaining non-blocking review findings).

## Rules

- **Autonomous mode**: Do not ask the user for input during the pipeline. Choose recommended answers for all questions. The only exceptions: (a) fold prompt when `autopilot.fold_commits` is not configured, (b) verification command fails after 2 fix attempts — then stop and report.
- **Commit boundaries override autonomy**: Even in autonomous mode, commit between phases when `tasks.md` defines diff boundaries. This is a structural gate, not an optional checkpoint.
- **Subagent dispatch**: Dispatch each SpecKit skill via the `Agent` tool in foreground mode (no `run_in_background`). Each subagent invokes its stage's `Skill()` call. The skills must still be listed here for pipeline contract tests: `speckit-specify`, `speckit-clarify`, `speckit-review`, `speckit-review-spec`, `speckit-review-plan`, `speckit-plan`, `speckit-tasks`, `speckit-implement`, `speckit-verify`.
- **Hook ownership**: Subagents fire their own `after_<stage>` hooks for pipeline-state writes. For sdd-commit: specify, clarify, plan, tasks, and verify have `sdd.commit` hooks that fire inside the subagent. `dispatch-hooks.sh` reports these hooks as `optional: true` (prompted for interactive runs), but autonomous mode treats them as mandatory — the subagent auto-executes them without prompting so downstream stages inherit a clean working copy. Review fixes are handled by review-auto (delegated via `--auto`), and committed by the review command's `after_review` hook. The orchestrator does NOT commit after implement — the implement subagent owns all commits including the commit boundaries `tasks.md` defines. The orchestrator itself has no remaining inline-commit responsibility — every stage now commits its own artifacts via its own hooks.
- **Artifact verification**: After each stage subagent returns, verify the expected output artifact exists. If missing, report the error with the artifact path and suggest resuming from the failed stage using `--from <stage>`.
- **Progress updates**: Print a one-line status update as each step completes (e.g., "Plan complete — 6 steps, single diff.").
- **Error recovery**: If a step fails, report the error with context and stop. Do not skip steps (except when `--skip-review` or `--skip-clarify` is used).
