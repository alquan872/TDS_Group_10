# README – LVQ

## LVQ1 Pipeline for CVD Prediction — Sex-Stratified Analysis

### Overview

This pipeline trains and evaluates Learning Vector Quantisation 1 (LVQ1) models for CVD prediction using a broad set of biomarkers, lifestyle, and physiological features. The analysis is sex-stratified, running three parallel models: one on all participants (with sex as a feature), one on females only, and one on males only.

Hyperparameters are tuned via Optuna in a first script, and the best configurations are then used in a second script to train final models, evaluate performance, inspect prototype profiles, and produce comparison plots across the three subgroups. A UMAP visualisation is also generated to inspect the learned prototype positions in 2D space.

---

### Required Libraries

The following Python packages are required:

- numpy
- pandas
- matplotlib
- optuna
- scikit-learn
- imbalanced-learn
- umap-learn
- pickle
- json
---

### Input Files

Both scripts read the same UK Biobank dataset splits from the correlation-filtered outputs:

- `../../3_Correlation/outputs/ukb_train_drop_correlation_score.csv`
- `../../3_Correlation/outputs/ukb_val_drop_correlation_score.csv`
- `../../3_Correlation/outputs/ukb_test_drop_correlation_score.csv`

Both CSV and Excel formats are supported. The dataset must contain the biomarker and lifestyle features listed below, the binary outcome `cvd`, and the variable `sex` (coded as "Female" / "Male").

---

### Features Used

The full feature set includes biomarkers, physiological measurements, lifestyle variables, and composite scores. Sex is included as a binary feature in the all-participants model and excluded from the sex-stratified models.

**Biomarkers and blood tests:** `biochem_apoa`, `biochem_apob`, `biochem_glucose`, `biochem_hba1c`, `biochem_hdl`, `biochem_triglycerides`, `biochem_crp`, `gamma_glutamyltransferase`, `igf1`, `creatinine`, `aspartate_aminotransferase`, `alanine_aminotransferase`, `biochem_sodium_urine`

**Blood count:** `blood_wbc_count`, `blood_rbc_count`, `blood_hemoglobin_conc`, `blood_hematocrit_pct`, `blood_platelet_count`, `blood_platelet_volume_mean`, `blood_platelet_distribution_width`, `blood_reticulocyte_pct`, `blood_reticulocyte_count`, `blood_reticulocyte_volume_mean`, `blood_reticulocyte_immature_fraction`, `blood_reticulocyte_hls_count`

**Physical and cardiovascular:** `systolic_bp`, `diastolic_bp`, `bmi`, `cardiac_pulse_rate`, `ecg_heart_rate`, `pwa_reflection_index`, `pwa_peak_position`, `pwa_notch_position`, `resp_fev1_best`, `resp_fev1_z_score`, `resp_fvc_z_score`, `resp_fev1_fvc_ratio_z_score`, `fat_free_mass`, `body_fat_pct`, `ecg_load`, `ecg_phase_time`, `ecg_during_exercise_duration`, `fitness_bicycle_speed`, `fitness_workload_max`

**Lifestyle and composite scores:** `age_at_recruitment`, `sex` (all model only), `MET_total`, `CVH_pa_score`, `energy`, `DASH_score`, `CVH_diet_score`, `pack_year_index`, `total_unit_alcohol_per_week`, `alcohol_freq_6plus_units`, `sleep_duration`, `med_cholesterol_bp_diabetes_hormones`, `depression_score`, `HSI`

---

### Output Structure

Outputs are organised per model label (`all`, `female`, `male`), plus a shared comparison folder:

- `outputs/models_lvq_{label}/` → fitted model, scaler, best parameters, feature list, preprocessed arrays
- `outputs/tables_lvq_{label}/` → performance tables, prototype difference tables, annotated datasets
- `outputs/plots_lvq_{label}/` → per-model figures
- `outputs/plots_lvq_comparison/` → cross-model comparison figures and combined performance table

---

### Scripts

#### 1. `lvq1_optuna.py` — Hyperparameter Tuning

Runs Optuna hyperparameter search for each of the three models (all, female, male) and saves the best parameters along with all preprocessing objects and scaled arrays.

**Preprocessing:**
- Features are standardised using StandardScaler fitted on the training set
- SMOTE is applied to the scaled training set with `sampling_strategy=0.5` to address CVD class imbalance
- Optuna trials are evaluated on the original (unbalanced) validation set

**LVQ1 hyperparameter search space:**

| Parameter | Range |
|---|---|
| Number of prototypes per class | 1–8 |
| Learning rate | 1e-3–0.3 (log scale) |
| Learning rate decay | 1e-5–0.01 (log scale) |
| Number of epochs | 20–200 |

**Optuna settings:**
- 50 trials per model, TPE sampler (seed=42), MedianPruner (10 startup trials)
- Objective: maximise validation AUC
- Trials that raise exceptions return AUC=0.5

**Final model training:**
- Best parameters are used to fit a final LVQ1 model on the SMOTE-balanced training data
- The fitted model is saved and predictions are appended to the original train/val/test datasets

