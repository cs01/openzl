---
name: speckit-specify
description: 'SpecKit SDD pipeline: create or update `specs/<feature>/spec.md` from a feature description. Requires an initialized SpecKit project.'
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:meta
  meta_preset_strategy: replace
  meta_preset_upstream: speckit.specify
user-invocable: true
disable-model-invocation: false
---



# Speckit Specify Skill

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Workspace check (MANDATORY)**: Run `speckit run require-workspace.sh`. This resolves the workspace from any subdirectory and produces the same fixed message when there is no workspace above the current directory. On a non-zero exit, relay its stderr output to the user verbatim — do not paraphrase, reword, summarize, or translate it; do not prepend or append anything (no preface, heading, or attribution such as "require-workspace.sh failed:"); do not name the script, the command, the exit code, or any internal path — then halt. On exit 0, proceed silently to the next check.

**Pre-execution hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.before_specify` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue. Wait for all hooks to complete before continuing.

**Model note**: Opus recommended for design exploration quality. If not running on Opus, suggest switching with `/model opus`.

## Outline

This command creates your feature specification through interactive exploration — discovering requirements, edge cases, and design context to produce a complete, testable spec.

Given the feature description from User Input above, do this:

Before starting work, briefly tell the user what this stage does and why it matters. Print the introduction in bold.

**Output discipline**: Suppress routine setup narration — step numbers, variable bindings, file reads, and scan-profile parsing. Errors, warnings, exploration progress, interactive prompts, and the completed spec are not routine narration and must still be shown.

1. **Load project context**: Without project context, exploration and spec generation operate in a vacuum. Before either begins, load context to ground the exploration in what already exists.

   **Progress message**: Before loading context, emit a user-facing progress message: "Exploring project context to inform the specification..."

   1. **Read CLAUDE.md** from the project root. Extract project context relevant to the feature.

   2. **Follow CLAUDE.md pointers to existing documentation** — if CLAUDE.md references documentation directories (design docs, architecture docs, etc.), scan those for files relevant to the feature. Read up to 5 files whose names appear relevant. Do NOT read every file.

   3. **Read `.specify/memory/constitution.md`** if it exists — project principles and spec conventions that must be respected. If the file contains the sentinel `<!-- speckit:constitution:placeholder -->`, it is an unconfigured placeholder — skip reading it entirely and do not use its content as context for spec generation.

   4. **Load scan profile**: Read `.specify/memory/scan-profile.json` if it exists.
      - If the file exists and contains valid JSON, parse the `test_infrastructure` object. Use this to include test infrastructure context when generating the spec (step 7).
      - If the file does not exist, proceed with default template sections — no warning, no error.
      - If the file exists but cannot be parsed as valid JSON, log a warning ("Scan profile at .specify/memory/scan-profile.json is malformed — using default template sections") and proceed with defaults.

   5. **Load project-context.md**: Read `.specify/memory/project-context.md` if it exists.
      - If the file exists, parse `## FrameworkName` headings, **excluding** the reserved enrichment heading (`## Deep Research Enrichment`) from framework-heading enumeration. For each non-excluded section found, include a framework-specific subsection under Functional Requirements using the section's content as prompting context. If the section contains a `<!-- Subsection heading: ### ... -->` comment, use that heading; otherwise derive a heading from the framework name.
      - If the file does not exist, proceed without framework-specific subsections — no warning, no error.

      **Enrichment advisory consumption**: The `## Deep Research Enrichment` heading is excluded from framework-heading parsing above, but its prose content is still valuable as general advisory context.

      If `project-context.md` contains a `## Deep Research Enrichment` section, use its content as advisory background context during exploration and spec generation. The enrichment describes project architecture, dependencies, configuration surfaces, and data flows as of the last `/speckit-setup` run — consider it a useful starting point that may be partially stale. Do not treat enrichment claims as authoritative facts or make enrichment content a required input to spec output.

