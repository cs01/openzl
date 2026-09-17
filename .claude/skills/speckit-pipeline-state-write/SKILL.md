---
name: speckit-pipeline-state-write
description: 'SpecKit internal: write stage completion to `specs/<feature>/pipeline-state.jsonl`.'
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: pipeline-state:commands/pipeline-state.write.md
---

# Pipeline State Writer

Record pipeline stage completion in `pipeline-state.jsonl` for tracking and diagram rendering.

## Behavior

This command is invoked as a lifecycle hook after each pipeline stage completes (`after_*` hooks). It writes a completion entry to the feature's `pipeline-state.jsonl` file.

## Execution

1. **Determine the stage** from the calling context:

   The hook name indicates the stage:
   - `after_<stage>` → stage name is `<stage>`

   Supported stages: `specify`, `clarify`, `review`, `plan`, `tasks`, `analyze`, `implement`, `verify`, `scan`, `generate`

2. **Write pipeline state**:

   ```bash
   speckit run write-pipeline-state.sh <stage> status=complete
   ```

   where `<stage>` is the parsed stage name.

3. **Error handling**:
   - **If the script exits 4** (a chain-stage prerequisite is unmet — this can occur for `specify`, `plan`, `tasks`, `implement`, or `verify`, whichever of them reaches the writer only through this hook rather than an inline call): this is NOT "the script failed" for suppression purposes. Relay it to the invoking stage's own error-surfacing path — the same mechanism this hook already uses for any other blocking result — and read and execute `.specify/templates/prerequisite-refusal-gate.md` there. Do not log it as a routine warning and continue.
   - **If the script exits 5** (a guard-internal fault): the stage completion was **not** recorded, exactly as with exit 4, so this must not be swallowed either. Relay it to the invoking stage's own error-surfacing path and read and execute `.specify/templates/prerequisite-refusal-gate.md` there, which distinguishes a fault from a refusal. Logging it as a routine warning would let the stage continue believing its completion was recorded, leaving the same silent gap in the history that the exit-4 handling above exists to prevent.
   - **If the script exits 6** (the record could not be written to the history file — a permissions or I/O failure, not a decision): the stage completion was **not** recorded, so this must not be swallowed either. Relay it to the invoking stage's own error-surfacing path exactly as exit 4 and exit 5 are relayed, then **halt with the `SPECKIT-STATE-WRITE-FAILED:` diagnostic relayed verbatim**. Do **not** read or execute `.specify/templates/prerequisite-refusal-gate.md` for this code, and do not present the Override / Fix now / Defer choice: no prerequisite is unmet, so none of those three options applies, and Override would only re-attempt a write that fails the same way. This is the one of the three that most easily passes for success — nothing about the run looks wrong afterwards, and the missing record reads to every later prerequisite check as a stage that never ran.
   - **For any other non-zero exit** (e.g., missing `feature.json`, missing script): log a warning but do not block the calling command. This is unchanged from before.

## Notes

- This command writes to `specs/<feature>/pipeline-state.jsonl` (feature-scoped, append-only)
- Review and clarify commands may write additional metadata (gate_type, question counts) via their own inline calls — this hook provides the baseline entry for stages that don't have inline writes
- The `write-pipeline-state.sh` script handles deduplication via sequence numbers
