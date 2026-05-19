#!/usr/bin/env python3
"""Rule-based IO500 report analysis sections.

Invoked by scripts/generate-report.sh when `claude` is unavailable (or
`--no-claude` is passed). Reads an io500 results directory and writes the
"Run Analysis" + "Suggested Improvements" markdown sections to stdout for
the bash wrapper to append. Also writes phases.png into the results dir
(if matplotlib is importable) and a Cross-Run Comparison table (if other
results dirs are present alongside this one).

Usage:
    python scripts/generate-report.py <results-dir>
"""
from __future__ import annotations

import argparse
import configparser
import re
import sys
from dataclasses import dataclass
from pathlib import Path

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    HAS_MPL = True
except ImportError:
    HAS_MPL = False


STONEWALL_DEFAULT = 300.0

# Group phases for the high-level summary. Order matters: matched first wins.
PHASE_GROUPS = {
    "bandwidth-easy": ["ior-easy-write", "ior-easy-read"],
    "bandwidth-hard": ["ior-hard-write", "ior-hard-read"],
    "metadata-easy":  ["mdtest-easy-write", "mdtest-easy-stat", "mdtest-easy-delete"],
    "metadata-hard":  ["mdtest-hard-write", "mdtest-hard-stat",
                       "mdtest-hard-read", "mdtest-hard-delete"],
    "find":           ["find"],
}

# Phases whose write/read time is byte-limited rather than time-limited;
# their elapsed time can legitimately exceed stonewall_time.
WRITE_PHASES = {"ior-easy-write", "ior-hard-write"}


@dataclass
class Phase:
    name: str
    score: float
    unit: str           # "GiB/s" or "kIOPS"
    elapsed: float      # seconds
    invalid: bool       # whether the [RESULT] line had [INVALID]


@dataclass
class RunData:
    phases: list[Phase]
    bandwidth: float | None
    iops: float | None
    total: float | None
    score_line: str | None
    score_invalid: bool


RESULT_RE = re.compile(
    r"^\[(RESULT|INVALID)\]\s+(\S+)\s+([\d.]+)\s+(\S+)\s*:\s*time\s+([\d.]+)\s+seconds",
)
SCORE_RE = re.compile(
    r"^\[SCORE\s*(INVALID)?\s*\]\s*Bandwidth\s+([\d.]+).*?IOPS\s+([\d.]+).*?TOTAL\s+([\d.]+)",
)


def parse_result_summary(path: Path) -> RunData:
    phases: list[Phase] = []
    bandwidth = iops = total = None
    score_line: str | None = None
    score_invalid = False
    for raw in path.read_text().splitlines():
        line = raw.rstrip()
        m = RESULT_RE.match(line)
        if m:
            tag, name, score, unit, elapsed = m.groups()
            phases.append(Phase(
                name=name,
                score=float(score),
                unit=unit,
                elapsed=float(elapsed),
                invalid=(tag == "INVALID"),
            ))
            continue
        m = SCORE_RE.match(line)
        if m:
            score_line = line
            invalid_marker, bw, io, tot = m.groups()
            score_invalid = bool(invalid_marker)
            bandwidth, iops, total = float(bw), float(io), float(tot)
    return RunData(phases, bandwidth, iops, total, score_line, score_invalid)


def parse_metadata(path: Path) -> dict[str, str]:
    md: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        if ":" in raw and not raw.startswith("==="):
            k, _, v = raw.partition(":")
            md[k.strip()] = v.strip()
    return md


def parse_config(path: Path | None) -> configparser.ConfigParser:
    cfg = configparser.ConfigParser(strict=False, interpolation=None)
    if path and path.is_file():
        cfg.read(path)
    return cfg


def stonewall_time(cfg: configparser.ConfigParser) -> float:
    if cfg.has_option("debug", "stonewall-time"):
        try:
            return float(cfg.get("debug", "stonewall-time"))
        except ValueError:
            pass
    return STONEWALL_DEFAULT


def fmt_phase(p: Phase) -> str:
    return f"`{p.name}` ({p.score:.3f} {p.unit}, {p.elapsed:.0f} s)"


