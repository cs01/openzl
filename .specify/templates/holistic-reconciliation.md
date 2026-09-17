---
description: Shared pre-write consistency check run over composed artifact content by every resolution path
---

HOLISTIC RECONCILIATION PASS:

This file defines one named procedure — the **Holistic reconciliation pass**. Every resolution
path runs it over composed content before that content reaches disk, and every path runs the same
one, so the four paths cannot drift apart on what "checked" means.

Use this name verbatim when announcing the pass. Do not rename it per path.

## What this pass exists to catch

Accepted fixes are composed into an artifact one after another. Each fix is sensible on its own;
the composed result may not be. A fix that changes a rule and another fix that restates the old
rule two sections down both apply cleanly and produce an artifact that contradicts itself. Nothing
reads the result before it is written, so the contradiction ships behind a gate that reports a
clean pass.

This pass is the read-back. It runs after composition and before the write, on every artifact that
received at least one fix — markdown artifact or source file, one fix or ten.

## Inputs the caller binds before running the pass

| Variable | Type | Meaning |
|---|---|---|
| `COMPOSED` | map: artifact path → candidate content | The full in-memory content of each artifact after every accepted fix routed to it has been applied |
| `BASELINES` | map: artifact path → pre-fix content | Each artifact's content as at the start of this pass, retained by the caller for the whole pass |
| `WRITTEN_REGIONS` | map: artifact path → spans | The regions of the composed content that a fix in this run wrote |
| `CONTRIBUTING` | map: artifact path → finding IDs | Which findings' fixes are in each composed artifact |
| `CANDIDATE_SET` | ordered list of artifact paths | The counterpart artifacts this stage declares in scope |
| `USER_PRESENT` | boolean | Whether a human is present to answer an escalation prompt |
| `GROUPS` | list of interacting groups, each with a repair budget | Optional |

`USER_PRESENT` is determined by the **dispatched path**, not by a mode chosen inside it. A bulk
"resolve everything remaining" selected by a user inside an interactive session is still
user-present: the human who chose it is still at the keyboard.

`GROUPS` is optional. When the caller supplies no groups, treat each composed artifact as its own
repair unit. That is the correct behaviour, not a degraded one.

**Absence of an outcome is not a clean outcome.** When no finding was accepted, nothing is composed
and this pass does not run. Do not report that as a passing check.

## What to read — the bound on this pass

Read exactly these, and nothing else:

- every artifact in `COMPOSED`, in full
- every artifact in `CANDIDATE_SET`
- source files cited in the evidence of the findings listed in `CONTRIBUTING`

**No repository-wide search.** Do not grep the tree for related content, do not follow references
out of the candidate set, and do not open files because their names look relevant. The bound above
is the whole read cost of this pass, and it is stated here so that no caller has to restate it.

## Detection

Read each composed artifact's content — the composed result, not the individual fixes — and look
for these five classes of defect.

1. **Internal contradiction** — two statements in the artifact that cannot both hold. A rule
   changed in one place and stated in its superseded form in another; a requirement whose
   condition contradicts a condition stated elsewhere; an instruction that forbids what a
   neighbouring instruction requires.
2. **No-effect branch** — an instruction block or code block whose branches all produce the same
   result, or produce no result at all. A conditional whose arms are identical, a guard that can
   never be false, a menu whose options all lead to the same place.
3. **Syntax error** — content that will not parse: an unclosed code fence, a broken table, a
   malformed list, invalid syntax in a source file.
4. **Duplicate or conflicting edit** — two fixes that wrote the same line or the same region, so
   that one silently overwrote the other, or both landed and the region now says something neither
   fix intended.
5. **Stale counterpart** — a rule this run changed that another artifact still states in its
   superseded form. Detecting this requires more than one artifact in scope; see the cross-artifact
   section at the end of this file.

**No-effect detection over a source file is confined to `WRITTEN_REGIONS`.** An inert branch that
was already in the file before this run is not this run's defect and is not reported by this pass.
The same confinement does not apply to markdown artifacts, where a fix's effect on the surrounding
document is the thing being checked.

**A mechanical parse is permitted alongside your own reading.** This pass is agent judgment: you
read the composed content and decide whether it holds together. Nothing here forbids also running
a parser, a syntax checker, a formatter in check mode, or any other mechanical tool over a
composed source file, and for a source-code artifact you should. Use the tool for what a tool is
good at and your own reading for the rest. The mechanical result never substitutes for the read.

### Attribution — is this defect ours?

A defect the artifact already had is worth reporting and is not grounds for discarding this run's
work. Decide which it is:

