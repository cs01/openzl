---
description: Shared triage classifier criteria consumed by review synthesis triage steps
---

Classify each reconciled finding into exactly one tentative disposition — `AUTO_APPLY`, `DISCARD`, or `PRESENTED` — by applying the checks below in order.

**Severity guard**: MUST-ADDRESS findings are never auto-applied or discarded — they always end up `PRESENTED`. Only SHOULD-CONSIDER and MINOR findings are eligible for auto-apply or discard.

**Constitution guard**: if the finding carries a Violated Principle, disposition is `PRESENTED` — a constitution-citing finding always gets human attention, whether or not it would otherwise qualify for auto-apply or discard. A finding citing a constitution principle must never be discarded; this guard runs before discard criteria are ever checked, so it always wins.

**Behavioral-claim verification guard**: if a finding asserts a claim about consumer impact, behavioral safety, or blast radius, and every originating prefix in its Agent field belongs to a reviewer role without codebase search capability (currently, the Risk Reviewer — RK prefix), discard criterion (c) does not apply to this finding. Citing the artifact's own design decision as evidence against a finding that challenges whether the decision accounts for all consumers is circular — only a codebase search can confirm. Disposition is `PRESENTED` when the finding would otherwise be discarded solely under criterion (c); criteria (a), (b), and (d) still apply normally.

**Auto-apply-first evaluation ordering**: auto-apply criteria are checked first, for every eligible finding. Discard criteria are checked only for a finding that did not qualify for auto-apply. A finding that passes every auto-apply criterion is auto-applied without ever being checked against discard criteria.

**Auto-apply criteria** — a finding tentatively becomes `AUTO_APPLY` only when ALL of the following hold:
a. the recommendation names a concrete edit (specific text, section, or action — not a vague direction)
b. the edit targets a single location in the artifact
c. the recommendation does not contradict any other auto-apply candidate's recommendation
d. the finding carries no Violated Principle (also enforced by the constitution guard above — check it here anyway)
e. the edit is additive or corrective — fixing, adding, or clarifying — not a restructuring of existing content
f. the finding is not MUST-ADDRESS severity (also enforced by the severity guard above — check it here anyway)
g. the recommendation addresses the complete defect, not a subset — a recommendation that fixes one named symptom of a broader gap must be routed to `PRESENTED` instead

**Discard criteria** — a finding becomes `DISCARD` when ANY of the following hold (checked only if it didn't qualify for auto-apply):
a. it is SHOULD-CONSIDER or MINOR tier and describes pre-existing debt explicitly
b. it is SHOULD-CONSIDER or MINOR tier and its recommendation says no artifact change is needed, or that it should be filed as a follow-up
c. it is SHOULD-CONSIDER or MINOR tier and its evidence or recommendation shows the artifact already made this an intentional design decision
d. it is MINOR severity and its recommendation is vague — no locatable edit target, or a location without a specific action

**Conservative bias**: when it is unclear whether a finding is mechanical (auto-apply) or judgmental, disposition is `PRESENTED`. When it is unclear whether a finding meets a discard criterion, disposition is `PRESENTED`. When the classifier itself errors out on a specific finding, disposition is `PRESENTED` and record the error as a `**Triage Advisories**:` line in the Summary section.

**Plan review relaxation** (applies only when the review target is `plan.md` and its siblings, not `spec.md`):
- Criterion (b) — single location: relaxed. A finding that adds content to multiple plan artifacts (e.g., a transition row to data-model.md AND a test case to Step 11) is auto-applicable if every individual edit is additive and concrete.
- Criterion (g) — complete defect: relaxed when the finding is part of a theme group and the group's other members are also auto-apply candidates. Apply the group as a unit.

Plan artifacts are drafts, not landed code — additive multi-location edits carry low risk. These relaxations do not apply to spec review, where the artifact is normative.

**Auto-applied fix classification** (confirmation-path use only — consumed by the dispatching command's All-Auto-Applied Confirmation step, not part of the `AUTO_APPLY`/`DISCARD`/`PRESENTED` disposition above): once a finding is confirmed as part of the final `AUTO_APPLY` set, classify it as `Semantic` or `Additive`:
- **Semantic**: the edit changes a requirement, a constraint, a schema, a method signature, or a design decision's verdict — anything that changes what the artifact commits to.
- **Additive**: the edit adds a note, a Verification Note, an edge case, or documentation — clarifying or extending the artifact without changing an existing commitment.

When it is unclear which applies, classify as `Semantic` — the conservative default that keeps a human in the loop, consistent with this fragment's conservative-bias rule above.

Anything that doesn't match `AUTO_APPLY` or `DISCARD` is `PRESENTED`.

**Missing-file fail-closed contract**: if this file cannot be read, skip triage entirely, route every finding to `PRESENTED`, and note the unavailability in Triage Advisories.

**Structural validation**: before applying any of the criteria above, verify this file contains all eight required structural elements — the severity guard, the constitution guard, the behavioral-claim verification guard, the seven auto-apply criteria, the four discard criteria, the conservative bias rule, the auto-apply-first evaluation ordering, and the missing-file fail-closed contract. If any element is absent, skip triage, route every finding to `PRESENTED`, and note the malformation in Triage Advisories.
