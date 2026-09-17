# Data Model: Codec Contract Verification

Four entities from the spec, plus the concrete shape each takes on disk. The
manifest (`proofs/cases.tsv`) is the physical form of **Coverage entry** and
**Expected verdict**; `CONTRACTS.md` is a rendering of it. **Contract clause**
lives in source, not in any data file. **Finding** is prose in `CONTRACTS.md`
that a manifest row can point at.

## Contract clause

A statement attached to a function declaration or a loop, carrying a single
obligation. Not stored in any data file — it is source text in a kernel header
or `.c`, expanded by `src/openzl/shared/c_contracts.h`.

| Field | Values | Notes |
|---|---|---|
| Kind | `pre`, `post`, `assigns`, `invariant`, `decreases`, `reads`/`reads_n`, `writes`/`writes_n` | The macro name determines lowering |
| Attachment | function declaration, or loop header | Loop clauses sit between the `for`/`while` header and the opening brace |
| Lowering | `__CPROVER_*` under `-DC_CONTRACTS_CPROVER`; `diagnose_if` under stock clang; nothing elsewhere | Chosen at include time, not by the author |

**Validation rules** (from the spec's requirements and the prototype's gotchas):

- `contract_post` requires a `contract_assigns` on the same function, or a
  caller assumes no write and branches are silently deleted.
- `contract_assigns` on a function unions across clauses; on a *loop* two
  clauses are a syntax error — use one clause with `;` separators.
- `contract_pre(p != NULL)` does not compile under clang. Write `0`.
- `contract_forall` degrades to `1` under stock clang, so a promoted value
  invariant costs nothing at call sites.
- An annotated region is fenced with `// clang-format off` / `on`.
- `<limits.h>` must sort before `<stddef.h>` or `SortIncludes` fails the gate.

**State transitions**: none — a clause is written or it is not.

## Coverage entry

One row per in-scope function. An entry always exists once the enumerator finds
the function; only its content varies. Physically one line of
`proofs/cases.tsv`.

| Field | Column | Type / vocabulary | Required |
|---|---|---|---|
| Function | `function` | C identifier | always |
| Source | `source` | repo-relative path to the `.c` or `.h` holding the definition | always |
| Mode | `mode` | `enforce`, `enforce-r`, `harness`, `none` | always |
| Extra flags | `flags` | verbatim tail passed to `prove.sh` (e.g. `-r ZS_deltaDecode64_scalar`); `-` when none | always |
| Tier | `tier` | `fast`, `slow`, `-` | always |
| Reachability | `reach` | `decode`, `test-only` | always |
| Expected verdict | `expect` | `PASS`, `FAIL`, `ERROR`, `-` | always |
| Reason class | `reason_class` | see vocabulary below | always |
| Note | `note` | free prose, no tab characters | always (`-` permitted) |

**Validation rules**

- `mode = none` ⟺ `expect = -` ⟺ `tier = -`. A row with no dispatchable
  command is a reason row; it appears in the record and never in the suite.
- `mode != none` requires `reason_class` ∈ {`-`, `defect`} and `expect` ≠ `-`.
- `expect = FAIL` requires `reason_class = defect` and a `note` naming the
  defect. This is the FR-009b mechanism: the demonstration failing to fail is
  itself a suite failure.
- `reason_class = todo` is transient. The completeness check accepts it during
  implementation and rejects it at final acceptance (D12).
- Every function the enumerator reports has exactly one row. A row naming a
  function the enumerator does not report is also an error — it means the
  surface moved underneath the record.
- `tier = slow` when measured elapsed exceeds 20s. Recorded, not inferred.

**Reason class vocabulary** (closed):

| Value | Means |
|---|---|
| `-` | No reason needed — the function is proved |
| `defect` | Expected `FAIL`; the row demonstrates a confirmed defect |
| `simd` | Only path is vector intrinsics CBMC cannot model, and no scalar leaf exists to contract |
| `alias` | Pointer arguments alias into one object, so `contract_fresh` cannot construct them |
| `inline-loop` | A loop-bearing callee cannot be separated; enforce aborts on the synthetic `__in_loop_havoc_block__` |
| `framework` | Takes a framework handle, or a struct with internal pointers the contract cannot build |
| `timeout` | Exceeded the budget; the `note` names the budget and the mode attempted |
| `todo` | Transient during implementation only |

