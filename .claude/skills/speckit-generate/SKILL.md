---
name: speckit-generate
description: 'SpecKit SDD brownfield: generate `specs/<feature>/spec.md` from existing code via interactive discovery or parallel generation.'
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:meta
  meta_preset_strategy: replace
user-invocable: true
disable-model-invocation: false
---



# Speckit Generate Skill

# Spec Generation from Existing Code

This command generates a formal specification from your existing code — reverse-engineering requirements, behaviors, and contracts so you can adopt spec-driven development without starting from scratch.

## User Input

```text
$ARGUMENTS
```

If the user provided arguments (file paths, module names, feature descriptions), use them to scope the generation. If empty, ask the user what area of the codebase to specify.

## Pre-Execution Checks

**Workspace check (MANDATORY)**: Run `speckit run require-workspace.sh`. This resolves the workspace from any subdirectory and produces the same fixed message when there is no workspace above the current directory. On a non-zero exit, relay its stderr output to the user verbatim — do not paraphrase, reword, summarize, or translate it; do not prepend or append anything (no preface, heading, or attribution such as "require-workspace.sh failed:"); do not name the script, the command, the exit code, or any internal path — then halt. On exit 0, proceed silently to the next check.

**Pre-execution hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.before_generate` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue. Wait for all hooks to complete before continuing.

## Step 0: Flag Parsing

**Parse and strip flags**: Check `$ARGUMENTS` for `--auto` and `--disable-auto-warning` flags. If present, record which flags were found, then strip them as standalone leading tokens from `$ARGUMENTS` before proceeding. Do not strip flags embedded in the feature description text (e.g., "Add --auto flag support" should keep the flag text).

After stripping, continue with the remaining `$ARGUMENTS` as the feature description.

## Step 1: Context Loading

Before starting work, briefly tell the user what this stage does and why it matters. Print the introduction in bold.

Before any exploration, load project context so that brainstorming and code exploration are grounded in what already exists.

1. **Read `CLAUDE.md`** from the project root. If it does not exist, emit a warning:
   ```
   ⚠️  No CLAUDE.md found. Generated spec may lack project context that improves agent accuracy.
   ```

   If it exists, extract:
   - Project overview, mission, domain terminology
   - Key concepts, anti-patterns, gotchas
   - Pointers to architecture docs, design docs, or other documentation directories
   - Diff conventions (title tag, reviewers, tags)

   **Grade CLAUDE.md quality** after reading it. Check for:
   - Project overview completeness (mission, domain, key systems)
   - Framework and technology stack documentation
   - Anti-patterns and gotchas (common mistakes, edge cases)
   - Conventions (naming, file structure, testing patterns)
   - Integration points and external dependencies

   If gaps are found (e.g., no mention of a framework used in the codebase, missing anti-patterns discovered during generation, unclear conventions), note them for the Step 7 recommendation.

2. **Follow CLAUDE.md pointers** — if CLAUDE.md references documentation directories (architecture docs, design docs, etc.), scan those for files relevant to the target area. Only read files whose names appear relevant — do not read every file.

3. **Read `.specify/memory/constitution.md`** if it exists — project principles and spec conventions that must be respected. If the file contains the sentinel `<!-- speckit:constitution:placeholder -->`, it is an unconfigured placeholder — skip reading it entirely and do not use its content as context for spec generation.

4. **Check for existing specs** — read `.specify/feature.json` and scan `specs/` to understand what has already been specified. Avoid duplicating existing specs.

## Step 1.5: Design Doc Loading

**When to run**: Only when `$ARGUMENTS` contains one or more `--doc <path>` flags. If no `--doc` flags are present, skip this step entirely.

1. **Parse `$ARGUMENTS` for `--doc` flags**: Extract all `--doc <path>` pairs from the arguments. Multiple `--doc` flags are supported (e.g., `--doc design.md --doc api-spec.md`). Remove the `--doc` flags from `$ARGUMENTS` after extraction so they don't confuse downstream scoping.

2. **Validate each doc path**: For each `--doc` path:
   - If the file does not exist: emit warning `⚠️ Design doc not found: <path>. Falling back to code-only generation.` and remove from the doc list.
   - If the file is binary or non-text (e.g., images, PDFs without text extraction): skip with warning `⚠️ Cannot parse <path> — unsupported format. Only markdown and plain text supported.`
   - If the file is empty or contains only whitespace: skip with warning `⚠️ Design doc is empty: <path>.`

3. **Read and parse each valid doc**: For each valid design doc, read the full content and extract structured claims. Organize claims into these categories:
   - **Architectural decisions**: System design choices, component relationships, technology selections
   - **Entity definitions**: Data models, schemas, field definitions, relationships
   - **Behavior descriptions**: How the system should behave, workflows, state transitions
   - **Data flow assertions**: How data moves through the system, input/output contracts
   - **Integration contracts**: APIs consumed or exposed, external service dependencies

   For each claim, record: the claim text, the source doc path, and the section/heading where it appeared.

4. **Handle no-claims case**: If all docs were parsed but no extractable claims were found (e.g., a one-line placeholder doc), log: `ℹ️ No extractable claims found in <path>. Proceeding with code-only generation.` and treat as if no `--doc` was provided.

5. **Store parsed claims** as context for downstream steps. The claims will be used in:
   - Step 4 (Execute Selected Mode): cross-reference claims against code findings
   - Step 4.5 (Gap Analysis): calibrate confidence based on doc agreement
   - Step 5 (Write Spec): produce the Drift Analysis section

## Step 2: Intent Exploration

**Auto-Resolution (T038)**: When `--auto` is active, apply auto-resolution logic to the brainstorming decision:

1. **Rich prompts or stack-scoped inputs** (diff numbers, bookmarks) → proceed with quick-checkpoint exploration (not full interactive exploration).
2. **Bare/unscoped prompts** (≤2 elements, no stack reference):
   - **Default behavior**: BLOCK with compounding-deviation warning (same format as specify command):
     ```
     🚫 AUTO-RESOLVE BLOCKED: Underspecified input

     Input has ≤2 elements and no stack reference. This often leads to:
     - Specs that miss key subsystems
     - Ambiguous scope boundaries
     - Planning failures due to underspecified requirements

     **Recommended actions**:
     1. Provide richer input: describe the feature, list affected files, or reference a design doc
     2. Use stack-scoped input: `speckit generate D12345` or `speckit generate my-bookmark`
     3. Override with `--disable-auto-warning` to proceed anyway (not recommended)

     Auto-resolution cannot safely proceed. Please refine your input or use `--disable-auto-warning`.
     ```
   - **With `--disable-auto-warning`**: Proceed to auto-brainstorming with a non-blocking warning:
     ```
     ⚠️ AUTO-RESOLVE: Proceeding with underspecified input (--disable-auto-warning active)

     Input has ≤2 elements. The generated spec may lack:
     - Complete subsystem coverage
     - Clear scope boundaries
     - Sufficient detail for downstream planning

     Recommend reviewing the spec carefully before `/speckit-plan`.
     ```
     Then proceed to quick-checkpoint brainstorming. Mark decision with `[AUTO-RESOLVED]` in completion report.
3. **Stack-scoped inputs** (bookmark, diff number) bypass the bare-prompt check — stack references are precise scope anchors.

**Stack-based scoping**: Check if `$ARGUMENTS` matches a Sapling bookmark or diff number pattern. If it does, derive feature scope from the stack automatically and skip open-ended brainstorming.

**If `$ARGUMENTS` matches a bookmark name (not starting with `D`) or diff number (`D\d+`)**:

1. **For bookmarks**: Run `sl status --change <bookmark>` to list changed files. If the bookmark spans a stack, use:
   ```bash
   sl log -r "ancestors(<bookmark>) & draft()" --template "{file_adds % '{file}\n'}{file_dels % '{file}\n'}{file_mods % '{file}\n'}"
   ```
   to identify all files across the stack.

2. **For diff numbers**: Run:
   ```bash
   sl log -r "phabdiff(D12345678)" --template "{file_adds % '{file}\n'}{file_dels % '{file}\n'}{file_mods % '{file}\n'}"
   ```
   to identify changed files. **Note**: `phabdiff()` is the correct Sapling revset for Phabricator diff resolution — bare `D12345678` is NOT a valid revset.

3. Present the file list with count. If >20 files, ask user to confirm or filter the scope.

4. If scope is confirmed, set `MODE = one-shot` and skip to Step 4 with the file-scoped mode. Record: "Scope derived from stack: <bookmark or diff number> (<N> files)"

**Error handling**:
- Bookmark not found → log "Bookmark not found: <name>" and fall back to interactive path-based scoping
- Diff not found locally → log "Diff not found locally: D<number>" and fall back to interactive
- Zero changed files → log "No changed files found in stack" and prompt for manual scope
- Excessive scope (hundreds of files) → present count, ask to confirm or filter
- `sl` commands fail (e.g., non-Sapling environment) → log "Sapling commands unavailable" and fall back to interactive with warning
- Path + bookmark conflict (both provided) → path takes precedence, bookmark ignored with warning: "Ignoring bookmark — path argument takes precedence"

**If no stack-based scope detected**, proceed with inline scope exploration:

Clarify what the user wants to specify through direct questioning. Brownfield codebases have many possible boundaries — the user needs to define scope before the agent starts reading files.

Use the project context loaded in Step 1 (CLAUDE.md, existing design docs, constitution, existing specs) so the exploration is grounded in what already exists rather than starting from scratch.

**Exploration guidelines**:
- Ask **one question at a time** about the area of codebase to specify
- When genuine alternatives exist, present **2-3 approaches with tradeoffs** rather than open-ended questions
- Prefer **multiple choice** when alternatives are discrete (e.g., "Which subsystem: (A) auth, (B) payments, (C) both?")
- Do **not** delegate to external skills for scope exploration
- **Convergence management**: After 8-10 questions, present a convergence checkpoint with explored/remaining disclosure: "Explored ~N of ~M subsystems/areas. Remaining: [brief list]. Proceed with current scope, or explore further?" Qualify estimates as approximate. Strongly recommend proceeding unless the user identifies new gap areas that would significantly impact scoping
- **Session interruption handling**: If the user stops responding mid-exploration, proceed with the context gathered so far. Annotate any unresolved gaps in the spec's "Gaps for Review" section with `[EXPLORATION-INCOMPLETE: <gap not explored>]`

Guide the exploration toward:
- What area of the codebase they want to specify
- What they plan to use the spec for (refactoring, onboarding, drift detection, new feature on top of existing code)
- Scope boundaries — which subsystems are in, which are out
- For broad scope: how it naturally splits into subsystems or modules
- For focused scope: which specific feature or subsystem to deep-dive
- **System context**: Is this target part of a larger system? What shared libraries, sibling projects, or cross-repo counterparts should I know about?

**Note**: The system context prompt above applies only when exploration occurs. In one-shot mode where stack-based scoping skips exploration, system boundary detection (Step 3.5) runs automatically without this prompt.

Once exploration produces a clear scope, recommend a mode:
- **Interactive discovery** if exploration identified a single focused subsystem, complex domain logic, or areas the user wants to explore conversationally
- **One-shot generation** if exploration identified multiple independent subsystems for broad coverage

Present the recommendation with rationale.

**Auto-Resolution (T041)**: When `--auto` is active, auto-accept the recommended mode without prompting. No `[AUTO-RESOLVED]` marker required for this decision.

If `--auto` is not active, wait for user confirmation or override.

Record the choice as `MODE` (either `interactive` or `one-shot`).

## Step 3: Determine Next Spec Number

Scan existing directories under `specs/` to determine the next sequential number:

1. List directories in `specs/`
2. Extract the highest `NNN` prefix (e.g., if `specs/002-auth/` exists, next is `003`)
3. If no `specs/` directory exists, start at `001`

Store the result as `NEXT_NUM`.

## Step 3.5: System Boundary Detection

**When to run**: Always run this step UNLESS `MODE = one-shot` was set by stack-based scoping. Stack-based scoping derives feature scope from a precise diff or bookmark — the scope is already tightly defined, so ecosystem context is less relevant. Skip to Step 4 in that case.

**Profile-first check**: Before running full detection, check if a valid project profile exists at `.specify/memory/project-profile.md`. A profile is valid if it: (a) exists, (b) is parseable markdown, and (c) contains at least a `## System Boundary` or `## System Context` section header. If the profile is malformed or truncated (missing `## Profile Complete`), treat it as absent and fall back to full detection below.

