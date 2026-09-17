---
name: speckit-implement
description: 'SpecKit SDD pipeline: execute all tasks from `specs/<feature>/tasks.md`.'
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:meta
  meta_preset_strategy: replace
  meta_preset_upstream: speckit.implement
user-invocable: true
disable-model-invocation: false
---



# Speckit Implement Skill

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Workspace check (MANDATORY)**: Run `speckit run require-workspace.sh`. This resolves the workspace from any subdirectory and produces the same fixed message when there is no workspace above the current directory. On a non-zero exit, relay its stderr output to the user verbatim — do not paraphrase, reword, summarize, or translate it; do not prepend or append anything (no preface, heading, or attribution such as "require-workspace.sh failed:"); do not name the script, the command, the exit code, or any internal path — then halt. On exit 0, proceed silently to the next check.

**Pre-execution hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.before_implement` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue. Wait for all hooks to complete before continuing.

**Model note**: This command is code generation from well-specified tasks — Sonnet is sufficient. If you are running on Opus, let the user know they can switch to Sonnet (`/model sonnet`) for faster implementation without quality loss. Opus is justified for adversarial review agents, not implementation.

## Outline

This command executes your task list phase by phase — running tests, applying code changes, and verifying each phase before moving to the next.

Before starting work, briefly tell the user what this stage does and why it matters. Print the introduction in bold.

1. **Parse and strip flags**: Check `$ARGUMENTS` for `--auto`, `--pause-between-phases`, and `--no-pause-between-phases` as standalone leading tokens. Record which flags were found, then strip them from `$ARGUMENTS`. Do not strip flags embedded in the feature description text (e.g., "Add --auto flag support" should keep the flag text). If both `--pause-between-phases` and `--no-pause-between-phases` are present, `--no-pause-between-phases` wins.

   After stripping, continue with the remaining `$ARGUMENTS` as the feature description.

2. **Run setup script**: Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root and parse FEATURE_DIR and AVAILABLE_DOCS list. All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

   `AVAILABLE_DOCS` lists optional docs only (e.g., `research.md`, `data-model.md`) — `spec.md`/`plan.md`/`tasks.md` are mandatory and already validated by the script, so their absence from that list does not mean they're missing.

   **Constitution violation gate**: Read the most recent `analyze` entry from `$FEATURE_DIR/pipeline-state.jsonl` (use `jq -R 'fromjson? // empty' "$FEATURE_DIR/pipeline-state.jsonl" | jq -sr '[.[] | select(.stage == "analyze")] | last'`; extract `.status // "not_found"` and `.override // "false"`). The line-wise parse is load-bearing: `jq -s` alone aborts on one unparseable line, and the empty result resolves to `not_found`, which reads as "proceed" — silently unblocking a gate that is actually blocked.

   - If override is `"true"`: Warn `Note: analyze gate was overridden — CRITICAL violations may remain unresolved.` and proceed.
   - If status is `"blocked"` (no override): Present options — **Fix now** (exit, re-run `/speckit-analyze`), **Override** (write `speckit run write-pipeline-state.sh analyze status=passed override=true`, proceed), or **Defer** (exit cleanly).
   - Otherwise: Proceed to step 3.

3. **Check checklists status** (if FEATURE_DIR/checklists/ exists):
   - Scan all checklist files in the checklists/ directory
   - For each checklist, count:
     - Total items: All lines matching `- [ ]` or `- [x]` or `- [X]`
     - Completed items: Lines matching `- [x]` or `- [X]`
     - Incomplete items: Lines matching `- [ ]`
   - Create a status table:

     ```text
     | Checklist | Total | Completed | Incomplete | Status |
     |-----------|-------|-----------|------------|--------|
     | ux.md     | 12    | 12        | 0          | ✓ PASS |
     | test.md   | 8     | 5         | 3          | ✗ FAIL |
     | security.md | 6   | 6         | 0          | ✓ PASS |
     ```

   - Calculate overall status:
     - **PASS**: All checklists have 0 incomplete items
     - **FAIL**: One or more checklists have incomplete items

   - **If any checklist is incomplete**:
     - Display the table with incomplete item counts
     - **If `--auto` flag is active**:
       - Log the skip decision (checklist validation gate skipped, proceeding as if user said "yes")
       - Proceed to step 4
     - **Otherwise**:
       - **STOP** and ask: "Some checklists are incomplete. Do you want to proceed with implementation anyway? (yes/no)"
       - Wait for user response before continuing
       - If user says "no" or "wait" or "stop", halt execution
       - If user says "yes" or "proceed" or "continue", proceed to step 4

   - **If all checklists are complete**:
     - Display the table showing all checklists passed
     - Automatically proceed to step 4

   - **Note**: Commit after completing meaningful milestones for work safety. Commit cadence is for progress preservation, not diff structure.

