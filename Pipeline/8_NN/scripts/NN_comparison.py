import matplotlib
matplotlib.use('Agg')
import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from sklearn.metrics import roc_auc_score, RocCurveDisplay, precision_recall_curve, average_precision_score

# DIRECTORIES

SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR   = os.path.join(SCRIPT_DIR, '..', 'outputs')

TABLE_OPTUNA = os.path.join(OUTPUT_DIR, 'tables_optuna')
TABLE_PAPER  = os.path.join(OUTPUT_DIR, 'tables_paper')

COMPARE_DIR  = os.path.join(OUTPUT_DIR, 'comparison')
os.makedirs(COMPARE_DIR, exist_ok=True)

print(f"Output dir: {COMPARE_DIR}")

# LOAD RESULTS

results_optuna = pd.read_csv(os.path.join(TABLE_OPTUNA, 'mlp_optuna_results.csv'))
results_paper  = pd.read_csv(os.path.join(TABLE_PAPER,  'mlp_paper_results.csv'))

auc_tr_opt  = results_optuna['auc_train'].values[0]
auc_vl_opt  = results_optuna['auc_val'].values[0]
auc_te_opt  = results_optuna['auc_test'].values[0]
time_optuna = results_optuna['training_time_seconds'].values[0]

auc_tr_paper  = results_paper['auc_train'].values[0]
auc_vl_paper  = results_paper['auc_val'].values[0]
auc_te_paper  = results_paper['auc_test'].values[0]
time_paper    = results_paper['training_time_seconds'].values[0]

preds_test_optuna = pd.read_csv(os.path.join(TABLE_OPTUNA, 'mlp_optuna_test_predictions.csv'))
preds_test_paper  = pd.read_csv(os.path.join(TABLE_PAPER,  'mlp_paper_test_predictions.csv'))
preds_val_optuna  = pd.read_csv(os.path.join(TABLE_OPTUNA, 'mlp_optuna_val_predictions.csv'))
preds_val_paper   = pd.read_csv(os.path.join(TABLE_PAPER,  'mlp_paper_val_predictions.csv'))

y_test         = preds_test_optuna['observed'].values
probs_te_opt   = preds_test_optuna['predicted_probability'].values
probs_te_paper = preds_test_paper['predicted_probability'].values

y_val          = preds_val_optuna['observed'].values
probs_vl_opt   = preds_val_optuna['predicted_probability'].values
probs_vl_paper = preds_val_paper['predicted_probability'].values

print(f"Optuna MLP  — Train: {auc_tr_opt:.4f} | Val: {auc_vl_opt:.4f} | Test: {auc_te_opt:.4f}")
print(f"Paper MLP   — Train: {auc_tr_paper:.4f} | Val: {auc_vl_paper:.4f} | Test: {auc_te_paper:.4f}")

# LABELS

NAME_PAPER    = 'Paper arch\n(256→128→100, SELU)'
NAME_OPTUNA   = 'Optuna MLP'
LEGEND_PAPER  = f'Paper arch (AUC={auc_vl_paper:.3f})'
LEGEND_OPTUNA = f'Optuna tuned (AUC={auc_vl_opt:.3f})'
colors        = ['steelblue', 'darkorange']

# FIGURE 1: Main comparison (ROC + AUC bar + Time)

fig, axes = plt.subplots(1, 3, figsize=(18, 5))

# ROC validation
RocCurveDisplay.from_predictions(y_val, probs_vl_paper, ax=axes[0], name=LEGEND_PAPER,  color='steelblue')
RocCurveDisplay.from_predictions(y_val, probs_vl_opt,   ax=axes[0], name=LEGEND_OPTUNA, color='darkorange')
axes[0].plot([0,1],[0,1],'k--', lw=0.8)
axes[0].set_title('ROC — Validation set')
axes[0].set_xlim((0.0, 1.0))
axes[0].set_ylim((0.0, 1.0))
axes[0].legend(fontsize=9)

