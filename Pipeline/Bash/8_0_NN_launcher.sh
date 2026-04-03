#!/bin/bash
#PBS -N nn_launcher
#PBS -l walltime=00:30:00
#PBS -l select=1:ncpus=8:mem=64gb
#PBS -o /dev/null
#PBS -e /dev/null

set -euo pipefail

cd $PBS_O_WORKDIR || exit 1

mkdir -p ../8_NN/logs
mkdir -p ../8_NN/outputs


JOB1=$(qsub ../Bash/8_1_MLP_optuna.sh)
echo "Paper MLP submitted: $JOB1"

JOB2=$(qsub -W depend=afterok:$JOB1 ../Bash/8_2_MLP_paper.sh)
echo "Optuna MLP submitted: $JOB2"

JOB3=$(qsub -W depend=afterok:$JOB2 ../Bash/8_3_MLP_compare.sh)
echo "Comparison submitted: $JOB3"
