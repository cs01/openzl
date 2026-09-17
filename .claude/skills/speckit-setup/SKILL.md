---
name: speckit-setup
description: SpecKit post-install setup wizard — configures `.specify/` for this project after `speckit init`.
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: preset:meta
  meta_preset_strategy: replace
user-invocable: true
disable-model-invocation: false
---



# Speckit Setup Skill

# Setup Command

This command configures your project for spec-driven development — scanning your codebase, setting up verification commands, and generating a project constitution tailored to your team's practices.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Behavior

- **First run**: scaffolds missing files, prompts for preferences, invokes constitution
- **Re-run**: reports status, skips existing artifacts, offers re-generation

## Steps

**Print this roadmap to the user before starting:**

```
Setup Wizard — Roadmap
═══════════════════════════════════════════════════════
 1. Pre-flight       Verify SpecKit is initialized
 2. Scan             Profile project languages, frameworks, conventions
 2b. Confirmation    Confirm discovered cross-root boundaries
 3. Enrichment       Deep research: architecture, dependencies, ops, data flow
 4. Project Context  Scaffold project identity and stack-specific guidance
 5. Verification     Configure language-specific verification commands
 6. Constitution     Generate governing principles for spec-driven development
 7. Commit & Summary Commit all artifacts, report what was created
═══════════════════════════════════════════════════════
```

**Progress reporting protocol**: After completing each roadmap phase, print a one-line progress bar to orient the user. Use `✓` for completed, `→` for in-progress, `○` for remaining:

```
── Progress ── ✓ Pre-flight | ✓ Scan | → Confirmation | ○ Enrichment | ○ Project Context | ○ Verification | ○ Constitution | ○ Commit & Summary
```

Phase-to-step mapping (internal steps → user-facing phases):

| Steps | Phase |
|-------|-------|
| 1–2 | Pre-flight |
| 3 | Scan |
| 3b | Confirmation |
| 4 | Enrichment |
| 5 | Project Context |
| 6 | Verification |
| 7 | Constitution |
| 8–9 | Commit & Summary |

### Step 1: Pre-flight Check

Before starting work, briefly tell the user what this stage does and why it matters. Print the introduction in bold.

**Workspace check (MANDATORY)**: Run `speckit run require-workspace.sh`. This resolves the workspace from any subdirectory and produces the same fixed message when there is no workspace above the current directory. On a non-zero exit, relay its stderr output to the user verbatim — do not paraphrase, reword, summarize, or translate it; do not prepend or append anything (no preface, heading, or attribution such as "require-workspace.sh failed:"); do not name the script, the command, the exit code, or any internal path — then halt. On exit 0, proceed to step 2.

---

### Step 2: Activate Hook Suppression

Create suppression marker to prevent sub-command sdd-commit hooks from firing during setup.

```bash
mkdir -p .specify
echo '{"timestamp": '$(date +%s)', "created_by": "speckit-setup"}' > .specify/.suppress-sdd-commit \
  || echo "Warning: could not write suppression marker; sub-command commits may not be suppressed"
```

This marker tells `/speckit-constitution` and `/speckit-scan` (invoked in steps below) to skip their individual `after_*` commit hooks. The `after_setup` hook in step 8 will capture all changes in a single commit.

---

### Step 3: Scan Check

Check if framework scan exists. Auto-invoke `/speckit-scan` if missing.

```bash
cat .specify/memory/scan-profile.json
```

**Decision:**

- **Scan profile exists** → proceed to step 3b.
- **Scan profile missing** → prompt user for scan tier (see below) → dispatch scan via Agent → wait for completion → proceed to step 3b.

**Tier Selection Prompt:**

"No scan profile found. `/speckit-scan` will analyze your project to detect frameworks, languages, and version control patterns.

**A) Comprehensive (Recommended)** — Analyzes version control history AND code review metadata (reviewer feedback themes, CI failure patterns, multi-round revision signals). Produces deeper diff archaeology with higher-value governance signals. Both tiers produce the same artifacts (`scan-profile.json`, `project-profile.md`); Comprehensive extracts richer patterns within them.

