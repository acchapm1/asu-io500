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
  run-io500.sbatch      # SLURM submission script
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

# 2. Edit scripts/run-io500.sbatch and uncomment/fill in:
#      #SBATCH --partition=...
#      #SBATCH --nodes=...
#      #SBATCH --ntasks-per-node=...
#      #SBATCH --time=...

# 3. Smoke test
sbatch scripts/run-io500.sbatch configs/config-minimal.ini pre-maint-smoke

# 4. Real pre-maintenance run
sbatch scripts/run-io500.sbatch configs/asu-beegfs.ini pre-maint

# 5. After maintenance, same commands with label "post-maint"
sbatch scripts/run-io500.sbatch configs/asu-beegfs.ini post-maint
```

Results land under `results/<UTC-timestamp>-<label>/` and include
`result_summary.txt`, `result.txt`, and a provenance snapshot (module list,
lscpu, BeeGFS targets, the config used).

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
