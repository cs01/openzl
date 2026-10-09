# ESBMC harnesses for OpenZL decoders

Bounded model checking of OpenZL decode paths with stock [ESBMC](https://github.com/esbmc/esbmc) 8.5.
Each `*_harness.c` includes the unmodified production sources.

```bash
./proofs/esbmc/run.sh                                  # every harness
./proofs/esbmc/run.sh partition_bucket_range_harness   # one harness
```

Logs and counterexample traces go to `/tmp/esbmc/openzl/<harness>.txt`. `.esbmc` holds each
harness's flags, unwind bound and expected verdict.

| Harness | Verdict |
|---------|---------|
| `dispatchN_byTag_segment_wrap_harness` | COUNTEREXAMPLE |
| `dispatchN_byTag_segment_bounded_harness` | PROVEN |
| `partition_bucket_range_harness` | COUNTEREXAMPLE |
| `tokenize_vsf_wildcopy_harness` | PROVEN (Boolector, ~22 min) |
