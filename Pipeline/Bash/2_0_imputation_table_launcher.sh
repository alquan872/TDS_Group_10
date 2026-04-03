#!/bin/bash
#PBS -N early_pipeline_launcher
#PBS -l walltime=01:00:00
#PBS -l select=1:ncpus=8:mem=64gb
#PBS -o /dev/null
#PBS -e /dev/null


cd $PBS_O_WORKDIR || exit 1

mkdir -p ../2_Imputation/logs
mkdir -p ../2_Imputation/outputs
mkdir -p ../table_1/logs
mkdir -p ../table_1/outputs


JOB1=$(qsub ../Bash/2_1_Imputation.sh)
echo "Imputation submitted: $JOB1"

JOB2=$(qsub -W depend=afterok:$JOB1 ../Bash/2_2_Table_1.sh)
echo "Table1 submitted: $JOB2"
