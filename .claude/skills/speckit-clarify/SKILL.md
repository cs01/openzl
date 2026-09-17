---
name: speckit-clarify
description: 'SpecKit SDD pipeline: identify underspecified areas in `specs/<feature>/spec.md` via gap-driven clarification questions with a risk-scaled convergence checkpoint.'
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:meta
  meta_preset_strategy: replace
  meta_preset_upstream: speckit.clarify
user-invocable: true
disable-model-invocation: false
---



# Speckit Clarify Skill

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Workspace check (MANDATORY)**: Run `speckit run require-workspace.sh`. This resolves the workspace from any subdirectory and produces the same fixed message when there is no workspace above the current directory. On a non-zero exit, relay its stderr output to the user verbatim — do not paraphrase, reword, summarize, or translate it; do not prepend or append anything (no preface, heading, or attribution such as "require-workspace.sh failed:"); do not name the script, the command, the exit code, or any internal path — then halt. On exit 0, proceed silently to the next check.

**Pre-execution hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.before_clarify` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue. Wait for all hooks to complete before continuing.

## Outline

This command identifies underspecified areas in your spec through focused clarification questions — resolving ambiguity now prevents rework during planning and implementation.

Note: This clarification workflow is expected to run (and be completed) BEFORE invoking `/speckit-review` or `/speckit-plan`. If the user explicitly states they are skipping clarification (e.g., exploratory spike), you may proceed, but must warn that downstream rework risk increases.

Execution steps:

Before starting work, briefly tell the user what this stage does and why it matters (emphasize 'resolving ambiguity'). Print the introduction in bold.

**Output discipline**: Suppress routine setup narration — step numbers and variable bindings. Errors, warnings, interactive prompts, and the command's primary output are not routine narration and must still be shown.

1. **Parse and strip flags**: Check `$ARGUMENTS` for `--auto` and `--skip-constitution-scan` flags. If present, record which flags were found, then strip them as standalone leading tokens from `$ARGUMENTS` before proceeding. Do not strip flags embedded in the feature description text (e.g., "Add --auto flag support" should keep the flag text).

   After stripping, continue with the remaining `$ARGUMENTS` as the feature description.

   **Resolve constitution-scan suppression**: Using the `--skip-constitution-scan` flag recorded above, resolve whether the constitution scan (step 3) runs: CLI flag present > `.specify/config.yml` `clarify.constitution_scan` value (if the file exists and the value is a valid boolean) > default (`true`, scan runs). If `.specify/config.yml` has invalid YAML or the value is not boolean, warn and use the default. Carry the resolved value into step 3.

2. Run `.specify/scripts/bash/check-prerequisites.sh --json --paths-only` from repo root **once** (combined `--json --paths-only` mode / `-Json -PathsOnly`). Parse minimal JSON payload fields:
   - `FEATURE_DIR`
   - `FEATURE_SPEC`
   - (Optionally capture `IMPL_PLAN`, `TASKS` for future chained flows.)
   - If JSON parsing fails, abort and instruct user to re-run `/speckit-specify` or verify feature branch environment.
   - For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

3. Load the current spec file. Parse the `risk` field from YAML frontmatter (low/medium/high). If the `risk` field is absent or has an unrecognized value, default to `medium`. Use this risk level to set the convergence checkpoint threshold for step 5: **3 for low, 5 for medium, 8 for high**. The threshold is where you pause and ask the user whether to keep going — it is not a ceiling on how many questions the session may ask. Perform a structured ambiguity & coverage scan using this taxonomy. For each category, mark status: Clear / Partial / Missing. Produce an internal coverage map used for prioritization (do not output raw map unless no questions will be asked).

   **Compact spec scoping (Meta preset enhancement):** Also parse the `complexity` field from YAML frontmatter. If the `complexity` field is absent or contains an unrecognized value, treat the spec as standard. If the spec has `complexity: compact` in its YAML frontmatter:
   - If the Success Criteria section is absent: skip "Core user goals & success criteria" gap detection for that portion. If present: scan normally.
   - If the Key Entities section is absent: skip "Entities, attributes, relationships" gap detection. If present: scan normally.
   - Recognize when discovered complexity during clarification warrants recommending a compact-to-standard upgrade: if clarify surfaces ≥3 new gap areas not covered by the compact format, recommend upgrading. (This threshold is a starting heuristic — calibrate based on observed upgrade rates after implementation.)
   - Note: "Compact spec — adjusting coverage scan to skip legitimately omitted sections."

   Functional Scope & Behavior:
   - Core user goals & success criteria
   - Explicit out-of-scope declarations
   - User roles / personas differentiation

   Domain & Data Model:
   - Entities, attributes, relationships
   - Identity & uniqueness rules
   - Lifecycle/state transitions
   - Data volume / scale assumptions
   - Schema change acknowledgment (does the feature require new fields, tables, migrations, or storage changes — and are they documented?)

   Interaction & UX Flow:
   - Critical user journeys / sequences
   - Error/empty/loading states
   - Accessibility or localization notes

   Non-Functional Quality Attributes:
   **Risk-based taxonomy scoping**: If spec risk is `low`, skip the "Non-Functional Quality Attributes"
   category entirely. The remaining categories provide sufficient coverage for low-risk features,
   and review agents (AC, RA) cover security/compliance concerns as a safety net.

   - Performance (latency, throughput targets)
   - Scalability (horizontal/vertical, limits)
   - Reliability & availability (uptime, recovery expectations)
   - Observability (logging, metrics, tracing signals)
   - Security & privacy (authN/Z, data protection, threat assumptions)
   - Measurement methodology (how metrics are collected, baseline definitions, what "improvement" means quantitatively)
   - Timeout and threshold values (specific numeric values for timeouts, retry limits, rate limits, circuit breaker thresholds)
   - Compliance / regulatory constraints (if any)

   Integration & External Dependencies:
   - External services/APIs and failure modes
   - Data import/export formats
   - Protocol/versioning assumptions
   - Injection point enumeration (where the feature hooks into existing systems — middleware, event handlers, lifecycle callbacks, extension points)

   Edge Cases & Failure Handling:
   - Negative scenarios
   - Rate limiting / throttling
   - Conflict resolution (e.g., concurrent edits)

   Constraints & Tradeoffs:
   - Technical constraints (language, storage, hosting)
   - Explicit tradeoffs or rejected alternatives

   Terminology & Consistency:
   - Canonical glossary terms
   - Avoided synonyms / deprecated terms

   Completion Signals:
   - Acceptance criteria testability
   - Measurable Definition of Done style indicators

   Misc / Placeholders:
   - TODO markers / unresolved decisions
   - Ambiguous adjectives ("robust", "intuitive") lacking quantification

   For each category with Partial or Missing status, add a candidate question opportunity unless:
   - Clarification would not materially change implementation or validation strategy
   - Information is better deferred to planning phase (note internally)

   **3a. Constitution Scan (Meta preset enhancement):** If step 1 resolved constitution-scan suppression to true, skip this substep entirely and record `scan_state: suppressed` for step 9. Otherwise, resolve the constitution from `REPO_ROOT/.specify/memory/constitution.md` — `REPO_ROOT` comes from step 2's `check-prerequisites.sh --json --paths-only` payload; never resolve against the process's current working directory, since `--project DIR` relocates `REPO_ROOT` and a cwd-relative read would silently load the wrong project's constitution.

   - **If the file does not exist**: record `scan_state: no_constitution` for step 9. Complete without error or warning. Unlike `/speckit-analyze`, whose job is constitution *compliance* and which reports a missing constitution as a CRITICAL finding, this stage's job is gap *discovery* — the constitution is supplementary context here, not the subject of a check, so a missing file is a supplementary-context gap rather than a check failure. This matches `/speckit-specify`'s optional-input pattern for the same file, not `/speckit-analyze`'s required-input pattern for it — a deliberate divergence, not an inconsistency.
   - **If the file exists but cannot be read or parsed**: record `scan_state: unreadable` for step 9. A warning is permitted here (unlike the absent case, since an unreadable file is a condition the user can act on). Complete without error.
   - **If the file exists and parses**: first check whether the file contains the sentinel `<!-- speckit:constitution:placeholder -->`. If the sentinel is present, the constitution is an unconfigured placeholder — record `scan_state: placeholder_only` for step 9 (the default state of every fresh install, distinct from an absent constitution), skip principle extraction entirely, and do not use the placeholder content. If the sentinel is absent, extract each principle's heading and its normative statements (lines containing `MUST`/`MUST NOT`/`SHOULD`) — not the whole document, so context cost does not scale with total constitution length, mirroring `/speckit-analyze`'s own reduction to principle names plus normative statements. Decompose each filled principle into distinct obligations, one per normative statement.
   - Unlike this scan's own taxonomy categories, the constitution scan runs at every risk level — do not add a risk-gated skip for low-risk specs the way the Non-Functional Quality Attributes category does above; constitution-derived gaps only materialize when the project actually declared the obligation, so they are self-limiting without a risk gate.
   - A constitution scanned and evaluated with every extracted obligation already addressed by the spec (no candidate gaps survive the spec-answerable fence and already-addressed check below) is `scan_state: scanned_clear` for step 9 — distinct from both `placeholder_only` and `scanned_with_gaps`, so a clean pass is never misreported as a scan that never ran.
   - If a future upstream SpecKit release adds its own constitution scan to this command, that scan supersedes this one rather than both running — reconciling the two is a known obligation of that vendored upgrade, not something this scan needs to detect at runtime.

   **3b. Spec-Answerable Fence (Meta preset enhancement):** Apply this fence to each obligation extracted in 3a individually, never to a whole principle — a principle can carry both spec-level and implementation-level obligations, and each is classified on its own.
   - **Spec-answerable**: the spec is the artifact that would answer this obligation (it governs requirements, scope, acceptance criteria, or success measures, and the spec is silent or ambiguous on it). This obligation becomes a candidate gap for step 4.
   - **Implementation-level**: the obligation falls on implementation or documentation practice (code structure, formatting, documentation upkeep) rather than the spec's content. Excluded from candidate gaps — no question is generated.
   - **Ambiguous**: neither clearly spec-answerable nor clearly implementation-level. Excluded from candidate gaps, and recorded in the constitution coverage block (step 9) under an "ambiguous — not raised" disposition, so the exclusion is auditable rather than silent.
   - **Precedence against the plan-level-execution-detail exclusion above**: an obligation the spec is the artifact to answer is admitted even where its subject matter is executed at plan time — that exclusion applies to the answer's detail level, not to the obligation's subject. A constitution rule about test-coverage tiers is spec-answerable (the spec template has a Testing Strategy section) even though coverage is ultimately executed at plan/implementation time.
   - An obligation already fully addressed by the spec is not a candidate gap regardless of classification — treat it as covered, the same already-addressed test taxonomy-derived gaps use.

   **3c. Severity Classification (Meta preset enhancement):**
   After completing the taxonomy scan and before generating questions, classify each identified gap by severity:
   - **CRITICAL**: Blocks correctness or rollout. Missing this clarification would cause the implementation to fail core acceptance tests, violate hard constraints, or be unshippable.
   - **HIGH**: Production risk. Missing this clarification introduces security vulnerabilities, data integrity issues, performance degradation, or operational incidents.
   - **MEDIUM**: Tech debt seed. Missing this clarification leads to maintainability issues, inconsistent UX, or future refactoring cost, but does not block initial delivery.

   **Classifying a constitution-derived gap**: The same three tiers apply, but a governance obligation's severity derives from the downstream cost of the gap surviving into plan and implementation — not from the normative strength of the obligation's wording. A constitution `MUST` does not by itself imply CRITICAL.
   - **CRITICAL**: The missing obligation would cause plan review, analyze, or verify to block or reject the artifact outright once it exists.
   - **HIGH** (the default tier for most governance gaps): The obligation would not itself block a gate, but its absence is first caught downstream (plan review, analyze, or verify) and forces a spec-plus-artifact rework cycle.
   - **MEDIUM**: The obligation is spec-answerable but its omission has low downstream cost (e.g., a completeness-style declaration with no gate dependency).

   Do not inherit `/speckit-analyze`'s rule that constitution violations are always CRITICAL — that rule serves analyze's compliance-enforcement job, not clarify's gap-discovery job.

   Use this classification to prioritize questions in step 4. Severity is an internal ordering signal — do not show severity labels to the user during question presentation. Severity labels appear only in the final coverage summary table (step 9).

4. Generate (internally) a prioritized queue of candidate clarification questions. Do NOT output them all at once. Queue **every** gap worth asking about — do not truncate the queue to the checkpoint threshold, and do not drop a gap because of a count. Apply these constraints:
    - Each question must be answerable with EITHER:
       - A short multiple‑choice selection (2–5 distinct, mutually exclusive options), OR
       - A one-word / short‑phrase answer (explicitly constrain: "Answer in <=5 words").
    - Only include questions whose answers materially impact architecture, data modeling, task decomposition, test design, UX behavior, operational readiness, or compliance validation.
    - **Severity-first ordering (Meta preset enhancement):** Sort candidate questions by severity descending (all CRITICAL before any HIGH, all HIGH before any MEDIUM). Within a severity tier, apply the Impact × Uncertainty heuristic as a tiebreaker. A CRITICAL gap with low Impact×Uncertainty always precedes all HIGH gaps regardless of their scores.
    - Exclude questions already answered, trivial stylistic preferences, or plan-level execution details (unless blocking correctness).
    - Favor clarifications that reduce downstream rework risk or prevent misaligned acceptance tests.
    - A dense spec may legitimately surface more gaps than the checkpoint threshold — spec size drives gap count more than declared risk does.
    - **Constitution-derived gaps (Meta preset enhancement):** Candidate gaps from step 3a's constitution scan enter this same severity-ordered queue alongside taxonomy-derived gaps — same sort, same threshold, no separate track.
    - **Same-area merge (Meta preset enhancement):** Before finalizing the queue, check each constitution-derived gap against the taxonomy-derived gaps for the same underspecified area. Two gaps merge only when a single answer to one would fully discharge the other — if answering one would leave any part of the other's obligation unaddressed, do not merge; queue both. A merged gap carries the higher of its two source severities and is asked once. Its disposition (Resolved/Deferred/etc.) is reported only in the constitution coverage block (step 9) — the taxonomy coverage table reflects it solely through its category's existing Status cell, never as a second row. Report a merged gap "Resolved" in the constitution coverage block only when the recorded answer addresses the constitution-derived obligation specifically, not merely the taxonomy-derived facet of the merged question.

5. Sequential questioning loop:
    - Present EXACTLY ONE question at a time.
    - For multiple‑choice questions:
       - **Analyze all options** and determine the **most suitable option** based on:
          - Best practices for the project type
          - Common patterns in similar implementations
          - Risk reduction (security, performance, maintainability)
          - Alignment with any explicit project goals or constraints visible in the spec
       - **Constitution-derived questions (Meta preset enhancement):** the recommendation's reasoning MAY state the governing constitutional rule in plain language where that rule is the actual justification (e.g., "the project's constitution requires a stated test-coverage decision"). This is the only place a constitution-derived question may be distinguished from a taxonomy-derived one — never attach an origin marker or label to the question itself, and never reorder questions on the basis of origin.
       - Render all options as a Markdown table:

       | Option | Description |
       |--------|-------------|
       | A | <Option A description> |
       | B | <Option B description> |
       | C | <Option C description> (add D/E as needed up to 5) |
       | Short | Provide a different short answer (<=5 words) (Include only if free-form alternative is appropriate) |
       | Discuss | Let's explore this topic before choosing |

       - After the table, present your recommendation with clear reasoning (1-2 sentences explaining why this is the best choice).
       - Format as: `**Recommended:** Option [X] - <reasoning>`
       - **If `--auto` flag was detected (step 1)**: Auto-accept the recommended option. Annotate the answer with `[AUTO-RESOLVED]` when integrating into the spec (step 6). Record the decision in the auto-resolution log. Do NOT present the table or wait for user input — proceed directly to integration.
    - For short‑answer style (no meaningful discrete options):
       - Provide your **suggested answer** based on best practices and context.
       - Format as: `**Suggested:** <your proposed answer> - <brief reasoning>`
       - **If `--auto` flag was detected (step 1)**: Auto-accept the suggested answer. Annotate the answer with `[AUTO-RESOLVED]` when integrating into the spec (step 6). Record the decision in the auto-resolution log. Do NOT wait for user input — proceed directly to integration.
       - **Otherwise** (interactive mode): After the suggestion, add: `Or say "let's discuss" to explore first.`
    - After the user answers (interactive mode only):
       - "yes", "recommended", or "suggested" → accept the stated recommendation/suggestion.
       - "let's discuss" → explore trade-offs, then re-present the question.
       - Ambiguous reply → ask for quick disambiguation (same question; do not advance).
       - Once satisfactory, record in working memory (do not write to disk) and move to the next question.
    - **Convergence management**:
       - Continue asking in severity-first order for as long as each answer resolves a gap that materially changes the spec.
       - **If `--auto` flag was detected (step 1)**: no user is present to answer a checkpoint. Treat the threshold as a hard stop — ask nothing further once it is reached, and record every unresolved gap under Deferred with its severity. Autonomous runs stay bounded. This hard stop applies only to invocations that actually pass `--auto` — a dispatch that instructs an agent to pick the recommended answer without passing the flag runs the interactive branch instead, with no hard stop.
       - **On reaching the checkpoint threshold from step 3** (3 / 5 / 8 by risk), interactive mode pauses before the next question and presents a convergence checkpoint disclosing roughly how much has been covered and what is left:

         > Resolved N of ~M identified gaps. Remaining: [unresolved categories, highest severity first]. Continue clarifying, or proceed with the spec as it stands?

         Qualify the counts as approximate. Present it as a structured choice with a freeform option and a "let's discuss" escape hatch.
       - If the user elects to continue, keep asking and re-present the checkpoint every 3 further questions.
       - Stop asking further questions when:
          - All critical ambiguities resolved early (remaining queued items become unnecessary), OR
          - User signals completion ("done", "good", "no more", "that's enough", "proceed"), OR
          - User declines to continue at a convergence checkpoint, OR
          - The queue is exhausted.
       - **In interactive mode there is no hard ceiling on question count.** The threshold governs when to check in, never whether a gap may be raised. An unresolved gap is either asked or reported under Deferred with its severity — never silently dropped because a count was reached.
    - Never reveal the text of future queued questions in advance. The convergence checkpoint discloses unresolved *categories*, not the questions themselves.
    - If no valid questions exist at start, immediately report no critical ambiguities.

6. Integration — accumulate in memory, write once at the end (batched update approach):
    - Maintain an in-memory representation of the spec (loaded once at start). Track all pending edits without writing to disk during the questioning loop.
    - For the first integrated answer in this session:
       - Ensure a `## Clarifications` section exists (create it just after `## Design Decisions` if present, otherwise just before `## Premise Validation`; if neither exists, place it after the last requirements/criteria section).
       - Under it, create (if not present) a `### Session YYYY-MM-DD` subheading for today.
    - For each accepted answer, apply the following to the in-memory spec:
       - Append a bullet line under the session subheading:
          - **If `--auto` flag was detected (step 1)**: `- Q: <question> → A: <final answer> [AUTO-RESOLVED]`
          - **Otherwise**: `- Q: <question> → A: <final answer>`
       - Apply the clarification to the most appropriate section(s):
          - Functional ambiguity → Update or add a bullet in Functional Requirements. **Atomic FR guard:** After integrating, apply the single-obligation test to each new or modified FR: could one half of this requirement pass verification while the other half fails? If yes, the FR is compound — split into separate atomic FRs (e.g., FR-NNNa, FR-NNNb) before proceeding.
          - User interaction / actor distinction → Update User Stories or Actors subsection (if present) with clarified role, constraint, or scenario.
          - Data shape / entities → Update Data Model (add fields, types, relationships) preserving ordering; note added constraints succinctly.
          - Non-functional constraint → Add/modify measurable criteria in Success Criteria > Measurable Outcomes (convert vague adjective to metric or explicit target).
          - Edge case / negative flow → Add a new bullet under Edge Cases / Error Handling (or create such subsection if template provides placeholder for it).
          - Terminology conflict → Normalize term across spec; retain original only if necessary by adding `(formerly referred to as "X")` once.
          - **Governance obligation (Meta preset enhancement)** → Integrate the answer into the spec section the constitutional obligation names, creating that section if the spec template defines one. Where no existing or definable section is the right target, do not write the answer only as a `## Clarifications` bullet — instead record the obligation as `Unintegrated` in the constitution coverage block (step 9), so the gap between "asked" and "actually addressed in spec content" is auditable rather than silently dropped.
       - If the clarification invalidates an earlier ambiguous statement, replace that statement instead of duplicating; leave no obsolete contradictory text.
    - **Do NOT write to disk until step 8.** All edits accumulate in memory during the questioning loop.
    - Preserve formatting: do not reorder unrelated sections; keep heading hierarchy intact.
    - Keep each inserted clarification minimal and testable (avoid narrative drift).

    **Exception — `--auto` mode**: When `--auto` is active (no interactive session), write after each integration to minimize risk of losing auto-resolved decisions on unexpected termination.

