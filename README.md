# TDS Group 10 Pipeline

## Overview

This repository contains the full end-to-end computational pipeline used to process, clean, model, and analyse the TDS Group 10 dataset for cardiovascular disease (CVD)-related research questions. The workflow is designed to run on an HPC cluster using **PBS job scheduling** and a combination of **R** and **Python** environments managed with **conda**.

The pipeline is organised into modular stages, from raw data extraction to downstream modelling and clustering.

- The **master launcher** runs the **entire pipeline sequentially**, from environment setup to the final modelling and clustering stages.
- The **individual launchers** are included so that a **specific block or model can be run separately**, for example for debugging, rerunning only one step, or updating one analysis without recomputing the full workflow.

---

## Main objectives of the pipeline

The pipeline covers the following stages:

1. **Environment setup**
2. **Raw data extraction and harmonisation**
3. **Preprocessing and NA screening**
4. **Imputation and descriptive Table 1 generation**
5. **Correlation and univariate analysis**
6. **Feature selection with stability-selection LASSO**
7. **Predictive modelling with XGBoost**
8. **DAG construction / causal structure work**
9. **Clustering analysis**
10. **Neural network modelling**
11. **LVQ / GRLVQ modelling**
12. **K-medoids clustering**

---

## Repository structure

```text
Pipeline/
├── 0_extract_data/
│   ├── docs/
│   ├── parameters/
│   ├── scripts/
│   └── ReadMe.txt
├── 1_recoding_extraction_preprocessing/
│   ├── script/
│   └── ReadMe.txt
├── 2_Imputation/
│   ├── script/
│   └── ReadMe.txt
├── 3_Correlation/
│   ├── script/
│   └── ReadMe.txt
├── 4_Stability_Selection_LASSO/
│   ├── scripts/
│   └── ReadMe.txt
├── 5_Xgboost/
│   ├── script/
│   └── ReadMe.txt
├── 6_DAG/
│   ├── script/
│   └── ReadMe.txt
├── 7_Clustering/
│   ├── scripts/
│   └── ReadMe.txt
├── 8_NN/
│   ├── scripts/
│   └── ReadMe.txt
├── 9_LVQ/
│   ├── scripts/
│   └── ReadMe.txt
├── 10_Kmeiods/
│   ├── scripts/
│   └── ReadMe.txt
├── environments/
├── table_1/
├── univariate_analysis/
└── Bash/
```

---

## Global flow of the pipeline

### High-level flow

```text
Raw UKB tabular data
        |
        v
[0] Data dictionary generation
        |
        v
[0] Selected variable extraction
        |
        v
[0] Variable recoding
        |
        v
[0] Merge with CVD outcome
        |
        v
[1] Preprocessing
        |
        v
[1] NA screening / cleaning
        |
        v
[2] Imputation
        |
        +------------------> [2] Table 1
        |
        v
[3] Correlation analysis
        |
        +------------------> [3] Univariate analysis
        |
        v
[4] Stability-selection LASSO
        |
        v
[5] XGBoost
        |
        v
[6] DAG
        |
        v
[7] Clustering
        |
        v
[8] Neural networks
        |
        v
[9] LVQ / GRLVQ
        |
        v
[10] K-medoids / sex-stratified K-medoids
```

### Execution logic in the master launcher

```text
Environments
   -> Data extraction block
   -> Preprocessing block
   -> Imputation + Table 1
   -> Correlation + Univariate analysis
   -> LASSO block
   -> XGBoost
   -> DAG
   -> Clustering
   -> Neural network block
   -> LVQ block
   -> K-medoids block
```

### Dependency scheme

