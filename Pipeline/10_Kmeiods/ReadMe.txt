# README – K-Medoids

## K-Medoids Per-Class Classifier Pipeline for CVD Prediction

### Overview

This pipeline trains and evaluates a custom K-Medoids per-class classifier for CVD prediction using a broad set of biomarkers, physiological measurements, and lifestyle features. The classifier learns separate medoid sets for CVD and No-CVD classes; predictions are based on relative distances to the nearest medoid from each class.

The pipeline runs in two modes:

- **Single model** (`kmedoids_optuna.py`): all participants combined, with sex as a feature
- **Sex-stratified** (`kmedoids_sex_stratified.py`): three parallel models — all participants, females only, and males only

Both scripts tune hyperparameters using Optuna, train final models on the original (unbalanced) training data, and produce a comprehensive set of diagnostic figures including medoid profiles, distance distributions, UMAP projections, ROC curves, and confusion matrices.

---

### Required Libraries

The following Python packages are required:

- numpy
- pandas
- matplotlib
- optuna
- scikit-learn
- sklearn-extra
- umap-learn
- pickle
- json
---

### Input Files

Both scripts read the correlation-filtered UK Biobank splits:

- `../../3_Correlation/outputs/ukb_train_drop_correlation_score.csv`
- `../../3_Correlation/outputs/ukb_test_drop_correlation_score.csv`
- `../../3_Correlation/outputs/ukb_val_drop_correlation_score.csv`

Both CSV and Excel formats are supported. The dataset must contain the biomarker and lifestyle features listed below, the binary outcome `cvd`, and the variable `sex` (coded as "Female" / "Male").

---

### Features Used

The feature set is identical to the LVQ pipeline and includes biomarkers, physiological measurements, and lifestyle variables. Sex is included as a binary feature in the all-participants model and excluded from the sex-stratified models. See the LVQ README for the full feature list.

---

### Output Structure

**Single model script** (`kmedoids_optuna.py`):
- `outputs/plots_kmedoids/` → all figures
- `outputs/tables_kmedoids/` → performance tables, medoid profiles, annotated datasets
- `outputs/models_kmedoids/` → fitted model, scaler, best parameters, feature list, preprocessed arrays

**Sex-stratified script** (`kmedoids_sex_stratified.py`), outputs are written to `outputs_sex/` and organised per label (`all`, `female`, `male`):
- `outputs_sex/plots_kmedoids_{label}/` → per-model figures
- `outputs_sex/tables_kmedoids_{label}/` → per-model tables
- `outputs_sex/models_kmedoids_{label}/` → per-model model objects and arrays
- `outputs_sex/plots_kmedoids_comparison/` → cross-model comparison figures and combined table

---

### KMedoidsClassifier Implementation

The classifier is implemented from scratch as a scikit-learn-compatible estimator. Key design details:

- Separate KMedoids clusterings are fitted independently on the CVD and No-CVD training subsets, using k-medoids++ initialisation
- Supported distance metrics: Euclidean, cosine, and Mahalanobis (disabled by default via `USE_MAHALANOBIS = False`). When Mahalanobis is enabled, pairwise distance matrices are computed in chunks to manage memory
- Prediction is based on the ratio of distances to the nearest CVD and No-CVD medoids, passed through a sigmoid function, using the same probability formulation as in the LVQ pipeline
- The number of medoids per class (`k_cvd` and `k_nocvd`) is treated as a hyperparameter and tuned separately

---

### Scripts

#### 1. `kmedoids_optuna.py` — Single Model

Runs Optuna hyperparameter search, trains a final model on all participants, evaluates performance, and produces all diagnostic figures.

**Hyperparameter search space:**

| Parameter | Range |
|---|---|
| k_cvd (medoids for CVD class) | 1–8 |
| k_nocvd (medoids for No-CVD class) | 1–8 |
| Distance metric | euclidean, cosine |

