# sbatch submission notes

Site-specific quirks of Sol's SLURM that affect this harness. Add to this
file when you hit a new submit-time wart — the wrappers are otherwise
straightforward.

## "Invalid feature specification" on `-p htc` during maintenance

### Symptom

```
$ sbatch scripts/smoke-test.sh
sbatch: error: Notice: Jobs submitted to partition 'htc' with QOS 'public' \
  are automatically rewritten to QOS 'htc'.
sbatch: error: Batch job submission failed: Invalid feature specification
```

Reproduces with bare `sbatch --partition=htc --qos=public ...` — it is not
caused by anything in the wrapper script.

### Root cause

During the `maint` reservation, every htc node carries
`State=IDLE+DYNAMIC_NORM+MAINTENANCE+RESERVED+PLANNED`. The reservation has
`Flags=...,ALL_NODES`, so it covers the full htc node set
(`sc[003-112],scc[001-049],scg[001-028],sg[001-050,230-239]`).

Sol's `job_submit.lua` plugin (the same one that emits the "automatically
rewritten to QOS 'htc'" notice) injects a feature requirement on every htc
submission. While the nodes are in `MAINTENANCE` state that feature isn't
satisfiable, so the controller rejects the job before it ever looks at the
reservation.

Adding `--constraint=htc`, `--constraint=epyc`, `--reservation=maint`, or
submitting with `--qos=htc` directly does **not** help — the injected
constraint is the problem, not anything the user passes.

### Fix

Submit to `--partition=public` for the duration of the maintenance window.
`public` covers the same physical nodes, has a 7-day `MaxTime` (so the 2 h /
4 h / 12 h jobs all fit), and the `job_submit.lua` plugin leaves public
submissions alone. The reservation still resolves normally:

```bash
sbatch --partition=public --qos=public --nodes=2 --ntasks-per-node=8 \
       --time=02:00:00 --reservation=maint scripts/smoke-test.sh
```

When the maintenance reservation ends and nodes leave `MAINTENANCE` state,
`-p htc` should work again and these wrappers can be reverted.

### Evidence (bisection on the dev node, 2026-05-19)

| Submission | Result |
| --- | --- |
| `-p htc --qos=public` (any nodes/time, with or without `--reservation=maint`) | Invalid feature specification |
| `-p htc --qos=public --constraint=htc` (or `epyc`) | Invalid feature specification |
| `-p htc --qos=htc` (skipping the rewrite) | Invalid feature specification |
| `-p public --qos=public --reservation=maint --nodes=2 --time=02:00:00` | Scheduled on `sc[005-006]` |

### Files that pin `--partition=htc`

These wrappers need a temporary swap to `--partition=public` while the
`maint` reservation is active:

- `scripts/smoke-test.sh`
- `scripts/run-io500.sbatch`
- `scripts/run-10node.sh`
- `scripts/run-10node-optimized.sh` *(check before submitting)*

`scripts/run-full-cluster.sh` already uses `--partition=public` and is
unaffected.

## Not to be confused with: dev-node SLURM blindness

A separate failure mode — covered in the `cluster-topology` memory — is
when `scontrol show reservation`, `sinfo -T`, `squeue --reservation`, etc.
return empty output from the dev login node because it can't see Sol's
controller. That manifests as "Reservation not found" / empty discovery
output, **not** as `Invalid feature specification`. If you're seeing the
latter you are talking to Sol's controller; it's the htc submit filter
that's rejecting you.
