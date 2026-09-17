---
description: Shared post-dispatch program for the review-panel bounded wait — read and executed inline by the dispatching command, never dispatched via Agent()
---

# Review Wait Protocol

This file is **read and executed in the calling command's own context** — never dispatched via `Agent()`. There is no return value to misparse and no subagent hop; the instructions below run exactly where the "Read and execute `.specify/templates/review-wait-protocol.md`" pointer sits in the calling command.

It picks up immediately after the calling command has dispatched the review panel (or determined that a `resume`d panel is still live) and needs to wait on it to conclude.

## Bindings

The calling command has already established these before reaching this point:

| Binding | Source |
|---|---|
| `ATTEMPT_ID`, `ATTEMPT_DIR`, `PANEL_SIZE`, `QUORUM_REQUIRED` | `review-attempt.sh init` or `resume` |
| `GATE_TYPE` | The calling command's own gate type (`primary` or `secondary`) |
| `ATTENDED` | Resolved at command entry — `false` whenever the command itself was dispatched or hook-invoked, regardless of any flag |
| `SYNTHESIS_TEMPLATE` | The gate type's synthesis template path, e.g. `.specify/templates/review-spec-synthesis.md` |
| The synthesis dispatch bindings | The same `FEATURE_DIR` / `FEATURE_SPEC` (or `IMPL_PLAN`) / `AUTO_MODE` the calling command already composed for its own panel dispatch |
| `SYNTHESIS_MODEL` | Optional. When set, the synthesis Agent call uses this model instead of inheriting from the dispatching command. |
| `PRE_AGGREGATE` | Optional. When `true`, pre-aggregation and raw finding count computation run before synthesis dispatch. |
| `CONDITIONAL_CEILING_THRESHOLD` | Optional integer. Requires `PRE_AGGREGATE=true` (the script computes `RAW_FINDING_COUNT`). When set, the synthesis ceiling scales: `RAW_FINDING_COUNT >= threshold` → 1500s, otherwise 900s. |

## Invoking the Wait

```bash
speckit run review-wait.sh --attempt-dir "$ATTEMPT_DIR" --expect reviewers
```