**If a valid profile exists**:
1. Read the profile's `## System Boundary` (or `## System Context` for pre-enhancement profiles) and `## Module Boundaries` sections
2. Use the profile data as the project-level ecosystem context baseline — skip all 4 project-level signal checks (import, sibling, cross-repo, metadata)
3. Perform a **lightweight subsystem import scan**: import-signal only (no sibling/cross-repo/metadata signals), scoped to the subsystem's files (as determined by Step 2 scoping). Read a sample of files in the subsystem scope and parse import statements to identify subsystem-specific dependencies not captured in the project-level profile
4. Merge subsystem findings additively: they appear in the spec's System Boundary section alongside profile-provided project context, annotated as "subsystem-specific." Subsystem findings do not modify the cached profile. When subsystem findings contradict profile data (e.g., different import rankings), both are presented without reconciliation
5. If the profile lacks `## Module Boundaries` (shallow profile from pre-deep-scan format), emit a warning: "Project profile is shallow (no Module Boundaries section). Consider re-running `/speckit-scan` for a deep profile with import analysis."
6. Check the profile's `## Profile Metadata` section for the `generated:` timestamp. If `## Profile Metadata` is absent (pre-deep-scan profile), skip staleness check silently. If the profile is older than 30 days, emit a staleness warning (non-blocking): "Project profile is X days old. Consider re-running `/speckit-scan` for a fresh profile."
7. Skip to the Confidence Assessment section below with profile-sourced confidence data

