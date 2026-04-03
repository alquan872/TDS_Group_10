#!/bin/bash
#PBS -N preprocessing_launcher
#PBS -l walltime=01:00:00
#PBS -l select=1:ncpus=8:mem=128gb
#PBS -o /dev/null
#PBS -e /dev/null

cd $PBS_O_WORKDIR || exit 1

mkdir -p ../1_recoding_extraction_preprocessing/logs
mkdir -p ../1_recoding_extraction_preprocessing/outputs

JOB1=$(qsub ../Bash/1_1_Preprocessing.sh)
echo "Preprocessing submitted: $JOB1"

JOB2=$(qsub -W depend=afterok:$JOB1 ../Bash/1_2_NA_Screening.sh)
echo "NA Cleaning submitted: $JOB2"