**B) Lightweight** — Analyzes version control history only (reverted-diff patterns, commit conventions). Faster, but misses the highest-value signals from code review. Choose this for a quick initial scan or if Phabricator access is limited.

Which tier? (A/B)"

Capture the user's choice as `{tier}`:
- User selects **A** → set `tier` to `comprehensive`
- User selects **B** → set `tier` to `lightweight`

**Scan Dispatch:**

Dispatch `/speckit-scan` via the Agent tool (foreground, `run_in_background: false`) with prompt:

```
Run: Skill("speckit-scan", args: "--tier {tier}")
```

Wait for the Agent to complete, then validate the scan output before proceeding to step 3b.

**Scan Profile Validation:**

After the Agent completes, verify that `scan-profile.json` is present AND valid:

```bash
jq -e '.version and .languages and .root_path' .specify/memory/scan-profile.json > /dev/null 2>&1
```

**Validation Decision:**

- **Valid profile** (jq exits 0, required keys present) → proceed to step 3b.
- **Invalid or missing profile** (jq exits non-zero, unparseable JSON, or missing required keys) → apply Scan Failure fallback (see Edge Cases section below) → proceed to step 3b with default configuration.

---

### Step 3b: Cross-Root Boundary Confirmation

After scan completes (successfully, or via the Scan Failure fallback), check whether it discovered any cross-root boundaries:

```bash
[ -f .specify/memory/scan-profile.json ] && \
  jq -e '.cross_root_boundaries | length > 0' .specify/memory/scan-profile.json > /dev/null 2>&1
```

**Decision:**

- **File missing, key absent, null, or empty array** → skip this step entirely, no log → proceed to step 4.
- **Key present with entries** → present the confirmation flow below.

**Non-interactive mode** (`--auto` or non-TTY): Auto-confirm HIGH-confidence roots (set `confirmed: true`) and write back per **Write-back** below; leave MEDIUM/LOW roots unchanged. Log: "Auto-confirmed {N} HIGH-confidence roots, skipped {M} MEDIUM/LOW." → proceed to step 4.

**Interactive confirmation flow**:

1. Present all discovered roots in a single table grouped by confidence (HIGH first, then MEDIUM, then LOW):

   ```
   Cross-Root Boundaries Detected
   ═══════════════════════════════

   Scan discovered N directories that may belong to this project:

   | # | Path | Confidence | Detection | Relationship |
   |---|------|-----------|-----------|--------------|
   | 1 | www/flib/intern/entity/eyepatch | HIGH | well_known_pattern | generated_dependency |

   Options:
   A) Confirm all — accept all discovered roots as-is
   B) Review individually — confirm, remove, or reclassify each root
   C) Add missing — add roots that detection missed
   D) Let's discuss — I have questions about these roots
   ```

2. **Confirm all**: Set `confirmed: true` on every entry, then write back.
3. **Review individually**: For each entry, offer Confirm (default), Remove, or Reclassify.
4. **Add missing**: Prompt for a path, then record it with `detection_methods: ["user_declared"]`, `confidence: "HIGH"`, `confirmed: true`, and prompt for a relationship type.
5. **Let's discuss**: Answer the user's questions about the discovered roots, then re-present the table.

**Stale + confirmed entries**: For entries with both `stale: true` and `confirmed: true`, surface: "You confirmed this root, but it's no longer detected — still relevant?"

**Re-run behavior**: When roots are already confirmed, present them with their current confirmation status and allow the user to modify, remove, or add roots.

**Write-back**: Read-modify-write `.specify/memory/scan-profile.json`, updating only the `cross_root_boundaries` array with this step's decisions. Write to a `.tmp` file then `mv` for atomicity. If a root is accidentally removed, re-run `/speckit-scan` to re-detect it.

Proceed to step 4.

---

### Step 4: Deep Research Enrichment

Automatically enrich the project context with deep codebase investigation across four dimensions: architecture & entry points, dependencies & configuration, operational context, and data flow. Enrichment runs on first setup, materializes cached findings after standalone scans, and prompts on upgrades or refreshes.