**If no valid profile exists** (or profile is absent/malformed): Run full detection as described below.

**For one-shot mode (non-stack-based)**: Run detection once at the target directory level before subsystem splitting. Each subsystem spec inherits the same System Boundary section with a note: "System boundary detected for `<target>/` (parent scope of this subsystem)."

Before diving into code, analyze whether this target is part of a larger system. Use multi-signal detection to identify ecosystem relationships:

### Detection Signals

Run all 4 signal types. If any signal check fails (timeout, VFS error, MCP unavailability), treat that signal as "not detected" and proceed with remaining signals. Note the failure in the Confidence Assessment (e.g., "Import signal: skipped — tool unavailable").

#### 1. Import Signal (HIGH Confidence)

Check for local workspace dependencies that indicate shared libraries or sibling projects:

**JavaScript/TypeScript** (package.json):
- Read `package.json` in the target directory
- Look for dependencies with `file:` prefix (e.g., `"@libs/shared": "file:../../libs/shared"`)
- These are ecosystem signals — shared libraries within the same monorepo or workspace
- **Exclude platform libraries**: Packages resolved from npm/yarn registries (no `file:` prefix) are platform dependencies, not ecosystem signals

**Hack/PHP** (use statements):
- Scan `.php` and `.hack` files for `use` statements
- Resolve relative imports to sibling directories (e.g., `use Libs\\Widget\\Template` resolving to `libs/widget_template/`)
- **Exclude platform libraries**: Framework imports (Ent, Thrift, React, Relay, XHP, GraphQL, Haste, Metro, Jest, Flow, Pyre) are platform, not ecosystem signals

**Platform library exclusion rule**: Packages from registries or monorepo-wide shared infrastructure are platform. Local workspace dependencies identified by `file:` prefix (JS) or relative `use` (Hack) are ecosystem signals.

#### 2. Parent/Sibling Enumeration (MEDIUM Confidence)

Enumerate sibling directories to detect naming patterns suggesting a shared system:

