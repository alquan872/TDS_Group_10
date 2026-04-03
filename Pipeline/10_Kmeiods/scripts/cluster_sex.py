# K-Medoids per-class classifier — sex-stratified analysis
# Runs 3 models: all participants (sex as feature), females only, males only

import matplotlib
matplotlib.use('Agg')
import warnings
warnings.filterwarnings("ignore")

import os
import gc
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import optuna
from optuna.samplers import TPESampler
from optuna.pruners  import MedianPruner
optuna.logging.set_verbosity(optuna.logging.WARNING)
import umap
from sklearn.preprocessing   import StandardScaler, LabelEncoder
from sklearn.base            import BaseEstimator, ClassifierMixin
from sklearn.metrics         import (
    accuracy_score, f1_score, recall_score,
    precision_score, classification_report, roc_auc_score,
    RocCurveDisplay, confusion_matrix, ConfusionMatrixDisplay,
)
from sklearn_extra.cluster  import KMedoids
import pickle, json

# Directories
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR   = os.path.join(SCRIPT_DIR, '..', '..', '3_Correlation', 'outputs')
OUTPUT_DIR = os.path.join(SCRIPT_DIR, '..', 'outputs_sex')

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

OUTCOME         = "cvd"
RANDOM_STATE    = 42
N_TRIALS        = 60
BLUE            = "#2563EB"
RED             = "#DC2626"
GREEN           = "#16A34A"
USE_MAHALANOBIS = False


def find_elbow_cutoff(values, min_n=3, max_n=30):
    vals = np.abs(values[:max_n])
    if len(vals) < min_n + 2:
        return min_n
    d2    = np.diff(np.diff(vals))
    elbow = np.argmax(d2) + 2
    return int(np.clip(elbow, min_n, max_n))


# KMedoids per-class classifier
class KMedoidsClassifier(BaseEstimator, ClassifierMixin):

    _estimator_type = "classifier"

    def __init__(self, k_cvd=2, k_nocvd=2, metric='euclidean', random_state=42):
        self.k_cvd        = k_cvd
        self.k_nocvd      = k_nocvd
        self.metric       = metric
        self.random_state = random_state

    def _dist_to_medoids(self, X, medoids):
        if self.metric == 'euclidean':
            diff = X[:, np.newaxis, :] - medoids[np.newaxis, :, :]
            return np.sqrt((diff ** 2).sum(axis=2))
        elif self.metric == 'cosine':
            Xn = X       / (np.linalg.norm(X,      axis=1, keepdims=True) + 1e-9)
            Mn = medoids / (np.linalg.norm(medoids, axis=1, keepdims=True) + 1e-9)
            return np.clip(1.0 - Xn @ Mn.T, 0, 2)
        elif self.metric == 'mahalanobis':
            VI   = self.VI_
            diff = X[:, np.newaxis, :] - medoids[np.newaxis, :, :]
            tmp  = np.einsum('nmd,dk->nmk', diff, VI)
            return np.sqrt(np.einsum('nmk,nmk->nm', tmp, diff).clip(0))
        else:
            raise ValueError(f"Unknown metric: {self.metric}")

    def _mahal_dist_matrix_chunked(self, Xc, chunk_size=500):
        n  = len(Xc)
        D  = np.zeros((n, n), dtype=np.float32)
        VI = self.VI_
        for start in range(0, n, chunk_size):
            end  = min(start + chunk_size, n)
            diff = Xc[start:end, np.newaxis, :] - Xc[np.newaxis, :, :]
            tmp  = np.einsum('imd,dk->imk', diff, VI)
            D[start:end, :] = np.sqrt(np.einsum('imk,imk->im', tmp, diff).clip(0))
        return D

    def fit(self, X, y):
        X = np.asarray(X, dtype=np.float64)
        y = np.asarray(y)
        self.classes_ = np.unique(y)

        if self.metric == 'mahalanobis':
            cov      = np.cov(X.T) + np.eye(X.shape[1]) * 1e-6
            self.VI_ = np.linalg.inv(cov)

        km_metric = 'euclidean' if self.metric == 'mahalanobis' else self.metric

        for cls, k_attr, k_val in [
            (1, 'medoids_cvd_',   self.k_cvd),
            (0, 'medoids_nocvd_', self.k_nocvd),
        ]:
            Xc = X[y == cls]
            k  = min(k_val, len(Xc))
            if self.metric == 'mahalanobis':
                D_pre = self._mahal_dist_matrix_chunked(Xc)
                km = KMedoids(n_clusters=k, metric='precomputed',
                              random_state=self.random_state, init='k-medoids++')
                km.fit(D_pre)
                setattr(self, k_attr, Xc[km.medoid_indices_])
                del D_pre; gc.collect()
            else:
                km = KMedoids(n_clusters=k, metric=km_metric,
                              random_state=self.random_state, init='k-medoids++')
                km.fit(Xc)
                setattr(self, k_attr, km.cluster_centers_)
        return self

    def predict_proba(self, X):
        X       = np.asarray(X, dtype=np.float64)
        d_cvd   = self._dist_to_medoids(X, self.medoids_cvd_  ).min(axis=1)
        d_nocvd = self._dist_to_medoids(X, self.medoids_nocvd_).min(axis=1)
        denom = d_cvd + d_nocvd
        mu    = np.where(denom > 1e-12, (d_cvd - d_nocvd) / denom, 0.0)
        mu    = np.clip(mu, -50.0, 50.0)
        p1    = 1.0 / (1.0 + np.exp(mu))
        return np.column_stack([1.0 - p1, p1])

    def predict(self, X):
        return (self.predict_proba(X)[:, 1] >= 0.5).astype(int)

    def medoids_original_scale(self, scaler, available):
        results = {}
        for label, medoids in [('CVD', self.medoids_cvd_), ('NoCVD', self.medoids_nocvd_)]:
            m = scaler.inverse_transform(medoids.copy())
            results[label] = pd.DataFrame(m, columns=available)
        return results

    def distances_to_nearest_medoid(self, X):
        X       = np.asarray(X, dtype=np.float64)
        d_cvd   = self._dist_to_medoids(X, self.medoids_cvd_  ).min(axis=1)
        d_nocvd = self._dist_to_medoids(X, self.medoids_nocvd_).min(axis=1)
        return d_cvd, d_nocvd

    def medoids_scaled(self):
        return self.medoids_cvd_.copy(), self.medoids_nocvd_.copy()


