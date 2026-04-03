# Train final LVQ1 and generate analysis plots — sex-stratified
# Loads best params from param script, trains on balanced data, evaluates on original splits, and produces comparison plots across models

import matplotlib
matplotlib.use('Agg')
import warnings
warnings.filterwarnings("ignore")

import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import umap
import pickle
import json

from sklearn.base    import BaseEstimator, ClassifierMixin
from sklearn.metrics import (
    accuracy_score, f1_score, recall_score,
    precision_score, classification_report, roc_auc_score,
)

# Directories
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, '..', 'outputs')

RANDOM_STATE = 42
BLUE         = "#2563EB"
RED          = "#DC2626"
GREEN        = "#16A34A"
LABELS       = ["all", "female", "male"]


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


def top_by_elbow(diff_df):
    """Cut biomarker list where the largest drop in |diff_%| occurs."""
    vals = diff_df["diff_%"].abs().values
    if len(vals) <= 2:
        return diff_df
    drops  = np.abs(np.diff(vals))
    cutoff = int(np.argmax(drops)) + 1
    cutoff = max(cutoff, 5)
    return diff_df.iloc[:cutoff]


# Train and evaluate each model
all_results  = {}
all_models   = {}
all_scalers  = {}
all_features = {}
all_data     = {}

for label in LABELS:

    print(f"\n{'='*60}")
    print(f"MODEL: {label.upper()}")
    print(f"{'='*60}")

    model_dir = os.path.join(OUTPUT_DIR, f'models_lvq_{label}')
    table_dir = os.path.join(OUTPUT_DIR, f'tables_lvq_{label}')
    plot_dir  = os.path.join(OUTPUT_DIR, f'plots_lvq_{label}')
    for d in [table_dir, plot_dir]:
        os.makedirs(d, exist_ok=True)

    with open(os.path.join(model_dir, f'lvq1_best_params_{label}.json')) as f:
        best_params = json.load(f)
    with open(os.path.join(model_dir, f'available_features_{label}.json')) as f:
        available = json.load(f)
    with open(os.path.join(model_dir, f'scaler_{label}.pkl'), 'rb') as f:
        scaler = pickle.load(f)

    X_train_bal = np.load(os.path.join(model_dir, f'X_train_bal_{label}.npy'))
    y_train_bal = np.load(os.path.join(model_dir, f'y_train_bal_{label}.npy'))
    X_train_s   = np.load(os.path.join(model_dir, f'X_train_s_{label}.npy'))
    X_val_s     = np.load(os.path.join(model_dir, f'X_val_s_{label}.npy'))
    X_test_s    = np.load(os.path.join(model_dir, f'X_test_s_{label}.npy'))
    y_train     = np.load(os.path.join(model_dir, f'y_train_{label}.npy'))
    y_val       = np.load(os.path.join(model_dir, f'y_val_{label}.npy'))
    y_test      = np.load(os.path.join(model_dir, f'y_test_{label}.npy'))

    print(f"Best params: {best_params}")

    # Load final model
    with open(os.path.join(model_dir, f'lvq1_final_model_{label}.pkl'), 'rb') as f:
        best = pickle.load(f)

    # Evaluate
    res = [
        evaluate(best, X_train_s, y_train, f"TRAIN ({label})"),
        evaluate(best, X_val_s,   y_val,   f"VAL ({label})"),
        evaluate(best, X_test_s,  y_test,  f"TEST ({label})"),
    ]
    pd.DataFrame(res).to_csv(
        os.path.join(table_dir, f'lvq1_performance_{label}.csv'), index=False)

    # Prototype profiles
    protos_orig = scaler.inverse_transform(best.prototypes_)
    cvd_mean    = protos_orig[best.proto_labels_ == 1].mean(axis=0)
    nocvd_mean  = protos_orig[best.proto_labels_ == 0].mean(axis=0)
    diff_pct    = 100 * (cvd_mean - nocvd_mean) / (np.abs(nocvd_mean) + 1e-9)

    diff_df = pd.DataFrame({
        "biomarker":   available,
        "proto_NoCVD": nocvd_mean,
        "proto_CVD":   cvd_mean,
        "diff_%":      diff_pct,
    }).sort_values("diff_%", key=abs, ascending=False)

    diff_df.to_csv(os.path.join(table_dir, f'lvq1_prototype_diff_{label}.csv'), index=False)

    top_df = top_by_elbow(diff_df)
    print(f"\nDifferential biomarkers ({label}) — elbow cutoff at n={len(top_df)}:")
    print(top_df.to_string(index=False))

    # Fig 1: biomarker bar + probability distribution
    fig1, axes = plt.subplots(1, 2, figsize=(18, max(6, len(top_df) * 0.4)))
    fig1.suptitle(f"LVQ1 Prototypes — {label.upper()}", fontsize=14, fontweight="bold")

    ax = axes[0]
    colors_bar = [RED if v > 0 else BLUE for v in top_df["diff_%"]]
    bars = ax.barh(top_df["biomarker"], top_df["diff_%"],
                   color=colors_bar, edgecolor="white", linewidth=0.5)
    ax.axvline(0, color="black", linewidth=0.8)
    ax.set_xlabel("% Difference (CVD − No-CVD prototype)")
    ax.set_title(f"Discriminative Biomarkers (n={len(top_df)})")
    ax.grid(True, alpha=0.3, axis="x")
    for bar, val in zip(bars, top_df["diff_%"]):
        offset = 1 if val > 0 else -1
        ax.text(val + offset, bar.get_y() + bar.get_height() / 2,
                f"{val:+.1f}%", va="center",
                ha="left" if val > 0 else "right", fontsize=7)
    ax.legend(handles=[mpatches.Patch(color=RED,  label="Higher in CVD"),
                       mpatches.Patch(color=BLUE, label="Higher in No-CVD")], fontsize=9)

    ax = axes[1]
    probs_test = best.predict_proba(X_test_s)[:, 1]
    ax.hist(probs_test[y_test == 0], bins=40, alpha=0.6, color=BLUE,
            label="No CVD", density=True)
    ax.hist(probs_test[y_test == 1], bins=40, alpha=0.6, color=RED,
            label="CVD", density=True)
    ax.axvline(0.5, color="black", linestyle="--", linewidth=1.2)
    ax.set_xlabel("P(CVD)"); ax.set_ylabel("Density")
    ax.set_title("Predicted probability — TEST")
    ax.legend(fontsize=9); ax.grid(True, alpha=0.3)

    plt.tight_layout()
    fig1.savefig(os.path.join(plot_dir, f'fig_biomarkers_{label}.png'), dpi=150, bbox_inches='tight')
    fig1.savefig(os.path.join(plot_dir, f'fig_biomarkers_{label}.pdf'), bbox_inches='tight')
    plt.close(fig1)
    print(f"Saved: fig_biomarkers_{label}")

    # Fig 2: prototype heatmap
    proto_norm = pd.DataFrame(protos_orig, columns=available)
    for col in proto_norm.columns:
        mn, mx = proto_norm[col].min(), proto_norm[col].max()
        proto_norm[col] = (proto_norm[col] - mn) / (mx - mn + 1e-9)

    n_nocvd    = (best.proto_labels_ == 0).sum()
    row_labels = [f"{'CVD' if l==1 else 'NoCVD'} — P{i+1}"
                  for i, l in enumerate(best.proto_labels_)]

    fig2, ax = plt.subplots(figsize=(22, max(4, len(row_labels) * 1.2)))
    im = ax.imshow(proto_norm.values, aspect="auto", cmap="RdYlBu_r", vmin=0, vmax=1)
    ax.set_xticks(range(len(available)))
    ax.set_xticklabels(available, rotation=45, ha="right", fontsize=7)
    ax.set_yticks(range(len(row_labels)))
    ax.set_yticklabels(row_labels, fontsize=9)
    ax.axhline(n_nocvd - 0.5, color="black", linewidth=2)
    ax.set_title(f"LVQ1 Prototype Heatmap — {label.upper()} (min-max normalised)",
                 fontsize=11, fontweight="bold")
    plt.colorbar(im, ax=ax, shrink=0.6, label="Normalised value (0=low, 1=high)")
    plt.tight_layout()
    fig2.savefig(os.path.join(plot_dir, f'fig_heatmap_{label}.png'), dpi=150, bbox_inches='tight')
    fig2.savefig(os.path.join(plot_dir, f'fig_heatmap_{label}.pdf'), bbox_inches='tight')
    plt.close(fig2)
    print(f"Saved: fig_heatmap_{label}")

    # Store for comparison
    all_results [label] = res
    all_models  [label] = best
    all_scalers [label] = scaler
    all_features[label] = available
    all_data    [label] = dict(
        X_test_s=X_test_s, y_test=y_test,
        protos_orig=protos_orig, diff_df=diff_df, top_df=top_df,
    )


