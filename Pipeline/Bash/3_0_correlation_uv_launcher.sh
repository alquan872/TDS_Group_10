#!/bin/bash
#PBS -N corr_univariate_launcher
#PBS -l walltime=00:30:00
#PBS -l select=1:ncpus=8:mem=64gb
#PBS -o /dev/null
#PBS -e /dev/null

set -euo pipefail

cd $PBS_O_WORKDIR || exit 1

mkdir -p ../3_Correlation/logs
mkdir -p ../3_Correlation/outputs
mkdir -p ../univariate_analysis/logs
mkdir -p ../univariate_analysis/outputs


JOB1=$(qsub ../Bash/3_1_Correlation.sh)
echo "Correlation submitted: $JOB1"

JOB2=$(qsub -W depend=afterok:$JOB1 ../Bash/3_2_univariate_analysis.sh)
echo "Univariate submitted: $JOB2"