- A defect **absent from this artifact's baseline content** is attributed to this run.
- A statement reproduced **unchanged** inside a larger rewrite is not a statement this run changed,
  even though the rewrite touched the lines around it.
- **Exception**: a rule this run changed counts as a participating statement wherever it appears.
  If a fix here changed a rule and a counterpart artifact states the superseded form, that
  contradiction is attributed to this run even though the counterpart received no fix at all.

A defect attributed to neither branch is pre-existing. Report it; do not discard this run's fixes
over it.

## Outcomes

Every artifact in `COMPOSED` gets exactly one outcome, set exactly once per pass.

| Outcome | When | What the caller does |
|---|---|---|
| `clean` | No defect attributed to this run | Write the artifact |
| `repaired` | A defect was found and one re-compose fixed it | Write the artifact; report the defect and the repair |
| `unrepairable` | A defect survived the re-compose | Escalate or discard — see below |
| `accepted-as-override` | A human accepted a composition that failed the check | Write the artifact; record the gate as overridden and state the accepted defect |

### The repair attempt is bounded at one

On a defect attributed to this run, re-compose the repair unit **once**. Compose it again from the
baseline plus the same accepted fixes, resolving the defect. Then read the result again.

A re-composed artifact that still fails escalates. It does not get a second repair attempt. There
is no loop here and there must not be one: a repair that needs three attempts is a signal that the
accepted fixes genuinely conflict, which is a decision for a human or a discard, not for more
composition.

**The repair may not resolve a defect by dropping accepted content.** The re-composed artifact
must still satisfy every accepted finding it was composed from. A repair that quietly removes one
fix to stop it contradicting another has not repaired anything — it has silently reversed a
decision. If the repair altered or removed any accepted fix, name that fix in the report, whether
or not the repair otherwise succeeded.

### Escalation on `unrepairable`

**When `USER_PRESENT` is true**, present the surviving defect to the user, quoting the composed
content that carries it, and offer exactly these:

- **Accept the composition** — write it as composed, defect included. This is an override: record
  it as one and state the accepted defect in the record.
- **Resolve a subset** — the user names which of the contributing fixes to keep. Compose that
  subset and check it once. This check does **not** consume a further repair attempt, and it is
  the last one: if the subset also fails, fall through to accept-or-discard for that artifact
  rather than prompting again.
- **Discard this artifact's fixes** — do not write the artifact; leave its contributing findings
  unresolved.

**When `USER_PRESENT` is false**, discard. Do not write the artifact, leave every contributing
finding unresolved with its checkbox unchecked, and report them as unresolved. There is nobody to
ask, and writing a known-contradictory artifact is worse than writing nothing.

### The gate condition a discard sets

A discard whose contributing findings include at least one of a **blocking tier** sets a condition
that is **run-scoped and sticky**: the gate for this run may not be recorded as passed, regardless
of any later finding recount.

A discard whose contributing findings are **all of an optional tier** does not set it. Nothing was
written, so nothing broken landed, and the gate does not rest on those fixes. Their findings are
still reported unresolved. Forcing a non-passing gate on them would contradict what the same run
stated when it opened that tier — that those findings do not block the gate.

This matters because a discarded fix leaves its finding unresolved, and a later validation round
may or may not resurface that finding. If it fails to resurface, a recount alone would show zero
blocking findings and the gate would pass over work that was thrown away. The sticky condition is
what prevents that. Once set, it stays set for the rest of the run, and any code that later assigns
a fresh finding count must not clear it.

An `unrepairable` or `accepted-as-override` outcome also invalidates a gate-passed state recorded
earlier in the same run.

## What the caller must do that this pass cannot

These are obligations on the calling command. This pass produces outcomes; it does not perform
writes.

- **No write before an outcome.** No artifact is written until it has an outcome, and no artifact
  a coordinated group spans is written until every artifact that group spans has one.
- **Recompose a passing artifact after a withdrawal.** Where a coordinated fix is discarded, every
  other artifact that group spans whose own check passed is recomposed without that fix and then
  written — its unrelated fixes still land.
- **A passing gate after every outcome settles — and one that actually happens.** The gate write
  moves to after the last outcome, but it must still occur. A path that resolves the last blocking
  finding and then reaches no gate write leaves the gate blocked over fully resolved work, which is
  as much a failure as passing it too early. Never announce a gate transition before performing it.
- **Bookkeeping writes come last.** Findings-file checkbox updates, audit-log appends, gate records
  and pipeline-state records are not checked by this pass — they carry no fix content — but they
  are emitted only after every composed artifact in the pass has an outcome. Emitting them earlier
  means a discard skips the artifact write while the checkbox already says the finding was
  resolved, leaving the findings file and the artifact disagreeing and the next round reading the
  finding as already fixed.
