---
name: speckit-constitution
description: 'SpecKit SDD pipeline: create or update `.specify/memory/constitution.md` with CLAUDE.md integration.'
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:meta
  meta_preset_strategy: replace
  meta_preset_upstream: speckit.constitution
user-invocable: true
disable-model-invocation: false
---



# Speckit Constitution Skill

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Workspace check (MANDATORY)**: Run `speckit run require-workspace.sh`. This resolves the workspace from any subdirectory and produces the same fixed message when there is no workspace above the current directory. On a non-zero exit, relay its stderr output to the user verbatim — do not paraphrase, reword, summarize, or translate it; do not prepend or append anything (no preface, heading, or attribution such as "require-workspace.sh failed:"); do not name the script, the command, the exit code, or any internal path — then halt. On exit 0, proceed silently to the next check.

**Pre-execution hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.before_constitution` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue. Wait for all hooks to complete before continuing.

## Outline

Before starting work, briefly tell the user what this stage does and why it matters. Print the introduction in bold.

This command creates or updates your project's constitution — the governing principles that guide every spec, plan, and implementation. It works interactively, learning about your project's values and constraints through guided discovery.

**Print this roadmap to the user before starting:**

```
Constitution Builder — Roadmap
════════════════════════════════════════════════════════════
 1. Setup              Load existing constitution, scan profile, project context
 2. Guided Discovery   Interactive topic-by-topic exploration:
    a. Identity        Project name, language, framework stack
    b. Conventions     Recommended patterns and coding standards
    c. Anti-Patterns   Forbidden patterns and approaches
    d. Checkpoints     Human-approval gates for sensitive changes
    e. Gotchas         Operational pitfalls → route to constitution or project-context
    f. Principles      Governing principles (litmus-tested for governance scope)
 3. Refinement         Litmus test, draft assembly, consistency checks
 4. Output             Write constitution, CLAUDE.md split, summary
