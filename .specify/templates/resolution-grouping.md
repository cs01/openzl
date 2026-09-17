---
description: Shared interaction-detection procedure that groups findings whose fixes must be resolved together
---

RESOLUTION GROUPING:

This file defines one named procedure — **Resolution grouping**. Every resolution path that
partitions accepted findings runs it before composing any edit, and every path runs the same one,
so the paths cannot drift apart on what counts as an interaction.

Use this name verbatim when announcing the procedure. Do not rename it per path.

## What this procedure exists to catch

Findings arrive as independent items and are resolved one at a time. Some of them are not
independent. Two findings can touch the same lines. One can change a rule that another restates
two sections away. One can change a rule that a different artifact states in its own words.

Resolved separately, each fix is correct and the result is not: the second fix reinstates what the
first removed, or the two write the same region and one silently wins. Grouping is the step that
notices this **before any edit is composed**, so interacting findings are resolved as one
coordinated fix rather than as a race.

## Inputs the caller binds before running

| Variable | Type | Meaning |
|---|---|---|
| `ACCEPTED` | list of accepted findings — each with tier, target artifact, evidence text, recommendation text | The findings to group |
| `CANDIDATE_SET` | ordered list of artifact paths | The counterpart artifacts this stage declares in scope |
| `TIER` | the severity tier currently being resolved | Grouping runs within one tier |

**Grouping runs before composition.** Groups are formed from the finding records, not from
composed content. A procedure that ran after composition would be reporting a collision that had
already happened — which is what the pre-write consistency check does, and why that check is not a
substitute for this one.

## Target inference

A finding that names its target artifact explicitly is taken at its word.

A finding that does not carries its target in prose, and the dispatching command already has a
step that infers a target from that prose. **Reuse that inference.** Introducing a second one
gives the run two answers to the same question, and nothing to decide between them when they
disagree.

An inference can be wrong. A finding grouped on a wrongly inferred target degrades to independent
composition — never to an unchecked write, because the pre-write consistency check reads the
composed result either way.

## The three signals

Evaluate each pair of accepted findings within `TIER` against these:

1. **Same region** — both findings target the same artifact *and* the same named place within it:
   the same section heading cited by both, quoted spans that overlap, or the same requirement or
   step identifier as the *subject* of both fixes.
2. **Same rule, same artifact** — one finding's fix changes a stated rule, and another finding in
   the same artifact quotes, restates, or depends on that rule somewhere else in it.
3. **Same rule, different artifact** — as signal 2, but the second finding targets a *different*
   artifact within `CANDIDATE_SET`.

Signal 1 needs position and cannot reach a rule restated three sections away. Signals 2 and 3 need
rule text and cannot reach several findings converging on one region without a shared rule. Both
kinds of match are required; neither alone covers the other's cases.

### A shared identifier is the seed, not the test

Two findings citing the same identifier — a requirement, a criterion, a step, a decision token —
is a cheap and precise way to **generate** candidate pairs for signals 2 and 3.

It is not the match. Read both findings and confirm the rule relationship before grouping them:
two findings can cite one identifier while touching obligations that have nothing to do with each
other, and grouping those forces a single coordinated decision over two unrelated fixes.

Signal 1 does not depend on identifiers at all and must not be reduced to them.

## Closing the groups

Matched pairs are closed **transitively**. If A matches B and B matches C, all three are one
group, whether or not A and C match each other directly. Several findings converging on one region
is a case this exists for, and it is a case where the pairwise matches do not all hold.

### Grouping never crosses a tier

Two findings in different severity tiers are never grouped, even when a signal matches between
them. Tiers are resolved in separate rounds with separate decisions, and a group spanning them
would force a decision about a lower-tier finding while a higher tier is still being worked.

Their interaction is not lost. It falls to the pre-write consistency check, which reads the
composed result regardless of which round produced each fix.

### A finding with no locatable position

A finding whose evidence identifies no section, no quoted span, and no identifier position is
excluded from **signal 1 only**. It stays eligible for signals 2 and 3, which match on rule text
rather than on position.

Excluding such a finding from grouping entirely would drop precisely the findings whose prose is
vaguest — and therefore the ones whose interactions a human reader is least likely to catch
unaided.

## Output

| Output | Shape |
|---|---|
| `GROUPS` | list of groups — members, tier, the signal that matched, the artifacts the group spans, and a repair budget of one |

A finding that matches nothing forms a group of one. Every accepted finding in the tier appears in
exactly one group.

## Group shapes that are valid outcomes

- **A group of one** is presented and composed exactly as an ungrouped finding is. It gets no
  combined action prompt, and the user sees no difference from the behaviour without grouping.
- **A group containing every accepted finding for an artifact** is valid, not a sign the matcher
  over-reached. A whole artifact resolved as one coordinated fix is an ordinary result when every
  finding against it concerns one rule.
- **No group of two or more anywhere in the run** is the common case, and it produces no combined
  action prompt anywhere in the run.

## What the caller must do

**Interactive callers:**

- Present every member of a group together under **one** combined action prompt.
- Show all members before recording any member's decision. A decision recorded on the first member
  while the rest are still unseen is the uncoordinated behaviour this procedure replaces.
- Permit accepting a subset of the group.
- Record an unaccepted member as skipped, rather than folding it into the coordinated fix.
- Record all of a group's decisions as one unit.
- Fire any decision-triggered gate evaluation once per group, not once per member.

**All callers:**

- Compose one coordinated fix per group, satisfying every accepted member of that group together.
- Compose ungrouped findings independently.
- Apply a coordinated fix to every artifact it spans, or to none of them.

## If this file is missing

A calling command that cannot read this file must fail closed: do not compose, do not write, tell
the user in plain language that the interaction check could not be run and name the file that is
absent, and do not record a passing gate.

Degrading silently to ungrouped resolution would be the more tempting choice, because the
pre-write consistency check would still read every composed artifact. It is the wrong one: the
user would be resolving interacting findings one at a time with no indication that anything was
missing, and would see the interaction only as a defect report after the fact — which is the
behaviour this procedure exists to replace, restored silently and without consent.
