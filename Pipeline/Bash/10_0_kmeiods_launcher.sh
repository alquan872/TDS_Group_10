#!/bin/bash
#PBS -N kmeiods_launcher
#PBS -l walltime=00:30:00
#PBS -l select=1:ncpus=4:mem=16gb
#PBS -o /dev/null
#PBS -e /dev/null

set -euo pipefail

cd $PBS_O_WORKDIR || exit 1

mkdir -p ../10_Kmeiods/logs
mkdir -p ../10_Kmeiods/outputs
mkdir -p ../10_Kmeiods/logs_sex
mkdir -p ../10_Kmeiods/outputs_sex

JOB1=$(qsub ../Bash/10_1_model.sh)
echo "LVQ Optuna submitted: $JOB1"

JOB2=$(qsub -W depend=afterok:$JOB1 ../Bash/10_2_model_sex.sh)
echo "LVQ Optuna Sex submitted: $JOB2"

