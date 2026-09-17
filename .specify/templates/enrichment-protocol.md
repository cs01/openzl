# Enrichment Protocol

Deep research enrichment: dispatch four concurrent investigations, validate envelopes, and return them to the caller for review and artifact writing.

This file is read and executed by a subagent dispatched from `/speckit-setup` step 4. It is NOT a standalone command.

## Inputs

The dispatching agent passes these via the Agent prompt:
- `REFRESH_MODE`: `true` if refreshing existing enrichment, `false` otherwise
- `INTERACTIVE`: `true` if interactive mode, `false` if `--auto` or non-TTY
- `RETRY_DIMENSIONS`: (optional) JSON array of dimension keys to retry (e.g., `["architecture", "data_flow"]`). When present, load `.specify/.enrichment-checkpoint.json` for previously succeeded envelopes and dispatch only these dimensions.
- `SKIP_DIMENSIONS`: (optional) JSON array of dimension keys to mark as gaps without dispatching. Combined with `RETRY_DIMENSIONS` when the caller chooses per-dimension handling.
- Working directory contains `.specify/memory/scan-profile.json` (valid, already checked by setup)

## CLAUDE.md Context

Before dispatching dimension agents, check for a project-level CLAUDE.md:

```bash
for f in .claude/CLAUDE.md CLAUDE.md; do
  [ -f "$f" ] && echo "$f" && break
done
```

If found, read the file and extract sections relevant to each dimension:
- **File inventory / directory structure** → Architecture & Entry Points
- **External paths / service dependencies** → Dependencies & Configuration
- **Oncall, dashboards, runbooks, doc references** → Operational Context
- **Data pipeline / flow descriptions** → Data Flow

Include the extracted context as a `### Project Context (from CLAUDE.md)` block in each dimension agent's prompt. This reduces discovery overhead — agents focus budget on investigation instead of rediscovering what CLAUDE.md already documents.

If no CLAUDE.md exists, proceed without it — agents discover context through codebase exploration (higher budget usage, protocol still works).

## Dispatch

Dispatch four `general-purpose` subagents in parallel via Agent tool, one per dimension. Each receives:
- All codebase paths from the current working directory
- CLAUDE.md context extract, if available (see above)
- Structured-findings contract schema (below)
- Per-dimension budget ceiling: 60 tool calls maximum

### Shared Envelope Schema

Every dimension agent MUST return a JSON object conforming to:

```json
{
  "dimension": "<dimension_key>",
  "status": "complete|budget_bounded|gap",
  "gap_reason": null,
  "budget": {"calls_used": N, "calls_max": 60},
  "prose_markdown": "### <Dimension Title>\n[Human-readable findings]",
  "machine": { <dimension-specific structured findings> }
}
```

### Mode Routing

- **Normal mode** (neither `RETRY_DIMENSIONS` nor `SKIP_DIMENSIONS` present): Dispatch all four dimensions below.
- **Resume mode** (`RETRY_DIMENSIONS` and/or `SKIP_DIMENSIONS` present): Load `.specify/.enrichment-checkpoint.json` for previously succeeded envelopes. Dispatch only dimensions in `RETRY_DIMENSIONS` using the dimension prompts below. Record gap markers for dimensions in `SKIP_DIMENSIONS` using the full envelope structure: `{"dimension": "<key>", "status": "gap", "gap_reason": "user_skipped", "budget": {"calls_used": 0, "calls_max": 0}, "prose_markdown": "", "machine": {}}`. After collection, merge all envelopes (checkpoint + newly returned + gap markers). Gap-marked dimensions count as resolved. If any retried dimensions still didn't return and `INTERACTIVE=true`, write updated checkpoint (merging newly succeeded with existing checkpoint contents) and emit `enrichment_status: partial` with remaining gaps. If any retried dimensions still didn't return and `INTERACTIVE=false`, emit `enrichment_status: failed` and stop. If all four dimensions are now resolved (succeeded or gap-marked), delete `.specify/.enrichment-checkpoint.json` and proceed to Synthesis.

### Dimension Prompts

In normal mode, dispatch all four in parallel. In resume mode, dispatch only dimensions in `RETRY_DIMENSIONS`:

**1. Architecture & Entry Points** (`dimension: "architecture"`):

Investigate the codebase architecture and entry points. Return findings using the shared envelope schema with machine fields:
```json
{
  "entry_points": [{"name": "...", "path": "project/relative/path", "kind": "cli|endpoint|controller|job", "responsibility": "..."}],
  "component_responsibilities": [{"component": "...", "responsibility": "..."}]
}
```
Do NOT re-emit `module_boundaries` or `system_boundary_confidence` from scan-profile.json.

**2. Dependencies & Configuration** (`dimension: "dependencies"`):

Investigate internal dependencies, external services, and configuration surfaces. Return findings using the shared envelope schema with machine fields:
```json
{
  "dependencies": {"internal": [{"name":"...","purpose":"..."}], "external_services": [{"name":"...","purpose":"..."}]},
  "configuration": {"surfaces": [{"kind":"justknobs|gk|qe|configerator|env","name":"...","purpose":"..."}]}
}
```

**3. Operational Context** (`dimension: "operational"`):

