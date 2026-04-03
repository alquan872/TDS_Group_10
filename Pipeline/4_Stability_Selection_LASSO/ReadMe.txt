# README – LASSO

## Stability Selection LASSO Pipeline for CVD Prediction

### Overview

This pipeline runs LASSO-based stability selection analyses for cardiovascular disease (CVD) prediction using UK Biobank data. It comprises four scripts covering different stratification strategies and a benchmark comparison:

- **Main analysis** (`lasso_main.R`): two-model analysis on all participants
- **Sex-stratified** (`lasso_sex.R`): separate models for men and women
- **Age-stratified** (`lasso_age.R`): separate models for three age groups (<50, 50–69, 70+)
- **RF vs LASSO benchmark** (`lasso_rf_comparison.R`): comparison of LASSO against random forest

All scripts use the `sharp` package for stability selection with calibrated pi and lambda thresholds. Each produces tables, plots, model objects, and a file manifest for reproducibility.

---

### Required Libraries

The following R packages are required:

- glmnet
- igraph
- pheatmap (main script only)
- sharp
- fake
- pROC
- ggplot2
- dplyr
- tidyr
- ranger (RF comparison only)
---

### Input Files

All scripts read the same correlation-filtered UK Biobank splits in RDS format:

- `../../3_Correlation/outputs/ukb_train_drop_correlation_score.rds`
- `../../3_Correlation/outputs/ukb_val_drop_correlation_score.rds`
- `../../3_Correlation/outputs/ukb_test_drop_correlation_score.rds`

Each dataset must contain the binary outcome `cvd`, the variable `sex` (Male/Female), and `age_at_recruitment`. Complete-case analysis is applied in all scripts.

---

### Model Strategy

Each script runs two model variants:

**Model 1 — All variables:** stability selection on the full predictor set; final LASSO fitted on stable predictors.

**Model 2 — Sensitivity analysis:** one or two strong clinical predictors are excluded during variable selection, then added back into the final predictive model. This tests whether selected predictors remain informative independently of dominant variables.

| Script | Variables excluded during selection | Added back for prediction |
|---|---|---|
| Main | age_at_recruitment, systolic_bp | Both |
| Sex-stratified | age_at_recruitment, systolic_bp | Both |
| Age-stratified | systolic_bp | systolic_bp |
| RF vs LASSO | — (no stability selection) | — |

---

### Scripts

#### 1. `lasso_main.R` — Two-Model Analysis (All Participants)

Runs stability selection and LASSO evaluation on the full dataset. Outputs are saved to `outputs/`.

**Per model, saves:**
- Stable predictor bar plot, heatmap, calibration plot, validation and test ROC curves
- Calibrated parameter table, all selection proportions, stable predictors table, AUC results, test predictions
- Sharp object, selection proportions, cvfit, ROC test object

**Additional outputs:**
- Combined model comparison table
- Workspace RData file

---

#### 2. `lasso_sex.R` — Sex-Stratified Analysis

Runs the two-model pipeline separately for men and women, then compares them. Outputs are saved to `outputs_sex/`.

**Additional sex comparison outputs per model:**
- Table of predictors stable in at least one sex
- Table of predictors stable in both sexes
- Faceted selection proportion plots (any sex, both sexes)
- Combined ROC curves (men vs women) for validation and test

---

#### 3. `lasso_age.R` — Age-Stratified Analysis

Runs the two-model pipeline separately for three age groups (<50, 50–69, 70+). Outputs are saved to `outputs_age/`. Age group is derived from `age_at_recruitment`; both `age_at_recruitment` and `age_group` are excluded from the design matrix within each subgroup model.

Note: if fewer than two predictors are selected in a subgroup, model fitting is skipped for that group.

**Additional age comparison outputs per model:**
- Table of predictors stable in at least one age group
- Table of predictors stable in all age groups
- Faceted selection proportion plots (any group, all groups)
- Combined ROC curves across age groups for validation and test

---

#### 4. `lasso_rf_comparison.R` — Random Forest vs LASSO Benchmark

