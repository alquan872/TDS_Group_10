import matplotlib
matplotlib.use('Agg')
import os
import pickle
import json
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import seaborn as sns
from matplotlib.patches import Ellipse
from sklearn.linear_model import LogisticRegression
from sklearn.mixture import GaussianMixture
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.metrics import (roc_auc_score, RocCurveDisplay, ConfusionMatrixDisplay,
                              precision_score, recall_score, f1_score, balanced_accuracy_score)
from sklearn.utils import resample


# Output directories
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PDF_DIR    = os.path.join(SCRIPT_DIR, '..', 'outputs', 'gmm_plots')
TABLE_DIR  = os.path.join(SCRIPT_DIR, '..', 'outputs', 'tables')
MODEL_DIR  = os.path.join(SCRIPT_DIR, '..', 'outputs', 'models')
os.makedirs(PDF_DIR,   exist_ok=True)
os.makedirs(TABLE_DIR, exist_ok=True)
os.makedirs(MODEL_DIR, exist_ok=True)


def save_fig(fig, name):
    fig.savefig(os.path.join(PDF_DIR, f'{name}.png'), dpi=150, bbox_inches='tight')
    fig.savefig(os.path.join(PDF_DIR, f'{name}.pdf'),           bbox_inches='tight')
    plt.close(fig)


def save_table(df, name):
    df.to_csv(os.path.join(TABLE_DIR, f'{name}.csv'), index=True)
    print(f'  [table saved] {name}.csv')


# Read the files
train = pd.read_csv("../../2_Imputation/outputs/ukb_train_imputed.csv")
val   = pd.read_csv("../../2_Imputation/outputs/ukb_val_imputed.csv")
test  = pd.read_csv("../../2_Imputation/outputs/ukb_test_imputed.csv")


# 3 categories: division in terciles
_, cvh_bins = pd.qcut(train['CVH_score'], q=3, labels=['Low', 'Mid', 'High'], retbins=True)
_, bhs_bins = pd.qcut(train['BHS'],       q=3, labels=['Low', 'Mid', 'High'], retbins=True)
for df in [train, val, test]:
    df['CVH_group'] = pd.cut(df['CVH_score'], bins=cvh_bins,
                              labels=['Low', 'Mid', 'High'], include_lowest=True)
    df['BHS_group'] = pd.cut(df['BHS'],       bins=bhs_bins,
                              labels=['Low', 'Mid', 'High'], include_lowest=True)
    df['profile']   = df['CVH_group'].astype(str) + ' CVH / ' + df['BHS_group'].astype(str) + ' BHS'

profile_cvd = train.groupby('profile')['cvd'].agg(['mean', 'count']).round(3)
profile_cvd.columns = ['cvd_rate', 'n']
profile_cvd_sorted = profile_cvd.sort_values('cvd_rate', ascending=False)
print(profile_cvd_sorted)
save_table(profile_cvd_sorted, 'T1_profile_cvd_rates')

# Heatmap
fig, axes = plt.subplots(1, 3, figsize=(18, 5))
for ax, df, name in zip(axes, [train, val, test], ['Train', 'Val', 'Test']):
    pivot = df.groupby(['CVH_group', 'BHS_group'], observed=True)['cvd'].mean().unstack()
    pivot = pivot.reindex(['High', 'Mid', 'Low']).reindex(['Low', 'Mid', 'High'], axis=1)
    sns.heatmap(pivot, annot=True, fmt='.3f', cmap='RdYlGn_r',
                ax=ax, linewidths=0.5, vmin=0.10, vmax=0.25)
    ax.set_title(f'CVD rate by CVH x BHS — {name}')
    ax.set_xlabel('BHS group'); ax.set_ylabel('CVH group')
plt.suptitle('CVD rate by CVH x BHS groups', fontweight='bold')
plt.tight_layout()
save_fig(fig, '00_cvh_bhs_heatmap')