Investigate operational context: oncall, metrics, logging, dashboards, alerts, related docs. Use `knowledge_filtered_search` for Meta-internal resources. If backing systems are unavailable, return `status: "gap"` with `gap_reason: "backing_systems_unavailable"`. Return findings using the shared envelope schema with machine fields:
```json
{"oncall": [...], "metrics": [...], "logging": [...], "dashboards_alerts": [...], "related_docs": [...]}
```

**4. Data Flow** (`dimension: "data_flow"`):

Investigate data flows through the system. Return findings using the shared envelope schema with machine fields:
```json
{"flows": [{"name": "...", "path": "source → transform → sink"}]}
```

## Failure Handling

### Dispatch Failure

- **Transient failure** (Agent tool spawn error on an otherwise-available mechanism): Abort with actionable error. Log: "ERROR: Failed to dispatch enrichment subagents. Re-run /speckit-setup to retry." → Emit terminal status `failed` and stop.
- **Permanent unavailability** (nested dispatch unsupported): Log: "⚠ Multi-agent dispatch unavailable. Applying minimal-scaffold fallback." → Emit terminal status `dispatch_unavailable` and stop.

### Partial Fan-out

Collect envelopes within a bounded window (600 seconds). If fewer than expected return (4 in normal mode, `len(RETRY_DIMENSIONS)` in resume mode), branch on mode before doing anything else:

**Non-interactive mode** (`INTERACTIVE=false`): Hard-fail. Log: "ERROR: Enrichment incomplete (<N>/<expected> dimensions returned). Aborting setup." → Emit terminal status `failed` and stop.

**Interactive mode** (`INTERACTIVE=true`): Do NOT prompt the user — this protocol runs inside a subagent where user prompts are invisible. Instead, report gaps for the caller to handle:

1. Write succeeded envelopes to `.specify/.enrichment-checkpoint.json` (merging with existing checkpoint contents if present, so earlier-iteration successes are preserved):
   ```json
   {"succeeded": {"<dimension_key>": <full envelope>, ...}}
   ```
2. Emit the gap list and terminal status:
   ```
   enrichment_gaps: ["<dim1>", "<dim2>"]
   enrichment_status: partial
   ```

## Synthesis

Store each response envelope in an isolated variable — no shared mutable state between subagents. Verify each envelope conforms to the structured-findings contract (`dimension`, `status`, `machine` fields present). Malformed envelopes are treated as investigation failures per the Partial Fan-out rules above.

### Envelope Validation (budget-bounded usability check)

For each returned envelope with `status == "budget_bounded"`, check its `machine` object for at least one non-empty item:
- architecture: ≥1 `entry_points` or `component_responsibilities`
- dependencies: ≥1 `dependencies.internal` or `dependencies.external_services` or `configuration.surfaces`
- operational: ≥1 item in any sub-array (`oncall`, `metrics`, `logging`, `dashboards_alerts`, `related_docs`)
- data_flow: ≥1 `flows`

If the machine object passes → keep `status: budget_bounded` (best-effort success). If the machine object is empty → reclassify to `status: gap`, `gap_reason: "budget_exhausted_no_findings"` → handle per Partial Fan-out rules above.

### Envelope Return

Serialize all validated envelopes (including gap-marked envelopes from resume mode) as a JSON array. Each element is the full envelope object conforming to the Shared Envelope Schema (dimension, status, gap_reason, budget, prose_markdown, machine).

Write the array to `.specify/.enrichment-findings.json`:

```json
[
  { "dimension": "architecture", "status": "complete", "gap_reason": null, "budget": {"calls_used": 12, "calls_max": 60}, "prose_markdown": "...", "machine": {...} },
  { "dimension": "dependencies", "status": "complete", "gap_reason": null, "budget": {"calls_used": 9, "calls_max": 60}, "prose_markdown": "...", "machine": {...} },
  { "dimension": "operational", "status": "complete", "gap_reason": null, "budget": {"calls_used": 15, "calls_max": 60}, "prose_markdown": "...", "machine": {...} },
  { "dimension": "data_flow", "status": "complete", "gap_reason": null, "budget": {"calls_used": 7, "calls_max": 60}, "prose_markdown": "...", "machine": {...} }
]
```

The file is durable — it persists after the run and is overwritten by the next enrichment run.

If the write fails (filesystem error), emit `enrichment_status: failed` with a diagnostic message instead of proceeding.

After a successful write, emit terminal status:

```
enrichment_status: ok
```

The caller (setup) is responsible for reading `.specify/.enrichment-findings.json` and composing prose and merging machine findings into project artifacts.

## Terminal Status

Every exit path — success or failure — MUST end the response with this line, and nothing after it:

```
enrichment_status: <ok|failed|dispatch_unavailable>
```

| Value | When |
|-------|------|
| `ok` | All envelopes validated and written to `.specify/.enrichment-findings.json` |
| `failed` | Transient dispatch failure or non-interactive incomplete fan-out |
| `partial` | Interactive mode: some dimensions didn't return; gaps reported for caller to handle |
| `dispatch_unavailable` | Nested dispatch is unsupported (permanent unavailability) |

The caller switches on this value. Do not rely on prose wording to signal the outcome — log lines may legitimately contain the token `ERROR:` without the run having failed.
