# Contract: the coverage record

`CONTRACTS.md` at the repository root is the artifact a reviewer reads (US2).
It is part hand-authored prose and part generated table. This contract fixes
which is which, so `render.py` and a human editing the same file do not
overwrite each other.

## Region model

| Region | Authored by | Content |
|---|---|---|
| Everything outside markers | Human | Scope, Requirements, Running, Legend, Gotchas, Open questions, and the rationale prose under each findings heading |
| Between `<!-- BEGIN GENERATED: <id> -->` and `<!-- END GENERATED: <id> -->` | `render.py` | Tables derived from `proofs/cases.tsv` |

`render.py` MUST NOT alter a byte outside a marker pair. `render.py --check`
compares only the generated regions, so hand edits to prose never make the
record report as stale.

## Required generated regions

| `<id>` | Contents | Satisfies |
|---|---|---|
| `coverage` | One row per manifest entry with `expect != -`: function, mode, expected verdict, what it establishes, reproduction command | FR-007, FR-008, FR-009a |
| `reasons` | One row per manifest entry with `mode = none`: function, reason class, note | FR-007, D2 acceptance bar |
| `defects` | One row per entry with `reason_class = defect`: function, what is wrong, reproduction command, expected verdict `FAIL` | FR-010, SC-004 |
| `samples` | Per codec: count of `PASS` rows, count of reason rows, and whether any defect was found | FR-011, SC-006 |
| `scope` | Counts: in-scope headers, in-scope functions, rows by reason class | SC-001 |

## Headings that must not be merged

FR-010 requires defects and non-defect observations under headings that do not
conflate them. The existing record already does this, after an earlier
correction split a table headed "Undefined behavior discovered" that contained
non-UB rows. The split is preserved:

- A heading asserting a defect was found contains only `reason_class = defect`
  rows. When there are none, its generated region renders the count and the
  sample size — never the bare word "None" without the denominator.
- Observations — unstated preconditions, prose/contract divergences — sit under
  a heading that does not imply a defect, with hand-written rationale for why
  each is not a bug.

## Sample-size rule

Every "nothing found here" statement is generated with the number behind it.
`render.py` computes it; no human types it. A codec with three proved functions
and no defect renders as a claim resting on three functions, not as a clean
codec. This is SC-006, and it is enforced by construction rather than by review.

## Reproduction commands

Each command in the `coverage` region is standalone: the full `prove.sh`
invocation with its flags, runnable after setting `CF` as the Running section
documents. It is not `proofs/run.sh --filter X`, because SC-003 asks a reviewer
who has run nothing to reproduce one verdict, and the per-entry command is the
shortest path to that.

## Consumers

| Consumer | Depends on | Effect of a change here |
|---|---|---|
| A reviewer (US2) | Prose and tables both | The whole point; no breakage possible |
| `render.py --check` | Marker pairs being present and balanced | A removed marker is exit 2, not a silent no-op |
| `proofs/run.sh` | Nothing in this file | The runner reads the manifest, never the record — that separation is why the record can be prose-heavy |
| `README.md`, `CONTRIBUTING.md` | Currently neither links `CONTRACTS.md` | No existing link to break; adding one is optional and out of scope |
