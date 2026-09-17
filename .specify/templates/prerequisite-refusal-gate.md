---
description: "Shared graduated gate presented when a pipeline-state write is refused for an unmet prerequisite"
---

# Prerequisite Refusal Gate

**Design note (not for the user):** This template is a `Read and execute` pointer target, not an `Agent()` dispatch target. The three-way choice below is an interactive decision that belongs in the invoking stage's own main context — a subagent dispatch would return a summary of a choice the user was supposed to make themselves, so it stays inline here even though the content is heavy enough that isolating it would otherwise be the usual pattern.

## When this applies

A pipeline-stage write was **refused** because a prerequisite stage hasn't completed yet (exit code 4 from the writer, or from a script that calls it). This can surface two ways:

- **Directly**: a command's own write call exits 4.
- **Via a hook**: a post-completion hook dispatch reports that its underlying write was refused, rather than swallowing it as a routine warning.

**Exit code 5 is a different problem — do not use this gate for it.** A `SPECKIT-GUARD-FAULT:`-prefixed diagnostic means the guard's own machinery failed (a config read error, a lock timeout, etc.) — it is not a statement about whether prerequisites are met. Relay that diagnostic to the user verbatim and stop; do not present the three options below for it.

**Exit code 6 is a different problem too — do not use this gate for it.** A `SPECKIT-STATE-WRITE-FAILED:`-prefixed diagnostic means the record was decided on but could not be appended to the history file — a permissions or I/O failure, not a decision about prerequisites. None of the three options below applies: there is no prerequisite to fix, and Override would re-attempt a write that will fail the same way. Relay that diagnostic to the user verbatim and halt. Do not present the Override / Fix now / Defer menu, do not retry, and do not continue the stage as though its completion had been recorded — it was not, and every later prerequisite check will read this stage as one that never ran.

## The three options

When a write is refused, stop and present exactly these three choices — do not pick one on the user's behalf, and do not invent a fourth:

1. **Override** — Re-invoke the same write, adding `prereq_override_reason=<a short reason the user gives>`. This is the only sanctioned bypass; there is no second override mechanism. The recorded entry will carry the override marker and the reason verbatim, so use the user's own words rather than paraphrasing.
2. **Fix now** — Run the pipeline command that produces the missing prerequisite stage, then retry the original write. The refusal diagnostic names which stage is missing; recommend the command that produces it (for example, a missing `plan` stage means `/speckit-plan`).
3. **Defer** — Leave the entry unrecorded and stop here. Warn the user this has two consequences: later stages in the chain may also decline (a cascading effect), and any tool that reads pipeline history — including the pipeline diagram — will show a gap at this stage rather than a completed one.

Wait for the user's choice before proceeding. Do not default to Override or Fix now without asking.

## Unattended runs

If this stage is running unattended (autopilot, an auto-resolve loop, or any flow that already has its own non-interactivity detection), do not present the three-way choice — there is no one to answer it. Halt and surface the refusal diagnostic instead, exactly as you would any other blocking failure in that flow. Use whatever non-interactivity detection your flow already has; this template does not define a new one.

## Presenting via the hook boundary

If you discover the refusal through a hook dispatch rather than a direct call, do not treat it as a routine "hook failed, log a warning and continue" case. Surface it the same way a direct exit 4 would be surfaced — read and act on this template — because the underlying problem (an unmet prerequisite) is identical regardless of which path found it.

## After the user chooses

- **Override chosen**: re-run the write with `prereq_override_reason=<reason>` appended, then continue the stage's normal flow as if the write had succeeded the first time.
- **Fix now chosen**: stop this stage's execution, tell the user to run the named recovery command, and do not attempt the original write again yourself — the user will re-invoke this stage once the prerequisite exists.
- **Defer chosen**: stop this stage's execution cleanly. Do not write anything. Do not suppress the diagnostic already shown.

Never treat a refusal as something to route around silently. Every path above ends with either a recorded override, a clean stop pointing at a fix, or an explicit, disclosed gap — never a hidden retry loop.