════════════════════════════════════════════════════════════
```

**Progress reporting protocol**: After completing each roadmap phase (Setup, each discovery topic Identity through Principles, Refinement, Output), print a one-line progress bar to orient the user. Use `✓` for completed, `→` for in-progress, `○` for remaining:

```
── Progress ── ✓ Setup | ✓ Identity | ✓ Conventions | → Anti-Patterns | ○ Checkpoints | ○ Gotchas | ○ Principles | ○ Refinement | ○ Output
```

You are updating the project constitution at `.specify/memory/constitution.md`. This file is a TEMPLATE containing placeholder tokens in square brackets (e.g. `[PROJECT_NAME]`, `[PRINCIPLE_1_NAME]`). Your job is to (a) collect/derive concrete values, (b) fill the template precisely, and (c) propagate any amendments across dependent artifacts.

**Note**: If `.specify/memory/constitution.md` does not exist yet, it should have been initialized from `.specify/templates/constitution-template.md` during project setup. If it's missing, copy the template first.

Follow this execution flow:


1. **Parse and strip deprecated flags**: Check `$ARGUMENTS` for a residual standalone leading `--auto` token. If present, strip it and emit a one-time notice:

   > ⚠️ `--auto` is no longer supported for `/speckit-constitution` — governance requires interactive review.

   Do not strip flags embedded in the feature description text (e.g., "Add --auto flag support" should keep the flag text). After stripping, continue with the remaining `$ARGUMENTS` as the feature description.

2. Load the existing constitution at `.specify/memory/constitution.md`.
   - Identify every placeholder token of the form `[ALL_CAPS_IDENTIFIER]`.
   - **Principle count guidance**: The template's principle slots are a starting point, not a target. Fewer strong governing principles are better than many that mix governance with premature design decisions. The user might require more or fewer principles than the template provides — if a number is specified, respect that and adjust the document accordingly.

3. Collect/derive values for placeholders:

   **Canonical profile input**:
   - Check if `.specify/memory/scan-profile.json` exists
   - Check if `.specify/memory/project-context.md` exists
   - If either is missing or unparseable:
     - Warn: "Missing or invalid profile artifacts — falling back to template-driven mode"
     - Skip to template-driven mode (below)
   - If both exist and are parseable:
     - Verify `scan-profile.json` integrity: parse as JSON, check for required top-level keys (`generated`, `architecture`)
     - Check staleness: parse `generated` timestamp from JSON, warn if >30 days old (default threshold)
     - Read `.specify/memory/project-context.md` for identity fields (see step 4 field-level skip)
     - **Load diff_patterns** (optional, backward compatible):
       - If `diff_patterns` key exists in `scan-profile.json`:
         - Parse the `status` field:
           - `"no_history"`: Log "Scan found no diff history in the configured time window."
           - `"degraded"`: Log "⚠️ Diff archaeology ran in degraded mode (Phabricator unavailable). Only VC-derived patterns are available."
           - `"error"`: Log "⚠️ Diff archaeology encountered an error. No patterns available."
           - `"scanned"`: Proceed to load patterns
         - If `status` is `"scanned"` and `patterns` array is non-empty:
           - Store patterns for use in guided discovery (4c Anti-Patterns and 4d Governance Checkpoints)
           - Separate patterns by `governance_hint`: `anti_pattern`/`both` → 4c Anti-Patterns, `checkpoint`/`both` → 4d Governance Checkpoints
         - If `patterns` array is empty: Log "Scan completed but found no recurring patterns."
       - If `diff_patterns` key is absent: proceed silently (backward compatibility — scan ran before diff archaeology feature)
       - `diff_patterns` MUST NOT be added to the required-keys integrity check

   **When profile artifacts exist and are valid**:
   - **Primary language guidance**: Extract `**Primary Language**` from `project-context.md`'s `## Overview` section. If present and non-empty, use it to inform language-specific conventions. Cross-reference with `scan-profile.json`'s `naming_conventions[]` array for detected patterns.
     - Example: "Primary language: Python (from project-context.md) — detected naming convention: snake_case (from scan-profile.json)"
   - **Module boundary rules**: Read `scan-profile.json`'s `architecture.module_boundaries` field (coarse module list). If present and contains multiple modules, note the architecture structure for reference in principles.
     - Example: "Multi-module architecture detected: `core/`, `api/`, `cli/` — consider module isolation principles"
   - **Staleness warning**: If `scan-profile.json` `generated` timestamp is >30 days old:
     ```
     ⚠️ Profile appears stale (generated YYYY-MM-DD, N days ago).
     Consider re-running `/speckit-scan` for up-to-date analysis.
     ```

   **Template-driven mode** (fallback when profile artifacts missing/invalid):
   - If user input (conversation) supplies a value, use it.
   - Otherwise infer from existing repo context (README, docs, prior constitution versions if embedded).
   - For governance dates: `RATIFICATION_DATE` is the original adoption date (if unknown ask or mark TODO), `LAST_AMENDED_DATE` is today if changes are made, otherwise keep previous.
   - `CONSTITUTION_VERSION` must increment according to semantic versioning rules:
     - MAJOR: Backward incompatible governance/principle removals or redefinitions.
     - MINOR: New principle/section added or materially expanded guidance.
     - PATCH: Clarifications, wording, typo fixes, non-semantic refinements.
   - If version bump type ambiguous, propose reasoning before finalizing.

   Print the Setup progress bar after completing this step.

