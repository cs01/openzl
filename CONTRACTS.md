# Contracts on OpenZL codecs

Preconditions, postconditions and frame conditions written on the codec
kernels, checked three ways from one annotation: CBMC proves them over all
inputs, stock clang warns at call sites it can fold, every other compiler sees
nothing. The header is [`src/openzl/shared/c_contracts.h`](src/openzl/shared/c_contracts.h),
vendored from [c-contracts](https://github.com/cs01/c-contracts).

## Scope

| Measure | Count | Why it matters |
|---|---|---|
| `src/` C++ files | 0 | CBMC is a C tool. The `cpp/` and `py/` trees are out of reach and out of scope |
| decode kernel `.c` | 31 (6672 LOC) | The attack surface: where attacker-chosen bytes become indices and lengths |
| decode binding `.c` | 34 | Opaque handles, allocation, error plumbing. **None annotated** — needs stubs |
| kernels taking `ZL_Decoder` / `ZL_Input` / `ZL_Output` | **0** | Why no harness is needed. Kernels are `(dst, src, nbElts, eltWidth)` leaves over caller-owned, non-aliasing buffers, so `contract_fresh` can build every argument and the contract generates the entry point |
| kernels that allocate | 6 | The rest have nothing to model |
| decode kernels that compile under `goto-cc` unmodified | every one probed | zigzag, delta, transpose, bitpack, flatpack, prefix, lz, range_pack, rolz, entropy — AVX2/SSSE3/NEON paths included. No `-DZL_NO_INTRINSICS` equivalent was needed, unlike zstd |

## Requirements

| Tool | Required? | Why | Verified with |
|---|---|---|---|
| `cbmc` 6+ | yes | Runs the proofs. CBMC 5.x lacks the contracts support used here; Ubuntu 24.04 ships 5.95, which will not work | `cbmc --version` (6.11.0) |
| `goto-cc` 6+ | yes | Compiles the preprocessed source to a goto binary. Ships with CBMC | `goto-cc --version` |
| `goto-instrument` 6+ | yes | Applies loop contracts, drops unreachable functions, enforces or replaces contracts. Ships with CBMC | `goto-instrument --version` |
| `/usr/bin/cc` | yes | Preprocesses the contract macros to CBMC syntax. Hardcoded path in `prove.sh` | `/usr/bin/cc --version` (gcc 11.5.0) |
| POSIX `sh` | yes | `prove.sh` and `proofs/run.sh` | — |
| `prove.sh` | yes | At the repo root, or a `c-contracts` checkout beside this one, or set `PROVE=` | `./prove.sh` |
| `clang-format` | no | 19.1.2 here. Annotated regions are fenced with `// clang-format off`; see Gotchas | `clang-format --version` |
| `z3` | no | One of the raced solvers. Without any of these CBMC still uses its built-in SAT backend | `z3 --version` (4.8.15) |
| `bitwuzla`, `cvc5` | no | Also raced if present. More installed solvers means the race has more to pick from | — |

## Running

| What | How |
|---|---|
| Set flags | `CF="-DNDEBUG -I include -I src"` |
| `-DNDEBUG` | Matches the release build. Drives `ZL_DBG_LVL` to 2, which makes `ZL_ENABLE_ASSERT` 0, which expands every `ZL_ASSERT(P)` to a statically dead `(0 && (P))` expression: `P` is never evaluated and nothing aborts. Asserts in the body are **not** checked by any proof here — and do nothing in production either. See the first finding below |
| Run all proofs | `./proofs/run.sh` |
| Run one proof | See the Command column in the tables below |
| SIMD | `goto-instrument` warns `no body for function __builtin_ia32_*` and carries on. A proof that actually enters a SIMD path would need those modelled; annotate the scalar leaf and reach the dispatcher with `-r` instead |

## Legend

| Term | Means |
|---|---|
| mode `enforce` | `--enforce-contract`. CBMC generates the entry point from the contract itself. Preconditions assumed, **postconditions checked**, body verified for every input satisfying the contract. No harness file exists |
| mode `enforce -r` | `-r FN`. As above, with a callee replaced by its own contract: preconditions **asserted** at the call site, assigns targets set nondeterministic, postconditions assumed. Keeps each proof small, and keeps loop-bearing callees out of the caller |
| mode `harness` | `-H`. Hand-written entry point. Needed only where pointers alias into one object, which `contract_fresh` cannot construct. **No OpenZL proof needs one yet**; 3 of 4 zstd proofs did |
| enforce beats harness | A harness is a choice of geometry — the proof covers the sizes and offsets someone picked. Enforce mode has no such choice: CBMC havocs everything the contract permits |
| `contract_post` needs `contract_assigns` | Without it a caller assumes no write, silently deleting branches |
| assigns syntax | `contract_assigns (a; b)` — semicolons, not commas. Two clauses union on a function but are a syntax error on a loop |

## Undefined behavior discovered

**None so far.** Four kernels are proven clean; no counterexample in this
codebase has turned out to be a defect in OpenZL. For contrast, the same
method on zstd found three UB sites in four proofs. What it has found here is
one unstated precondition and one structural weakness, neither of which is a
bug you can trigger today.

| Where | Code | What it is | Exhibited by |
|---|---|---|---|
| all decode kernels | `ZL_ASSERT(...)` | **Structural, not UB.** ~300 assertions across the 31 decode kernels are the only guard on their parameters, and under `NDEBUG` each expands to `(0 && (P))` — the predicate is never evaluated and nothing aborts. In release the kernels trust their callers completely; the bindings are the sole validation layer. Every one of those asserts is a `contract_pre` waiting to be written, and promoting them moves the check from "does nothing in production" to "proven at the call site" | `grep -cE '^\s*(ZL_ASSERT\|assert)' src/openzl/codecs/*/decode_*kernel*.c` |
| `decode_zigzag_kernel.h` | `ZL_zigzagDecode64(dst, src, nbElts)` | **Unstated precondition, not UB.** The proof does not hold without `contract_pre (nbElts <= SIZE_MAX / 8)`: nothing in the signature stops `nbElts * 8` from wrapping, and `r_ok(src, <wrapped>)` then permits `src + i` to leave the object. Not reachable from any real caller — no object is that large — but the header said this only in prose ("sized accordingly"), and the clause is that sentence made checkable | remove the clause and re-run the `ZL_zigzagDecode64` command below: `arithmetic overflow on signed *` at `src[i]`, FAIL 2s |

## Proven correct

| Function | Mode | Verdict | What it establishes | Command |
|---|---|---|---|---|
| `ZL_zigzagDecode64` | enforce | PASS 2s | 148 properties. Memory safe and overflow free for every input satisfying the contract. No harness: pointers never alias, so `contract_fresh` allocates them and the contract generates the entry point | `./prove.sh ZL_zigzagDecode64 src/openzl/codecs/zigzag/decode_zigzag_kernel.c $CF` |
| `ZL_zigzagDecode32` | enforce | PASS 3s | Same, for the 32-bit width | `./prove.sh ZL_zigzagDecode32 src/openzl/codecs/zigzag/decode_zigzag_kernel.c $CF` |
| `ZS_deltaDecode64_scalar` | enforce | PASS 34s | 831 properties. The serial dependence `dst[n] = dst[n-1] + deltas[n-1]` stays in bounds for every `nbElts`, proven by induction from the loop invariant rather than unwound to a bound | `./prove.sh ZS_deltaDecode64_scalar src/openzl/codecs/delta/decode_delta_kernel.c $CF` |
| `ZS_deltaDecode64` | enforce `-r` | PASS 33s | 846 properties. That the wrapper's `if (nbElts == 0) return;` is what discharges the leaf's `contract_pre (nbElts >= 1)`. Checked, not assumed: `-r` asserts every one of the leaf's preconditions at the call site instead of inlining its body | `./prove.sh ZS_deltaDecode64 src/openzl/codecs/delta/decode_delta_kernel.c -r ZS_deltaDecode64_scalar $CF` |

Both annotated files compile warning-free under gcc and clang with the repo's
full `compile_flags.txt` warning set, and are `clang-format` clean.

## TODO

| Function | File | Blocker |
|---|---|---|
| `ZL_zigzagDecode8/16`, `ZL_zigzagDecode` | `codecs/zigzag/decode_zigzag_kernel.h` | Annotated, clauses lower cleanly, simply not in `proofs/run.sh` yet |
| `ZS_deltaDecode8/16/32` and their `_scalar` leaves | `codecs/delta/decode_delta_kernel.c` | Annotated. These widths dispatch through SSSE3, so the dispatcher needs `-r` onto the scalar leaf or the intrinsics need modelling |
| `ZS_deltaDecode` | `codecs/delta/decode_delta_kernel.h` | Annotated, unproven. Reads `first` through `ZL_readLE*`, so the proof needs `openzl/shared/mem.h` reachable from the entry point |
| `rangePackDecode` | `codecs/range_pack/decode_range_pack_kernel.c` | Unannotated. 10 macro-generated static leaves, each with a loop; needs a `-r` per width pair |
| `ZS_bitpackEncode` / bitpack decode | `codecs/bitpack/common_bitpack_kernel.c` | Unannotated, 1392 LOC, 85 asserts. The highest-value kernel target: `nbBits` reaches it straight off the wire via `DI_bitunpack` |
| `DI_bitunpack` and the other 33 decode bindings | `codecs/*/decode_*_binding.c` | Take `ZL_Decoder*` / `ZL_Input*`. Needs stubs for `ZL_Decoder_getCodecHeader`, `ZL_Decoder_create1OutStream`, `ZL_Output_ptr`. This is where attacker-controlled header bytes actually become sizes |

## Open questions

| Where | Question |
|---|---|
| `DI_bitunpack` | `nbBits` comes off the wire and is bounded only by `ZL_ERR_IF_GT(nbBits, 8 * eltWidth)` before reaching `ZS_bitpackEncodeBound` and `ZS_bitpackEncode`. Is that single check sufficient for every `eltWidth`/`nbElts` the frame can encode? Unanswerable until the bitpack kernel carries contracts |
| `rangePackDecode` | With `srcWidth`/`dstWidth` not a supported pair, every `RANGE_PACK_DECODE_CASE` falls through to `ZL_ASSERT_FAIL`, which under `NDEBUG` is a no-op rather than an abort — the function returns having written nothing, and the caller commits an uninitialised output. Is any unsupported pair reachable from a crafted frame? |
| kernel preconditions vs binding checks | The contracts state what each kernel needs. Nothing yet proves the bindings establish it, because the bindings are unannotated. Until they are, a green kernel proof says the kernel is safe *if called correctly*, not that it is called correctly |
| `-DNDEBUG` on the proofs | Proving the release configuration is the right default, but it means the ~300 asserts are invisible to CBMC. A second suite at `ZL_DBG_LVL 4` would check the asserts themselves as assertions — a different and also useful question |

## Gotchas found here

| Where | What |
|---|---|
| loop contracts + enforce | `--apply-loop-contracts` leaves a synthetic `__in_loop_havoc_block__` bool in the function. If a loop-bearing callee is then **inlined** into the function under `--enforce-contract`, the enforce pass cannot size that bool and aborts with a CBMC invariant violation. The fix is `-r` on the callee, which is also right for proof size. A loop directly in the enforced function is fine |
| `--dfcc <fn> --enforce-contract <fn>` | Not a way around it: CBMC asserts `pair.first != harness_id`. DFCC needs a harness distinct from the enforced function |
| clang-format | `AttributeMacros` is not enough — clang-format 19 lists the macros but still collapses trailing clauses onto one line. Annotated declarations and whole annotated loops (opening `for` through closing brace) are fenced with `// clang-format off` / `on`. `.clang-format` lists the macros anyway so partially formatted regions stay sane |
| `contract_pre (p != NULL)` | Does not compile on clang: `NULL` is `((void *)0)` and a cast to a pointer is not a constant expression in C. Write `0` |
| include order | `<limits.h>` for `SIZE_MAX` must sort before `<stddef.h>`; the repo's `SortIncludes` will move it and fail the format gate otherwise |
