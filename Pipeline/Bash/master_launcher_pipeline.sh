#!/bin/bash
#PBS -N master_launcher
#PBS -l walltime=00:10:00
#PBS -l select=1:ncpus=1:mem=4gb
#PBS -o /dev/null
#PBS -e /dev/null

set -euo pipefail

cd $PBS_O_WORKDIR || exit 1

# Create all directories 
mkdir -p ../0_extract_data/logs
mkdir -p ../0_extract_data/outputs
mkdir -p ../1_recoding_extraction_preprocessing/logs
mkdir -p ../1_recoding_extraction_preprocessing/outputs
mkdir -p ../2_Imputation/logs
mkdir -p ../2_Imputation/outputs
mkdir -p ../table_1/logs
mkdir -p ../table_1/outputs
mkdir -p ../3_Correlation/logs
mkdir -p ../3_Correlation/outputs
mkdir -p ../univariate_analysis/logs
mkdir -p ../univariate_analysis/outputs
mkdir -p ../4_Stability_Selection_LASSO/logs
mkdir -p ../4_Stability_Selection_LASSO/outputs
mkdir -p ../5_Xgboost/logs
mkdir -p ../5_Xgboost/outputs
mkdir -p ../6_DAG/logs
mkdir -p ../6_DAG/outputs
mkdir -p ../7_Clustering/logs
mkdir -p ../7_Clustering/outputs
mkdir -p ../8_NN/logs
mkdir -p ../8_NN/outputs
mkdir -p ../9_LVQ/logs
mkdir -p ../9_LVQ/outputs
mkdir -p ../10_Kmeiods/logs
mkdir -p ../10_Kmeiods/outputs
mkdir -p ../10_Kmeiods/logs_sex
mkdir -p ../10_Kmeiods/outputs_sex

# Block 0: environments
JOB1=$(qsub ../Bash/0_0_0_environments_launcher.sh)
echo "Environments submitted: $JOB1"

# Block 0: data extraction 
JOB2=$(qsub -W depend=afterok:$JOB1 ../Bash/0_1_generate_data_dict.sh)
echo "Generate data dict submitted: $JOB2"
JOB3=$(qsub -W depend=afterok:$JOB2 ../Bash/0_2_extract_selected.sh)
echo "Extract selected submitted: $JOB3"
JOB4=$(qsub -W depend=afterok:$JOB3 ../Bash/0_3_recode_extracted.sh)
echo "Recode extracted submitted: $JOB4"
JOB5=$(qsub -W depend=afterok:$JOB4 ../Bash/0_4_merge_cvd.sh)
echo "Merge CVD submitted: $JOB5"

# Block 1: preprocessing 
JOB6=$(qsub -W depend=afterok:$JOB5 ../Bash/1_1_Preprocessing.sh)
echo "Preprocessing submitted: $JOB6"
JOB7=$(qsub -W depend=afterok:$JOB6 ../Bash/1_2_NA_Screening.sh)
echo "NA Screening submitted: $JOB7"

# Block 2: imputation
JOB8=$(qsub -W depend=afterok:$JOB7 ../Bash/2_1_Imputation.sh)
echo "Imputation submitted: $JOB8"
JOB9=$(qsub -W depend=afterok:$JOB8 ../Bash/2_2_Table_1.sh)
echo "Table1 submitted: $JOB9"

# Block 3: correlation 
JOB10=$(qsub -W depend=afterok:$JOB9  ../Bash/3_1_Correlation.sh)
echo "Correlation submitted: $JOB10"
JOB11=$(qsub -W depend=afterok:$JOB10 ../Bash/3_2_univariate_analysis.sh)
echo "Univariate submitted: $JOB11"

# Block 4: lasso
JOB12=$(qsub -W depend=afterok:$JOB11 ../Bash/4_1_lasso.sh)
echo "Lasso submitted: $JOB12"
JOB13=$(qsub -W depend=afterok:$JOB12 ../Bash/4_2_sex_lasso.sh)
echo "Sex lasso submitted: $JOB13"
JOB14=$(qsub -W depend=afterok:$JOB13 ../Bash/4_3_age_lasso.sh)
echo "Age lasso submitted: $JOB14"
JOB15=$(qsub -W depend=afterok:$JOB14 ../Bash/4_4_rf_lasso.sh)
echo "RF lasso submitted: $JOB15"

# Block 5: xgboost
JOB16=$(qsub -W depend=afterok:$JOB15 ../Bash/5_1_Xgboost.sh)
echo "Xgboost submitted: $JOB16"

# Block 6: DAG
JOB17=$(qsub -W depend=afterok:$JOB16 ../Bash/6_1_DAG.sh)
echo "DAG submitted: $JOB17"

# Block 7: clustering 
JOB18=$(qsub -W depend=afterok:$JOB17 ../Bash/7_1_Clustering.sh)
echo "Clustering submitted: $JOB18"

# Block 8: NN
JOB19=$(qsub -W depend=afterok:$JOB18 ../Bash/8_1_MLP_optuna.sh)
echo "MLP optuna submitted: $JOB19"
JOB20=$(qsub -W depend=afterok:$JOB19 ../Bash/8_2_MLP_paper.sh)
echo "MLP paper submitted: $JOB20"
JOB21=$(qsub -W depend=afterok:$JOB20 ../Bash/8_3_MLP_compare.sh)
echo "MLP compare submitted: $JOB21"

# Block 9: LVQ
JOB22=$(qsub -W depend=afterok:$JOB21 ../Bash/9_1_param.sh)
echo "LVQ param submitted: $JOB22"
JOB23=$(qsub -W depend=afterok:$JOB22 ../Bash/9_2_train.sh)
echo "LVQ train submitted: $JOB23"

# Block 10: kmedoids
JOB24=$(qsub -W depend=afterok:$JOB23 ../Bash/10_1_model.sh)
echo "Kmedoids submitted: $JOB24"
JOB25=$(qsub -W depend=afterok:$JOB24 ../Bash/10_2_model_sex.sh)
echo "Kmedoids sex submitted: $JOB25"

echo "All jobs submitted sequentially."