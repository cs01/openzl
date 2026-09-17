---
name: speckit-tasks
description: 'SpecKit SDD pipeline: generate `specs/<feature>/tasks.md` from an existing SpecKit plan.'
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:meta
  meta_preset_strategy: replace
  meta_preset_upstream: speckit.tasks
user-invocable: true
disable-model-invocation: false
---



# Speckit Tasks Skill

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Workspace check (MANDATORY)**: Run `speckit run require-workspace.sh`. This resolves the workspace from any subdirectory and produces the same fixed message when there is no workspace above the current directory. On a non-zero exit, relay its stderr output to the user verbatim — do not paraphrase, reword, summarize, or translate it; do not prepend or append anything (no preface, heading, or attribution such as "require-workspace.sh failed:"); do not name the script, the command, the exit code, or any internal path — then halt. On exit 0, proceed silently to the next check.

**Pre-execution hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.before_tasks` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue. Wait for all hooks to complete before continuing.

**Model note**: This command is structured decomposition — Sonnet is sufficient. If you are running on Opus, let the user know they can switch to Sonnet (`/model sonnet`) for faster task generation without quality loss.

## Outline

This command breaks down your implementation plan into a structured task list — organizing work by user story, identifying parallel opportunities, and creating verification gates for each phase.

**Note**: This command is already non-interactive. The `--auto` flag is accepted but has no effect.

Before starting work, briefly tell the user what this stage does and why it matters. Print the introduction in bold.

**Output discipline**: Suppress routine setup narration — step numbers and variable bindings. Errors, warnings, interactive prompts, and the command's primary output are not routine narration and must still be shown.

1. **Setup**: Run `.specify/scripts/bash/check-prerequisites.sh --json` from repo root and parse FEATURE_DIR and AVAILABLE_DOCS list. All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

   `AVAILABLE_DOCS` lists optional docs only (e.g., `research.md`, `data-model.md`) — `plan.md`/`spec.md` are mandatory (see Required list below) and are read directly regardless of whether they appear in that list.

2. **Load design documents**: Read from FEATURE_DIR:
   - **Required**: plan.md (tech stack, libraries, structure), spec.md (user stories with priorities)
   - **Optional**: data-model.md (entities), contracts/ (interface contracts), research.md (decisions), quickstart.md (test scenarios)
   - Note: Not all projects have all documents. Generate tasks based on what's available.

   **Load project context**: Read `.specify/memory/project-context.md` if it exists.
   - If the file exists, parse `## FrameworkName` headings, **excluding** the reserved enrichment heading (`## Deep Research Enrichment`) from framework-heading enumeration. For each non-excluded section, extract lines under "When generating task checklists, include:" and add them as framework-specific checklist items in the task breakdown.
   - If the file does not exist, proceed without framework-specific checklist items.

   **Enrichment advisory consumption**: The `## Deep Research Enrichment` heading is excluded from framework-heading parsing above, but its prose content is still valuable as general advisory context.

   If `project-context.md` contains a `## Deep Research Enrichment` section, use its content as advisory background context during task breakdown generation. The enrichment describes project architecture, dependencies, configuration surfaces, and data flows as of the last `/speckit-setup` run — consider it a useful starting point that may be partially stale. Do not treat enrichment claims as authoritative facts or make enrichment content a required input to task output.

   **Load scan profile**: Read `.specify/memory/scan-profile.json` if it exists.
   - If the file exists and contains valid JSON with non-empty `test_infrastructure.targets`, use detected target patterns in verification gate tasks instead of generic commands.
   - If the file does not exist, proceed with default task generation.
   - If the file exists but cannot be parsed as valid JSON, log a warning ("Scan profile at .specify/memory/scan-profile.json is malformed — using default task generation") and proceed with defaults.