Trains a full LASSO and a `ranger` random forest on all variables without stability selection, and compares their AUC. Outputs are saved to `outputs_rf/`.

**Random forest settings:** 500 trees, probability predictions, permutation importance.

**LASSO settings:** `cv.glmnet` with binomial family and AUC tuning, lambda selected by cross-validation.

---

### Stability Selection Details

All stability selection runs use the following settings:

- Package: `sharp`, function `VariableSelection()`
- Family: binomial
- `n_cat = 3`
- `pi_list = seq(0.5, 0.9, by = 0.05)`
- Calibrated pi and lambda selected by `Argmax()`
- Fixed seed: 123

A predictor is considered stable if its selection proportion meets or exceeds the calibrated pi threshold.

---

### Important Notes

- Complete-case analysis is applied to all splits before modelling
- All output directories are deleted and recreated at the start of each run
- The `sex` variable is excluded from the design matrix in the sex-stratified script (stratification is done by row subsetting, not as a covariate)
- `age_at_recruitment` and `age_group` are excluded from design matrices in the age-stratified script
- Model 2 excludes the specified variables only during selection, not prediction
- A fixed random seed (123) is used throughout for reproducibility
- ROC and AUC are computed separately for validation and test sets
- Variable importance in the RF comparison reflects permutation importance, not effect direction

---

### Outputs Summary

All figures are saved in PNG and PDF format unless noted otherwise.

---

**`outputs/plots/`** (main script)
- `stable_predictors_model1_all_vars.png` / `.pdf`
- `stable_predictors_model2_no_age_sysbp.png` / `.pdf`
- `heatmap_model1_all_vars.png` / `.pdf`
- `heatmap_model2_no_age_sysbp.png` / `.pdf`
- `calibration_plot_model1_all_vars.png` / `.pdf`
- `calibration_plot_model2_no_age_sysbp.png` / `.pdf`
- `roc_validation_model1_all_vars.png` / `.pdf`
- `roc_validation_model2_no_age_sysbp.png` / `.pdf`
- `roc_test_model1_all_vars.png` / `.pdf`
- `roc_test_model2_no_age_sysbp.png` / `.pdf`

**`outputs/tables/`** (main script)
- `calibrated_parameters_model1_all_vars.csv`
- `calibrated_parameters_model2_no_age_sysbp.csv`
- `all_selection_proportions_model1_all_vars.csv`
- `all_selection_proportions_model2_no_age_sysbp.csv`
- `stable_predictors_model1_all_vars.csv`
- `stable_predictors_model2_no_age_sysbp.csv`
- `auc_results_model1_all_vars.csv`
- `auc_results_model2_no_age_sysbp.csv`
- `test_predictions_model1_all_vars.csv`
- `test_predictions_model2_no_age_sysbp.csv`
- `model_comparison.csv`
- `session_info.txt`
- `saved_files_manifest.txt`

**`outputs/models/`** (main script)
- `sharp_model1_all_vars.rds`
- `sharp_model2_no_age_sysbp.rds`
- `selprop_model1_all_vars.rds`
- `selprop_model2_no_age_sysbp.rds`
- `cvfit_model1_all_vars.rds`
- `cvfit_model2_no_age_sysbp.rds`
- `roc_test_model1_all_vars.rds`
- `roc_test_model2_no_age_sysbp.rds`
- `lasso_workspace.RData`

---

**`outputs_sex/plots_sex/`** — per model × sex combination (`model1_all_vars`, `model2_no_age_sysbp`) × (`men`, `women`)
- `roc_validation_{label}_{sex}.png` / `.pdf`
- `roc_test_{label}_{sex}.png` / `.pdf`
- `stable_predictors_any_sex_{label}.png` / `.pdf`
- `stable_predictors_both_sexes_{label}.png` / `.pdf`
- `roc_combined_test_{label}.png` / `.pdf`
- `roc_combined_validation_{label}.png` / `.pdf`

