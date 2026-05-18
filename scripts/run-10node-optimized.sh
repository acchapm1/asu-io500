#!/usr/bin/env bash
#SBATCH --job-name=io500-10node-opt
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err
#SBATCH --partition=htc
#SBATCH --qos=public
#SBATCH --nodes=10
#SBATCH --ntasks-per-node=16
#SBATCH -c 2
#SBATCH --time=04:00:00
#SBATCH --reservation=maint
##SBATCH --exclusive
#
# Mid-scale io500 benchmark, OPTIMIZED variant. Differs from
# run-10node.sh in two ways:
#   - --ntasks-per-node bumped from 8 to 16 (160 total ranks instead
#     of 80) to attack the hard-metadata bottleneck observed in the
#     pre-maint baseline.
#   - Uses configs/asu-beegfs-optimized.ini, which right-sizes the
#     stonewall budgets so phases exit near 300 s instead of dragging
#     to 700-800 s.
#
# NOT for the pre/post-maintenance comparison -- that pair must use
# the unchanged run-10node.sh + asu-beegfs.ini. Use this script as
# the new baseline for future benchmark seasons. See TODO-After.md.
#
# Submit with:
#
#   sbatch scripts/run-10node-optimized.sh baseline-optimized-v1
#
# Use the same --nodes, --ntasks-per-node, and config on every
# subsequent run if you want them comparable to this baseline.

set -euo pipefail

LABEL="${1:-}"
if [[ -z "$LABEL" ]]; then
  echo "ERROR: pass a label, e.g.:" >&2
  echo "  sbatch $0 baseline-optimized-v1" >&2
  exit 2
fi

REPO_DIR="${REPO_DIR:-/home/acchapm1/io/asu-io500}"
exec "$REPO_DIR/scripts/run-io500.sbatch" \
  "$REPO_DIR/configs/asu-beegfs-optimized.ini" \
  "$LABEL"
