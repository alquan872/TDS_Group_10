#!/bin/bash
#PBS -N mlp_optuna
#PBS -l select=1:ncpus=16:mem=256gb
#PBS -l walltime=6:00:00
#PBS -o ../8_NN/logs/mlp_optuna.o
#PBS -e ../8_NN/logs/mlp_optuna.e

set -euo pipefail

WORKDIR="${PBS_O_WORKDIR}/../8_NN/scripts"
LOGDIR="${PBS_O_WORKDIR}/../8_NN/logs"

mkdir -p "$LOGDIR"
cd "$WORKDIR" || { echo "cd failed: $WORKDIR"; exit 1; }

eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate group10_python


python3 NN_optuna.py 2>&1 | tee "$LOGDIR/mlp_optuna_output.log"
