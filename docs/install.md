# Installing io500

`scripts/install-io500.sh` automates the steps below. Read this once so you
know what to do when it fails.

## Prerequisites

- `module` (Lmod or environment-modules) on PATH
- The following cluster modules:
  - `openmpi/5.0.8`
  - `autoconf/2.73` (IOR's `configure.ac` requires autoconf ≥ 2.71; the
    system `/usr/bin/autoconf` is older)
  - `automake/1.17`
  - `libtool/2.4.7`
  - `make/4.4.1`
- `git` on PATH (system git is fine)
- Write access to `/home/acchapm1/io/io500`

The install script loads all of these for you via `module purge && module load
...`; you don't need to load them in your shell first.

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

## Override the MPI stack or build toolchain

The script's module defaults live at the top of `scripts/install-io500.sh`:

- `MPI_MODULE` — `scripts/install-io500.sh:13`, default `openmpi/5.0.8`
- `TOOLCHAIN_MODULES` — `scripts/install-io500.sh:18`, default
  `autoconf/2.73 automake/1.17 libtool/2.4.7 make/4.4.1`
- `ACLOCAL_EXTRA_DIR` — `scripts/install-io500.sh:70`, default
  `/usr/share/aclocal` (where the script looks for `pkg.m4`)

Two ways to change them:

1. **Per-invocation, via environment variable** (no edit; the `${VAR:-default}`
   form lets you override any of them):

   ```bash
   MPI_MODULE=openmpi/4.1.6 bash scripts/install-io500.sh
   TOOLCHAIN_MODULES="autoconf/2.71 automake/1.16 libtool/2.4.6 make/4.3" \
     bash scripts/install-io500.sh
   ACLOCAL_EXTRA_DIR=/opt/pkgconfig/share/aclocal bash scripts/install-io500.sh
   ```

2. **Permanently, by editing the default in the script.** Open
   `scripts/install-io500.sh` and change the literal after `:-` on the
   relevant line — e.g. line 13 for MPI, line 18 for the autotools stack.
   Commit the change so the install is reproducible for the next run.

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
- **`autoreconf: ... error: Autoconf version 2.71 or higher is required`** —
  the toolchain modules didn't load. Confirm `autoconf/2.72` (or your site's
  equivalent) is in `module avail` output and adjust `TOOLCHAIN_MODULES`.
- **`configure.ac:NNN: error: undefined or overquoted macro: AC_DEFINE` (or
  `AC_SUBST`)** — `pkg.m4` (the file that defines `PKG_CHECK_MODULES`) isn't
  on aclocal's search path. The install script prepends `/usr/share/aclocal`
  to `ACLOCAL_PATH` to fix this; if your site keeps `pkg.m4` somewhere else,
  set `ACLOCAL_EXTRA_DIR=/path/to/aclocal` before running the script. Find
  it with `find / -name pkg.m4 2>/dev/null`.
- **`prepare.sh` clone fails with SSL** — head node has no internet. Run
  install from a node that does, or pre-populate `io500/build/{ior,pfind,cdcl-schema-tools}`.
- **Stale build after pulling new io500 commits** — `cd /home/acchapm1/io/io500 && make clean && bash scripts/install-io500.sh`.