1. Run `ls` on the parent directory of the target
2. **If >20 children**: Filter by naming prefix to avoid overwhelming output
   - Split the target directory name on `_` (e.g., `rl_datagen_dashboard` → `rl`, `rl_datagen`, `rl_datagen_dashboard`)
   - Try progressively shorter prefixes: start with longest (`rl_datagen`), then try `rl`, then give up
   - Report siblings matching the longest prefix that yields <20 results
3. **If ≤20 children**: Report all siblings

Siblings with shared prefixes suggest a microservices architecture or a family of related projects.

#### 3. Cross-Repo Counterpart (MEDIUM Confidence)

Search for counterparts in other major trees by name/prefix match:

**For `nest/` targets**:
- Check `www/flib/intern/<prefix>*/` (3 directory levels deep max)
- Check `fbcode/<prefix>*/` (3 directory levels deep max)

**Search method**:
- Use chained `ls` commands at known counterpart locations — NOT recursive `find` or `grep` (violates fbsource constraints)
- Example: `ls www/flib/intern/ | grep <prefix>`, then `ls www/flib/intern/<match>/` to verify
- Cap at top 5 matches by prefix overlap length (longest prefix match = highest relevance)

**For `www/` or `fbcode/` targets**: Apply reverse search (check `nest/` for counterparts)

#### 4. Metadata Signals (LOW Confidence)

Check for shared operational context:

- **Sibling CLAUDE.md files**: If siblings share CLAUDE.md content (oncall rotations, reviewer groups, architecture docs), they're likely part of a system
- **Shared oncall annotations**: Check if CLAUDE.md or README files mention the same oncall rotation
- **Shared reviewer groups**: Check if CLAUDE.md references shared reviewer aliases

### Confidence Assessment

Aggregate signals into an overall boundary confidence:

| Confidence Level | Condition | Outcome |
|-----------------|-----------|---------|
| **"detected"** | 2+ signal types agree (any combination of HIGH/MEDIUM/LOW showing the same ecosystem members) | Produce full `## System Boundary` section in spec |
| **"possible"** | 1 MEDIUM or HIGH signal only | Produce `## System Boundary` section with caveat line noting single-signal basis |
| **"not detected"** | 0 signals, or 1 LOW signal only | No `## System Boundary` section; add "System boundary: not detected" row to Confidence Assessment; add "target treated as self-contained" note to Gaps for Review |

**Signal agreement**: Signals "agree" when they identify the same ecosystem members (e.g., import signal finds `rl_widget_template`, sibling enumeration finds `rl_*` siblings). Different signals finding different members still counts as agreement if there's overlap.

### Graceful Degradation

If a signal check fails (timeout, VFS error, MCP tool unavailable):
- Treat that signal as "not detected" for confidence calculation
- Note the failure in the Confidence Assessment table: "Import signal: skipped — tool unavailable"
- Proceed with remaining signals

Do not halt generation due to signal failures. The worst case is a spec without a System Boundary section — still useful for downstream planning.

## Step 4: Execute Selected Mode

### If MODE is `interactive`

Explore the codebase conversationally with the user. Brainstorming already established scope and boundaries — this step focuses on understanding the CODE within those boundaries.

1. **Initial scan** — based on the scope from brainstorming, read key entry points:
   - Main classes, controllers, or modules
   - Configuration files
   - Test files (reveal intended behavior and edge cases)
   - Use the `search_files` MCP tool to find relevant files — never use `grep`, `find`, or `rg` directly

2. **Ask code-specific clarifying questions** — as you read code, ask the user about:
   - Intent behind non-obvious design choices
   - Which behaviors are intentional vs. accidental
   - Known edge cases or failure modes not visible in code
   - Historical context that explains surprising patterns

   **Auto-Resolution (T043)**: When `--auto` is active, skip code questions. Tag any ambiguous findings as low-confidence in the spec's Confidence Assessment table. No `[AUTO-RESOLVED]` marker required for this decision.

3. **Dispatch subagents for heavy research** — if you need to map dependency graphs, trace call chains across many files, or explore all callers of an API, dispatch a subagent to keep the main session context clean. The subagent should:
   - Use `search_files` MCP tool for code search
   - Read relevant files and report findings
   - Return a structured summary (not raw file contents)
   - **Trace error propagation paths**: For error handling, trace data propagation end-to-end: source function → data shape → intermediate handlers → final consumer. Cap at 3 representative flows, prioritizing paths that cross component boundaries. When >3 flows exist, note total count and selection rationale. **Fallback**: When error handling uses global boundaries (React `ErrorBoundary`) or implicit propagation (exception bubbling), document the error handling strategy rather than attempting flow tracing.
   - **Check for convention-based files**: Beyond direct import tracing, check for framework-loaded middleware, auto-discovered plugins, and convention-based files that may not appear in explicit imports but are loaded at runtime.
   - **Check reverse dependencies**: Check for reverse dependencies — sibling directories and known shared libraries (identified in Step 3.5 system boundary detection) that consume components from the target. Scope: siblings and known shared libraries only (not the entire monorepo).

4. **Cross-reference design doc claims** (only when `--doc` was provided in Step 1.5):
   - For each claim extracted from the design docs, compare it against code findings
   - Classify each claim:
     - `confirmed`: Doc claim matches observed code behavior
     - `evolved`: Code has intentionally diverged from the doc (new approach, refactored design, improved implementation)
     - `stale`: Doc describes something that no longer exists or has been superseded by newer code
     - `missing`: Doc claims a capability that was not found in the code (may be unimplemented, removed, or in a different location)
   - Record each drift entry with: doc claim text, code finding, classification, impact level (low/medium/high), and source doc path