**Parse --auto flag** (interactivity detection):

Check `$ARGUMENTS` for `--auto` flag (standalone leading token, not embedded in feature description text). Interactivity precedence: explicit `--auto` → non-interactive; else TTY detection; default interactive.

**State Detection** (triple-signal):

Read three signals to compute enrichment state:

1. **Marker**: Check if `.specify/memory/enrichment.json` exists and is parseable
2. **Prose**: Check if `.specify/memory/project-context.md` exists
3. **Projection**: Check if `.specify/memory/scan-profile.json` contains `.enrichment` key

```bash
MARKER_EXISTS=false
PROSE_EXISTS=false
PROJECTION_EXISTS=false

if [ -f .specify/memory/enrichment.json ] && jq -e '.enrichment' .specify/memory/enrichment.json > /dev/null 2>&1; then
  MARKER_EXISTS=true
fi

if [ -f .specify/memory/project-context.md ]; then
  PROSE_EXISTS=true
fi

if [ -f .specify/memory/scan-profile.json ] && jq -e '.enrichment' .specify/memory/scan-profile.json > /dev/null 2>&1; then
  PROJECTION_EXISTS=true
fi
```

**State Routing** (evaluated BEFORE scaffold's file-existence early-exit in step 5):

| Marker | Prose | Projection | State | Action |
|--------|-------|------------|-------|--------|
| absent | absent | absent | S0 (greenfield) | Scaffold inline (within step 4), then enrich automatically |
| absent | **present** | absent | S1 (upgrade-unmarked) | **Prompt** before enriching — never silent |
| present | present | present | S2 (enriched-consistent) | **Refresh prompt** |
| present | present | absent | S3 (thin-projection) | **Materialize** from cache, no research |
| absent | present w/ reserved section | absent | S4 (orphaned-prose) | **Prompt**; on decline, delete orphaned section |
| absent | partial | partial | S5 (crash-mid-write) | Route by prose presence → S1/S4 or S0 |

**S0 (Greenfield — first-time setup):**

- Log: "First-time setup detected. Scaffolding project context..."
- Parse `.specify/memory/scan-profile.json`: extract `root_path` (strip any trailing slash, then take the last path component as the project name), `languages` array (primary language by plurality — highest `files` count, alphabetical tie-break; treat absent/empty as genuinely empty), `frameworks` array
- Read `.specify/templates/project-context-template.md`, fill bracketed placeholders from scan-profile data, include only framework sections matching detected frameworks, write to `.specify/memory/project-context.md`. For the `Generated` field, use the current date in YYYY-MM-DD format.
- Log: "✓ Project context scaffolded. Enrichment will run automatically."
- Proceed to Dispatch & Synthesis below

**S1 (Upgrade — unmarked prose exists):**

- **Interactive mode**: Prompt: "Existing project context detected without enrichment marker. Enrich with deep codebase investigation (architecture, dependencies, operational, data flow)? (yes/no)"
  - If yes → proceed to Dispatch & Synthesis
  - If no → Log: "Enrichment skipped." → proceed to step 5
- **Non-interactive mode** (`--auto` or non-TTY): Log: "Upgrade path detected. Enrichment skipped in non-interactive mode." → proceed to step 5

**S2 (Enriched-consistent — refresh prompt):**

- **Interactive mode**: Prompt: "Project context already enriched (generated <timestamp from enrichment.generated>). Regenerate all four dimensions? Decline preserves existing content including manual edits. (yes/no)"
  - If yes → set `REFRESH_MODE=true` → proceed to Dispatch & Synthesis
  - If no → Log: "Enrichment preserved." → proceed to step 5
- **Non-interactive mode**: Log: "Enrichment already present. Skipping refresh in non-interactive mode." → proceed to step 5

**S3 (Thin-projection — materialize from cache):**

- Log: "Enrichment marker present, but projection missing (likely due to standalone scan re-run). Re-materializing from cache..."
- Run materialize. Do not narrate the script filename or internal tooling names in user-facing output — describe the operation as "Re-materializing enrichment findings from cache" instead:
  ```bash
  speckit run enrichment-merge.sh materialize \
    .specify/memory/scan-profile.json \
    .specify/memory/enrichment.json 2>/dev/null
  ```
- If the command exits non-zero, log "⚠ Enrichment findings could not be re-materialized from cache" and proceed to step 5 with the existing thin projection — skip the staleness check below (its input was not refreshed).
- Otherwise, log "✓ Enrichment findings re-materialized" and check for staleness flag:
  ```bash
  if jq -e '.enrichment.stale == true' .specify/memory/scan-profile.json > /dev/null 2>&1; then
    echo "⚠ Enrichment findings may be stale (codebase changed since last enrichment). Consider running refresh."
  fi
  ```
- Proceed to step 5

**S4 (Orphaned-prose — crash after prose write):**

- **Interactive mode**: Prompt user:
  ```
  Detected orphaned "Deep Research Enrichment" section in project-context.md without marker.
  This suggests a prior enrichment crashed mid-write.

  Delete orphaned section and re-enrich? (yes/no)
  ```
  - If yes → Delete orphaned `## Deep Research Enrichment` section → proceed to Dispatch & Synthesis
  - If no → Log: "Orphaned section preserved. Manual cleanup required." → proceed to step 5
- **Non-interactive mode**: Log: "Orphaned enrichment section detected. Skipping cleanup in non-interactive mode." → proceed to step 5

**S5 (Crash-mid-write):**

- If prose contains `## Deep Research Enrichment` section → treat as S4 (orphaned-prose)
- Else → treat as S0 (greenfield)

**Dispatch & Synthesis** (when enrichment will run):

Dispatch a `general-purpose` Agent (foreground, `run_in_background: false`) with prompt:

```
Read and execute .specify/templates/enrichment-protocol.md

REFRESH_MODE=<true if S2 refresh, false otherwise>
INTERACTIVE=<true if interactive mode, false if --auto or non-TTY>

The working directory contains a valid .specify/memory/scan-profile.json.
Investigate all four dimensions and write validated envelopes per the protocol.
```

**After Agent returns**: Read the `enrichment_status: <value>` line the protocol emits as the last line of its response. Switch on that value — do NOT substring-match the response for "ERROR:", which both misses `dispatch_unavailable` and false-positives on log lines that legitimately contain the token.

- `ok` → Read enrichment envelopes and proceed through review and artifact writing (4-A through 4-D below), then continue to step 5.
- `partial` → Parse `enrichment_gaps:` line from agent output to get the list of non-returning dimensions. Handle via Partial Enrichment Recovery below.
- `failed` → **Interactive mode**: Log: "⚠ Enrichment failed. Proceeding with existing context." → Proceed to step 5. **Non-interactive mode**: Log the error. Clean suppression marker: `rm -f .specify/.suppress-sdd-commit`. **Exit non-zero** — non-interactive setup must fail on enrichment failure, not silently proceed.
- `dispatch_unavailable` → Log "⚠ Enrichment dispatch unavailable. Applying minimal-scaffold fallback." → Proceed to step 5 without enrichment.

If the Agent dispatch itself fails (spawn error or agent type unavailable) so that no status line is returned at all, treat it as `dispatch_unavailable`.

**4-A. Read envelopes**:

Read `.specify/.enrichment-findings.json` and JSON-parse it as an array of envelope objects. Validate each envelope has `dimension`, `status`, and `machine` fields present (per the protocol's Shared Envelope Schema). If the file does not exist, or parsing or validation fails, treat this as `enrichment_status: failed` and apply the `failed` handling above instead of continuing to 4-B.

**4-B. Review gate** (interactive mode only):

Present a compact summary table of all returned dimensions:

```
Enrichment findings ready for review:

| # | Dimension | Findings | Key Discovery |
|---|-----------|----------|---------------|
| 1 | Architecture | 5 entry points, 3 components | CLI entrypoint at wrapper.py |
| 2 | Dependencies | 4 internal, 2 external | Phabricator API dependency |
| 3 | Operational | 2 dashboards, 1 oncall | SEV oncall: speckit_oncall |
| 4 | Data Flow | 3 flows | scan → enrich → persist pipeline |

Options:
A) Accept all — write findings as-is
B) Review specific dimensions — type dimension numbers to drill into (e.g., "1, 3")
C) Reject specific dimensions — type dimension numbers to reject entirely (e.g., "3")
D) Let's discuss — I have questions about these findings
```

**Accept all** (fast path): Proceed directly to artifact writing (4-D) with all envelopes accepted.

**Drill-down**: For each named dimension, present a numbered findings list extracted from `prose_markdown` (split on list items or sub-headings):

```
Dimension: Architecture & Entry Points

Findings:
  1. CLI entrypoint at wrapper.py — handles speckit init, speckit setup
  2. PAR build pipeline — Buck target builds distributable archive
  3. Preset resolution — .specify/presets/ loaded at init time
  4. Template installation — _install_custom_templates() copies to .specify/templates/
  5. Hook system — extensions.yml dispatches post-stage hooks

Strike incorrect findings by number (e.g., "3, 5"), type "reject" to reject entire dimension, or press Enter to accept all:
```

Struck findings are excluded from the dimension's prose output. If ALL findings in a dimension are struck, or "reject" is typed, treat as dimension-level rejection (4-C). Machine fields are left as-is when individual findings are struck — only prose is affected. Machine fields are advisory and are not consumed by any downstream command.

After drill-down, return to the dimension summary table for remaining unreviewed dimensions. When all dimensions are reviewed (remaining ones default to accepted), proceed to artifact writing (4-D).

**Non-interactive mode**: Skip the review gate entirely. Auto-accept all envelopes. Proceed directly to artifact writing (4-D). This preserves equivalent behavior to the current autonomous write path.

**4-C. Handle rejected dimensions**:

For each rejected dimension (whole-dimension rejection or all-findings-struck):
- Set `status: "gap"` and `gap_reason: "user_rejected"` in the envelope
- The `dependencies` dimension rejection applies to both its `dependencies` and `configuration` output keys
- Rejected dimensions' `prose_markdown` is omitted from `project-context.md`
- Rejected dimensions are still included in the findings JSON (with gap status) so `enrichment-merge.sh persist` records them correctly

If ALL dimensions are rejected: omit the `## Deep Research Enrichment` section entirely from `project-context.md`, and write gap markers for all dimensions in `enrichment.json`.

**4-D. Write artifacts**:

Write ordering: `project-context.md` prose FIRST, `scan-profile.json` projection SECOND, `enrichment.json` marker LAST (marker-last crash consistency). Idempotent replace: any existing `## Deep Research Enrichment` section in `project-context.md` is deleted before writing the new one — never append duplicate sections.

Dispatch a `general-purpose` Agent (foreground, `run_in_background: false`) to perform the write — isolating file-write mechanics from this interactive step keeps the step's context small:

```
Read and execute .specify/templates/enrichment-artifact-write.md

ENVELOPES=<JSON array of all four dimension envelopes, post-review: rejected dimensions have status "gap" and gap_reason "user_rejected" (with struck findings removed from prose_markdown for partially-rejected dimensions)>
REFRESH_MODE=<true if S2 refresh, false otherwise>
```

**After Agent returns**: Read the `enrichment_write_status: <value>` line.
- `ok` → Log: "✓ Enrichment complete: N dimensions accepted, M rejected."
- `failed` → Log: "⚠ Failed to merge enrichment findings. Details in `/tmp/enrichment-merge-$$.err`. Check `.specify/memory/` permissions and re-run `/speckit-setup` to retry." Proceed with existing context (do not exit non-zero — enrichment merge failure is not a setup failure).

Proceed to step 5.

**Partial Enrichment Recovery**:

When enrichment returns `partial`, present the gap dimensions and prompt the user:

```
<N> enrichment dimension(s) did not complete: <dimension list>.

Options:
1. **Retry all** — Re-dispatch only the failed dimensions
2. **Skip all** — Proceed with gap markers for missing dimensions
3. **Abort** — Stop enrichment entirely
4. **Choose per dimension** — Pick retry or skip for each failed dimension
5. **Let's discuss** — I have questions

> Which fits best? (1/2/3/4/5)
```

Handle the user's choice:

**Option 1 (Retry all)**: Set `RETRY_DIMENSIONS` to all gap dimensions, `SKIP_DIMENSIONS` to empty. Proceed to recovery dispatch.

**Option 2 (Skip all)**: Set `RETRY_DIMENSIONS` to empty, `SKIP_DIMENSIONS` to all gap dimensions. Proceed to recovery dispatch.

**Option 3 (Abort)**: Clean up checkpoint: `rm -f .specify/.enrichment-checkpoint.json`. Log: "⚠ Enrichment aborted. Proceeding with existing context." → Proceed to step 5.

**Option 5 (Let's discuss)**: Answer the user's questions about the failed dimensions, enrichment process, or implications of each choice. After discussion, re-present the Partial Enrichment Recovery prompt.

**Option 4 (Choose per dimension)**: For each gap dimension, prompt:
```
Dimension '<dimension>': Retry or Skip?
```
Collect all decisions, then set `RETRY_DIMENSIONS` and `SKIP_DIMENSIONS` accordingly. Proceed to recovery dispatch.

**Recovery dispatch**: Re-dispatch the enrichment protocol via Agent (foreground) with:

```
Read and execute .specify/templates/enrichment-protocol.md

REFRESH_MODE=<same as original dispatch>
INTERACTIVE=true
RETRY_DIMENSIONS=<JSON array of dimensions to retry>
SKIP_DIMENSIONS=<JSON array of dimensions to skip>
```

After recovery agent returns, switch on `enrichment_status` again:
- `ok` → All dimensions are now resolved (succeeded from the original dispatch and from recovery retries, plus any gap-marked from recovery). Read envelopes (4-A). Run the review gate (4-B) exactly once, covering all dimensions that returned findings — exclude recovery-gap-marked dimensions (`user_skipped`, `backing_systems_unavailable`) from the review gate, since they're already finalized. Write artifacts (4-D). Clean up checkpoint: `rm -f .specify/.enrichment-checkpoint.json`. Proceed to step 5.
- `partial` → Re-present the Partial Enrichment Recovery prompt with remaining gaps. The recovery loop is intentionally unbounded — the user controls termination via Abort or Skip at every iteration.
- `failed` → Clean up checkpoint: `rm -f .specify/.enrichment-checkpoint.json`. Log: "⚠ Enrichment recovery failed. Proceeding with existing context." → Proceed to step 5.
- `dispatch_unavailable` → Clean up checkpoint: `rm -f .specify/.enrichment-checkpoint.json`. Log: "⚠ Enrichment dispatch unavailable during recovery. Proceeding with existing context." → Proceed to step 5.

If the recovery Agent dispatch itself fails (spawn error or agent type unavailable) so that no status line is returned at all, treat it as `dispatch_unavailable`.

**Edge case — scan failure**: If step 3 applied Scan Failure fallback, skip enrichment entirely. Log: "⚠ Scan failed. Skipping enrichment (requires valid scan-profile.json)." → Proceed to step 5.

After enrichment completes (or is skipped), proceed to step 5.

---

### Step 5: Scaffold Project Context

Check if `.specify/memory/project-context.md` exists. If missing, scaffold from scan results.

```bash
ls -la .specify/memory/project-context.md
```

**Decision:**

- **File exists** → Log: "✓ Project context already configured" → proceed to step 6.
- **File missing** → scaffold new file (see Scaffolding Template below) → proceed to step 6.

#### Scaffolding Template

Parse `.specify/memory/scan-profile.json` to extract:
- `root_path` → derive project name from last path component
- `languages` array → select the **primary language** by plurality: the entry with the highest `files` count, breaking ties alphabetically by `name` (ascending). Treat an absent `languages` field identically to an empty array. When empty or absent, leave Primary Language genuinely empty — do NOT invent a value or emit a bracketed placeholder.
- `frameworks` array → select framework-specific content

Read `.specify/templates/project-context-template.md`, fill in the bracketed placeholders from scan-profile data, include only framework sections matching detected frameworks, and write to `.specify/memory/project-context.md`. For the `Generated` field, use the current date in YYYY-MM-DD format.

**After writing**: Display diff summary showing what was created. Continue to step 6.

---

### Step 6: Verification Commands

Check if verification commands are configured. Suggest based on detected stack.

**Check for existing configuration:**

1. Read `.specify/memory/project-context.md` and search for `## Verification Commands` section.
2. If section exists with non-empty command list → Log: "✓ Verification commands already configured" → proceed to step 7.
3. If section missing or empty → prompt user (see below).

**Prompt user:**

"I can suggest verification commands based on your stack. Where should I write them?"

**Options:**

A. Append to `.specify/memory/project-context.md` (recommended for this project only)
B. Create/update `~/.claude/CLAUDE.md` (global for all your projects)
C. Create/update `.claude/CLAUDE.md` (team-wide via version control)
D. Create/update `.specify/memory/verification-commands.md` (alternate file for teams that prefer not to modify CLAUDE.md)
E. Skip (configure manually later)

**User selects option** → Apply choice:

**Option A**: Append `## Verification Commands` section to `.specify/memory/project-context.md`:

````markdown
## Verification Commands

Run these in order before every `jf submit`. Stop on first failure.

```bash
sl status             # Check for untracked files (? = won't be in diff)
[Language-specific commands from heuristics table below]
arc f                 # Format changed files
arc lint -a           # Lint + autofix
arc unit              # Tests for modified files
```

If `.specify/memory/constitution.md` exists, audit this diff against its
principles before submitting. The spec pipeline checks constitution compliance
automatically; this step covers changes made without a spec.
````

**Option B/C/D**: Same content, but write to the selected file (CLAUDE.md or verification-commands.md). Create file if missing, or append section if file exists.

**Option E**: Log: "Skipped verification commands configuration" → proceed to step 7.

**Verification Command Heuristics:**

Select based on the full set of `languages[].name` values in scan-profile.json — emit commands for **every** detected language, not just the primary one. Treat an absent `languages` field the same as an empty array (no language-specific commands).

| Detected Language | Commands to Include |
|-------------------|---------------------|
| `hack`, `php` | `hh                   # Hack type check` |
| `python` | `arc pyre check <targets>-library  # Pyre type check (Python changes only — use -library suffix for test targets)` |
| `javascript`, `flow` | `flow status           # Flow type check (JS changes only — run from www/)` <br> `eslint-fb <file>      # ESLint check (JS changes only — run per modified .js file)` |
| `rust` | `cargo check           # Rust type check` <br> `cargo test            # Rust tests` <br> `cargo clippy          # Rust linter` |
| `cpp` | `buck2 build <targets> # C++ build check` <br> `buck2 test <targets>  # C++ tests` |

Always include these after language-specific commands:
```
arc f                 # Format changed files
arc lint -a           # Lint + autofix
arc unit              # Tests for modified files
```

**After writing**: Display what was configured. Continue to step 7.

---

### Step 7: Constitution Generation

Check if constitution exists. Prompt user to generate if missing.

```bash
ls -la .specify/memory/constitution.md
```

**Decision:**

- **Constitution exists and is NOT placeholder** → Log: "✓ Constitution already configured" → set `{constitution_outcome}` to `existed` → proceed to step 8.
- **Constitution missing OR is placeholder** → Prompt user.

**Detect placeholder**: Check whether the file contains the sentinel `<!-- speckit:constitution:placeholder -->`. If the sentinel is present, the constitution is an unconfigured placeholder.

**Prompt:**

"No constitution found (or placeholder detected).

A **constitution** is a governance document that defines how specs in this project are written, reviewed, and maintained — coding standards, testing requirements, architectural boundaries, and review criteria specific to your team. Projects with constitutions get more consistent spec reviews because the review agents can check against your team's actual conventions instead of generic best practices.

**A) Yes, generate now (Recommended)** — Creates a constitution from your scan profile, tailored to your detected stack and patterns. You can review and customize it afterward.

**B) No, skip** — You can generate one later with `/speckit-constitution`.

Generate constitution? (A/B)"

**User selects A** → Invoke `/speckit-constitution` via Skill tool → wait for completion → set `{constitution_outcome}` to `generated` → proceed to step 8.

**User selects B** → Log: "Skipped constitution generation. Run `/speckit-constitution` when ready." → set `{constitution_outcome}` to `skipped` → proceed to step 8.

---

### Step 8: Deactivate Suppression & Fire Hook

Remove the suppression marker and fire the `after_setup` hook to commit all setup artifacts.

```bash
rm -f .specify/.suppress-sdd-commit
export SPECKIT_COMMIT_EXTRA_PATHS=".claude/:CLAUDE.md"
```

Then run this (MANDATORY — DO NOT SKIP): `speckit run dispatch-hooks.sh hooks.after_setup` — do not redirect or suppress stderr. If the script is missing, halt and direct the user to reinstall via `speckit init`. If it exits non-zero, show the user the stderr output and halt. If it exits zero, parse each tab-delimited output line (command, optional flag, description): execute `/<command>` immediately for mandatory hooks (`false`) — if a mandatory hook's invocation fails or terminates abnormally, halt with "`<stage>` completed but the follow-up step failed — re-run `/<command>` to retry" (a hook returning a result, including a blocking one, is a successful dispatch, not a failure); for optional hooks (`true`), offer the user a prompt derived from the description and execute only if accepted. If an optional hook fails, warn and continue.

The `after_setup` hook will commit all files created/modified during setup (scan profile, constitution, project-context, verification commands, enrichment artifacts) in a single commit.

---

### Step 9: Summary & Next Steps

Report what was created/configured. Recommend next actions.

**Artifact summary:**

| Artifact | Path |
|----------|------|
| Project context | `.specify/memory/project-context.md` |
| Scan profile | `.specify/memory/scan-profile.json` |
| Constitution | `.specify/memory/constitution.md` |

**Display:**

```
Setup Complete

✓ SpecKit initialized at .specify/
✓ Scan profile: [`len(languages)` languages, M frameworks detected]
[✓/○] Project context: [created/already existed]
[✓/○] Verification commands: [configured in <file>/skipped]
[✓/○] Constitution: [generated/already existed/skipped]

➡️ Next Steps:

1. Review .specify/memory/project-context.md — add project-specific conventions
2. [IF {constitution_outcome} == generated] Review .specify/memory/constitution.md — customize the generated principles for your team's practices
3. [IF {constitution_outcome} == existed] Review .specify/memory/constitution.md — verify it still reflects your team's current practices
4. [IF {constitution_outcome} == skipped] Run /speckit-constitution to generate development principles
5. [IF verification commands were skipped] Configure verification commands in CLAUDE.md
6. Start your first spec with /speckit-generate <feature-name>
```

**➡️ Final instruction to user:**

"Setup complete. Would you like to start your first spec now, or customize any configuration first?"

**STOP.** No further actions without user input.

---

## Edge Cases

### Scan Failure

If `/speckit-scan` fails in step 3 (subagent returns control after failure, or validation detects absent/unparseable/incomplete profile):

- Log: "⚠ Scan failed or produced an invalid profile. Proceeding with default configuration."
- Step 3b: Skips automatically — its own gate requires a readable `scan-profile.json` with a non-empty `cross_root_boundaries` array
- Step 4: Skip enrichment (requires valid scan-profile.json)
- Step 5: Scaffold project-context.md with minimal template (no framework sections, Primary Language empty)
- Step 6: Suggest only default Meta commands (`arc f`, `arc lint -a`, `arc unit`)
- Continue to step 7.

**Note**: This fallback does NOT cover Agent tool spawn failures (those abort setup and require re-run — matching spec Design Decision).

---