```text
0_0_0_environments_launcher.sh
    -> 0_1_generate_data_dict.sh
        -> 0_2_extract_selected.sh
            -> 0_3_recode_extracted.sh
                -> 0_4_merge_cvd.sh
                    -> 1_1_Preprocessing.sh
                        -> 1_2_NA_Screening.sh
                            -> 2_1_Imputation.sh
                                -> 2_2_Table1.sh
                                    -> 3_1_Correlation.sh
                                        -> 3_2_univariate_analysis.sh
                                            -> 4_1_lasso.sh
                                                -> 4_2_sex_lasso.sh
                                                    -> 4_3_age_lasso.sh
                                                        -> 4_4_rf_lasso.sh
                                                            -> 5_1_Xgboost.sh
                                                                -> 6_1_DAG.sh
                                                                    -> 7_1_Clustering.sh
                                                                        -> 8_1_MLP_optuna.sh
                                                                            -> 8_2_MLP_paper.sh
                                                                                -> 8_3_MLP_compare.sh
                                                                                    -> 9_1_param.sh
                                                                                        -> 9_2_train.sh
                                                                                            -> 10_1_model.sh
                                                                                                -> 10_2_model_sex.sh
```

---

## Environments

The pipeline uses several conda environments depending on the stage:

- **group10_R**: main R environment for extraction, preprocessing, imputation, Table 1, correlation, univariate analysis, DAG, and LASSO.
- **group10_python**: Python environment for XGBoost, clustering, neural networks, and LVQ / GRLVQ.
- **group10_kmedoids**: Python environment dedicated to K-medoids analyses.
- **tds_env**: environment used in the Table 1 step according to the current launcher.

### Environment installation launcher

`0_0_0_environments_launcher.sh` installs R packages from inside the `environments/` folder.

#### What it does

- Requests 1 CPU, 10 GB RAM, 1 hour.
- Moves into `../environments`.
- Activates `group10_R`.
- Runs `packages.R`.

#### Script summary

```bash
eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate group10_R
Rscript packages.R
```

#### Expected purpose

This step prepares the required R package ecosystem before running the rest of the workflow.

---

## Block 0: data extraction and initial harmonisation

This block creates the analytical base dataset starting from the raw tabular UK Biobank-like source.

### Inputs

- Raw dataset:
  `/rds/general/project/hda_25-26/live/TDS/General/Data/tabular.tsv`
- Extraction parameters and codings:
  - `0_extract_data/parameters/parameters.xlsx`
  - `0_extract_data/parameters/selection.xlsx`
  - `0_extract_data/parameters/codings/`
  - documentation files in `0_extract_data/docs/`

### Outputs

A progressively filtered, recoded, and merged dataset ready for preprocessing.

### Flow inside block 0

```text
1-make_data_dict.R
    -> creates a data dictionary from raw tabular input
2-extract_selected.R
    -> extracts the selected variables based on the parameter files
3-recode_variables.R
    -> applies recoding / harmonisation rules
4-merge_cvd.R
    -> merges processed data with the CVD outcome definition
```

### Launcher: `0_0_data_extraction_launcher.sh`

This launcher:

- creates the required output and log folders,
- submits each extraction step,
- links them with `afterok` dependencies.

### Step-by-step jobs

#### 0_1_generate_data_dict.sh

**Purpose**  
Builds a data dictionary directly from the raw `.tsv` source.

**Resources**  
- 30 min
- 1 CPU
- 10 GB RAM

**Main script called**  
`1-make_data_dict.R`

**Environment**  
`group10_R`

**Key details**  
- Activates `group10_R`
- Passes the UKB path as a command-line argument
- Saves cluster and R logs into `0_extract_data/logs/`

---

#### 0_2_extract_selected.sh

**Purpose**  
Extracts the variables of interest from the raw tabular dataset.

**Resources**  
- 4 hours
- 1 CPU
- 50 GB RAM

**Main script called**  
`2-extract_selected.R`

**Environment**  
`group10_R`

**Key details**  
- Uses the data dictionary / parameter selection files
- Produces a reduced dataset containing only required variables

---

#### 0_3_recode_extracted.sh

**Purpose**  
Recodes extracted variables into analysis-ready representations.

**Resources**  
- 2 hours
- 1 CPU
- 50 GB RAM

**Main script called**  
`3-recode_variables.R`

**Environment**  
`group10_R`

**Typical tasks expected here**