# AUC bar
models     = [NAME_PAPER, NAME_OPTUNA]
train_aucs = [auc_tr_paper, auc_tr_opt]
val_aucs   = [auc_vl_paper, auc_vl_opt]
x          = range(len(models))
axes[1].bar([i - 0.2 for i in x], train_aucs, width=0.35, color=colors, alpha=0.5, label='Train AUC')
axes[1].bar([i + 0.2 for i in x], val_aucs,   width=0.35, color=colors, alpha=1.0, label='Val AUC')
axes[1].set_xticks(x)
axes[1].set_xticklabels(models, fontsize=9)
axes[1].set_ylabel('AUC')
axes[1].set_ylim((0.5, 1.0))
axes[1].set_title('AUC comparison')
axes[1].legend(fontsize=9)
for i, (tr, vl) in enumerate(zip(train_aucs, val_aucs)):
    axes[1].text(i - 0.2, tr + 0.005, f'{tr:.3f}', ha='center', fontsize=8)
    axes[1].text(i + 0.2, vl + 0.005, f'{vl:.3f}', ha='center', fontsize=8)

# Time
times  = [time_paper, time_optuna]
labels = [f'Paper arch\n({time_paper:.0f}s)', f'Optuna tuned\n({time_optuna:.0f}s)\n(tuning + final)']
bars   = axes[2].bar(labels, times, color=colors, alpha=0.85)
axes[2].set_ylabel('Time (seconds)')
axes[2].set_title('Total compute time')
for bar, t in zip(bars, times):
    axes[2].text(bar.get_x() + bar.get_width()/2, bar.get_height() + 1,
                 f'{t:.0f}s', ha='center', fontsize=10, fontweight='bold')

plt.suptitle('Paper architecture (NeuralCVD: 256→128→100 SELU) vs Optuna-tuned MLP\n', fontweight='bold')
plt.tight_layout()
fig.savefig(os.path.join(COMPARE_DIR, 'fig1_main_comparison.png'), dpi=150, bbox_inches='tight')
fig.savefig(os.path.join(COMPARE_DIR, 'fig1_main_comparison.pdf'),           bbox_inches='tight')
plt.close(fig)
print("Saved: fig1_main_comparison")

# FIGURE 2: ROC test set side by side

fig, axes = plt.subplots(1, 2, figsize=(14, 6))

for ax, y, probs_p, probs_o, split in [
    (axes[0], y_val,  probs_vl_paper, probs_vl_opt, 'Validation'),
    (axes[1], y_test, probs_te_paper, probs_te_opt, 'Test')
]:
    RocCurveDisplay.from_predictions(y, probs_p, ax=ax,
        name=f'Paper arch (AUC={roc_auc_score(y, probs_p):.3f})', color='steelblue')
    RocCurveDisplay.from_predictions(y, probs_o, ax=ax,
        name=f'Optuna MLP (AUC={roc_auc_score(y, probs_o):.3f})', color='darkorange')
    ax.plot([0,1],[0,1],'k--', lw=0.8)
    ax.set_title(f'ROC Curve — {split}')
    ax.set_xlim((0.0, 1.0))
    ax.set_ylim((0.0, 1.0))
    ax.legend(fontsize=9)

plt.suptitle('ROC Curves — Validation vs Test', fontweight='bold')
plt.tight_layout()
fig.savefig(os.path.join(COMPARE_DIR, 'fig2_roc_val_test.png'), dpi=150, bbox_inches='tight')
fig.savefig(os.path.join(COMPARE_DIR, 'fig2_roc_val_test.pdf'),           bbox_inches='tight')
plt.close(fig)
print("Saved: fig2_roc_val_test")

# FIGURE 3: Precision-Recall curves 

fig, axes = plt.subplots(1, 2, figsize=(14, 6))

for ax, y, probs_p, probs_o, split in [
    (axes[0], y_val,  probs_vl_paper, probs_vl_opt, 'Validation'),
    (axes[1], y_test, probs_te_paper, probs_te_opt, 'Test')
]:
    for probs, color, name in [
        (probs_p, 'steelblue',  'Paper arch'),
        (probs_o, 'darkorange', 'Optuna MLP')
    ]:
        prec, rec, _ = precision_recall_curve(y, probs)
        ap = average_precision_score(y, probs)
        ax.plot(rec, prec, color=color, label=f'{name} (AP={ap:.3f})')
    ax.axhline(y.mean(), color='grey', linestyle='--', lw=0.8, label=f'Baseline ({y.mean():.3f})')
    ax.set_xlabel('Recall')
    ax.set_ylabel('Precision')
    ax.set_title(f'Precision-Recall — {split}')
    ax.legend(fontsize=9)
    ax.set_xlim((0.0, 1.0))
    ax.set_ylim((0.0, 1.0))

