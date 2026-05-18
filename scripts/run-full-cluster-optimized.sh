#!/usr/bin/env bash
#SBATCH --job-name=io500-full-opt
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err
#SBATCH --partition=public
#SBATCH --qos=public
#SBATCH --nodes=185
#SBATCH --ntasks-per-node=16
#SBATCH -c 2
#SBATCH --time=12:00:00
#SBATCH --exclusive
#SBATCH --reservation=maint
#
# Full-cluster io500 benchmark, OPTIMIZED variant. Differs from
# run-full-cluster.sh in two ways:
#   - --ntasks-per-node suggestion bumped from 8 to 16 to attack the
#     hard-metadata bottleneck.
#   - Uses configs/asu-beegfs-optimized.ini, which right-sizes the
#     stonewall budgets.
#
# !!! READ BEFORE SUBMITTING !!!
# The 16-rpn bump is an extrapolation from the 10-node optimized run.
# At full-cluster scale (e.g. 185 nodes x 16 rpn = 2960 ranks), the
# BeeGFS MDS may saturate before 16 rpn beats 8 rpn. Compare this
# run against the unoptimized full-cluster baseline FIRST; if any
# mdtest-hard-* score regresses, dial rpn back to 12 or 8 here. See
# TODO-After.md.
#
# Like run-full-cluster.sh, the #SBATCH directives above are
# placeholders (##SBATCH). Before the first submit, edit this file
# to fill in real values for your allocation, e.g.:
#
#   #SBATCH --partition=general
#   #SBATCH --qos=public
#   #SBATCH --nodes=185
#   #SBATCH --ntasks-per-node=16
#   #SBATCH -c 2
#   #SBATCH --time=12:00:00
#   #SBATCH --exclusive
#
# Submit with:
#
#   sbatch scripts/run-full-cluster-optimized.sh baseline-optimized-v1

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