# Scale
scaler  = StandardScaler()
X_train = scaler.fit_transform(train[['CVH_score', 'BHS']])
X_val   = scaler.transform(val[['CVH_score', 'BHS']])
X_test  = scaler.transform(test[['CVH_score', 'BHS']])

COV_TYPE = 'full'
K_RANGE  = range(2, 9)
N_SEEDS  = 5
N_INITS  = 10

# Select K via BIC
bic_scores = []
for k in K_RANGE:
    bic_k = [GaussianMixture(n_components=k, n_init=N_INITS, covariance_type=COV_TYPE,
                              random_state=s).fit(X_train).bic(X_train)
             for s in range(N_SEEDS)]
    bic_scores.append(min(bic_k))
    print(f'K={k} | BIC={bic_scores[-1]:.0f}')

ks        = list(K_RANGE)
bic_diff2 = np.diff(np.diff(bic_scores))
best_k    = ks[1 + np.argmax(bic_diff2)]
print(f'\nK selected: {best_k}')

# GMM model
candidates = [GaussianMixture(n_components=best_k, n_init=N_INITS, covariance_type=COV_TYPE,
                               random_state=s).fit(X_train)
              for s in range(N_SEEDS)]
gmm = min(candidates, key=lambda m: m.bic(X_train))

# Assign clusters
train, val, test = train.copy(), val.copy(), test.copy()
train['cluster'] = gmm.predict(X_train)
val['cluster']   = gmm.predict(X_val)
test['cluster']  = gmm.predict(X_test)

order            = train.groupby('cluster')['CVH_score'].mean().sort_values().index
remap            = {old: new for new, old in enumerate(order)}
train['cluster'] = train['cluster'].map(remap)
val['cluster']   = val['cluster'].map(remap)
test['cluster']  = test['cluster'].map(remap)

cmap    = plt.cm.get_cmap('tab10', best_k)
MARKERS = ['o', 's', '^', 'D', 'v', 'p', '*']


# Ellipses for the clusters
def draw_ellipses(ax, gmm, remap, scaler, cmap):
    S = scaler.scale_
    for new_idx in range(gmm.n_components):
        orig_idx   = [o for o, n in remap.items() if n == new_idx][0]
        mean       = scaler.inverse_transform(gmm.means_[orig_idx].reshape(1, -1)).flatten()
        cov        = gmm.covariances_[orig_idx] * np.outer(S, S)
        vals, vecs = np.linalg.eigh(cov)
        angle      = np.degrees(np.arctan2(vecs[1, -1], vecs[0, -1]))
        for n_std, lw, alpha in [(1, 1.5, 0.7), (2, 0.8, 0.35)]:
            ax.add_patch(Ellipse(xy=mean,
                                 width=2 * n_std * np.sqrt(vals[-1]),
                                 height=2 * n_std * np.sqrt(vals[-2]),
                                 angle=angle, edgecolor=cmap(new_idx),
                                 facecolor='none', lw=lw, linestyle='--', alpha=alpha))
        ax.plot(*mean, '+', color=cmap(new_idx), ms=10, mew=2)


def scatter_clusters(ax, df, title, gmm, remap, scaler, cmap):
    X   = df[['CVH_score', 'BHS']].values
    lbl = df['cluster'].values
    for c in range(gmm.n_components):
        m = lbl == c
        ax.scatter(X[m, 0], X[m, 1],
                   marker=MARKERS[c % len(MARKERS)],
                   color=cmap(c), edgecolors='white', linewidths=0.3,
                   s=15, alpha=0.85, label=f'Cluster {c}')
    draw_ellipses(ax, gmm, remap, scaler, cmap)
    ax.set(xlim=(X[:, 0].min() - 1, X[:, 0].max() + 1),
           ylim=(X[:, 1].min() - 0.02, X[:, 1].max() + 0.02),
           xlabel='CVH_score', ylabel='BHS', title=title)
    ax.legend(markerscale=1.2, fontsize=7, framealpha=0.9)