plt.suptitle('Precision-Recall Curves', fontweight='bold')
plt.tight_layout()
fig.savefig(os.path.join(COMPARE_DIR, 'fig3_precision_recall.png'), dpi=150, bbox_inches='tight')
fig.savefig(os.path.join(COMPARE_DIR, 'fig3_precision_recall.pdf'),           bbox_inches='tight')
plt.close(fig)
print("Saved: fig3_precision_recall")

# FIGURE 4: AUC train/val/test grouped

fig, ax = plt.subplots(figsize=(9, 5))

splits     = ['Train', 'Val', 'Test']
aucs_paper = [auc_tr_paper, auc_vl_paper, auc_te_paper]
aucs_opt   = [auc_tr_opt,   auc_vl_opt,   auc_te_opt]
x          = np.arange(len(splits))
width      = 0.35

bars1 = ax.bar(x - width/2, aucs_paper, width, label='Paper arch',  color='steelblue',  alpha=0.85)
bars2 = ax.bar(x + width/2, aucs_opt,   width, label='Optuna MLP',  color='darkorange', alpha=0.85)

for bar in bars1:
    ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.003,
            f'{bar.get_height():.3f}', ha='center', fontsize=8)
for bar in bars2:
    ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.003,
            f'{bar.get_height():.3f}', ha='center', fontsize=8)

ax.set_xticks(x)
ax.set_xticklabels(splits)
ax.set_ylabel('AUC')
ax.set_ylim((0.5, 1.0))
ax.set_title('AUC across Train / Val / Test splits')
ax.legend(fontsize=10)
ax.axhline(0.5, color='grey', linestyle='--', lw=0.8)

plt.tight_layout()
fig.savefig(os.path.join(COMPARE_DIR, 'fig4_auc_splits.png'), dpi=150, bbox_inches='tight')
fig.savefig(os.path.join(COMPARE_DIR, 'fig4_auc_splits.pdf'),           bbox_inches='tight')
plt.close(fig)
print("Saved: fig4_auc_splits")

# FIGURE 5: Predicted probability distributions

fig, axes = plt.subplots(2, 2, figsize=(14, 10))

for row, (probs, name, color) in enumerate([
    (probs_te_paper, 'Paper arch',  'steelblue'),
    (probs_te_opt,   'Optuna MLP',  'darkorange')
]):
    for col, label, mask in [
        (0, 'No CVD (0)', y_test == 0),
        (1, 'CVD (1)',    y_test == 1)
    ]:
        axes[row, col].hist(probs[mask], bins=50, color=color, alpha=0.7, edgecolor='white')
        axes[row, col].set_title(f'{name} — {label}')
        axes[row, col].set_xlabel('Predicted probability')
        axes[row, col].set_ylabel('Count')
        axes[row, col].axvline(0.5, color='red', linestyle='--', lw=1)

plt.suptitle('Predicted probability distributions by outcome — Test set', fontweight='bold')
plt.tight_layout()
fig.savefig(os.path.join(COMPARE_DIR, 'fig5_prob_distributions.png'), dpi=150, bbox_inches='tight')
fig.savefig(os.path.join(COMPARE_DIR, 'fig5_prob_distributions.pdf'),           bbox_inches='tight')
plt.close(fig)
print("Saved: fig5_prob_distributions")

# Final table

summary = pd.DataFrame([
    {
        'model':                 'Paper arch (256→128→100, SELU)',
        'auc_train':             round(auc_tr_paper, 4),
        'auc_val':               round(auc_vl_paper, 4),
        'auc_test':              round(auc_te_paper, 4),
        'training_time_seconds': round(time_paper, 1),
    },
    {
        'model':                 'Optuna tuned MLP',
        'auc_train':             round(auc_tr_opt, 4),
        'auc_val':               round(auc_vl_opt, 4),
        'auc_test':              round(auc_te_opt, 4),
        'training_time_seconds': round(time_optuna, 1),
    }
])

summary.to_csv(os.path.join(COMPARE_DIR, 'mlp_comparison_summary.csv'), index=False)

print('\n' + '='*70)
print('COMPARISON SUMMARY')
print('='*70)
print(f"{'Model':<35} {'Train':>8} {'Val':>8} {'Test':>8} {'Time(s)':>10}")
print('-'*70)
for _, row in summary.iterrows():
    print(f"{row['model']:<35} {row['auc_train']:>8.4f} {row['auc_val']:>8.4f} {row['auc_test']:>8.4f} {row['training_time_seconds']:>10.1f}")
print('='*70)

print(f'\nAll outputs saved to: {COMPARE_DIR}')