**Outputs saved per model:**
- `lvq1_best_params_{label}.json` (in both tables and models directories)
- `lvq1_final_model_{label}.pkl`
- `scaler_{label}.pkl`
- `available_features_{label}.json`
- Preprocessed arrays as `.npy`: `X_train_bal`, `y_train_bal`, `X_train_s`, `X_val_s`, `X_test_s`, `y_train`, `y_val`, `y_test`
- `lvq1_optuna_trials_{label}.csv`
- `lvq_data_train/val/test_{label}.csv` (original data with `lvq_pred` and `lvq_proba` columns appended)
- `optuna_history_{label}.png` / `.pdf`

---

#### 2. `lvq1_analysis.py` — Final Evaluation and Visualisation

Loads the saved models and preprocessed data from the tuning script and produces a full evaluation and visual comparison across the three models.

**Per-model outputs:**

Performance is evaluated on the original (unbalanced) train, validation, and test splits. Prototype profiles are examined by inverse-transforming the learned prototypes back to the original feature scale and computing the percentage difference between CVD and No-CVD prototypes for each biomarker. The most discriminative biomarkers are selected using an elbow method on the ranked absolute differences.

Figures produced per model:

- `fig_biomarkers_{label}` — horizontal bar chart of discriminative biomarkers (elbow cutoff) and predicted probability distribution on the test set
- `fig_heatmap_{label}` — heatmap of all prototype vectors across all features (min-max normalised)

Tables produced per model:

- `lvq1_performance_{label}.csv` — AUC, accuracy, F1, recall, precision per split
- `lvq1_prototype_diff_{label}.csv` — full ranked list of biomarker differences between CVD and No-CVD prototypes

**Cross-model comparison outputs (in `plots_lvq_comparison/`):**

- `fig_comparison_performance` — grouped bar chart of test-set AUC, F1, recall, precision, and accuracy for all three models
- `fig_comparison_biomarkers` — side-by-side discriminative biomarker bar charts for all three models
- `fig_comparison_umap` — UMAP projections (2×3 grid) showing true labels and predicted labels with prototype positions marked as stars, for each of the three models
- `lvq1_all_performance.csv` — combined performance table for all models and splits

---

### LVQ1 Implementation

The LVQ1 classifier is implemented from scratch as a scikit-learn-compatible estimator. Key implementation details:

- Prototypes are initialised by sampling randomly from each class in the training data; if fewer samples than `n_prototypes` exist, the class mean is used with small random noise
- At each epoch, samples are presented in random order and the nearest prototype is moved toward the sample if its label matches, or away if it does not
- The learning rate decays as `lr / (1 + lr_decay × epoch)`
- Probability estimates are derived from the ratio of distances to the nearest CVD and No-CVD prototypes, passed through a sigmoid function

---

### Important Notes

- All scalers are fitted on the training set only and applied to validation and test sets
- SMOTE is applied after scaling and only to the training set; validation and test sets are evaluated on the original class distribution
- Sex is label-encoded as Male=1, Female=0 before modelling
- Only features present in the loaded dataset are used; missing features are silently dropped
- UMAP subsamples up to 2,000 test-set points for speed; prototype positions are projected into the same UMAP space
- The elbow cutoff for discriminative biomarkers uses the largest drop in absolute percentage difference; a minimum of 5 biomarkers is always retained

---

### Outputs Summary

All figures are saved in PNG and PDF format unless noted otherwise.

**`outputs/models_lvq_{label}/`** — repeated for `all`, `female`, `male`
- `lvq1_final_model_{label}.pkl`
- `lvq1_best_params_{label}.json`
- `scaler_{label}.pkl`
- `available_features_{label}.json`
- `X_train_bal_{label}.npy`, `y_train_bal_{label}.npy`
- `X_train_s_{label}.npy`, `y_train_{label}.npy`
- `X_val_s_{label}.npy`, `y_val_{label}.npy`
- `X_test_s_{label}.npy`, `y_test_{label}.npy`

**`outputs/tables_lvq_{label}/`** — repeated for `all`, `female`, `male`
- `lvq1_performance_{label}.csv`
- `lvq1_prototype_diff_{label}.csv`
- `lvq_data_train_{label}.csv`
- `lvq_data_val_{label}.csv`
- `lvq_data_test_{label}.csv`
- `lvq1_optuna_trials_{label}.csv`
- `lvq1_best_params_{label}.json`

**`outputs/plots_lvq_{label}/`** — repeated for `all`, `female`, `male`
- `fig_biomarkers_{label}.png` / `.pdf`
- `fig_heatmap_{label}.png` / `.pdf`
- `optuna_history_{label}.png` / `.pdf`

**`outputs/plots_lvq_comparison/`**
- `fig_comparison_performance.png` / `.pdf`
- `fig_comparison_biomarkers.png` / `.pdf`
- `fig_comparison_umap.png` / `.pdf`
- `lvq1_all_performance.csv`

---

End of file