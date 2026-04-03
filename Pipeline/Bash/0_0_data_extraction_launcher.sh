#!/bin/bash
#PBS -N preprocessing_launcher
#PBS -l walltime=00:30:00
#PBS -l select=1:ncpus=4:mem=16gb
#PBS -o /dev/null
#PBS -e /dev/null

set -euo pipefail

cd $PBS_O_WORKDIR || exit 1

mkdir -p ../0_extract_data/logs
mkdir -p ../0_extract_data/outputs
mkdir -p ../1_recoding_extraction_preprocessing/outputs


JOB1=$(qsub ../Bash/0_1_generate_data_dict.sh)
echo "Generate data dict submitted: $JOB1"

JOB2=$(qsub -W depend=afterok:$JOB1 ../Bash/0_2_extract_selected.sh)
echo "Extract selected submitted: $JOB2"

JOB3=$(qsub -W depend=afterok:$JOB2 ../Bash/0_3_recode_extracted.sh)
echo "Recode extracted submitted: $JOB3"

JOB4=$(qsub -W depend=afterok:$JOB3 ../Bash/0_4_merge_cvd.sh)
echo "Recode extracted submitted: $JOB4"