# BIC plot
fig, ax = plt.subplots(figsize=(7, 4))
ax.plot(ks, bic_scores, 'o-', color='steelblue')
ax.axvline(best_k, color='red', linestyle='--', label=f'Elbow K={best_k}')
ax.set(xlabel='K', ylabel='BIC', title='K selection — GMM')
ax.legend()
plt.tight_layout()
save_fig(fig, '01_bic')

# Scatter plots
for i, (df, label) in enumerate([(train, 'Train'), (val, 'Val'), (test, 'Test')], start=2):
    fig, ax = plt.subplots(figsize=(6, 4))
    scatter_clusters(ax, df, f'GMM clusters (K={best_k}) — {label}', gmm, remap, scaler, cmap)
    plt.tight_layout()
    save_fig(fig, f'0{i}_scatter_{label.lower()}')

# Cluster profiles heatmap Train vs Test
fig, axes = plt.subplots(1, 2, figsize=(14, max(3, best_k * 0.9 + 2)))
for ax, df, label in zip(axes, [train, test], ['Train', 'Test']):
    p             = df.groupby('cluster')[['CVH_score', 'BHS']].mean().round(3)
    p['cvd_rate'] = df.groupby('cluster')['cvd'].mean().round(3)
    p['n']        = df.groupby('cluster').size()

    p_z          = p[['CVH_score', 'BHS', 'cvd_rate']].apply(lambda x: (x - x.mean()) / x.std())
    p_z_plot     = p_z.copy()
    p_z_plot['BHS']      = -p_z_plot['BHS']
    p_z_plot['cvd_rate'] = -p_z_plot['cvd_rate']

    im = ax.imshow(p_z_plot.values, cmap='RdYlGn', aspect='auto', vmin=-2, vmax=2)
    ax.set_xticks(range(3))
    ax.set_xticklabels(['CVH_score', 'BHS ↓', 'CVD rate ↓'])
    ax.set_yticks(range(best_k))
    ax.set_yticklabels([f'Cluster {c}  (n={int(p["n"].iloc[c]):,})' for c in range(best_k)])
    ax.set_title(f'Cluster profiles (z-scored) — {label}')
    plt.colorbar(im, ax=ax, shrink=0.8, label='← worse   better →')
    for i in range(best_k):
        for j, col in enumerate(['CVH_score', 'BHS', 'cvd_rate']):
            ax.text(j, i, f'{p[col].iloc[i]:.3f}',
                    ha='center', va='center', fontsize=9, fontweight='bold')

plt.suptitle('GMM Cluster Profiles — CVH & BHS\n(green = better, red = worse)', fontweight='bold')
plt.tight_layout()
save_fig(fig, '05_profiles')

# CVD rate barplot Train vs Test
fig, axes = plt.subplots(1, 2, figsize=(14, max(3, best_k * 0.9 + 2)))
for ax, df, label in zip(axes, [train, test], ['Train', 'Test']):
    cvd_rates = df.groupby('cluster')['cvd'].mean().values
    ax.barh(range(best_k), cvd_rates, color=[cmap(c) for c in range(best_k)], alpha=0.85)
    ax.axvline(df['cvd'].mean(), color='red', linestyle='--',
               label=f'Global mean ({df["cvd"].mean():.3f})')
    ax.set_yticks(range(best_k))
    ax.set_yticklabels([f'Cluster {c}' for c in range(best_k)])
    ax.set(xlabel='CVD rate', title=f'CVD rate per cluster — {label}')
    ax.legend(fontsize=8)
    for i, v in enumerate(cvd_rates):
        ax.text(v + 0.001, i, f'{v:.3f}', va='center', fontsize=9)
plt.suptitle('CVD rate per cluster — Train vs Test', fontweight='bold')
plt.tight_layout()
save_fig(fig, '06_cvd_rates')

print(f'\nPDFs/PNGs saved to: {PDF_DIR}/')

