# Running io500

## Before the first run

1. Build: `bash scripts/install-io500.sh`
2. Open `scripts/run-io500.sbatch` and uncomment + edit the `#SBATCH` lines
   for your environment:
   ```
   #SBATCH --partition=<your partition>
   #SBATCH --nodes=<N>
   #SBATCH --ntasks-per-node=<ranks per node>
   #SBATCH --time=02:00:00      # allow >300s per phase + slop
   #SBATCH --exclusive
   ```
   For an IO500 score that has any chance of being valid, you need enough
   ranks to push the array — single-node 2-rank runs always come back INVALID.

## Submitting

```bash
sbatch scripts/run-io500.sbatch <config> <label>
```

Example sequence for the maintenance comparison:

```bash
# Sanity check the install
sbatch scripts/run-io500.sbatch configs/config-minimal.ini pre-maint-smoke

# Real pre-maintenance benchmark
sbatch scripts/run-io500.sbatch configs/asu-beegfs.ini pre-maint

# ... maintenance happens ...

# Real post-maintenance benchmark (same config, same node count!)
sbatch scripts/run-io500.sbatch configs/asu-beegfs.ini post-maint
```

The two real runs **must** use the same config, same node count, same
ranks-per-node, same MPI stack. Anything different and you're comparing apples
to oranges.

## What lands in the repo

Each run creates `results/<UTC-timestamp>-<label>/` containing:

| File | Source |
| --- | --- |
| `result_summary.txt` | io500 — the headline per-phase scores |
| `result.txt`         | io500 — full INI-format results with hashes |
| `config-used.ini`    | exact config file submitted (so you know what ran) |
| `run-metadata.txt`   | SLURM job id, nodelist, ntasks, host |
| `module-list.txt`    | `module list` output for MPI version capture |
| `lscpu.txt`          | CPU info of the launch node |
| `df.txt`             | `df -hT /scratch/acchapm1/io` |
| `mount-beegfs.txt`   | BeeGFS mount options at run time |
| `beegfs-targets.txt` | `beegfs-ctl --listtargets` (storage targets) |
| `beegfs-net.txt`     | `beegfs-net` (connection state) |
| `io500.stdout`       | full launch-time stdout |
| `io500.stderr`       | full launch-time stderr |
| `ior-*`, `mdtest-*`  | per-phase logs copied from io500's `results/` dir |

`result_summary.txt` is the file you compare pre vs post. Everything else is
provenance so future-you remembers what changed.

## Interactive run (no sbatch)

For debugging only:

```bash
salloc --partition=<...> --nodes=1 --ntasks=4 --time=00:30:00 --exclusive
module load openmpi/5.0.8
cd /home/acchapm1/io/io500
mpirun -np 4 ./io500 /home/acchapm1/io/asu-io500/configs/config-minimal.ini
```

This won't write `results/<...>/` into the asu-io500 repo — only the sbatch
script does the capture/copy. Use it just to confirm the binary launches.

## Dry-run

```bash
cd /home/acchapm1/io/io500
./io500 /home/acchapm1/io/asu-io500/configs/asu-beegfs.ini --dry-run
```

Prints the ior/mdtest command lines that would run, without touching the
filesystem. Useful for sanity-checking config changes.
