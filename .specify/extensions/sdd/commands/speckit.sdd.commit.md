---
description: "SpecKit internal: Sapling auto-commit for `specs/` and `.specify/` artifacts after a SpecKit pipeline stage completes."
---

# Sapling Auto-Commit

Commit spec artifacts via Sapling after a SpecKit command completes. This command is invoked as a lifecycle hook — it is not intended to be called directly by the user.

## Behavior

This command commits only files under `specs/` and `.specify/` — it never commits code changes. Sapling has no staging area, so explicit path scoping is critical to avoid committing unrelated work.

## Execution

1. **Determine the event name** from the hook that triggered this command. The event name comes from the calling context — for example, if invoked as an `after_specify` hook, the event is `after_specify`. If invoked as `after_plan`, the event is `after_plan`.

2. **Check for changes** under `specs/` and `.specify/`. If no changes exist, skip silently — nothing to commit.

   ```bash
   sl status specs/ .specify/
   ```

3. **Generate commit metadata** (summary + test plan) based on the event and changes:

   a. **Analyze the changes**: Run `sl diff specs/ .specify/` to see what was added/modified

   b. **Draft the summary** following the WHY + WHAT format:
      - **WHY**: Explain the purpose of this pipeline step (clarify ambiguities, validate spec via review, plan implementation, etc.)
      - **WHAT**: Describe the artifacts created/modified and key changes (e.g., "Added `plan.md` with 3-phase implementation plan", "Created `review/review-findings.md` with 31 categorized findings")

   c. **Draft the test plan**: Document verification steps showing how the artifacts were validated
      - For spec/clarify: show the clarification Q&A was added
      - For review: show findings were generated and gate status was set
      - For plan: show plan artifacts exist and have expected structure
      - For tasks: show task breakdown exists with all phases
      - For implement: show implementation verification steps (tests pass, lint clean, etc.)

   d. **Export metadata** as environment variables for the commit script:

      ```bash
      export SPECKIT_COMMIT_SUMMARY="<generated_summary>"
      export SPECKIT_COMMIT_TEST_PLAN="<generated_test_plan>"
      ```

4. **Locate the commit script** at `.specify/extensions/sdd/scripts/bash/sapling-commit.sh`. If the script does not exist, skip silently — the extension may not be fully installed.

5. **Run the script** with the event name as the sole argument:

   ```bash
   bash .specify/extensions/sdd/scripts/bash/sapling-commit.sh <event_name>
   ```

   Replace `<event_name>` with the actual hook event (e.g., `after_specify`, `after_plan`, `after_constitution`). The script will use the `SPECKIT_COMMIT_SUMMARY` and `SPECKIT_COMMIT_TEST_PLAN` environment variables if set.

6. **Report the result** briefly. Do not break the calling skill's flow:
   - On success: note that spec artifacts were committed with full metadata
   - On "no changes": skip silently — nothing to report
   - On error: note the failure but do not stop the parent workflow

## Commit Title Prefix

The commit script resolves the title prefix automatically using this precedence:

1. **Project CLAUDE.md**: Checks `.claude/CLAUDE.md` then `CLAUDE.md` at the project root for a `Prefix:` field (e.g., `Prefix: [NSync]`) or a `Title tag` table entry (e.g., `| Title tag | \`[MyApp]\` |`) within any `## Diff *` section.
2. **Project directory name**: If no prefix is found, uses the project root directory basename in brackets (e.g., `[hello-world-3]`).

No agent action needed — prefix resolution is handled by the script.

In the table below, `[PREFIX]` refers to the resolved value.

## Supported Events