4. **Guided Discovery** — Interactive constitution building through topic-structured conversation:

   Follow the fixed topic spine in order: **Identity** → **Conventions** → **Anti-Patterns** → **Governance Checkpoints** → **Operational Gotchas** → **Principles**. Within each topic, ask adaptive follow-up questions when an answer reveals a new gap. When a topic has no further gaps, advance to the next. Print the progress bar after completing each topic.

   **4a. Identity questions** (field-level skip per `project-context.md` population):

   For each identity field below, check if the backing field in `.specify/memory/project-context.md` is populated:

   | Question | Backing field in `project-context.md` | Skip condition |
   |----------|----------------------------------------|----------------|
   | Project name/purpose | `## Overview` → `**Project**` | Skip iff present, non-empty, AND not a `[bracketed]` placeholder |
   | Primary language | `## Overview` → `**Primary Language**` | Skip iff present, non-empty, AND not a `[bracketed]` placeholder |
   | Framework stack | `## Overview` → `**Frameworks**` | Skip iff present, non-empty, AND not a `[bracketed]` placeholder |

   - Skip individual questions whose backing field is already populated — where "populated" means present, non-empty, AND not a `[bracketed]` placeholder token. All three identity rows share the same bracketed scaffold, so a bracketed value counts as unpopulated for every row (an empty or `[...]` Primary Language means the identity question IS asked). (NOT file-level skip — partial artifacts are valid.)
   - Use any present field value as an informed default when asking remaining questions
   - Log the derived-vs-asked breakdown, e.g.:
     - "✓ Project identity derived from project-context.md (Project, Primary Language)"
     - "Asked: framework stack (project-context.md field empty)"

   **Diff-derived suggestions protocol** (used by both 4c and 4d):

   After collecting the user's manual input for a topic, present patterns stored from step 3 where `governance_hint` matches the topic's filter:

   - **Present at most 10 patterns** (top 10 by `occurrence_count` descending). If more patterns exist, note: "N additional patterns are available in `scan-profile.json` for manual review."

   - **High-confidence patterns** (occurrence_count ≥ 3):
     > Based on your diff history, we found these recurring {TOPIC_HEADING}. Would you like to add any as {CONFIRM_LABEL}s?

     For each high-confidence pattern:
     ```
     [N] {summary} ({occurrence_count} occurrences across {evidence diffs})
         Evidence: "{evidence[0].excerpt}" (from {evidence[0].diff})
         → Confirm as {CONFIRM_LABEL}? [Y/n]
     ```
     Note: High-confidence defaults to confirm (Y).

   - **Low-confidence patterns** (occurrence_count < 3):
     > Did you know: we also found these in your diff history:

     For each low-confidence pattern:
     ```
     [N] {summary} ({occurrence_count} occurrence(s))
         Evidence: "{evidence[0].excerpt}" (from {evidence[0].diff})
         → Promote to {CONFIRM_LABEL}? [y/N]
     ```
     Note: Low-confidence defaults to skip (N).

   **4b. Conventions** — Ask about recommended patterns and coding standards:

   - "What patterns, conventions, or coding standards SHOULD code in this project follow?"
   - Prompt with examples if needed: "E.g., snake_case naming, prefer composition over inheritance, all public APIs must have docstrings, use dependency injection for external services"
   - If the primary language was identified in 4a, tailor examples to that language
   - If the answer reveals a convention, ask clarifying follow-ups (scope, exceptions, enforcement mechanism)
   - Continue until no further conventions emerge
   - If `scan-profile.json` contains `naming_conventions[]`, present detected conventions as pre-populated candidates for confirmation

   **4c. Anti-Patterns** — Ask about forbidden patterns specific to this project:

   - "Are there any patterns, libraries, or approaches that code in this project must NOT use?"
   - If the answer reveals a pattern, ask clarifying follow-ups (scope, rationale, exceptions)
   - Continue until no further anti-patterns emerge

   Apply the **diff-derived suggestions protocol** (if diff archaeology patterns are available):
   - `governance_hint` filter: `anti_pattern` or `both`
   - `{CONFIRM_LABEL}`: `"anti-pattern"`
   - `{TOPIC_HEADING}`: `"patterns"`

   **4d. Governance Checkpoints** — Ask about human-approval gates:

   - "Are there any changes that require human approval before implementation?"
   - Examples: schema changes, public API changes, config migrations, access control changes
   - If the answer reveals a checkpoint, ask clarifying follow-ups (who approves, what triggers it, edge cases)
   - Continue until no further checkpoints emerge

   Apply the **diff-derived suggestions protocol** (if diff archaeology patterns are available):
   - `governance_hint` filter: `checkpoint` or `both`
   - `{CONFIRM_LABEL}`: `"governance checkpoint"`
   - `{TOPIC_HEADING}`: `"process patterns"`

   **4e. Operational Gotchas** — Ask about tooling, infrastructure, and environment pitfalls:

   - "What tooling or infrastructure pitfalls should developers watch out for in this project?"
   - Prompt with examples: "E.g., 'never run X without Y flag', 'this CI step silently swallows errors', 'file watches don't work on mounted volumes', 'the linter auto-fixes break this pattern'"
   - If `scan-profile.json` contains `architecture.build_system` or `architecture.test_infrastructure`, use these to prompt for build/test-specific gotchas
   - If the answer reveals a gotcha, ask clarifying follow-ups (trigger conditions, workaround, severity)
   - Continue until no further gotchas emerge

   **Inline routing** — For each gotcha, apply the governance routing test immediately after it's described:

   Ask: "Does this affect how features are designed and specced (governance), or is it operational knowledge about working in this repo?"

   | Route | Test | Destination |
   |-------|------|-------------|
   | **Governance** | Violating it would invalidate any feature spec | Constitution `## Anti-Patterns` as a MUST NOT statement |
   | **Operational** | Project-specific tooling/workflow knowledge | `.specify/memory/project-context.md` under `## Operational Gotchas` |

   Show the routing decision to the user:
   ```
   → Routed to [constitution / project-context.md]: "{gotcha summary}"
   ```

   If the user disagrees with a routing decision, re-route without argument.

   **4f. Principles** — Ask about governing principles (each will be passed through the litmus test in step 5):

   **4f-i. CLAUDE.md grading** (if CLAUDE.md exists):

   - Read the project's `CLAUDE.md`
   - For each section (by markdown heading), apply the gateability test — specifically, whether the section's rules would be checked by these two enforcement points:
     - `/speckit-plan` loads the constitution during planning (Outline step 2) and uses it to inform plan generation (step 4). Constitution compliance is then verified by Plan Review (auto-triggered via the `after_plan` hook)
     - `/speckit-analyze` checks "Detection Pass D: Constitution Alignment" during analysis (step 4D) — it flags spec requirements or plan elements that conflict with constitution principles
   - Assign a grade:
     - **A**: Directly gateable — contains enforceable principles or constraints
     - **B**: Indirectly useful — informs plan/spec generation (e.g., coding conventions that affect task decomposition)
     - **C**: Operational — affects how you interact with repo tooling, not what gets built (e.g., build commands, diff conventions)
     - **D**: Informational — identity, vocabulary, routing (e.g., mission statements, folder descriptions)
   - Present a graded table:

     ```
     CLAUDE.md sections graded for constitution candidacy:

     | Section | Grade | Recommendation |
     |---------|-------|----------------|
     | "Testing Requirements" | A | ☑ Include as principle |
     | "Code Style" | B | ☑ Include as convention |
     | "Build Commands" | C | ☐ Skip (operational) |
     | "Project Overview" | D | ☐ Skip (informational) |

     A/B-grade sections are pre-selected. Adjust selections, or accept all? (accept/adjust)
     ```

   - If user accepts: confirmed A/B sections become principle/convention candidates
   - If user adjusts: toggle selections per user input
   - Confirmed candidates join the same step-4 principle candidate pool that step 5's litmus test evaluates — they go through step 5 like any other candidate. `CLAUDE_MD_DECISIONS` (below) is used only for step 10's migration bookkeeping (routing already-approved content to its target heading); it is never a path that writes principles into the constitution directly, bypassing step 5.
   - Compile `CLAUDE_MD_DECISIONS`: a list of `{section, grade, decision: include|skip, target: "Core Principles"|"Conventions"|"Anti-Patterns"|"Governance Checkpoints"}`

   **4f-ii. diff_patterns evidence** (if `diff_patterns` exists in scan-profile.json):

   - Present relevant patterns informally as evidence for principle candidates — presented informally, not through the formal suggestions protocol (no `governance_hint` filtering)
   - Format:

     ```
     Patterns from your diff history that may inform principles:
     - "{summary}" ({occurrence_count} occurrences)
     - "{summary}" ({occurrence_count} occurrences)

     Consider these as you define principles below.
     ```

   - Patterns already surfaced in steps 4c/4d may overlap; the user handles dedup during selection

   **4f-iii. Open-ended question** (runs after the evidence presented above):

   - "Beyond the candidates above, what are the core principles that should govern how features are designed and implemented in this project?"
   - Prompt with examples if needed: "E.g., testability without runtime environment, every milestone produces a runnable artifact, core logic independent of UI framework"
   - Continue until no further principles emerge

   **4f-iv. Fallback**: When CLAUDE.md does not exist or contains no A/B-grade sections, skip 4f-i entirely and proceed directly with 4f-ii and 4f-iii — no regression from current behavior.

   **Convergence checkpoint** (adopted from `/speckit-specify`):
   - Do NOT present a convergence checkpoint before 2 questions have been asked
   - After a reasonable number of questions, present a convergence checkpoint with explored/remaining disclosure: "Explored ~N of ~M topic areas. Remaining: [brief list of unvisited spine topics — e.g., Conventions, Anti-Patterns, Governance Checkpoints, Operational Gotchas, Principles]. Proceed to next topic, or explore further?" Qualify estimates as approximate.
   - User MAY trigger early convergence at any time ("that's enough" / "proceed") — this is a COMPLETION and writes the constitution
   - Provide a distinct **quit/abandon** affordance ("quit" / "abandon") that ends discovery WITHOUT writing the constitution (preserves existing constitution + annotates deferred fields)

   **Convergence vs Abandonment**:
   - **Completion** (normal end of spine OR user-triggered "proceed" after 2-question floor): draft is assembled and written (step 9)
   - **Abandonment** (explicit "quit/abandon" OR session ends before convergence): existing constitution preserved unchanged; deferred fields annotated (not dropped); no write occurs

   The convergence "proceed" affordance and the "quit/abandon" affordance MUST be distinct so the command classifies the terminal state deterministically.

