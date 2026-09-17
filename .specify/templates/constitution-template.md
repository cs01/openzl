<!-- speckit:constitution:placeholder -->
# [PROJECT_NAME] Constitution
<!-- Example: Spec Constitution, TaskFlow Constitution, etc. -->

## Core Principles

<!-- GUIDANCE — Governance vs Design Decisions

Litmus test for every candidate principle:
  "Would violating this invalidate ANY feature we might spec, or just ONE PARTICULAR design?"

If the answer is "just one design," confirm whether it's a deliberately elevated governance decision. If not, demote it to a spec or plan — not the constitution.

Good examples (governance-level):
  - "Game logic independent of rendering" — any renderer should work
  - "Every milestone must produce a runnable artifact" — applies to every feature
  - "Core logic testable without runtime environment" — universal testing constraint

Bad examples (design decisions disguised as governance):
  - "Use Canvas for rendering" — locks one design choice
  - "Use requestAnimationFrame" — implementation detail
  - "Vanilla JS only" — technology selection, not governance
  - "DAS/ARR must match guidelines" — product-specific constraint

Fewer strong principles > many prescriptive ones.
Add or remove sections as needed — the template count is a starting point, not a target. -->

### [PRINCIPLE_1_NAME]
<!-- Example: I. Separation of Concerns -->
[PRINCIPLE_1_DESCRIPTION]
<!-- Example: Each module owns one responsibility; cross-cutting concerns are isolated into shared infrastructure; no feature should depend on the implementation details of another feature -->

### [PRINCIPLE_2_NAME]
<!-- Example: II. Playable Increments -->
[PRINCIPLE_2_DESCRIPTION]
<!-- Example: Every milestone must produce a runnable artifact that can be demoed or tested; no multi-sprint work without intermediate checkpoints; scope cuts preferred over deadline slips -->

### [PRINCIPLE_3_NAME]
<!-- Example: III. Testable Core -->
[PRINCIPLE_3_DESCRIPTION]
<!-- Example: Core logic must be testable without runtime environment, UI framework, or external services; test boundaries defined at module interfaces; mocking allowed only at system boundaries -->

## Conventions

<!-- Recommended patterns and coding standards. Use normative SHOULD phrasing. -->

[CONVENTION_1]
<!-- Example: SHOULD use snake_case for all function and variable names -->

[CONVENTION_2]
<!-- Example: SHOULD prefer composition over inheritance for shared behavior -->

## Anti-Patterns

<!-- Behaviors that MUST NOT occur in this project. Use normative MUST NOT or SHOULD NOT phrasing. -->

[ANTI_PATTERN_1]
<!-- Example: MUST NOT use global mutable state for feature configuration — use dependency injection or explicit parameter passing -->

[ANTI_PATTERN_2]
<!-- Example: MUST NOT bypass the authentication layer — all entry points must verify credentials before processing requests -->

## Governance Checkpoints

<!-- Actions requiring explicit human approval or cross-team review. Use normative MUST phrasing. -->

[GOVERNANCE_CHECKPOINT_1]
<!-- Example: Schema changes MUST have human approval before landing — automated migrations are prohibited -->

[GOVERNANCE_CHECKPOINT_2]
<!-- Example: Production deployments MUST pass the security scan — no override flag without VP approval -->

## Governance
<!-- Example: Constitution supersedes all other practices; Amendments require documentation, approval, migration plan -->

[GOVERNANCE_RULES]
<!-- Example: All PRs/reviews must verify compliance; Complexity must be justified; Use [GUIDANCE_FILE] for runtime development guidance -->

**Version**: [CONSTITUTION_VERSION] | **Ratified**: [RATIFICATION_DATE] | **Last Amended**: [LAST_AMENDED_DATE]
<!-- Example: Version: 2.1.1 | Ratified: 2025-06-13 | Last Amended: 2025-07-16 -->
