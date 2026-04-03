# README – Neural Network

## MLP Pipeline for CVD Prediction

### Overview

This pipeline trains and compares two Multilayer Perceptron (MLP) models for CVD prediction using the same feature set derived from CVH and BHS components. The two models differ in their architecture and hyperparameter selection strategy:

- **Paper MLP**: fixed architecture replicating the NeuralCVD design (256→128→100, SELU activation)
- **Optuna MLP**: architecture and hyperparameters tuned automatically via Bayesian optimisation using Optuna

Both models are trained with early stopping on validation AUC, saved with their preprocessing objects, and compared in a dedicated comparison script that produces ROC curves, precision-recall curves, AUC bar charts, and predicted probability distributions.

---

### Required Libraries

The following Python packages are required:

- numpy
- pandas
- matplotlib
- torch
- optuna
- scikit-learn
- json
- pickle
---

### Input Files

All three scripts read the same pre-imputed UK Biobank splits:

- `../../2_Imputation/outputs/ukb_train_imputed.csv`
- `../../2_Imputation/outputs/ukb_val_imputed.csv`
- `../../2_Imputation/outputs/ukb_test_imputed.csv`

The comparison script additionally reads the prediction and results tables saved by the two training scripts.

Each dataset must contain at minimum:

- All CVH and BHS component features (listed below)
- `cvd` — binary outcome (1 = CVD event, 0 = no event)
- `age_at_recruitment` — continuous confounder
- `sex` — categorical confounder

---

### Features Used

Both models use the same input features, deduplicated across the two score components:

CVH features: `DASH_score`, `MET_total`, `pack_year_index`, `bmi`, `biochem_cholesterol`, `biochem_hdl`, `biochem_hba1c`, `biochem_glucose`, `systolic_bp`, `diastolic_bp`

BHS features: `biochem_hba1c`, `biochem_hdl`, `biochem_ldl_direct`, `biochem_triglycerides`, `systolic_bp`, `diastolic_bp`, `cardiac_pulse_rate`, `biochem_crp`, `igf1`, `alanine_aminotransferase`, `aspartate_aminotransferase`, `gamma_glutamyltransferase`, `creatinine`

In addition: `age_at_recruitment` (standardised) and `sex` (one-hot encoded, reference category dropped).

---

### Output Structure

Outputs are saved into the following folders, created automatically if missing:

**Paper MLP:**
- `outputs/plots_paper/` → ROC curve figure
- `outputs/tables_paper/` → predictions and results tables
- `outputs/models_paper/` → model weights, architecture JSON, scaler, and OHE objects

**Optuna MLP:**
- `outputs/plots_optuna/` → ROC curve and optimisation history figure
- `outputs/tables_optuna/` → predictions, results, best hyperparameters, and full trials table
- `outputs/models_optuna/` → model weights, architecture JSON, scaler, and OHE objects
- `outputs/logs_optuna/` → folder created for run logs if needed

**Comparison:**
- `outputs/comparison/` → all comparison figures and summary table

---

### Scripts

#### 1. `mlp_paper.py` — Paper Architecture (NeuralCVD)

Trains a fixed MLP replicating the NeuralCVD architecture from the literature.

**Architecture:** input → 256 → 128 → 100 → 1, SELU activations throughout

**Training setup:**
- Optimiser: Adam (lr=1e-3, weight_decay=1e-4)
- Batch size: 256
- Max epochs: 200 with early stopping (patience = 15 epochs, monitored on validation AUC)
- Loss: BCEWithLogitsLoss with positive class weighting to handle outcome imbalance

**Outputs saved:**
- `mlp_paper_test_predictions.csv`, `mlp_paper_val_predictions.csv`
- `mlp_paper_results.csv`
- `mlp_paper_state_dict.pt`, `mlp_paper_architecture.json`
- `mlp_paper_scaler.pkl`, `mlp_paper_ohe.pkl`
- `mlp_paper_roc_curve.png` / `.pdf`

---

#### 2. `mlp_optuna.py` — Optuna-Tuned Architecture

Searches for the best MLP architecture and training hyperparameters using Optuna with TPE sampling and median pruning.

**Hyperparameter search space:**