print("\nCluster counts:")
cluster_counts_list = []
for label, df in [('Train', train), ('Val', val), ('Test', test)]:
    counts = df['cluster'].value_counts().sort_index().rename(label)
    cluster_counts_list.append(counts)
    print(f'\n{label}:')
    print(counts)

cluster_counts_df = pd.concat(cluster_counts_list, axis=1)
save_table(cluster_counts_df, 'T2_cluster_counts')


# Outcome and confounders
y_train = train['cvd'].astype(int)
y_val   = val['cvd'].astype(int)
y_test  = test['cvd'].astype(int)

CONFOUNDER_NUM = ['age_at_recruitment']
CONFOUNDER_CAT = ['sex']

MODELS = {
    'CVH + confounders':          ['CVH_score'],
    'BHS + confounders':          ['BHS'],
    'CVH + BHS + confounders':    ['CVH_score', 'BHS'],
    'CVH + BHS + cluster + conf': ['CVH_score', 'BHS'],
    'CVH * BHS + confounders':    ['CVH_score', 'BHS'],
}

ohe_sex     = OneHotEncoder(drop='first', sparse_output=False, handle_unknown='ignore')
ohe_cluster = OneHotEncoder(drop='first', sparse_output=False, handle_unknown='ignore')
ohe_sex.fit(train[CONFOUNDER_CAT])
ohe_cluster.fit(train[['cluster']])

results = {}
for name, features in MODELS.items():
    use_confounders = 'conf' in name
    use_cluster     = 'cluster' in name
    use_interaction = '*' in name

    num_cols = features + (CONFOUNDER_NUM if use_confounders else [])
    scaler_m = StandardScaler()
    X_tr = scaler_m.fit_transform(train[num_cols])
    X_vl = scaler_m.transform(val[num_cols])
    X_te = scaler_m.transform(test[num_cols])

    if use_interaction:
        scaler_inter = StandardScaler()
        inter_tr = scaler_inter.fit_transform((train['CVH_score'] * train['BHS']).values.reshape(-1, 1))
        inter_vl = scaler_inter.transform((val['CVH_score']  * val['BHS']).values.reshape(-1, 1))
        inter_te = scaler_inter.transform((test['CVH_score'] * test['BHS']).values.reshape(-1, 1))
        X_tr = np.hstack([X_tr, inter_tr])
        X_vl = np.hstack([X_vl, inter_vl])
        X_te = np.hstack([X_te, inter_te])

    if use_confounders:
        X_tr = np.hstack([X_tr, ohe_sex.transform(train[CONFOUNDER_CAT])])
        X_vl = np.hstack([X_vl, ohe_sex.transform(val[CONFOUNDER_CAT])])
        X_te = np.hstack([X_te, ohe_sex.transform(test[CONFOUNDER_CAT])])

    if use_cluster:
        X_tr = np.hstack([X_tr, ohe_cluster.transform(train[['cluster']])])
        X_vl = np.hstack([X_vl, ohe_cluster.transform(val[['cluster']])])
        X_te = np.hstack([X_te, ohe_cluster.transform(test[['cluster']])])

    model = LogisticRegression(max_iter=1000, random_state=42, class_weight='balanced')
    model.fit(X_tr, y_train)

    results[name] = {
        'train_auc': roc_auc_score(y_train, model.predict_proba(X_tr)[:, 1]),
        'val_auc':   roc_auc_score(y_val,   model.predict_proba(X_vl)[:, 1]),
        'test_auc':  roc_auc_score(y_test,  model.predict_proba(X_te)[:, 1]),
        'model':     model,
        'X_tr':      X_tr,
        'X_vl':      X_vl,
        'X_te':      X_te,
    }


def get_color(name):
    if 'CVH' in name and 'BHS' in name:
        return '#55A868'
    elif 'CVH' in name:
        return '#4C72B0'
    else:
        return '#DD8452'

