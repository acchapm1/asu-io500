# Generating IO500 Run Reports

After a benchmark run finishes, `scripts/generate-report.sh` produces a
markdown report inside the results directory. The report has three sections:

1. **Header** — label, timestamp, nodes/ranks, slurm job, config path.
2. **Phase Results** — the per-phase scores table parsed from
   `result_summary.txt`, plus the final `[SCORE]` line.
3. **Run Analysis + Suggested Improvements** — either prose written by
   the `claude` CLI, or a rule-based fallback (with a matplotlib chart and
   an optional cross-run comparison table) written by
   `scripts/generate-report.py`.

The script auto-detects which analysis source to use; you can also force
either path.

## Quick start

```bash
# Default: use claude if available, else fall back to Python.
bash scripts/generate-report.sh results/20260518T152012Z-pre-maint

# Force the Python rule-based path (no LLM):
bash scripts/generate-report.sh --no-claude results/20260518T152012Z-pre-maint

# Require claude (error out if it's not on PATH):
bash scripts/generate-report.sh --with-claude results/20260518T152012Z-pre-maint
```

The output is written to
`results/<UTC-ts>-<label>/report-<UTC-ts>-<label>.md`. If the Python path
runs, it also drops `phases.png` (per-phase score bar chart) into the same
directory and the markdown references it inline.

## Choosing between Claude and the Python fallback

| Path | When it runs | Strengths | Cost |
|---|---|---|---|
| `claude -p` | `claude` is on `$PATH` and `--no-claude` wasn't passed | Free-form prose, can spot subtle patterns | Needs network + Claude credentials, ~30–60 s per report |
| `scripts/generate-report.py` | No `claude`, or `--no-claude` flag | Deterministic, fast, embeds a chart, scans sibling result dirs | Limited to the heuristics we've coded |

For routine pre/post-maintenance comparisons the Python fallback is fine.
Use the Claude path when you want a written interpretation.

## Setting up the Python fallback environment

The Python path needs Python 3.7+ and `matplotlib`. The cleanest way to get
both is the project's pixi env (`pixi.toml` at the repo root). The bash
wrapper auto-invokes `pixi run …`; you just need `pixi` reachable.

### On the ASU Sol HPC cluster

Pixi is available as an Lmod module. Load it once per shell session
before running the report script:

```bash
module load pixi/.0.68.1
pixi --version          # confirm
```

The leading `.` in `.0.68.1` is the cluster module name — it does not
appear in `module avail` output by default because Lmod hides modules
whose version starts with a dot. Use the explicit string above and it
will load.

You don't need to `pixi install` explicitly — `pixi run` materializes the
env on first use. But running it once interactively makes the first
report fast instead of slow:

```bash
cd /path/to/asu-io500
pixi install            # ~30 s, populates .pixi/envs/default
```

After that:

```bash
bash scripts/generate-report.sh --no-claude results/<ts>-<label>
# or, equivalently:
pixi run report --no-claude results/<ts>-<label>
```

### Off the cluster (general install)

Pixi is a single-binary install — no Python or conda prerequisites:

```bash
# Linux / macOS (official installer):
curl -fsSL https://pixi.sh/install.sh | bash
# then restart your shell or:
export PATH="$HOME/.pixi/bin:$PATH"

# Or via a package manager:
brew install pixi                    # macOS
cargo install pixi                   # from source
```

Confirm and install the env:

```bash
pixi --version
cd /path/to/asu-io500
pixi install
bash scripts/generate-report.sh --no-claude results/<ts>-<label>
```

### Without pixi (minimal fallback)

If pixi cannot be installed, the bash wrapper will fall back to your
system `python3` provided it is Python 3.7 or newer. Charts will be
skipped (no matplotlib), but the analysis prose and the cross-run
comparison table still render. RHEL 8's default `/usr/bin/python3` is
3.6.8 — too old; load a newer Python module or install pixi.

## What the Python report includes

Run `scripts/generate-report.py results/<ts>-<label>` directly to see the
raw output:

- **Run Analysis** — 2–3 paragraphs derived from `result_summary.txt`:
  which phase dominated total time, the easy/hard write ratio (a proxy
  for small-IO health on BeeGFS), whether the score is `[SCORE]` or
  `[SCORE INVALID]`, and which phases finished well under the stonewall
  window (count-limited rather than time-limited).
- **`phases.png`** — horizontal bar chart of every phase, split into
  bandwidth and metadata subplots. Referenced from the markdown.
- **Suggested Improvements** — 4–6 bullets, ordered by expected impact,
  each anchored to a specific number from the run. Heuristics include:
  ior-hard write small-IO bottlenecks, metadata-target saturation,
  count-limited phases that need bigger `n` / `segmentCount` / `blockSize`,
  find-phase tuning, stonewall sanity, and `[INVALID]` triage.
- **Cross-Run Comparison** — only emitted when ≥ 2 result directories
  exist under `results/`. A small table comparing Bandwidth / IOPS /
  TOTAL across runs, with the current run marked with an arrow.

Heuristic suggestions are intentionally conservative — they will not
recommend changes that would invalidate the IO500 score (e.g. lowering
`stonewall-time` below 300 s). Treat them as a starting point, not a
prescription.

## Regenerating an existing report

The report file is named deterministically from the run's timestamp and
label, so re-running the script overwrites the existing report:

```bash
# Was generated with claude; want a deterministic chart-based version:
bash scripts/generate-report.sh --no-claude results/20260518T152012Z-pre-maint
```

If you want both, copy the existing `report-*.md` to a different name
first.

## Troubleshooting

- **`ERROR: <dir> is missing result_summary.txt`** — the path you passed
  is not an io500 results directory, or the run failed before producing
  a summary. Check `io500.stdout` / `io500.stderr` in that directory.
- **`claude -p` failed during report generation** — the bash script
  saves stderr to `/tmp/claude-err.<pid>` and leaves a stub in the
  report. Common causes: no Claude credentials, network blocked on a
  compute node. Retry from a login node or use `--no-claude`.
- **Python path runs but no chart** — matplotlib was not importable.
  Run via `pixi run …` instead of system `python3`, or `pixi install`
  first.
- **`module load pixi/.0.68.1` says "no such module"** — your shell may
  not have Lmod sourced. Try `source /etc/profile.d/lmod.sh` first, or
  open a fresh login shell.

## Related

- `docs/running.md` — how to launch the benchmark in the first place.
- `docs/interpreting-results.md` — what the individual phases mean.
- `docs/install.md` — building io500 itself.