def evaluate(model, X, y, name):
    preds = model.predict(X)
    probs = model.predict_proba(X)[:, 1]
    acc   = accuracy_score(y, preds)
    f1    = f1_score(y, preds, zero_division=0)
    rec   = recall_score(y, preds, zero_division=0)
    prec  = precision_score(y, preds, zero_division=0)
    auc   = roc_auc_score(y, probs)
    print(f"\n── {name} ──")
    print(f"  AUC {auc:.4f} | Acc {acc:.4f} | Prec {prec:.4f} | Rec {rec:.4f} | F1 {f1:.4f}")
    print(classification_report(y, preds, target_names=["No CVD", "CVD"], zero_division=0))
    return dict(split=name, accuracy=acc, f1=f1, recall=rec, precision=prec, auc=auc)


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

metric_choices = ["euclidean", "cosine", "mahalanobis"] if USE_MAHALANOBIS \
                 else ["euclidean", "cosine"]

all_results  = {}
all_models   = {}
all_scalers  = {}
all_features = {}
all_data     = {}

# Main loop
for cfg in models_config:

    label      = cfg["label"]
    biomarkers = cfg["biomarkers"]
    tr         = cfg["train"]
    te         = cfg["test"]
    va         = cfg["val"]

    print(f"\n{'='*60}")
    print(f"MODEL: {label.upper()}")
    print(f"{'='*60}")

    PLOT_DIR  = os.path.join(OUTPUT_DIR, f'plots_kmedoids_{label}')
    TABLE_DIR = os.path.join(OUTPUT_DIR, f'tables_kmedoids_{label}')
    MODEL_DIR = os.path.join(OUTPUT_DIR, f'models_kmedoids_{label}')
    for d in [PLOT_DIR, TABLE_DIR, MODEL_DIR]:
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

    del X_train, X_test, X_val; gc.collect()

    # Optuna — train on X_train_s, evaluate on X_val_s
    def objective(trial):
        params = dict(
            k_cvd        = trial.suggest_int        ("k_cvd",   1, 8),
            k_nocvd      = trial.suggest_int        ("k_nocvd", 1, 8),
            metric       = trial.suggest_categorical("metric",  metric_choices),
            random_state = RANDOM_STATE,
        )
        try:
            clf   = KMedoidsClassifier(**params)
            clf.fit(X_train_s, y_train)
            probs = clf.predict_proba(X_val_s)[:, 1]
            auc   = roc_auc_score(y_val, probs)
            del clf; gc.collect()
            return auc
        except Exception:
            return 0.5

    print(f"\nOptuna — {N_TRIALS} trials (val set)")
    study = optuna.create_study(
        direction = "maximize",
        sampler   = TPESampler(seed=RANDOM_STATE),
        pruner    = MedianPruner(n_startup_trials=10, n_warmup_steps=0),
    )
    study.optimize(objective, n_trials=N_TRIALS, show_progress_bar=True)

    print(f"\nBest AUC ({label}): {study.best_value:.4f}")
    for k, v in study.best_params.items():
        print(f"  {k:15s} = {v}")

    study.trials_dataframe().to_csv(
        os.path.join(TABLE_DIR, f'kmedoids_optuna_trials_{label}.csv'), index=False)

    with open(os.path.join(MODEL_DIR, f'kmedoids_best_params_{label}.json'), 'w') as f:
        json.dump(study.best_params, f, indent=2)
    with open(os.path.join(MODEL_DIR, f'scaler_{label}.pkl'), 'wb') as f:
        pickle.dump(scaler, f)
    with open(os.path.join(MODEL_DIR, f'available_features_{label}.json'), 'w') as f:
        json.dump(available, f)

    for name, arr in [
        ('X_train_s', X_train_s), ('y_train', y_train),
        ('X_val_s',   X_val_s),   ('y_val',   y_val),
        ('X_test_s',  X_test_s),  ('y_test',  y_test),
    ]:
        np.save(os.path.join(MODEL_DIR, f'{name}_{label}.npy'), arr)

    # Train final model on X_train_s (real patients)
    best = KMedoidsClassifier(**study.best_params, random_state=RANDOM_STATE)
    best.fit(X_train_s, y_train)
    with open(os.path.join(MODEL_DIR, f'kmedoids_final_model_{label}.pkl'), 'wb') as f:
        pickle.dump(best, f)

    # Save datasets with predictions
    tr_out = tr.copy()
    va_out = va.copy()
    te_out = te.copy()

    tr_out["kmedoids_pred"]  = best.predict(X_train_s)
    tr_out["kmedoids_proba"] = best.predict_proba(X_train_s)[:, 1]
    va_out["kmedoids_pred"]  = best.predict(X_val_s)
    va_out["kmedoids_proba"] = best.predict_proba(X_val_s)[:, 1]
    te_out["kmedoids_pred"]  = best.predict(X_test_s)
    te_out["kmedoids_proba"] = best.predict_proba(X_test_s)[:, 1]

    tr_out.to_csv(os.path.join(TABLE_DIR, f'kmedoids_data_train_{label}.csv'), index=False)
    va_out.to_csv(os.path.join(TABLE_DIR, f'kmedoids_data_val_{label}.csv'),   index=False)
    te_out.to_csv(os.path.join(TABLE_DIR, f'kmedoids_data_test_{label}.csv'),  index=False)
    print(f"Saved: kmedoids_data_train/val/test_{label}.csv")

    # Evaluate
    res = [
        evaluate(best, X_train_s, y_train, f"TRAIN ({label})"),
        evaluate(best, X_val_s,   y_val,   f"VAL ({label})"),
        evaluate(best, X_test_s,  y_test,  f"TEST ({label})"),
    ]
    pd.DataFrame(res).to_csv(
        os.path.join(TABLE_DIR, f'kmedoids_performance_{label}.csv'), index=False)

    # Medoid profiles
    medoid_profiles = best.medoids_original_scale(scaler, available)
    for lbl, df in medoid_profiles.items():
        df.index = [f"Medoid_{i+1}" for i in range(len(df))]
        df.to_csv(os.path.join(TABLE_DIR, f'medoids_{lbl}_{label}.csv'))

    cvd_mean   = medoid_profiles['CVD'  ].mean(axis=0)
    nocvd_mean = medoid_profiles['NoCVD'].mean(axis=0)
    diff_pct   = 100 * (cvd_mean - nocvd_mean) / (np.abs(nocvd_mean) + 1e-9)

    diff_df = pd.DataFrame({
        "biomarker":    available,
        "medoid_NoCVD": nocvd_mean.values,
        "medoid_CVD":   cvd_mean.values,
        "diff_%":       diff_pct.values,
    }).sort_values("diff_%", key=abs, ascending=False)

    diff_df.to_csv(os.path.join(TABLE_DIR, f'kmedoids_biomarker_diff_{label}.csv'), index=False)

    TOP_N    = find_elbow_cutoff(diff_df["diff_%"].values)
    top_n    = diff_df.head(TOP_N)
    pop_mean = scaler.inverse_transform(X_train_s.mean(axis=0).reshape(1, -1)).flatten()
    idx_map  = {b: i for i, b in enumerate(available)}
    med_cvd_s, med_nocvd_s = best.medoids_scaled()

    print(f"\nElbow cutoff ({label}): n={TOP_N}")
    print(diff_df.to_string(index=False))

    probs_test = best.predict_proba(X_test_s)[:, 1]
    preds_test = best.predict(X_test_s)

    # Fig 1: Optuna history + importance + performance
    fig1, axes = plt.subplots(1, 3, figsize=(20, 5))
    fig1.suptitle(f"K-Medoids — Optuna tuning [{label.upper()}]",
                  fontsize=14, fontweight="bold")

    ax = axes[0]
    trial_vals  = [t.value for t in study.trials if t.value is not None]
    best_so_far = np.maximum.accumulate(trial_vals)
    ax.scatter(range(len(trial_vals)), trial_vals, s=20, alpha=0.5,
               color="#6366F1", label="Trial")
    ax.plot(range(len(trial_vals)), best_so_far, color=RED, linewidth=2, label="Best so far")
    ax.axhline(study.best_value, color="green", linestyle="--", linewidth=1.2,
               label=f"Best={study.best_value:.4f}")
    ax.set_xlabel("Trial"); ax.set_ylabel("roc_auc")
    ax.set_title("Optimisation history")
    ax.legend(fontsize=8); ax.grid(True, alpha=0.3)

    ax = axes[1]
    try:
        importances = optuna.importance.get_param_importances(study)
        names  = list(importances.keys())
        values = list(importances.values())
        colors = plt.cm.viridis(np.linspace(0.2, 0.85, len(names)))
        ax.barh(names[::-1], values[::-1], color=colors[::-1],
                edgecolor="white", linewidth=0.5)
        ax.set_xlabel("Relative importance (fANOVA)")
        ax.set_title("Hyperparameter importance")
        ax.grid(True, alpha=0.3, axis="x")
    except Exception as e:
        ax.text(0.5, 0.5, f"Not available\n({e})", ha="center", va="center",
                transform=ax.transAxes, fontsize=8)
        ax.set_title("Hyperparameter importance")

    ax = axes[2]
    metrics = ["auc", "accuracy", "precision", "recall", "f1"]
    x = np.arange(len(metrics)); w = 0.25
    split_colors = ["#2196F3", "#FF9800", "#4CAF50"]
    for i, r in enumerate(res):
        vals_m = [r[m] for m in metrics]
        bars   = ax.bar(x + i * w, vals_m, w, label=r["split"],
                        color=split_colors[i], alpha=0.85, edgecolor="white")
        for bar, val in zip(bars, vals_m):
            ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.005,
                    f"{val:.3f}", ha="center", va="bottom", fontsize=7)
    ax.set_xticks(x + w)
    ax.set_xticklabels(["AUC", "Accuracy", "Precision", "Recall", "F1"])
    ax.set_ylim(0, 1.15)
    ax.set_title("Performance")
    ax.legend(fontsize=8); ax.grid(True, alpha=0.3, axis="y")

    plt.tight_layout()
    fig1.savefig(os.path.join(PLOT_DIR, f'fig1_optuna_{label}.png'), dpi=150, bbox_inches='tight')
    fig1.savefig(os.path.join(PLOT_DIR, f'fig1_optuna_{label}.pdf'), bbox_inches='tight')
    plt.close(fig1)
    print(f"Saved: fig1_optuna_{label}")

    # Fig 2: Medoid profiles
    fig2, axes = plt.subplots(1, 3, figsize=(24, max(6, TOP_N * 0.4)))
    fig2.suptitle(f"K-Medoids — Biomarker Profiles [{label.upper()}] (elbow n={TOP_N})",
                  fontsize=14, fontweight="bold")

    ax = axes[0]
    all_abs = np.abs(diff_df["diff_%"].values)
    ax.plot(range(1, len(all_abs) + 1), all_abs, color="#6366F1", linewidth=1.5)
    ax.axvline(TOP_N, color=RED, linestyle="--", linewidth=1.5,
               label=f"Elbow cutoff (n={TOP_N})")
    ax.set_xlabel("Biomarker rank"); ax.set_ylabel("|% Difference|")
    ax.set_title("Elbow — discrimination drop-off")
    ax.legend(fontsize=9); ax.grid(True, alpha=0.3)

    ax = axes[1]
    colors_bar = [RED if v > 0 else BLUE for v in top_n["diff_%"]]
    bars = ax.barh(top_n["biomarker"], top_n["diff_%"],
                   color=colors_bar, edgecolor="white", linewidth=0.5)
    ax.axvline(0, color="black", linewidth=0.8)
    ax.set_xlabel("% Difference (CVD − No-CVD medoid)")
    ax.set_title(f"Top {TOP_N} Discriminative Biomarkers")
    ax.grid(True, alpha=0.3, axis="x")
    for bar, val in zip(bars, top_n["diff_%"]):
        offset = 1 if val > 0 else -1
        ax.text(val + offset, bar.get_y() + bar.get_height() / 2,
                f"{val:+.1f}%", va="center",
                ha="left" if val > 0 else "right", fontsize=7)
    ax.legend(handles=[mpatches.Patch(color=RED,  label="Higher in CVD"),
                       mpatches.Patch(color=BLUE, label="Higher in No-CVD")], fontsize=9)

    ax = axes[2]
    bio_labels = [b.replace("_", "\n", 1) for b in top_n["biomarker"]]
    x_n = np.arange(len(top_n)); w_n = 0.35
    ax.bar(x_n - w_n/2, top_n["medoid_NoCVD"], w_n,
           label="No CVD medoid", color=BLUE, alpha=0.8, edgecolor="white")
    ax.bar(x_n + w_n/2, top_n["medoid_CVD"],   w_n,
           label="CVD medoid",    color=RED,  alpha=0.8, edgecolor="white")
    ax.set_xticks(x_n)
    ax.set_xticklabels(bio_labels, fontsize=7, rotation=30, ha="right")
    ax.set_ylabel("Medoid value (original scale)")
    ax.set_title(f"Medoid Values — CVD vs No-CVD (top {TOP_N})")
    ax.legend(fontsize=9); ax.grid(True, alpha=0.3, axis="y")

    plt.tight_layout()
    fig2.savefig(os.path.join(PLOT_DIR, f'fig2_medoid_profiles_{label}.png'), dpi=150, bbox_inches='tight')
    fig2.savefig(os.path.join(PLOT_DIR, f'fig2_medoid_profiles_{label}.pdf'), bbox_inches='tight')
    plt.close(fig2)
    print(f"Saved: fig2_medoid_profiles_{label}")

    # Fig 3: Predicted probability distribution
    fig3, ax = plt.subplots(figsize=(9, 5))
    ax.hist(probs_test[y_test == 0], bins=40, alpha=0.6, color=BLUE,
            label="No CVD", density=True)
    ax.hist(probs_test[y_test == 1], bins=40, alpha=0.6, color=RED,
            label="CVD", density=True)
    ax.axvline(0.5, color="black", linestyle="--", linewidth=1.2, label="threshold=0.5")
    ax.set_xlabel("P(CVD)"); ax.set_ylabel("Density")
    ax.set_title(f"Predicted probability — TEST [{label.upper()}]")
    ax.legend(fontsize=10); ax.grid(True, alpha=0.3)
    plt.tight_layout()
    fig3.savefig(os.path.join(PLOT_DIR, f'fig3_prob_dist_{label}.png'), dpi=150, bbox_inches='tight')
    fig3.savefig(os.path.join(PLOT_DIR, f'fig3_prob_dist_{label}.pdf'), bbox_inches='tight')
    plt.close(fig3)
    print(f"Saved: fig3_prob_dist_{label}")

    # Fig 4: Prototype patient cards
    card_bios_elbow = diff_df.head(TOP_N)["biomarker"].tolist()
    card_bios_all   = diff_df["biomarker"].tolist()

    all_medoid_data = []
    for lbl, color in [('CVD', RED), ('NoCVD', BLUE)]:
        for i, row in medoid_profiles[lbl].iterrows():
            all_medoid_data.append((lbl, color, i, row.values))

    def plot_prototype_cards(card_bios, suffix, title):
        n_cards = len(all_medoid_data)
        fig4, axes = plt.subplots(1, n_cards,
                                  figsize=(7 * n_cards, max(9, len(card_bios) * 0.28)))
        if n_cards == 1:
            axes = [axes]
        fig4.suptitle(title, fontsize=13, fontweight="bold")

        for ax, (lbl, color, mid, vals) in zip(axes, all_medoid_data):
            bios   = [b for b in card_bios if b in idx_map]
            m_vals = [vals[idx_map[b]] for b in bios]
            p_vals = [pop_mean[idx_map[b]] for b in bios]
            y_pos  = np.arange(len(bios))
            ax.barh(y_pos, m_vals, color=color, alpha=0.7, edgecolor="white")
            ax.plot(p_vals, y_pos, 'o', color='black', markersize=5,
                    label="Population mean", zorder=5)
            ax.set_yticks(y_pos)
            ax.set_yticklabels(bios, fontsize=8)
            ax.set_xlabel("Value (original scale)")
            ax.set_title(f"{'CVD' if lbl=='CVD' else 'No CVD'} — {mid}",
                         fontsize=11, fontweight="bold", color=color)
            ax.legend(fontsize=8)
            ax.grid(True, alpha=0.3, axis="x")

        plt.tight_layout()
        fig4.savefig(os.path.join(PLOT_DIR, f'fig4_prototype_cards_{suffix}_{label}.png'),
                     dpi=150, bbox_inches='tight')
        fig4.savefig(os.path.join(PLOT_DIR, f'fig4_prototype_cards_{suffix}_{label}.pdf'),
                     bbox_inches='tight')
        plt.close(fig4)
        print(f"Saved: fig4_prototype_cards_{suffix}_{label}")

    plot_prototype_cards(card_bios_elbow, "elbow",
        f"Prototype Patient Cards [{label.upper()}] — elbow-selected biomarkers")
    plot_prototype_cards(card_bios_all, "all",
        f"Prototype Patient Cards [{label.upper()}] — all biomarkers")

    # Fig 5: Prototype heatmap (z-scored)
    all_meds_s  = np.vstack([med_cvd_s, med_nocvd_s])
    n_cvd_m     = len(med_cvd_s)
    n_nocvd_m   = len(med_nocvd_s)
    row_labels  = ([f"CVD — M{i+1}"   for i in range(n_cvd_m)] +
                   [f"NoCVD — M{i+1}" for i in range(n_nocvd_m)])

    fig5, ax = plt.subplots(figsize=(max(20, len(available) * 0.35),
                                     max(4, len(row_labels) * 1.2)))
    im = ax.imshow(all_meds_s, aspect="auto", cmap="RdBu_r", vmin=-3, vmax=3)
    ax.set_xticks(range(len(available)))
    ax.set_xticklabels(available, rotation=45, ha="right", fontsize=6)
    ax.set_yticks(range(len(row_labels)))
    ax.set_yticklabels(row_labels, fontsize=9)
    ax.axhline(n_cvd_m - 0.5, color="black", linewidth=2)
    plt.colorbar(im, ax=ax, shrink=0.6, label="Z-score vs population mean")
    ax.set_title(f"Prototype Heatmap [{label.upper()}] — all biomarkers (z-scored)",
                 fontsize=11, fontweight="bold")
    plt.tight_layout()
    fig5.savefig(os.path.join(PLOT_DIR, f'fig5_prototype_heatmap_{label}.png'), dpi=150, bbox_inches='tight')
    fig5.savefig(os.path.join(PLOT_DIR, f'fig5_prototype_heatmap_{label}.pdf'), bbox_inches='tight')
    plt.close(fig5)
    print(f"Saved: fig5_prototype_heatmap_{label}")

    # Fig 6: Distance distributions
    d_cvd_test, d_nocvd_test = best.distances_to_nearest_medoid(X_test_s)

    fig6, axes = plt.subplots(1, 3, figsize=(18, 5))
    fig6.suptitle(f"Distance to Nearest Medoid — TEST [{label.upper()}]",
                  fontsize=13, fontweight="bold")

    ax = axes[0]
    ax.hist(d_cvd_test[y_test == 0], bins=40, alpha=0.6, color=BLUE,
            label="True No CVD", density=True)
    ax.hist(d_cvd_test[y_test == 1], bins=40, alpha=0.6, color=RED,
            label="True CVD", density=True)
    ax.set_xlabel("Distance to nearest CVD medoid")
    ax.set_ylabel("Density"); ax.set_title("Dist. to CVD medoid")
    ax.legend(fontsize=9); ax.grid(True, alpha=0.3)

    ax = axes[1]
    ax.hist(d_nocvd_test[y_test == 0], bins=40, alpha=0.6, color=BLUE,
            label="True No CVD", density=True)
    ax.hist(d_nocvd_test[y_test == 1], bins=40, alpha=0.6, color=RED,
            label="True CVD", density=True)
    ax.set_xlabel("Distance to nearest No-CVD medoid")
    ax.set_ylabel("Density"); ax.set_title("Dist. to No-CVD medoid")
    ax.legend(fontsize=9); ax.grid(True, alpha=0.3)

    ax = axes[2]
    for cls, lbl, col in [(0, "No CVD", BLUE), (1, "CVD", RED)]:
        mask = y_test == cls
        ax.scatter(d_nocvd_test[mask], d_cvd_test[mask],
                   c=col, alpha=0.15, s=8, label=lbl)
    lim = max(d_cvd_test.max(), d_nocvd_test.max()) * 1.05
    ax.plot([0, lim], [0, lim], 'k--', lw=1, label="Decision boundary")
    ax.set_xlabel("Dist. to No-CVD medoid"); ax.set_ylabel("Dist. to CVD medoid")
    ax.set_title("Above diagonal → predicted CVD")
    ax.legend(fontsize=8); ax.grid(True, alpha=0.3)
    ax.set_xlim(0, lim); ax.set_ylim(0, lim)

    plt.tight_layout()
    fig6.savefig(os.path.join(PLOT_DIR, f'fig6_distances_{label}.png'), dpi=150, bbox_inches='tight')
    fig6.savefig(os.path.join(PLOT_DIR, f'fig6_distances_{label}.pdf'), bbox_inches='tight')
    plt.close(fig6)
    print(f"Saved: fig6_distances_{label}")

    # Fig 7: ROC + confusion matrix
    fig7, axes = plt.subplots(1, 2, figsize=(13, 5))
    fig7.suptitle(f"Model Performance — TEST [{label.upper()}]",
                  fontsize=13, fontweight="bold")

    ax = axes[0]
    RocCurveDisplay.from_predictions(y_test, probs_test, ax=ax,
        name=f"K-Medoids (AUC={roc_auc_score(y_test, probs_test):.3f})", color=RED)
    ax.plot([0, 1], [0, 1], 'k--', lw=0.8)
    ax.set_title("ROC Curve — TEST"); ax.grid(True, alpha=0.3)

    ax = axes[1]
    cm_mat = confusion_matrix(y_test, preds_test)
    disp   = ConfusionMatrixDisplay(confusion_matrix=cm_mat,
                                     display_labels=["No CVD", "CVD"])
    disp.plot(ax=ax, colorbar=False, cmap="Blues")
    ax.set_title("Confusion Matrix — TEST")

    plt.tight_layout()
    fig7.savefig(os.path.join(PLOT_DIR, f'fig7_roc_confusion_{label}.png'), dpi=150, bbox_inches='tight')
    fig7.savefig(os.path.join(PLOT_DIR, f'fig7_roc_confusion_{label}.pdf'), bbox_inches='tight')
    plt.close(fig7)
    print(f"Saved: fig7_roc_confusion_{label}")

    # Fig 8: UMAP
    print(f"UMAP for {label}...")
    all_meds_s_plot = np.vstack([med_cvd_s, med_nocvd_s])
    med_labels_plot = ["CVD"] * n_cvd_m + ["NoCVD"] * n_nocvd_m

    np.random.seed(RANDOM_STATE)
    idx_sub = np.random.choice(len(X_test_s), size=min(3000, len(X_test_s)), replace=False)

    reducer = umap.UMAP(n_components=2, random_state=RANDOM_STATE,
                        n_neighbors=15, min_dist=0.1)
    reducer.fit(X_train_s)
    X_test_2d = reducer.transform(X_test_s[idx_sub])
    meds_2d   = reducer.transform(all_meds_s_plot)

    fig8, axes = plt.subplots(1, 2, figsize=(16, 6))
    fig8.suptitle(f"UMAP — test patients and medoids (★) [{label.upper()}]",
                  fontsize=13, fontweight="bold")

    for ax, true_labels, title in zip(
        axes,
        [y_test[idx_sub], best.predict(X_test_s[idx_sub])],
        ["True labels + medoids (★)", "Predicted labels + medoids (★)"],
    ):
        for cls, lbl, col in [(0, "No CVD", BLUE), (1, "CVD", RED)]:
            mask = true_labels == cls
            ax.scatter(X_test_2d[mask, 0], X_test_2d[mask, 1],
                       c=col, alpha=0.12, s=8, label=lbl)
        for i, (pt, lbl) in enumerate(zip(meds_2d, med_labels_plot)):
            col = RED if lbl == "CVD" else BLUE
            ax.scatter(pt[0], pt[1], c=col, s=350, marker="*",
                       edgecolors="black", linewidths=1.2, zorder=6)
            ax.annotate(f"M{i+1}", (pt[0], pt[1]), textcoords="offset points",
                        xytext=(6, 4), fontsize=8, fontweight="bold")
        ax.set_xlabel("UMAP 1"); ax.set_ylabel("UMAP 2")
        ax.set_title(title); ax.legend(fontsize=9); ax.grid(True, alpha=0.2)

    plt.tight_layout()
    fig8.savefig(os.path.join(PLOT_DIR, f'fig8_umap_{label}.png'), dpi=150, bbox_inches='tight')
    fig8.savefig(os.path.join(PLOT_DIR, f'fig8_umap_{label}.pdf'), bbox_inches='tight')
    plt.close(fig8)
    print(f"Saved: fig8_umap_{label}")

    # Store for comparison
    all_results [label] = res
    all_models  [label] = best
    all_scalers [label] = scaler
    all_features[label] = available
    all_data    [label] = dict(
        X_test_s=X_test_s, y_test=y_test,
        X_train_s=X_train_s,
        diff_df=diff_df, top_n=top_n, TOP_N=TOP_N,
        probs_test=probs_test, preds_test=preds_test,
        med_cvd_s=med_cvd_s, med_nocvd_s=med_nocvd_s,
        n_cvd_m=n_cvd_m, n_nocvd_m=n_nocvd_m,
    )

    gc.collect()


