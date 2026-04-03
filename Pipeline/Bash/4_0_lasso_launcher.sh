#!/bin/bash
#PBS -N lasso_pipeline_launcher
#PBS -l walltime=02:00:00
#PBS -l select=1:ncpus=8:mem=64gb
#PBS -o /dev/null
#PBS -e /dev/null

set -euo pipefail

cd $PBS_O_WORKDIR || exit 1

mkdir -p ../4_Stability_Selection_LASSO/outputs
mkdir -p ../4_Stability_Selection_LASSO/logs


JOB1=$(qsub ../Bash/4_1_lasso.sh)
echo "Q1.1 submitted: $JOB1"

JOB2=$(qsub -W depend=afterok:$JOB1 ../Bash/4_2_sex_lasso.sh)
echo "Q1.2 submitted: $JOB2"

JOB3=$(qsub -W depend=afterok:$JOB2 ../Bash/4_3_age_lasso.sh)
echo "Q1.3 submitted: $JOB3"

JOB4=$(qsub -W depend=afterok:$JOB3 ../Bash/4_4_rf_lasso.sh)
echo "Q1.4 submitted: $JOB4"

