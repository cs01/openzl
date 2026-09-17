---
name: speckit-review
description: 'SpecKit SDD pipeline: auto-dispatch review — routes to `/speckit-review-spec` or `/speckit-review-plan` based on pipeline state.'
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:meta
  meta_preset_strategy: replace
user-invocable: true
disable-model-invocation: false
---



# Speckit Review Skill

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Workspace check (MANDATORY)**: Run `speckit run require-workspace.sh`. This resolves the workspace from any subdirectory and produces the same fixed message when there is no workspace above the current directory. On a non-zero exit, relay its stderr output to the user verbatim — do not paraphrase, reword, summarize, or translate it; do not prepend or append anything (no preface, heading, or attribution such as "require-workspace.sh failed:"); do not name the script, the command, the exit code, or any internal path — then halt. On exit 0, proceed silently to the next check.

**Pre-execution hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.before_review` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue. Wait for all hooks to complete before continuing.

## Outline

This command determines which review stage your spec needs next and runs it automatically — routing to spec review if the spec hasn't been reviewed yet, or plan review if the spec review is complete and a plan exists.

Before starting work, briefly tell the user what this stage does and why it matters. Print the introduction in bold.

**Output discipline**: Suppress routine setup narration — step numbers, variable names, and pipeline-state parsing. Errors, warnings, the dispatch decision, and any user prompts are not routine narration and must still be shown.

1. **Parse and strip flags**: Check `$ARGUMENTS` for `--auto` and `--skip-review` flags. If present, record which flags were found, then strip them as standalone leading tokens from `$ARGUMENTS` before proceeding. Do not strip flags embedded in the feature description text.

   After stripping, continue with the remaining `$ARGUMENTS` as the feature description.

2. **Setup**: Run `.specify/scripts/bash/check-prerequisites.sh --json --paths-only` from repo root and parse JSON for FEATURE_DIR.

3. **Handle --skip-review**: If `--skip-review` was passed, write synthetic passed gates for BOTH review stages:
   ```bash
   # Write primary gate
   speckit run write-review-gate-unified.sh \
     --gate-type "primary" \
     --status passed \
     --must-address 0 --should-consider 0 --minor 0 \
     --agents-completed 0

   # Write secondary gate (only if plan.md exists)
   if [ -f "${FEATURE_DIR}/plan.md" ]; then
     speckit run write-review-gate-unified.sh \
       --gate-type "secondary" \
       --status passed \
       --must-address 0 --should-consider 0 --minor 0 \
       --agents-completed 0
   fi
   ```
   Log: "Review skipped — pipeline will proceed as if review passed."
   Run the Extension Hook Protocol for key `hooks.after_review` (MANDATORY on this path — DO NOT SKIP) — this is required because the dispatched commands are not invoked in the skip-review path, so their mandatory hook steps never fire; without this, synthetic gate files remain uncommitted: `speckit run dispatch-hooks.sh hooks.after_review` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`) — if a mandatory hook's invocation fails or terminates abnormally, halt with "`<stage>` completed but the follow-up step failed — re-run `/<command>` to retry" (a hook returning a result, including a blocking one, is a successful dispatch, not a failure); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue. This call fires only inside the `--skip-review` branch — the normal dispatch path (step 5) does not fire `after_review` itself; the dispatched command (`/speckit-review-spec` or `/speckit-review-plan`) owns that call, so firing it here on the normal path would double-dispatch.
   Exit after hooks complete.

4. **Detect pipeline state**: Determine which review to dispatch.

   ```bash
   # Detect plan existence
   PLAN_EXISTS=$(test -f "${FEATURE_DIR}/plan.md" && echo "true" || echo "false")

   # Detect spec review completion (gate_type == "primary")
   SPEC_REVIEW_DONE=$(jq -sr '[.[] | select(.stage == "review") | select(.gate_type == "primary")] | length > 0' "${FEATURE_DIR}/pipeline-state.jsonl" 2>/dev/null || echo "false")

   # Detect plan review completion (gate_type == "secondary")
   PLAN_REVIEW_DONE=$(jq -sr '[.[] | select(.stage == "review") | select(.gate_type == "secondary")] | length > 0' "${FEATURE_DIR}/pipeline-state.jsonl" 2>/dev/null || echo "false")

   # Detect whether that plan review left its gate blocked
   PLAN_REVIEW_BLOCKED=$(jq -sr '[.[] | select(.stage == "review") | select(.gate_type == "secondary")] | last | .status == "blocked"' "${FEATURE_DIR}/pipeline-state.jsonl" 2>/dev/null || echo "false")
   ```

   **Error handling**: If `pipeline-state.jsonl` is missing or unparseable, treat `SPEC_REVIEW_DONE`, `PLAN_REVIEW_DONE` and `PLAN_REVIEW_BLOCKED` as false. Log: "Pipeline state unreadable — defaulting to spec review."

   **Why the blocked check exists.** Detection here is presence-based: a secondary review that ran and left its gate blocked still counts as done, and without this the user is told both reviews are complete and asked whether to re-run one. That is the wrong question — a blocked gate is unfinished, not finished. The dispatched command's own guard already handles the re-entry correctly; this check is what stops the router from describing the state incorrectly on the way there.

5. **Dispatch based on state**:

   | PLAN_EXISTS | SPEC_REVIEW_DONE | PLAN_REVIEW_DONE | Action |
   |:-:|:-:|:-:|--------|
   | false | false | — | Auto-dispatch → spec review |
   | true | true | false | Auto-dispatch → plan review |
   | true | false | false | Prompt user: "Spec review hasn't run yet. Run (A) spec review, (B) plan review?" |
   | true | true | true, `PLAN_REVIEW_BLOCKED` true | Auto-dispatch → plan review (its gate is still blocked, so the work is unfinished) |
   | true | true | true, `PLAN_REVIEW_BLOCKED` false | Prompt user: "Both reviews complete. Re-run (A) spec review, (B) plan review?" |
   | false | true | — | Auto-dispatch → spec review (re-run) |
   | *(any unmatched state)* | | | Log warning: "Unexpected review state. Defaulting to spec review." → Auto-dispatch → spec review |

   **Dispatch mechanism**: Forward all remaining arguments (including `--auto` if present) via Skill() call:
   ```
   Skill("speckit-review-spec", args: "$ARGUMENTS")
   ```
   or
   ```
   Skill("speckit-review-plan", args: "$ARGUMENTS")
   ```

   In the normal dispatch path, the router does NOT run `after_review` hooks — each dispatched command handles its own hooks. (The skip-review path in step 3 is the exception — it fires hooks itself since no command is dispatched.)

6. **Post-dispatch note**: After the dispatched command completes, the router's work is done. The dispatched command handles its own `after_review` hooks, so the router does not fire them again.