5. **Litmus test — Governance vs Design**: Evaluate each candidate principle collected in step 4f against the governance litmus test:

   For every principle, ask: "Would violating this invalidate ANY feature we might spec, or just ONE PARTICULAR design?"

   | Category | Scope | Example | Constitution? |
   |----------|-------|---------|---------------|
   | Governance constraint | Affects every feature | "Core logic testable without runtime environment" | Yes |
   | Governance constraint | Affects every feature | "Every milestone must produce a runnable artifact" | Yes |
   | Governance constraint | Affects every feature | "Game logic independent of rendering" | Yes |
   | Design decision | Affects one design | "Use Canvas for rendering" | No (but see below) |
   | Design decision | Affects one design | "Use requestAnimationFrame for game loop" | No (but see below) |
   | Design decision | Affects one design | "Vanilla JS only" | No (but see below) |

   **For principles that fail the litmus test** (design decisions):
   - Present the flagged principle to the user with the question: "This appears to be a design decision rather than governance. Would you like to:"
     - **Keep as governance constraint** (deliberate elevation — user has a rationale for treating it as non-negotiable across all features)
     - **Demote to design hint** (append to `.specify/memory/project-context.md` under a `## Design Hints` heading, creating it if absent, as design guidance for future specs, not governance)
   - If user chooses "Keep as governance constraint", add an annotation noting the deliberate elevation:
     - Example: "*(Deliberately elevated to governance — applies to all features per team decision)*"

   **Principles that pass the litmus test**: keep as constitution principles without annotation.

   **Remove unused template principle slots** rather than filling them with weak or design-level content.

   Print the Refinement progress bar after completing this step.

