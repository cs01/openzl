# ESBMC harnesses for OpenZL decoders

Bounded model checking of OpenZL decode paths with stock [ESBMC](https://github.com/esbmc/esbmc) 8.5.
Each `*_harness.c` includes the unmodified production sources.

```bash
./proofs/esbmc/run.sh                                  # every harness
./proofs/esbmc/run.sh partition_bucket_range_harness   # one harness
```

`.esbmc` holds each harness's flags, unwind bound and expected verdict. Each run writes its full
ESBMC output to `$ESBMC_OUT/<harness>.txt` (default `/tmp/esbmc/openzl`) on the machine running it.

| Harness | Verdict |
|---------|---------|
| `dispatchN_byTag_segment_wrap_harness` | COUNTEREXAMPLE |
| `dispatchN_byTag_segment_bounded_harness` | PROVEN |
| `partition_bucket_range_harness` | COUNTEREXAMPLE |
| `tokenize_vsf_wildcopy_harness` | PROVEN (Boolector, ~22 min) |

## Counterexamples

ESBMC 8.5 traces, trimmed: repeated byte-level states are collapsed to `(xN)` and pointer-encoding
noise is elided.

### `dispatchN_byTag_segment_wrap_harness`

<details>
<summary>Counterexample</summary>

```
proofs/esbmc/dispatchN_byTag_segment_wrap_harness.c:21 main
  srcLen = 4
proofs/esbmc/dispatchN_byTag_segment_wrap_harness.c:27 main
  variable = { .ptr=&dynamic_1_array[0], .numElts=srcLen?1!0&0#1, .eltWidth=1, .capacity=srcLen?1!0&0#1, .type=1, .anon_pad#5=0 }
proofs/esbmc/dispatchN_byTag_segment_wrap_harness.c:29 main
  nbSegments = 2
proofs/esbmc/dispatchN_byTag_segment_wrap_harness.c:34 main
  sizes[(signed long int)i] = -25   (x8)
proofs/esbmc/dispatchN_byTag_segment_wrap_harness.c:35 main
  tags[(signed long int)i] = 0
proofs/esbmc/dispatchN_byTag_segment_wrap_harness.c:34 main
  sizes[(signed long int)i] = 29   (x8)
proofs/esbmc/dispatchN_byTag_segment_wrap_harness.c:35 main
  tags[(signed long int)i] = 0
proofs/esbmc/dispatchN_byTag_segment_wrap_harness.c:37 main
  tagStream = { .ptr=&dynamic_3_array[0], .numElts=nbSegments?1!0&0#1, .eltWidth=1, .capacity=nbSegments?1!0&0#1, .type=4, .anon_pad#5=0 }
  ... 1 state(s) elided
src/openzl/codecs/dispatchN_byTag/decode_dispatchN_byTag_binding.c:36 DI_dispatchN_byTag
  __dbg_lhs = 4   (x2)
src/openzl/codecs/dispatchN_byTag/decode_dispatchN_byTag_binding.c:40 DI_dispatchN_byTag
  nbSegments = 2
src/openzl/codecs/dispatchN_byTag/decode_dispatchN_byTag_binding.c:41 DI_dispatchN_byTag
  __dbg_lhs = 2
src/openzl/codecs/dispatchN_byTag/decode_dispatchN_byTag_binding.c:41 DI_dispatchN_byTag
  __dbg_rhs = 2
src/openzl/codecs/dispatchN_byTag/decode_dispatchN_byTag_binding.c:48 DI_dispatchN_byTag
  __dbg_lhs = 1
src/openzl/codecs/dispatchN_byTag/decode_dispatchN_byTag_binding.c:55 DI_dispatchN_byTag
  __dbg_lhs = 1
src/openzl/codecs/dispatchN_byTag/decode_dispatchN_byTag_binding.c:56 DI_dispatchN_byTag
  total = 4
proofs/esbmc/zl_decoder_stubs.h:66 ZL_Decoder_create1OutStream
  stub_out.capacity = { .ptr=&dynamic_4_array[0], .numElts=0, .eltWidth=0, .capacity=eltsCapacity?1!0&0#1, .type=0, .anon_pad#5=0 }
  ... 8 state(s) elided
src/openzl/codecs/range_pack/decode_range_pack_kernel.c:50 rangePackDecode
  __dbg_lhs = 8
src/openzl/codecs/range_pack/decode_range_pack_kernel.c:50 rangePackDecode
  __dbg_lhs = 1
src/openzl/codecs/range_pack/decode_range_pack_kernel.c:37 rangeUnpack_uint8_t_uint16_t
  __dbg_lhs = 0
src/openzl/codecs/range_pack/decode_range_pack_kernel.c:37 rangeUnpack_uint8_t_uint16_t
  dst[(signed long int)i] = 0   (x2)
src/openzl/codecs/range_pack/decode_range_pack_kernel.c:37 rangeUnpack_uint8_t_uint16_t
  __dbg_lhs = 0
src/openzl/codecs/range_pack/decode_range_pack_kernel.c:37 rangeUnpack_uint8_t_uint16_t
  dst[(signed long int)i] = 0   (x2)
src/openzl/shared/numeric_operations.c:105 NUMOP_underLimitU16
  underLimit = 1   (x2)
src/openzl/codecs/dispatchN_byTag/decode_dispatchN_byTag_binding.c:107 DI_dispatchN_byTag
  srcSizes[(signed long int)(bufIndex[(signed long int)n])] = -25   (x8)
src/openzl/codecs/dispatchN_byTag/decode_dispatchN_byTag_binding.c:107 DI_dispatchN_byTag
  srcSizes[(signed long int)(bufIndex[(signed long int)n])] = 4   (x8)
src/openzl/codecs/dispatchN_byTag/decode_dispatchN_byTag_kernel.c:16 sumArrayST
  total = 575755447793856743
src/openzl/codecs/dispatchN_byTag/decode_dispatchN_byTag_kernel.c:16 sumArrayST
  total = 4
src/openzl/codecs/dispatchN_byTag/decode_dispatchN_byTag_kernel.c:53 ZL_dispatchN_byTag_decode
  dstSize = 4
src/openzl/shared/numeric_operations.c:105 NUMOP_underLimitU16
  underLimit = 1   (x2)
src/openzl/codecs/dispatchN_byTag/decode_dispatchN_byTag_kernel.c:66 ZL_dispatchN_byTag_decode
  segSize = 575755447793856743
src/openzl/codecs/dispatchN_byTag/decode_dispatchN_byTag_kernel.c:67 ZL_dispatchN_byTag_decode
  tag = 0
  ... 1 state(s) elided

Violated property:
  file /esbmc-vfs/libc/library/string.c line 286 column 5 function __memcpy_impl
  dereference failure: array bounds violated: heap object
  CWE: CWE-122, CWE-125, CWE-129, CWE-131, CWE-193, CWE-787
```

</details>

### `partition_bucket_range_harness`

<details>
<summary>Counterexample</summary>

```
proofs/esbmc/partition_bucket_range_harness.c:27 main
  nbValues = 2
proofs/esbmc/partition_bucket_range_harness.c:31 main
  buckets[(signed long int)i] = -1   (x2)
proofs/esbmc/partition_bucket_range_harness.c:35 main
  offsets[(signed long int)i] = 0   (x2)
proofs/esbmc/partition_bucket_range_harness.c:38 main
  bucketStream = { .ptr=&dynamic_2_array[0], .numElts=nbValues?1!0&0#1, .eltWidth=1, .capacity=nbValues?1!0&0#1, .type=4, .anon_pad#5=0 }
src/openzl/codecs/partition/decode_partition_binding.c:39 DI_partition
  __dbg_lhs = 1
src/openzl/codecs/partition/decode_partition_binding.c:42 DI_partition
  numElts = 2
  ... 3 state(s) elided
include/openzl/zl_errors.h:259 ZL_returnValue
  report._value._code = 0
include/openzl/zl_errors.h:260 ZL_returnValue
  report._value._value = 0
  ... 2 state(s) elided
include/openzl/zl_errors.h:259 ZL_returnValue
  report._value._code = 0
include/openzl/zl_errors.h:260 ZL_returnValue
  report._value._value = 0
  ... 1 state(s) elided
proofs/esbmc/zl_decoder_stubs.h:66 ZL_Decoder_create1OutStream
  stub_out.capacity = { .ptr=&dynamic_5_array[0], .numElts=0, .eltWidth=0, .capacity=eltsCapacity?1!0&0#1, .type=0, .anon_pad#5=0 }
proofs/esbmc/zl_decoder_stubs.h:67 ZL_Decoder_create1OutStream
  stub_out.eltWidth = { .ptr=&dynamic_5_array[0], .numElts=0, .eltWidth=1, .capacity=2, .type=0, .anon_pad#5=0 }
src/openzl/codecs/partition/common_partition.c:26 ZL_PartitionParams_validate
  sum = 0
src/openzl/shared/overflow.h:186 ZL_overflowAddU64
  *result = 1
src/openzl/shared/overflow.h:186 ZL_overflowAddU64
  *result = 2
  ... 1 state(s) elided
src/openzl/codecs/partition/common_partition.c:148 ZL_PartitionParams_computeBits
  bits[(signed long int)i] = 0   (x2)
src/openzl/codecs/common/bitstream/ff_bitstream.h:354 ZS_BitDStreamFF_loadPartial
  container = 0   (x2)
  ... 1 state(s) elided
src/openzl/codecs/partition/decode_partition_kernel.c:75 ZL_partitionDecode
  bitstream = { .container=0, .nbBitsRead=48, .ptr=&dynamic_3_array[2], .limit=&dynamic_3_array[0], .end=&dynamic_3_array[2], .begin=&dynamic_3_array[0] }
src/openzl/codecs/common/bitstream/ff_bitstream.h:422 ZS_BitDStreamFF_skip
  bits->container = { .container=0, .nbBitsRead=48, .ptr=&dynamic_3_array[2], .limit=&dynamic_3_array[0], .end=&dynamic_3_array[2], .begin=&dynamic_3_array[0] }
src/openzl/codecs/common/bitstream/ff_bitstream.h:423 ZS_BitDStreamFF_skip
  bits->nbBitsRead = { .container=0, .nbBitsRead=80, .ptr=&dynamic_3_array[2], .limit=&dynamic_3_array[0], .end=&dynamic_3_array[2], .begin=&dynamic_3_array[0] }
src/openzl/codecs/common/bitstream/ff_bitstream.h:428 ZS_BitDStreamFF_reload
  ptr = bitstream.ptr + 10
  ... 1 state(s) elided

Violated property:
  file src/openzl/codecs/common/bitstream/ff_bitstream.h line 422 column 5 function ZS_BitDStreamFF_skip
  undefined behavior on shift operation lshr
  CWE: CWE-1335
  nbBits < 64
```

</details>