5. **Synthesize into one spec** — after exploration, proceed to Step 5 to write the spec. Produce a single `spec.md`.

### If MODE is `one-shot`

Dispatch parallel subagents to explore subsystems. Exploration already identified the subsystem split — use it as the starting point.

1. **Refine scope split** — present the subsystem split from exploration with concrete file/directory mappings. The user already agreed to the conceptual split; this adds implementation detail:

   ```
   Scope split (from exploration):

   1. **[Subsystem A]** — [key files/directories]
   2. **[Subsystem B]** — [key files/directories]
   3. **[Subsystem C]** — [key files/directories]

   Each subsystem gets its own spec. Confirm or adjust?
   ```

2. **Wait for user confirmation** — do not launch subagents until the user confirms. They may want to adjust file mappings or merge/split subsystems.

   **Auto-Resolution (T039)**: When `--auto` is active, auto-confirm the subsystem split without prompting. No `[AUTO-RESOLVED]` marker required for this decision.

3. **Dispatch parallel subagents** — one per confirmed subsystem. Each subagent receives:
   - The project context loaded in Step 1
   - The specific subsystem scope (files, directories, entry points)
   - Instructions to explore code and produce a structured findings report with:
     - Purpose and responsibility of the subsystem
     - Key behaviors and workflows
     - Data entities and relationships
     - Error handling and edge cases
       - **Error flow tracing**: Trace error propagation paths end-to-end: source function → data shape → intermediate handlers → final consumer. Cap at 3 representative flows, prioritizing paths that cross component boundaries. When >3 flows exist, note total count and selection rationale. **Fallback**: When error handling uses global boundaries (React `ErrorBoundary`) or implicit propagation (exception bubbling), document the error handling strategy rather than attempting flow tracing.
     - Integration points with other subsystems
     - Inferred requirements (what the code enforces)
     - Confidence levels per finding (high/medium/low)
     - Gaps — areas where code was ambiguous or behavior unclear
     - **Convention-based files**: Beyond direct import tracing, check for framework-loaded middleware, auto-discovered plugins, and convention-based files that may not appear in explicit imports but are loaded at runtime.
     - **Reverse dependencies**: Check for reverse dependencies — sibling directories and known shared libraries (identified in Step 3.5 system boundary detection) that consume components from the target. Scope: siblings and known shared libraries only (not the entire monorepo).

4. **Cross-reference design doc claims** (only when `--doc` was provided in Step 1.5):
   - After subagent reports return, cross-reference design doc claims against the combined code findings
   - For each claim, classify as `confirmed`, `evolved`, `stale`, or `missing` (see interactive mode step 4 for classification definitions)
   - Record drift entries with: doc claim text, code finding, classification, impact level, and source doc path

5. **Synthesize findings** — as each subagent completes, emit a progress update: "Exploration: {subsystem} complete ({N} of {M})." When all subagents complete, review their reports. For each subsystem, proceed to Step 4.5 for gap analysis, then Step 5 to write a separate `spec.md`. Increment `NEXT_NUM` for each spec.

## Step 4.5: Gap Analysis and Scope Metrics

Before writing the spec, analyze the scoped area for test coverage gaps and present scope metrics:

1. **Scope metrics**:
   - Count source files in the scoped area
   - Count total lines across all source files
   - Present metrics to the user BEFORE writing the spec:
     ```
     Scope: 45 source files, 3,200 lines
     ```

   **Auto-Resolution (T040, T042)**: When `--auto` is active:
   - **Scope confirmation (>20 files)**: Auto-accept all files without prompting. If >50 files, emit a warning in the log but continue. No `[AUTO-RESOLVED]` marker required.
   - **Excessive scope prompts**: Auto-confirm without prompting. No `[AUTO-RESOLVED]` marker required.

2. **Test coverage gap detection**:
   - For each source file in scope, check for a corresponding test file
   - Test file patterns: same name with `test_` prefix or `Test` suffix, in a `tests/` or `__tests__/` directory
   - Example: `src/auth.py` → look for `tests/test_auth.py` or `tests/unit/test_auth.py`
   - List all source files that DO NOT have corresponding test files

3. **Profile-informed gaps**:
   - Check if `.specify/memory/project-profile.md` exists
   - If it exists:
     - Verify integrity: check for `## Profile Complete` section with `Status: complete`
     - If valid, read the `## Test Infrastructure` section to inform gap detection heuristics
     - Use known test patterns from the profile (e.g., if profile shows `__tests__/` directories, prioritize that pattern)
   - If it does not exist or is invalid, use default test file patterns only

4. **Staleness warning**:
   - If profile exists, parse `Generated:` timestamp
   - If >30 days old (default threshold), warn:
     ```
     ⚠️ Profile appears stale (generated YYYY-MM-DD, N days ago).
     Consider re-running `/speckit-scan` for up-to-date analysis.
     ```

5. **Gap remediation**:
   - For each source file without tests, suggest: "No tests for `<file>` → consider `/speckit-plan` with testing focus for `<module>`"
   - Group suggestions by module or subsystem for clarity
   - Example: "8 source files in `auth/` module lack tests → consider `/speckit-plan` with testing focus for auth module"

