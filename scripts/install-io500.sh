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
# IOR's configure.ac requires autoconf >= 2.71; the system autoconf at
# /usr/bin/autoconf on this cluster is older, so we must load the toolchain
# modules explicitly (module purge below wipes the user's environment first).
# Override TOOLCHAIN_MODULES if your site uses different module names.
TOOLCHAIN_MODULES="${TOOLCHAIN_MODULES:-autoconf/2.73 automake/1.17 libtool/2.4.7 make/4.4.1}"

echo "=== io500 install ==="
echo "io500 source     : $IO500_DIR"
echo "MPI module       : $MPI_MODULE"
echo "Toolchain modules: $TOOLCHAIN_MODULES"
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
# Intentionally unquoted so each whitespace-separated module is a separate arg.
module load $TOOLCHAIN_MODULES
module list

if ! command -v mpicc >/dev/null 2>&1; then
  echo "ERROR: mpicc not on PATH after 'module load $MPI_MODULE'" >&2
  exit 1
fi
# Some compiler modules (e.g. gcc/15.2.0, pulled in by openmpi/5.0.8-gcc-*)
# set CC=gcc / CXX=g++. IOR's configure uses AX_PROG_CC_MPI which honors
# $CC, so without overriding we'd build IOR with plain gcc and the
# MPI_Init link test fails. Force the MPI wrappers after modules load.
export CC=mpicc
export CXX=mpicxx
if ! command -v autoreconf >/dev/null 2>&1; then
  echo "ERROR: autoreconf not on PATH after loading $TOOLCHAIN_MODULES" >&2
  exit 1
fi
ac_ver="$(autoconf --version 2>/dev/null | head -n1)"
echo "mpicc:      $(command -v mpicc)"
mpicc --version | head -n1
echo "autoconf:   $ac_ver"
echo "autoreconf: $(command -v autoreconf)"

# pkg.m4 (PKG_CHECK_MODULES) ships with pkg-config at /usr/share/aclocal/
# on this cluster, but loading the automake module replaces aclocal's search
# path with /packages/apps/automake/.../share/aclocal/ and drops the system
# dir. IOR's configure.ac uses PKG_CHECK_MODULES for the CHFS/FINCHFS
# backends; without pkg.m4 those macros pass through unexpanded and the
# nested AC_DEFINE/AC_SUBST trip autoconf's m4_pattern_forbid check
# ("undefined or overquoted macro: AC_DEFINE"). Re-include the system dir.
ACLOCAL_EXTRA_DIR="${ACLOCAL_EXTRA_DIR:-/usr/share/aclocal}"
if [[ -d "$ACLOCAL_EXTRA_DIR" ]]; then
  export ACLOCAL_PATH="$ACLOCAL_EXTRA_DIR${ACLOCAL_PATH:+:$ACLOCAL_PATH}"
  echo "ACLOCAL_PATH: $ACLOCAL_PATH"
else
  echo "WARNING: $ACLOCAL_EXTRA_DIR not found; PKG_CHECK_MODULES may fail" >&2
fi
echo

# Wipe stale autotools state from any prior failed run so autoreconf -f
# regenerates cleanly. prepare.sh keeps the IOR clone but will re-bootstrap.
if [[ -d "$IO500_DIR/build/ior" ]]; then
  rm -rf "$IO500_DIR/build/ior/autom4te.cache" \
         "$IO500_DIR/build/ior/aclocal.m4" \
         "$IO500_DIR/build/ior/configure" 2>/dev/null || true
fi

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
