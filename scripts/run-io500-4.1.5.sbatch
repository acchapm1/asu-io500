#!/usr/bin/env bash
#SBATCH --job-name=io500-4.1.5
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err
#SBATCH --partition=htc
#SBATCH --qos=public
#SBATCH --nodes=10
#SBATCH --ntasks-per-node=16
#SBATCH -c 2
#SBATCH --time=03:00:00
#SBATCH --exclusive
#
# Usage:
#   sbatch scripts/run-io500-4.1.5.sbatch <config.ini> <label>
#
# Examples:
#   sbatch scripts/run-io500-4.1.5.sbatch configs/config-minimal.ini pre-maint-smoke-4.1.5
#   sbatch scripts/run-io500-4.1.5.sbatch configs/asu-beegfs.ini pre-maint-4.1.5
#
# This is the openmpi/4.1.5 (NVIDIA HPCX 2.13.1) variant of run-io500.sbatch.
# It points at /home/acchapm1/io/io500-4.1.5 — a separate io500 build linked
# against the HPCX-bundled 4.1.5 stack — so it can be run side-by-side with
# the 5.0.8 build without cross-contaminating result dirs or LD paths.
#
# What this does:
#   1. Loads openmpi/4.1.5.
#   2. Creates results/<UTC-ts>-<label>/ in this repo and snapshots provenance
#      (module list, lscpu, BeeGFS info, the config).
#   3. Runs io500 via mpirun across the SLURM allocation.
#   4. Copies io500's own results directory (timestamped) into results/<...>/
#      so result.txt + result_summary.txt are committed to git.

set -euo pipefail

CONFIG="${1:-}"
LABEL="${2:-run}"

if [[ -z "$CONFIG" || ! -s "$CONFIG" ]]; then
  echo "ERROR: pass a config file as arg 1, e.g.:" >&2
  echo "  sbatch $0 configs/config-minimal.ini pre-maint-smoke-4.1.5" >&2
  exit 2
fi

REPO_DIR="${REPO_DIR:-/home/acchapm1/io/asu-io500}"
IO500_DIR="${IO500_DIR:-/home/acchapm1/io/io500-4.1.5}"
IO500_BIN="$IO500_DIR/io500"
MPI_MODULE="${MPI_MODULE:-openmpi/4.1.5}"
# openmpi/4.1.5 is HPCX-bundled (2.13.1) and already sets LD_LIBRARY_PATH for
# hcoll, so the fallback below is normally a no-op. Kept for parity with the
# 5.0.8 sbatch and so a future HPCX module reshuffle still resolves cleanly.
HCOLL_FALLBACK_DIR="${HCOLL_FALLBACK_DIR:-/packages/apps/hpcx/2.13.1/hcoll/lib}"

if [[ ! -x "$IO500_BIN" ]]; then
  echo "ERROR: $IO500_BIN not built. Run scripts/install-io500.sh first" >&2
  echo "       (with IO500_DIR=$IO500_DIR MPI_MODULE=$MPI_MODULE)." >&2
  exit 1
fi

# Resolve config to absolute path so cwd changes don't break it.
CONFIG_ABS="$(readlink -f -- "$CONFIG")"

# Per-run output dir inside the repo.
TS="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$REPO_DIR/results/${TS}-${LABEL}"
mkdir -p "$RUN_DIR"

# Load MPI.
if ! command -v module >/dev/null 2>&1; then
  for init in /etc/profile.d/lmod.sh /etc/profile.d/modules.sh /usr/share/lmod/lmod/init/bash; do
    [[ -r "$init" ]] && source "$init" && break
  done
fi
module purge
module load "$MPI_MODULE"

# Same logic as the 5.0.8 sbatch: add libmpi's RUNPATH to LD_LIBRARY_PATH so
# transitive NEEDED libs (libhcoll/libocoms) resolve at runtime. For
# HPCX-bundled 4.1.5 the module already prepends these dirs to
# LD_LIBRARY_PATH, so both branches below are typically no-ops — they only
# kick in if the module layout ever changes and stops covering them.
if command -v mpicc >/dev/null 2>&1 && command -v readelf >/dev/null 2>&1; then
  _libmpi_dir=$(mpicc --showme:libdirs 2>/dev/null | awk '{print $1}')
  _libmpi_so=$(ls "$_libmpi_dir"/libmpi.so* 2>/dev/null | head -n1)
  if [[ -n "$_libmpi_so" ]]; then
    _rp=$(readelf -d "$_libmpi_so" 2>/dev/null \
      | awk -F'[][]' '/RUNPATH|RPATH/{print $2; exit}')
    if [[ -n "$_rp" ]]; then
      export LD_LIBRARY_PATH="${_rp}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      echo "libmpi RUNPATH added to LD_LIBRARY_PATH: $_rp"
    fi
    if readelf -d "$_libmpi_so" 2>/dev/null \
         | grep -qE 'NEEDED.*lib(hcoll|ocoms)' \
       && [[ -d "$HCOLL_FALLBACK_DIR" ]]; then
      case ":${LD_LIBRARY_PATH:-}:" in *":$HCOLL_FALLBACK_DIR:"*) :;;
        *) export LD_LIBRARY_PATH="${HCOLL_FALLBACK_DIR}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
           echo "HCOLL fallback added to LD_LIBRARY_PATH: $HCOLL_FALLBACK_DIR" ;;
      esac
    fi
  fi