6. **Confidence calibration from design docs** (only when `--doc` was provided in Step 1.5):
   - For each spec section (User Scenarios, Requirements, Key Entities, Success Criteria), check whether the design doc claims and code findings agree:
     - **Agreement**: Doc and code describe the same behavior/structure → upgrade the section's confidence level by one step: low → medium, medium → high. High stays high.
     - **Disagreement**: Doc and code diverge → keep the code-derived confidence level unchanged. The divergence is already recorded as a drift entry in Step 4.
   - This calibration is applied when writing the Confidence Assessment table in Step 5. Note which sections were upgraded and why (e.g., "Confidence upgraded: doc confirms entity structure").

## Step 5: Write Spec

Read the spec template from `.specify/templates/spec-template.md`. If the template does not exist, use the standard SpecKit spec template structure (User Scenarios, Requirements, Success Criteria, Assumptions).

For each spec to write:

1. **Generate short name** — create a 2-4 word kebab-case name from the subsystem or feature (e.g., `auth-middleware`, `payment-processing`, `user-profile-sync`).

2. **Create spec directory**:
   ```
   mkdir -p specs/<NEXT_NUM>-<short-name>
   ```

3. **Write `spec.md`** with this structure:

   ```markdown
   # Feature Specification: [Feature Name]

   ---
   type: <feature|bugfix|refactor|infrastructure>
   risk: <low|medium|high>
   owner: <from CLAUDE.md or "TBD">
   created: <YYYY-MM-DD>
   source: reverse-engineered from existing code
   ---

   ## User Scenarios & Testing

   [Populated from code analysis — what the code actually does,
   expressed as user-facing scenarios]

   ## Requirements

   ### Functional Requirements

   [Each requirement derived from observed code behavior.
   Use FR-NNN numbering. Mark inferred requirements with
   (inferred) and verified requirements with (verified).
   Each FR must contain exactly one independent obligation — apply the single-obligation test:
   could one half of this requirement pass verification while the other half fails?
   If a single function bundles multiple independent behaviors, the FR is compound —
   split it into separate atomic FRs (one per behavior) instead of one FR describing
   the whole function.]

   ### Key Entities

   [Data models, their relationships, key attributes]

   ## System Boundary

   **Position**: This section appears after Requirements and before Success Criteria.

   **Include this section only when system boundary confidence is "detected" or "possible" (from Step 3.5).**

   **For "detected" confidence (2+ signals)** — full section without caveat:

   | Name | Type | Relationship |
   |------|------|--------------|
   | [Ecosystem member 1] | Shared Library / Sibling / Cross-Repo / Metadata | [Brief description of dependency direction] |
   | [Ecosystem member 2] | ... | ... |

   **[Ecosystem member 1]**: [1-2 sentence explanation of dependency direction and owned concerns. Example: "Shared UI component library consumed by this project and 4 sibling apps. Owned by the Platform team. Changes to the library require coordination across consuming apps."]

   **[Ecosystem member 2]**: [...]

   **For "possible" confidence (1 MEDIUM or HIGH signal only)** — include caveat line:

   *Note: System boundary detected from a single signal type. Confidence is reduced — verify ecosystem relationships during planning or implementation.*

   [Then include the same table and prose format as above]

   **For "not detected" confidence (0 signals or 1 LOW only)** — omit this section entirely. Instead, add a row to the Confidence Assessment table and a note to Gaps for Review (handled in T004).

   ## Success Criteria

   [Measurable outcomes based on what the code currently achieves]

   ## Assumptions

   [Assumptions made during generation — defaults chosen,
   scope boundaries inferred]

   ## Generation Notes

   This spec was reverse-engineered from existing code by `/speckit-generate`.

   **Profile consumption**: [If a project profile was consumed, note: "Project profile consumed (generated: <timestamp from Profile Metadata>, scan-depth: <depth>). Subsystem-specific imports added for <subsystem scope>." If full detection was performed: "No valid project profile found. Full 4-signal detection performed."]

   ### Confidence Assessment

   | Section | Confidence | Notes |
   |---------|------------|-------|
   | User Scenarios | high/medium/low | [what was inferred vs observed] |
   | Requirements | high/medium/low | [what was inferred vs observed] |
   | Key Entities | high/medium/low | [what was inferred vs observed] |
   | Success Criteria | high/medium/low | [what was inferred vs observed] |
   | System boundary | detected / possible / not detected | [Include this row. For "not detected": explain which signals were checked and why they didn't trigger. For signal failures: list which signals failed (e.g., "Import signal: skipped — tool unavailable")] |

   ### Gaps for Review

   - [List specific areas where the code was ambiguous]
   - [List behaviors that may be intentional or accidental]
   - [List cross-cutting concerns not fully traced]
   - **[If system boundary is "not detected"]**: Target treated as self-contained. If this assumption is incorrect (e.g., the target is part of a larger system not detected by automated signals), update the spec to document ecosystem relationships before planning.

   ### Source Files

   - [List the primary files/directories analyzed, using project-relative paths]

   ## Drift Analysis

   **Include this section only when `--doc` was provided in Step 1.5. Omit entirely for code-only generation.**

   **Source docs analyzed**: [list each --doc path provided]

   | Doc Claim | Code Reality | Classification | Impact |
   |-----------|-------------|----------------|--------|
   | [claim text from design doc] | [what the code actually does] | confirmed/evolved/stale/missing | low/medium/high |

   **When multiple `--doc` arguments were provided**, add a Source Doc column to attribute each entry:

   | Doc Claim | Code Reality | Classification | Impact | Source Doc |
   |-----------|-------------|----------------|--------|------------|
   | [claim text] | [code finding] | confirmed/evolved/stale/missing | low/medium/high | [doc path] |

   **Classification definitions**:
   - **confirmed**: Doc claim matches observed code behavior — no drift
   - **evolved**: Code has intentionally diverged from the doc (new approach, refactored design)
   - **stale**: Doc describes something that no longer exists or has been superseded
   - **missing**: Doc claims a capability not found in the code (may be unimplemented or removed)

   **Summary**: Drift Analysis: [N] drift entries ([X] confirmed, [Y] evolved, [Z] stale, [W] missing)

   ## Gap Report

   **Note**: This section is specific to `/speckit-generate` and does NOT appear in specs produced by `/speckit-specify`. Gap reports only make sense for brownfield-generated specs where we're analyzing existing code.

   ### Scope Metrics

   | Metric | Value |
   |--------|-------|
   | Source files | [N] |
   | Test files | [N] |
   | Total lines | [N] |
   | Test coverage ratio | [N/M] ([X]%) |

   ### Test Coverage Gaps

   | Source File | Has Test? | Suggested Action |
   |------------|-----------|-----------------|
   | [file] | No | `/speckit-plan` with testing focus for [module] |

   ### Remediation Suggestions

   - **[N] source files without tests** — consider `/speckit-plan` with testing focus for [untested files]
   - [Additional gap-specific suggestions based on Step 4.5 findings]
   ```

