#!/bin/bash
#PBS -l walltime=04:00:00
#PBS -l select=1:ncpus=16:mem=128gb
#PBS -N Correlation
#PBS -o ../3_Correlation/logs/correlation.out
#PBS -e ../3_Correlation/logs/correlation.err

set -euo pipefail

WORKDIR="${PBS_O_WORKDIR}/../3_Correlation/script"
LOGDIR="${PBS_O_WORKDIR}/../3_Correlation/logs"
R_LOG="$LOGDIR/correlation_R.log"

mkdir -p "$LOGDIR"
cd "$WORKDIR" || { echo "cd failed: $WORKDIR"; exit 1; }



eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate group10_R


Rscript --no-save --no-restore 3_Correlation.R 2>&1 | tee "$R_LOG"