# Comparison plots
comparison_dir = os.path.join(OUTPUT_DIR, 'plots_kmedoids_comparison')
os.makedirs(comparison_dir, exist_ok=True)

LABELS       = ["all", "female", "male"]
model_colors = {"all": "#6366F1", "female": "#EC4899", "male": "#0EA5E9"}

# Fig A: TEST performance all 3 models
fig_a, ax = plt.subplots(figsize=(12, 6))
metrics = ["auc", "f1", "recall", "precision", "accuracy"]
x = np.arange(len(metrics)); w = 0.25

for i, label in enumerate(LABELS):
    test_res = all_results[label][2]
    vals     = [test_res[m] for m in metrics]
    bars     = ax.bar(x + i * w, vals, w, label=label.capitalize(),
                      color=model_colors[label], alpha=0.85, edgecolor="white")
    for bar, val in zip(bars, vals):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.005,
                f"{val:.3f}", ha="center", va="bottom", fontsize=7)

ax.set_xticks(x + w)
ax.set_xticklabels(["AUC", "F1", "Recall", "Precision", "Accuracy"])
ax.set_ylim(0, 1.15)
ax.set_title("TEST performance — All vs Female vs Male", fontweight="bold")
ax.legend(fontsize=10); ax.grid(True, alpha=0.3, axis="y")
plt.tight_layout()
fig_a.savefig(os.path.join(comparison_dir, 'fig_comparison_performance.png'), dpi=150, bbox_inches='tight')
fig_a.savefig(os.path.join(comparison_dir, 'fig_comparison_performance.pdf'), bbox_inches='tight')
plt.close(fig_a)
print("Saved: fig_comparison_performance")