3. **Execute task generation workflow**:
   - Load plan.md and extract tech stack, libraries, project structure
   - If plan.md contains a **Task Dependencies** table with parallel groups, extract it — this table flows through to tasks.md so `/speckit-implement` can dispatch parallel agents
   - Load spec.md and extract user stories with their priorities (P1, P2, P3, etc.)
   - Parse the `complexity` field from spec.md's YAML frontmatter (same pattern as `risk` in `/speckit-clarify`). If the `complexity` field is absent or contains an unrecognized value, treat the spec as standard.
   - If the spec has `complexity: compact` in its YAML frontmatter:
     - Extract the single user story and organize tasks around it without generating phantom story groups.
     - Phase 3 is the only story-driven phase (no Phase 4+).
     - Note: "Compact spec — single-story task organization."
   - If data-model.md exists: Extract entities and map to user stories
   - If contracts/ exists: Map interface contracts to user stories
   - If research.md exists: Extract decisions for setup tasks
   - Generate tasks organized by user story (see Task Generation Rules below)
   - Generate dependency graph showing user story completion order
   - Create parallel execution examples per user story
   - Validate task completeness (each user story has all needed tasks, independently testable)

4. **Generate tasks.md**: Use `.specify/templates/tasks-template.md` as structure, fill with:
   - Correct feature name from plan.md
   - Phase 1: Setup tasks (project initialization)
   - Phase 2: Foundational tasks (blocking prerequisites for all user stories)
   - Phase 3+: One phase per user story (in priority order from spec.md)
   - Each phase includes: story goal, independent test criteria, tests (if requested), implementation tasks
   - Final Phase: Polish & cross-cutting concerns
   - All tasks must follow the strict checklist format (see Task Generation Rules below)
   - Clear project-relative file paths for each task
   - Dependencies section showing story completion order
   - Parallel execution examples per story
   - If a Task Dependencies table was extracted from the plan, include it verbatim under a `## Task Dependencies` heading — `/speckit-implement` reads this table to dispatch parallel agents across groups
   - Implementation strategy section (MVP first, incremental delivery)

5. **Report**: Output path to generated tasks.md and summary.

   Determine the successor obligation below, but do not display it yet — step 7 displays it after the post-completion hooks, so it is the last thing shown this turn:

   ➡️ **Successor obligation**: the next stage is `/speckit-implement`, optionally preceded by `/speckit-analyze`. Always name it as the recommended next step — do not substitute an ordering of your own, and do not recommend jumping ahead to a later stage.

   > **Context tip:** Task breakdown is saved to specs/<feature>/tasks.md. Run /speckit-analyze first to validate cross-artifact consistency, or go straight to /speckit-implement. Consider /clear before implement to free context for code exploration.

   Include:
   - Total task count
   - Task count per user story
   - Parallel opportunities identified
   - Independent test criteria for each story
   - Suggested MVP scope (typically just User Story 1)
   - Format validation: Confirm ALL tasks follow the checklist format (checkbox, ID, labels, file paths)

   **Artifact summary:**

   | Artifact | Path |
   |----------|------|
   | Task breakdown | `specs/<feature>/tasks.md` |

6. **Post-completion hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.after_tasks` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`) — if a mandatory hook's invocation fails or terminates abnormally, halt with "`<stage>` completed but the follow-up step failed — re-run `/<command>` to retry" (a hook returning a result, including a blocking one, is a successful dispatch, not a failure); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue.

7. **🔁 Display next-step guidance (ALWAYS RUN — DO NOT OMIT)**: Now that the hook(s) in step 6 have finished executing, display the ➡️ **Successor obligation** line (and Context tip) from step 5. This is the only time it is shown, and it must be the last thing shown to the user this turn.

Context for task generation: $ARGUMENTS

The tasks.md should be immediately executable - each task must be specific enough that an LLM can complete it without additional context.

## Task Structure

The Task Generation Rules, Checklist Format, Task Efficiency, and Parallel Marker Validation sections below are the methodology for creating tasks. Do not delegate to external skills. Each task must specify: the exact file to create/modify, the acceptance criteria, and estimated scope.

