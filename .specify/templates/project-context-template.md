# Project Context

<!-- Populated by /speckit-setup from scan-profile.json -->

## Overview

**Project**: [Derived from root_path]
**Generated**: [Current date in YYYY-MM-DD format]
**Primary Language**: [Plurality language from the scan-profile `languages` array — highest `files` count, alphabetical tie-break. If `languages` is empty or absent, leave this field genuinely empty: no value after the colon, no bracket placeholder.]
**Frameworks**: [Comma-separated frameworks list]

## Stack-Specific Guidance

[CONDITIONAL: Include sections below ONLY if corresponding framework appears in scan-profile.json frameworks array]

### Ent

Spec guidance:
- EntSchema changes (new fields, edge definitions, indexes)
- Privacy policies (who can read/write, viewer context constraints)
- `PackageOverrideInclusions` (required when adding new Ent fields)
- Migration considerations (backward compatibility, lazy migration vs. backfill)

Task checklist items:
- Verify `PackageOverrideInclusions` for new Ent fields
- Review EntSchema migration strategy (lazy migration vs. backfill)
- Verify privacy policies on new/modified EntSchemas

### Thrift

Spec guidance:
- Endpoint definitions (request/response types, error codes)
- Backward compatibility (field numbering, deprecation strategy)
- Client regeneration requirements
- Service versioning considerations

Task checklist items:
- Verify Thrift struct backward compatibility (field numbering)
- Regenerate Thrift service clients after schema changes

### GraphQL

Spec guidance:
- Query/mutation definitions
- Schema evolution (nullable fields, deprecation directives)
- Relay connection patterns (if applicable)

## Project-Specific Notes

<!-- Add custom guidance here: coding conventions, test patterns, team preferences -->

## Operational Gotchas

<!-- Tooling and infrastructure pitfalls routed here by /speckit-constitution. Each entry describes a footgun, its trigger conditions, and a workaround if known. -->
