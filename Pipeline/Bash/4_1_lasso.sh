#!/bin/bash
#PBS -N Q1_1_lasso
#PBS -l select=1:ncpus=8:mem=64gb
#PBS -l walltime=08:00:00
#PBS -o ../4_Stability_Selection_LASSO/logs/Q1_1_lasso.o
#PBS -e ../4_Stability_Selection_LASSO/logs/Q1_1_lasso.e

set -euo pipefail
WORKDIR="${PBS_O_WORKDIR}/../4_Stability_Selection_LASSO/scripts"
LOGDIR="${PBS_O_WORKDIR}/../4_Stability_Selection_LASSO/logs"
R_LOG="$LOGDIR/Q1_1_lasso_outcome.log"
mkdir -p "$LOGDIR"
cd "$WORKDIR" || { echo "cd failed: $WORKDIR"; exit 1; }


eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate group10_R



Rscript --vanilla Q1_1_lasso_basic_model.R 2>&1 | tee "$R_LOG"
