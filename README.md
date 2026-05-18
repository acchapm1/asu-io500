# asu-io500

io500 benchmark harness for the ASU scratch BeeGFS array
(`/scratch/acchapm1/io`). Purpose: run an identical benchmark before and after
filesystem maintenance and compare the two `result_summary.txt` files.

## Layout

```
configs/
  config-minimal.ini    # smoke test
  asu-beegfs.ini        # the real pre/post-maintenance benchmark
scripts/
  install-io500.sh      # one-time build of /home/acchapm1/io/io500
  run-io500.sbatch      # core SLURM submission script
  smoke-test.sh         # sbatch wrapper: 2 nodes x 8 ranks, minimal config
  run-10node.sh         # sbatch wrapper: 10 nodes x 8 ranks, real config
  run-full-cluster.sh   # sbatch wrapper: full-cluster, real config (edit before first use)
  cleanup-datadir.sh    # parallel rm -rf of a leftover io500 datadir on BeeGFS
  generate-report.sh    # build a markdown report (+ AI analysis) for a results dir
results/                # per-run output, committed to git
docs/
  install.md            # detailed install walkthrough
  running.md            # how to submit and what gets captured
  interpreting-results.md  # comparing pre vs post
.claude/
  settings.json         # PostToolUse hook -> auto commit + push
  auto-push.sh          # hook helper (see "Auto-push" below)
```

## Quickstart

```bash
# 1. Build io500 + IOR + pfind (once)
bash scripts/install-io500.sh

# 2. Smoke test (2 nodes x 8 ranks, minimal config, ~2h walltime)
sbatch scripts/smoke-test.sh

# 3. Real pre-maintenance run at 10 nodes
sbatch scripts/run-10node.sh pre-maint

# 4. After maintenance, same wrapper with label "post-maint"
sbatch scripts/run-10node.sh post-maint

# 5. Full-cluster run (edit scripts/run-full-cluster.sh first to set
#    --partition / --nodes / --time / --reservation for your allocation)
sbatch scripts/run-full-cluster.sh pre-maint
sbatch scripts/run-full-cluster.sh post-maint
```

The wrappers delegate to `scripts/run-io500.sbatch <config> <label>`, which is
also fine to call directly if you want a one-off node count. `run-io500.sbatch`
ships with sensible `#SBATCH` defaults (htc / public / 2 nodes / 2h); the
wrappers override them for their own scale.

Results land under `results/<UTC-timestamp>-<label>/` and include
`result_summary.txt`, `result.txt`, and a provenance snapshot (module list,
lscpu, BeeGFS targets, the config used). SLURM stdout/stderr go under
`scripts/logs/`.

## Generating a report

After a run finishes, build a markdown report (header + phase-results table +
AI-generated analysis and improvement suggestions):

```bash
scripts/generate-report.sh results/<UTC-timestamp>-<label>
```

The script writes `report-<timestamp>-<label>.md` into the results dir. The
analysis section is produced by `claude -p` from `result_summary.txt`,
`run-metadata.txt`, and `config-used.ini`; if the `claude` CLI is not on PATH,
those sections are stubbed out for manual completion.

## Cleaning up a datadir

io500 leaves a populated datadir on BeeGFS (default
`/scratch/acchapm1/io/io500-bench/<benchmark-timestamp>`) that can hold
millions of files. `scripts/cleanup-datadir.sh` removes one in parallel using
MPI:

```bash
sbatch scripts/cleanup-datadir.sh latest                # newest subdir
sbatch scripts/cleanup-datadir.sh 2026.05.18-15.20.12   # specific subdir
```

It refuses to touch anything that doesn't live under a `*/io500-*/` tree, as
a guard against typos in the argument.

## Auto-push

This repo has a project-scoped Claude Code hook
(`.claude/settings.json`) that runs `.claude/auto-push.sh` after every
`Write`/`Edit`/`MultiEdit` tool use. The script:

- only acts on files under this repo;
- skips when `NO_AUTO_PUSH` exists at the repo root or
  `$CLAUDE_DISABLE_AUTOPUSH` is set;
- runs `git add` → `git commit -m "auto: update <file>"` → `git push origin main`;
- logs to `.claude/auto-push.log` (gitignored).

To disable for a session, say "do not push to github" and the assistant will
`touch NO_AUTO_PUSH`. `rm NO_AUTO_PUSH` re-enables it.

## Docs

- [docs/install.md](docs/install.md)
- [docs/running.md](docs/running.md)
- [docs/interpreting-results.md](docs/interpreting-results.md)

## Upstream

- io500: https://github.com/IO500/io500 (cloned at `/home/acchapm1/io/io500`)
- IOR:   https://github.com/hpc/ior   (cloned at `/home/acchapm1/io/ior`; pulled
  fresh into `io500/build/ior/` by `prepare.sh`)
- io500.org: https://io500.org/
