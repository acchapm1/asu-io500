#!/usr/bin/env bash
#SBATCH --job-name=io500-full-01
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err
#SBATCH --partition=public
#SBATCH --qos=public
#SBATCH --nodes=185
#SBATCH --ntasks-per-node=8
#SBATCH -c 2
#SBATCH --time=12
#SBATCH --exclusive
#SBATCH --reservation=maint
#
# Full-cluster io500 benchmark against configs/asu-beegfs.ini. The
# #SBATCH directives above are intentionally double-commented (##SBATCH)
# because a full-cluster run depends on what the site admins have set
# aside for you: partition, QOS, node count, and wall-clock budget.
#
# Before the first submit, edit this file to uncomment the directives
# and fill in real values, for example:
#
#   #SBATCH --partition=general
#   #SBATCH --qos=public
#   #SBATCH --nodes=128
#   #SBATCH --ntasks-per-node=8
#   #SBATCH -c 2
#   #SBATCH --time=12:00:00
#   #SBATCH --exclusive
#
# Sizing notes:
#   --exclusive is strongly recommended at full scale so nothing else
#     on a node steals CPU or page cache from io500.
#   --time should be at least 4x what the smoke run took (the smoke
#     job hit ~56 min on writes alone and was killed mid-find), with
#     headroom for the read phases on top.
#
# Submit with:
#
#   sbatch scripts/run-full-cluster.sh pre-maint
#   sbatch scripts/run-full-cluster.sh post-maint
#
# Use the same --nodes and config on both sides of the maintenance
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
