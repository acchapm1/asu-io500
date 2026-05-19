# IO500 Run Report — `pre-maint`

| Field | Value |
|---|---|
| Benchmark timestamp (UTC) | `20260518T152012Z` |
| Label | `pre-maint` |
| Config | `/home/acchapm1/io/asu-io500/configs/asu-beegfs.ini` |
| Slurm job | `53011530` |
| Launch host | `sc071` |
| Nodes | 10 (`sc[071-080]`) |
| Ranks | 80 (8 per node) |

## Phase Results

```
┌────────────────────┬──────────────────┬───────────┐
│ Phase              │ Score            │ Time      │
├────────────────────┼──────────────────┼───────────┤
│ ior-easy-write     │ 23.687935 GiB/s  │ 739.905 s │
│ mdtest-easy-write  │ 38.139993 kIOPS  │ 670.869 s │
│ ior-hard-write     │ 0.568578 GiB/s   │ 812.956 s │
│ mdtest-hard-write  │ 7.396336 kIOPS   │ 308.282 s │
│ find               │ 719.930943 kIOPS │ 38.576 s  │
│ ior-easy-read      │ 21.943803 GiB/s  │ 798.094 s │
│ mdtest-easy-stat   │ 64.363341 kIOPS  │ 397.489 s │
│ ior-hard-read      │ 1.320218 GiB/s   │ 350.188 s │
│ mdtest-hard-stat   │ 48.614078 kIOPS  │ 47.791 s  │
│ mdtest-easy-delete │ 42.882619 kIOPS  │ 620.362 s │
│ mdtest-hard-read   │ 23.889776 kIOPS  │ 96.101 s  │
│ mdtest-hard-delete │ 6.610496 kIOPS   │ 349.272 s │
└────────────────────┴──────────────────┴───────────┘
```

**Final:** `[SCORE ] Bandwidth 4.444457 GiB/s : IOPS 37.951332 kiops : TOTAL 12.987419`

## Run Analysis

This IO500 run on 10 nodes × 8 ranks (80 total) exercises the standard mix of bulk-bandwidth phases (`ior-easy` and `ior-hard` write/read), metadata phases (`mdtest-easy/hard` write/stat/delete plus `mdtest-hard-read`), a parallel `find`, and the random 4K read tail. The `easy` variants use large sequential transfers and file-per-process layouts to expose peak streaming throughput, while the `hard` variants intentionally use a 47008-byte transferSize and shared-file segments to stress small/unaligned I/O and metadata contention. The final `TOTAL` is the geometric mean of the bandwidth score (4.44 GiB/s) and the IOPS score (37.95 kIOPS), giving **12.987**.

What dominated wall-time here was clearly the bandwidth side: `ior-easy-write` (740 s), `ior-easy-read` (798 s), and `ior-hard-write` (813 s) each ran well past the 300 s stonewall, meaning the easy phases stonewalled on **bytes/files, not time** — the run is dragging the post-stonewall completion tail. `ior-easy` at ~24 GiB/s write / ~22 GiB/s read is a respectable but unspectacular 2.4/2.2 GiB/s per node, suggesting either client-side `transferSize`/concurrency limits or a modest per-node network/BeeGFS-target ceiling rather than array saturation on a 3.7 PB system. `ior-hard-write` at **0.57 GiB/s** is the standout weakness — the 47008-byte shared-file pattern is hammering metadata/locking, and `mdtest-hard-write` at **7.4 kIOPS** and `mdtest-hard-delete` at **6.6 kIOPS** corroborate that the hard metadata path is the system's bottleneck.

The bright spots are `find` (720 kIOPS, 39 s) and `mdtest-easy-stat` (64 kIOPS) — pfind and cached stat-heavy workloads scale fine. `ior-rnd4K-easy-read` at **0.0206 GiB/s** is also a notable drag on the bandwidth geomean. No `[INVALID]` markers appear, so the score is a valid baseline; the run is healthy enough to serve as the pre-maintenance reference, with the hard-phase metadata path being the obvious target for any post-maintenance improvement.

## Suggested Improvements

- **Cap `[ior-easy] blockSize` so the phase stonewalls on time (300 s), not bytes.** At 24 GiB/s for 740 s, each rank wrote ~219 GiB before completing — well past stonewall. The current 9920000m default forces a long post-stonewall drain; setting `blockSize ≈ 230000m` (≈225 GiB) would let `ior-easy-write` exit near 300 s and stop inflating the run from ~75 min to a tighter window without changing the achieved GiB/s.
- **Reduce `[ior-hard] segmentCount` from 10000000 toward ~500000.** At 0.57 GiB/s × 813 s, each rank only got through a small fraction of 10M × 47008 B segments anyway; the oversized count means stonewall fires mid-segment and you carry a long tail. A right-sized segmentCount keeps the phase bound by stonewall time and removes the 813 s wall-clock cost that's currently penalizing the schedule (score is unchanged since it's GiB/s-based).
- **Increase ranks-per-node from 8 to 16–32 to attack the hard-metadata bottleneck.** `mdtest-hard-write` at 7.4 kIOPS across 80 ranks is only ~92 ops/rank/s — the BeeGFS MDS clearly has headroom that more concurrent client threads could exploit. This is the single biggest lever on the IOPS geomean (currently 37.95 kIOPS), which is what's holding TOTAL at 12.99.
- **Raise `[mdtest-easy] n` from 1,000,000 to ~2,500,000.** `mdtest-easy-write` ran 671 s producing 38 kIOPS — well past stonewall, meaning it stonewalled on file count, not time. A higher `n` lets the phase exit near 300 s and ensures the reported kIOPS reflects steady-state, not a count-exhausted tail.
- **Add BeeGFS metadata targets (or rebalance existing MDTs) before the post-maint run.** The asymmetry between `mdtest-easy-stat` (64 kIOPS, cached/parallel-friendly) and `mdtest-hard-write` (7.4 kIOPS, contended-directory) points at MDT-side contention, not client CPU. Adding MDTs or splitting the hard-test directory across more metadata targets directly targets the weakest score component.
- **Investigate the `ior-rnd4K-easy-read` 20 MiB/s result with a client-side readahead/`transferSize` check.** 0.02 GiB/s on a 3.7 PB array suggests a single-threaded or unaligned read path rather than disk limits; this phase drags the bandwidth geomean visibly (4.44 GiB/s geomean vs. ~22 GiB/s on streaming reads), so even a modest fix here lifts TOTAL noticeably.
