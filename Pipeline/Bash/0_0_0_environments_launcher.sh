#!/bin/bash
#PBS -l walltime=01:00:00
#PBS -l select=1:ncpus=1:mem=10gb
#PBS -N install_R_packages
#PBS -o ../environments/install_R_packages.out
#PBS -e ../environments/install_R_packages.err

set -euo pipefail
WORKDIR="${PBS_O_WORKDIR}/../environments"
cd "$WORKDIR" || { echo "cd failed: $WORKDIR"; exit 1; }

eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate group10_R

Rscript packages.R