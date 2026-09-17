---
description: "SpecKit internal: display ASCII pipeline progress diagram from `specs/<feature>/pipeline-state.jsonl`."
---

# Pipeline Progress Display

Display the SpecKit pipeline progress diagram showing completed stages, current stage, and upcoming stages.

## Behavior

This command is invoked as a lifecycle hook at stage boundaries (before/after review, plan, tasks, etc.). It displays the pipeline state diagram to provide visual context for where the user is in the SDD workflow.

## Execution

1. **Determine the stage and status** from the calling context:

   The hook name indicates both the stage and whether it's entry or exit:
   - `before_<stage>` → status: `running`
   - `after_<stage>` → status: `complete`

   Supported stages: `specify`, `clarify`, `review`, `plan`, `tasks`, `analyze`, `implement`, `verify`, `scan`, `generate`

   Parse the hook name to extract the stage:
   - Hook name format: `before_<stage>` or `after_<stage>`
   - Extract stage from the hook context (the calling skill should identify itself)
   - Determine status: `before_*` → `running`, `after_*` → `complete`

2. **Run the pipeline diagram script**:

   ```bash
   speckit run speckit-pipeline-diagram <stage> <status>
   ```

   where `<stage>` is the parsed stage name and `<status>` is either `running` or `complete`.

3. **Display the output**:

   Show the diagram output in a code fence to ensure it's visible in the main chat:

   ```
   <diagram output>
   ```

   **CRITICAL**: The diagram MUST appear in your text response, not just in tool call details. Users need to see the pipeline state without expanding tool results.

## Example Output

When invoked as a `before_review` hook:

```
  ✓ specify ──▶ ✓ clarify ──▶ ● review ──▶ plan ──▶ tasks ──▶ analyze ──▶ implement ──▶ verify
  ▲ running
```

When invoked as an `after_review` hook:

```
  ✓ specify ──▶ ✓ clarify ──▶ ✓ review ──▶ plan (next)

  ▶ /speckit-plan
```

## Notes

- This command is designed to run automatically via hooks — direct user invocation is not expected
- The diagram uses ANSI color codes for visual clarity (green checkmarks, bold current stage)
- If the diagram script fails, log a warning but don't block the calling command
