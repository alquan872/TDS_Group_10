#!/bin/bash
#PBS -N clustering_launcher
#PBS -l walltime=00:30:00
#PBS -l select=1:ncpus=8:mem=64gb
#PBS -o /dev/null
#PBS -e /dev/null

set -euo pipefail

cd $PBS_O_WORKDIR || exit 1

mkdir -p ../7_Clustering/logs
mkdir -p ../7_Clustering/outputs


JOB1=$(qsub ../Bash/7_1_Clustering.sh)
echo "Clustering submitted: $JOB1"
