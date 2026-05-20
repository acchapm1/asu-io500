# Checkpoint — 2026-05-20

Saved before a maintenance reboot of the dev node. Pick up from here when the
node is back.

## What we were doing

Triaging a failed 10-node optimized run (`logs/io500-10node-opt-53015606.err`,
SLURM job 53015606). Every rank crashed at startup with:

```
/home/acchapm1/io/io500/io500: error while loading shared libraries:
libhcoll.so.1: cannot open shared object file: No such file or directory
```

## What we found

1. The crashed binary `/home/acchapm1/io/io500/io500` was built against the
   bare `openmpi/5.0.8` module **but** its runtime resolution on this dev
   node pulled `libmpi.so.40` out of `~/.local/lib/` — a user-built Open MPI
   that has a hard DT_NEEDED on `libhcoll.so.1` (HPC-X / Mellanox HCOLL).
   The compute nodes lack `libhcoll.so.1` on their default library path, so
   the dynamic linker bails before `main()`.
2. `libhcoll.so.1` *does* exist on `/packages` (multiple HPC-X versions: 2.13.1,
   2.17.1, 2.18.1-LTS, 2.19, 2.21.2, 2.21.3-lts, 2.23, plus 2.25.1 under
   `/packages/apps/hpcx/2.25.1/doca/hcoll/`), so a workaround would be
   `LD_LIBRARY_PATH`-prepending an HPC-X hcoll dir in the sbatch script —
   but that's brittle.
3. The cluster also exposes compiler-flavored variants:
   - `openmpi/5.0.8-gcc-15.2.0`
   - `openmpi/5.0.8-intel-classic-2023.1.0`
   - `openmpi/5.0.8-intel-oneapi-2025.3.3`
   - `openmpi/5.0.8-nvhpc-26.3`

   All four auto-load `ucx/1.20.0-gcc-15.2.0`. The bare `openmpi/5.0.8`
   module does not.

## What we tried

Decision: **rebuild io500 against `openmpi/5.0.8-gcc-15.2.0`** — the cleanest
fix, dropping any dependence on the homebrew `~/.local` MPI.

Two issues uncovered (and one fix already committed) before the maintenance
window:

1. **`gcc/15.2.0` (a dep of the gcc-15.2.0 openmpi module) sets `CC=gcc`.**
   This clobbers any `CC=mpicc` exported before `module load`. IOR's
   `configure` uses `AX_PROG_CC_MPI`, which honors `$CC`, so we silently
   linked against plain gcc and failed the `MPI_Init` test.

   **Fix landed:** `scripts/install-io500.sh` now exports `CC=mpicc CXX=mpicxx`
   *after* the module-load section. Verified the override survives via:

   ```
   $ export CC=mpicc; module load openmpi/5.0.8-gcc-15.2.0
   After load: CC=gcc, mpicc=/packages/apps/openmpi/5.0.8-gcc-15.2.0/bin/mpicc
   ```

2. **`mpicc` from `openmpi/5.0.8-gcc-15.2.0` is itself broken on the dev
   node.** Even a trivial `conftest.c` link fails because the wrapper
   auto-links `/packages/apps/hpcx/2.25.1/doca/hcoll/lib/libhcoll.so.1`,
   which has an unresolved dep on `libocoms.so.0`:

   ```
   /usr/bin/ld: warning: libocoms.so.0, needed by .../doca/hcoll/lib/libhcoll.so.1,
                not found (try using -rpath or -rpath-link)
   .../libhcoll.so.1: undefined reference to `ocoms_argv_count'
   .../libhcoll.so.1: undefined reference to `ocoms_hash_table_set_value_ptr'
   .../libhcoll.so.1: undefined reference to `ocoms_datatype_resize'
   ```

   We did not get to locate `libocoms.so.0` on `/packages` before the
   reboot. The user interrupted the `find /packages/apps/hpcx ...` step.

## State of the tree at checkpoint

- `scripts/install-io500.sh` — modified, the `CC=mpicc`/`CXX=mpicxx` fix is
  on disk and auto-pushed to GitHub.
- `/home/acchapm1/io/io500/` — half-built tree. `make clean` was run; IOR's
  `build/ior/` no longer has `configure`/`Makefile.in`. The old `io500` and
  `io500-verify` binaries from 2026-05-15 are still in place (the rebuild
  hasn't gotten past IOR's `configure` yet, so it didn't overwrite them).
- Working tree status (uncommitted at top of session):
  `scripts/run-10node-optimized.sh`, `scripts/run-io500.sbatch`,
  `scripts/smoke-test.sh` — unrelated to this thread.
- `results/20260519T195805Z-pre-maint-smoke/` — untracked, unrelated.

## To resume after the reboot

1. **Re-test from a clean shell** that the bare `mpicc` works on its own:

   ```
   module purge && module load openmpi/5.0.8-gcc-15.2.0
   echo 'int main(){return 0;}' > /tmp/t.c
   mpicc /tmp/t.c -o /tmp/t && echo OK || echo BROKEN
   ```

   - If `OK` after the reboot, the post-maintenance HPC-X / libocoms
     layout was fixed by ops. Run the rebuild:
     ```
     cd /home/acchapm1/io/io500 && make clean
     MPI_MODULE=openmpi/5.0.8-gcc-15.2.0 bash \
       /home/acchapm1/io/asu-io500/scripts/install-io500.sh
     ```
   - If still `BROKEN`, locate `libocoms.so.0` (skipped pre-reboot):
     ```
     find /packages -name 'libocoms.so*' 2>/dev/null
     ```
     and either add its dir to `LD_LIBRARY_PATH`/`LIBRARY_PATH` for the
     build, or escalate to RC — the openmpi/5.0.8-gcc-15.2.0 module
     shouldn't be linking against a `doca/hcoll` whose deps don't resolve.
   - As a fallback, try one of the other compiler-flavored variants
     (`-intel-oneapi-2025.3.3` is the most modern). All four pull the same
     UCX, so the mpicc wrapper config is the variable.

2. Once the rebuild succeeds, verify the new binary doesn't depend on
   `libhcoll`:

   ```
   ldd /home/acchapm1/io/io500/io500 | grep -i hcoll
   # expect: empty output
   ```

3. Re-submit the smoke test and then the 10-node optimized run:

   ```
   cd /home/acchapm1/io/asu-io500
   sbatch scripts/run-io500.sbatch configs/config-minimal.ini post-reboot-smoke
   sbatch scripts/run-10node-optimized.sh baseline-optimized-v1
   ```

## Open question for the user

The original baseline runs (pre-maint) used the same `~/.local`-built MPI
binary. They produced valid io500 scores — meaning the compute nodes *did*
resolve `libhcoll.so.1` at that time. Something changed between then and
the failed job on 2026-05-19 that removed `libhcoll` from the compute
nodes' library path. Worth asking RC whether HPC-X was de-installed or
moved as part of the maintenance prep.
