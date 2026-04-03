#!/bin/bash
#PBS -N kmeiods_sex
#PBS -l select=1:ncpus=16:mem=512gb
#PBS -l walltime=48:00:00
#PBS -o ../10_Kmeiods/logs_sex/km.o
#PBS -e ../10_Kmeiods/logs_sex/km.e

set -euo pipefail

WORKDIR="${PBS_O_WORKDIR}/../10_Kmeiods/scripts"
LOGDIR="${PBS_O_WORKDIR}/../10_Kmeiods/logs_sex"

mkdir -p "$LOGDIR"
cd "$WORKDIR" || { echo "cd failed: $WORKDIR"; exit 1; }

eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate group10_kmedoids


python3 cluster_sex.py 2>&1 | tee "$LOGDIR/kmeiods_sex_output.log"