7. Validation (performed once after all answers are collected, before writing):
   - Clarifications session contains exactly one bullet per accepted answer (no duplicates).
   - Every question asked beyond the checkpoint threshold was preceded by the user electing to continue at a convergence checkpoint.
   - Updated sections contain no lingering vague placeholders the new answer was meant to resolve.
   - No contradictory earlier statement remains (scan for now-invalid alternative choices removed).
   - Markdown structure valid; only allowed new headings: `## Clarifications`, `### Session YYYY-MM-DD`.
   - Terminology consistency: same canonical term used across all updated sections.

8. Write the updated spec back to `FEATURE_SPEC` (single batched write after all clarifications are collected and validated).

9. Report completion (after questioning loop ends or early termination):

   > **Context tip:** Clarifications are saved in spec.md. Consider /clear before /speckit-review (or /speckit-plan) to free context for the next phase.

   - Number of questions asked & answered.
   - Path to updated spec.
   - Sections touched (list names).
   - **Coverage summary table (Meta preset enhancement):** Present a markdown table with three columns in this exact order:

   | Category | Severity | Status |
   |----------|----------|--------|
   | Functional Scope & Behavior | CRITICAL / IMPORTANT / NICE-TO-HAVE | Resolved / Deferred / Clear / Outstanding |
   | Domain & Data Model | CRITICAL / IMPORTANT / NICE-TO-HAVE | Resolved / Deferred / Clear / Outstanding |
   | ... | ... | ... |

   Where:
   - **Severity**: The user-facing severity label (CRITICAL/IMPORTANT/NICE-TO-HAVE) mapped from the internal classification (CRITICAL/HIGH/MEDIUM respectively). If the category is Clear (no gaps), leave severity blank or mark as "—".
   - **Status**: Resolved (was Partial/Missing and addressed), Deferred (user converged before it was raised, or better suited for planning), Clear (already sufficient), Outstanding (still Partial/Missing but low impact).

   - **Constitution coverage block (Meta preset enhancement):** Immediately after the coverage summary table above, and before the Auto-Resolution Log section when present, render a separate block reporting the constitution scan's outcome. This block never alters the taxonomy coverage table's per-category row structure above.

     First line — state exactly one of the following, in wording that distinguishes each from every other:
     - "No constitution was present, so the scan did not run." (no constitution found at all)
     - "The constitution scan was suppressed for this session/project." (step 1 resolved suppression to true)
     - "A constitution was present but could not be read or parsed." (unreadable — a warning is permitted here, per step 3a)
     - "The constitution's principles are unfilled placeholders, so no spec-level obligations were declared." (every principle still bracketed)
     - "The scan ran, obligations were extracted and evaluated, and none were left unaddressed." (scanned, fully clear)
     - "The scan ran and one or more spec-level obligations were left unaddressed." (scanned, gaps follow below)

     If the constitution was partially authored (some principles filled, some still bracketed), add a second sentence noting this alongside whichever of the two scan-ran states above applies — never alongside the no-constitution, suppressed, or unreadable states.

     Second line — for every state above except "no constitution" and "suppressed": `Scanned against constitution version: <value>`, where `<value>` is the constitution's `**Version**:` line content, or `unversioned` if that line is absent or still a bracketed placeholder. This pins the block to the constitution state it was produced against, so a reader returning to the report later cannot mistake it for a statement about a constitution that has since been amended.

     If any constitution-derived gaps, ambiguous-excluded obligations (step 3b), or `Unintegrated` answers (step 6) exist this session, render an entry table:

     | Obligation | Severity | Disposition |
     |------------|----------|-------------|
     | <one-line obligation summary> | CRITICAL / IMPORTANT / NICE-TO-HAVE / — | Resolved / Deferred / Outstanding / Ambiguous — not raised / Unintegrated |

     - **Severity** uses the identical user-facing vocabulary as the taxonomy table above (CRITICAL/IMPORTANT/NICE-TO-HAVE) — never the internal CRITICAL/HIGH/MEDIUM labels. An "Ambiguous — not raised" entry was excluded before classification and uses `—`, the same blank-dash convention the taxonomy table uses for a no-gap category.
     - A merged gap (step 4) contributes exactly one row here, reporting "Resolved" only when the recorded answer addressed the constitution-derived obligation specifically — its taxonomy-side reflection is that category's existing Status cell only, never a second row in the taxonomy table.
     - A Deferred constitution-derived gap is re-derived on the next `/speckit-clarify` run — a Deferred disposition leaves no trace in `spec.md` for an already-addressed check to match against. The same already-addressed test that governs whether any gap is re-raised applies here too.
     - This block is advisory only within the session that produces it — no downstream stage reads it. Its value is telling the user what is outstanding before they move on, not carrying that record forward; enforcement remains with plan review, analyze, and verify.

   - **Auto-resolution log (if `--auto` flag was detected in step 1):**

     Include an `## Auto-Resolution Log` section in the completion report listing each clarification question, the auto-resolved answer, and reasoning:

     ```markdown
     ## Auto-Resolution Log

     - **Question**: <question text>
     - **Auto-Resolved Answer**: <chosen answer>
     - **Reasoning**: <why this answer was chosen — e.g., "Recommended based on best practices for CLI tools" / "Suggested based on existing project patterns in CLAUDE.md">

     (Repeat for each auto-resolved question)
     ```

     **Constitution-derived auto-resolutions (Meta preset enhancement):** For each auto-resolved answer to a constitution-derived question, append `[GOVERNANCE-DERIVED ASSUMPTION — awaiting human confirmation]` to its log entry. With no user present to confirm the guess, a later stage must not read this answer as a satisfied constitutional obligation.

     After displaying the log in the completion report, append it to `auto-resolution-log.md` in the feature directory:

     1. Determine feature directory from `.specify/feature.json`
     2. Check if `{feature_directory}/auto-resolution-log.md` exists
     3. If not, create it with header: `# Auto-Resolution Audit Trail`
     4. Append a new section with timestamp:
        ```markdown
        ## speckit.clarify — {ISO 8601 timestamp}

        {decision entries from auto-resolution log above}
        ```

   - **Completion report next steps (Meta preset enhancement)** — determine this now, but do not display it yet; display it after the post-completion hooks (Post-Execution Checks below), so it is the last thing shown:
     - ➡️ **Successor obligation**: the next stage is `/speckit-review`. Always recommend it, regardless of risk level, test tiers, or file plan content. Whether to skip it is the user's call, never yours.
     - If outstanding or deferred high-severity ambiguities remain: Recommend re-running `/speckit-clarify` first, then `/speckit-review`, then `/speckit-plan`.
     - If all critical ambiguities resolved: Recommend `/speckit-review` as the next step.