6. Draft the updated constitution content:
   - Replace every placeholder with concrete text (no bracketed tokens left except intentionally retained template slots that the project has chosen not to define yet—explicitly justify any left).
   - Preserve heading hierarchy and comments can be removed once replaced unless they still add clarifying guidance.
   - Ensure each Principle section: succinct name line, paragraph (or bullet list) capturing non‑negotiable rules, explicit rationale if not obvious.
   - Ensure Governance section lists amendment procedure, versioning policy, and compliance review expectations.
   - **Populate `## Conventions` section**:
     - If step 4b discovered conventions, write them as normative SHOULD statements
     - If naming conventions were detected from `scan-profile.json`, include them
     - If no conventions were discovered, write: "None defined"
   - **Populate `## Anti-Patterns` section**:
     - If step 4c discovered anti-patterns, write them as normative MUST NOT / SHOULD NOT statements (visible to `/speckit-analyze` Pass D)
     - Include any governance-routed gotchas from step 4e as MUST NOT statements
     - If no anti-patterns were discovered, write: "None defined"
   - **Populate `## Governance Checkpoints` section**:
     - If step 4d discovered governance checkpoints, write them as normative MUST statements (visible to `/speckit-analyze` Pass D)
     - If no governance checkpoints were discovered, write: "None defined"
   - **Write operational gotchas to `.specify/memory/project-context.md`**:
     - If step 4e produced operational-routed gotchas, append them to `.specify/memory/project-context.md` under `## Operational Gotchas` (create the heading if absent)
     - Each gotcha as a bullet: `- **{short label}**: {description} — {workaround if known}`
     - If the section already exists, merge new gotchas with existing ones (no duplicates)

