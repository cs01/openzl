---
description: Shared layer-allocation and finding-routing doctrine for verify command agents
---

VERIFICATION DOCTRINE:

LAYER ALLOCATION:
SpecKit artifacts own different layers. A finding's fix belongs to the artifact that owns its layer.

- `spec.md` owns WHAT and WHY — user-observable behavior, external contracts, data shapes, constraints, rationale.
- `plan.md` / `tasks.md` own HOW — architecture, sequencing, file-level changes.
- `CLAUDE.md` and other project documentation are governed directly by the constitution's principles, not owned by the spec/plan layers — a finding against them is `route: none`, informational only, since no agent here has the evidence base to target it for an automated fix.
- The verification report owns DISCOVERY — internal mechanics learned by reading code.

THE REWRITE TEST:
A statement belongs in `spec.md` only if it would still be true after the implementation is rewritten with entirely different internals. If a sentence names a function, method, variable, constant, class, decorator, module, file path, or call/iteration order, it is HOW — it does not belong in `spec.md`, no matter how important it is.

NEVER suggest adding to `spec.md`:
- Identifier names of any kind (functions, methods, variables, constants, classes, dicts)
- Framework mechanisms (hooks, decorators, `atexit`, middleware, signals, callbacks)
- Internal data structures or their contents
- Control flow, iteration order, or call ordering
- Any new requirement whose sole justification is "the code does this and the spec doesn't say so"

SPEC-WORTHINESS TEST:
Before proposing that any behavior be added to `spec.md`, confirm it passes at least one of these:

- (a) **Observable** — a user or calling system can see it: output, error message, exit code, API response, a file created or modified.
- (b) **External contract** — a CLI flag, config key, schema field, file format, or path that another tool or team depends on.
- (c) **Data shape / persistence** — what is stored, its structure, its lifetime.
- (d) **Security, permission, or privacy** relevant.
- (e) **Contradicts an implied guarantee** — the spec states a universal ("all X are Y", "every skill gets Z") and the code exempts some cases. Report as a scope correction to the EXISTING requirement — never as a new requirement describing the mechanism of the exemption.

A behavior that passes none of these is `route: discovery`.

MATERIALITY TEST:
A spec edit must change what a reader would build, test, or decide. Before proposing one, state what a reader would do differently once it lands. If the answer is "nothing — the text just reads better", the finding is `route: none`: note it, do not edit the spec.

Never propose a spec edit for:
- Wording preference, synonym choice, or tone
- Restating something the spec already says elsewhere
- Adding emphasis, examples, or elaboration to text that is already correct and unambiguous
- Formatting, heading style, or list structure
- Defining a term whose meaning is clear in context

Specs are read end-to-end by humans. Every added line spends attention from every future reader. A correct spec that is silent on a point beats a correct spec that belabors it.

EDIT ECONOMY:
Every spec edit you propose must be the smallest one that fixes the defect.

- **Amend before adding.** If an existing requirement covers the behavior, correct that requirement in place. Add a new requirement only when no existing one covers it — and name the requirements you checked.
- **Replace, don't append.** Give the corrected text as a full replacement for the quoted wrong text, so applying it is a swap rather than a growth.
- **One sentence.** A spec edit is a single sentence unless the defect genuinely spans more. No preamble, no restating the problem, no rationale — rationale belongs in your finding, not in the spec.
- **Report the cost.** Every finding that edits an artifact carries `net_lines:` — how many lines that artifact gains or loses if your suggestion is applied. `0` for a one-line swap, `+1` for a new single-line requirement. Zero or negative is the target.

PROVENANCE TEST:
Some spec content records a decision a human made. It is evidence of intent, not a claim about the code, and it is never wrong just because the code disagrees with it.

Treat these sections as a transcript — NEVER `route: spec.md`, never rewritten, never "made consistent":
- `## Clarifications` — literal questions and the answers a human gave
- `## Design Decisions` — choices made with rationale
- `## Premise Validation` — the go/no-go judgement

Before routing ANY finding to `spec.md`, ask where the claim came from. If it traces to one of those sections — a requirement that restates a clarification answer, a constraint that implements a design decision — the code is what diverged. Route it `code`. If you believe the recorded decision is itself wrong, that is a question for the human: say so in the finding and leave both the requirement and the transcript untouched. Silently editing a recorded answer to match shipped behavior destroys the only record that the decision was ever made differently.

CODEBASE GROUNDING RULE:
A spec's `## Codebase Grounding` section documents facts verified at spec authorship time. CG claims use present tense as a convention of the observation form — they are point-in-time records, not invariants about the current code state.

Do NOT flag a CG claim as a SPEC-DEFECT solely because the code has since changed — including changes made by the spec's own implementation. A CG claim that was accurate when written and informed the spec's requirements has served its purpose. When the code now satisfies an FR that the CG claim motivated, all three artifacts (CG observation → FR requirement → code implementation) are consistent, not contradictory.

Only flag a CG claim if:
- It was factually wrong at the time of writing (verify via `sl log` at the spec's `created` date)
- A factual error causes a reader to derive wrong conclusions about what the spec REQUIRES

RECENT-COMMIT CORROBORATION RULE:
`search_files` queries hit a secondary index that can lag behind freshly-committed code by tens of minutes — a file that exists on disk and in the commit history can return zero results until the index catches up. `/speckit-verify` always runs immediately after `/speckit-implement`, so the code under verification is, by construction, often only minutes old — exactly the window where this lag bites.

Before reporting a finding that an artifact does not exist — a missing file, a missing generated build output, a missing symbol, class, or config declaration — corroborate any negative `search_files` result with a direct check:
- `Read` the exact expected file path, or `ls` the exact expected directory, if you can name it precisely.
- If the artifact should have been produced by a recent commit, inspect that commit directly (e.g. `sl show <rev> --stat`) rather than trusting a secondary index.

A single `search_files` negative on code from the most recent commit(s) is not sufficient evidence of absence. Do not report a missing-artifact finding as `must-address` without this corroboration. If corroboration is not possible within the available tool budget, downgrade the finding to `should-consider` and state explicitly that non-existence was inferred from `search_files` alone and was not independently confirmed via direct file read or commit inspection.

ROUTING:
Every finding MUST carry a `route` field. The route names the artifact that must change.

| `route` | Use when | Gates status? |
|---------|----------|---------------|
| `spec.md` | The spec ASSERTS something the code contradicts, or a name/label/value/direction/condition stated in the spec is wrong — AND the claim does not trace to a recorded decision (see PROVENANCE TEST) | Yes |
| `code` | The spec states a required user-observable behavior the code does not implement | Yes |
| `discovery` | Real, correct implementation behavior the spec does not mention AND should not — internal mechanics | No |
| `none` | Informational only | No |

`route: spec.md` requires you to quote the exact spec text that is wrong. If you cannot quote a specific incorrect claim, the finding is NOT `route: spec.md`. "The spec is silent about X" is never `route: spec.md`.

`route: discovery` findings are capped at severity `minor` and are never `must-address`. They are recorded for the record, not fixed. Recording them is a successful outcome — a spec that omits internal mechanics is CORRECT, not incomplete.

`plan.md` and `tasks.md` are never routes. `/speckit-verify` only runs after `/speckit-implement` has executed every task, so both artifacts already describe completed work — a HOW-artifact inconsistency discovered now has nothing left to fix. The Cross-Artifact agent reports these as `route: none` (informational) or, if the underlying claim is actually wrong in `spec.md`, as `route: spec.md`.
