# LVQ1 with Optuna hyperparameter tuning — sex-stratified analysis
# Runs 3 models: all participants (sex as feature), females only, males only

import matplotlib
matplotlib.use('Agg')
import warnings
warnings.filterwarnings("ignore")

import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import optuna
from optuna.samplers import TPESampler
from optuna.pruners  import MedianPruner
optuna.logging.set_verbosity(optuna.logging.WARNING)

from sklearn.preprocessing   import StandardScaler, LabelEncoder
from sklearn.base            import BaseEstimator, ClassifierMixin
from sklearn.metrics         import roc_auc_score
from imblearn.over_sampling  import SMOTE
import pickle, json

# Directories
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR   = os.path.join(SCRIPT_DIR, '..', '..', '3_Correlation', 'outputs')
OUTPUT_DIR = os.path.join(SCRIPT_DIR, '..', 'outputs')

TRAIN_PATH = os.path.join(DATA_DIR, 'ukb_train_drop_correlation_score.csv')
TEST_PATH  = os.path.join(DATA_DIR, 'ukb_test_drop_correlation_score.csv')
VAL_PATH   = os.path.join(DATA_DIR, 'ukb_val_drop_correlation_score.csv')

BIOMARKERS_WITH_SEX = [
    "biochem_apoa", "biochem_apob", "biochem_glucose", "biochem_hba1c",
    "biochem_hdl", "biochem_triglycerides", "biochem_crp",
    "gamma_glutamyltransferase", "igf1", "creatinine",
    "aspartate_aminotransferase", "alanine_aminotransferase",
    "biochem_sodium_urine",
    "blood_wbc_count", "blood_rbc_count", "blood_hemoglobin_conc",
    "blood_hematocrit_pct", "blood_platelet_count", "blood_platelet_volume_mean",
    "blood_platelet_distribution_width", "blood_reticulocyte_pct",
    "blood_reticulocyte_count", "blood_reticulocyte_volume_mean",
    "blood_reticulocyte_immature_fraction", "blood_reticulocyte_hls_count",
    "systolic_bp", "diastolic_bp", "bmi",
    "cardiac_pulse_rate", "ecg_heart_rate",
    "pwa_reflection_index", "pwa_peak_position", "pwa_notch_position",
    "resp_fev1_best", "resp_fev1_z_score", "resp_fvc_z_score",
    "resp_fev1_fvc_ratio_z_score",
    "fat_free_mass", "body_fat_pct",
    "ecg_load", "ecg_phase_time", "ecg_during_exercise_duration",
    "fitness_bicycle_speed", "fitness_workload_max",
    "age_at_recruitment", "sex",
    "MET_total", "CVH_pa_score", "energy",
    "DASH_score", "CVH_diet_score",
    "pack_year_index", "total_unit_alcohol_per_week",
    "alcohol_freq_6plus_units", "sleep_duration",
    "med_cholesterol_bp_diabetes_hormones",
    "depression_score", "HSI",
]

BIOMARKERS_NO_SEX = [b for b in BIOMARKERS_WITH_SEX if b != "sex"]

OUTCOME      = "cvd"
RANDOM_STATE = 42
N_TRIALS     = 50


# LVQ1
class LVQ1(BaseEstimator, ClassifierMixin):

    _estimator_type = "classifier"

    def __init__(self, n_prototypes=2, lr=0.01, lr_decay=0.001,
                 n_epochs=50, random_state=42):
        self.n_prototypes = n_prototypes
        self.lr           = lr
        self.lr_decay     = lr_decay
        self.n_epochs     = n_epochs
        self.random_state = random_state

    def _init_prototypes(self, X, y):
        rng = np.random.RandomState(self.random_state)
        protos, labels = [], []
        for cls in self.classes_:
            X_cls  = X[y == cls]
            n_pick = min(self.n_prototypes, len(X_cls))
            idx    = rng.choice(len(X_cls), size=n_pick, replace=False)
            for i in idx:
                protos.append(X_cls[i].copy())
                labels.append(cls)
            for _ in range(self.n_prototypes - n_pick):
                protos.append(X_cls.mean(axis=0) + rng.randn(X_cls.shape[1]) * 0.01)
                labels.append(cls)
        self.prototypes_   = np.array(protos, dtype=np.float64)
        self.proto_labels_ = np.array(labels)

    def fit(self, X, y):
        X = np.asarray(X, dtype=np.float64)
        y = np.asarray(y)
        self.classes_ = np.unique(y)
        self._init_prototypes(X, y)
        for epoch in range(self.n_epochs):
            lr_t = self.lr / (1.0 + self.lr_decay * epoch)
            idx  = np.random.RandomState(self.random_state + epoch).permutation(len(X))
            for i in idx:
                x  = X[i]; yi = y[i]
                dists = np.sum((self.prototypes_ - x) ** 2, axis=1)
                j     = np.argmin(dists)
                if self.proto_labels_[j] == yi:
                    self.prototypes_[j] += lr_t * (x - self.prototypes_[j])
                else:
                    self.prototypes_[j] -= lr_t * (x - self.prototypes_[j])
        return self

    def predict(self, X):
        X     = np.asarray(X, dtype=np.float64)
        dists = np.sum((X[:, np.newaxis, :] - self.prototypes_[np.newaxis, :, :]) ** 2, axis=2)
        return self.proto_labels_[dists.argmin(axis=1)]

    def predict_proba(self, X):
        X     = np.asarray(X, dtype=np.float64)
        dists = np.sum((X[:, np.newaxis, :] - self.prototypes_[np.newaxis, :, :]) ** 2, axis=2)
        d1    = dists[:, self.proto_labels_ == 1].min(axis=1)
        d0    = dists[:, self.proto_labels_ == 0].min(axis=1)
        denom = d1 + d0
        mu    = np.where(denom > 1e-12, (d1 - d0) / denom, 0.0)
        mu    = np.clip(mu, -50.0, 50.0)
        p1    = 1.0 / (1.0 + np.exp(mu))
        return np.column_stack([1.0 - p1, p1])