- categorical harmonisation,
- removal or relabelling of special values,
- coding transformations,
- derivation of cleaner feature representations.

---

#### 0_4_merge_cvd.sh

**Purpose**  
Merges the extracted and recoded data with the target CVD outcome.

**Resources**  
- 24 hours
- 8 CPUs
- 64 GB RAM

**Main script called**  
`4-merge_cvd.R`

**Environment**  
`group10_R`

**Expected result**  
A merged dataset that becomes the starting point for preprocessing.

---

## Block 1: preprocessing and NA screening

This block prepares the merged extracted dataset for imputation and downstream modelling.

### Flow

```text
Merged extracted dataset
      -> 1_Preprocessing.R
      -> 2_NA_cleaning.R
```

### Launcher: `1_0_Preprocessing_screening_launcher.sh`

This launcher:

- creates logs and outputs directories,
- submits preprocessing,
- then submits NA screening after preprocessing succeeds.

### 1_1_Preprocessing.sh

**Purpose**  
Runs the main preprocessing pipeline.

**Resources**  
- 24 hours
- 8 CPUs
- 256 GB RAM

**Main script called**  
`1_Preprocessing.R`

**Environment**  
`group10_R`

**Potential tasks in this step**

- variable renaming,
- feature engineering,
- type corrections,
- derivation of final analysis-ready fields,
- train/validation/test preparation if implemented there.

### 1_2_NA_Screening.sh

**Purpose**  
Screens missingness and performs NA cleaning after preprocessing.

**Resources**  
- 30 min
- 8 CPUs
- 64 GB RAM

**Main script called**  
`2_NA_cleaning.R`

**Environment**  
`group10_R`

**Expected tasks**

- missingness inspection,
- filtering problematic variables or rows,
- producing NA summaries for later imputation decisions.

---

## Block 2: imputation and Table 1

This block imputes the cleaned dataset and then generates the main descriptive summary table.

### Flow

```text
Preprocessed + NA-cleaned dataset
        -> 2_Imputation.R
        -> Table1.R
```

### Launcher: `2_0_imputation_table_launcher.sh`

This launcher:

- creates logs and outputs for both imputation and Table 1,
- submits imputation first,
- launches Table 1 after imputation completes successfully.

### 2_1_Imputation.sh

**Purpose**  
Imputes missing values in the processed dataset.

**Resources**  
- 24 hours
- 8 CPUs
- 256 GB RAM

**Main script called**  
`2_Imputation.R`

**Environment**  
`group10_R`

**Comment**  
This is one of the most computationally expensive R stages in the pipeline.

### 2_2_Table1.sh

**Purpose**  
Generates the descriptive baseline Table 1 from the imputed dataset.

**Resources**  
- 3 hours
- 8 CPUs
- 64 GB RAM

**Main script called**  
`Table1.R`

**Environment**  
`tds_env`

**Expected outputs**

- descriptive cohort table,
- summary statistics for paper/reporting use.

---

## Block 3: correlation and univariate analysis

This stage performs exploratory variable analysis after imputation.

### Flow

```text
Imputed dataset
    -> 3_Correlation.R
    -> univariate_analysis.R
```

### Launcher: `3_0_correlation_uv_launcher.sh`

This launcher:

- creates directories for both correlation and univariate outputs,
- submits the correlation analysis,
- then runs univariate analysis after it finishes.

### 3_1_Correlation.sh

**Purpose**  
Computes correlation structures across the dataset.

**Resources**  
- 4 hours
- 16 CPUs
- 128 GB RAM

**Main script called**  
`3_Correlation.R`

**Environment**  
`group10_R`

**Expected outputs**

- correlation matrices,
- highly correlated feature reports,
- plots or summary tables for redundancy assessment.

### 3_2_univariate_analysis.sh

**Purpose**  
Performs univariate statistical analysis.

**Resources**  
- 3 hours
- 8 CPUs
- 64 GB RAM

**Main script called**  
`univariate_analysis.R`

**Environment**  
`group10_R`

