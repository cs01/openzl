---
name: speckit-sdd-coevolution
description: 'SpecKit SDD pipeline: check co-evolution compliance between code changes and `specs/<feature>/spec.md`.'
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: sdd:commands/speckit.sdd.coevolution.md
disable-model-invocation: false
---


# Co-evolution Compliance Check

Checks whether spec-covered source files have been modified without a corresponding spec update in the same commit. Outputs a warning if co-evolution drift is detected.

## When to Use

Run before committing when you've modified code that is covered by a spec. The check is informational only — it warns but does not block.

## Execution

Before starting work, briefly tell the user what this stage does and why it matters.

```bash
bash .specify/extensions/sdd/scripts/bash/coevolution-check.sh
```

## What It Checks

1. Scans all `specs/*/spec.md` files for `### Source Files` sections
2. Extracts the listed file paths (the spec-covered code)
3. Compares against `sl status` to find modified files
4. If any spec-covered file is modified and no spec file (`specs/*`) is also modified, prints a warning

## Behavior

- **Always exits 0** — this is a Phase 2 pilot nudge, not a gate
- Gracefully handles missing Sapling, missing specs directory, or no changes
- If drift is detected, display a brief natural-language warning (e.g., "Heads up: you modified files covered by a spec but haven't updated the spec in this commit"). Do not reference script names or implementation paths in user-facing messages.