## Task Generation Rules

**CRITICAL**: Tasks MUST be organized by user story to enable independent implementation and testing.

**Tests**: Follow the spec's `## Testing Strategy` section for test generation. If no Testing Strategy exists, tests are optional unless explicitly requested. Note: Meta Verification Gates (below) run *existing* tests via `arc unit` — they do not generate new test tasks.

### Checklist Format (REQUIRED)

Every task MUST strictly follow this format:

**Simple tasks** (<150 chars):
```text
- [ ] TaskID [P?] [Story?] Description with file path
```

**Complex tasks** (≥150 chars):
```text
- [ ] TaskID [P?] [Story?] Short description
  **File**: path/to/file
  **Action**: Detailed description
  **Acceptance**: What "done" looks like — see Acceptance Criteria Quality below
```

**Format Components**:

1. **Checkbox**: ALWAYS start with `- [ ]` (unchecked) — use `- [x]` when marking complete
2. **Task ID**: Sequential number (T001, T002, T003...) in execution order
3. **[P] marker**: Include ONLY if task is parallelizable. A task is parallelizable when it meets ALL of these conditions: (a) it modifies different files than every other `[P]` task in the same phase, (b) it has no data dependency on incomplete tasks, (c) no other `[P]` task in the same phase creates a file this task modifies. If two tasks share ANY file in their `**File**:` fields, they MUST be sequential (no `[P]`).
4. **[Story] label**: REQUIRED for user story phase tasks only
   - Format: [US1], [US2], [US3], etc. (maps to user stories from spec.md)
   - Setup phase: NO story label
   - Foundational phase: NO story label
   - User Story phases: MUST have story label
   - Polish phase: NO story label
5. **Description**: Clear action with exact project-relative file path (or multi-line fields for complex tasks). Never write absolute checkout paths — use paths relative to the project root (e.g., `src/models/user.py`, not `/data/repos/fbsource/src/models/user.py`).

**Examples**:

✅ CORRECT (simple):
```
- [ ] T001 Create project structure per implementation plan
- [ ] T005 [P] Implement authentication middleware in src/middleware/auth.py
- [ ] T012 [P] [US1] Create User model in src/models/user.py
```

✅ CORRECT (complex):
```
- [ ] T020 [P] [US2] Add validation to User model
  **File**: src/models/user.py
  **Fields**: email (unique), hashed_password, created_at, is_active
  **Validation**: Email format check, password min length 8 chars
  **Acceptance**: All validators pass, unique constraint enforced
```

❌ WRONG:
```
- [ ] Create User model  (missing Task ID)
T001 [US1] Create model  (missing checkbox)
- [ ] [US1] Create User model  (missing Task ID)
- [ ] T001 [US1] Create model  (missing file path)
```

### Task Description Formatting

When generating task descriptions, apply these formatting rules:

**Simple tasks** (short description, single file, obvious action):
- Use single-line format: `- [ ] T001 [P?] [Story?] Description with file path`

**Complex tasks** (detailed steps, multiple concerns, or >150 chars):
- Use multi-line format with bulleted **Action** field
- Break **Action** into bullet points (one per discrete step)
- If 5+ methods/functions, nest them as sub-bullets
- If multiple test scenarios, list each as a bullet in **Tests** field
- Use 2-space indentation for sub-bullets

**Multi-file tasks**:
- Use **Files**: (plural) with bulleted list instead of single **File**: line
- List each file on its own bullet with brief role description

**Before** (run-on paragraph — hard to scan):
```
- [ ] T020 [US2] Implement auth service
  **File**: src/services/auth.py
  **Action**: Hash passwords using bcrypt with salt rounds 12, generate JWT tokens with 24h expiry, implement token refresh endpoint, add rate limiting of 5 login attempts per 15min window
```