**Optuna settings:**
- 60 trials, TPE sampler (seed=42), MedianPruner (10 startup trials)
- Objective: maximise validation AUC
- Trials that raise exceptions return AUC=0.5

**Key difference from the LVQ pipeline:** no SMOTE is applied. The final model is trained directly on the standardised training set with the original class distribution.

**Figures produced:**

| File | Content |
|---|---|
| `fig1_optuna` | Optimisation history, hyperparameter importance (fANOVA), performance bar chart |
| `fig2_medoid_profiles` | Elbow curve, discriminative biomarker bar chart (elbow cutoff), medoid value comparison |
| `fig3_prob_dist` | Predicted probability distribution by true outcome class (test set) |
| `fig4_prototype_cards_elbow` | Per-medoid bar charts showing feature values vs population mean (elbow-selected features) |
| `fig4_prototype_cards_all` | Same as above but for all features |
| `fig5_prototype_heatmap` | Heatmap of all medoid vectors across all features (z-scored) |
| `fig6_distance_distributions` | Distance distributions to CVD and No-CVD medoids by true label, plus scatter decision boundary |
| `fig7_roc_confusion` | ROC curve and confusion matrix on the test set |
| `fig8_umap` | UMAP projection of test patients with medoid positions marked as stars, for true and predicted labels |

**Tables produced:**
- `kmedoids_performance.csv` — AUC, accuracy, F1, recall, precision across train/val/test
- `kmedoids_biomarker_diff.csv` — full ranked biomarker difference table (CVD vs No-CVD medoid mean)
- `medoids_CVD.csv`, `medoids_NoCVD.csv` — medoid vectors in original feature scale
- `kmedoids_data_train/val/test.csv` — original data with `kmedoids_pred` and `kmedoids_proba` columns appended
- `kmedoids_optuna_trials.csv` — full Optuna trials table

**Model objects saved:**
- `kmedoids_final_model.pkl`
- `kmedoids_best_params.json`
- `scaler.pkl`, `available_features.json`
- Preprocessed arrays as `.npy`: `X_train_s`, `X_val_s`, `X_test_s`, `y_train`, `y_val`, `y_test`

---

#### 2. `kmedoids_sex_stratified.py` — Sex-Stratified Models

Runs the same pipeline three times in sequence (all, female, male) and additionally produces cross-model comparison outputs. The logic within each iteration is identical to the single-model script, with all figure and table filenames suffixed by the model label.

**Comparison outputs (in `plots_kmedoids_comparison/`):**

| File | Content |
|---|---|
| `fig_comparison_performance` | Grouped bar chart of test-set AUC, F1, recall, precision, and accuracy for all three models |
| `fig_comparison_biomarkers` | Side-by-side discriminative biomarker bar charts (elbow cutoff) for all three models |
| `fig_comparison_umap` | 3×2 UMAP grid showing true and predicted labels with medoid positions, one row per model |
| `fig_comparison_roc` | Overlaid ROC curves for all three models on their respective test sets |
| `kmedoids_all_performance.csv` | Combined performance table across all models and splits |

---

### Elbow Cutoff for Discriminative Biomarkers

The number of biomarkers shown in profile figures is selected automatically using a second-order difference elbow method on the ranked absolute percentage differences between CVD and No-CVD medoids. A minimum of 3 and a maximum of 30 biomarkers are enforced. The elbow curve itself is shown as the first panel in `fig2_medoid_profiles`.

---

### Important Notes

- All scalers are fitted on the training set only and applied to validation and test sets
- Unlike the LVQ pipeline, no SMOTE is applied; the K-Medoids classifier is trained on the original unbalanced class distribution
- Sex is label-encoded as Male=1, Female=0 before modelling
- Mahalanobis distance is implemented but disabled by default (`USE_MAHALANOBIS = False`); enabling it substantially increases compute time due to pairwise distance matrix construction
- Hyperparameter importance is computed via fANOVA using `optuna.importance.get_param_importances`; if too few completed trials exist this panel falls back to a text message
- UMAP is fitted on the training set and used to transform both test patients and medoid positions into the same 2D space; test sets are subsampled to 3,000 points for speed
- The decision rule is: predict CVD if distance to nearest CVD medoid < distance to nearest No-CVD medoid (equivalent to predicted probability > 0.5)