names      = list(results.keys())
train_aucs = [v['train_auc'] for v in results.values()]
val_aucs   = [v['val_auc']   for v in results.values()]
test_aucs  = [v['test_auc']  for v in results.values()]
colors     = [get_color(n) for n in names]

n = len(names)
x = list(range(n))

fig, ax = plt.subplots(figsize=(11, n * 0.45 + 1.5))
for i, (tr, vl, te, color) in enumerate(zip(train_aucs, val_aucs, test_aucs, colors)):
    ax.barh(i + 0.25, tr, height=0.25, color=color, alpha=0.35)
    ax.barh(i,        vl, height=0.25, color=color, alpha=0.70)
    ax.barh(i - 0.25, te, height=0.25, color=color, alpha=1.00)
    ax.text(max(tr, vl, te) + 0.002, i, f'v:{vl:.3f} t:{te:.3f}', va='center', fontsize=7.5)

ax.axvline(0.5, color='grey', linestyle='--', lw=0.8)
for sep in [2.5]:
    ax.axhline(sep, color='black', linestyle=':', linewidth=0.8)

ax.set_xlabel('ROC-AUC')
ax.set_title('CVD prediction performance', fontweight='bold')
ax.set_xlim(0.40, 1.02)
ax.set_yticks(x)
ax.set_yticklabels(names, fontsize=8.5)
ax.legend(handles=[
    mpatches.Patch(facecolor='#333333', alpha=0.35, label='Train'),
    mpatches.Patch(facecolor='#333333', alpha=0.70, label='Validation'),
    mpatches.Patch(facecolor='#333333', alpha=1.00, label='Test'),
    mpatches.Patch(facecolor='#4C72B0', label='CVH'),
    mpatches.Patch(facecolor='#DD8452', label='BHS'),
    mpatches.Patch(facecolor='#55A868', label='CVH + BHS'),
], fontsize=8)
plt.tight_layout()
save_fig(fig, '08_auc_comparison')


# Logistic regression model
best_features  = ['CVH_score', 'BHS']
ohe_best       = OneHotEncoder(drop='first', sparse_output=False, handle_unknown='ignore')
scaler_best    = StandardScaler()
scaler_inter   = StandardScaler()

ohe_best.fit(train[CONFOUNDER_CAT])
scaler_best.fit(train[best_features + CONFOUNDER_NUM])

interaction_train = (train['CVH_score'] * train['BHS']).values.reshape(-1, 1)
interaction_val   = (val['CVH_score']   * val['BHS']).values.reshape(-1, 1)
interaction_test  = (test['CVH_score']  * test['BHS']).values.reshape(-1, 1)
scaler_inter.fit(interaction_train)


def preprocess_best(df_split, interaction):
    num   = scaler_best.transform(df_split[best_features + CONFOUNDER_NUM])
    cat   = ohe_best.transform(df_split[CONFOUNDER_CAT])
    inter = scaler_inter.transform(interaction)
    return np.hstack([num, cat, inter]).astype(np.float32)


X_train_best = preprocess_best(train, interaction_train)
X_val_best   = preprocess_best(val,   interaction_val)
X_test_best  = preprocess_best(test,  interaction_test)

clf = LogisticRegression(max_iter=1000, random_state=42, class_weight='balanced')
clf.fit(X_train_best, y_train)

ohe_cols     = ohe_best.get_feature_names_out(CONFOUNDER_CAT).tolist()
all_features = best_features + CONFOUNDER_NUM + ohe_cols + ['CVH_score * BHS']


