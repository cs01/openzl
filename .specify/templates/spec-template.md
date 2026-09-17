---
type: <feature|bugfix|refactor|infrastructure|documentation>
risk: <low|medium|high>
complexity: <compact|standard>
owner: <inferred from CLAUDE.md or "TBD">
created: <YYYY-MM-DD>
---

# Feature Specification: [FEATURE NAME]

**Feature Branch**: `[###-feature-name]`

## Summary

<!--
  Plain-language orientation context — the feature's purpose, scope, and key constraints.
  Open with 2-3 sentences of narrative, then match the structure to the content:
  three or more discrete items (separate stories, distinct mechanisms, scope boundaries)
  become a bulleted list with bold lead-ins; a sequence whose order matters becomes a
  numbered list; a single continuous argument stays prose. Cap at roughly 200 words.
-->

## User Scenarios & Testing *(mandatory)*

<!--
  IMPORTANT: User stories should be PRIORITIZED as user journeys ordered by importance.
  Each user story/journey must be INDEPENDENTLY TESTABLE - meaning if you implement just ONE of them,
  you should still have a viable MVP (Minimum Viable Product) that delivers value.

  Assign priorities (P1, P2, P3, etc.) to each story, where P1 is the most critical.
  Think of each story as a standalone slice of functionality that can be:
  - Developed independently
  - Tested independently
  - Deployed independently
  - Demonstrated to users independently
-->

### User Story 1 - [Brief Title] (Priority: P1)

**Problem:** [Describe the problem, friction, or gap this user story addresses]

**Why this priority**: [Explain the value and why it has this priority level]

**Independent Test**: [Describe how this can be tested independently - e.g., "Can be fully tested by [specific action] and delivers [specific value]"]

**Acceptance Scenarios**:

1. **Given** [initial state], **When** [action], **Then** [expected outcome]
2. **Given** [initial state], **When** [action], **Then** [expected outcome]

---

### User Story 2 - [Brief Title] (Priority: P2)

**Problem:** [Describe the problem, friction, or gap this user story addresses]

**Why this priority**: [Explain the value and why it has this priority level]

**Independent Test**: [Describe how this can be tested independently]

**Acceptance Scenarios**:

1. **Given** [initial state], **When** [action], **Then** [expected outcome]

---

### User Story 3 - [Brief Title] (Priority: P3)

**Problem:** [Describe the problem, friction, or gap this user story addresses]

**Why this priority**: [Explain the value and why it has this priority level]

**Independent Test**: [Describe how this can be tested independently]

**Acceptance Scenarios**:

1. **Given** [initial state], **When** [action], **Then** [expected outcome]

---

[Add more user stories as needed, each with an assigned priority]

### Edge Cases

<!--
  ACTION REQUIRED: Replace these placeholders with concrete edge cases.
  For each edge case, decide a sensible default behavior — do not leave
  them as open questions.
-->

- What happens when [boundary condition]?
- How does system handle [error scenario]?

## Requirements *(mandatory)*

<!--
  ACTION REQUIRED: The content in this section represents placeholders.
  Fill them out with the right functional requirements.
-->

### Functional Requirements

<!--
  Each FR must contain exactly one independent obligation. Apply the single-obligation test:
  could one half of this requirement pass verification while the other half fails?
  If yes, split it into separate atomic FRs.
-->

- **FR-001**: System MUST [specific capability, e.g., "allow users to create accounts"]
- **FR-002**: System MUST [specific capability, e.g., "validate email addresses"]
- **FR-003**: Users MUST be able to [key interaction, e.g., "reset their password"]
- **FR-004**: System MUST [data requirement, e.g., "persist user preferences"]
- **FR-005**: System MUST [behavior, e.g., "log all security events"]

*Example of marking unclear requirements:*

- **FR-006**: System MUST authenticate users via [NEEDS CLARIFICATION: auth method not specified - email/password, SSO, OAuth?]
- **FR-007**: System MUST retain user data for [NEEDS CLARIFICATION: retention period not specified]

### Key Entities *(include if feature involves data)*

- **[Entity 1]**: [What it represents, key attributes without implementation]
- **[Entity 2]**: [What it represents, relationships to other entities]

## Verification Notes *(compact specs only — one line per FR replacing full acceptance scenarios)*

<!--
  CONDITIONAL: Present only when complexity: compact. Compact specs replace
  per-story Acceptance Scenarios with a single verification line per FR here.
  Omit this section entirely for complexity: standard specs.
-->

## Success Criteria *(omit only when complexity: compact and every FR is directly testable by assertion; see spec's Functional Requirements)*

<!--
  ACTION REQUIRED: Define measurable success criteria.
  These must be technology-agnostic and measurable.
-->

### Measurable Outcomes

- **SC-001**: [Measurable metric, e.g., "Users can complete account creation in under 2 minutes"]
- **SC-002**: [Measurable metric, e.g., "System handles 1000 concurrent users without degradation"]
- **SC-003**: [User satisfaction metric, e.g., "90% of users successfully complete primary task on first attempt"]
- **SC-004**: [Business metric, e.g., "Reduce support tickets related to [X] by 50%"]

## Assumptions

<!--
  ACTION REQUIRED: The content in this section represents placeholders.
  Fill them out with the right assumptions based on reasonable defaults
  chosen when the feature description did not specify certain details.
-->

- [Assumption about target users, e.g., "Users have stable internet connectivity"]
- [Assumption about scope boundaries, e.g., "Mobile support is out of scope for v1"]
- [Assumption about data/environment, e.g., "Existing authentication system will be reused"]
- [Dependency on existing system/service, e.g., "Requires access to the existing user profile API"]

## Design Decisions

<!--
  MANDATORY: Record the chosen approach and 1-line rationale per decision.
  Full analysis (alternatives, tradeoffs, rejected approaches) goes in exploration.md.
-->

*Full analysis: [exploration.md](exploration.md)*

- **[Decision topic]**: [chosen approach] — [1-line rationale]

## Premise Validation *(mandatory)*

<!--
  MANDATORY: 2-line verdict. Full analysis (existing solutions, friction evidence,
  disproportionality assessment) goes in exploration.md.
-->

**Verdict:** proceed|reduce scope|cancel — [1-line friction summary]

*Full analysis: [exploration.md](exploration.md)*

## Testing Strategy

<!--
  CONDITIONAL: Present unless feature is documentation-only.
  Omit this section when the feature requires no code changes.
-->

**Test Tiers**: [unit | integration | both | defer to planning]
**Rationale**: [why this test tier is appropriate for this feature]

## Input Data

<!--
  OPTIONAL: Include only when the feature description or project context
  references relevant artifacts. Omit when no references exist.
-->

| Reference | What It Provides |
|-----------|-----------------|
| [file path] | [brief description] |