# Comparison plots
comparison_dir = os.path.join(OUTPUT_DIR, 'plots_lvq_comparison')
os.makedirs(comparison_dir, exist_ok=True)

# Fig A: TEST performance all models
fig_a, ax = plt.subplots(figsize=(10, 6))
metrics      = ["auc", "f1", "recall", "precision", "accuracy"]
x            = np.arange(len(metrics))
w            = 0.25
model_colors = {"all": "#6366F1", "female": "#EC4899", "male": "#0EA5E9"}

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

# Fig B: biomarkers all 3 models with elbow cutoff
fig_b, axes = plt.subplots(1, 3, figsize=(33, 10))
fig_b.suptitle("Discriminative Biomarkers — All vs Female vs Male (elbow cutoff)",
               fontsize=14, fontweight="bold")

for ax, label in zip(axes, ["all", "female", "male"]):
    top_df     = all_data[label]["top_df"]
    colors_bar = [RED if v > 0 else BLUE for v in top_df["diff_%"]]
    bars = ax.barh(top_df["biomarker"], top_df["diff_%"],
                   color=colors_bar, edgecolor="white", linewidth=0.5)
    ax.axvline(0, color="black", linewidth=0.8)
    ax.set_xlabel("% Difference (CVD − No-CVD prototype)")
    ax.set_title(f"{label.capitalize()} model (n={len(top_df)})")
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