def write_chart(run: RunData, out_path: Path) -> bool:
    """Render a horizontal bar chart of phase scores. Bandwidth and metadata
    phases use separate subplots since they have different units."""
    if not HAS_MPL or not run.phases:
        return False
    bw = [p for p in run.phases if p.unit.endswith("/s")]
    md = [p for p in run.phases if "IOPS" in p.unit]
    if not bw and not md:
        return False

    n_plots = (1 if bw else 0) + (1 if md else 0)
    fig, axes = plt.subplots(n_plots, 1, figsize=(8, 1.0 + 0.4 * len(run.phases)))
    if n_plots == 1:
        axes = [axes]

    idx = 0
    if bw:
        ax = axes[idx]; idx += 1
        names = [p.name for p in bw]
        scores = [p.score for p in bw]
        ax.barh(names, scores, color="#3b82f6")
        ax.set_xlabel(f"Score ({bw[0].unit})")
        ax.set_title("Bandwidth phases")
        ax.invert_yaxis()
        for i, p in enumerate(bw):
            ax.text(p.score, i, f" {p.score:.2f}", va="center", fontsize=8)
    if md:
        ax = axes[idx]
        names = [p.name for p in md]
        scores = [p.score for p in md]
        ax.barh(names, scores, color="#10b981")
        ax.set_xlabel(f"Score ({md[0].unit})")
        ax.set_title("Metadata + find phases")
        ax.invert_yaxis()
        for i, p in enumerate(md):
            ax.text(p.score, i, f" {p.score:.2f}", va="center", fontsize=8)

    fig.tight_layout()
    fig.savefig(out_path, dpi=110)
    plt.close(fig)
    return True


def find_phase(run: RunData, name: str) -> Phase | None:
    for p in run.phases:
        if p.name == name:
            return p
    return None


def render_analysis(run: RunData, md: dict[str, str], cfg: configparser.ConfigParser) -> str:
    """Two short paragraphs of prose describing this specific run."""
    sw = stonewall_time(cfg)
    nodes = md.get("slurm_nnodes", "?")
    ranks = md.get("slurm_ntasks", "?")

    if not run.phases:
        return (
            "_No `[RESULT]` lines were found in `result_summary.txt`. The run\n"
            "likely failed before any phase reported a score — check\n"
            "`io500.stderr` for the underlying error._\n"
        )

    longest = max(run.phases, key=lambda p: p.elapsed)
    total_time = sum(p.elapsed for p in run.phases)
    invalid_phases = [p for p in run.phases if p.invalid]

    # Score commentary
    if run.score_line is None:
        score_para = (
            "The run did not produce a `[SCORE]` line, so no aggregate is "
            "available — the harness likely killed it before the final "
            "phase completed."
        )
    elif run.score_invalid:
        score_para = (
            f"The final score line is **`[SCORE INVALID]`** "
            f"(TOTAL {run.total:.3f}). This usually means `stonewall-time` "
            f"was lowered below 300 s (here: {sw:.0f} s), or a phase reported "
            f"`[INVALID]`. The number is fine as a smoke test but cannot be "
            f"submitted as a benchmark result."
        )
    else:
        score_para = (
            f"Final score: **TOTAL {run.total:.3f}** "
            f"(Bandwidth {run.bandwidth:.3f} GiB/s, IOPS {run.iops:.3f} kIOPS). "
            f"The TOTAL is the geometric mean of the bandwidth and IOPS legs, "
            f"so neither side can be hidden by the other."
        )

    # What dominated
    pct = 100.0 * longest.elapsed / total_time if total_time else 0.0
    dom_para = (
        f"Across {nodes} nodes / {ranks} ranks, the run spent ~{total_time:.0f} s "
        f"of phase time total, dominated by {fmt_phase(longest)} at {pct:.0f}% "
        f"of that. "
    )

    iew = find_phase(run, "ior-easy-write")
    ihw = find_phase(run, "ior-hard-write")
    if iew and ihw and ihw.score > 0:
        ratio = iew.score / ihw.score
        dom_para += (
            f"Easy/hard write bandwidth ratio is {ratio:.0f}× "
            f"({iew.score:.2f} vs {ihw.score:.2f} GiB/s), so 47008-byte "
            f"transfers cost roughly {ratio:.0f}× more per byte than 2 MiB "
            f"transfers on this filesystem. "
        )

    if invalid_phases:
        names = ", ".join(f"`{p.name}`" for p in invalid_phases)
        dom_para += (
            f"⚠ The following phases were marked `[INVALID]`: {names}. "
            f"They contribute zero to the aggregate score."
        )

    # Phases that finished well under stonewall — count-limited, not time-limited.
    short = [
        p for p in run.phases
        if p.name not in WRITE_PHASES
        and p.name != "find"
        and p.elapsed < sw * 0.5
    ]
    if short:
        items = ", ".join(fmt_phase(p) for p in short)
        short_para = (
            f"Several read/stat/delete phases finished well under the {sw:.0f} s "
            f"stonewall — {items}. These hit the dataset size cap (`n` / "
            f"`segmentCount` / `blockSize`) instead of the time cap, so their "
            f"scores are bounded by how much data the preceding write phase "
            f"laid down. "
        )
    else:
        short_para = ""

    return f"{score_para}\n\n{dom_para}\n\n{short_para}".strip() + "\n"


