#!/bin/bash
#PBS -N xgboost_launcher
#PBS -l walltime=01:00:00
#PBS -l select=1:ncpus=8:mem=64gb
#PBS -o /dev/null
#PBS -e /dev/null

cd $PBS_O_WORKDIR || exit 1
mkdir -p ../5_Xgboost/logs
mkdir -p ../5_Xgboost/outputs

qsub ../Bash/5_1_Xgboost.sh

