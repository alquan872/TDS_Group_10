# README – Univariate Analysis

## Univariate Analysis and Random Forest Pipeline for CVD Prediction

### Overview

This script performs a full analysis pipeline on a test dataset to investigate predictors of cardiovascular disease (CVD). It combines descriptive statistics, univariate logistic regression, and a random forest model to identify and evaluate important variables.

The workflow automatically organises outputs into structured folders and saves all intermediate and final results for reproducibility.

---

### Required Libraries

The following R packages are required:

- dplyr
- ggplot2
- knitr
- kableExtra
- parallel
- ranger
- pROC
- ggrepel
---

### Input Files

The script expects a single RDS file:

- `../../3_Correlation/outputs/ukb_test_drop_correlation_score.rds`

The outcome variable must be named `cvd` and encoded as binary (0/1). The dataset should already be preprocessed with high-correlation variables removed.

---

### Output Structure

All outputs are saved into the following folders, cleared and recreated at the start of each run:

- `outputs/plots/` → figures in PNG and PDF format
- `outputs/tables/` → CSV and HTML tables
- `outputs/models/` → RDS model objects and workspace files
- `outputs/logs/` → session info and file manifest

---

### Main Steps

**1. Setup** — sets the working directory automatically, creates clean output folders, and loads all libraries.

**2. Dataset summary** — reports number of rows and columns, lists all predictor variables, computes CVD prevalence (counts and percentages), saves summary tables and a bar plot.

**3. Univariate logistic regression** — runs independent logistic regression for each predictor using parallel processing. Extracts odds ratios, 95% Wald confidence intervals, and p-values for all variables.

**4. Visualisation** — produces a forest plot of all significant predictors (p < 0.05), a forest plot of the top 20 by p-value, and a Manhattan plot of −log10(p-values) with nominal (p=0.05) and Bonferroni thresholds. Truncated points on the Manhattan plot are shown as triangles with their true −log10(p) value labelled.

**5. Random forest — variable importance** — trains a `ranger` model on all complete cases with permutation importance. Outputs a full importance table and a top-20 bar chart.

**6. Random forest — AUC evaluation** — splits data 70/30, trains a second random forest, generates predicted probabilities, and computes ROC curve and AUC.

**7. Reproducibility outputs** — saves workspace objects, session information, and a manifest of all output files.

---

### Important Notes

- Complete-case analysis is used for all modelling steps
- Logistic regression results are unadjusted (univariate only)
- Parallel processing uses `detectCores() - 1` cores
- Random forest uses 500 trees with a fixed seed (123)
- Character variables are converted to factors before random forest fitting
- The Manhattan plot Y-axis is capped just above the 4th highest value to keep the bulk of significant points visible; truncated values are labelled

---

### Outputs Summary

All figures are saved in PNG and PDF format unless noted otherwise.

**`outputs/plots/`**
- `q1_5_cvd_prevalence_bar_plot.png` / `.pdf`
- `q1_5_significant_predictors_forest_plot.png` / `.pdf`
- `q1_5_top20_significant_predictors_forest_plot.png` / `.pdf`
- `q1_5_manhattan_plot.png` / `.pdf`
- `q1_5_random_forest_importance_top20.png` / `.pdf`
- `q1_5_random_forest_auc_roc_curve.png` / `.pdf`

**`outputs/tables/`**
- `q1_5_dataset_summary.csv`
- `q1_5_variables_tested.csv`
- `q1_5_cvd_prevalence_summary.csv`
- `q1_5_cvd_prevalence_table.csv`
- `q1_5_cvd_prevalence_table.html`
- `q1_5_univariate_logistic_results_all.csv`
- `q1_5_significant_predictors_table.csv`
- `q1_5_significant_predictors_table.html`
- `q1_5_significant_predictors_plot_data.csv`
- `q1_5_top20_significant_predictors_plot_data.csv`
- `q1_5_manhattan_plot_data.csv`
- `q1_5_rf_character_variables_converted_to_factor.csv`
- `q1_5_random_forest_variable_importance_all.csv`
- `q1_5_random_forest_variable_importance_top20.csv`
- `q1_5_random_forest_auc_predictions.csv`
- `q1_5_random_forest_auc_results.csv`

**`outputs/models/`**
- `q1_5_cvd_prevalence_plot.rds`
- `q1_5_univariate_logit_results_list.rds`
- `q1_5_univariate_logistic_results_all.rds`
- `q1_5_significant_predictors_plot.rds`
- `q1_5_top20_significant_predictors_plot.rds`
- `q1_5_manhattan_plot.rds`
- `q1_5_ranger_model.rds`
- `q1_5_random_forest_importance_plot.rds`
- `q1_5_ranger_auc_model.rds`
- `q1_5_random_forest_roc_object.rds`
- `q1_5_workspace_objects.RData`
- `q1_5_full_workspace.RData`

**`outputs/logs/`**
- `q1_5_session_info.txt`
- `q1_5_saved_files_manifest.txt`

---

End of file