7. Consistency propagation checklist (convert prior checklist into active validations):
   - Read `.specify/templates/plan-template.md` and ensure any "Constitution Check" or rules align with updated principles.
   - Read `.specify/templates/spec-template.md` for scope/requirements alignment—update if constitution adds/removes mandatory sections or constraints.
   - Read `.specify/templates/tasks-template.md` and ensure task categorization reflects new or removed principle-driven task types (e.g., observability, versioning, testing discipline).
   - Read each command file in `.specify/templates/commands/*.md` (including this one) to verify no outdated references (agent-specific names like CLAUDE only) remain when generic guidance is required.
   - Read any runtime guidance docs (e.g., `README.md`, `docs/quickstart.md`, or agent-specific guidance files if present). Update references to principles changed.

8. Validation before final output:
   - No remaining unexplained bracket tokens.
   - Version line is correctly incremented.
   - Dates ISO format YYYY-MM-DD.
   - Principles are declarative, testable, and free of vague language ("should" → replace with MUST/SHOULD rationale where appropriate).

9. Write the completed constitution back to `.specify/memory/constitution.md` (overwrite):

   **Sentinel strip (defense-in-depth)**: After writing the generated constitution, verify that the sentinel comment `<!-- speckit:constitution:placeholder -->` is NOT present in the output. If it is (e.g., template content leaked into the generated constitution), strip it. The command writes fresh content so the sentinel should never appear, but this check makes that guarantee explicit.

   **Interrupted-discovery guard**: Only write if discovery completed (normal end of step 4 spine OR user-triggered early convergence via "proceed" affordance after the 2-question floor).

   **If discovery was abandoned** (explicit "quit/abandon" affordance OR session ended before convergence):
   - Preserve the existing valid constitution file unchanged
   - Annotate any deferred fields in the constitution with a comment noting they were not updated in this session
   - Do NOT write a new constitution file
   - Skip to step 11 (final summary) and note that the constitution was not updated due to abandonment

   **If discovery completed**:
   - Write the drafted constitution to `.specify/memory/constitution.md` (overwrite)
   - Proceed to step 10

---

*The constitution update is complete (steps 1-9). The following step is an optional, independent workflow that evaluates CLAUDE.md for content that belongs in the constitution.*

