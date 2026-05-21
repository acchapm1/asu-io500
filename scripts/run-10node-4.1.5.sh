#!/usr/bin/env bash
#SBATCH --job-name=io500-10node-4.1.5
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err
#SBATCH --partition=htc
#SBATCH --qos=public
#SBATCH --nodes=10
##SBATCH -w 'sc[003-112]'
#SBATCH --ntasks-per-node=16
#SBATCH -c 2
#SBATCH --time=02:00:00
#SBATCH --reservation=maint
#SBATCH --exclusive
#
# Mid-scale io500 benchmark using the openmpi/4.1.5 (NVIDIA HPCX 2.13.1)
# build at /home/acchapm1/io/io500-4.1.5. 10 nodes x 16 ranks/node = 160 ranks
# against configs/asu-beegfs.ini.
#
# Submit with:
#
#   sbatch scripts/run-10node-4.1.5.sh pre-maint-4.1.5
#   sbatch scripts/run-10node-4.1.5.sh post-maint-4.1.5
#
# Use the same node count and config on both sides of the maintenance
# window so the scores are directly comparable.

set -euo pipefail

LABEL="${1:-}"
if [[ -z "$LABEL" ]]; then
  echo "ERROR: pass a label, e.g.:" >&2
  echo "  sbatch $0 pre-maint-4.1.5" >&2
  exit 2
fi

REPO_DIR="${REPO_DIR:-/home/acchapm1/io/asu-io500}"
exec "$REPO_DIR/scripts/run-io500-4.1.5.sbatch" \
  "$REPO_DIR/configs/asu-beegfs.ini" \
  "$LABEL"