| Parameter | Range |
|---|---|
| Number of layers | 1–4 |
| Units per layer | 16–256 |
| Dropout | 0.0–0.5 |
| Learning rate | 1e-4–1e-2 (log scale) |
| Weight decay | 1e-5–1e-2 (log scale) |
| Batch size | 64, 128, 256, 512 |
| Activation | ReLU, Tanh, ELU |

**Optuna settings:**
- 100 trials, TPE sampler (seed=42), MedianPruner (5 startup trials, 10 warmup steps)
- Each trial trains up to 100 epochs with early stopping (patience = 10)
- Objective: maximise validation AUC

**Final training:**
- Best hyperparameters applied, trained up to 200 epochs with early stopping (patience = 15)
- Best validation AUC checkpoint restored before evaluation

**Outputs saved:**
- `mlp_optuna_test_predictions.csv`, `mlp_optuna_val_predictions.csv`
- `mlp_optuna_results.csv`, `mlp_optuna_best_params.json`, `mlp_optuna_trials.csv`
- `mlp_optuna_state_dict.pt`, `mlp_optuna_architecture.json`
- `mlp_optuna_scaler.pkl`, `mlp_optuna_ohe.pkl`
- `mlp_optuna_roc_curve.png` / `.pdf`
- `mlp_optuna_optimization_history.png` / `.pdf`

---

#### 3. `mlp_comparison.py` — Model Comparison

Loads the saved predictions and results from both models and produces a comprehensive visual comparison. Does not retrain any model.

**Figures produced:**

| File | Content |
|---|---|
| `fig1_main_comparison` | ROC (validation), AUC bar chart, compute time |
| `fig2_roc_val_test` | ROC curves for validation and test splits side by side |
| `fig3_precision_recall` | Precision-recall curves with average precision for validation and test |
| `fig4_auc_splits` | Grouped bar chart of AUC across train, val, and test |
| `fig5_prob_distributions` | Histograms of predicted probabilities by outcome class (test set) |

**Tables produced:**
- `mlp_comparison_summary.csv` — AUC and compute time for both models across all splits

---

### Important Notes

- All scalers and encoders are fitted on the training set only and applied to validation and test sets
- Positive class weighting (`pos_weight = n_negative / n_positive`) is used in the loss function to address CVD outcome imbalance
- The best model checkpoint during final training is restored based on validation AUC before evaluation and saving
- The comparison script depends on output files from both training scripts and must be run after them
- GPU is used automatically if available (`torch.cuda.is_available()`); otherwise falls back to CPU
- Optuna logging is suppressed during search; a progress bar is shown instead
- The Paper MLP does not use dropout; the Optuna MLP may include dropout depending on the best trial found

---

### Outputs Summary

All figures are saved in PNG and PDF format unless noted otherwise.

**`outputs/models_paper/`**
- `mlp_paper_state_dict.pt`
- `mlp_paper_architecture.json`
- `mlp_paper_scaler.pkl`
- `mlp_paper_ohe.pkl`

**`outputs/tables_paper/`**
- `mlp_paper_results.csv`
- `mlp_paper_test_predictions.csv`
- `mlp_paper_val_predictions.csv`

**`outputs/plots_paper/`**
- `mlp_paper_roc_curve.png` / `.pdf`

**`outputs/models_optuna/`**
- `mlp_optuna_state_dict.pt`
- `mlp_optuna_architecture.json`
- `mlp_optuna_scaler.pkl`
- `mlp_optuna_ohe.pkl`

**`outputs/tables_optuna/`**
- `mlp_optuna_results.csv`
- `mlp_optuna_best_params.json`
- `mlp_optuna_trials.csv`
- `mlp_optuna_test_predictions.csv`
- `mlp_optuna_val_predictions.csv`

**`outputs/plots_optuna/`**
- `mlp_optuna_roc_curve.png` / `.pdf`
- `mlp_optuna_optimization_history.png` / `.pdf`

**`outputs/comparison/`**
- `fig1_main_comparison.png` / `.pdf`
- `fig2_roc_val_test.png` / `.pdf`
- `fig3_precision_recall.png` / `.pdf`
- `fig4_auc_splits.png` / `.pdf`
- `fig5_prob_distributions.png` / `.pdf`
- `mlp_comparison_summary.csv`

---

End of file