#!/bin/bash
#PBS -l walltime=4:00:00
#PBS -l select=1:ncpus=1:mem=50gb
#PBS -N extraction
#PBS -o ../0_extract_data/logs/extraction.out
#PBS -e ../0_extract_data/logs/extraction.err

set -euo pipefail

WORKDIR="${PBS_O_WORKDIR}/../0_extract_data/scripts"
LOGDIR="${PBS_O_WORKDIR}/../0_extract_data/logs"
R_LOG="$LOGDIR/extraction_R.log"

mkdir -p "$LOGDIR"
cd "$WORKDIR" || { echo "cd failed: $WORKDIR"; exit 1; }

eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate group10_R

ukb_path=/rds/general/project/hda_25-26/live/TDS/General/Data/tabular.tsv
Rscript --no-save --no-restore 2-extract_selected.R $ukb_path 2>&1 | tee "$R_LOG"
