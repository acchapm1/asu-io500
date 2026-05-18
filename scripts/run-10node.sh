#!/usr/bin/env bash
#SBATCH --job-name=io500-10node
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err
#SBATCH --partition=htc
#SBATCH --qos=public
#SBATCH --nodes=10
#SBATCH --ntasks-per-node=8
#SBATCH -c 2
#SBATCH --time=04:00:00
#SBATCH --exclusive
#SBATCH --reservation=maint
#
# Mid-scale io500 benchmark: 10 nodes x 8 ranks/node = 80 ranks against
# configs/asu-beegfs.ini.
#
# Submit with:
#
#   sbatch scripts/run-10node.sh pre-maint
#   sbatch scripts/run-10node.sh post-maint
#
# Use the same node count and config on both sides of the maintenance
# window so the scores are directly comparable.

set -euo pipefail

LABEL="${1:-}"
if [[ -z "$LABEL" ]]; then
  echo "ERROR: pass a label, e.g.:" >&2
  echo "  sbatch $0 pre-maint" >&2
  exit 2
fi

REPO_DIR="${REPO_DIR:-/home/acchapm1/io/asu-io500}"
exec "$REPO_DIR/scripts/run-io500.sbatch" \
  "$REPO_DIR/configs/asu-beegfs.ini" \
  "$LABEL"
