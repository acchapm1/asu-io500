#!/bin/bash

sbatch /home/acchapm1/io/asu-io500/scripts/run-io500.sbatch \
	/home/acchapm1/io/asu-io500/configs/config-minimal.ini \
	pre-maint-smoke 2>&1 | tee /home/acchapm1/io/asu-io500/scripts/logs/output.log
