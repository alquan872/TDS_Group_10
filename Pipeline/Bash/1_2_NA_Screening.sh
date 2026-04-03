#!/bin/bash
#PBS -l walltime=00:30:00
#PBS -l select=1:ncpus=8:mem=64gb
#PBS -N NA_Screening
#PBS -o ../1_recoding_extraction_preprocessing/logs/1_2_NA_screening.out
#PBS -e ../1_recoding_extraction_preprocessing/logs/1_2_NA_screening.err

set -euo pipefail

WORKDIR="${PBS_O_WORKDIR}/../1_recoding_extraction_preprocessing/script"
LOGDIR="${PBS_O_WORKDIR}/../1_recoding_extraction_preprocessing/logs"
R_LOG="$LOGDIR/NA_screening_R.log"

mkdir -p "$LOGDIR"
cd "$WORKDIR" || { echo "cd failed: $WORKDIR"; exit 1; }



eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate group10_R

Rscript --no-save --no-restore 2_NA_cleaning.R 2>&1 | tee "$R_LOG"


