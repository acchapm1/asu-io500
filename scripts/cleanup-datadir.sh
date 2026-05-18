#!/usr/bin/env bash
#SBATCH --job-name=io500-cleanup
#SBATCH --output=%x-%j.out
#SBATCH --error=%x-%j.err
#SBATCH --partition=htc
#SBATCH --qos=public
#SBATCH --nodes=10
#SBATCH --ntasks-per-node=8
#SBATCH -c 1
#SBATCH --time=02:00:00
#
# Parallel cleanup of an io500 datadir on BeeGFS.
#
# Submit with:
#
#   sbatch scripts/cleanup-datadir.sh <timestamp>
#   sbatch scripts/cleanup-datadir.sh latest
#
# <timestamp> is the subdirectory name under $DATADIR_ROOT (default:
# /scratch/acchapm1/io/io500-bench), e.g. "2026.05.15-21.14.17".
# "latest" resolves to the most-recently-modified subdir.
#
# How it works: each MPI rank takes a modulo-N slice of the depth-2
# entries under the target dir (per-rank mdtest trees, per-rank ior
# files, etc.) and rm -rf's its slice in parallel. A final serial
# rm -rf catches the top level (ior-hard's shared file, empty dirs,
# stragglers).
#
# Tune --nodes / --ntasks-per-node to the scale you ran. Cleanup is
# metadata-bound, not CPU-bound, so more ranks usually wins -- but
# don't oversubscribe the BeeGFS metadata server beyond what your
# benchmark already pushed.

set -euo pipefail

DATADIR_ROOT="${DATADIR_ROOT:-/scratch/acchapm1/io/io500-bench}"

TS="${1:-}"
if [[ -z "$TS" ]]; then
  echo "ERROR: pass a timestamp (or 'latest'), e.g.:" >&2
  echo "  sbatch $0 2026.05.15-21.14.17" >&2
  echo "  sbatch $0 latest" >&2
  exit 2
fi

if [[ "$TS" == "latest" ]]; then
  TS="$(ls -1t "$DATADIR_ROOT" 2>/dev/null | head -n1 || true)"
  if [[ -z "$TS" ]]; then
    echo "ERROR: no subdirs found under $DATADIR_ROOT" >&2
    exit 1
  fi
  echo "Resolved 'latest' -> $TS"
fi

TARGET="$DATADIR_ROOT/$TS"
if [[ ! -d "$TARGET" ]]; then
  echo "ERROR: $TARGET does not exist or is not a directory" >&2
  exit 1
fi

# Safety guard: refuse to touch anything that doesn't clearly live under a
# /scratch/.../io500-* tree. Last line of defense against a typo'd $1.
case "$TARGET" in
  /scratch/*/io500-bench/*|/scratch/*/io500-minimal/*|/scratch/*/io500-bench-results/*)
    : ;;
  *)
    echo "ERROR: $TARGET doesn't look like an io500 datadir; refusing." >&2
    exit 1 ;;
esac

# Load MPI.
if ! command -v module >/dev/null 2>&1; then
  for init in /etc/profile.d/lmod.sh /etc/profile.d/modules.sh /usr/share/lmod/lmod/init/bash; do
    [[ -r "$init" ]] && source "$init" && break
  done
fi
module purge
module load openmpi/5.0.8

NTASKS="${SLURM_NTASKS:-1}"

# Snapshot the work list at depth 2 once, here on the launch node. Each rank
# reads the same file and picks its modulo-N share. Using a shared file (on
# BeeGFS, since /tmp may be per-node) so every rank can see it.
WORKLIST="$TARGET/.cleanup-worklist.$$"
trap 'rm -f "$WORKLIST"' EXIT
find "$TARGET" -mindepth 2 -maxdepth 2 -print0 > "$WORKLIST"

ENTRIES="$(tr -cd '\0' < "$WORKLIST" | wc -c)"
echo "=== cleanup ==="
echo "  target:  $TARGET"
echo "  ranks:   $NTASKS"
echo "  entries: $ENTRIES (depth-2)"
echo

START="$(date +%s)"

# Each rank reads the worklist and rm -rf's the entries where (index % size == rank).
mpirun -np "$NTASKS" bash -c '
  set -euo pipefail
  rank="${OMPI_COMM_WORLD_RANK:-${PMI_RANK:-${SLURM_PROCID:-0}}}"
  size="${OMPI_COMM_WORLD_SIZE:-${PMI_SIZE:-${SLURM_NTASKS:-1}}}"
  i=0
  while IFS= read -r -d "" path; do
    if (( i % size == rank )); then
      rm -rf -- "$path"
    fi
    i=$((i+1))
  done < "'"$WORKLIST"'"
'

echo "  parallel sweep: $(( $(date +%s) - START ))s"

# Final serial sweep: top-level files (e.g., the ior-hard shared file lives at
# depth 1) and any now-empty depth-1 subdirs.
SERIAL_START="$(date +%s)"
rm -rf -- "$TARGET"
echo "  serial sweep:   $(( $(date +%s) - SERIAL_START ))s"

echo
echo "=== cleanup complete ==="
echo "removed: $TARGET"
