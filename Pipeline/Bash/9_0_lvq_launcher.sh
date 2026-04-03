#!/bin/bash
#PBS -N grlvq_launcher
#PBS -l walltime=00:30:00
#PBS -l select=1:ncpus=4:mem=16gb
#PBS -o /dev/null
#PBS -e /dev/null

set -euo pipefail

cd $PBS_O_WORKDIR || exit 1

mkdir -p ../9_LVQ/logs
mkdir -p ../9_LVQ/outputs

JOB1=$(qsub ../Bash/9_1_param.sh)
echo "LVQ Optuna submitted: $JOB1"

JOB2=$(qsub -W depend=afterok:$JOB1 ../Bash/9_2_train.sh)
echo "LVQ Model submitted: $JOB2"