def render_suggestions(run: RunData, cfg: configparser.ConfigParser) -> list[str]:
    """Rule-based suggested improvements, ordered by expected impact."""
    sw = stonewall_time(cfg)
    bullets: list[tuple[int, str]] = []  # (priority, text); lower priority = higher impact

    if not run.phases:
        return ["No `[RESULT]` phases were captured, so no actionable suggestions can be derived. Inspect `io500.stderr` and re-run."]

    iew = find_phase(run, "ior-easy-write")
    ihw = find_phase(run, "ior-hard-write")
    mhw = find_phase(run, "mdtest-hard-write")
    mew = find_phase(run, "mdtest-easy-write")
    find_p = find_phase(run, "find")

    # 1. ior-hard write small-IO bottleneck — usually the biggest single win.
    if ihw and ihw.score < 1.0:
        bullets.append((1, (
            f"**Investigate ior-hard write bottleneck** — only "
            f"{ihw.score:.2f} GiB/s on 47008-byte transfers, vs "
            f"{iew.score:.2f} GiB/s on 2 MiB transfers (`ior-easy`). Try a "
            f"larger BeeGFS `chunksize`, raise the stripe count for the "
            f"ior-hard datadir with `beegfs-ctl --setpattern`, or "
            f"investigate small-IO coalescing on the OSS side."
        )))

    # 2. mdtest-hard write — common metadata-target saturation tell.
    if mhw and mew and mhw.score > 0 and mew.score / mhw.score > 4:
        bullets.append((2, (
            f"**Add BeeGFS metadata targets** — `mdtest-hard-write` is "
            f"{mhw.score:.2f} kIOPS vs `mdtest-easy-write` at "
            f"{mew.score:.2f} kIOPS (a {mew.score/mhw.score:.0f}× gap). "
            f"Shared-directory metadata typically scales with the number "
            f"of metadata targets; the easy/hard gap is the classic sign "
            f"that the hard phase is funneling through too few MDTs."
        )))

    # 3. Count-limited phases — raise dataset size knobs.
    count_limited = [
        p for p in run.phases
        if p.name not in WRITE_PHASES and p.name != "find" and p.elapsed < sw * 0.5
    ]
    if count_limited:
        knob_for = {
            "ior-easy-read":       "`[ior-easy] blockSize`",
            "ior-hard-read":       "`[ior-hard] segmentCount`",
            "ior-rnd4K-easy-read": "`[ior-easy] blockSize`",
            "mdtest-easy-stat":    "`[mdtest-easy] n`",
            "mdtest-easy-delete":  "`[mdtest-easy] n`",
            "mdtest-hard-stat":    "`[mdtest-hard] n`",
            "mdtest-hard-read":    "`[mdtest-hard] n`",
            "mdtest-hard-delete":  "`[mdtest-hard] n`",
        }
        names = ", ".join(
            f"`{p.name}` ({p.elapsed:.0f} s, knob: {knob_for.get(p.name, '?')})"
            for p in count_limited
        )
        bullets.append((3, (
            f"**Raise dataset-size knobs for count-limited phases** — "
            f"these phases finished well under the {sw:.0f} s stonewall and "
            f"so were capped by dataset size, not time: {names}. Bumping the "
            f"matching `n` / `segmentCount` / `blockSize` lets stonewall do "
            f"its job and gives a more honest score. Remember: a change here "
            f"invalidates pre-vs-post comparability, so re-run **both** halves."
        )))

    # 4. find phase
    if find_p and find_p.elapsed > 120:
        bullets.append((4, (
            f"**Tune the find phase** — `find` ran {find_p.elapsed:.0f} s at "
            f"{find_p.score:.0f} kIOPS. Try raising `pfind-queue-length` above "
            f"its current value and setting `pfind-steal-next = TRUE` so idle "
            f"workers steal directories instead of stalling."
        )))
    elif find_p and find_p.elapsed < 30:
        # find finished extremely fast — likely the dataset shrank
        bullets.append((5, (
            f"**Check find dataset size** — `find` finished in only "
            f"{find_p.elapsed:.0f} s. That is suspiciously fast and usually "
            f"means the prior mdtest phases laid down fewer files than expected. "
            f"Cross-check `mdtest-easy` / `mdtest-hard` `n` against the "
            f"phase elapsed times — if they too are count-limited, the find "
            f"phase has very little to do."
        )))

    # 5. Stonewall sanity check.
    if sw < 300:
        bullets.append((1, (
            f"**Restore `stonewall-time = 300`** — current config uses "
            f"{sw:.0f} s, which produces `[SCORE INVALID]`. This is fine for "
            f"a smoke test but the pre/post-maintenance comparison needs the "
            f"300 s minimum to be a valid IO500 result."
        )))

    # 6. INVALID phases.
    invalid = [p for p in run.phases if p.invalid]
    if invalid:
        names = ", ".join(f"`{p.name}`" for p in invalid)
        bullets.append((1, (
            f"**Fix the `[INVALID]` phases** ({names}) — they contribute "
            f"zero to the aggregate. Check `io500.stderr` and the per-phase "
            f"`.txt` / `.csv` files in the results dir for the underlying "
            f"reason (often: stonewall not reached, or the per-phase "
            f"validator rejected the run)."
        )))

    # 7. Generic fallback so we always have something.
    if len(bullets) < 4:
        bullets.append((9, (
            "**Capture per-phase OSS/MDS utilization** — none of the existing "
            "result files include filesystem-side counters. Wrap the next run "
            "with a `beegfs-ctl --serverstats` poller or `sar -d` on each "
            "OSS so we can tell whether a poor score is the client side or "
            "the storage side."
        )))

    bullets.sort(key=lambda b: b[0])
    # Cap at 6 to match the prompt the Claude path uses.
    return [text for _, text in bullets[:6]]