4. **Load implementation context**:
   - **REQUIRED**: Read tasks.md for the complete task list and execution plan
   - **REQUIRED**: Read plan.md for tech stack, architecture, and file structure
   - **IF EXISTS**: Read data-model.md for entities and relationships
   - **IF EXISTS**: Read contracts/ for API specifications and test requirements
   - **IF EXISTS**: Read research.md for technical decisions and constraints
   - **IF EXISTS**: Read quickstart.md for integration scenarios

5. **Project setup verification** (technology-dependent — skip items that don't apply):

   - This is a Meta monorepo using Sapling SCM. Do NOT create or modify .gitignore files.
   - For other tool-specific ignore files (`.dockerignore`, `.eslintignore`, `.prettierignore`): verify existing files contain essential patterns, or create with standard patterns if missing. Only check tools actually detected in the project.

6. **Resolve `pause_between_phases`**: Using the flags recorded in step 1, resolve the knob: CLI flag (from step 1) > `.specify/config.yml` `implement.pause_between_phases` value (if file exists and value is a valid boolean) > default (`false`). If config.yml has invalid YAML or the value is not boolean, warn and use the default. Use the resolved value in step 7's Execution Behavior section.

7. **Execute tasks**: Parse tasks.md for phases, dependencies, and parallel markers `[P]`. The skill should parse the Checklist Format from tasks.md — task IDs (T001), parallel markers [P], and story labels [US1]. Tasks are organized by user story ([US1], [US2], etc.). Execute phase-by-phase, completing each phase before moving to the next. Do not delegate to external skills for task execution.

   ### Parallel Dispatch

   Tasks marked `[P]` within the same phase touch different files and have no dependencies on each other. **Before dispatching, validate**: scan all `[P]` tasks in the current phase and extract their target files (from `**File**:` fields or description paths). If any two `[P]` tasks share a file, execute them sequentially instead — do not dispatch them in parallel. Log a warning: "Tasks TXXX and TYYY both modify `<file>` — executing sequentially despite [P] marker."

   **Also validate for contract coupling, not just shared files.** Two tasks can touch different files and still be unsafe to parallelize if one calls into an interface the other defines or modifies — a script's argument parsing, a function signature, a CLI flag set, a config schema. Scan each `[P]` task's description and File Plan for language indicating it invokes, calls, or depends on a file another `[P]` task in the same batch also creates or modifies. If found, treat it as a conflict: execute the two sequentially (producer before consumer), never in parallel. Log a warning: "Tasks TXXX and TYYY are contract-coupled (TYYY calls into a file TXXX modifies) — executing sequentially despite [P] marker."

   After validation, **dispatch all validated `[P]` tasks as parallel `Agent()` calls** in a single message, then wait for all to complete before the phase verification gate. Non-`[P]` tasks run sequentially in ID order (T001, T002, T003...).

   If the plan includes a **Task Dependencies** table with parallel groups, use it to determine which phases can overlap. Groups within a phase parallelize via `Agent()`; groups across phases are sequential boundaries.

   Example: if Phase 2 has T005 [P], T006 [P], T007 [P], T008 [P], T009 [P] — dispatch all 5 as parallel agents, then run T010 (verification) after all complete.

   ### Cross-File Contract Verification — MANDATORY

   Sequential phase ordering guarantees a producer task's files are on disk before a consumer task's dispatch begins — it does NOT guarantee the consumer's implementation actually matches what the producer shipped. A dispatched subagent implementing a call into another file (a script invocation, a function call, an API request) can silently drift from that file's real contract by inferring the call shape from the plan's prose or by copying a similar-looking call elsewhere in the codebase, instead of reading the file it is actually calling.

   **Before marking any task complete that adds a call into a file modified or created by a different task** — whether that producer task ran earlier in this same session (an earlier phase, or an earlier task in the same phase) or already existed in the codebase — the implementing agent MUST:

   1. Read the callee file's actual current source (not the plan's description of it, not `research.md`'s summary, not an analogous call site elsewhere).
   2. Confirm every argument name, accepted value or enum, and validation branch the call relies on actually exists in that source, exactly as invoked.
   3. If a mismatch is found, fix it as part of the current task — do not defer it to a later "integration" or "polish" phase, and do not assume the callee's own test suite will catch it. A callee's unit tests validate the callee in isolation; they do not validate a caller invented in a different task.

   This check applies regardless of whether the two tasks were dispatched in parallel or sequentially — parallelism only changes scheduling, not whether the contract was actually verified.

   ### Execution Behavior — MANDATORY

   Follow ONLY the variant below that matches your resolved `pause_between_phases` value from step 6. Ignore the other variant entirely.

   **[Default: pause_between_phases = false]** Execute ALL tasks without stopping. do NOT pause for feedback checkpoints, do NOT ask the user for feedback between phases, do NOT wait for human input between phases, do NOT pause for "Ready for feedback" checkpoints. The ONLY acceptable reason to stop is an actual blocker: failed verification, missing dependency, or unclear instruction. Commit after completing meaningful milestones to prevent work loss.

   **[Variant: pause_between_phases = true]** Pause for user feedback after each phase completes and verification passes. Allow "Ready for feedback" checkpoints between phases. The ONLY exception: do NOT pause within a phase between individual tasks.

   ### Implementation Context

   - **Spec context**: Implement exactly what the tasks and plan specify — do not improvise or add features beyond requirements
   - **Meta verification per phase**: After each phase, run the project's verification commands (defined in the project's CLAUDE.md verification commands section, `.specify/memory/verification-commands.md`, or fallback defaults (`arc f` + `arc lint -a` + `arc unit`)) on all files modified in that phase. Show full command output including exit codes.
   - **TDD ordering**: Execute test tasks before their corresponding implementation tasks within each phase
   - **Task marking**: After each task completes, MUST mark it done in tasks.md by replacing `- [ ]` with `- [x]`. Do not skip this step — tasks.md completion status is the primary signal for whether a spec has been implemented. **The orchestrator performs this edit, never a dispatched subagent** — parallel `[P]` subagents writing tasks.md concurrently overwrite each other's marks. For a task dispatched via `Agent()`, mark it after that agent returns. Step 8 reconciles marks missed here, but that pass is a safety net, not a substitute for marking as you go
   - **Error handling**: When a task fails or is blocked, provide clear diagnostics with context and suggest next steps before halting
   - **Dependency ordering**: Respect task dependencies — sequential tasks in order, parallel tasks `[P]` can run together via `Agent()` dispatch
   - **File conflicts**: Tasks affecting the same files must run sequentially, even if marked `[P]`
   - **Progress reporting**: Report completion after each task
   - **Failure handling**: Halt execution if any non-parallel task fails; for parallel tasks, continue with successful ones and report failures

   ### Evidence discipline

   Before claiming a phase is complete, you MUST show the full output of every verification command above, including exit codes. Do not use hedging language ("should pass", "looks good", "probably clean") — show the actual command output. If any command fails, report the failure with its output and fix the issue before claiming phase completion. If a verification command is not available (tool not found, timeout), report the failure as a blocking issue — do not silently skip that verification step. Run ALL applicable commands and report a full summary — do not stop at the first failure. After 2 consecutive verification failures for the same phase, stop and ask the human for direction rather than continuing to attempt fixes.

   ### Optional Per-Task Quality Gate

   For complex or high-risk tasks, consider applying a two-stage review before marking the task complete:

   1. **Spec compliance review**: Does the implementation match spec requirements? Are all acceptance criteria met? Does it solve the stated problem?
   2. **Code quality review**: Does the code follow project conventions? Is it maintainable? Are there edge cases or error handling gaps?
   3. **Fix-and-retry**: If either review finds issues, fix them before proceeding to the next task

   **Self-review checklist** (before submitting a task for review):
   - **Completeness**: All acceptance criteria met, no half-finished work
   - **Quality**: Follows project conventions, readable, maintainable
   - **Discipline/YAGNI**: No features beyond spec, no premature abstractions
   - **Testing**: Tests written (if required), tests pass
   - **Referential integrity** (if task modifies structured Markdown with numbered steps): Step numbering sequential with no gaps, all "skip to step N" targets exist, substep prefixes match parent step numbers, no dead variable handoffs, appendix numbering starts at 1, no absent/unrecognized-value fallback nested inside the conditional block it is meant to be the alternative to

   **Raise concerns first** protocol: Before starting a task, review it for ambiguity or missing context. If the task description is unclear or seems incomplete, ask the user for clarification before implementing — not after. This prevents wasted work and rework loops.