**Expected outputs**

- per-variable significance screening,
- summary tables and/or plots,
- support for variable prioritisation.

---

## Block 4: stability-selection LASSO

This block addresses **RQ1-style feature selection**, with multiple LASSO analyses exploring the effect of sex, age, and model comparison.

### Internal flow

```text
Q1_1_lasso_basic_model.R
    -> Q1_2_lasso_sex.R
        -> Q1_3_lasso_age.R
            -> Q1_4_lasso_AUC_rf_vs_LASSO.R
```

### Launcher: `4_0_lasso_launcher.sh`

Sequentially runs four LASSO-related jobs.

### 4_1_lasso.sh

**Purpose**  
Runs the baseline stability-selection LASSO model.

**Resources**  
- 8 hours
- 8 CPUs
- 64 GB RAM

**Main script called**  
`Q1_1_lasso_basic_model.R`

**Environment**  
`group10_R`

### 4_2_sex_lasso.sh

**Purpose**  
Runs the LASSO analysis with sex-related modelling or stratification.

**Resources**  
- 8 hours
- 8 CPUs
- 64 GB RAM

**Main script called**  
`Q1_2_lasso_sex.R`

**Environment**  
`group10_R`

### 4_3_age_lasso.sh

**Purpose**  
Runs the age-focused LASSO analysis.

**Resources**  
- 8 hours
- 8 CPUs
- 64 GB RAM

**Main script called**  
`Q1_3_lasso_age.R`

**Environment**  
`group10_R`

### 4_4_rf_lasso.sh

**Purpose**  
Compares LASSO against an RF/AUC benchmark.

**Resources**  
- 8 hours
- 8 CPUs
- 64 GB RAM

**Main script called**  
`Q1_4_lasso_AUC_rf_vs_LASSO.R`

**Environment**  
`group10_R`

**Expected outputs across the LASSO block**

- selected variables,
- selection frequencies / stability metrics,
- sex- and age-related comparisons,
- AUC comparison between LASSO and RF-based approaches.

---

## Block 5: XGBoost

This block trains an XGBoost model for predictive modelling and feature importance analysis.

### Launcher: `5_0_Xgboost_launcher.sh`

Creates directories and submits the XGBoost job.

### 5_1_Xgboost.sh

**Purpose**  
Runs the Python XGBoost modelling stage.

**Resources**  
- 48 hours
- 8 CPUs
- 256 GB RAM

**Main script called**  
`5_Xgboost.py`

**Environment**  
`group10_python`

**Expected outputs**

- trained XGBoost model,
- performance metrics,
- feature importance / SHAP-style downstream summaries if implemented.

---

## Block 6: DAG

This block runs the DAG analysis / causal structure step.

### Launcher: `6_0_DAG_launcher.sh`

Creates logs and outputs, then submits the DAG job.

### 6_1_DAG.sh

**Purpose**  
Runs DAG construction or DAG-based causal analysis.

**Resources**  
- 1 hour
- 8 CPUs
- 64 GB RAM

**Main script called**  
`6_DAG.R`

**Environment**  
`group10_R`

**Expected outputs**

- DAG figures,
- causal structure files,
- reports supporting downstream interpretation.

---

## Block 7: clustering

This block performs clustering analysis, likely around phenotype discovery or subgroup structure.

### Launcher: `7_0_clustering_launcher.sh`

Creates directories and submits clustering.

### 7_1_Clustering.sh

**Purpose**  
Runs the clustering workflow.

**Resources**  
- 8 hours
- 8 CPUs
- 64 GB RAM

**Main script called**  
`clustering.py`

**Environment**  
`group10_python`

**Notable directories created**

- `outputs/gmm_plots/`
- `outputs/tables/`

**Interpretation**  
This suggests the script likely produces clustering plots and tabular summaries, possibly involving Gaussian mixture model visualisations even if the folder is within the clustering block.

---

## Block 8: neural networks

This block trains and compares MLP-based neural network models.

### Internal flow