# ROC curves
fig, axes = plt.subplots(1, 3, figsize=(20, 6))
for split_name, ax in zip(['Train', 'Validation', 'Test'], axes):
    if split_name == 'Train':
        y_plot = y_train
    elif split_name == 'Validation':
        y_plot = y_val
    else:
        y_plot = y_test

    for name, res in results.items():
        if split_name == 'Train':
            X_plot, auc = res['X_tr'], res['train_auc']
        elif split_name == 'Validation':
            X_plot, auc = res['X_vl'], res['val_auc']
        else:
            X_plot, auc = res['X_te'], res['test_auc']
        RocCurveDisplay.from_estimator(res['model'], X_plot, y_plot, ax=ax,
                                       name=f'{name} (AUC={auc:.3f})')
    ax.plot([0, 1], [0, 1], 'k--', lw=0.8, label='Random')
    ax.set_title(f'ROC Curves — {split_name}')
    ax.legend(fontsize=6.5, loc='lower right')
plt.suptitle('ROC Curves per model', fontweight='bold')
plt.tight_layout()
save_fig(fig, '09_roc_curves')


# Confusion matrix
n_models = len(results)
fig, axes = plt.subplots(n_models, 3, figsize=(14, n_models * 3.5))
for row_idx, (name, res) in enumerate(results.items()):
    for col_idx, (X, y, split_name) in enumerate([
        (res['X_tr'], y_train, 'Train'),
        (res['X_vl'], y_val,   'Validation'),
        (res['X_te'], y_test,  'Test')
    ]):
        ax = axes[row_idx, col_idx] if n_models > 1 else axes[col_idx]
        ConfusionMatrixDisplay.from_estimator(
            res['model'], X, y, ax=ax,
            display_labels=['No CVD', 'CVD'],
            colorbar=False, cmap='Blues'
        )
        ax.set_title(f'{name}\n{split_name}', fontsize=8)
plt.suptitle('Confusion Matrices per model', fontweight='bold', y=1.01)
plt.tight_layout()
save_fig(fig, '10_confusion_matrices')


# Forest plot
N_BOOT     = 500
boot_coefs = []
for _ in range(N_BOOT):
    X_b, y_b = resample(X_train_best, y_train, random_state=None)
    m = LogisticRegression(max_iter=1000, random_state=None, class_weight='balanced')
    m.fit(X_b, y_b)
    boot_coefs.append(m.coef_[0])

boot_coefs = np.array(boot_coefs)
coef_mean  = clf.coef_[0]
ci_low_log = np.percentile(boot_coefs, 2.5,  axis=0)
ci_hi_log  = np.percentile(boot_coefs, 97.5, axis=0)
p_vals     = np.array([
    2 * min(np.mean(boot_coefs[:, j] >= 0), np.mean(boot_coefs[:, j] <= 0))
    for j in range(len(coef_mean))
])

or_     = np.exp(coef_mean)
ci_low  = np.exp(ci_low_log)
ci_high = np.exp(ci_hi_log)

forest_df = pd.DataFrame({
    'feature': all_features,
    'OR':      or_,
    'CI_low':  ci_low,
    'CI_high': ci_high,
    'p':       p_vals,
}).sort_values('OR', ascending=True).reset_index(drop=True)

fig, ax = plt.subplots(figsize=(9, len(all_features) * 0.8 + 1.5))
for i, row in forest_df.iterrows():
    color = '#2166ac' if row['OR'] < 1 else '#d6604d'
    alpha = 1.0 if row['p'] < 0.05 else 0.4
    ax.plot([row['CI_low'], row['CI_high']], [i, i], color=color, lw=2.0, alpha=alpha)
    ax.scatter(row['OR'], i, color=color, s=70, zorder=3, alpha=alpha)
    sig = ('***' if row['p'] < 0.001 else
           ('**'  if row['p'] < 0.01  else
           ('*'   if row['p'] < 0.05  else 'ns')))
    ax.text(row['CI_high'] + 0.01, i,
            f"OR={row['OR']:.2f} [{row['CI_low']:.2f}–{row['CI_high']:.2f}]  {sig}",
            va='center', fontsize=8.5)
