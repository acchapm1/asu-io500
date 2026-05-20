# Open MPI / HCOLL / OCOMS findings on Sol

Investigated 2026-05-19 / 2026-05-20 while triaging the failed 10-node
optimized run (SLURM job 53015606) and the follow-up "`./io500 -h`:
`libocoms.so.0`: cannot open shared object file" report.

This document records what each Open MPI module on the cluster actually
links against, why the original io500 binary worked pre-maintenance and
broke post-maintenance, and the recipes that make io500 build and run
reliably against any of them.

## TL;DR

- The harness now defaults to **`openmpi/5.0.8`** (bare) plus a
  hard-coded HPC-X hcoll fallback (`/packages/apps/hpcx/2.25.1/doca/hcoll/lib`)
  injected into `LIBRARY_PATH` (build) and `LD_LIBRARY_PATH` (runtime)
  by `scripts/install-io500.sh` and `scripts/run-io500.sbatch`. The
  default and the fallback dir are both overridable via env vars.
- For **interactive** use of the resulting binary, run:

  ```bash
  module purge && module load openmpi/5.0.8
  export LD_LIBRARY_PATH=/packages/apps/hpcx/2.25.1/doca/hcoll/lib:$LD_LIBRARY_PATH
  /home/acchapm1/io/io500/io500 -h
  ```

  Or `sbatch` any of `scripts/{smoke-test,run-io500,run-10node-optimized}.sh`
  — the LD path is injected automatically by the sbatch script.

- **`openmpi/4.1.5`** is the only fully self-contained option on this
  cluster (clean `libmpi.so.40`, no hcoll/ocoms hardlink). We did not
  switch to it because the user wanted to stay on the 5.x line.

## What HCOLL and OCOMS are

- **HCOLL** (Hierarchical Collectives) — Mellanox/NVIDIA's optimised MPI
  collective library, integrated into Open MPI via the `coll/hcoll`
  component. Ships only with HPC-X, never with vanilla Open MPI.
- **OCOMS** (Open CCS Modular Subsystem) — `libocoms.so.0`. NVIDIA's
  internal "opal-lite" plumbing — datatypes, lists, hash tables, MCA
  framework — extracted from Open MPI 1.x so HCOLL doesn't have to
  link against a specific Open MPI build. `libhcoll.so.1` `DT_NEED`s
  `libocoms.so.0`; both live side-by-side under
  `<HPCX_ROOT>/{hcoll,doca/hcoll}/lib/`.

`libocoms.so.0` is **never** in the openmpi module's own lib tree on
this cluster. Every openmpi module that uses HCOLL must reach into
`/packages/apps/hpcx/<version>/...hcoll/lib/` to find both libs.

## The DT_RUNPATH inheritance trap

This is the root cause of the link-time and runtime symptoms.

When `ld` (link time) or `ld.so` (runtime) resolves a library's
`DT_NEEDED` deps, it searches:

1. `LD_LIBRARY_PATH` (runtime) / `LIBRARY_PATH` (link time)
2. The **containing object's** `DT_RPATH` *or* `DT_RUNPATH`
3. The system cache (`/etc/ld.so.cache`)
4. Default dirs (`/lib`, `/usr/lib`)

The critical distinction is **between RPATH and RUNPATH** when a
library has its own `DT_NEEDED` entries:

| Tag           | Direct deps                | Transitive deps    |
| ------------- | -------------------------- | ------------------ |
| `DT_RPATH`    | Searched                   | **Also searched**  |
| `DT_RUNPATH`  | Searched                   | **NOT searched**   |

Modern `ld` (and Open MPI's `mpicc` wrapper, which passes
`-Wl,--enable-new-dtags`) emits `DT_RUNPATH`, **not** `DT_RPATH`. The
practical consequence:

- `libmpi.so.40` (with `DT_RUNPATH = .../hcoll/lib`) can resolve its
  own `DT_NEEDED libhcoll.so.1` via its RUNPATH.
- But `libhcoll.so.1` then needs `libocoms.so.0`. `ld.so` does **not**
  look in libmpi's RUNPATH to find it — only in libhcoll's own
  RUNPATH/RPATH (if any), the executable's RUNPATH, `LD_LIBRARY_PATH`,
  and the system cache.

