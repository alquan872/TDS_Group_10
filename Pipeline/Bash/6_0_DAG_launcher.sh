#!/bin/bash
#PBS -N dag_launcher
#PBS -l walltime=00:30:00
#PBS -l select=1:ncpus=8:mem=64gb
#PBS -o /dev/null
#PBS -e /dev/null

set -euo pipefail

cd $PBS_O_WORKDIR || exit 1

mkdir -p ../6_DAG/logs
mkdir -p ../6_DAG/outputs


JOB1=$(qsub ../Bash/6_1_DAG.sh)
echo "DAG submitted: $JOB1"