fi

# Provenance snapshot (best-effort).
{
  echo "=== run metadata ==="
  echo "timestamp_utc: $TS"
  echo "label:         $LABEL"
  echo "config:        $CONFIG_ABS"
  echo "io500_bin:     $IO500_BIN"
  echo "mpi_module:    $MPI_MODULE"
  echo "host:          $(hostname)"
  echo "slurm_job_id:  ${SLURM_JOB_ID:-N/A}"
  echo "slurm_nodelist: ${SLURM_JOB_NODELIST:-N/A}"
  echo "slurm_ntasks:  ${SLURM_NTASKS:-N/A}"
  echo "slurm_ntasks_per_node: ${SLURM_NTASKS_PER_NODE:-N/A}"
  echo "slurm_nnodes:  ${SLURM_NNODES:-N/A}"
} > "$RUN_DIR/run-metadata.txt"

cp -- "$CONFIG_ABS" "$RUN_DIR/config-used.ini"

{ module list; } >"$RUN_DIR/module-list.txt" 2>&1 || true
lscpu                 >"$RUN_DIR/lscpu.txt"        2>&1 || true
uname -a              >"$RUN_DIR/uname.txt"        2>&1 || true
df -hT /scratch/acchapm1/io >"$RUN_DIR/df.txt"     2>&1 || true
mount | grep -i beegfs     >"$RUN_DIR/mount-beegfs.txt" 2>&1 || true
beegfs-ctl --listtargets   >"$RUN_DIR/beegfs-targets.txt" 2>&1 || true
beegfs-net                 >"$RUN_DIR/beegfs-net.txt"     2>&1 || true

# Launch. io500 must run from its own dir so relative paths to bin/ resolve.
NTASKS="${SLURM_NTASKS:-2}"
echo "=== launching: mpirun -np $NTASKS $IO500_BIN $CONFIG_ABS ==="

cd "$IO500_DIR"
mpirun -np "$NTASKS" "$IO500_BIN" "$CONFIG_ABS" \
  2> >(tee "$RUN_DIR/io500.stderr" >&2) \
  | tee "$RUN_DIR/io500.stdout"

# Copy io500's results dir into the repo run dir. io500 prints its own
# resultdir near the end of stdout, e.g.:
#   "The result files are stored in the directory: <path>"
# Parsing that is the only reliable way, because the config may override
# `resultdir` (asu-beegfs.ini does); guessing $IO500_DIR/results/ would
# pick up stale dirs from earlier runs whose configs didn't override it.
IO500_RESULT_DIR="$(sed -n 's|^The result files are stored in the directory: ||p' \
                       "$RUN_DIR/io500.stdout" | tail -n1 | tr -d '\r')"

if [[ -z "$IO500_RESULT_DIR" ]]; then
  # Fallback: io500 didn't print the line (crash, kill, or version skew).
  # Use the newest dir under $IO500_DIR/results/ as a last-ditch guess and warn.
  IO500_RESULT_DIR="$(ls -1dt "$IO500_DIR"/results/*/ 2>/dev/null | head -n1 || true)"
  [[ -n "$IO500_RESULT_DIR" ]] && \
    echo "WARNING: couldn't parse result-dir from io500 stdout; falling back to $IO500_RESULT_DIR" >&2
fi

if [[ -n "$IO500_RESULT_DIR" && -d "$IO500_RESULT_DIR" ]]; then
  cp -rf -- "$IO500_RESULT_DIR"/* "$RUN_DIR/"
  echo "Copied $IO500_RESULT_DIR -> $RUN_DIR/"
else
  echo "WARNING: no io500 results dir found to copy (looked in stdout and $IO500_DIR/results/)" >&2
fi

echo
echo "=== run complete ==="
echo "Output: $RUN_DIR"
ls -la "$RUN_DIR"