On this cluster, `libhcoll.so.1` has no RUNPATH pointing at its sibling
`libocoms.so.0`, so `LD_LIBRARY_PATH` is the only way to make it
resolve. That's why `./io500 -h` printed
`libocoms.so.0: cannot open shared object file` even when libhcoll
itself was found.

## Module-by-module breakdown

All readelf data taken on 2026-05-20 against
`/packages/apps/openmpi/<module>/lib/libmpi.so.40`.

### `openmpi/4.1.5` (cluster default, `(D)`)

```
DT_NEEDED hcoll/ucc/ocoms? No (clean)
DT_RPATH: /packages/apps/openmpi/4.1.5/lib
```

`mpicc` resolves to `/packages/apps/hpcx/2.13.1/hpcx-ompi/bin/mpicc`.
Compiles with gcc 11.2.0 (Spack). `mpicc /tmp/t.c -o /tmp/t` works
out of the box, and `ldd` shows nothing but `libmpi.so.40` + libc
deps — HCOLL/UCC are loaded as MCA dlopens at MPI_Init, not as hard
DT_NEEDED. **No LD_LIBRARY_PATH hacks needed at any stage.**

### `openmpi/5.0.8` (bare, current default)

```
DT_NEEDED hcoll/ucc/ocoms?
  libucc.so.1
  libhcoll.so.1
  libocoms.so.0     <-- direct NEEDED of libmpi itself
DT_RUNPATH:
  /packages/apps/spack/.../gcc-12.1.0-hxm/lib64
  /packages/apps/openmpi/5.0.8/lib
  /packages/apps/pmix/4.2.8-slurm/lib
  /packages/apps/libevent/2.1.12/lib
  /packages/apps/hwloc/2.9.3/lib
```

libmpi declares the deps **but its RUNPATH doesn't include any hpcx
dir**, so even at link time `mpicc /tmp/t.c` emits 55 undefined
references and fails. Pre-maintenance, the `~/.local`-built MPI
(which had its own `libhcoll`/`libocoms`) was on the user's
LD_LIBRARY_PATH and shadowed the module's libmpi — that's how the
May-18 baseline ran at all. Post-maintenance, `~/.local/lib` no longer
contains `libmpi`/`libhcoll`/`libocoms` and the path is commented out
in `.bash_profile`, so the module is unusable on its own.

**Fix:** prepend an hpcx hcoll dir to `LIBRARY_PATH` (build) and
`LD_LIBRARY_PATH` (runtime). We use 2.25.1 — but 2.13.1, 2.21.3-lts,
2.23, and 2.26 all also export a symbol-compatible
`libhcoll.so.1`/`libocoms.so.0`. (Verified by linking
`mpicc /tmp/t.c` against each in turn.)

### `openmpi/5.0.8-gcc-15.2.0`

```
DT_NEEDED hcoll/ucc/ocoms?
  libucc.so.1
  libhcoll.so.1
DT_RUNPATH:
  /packages/apps/ucc/1.7.0-ucx-1.20.0/lib
  /packages/apps/hpcx/2.25.1/doca/hcoll/lib   <-- HCOLL dir
  /packages/apps/openmpi/5.0.8-gcc-15.2.0/lib
  /packages/apps/ucx/1.20.0/lib
  /usr/lib64
  /packages/apps/pmix/4.2.8-slurm/lib
  /packages/apps/libevent/2.1.12/lib
  /packages/apps/hwloc/2.9.3/lib
```

libmpi's RUNPATH **does** include the hpcx hcoll dir, so libhcoll
itself resolves. But because RUNPATH is not inherited (see above),
libhcoll's own `DT_NEEDED libocoms.so.0` cannot be found at either
link time or runtime — the linker emits the
`undefined reference to ocoms_*` errors documented in the original
checkpoint (`docs/checkpoint-2026-05-20.md`).

**Fix:** identical to bare 5.0.8 — prepend the hpcx hcoll dir to
`LIBRARY_PATH` / `LD_LIBRARY_PATH`. The auto-loaded `gcc/15.2.0` also
clobbers `CC=mpicc` (covered separately in the install script — search
for `export CC=mpicc`).

### `openmpi/5.0.8-{intel-classic-2023.1.0,intel-oneapi-2025.3.3,nvhpc-26.3}`

Not investigated in depth. All three auto-load
`ucx/1.20.0-gcc-15.2.0` and pull the same HPC-X tree, so they likely
exhibit the same RUNPATH-inheritance issue as
`openmpi/5.0.8-gcc-15.2.0`. The same `HCOLL_FALLBACK_DIR` fix in our
scripts should apply unchanged.