---

### Outputs Summary

All files are saved in PNG and PDF format unless noted otherwise.

**`outputs/models_kmedoids/`** (single model)
- `kmedoids_final_model.pkl`
- `kmedoids_best_params.json`
- `scaler.pkl`
- `available_features.json`
- `X_train_s.npy`, `y_train.npy`
- `X_val_s.npy`, `y_val.npy`
- `X_test_s.npy`, `y_test.npy`

**`outputs/tables_kmedoids/`** (single model)
- `kmedoids_performance.csv`
- `kmedoids_biomarker_diff.csv`
- `medoids_CVD.csv`
- `medoids_NoCVD.csv`
- `kmedoids_data_train.csv`
- `kmedoids_data_val.csv`
- `kmedoids_data_test.csv`
- `kmedoids_optuna_trials.csv`

**`outputs/plots_kmedoids/`** (single model)
- `fig1_optuna.png` / `.pdf`
- `fig2_medoid_profiles.png` / `.pdf`
- `fig3_prob_dist.png` / `.pdf`
- `fig4_prototype_cards_elbow.png` / `.pdf`
- `fig4_prototype_cards_all.png` / `.pdf`
- `fig5_prototype_heatmap.png` / `.pdf`
- `fig6_distance_distributions.png` / `.pdf`
- `fig7_roc_confusion.png` / `.pdf`
- `fig8_umap.png` / `.pdf`

**`outputs_sex/models_kmedoids_{label}/`** — repeated for `all`, `female`, `male`
- `kmedoids_final_model_{label}.pkl`
- `kmedoids_best_params_{label}.json`
- `scaler_{label}.pkl`
- `available_features_{label}.json`
- `X_train_s_{label}.npy`, `y_train_{label}.npy`
- `X_val_s_{label}.npy`, `y_val_{label}.npy`
- `X_test_s_{label}.npy`, `y_test_{label}.npy`

**`outputs_sex/tables_kmedoids_{label}/`** — repeated for `all`, `female`, `male`
- `kmedoids_performance_{label}.csv`
- `kmedoids_biomarker_diff_{label}.csv`
- `medoids_CVD_{label}.csv`
- `medoids_NoCVD_{label}.csv`
- `kmedoids_data_train_{label}.csv`
- `kmedoids_data_val_{label}.csv`
- `kmedoids_data_test_{label}.csv`
- `kmedoids_optuna_trials_{label}.csv`

**`outputs_sex/plots_kmedoids_{label}/`** — repeated for `all`, `female`, `male`
- `fig1_optuna_{label}.png` / `.pdf`
- `fig2_medoid_profiles_{label}.png` / `.pdf`
- `fig3_prob_dist_{label}.png` / `.pdf`
- `fig4_prototype_cards_elbow_{label}.png` / `.pdf`
- `fig4_prototype_cards_all_{label}.png` / `.pdf`
- `fig5_prototype_heatmap_{label}.png` / `.pdf`
- `fig6_distances_{label}.png` / `.pdf`
- `fig7_roc_confusion_{label}.png` / `.pdf`
- `fig8_umap_{label}.png` / `.pdf`

**`outputs_sex/plots_kmedoids_comparison/`**
- `fig_comparison_performance.png` / `.pdf`
- `fig_comparison_biomarkers.png` / `.pdf`
- `fig_comparison_umap.png` / `.pdf`
- `fig_comparison_roc.png` / `.pdf`
- `kmedoids_all_performance.csv`

---

End of file