#!/bin/bash
#PBS -l walltime=08:00:00
#PBS -l select=1:ncpus=8:mem=64gb
#PBS -N Q1_4_rf_lasso
#PBS -o ../4_Stability_Selection_LASSO/logs/Q1_4_rf_lasso.o
#PBS -e ../4_Stability_Selection_LASSO/logs/Q1_4_rf_lasso.e

set -euo pipefail

WORKDIR="${PBS_O_WORKDIR}/../4_Stability_Selection_LASSO/scripts"
LOGDIR="${PBS_O_WORKDIR}/../4_Stability_Selection_LASSO/logs"
R_LOG="$LOGDIR/Q1_4_rf_lasso_outcome.log"

mkdir -p "$LOGDIR"
cd "$WORKDIR" || { echo "cd failed: $WORKDIR"; exit 1; }



eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate group10_R



Rscript --vanilla Q1_4_lasso_AUC_rf_vs_LASSO.R 2>&1 | tee "$R_LOG"