**State transitions**

```text
   enumerator finds function
             │
             ▼
     ┌──────────────┐   triage says     ┌───────────────┐
     │ todo         │──── unprovable ──▶│ terminal      │
     │ (mode=none)  │                   │ reason        │
     └──────┬───────┘                   │ simd / alias  │
            │ triage picks a mode       │ inline-loop   │
            │                           │ framework     │
            ▼                           └───────────────┘
     ┌──────────────┐                           ▲
     │ dispatchable │─── budget exceeded ───────┤
     │ expect=PASS  │                    timeout│
     └──────┬───────┘                           │
            │ proof discharges                  │
            ▼                                   │
     ┌──────────────┐  counterexample is real   │
     │ proved       │◀──────┐            ┌──────┴───────┐
     │ reason = -   │       └────────────│ expect=FAIL  │
     └──────────────┘   defect fixed     │ reason=defect│
                        elsewhere        └──────────────┘
```

`todo` is the only state the final acceptance check rejects.

## Expected verdict

Not a separate file — the `expect` column. Modelled separately because its
semantics are the spec's load-bearing idea: the suite fails on a *mismatch*, in
either direction.

| Actual \ Expected | `PASS` | `FAIL` | `ERROR` |
|---|---|---|---|
| `PASS` | match | **suite fails** — demonstration stopped working | **suite fails** |
| `FAIL` | **suite fails** — regression | match | **suite fails** |
| `ERROR` | **suite fails** | **suite fails** | match |
| `SKIP` | not a result — missing prerequisite, reported and not counted | same | same |

`SKIP` is deliberately outside the matrix: `proofs/run.sh` emits it when `cbmc`
or `prove.sh` is absent, and it is reported as "skipped = missing prerequisite,
not a result". Preserved from the existing runner.

## Finding

An observation produced by the verification effort. Prose in `CONTRACTS.md`, in
one of two sections that must not be merged (FR-010).

| Field | Values |
|---|---|
| Classification | `defect` — a real bug in OpenZL; or `observation` — an unstated precondition, a prose/contract divergence, a specification gap |
| Location | codec, file, function |
| Basis | the command or measurement that established it |
| Linked entry | the manifest row that demonstrates it, if any |

**Validation rules**

- A `defect` is rendered under a heading that says a defect was found; an
  `observation` is rendered under one that does not. The existing record already
  splits these ("Undefined behavior discovered" vs "Observations") after an
  earlier correction; the split is preserved.
- A defect-free area states its sample size rather than asserting cleanliness
  (FR-011, SC-006). The generator emits the sample size from the manifest —
  count of rows with `expect = PASS` in that codec — so the number cannot drift
  from the evidence.
- A `defect` never causes a codec behavior change in this feature (FR-015). It
  causes a row with `expect = FAIL` and a reproduction command.

## Relationships

```text
  ┌─────────────────────┐
  │ Contract clause     │  in source: kernel .h / .c
  │  kind, attachment   │
  └──────────┬──────────┘
             │ 1..*  attached to one function
             ▼
  ┌─────────────────────┐        ┌──────────────────────┐
  │ Coverage entry      │───1──▶ │ Expected verdict     │
  │  proofs/cases.tsv   │        │  expect column       │
  │  one row / function │        │  PASS | FAIL | ERROR │
  └──────────┬──────────┘        └──────────────────────┘
             │ 0..*  demonstrates
             ▼
  ┌─────────────────────┐
  │ Finding             │  prose in CONTRACTS.md
  │  defect |           │
  │  observation        │
  └─────────────────────┘

  ┌─────────────────────┐        ┌──────────────────────┐
  │ enumerate.py        │──────▶ │ Coverage entry set   │
  │  surface (D6)       │  must  │  must be equal       │
  └─────────────────────┘  equal └──────────────────────┘
```

The bottom relation is the whole of SC-001: the enumerated surface and the set
of manifest rows are the same set, and a check says so.
