#!/usr/bin/env bash
# Run OpenZL's ESBMC harnesses with stock ESBMC and print one verdict per harness.
#
#   ./proofs/esbmc/run.sh                  # every *_harness.c in this directory
#   ./proofs/esbmc/run.sh <name> [<name>]  # just the named harness(es)
#
# Each harness #includes the unmodified production sources and models its
# input as nondeterministic. ESBMC explores every input within the unwind bound.
#
# Each harness is one solver query, not --multi-property: a proof needs every
# claim to hold anyway, and a disproof needs only the first violation, while
# per-claim solving costs minutes on 64-bit symbolic sizes.
#
# .esbmc in this directory is sourced and may set:
#   ESBMC_UNWIND=N                         default loop unwind bound
#   ESBMC_CHECKS=(flag ...)                checks for every harness
#   ESBMC_HARNESS_CHECKS[name]="flag ..."  replaces ESBMC_CHECKS for one harness
#   ESBMC_HARNESS_UNWIND[name]=N           replaces ESBMC_UNWIND for one harness
#   ESBMC_EXPECT[name]=VERDICT             recorded verdict (default PROVEN)
#
# Verdicts:
#   PROVEN          every property holds for every input within the bound
#   COUNTEREXAMPLE  ESBMC found a concrete input that violates a property
#   INCONCLUSIVE    a loop needed more than the unwind bound; nothing is proven
#   ERROR           ESBMC could not parse or run the harness
#
# A COUNTEREXAMPLE can be the recorded verdict: such a harness exists to
# demonstrate a violation, and the runner fails only when a harness stops
# behaving as recorded. Environment overrides: UNWIND, ESBMC_OUT, ESBMC.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../.." && pwd)"

ESBMC_UNWIND=13
ESBMC_CHECKS=(--overflow-check --ub-shift-check)
declare -A ESBMC_HARNESS_CHECKS=()
declare -A ESBMC_HARNESS_UNWIND=()
declare -A ESBMC_EXPECT=()
if [[ -f "${HERE}/.esbmc" ]]; then
  # shellcheck source=/dev/null
  source "${HERE}/.esbmc"
fi
OUT="${ESBMC_OUT:-/tmp/esbmc/openzl}"
ESBMC="${ESBMC:-esbmc}"
if ! command -v "${ESBMC}" >/dev/null 2>&1; then
  echo "SKIP: esbmc not found (https://github.com/esbmc/esbmc/releases), or set ESBMC" >&2
  exit 0
fi
mkdir -p "${OUT}"

includes=(-I "${HERE}" -I "${ROOT}/include" -I "${ROOT}/src")

if [[ $# -gt 0 ]]; then
  harnesses=()
  for name in "$@"; do
    f="${HERE}/${name%.c}.c"
    [[ -f "${f}" ]] || { echo "no such harness: ${f}" >&2; exit 2; }
    harnesses+=("${f}")
  done
else
  shopt -s nullglob
  harnesses=("${HERE}"/*_harness.c)
  shopt -u nullglob
fi

echo "$("${ESBMC}" --version)  logs=${OUT}"
matched=0
mismatched=0
for harness in "${harnesses[@]}"; do
  name="$(basename "${harness}" .c)"
  log="${OUT}/${name}.txt"
  checks=("${ESBMC_CHECKS[@]}")
  if [[ -n "${ESBMC_HARNESS_CHECKS[${name}]+set}" ]]; then
    read -r -a checks <<<"${ESBMC_HARNESS_CHECKS[${name}]}"
  fi
  unwind="${UNWIND:-${ESBMC_HARNESS_UNWIND[${name}]:-${ESBMC_UNWIND}}}"
  expect="${ESBMC_EXPECT[${name}]:-PROVEN}"
  start=${SECONDS}
  "${ESBMC}" --std c11 "${checks[@]}" --unwind "${unwind}" \
    "${includes[@]}" "${harness}" >"${log}" 2>&1
  rc=$?
  elapsed=$((SECONDS - start))
  counts="$(grep -oE '[0-9]+ of [0-9]+ properties failed' "${log}" | tail -1)"
  violated="$(grep -A3 '^Violated property:' "${log}" | sed -n '2,3p' | sed 's/^ *//' | paste -sd' ')"
  if [[ "${violated}" == *"unwinding assertion"* ]]; then
    verdict="INCONCLUSIVE"
  elif [[ ${rc} -eq 0 ]] && grep -q 'VERIFICATION SUCCESSFUL' "${log}"; then
    verdict="PROVEN"
  elif [[ ${rc} -ne 0 ]] && grep -q 'VERIFICATION FAILED' "${log}"; then
    verdict="COUNTEREXAMPLE"
  else
    verdict="ERROR"
  fi
  note=""
  if [[ "${verdict}" == "${expect}" ]]; then
    matched=$((matched + 1))
  else
    mismatched=$((mismatched + 1))
    note="  <-- RECORDED ${expect}"
  fi
  printf '%-15s %-44s %-30s %5ss  unwind=%s%s\n' \
    "${verdict}" "${name}" "${counts}" "${elapsed}" "${unwind}" "${note}"
  if [[ -n "${violated}" ]]; then
    printf '    %s\n' "${violated}"
  fi
done
echo "${matched} behaved as recorded, ${mismatched} did not"
exit "${mismatched}"
