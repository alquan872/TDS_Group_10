#!/bin/bash
#PBS -N clustering
#PBS -l select=1:ncpus=8:mem=64gb
#PBS -l walltime=08:00:00
#PBS -o ../7_Clustering/logs/clustering.o
#PBS -e ../7_Clustering/logs/clustering.e

set -euo pipefail

WORKDIR="${PBS_O_WORKDIR}/../7_Clustering/scripts"
LOGDIR="${PBS_O_WORKDIR}/../7_Clustering/logs"

mkdir -p "$LOGDIR"
mkdir -p "${PBS_O_WORKDIR}/../7_Clustering/outputs/gmm_plots"
mkdir -p "${PBS_O_WORKDIR}/../7_Clustering/outputs/tables"

cd "$WORKDIR" || { echo "cd failed: $WORKDIR"; exit 1; }

eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate group10_python


python3 clustering.py 2>&1 | tee "$LOGDIR/clustering_output.log"

