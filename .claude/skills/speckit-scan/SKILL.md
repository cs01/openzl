---
name: speckit-scan
description: 'SpecKit SDD pipeline: profile project into `.specify/memory/scan-profile.json` — languages, frameworks, test infra, conventions.'
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:meta
  meta_preset_strategy: replace
user-invocable: true
disable-model-invocation: false
---



# Speckit Scan Skill

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Workspace check (MANDATORY)**: Run `speckit run require-workspace.sh`. This resolves the workspace from any subdirectory and produces the same fixed message when there is no workspace above the current directory. On a non-zero exit, relay its stderr output to the user verbatim — do not paraphrase, reword, summarize, or translate it; do not prepend or append anything (no preface, heading, or attribution such as "require-workspace.sh failed:"); do not name the script, the command, the exit code, or any internal path — then halt. On exit 0, proceed silently to the next check.

**Pre-execution hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.before_scan` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue. Wait for all hooks to complete before continuing.

## Outline

Before starting work, briefly tell the user what this stage does and why it matters. Print the introduction in bold.

This command profiles your project — detecting languages, frameworks, test infrastructure, and naming conventions to inform every downstream pipeline stage.

**Output discipline**: Suppress routine setup narration — step numbers and variable bindings. Errors, warnings, interactive prompts, and the command's primary output are not routine narration and must still be shown.

**System context prompt** (optional, before automated detection): If `--auto` OR `--tier` is provided, auto-skip (proceed with codebase-only context without prompting). Otherwise, ask the user: "Any sibling projects, shared libraries, or cross-repo counterparts I should be aware of for this target?" User responses are incorporated into the `## System Boundary` section (step 8) alongside automated signal results. If the user declines or provides no input, proceed with automated detection only.


1. **Parse and strip flags**: Check `$ARGUMENTS` for `--auto` and `--tier` flags. If present, record which flags were found (including tier value for `--tier comprehensive` or `--tier lightweight`), then strip them as standalone leading tokens from `$ARGUMENTS` before proceeding. Do not strip flags embedded in the feature description text (e.g., "Add --auto flag support" should keep the flag text).

   After stripping, continue with the remaining `$ARGUMENTS` as the feature description.

2. **Determine scan root**: Use the location of `.specify/` as the project root. All file discovery and analysis is relative to this root.

   **Compute repo-relative path**: Determine the VCS root (`sl root 2>/dev/null || git rev-parse --show-toplevel 2>/dev/null`). If found, compute the project root as a path relative to the VCS root (e.g., `fbcode/rlce/speckit` instead of `/data/repos/fbsource/fbcode/rlce/speckit`). If the project root IS the VCS root, use `.`. If no VCS root is found, use the project directory name (basename) as fallback — never write an absolute checkout path to a persistent artifact. Store this repo-relative path for use in steps 10 and 11.

   **CLAUDE.md context** (optional): Check for a project-level CLAUDE.md:

   ```bash
   for f in .claude/CLAUDE.md CLAUDE.md; do
     [ -f "$f" ] && echo "$f" && break
   done
   ```

   If found, read the file and note human-curated context that supplements automated detection: file inventory, architecture descriptions, framework mentions, sibling projects, shared libraries, external dependencies. Use as supplementary signal in framework detection (step 5), system boundary detection (step 8), and module boundaries output (step 10). CLAUDE.md context does not override automated results but can surface items that pattern-based detection misses. When no CLAUDE.md exists, proceed with automated detection only.

3. **File discovery**: Use a two-pronged approach optimized for fbsource's virtual filesystem:

   **For language detection (file extension enumeration)**:
   - Use targeted `ls` commands on known top-level directories to enumerate file extensions
   - The fbsource prohibition targets recursive `find`/`grep`/`rg` traversals, not `ls` on specific directories
   - Enumerate extensions from directories like `src/`, `lib/`, `app/`, `tests/`, etc.

   **For content pattern matching (import detection, test file patterns)**:
   - Use `search_files` MCP tool exclusively
   - Never use `grep`, `find`, or `rg` for content search in fbsource

   **Stratified sampling strategy**:
   - 5,000-file cap project-wide to prevent timeout
   - 500 files per directory maximum
   - Report both sample size and total file count discovered
   - If total files exceed 5,000, select a stratified sample across directories

4. **Language detection**:
   - Count file extensions from directory listings
   - Compute proportions of each language
   - Group unrecognized extensions as "Other" with top 5 listed
   - Present results in table format:
     ```
     | Language | Files | Proportion | Evidence |
     |----------|-------|------------|----------|
     | Hack     | 310   | 62%        | .php extension |
     | Python   | 140   | 28%        | .py extension  |
     | Other    | 25    | 5%         | .thrift (15), .cconf (10) |
     ```

