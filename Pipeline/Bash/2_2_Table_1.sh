#!/bin/bash
#PBS -l walltime=03:00:00
#PBS -l select=1:ncpus=8:mem=64gb
#PBS -N Table1
#PBS -o ../table_1/logs/1_3_Table1.out
#PBS -e ../table_1/logs/1_3_Table1.err

set -euo pipefail

WORKDIR="${PBS_O_WORKDIR}/../table_1/scripts"
LOGDIR="${PBS_O_WORKDIR}/../table_1/logs"
R_LOG="$LOGDIR/table1_R.log"

mkdir -p "$LOGDIR"
cd "$WORKDIR" || { echo "cd failed: $WORKDIR"; exit 1; }


eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate tds_env

Rscript --no-save --no-restore Table1.R 2>&1 | tee "$R_LOG"

