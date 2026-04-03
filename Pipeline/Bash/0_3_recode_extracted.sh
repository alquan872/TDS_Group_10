#!/bin/bash
#PBS -l walltime=2:00:00
#PBS -l select=1:ncpus=1:mem=50gb
#PBS -N recoding
#PBS -o ../0_extract_data/logs/recoding.out
#PBS -e ../0_extract_data/logs/recoding.err

set -euo pipefail

WORKDIR="${PBS_O_WORKDIR}/../0_extract_data/scripts"
LOGDIR="${PBS_O_WORKDIR}/../0_extract_data/logs"
R_LOG="$LOGDIR/recoding_R.log"

mkdir -p "$LOGDIR"
cd "$WORKDIR" || { echo "cd failed: $WORKDIR"; exit 1; }

eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate group10_R

Rscript --no-save --no-restore 3-recode_variables.R 2>&1 | tee "$R_LOG"

