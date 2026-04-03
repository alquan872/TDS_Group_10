#!/bin/bash
#PBS -l walltime=24:00:00
#PBS -l select=1:ncpus=8:mem=256gb
#PBS -N Preprocessing
#PBS -o ../1_recoding_extraction_preprocessing/logs/1_1_preprocessing.out
#PBS -e ../1_recoding_extraction_preprocessing/logs/1_1_preprocessing.err

set -euo pipefail

WORKDIR="${PBS_O_WORKDIR}/../1_recoding_extraction_preprocessing/script"
LOGDIR="${PBS_O_WORKDIR}/../1_recoding_extraction_preprocessing/logs"
R_LOG="$LOGDIR/preprocessing_R.log"

mkdir -p "$LOGDIR"
cd "$WORKDIR" || { echo "cd failed: $WORKDIR"; exit 1; }


eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate group10_R


Rscript --no-save --no-restore 1_Preprocessing.R 2>&1 | tee "$R_LOG"


