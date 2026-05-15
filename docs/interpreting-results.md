# Interpreting results

io500 measures twelve I/O phases and rolls them up into three numbers:

- **BW** (bandwidth, GB/s) — geometric mean of the four bandwidth phases
  (`ior-easy-write`, `ior-easy-read`, `ior-hard-write`, `ior-hard-read`).
- **MD** (metadata, kIOPS) — geometric mean of eight metadata phases
  (`mdtest-easy-{write,stat,delete}`, `mdtest-hard-{write,stat,read,delete}`, `find`).
- **SCORE** — geometric mean of BW and MD. This is the headline io500 number.

The full breakdown is in `result_summary.txt`:

```
[RESULT]       ior-easy-write   ... GiB/s
[RESULT]    mdtest-easy-write   ... kIOPS
... (12 phases) ...
[SCORE]    Bandwidth ... GB/s : IOPS ... kiops : TOTAL ...
```

## Valid vs invalid runs

A run is `[SCORE INVALID]` (not `[SCORE]`) when:

- any phase finished in less than `stonewall-time` (default 300s), or
- `stonewall-time` is below 300, or
- non-default flags inflate scores (e.g., `pause-dir`, `files-per-dir`).

Our smoke runs (`config-minimal.ini`) will always come back INVALID — that's
fine, we're only checking that the binary launches and writes through to
BeeGFS. The real runs (`asu-beegfs.ini`) should be VALID; if they aren't,
either give them more data (raise `blockSize`, `segmentCount`, or `n`) or more
ranks so the phases stretch past 300s.

## Comparing pre vs post maintenance

Side-by-side diff of the two `result_summary.txt` files:

```bash
diff -u \
  results/<ts>-pre-maint/result_summary.txt \
  results/<ts>-post-maint/result_summary.txt
```

Or a quick column-aligned view:

```bash
paste \
  <(grep '\[RESULT\]\|\[SCORE\]' results/<ts>-pre-maint/result_summary.txt) \
  <(grep '\[RESULT\]\|\[SCORE\]' results/<ts>-post-maint/result_summary.txt)
```

## What "regression" looks like

Day-to-day noise on a shared filesystem is real — 5–10% swings in individual
phases are common even with no changes. Things to look for:

- **Aggregate SCORE drops by >10%** — maintenance likely regressed something.
- **A specific phase drops sharply while others don't** — points at one
  subsystem. `mdtest-*-write` regression → MDT/metadata path. `ior-easy-write`
  regression → OSS/storage targets. `find` regression → directory listing path.
- **Read phases regress more than write** — caches got dropped or stripe
  layout changed.
- **Run is now INVALID where it was VALID** — stonewall no longer reached;
  array got slower for the easy phase. This itself is a regression signal.

Capture the diff in an issue or commit message so the comparison is reviewable
later. The per-phase logs (`ior-*`, `mdtest-*` in the result dir) have client
latency histograms that are useful for root-causing a regression.

## Integrity check

To confirm a result wasn't edited after the fact:

```bash
/home/acchapm1/io/io500/io500-verify \
  results/<ts>-<label>/config-used.ini \
  results/<ts>-<label>/result.txt
```

Outputs `config-hash` and `score-hash`; both should match the values inside
`result.txt`.