**After** (bulleted — scannable and actionable):
```
- [ ] T020 [US2] Implement auth service
  **File**: src/services/auth.py
  **Action**:
  - Hash passwords using bcrypt (salt rounds: 12)
  - Generate JWT tokens with 24h expiry
  - Implement token refresh endpoint
  - Add rate limiting: 5 login attempts per 15min
```

### Task Organization

1. **From User Stories (spec.md)** - PRIMARY ORGANIZATION:
   - Each user story (P1, P2, P3...) gets its own phase
   - Map all related components to their story:
     - Models needed for that story
     - Services needed for that story
     - Interfaces/UI needed for that story
     - If tests requested: Tests specific to that story
   - Mark story dependencies (most stories should be independent)

2. **From Contracts**:
   - Map each interface contract → to the user story it serves
   - If tests requested: Each interface contract → contract test task [P] before implementation in that story's phase

3. **From Data Model**:
   - Map each entity to the user story(ies) that need it
   - If entity serves multiple stories: Put in earliest story or Setup phase
   - Relationships → service layer tasks in appropriate story phase

4. **From Setup/Infrastructure**:
   - Shared infrastructure → Setup phase (Phase 1)
   - Foundational/blocking tasks → Foundational phase (Phase 2)
   - Story-specific setup → within that story's phase

### Phase Structure

- **Phase 1**: Setup (project initialization)
- **Phase 2**: Foundational (blocking prerequisites - MUST complete before user stories)
- **Phase 3+**: User Stories in priority order (P1, P2, P3...)
  - Within each story: Tests (if requested) → Models → Services → Endpoints → Integration
  - Each phase should be a complete, independently testable increment
- **Final Phase**: Polish & Cross-Cutting Concerns

### Meta Verification Gates

Every implementation phase MUST end with a verification gate task that runs the project's verification commands on all files modified in that phase. Verification commands are sourced from (in priority order):
1. Project's CLAUDE.md verification commands section
2. `.specify/memory/verification-commands.md` if it exists
3. Fallback defaults: `arc f` + `arc lint -a` + `arc unit`

Format: `- [ ] TXXX Verify phase N: run verification commands on all modified files`

### Acceptance Criteria Quality

Acceptance criteria must match the *kind* of change the task performs:

- **Structural tasks** (create file, add field, wire hook): acceptance is binary — "file exists with X," "test passes," "hook fires." Absence-of-bad checks work: "no lint errors," "no type errors."
- **Qualitative tasks** (improve output, rewrite prompts, enhance UX): acceptance must require *producing new content that meets a stated quality bar* — not just passing absence-of-bad checks. "No internal names in output" passes when zero improvements are made. Instead: "output instructions use natural language describing what happened and what it means" or "each error message states the problem, its cause, and what the user should do."

When the plan provides a before/after exemplar for qualitative work, reference it in the acceptance criteria: "Matches the depth of change shown in the plan's exemplar."

### Task Efficiency

Tasks are optimized for agent execution speed and token efficiency:

- **Batch similar operations.** When the same pattern applies to multiple files, emit one task — not N separate tasks. "Add flag parsing to all 12 commands" is one task, not twelve.
- **Combine implementation and tests.** Each task includes its corresponding test updates. Never emit separate "add test for X" tasks.
- **Target 10–20 tasks for a medium feature.** Excessive decomposition (50+ tasks) causes context compaction cascades. Prefer logical grouping over per-file granularity.
- **Front-load reference reads.** Include one orientation task to read contracts and reference files before implementation tasks.

### Parallel Marker Validation

After generating all tasks, validate `[P]` markers before writing tasks.md:

1. For each phase, collect all tasks marked `[P]`
2. Extract the `**File**:` field from each `[P]` task (for simple tasks, extract the file path from the description)
3. If any two `[P]` tasks in the same phase share a file path, remove `[P]` from the later task and add a note in the Task Dependencies table explaining the sequential dependency
4. If a `[P]` task's file is created by a preceding non-`[P]` task in the same phase, remove `[P]`

This validation catches the common error of marking tasks as parallel when they modify the same file.