```text
NN_optuna.py
    -> NN_paper.py
        -> NN_comparison.py
```

### Launcher: `8_0_NN_launcher.sh`

Submits three sequential jobs for optimisation, final paper-style training, and comparison.

### 8_1_MLP_optuna.sh

**Purpose**  
Hyperparameter optimisation for the neural network using Optuna.

**Resources**  
- 6 hours
- 16 CPUs
- 256 GB RAM

**Main script called**  
`NN_optuna.py`

**Environment**  
`group10_python`

### 8_2_MLP_paper.sh

**Purpose**  
Runs the selected final neural network configuration.

**Resources**  
- 6 hours
- 16 CPUs
- 256 GB RAM

**Main script called**  
`NN_paper.py`

**Environment**  
`group10_python`

### 8_3_MLP_compare.sh

**Purpose**  
Compares neural network models or compares NN against alternative approaches.

**Resources**  
- 1 hour
- 16 CPUs
- 256 GB RAM

**Main script called**  
`NN_comparison.py`

**Environment**  
`group10_python`

**Expected outputs**

- Optuna tuning logs,
- final trained MLP,
- comparison metrics and summary tables/plots.

---

## Block 9: LVQ / GRLVQ

This block performs LVQ-based modelling, including hyperparameter optimisation and final training.

### Internal flow

```text
LVQ_param.py
    -> LVQ_train.py
```

### Launcher: `9_0_lvq_launcher.sh`

Creates directories and runs the two-step LVQ workflow.

### 9_1_param.sh

**Purpose**  
Optimises LVQ / GRLVQ parameters.

**Resources**  
- 48 hours
- 16 CPUs
- 256 GB RAM

**Main script called**  
`LVQ_param.py`

**Environment**  
`group10_python`

### 9_2_train.sh

**Purpose**  
Trains the final LVQ / GRLVQ model using selected parameters.

**Resources**  
- 48 hours
- 16 CPUs
- 256 GB RAM

**Main script called**  
`LVQ_train.py`

**Environment**  
`group10_python`

**Expected outputs**

- tuned LVQ hyperparameters,
- trained LVQ / GRLVQ model,
- evaluation metrics and logs.

---

## Block 10: K-medoids

This block performs K-medoids clustering, including a sex-stratified analysis.

### Internal flow

```text
cluster.py
    -> cluster_sex.py
```

### Launcher: `10_0_kmeiods_launcher.sh`

Creates standard and sex-specific folders, then submits two dependent K-medoids jobs.

### 10_1_model.sh

**Purpose**  
Runs the main K-medoids clustering model.

**Resources**  
- 48 hours
- 16 CPUs
- 512 GB RAM

**Main script called**  
`cluster.py`

**Environment**  
`group10_kmedoids`

### 10_2_model_sex.sh

**Purpose**  
Runs sex-stratified K-medoids clustering.

**Resources**  
- 48 hours
- 16 CPUs
- 512 GB RAM

**Main script called**  
`cluster_sex.py`

**Environment**  
`group10_kmedoids`

**Expected outputs**

- cluster assignments,
- sex-specific clustering results,
- logs stored separately in `logs/` and `logs_sex/`.

---

## Master launcher

The script `master_launcher_pipeline.sh` is the full orchestration entry point for the entire project.

### What it does

1. Creates all required log and output directories.
2. Submits all jobs in strict sequence.
3. Uses PBS dependencies (`-W depend=afterok:<jobid>`) so each job only starts if the previous one completed successfully.
4. Runs the **full pipeline end-to-end**, from environment setup to the final K-medoids analyses.

### Conceptual flow of the master launcher

```text
[Environment setup]
        |
        v
[Extraction + recoding + CVD merge]
        |
        v
[Preprocessing + NA screening]
        |
        v
[Imputation + Table 1]
        |
        v
[Correlation + Univariate]
        |
        v
[LASSO sequence]
        |
        v
[XGBoost]
        |
        v
[DAG]
        |
        v
[Clustering]
        |
        v
[NN sequence]
        |
        v
[LVQ sequence]
        |
        v
[K-medoids sequence]
```

