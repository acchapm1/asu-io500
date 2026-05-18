# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## This directory

`/home/acchapm1/io/asu-io500` **is** the git repo
(`git@github.com:acchapm1/asu-io500.git`, branch `main`). All edits made here
trigger the auto-push hook described below, so any change Claude makes lands
on GitHub automatically.

Sibling directories one level up (`/home/acchapm1/io/`) are upstream sources —
`io500/` and `ior/` — and are read-only. Build artifacts go there, but the
source isn't ours to modify. See `/home/acchapm1/io/CLAUDE.md` for the
parent-level layout.

## Project goal

Benchmark the ASU BeeGFS scratch array (`/scratch/acchapm1/io/asu-io500`,
3.7 PB) before and after a maintenance window and compare the two
`result_summary.txt` files. For the comparison to be meaningful, the pre and
post runs must use the **same** config, MPI stack (`openmpi/5.0.8`), node
count, and ranks-per-node.

## Common commands (run from this directory)

```bash
# One-time build of /home/acchapm1/io/io500 + IOR + pfind
bash scripts/install-io500.sh

# Override the MPI module
MPI_MODULE=openmpi/4.1.6 bash scripts/install-io500.sh

# Submit a smoke test
sbatch scripts/run-io500.sbatch configs/config-minimal.ini pre-maint-smoke

# Submit the real benchmark
sbatch scripts/run-io500.sbatch configs/asu-beegfs.ini pre-maint
sbatch scripts/run-io500.sbatch configs/asu-beegfs.ini post-maint

# Dry-run a config without touching the FS (run from io500 dir)
cd /home/acchapm1/io/io500
./io500 /home/acchapm1/io/asu-io500/configs/asu-beegfs.ini --dry-run

# Verify a result file wasn't tampered with
/home/acchapm1/io/io500/io500-verify <config-used.ini> <result.txt>

# Diff pre vs post
diff -u results/<ts>-pre-maint/result_summary.txt \
        results/<ts>-post-maint/result_summary.txt
```

`scripts/run-io500.sbatch` ships with the `#SBATCH` directives commented out
(`##SBATCH ...`); the user must uncomment and fill in `--partition`, `--nodes`,
`--ntasks-per-node`, `--time` before the first submit.

## Auto-push hook (active in this directory)

`.claude/settings.json` registers a `PostToolUse` hook (`.claude/auto-push.sh`)
that fires after every `Write`/`Edit`/`MultiEdit`. It:

1. Bails out (exit 0) if the touched path is outside this repo.
2. Bails out if `NO_AUTO_PUSH` exists at the repo root or
   `$CLAUDE_DISABLE_AUTOPUSH` is set.
3. Otherwise `git add` → `git commit -m "auto: update <file>"` →
   `git push origin main`.
4. Logs to `.claude/auto-push.log` (gitignored). Always exits 0 so a hook
   failure never blocks the parent tool call.

**Consequences for Claude Code:**

- Because Claude Code's cwd is inside this repo, the hook **will** fire on
  every edit. No manual commit/push needed for changes made here.
- If the user says "do not push to github", `touch NO_AUTO_PUSH` before
  editing and remove it when they want auto-push back.
- `git push origin main` is blocked by the auto-mode classifier by default.
  `.claude/settings.json` includes permission rules
  (`Bash(git push origin main:*)` and the `git -C ...` variant) so the hook
  works without prompting — but if a push is blocked, **do not work around
  the classifier**; stop and ask the user.

## Config invariants (do not break the comparison)

- `configs/asu-beegfs.ini` is **frozen** between the pre and post runs. If a
  config change is genuinely necessary (e.g., the easy phase saturates before
  `stonewall-time`), the pre run has to be re-done at the same time so the two
  data points stay comparable.
- `stonewall-time = 300` is required for a `[SCORE]` valid result. Anything
  lower produces `[SCORE INVALID]` and shouldn't be reported as a benchmark.
- `configs/config-minimal.ini` is a smoke test; its `[SCORE INVALID]` output
  is expected and OK.

## Result directory contract

`scripts/run-io500.sbatch` writes to `results/<UTC-timestamp>-<label>/` and
captures, alongside io500's own `result.txt` / `result_summary.txt`:

- `config-used.ini` — the exact config submitted
- `run-metadata.txt` — SLURM job id, nodelist, ntasks
- `module-list.txt`, `lscpu.txt`, `uname.txt`
- `df.txt`, `mount-beegfs.txt`, `beegfs-targets.txt`, `beegfs-net.txt`
- `io500.stdout`, `io500.stderr`

When investigating regressions, these provenance files matter — don't delete
them or restructure the directory without updating `docs/running.md`.

## Reference docs

`docs/` has the user-facing walkthrough:
- `install.md` — detailed install troubleshooting
- `running.md` — submit, capture, dry-run
- `interpreting-results.md` — phase definitions, regression triage