## Write Pipeline State

Run: `speckit run write-pipeline-state.sh clarify status=complete questions_asked=<N> questions_answered=<N> auto_resolved=<N> constitution_gaps=<N>`

Replace `<N>` placeholders with actual counts from this session. `constitution_gaps` (Meta preset enhancement) counts how many of the total questions originated from the constitution scan — constitution-derived questions are already included in `questions_asked`/`questions_answered`, so this field attributes a subset of those totals rather than adding to them.

Behavior rules:

- If no meaningful ambiguities found (or all potential questions would be low-impact), respond: "No critical ambiguities detected worth formal clarification." and recommend `/speckit-review` as the next step.
- If spec file missing, instruct user to run `/speckit-specify` first (do not create a new spec here).
- Never pass the risk-scaled checkpoint threshold (3 for low-risk, 5 for medium-risk, 8 for high-risk) without pausing at a convergence checkpoint and asking the user whether to continue. Clarification retries for a single question do not count as new questions. There is no upper bound on the questions a user may elect to continue through.
- Avoid speculative tech stack questions unless the absence blocks functional clarity.
- Respect user early termination signals ("stop", "done", "proceed").
- If no questions asked due to full coverage, output a compact coverage summary (all categories Clear) then recommend `/speckit-review`.
- If the user converges with unresolved high-impact categories remaining, explicitly flag them under Deferred with rationale.
- The default recommendation after clarify is `/speckit-review`, not `/speckit-plan`.

Context for prioritization: $ARGUMENTS

## Post-Execution Checks

**Post-completion hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.after_clarify` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`) — if a mandatory hook's invocation fails or terminates abnormally, halt with "`<stage>` completed but the follow-up step failed — re-run `/<command>` to retry" (a hook returning a result, including a blocking one, is a successful dispatch, not a failure); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue.

**🔁 Display next-step guidance (ALWAYS RUN — DO NOT OMIT)**: Now that the hook(s) above have finished executing, display the completion report's next-steps recommendation computed above. This is the only time it is shown, and it must be the last thing shown to the user this turn.