### To launch the full pipeline

From the `Bash/` directory context used by the scripts:

```bash
qsub master_launcher_pipeline.sh
```

---

## How to run individual blocks

If only one part of the pipeline needs to be rerun, the corresponding launcher can be submitted directly. These individual launchers are intended for running **one block or one model separately**, rather than the entire workflow.

### Examples

```bash
qsub 0_0_0_environments_launcher.sh
qsub 1_0_Preprocessing_screening_launcher.sh
qsub 2_0_imputation_table_launcher.sh
qsub 3_0_correlation_uv_launcher.sh
qsub 4_0_lasso_launcher.sh
qsub 5_0_Xgboost_launcher.sh
qsub 6_0_DAG_launcher.sh
qsub 7_0_clustering_launcher.sh
qsub 8_0_NN_launcher.sh
qsub 9_0_lvq_launcher.sh
qsub 10_0_kmeiods_launcher.sh
```

This is useful for:

- debugging a single stage,
- rerunning only one model after a code update,
- continuing from a failed block,
- avoiding recomputation of expensive early stages.

---

## Logs and outputs

Almost every block follows the same organisational logic:

- `logs/` stores PBS stdout/stderr and optionally script-specific log files.
- `outputs/` stores generated datasets, models, plots, and tables.

### Typical pattern

```text
<block>/
├── logs/
│   ├── *.out
│   ├── *.err
│   └── *_R.log or *_output.log
└── outputs/
```

### Logging design

Many scripts use:

```bash
Rscript ... 2>&1 | tee "$R_LOG"
python3 ... 2>&1 | tee "$LOGDIR/<name>.log"
```

This means output is both:

- sent to the terminal / PBS stream, and
- saved into a persistent log file for debugging.

---

## Computational profile

Some stages are lightweight, but others are computationally demanding.

### Most expensive stages

- `0_4_merge_cvd.sh`
- `1_1_Preprocessing.sh`
- `2_1_Imputation.sh`
- `5_1_Xgboost.sh`
- `8_1_MLP_optuna.sh`
- `9_1_param.sh`
- `9_2_train.sh`
- `10_1_model.sh`
- `10_2_model_sex.sh`

### Highest memory jobs

- K-medoids: **512 GB RAM**
- Several Python/R modelling steps: **256 GB RAM**

This means the full pipeline should be launched only when the required cluster resources are available.

---

## Reproducibility features

The pipeline includes several good reproducibility practices:

- modular directory organisation,
- explicit conda environments,
- PBS dependency chaining,
- separate log files for each step,
- separation between scripts, outputs, and documentation,
- support for full and partial reruns.

---

## Recommended usage pattern

### First-time run

1. Check that all conda environments exist.
2. Check that the raw dataset path is valid.
3. Check that parameter files are in place.
4. Submit the master launcher.

### Development / debugging run

1. Test the relevant R or Python script interactively.
2. Submit only the corresponding launcher.
3. Inspect `logs/` and `*.err` if a job fails.
4. Resume from the failed block instead of recomputing everything.

---

## Suggested quick start

```bash
cd /rds/general/project/hda_25-26/live/TDS/TDS_Group10/Pipeline/Bash
qsub master_launcher_pipeline.sh
```

To monitor jobs:

```bash
qstat -u $USER
```

To inspect logs:

```bash
tail -f ../4_Stability_Selection_LASSO/logs/Q1_1_lasso_outcome.log
```

---

## Block summary table