2. **Explore intent**: Clarify the feature's WHAT (capabilities, behaviors, outcomes) and WHY (problems solved, friction removed) through inline adaptive exploration:

   **Exploration Scope — WHAT/WHY Only**:
   - **WHAT**: Capabilities, behaviors, user-facing outcomes, acceptance criteria
   - **WHY**: Problems solved, friction removed, value delivered, constraints respected
   - **NOT HOW**: Implementation details, tech stack choices, architectural patterns belong in `/speckit-plan`

   1. **Present interpretation + gaps checkpoint**:
      - Show your understanding of the feature: "Based on your description, I understand this feature as: [1-2 sentence interpretation of WHAT and WHY]"
      - List WHAT/WHY gaps you've identified: "I have questions about: [list the gap topics]"
      - Ask: "Do you want to (a) explore these, (b) skip exploration and let me fill in the gaps with my best guesses (marked as assumptions in the spec), or (c) dismiss them as not applicable?"
      - If user says "just proceed" / "skip" / "use defaults" (option b): skip the exploration dialog (items 2-3 below) and make informed guesses annotated with `[USER-SKIPPED: informed guess based on <source>]`. Do NOT jump directly to step 3 — continue below to the Scope checkpoint and Complexity Assessment, using these informed guesses and your initial interpretation above in place of dialog output for their signals, then the codebase scan dispatch, then proceed to step 3.
      - If user dismisses gaps (option c): skip the exploration dialog (items 2-3 below), do NOT generate guesses or annotate spec.md. Record a per-gap dismissal table in exploration.md `## Design Decisions — Full Analysis` section (step 7b) with format: `| Gap topic | Question that would have been asked | User disposition: dismissed |` for each gap. This gives downstream review agents enough context to challenge individual dismissals. Do NOT jump directly to step 3 — continue below to the Scope checkpoint and Complexity Assessment, using your initial interpretation above in place of dialog output for their signals, then the codebase scan dispatch, then proceed to step 3.
      - If user wants to explore (option a): continue with the Exploration dialog below

   2. **Exploration dialog** (WHAT/WHY scoped):
      - Ask one question at a time
      - Prefer multiple choice when genuine alternatives exist (2-3 options with tradeoffs). Present all options first, then state your recommendation with a brief rationale.
      - Focus on WHAT (capabilities, behaviors, edge cases) and WHY (problems, value, constraints)
      - **Question scope gate**: Before asking each exploration question, apply the same WHAT/WHY scope fence used for spec content (step 7). If the question asks the user to choose between implementation approaches (file organization, tech stack, architectural patterns, packaging formats, data structures), do NOT ask it as-is. Instead:
        1. **Reframe**: Extract the user-facing constraint the HOW question implies and ask that instead. Example: "Single HTML file vs. multi-file vs. build step?" → "Should the game work immediately when opened in a browser, or is a setup/build step acceptable?"
        2. **Flag for planning**: Add the original HOW question to the "Design Context for Planning" accumulator as an unresolved implementation question. Format: `[EXPLORATION-FLAGGED]: <original HOW question> — user-facing constraint captured as: <reframed WHAT/WHY question>`

        The user's answer to the reframed question becomes a spec-level constraint. The flagged HOW question becomes input for `/speckit-plan` to resolve during its research phase.

      - **HOW redirect pattern** *(applies when user volunteers HOW details — for agent-initiated HOW questions, see Question scope gate above)*: When user provides implementation-direction answers (tech stack, architecture, data structures):
        - Acknowledge: "Good insight on [topic] — I'll capture that as a hint for planning."
        - Add to "Design Context for Planning" section accumulator
        - Redirect to WHAT/WHY: "[Relevant WHAT/WHY follow-up question based on their HOW answer]"

   3. **Convergence management**:
      - **No checkpoint before 2 questions** — give exploration room to breathe
      - After 2-7 questions: continue naturally as long as answers reveal new gaps
      - After 8-10 questions: present convergence checkpoint with explored/remaining disclosure. Derive remaining areas from spec-template.md mandatory sections (requirements, user stories, testing strategy, assumptions, edge cases, input data). Present as: "Explored ~N of ~M areas. Remaining: [brief list of unexplored mandatory sections]. Proceed with informed defaults for the remaining areas, or explore further?" Qualify estimates as approximate.
      - User can trigger convergence anytime by saying "that's enough" / "proceed" / "write the spec", or say "let's discuss" to explore a specific area before deciding
      - **Session interruption**: If user stops responding mid-exploration, proceed with gathered context. Annotate remaining gaps with `[EXPLORATION-INCOMPLETE: <gap not explored>]` in the spec.

   **Context source**: Use project context loaded in step 1 (CLAUDE.md, constitution, existing specs, scan profile). Do NOT perform additional codebase scanning during exploration.

   **Concrete examples**:

   **Example 1 — Vague prompt (gaps found)**:

   ```
   User: "Add a feature to track user activity"

   Agent: Based on your description, I understand this feature as: A system to record user actions for analytics or auditing.

   I have questions about:
   - What specific user actions should be tracked?
   - Who needs access to this activity data?
   - How long should activity data be retained?

   Do you want to explore these, or should I proceed to spec generation with informed guesses for the gaps above?

   User: Let's explore.

   [... 3-5 questions with multiple choice options, then convergence checkpoint ...]

   User: Proceed.
   ```

   **Example 2 — Detailed prompt (no gaps found — still present interpretation)**:

   ```
   User: "Add rate-limiting — per-client at 100 req/sec, 429 responses, preserve auth flow."

   Agent: Based on your description, I understand this feature as: A per-client rate limiting system...
   No significant WHAT/WHY gaps detected.
   Do you want to explore edge cases, or should I proceed to spec generation?
   ```

   **Example 3 — Agent catches its own HOW question (question scope gate)**:

   ```
   [Agent internally drafts: "Should this be a single HTML file, multi-file, or use a build step?"]
   [Gate fires: this is a packaging/architecture choice → reframe as user-facing constraint]
   [Flags to Design Context: "[EXPLORATION-FLAGGED]: Single file vs multi-file vs build step — user-facing constraint captured as: zero-setup vs build-step-required"]

   Agent: Should the game work immediately when you open it in a browser, or is running a build/setup step first acceptable?

   A) Zero setup — open a file, play immediately
   B) Minimal setup — run a command first, then open and play

   User: A — zero setup.

   [Adds "Zero-setup delivery: user opens file(s) in browser and plays immediately, no build step" to spec constraints]
   ```

   **Scope checkpoint** (after exploration converges, before codebase scan):

   When exploration identifies >2 user stories, present the user with a scope summary before proceeding. Scope matters because it compounds: each additional user story adds functional requirements, which produce more plan steps, more review findings, more tasks, and more implementation work. Scoping down here is the highest-leverage way to keep downstream stages manageable.

   > I've identified [N] user stories:
   > 1. [Story name] ([coupling note] — [rough FR count] FRs)
   > 2. [Story name] ([coupling note] — [rough FR count] FRs)
   > ...
   >
   > Larger specs compound into larger plans, reviews, and task lists — each story adds downstream volume at every stage. [Which stories are tightly coupled vs. independently deferrable]. [Recommendation on scope, e.g., "Stories 1–2 are the core fix; 3–4 could be separate specs to keep each pass focused."]
   >
   > Proceed with all [N] stories, or scope down?

   If the user scopes down, record the deferred stories in the spec's Out of Scope section with a note that they are candidates for follow-up specs. Skip the checkpoint when exploration finds ≤2 user stories — the scope is already small.

   **Complexity Assessment** (after scope checkpoint, before codebase scan):

   Classify the spec as `compact` or `standard` from two primary signals, both drawn from the exploration output above. Both signals must indicate compact, or the classification is `standard`:

   - **Signal 1 — Independent user journeys**: Count distinct user journeys directly from the exploration output — the same count the scope checkpoint uses when it fires for >2 stories, taken from the underlying output, not the checkpoint's rendered presentation. ≤1 independent journey → compact.
   - **Signal 2 — Cross-cutting scope**: From the exploration dialog (or, if exploration was skipped, your initial interpretation of the feature and the informed guesses filling its gaps), assess whether the feature touches a single component or crosses multiple components/subsystems. Single-component scope → compact.
   - **Tiebreaker**: If both signals are genuinely ambiguous (not merely low-confidence), apply pattern-following judgment — an established pattern in this codebase or domain → compact; a novel design with no precedent → standard.

   Announce the classification and proceed unless the user opts out:

   > This looks like a **compact** change — I'll use a lean spec format. Say "full" if you want the complete template.

   or:

   > This is a **standard** feature — I'll use the full spec template. Say "compact" if you think it's simpler than it looks.

   Do not present a multi-option structured choice — the agent's two signals are sufficient for a correct classification in the common case, and the opt-out framing lets the user override without ceremony.

   - **Standard→compact override**: If the user overrides toward compact, warn that full Acceptance Scenarios will always be replaced by Verification Notes, and that Success Criteria and Key Entities may be omitted depending on FR measurability and whether the feature involves data — then require explicit confirmation before proceeding.
   - **Compact→standard override**: If the user overrides toward standard and `plan.md` or `tasks.md` already exist for this feature, warn that those artifacts were built from the compact format and let the user choose whether to regenerate them.
   - **Re-run detection**: If the spec being updated already has a `complexity` field, present both the new assessment and the existing classification together and ask the user to confirm or override.

   Record the classification, both signals, the tiebreaker outcome (if invoked), and any user override in exploration.md's `## Complexity Assessment` section (step 7b). Carry the final classification forward to step 7's compact generation rules and step 8's `complexity` frontmatter field.

   Once exploration produces a validated design direction (or is skipped), **dispatch the codebase scan subagent** immediately (see codebase scan details below), then proceed to step 3. The scan runs in parallel with step 3's document-only checks.

   **Codebase scan** (parallel dispatch):

   Dispatch a `general-purpose` subagent to search the project's codebase for the proposed feature. The subagent should search for:
   1. Existing solutions to this feature's problem domain (base classes, utility functions, shared modules)
   2. Patterns that contradict assumptions in the feature description
   3. Existing infrastructure that imposes constraints (locking semantics, event ordering, naming conventions)
   4. Prior implementations of similar features that established precedents

   Search budget: Target 10 minutes maximum. If approaching the limit, report what you found so far.

   Report budget: Target 40 lines maximum. The search is absorbed by the subagent; the report is not — it lands in this command's context on top of the exploration record, the template, and partial spec text. Report conclusions plus `path:line` citations only. No verbatim file contents, function or class bodies, complete list dumps, or reproduced examples — cite the location and let this command read it later, at the granularity it actually needs. **This budget binds the dispatch prompt too**: do not ask the subagent for verbatim content or exhaustive inventories. If findings exceed the budget, keep the ones that change a requirement or a constraint and drop the rest.

   The subagent should report findings as a structured list with sections: **Existing solutions** [with project-relative file paths], **Contradicting patterns** [with project-relative file paths], **Relevant constraints** [with evidence], or **No relevant infrastructure found**.

   **Scope fence**: Codebase scan results inform WHAT/WHY (requirements and constraints) but NOT implementation details:
   - DO use: "Existing `BatchProcessor` base class" → requirement: "extend existing batch processing framework"
   - DO use: "Row-level locking in data model" → constraint: "must handle concurrent access"
   - Do NOT use: "use `BatchProcessor.process()` method on line 42"
   - Do NOT use: "call `db.lock_row()` before updating"

   **Partition**: Use codebase scan results when generating requirements and constraints in the spec. Do NOT use codebase scan results when determining the verdict (proceed/reduce scope/cancel) — the verdict is based on document evidence only.

   **Fallback**: If the codebase scan subagent times out, returns an error, is unavailable, or has reached no terminal state by step 6's deadline, proceed with document-only premise validation. Log: "Codebase scan [timed out | was unavailable | returned error | never delivered]. Proceeding with document-only validation."

   The last case is the silent one — the subagent neither fails nor returns, so nothing announces it and it is indistinguishable from a healthy scan that is merely slow. Step 6 is what separates the two: it defines the terminal states and the deadline for reaching one. Never resolve the ambiguity by pinging the subagent, and never re-dispatch the scan — a re-request risks the full report being delivered twice, and the report is the largest single payload the scan puts into this command's context.

   **Late arrival**: If the report arrives after the fallback fired and spec content already exists, fold it in rather than discarding it: run one additional iteration of step 9's validation loop over the findings, over and above that loop's 3-iteration cap. Verify any late claim that contradicts already-written spec text directly against the codebase before acting on either version — a late report did not see the text it contradicts, and a report delivered in fragments can contradict itself.