# Fig B: Biomarkers all 3 models
fig_b, axes = plt.subplots(1, 3, figsize=(33, 10))
fig_b.suptitle("Discriminative Biomarkers — All vs Female vs Male (elbow cutoff)",
               fontsize=14, fontweight="bold")

for ax, label in zip(axes, LABELS):
    top_df  = all_data[label]["top_n"]
    TOP_N_l = all_data[label]["TOP_N"]
    colors_bar = [RED if v > 0 else BLUE for v in top_df["diff_%"]]
    bars = ax.barh(top_df["biomarker"], top_df["diff_%"],
                   color=colors_bar, edgecolor="white", linewidth=0.5)
    ax.axvline(0, color="black", linewidth=0.8)
    ax.set_xlabel("% Difference (CVD − No-CVD medoid)")
    ax.set_title(f"{label.capitalize()} model (n={TOP_N_l})")
    ax.grid(True, alpha=0.3, axis="x")
    for bar, val in zip(bars, top_df["diff_%"]):
        offset = 1 if val > 0 else -1
        ax.text(val + offset, bar.get_y() + bar.get_height() / 2,
                f"{val:+.1f}%", va="center",
                ha="left" if val > 0 else "right", fontsize=7)
    ax.legend(handles=[mpatches.Patch(color=RED,  label="Higher in CVD"),
                       mpatches.Patch(color=BLUE, label="Higher in No-CVD")], fontsize=9)