## How `scripts/install-io500.sh` handles it

Auto-discovery + hard fallback. Pseudo-code of the relevant block:

```bash
# Discover libmpi.so.40 and its RUNPATH/RPATH.
libdir=$(mpicc --showme:libdirs | awk '{print $1}')
libmpi=$(ls "$libdir"/libmpi.so* | head -1)
runpath=$(readelf -d "$libmpi" | awk -F'[][]' '/RUNPATH|RPATH/{print $2; exit}')

# Step 1 — prepend libmpi's own RUNPATH (no-op for openmpi/4.1.5; pulls
# the hpcx dir in for 5.0.8-gcc-15.2.0; harmless extras for bare 5.0.8).
[[ -n "$runpath" ]] && export LIBRARY_PATH="$runpath:$LIBRARY_PATH" \
                    && export LD_LIBRARY_PATH="$runpath:$LD_LIBRARY_PATH"

# Step 2 — if libmpi DT_NEEDs libhcoll/libocoms, force the fallback hpcx
# dir onto the front of both paths so ld can satisfy transitive deps.
if readelf -d "$libmpi" | grep -qE 'NEEDED.*lib(hcoll|ocoms)'; then
  export LIBRARY_PATH="$HCOLL_FALLBACK_DIR:$LIBRARY_PATH"
  export LD_LIBRARY_PATH="$HCOLL_FALLBACK_DIR:$LD_LIBRARY_PATH"
fi
```

The runtime equivalent lives in `scripts/run-io500.sbatch`, applied
right after `module load "$MPI_MODULE"`. Both honour an override
`HCOLL_FALLBACK_DIR=/packages/apps/hpcx/<other>/hcoll/lib` if 2.25.1
goes away or is moved.

## Quick reference — switching modules

### Stay on bare openmpi/5.0.8 (default)

```bash
# Build:
cd /home/acchapm1/io/io500 && rm -rf build/* io500 io500-verify
bash /home/acchapm1/io/asu-io500/scripts/install-io500.sh

# Interactive:
module purge && module load openmpi/5.0.8
export LD_LIBRARY_PATH=/packages/apps/hpcx/2.25.1/doca/hcoll/lib:$LD_LIBRARY_PATH
/home/acchapm1/io/io500/io500 -h
```

### Try openmpi/5.0.8-gcc-15.2.0

```bash
cd /home/acchapm1/io/io500 && rm -rf build/* io500 io500-verify
MPI_MODULE=openmpi/5.0.8-gcc-15.2.0 \
  bash /home/acchapm1/io/asu-io500/scripts/install-io500.sh

# sbatch automatically picks up the same MPI_MODULE if exported:
MPI_MODULE=openmpi/5.0.8-gcc-15.2.0 \
  sbatch /home/acchapm1/io/asu-io500/scripts/run-io500.sbatch \
    /home/acchapm1/io/asu-io500/configs/config-minimal.ini smoke
```

### Switch to openmpi/4.1.5 (no hcoll drama)

```bash
cd /home/acchapm1/io/io500 && rm -rf build/* io500 io500-verify
MPI_MODULE=openmpi/4.1.5 \
  bash /home/acchapm1/io/asu-io500/scripts/install-io500.sh

# Interactive: no LD_LIBRARY_PATH augment needed.
module purge && module load openmpi/4.1.5
/home/acchapm1/io/io500/io500 -h
```

## When to file an RC ticket

The clean fix is in the module files themselves — RC could edit
`/packages/modulefiles/apps/openmpi/5.0.8.lua` (and the `-gcc-15.2.0`
variant) to add:

```lua
prepend_path("LD_LIBRARY_PATH", "/packages/apps/hpcx/2.25.1/doca/hcoll/lib")
```

…which would let interactive `./io500 -h` work without any
user-side `export`. Worth opening a ticket if this affects other users
of the 5.0.8 modules.

Open question for RC: between the May-18 valid run and the May-19
failure, something removed `libhcoll`/`libocoms` from whatever path
the compute nodes used to find them (likely the user's `~/.local`
artifacts and/or a system `ldconfig` cache change). Worth confirming
whether HPC-X 2.25.1 itself was moved or rebuilt as part of the
maintenance prep — if so, the openmpi/5.0.8 modules need to be
updated to track it.