3. **Premise validation**:

   **Interactive mode gate**: If you have not yet presented your interpretation and identified gaps to the user, STOP. Return to step 2 and present the exploration checkpoint before proceeding.

   Before running the checks, briefly tell the user what premise validation does and why it matters.

   Use the explored understanding from step 2 and loaded project context (step 1) to perform four checks:

   **Skeptical stance**: Assume the feature is unnecessary and look for evidence to the contrary. Search for both the explored understanding AND the user's original raw prompt terms to catch cases where exploration over-refined the goal.

   **PV timing tradeoff note**: The codebase scan was dispatched at the end of step 2 and runs in parallel with PV's document-only checks below. PV's existing-solutions check may proceed without codebase scan results under this timing. This is an accepted tradeoff for wall-clock savings — the scan results will be available before spec content generation (step 7).

   1. **Existing solutions check**: Search loaded context (CLAUDE.md, constitution, exploration context) plus targeted directory scans (docs/, baselines/, .specify/scripts/, existing specs) for existing workflows, scripts, commands, or documented processes that achieve the same goal as the proposed feature. Incorporate codebase scan results (if available) alongside documentation and known artifact locations. If the codebase scan is still running, proceed with document-only checks.

   2. **Current workflow documentation**: Document how the goal is accomplished today — manually or otherwise — with specific steps. If no current workflow exists, document "No current workflow — this is a new capability."

   3. **Friction assessment**: Identify what specific, measurable friction the proposed feature removes. Distinguish between genuine friction ("users forget step 3 and corrupt output 40% of the time", "manual process takes 30 minutes and runs daily") and convenience ("it would be nice to automate this"). If friction cannot be quantified, note the qualitative assessment with a confidence level.

   4. **Disproportionality assessment (coarse filter)**: Assess whether the friction is so low that any non-trivial solution is suspect. This is the specify-phase coarse filter — it catches obviously disproportionate cases. The plan-phase check (which has implementation cost data) performs the precise proportionality assessment.

   **Verdict**: Based on the four checks, produce one of:
   - **proceed** — genuine friction with no existing solution, or existing solution with significant gaps
   - **reduce scope** — partial existing solution covers most of the use case; build only the gap
   - **cancel** — existing solution works, friction is near-zero, or implementation would be obviously disproportionate

   **When verdict is "reduce scope"**:
   - Present the user with two options:
     - **(A) Interactive confirmation** — confirm the scope reduction before generating requirements (requirements address only the residual friction)
     - **(B) Auto-narrow** — let the agent auto-narrow requirements based on the verdict (user can override by re-running specify)
   - In non-interactive mode (background agents, `/overnight`), default to option B.

   **IMPORTANT**: Premise validation is advisory, not a gate. The spec is ALWAYS generated regardless of verdict, serving as a decision record. The verdict informs the completion report's next-step recommendations (step 10).

   This step is internal reasoning — present the verdict to the user with a brief summary of findings, but do not present the full 4-check analysis unless the user asks for details.

