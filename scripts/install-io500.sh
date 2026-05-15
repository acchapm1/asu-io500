#!/usr/bin/env bash
# Build io500 and its dependencies (IOR, mdtest, pfind) against openmpi/5.0.8.
#
# Usage: bash scripts/install-io500.sh
#
# Idempotent: prepare.sh skips already-cloned deps; make rebuilds only what changed.
# Run this once on the head node (or inside an interactive allocation) before
# the first benchmark. Re-run after pulling a new io500 commit.

set -euo pipefail

IO500_DIR="${IO500_DIR:-/home/acchapm1/io/io500}"
MPI_MODULE="${MPI_MODULE:-openmpi/5.0.8}"

echo "=== io500 install ==="
echo "io500 source : $IO500_DIR"
echo "MPI module   : $MPI_MODULE"
echo

if [[ ! -d "$IO500_DIR" ]]; then
  echo "ERROR: io500 source not found at $IO500_DIR" >&2
  exit 1
fi

# Load the MPI module so mpicc is on PATH for IOR/mdtest's autoconf.
# 'module' is a shell function defined by Lmod; source the init file if needed.
if ! command -v module >/dev/null 2>&1; then
  for init in /etc/profile.d/lmod.sh /etc/profile.d/modules.sh /usr/share/lmod/lmod/init/bash; do
    [[ -r "$init" ]] && source "$init" && break
  done
fi
if ! command -v module >/dev/null 2>&1; then
  echo "ERROR: 'module' command not available; cannot load $MPI_MODULE" >&2
  exit 1
fi

module purge
module load "$MPI_MODULE"
module list

if ! command -v mpicc >/dev/null 2>&1; then
  echo "ERROR: mpicc not on PATH after 'module load $MPI_MODULE'" >&2
  exit 1
fi
echo "mpicc: $(command -v mpicc)"
mpicc --version | head -n1
echo

cd "$IO500_DIR"

echo "=== running ./prepare.sh ==="
./prepare.sh

echo
echo "=== running make ==="
make -j"${NPROC:-$(nproc 2>/dev/null || echo 4)}"

echo
echo "=== build complete ==="
ls -lh "$IO500_DIR/io500" "$IO500_DIR/io500-verify" 2>/dev/null || true
echo
echo "Try: $IO500_DIR/io500 --list | head"