5. **Framework detection**:
   - Use `search_files` MCP tool to search for import patterns:
     - `use Ent\*` → Ent framework
     - `use Thrift\*` → Thrift
     - `require GraphQL\*` → GraphQL
     - `use XHP\*` → XHP
   - Report with evidence citations and file counts:
     ```
     | Framework | Evidence | Files Found |
     |-----------|----------|-------------|
     | Ent       | `use Ent\*` imports | 15 |
     | Thrift    | `use Thrift\*` imports | 8 |
     ```
   - When no frameworks are detected in a category, report "Not detected" rather than guessing

6. **Test infrastructure detection**:
   - Use `search_files` MCP tool to search for:
     - Buck test targets (search for `python_unittest`, `cpp_unittest`, etc. in TARGETS files)
     - Test directories (`__tests__/`, `tests/unit/`)
     - Test file naming patterns (`test_*.py`, `*Test.php`, `*_test.cpp`)
   - Report findings in table format:
     ```
     | Aspect | Detected | Evidence |
     |--------|----------|----------|
     | Test directories | Yes | `__tests__/`, `tests/unit/` |
     | Buck test targets | Yes | `TARGETS` files with `python_unittest` |
     | Test file pattern | Yes | `test_*.py`, `*Test.php` |
     ```
   - When no test infrastructure is detected in a category, report "Not detected"

7. **Naming convention sampling**:
   - Sample min(50, 10%) files per category using stratified sampling
   - Same sampling approach as step 3: 500 files per directory, capped at 5,000 total
   - Report convention, compliance percentage, and sample size:
     ```
     | Category | Convention | Compliance | Sample Size | Evidence |
     |----------|-----------|------------|-------------|----------|
     | Python files | snake_case | 94% | 50 | Sampled from `src/`, `lib/` |
     | PHP files | PascalCase | 88% | 50 | Sampled from `src/` |
     ```
   - When naming patterns are inconsistent, report the dominant convention with compliance percentage

