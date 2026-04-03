#!/bin/bash
#PBS -l walltime=24:00:00
#PBS -l select=1:ncpus=8:mem=256gb
#PBS -N Imputation
#PBS -o ../2_Imputation/logs/2_Imputation.out
#PBS -e ../2_Imputation/logs/2_Imputation.err

cd "$PBS_O_WORKDIR/../2_Imputation/script" || exit 1

eval "$(~/anaconda3/bin/conda shell.bash hook)"
source activate group10_R

Rscript 2_Imputation.R