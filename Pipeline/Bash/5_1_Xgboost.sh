#!/bin/bash
#PBS -N xgboost
#PBS -l walltime=48:00:00
#PBS -l select=1:ncpus=8:mem=256gb
#PBS -o ../5_Xgboost/logs/xgboost.out
#PBS -e ../5_Xgboost/logs/xgboost.err

echo "===== JOB START ====="
echo "Time: $(date)"

cd "$PBS_O_WORKDIR/../5_Xgboost/script" || exit 1

eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate group10_python

python3 5_Xgboost.py