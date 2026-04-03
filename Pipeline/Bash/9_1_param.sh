#!/bin/bash
#PBS -N grlvq_optuna
#PBS -l select=1:ncpus=16:mem=256gb
#PBS -l walltime=48:00:00
#PBS -o ../9_LVQ/logs/grlvq_optuna.o
#PBS -e ../9_LVQ/logs/grlvq_optuna.e

set -euo pipefail

WORKDIR="${PBS_O_WORKDIR}/../9_LVQ/scripts"
LOGDIR="${PBS_O_WORKDIR}/../9_LVQ/logs"

mkdir -p "$LOGDIR"
cd "$WORKDIR" || { echo "cd failed: $WORKDIR"; exit 1; }

eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate group10_python


python3 LVQ_param.py 2>&1 | tee "$LOGDIR/grlvq_optuna_output.log"

