#!/usr/bin/env bash
# Copyright (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.
#
# enrichment-merge.sh — Deterministic JSON merge/materialize helper for deep-research enrichment
#
# Consumption state (2026-08-01):
#   The structured fields this script writes to scan-profile.json (.architecture enrichment
#   keys, .dependencies, .configuration, .operational, .data_flow, .enrichment marker) are
#   NOT read by any downstream pipeline command. Only setup reads .enrichment for state
#   detection. The prose companion in project-context.md is consumed as advisory context
#   as advisory context. Structured field consumption is deferred pending a
#   staleness/freshness solution.
#
# Four entry points:
#   materialize  — enrichment.json.findings → scan-profile.json projection (consistency restoration)
#   persist      — synthesis findings → both files (enrichment + projection)
#   persist --preserve-failed — carry forward prior findings for gap dimensions
#   merge-roots  — merge freshly-detected cross_root_boundaries into scan-profile.json (re-scan preservation)

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
readonly COMMAND="${1:-}"

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME materialize <scan-profile.json> <enrichment.json>
    Re-materialize cached findings into scan-profile.json projection.
    Preserves scan-owned architecture keys (module_boundaries, system_boundary_confidence).
    Staleness check: if scan.generated > enrichment.generated, set enrichment.stale=true.

  $SCRIPT_NAME persist <scan-profile.json> <enrichment.json> <findings-json>
    Write synthesis findings to both artifacts (idempotent replace).
    <findings-json> is a temp file with the merged dimension findings.

  $SCRIPT_NAME persist --preserve-failed <scan-profile.json> <enrichment.json> <findings-json>
    Like 'persist', but carry forward prior enrichment.json.findings for dimensions
    with status "gap". Exception: dimensions with gap_reason "user_rejected"
    receive fresh gap entries (empty machine fields) instead of stale prior
    findings.

  $SCRIPT_NAME merge-roots <scan-profile.json> <new-discoveries.json>
    Merge freshly-detected cross_root_boundaries entries into scan-profile.json.
    Preserves confirmed:true entries across re-detection, flags previously-detected
    entries that are no longer found as stale:true (never removed), and adds new
    discoveries with confirmed:false. A missing or unparseable scan-profile.json
    is treated as a first scan (all entries newly discovered).

Exit codes:
  0 — success
  1 — malformed JSON input
  2 — usage error
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# Validate JSON file is parseable
validate_json() {
  local file="$1"
  if ! jq empty "$file" 2>/dev/null; then
    die "Malformed JSON in $file"
  fi
}