**`outputs_sex/tables_sex/`**
- `sex_split_counts.csv`
- `calibrated_parameters_{label}_{sex}.csv` (× 4 combinations)
- `stable_predictors_{label}_{sex}.csv` (× 4)
- `auc_results_{label}_{sex}.csv` (× 4)
- `test_predictions_{label}_{sex}.csv` (× 4)
- `stable_predictors_any_sex_{label}.csv` (× 2 models)
- `stable_predictors_both_sexes_{label}.csv` (× 2 models)
- `full_model_comparison.csv`
- `session_info.txt`
- `saved_files_manifest.txt`

**`outputs_sex/models_sex/`**
- `sharp_{label}_{sex}.rds` (× 4)
- `selprop_{label}_{sex}.rds` (× 4)
- `cvfit_{label}_{sex}.rds` (× 4)
- `roc_test_{label}_{sex}.rds` (× 4)
- `lasso_sex_stratified_workspace.RData`

---

**`outputs_age/plots_age/`** — per model × age group (`_50`, `_50_69`, `_70`)
- `roc_validation_model1_all_vars_age_{group}.png` / `.pdf`
- `roc_test_model1_all_vars_age_{group}.png` / `.pdf`
- `roc_validation_model2_no_sysbp_age_{group}.png` / `.pdf`
- `roc_test_model2_no_sysbp_age_{group}.png` / `.pdf`
- `stable_predictors_any_age_model1_all_vars.png` / `.pdf`
- `stable_predictors_any_age_model2_no_sysbp.png` / `.pdf`
- `stable_predictors_all_ages_model1_all_vars.png` / `.pdf`
- `stable_predictors_all_ages_model2_no_sysbp.png` / `.pdf`
- `roc_combined_test_model1_all_vars.png` / `.pdf`
- `roc_combined_test_model2_no_sysbp.png` / `.pdf`
- `roc_combined_validation_model1_all_vars.png` / `.pdf`
- `roc_combined_validation_model2_no_sysbp.png` / `.pdf`

**`outputs_age/tables_age/`**
- `age_split_counts.csv`
- `calibrated_parameters_{label}_age_{group}.csv` (× 6)
- `stable_predictors_{label}_age_{group}.csv` (× 6)
- `auc_results_{label}_age_{group}.csv` (× 6)
- `test_predictions_{label}_age_{group}.csv` (× 6, where model fitted)
- `stable_predictors_any_age_{label}.csv` (× 2 models)
- `stable_predictors_all_ages_{label}.csv` (× 2 models)
- `full_model_comparison.csv`
- `session_info.txt`
- `saved_files_manifest.txt`

**`outputs_age/models_age/`**
- `sharp_{label}_age_{group}.rds` (× 6)
- `selprop_{label}_age_{group}.rds` (× 6)
- `cvfit_{label}_age_{group}.rds` (× 6, where model fitted)
- `roc_test_{label}_age_{group}.rds` (× 6, where model fitted)
- `lasso_age_stratified_workspace.RData`

---

**`outputs_rf/plots_rf/`**
- `roc_lasso_validation.png` / `.pdf`
- `roc_lasso_test.png` / `.pdf`
- `roc_rf_validation.png` / `.pdf`
- `roc_rf_test.png` / `.pdf`
- `roc_combined_validation.png` / `.pdf`
- `roc_combined_test.png` / `.pdf`
- `rf_variable_importance_top20.png` / `.pdf`

**`outputs_rf/tables_rf/`**
- `data_split_summary.csv`
- `lasso_auc.csv`
- `lasso_test_predictions.csv`
- `rf_auc.csv`
- `rf_test_predictions.csv`
- `rf_variable_importance.csv`
- `auc_comparison.csv`
- `session_info.txt`
- `saved_files_manifest.txt`

**`outputs_rf/models_rf/`**
- `lasso_cvfit.rds`
- `lasso_roc_test.rds`
- `rf_model.rds`
- `rf_roc_test.rds`
- `rf_lasso_workspace.RData`

---

End of file