# Fig C: UMAP all 3 models
fig_c, axes = plt.subplots(3, 2, figsize=(18, 18))
fig_c.suptitle("UMAP — All vs Female vs Male models", fontsize=14, fontweight="bold")

for row, label in enumerate(["all", "female", "male"]):
    model    = all_models[label]
    X_test_s = all_data[label]["X_test_s"]
    y_test   = all_data[label]["y_test"]

    np.random.seed(RANDOM_STATE)
    idx_s = np.random.choice(len(X_test_s), size=min(2000, len(X_test_s)), replace=False)

    print(f"Running UMAP for {label}...")
    reducer  = umap.UMAP(n_components=2, random_state=RANDOM_STATE,
                         n_neighbors=15, min_dist=0.1)
    all_umap = reducer.fit_transform(np.vstack([X_test_s[idx_s], model.prototypes_]))
    pts_umap  = all_umap[:len(idx_s)]
    prot_umap = all_umap[len(idx_s):]

    for col, (labels_plot, title) in enumerate([
        (y_test[idx_s],                  f"True labels ({label})"),
        (model.predict(X_test_s[idx_s]), f"Predicted ({label})"),
    ]):
        ax = axes[row][col]
        for cls, lbl, col_c in [(0, "No CVD", BLUE), (1, "CVD", RED)]:
            mask = labels_plot == cls
            ax.scatter(pts_umap[mask, 0], pts_umap[mask, 1],
                       c=col_c, alpha=0.15, s=10, label=lbl)
        for i, (pt, lbl) in enumerate(zip(prot_umap, model.proto_labels_)):
            c = RED if lbl == 1 else BLUE
            ax.scatter(pt[0], pt[1], c=c, s=300, marker="*",
                       edgecolors="black", linewidths=1.2, zorder=6)
            ax.annotate(f"P{i+1}", (pt[0], pt[1]), textcoords="offset points",
                        xytext=(6, 4), fontsize=8, fontweight="bold")
        ax.set_xlabel("UMAP 1"); ax.set_ylabel("UMAP 2")
        ax.set_title(title); ax.legend(fontsize=8); ax.grid(True, alpha=0.2)

plt.tight_layout()
fig_c.savefig(os.path.join(comparison_dir, 'fig_comparison_umap.png'), dpi=150, bbox_inches='tight')
fig_c.savefig(os.path.join(comparison_dir, 'fig_comparison_umap.pdf'), bbox_inches='tight')
plt.close(fig_c)
print("Saved: fig_comparison_umap")

# Combined performance table
all_perf = []
for label in LABELS:
    for r in all_results[label]:
        r2 = r.copy()
        r2["model"] = label
        all_perf.append(r2)
pd.DataFrame(all_perf).to_csv(
    os.path.join(comparison_dir, 'lvq1_all_performance.csv'), index=False)

print(f"\nAll outputs saved to: {OUTPUT_DIR}")