| Event | Commit Title | Summary Template | Test Plan Template |
|-------|--------------|------------------|-------------------|
| `after_clarify` | `[PREFIX] [<feature>] Clarify` | WHY: The `/speckit-clarify` session revealed N underspecified areas in the spec that needed clarification before planning. WHAT: Added `## Clarifications` section documenting N Q&A pairs from the session, updated affected requirements. | Ran `/speckit-clarify` on the spec, answered N clarifying questions, verified clarifications section exists and contains Q&A pairs. |
| `after_review` | `[PREFIX] [<feature>] Review` | WHY: The spec needed adversarial review to identify gaps, inconsistencies, edge cases before planning. WHAT: Ran `/speckit-review` dispatching N parallel agents, generated `review/review-findings.md` with categorized findings (X MUST-ADDRESS, Y SHOULD-CONSIDER, Z MINOR), updated review gate status. | Ran `/speckit-review`, verified findings file exists with expected categories, confirmed gate status reflects MUST-ADDRESS count. |
| `after_specify` | `[PREFIX] [<feature>] Specify` | WHY: Initial feature specification from user requirements. WHAT: Created `spec.md` with Problem, Solution, Requirements sections defining scope and constraints. | Ran `/speckit-specify` to generate initial spec, verified spec.md exists with mandatory sections. |
| `after_plan` | `[PREFIX] [<feature>] Plan` | WHY: With spec validated, generate technical implementation plan breaking down user stories into phases. WHAT: Created N planning artifacts — `plan.md` (X phases, Y tasks across Z diffs), `data-model.md`, `quickstart.md`, supplementary docs. | Ran `/speckit-plan`, verified plan artifacts exist, checked plan.md structure (phase count, task count, diff references). |
| `after_tasks` | `[PREFIX] [<feature>] Tasks` | WHY: Break down implementation plan into actionable task list. WHAT: Created `tasks.md` with N tasks organized by phase/diff boundaries, each with acceptance criteria. | Ran `/speckit-tasks`, verified tasks.md exists with expected task count and phase organization. |
| `after_implement` | `[PREFIX] [<feature>] Implement` | WHY: Execute implementation tasks from plan. WHAT: Implemented [describe features/changes], modified N files, added/updated M tests. | Ran implementation verification: [test commands], [lint commands], confirmed [specific behaviors]. |
| `after_constitution` | `[PREFIX] Update project constitution` | WHY: [Reason for constitution update]. WHAT: Updated `constitution.md` — [describe changes]. | Verified constitution.md changes: [describe verification]. |
| `after_checklist` | `[PREFIX] [<feature>] Checklist` | WHY: Generate custom checklist for current feature requirements. WHAT: Created `checklists/<domain>.md` with N items covering [aspects]. | Ran `/speckit-checklist`, verified the checklists/ entry exists with feature-specific items. |
| `after_generate` | `[PREFIX] [<feature>] Generate` or `[PREFIX] Generate` | WHY: Generate specification from minimal input. WHAT: Created `spec.md` with [describe what was generated]. | Ran `/speckit-generate`, verified spec.md exists with generated content. |
| `after_scan` | `[PREFIX] [<feature>] Scan` or `[PREFIX] Scan` | WHY: Detect project stack and frameworks. WHAT: Created/updated `scan-profile.json` with detected languages and frameworks. | Ran `/speckit-scan`, verified scan-profile.json exists with detection results. |
| `after_setup` | `[PREFIX] [<feature>] Setup` or `[PREFIX] Setup project configuration` | WHY: Bootstrap project-specific configuration after init. WHAT: Created/updated project-context.md, verification commands, constitution.md, and scan profile. | Ran `/speckit-setup`, verified all setup artifacts exist. |

Each commit message includes:
- **Title**: Resolved prefix with feature name
- **Summary**: WHY (motivation) + WHAT (artifacts created/modified)
- **Test Plan**: Verification steps showing how artifacts were validated
- **Spec reference**: `Spec: specs/<feature>/spec.md` (except `after_constitution`)

## Hook Suppression

The `/speckit-setup` command orchestrates multiple sub-commands (`/speckit-scan`, `/speckit-constitution`) and wants to capture all their artifacts in a single `after_setup` commit rather than creating separate commits for each sub-command.

**Mechanism**: Setup creates a suppression marker file at `.specify/.suppress-sdd-commit` before invoking sub-commands. The marker is a JSON file containing a Unix timestamp:

```json
{"timestamp": <unix_epoch_seconds>, "created_by": "speckit-setup"}
```

When `speckit.sdd.commit` runs, it checks for this marker file. If the marker exists and is fresh (age < 3600 seconds / 60 minutes), the commit is suppressed — the command exits silently without creating a commit.

**Stale marker cleanup**: If the marker is older than 60 minutes (e.g., from a crashed or interrupted setup session), it is considered stale. The commit script removes the marker with a warning and proceeds with the commit normally. This prevents a stale marker from permanently blocking commits.

**Suppression is opt-in**: Sub-commands invoked standalone (outside of setup) do not have a suppression marker, so their `after_*` hooks fire normally and create commits as expected.

## Graceful Degradation

- If Sapling (`sl`) is not available: skips with a warning
- If no spec-related changes exist: skips silently
- If the commit script is missing: skips silently
- If the commit fails: warns but does not stop the parent workflow

## Benefits of Pre-Generating Metadata

By generating summary and test plan at commit time (instead of during diff creation):

1. **Context is fresh**: The changes and their rationale are still in working memory
2. **Streamlined diff creation**: Later `jf submit` can reuse the commit metadata without regeneration
3. **Consistent messaging**: Same summary/test plan in local commit and Phabricator diff
4. **Reduced diff workflow friction**: No need to re-analyze changes when creating the diff

When the user later runs `jf submit`, the commit message already contains Summary and Test Plan fields that Phabricator can parse directly.

## Scope

This command does NOT:
- Commit code changes (only `specs/` and `.specify/`)
- Submit Phabricator diffs (diff creation stays with existing `source-control-at-meta` skills)
- Create branches or bookmarks
- Modify existing commits (only creates new commits)