# Load data
def load(path):
    return pd.read_excel(path) if path.endswith((".xlsx", ".xls")) else pd.read_csv(path)

train = load(TRAIN_PATH)
test  = load(TEST_PATH)
val   = load(VAL_PATH)

le = LabelEncoder().fit(["Female", "Male"])
for df in [train, test, val]:
    df["sex"] = le.transform(df["sex"])


# Model configurations
models_config = [
    {
        "label":      "all",
        "biomarkers": BIOMARKERS_WITH_SEX,
        "train":      train,
        "test":       test,
        "val":        val,
    },
    {
        "label":      "female",
        "biomarkers": BIOMARKERS_NO_SEX,
        "train":      train[train["sex"] == 0].reset_index(drop=True),
        "test":       test [test ["sex"] == 0].reset_index(drop=True),
        "val":        val  [val  ["sex"] == 0].reset_index(drop=True),
    },
    {
        "label":      "male",
        "biomarkers": BIOMARKERS_NO_SEX,
        "train":      train[train["sex"] == 1].reset_index(drop=True),
        "test":       test [test ["sex"] == 1].reset_index(drop=True),
        "val":        val  [val  ["sex"] == 1].reset_index(drop=True),
    },
]


# Run Optuna for each model
for cfg in models_config:

    label      = cfg["label"]
    biomarkers = cfg["biomarkers"]
    tr         = cfg["train"]
    te         = cfg["test"]
    va         = cfg["val"]

    print(f"\n{'='*60}")
    print(f"MODEL: {label.upper()}")
    print(f"{'='*60}")

    model_out = os.path.join(OUTPUT_DIR, f'models_lvq_{label}')
    table_out = os.path.join(OUTPUT_DIR, f'tables_lvq_{label}')
    plot_out  = os.path.join(OUTPUT_DIR, f'plots_lvq_{label}')
    for d in [model_out, table_out, plot_out]:
        os.makedirs(d, exist_ok=True)

    available = [c for c in biomarkers if c in tr.columns]
    print(f"Features: {len(available)} | Train: {tr.shape[0]} | "
          f"Val: {va.shape[0]} | Test: {te.shape[0]}")
    print(f"CVD prevalence — train: {tr[OUTCOME].mean():.3f}")

    X_train = tr[available].values.astype(float)
    y_train = tr[OUTCOME].values.astype(int)
    X_test  = te[available].values.astype(float)
    y_test  = te[OUTCOME].values.astype(int)
    X_val   = va[available].values.astype(float)
    y_val   = va[OUTCOME].values.astype(int)

    scaler    = StandardScaler()
    X_train_s = scaler.fit_transform(X_train)
    X_test_s  = scaler.transform(X_test)
    X_val_s   = scaler.transform(X_val)

    # SMOTE on train only
    print("Applying SMOTE...")
    sm = SMOTE(random_state=RANDOM_STATE, sampling_strategy=0.5)
    X_train_bal, y_train_bal = sm.fit_resample(X_train_s, y_train)
    print(f"After SMOTE — samples: {X_train_bal.shape[0]} | "
          f"CVD: {y_train_bal.sum()} ({y_train_bal.mean():.3f})")

    # Optuna — train on X_train_bal, evaluate on X_val_s
    def objective(trial):
        params = dict(
            n_prototypes = trial.suggest_int  ("n_prototypes", 1, 8),
            lr           = trial.suggest_float("lr",           1e-3, 0.3,  log=True),
            lr_decay     = trial.suggest_float("lr_decay",     1e-5, 0.01, log=True),
            n_epochs     = trial.suggest_int  ("n_epochs",     20, 200),
            random_state = RANDOM_STATE,
        )
        try:
            clf   = LVQ1(**params)
            clf.fit(X_train_bal, y_train_bal)
            probs = clf.predict_proba(X_val_s)[:, 1]
            return roc_auc_score(y_val, probs)
        except Exception:
            return 0.5

    print(f"\nOptuna — {N_TRIALS} trials (val set evaluation)")
    study = optuna.create_study(
        direction = "maximize",
        sampler   = TPESampler(seed=RANDOM_STATE),
        pruner    = MedianPruner(n_startup_trials=10, n_warmup_steps=0),
    )
    study.optimize(objective, n_trials=N_TRIALS, show_progress_bar=True)

    print(f"\nBest AUC ({label}): {study.best_value:.4f}")
    for k, v in study.best_params.items():
        print(f"  {k:20s} = {v}")

    # Save outputs
    study.trials_dataframe().to_csv(
        os.path.join(table_out, f'lvq1_optuna_trials_{label}.csv'), index=False)

    for path in [os.path.join(table_out, f'lvq1_best_params_{label}.json'),
                 os.path.join(model_out,  f'lvq1_best_params_{label}.json')]:
        with open(path, 'w') as f:
            json.dump(study.best_params, f, indent=2)

    with open(os.path.join(model_out, f'scaler_{label}.pkl'), 'wb') as f:
        pickle.dump(scaler, f)

    with open(os.path.join(model_out, f'available_features_{label}.json'), 'w') as f:
        json.dump(available, f)

    for name, arr in [
        ('X_train_bal', X_train_bal), ('y_train_bal', y_train_bal),
        ('X_train_s',   X_train_s),   ('y_train',     y_train),
        ('X_val_s',     X_val_s),     ('y_val',       y_val),
        ('X_test_s',    X_test_s),    ('y_test',      y_test),
    ]:
        np.save(os.path.join(model_out, f'{name}_{label}.npy'), arr)

    # Train final model on X_train_bal only (Opción A — consistent with Optuna)
    best_model = LVQ1(**study.best_params, random_state=RANDOM_STATE)
    best_model.fit(X_train_bal, y_train_bal)
    with open(os.path.join(model_out, f'lvq1_final_model_{label}.pkl'), 'wb') as f:
        pickle.dump(best_model, f)

    # Save clustered datasets with predictions
    tr_out = tr.copy()
    va_out = va.copy()
    te_out = te.copy()

    tr_out["lvq_pred"]  = best_model.predict(X_train_s)
    tr_out["lvq_proba"] = best_model.predict_proba(X_train_s)[:, 1]
    va_out["lvq_pred"]  = best_model.predict(X_val_s)
    va_out["lvq_proba"] = best_model.predict_proba(X_val_s)[:, 1]
    te_out["lvq_pred"]  = best_model.predict(X_test_s)
    te_out["lvq_proba"] = best_model.predict_proba(X_test_s)[:, 1]

    tr_out.to_csv(os.path.join(table_out, f'lvq_data_train_{label}.csv'), index=False)
    va_out.to_csv(os.path.join(table_out, f'lvq_data_val_{label}.csv'),   index=False)
    te_out.to_csv(os.path.join(table_out, f'lvq_data_test_{label}.csv'),  index=False)
    print(f"Saved: lvq_data_train/val/test_{label}.csv")

    # Optuna history plot
    fig, ax = plt.subplots(figsize=(8, 5))
    trial_vals  = [t.value for t in study.trials if t.value is not None]
    best_so_far = np.maximum.accumulate(trial_vals)
    ax.scatter(range(len(trial_vals)), trial_vals, s=20, alpha=0.5,
               color="#6366F1", label="Trial")
    ax.plot(range(len(trial_vals)), best_so_far, color="#DC2626",
            linewidth=2, label="Best so far")
    ax.axhline(study.best_value, color="green", linestyle="--", linewidth=1.2,
               label=f"Best = {study.best_value:.4f}")
    ax.set_xlabel("Trial"); ax.set_ylabel("roc_auc")
    ax.set_title(f"Optuna history — {label}")
    ax.legend(fontsize=8); ax.grid(True, alpha=0.3)
    plt.tight_layout()
    fig.savefig(os.path.join(plot_out, f'optuna_history_{label}.png'), dpi=150, bbox_inches='tight')
    fig.savefig(os.path.join(plot_out, f'optuna_history_{label}.pdf'), bbox_inches='tight')
    plt.close(fig)

print("\nAll models tuned and saved.")