8. **Completion validation**:

   Determine the successor obligation below, but do not display it yet — step 10 displays it after the post-completion hooks, so it is the last thing shown this turn:

   ➡️ **Successor obligation**: the next stage is `/speckit-verify`. Always name it as the recommended next step, whatever your own confidence in the implementation — do not point the user at a diff, `/pre-review`, or submission instead. Whether to skip verification is the user's call, never yours.

   > **Context tip:** Implementation is complete — all changes are in the working tree. Consider /clear before /speckit-verify to free context for verification.

   - **Task completion reconciliation — MANDATORY**: Re-read `tasks.md` from disk and count:
     - Total tasks: lines matching `- [ ] T` or `- [x] T`
     - Marked complete: lines matching `- [x] T`
     - Still unmarked: lines matching `- [ ] T`

     For each still-unmarked task, decide from this session's work which case applies:
     - **Its work was completed** — mark it now by replacing `- [ ]` with `- [x]`. Marking during step 7 is easy to miss when a task involves substantial work; this pass is what makes the file accurate.
     - **Its work was not completed** — leave it unmarked and name it in the completion report as outstanding.

     Then re-count and show the user `Tasks: N/M complete`, listing the IDs of anything still unmarked. Show this count before the final status summary — do not assert completion without it.

   - **Write pipeline state**: After the reconciliation count above, write the pipeline-state entry: `speckit run write-pipeline-state.sh implement status=complete`. This explicit call is implement's own completion signal — the hook-based entry from `after_implement` (step 9) is not a substitute for it, since that hook does not always fire, which previously left `implement` unrecorded for some features even after a genuine implementation run.

     **If this call exits 4** (the `tasks` prerequisite is unmet): Read and execute `.specify/templates/prerequisite-refusal-gate.md` instead of proceeding to step 9.

   - Check that implemented features match the original specification
   - Validate that tests pass and coverage meets requirements
   - Confirm the implementation follows the technical plan
   - **Referential integrity sweep**: If any structured Markdown files with numbered steps were modified, verify each one is internally consistent — step numbering, skip-to targets, variable handoffs, conditional branches, label consistency, substep parent alignment, appendix numbering, and fallback-rule nesting (an absent/unrecognized-value fallback must sit as a sibling of the field's parsing instruction, not inside the conditional block it is an alternative to)
   - Report final status with summary of completed work
   - When ALL tasks across ALL phases are complete, verification passes, and the reconciliation count shows zero unmarked tasks, end the summary with: **Spec Complete**. If any task remains unmarked, report what is outstanding instead — do not emit **Spec Complete** over an incomplete task list

   **If `--auto` flag was active**: Include an `## Auto-Resolution Log` section in the completion report listing all auto-resolved decision points during this session. Append this log to `{FEATURE_DIR}/auto-resolution-log.md` (create if it doesn't exist) with a timestamp header.

   Note: This command assumes a complete task breakdown exists in tasks.md. If tasks are incomplete or missing, suggest running `/speckit-tasks` first to regenerate the task list.

9. **Post-completion hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.after_implement` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`) — if a mandatory hook's invocation fails or terminates abnormally, halt with "`<stage>` completed but the follow-up step failed — re-run `/<command>` to retry" (a hook returning a result, including a blocking one, is a successful dispatch, not a failure); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue.

10. **🔁 Display next-step guidance (ALWAYS RUN — DO NOT OMIT)**: Now that the hook(s) in step 9 have finished executing, display the ➡️ **Successor obligation** line (and Context tip) from step 8. This is the only time it is shown, and it must be the last thing shown to the user this turn.