ax.axvline(1.0, color='black', linestyle='--', lw=0.8)
ax.set_yticks(range(len(forest_df)))
ax.set_yticklabels(forest_df['feature'], fontsize=9)
ax.set_xlabel('Odds Ratio (95% CI — bootstrap)')
ax.set_title('Forest Plot — Effect sizes\n(faded = p≥0.05,  blue = protective,  red = risk factor)')
ax.set_xlim(forest_df['CI_low'].min() * 0.85, forest_df['CI_high'].max() * 1.5)
ax.text(0.98, 0.02, '* p<0.05   ** p<0.01   *** p<0.001   ns = not significant',
        transform=ax.transAxes, fontsize=7.5, ha='right', color='grey')
plt.tight_layout()
save_fig(fig, '11_forest_plot')


# Summary table
summary_rows = []
for name, res in results.items():
    for split_name, X, y in [
        ('Train', res['X_tr'], y_train),
        ('Val',   res['X_vl'], y_val),
        ('Test',  res['X_te'], y_test)
    ]:
        y_pred = res['model'].predict(X)
        y_prob = res['model'].predict_proba(X)[:, 1]
        summary_rows.append({
            'Model':     name,
            'Split':     split_name,
            'AUC':       round(roc_auc_score(y, y_prob), 4),
            'Bal. Acc':  round(balanced_accuracy_score(y, y_pred), 4),
            'Precision': round(precision_score(y, y_pred, zero_division=0), 4),
            'Recall':    round(recall_score(y, y_pred, zero_division=0), 4),
            'F1':        round(f1_score(y, y_pred, zero_division=0), 4),
        })

summary_df = pd.DataFrame(summary_rows)
print('\n' + '='*90)
print('RESULTS SUMMARY')
print('='*90)
print(summary_df.to_string(index=False))
print('='*90)
save_table(summary_df.set_index(['Model', 'Split']), 'T3_model_performance_summary')

print('\nEffect sizes — best model (CVH + BHS + interaction + confounders):')
forest_out = forest_df[['feature', 'OR', 'CI_low', 'CI_high', 'p']].round(4)
print(forest_out.to_string(index=False))
save_table(forest_out.set_index('feature'), 'T4_forest_plot_effect_sizes')


# Save clustered datasets
train.to_csv(os.path.join(TABLE_DIR, 'clustered_data_train.csv'), index=False)
val.to_csv(os.path.join(TABLE_DIR,   'clustered_data_val.csv'),   index=False)
test.to_csv(os.path.join(TABLE_DIR,  'clustered_data_test.csv'),  index=False)
print('\nSaved: clustered_data_train/val/test.csv')

# Save GMM model and scaler
with open(os.path.join(MODEL_DIR, 'gmm_model.pkl'), 'wb') as f:
    pickle.dump(gmm, f)
with open(os.path.join(MODEL_DIR, 'gmm_scaler.pkl'), 'wb') as f:
    pickle.dump(scaler, f)
print('Saved: gmm_model.pkl, gmm_scaler.pkl')

# Save cluster remap
with open(os.path.join(MODEL_DIR, 'gmm_remap.json'), 'w') as f:
    json.dump({str(k): int(v) for k, v in remap.items()}, f, indent=2)
print('Saved: gmm_remap.json')

# Save best_k
with open(os.path.join(MODEL_DIR, 'gmm_best_k.json'), 'w') as f:
    json.dump({'best_k': best_k}, f, indent=2)
print(f'Saved: gmm_best_k.json (K={best_k})')

# Save cluster stats
cluster_stats = train.groupby('cluster').agg(
    n=('cvd', 'count'),
    cvd_rate=('cvd', 'mean'),
    cvh_mean=('CVH_score', 'mean'),
    bhs_mean=('BHS', 'mean'),
).round(4)
cluster_stats.to_csv(os.path.join(TABLE_DIR, 'T5_gmm_cluster_stats.csv'))
print('Saved: T5_gmm_cluster_stats.csv')

print(f'\nAll outputs saved to:')
print(f'  Plots:  {PDF_DIR}/')
print(f'  Tables: {TABLE_DIR}/')
print(f'  Models: {MODEL_DIR}/')
