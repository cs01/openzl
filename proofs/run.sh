#!/bin/sh
# Prove annotated OpenZL codec kernels with CBMC. Needs CBMC 6+.
#
#   ./proofs/run.sh
#
# PROVE defaults to ./prove.sh at the top of this tree, falling back to a
# c-contracts checkout sitting beside it. Override to point at another copy.
#
# Each case records the verdict it is expected to produce, and the runner
# fails only on a mismatch. FAIL is the recorded verdict for a case that
# exposes a real defect: the case exists to demonstrate the violation, so a
# PASS there would mean the demonstration stopped working.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
if [ -z "${PROVE:-}" ]; then
  if [ -x "$ROOT/prove.sh" ]; then PROVE=$ROOT/prove.sh
  else PROVE=$(dirname "$ROOT")/c-contracts/prove.sh
  fi
fi
BUDGET=${BUDGET:-180}
FAILED=0
SKIPPED=0
MATCHED=0

CFLAGS="-DNDEBUG -U__ARM_NEON -I $ROOT/include -I $ROOT/src"

report() {
  NAME=$1; EXPECT=$2; ACTUAL=$3; DETAIL=$4
  if [ "$ACTUAL" = "SKIP" ]; then
    printf '  %-38s %-6s %s\n' "$NAME" SKIP "$DETAIL"
    SKIPPED=$((SKIPPED + 1))
  elif [ "$EXPECT" = "$ACTUAL" ]; then
    printf '  %-38s %-6s %s\n' "$NAME" "$ACTUAL" "$DETAIL"
    MATCHED=$((MATCHED + 1))
  else
    printf '  %-38s %-6s %s  <-- RECORDED %s\n' "$NAME" "$ACTUAL" "$DETAIL" "$EXPECT"
    FAILED=$((FAILED + 1))
  fi
}

run_proof() {
  NAME=$1; EXPECT=$2; shift 2
  if ! command -v cbmc >/dev/null 2>&1; then
    report "$NAME" "$EXPECT" SKIP "no cbmc"; return
  fi
  if [ ! -x "$PROVE" ]; then
    report "$NAME" "$EXPECT" SKIP "no prove.sh at \$PROVE"; return
  fi
  T0=$(date +%s)
  # shellcheck disable=SC2086
  OUT=$(TIMEOUT=$BUDGET "$PROVE" "$@" 2>&1) || true
  E=$(( $(date +%s) - T0 ))
  if printf '%s' "$OUT" | grep -q "VERIFICATION SUCCESSFUL"; then
    report "$NAME" "$EXPECT" PASS "${E}s"
  elif printf '%s' "$OUT" | grep -q "VERIFICATION FAILED"; then
    D=$(printf '%s' "$OUT" | grep -m1 "FAILURE" | sed 's/^\[[^]]*\] //' | cut -c1-48)
    report "$NAME" "$EXPECT" FAIL "${E}s  $D"
  else
    D=$(printf '%s' "$OUT" | grep -m1 "error:\|no solver\|cannot" | cut -c1-48)
    report "$NAME" "$EXPECT" ERROR "${E}s  ${D:-no verdict}"
  fi
}

if ! grep -qs "c_contracts.h" "$ROOT/src/openzl/codecs/zigzag/decode_zigzag_kernel.h"; then
  echo "SKIP: this checkout does not carry the contract annotations"
  exit 0
fi

echo "== OpenZL codec kernel proofs =="
echo

# Enforce mode: no harness exists, and none should. The contract generates the
# entry point, so the proof covers every input satisfying it rather than one
# geometry someone chose -- and the same clauses are what stock clang checks at
# each real call site. OpenZL kernels are the sweet spot for this: they take
# (dst, src, nbElts, eltWidth), allocate nothing, and their pointers never
# alias, so contract_fresh can build every argument.
echo "--- enforce mode: contract is the entry point ---"

# shellcheck disable=SC2086
run_proof "ZL_zigzagDecode64" PASS \
  ZL_zigzagDecode64 "$ROOT/src/openzl/codecs/zigzag/decode_zigzag_kernel.c" $CFLAGS

# shellcheck disable=SC2086
run_proof "ZL_zigzagDecode32" PASS \
  ZL_zigzagDecode32 "$ROOT/src/openzl/codecs/zigzag/decode_zigzag_kernel.c" $CFLAGS

# shellcheck disable=SC2086
run_proof "ZS_deltaDecode64_scalar" PASS \
  ZS_deltaDecode64_scalar "$ROOT/src/openzl/codecs/delta/decode_delta_kernel.c" $CFLAGS

echo
# Prove the leaf, then let the caller trust its contract instead of inlining
# its body. Needed here for a second reason beyond proof size: --enforce-contract
# refuses a function that still contains a loop after inlining, and
# --apply-loop-contracts leaves behind a synthetic bool the enforce pass then
# cannot size. Replacing the loop-bearing callee keeps both out of the caller.
echo "--- modular: leaf replaced by its contract ---"

# shellcheck disable=SC2086
run_proof "ZS_deltaDecode64" PASS \
  ZS_deltaDecode64 "$ROOT/src/openzl/codecs/delta/decode_delta_kernel.c" \
  -r ZS_deltaDecode64_scalar $CFLAGS

echo
echo "--- summary ---"
echo "$MATCHED behaved as recorded, $FAILED did not, $SKIPPED skipped"
[ "$SKIPPED" -gt 0 ] && echo "(skipped = missing prerequisite, not a result)"
exit "$FAILED"