4. **Populate content from code analysis** — fill each section with findings from the exploration (interactive) or subagent reports (one-shot):
   - User Scenarios: derive from how the code is actually used (entry points, API handlers, CLI commands, test cases)
   - Requirements: derive from what the code enforces (validation, business rules, access control, error handling)
   - Key Entities: derive from data models, database schemas, Ent definitions, thrift types
     - **Enum field annotation**: When documenting enum-typed fields in entity tables, trace the enum to its defining class and annotate with the class name and relative file path. Don't just list enum values — show where the enum lives so readers know which file to examine.
       - Before: `DeliveryMode | enum (DIRECT/HITL/SUPPORTMATE)`
       - After: `DeliveryMode | WilsonDeliveryMode (from Delivery/WilsonDeliveryMode.php)`
   - Success Criteria: derive from what the code currently achieves (performance characteristics, capacity, reliability)
   - Assumptions: document defaults you chose where the code was ambiguous
   - Generation Notes: be honest about confidence levels and gaps

5. **Update `.specify/feature.json`** with the resolved feature directory:
   ```json
   {
     "feature_directory": "specs/<NEXT_NUM>-<short-name>"
   }
   ```
   For one-shot mode with multiple specs, set this to the last spec written.

## Step 5.5: Quality Gate Check

After writing each spec, check whether it meets the minimum content threshold for a useful brownfield specification. A spec without entity definitions or class inventories is a problem statement, not a spec — it cannot support cold-start implementation work.

1. **Check minimum content**:
   - **Entity definitions**: Does the `### Key Entities` section contain at least one named entity with attributes? An empty section or a section with only placeholder text fails this check. **Exception**: If the generated spec omits the `### Key Entities` section entirely (not merely present-but-empty), skip this check — an absent section signals the feature genuinely involves no data model. This exception is keyed on the generated spec's own content, never on the template's own conditional annotation (`### Key Entities *(include if feature involves data)*`), which is a fixed, always-present part of `spec-template.md` and would otherwise make the exception fire unconditionally for every spec.
   - **Class/module inventory**: Does the spec contain at least one named class, module, or component with its file location? This can appear in Key Entities, Requirements, or User Scenarios.

   `complexity` detection: not applicable — Generate does not consume `/speckit-specify`-produced specs.

2. **If below threshold AND `--doc` was provided** (enrichment attempt):
   - The source doc lacked implementation context, but the codebase may have discoverable entities.
   - Probe the codebase for entity definitions: search for Ent definitions (`class.*extends.*EntSchema`), data model files, database schema files, thrift types, or class definitions in the scoped area.
   - If entities are discovered, update the spec's `### Key Entities` section with the discovered entities and their attributes.
   - Re-check the quality gate after enrichment.

3. **If below threshold after enrichment** (or no `--doc` provided):
   - Add the following warning to the spec, after the Generation Notes section:
     ```
     ⚠️ QUALITY GATE: Spec below minimum content threshold. Missing: [entity definitions | class inventory | both]. Consider providing richer source docs or adding entity definitions manually.
     ```
   - Do NOT block spec generation — the warning is informational. The spec is still written and verified.

4. **If above threshold**: No action needed. The quality gate passes silently.

**Scope**: The quality gate runs for ALL generated specs (not just `--doc` specs). However, the enrichment probing step (step 2 above) is only triggered when `--doc` was provided — for code-only generation, if the spec lacks entities, only the warning is emitted.

## Step 6: Post-Generation Verification

After writing all spec(s), automatically invoke `/speckit-verify` to run multi-agent verification.

1. **Invoke verification** — run `/speckit-verify` against the generated spec(s). For one-shot mode with multiple specs, verify each one.

2. **On verification success**:
   - Report verification results to the user

3. **On verification failure** (any subagent times out, hits context overflow, or errors):
   - Write a partial `verification.md` in the spec directory with whatever results completed
   - Tell the user which verification agents failed
   - Instruct them to re-run `/speckit-verify` manually after addressing any issues

## Step 7: Report Completion

Report to the user:

**Artifact summary:**