4. **Generate a short name** (2-4 words, action-noun format) for the feature directory. Preserve technical terms and acronyms.
   Example: "Add system boundary probe" → "system-boundary-probe"

5. **Create the spec feature directory**:

   **Existing spec detection** (before any file creation):
   - Check `.specify/feature.json` — if it points to a directory with `spec.md`, that's an existing spec
   - Check the auto-generated directory name — if it matches an existing directory with `spec.md`, that's an existing spec
   - If either check finds an existing spec, warn and present options:
       ```
       ⚠️ Found existing spec at [path].
       Options:
         [O] Overwrite — generate a fresh spec (old content is lost)
         [E] Edit — abort and manually edit the existing spec.md
         [N] New — create a new feature directory instead
         [D] Something else — describe what you'd like to do
         [?] Let's discuss — I have questions before deciding
       Choose [O/E/N/D/?]:
       ```
     - If user chooses O: proceed with overwrite (delete existing spec, continue with creation)
     - If user chooses E: abort the specify command
     - If user chooses N: skip to short name regeneration, then create new directory
     - If user chooses D: follow the user's stated preference
     - If user chooses ?: discuss the situation before re-presenting options

   Specs live under the default `specs/` directory unless the user explicitly provides `SPECIFY_FEATURE_DIRECTORY`.

   **Resolution order for `SPECIFY_FEATURE_DIRECTORY`**:
   1. If the user explicitly provided `SPECIFY_FEATURE_DIRECTORY` (e.g., via environment variable, argument, or configuration), use it as-is
   2. Otherwise, auto-generate it under `specs/`:
      - Check `.specify/init-options.json` for `branch_numbering`
      - If `"timestamp"`: prefix is `YYYYMMDD-HHMMSS` (current timestamp)
      - If `"sequential"` or absent: prefix is `NNN` (next available 3-digit number after scanning existing directories in `specs/`)
      - Construct the directory name: `<prefix>-<short-name>` (e.g., `003-user-auth` or `20260319-143022-user-auth`)
      - Set `SPECIFY_FEATURE_DIRECTORY` to `specs/<directory-name>`

   **Create the directory and spec file**:
   - `mkdir -p SPECIFY_FEATURE_DIRECTORY`
   - Copy `.specify/templates/spec-template.md` to `SPECIFY_FEATURE_DIRECTORY/spec.md`. If the template does not exist, abort with error: "Template not found — reinstall with `speckit init`. Expected: .specify/templates/spec-template.md"
   - Set `SPEC_FILE` to `SPECIFY_FEATURE_DIRECTORY/spec.md`
   - Persist the resolved path to `.specify/feature.json`:
     ```json
     {
       "feature_directory": "<resolved feature dir>"
     }
     ```
     Write the actual resolved directory path value (for example, `specs/003-user-auth`), not the literal string `SPECIFY_FEATURE_DIRECTORY`.
     This allows downstream commands (`/speckit-plan`, `/speckit-tasks`, etc.) to locate the feature directory without relying on branch name conventions.

   **Write user prompt file**: Save the user's verbatim input to `SPECIFY_FEATURE_DIRECTORY/user-prompt.md`. This is an audit trail of what the user actually requested — do not summarize, paraphrase, or abridge. The prompt is kept in a separate file (not in spec.md) so that downstream commands reading the spec are not polluted by implementation details that the spec deliberately abstracted away.

   **IMPORTANT**:
   - You must only create one feature per `/speckit-specify` invocation
   - The spec directory name and the branch name are independent — they may be the same but that is the user's choice
   - The spec directory and file are always created by this command, never by the hook

