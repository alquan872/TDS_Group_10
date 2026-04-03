#!/bin/bash
#PBS -l walltime=03:00:00
#PBS -l select=1:ncpus=8:mem=64gb
#PBS -N Univariate
#PBS -o ../univariate_analysis/logs/1_4_univariate_analysis.out
#PBS -e ../univariate_analysis/logs/1_3_univariate_analysis.err


cd "$PBS_O_WORKDIR/../univariate_analysis/scripts" || exit 1

eval "$(~/anaconda3/bin/conda shell.bash hook)"
source activate group10_R

Rscript univariate_analysis.R