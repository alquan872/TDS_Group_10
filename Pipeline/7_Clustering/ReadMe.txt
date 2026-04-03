# README – Clustering

## GMM-Based Clustering Pipeline for CVH and BHS Profiles

### Overview

This script performs unsupervised clustering of UK Biobank participants based on two cardiovascular health scores: CVH_score and BHS. It uses Gaussian Mixture Models (GMM) to identify latent subgroups, characterises each cluster by CVD rate and score profiles, and evaluates whether cluster membership improves CVD prediction beyond the raw scores alone.

For each logistic regression model evaluated, the script computes AUC, balanced accuracy, precision, recall, and F1 on train, validation, and test splits. A forest plot with bootstrapped confidence intervals is produced for the best-performing model.

---

### Required Libraries

The following Python packages are required:

- numpy
- pandas
- matplotlib
- seaborn
- scikit-learn
- pickle
- json
---

### Input Files

The script reads three pre-imputed splits of the UK Biobank dataset:

- `../../2_Imputation/outputs/ukb_train_imputed.csv`
- `../../2_Imputation/outputs/ukb_val_imputed.csv`
- `../../2_Imputation/outputs/ukb_test_imputed.csv`

Each file must contain at minimum the following columns:

- `CVH_score` — continuous cardiovascular health score
- `BHS` — continuous behavioural health score
- `cvd` — binary outcome (1 = CVD event, 0 = no event)
- `age_at_recruitment` — continuous confounder
- `sex` — categorical confounder

---

### Output Structure

All outputs are saved into the following folders, created automatically if missing:

- `outputs/gmm_plots/` → figures in PNG and PDF format
- `outputs/tables/` → summary tables, cluster stats, and clustered datasets as CSV
- `outputs/models/` → fitted GMM model, scaler, cluster remap, and best K saved as pickle/JSON

---

### Main Purpose

This script identifies participant subgroups based on the joint distribution of CVH_score and BHS, assesses whether these subgroups capture meaningful variation in CVD risk, and tests whether adding cluster membership to logistic regression improves prediction performance.

---

### Main Steps

#### 1. Setup

- Defines output directories and creates them if missing
- Loads train, validation, and test datasets

#### 2. Tercile-Based Profile Assignment

- Divides CVH_score and BHS each into three groups (Low / Mid / High) based on tercile thresholds derived from the training set
- Assigns a combined profile label to each participant (e.g. "High CVH / Low BHS")
- Computes and saves CVD rates per profile
- Produces a 3×3 heatmap of CVD rates by CVH group × BHS group for all three splits

#### 3. K Selection via BIC

- Standardises CVH_score and BHS using a StandardScaler fitted on training data
- Fits GMMs with K ranging from 2 to 8, using multiple random seeds and initialisations
- Selects the optimal K using the elbow of the second-order difference of BIC scores
- Saves a BIC curve plot

#### 4. GMM Fitting

- Fits the best GMM (full covariance) across multiple seeds and selects the model with the lowest BIC
- Assigns cluster labels to train, validation, and test sets
- Remaps cluster indices so that Cluster 0 has the lowest mean CVH_score

#### 5. Cluster Visualisation

- Produces scatter plots of CVH_score vs BHS coloured by cluster for each split
- Overlays 1σ and 2σ ellipses representing the fitted Gaussian components

#### 6. Cluster Profiling

- Computes mean CVH_score, mean BHS, CVD rate, and cluster size for each cluster
- Produces a z-scored heatmap of cluster profiles for train and test (green = better, red = worse)
- Produces a horizontal bar chart of CVD rate per cluster for train and test

#### 7. Logistic Regression Models

Five models are evaluated, all including age and sex as confounders:

- CVH + confounders
- BHS + confounders
- CVH + BHS + confounders
- CVH + BHS + cluster + confounders
- CVH × BHS + confounders (interaction term)

All models use balanced class weights to handle outcome imbalance.

#### 8. Performance Evaluation

- Computes AUC, balanced accuracy, precision, recall, and F1 for each model across all splits
- Produces a horizontal bar chart comparing AUC across models
- Produces ROC curves for all models across train, validation, and test splits
- Produces confusion matrices for all models and splits

#### 9. Forest Plot

- Fits the best model (CVH + BHS + interaction + confounders) and bootstraps coefficients 500 times
- Computes odds ratios with 95% bootstrap confidence intervals and empirical p-values
- Saves a forest plot coloured by direction of effect (blue = protective, red = risk factor)

#### 10. Saving Outputs

Saves the following files:

- Cluster-annotated datasets: `clustered_data_train/val/test.csv`
- Fitted GMM model: `gmm_model.pkl`
- StandardScaler used for GMM input: `gmm_scaler.pkl`
- Cluster index remap: `gmm_remap.json`
- Best K value: `gmm_best_k.json`
- Cluster summary statistics: `T5_gmm_cluster_stats.csv`
- All performance and effect size tables

---

### Key Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `COV_TYPE` | `'full'` | GMM covariance type |
| `K_RANGE` | 2–8 | Range of K values evaluated |
| `N_SEEDS` | 5 | Random seeds per K for stability |
| `N_INITS` | 10 | EM initialisations per GMM fit |
| `N_BOOT` | 500 | Bootstrap iterations for forest plot |

---

### Models Included

| Model name | Features |
|---|---|
| CVH + confounders | CVH_score, age, sex |
| BHS + confounders | BHS, age, sex |
| CVH + BHS + confounders | CVH_score, BHS, age, sex |
| CVH + BHS + cluster + confounders | CVH_score, BHS, cluster (OHE), age, sex |
| CVH × BHS + confounders | CVH_score, BHS, CVH×BHS interaction, age, sex |

---

### Outputs Summary

All figures are saved in PNG and PDF format unless noted otherwise.

**`outputs/gmm_plots/`**
- `00_cvh_bhs_heatmap.png` / `.pdf`
- `01_bic.png` / `.pdf`
- `02_scatter_train.png` / `.pdf`
- `03_scatter_val.png` / `.pdf`
- `04_scatter_test.png` / `.pdf`
- `05_profiles.png` / `.pdf`
- `06_cvd_rates.png` / `.pdf`
- `08_auc_comparison.png` / `.pdf`
- `09_roc_curves.png` / `.pdf`
- `10_confusion_matrices.png` / `.pdf`
- `11_forest_plot.png` / `.pdf`

**`outputs/tables/`**
- `T1_profile_cvd_rates.csv`
- `T2_cluster_counts.csv`
- `T3_model_performance_summary.csv`
- `T4_forest_plot_effect_sizes.csv`
- `T5_gmm_cluster_stats.csv`
- `clustered_data_train.csv`
- `clustered_data_val.csv`
- `clustered_data_test.csv`

**`outputs/models/`**
- `gmm_model.pkl`
- `gmm_scaler.pkl`
- `gmm_remap.json`
- `gmm_best_k.json`

---

### Important Notes

- All tercile thresholds and scalers are derived from the training set only and applied to validation and test sets
- Cluster indices are remapped after fitting so that Cluster 0 always corresponds to the lowest mean CVH_score
- The GMM uses full covariance matrices, allowing clusters to take arbitrary elliptical shapes in the CVH/BHS space
- Logistic regression models use `class_weight='balanced'` to account for CVD class imbalance
- The forest plot uses empirical bootstrap p-values; faded points indicate non-significant effects (p ≥ 0.05)
- The interaction term CVH_score × BHS is standardised independently before being added to the model

---

End of file