6. **Load spec template**: Load `.specify/templates/spec-template.md` to understand required sections. If the template does not exist, abort with error: "Template not found — reinstall with `speckit init`. Expected: .specify/templates/spec-template.md"

   **Codebase scan synchronization**: The codebase scan MUST complete before spec content generation begins — the parallelism window is between exploration convergence and content generation. The scan (dispatched at the end of step 2) is in a **terminal state** once it has delivered a report (full or partial), returned an error, or reported itself unavailable.

   - **Terminal state reached** → proceed with whatever it delivered.
   - **Not yet terminal** → the scan is still running. Wait for it, without prompting it.
   - **Deadline**: the wait is bounded by the subagent's own 10-minute search budget. A scan that is still in no terminal state once that budget is spent has not run long — it has failed silently. Apply step 2's fallback, log it, and proceed with document-only validation. Like the search budget itself, this deadline is best-effort prompt guidance, not a mechanically enforced timer; when in doubt, wait rather than discard a scan that may still deliver.

   Do not ping the subagent at any point in this wait, and do not re-dispatch. If the report lands after the deadline has passed, step 2's late-arrival rule governs what happens to it — nothing is lost by falling back on time.

7. **Generate specification content**: Using the explored design direction (step 2) and loaded project context (step 1), follow this execution flow:

    **WHAT/WHY Scope Fence**: Throughout this step, name capabilities and behaviors — not files, methods, or data structures. The spec describes WHAT the feature does and WHY it matters. The plan (`/speckit-plan`) decomposes WHAT into HOW — that is where implementation details belong. If you find yourself writing any of the following, you have crossed the spec/plan boundary — pull back to the capability or behavior the detail supports:

    - File paths, class names, function signatures, method names
    - Database schemas, API endpoints, JSON schemas
    - HTML comment markers, sentinel markers, format tokens (e.g., `<!-- MARKER -->`, `<!-- BOUNDARY -->`)
    - Template syntax, output format specifications, concrete markup patterns
    - Specific data structures, wire formats, or serialization details

    **Test**: For each functional requirement, ask: "Could this FR be satisfied by multiple different implementations?" If the FR prescribes a *specific* implementation mechanism (a particular marker format, a specific file structure, a concrete syntax), it belongs in plan.md, not spec.md. The FR should describe the *capability* ("tasks template generates diff grouping guidance from the plan's execution model") not the *mechanism* ("tasks template emits `<!-- DIFF BOUNDARY -->` markers").

    **Compact Generation Mode**: If step 2's Complexity Assessment classified this spec as `compact`, apply the following overrides to the numbered generation flow below. If classified `standard`, generate using the full template with no changes.

    - **Substep 5 — User Scenarios**: Generate exactly one user story, with `**Problem:**`, `**Why this priority**:`, and `**Independent Test**:` fields only — omit the `**Acceptance Scenarios**:` sub-section entirely.
    - **Substep 7 — Functional Requirements — Verification Notes**: In place of per-story acceptance scenarios, generate a `## Verification Notes` section (positioned per the template's conditional placeholder) with one line per FR: `- **FR-NNN**: [one-line verification description]`. This is the sole acceptance-criteria artifact for a compact spec. If an FR has no meaningful verification beyond "the tests pass," say exactly that rather than omitting the line.
    - **Substep 7 — Functional Requirements — FR budget**: Target ≤5 FRs, subordinate to substep 7's single-obligation test. If you find yourself writing >5 FRs for a compact feature, verify each still passes the single-obligation test — if they do, the feature may warrant `standard` classification, but the FRs stay atomic regardless of which classification wins.
    - **Substep 10 — Success Criteria**: Omit `## Success Criteria` when every FR is directly verifiable by a test assertion. Retain it when any FR requires measurement beyond assertion (e.g., a performance target, a satisfaction metric). Tiebreaker by spec type: `refactor`/`bugfix` lean toward omission; `feature`/`infrastructure`/`documentation` lean toward retention.
    - **Substep 11 — Key Entities**: Omit `### Key Entities` when the feature involves no data model.

    1. Parse user description from arguments
       If empty AND exploration produced a validated direction in step 2:
         Synthesize a one-paragraph summary of the validated direction.
         Use this summary as the effective feature description for spec generation.
       If empty AND exploration did NOT produce a validated direction:
         ERROR "No feature description provided and exploration produced no validated direction."
    2. Extract key concepts from description
       Identify: actors, actions, data, constraints
    3. For unclear aspects:
       - Make informed guesses based on context and industry standards
       - Only mark with [NEEDS CLARIFICATION: specific question] if:
         - The choice significantly impacts feature scope or user experience
         - Multiple reasonable interpretations exist with different implications
         - No reasonable default exists
       - **LIMIT: Maximum 3 [NEEDS CLARIFICATION] markers total**
       - Prioritize clarifications by impact: scope > security/privacy > user experience > technical details
    4. Generate Summary section
       Create a `## Summary` section giving plain-language orientation — the feature's purpose, scope, and key constraints. Place it below the metadata header (frontmatter + Feature Branch) and above `## User Scenarios & Testing`. This section is for human readers — downstream pipeline commands treat it as orientation context.

       **Shape**: open with 2-3 sentences of narrative covering purpose and scope, then match the structure to the content:
       - Three or more discrete items — separate user stories, distinct mechanisms, scope boundaries — become a bulleted list, one line each, with a bold lead-in naming the item.
       - A sequence whose order matters becomes a numbered list.
       - A single continuous argument stays prose. Prefer a second short paragraph over a one-item list.

       Never chain three or more discrete items into a single sentence with semicolons or "and". Cap the section at roughly 200 words — it is orientation, not a second copy of the requirements.
    5. Fill User Scenarios & Testing section
       **Story quality gate**: Before generating user stories, evaluate each candidate story:
       - Does it represent a genuinely independent user journey with a distinct actor or goal?
       - Could it be tested independently (separate acceptance scenarios, distinct verification)?
       If a candidate story is an edge case, implementation step, or minor variation of another story,
       fold it into the acceptance scenarios of the parent story instead of creating a separate story.
       If all candidate stories are aspects of one journey, generate a single user story directly —
       do not create multiple stories and then test them.

       For compact-classified specs, this gate is advisory — its assessment is recorded in
       exploration.md but does not affect the single-story output mandated by the Compact
       Generation Mode rules below.

       Each user story begins with a `**Problem:**` line describing the friction or gap it addresses, followed by `**Why this priority**:`, `**Independent Test**:`, and `**Acceptance Scenarios**:`.
       If no clear user flow: ERROR "Cannot determine user scenarios"
    6. **Edge Case Resolution Gate**
       After generating edge cases, verify that each edge case has a decided behavior — not an open question. If any edge case is left as an unanswered question without a decided behavior, resolve it by choosing a sensible default based on project context and industry standards. Only use a [NEEDS CLARIFICATION] marker if no reasonable default exists AND the 3-marker budget is not exhausted.
    7. Generate Functional Requirements
       Each requirement must be testable
       Use reasonable defaults for unspecified details (document assumptions in Assumptions section)
       **Implementation detail filter**: After drafting FRs, re-read each one and apply the scope fence test: "Could this FR be satisfied by multiple different implementations?" If an FR prescribes a specific marker format, file layout, syntax pattern, or output structure, rewrite it to describe the capability instead. Move the implementation detail to the `## Input Data` section as a reference for the plan phase (annotate with "[plan-level detail]").
       **Single-obligation test**: In the same re-read pass, apply the single-obligation test to each FR: could one half of this requirement pass verification while the other half fails? If yes, the FR is compound — split it into separate atomic FRs (e.g., FR-NNN → FR-NNNa, FR-NNNb), each containing one independent obligation.
    8. Infer Testing Strategy
       - Determine test tier preference from feature description and codebase context (unit / integration / both / defer to planning)
       - Write a 1-2 sentence Rationale explaining WHY this tier is appropriate for THIS feature (focus on what kind of behavior needs verification, not implementation details)
       - **SPEC/PLAN BOUNDARY**: Do NOT include test class names, test method counts, file paths, coverage percentages, or implementation details. Those belong in plan.md, not spec.md. The spec states WHAT tier and WHY; the plan states HOW to test.
       - If feature is documentation-only: record `**Test Tiers**: N/A (documentation-only)` with Rationale explaining the verification approach (cross-reference integrity, link validity, co-evolution compliance)

       **Good example (spec-level — behavior rationale only)**:
       ```
       **Test Tiers**: unit
       **Rationale**: Template files are static text validated via content assertions. No runtime behavior to test.
       ```

       **Bad example (plan-level details — DO NOT include in spec)**:
       ```
       **Test Tiers**: unit
       **Rationale**: ClarifyCommandContentTest (9 methods) in test_command_content.py validates template structure. Pipeline contract tests verify handoff ordering.
       ```
    9. Extract Input Data
       - Scan the feature description for explicit file references (paths, doc names, artifact names)
       - Scan loaded project context (CLAUDE.md pointers, constitution references) for relevant artifacts
       - If references found: populate ## Input Data section with structured reading list (file path + brief description of what it provides)
       - If file references point to non-existent files: annotate with "[not found]"
       - If no references found: omit ## Input Data section entirely
       - Flag references that could serve as acceptance test inputs — particularly documented failure cases, case studies, or baseline artifacts that motivated the feature. Annotate these with "[test input]" in the What It Provides column
    10. Define Success Criteria
       Create measurable, technology-agnostic outcomes
       Include both quantitative metrics (time, performance, volume) and qualitative measures (user satisfaction, task completion)
       Each criterion must be verifiable without implementation details
    11. Identify Key Entities (if data involved)
    12. Return: SUCCESS (spec ready for planning)

    Incorporate loaded context throughout:
    - Reference established patterns and architectural decisions
    - Use domain terminology consistently with existing docs
    - Note constraints or dependencies from prior design decisions

7b. **Write exploration.md**: Before writing spec.md, write `SPECIFY_FEATURE_DIRECTORY/exploration.md` using the exploration record format given in the **File structure** block below.

    **Content sourcing**:
    - **Design Decisions — Full Analysis**: Assemble from the exploration dialog (step 2) — all alternatives considered, tradeoffs evaluated, rejected approaches with rationale. If user chose option (b) and exploration produced no design decisions, write: "No design decisions recorded during exploration." If user dismissed gaps (option c), write the per-gap dismissal table instead.
    - **Design Context for Planning**: Assemble from the HOW redirect accumulator (step 2) — implementation-direction insights and EXPLORATION-FLAGGED questions. If no HOW hints were captured, write: "No implementation-direction insights captured during exploration."
    - **Complexity Assessment**: Copy directly from step 2's Complexity Assessment substep — classification, both signals, the tiebreaker outcome (or "not invoked"), and any user override (or "none").
    - **Premise Validation — Full Analysis**: Assemble from premise validation output (step 3) — all four checks (existing solutions, current workflow, friction, disproportionality) plus verdict. Use the full structured format, not the slim verdict that goes in spec.md.

    **Write ordering**: Write exploration.md BEFORE spec.md. If specify crashes between them, re-running `/speckit-specify` regenerates both files.

    **File structure**:
    ```markdown
    # Exploration Record: [FEATURE NAME]

    ## Design Decisions — Full Analysis

    [Full analysis from step 2, "No design decisions recorded" if option (b) with no decisions, or per-gap dismissal table if option (c)]

    ## Design Context for Planning

    *Implementation-direction insights captured during specification exploration.
    These are hints for /speckit-plan, not spec-level requirements. Plan may use,
    challenge, or override them after its own research phase.*

    [HOW hints from step 2 accumulator, or "No implementation-direction insights captured during exploration."]

    ## Complexity Assessment

    **Classification**: [compact | standard]
    **Signal 1 — User journeys**: [count] ([compact/standard/ambiguous])
    **Signal 2 — Cross-cutting scope**: [single-component/multi-component/ambiguous]
    **Tiebreaker**: [not invoked | pattern-following → compact | novel design → standard]
    **User override**: [none | compact→standard | standard→compact]

    ## Premise Validation — Full Analysis

    [Full structured analysis from step 3]
    ```

8. **Write specification**: Write to SPEC_FILE using the template structure, replacing placeholders with concrete details derived from the explored design direction while preserving section order and headings. The spec.md contains slim verdicts for Design Decisions and Premise Validation (full analysis is in exploration.md per step 7b).

   **Design Decisions slim verdict format**: For each decision, write a single bullet: `- **[Decision title]**: [chosen approach] — [1-line rationale]`. The template already includes the section-level link to exploration.md — do not add per-entry links.

   **Premise Validation slim verdict format**: Write a 2-line verdict: `**Verdict:** [verdict] — [1-line friction summary]`. The template already includes the link to exploration.md below the verdict.

   When writing the spec, resolve the plan handoff prompt's `{SPEC_FILE}` placeholder with the actual spec path.

   The template already includes a YAML frontmatter block between `---` fences at the top of the file (before the title). Fill in its placeholder values:

   - **type**: Infer from the feature description (`feature`, `bugfix`, `refactor`, `infrastructure`, or `documentation`)
   - **risk**: High = cross-cutting or data model changes. Medium = single-system changes. Low = additive-only.
   - **complexity**: `compact` or `standard`, per step 2's Complexity Assessment classification (including any user override).
   - **owner**: Extract from CLAUDE.md if available, otherwise `TBD`
   - **created**: Current date (YYYY-MM-DD)

   Do NOT add separate `**Created**` header fields — these are already captured in the frontmatter. The header section contains only `**Feature Branch**` — set it to the spec directory name generated in step 4 (e.g., `003-user-auth`), or the branch name if one was created by the `before_specify` hook. The user's verbatim prompt is saved to `user-prompt.md` (step 5), not embedded in the spec.

9. **Specification Quality Validation**: After writing the initial spec, validate it against quality criteria:

    a. **Create Spec Quality Checklist**: Generate a checklist file at `SPECIFY_FEATURE_DIRECTORY/checklists/requirements.md` using the template at `.specify/templates/requirements-checklist.md`, filling in feature name, date, and spec link. If the template does not exist, abort with error: "Checklist template not found — reinstall with `speckit init`. Expected: .specify/templates/requirements-checklist.md"

    b. **Run Validation Check**: Review the spec against each checklist item:
       - For each item, determine if it passes or fails
       - Document specific issues found (quote relevant spec sections)
       - **Edge case default check**: Scan the Edge Cases section for bullets left as open questions without a decided behavior. Unresolved edge cases are a validation failure — decide a sensible default for each before proceeding
       - **Compact-mode validation**: If the spec has `complexity: compact` in its YAML frontmatter, follow the checklist's compact-mode preamble — validate only items marked `[compact]`. Do not flag the absence of sections that compact specs legitimately omit (Success Criteria, Key Entities, full acceptance scenarios).

    c. **Handle Validation Results**:

       - **If all items pass**: Mark checklist complete and proceed to step 10

       - **If items fail (excluding [NEEDS CLARIFICATION])**:
         1. List the failing items and specific issues
         2. Update the spec to address each failing item
         3. Re-validate the updated spec (max 3 total iterations)
         4. If all items pass after any iteration, proceed to step 10
         5. If still failing after 3 iterations, document remaining issues in checklist notes, warn user, and proceed to step 10

       - **If [NEEDS CLARIFICATION] markers remain**:
         1. Extract all [NEEDS CLARIFICATION: ...] markers from the spec
         2. **LIMIT CHECK**: If more than 3 markers exist, keep only the 3 most critical (by scope/security/UX impact) and make informed guesses for the rest

         3. For each clarification needed (max 3), present options to user in this format:

            ```markdown
            ## Question [N]: [Topic]

            **Context**: [Quote relevant spec section]

            **What we need to know**: [Specific question from NEEDS CLARIFICATION marker]

            **Suggested Answers**:

            | Option | Answer | Implications |
            |--------|--------|--------------|
            | A      | [First suggested answer] | [What this means for the feature] |
            | B      | [Second suggested answer] | [What this means for the feature] |
            | C      | [Third suggested answer] | [What this means for the feature] |
            | Custom | Provide your own answer | [Explain how to provide custom input] |

            **Recommendation**: [State which option you recommend and a brief rationale]

            **Your choice**: _[Wait for user response]_
            ```

         4. Number questions sequentially (Q1, Q2, Q3 - max 3 total)
         5. Present all questions together before waiting for responses
         6. Wait for user to respond with their choices for all questions (e.g., "Q1: A, Q2: Custom - [details], Q3: B")
         7. Update the spec by replacing each [NEEDS CLARIFICATION] marker with the user's selected or provided answer
         8. Re-run validation after all clarifications are resolved

    d. **Update Checklist**: After each validation iteration, update the checklist file with current pass/fail status

10. **Report completion** to the user with:

    **Artifact summary:**

    | Artifact | Path |
    |----------|------|
    | Spec | `SPEC_FILE` |
    | Exploration notes | `SPECIFY_FEATURE_DIRECTORY/exploration.md` |
    | Requirements checklist | `SPECIFY_FEATURE_DIRECTORY/checklists/requirements.md` |

    - Checklist results summary
    - Premise validation verdict summary (from step 3)
    - Determine the recommended next steps based on verdict below, but do not display this block yet — step 12 displays it after the post-completion hooks, so it is the last thing shown this turn:

      ➡️ **Successor obligation**: the next stage is `/speckit-clarify`. Always recommend it on a `proceed` or `reduce scope` verdict, and do not substitute an ordering of your own — not for a spec you judge low-risk, well-understood, thoroughly explored, or already correct. You authored this spec, which makes you the worst-positioned judge of what is still ambiguous in it. Whether to skip a stage is the user's call, never yours; if they choose to, note that downstream rework risk increases and carry on. A `cancel` verdict is the exception: it recommends not building the feature at all, so follow that branch's guidance instead of pushing the next stage.

      **If verdict is "proceed"**:

      > **Context tip:** Your spec is saved to specs/<feature>/spec.md. Consider /clear before /speckit-clarify (or /speckit-review) to free context for the next phase.

      **➡️ Next steps:**
      1. `/speckit-clarify` (Opus recommended) — stress-test the spec for hidden ambiguity
      2. `/speckit-review` (Opus for review agents) — adversarially challenge the spec
      3. `/speckit-plan` (Sonnet sufficient) — decompose into implementation steps

      **If verdict is "cancel"**:

      ⚠️ Premise validation recommends **stopping**. The existing solution appears sufficient and the friction does not justify new development. The spec has been generated as a decision record.

      If you disagree with this assessment, proceed to `/speckit-clarify` to stress-test the premise validation conclusions. Otherwise, consider this feature complete — no further pipeline steps needed.

      **If verdict is "reduce scope"**:

      ⚠️ Premise validation recommends **reducing scope** to address only the residual friction not covered by the existing solution.

      > **Context tip:** Your spec is saved to specs/<feature>/spec.md. Consider /clear before /speckit-clarify (or /speckit-review) to free context for the next phase.

      1. `/speckit-clarify` (Opus recommended) — validate the scope reduction and stress-test remaining requirements
      2. `/speckit-review` (Opus for review agents) — adversarially challenge the reduced spec
      3. `/speckit-plan` (Sonnet sufficient) — plan only the reduced scope

11. **Post-completion hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.after_specify` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`) — if a mandatory hook's invocation fails or terminates abnormally, halt with "`<stage>` completed but the follow-up step failed — re-run `/<command>` to retry" (a hook returning a result, including a blocking one, is a successful dispatch, not a failure); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue.

12. **🔁 Display next-step guidance (ALWAYS RUN — DO NOT OMIT)**: Now that the hook(s) in step 11 have finished executing, display the verdict-specific guidance computed in step 10 — the ➡️ **Successor obligation** line and its next-steps block. This is the only time it is shown, and it must be the last thing shown to the user this turn.

**NOTE:** Branch creation is handled by the `before_specify` hook (extension). Spec directory and file creation are always handled by this core command.

## Quick Guidelines

- Focus on **WHAT** users need and **WHY**.
- Avoid HOW to implement (no tech stack, APIs, code structure).
- DO NOT create any checklists that are embedded in the spec. That will be a separate command.

### Section Requirements

- **Mandatory sections**: Must be completed for every feature
- **Optional sections**: Include only when relevant to the feature
- When a section doesn't apply, remove it entirely (don't leave as "N/A")

### For AI Generation

- **Think like a tester**: Every vague requirement should fail the "testable and unambiguous" checklist item
- **Default, don't ask**: Use project-appropriate defaults for integration patterns, error handling, performance targets, and data retention. Only ask when no reasonable default exists.