10. **CLAUDE.md Split Workflow**: Apply the CLAUDE.md migration decisions confirmed during step 4f discovery. This step performs migration only — grading and presentation already happened in step 4f-i; step 10 does not re-grade.

   **Step 10a — Detection:**
   - Check if `CLAUDE.md` exists in the project root
   - If it does not exist, output:
     > **Tip:** When you create a CLAUDE.md, you can import the constitution with `@.specify/memory/constitution.md` at the top of the file. This makes constitution principles available in every session without duplication. Note: `@` import is Claude Code-specific. For other agents, copy constitution principles into AGENTS.md or your agent's equivalent.
   - Then skip to step 11

   **Step 10b — Apply Split:**

   Using `CLAUDE_MD_DECISIONS` compiled in step 4f-i:
   1. For each section with `decision: include` in `CLAUDE_MD_DECISIONS`, route it to its target heading:
      - `Core Principles` target → `## Core Principles`
      - `Conventions` target → `## Conventions`
      - `Anti-Patterns` target → `## Anti-Patterns` (MUST NOT / SHOULD NOT statements about forbidden approaches)
      - `Governance Checkpoints` target → `## Governance Checkpoints` (MUST-approval statements about human gates)
   2. Remove moved sections from `CLAUDE.md`
   3. If `CLAUDE.md` does not already start with `@.specify/memory/constitution.md`, add it as the first line
   4. Add a comment on the line after the import: `<!-- @import is Claude Code-specific. For other agents, copy constitution principles into AGENTS.md or equivalent. -->`
   5. Increment the constitution version (MINOR — new principles added from CLAUDE.md split)
   6. Output a summary: what moved, what stayed, new version number

   **Compaction fallback**: If `CLAUDE_MD_DECISIONS` was lost to context compaction between step 4f and step 10, do not re-grade from scratch. Instead, check which CLAUDE.md sections are already present in the constitution (written in step 9):
   - Section already present in the constitution → migrate it (remove from CLAUDE.md, add the `@import` if missing)
   - Section absent but a quick re-check shows it's clearly governance-grade (A/B) → prompt: "Step 4f decisions were lost to context compaction. These CLAUDE.md sections appear governance-grade. Migrate them? [list]"
   - Section absent and clearly operational/informational (C/D) → skip, no prompt

11. Output a final summary to the user with:
   - New version and bump rationale.
   - Any files flagged for manual follow-up.
   - CLAUDE.md split results (if step 10 ran).
   - Operational gotchas routed to `.specify/memory/project-context.md` (if step 4e produced any) — list each with its destination.
   - If discovery was abandoned (step 4): note that the constitution was not updated and explain why.
   - Suggested commit message (e.g., `docs: amend constitution to vX.Y.Z (principle additions + governance update)`).

   **Artifact summary:**

   | Artifact | Path |
   |----------|------|
   | Constitution | `.specify/memory/constitution.md` |

   If operational gotchas were written:

   | Artifact | Path |
   |----------|------|
   | Constitution | `.specify/memory/constitution.md` |
   | Project context (gotchas) | `.specify/memory/project-context.md` |

   Print the final Output progress bar (all ✓).

Formatting & Style Requirements:

- Use Markdown headings exactly as in the template (do not demote/promote levels).
- Wrap long rationale lines to keep readability (<100 chars ideally) but do not hard enforce with awkward breaks.
- Keep a single blank line between sections.
- Avoid trailing whitespace.

If the user supplies partial updates (e.g., only one principle revision), still perform validation and version decision steps.

If critical info missing (e.g., ratification date truly unknown), insert `TODO(<FIELD_NAME>): explanation` inline in the constitution body.

Do not create a new template; always operate on the existing `.specify/memory/constitution.md` file.

## Post-Execution Checks

**Post-completion hook (MANDATORY — DO NOT SKIP)**: Before running the hook, export extra commit paths so the SDD commit hook includes constitution-related files outside `specs/` and `.specify/`:

```bash
export SPECKIT_COMMIT_EXTRA_PATHS="CLAUDE.md:.claude/"
```

Then run `speckit run dispatch-hooks.sh hooks.after_constitution` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`) — if a mandatory hook's invocation fails or terminates abnormally, halt with "`<stage>` completed but the follow-up step failed — re-run `/<command>` to retry" (a hook returning a result, including a blocking one, is a successful dispatch, not a failure); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue.