| Artifact | Path |
|----------|------|
| Spec | `specs/<NNN>-<name>/spec.md` (one row per generated spec) |
| Verification report | `specs/<NNN>-<name>/verification.md` (if verification ran) |

- Mode used (interactive / one-shot)
- Verification results summary (passed / partial / failed)
- Generation Notes highlights — top 3 gaps or low-confidence areas to review
- Gap summary: Test coverage: N/M source files have tests (X%). Top gaps: [list top 3 untested modules or files]
- Drift Analysis summary (only when `--doc` was used): "Drift Analysis: N drift entries (X confirmed, Y evolved, Z stale, W missing)"
- Quality gate result: "Quality Gate: PASS" or "Quality Gate: WARNING — missing [entity definitions | class inventory | both]"
- Determine the **➡️ Next steps** recommendation, but do not display it yet — Step 9 displays it after the post-completion hook, so it is the last thing shown: review the spec, then run `/speckit-plan` to create an implementation plan, or `/speckit-clarify` to refine underspecified areas

**Auto-Resolution Log (T044)**: When `--auto` was active, include an `## Auto-Resolution Log` section in the completion report listing all decisions that were auto-resolved:

```
## Auto-Resolution Log

The following decisions were auto-resolved by `--auto` mode:

1. **Brainstorming**: [Auto-brainstormed (bare prompt + --disable-auto-warning) | Quick-checkpoint (rich/stack-scoped input)]
2. **Subsystem split**: Auto-confirmed [N] subsystems
3. **Scope confirmation**: Auto-accepted [N] files (>20 threshold)
4. **Mode recommendation**: Auto-accepted [interactive|one-shot] mode
5. **Excessive scope**: Auto-confirmed large scope ([N] files)
6. **Code questions**: Skipped (ambiguous findings tagged as low-confidence)
```

After reporting completion, append this log to `auto-resolution-log.md` in the feature directory recorded at step 5 (create if absent, append if exists) with a timestamped entry:

```markdown
## [YYYY-MM-DD HH:MM:SS] /speckit-generate (auto mode)

**Scope**: [feature/subsystem name]
**Spec(s)**: [spec paths]

**Decisions auto-resolved**:
1. Brainstorming: [details]
2. Subsystem split: [details]
3. Scope confirmation: [details]
4. Mode recommendation: [details]
5. Excessive scope: [details]
6. Code questions: [details]
```

**CLAUDE.md scaffolding recommendation** (only if no CLAUDE.md was found in Step 1):

If no CLAUDE.md exists at the project root, recommend creating one based on what was learned during generation. Present a scaffolded CLAUDE.md with:
- Project overview section populated from the subsystem/feature name and purpose
- Key file locations discovered during exploration
- Framework choices observed (build system, testing framework, language stack)
- Anti-patterns or gotchas discovered (e.g., enum namespaces, test file patterns, configuration loading)
- Conventions inferred from code (naming patterns, directory structure, import patterns)

Format the recommendation as:
```
📝 Recommendation: Create CLAUDE.md to improve future spec generation

Based on this generation session, here's a starter CLAUDE.md:

[scaffolded content]

Adding this file will help future `/speckit-generate` runs produce more accurate specs with better context.
```

**CLAUDE.md quality feedback** (only if CLAUDE.md exists but gaps were found in Step 1):

If CLAUDE.md exists but quality grading found gaps, present suggestions as:
```
📝 CLAUDE.md Quality Feedback

Your CLAUDE.md could be improved in these areas:
- [Gap 1]: [What's missing and why it matters]
- [Gap 2]: [What's missing and why it matters]

Consider adding these details to help future agents understand the codebase better.
```

Only report gaps that were discovered during generation and would have made the spec more accurate if they had been in CLAUDE.md upfront.

## Step 8: After-Hooks

**Post-completion hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.after_generate` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`) — if a mandatory hook's invocation fails or terminates abnormally, halt with "`<stage>` completed but the follow-up step failed — re-run `/<command>` to retry" (a hook returning a result, including a blocking one, is a successful dispatch, not a failure); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue.

## Step 9: Display Next-Step Guidance

Now that the hook(s) in Step 8 have finished executing, display the ➡️ **Next steps** line from Step 7. This is the only time it is shown, and it must be the last thing shown to the user this turn.

## Guidelines

### What to Capture vs. Skip

**Capture** — behaviors that define the feature:
- Business rules and validation logic
- Data flow and transformations
- Error handling and recovery strategies
- Access control and authorization checks
- Integration contracts (APIs consumed and exposed)
- Configuration-driven behavior

**Skip** — implementation details that belong in plans, not specs:
- Specific class hierarchies or inheritance patterns
- Framework-specific boilerplate
- Logging and observability instrumentation
- Performance optimizations (cache strategies, query tuning)
- Internal helper functions with no user-facing impact

### Confidence Tagging

Tag each inferred requirement with a confidence level:
- **High** — directly observed in code with test coverage
- **Medium** — observed in code but no tests, or inferred from naming/structure
- **Low** — inferred from context, comments, or conventions; no direct code evidence

### Search Strategy

- Use `search_files` MCP tool for all code search — never use `grep`, `find`, or `rg`
- Start with entry points (controllers, handlers, CLI commands) and trace inward
- Read test files — they reveal intended behavior and edge cases
- Check configuration files for feature flags, environment-dependent behavior
- Look at recent changes (`sl log <file>`) to understand evolution