| Block | Purpose | Main language | Environment | Launcher | Main outputs |
|---|---|---|---|---|---|
| environments | Install/check required packages | R | `group10_R` | `0_0_0_environments_launcher.sh` | ready-to-use environments |
| 0_extract_data | dictionary, extraction, recoding, merge with CVD | R | `group10_R` | `0_0_data_extraction_launcher.sh` | analytical base dataset |
| 1_preprocessing | preprocessing and NA screening | R | `group10_R` | `1_0_Preprocessing_screening_launcher.sh` | cleaned dataset |
| 2_Imputation | missing data imputation | R | `group10_R` | `2_0_imputation_table_launcher.sh` | imputed dataset |
| table_1 | descriptive baseline table | R | `tds_env` | same as block 2 | Table 1 |
| 3_Correlation | exploratory correlation analysis | R | `group10_R` | `3_0_correlation_uv_launcher.sh` | correlation reports |
| univariate_analysis | per-variable association analysis | R | `group10_R` | same as block 3 | univariate results |
| 4_Stability_Selection_LASSO | feature selection and comparisons | R | `group10_R` | `4_0_lasso_launcher.sh` | selected variables, AUC comparisons |
| 5_Xgboost | predictive modelling | Python | `group10_python` | `5_0_Xgboost_launcher.sh` | model + importance summaries |
| 6_DAG | causal structure | R | `group10_R` | `6_0_DAG_launcher.sh` | DAG outputs |
| 7_Clustering | phenotype/subgroup discovery | Python | `group10_python` | `7_0_clustering_launcher.sh` | cluster plots/tables |
| 8_NN | MLP optimisation and comparison | Python | `group10_python` | `8_0_NN_launcher.sh` | tuned/final NN results |
| 9_LVQ | LVQ / GRLVQ modelling | Python | `group10_python` | `9_0_lvq_launcher.sh` | tuned and trained LVQ models |
| 10_Kmeiods | K-medoids and sex-stratified clustering | Python | `group10_kmedoids` | `10_0_kmeiods_launcher.sh` | cluster assignments |

---

## Notes and minor inconsistencies to review

A few naming inconsistencies appear across scripts and folders. They do not necessarily break the pipeline, but they are worth standardising.

### Folder naming

- `10_Kmeiods` appears to be a misspelling of `10_Kmedoids`.
- Some folders use `script/`, others use `scripts/`.

### File naming

- In the master launcher, `2_2_Table_1.sh` appears, while elsewhere the file is written as `2_2_Table1.sh` or similar.
- Some scripts use hyphens in filenames, others use underscores.

### Environment activation style

Both forms appear:

```bash
conda activate <env>
```

and

```bash
source activate <env>
```

It is safer to standardise to:

```bash
eval "$(~/anaconda3/bin/conda shell.bash hook)"
conda activate <env>
```

### Logging conventions

Most scripts use `set -euo pipefail`, but a few do not. For robustness, it is better if all launcher and job scripts include it.

---

## Recommended future improvements

To make the pipeline even more robust, the following improvements would help:

1. **Add a single configuration file** for paths, environment names, and raw input locations.
2. **Standardise naming** across all folders and scripts.
3. **Write outputs explicitly in each README** inside each block.
4. **Add file existence checks** before each stage starts.
5. **Store software versions** for R, Python, and package snapshots.
6. **Add final success/failure summaries** at the end of the master launcher.
7. **Optionally split the master pipeline** into an early-data pipeline and a modelling pipeline for faster reruns.

---

## Minimal conceptual schema for the full project

```text
RAW DATA
  |
  +--> dictionary construction
  |
  +--> selected variable extraction
  |
  +--> recoding and harmonisation
  |
  +--> merge with CVD outcome
  v
CLEAN BASE DATASET
  |
  +--> preprocessing
  +--> NA screening
  v
MODELLING-READY DATASET
  |
  +--> imputation
  +--> descriptive Table 1
  +--> correlation analysis
  +--> univariate analysis
  v
ANALYTICAL DATASET
  |
  +--> LASSO feature selection
  +--> XGBoost prediction
  +--> DAG/causal structure
  +--> clustering
  +--> neural networks
  +--> LVQ/GRLVQ
  +--> K-medoids
  v
FINAL RESULTS, TABLES, PLOTS, MODELS
```

---

## Contact / maintenance note

This README is intended as the central guide for understanding and launching the full Group 10 pipeline. Each subfolder can additionally maintain its own local `ReadMe.txt` with script-specific details, inputs, and outputs.