7b. **Well-known path probing** (Layer 1 cross-root boundary detection):

   Derive the project name from the scan root's last path component (step 2).

   Probe the 12 well-known Meta monorepo path patterns below:

   | # | Pattern | Path Template | Signal | Relationship |
   |---|---------|---------------|--------|---------------|
   | 1 | Ent schemas | `www/flib/intern/entity/{project}` | Existence | `generated_dependency` |
   | 2 | GraphQL types | `www/flib/intern/graphql/types/{project}` | Existence | `generated_dependency` |
   | 3 | CLI scripts | `www/flib/intern/scripts/{project}` | Existence | `tight_coupling` |
   | 4 | Diff fields (Hack) | `www/flib/intern/diff/fields/{project}` | Existence | `tight_coupling` |
   | 5 | Diff fields (JS) | `www/html/intern/js/diff/fields/{project}_*` | Prefix | `tight_coupling` |
   | 6 | Power Search | `www/flib/intern/powersearch/apps/{project}` | Existence | `structural_colocation` |
   | 7 | Butterfly actions | `www/flib/intern/butterfly/actions/async/{project}` | Existence | `generated_dependency` |
   | 8 | Metamate commands | `www/flib/intern/metamate/engine/hack_commands/*/{project}` | Glob | `structural_colocation` |
   | 9 | Configerator | `configerator/source/**/{project}` | Search | `configuration` |
   | 10 | Skycastle workflows | `tools/skycastle/workflows2/**/{project}.*` | Search | `configuration` |
   | 11 | Entschema codegen | `www/flib/intern/entschema/generated/entity/{project}` | Existence | `generated_dependency` |
   | 12 | InternalFB frontend | `www/html/intern/js/internalfb/{project}` | Existence | `tight_coupling` |

   - **Existence** (#1–4, #6–7, #11–12): `ls` the pattern's parent directory, match entries case-insensitively against the project name.
   - **Prefix** (#5): `ls` `www/html/intern/js/diff/fields/`, match entries with a case-insensitive `{project}_` prefix. Each match is a separate discovery.
   - **Glob** (#8): `ls` `www/flib/intern/metamate/engine/hack_commands/`, check each subdirectory for a case-insensitive `{project}` child. Apply a 10-second timeout; silently skip on timeout.
   - **Search** (#9–10): Use MCP `search_files` scoped to `configerator/source/` and `tools/skycastle/workflows2/` respectively. Apply a 10-second timeout per probe; silently skip if `search_files` is unavailable or times out.

   **Inaccessibility handling**: Any probe to a path outside the current EdenFS checkout, a permission error, a tool-unavailability, or a timeout is silently skipped — no error, no warning, no impact on other probes.

   Each discovery carries: `path` (repo-relative, no trailing slash), `confidence: "HIGH"`, `detection_methods: ["well_known_pattern"]`, and the pattern's relationship type from the table above. Accumulate as interim data for steps 8g, 10, and 11.

8. **System boundary detection** (full signal set):

   Run multi-signal detection with all 4 signal types. If any signal check fails (timeout, VFS error, MCP unavailability), treat that signal as "skipped" with the reason noted in the confidence assessment, and proceed with remaining signals.

   #### 8a. Import Signal (HIGH Confidence)

   Perform import-based dependency analysis to identify cross-module and cross-project imports:

   **Import analysis sampling** (separate from step 3 file discovery):
   - Use `search_files` MCP to discover files by extension per top-level directory (module)
   - For each module, sort discovered files by size descending (larger files tend to have more imports)
   - Sample up to 50 files per module, cap at 500 files total project-wide
   - If global cap reached, distribute remaining budget proportionally across modules by file count
   - Note "sampled" in Module Boundaries output when the cap was applied

   **For each sampled file**, use the `Read` tool to read the file content and parse import statements:

   - **Hack** (`.php`, `.hack`): Parse `use` statements. A `use` statement is a local ecosystem signal if its first namespace segment matches a top-level directory under the project root (e.g., `use Wilson\Delivery\Handler` is local if `Delivery/` exists). All other `use` statements are platform dependencies.
   - **Python** (`.py`): Parse `import` and `from ... import` statements. Relative imports (`from .module import X`) and absolute imports matching the project namespace (dotted path resolves to a file under the project root) are ecosystem signals. External pip packages are platform dependencies.
   - **JavaScript/TypeScript** (`.js`, `.ts`, `.jsx`, `.tsx`): Parse `import` and `require` statements, including `import type`. Dependencies with `file:` prefix in `package.json` or relative path imports (`./`, `../`) are ecosystem signals. npm/yarn registry packages are platform dependencies.
   - **Other languages**: Report "Import analysis not supported for [language]."

   **Platform library exclusion heuristic**: Imports from paths outside the project root are platform dependencies, not ecosystem signals. The default exclusion list (Ent, Thrift, React, Relay, XHP, GraphQL) is illustrative — the path-based heuristic is the primary mechanism.

   **Partial failure handling**: If import analysis times out for a module, mark that module as "skipped (timeout)" in the Module Boundaries output (step 10) and continue with remaining modules. If the import signal fails entirely (e.g., MCP unavailable), note as "skipped — [reason]" in the confidence assessment.

   #### 8b. Parent/Sibling Enumeration (MEDIUM Confidence)

   - `ls` on parent directory, naming prefix filtering (>20 children → filter by prefix)

   #### 8c. Cross-Repo Counterpart (MEDIUM Confidence)

   - Search for counterparts in other major trees by name/prefix match. For `nest/` targets check `www/flib/intern/<prefix>*/` and `fbcode/<prefix>*/`. For `www/` or `fbcode/` targets apply reverse search (check `nest/` for counterparts). Use targeted `ls` at known counterpart locations, cap at top 5 matches by prefix overlap.

   #### 8d. Metadata Signals (LOW Confidence)

   - Check sibling CLAUDE.md files, shared oncall annotations, shared reviewer groups

   **Confidence assessment** (4 signal types):
   - **"detected"**: 2+ signal types agree (any combination showing the same ecosystem members), OR import signal alone at HIGH confidence with concrete evidence
   - **"possible"**: 1 MEDIUM signal only
   - **"not detected"**: 0 signals, or 1 LOW signal only

   Result: Determines whether to include `## System Boundary` section in step 10 output, and populates `## Module Boundaries` data

   #### 8e. Cross-Root Import Analysis

   From step 8a's Module Boundaries import data (top cross-module import targets per module), identify import targets that resolve to directories outside the scan root. Exclude known platform framework namespaces (Ent, Thrift, React, Relay, XHP, GraphQL — the same exclusion list step 8a uses). For remaining outside-root imports, verify the target resolves to a real directory via targeted `ls`. Each verified directory = one discovery with `confidence: "HIGH"`, `detection_methods: ["import_analysis"]`, `relationship: "tight_coupling"`. First-level imports only — no transitive traversal, and coverage is bounded by step 8a's sampling cap. If step 8a did not complete (shallow scan-depth, or 8a skipped/failed), 8e produces no discoveries.

   #### 8f. Name-Pattern Search

   Search for the project name across monorepo subtrees using MCP `search_files`, excluding all 12 Layer 1 pattern parent paths (step 7b) and known platform framework directories. Rank results before capping: prioritize directories that (a) contain source files, (b) are not under known platform paths, (c) are at depth ≥ 3 from repo root. Take the top 10 after ranking. Each unique matching directory = one discovery with `confidence: "MEDIUM"`, `detection_methods: ["name_pattern_search"]`, `relationship: "structural_colocation"`.

   #### 8g. Oncall Confirmation

   For every discovery accumulated so far from steps 7b, 8e, and 8f, search the discovered root and the primary root for oncall annotations — `<<Oncalls(` (Hack/XHP), `OWNERS` file entries, or BUCK oncall attributes. If they match, upgrade the discovery's confidence to `"HIGH"` and add `"oncall_confirmation"` to `detection_methods`. Best-effort: non-`www/` projects without standard oncall annotations may not benefit from this signal.

   **Layer 2 error handling**: Any Layer 2 signal check that fails (timeout, VFS error, tool unavailability) is treated as "not detected" — remaining signals proceed normally, and this degradation is not surfaced to the user.

   **Deduplication** (after all Layer 1 and Layer 2 signals complete): Normalize discovered paths (strip trailing slashes, repo-relative form), compare case-insensitively, and merge same-path entries keeping the higher confidence and unioning `detection_methods`. Exclude the primary scan root itself from the result set. The deduplicated result flows into steps 10 and 11 as `cross_root_boundaries`.

   **User-facing output**: After deduplication completes, report only the discovered roots in the deduplicated `cross_root_boundaries` list. Never report what was probed, found nothing, or was skipped, including tool-unavailability skips.

9. **Diff archaeology**: Analyze version control and code review history to extract recurring team patterns. This step runs at the user-selected depth tier and is wrapped in a step-level error containment boundary.

   **Error containment boundary**: If ANY part of diff archaeology fails (command errors, malformed output, LLM context overflow, or any unhandled exception), set `diff_patterns.status` to `"error"` and write an empty `patterns` array. Do not log immediately — step 10's "Scan-category warning" block owns the single user-facing message for this case, including when it supersedes an already-set `vc_signal_failed` or `phabricator_status` flag from earlier in this step. The `"error"` status is distinct from `"degraded"` (Phabricator-specific fallback) and `"no_history"` (no diffs found). This boundary prevents diff archaeology failures from blocking the scan's core profiling artifacts.

   **Tier selection**:

   If `--tier` was provided: use the specified tier (`comprehensive` or `lightweight`), skip the interactive tier menu, use default 6-month time window without prompting, do NOT write to auto-resolution-log.md. Proceed directly to signal extraction.

   Otherwise, if `--auto` is active: select Tier B (lightweight) automatically without prompting, use 6-month default time window without prompting. Log the tier selection to the auto-resolution log (see step 13).

   Otherwise (interactive mode): display the tier selection menu:

   ```
   Diff archaeology analyzes your project's version control and code review history
   to surface recurring patterns for governance consideration.

   Select analysis depth:
     A) Comprehensive (Recommended) — All signals including code review metadata.
        Surfaces reviewer feedback themes, CI failure patterns, and multi-round
        revision signals that are invisible to version control alone.
     B) Lightweight — Version control history only.
        Extracts reverted-diff patterns and commit message conventions.
        Faster, but misses the highest-value signals from code review.

   Time window:
     A) 6 months (Recommended) — Covers most active development cycles
     B) 3 months — Recent work only
     C) 12 months — Wider discovery window (enrichment still capped at top 50)
     D) Custom — Enter a specific number of months
     E) Let's discuss — Not sure which window fits this project

   Select time window: [A]
   ```

   **Time window**: After tier selection, prompt for time window selection. Default is 6 months (option A). If the user selects E ("Let's discuss"), ask what they're trying to capture (e.g., a specific build phase, a release cycle, the full project history), recommend a window based on their answer, and confirm before proceeding.

   **Lightweight tier signals** (both tiers extract these):

   Run the version-control signal extractor once and parse its JSON output:
   ```bash
   speckit run extract-vc-signals.sh \
     --path <project-path> --start <start-date> --end <end-date> --limit 200 2>/dev/null
   ```

   If the command exits non-zero, set `vc_signal_failed = true` and proceed with available data. Do not log a warning yet — step 10 below evaluates all diff-archaeology failures together and logs exactly one scan-category warning.

   The script emits:
   ```json
   {
     "reverts": [
       {"diff": "D12345", "hash": "abc123", "date": "2026-05-15", "desc": "Backout of D12000 — broke CI"}
     ],
     "commit_first_lines": ["[SpecKit] Add revert detection", "..."]
   }
   ```

   The revert queries live in the script — not inline — so their OR semantics are executable and unit-tested (see `tests/unit/test_extract_vc_signals.py`). The script runs one scoped `sl log -k` per keyword variant (`backout`, `revert`, `back out`), unions the results, and dedups by `phabdiff` (falling back to the short commit hash when `phabdiff` is empty). This is deliberate: passing one `-k` a pipe-joined value never matches, because Sapling's `-k` is a literal case-insensitive substring match and multiple `-k` flags are AND-ed (the pipe is treated as a literal character). The queries stay path- and date-scoped and `-l`-bounded — never an O(repo) `grep()` revset.

   **Revert detection**: From the `reverts[]` array, extract the revert reason from each entry's `desc` and group by revert target ("Backout of D12345" → original diff D12345 was reverted). Each revert = one pattern entry with `category: "revert"`, `governance_hint: "anti_pattern"`.

   **Commit convention extraction**: From the `commit_first_lines[]` array, analyze for recurring structural patterns:
     - Tag prefixes: `[SpecKit]`, `[NSync]`, `[ProjectName]`
     - Section formats: `WHY: ... WHAT: ...`
     - Conventional commits: `feat:`, `fix:`, `docs:`

   Patterns appearing in >50% of commits = high-confidence convention. Each detected convention = one pattern entry with `category: "commit_convention"`, `governance_hint: "checkpoint"`.

   **Comprehensive tier signals** (Tier A only):

   **Diff discovery**:

   Phabricator stores affected filepaths with the repo-tree prefix (e.g., `www/flib/...` or `fbcode/rlce/...`). Compute the project path relative to the repo root so the prefix query matches:
   ```bash
   REPO_ROOT=$(sl root --reason "scan - sl help root")
   if [ "$PWD" = "$REPO_ROOT" ]; then
     PHAB_PROJECT_PATH=""
   else
     PHAB_PROJECT_PATH="${PWD#"$REPO_ROOT"/}"
   fi
   ```

   If `PHAB_PROJECT_PATH` is empty, the scan is running from the repo root — omit the `--filepaths-affected-any-start-with` filter entirely (a root-level prefix would match all diffs in the repository).

   ```bash
   meta phabricator.diff list \
     ${PHAB_PROJECT_PATH:+--filepaths-affected-any-start-with="$PHAB_PROJECT_PATH"} \
     --time-created-is-after=<start-date> \
     --time-created-is-before=<end-date> \
     --repository-is=fbsource \
     --limit=200 \
     --sort-by=created --sort-direction=desc \
     --columns=number,comment_count,version,status,title \
     --output=json
   ```

   **Tiered graceful degradation**:
   - **If `list` fails** (Phabricator entirely unavailable):
     - Set `phabricator_status = "unavailable"` (do not log yet — see step 10)
     - Set `diff_patterns.status` to `"degraded"`
     - Continue with lightweight tier signals only (already extracted above)
     - Skip all remaining comprehensive-tier steps
   - **If `list` succeeds but `batch-get` fails** (partial Phabricator availability):
     - Set `phabricator_status = "partial"` (do not log yet — see step 10)
     - Set `diff_patterns.status` to `"degraded"`
     - Retain revision_rounds patterns from `list` output (see below)
     - Skip reviewer theme and CI failure extraction

   **Empty-result cross-check**: If `list` succeeds (exit 0) but returns zero diffs, AND the VC signal extractor found commits in the same time window, log a warning: "⚠ Phabricator query returned 0 diffs but version control found N commits — the query path may be wrong." This catches bad queries that return valid-but-empty JSON without triggering the failure path.

   **Smart sampling for enrichment**:
   - Sort discovered diffs by `comment_count + version` descending (highest-signal diffs first)
   - Select top-50 diffs for `batch-get` enrichment
   - Remaining diffs: metadata-only analysis (version count for revision rounds)
   - Log: "Enriching N of M discovered diffs (highest-signal subset)"

   **Per-diff enrichment** (top-50 diffs):
   ```bash
   meta phabricator.diff batch-get \
     --number=<D-number> \
     --include=comments,signals \
     --comments-inline-only \
     --signals-status=failed,warning \
     --output=json
   ```
   - Process sequentially (API latency ~1-2s per call)
   - Extract inline comment text and failed/warning signal names from each diff

   **Reviewer theme extraction**:
   - For each enriched diff: read inline comments, extract 1-3 theme labels using your own reasoning (e.g., "missing error handling," "lacks type safety," "unclear naming")
   - After all diffs: aggregate theme labels, cluster by semantic similarity using your own reasoning — group labels that describe the same underlying concern even if worded differently
   - Themes appearing in 3+ diffs = high-confidence `reviewer_theme` pattern
   - Determine `governance_hint` based on content: "don't do X" = `anti_pattern`, "always check Y" = `checkpoint`, mixed = `both`
   - **Context-budget escape hatch**: If accumulated comment volume from enriched diffs is excessive (estimated >50K tokens of raw comment text), reduce the enrichment set from 50 to a smaller number that fits within context capacity. Report "Enriched N of M (context budget)" in the output

   **CI failure pattern extraction**:
   - Group failed/warning signals by signal name across all enriched diffs (deterministic)
   - Signal names recurring in 3+ diffs = high-confidence `ci_failure` pattern with `governance_hint: "anti_pattern"`
   - Include signal type and representative error excerpts in evidence

   **Multi-round revision detection**:
   - From `list` output: identify diffs with version count ≥ 5
   - Each = one pattern entry with `category: "revision_rounds"`, `governance_hint: "checkpoint"`
   - Include diff title and version count in evidence

10. **Output generation**:

   **Scan-category warning** (evaluate exactly once, regardless of which tier or degradation path step 9 took): log at most one of the following, in priority order:
     - If `diff_patterns.status == "error"` (the error containment boundary fired): "⚠ Diff archaeology could not complete; continuing without version-control or code-review patterns." This case takes priority over all others below, even if `vc_signal_failed` or `phabricator_status` was also set earlier in step 9.
     - Else if `vc_signal_failed` and `phabricator_status` are both set: "⚠ Some signals could not be collected (version control and Phabricator)"
     - Else if only `vc_signal_failed` is set: "⚠ Some version control signals could not be collected"
     - Else if `phabricator_status == "unavailable"`: "⚠️ Phabricator unavailable. Falling back to version-control-only signals."
     - Else if `phabricator_status == "partial"`: "⚠️ Phabricator comment/signal retrieval failed. Retaining metadata-derived patterns."
     - Else: no warning needed.

   - Write `.specify/memory/project-profile.md` with sections in this order:

     Include header block with metadata:
     ```markdown
     # Project Profile

     Generated: YYYY-MM-DD HH:MM
     Project Root: <repo-relative path from step 2>
     Sample Strategy: stratified | exhaustive
     Total Files: <N>
     Files Sampled: <N>
     ```

     **Mandatory sections** (8):

     1. `## Profile Metadata` — machine-parseable metadata for downstream consumers:
        ```markdown
        ## Profile Metadata

        generated: YYYY-MM-DDTHH:MM:SSZ
        scan-depth: deep | shallow
        signals-attempted: import, sibling, cross-repo, metadata
        signals-completed: import, sibling, cross-repo, metadata
        ```
        - `generated`: ISO 8601 timestamp with timezone
        - `scan-depth`: `deep` if import analysis ran (even partially); `shallow` if import analysis was skipped entirely
        - `signals-attempted`: list of signal types that were attempted in step 8
        - `signals-completed`: list of signal types that completed successfully (omit any that were skipped or failed)

     2. `## Languages` (with table from step 4)
     3. `## Frameworks` (with table from step 5)
     4. `## Test Infrastructure` (with table from step 6)
     5. `## Naming Conventions` (with table from step 7)
     6. `## Directory Map` (top-level directories with file counts and primary language)
     7. `## Diff Archaeology` — diff archaeology results from step 9 (always present):
        ```markdown
        ## Diff Archaeology

        **Tier**: comprehensive | lightweight
        **Time Window**: YYYY-MM-DD to YYYY-MM-DD
        **Diffs Analyzed**: N of M (cap: 200)

        ### Patterns Found

        | # | Category | Confidence | Occurrences | Summary |
        |---|----------|-----------|-------------|---------|
        | 1 | Revert | High | 3 | Preset command changes reverted due to missing test coverage |
        | 2 | Reviewer Theme | High | 5 | Reviewers consistently flag missing error handling in atexit handlers |
        ```
        - When no patterns found (`status: "no_history"`): "No diff history found in the configured time window"
        - When status is `"error"`: "Diff archaeology encountered an error and was skipped"
        - When status is `"degraded"`: Include warning and show available patterns
     8. `## Profile Complete` (completion marker — MUST be the LAST section):
        ```markdown
        ## Profile Complete

        Generated: YYYY-MM-DD HH:MM
        Status: complete
        ```
        This is the integrity marker downstream consumers check to verify the profile was not truncated

     **Conditional sections** (3, omitted when conditions not met):

     9. `## Module Boundaries` — cross-module dependency topology from import analysis (step 8a):
        ```markdown
        ## Module Boundaries

        | Module | Files | Primary Language | Top Imports | Responsibility |
        |--------|-------|-----------------|-------------|----------------|
        | Delivery | 45 | Hack | root (12), agents (5), QualityAudit (3) | Delivery orchestration |
        | agents | 30 | Hack | root (8), Delivery (4), Trajectory (2) | Agent implementations |
        | QualityAudit | 15 | Hack | root (6), Delivery ↔ QualityAudit (circular) (3) | Quality checks |
        ```
        - List each top-level directory (depth=1 only) as a module
        - **Top Imports**: Top 3 cross-module import targets ranked by import frequency (number of distinct files containing at least one import from the target module — file-level deduplication)
        - **Responsibility**: Inferred from file names and directory structure
        - If only one top-level directory exists: report "Single module — no internal boundaries detected."
        - If a module's import analysis was skipped due to timeout: mark as "skipped (timeout)" in the Top Imports column
        - If circular imports exist between modules: note as "A ↔ B (circular)" in the Top Imports column
        - If import analysis was skipped entirely (scan-depth: shallow): omit this section

     10. `## System Boundary` — ecosystem context from multi-signal detection (step 8):
        ```markdown
        ## System Boundary

        **Confidence**: detected | possible | not detected

        **Confidence Assessment**:
        | Signal | Confidence | Status | Evidence |
        |--------|-----------|--------|----------|
        | Import | HIGH | detected | `use Wilson\Delivery\*` in 12 files |
        | Parent/Sibling | MEDIUM | detected | 6 siblings in `rl_devai/` |
        | Cross-repo | MEDIUM | not detected | No counterparts found |
        | Metadata | LOW | skipped — timeout | — |

        **Parent**: `<parent-directory-path>`

        **Siblings**:
        - `<sibling-1>` — [brief description if available from user input]
        - `<sibling-2>` — [brief description if available from user input]

        **Shared Libraries**:
        - `<shared-lib-1>` — [brief description if available from user input or metadata]

        **Cross-Repo Counterparts**:
        - `<counterpart-1>` in `<tree>` — [brief description if available]
        ```
        - Use the confidence assessment table to show per-signal status with evidence citations
        - If a signal was skipped (timeout, MCP unavailable), show status as "skipped — [reason]"
        - If a category has no findings, omit that category's subsection (don't write "None detected" placeholders)
        - If system boundary was "not detected" in step 8 (all signals negative), omit `## System Boundary` entirely. Downstream consumers must handle absence.

     11. `## Cross-Root Boundaries` — deduplicated Layer 1 + Layer 2 discoveries (steps 7b, 8e–8g):
        ```markdown
        ## Cross-Root Boundaries

        **Discovered Roots**: N

        | # | Path | Confidence | Detection | Relationship | Status |
        |---|------|-----------|-----------|--------------|--------|
        | 1 | www/flib/intern/entity/eyepatch | HIGH | well_known_pattern | generated_dependency | new |
        | 2 | www/flib/intern/graphql/types/eyepatch | HIGH | well_known_pattern, name_pattern_search | generated_dependency | new |
        ```
        - Status column: `new` (first scan), `confirmed` (user confirmed in a prior `/speckit-setup` run), `stale` (no longer detected on re-scan)
        - Omit this section entirely when no roots are discovered (empty array)

11. **JSON scan profile output**: After writing `.specify/memory/project-profile.md`, write a structured JSON file to `.specify/memory/scan-profile.json` for consumption by downstream pipeline commands (`/speckit-specify`, `/speckit-plan`, `/speckit-tasks`).

   The JSON MUST conform to this schema (version 1):
   ```json
   {
     "version": 1,
     "generated": "YYYY-MM-DDTHH:MM:SSZ",
     "root_path": "fbcode/rlce/speckit",
     "languages": [
       {"name": "Hack", "files": 310},
       {"name": "Python", "files": 140}
     ],
     "frameworks": [
       {"name": "Ent", "evidence": "use Ent\\* imports", "file_count": 15}
     ],
     "test_infrastructure": {
       "directories": ["tests/unit/", "__tests__/"],
       "targets": ["python_unittest"],
       "file_patterns": ["test_*.py", "*Test.php"]
     },
     "naming_conventions": [
       {"category": "Python files", "convention": "snake_case", "compliance": 0.94}
     ],
     "architecture": {
       "module_boundaries": [
         {"name": "Delivery", "files": 45, "primary_language": "Hack"}
       ],
       "system_boundary_confidence": "detected"
     },
     "diff_patterns": {
       "status": "scanned",
       "tier": "comprehensive",
       "time_window": {
         "start": "2026-03-14T00:00:00Z",
         "end": "2026-07-14T00:00:00Z"
       },
       "diff_count": {
         "total": 150,
         "analyzed": 50,
         "cap": 200
       },
       "patterns": [
         {
           "id": "revert-001",
           "category": "revert",
           "confidence": "high",
           "occurrence_count": 3,
           "summary": "Preset command changes reverted due to missing test coverage",
           "evidence": [
             {
               "diff": "D106011323",
               "excerpt": "Revert D106011323 preset changes (replaced by D106044241 extension)",
               "date": "2026-05-15"
             }
           ],
           "governance_hint": "anti_pattern"
         }
       ]
     },
     "cross_root_boundaries": [
       {
         "path": "www/flib/intern/entity/eyepatch",
         "confidence": "HIGH",
         "detection_methods": ["well_known_pattern"],
         "relationship": "generated_dependency",
         "confirmed": false,
         "stale": false
       }
     ]
   }
   ```

   **Population rules:**
   - `version`: Always `1`
   - `generated`: ISO 8601 timestamp matching the markdown profile's generated timestamp
   - `root_path`: The repo-relative project root path computed in step 2. Consumed by `/speckit-setup` to derive the project name (last path component). Must be repo-relative (e.g., `fbcode/rlce/speckit`), not an absolute checkout path.
   - `languages`: One entry per detected language from the step 4 `## Languages` table, ordered by descending `files` count. Each entry is `{"name": <language>, "files": <file count>}`. Exclude the aggregate `"Other"` bucket (it is not a single language). Use empty array `[]` only when no language was detected at all. Consumed by `/speckit-setup` (Primary Language selection, verification-command heuristics, and the language count).
   - `frameworks`: One entry per detected framework from step 5. If no frameworks detected, use empty array `[]`
   - `test_infrastructure`: Populate from step 6 results. If no test infrastructure detected, use empty values (`"directories": [], "targets": [], "file_patterns": []`)
   - `naming_conventions`: One entry per category from step 7. If no conventions detected, use empty array `[]`
   - `architecture.module_boundaries`: Populate from step 8 Module Boundaries data (if import analysis ran). If scan-depth was shallow or only one module exists, use empty array `[]`
   - `architecture.system_boundary_confidence`: The overall confidence from step 8 (`"detected"`, `"possible"`, or `"not detected"`)
   - `diff_patterns`: Populate from step 9 diff archaeology results. Always present. `status` is one of: `"scanned"` (success with or without patterns), `"no_history"` (no diffs in time window), `"degraded"` (Phabricator unavailable, fell back to VC-only signals), `"error"` (diff archaeology step failed entirely). `patterns` is always an array (empty if no patterns found). Each pattern has `id`, `category`, `confidence` (`"high"` if occurrence_count >= 3, else `"low"`), `occurrence_count`, `summary`, `evidence` (max 5 items), and `governance_hint` (`"anti_pattern"`, `"checkpoint"`, or `"both"`)
   - `cross_root_boundaries`: Array of discovered root entries from steps 7b and 8e–8g. Always present (empty array `[]` when no roots discovered). Each entry has `path` (string, repo-relative), `confidence` (`HIGH`/`MEDIUM`/`LOW`), `detection_methods` (string array), `relationship` (one of `tight_coupling`, `generated_dependency`, `read_only_dependency`, `configuration`, `structural_colocation`), `confirmed` (boolean, default `false`), `stale` (boolean, default `false`). Uses merge semantics via `merge_cross_root_boundaries()` — not regenerated from scratch like other keys.

   **Schema evolution policy**: Changes are backward-compatible and additive only. New fields may be added; existing fields are never renamed or removed.

   If `.specify/memory/scan-profile.json` already exists, overwrite it with fresh results, EXCEPT for `cross_root_boundaries` which uses merge semantics (same behavior as the markdown profile for all other keys). Invoke `speckit run enrichment-merge.sh merge-roots .specify/memory/scan-profile.json <new-discoveries.json>` (see `merge_cross_root_boundaries()`) to merge the step 7b/8e–8g discoveries into the existing file rather than merging inline.

## Guidelines

- **Read-only**: Never modify project source files. This command only reads and analyzes.
- **"Not detected" principle**: When a category has no findings, report "Not detected" rather than guessing or omitting the category.
- **Output hygiene**: Do not surface internal script filenames, raw error messages, or implementation-detail diagnostics in user-facing output. When a script emits a diagnostic or error, summarize the outcome in natural language (e.g., "Scan complete" or "⚠ Some signals could not be collected") instead of echoing the raw message. At most one aggregate status message per category.
- **File discovery clarification**: Targeted `ls` on known directories is acceptable for extension enumeration. Use `search_files` MCP for all content pattern matching. The fbsource prohibition targets recursive traversals of the monorepo, not `ls` on specific paths.

## Edge Case Handling

- **Empty directory**: If the project root is empty or has no recognizable source files, create a minimal profile with all categories showing "Not detected" and mark as complete.
- **Large project sampling**: If total file count exceeds 5,000, apply stratified sampling and report sample statistics in the header.
- **Re-run overwrite**: If `.specify/memory/project-profile.md` already exists, overwrite it with fresh results. Log: "Overwriting existing profile with fresh scan."
- **Truncated profile detection**: Downstream consumers check for `## Profile Complete` section with `Status: complete`. If this section is missing, the profile is considered invalid.
- **Unrecognized extensions**: Group all unrecognized extensions as "Other" and list the top 5 by count.

## Step 12: After-Hooks

**Post-completion hook (MANDATORY — DO NOT SKIP)**: Run `speckit run dispatch-hooks.sh hooks.after_scan` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`) — if a mandatory hook's invocation fails or terminates abnormally, halt with "`<stage>` completed but the follow-up step failed — re-run `/<command>` to retry" (a hook returning a result, including a blocking one, is a successful dispatch, not a failure); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue.

## Step 13: Completion Report

Generate a completion report with the following sections:

**Mandatory sections:**
- `## Scan Complete` — summary of what was profiled
- `## Outputs` — list of generated artifacts:

  **Artifact summary:**

  | Artifact | Path |
  |----------|------|
  | Scan profile | `.specify/memory/scan-profile.json` |
  | Project profile | `.specify/memory/project-profile.md` |

**Compact summary mode (when `--tier` is provided):**

When invoked with `--tier`, produce ONLY a brief structured summary suitable for programmatic callers instead of the full section-by-section report:

- Scan status: success or failure
- Tier used: `{tier}`
- Languages detected: count and top 3
- Frameworks detected: list
- Diff archaeology: ran/skipped, pattern count

Do NOT include file listings, import analysis details, diff-archaeology comments, or verbose output. The `## Outputs` list and `## Auto-Resolution Log` are also omitted (`--tier` mode does not write an auto-resolution log).

**Conditional sections (only when `--auto` is active):**
- `## Auto-Resolution Log` — decisions made automatically:
  ```markdown
  ## Auto-Resolution Log

  - **System context prompt**: Auto-skipped (proceeded with codebase-only context)
  - **Diff archaeology tier**: Auto-selected lightweight (Tier B) — Phabricator queries may be slow or unavailable in automated contexts
  - **Diff archaeology time window**: 6 months (default)
  ```

**Auto-resolution log file** (only when `--auto` is active):
- Append auto-resolution decisions to `.specify/auto-resolution-log.md`:
  ```markdown
  ## speckit scan — YYYY-MM-DD HH:MM

  [Include the auto-resolution entries defined above]
  ```
- If the file doesn't exist, create it with a header:
  ```markdown
  # Auto-Resolution Log

  This log tracks decisions made automatically when commands run with `--auto` flag.

  ---

  ## speckit scan — YYYY-MM-DD HH:MM

  [Include the auto-resolution entries defined above]
  ```