Pass a tool timeout of at least 120 seconds (the script's 90s default budget plus margin) on every call. Relay stdout **verbatim** to the user — it carries the delivery table, the coverage line and the quorum verdict. Read the `review_wait_status:` line from **stderr** as control input; never display it.

## Wait-Token Branch Table

Six outcomes reach this point. Every one below resolves to either a re-invocation or a terminal record — none may fall through unhandled.

| Token | Action |
|---|---|
| **No token at all** (killed invocation, no `review_wait_status:` line on stderr) | Re-invoke the same wait call unchanged. Absence is never an outcome — a killed invocation emits no token, and treating silence as a verdict is exactly the failure mode this feature retires. |
| `in_progress` | Re-invoke the same wait call unchanged. Never proceed past this token. |
| `no_artifacts` | The stdout already carries the adopter-facing remedy verbatim (the script prints it inline). Route to **Terminal Records** below with reason `infra-failure` — zero artifacts of any kind is a total contract break, not a slow panel. |
| `infra_error` | Route to **Terminal Records** below with reason `infra-failure`. |
| `all_delivered` | Execute **Pre-Synthesis Preparation** (below, when applicable), then **Dispatch Synthesis**, write `synthesis_deadline_epoch`, then re-invoke the wait with `--expect synthesis`. |
| `ceiling_reached` | See **Ceiling Handling** below — the unattended and attended branches differ. |

### Pre-Synthesis Preparation

*`SYNTHESIS_MODEL`, `PRE_AGGREGATE`, and `CONDITIONAL_CEILING_THRESHOLD` are plan-review-specific bindings — spec review never sets them, so this section is inert there.*

*Runs between `all_delivered` and Dispatch Synthesis. All steps are gated on optional bindings — when no optimization bindings are set, this section is a no-op and Dispatch Synthesis runs immediately.*

**Pre-aggregation and finding count** (when `PRE_AGGREGATE` is `true`):

```bash
speckit run review-pre-aggregate.sh --attempt-dir "$ATTEMPT_DIR"
```

On exit 0: parse stdout for `AGGREGATE_PATH` and `RAW_FINDING_COUNT`.
On exit non-zero: log warning from stderr. Proceed without `AGGREGATE_PATH` — synthesis reads individual finding files as a fallback.

**Conditional ceiling** (when `CONDITIONAL_CEILING_THRESHOLD` is set and `RAW_FINDING_COUNT` is available):

If `RAW_FINDING_COUNT >= CONDITIONAL_CEILING_THRESHOLD`: set `SYNTHESIS_CEILING_SECONDS = 1500`.
Otherwise: read `ceiling_seconds` from `$ATTEMPT_DIR/manifest.json` (the same field the reviewer wait's own deadline used, which a "continue waiting" extension may have already raised above 900) and set `SYNTHESIS_CEILING_SECONDS = max(900, that value)`. This low-count branch exists to keep synthesis fast on ordinary volume — it must never shorten a deadline the reviewer wait itself already extended.

### Dispatch Synthesis

```
Agent("general-purpose", """
Execute the synthesis pipeline in `{SYNTHESIS_TEMPLATE}`.

FEATURE_DIR={FEATURE_DIR}
FEATURE_SPEC={FEATURE_SPEC}
GATE_TYPE={GATE_TYPE}
AUTO_MODE={AUTO_MODE}
ATTEMPT_ID={ATTEMPT_ID}
ATTEMPT_DIR={ATTEMPT_DIR}
PANEL_SIZE={PANEL_SIZE}
""")
```

Use the same `FEATURE_SPEC`/`IMPL_PLAN` binding the calling command's own panel dispatch used. The illustration above shows only the bindings common to every review type — when `SYNTHESIS_MODEL` is set, add `model: "{SYNTHESIS_MODEL}"` to the Agent call; when Pre-Synthesis Preparation produced `AGGREGATE_PATH`, forward it to the synthesis bindings as `AGGREGATE_PATH={AGGREGATE_PATH}`. Whenever the calling command set `PRE_AGGREGATE`, forward it unchanged as `PRE_AGGREGATE={PRE_AGGREGATE}` too — synthesis needs it to tell a `failed` pre-aggregation (requested, no usable `AGGREGATE_PATH`) apart from `skipped` (never requested); `AGGREGATE_PATH` alone can't distinguish the two. Before waiting on it, patch the manifest so the synthesis wait has a deadline to compare against — `synthesis_deadline_epoch` is `now + ceiling_seconds`, reusing the same `ceiling_seconds` the reviewer wait was bounded by:

```bash
if [ -n "${SYNTHESIS_CEILING_SECONDS:-}" ]; then
  CEILING_SECONDS="$SYNTHESIS_CEILING_SECONDS"
else
  CEILING_SECONDS=$(jq -r '.ceiling_seconds' "$ATTEMPT_DIR/manifest.json")
fi
SYN_DEADLINE=$(( $(date +%s) + CEILING_SECONDS ))
jq --argjson d "$SYN_DEADLINE" '.synthesis_deadline_epoch = $d' "$ATTEMPT_DIR/manifest.json" > "$ATTEMPT_DIR/manifest.json.tmp" \
  && mv "$ATTEMPT_DIR/manifest.json.tmp" "$ATTEMPT_DIR/manifest.json"
```

Then wait: `speckit run review-wait.sh --attempt-dir "$ATTEMPT_DIR" --expect synthesis`. This wait's own tokens route through the same branch table above — `no token`/`in_progress` re-invoke, `infra_error` routes to Terminal Records, `all_delivered` proceeds to **Outcome Classification**, and `ceiling_reached` under `--expect synthesis` has no quorum option — route straight to Terminal Records with reason `synthesis-failure` (no synthesis marker ever appeared).

### Ceiling Handling (reviewer wait only)

Parse `AGENTS_COMPLETED` from the relayed stdout's `Coverage: N/M reviewers delivered.` line (`M` is `PANEL_SIZE`) and the `Quorum: met`/`Quorum: not met` verdict from the line beneath it — these are the same figures the completion report needs; do not re-derive them by re-invoking the wait.

- **Unattended** (`ATTENDED == false`): the script's own quorum verdict decides.
  - **Quorum met** → proceed on partial findings: call `review-attempt.sh abandon --attempt-dir "$ATTEMPT_DIR" --reason partial-coverage --coverage "$AGENTS_COMPLETED/$PANEL_SIZE"` **first** (this is the permanent record of who was still outstanding at the ceiling), then execute **Pre-Synthesis Preparation** (when applicable) and **Dispatch Synthesis** exactly as the `all_delivered` row does — synthesis reads live delivery state and writes the real gate with `--partial` since coverage is short. Disclose the attempt directory location in the final report; `cleanup`'s coverage refusal means this directory is retained forever.
  - **Quorum not met** → route to **Terminal Records** with reason `ceiling`.
- **Attended** (`ATTENDED == true`): the calling command's own inline ceiling prompt (continue waiting / proceed with partial / abort / freeform duration / discuss first) decides. An unanswered prompt within its stated interval falls through to the **Unattended** rule above.
  - "Continue waiting" → see **Extension Re-entry** below.
  - "Proceed with partial findings" → same as the unattended quorum-met branch above, regardless of what the script's own quorum verdict says — the user's choice overrides it.
  - "Abort" → route to **Terminal Records** with reason `user-abort`.

## Extension Re-entry

```bash
speckit run review-wait.sh --attempt-dir "$ATTEMPT_DIR" --extend "$SECONDS"
```

Default `$SECONDS` to 300 when the user chose "continue waiting" without naming a duration.

| Exit | Response |
|---|---|
| `0` | Re-invoke the reviewer wait (`--expect reviewers`) from the top of the branch table. |
| `5` | Over-cap extension. Re-present the ceiling prompt, naming the 1800s cumulative cap in the re-prompt. |
| `2` | Route to **Terminal Records** with reason `infra-failure`. |

## Outcome Classification

Applies wherever this protocol reads `synthesis.done.json` or `review/review-gate.json` to decide what happened.

**Check both against the current `ATTEMPT_ID`.** A file that is absent, or whose `attempt_id` differs from `ATTEMPT_ID`, is **"not yet written"** — never a verdict. This covers the ordinary crash-recovery gap (a prior gate from an earlier attempt still on disk), not a fresh signal to act on. An absent or malformed status line in an agent's own returned text is likewise not evidence of failure — the artifacts on disk are the only record this protocol trusts.

**Do not retry while any step this attempt dispatched is still outstanding.** A dispatched `Agent()` call that has returned control has necessarily finished writing its artifacts by the time control returns — re-reading disk immediately afterward is safe. What this guard forbids is treating a *not-yet-concluded* wait (an `in_progress` token, or a `synthesis.done.json` that has not yet appeared) as grounds to re-dispatch synthesis a second time, or to declare failure before the wait itself has returned a terminal token.

Only these conditions are genuine failures, ready to route to **Terminal Records**:
- `synthesis.done.json` present, `attempt_id` matches, `status == "error"` → reason `synthesis-failure`.
- `synthesis.done.json` reports `gate_written: true` but `review/review-gate.json` is absent or its `attempt_id` doesn't match → reason `synthesis-failure` (the gate-write half).
- Any wait-script terminal token already routed above (`ceiling_reached` under `--expect synthesis`, `infra_error`, `no_artifacts`).

Otherwise — `status` is `ok`, `all_auto_applied`, or `quorum_failed` — this is a normal conclusion, not a terminal-record path. Return control to the calling command's completion report with the fields `synthesis.done.json` carries.

## Terminal Records

Four categories each reach a terminal record: a synthesis-or-gate-write failure, an abort, an infrastructure failure, and the unattended (or user-chosen) partial-coverage proceed already handled above. Every one of them:

1. Calls `review-attempt.sh abandon --attempt-dir "$ATTEMPT_DIR" --reason <reason> --coverage "$AGENTS_COMPLETED/$PANEL_SIZE"` **first** — before anything else, including any gate write.
2. **Records the gate.** For the partial-coverage-proceed path this is satisfied by the synthesis dispatch already underway (it writes `review/review-gate.json` itself, forwarding `--partial`). For the other three categories — no successful synthesis output exists to rely on — write a blocked gate directly:
   ```bash
   speckit run write-review-gate-unified.sh \
     --gate-type "$GATE_TYPE" \
     --status blocked \
     --must-address 0 \
     --should-consider 0 \
     --minor 0 \
     --agents-completed "${AGENTS_COMPLETED:-0}" \
     --panel-size "$PANEL_SIZE" \
     --quorum-met false \
     --attempt-id "$ATTEMPT_ID" \
     --partial
   ```
3. **Discloses the retained attempt-directory location to the user.** Every one of these paths leaves the attempt directory behind — `cleanup` refuses on the `abandoned.json` this step just wrote — so the findings a reviewer already published are recoverable only if the user is told where. State the absolute `$ATTEMPT_DIR` path plainly.

| Category | `abandon --reason` |
|---|---|
| Synthesis or gate-write failure | `synthesis-failure` |
| Abort (user chose it at the ceiling prompt) | `user-abort` |
| Infrastructure failure (`infra_error`, `no_artifacts`, or extension exit 2) | `infra-failure` |
| Ceiling reached, quorum not met, unattended | `ceiling` |
| Ceiling reached, quorum met, proceeding on partial findings | `partial-coverage` |

## Cleanup

`review-attempt.sh cleanup --attempt-dir "$ATTEMPT_DIR" --gate-file "$FEATURE_DIR/review/review-gate.json"` runs **only after** the canonical findings and gate are durable on disk — never before. On the ordinary `ok`/`quorum_failed` outcomes, that means immediately after `Outcome Classification` confirms the gate matches `ATTEMPT_ID`. It succeeds only at full coverage; see "A refused cleanup retains and discloses" below for the partial case.

**Deferred on the `all_auto_applied` path.** Synthesis skips its own gate write there — the calling command writes the gate itself, after presenting the auto-applied/discarded confirmation. Cleanup therefore waits for that write: call it once the command's own gate write lands, never before.

**A rejected confirmation retains and discloses.** If the user rejects the auto-applied/discarded confirmation, do not call cleanup at all — disclose the attempt directory location instead, exactly as a terminal-record path does.

**A refused cleanup retains and discloses.** `cleanup` exits non-zero and removes nothing whenever coverage is short of the panel size (`agents_completed < panel_size` on the gate it was handed). Both ordinary outcomes reach this: `quorum_failed` by definition, and `ok` whenever any reviewer wrote a `failed` marker — the wait still returns `all_delivered` once every marker is terminal, so a failed reviewer produces a normal conclusion at less than full coverage. Treat a non-zero exit as a **retention, not an error**: state the absolute `$ATTEMPT_DIR` path in the completion report, in the same words a terminal-record path uses (Terminal Records step 3). Do not report the refusal as a cleanup failure, and do not retry it. Retention without disclosure is the failure this guards against — the per-reviewer findings survive on disk and nobody is told where, which on `quorum_failed` is the case where recovering them matters most.

Every one of the four terminal-record categories above already retains its attempt directory permanently (`cleanup`'s abandonment refusal), so none of them call `cleanup` either.