def render_comparison(this_dir: Path) -> str | None:
    """If `<this_dir>/..` holds other result dirs with valid score lines,
    return a markdown table comparing them."""
    results_root = this_dir.parent
    if not results_root.is_dir():
        return None

    rows: list[tuple[Path, RunData, dict[str, str]]] = []
    for sub in sorted(results_root.iterdir()):
        if not sub.is_dir() or sub.name == "old":
            continue
        rs = sub / "result_summary.txt"
        rm = sub / "run-metadata.txt"
        if not rs.is_file() or not rm.is_file():
            continue
        try:
            run = parse_result_summary(rs)
            meta = parse_metadata(rm)
        except Exception:
            continue
        rows.append((sub, run, meta))

    if len(rows) < 2:
        return None

    lines = [
        "## Cross-Run Comparison",
        "",
        f"Found {len(rows)} result directories under `{results_root}`. "
        "TOTAL is the geometric mean of Bandwidth and IOPS scores.",
        "",
        "| Run | Nodes | Ranks | Bandwidth (GiB/s) | IOPS (kIOPS) | TOTAL | Valid |",
        "|---|---:|---:|---:|---:|---:|:---:|",
    ]
    for sub, run, meta in rows:
        marker = "←" if sub.resolve() == this_dir.resolve() else ""
        valid = "no" if (run.score_invalid or run.score_line is None) else "yes"
        bw = f"{run.bandwidth:.3f}" if run.bandwidth is not None else "—"
        io = f"{run.iops:.3f}" if run.iops is not None else "—"
        tot = f"{run.total:.3f}" if run.total is not None else "—"
        lines.append(
            f"| `{sub.name}` {marker} "
            f"| {meta.get('slurm_nnodes', '?')} "
            f"| {meta.get('slurm_ntasks', '?')} "
            f"| {bw} | {io} | {tot} | {valid} |"
        )
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("results_dir", type=Path,
                    help="path to results/<UTC-ts>-<label>/")
    ap.add_argument("--no-charts", action="store_true",
                    help="skip phases.png even if matplotlib is available")
    ap.add_argument("--no-comparison", action="store_true",
                    help="skip the Cross-Run Comparison table")
    args = ap.parse_args()

    d = args.results_dir.resolve()
    rs = d / "result_summary.txt"
    rm = d / "run-metadata.txt"
    cu = d / "config-used.ini"

    for required in (rs, rm):
        if not required.is_file():
            print(f"ERROR: {d} is missing {required.name} — doesn't look like an io500 results dir",
                  file=sys.stderr)
            return 1

    run = parse_result_summary(rs)
    meta = parse_metadata(rm)
    cfg = parse_config(cu if cu.is_file() else None)

    out: list[str] = []

    chart_ok = False
    if not args.no_charts:
        chart_path = d / "phases.png"
        chart_ok = write_chart(run, chart_path)

    out.append("## Run Analysis")
    out.append("")
    out.append(render_analysis(run, meta, cfg))
    if chart_ok:
        out.append("")
        out.append("![Per-phase scores](phases.png)")
        out.append("")
    elif not args.no_charts and not HAS_MPL:
        out.append("")
        out.append("_(Per-phase chart skipped: matplotlib not importable. "
                   "Install via `pixi install` and re-run for `phases.png`.)_")
        out.append("")

    out.append("## Suggested Improvements")
    out.append("")
    bullets = render_suggestions(run, cfg)
    for b in bullets:
        out.append(f"- {b}")
    out.append("")
    out.append("_(Heuristic analysis — generated by `scripts/generate-report.py`, "
               "no LLM in the loop.)_")
    out.append("")

    if not args.no_comparison:
        cmp_md = render_comparison(d)
        if cmp_md:
            out.append("")
            out.append(cmp_md)

    sys.stdout.write("\n".join(out))
    if not out[-1].endswith("\n"):
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
