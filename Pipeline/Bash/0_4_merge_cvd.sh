#!/bin/bash
#PBS -l walltime=24:00:00
#PBS -l select=1:ncpus=8:mem=64gb
#PBS -N merge
#PBS -o ../0_extract_data/logs/0_4_merge.out
#PBS -e ../0_extract_data/logs/1_4_merge.err

set -euo pipefail

WORKDIR="${PBS_O_WORKDIR}/../0_extract_data/scripts"
LOGDIR="${PBS_O_WORKDIR}/../0_extract_data/logs"
R_LOG="$LOGDIR/merge_R.log"

mkdir -p "$LOGDIR"
cd "$WORKDIR" || { echo "cd failed: $WORKDIR"; exit 1; }

eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate group10_R

Rscript --no-save --no-restore 4-merge_cvd.R 2>&1 | tee "$R_LOG"