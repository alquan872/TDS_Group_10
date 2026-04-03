# README – DAG

## Directed Acyclic Graph Pipeline for Selected Predictors

### Overview

This script builds and saves directed acyclic graphs (DAGs) for predictor sets identified by previous modelling workflows. It uses selected variables from LASSO and XGBoost outputs, combines them with predefined confounders, fits logistic regression models, applies multiple-testing correction, and retains variables for DAG visualisation based on adjusted significance.

For each model input, the script creates two DAG versions: one including age and sex as confounders, and one excluding them. The workflow also saves regression summaries, edge tables, fitted models, graph objects, and a file manifest.

---

### Required Libraries

The following R packages are required:

- dplyr
- ggplot2
- dagitty
- ggdag
---

### Input Files

The script reads the main UK Biobank dataset:

- `../../3_Correlation/outputs/ukb_all_drop_correlation_score.rds`

It also reads selected predictor tables from earlier modelling pipelines:

**LASSO:**
- `../../4_Stability_Selection_LASSO/outputs/tables/stable_predictors_model1_all_vars.csv`
- `../../4_Stability_Selection_LASSO/outputs/tables/stable_predictors_model2_no_age_sysbp.csv`

**XGBoost:**
- `../../5_Xgboost/outputs/stable_predictors_model1_all_vars_xgb_importance_nonzero_ranked.csv`
- `../../5_Xgboost/outputs/stable_predictors_model2_no_age_sysbp_xgb_importance_nonzero_ranked.csv`

The script automatically detects the predictor column name by checking for: `predictor`, `predictors`, `feature`, `variable`.

---

### Output Structure

All outputs are saved into the following folders, created if missing but not deleted between runs:

- `outputs/plots/` → DAG figures in PNG and PDF format
- `outputs/tables/` → regression summaries, edge tables, and file manifest
- `outputs/models/` → fitted logistic models and DAG plot objects as RDS
- `outputs/logs/` → folder created for run outputs if needed

---

### Main Purpose

This script takes predictor sets from earlier machine learning or feature selection workflows and turns them into interpretable DAG-style summaries by:

- selecting variables present in the main dataset
- adjusting for age and sex
- fitting a logistic regression model for CVD
- correcting p-values using the Benjamini–Hochberg method
- retaining significant predictors for graph construction
- building simplified DAG structures for visualisation

---

### Models Included

The script builds DAG outputs for four model inputs:

- LASSO model 1 (all variables)
- LASSO model 2 (excluding age and systolic blood pressure during selection)
- XGBoost model 1 (all variables)
- XGBoost model 2 (excluding age and systolic blood pressure during selection)

Each generates a DAG with age and sex, a DAG without age and sex, regression and edge summary tables, and saved model objects.

---

### DAG Construction

For each model, two DAGs are built:

**DAG with age and sex:** confounders point to selected variables, confounders point to the outcome, and selected variables point to the outcome.

**DAG without age and sex:** selected variables point directly to the outcome only.

DAG objects are created using `dagitty` with custom coordinates (confounders at y=3, variables at y=2, outcome at y=1) and plotted with `ggdag`.

---

### Logistic Regression Filtering

For each predictor set a logistic regression is fitted with `cvd` as the outcome and age and sex as confounders. Benjamini–Hochberg correction is applied to all p-values. Predictors with adjusted p-value below 0.05 are retained for DAG construction. If no predictors pass this threshold, the top five by adjusted p-value are retained instead.

---

### Important Notes

- Output folders are created if missing but are not deleted before each run
- The `sex` variable is recoded internally: Male / male / 1 → 1, all other values → 0
- `cvd` is converted to numeric before modelling
- Only variables present in the main dataset are used; others are silently dropped
- Missing data are handled by complete-case analysis within each model run
- DAGs are constructed from predefined directional rules, not learned causally from data

---

### Outputs Summary

All figures are saved in PNG and PDF format unless noted otherwise.

**`outputs/plots/`**
- `lasso_model1_with_age_sex.png` / `.pdf`
- `lasso_model1_without_age_sex.png` / `.pdf`
- `lasso_model2_with_age_sex.png` / `.pdf`
- `lasso_model2_without_age_sex.png` / `.pdf`
- `xgboost_model1_with_age_sex.png` / `.pdf`
- `xgboost_model1_without_age_sex.png` / `.pdf`
- `xgboost_model2_with_age_sex.png` / `.pdf`
- `xgboost_model2_without_age_sex.png` / `.pdf`

**`outputs/tables/`**
- `lasso_model1_regression_summary.csv`
- `lasso_model1_edges_with_age_sex.csv`
- `lasso_model1_edges_without_age_sex.csv`
- `lasso_model2_regression_summary.csv`
- `lasso_model2_edges_with_age_sex.csv`
- `lasso_model2_edges_without_age_sex.csv`
- `xgboost_model1_regression_summary.csv`
- `xgboost_model1_edges_with_age_sex.csv`
- `xgboost_model1_edges_without_age_sex.csv`
- `xgboost_model2_regression_summary.csv`
- `xgboost_model2_edges_with_age_sex.csv`
- `xgboost_model2_edges_without_age_sex.csv`
- `saved_files_manifest.txt`

**`outputs/models/`**
- `lasso_model1_dag_with_age_sex.rds`
- `lasso_model1_dag_without_age_sex.rds`
- `lasso_model1_logistic_model.rds`
- `lasso_model2_dag_with_age_sex.rds`
- `lasso_model2_dag_without_age_sex.rds`
- `lasso_model2_logistic_model.rds`
- `xgboost_model1_dag_with_age_sex.rds`
- `xgboost_model1_dag_without_age_sex.rds`
- `xgboost_model1_logistic_model.rds`
- `xgboost_model2_dag_with_age_sex.rds`
- `xgboost_model2_dag_without_age_sex.rds`
- `xgboost_model2_logistic_model.rds`

---

End of file