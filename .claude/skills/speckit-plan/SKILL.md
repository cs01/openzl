---
name: speckit-plan
description: 'SpecKit SDD pipeline: generate `specs/<feature>/plan.md` from an existing SpecKit spec.'
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:meta
  meta_preset_strategy: replace
  meta_preset_upstream: speckit.plan
user-invocable: true
disable-model-invocation: false
---



# Speckit Plan Skill

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Workspace check (MANDATORY)**: Run `speckit run require-workspace.sh`. This resolves the workspace from any subdirectory and produces the same fixed message when there is no workspace above the current directory. On a non-zero exit, relay its stderr output to the user verbatim — do not paraphrase, reword, summarize, or translate it; do not prepend or append anything (no preface, heading, or attribution such as "require-workspace.sh failed:"); do not name the script, the command, the exit code, or any internal path — then halt. On exit 0, proceed silently to the next check.

**Pre-execution hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.before_plan` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue. Wait for all hooks to complete before continuing.

**Model note**: This command is research and synthesis — Sonnet is sufficient. If you are running on Opus, let the user know they can switch to Sonnet (`/model sonnet`) for faster planning without quality loss. The adversarial *review* agents benefit from Opus; the *planning* command does not.

## Outline

This command generates your implementation plan from the spec — resolving HOW decisions, creating a phased architecture, and defining the file structure and dependencies for your feature.

**Note**: The `--auto` flag auto-resolves HOW exploration gaps with informed guesses annotated with `[AUTO-RESOLVED: <reasoning>]` instead of asking the user.

Before starting work, briefly tell the user what this stage does and why it matters. Print the introduction in bold.

**Output discipline**: Suppress routine setup narration — step numbers, variable bindings, file reads, and scan-profile parsing. Errors, warnings, interactive prompts, research progress milestones, and the completed plan are not routine narration and must still be shown.

1. **Setup**: Run `.specify/scripts/bash/setup-plan.sh --json` from repo root and parse JSON for FEATURE_SPEC, IMPL_PLAN, SPECS_DIR, BRANCH, PREV_PLAN. Also parse `--auto` and `--skip-review` flags from user input. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Load context**: Read FEATURE_SPEC and `.specify/memory/constitution.md`. If the constitution file contains the sentinel `<!-- speckit:constitution:placeholder -->`, it is an unconfigured placeholder — skip reading it entirely and treat it as absent for all downstream references (including the "constitution compliance" Plan Review dimension). Load IMPL_PLAN template (already copied). Check for review findings: if `review/review-findings.md` exists in the same directory as FEATURE_SPEC, read it. Implementation-detail recommendations from the review step belong in the plan, not the spec.

   **Parse spec complexity**: Parse the `complexity` field from FEATURE_SPEC's YAML frontmatter. If the spec has `complexity: compact` in its YAML frontmatter, note "Compact spec detected — adjusting scope assessment." If the `complexity` field is absent or contains an unrecognized value, treat the spec as standard.

   **Load previous plan** (if PREV_PLAN is non-empty): Read PREV_PLAN as advisory context. The previous plan contains design decisions, implementation details (function signatures, state management, test cases), and structural choices from the prior iteration. Use it to:
   - **Preserve settled decisions**: If the previous plan resolved a HOW question (e.g., chose a data structure, defined a function decomposition), carry it forward unless the updated spec or review findings invalidate it.
   - **Refine rather than restart**: Use the previous plan's structure as a starting point. Add, modify, or remove sections based on spec/review changes — don't re-derive from scratch.
   - **Detect invalidations**: If the spec changed in ways that conflict with the previous plan's decisions (e.g., new requirements that break an assumption, removed features that eliminate a module), note the change and update accordingly.
   - The previous plan is advisory, not authoritative — the current spec and review findings take precedence on any conflict.

   **Extract HOW context** from two sources for the exploration step:
   - **Design Context for Planning**: Read from `exploration.md` (in the same directory as FEATURE_SPEC) if it exists, extracting the `## Design Context for Planning` section content. If `exploration.md` does not exist, fall back to reading `## Design Context for Planning` from FEATURE_SPEC (spec.md). Skip silently only if neither source has the section. This contains advisory HOW hints captured during specification exploration.
   - From the review findings file (if present): extract Plan-deferred findings (marked with DT-### codes). These are HOW decisions deferred from the review stage.

   **Plan-deferred finding incorporation**: If the review findings file contains a `### PLAN-DEFERRED` section, treat each finding as a concrete implementation requirement. For each Plan-deferred finding: read its recommendation, then incorporate it into the appropriate plan section (e.g., a finding about heading structure → plan's template modification steps; a finding about marker syntax → plan's output format specification; a finding about vocabulary values → plan's contract definitions). Plan-deferred findings represent implementation details that the spec intentionally excluded to maintain WHAT/WHY purity — the plan is where these details become concrete.

   **Load scan profile**: Read `.specify/memory/scan-profile.json` if it exists.
   - If the file exists and contains valid JSON, parse `test_infrastructure` and `frameworks`. Use these to customize the plan:
     - If `test_infrastructure.targets` is non-empty: use the detected target types (e.g., `python_unittest`, `cpp_unittest`) to generate concrete `buck2 test` commands in the plan's verification steps instead of generic placeholders. For example, if targets include `python_unittest`, verification steps should use `buck2 test fbcode//path/to:test_target` patterns.
     - If `test_infrastructure.directories` is non-empty: reference detected test directories (e.g., `tests/unit/`, `__tests__/`) in the project structure section of the plan.
     - If `frameworks` contains Ent-related entries: note Ent migration requirements in the plan's technical context.
   - If the file does not exist, proceed with default plan generation — no warning, no error.
   - If the file exists but cannot be parsed as valid JSON, log a warning and proceed with defaults.

   **Load project context**: Read `.specify/memory/project-context.md` if it exists.
   - If the file exists, read its full content. Use the entire file as advisory background context during implementation step generation (whole-file mode — plan does not parse framework headings).
   - If the file does not exist, proceed without enrichment context — no warning, no error.

   If `project-context.md` contains a `## Deep Research Enrichment` section, use its content as advisory background context during implementation step generation. The enrichment describes project architecture, dependencies, configuration surfaces, and data flows as of the last `/speckit-setup` run — consider it a useful starting point that may be partially stale. Do not treat enrichment claims as authoritative facts or make enrichment content a required input to plan output.

3. **Explore HOW gaps**: Before proceeding to research, evaluate whether the spec and review findings have already established HOW decisions (architectural approach, data flow, major tradeoffs), or whether significant gaps remain.

   **Load pre-established HOW context** (from step 2):
   - Design Context hints from `exploration.md` (or spec.md fallback) `## Design Context for Planning` section
   - Plan-deferred findings from review findings file (DT-### codes)

   **Evaluate HOW gaps**: Do significant HOW decisions remain unresolved? Examples of HOW gaps:
   - Architectural approach unclear (client-side vs. server-side, monolith vs. microservices, synchronous vs. asynchronous)
   - Data flow undefined (where data is stored, how it flows between components, caching strategy)
   - Major tradeoffs unresolved (performance vs. maintainability, flexibility vs. simplicity)
   - Technology choices unmotivated (why X instead of Y)

   **Short-circuit** (when HOW context is sufficient):
   If the Design Context and review findings already cover key HOW decisions — architecture approach selected, major tradeoffs resolved, data flow defined — state: "No significant HOW gaps. Proceeding to research and design." Skip to step 4.

   **Interactive exploration** (when HOW gaps exist and `--auto` flag is NOT present):
   - Present pre-established HOW context alongside remaining gaps
   - Ask one HOW question at a time
   - When genuine alternatives exist, propose 2-3 approaches with their tradeoffs (e.g., "Approach A: client-side validation — fast feedback, but duplicates logic. Approach B: server-side only — single source of truth, but slower UX.")
   - Prefer multiple choice when alternatives are discrete; include a freeform text option and a "let's discuss" escape hatch for questions where the user wants to explore before choosing
   - Apply convergence pattern: no checkpoint before 2 questions; after 8-10 questions, strongly recommend proceeding unless user identifies new gap areas
   - On session interruption: proceed with gathered context, annotate remaining gaps with `[EXPLORATION-INCOMPLETE: gap not explored]`

   **Auto mode** (when `--auto` flag IS present):
   - Auto-resolve HOW gaps with informed guesses drawn from project context (loaded constitution, CLAUDE.md, scan profile, existing architecture patterns)
   - Annotate each resolution with `[AUTO-RESOLVED: <reasoning>]` explaining the inference basis
   - No user interaction
   - Example: `[AUTO-RESOLVED: client-side validation chosen based on existing pattern in XYZ module]`

   **Conflict detection**:
   If HOW exploration reaches a conclusion that contradicts the spec's requirements or Design Context hints (e.g., makes a requirement infeasible, unnecessary, or semantically different), surface the contradiction:
   - **Interactive mode**: Ask user how to proceed. Example: "The spec requires offline support, but the HOW exploration suggests this is infeasible because the feature depends on real-time server data. How should we proceed: (A) remove offline requirement, (B) add local data sync, (C) other?"
   - **Auto mode**: Log the conflict (`[CONFLICT DETECTED: <description>]`), but proceed with spec requirements taking precedence over HOW conclusions. Document the conflict in `research.md` under its Design Decisions (the canonical home for HOW decisions and their rationale; `plan.md` references research.md rather than inlining decisions).

   **Concrete examples**:

   **Example 1 — HOW exploration dialog**:

   ```
   Agent: I've reviewed the Design Context and review findings. Two HOW gaps remain:

   Pre-established HOW context:
   - Design Context suggests "Redis for caching" (captured during spec exploration)
   - Plan-deferred review finding: "Consider worker queue for async processing"

   Remaining gaps:
   1. How should errors be surfaced to users? (UI toast vs. inline validation vs. error page)
   2. How should the cache be invalidated? (TTL vs. event-driven vs. manual)

   Let's resolve gap 1 first. How should errors be surfaced?

   A) UI toast notifications — non-blocking, but can be missed
   B) Inline validation — immediate feedback, but clutters UI
   C) Dedicated error page — clear messaging, but interrupts flow

   User: B

   Agent: Inline validation it is. Now for gap 2: cache invalidation strategy?

   A) TTL-based (5min expiry) — simple, but may serve stale data
   B) Event-driven (invalidate on writes) — always fresh, but more complex
   C) Manual (admin tool) — full control, but requires manual intervention

   User: A

   Agent: Got it. All HOW gaps resolved. Proceeding to research and design.
   ```

   **Example 2 — Short-circuit scenario**:

   ```
   Agent: I've reviewed the Design Context and review findings:

   Pre-established HOW context:
   - Architecture: client-side SPA with REST API backend (Design Context)
   - Data flow: user → React form → API endpoint → database (Design Context)
   - Caching: Redis with 5min TTL (plan-deferred review finding)
   - Error handling: inline validation (Design Context)
   - Technology choice: TypeScript + React (project standard per CLAUDE.md)

   All key HOW decisions are established. No significant HOW gaps. Proceeding to research and design.
   ```

4. **Execute plan workflow**: Follow the structure in IMPL_PLAN template (loaded in step 2) to:
   - Fill Technical Context section in IMPL_PLAN. Include only observations that are novel, surprising, or load-bearing for design decisions in the plan. Omit fields whose values are directly derivable from the scan profile or project CLAUDE.md. A Technical Context section that restates known facts wastes the reviewer's attention. Mark genuine unknowns as "NEEDS CLARIFICATION"
   - **Change Overview** (conditional — non-greenfield only): If the plan modifies existing code or behavior (not a pure greenfield project), generate a `## Change Overview` section placed between the `---` separator (after Project Structure / Complexity Tracking) and `## Plan Flow` (or before the first `## Phase` heading if no Plan Flow is generated). Omit this section entirely for pure greenfield projects where there is no "before" state — never emit an empty heading. Content is a Markdown table with columns `Area | Before | After`, where each row describes a behavioral change — what the system does now versus what it will do after implementation. Each row should be scannable without spec knowledge — describe the behavioral shift in plain language, not method signatures or FR citations. Rows describe behavioral shifts, not file-level diffs (those belong in `## Project Structure`). Keep it concise: 3–8 rows covering the major changes a reviewer needs to understand.
   - Phase 0: Generate research.md (resolve all NEEDS CLARIFICATION). Before research, scan the spec's `## Premise Validation` section for conditional validation gates — look for language indicating prerequisites (e.g., "verify X before Y", "confirm X", "contingent on Y", "only if Z"). If any gates are found, surface them as Phase 0 steps that must be validated before proceeding to research. If the Premise Validation section is absent or contains no extractable gates, skip gate propagation silently.
   - Phase 1: Generate data-model.md, contracts/ (skip if the feature has no user-facing interface), and quickstart.md (greenfield projects only; for non-greenfield projects, check for an existing quickstart location — CLAUDE.md first, then README.md, then docs/, but not limited to these — and reference it in the plan if found; skip silently if no quickstart location is identifiable)

   **Constitution Review**: Write exactly: "Constitution compliance is evaluated by Plan Review (auto-triggered via `after_plan` hook). See `review/review-findings.md` for findings." Do not add alignment bullets or self-assessment — the review's Constitution Compliance agent runs its own analysis.

   **Complexity Tracking**: Omit the Complexity Tracking section entirely when there are no Constitution violations to justify. Do not write an empty table.

   **Plan-Phase Proportionality Check**: After generating the implementation plan and before reporting, check whether the plan's complexity is proportionate to the documented friction:

   1. **Read the spec's Premise Validation**:
      - If `exploration.md` exists (in the same directory as FEATURE_SPEC): read `## Premise Validation — Full Analysis` from exploration.md and extract `**Friction Evidence:**` and `**Verdict:**` fields.
      - Fallback: if `exploration.md` does not exist, read `## Premise Validation` from FEATURE_SPEC (spec.md) and extract the same fields. **Note**: this fallback works for old-format specs (pre-feature) which have structured `**Friction Evidence:**` / `**Verdict:**` fields. For new-format specs where exploration.md is somehow missing, spec.md contains only a 2-line verdict without `**Friction Evidence:**` — the proportionality check degrades gracefully (skips silently), consistent with existing malformed-section behavior.
      - If neither source has the section: skip the proportionality check silently.
      - **Malformed section handling**: If the section exists but `**Verdict:**` is missing or contains an unrecognized value (not one of `proceed`, `reduce scope`, or `cancel`), treat as if the section doesn't exist — skip the proportionality check and log a warning.

   2. **Assess plan complexity**:
      - Count the number of implementation steps/tasks in the plan
      - Count the number of diffs implied by the plan's structure
      - Note the overall scope (files modified, new files created)

   3. **Compare friction against complexity**:
      - This is a judgment call, not a formula. Flag when the ratio of implementation effort to friction seems obviously skewed.
      - Examples of disproportionality: 20+ tasks to save one manual command; 4+ diffs for convenience-level friction; complex infrastructure for a problem that affects <1% of usage.

   4. **Include proportionality assessment in the completion report** (step 6):
      - If proportionate: no special warning needed
      - If disproportionate: flag prominently with the evidence in the completion report:
        > ⚠️ **Proportionality warning**: The spec documents [friction level] friction ([friction description]) but this plan requires [N] tasks across [M] diffs. Consider reducing scope or re-evaluating whether the feature is worth the implementation cost.

   5. **Backward compatibility**: If the spec has no `## Premise Validation` section (specs created before this feature), skip the proportionality check silently. Do not error or warn about the missing section.

   6. **Advisory only**: The proportionality check is a recommendation, not a gate. The plan is always generated and reported regardless of the proportionality assessment.

4b. **PLAN-DEFERRED coverage check**: If the review findings file contains a `### PLAN-DEFERRED` section, verify each finding is addressed by at least one plan step using semantic topic matching:

   For each PLAN-DEFERRED finding:
   1. Extract the finding's topic (from title and description)
   2. Search plan steps for semantic overlap (step description covers same topic area)
   3. If addressed: log "✓ [Finding ID]: addressed by [step reference]"
   4. If not addressed: log "⚠ [Finding ID]: not addressed by any plan step"

   Include unaddressed findings as warnings in the completion report (step 6). This is advisory — unaddressed findings do not block plan generation. Plan Review provides an independent safety net for any gaps the coverage check misses.

5. **Write pipeline state**: After plan generation is complete, write the pipeline-state entry with metadata fields that Plan Review and downstream commands will read:

   ```bash
   speckit run write-pipeline-state.sh plan status=complete auto_mode=<bool> skip_review=<bool>
   ```

   Where:
   - `auto_mode`: set to `true` if `--auto` flag was present in user input (step 1), `false` otherwise
   - `skip_review`: set to `true` if `--skip-review` flag was present in user input (step 1), `false` otherwise

   **Note**: This explicit call provides metadata fields that Plan Review reads to determine whether to run primary review. The hook-based pipeline-state entry (from `after_plan` hook) does not include these fields.

   **If this call exits 4** (the `specify` prerequisite is unmet): Read and execute `.specify/templates/prerequisite-refusal-gate.md` instead of proceeding to step 6.

6. **Stop and report**: Plan output ends after Phase 1 design — proceed to step 7 for mandatory post-completion hooks.

   > **Context tip:** Your plan is saved to specs/<feature>/plan.md. Consider /clear before /speckit-tasks to free context for task breakdown.

   Report branch, IMPL_PLAN path, and generated artifacts.

   **Artifact summary:**

   | Artifact | Path |
   |----------|------|
   | Implementation plan | `specs/<feature>/plan.md` |
   | Research & decisions | `specs/<feature>/research.md` |
   | Data model (if applicable) | `specs/<feature>/data-model.md` |
   | Interface contracts (if applicable) | `specs/<feature>/contracts/*` |

   **Proportionality assessment**: If the proportionality check (above) flagged disproportionality, include the warning in the completion report here.

   ➡️ **Successor obligation**: the next stage after plan is the post-plan adversarial review (Plan Review); `/speckit-tasks` follows it. Never present `/speckit-tasks` as the immediate next step, and never recommend skipping the review on your own judgment of the plan's quality — whether to skip it is the user's call. How this is worded depends on the predicate outcome below; under `REVIEW2_UNKNOWN`, say nothing about Plan Review at all.

   **Review recommendation**: First, determine which of four outcomes applies to the `after_plan` hook — this must be the same script the Extension Hook Protocol uses to dispatch, or the report contradicts what actually happens next. Do not redirect or suppress this script's stderr (which propagates the dispatcher's own stderr on this call):

   ```bash
   speckit run plan-review2-predicate.sh
   ```

   If `.specify/scripts/bash/plan-review2-predicate.sh` is missing or unreadable, or produces no output or a token other than the four below, treat this the same as `REVIEW2_UNKNOWN` — say nothing about Plan Review in this section rather than guessing.

   **If `REVIEW2_AUTO` (a mandatory review-family hook is registered):**
   - Do NOT recommend running `/speckit-review` manually — it runs automatically
   - Include in the completion report:

     > Plan Review (post-plan adversarial review) will run automatically next. It evaluates the plan for **constitution compliance**, **correctness**, **coverage**, and **risk**, and its findings can block progress to `/speckit-tasks`.

   - Suppress **constitution compliance** from that sentence when `.specify/memory/constitution.md` does not exist or is an unconfigured placeholder (contains the sentinel `<!-- speckit:constitution:placeholder -->`) — the sentence then names the remaining three dimensions: **correctness**, **coverage**, and **risk**.
   - **Plan orientation** — when `auto_mode` (computed in step 5) is `false`, follow the dispatch notice with a bolded, unmissable invitation to read the plan while the review runs. Lead with a bold callout label (matching the `**Context tip:**` convention used elsewhere in this file) so it reads as a distinct call to action rather than a second line of the dispatch notice above it:

     > **Read this while Plan Review runs:** your plan is at `{IMPL_PLAN}` — {one-line summary drawn from the plan's `## Summary`}. It has {N} steps across {M} parallel groups and touches {K} files.

     Derive each count from the plan you just wrote: steps from `^### Step N` headings, parallel groups from rows in `## Task Dependencies`, files from entries under `### Source Code`, phases from `^#{2,3} Phase` headings. **Omit any count whose structure is absent from the plan — never fabricate one.** Do not look for a `## File Plan` section; no plan template defines it.
   - When `auto_mode` is `true`, suppress the entire orientation and emit the dispatch notice only.

   **If `REVIEW2_OFFERED` (an optional review-family hook is registered):**
   - Do NOT recommend running `/speckit-review` manually — it will be offered by the post-completion hook dispatch (step 7)
   - Include in the completion report:

     > You'll be offered Plan Review (post-plan adversarial review) after plan generation. It evaluates the plan for **constitution compliance**, **correctness**, **coverage**, and **risk**, and its findings can block progress to `/speckit-tasks` if you accept it.

   - Suppress **constitution compliance** from that sentence when `.specify/memory/constitution.md` does not exist or is an unconfigured placeholder (contains the sentinel `<!-- speckit:constitution:placeholder -->`) — the sentence then names the remaining three dimensions: **correctness**, **coverage**, and **risk**.
   - **Plan orientation** — same gating as `REVIEW2_AUTO` above: when `auto_mode` is `false`, follow the dispatch notice with the bolded reading invitation (same callout-label format); when `auto_mode` is `true`, suppress it.

   **If `REVIEW2_MANUAL` (no review-family hook registered):**

   > **Recommendation**: Plan Review will not run automatically. Run `/speckit-review` before `/speckit-tasks` to stress-test the plan's constitution compliance, correctness, coverage, and risk. Go straight to `/speckit-tasks` only if you choose to skip the plan review.

   **If `REVIEW2_UNKNOWN` (the dispatcher failed):**

   Say nothing about Plan Review in this section — no automatic, offered, or manual claim, since the actual outcome is unknown at this point. Do not fall back to the `REVIEW2_MANUAL` recommendation either, since a mandatory or optional hook may still fire once the dispatcher's transient failure clears. The post-completion hook dispatch (step 7) re-runs `hooks.after_plan` and surfaces the failure there.

7. **Post-completion hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.after_plan` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`) — if a mandatory hook's invocation fails or terminates abnormally, halt with "`<stage>` completed but the follow-up step failed — re-run `/<command>` to retry" (a hook returning a result, including a blocking one, is a successful dispatch, not a failure); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue.

## Phases

### Phase 0: Outline & Research

#### Short-Circuit: Existing Research Check

Before dispatching research agents, check whether existing project documentation already answers the research questions:

1. **Scan existing documentation:**
   - `CLAUDE.md` — project context, conventions, key concepts, and pointers to documentation directories
   - Documentation directories referenced by CLAUDE.md (design docs, architecture docs, etc.)
   - `.specify/memory/constitution.md` — project principles
   - The spec's `## Input Data` section (if present) — pre-identified files, docs, and artifacts from the specify stage. For `[test input]` handling, see Acceptance Test Inputs below

2. **For each "NEEDS CLARIFICATION" or research task:**
   - Search existing docs for answers before creating a research agent task
   - If an existing doc covers the topic, reference it in `research.md` with a pointer instead of re-researching. A doc "covers" a research question only when it supplies the concrete values the plan will use — field types, character constraints, exact file paths, method signatures, and API preconditions. A doc that names a field without stating its type constraint, or describes a fallback without naming the file that implements it, provides a lead, not an answer. Dispatch a targeted read for the missing values before short-circuiting.
   - Only dispatch research agents for genuinely unresolved questions

3. **If all research questions are answered by existing docs:**
   - Skip Phase 0 research agent dispatch entirely
   - Write `research.md` as a summary of existing findings with pointers to source docs
   - Proceed directly to Phase 1

#### Research (for unresolved questions only)

1. **Extract unknowns from the Technical Context section in IMPL_PLAN**:
   - For each NEEDS CLARIFICATION → research task
   - For each dependency → best practices task
   - For each integration → patterns task

2. **Generate and dispatch research agents**:

   ```text
   For each unknown in Technical Context:
     Task: "Research {unknown} for {feature context}"
   For each technology choice:
     Task: "Find best practices for {tech} in {domain}"
   ```

3. **Consolidate findings** in `research.md` using compressed format:
   - Each decision: **Decision** (what) + **Why** (1–2 sentences of rationale). Include **Alternatives rejected** only when the rejected approach is a foreseeable implementation mistake — something the implementer might try without this note. Omit Alternatives for decisions where the rejected path is clearly inapplicable.
   - Omit "Method", "Premise-validation gates", and "Conflicts detected" sections when they would contain only "None", "N/A", or a list of files read. The Resolved Unknowns table at the end is always included — it serves as a quick index.

**Output**: research.md with all NEEDS CLARIFICATION resolved

### Phase 1: Design & Contracts

**Prerequisites:** `research.md` complete

1. **Extract entities from feature spec** → `data-model.md`:
   - Entity name, fields, relationships
   - Validation rules from requirements
   - State transitions if applicable
   - **Relationship diagram** (conditional — two or more related entities only): When `data-model.md` documents two or more entities with relationships between them, include an entity-relationship diagram in a `## Relationships` section using a ` ```text ` fence. Use Unicode box-drawing (`┌┐└┘─│`) for entity boxes and labeled arrows (`──▶`, `──*`) for relationships with cardinality. ≤80 columns, no color. Omit entirely for a single entity or when no relationships exist — never emit an empty heading or a diagram that restates a single entity's fields.
   - **State diagram** (conditional — entities with lifecycles only): When an entity has a lifecycle with distinct states and transitions, include a state diagram in a `## State Transitions` section using a ` ```text ` fence. Use the same box-drawing character set, with labeled edges for transition triggers. Omit entirely when the entity is stateless — retain the existing honest form (e.g., "None — detection is stateless.") when appropriate.

2. **Define interface contracts** (if the feature has a user-facing interface) → `/contracts/`:
   - Identify what interfaces the project exposes to users or other systems
   - Document the contract format appropriate for the project type
   - Examples: public APIs for libraries, command schemas for CLI tools, endpoints for web services, grammars for parsers, UI contracts for applications
   - Skip if the feature has no user-facing interface — refactors, config changes, library internals with no exposed interface. CLI scripts, internal APIs, async jobs, and internal web routes all have interfaces worth documenting. When the feature's interface status is ambiguous, check whether the interface crosses a file, system, or repository boundary. If it does, include a contract. If the interface is internal to a single class or module, document it in the relevant plan step instead.

   Create a standalone contract file when the interface crosses a repository or system boundary, has multiple consumers to enumerate, or has verification steps that `tasks.md` needs to reference independently. A contract may be inlined as a section of `plan.md` only when none of these criteria apply and it fits in a single table or under ~30 lines.

2b. **Check existing producer/consumer contracts** (distinct from step 2 — that step documents *new* interfaces this feature introduces; this step covers *existing* ones this feature changes): for any step that changes a contract other code depends on — the format of a file section, schema field, or shared data structure; the output shape or safety properties of a function being consolidated from multiple prior implementations into one; or a value passed from the changed logic into a system outside this plan's own file set (a log or telemetry call, an external service, another process) — identify every existing consumer and add an update step for each one whose assumptions the change would break. A change can be entirely correct against this feature's own spec and still silently break a consumer the spec never mentions.

3. **Validate file placement** (before finalizing the plan's Project Structure section): check whether the class types being introduced (daemons, framework base-class subclasses, CLI entry points, or other framework-integration points) are subject to known placement constraints. Check only context already loaded in step 2 — do not perform new codebase-wide scanning:
   1. `CLAUDE.md`'s directory-structure / file-organization conventions
   2. `.specify/memory/project-context.md`'s architecture section, if loaded
   3. Any lint-rule or build-convention documentation already surfaced in loaded context

   If a constraint is found, place the file accordingly in the Project Structure section. If a constraint is *suspected* but not confirmed by loaded context (e.g., the feature introduces a class type not covered by existing project docs), do not guess — flag it as a `NEEDS CLARIFICATION` in Technical Context or a research task in Phase 0, the same way other unknowns are handled.

If the spec has `complexity: compact` in its YAML frontmatter:
- Skip entity extraction for data-model.md if no Key Entities section exists — note "No Key Entities in compact spec; data-model.md skipped."
- If the Success Criteria section is present, use it in scope assessment normally. If absent, consult the Verification Notes section as the alternative source of verification criteria and adjust scope assessment without penalizing the spec for the omission.
- The plan should still be proportionate — compact specs typically produce simpler plans.

**Output**: data-model.md, /contracts/* (skip if feature has no user-facing interface), quickstart.md (greenfield only; non-greenfield references existing quickstart location if found, skips silently otherwise)

## Plan Structure

When generating the implementation plan, decompose the feature using the existing Outline, Phase, and Parallelization sections defined in this command. The structure you've already built (Phase 0: Outline & Research, Phase 1: Design & Contracts) IS the decomposition methodology.

**Phase identification heuristics:**
- Group by logical concern — separate phases for data model, API layer, UI layer, infrastructure
- Each phase should be independently verifiable — can you test/validate the phase output before starting the next phase?
- Phases should reflect major architectural boundaries, not arbitrary work splits

**Step sizing heuristics:**
- Coarser than individual tasks (a step maps to one parallel group in the Task Dependencies table)
- Finer than "do the whole feature" (each step should have clear completion criteria)
- Each step typically produces one or more named artifacts (files, configs, test outputs)
- Steps within a phase can often run in parallel if they touch different files with no data dependency

**Qualitative vs. structural changes:** When a spec's FRs require improving the quality of human-readable output — error messages, user-facing prompts, agent instructions, LLM prompts, documentation, CLI output — the plan MUST frame these as **rewrite tasks** with before/after exemplars, not **audit tasks** that check for violations. The distinction matters:
- *Structural change* (add a field, wire a hook, create a file): acceptance is binary — the thing exists or it doesn't. "Audit for missing X" is the right decomposition.
- *Qualitative change* (improve output clarity, add behavioral instructions, rewrite prompts): the current content isn't broken, it's insufficient. "Audit for violations" finds nothing wrong and produces no improvement. The plan must instead: (1) include a concrete before/after exemplar for one representative item showing the expected depth of change, and (2) generate acceptance criteria that require producing new content meeting a stated quality bar, not just passing absence-of-bad checks.

The plan output MUST conform to the Phase 0/Phase 1 artifact structure defined in this document (research.md, data-model.md, contracts/). Plan steps are implementation phases that will be converted to checklist tasks by `/speckit-tasks`. Plan output ends at "stop and report" (Outline step 6) — proceed to step 7 for mandatory post-completion hooks.

### Acceptance Test Inputs

If the spec's `## Input Data` section contains entries annotated with `[test input]`, include an acceptance test step in the plan for each one. These are documented case studies, failure analyses, or baseline artifacts that the specify stage identified as validation data. The plan step should describe how to use the test input to verify the feature works as intended — e.g., "Run `/speckit-plan` on `specs/001-your-feature/spec.md` and verify the proportionality check flags the disproportion."

### Parallelization

Actively identify steps that can run in parallel and group them in a **Task Dependencies** table. Downstream commands (`/speckit-tasks`, `/speckit-implement`) use this table to dispatch parallel agents. Place the Task Dependencies table at the end of plan.md (after Complexity Tracking) and prefix it with:

> *This section is consumed by downstream pipeline stages (`/speckit-tasks`, `/speckit-implement`) and is not part of the review surface.*

Parallelization rules:
- Steps that touch **different files** with **no data dependency** belong in the same parallel group
- **Before finalizing a parallel group**, check whether any step's described implementation (pseudocode, method calls, class/interface references) invokes a symbol — a class, function, or interface — that another candidate-parallel step defines or creates. If so, the referencing step depends on the defining step and must be sequenced after it, **regardless of file overlap**. File-level independence is necessary but not sufficient for parallelizability.
- Steps that produce artifacts consumed by later steps are sequential group boundaries
- Research agents (Phase 0) should always run in parallel when there are multiple unknowns
- Test updates for independent test files can parallelize
- The final verification step is always sequential (depends on all prior groups)

Format:

```markdown
| Group | Steps | Can Parallelize | Notes |
|-------|-------|-----------------|-------|
| 1 | Steps 1, 2 | Yes | Independent file creates |
| 2 | Step 3 | No | Depends on Group 1 output |
```

**Example — file-independent but symbol-coupled**: Step 3 creates an `OrderValidator` class in `validation/order_validator.py`. Step 4 creates a `submit_order` handler in `handlers/submit_order.py` whose pseudocode calls `OrderValidator.validate()`. The two steps touch different files, but Step 4 depends on the symbol Step 3 defines — they belong in sequential groups, not the same parallel group:

```markdown
| Group | Steps | Can Parallelize | Notes |
|-------|-------|-----------------|-------|
| 1 | Step 3 | No | Defines `OrderValidator` |
| 2 | Step 4 | No | Calls `OrderValidator.validate()` from Step 3 — sequential despite touching a different file |
```

### Plan Flow Diagram

After all phases and the Task Dependencies table are complete, assess whether a Plan Flow diagram would help a reviewer understand the plan's shape. Generate a `## Plan Flow` section if the plan has more than one phase, OR more than five steps. Place it right after `## Change Overview` when present, or right after the `---` separator (after metadata sections) if no Change Overview was generated. It appears right before the first `## Phase` heading. Omit this section entirely for simple plans — never emit an empty heading.

Format: a ` ```text ` fence, ≤80 columns, no color, using Unicode box-drawing (`┌┐└┘─│▼→┬├`). The diagram uses nested boxes: each implementation phase is a named outer box (use conceptual names like "Foundation", "Core", "Integration" — not "Diff 1/2/3"), and each step is an inner box within its phase. Steps flow left-to-right with `→` arrows. Parallel steps share a single inner box and fork/rejoin with `─┐`/`─┘` connectors. Pre-implementation phases (Research, Design) sit above as an unbounded preamble with parenthetical labels. Phase boxes connect vertically with `│` and `▼` to show the dependency chain.

Each step gets a 1–3 word label derived from its `### Step N` heading, making the diagram self-contained without a separate legend.

The example below illustrates the format only — phase names, step counts, step labels, and the number of outer boxes will differ for each plan.

````text
Research (resolve unknowns) → Design (data model + contracts)
       │
┌─ Foundation ─────────────────────────────────────────────┐
│ ┌────────────┐   ┌────────────┐   ┌──────────────┐      │
│ │ Step 1     │ → │ Step 2     │ → │ Step 3       │      │
│ │ data model │   │ validation │   │ tests+verify │      │
│ └────────────┘   └────────────┘   └──────────────┘      │
└──────────────────────────────────────────────────────┬───┘
                                                       │
┌─ Core ──────────────────────────────────────────────▼───┐
│ ┌─────────────┐   ┌────────────────┐   ┌──────────────┐ │
│ │ Step 4      │ → │ Step 5         │ → │ Step 6       │ │
│ │ API handler │   │ auth layer     │   │ tests+verify │ │
│ └─────────────┘   └────────────────┘   └──────────────┘ │
└──────────────────────────────────────────────────────┬───┘
                                                       │
┌─ Integration ───────────────────────────────────────▼───┐
│ ┌────────────┐                                          │
│ │ Step 7     │─┐   ┌───────────┐   ┌──────────────┐    │
│ │ docs       │ ├─→ │ Step 9    │ → │ Step 10      │    │
│ │ Step 8     │─┘   │ migration │   │ wiring+verify│    │
│ │ config     │     └───────────┘   └──────────────┘    │
│ └────────────┘                                          │
└─────────────────────────────────────────────────────────┘
````

## Verification Commands

Include the project's verification commands as verification steps in the plan:
- First, check the project's CLAUDE.md for a verification commands section (heading containing "Verification Commands" or similar)
- If not found, check `.specify/memory/verification-commands.md`
- If neither exists, use fallback defaults: `arc f` (format) + `arc lint -a` (lint + autofix) + `arc unit` (tests)

## Key Rules

- Use absolute paths for filesystem operations; use project-relative paths for references in documentation and agent context files
- ERROR on gate failures or unresolved clarifications
- Do NOT update `<!-- SPECKIT START -->` / `<!-- SPECKIT END -->` markers in the agent context file. Feature discovery is handled by `check-prerequisites.sh --json` via `.specify/feature.json`, and `specs/` directory naming is self-documenting.
- If the review gate file exists (`review/review-gate.json`, or `review-gate.json` at the feature-dir root for older specs) with `status: blocked`, present graduated gate options:
  ```
  Review gate is blocked — unresolved MUST-ADDRESS findings remain.

  Options:
  1. **Fix now** — Address findings in the review findings file and re-run `/speckit-review`.
  2. **Override** — Proceed despite findings. Unresolved review findings may propagate to plan and implementation, requiring later rework.
  3. **Defer** — Exit now. To unblock, resolve the findings and re-run `/speckit-review`.
  ```
  - If **Fix now** or **Defer**: Exit with appropriate guidance.
  - If **Override**: Write override: `speckit run write-pipeline-state.sh review status=passed override=true`. Proceed to planning.