- **Do not re-validate over unchanged content, and do not stall on it either.** A pass that
  discarded every fix it composed for an artifact left that artifact unchanged. Re-running
  validation over it wastes a dispatch and returns the same findings. But a surrounding convergence
  loop must also not treat "no new count" as "the count did not go down" — that burns an iteration
  on nothing, and enough of them exhaust the loop's fixed iteration budget for zero benefit — every
  fix that already passed its own check is retained regardless of how the loop ends, so the only
  cost of continuing past a discard-only iteration is wasted dispatch time. Exit the loop instead.

## Report — evidence before verdict

Report in this order, and do not reorder it. A verdict whose supporting evidence is not visible
first is an unverifiable claim.

For each artifact, in this order:

1. the defects found in it — each quoted, classified, and marked as attributed to this run or
   pre-existing
2. then that artifact's outcome verdict, and for a repaired outcome, what the repair changed and
   any accepted fix it altered or removed

Then, after every artifact has been reported:

3. the run-level summary — how many artifacts were checked, how many were written, how many were
   discarded, and which findings were left unresolved

An unattended path additionally appends the same content to its durable resolution log, so the
record survives a session that nobody watched.

## If this file is missing

A calling command that cannot read this file must fail closed: do not write the composed artifact,
tell the user in plain language that the consistency check could not be run and name the file that
is absent, and do not record a passing gate. Proceeding without the check is precisely the
unchecked write this pass exists to prevent.

## Cross-artifact reach

The stale-counterpart detection class needs a counterpart to compare against. This section defines
where those counterparts come from, which of them are worth reading, and how a fix spanning
several artifacts is written.

### The declared candidate set

`CANDIDATE_SET` is **declared by the stage that dispatches this pass, not discovered by it**. The
caller binds it from this table:

| Dispatching stage | Declared candidate set |
|---|---|
| Review at the primary gate | `spec.md` |
| Review at the secondary gate | `spec.md`, `plan.md`, `research.md`, the files under `contracts/` |
| Verification, spec mode | `spec.md`, `plan.md`, `tasks.md`, the files under `contracts/` |
| Verification, constitution mode | the single constitution artifact |
| Fixes routed to source files | the files this run already wrote, plus the files cited in the evidence of the findings in `CONTRIBUTING` |

The source-file row is a **restricted set, and it is the whole set**. Do not widen it by searching
the repository for callers, importers, subclasses, or similarly-named files. A fix to a source
file reaches the files this run touched and the files its own finding pointed at — nothing else.
This is the same bound the read section above states, applied to the one row where the temptation
to go looking is strongest.

### The changed-rule filter narrows the set; it does not define it

Within the declared set, read the artifacts that state a rule a fix in this run changed.

That filter is a **narrowing of the declared set, never a replacement for it**. An artifact is a
candidate because the stage declared it; the filter only decides which declared candidates are
worth reading in full during this pass. An artifact that states no rule this run touched is passed
over for now — it is not removed from the set, and a later fix in the same run that changes a rule
it does state brings it back into play.

Reading this the other way round — treating the filter as the source of the set — silently
replaces a declared scope with a discovered one, which is how a bounded read becomes a search.

### When the reach is inert

- **The candidate set is empty** — there is nothing to compare against, so the stale-counterpart
  class does not fire.
- **The candidate set has exactly one member** — there is no counterpart, so the class does not
  fire. Verification in constitution mode is always this case.

Both are correct outcomes. Report the pass as having run with no counterpart in scope; do not
report a defect, and do not report the check as skipped.

### Attribution across artifacts

The attribution test above compares a composed artifact against its own baseline. A counterpart
artifact has no baseline in this pass, because this run wrote no fix into it — so that test on its
own would attribute every stale counterpart to "pre-existing", and the class would never fire at
all.

The changed-rule exception is what resolves this: a rule this run changed is a participating
statement **wherever it appears**, including in an artifact that received no fix. A counterpart
still stating the superseded form is attributed to this run, and is this run's defect to resolve.

### Writing a fix that spans several artifacts

No artifact a coordinated group spans is written until **every** artifact that group spans has
produced an outcome. Compose them all, check them all, then write.

A coordinated fix discarded in one artifact is discarded in every artifact it spans. Half a
coordinated fix on disk is exactly the contradiction this pass exists to prevent, written
deliberately rather than by accident.

An artifact whose own check passed and that the discarded group also spanned is still written:
recompose it without the withdrawn fix so its unrelated fixes land, and leave that group's findings
unresolved in every artifact it spanned. Only the artifact that failed its own check loses
everything.
