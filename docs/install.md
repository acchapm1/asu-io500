# Installing io500

`scripts/install-io500.sh` automates the steps below. Read this once so you
know what to do when it fails.

## Prerequisites

- `module` (Lmod or environment-modules) on PATH
- `openmpi/5.0.8` available as a module
- `git`, `make`, `autoconf`, `automake`, `libtool` (for IOR's `./bootstrap`)
- Write access to `/home/acchapm1/io/io500`

## What the script does

1. Loads `openmpi/5.0.8` so `mpicc` is on PATH.
2. Runs `/home/acchapm1/io/io500/prepare.sh`, which:
   - clones IOR at commit `5fcf0ba995f` into `io500/build/ior/`
   - clones pfind at commit `d08501f9976` into `io500/build/pfind/`
   - clones cdcl-schema-tools
   - builds IOR (`./bootstrap && ./configure --prefix=$IO500_DIR && make install`)
   - builds pfind
3. Runs `make` in `/home/acchapm1/io/io500` to produce `io500` and
   `io500-verify` binaries.

## Run it

```bash
bash /home/acchapm1/io/asu-io500/scripts/install-io500.sh
```

Re-running is safe — `prepare.sh` skips cloned repos and `make` rebuilds only
what changed.

## Override the MPI stack

The script defaults to `openmpi/5.0.8`. To test against a different stack:

```bash
MPI_MODULE=openmpi/4.1.6 bash scripts/install-io500.sh
```

If you swap MPI stacks, **re-run the install** so IOR is relinked against the
right MPI; otherwise mpirun will fail at runtime with confusing dlopen errors.

## Verify the build

```bash
/home/acchapm1/io/io500/io500 --list | head
/home/acchapm1/io/io500/io500 -h
```

A quick local dry-run (no MPI, no I/O):

```bash
cd /home/acchapm1/io/io500
./io500 /home/acchapm1/io/asu-io500/configs/config-minimal.ini --dry-run
```

## Troubleshooting

- **`mpicc: command not found`** — the module didn't load. Run
  `module load openmpi/5.0.8` manually and confirm with `which mpicc`.
- **IOR bootstrap fails on autoconf** — older autotools on the head node.
  Load a newer `autoconf` module before running install.
- **`prepare.sh` clone fails with SSL** — head node has no internet. Run
  install from a node that does, or pre-populate `io500/build/{ior,pfind,cdcl-schema-tools}`.
- **Stale build after pulling new io500 commits** — `cd /home/acchapm1/io/io500 && make clean && bash scripts/install-io500.sh`.