# materialize: enrichment.json.findings → scan-profile.json projection
materialize() {
  local scan_profile="$1"
  local enrichment_json="$2"

  [[ -f "$scan_profile" ]] || die "scan-profile.json not found: $scan_profile"
  [[ -f "$enrichment_json" ]] || die "enrichment.json not found: $enrichment_json"

  validate_json "$scan_profile"
  validate_json "$enrichment_json"

  # Staleness check: compare scan.generated vs enrichment.generated
  local scan_generated enrichment_generated stale_flag
  scan_generated=$(jq -r '.generated // ""' "$scan_profile")
  enrichment_generated=$(jq -r '.enrichment.generated // ""' "$enrichment_json")

  if [[ -n "$scan_generated" && -n "$enrichment_generated" ]]; then
    if [[ "$scan_generated" > "$enrichment_generated" ]]; then
      stale_flag="true"
    else
      stale_flag="false"
    fi
  else
    stale_flag="false"
  fi

  # Merge: preserve scan-owned architecture keys, replace enrichment-owned keys
  # Consumer: .enrichment marker read by setup (state detection only).
  # Remaining fields (.architecture enrichment keys, .dependencies, .configuration,
  # .operational, .data_flow) are not read by any downstream command.
  jq --arg stale "$stale_flag" '
    . as $scan |
    input as $enrich |
    $scan |
    # Preserve scan-owned keys, merge enrichment-owned keys
    .architecture = (
      ($scan.architecture // {}) +
      ($enrich.findings.architecture // {}) |
      # Restore scan-owned keys if they were present
      if $scan.architecture.module_boundaries then .module_boundaries = $scan.architecture.module_boundaries else . end |
      if $scan.architecture.system_boundary_confidence then .system_boundary_confidence = $scan.architecture.system_boundary_confidence else . end
    ) |
    .dependencies = ($enrich.findings.dependencies // {}) |
    .configuration = ($enrich.findings.configuration // {}) |
    .operational = ($enrich.findings.operational // {}) |
    .data_flow = ($enrich.findings.data_flow // {}) |
    .enrichment = (
      $enrich.enrichment |
      if ($stale == "true") then .stale = true else . end
    )
  ' "$scan_profile" "$enrichment_json" > "${scan_profile}.tmp"

  mv "${scan_profile}.tmp" "$scan_profile"
}

# persist: synthesis findings → both files (idempotent replace)
persist() {
  local preserve_failed=false
  if [[ "${1:-}" == "--preserve-failed" ]]; then
    preserve_failed=true
    shift
  fi

  local scan_profile="$1"
  local enrichment_json="$2"
  local findings_json="$3"

  [[ -f "$scan_profile" ]] || die "scan-profile.json not found: $scan_profile"
  [[ -f "$findings_json" ]] || die "findings JSON not found: $findings_json"

  validate_json "$scan_profile"
  validate_json "$findings_json"

  # If --preserve-failed and enrichment.json exists, carry forward prior findings for gap dimensions
  local prior_findings="{}"
  if [[ "$preserve_failed" == true && -f "$enrichment_json" ]]; then
    validate_json "$enrichment_json"
    prior_findings=$(jq -c '.findings // {}' "$enrichment_json")
  fi

  # Build enrichment.json marker + findings
  local enrichment_marker
  enrichment_marker=$(jq -n --argjson findings "$(cat "$findings_json")" \
    --argjson prior "$prior_findings" '
    $findings as $new |
    {
      enrichment: {
        enrichment_version: 1,
        generated: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
        dimensions: (
          $new |
          to_entries |
          map({key: .key, value: (.value.status // "complete")}) |
          from_entries
        ),
        gap_reasons: (
          $new |
          to_entries |
          map(select(.value.status == "gap" and .value.gap_reason != null)) |
          map({key: .key, value: .value.gap_reason}) |
          from_entries
        )
      },
      findings: (
        if ($prior | length) > 0 then
          # Carry forward prior findings for gap dimensions, except user_rejected
          # dimensions — those get fresh gap entries per spec AS-6.
          ($prior * $new) as $merged |
          $merged |
          to_entries |
          map(
            if ($new[.key].status == "gap" and ($new[.key].gap_reason // "") != "user_rejected") then
              {key: .key, value: $prior[.key]}
            else
              {key: .key, value: $new[.key].machine}
            end
          ) |
          from_entries
        else
          # No prior findings, use all new findings
          $new | map_values(.machine)
        end
      )
    }
  ')

  # Write scan-profile.json projection (idempotent replace)
  # Consumer: .enrichment marker read by setup (state detection only).
  # Remaining fields not read by any downstream command.
  local scan_arch_module_boundaries scan_arch_system_boundary
  scan_arch_module_boundaries=$(jq -c '.architecture.module_boundaries // null' "$scan_profile")
  scan_arch_system_boundary=$(jq -c '.architecture.system_boundary_confidence // null' "$scan_profile")

  jq --argjson findings "$(echo "$enrichment_marker" | jq -c '.findings')" \
    --argjson marker "$(echo "$enrichment_marker" | jq -c '.enrichment')" \
    --argjson scan_mod "$scan_arch_module_boundaries" \
    --argjson scan_sys "$scan_arch_system_boundary" '
    .architecture = (
      ($findings.architecture // {}) +
      (if $scan_mod then {module_boundaries: $scan_mod} else {} end) +
      (if $scan_sys then {system_boundary_confidence: $scan_sys} else {} end)
    ) |
    .dependencies = ($findings.dependencies // {}) |
    .configuration = ($findings.configuration // {}) |
    .operational = ($findings.operational // {}) |
    .data_flow = ($findings.data_flow // {}) |
    .enrichment = $marker
  ' "$scan_profile" > "${scan_profile}.tmp"

  mv "${scan_profile}.tmp" "$scan_profile"

  # Write enrichment.json LAST: the marker file is the completion signal, so
  # it must not exist until everything it vouches for is already on disk.
  echo "$enrichment_marker" > "$enrichment_json"
}

# merge_cross_root_boundaries: merge new discoveries into existing cross_root_boundaries
# Usage: enrichment-merge.sh merge-roots <scan-profile.json> <new-discoveries.json>
merge_cross_root_boundaries() {
  local scan_profile="$1"
  local new_discoveries="$2"

  [[ -f "$new_discoveries" ]] || die "new-discoveries.json not found: $new_discoveries"
  validate_json "$new_discoveries"

  # A missing or unparseable existing scan-profile.json is treated as a first
  # scan: all new discoveries become newly-discovered entries. This is the
  # explicit exception to confirmed-preservation and stale-flagging — there is
  # no readable prior state to preserve or flag against.
  local profile_readable=false
  local existing="[]"
  if [[ -f "$scan_profile" ]] && jq empty "$scan_profile" 2>/dev/null; then
    profile_readable=true
    existing=$(jq -c '.cross_root_boundaries // []' "$scan_profile")
  fi

  local merged
  merged=$(jq -c -n --argjson existing "$existing" --slurpfile new "$new_discoveries" '
    def rank: {"LOW": 0, "MEDIUM": 1, "HIGH": 2};
    def max_confidence(a; b): if (rank[a] // 0) >= (rank[b] // 0) then a else b end;

    ($new[0]) as $new_list |
    ($new_list | map({key: .path, value: .}) | from_entries) as $new_by_path |
    ($existing | map({key: .path, value: .}) | from_entries) as $existing_by_path |

    # Re-detected or now-missing existing entries
    ($existing | map(
      . as $e |
      ($new_by_path[$e.path]) as $fresh |
      if $fresh == null then
        # No longer detected: flag stale, never remove, preserve everything else
        $e + {stale: true}
      elif ($e.confirmed // false) == true then
        # Confirmed + re-detected: preserve user-set fields, refresh detection fields
        $e + {
          detection_methods: (($e.detection_methods + $fresh.detection_methods) | unique),
          confidence: max_confidence($e.confidence; $fresh.confidence),
          stale: false
        }
      else
        # Unconfirmed + re-detected: replace with fresh data
        $fresh + {confirmed: false, stale: false}
      end
    )) as $merged_existing |

    # Newly-discovered entries not previously seen
    ($new_list
      | map(select($existing_by_path[.path] == null))
      | map(. + {confirmed: false, stale: false})
    ) as $added |

    $merged_existing + $added
  ')

  if [[ "$profile_readable" == true ]]; then
    jq --argjson roots "$merged" '.cross_root_boundaries = $roots' "$scan_profile" > "${scan_profile}.tmp"
  else
    jq -n --argjson roots "$merged" '{cross_root_boundaries: $roots}' > "${scan_profile}.tmp"
  fi

  mv "${scan_profile}.tmp" "$scan_profile"
}

case "$COMMAND" in
  materialize)
    [[ $# -eq 3 ]] || { usage; exit 2; }
    materialize "$2" "$3"
    ;;
  persist)
    if [[ "${2:-}" == "--preserve-failed" ]]; then
      [[ $# -eq 5 ]] || { usage; exit 2; }
      persist --preserve-failed "$3" "$4" "$5"
    else
      [[ $# -eq 4 ]] || { usage; exit 2; }
      persist "$2" "$3" "$4"
    fi
    ;;
  merge-roots)
    [[ $# -eq 3 ]] || { usage; exit 2; }
    merge_cross_root_boundaries "$2" "$3"
    ;;
  help|--help|-h|"")
    usage
    exit 0
    ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    usage
    exit 2
    ;;
esac