plt.tight_layout()
fig_b.savefig(os.path.join(comparison_dir, 'fig_comparison_biomarkers.png'), dpi=150, bbox_inches='tight')
fig_b.savefig(os.path.join(comparison_dir, 'fig_comparison_biomarkers.pdf'), bbox_inches='tight')
plt.close(fig_b)
print("Saved: fig_comparison_biomarkers")

# Fig C: UMAP all 3 models (3x2)
fig_c, axes = plt.subplots(3, 2, figsize=(18, 18))
fig_c.suptitle("UMAP — All vs Female vs Male models", fontsize=14, fontweight="bold")

for row, label in enumerate(LABELS):
    model       = all_models[label]
    X_test_s    = all_data[label]["X_test_s"]
    X_train_s   = all_data[label]["X_train_s"]
    y_test      = all_data[label]["y_test"]
    med_cvd_s   = all_data[label]["med_cvd_s"]
    med_nocvd_s = all_data[label]["med_nocvd_s"]
    n_cvd_m     = all_data[label]["n_cvd_m"]
    n_nocvd_m   = all_data[label]["n_nocvd_m"]

    all_meds_s_c = np.vstack([med_cvd_s, med_nocvd_s])
    med_labels_c = ["CVD"] * n_cvd_m + ["NoCVD"] * n_nocvd_m

    np.random.seed(RANDOM_STATE)
    idx_sub = np.random.choice(len(X_test_s), size=min(2000, len(X_test_s)), replace=False)

    print(f"Running UMAP for comparison [{label}]...")
    reducer = umap.UMAP(n_components=2, random_state=RANDOM_STATE,
                        n_neighbors=15, min_dist=0.1)
    reducer.fit(X_train_s)
    X_test_2d = reducer.transform(X_test_s[idx_sub])
    meds_2d   = reducer.transform(all_meds_s_c)

    for col, (labels_plot, title) in enumerate([
        (y_test[idx_sub],                  f"True labels ({label})"),
        (model.predict(X_test_s[idx_sub]), f"Predicted ({label})"),
    ]):
        ax = axes[row][col]
        for cls, lbl, col_c in [(0, "No CVD", BLUE), (1, "CVD", RED)]:
            mask = labels_plot == cls
            ax.scatter(X_test_2d[mask, 0], X_test_2d[mask, 1],
                       c=col_c, alpha=0.12, s=8, label=lbl)
        for i, (pt, lbl) in enumerate(zip(meds_2d, med_labels_c)):
            c = RED if lbl == "CVD" else BLUE
            ax.scatter(pt[0], pt[1], c=c, s=350, marker="*",
                       edgecolors="black", linewidths=1.2, zorder=6)
            ax.annotate(f"M{i+1}", (pt[0], pt[1]), textcoords="offset points",
                        xytext=(6, 4), fontsize=8, fontweight="bold")
        ax.set_xlabel("UMAP 1"); ax.set_ylabel("UMAP 2")
        ax.set_title(title); ax.legend(fontsize=8); ax.grid(True, alpha=0.2)

