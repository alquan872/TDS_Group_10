#!/bin/bash
#PBS -l walltime=01:00:00
#PBS -l select=1:ncpus=8:mem=64gb
#PBS -N DAG
#PBS -o ../6_DAG/logs/DAG.out
#PBS -e ../6_DAG/logs/DAG.err

set -euo pipefail

WORKDIR="${PBS_O_WORKDIR}/../6_DAG/script"
LOGDIR="${PBS_O_WORKDIR}/../6_DAG/logs"
R_LOG="$LOGDIR/DAG_R.log"

mkdir -p "$LOGDIR"
cd "$WORKDIR" || { echo "cd failed: $WORKDIR"; exit 1; }


eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate group10_R


Rscript --no-save --no-restore 6_DAG.R 2>&1 | tee "$R_LOG"