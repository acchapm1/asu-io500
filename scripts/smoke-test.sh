#!/bin/bash
#SBATCH --job-name=io500-smoke
#SBATCH --output=logs/%x-%j.out
#SBATCH --error=logs/%x-%j.err
#SBATCH --partition=htc
#SBATCH --qos=public
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=8
#SBATCH -c 2
#SBATCH --time=02:00:00
#SBATCH --reservation=maint
#SBATCH --exclusive

#
# Smoke test for the io500 harness. Submit with:
#
#   sbatch scripts/smoke-test.sh
#
# Delegates the actual run to run-io500.sbatch with the minimal config.
# The previous smoke run with --time=01:00:00 was killed by SLURM mid-find
# phase, so this script asks for 2 hours.

set -euo pipefail

REPO_DIR="${REPO_DIR:-/home/acchapm1/io/asu-io500}"
exec "$REPO_DIR/scripts/run-io500.sbatch" \
  "$REPO_DIR/configs/config-minimal.ini" \
  pre-maint-smoke