plt.tight_layout()
fig_c.savefig(os.path.join(comparison_dir, 'fig_comparison_umap.png'), dpi=150, bbox_inches='tight')
fig_c.savefig(os.path.join(comparison_dir, 'fig_comparison_umap.pdf'), bbox_inches='tight')
plt.close(fig_c)
print("Saved: fig_comparison_umap")

# Fig D: ROC curves all 3 models together
fig_d, ax = plt.subplots(figsize=(8, 6))
for label in LABELS:
    probs = all_data[label]["probs_test"]
    y     = all_data[label]["y_test"]
    auc   = roc_auc_score(y, probs)
    RocCurveDisplay.from_predictions(y, probs, ax=ax,
        name=f"{label.capitalize()} (AUC={auc:.3f})",
        color=model_colors[label])
ax.plot([0, 1], [0, 1], 'k--', lw=0.8)
ax.set_title("ROC Curves — All vs Female vs Male", fontweight="bold")
ax.grid(True, alpha=0.3)
plt.tight_layout()
fig_d.savefig(os.path.join(comparison_dir, 'fig_comparison_roc.png'), dpi=150, bbox_inches='tight')
fig_d.savefig(os.path.join(comparison_dir, 'fig_comparison_roc.pdf'), bbox_inches='tight')
plt.close(fig_d)
print("Saved: fig_comparison_roc")

# Combined performance table
all_perf = []
for label in LABELS:
    for r in all_results[label]:
        r2 = r.copy(); r2["model"] = label
        all_perf.append(r2)
pd.DataFrame(all_perf).to_csv(
    os.path.join(comparison_dir, 'kmedoids_all_performance.csv'), index=False)

print(f"\nAll outputs saved to: {OUTPUT_DIR}")
