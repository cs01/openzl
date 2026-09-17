# Specification Quality Checklist: [FEATURE NAME]

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: [DATE]
**Feature**: [Link to spec.md]

**Compact spec mode**: If the spec's YAML frontmatter contains `complexity: compact`, validate only the items marked `[compact]` below. Skip all other items — they validate sections that compact specs legitimately omit.

## Content Quality

- [ ] No implementation details — scan each FR for: file paths, class/method names, JSON schemas, HTML comment markers or sentinel syntax (e.g., `<!-- ... -->`), format tokens, wire formats, concrete markup patterns. If an FR prescribes a specific mechanism rather than a capability, rewrite it. [compact]
- [ ] Focused on user value and business needs [compact]
- [ ] Suitable for AI implementation consumption [compact]
- [ ] All mandatory sections completed [compact]

## Requirement Completeness

- [ ] No [NEEDS CLARIFICATION] markers remain [compact]
- [ ] Requirements are testable and unambiguous [compact]
- [ ] Success criteria are measurable
- [ ] Success criteria are technology-agnostic (no implementation details)
- [ ] All acceptance scenarios are defined
- [ ] Edge cases are identified with sensible default behaviors defined [compact]
- [ ] Scope is clearly bounded [compact]
- [ ] Dependencies and assumptions identified [compact]
- [ ] Each functional requirement contains a single independent obligation — apply the single-obligation test: could one half pass verification while the other half fails? If yes, split into separate atomic FRs. [compact]

  **Recognition patterns** — compound FRs disguise themselves as single obligations via:
  - Comma-joined independent actions: "MUST apply fixes sequentially, reconcile conflicts, and handle mode-specific edge cases" — three operations where applying could pass while reconciling fails
  - Multi-action bundles: "MUST keep accepted fixes, report residual findings, and offer user a choice" — three user-facing actions, each independently testable
  - Bundled structural concerns: "MUST organize findings by severity tier, enforce field requirements per tier, and separate discovery from resolution" — three structural rules that could individually pass or fail

  **Key insight**: Thematic relatedness does not make obligations dependent. Two operations about the same workflow are compound if either could pass verification independently.

## Feature Readiness

- [ ] All functional requirements have clear acceptance criteria [compact]
- [ ] Design Decisions section records the chosen approach and rationale for each key decision [compact]
- [ ] User scenarios cover primary flows [compact]
- [ ] User stories are independent, testable journeys — each states its Problem, Why-this-priority, and Independent Test; edge cases and minor variations are folded into a parent story's acceptance scenarios rather than promoted to standalone stories
- [ ] Feature meets measurable outcomes defined in Success Criteria
- [ ] No implementation details leak into specification [compact]

## Notes

- Items marked incomplete require spec updates before `/speckit-clarify` or `/speckit-plan`
