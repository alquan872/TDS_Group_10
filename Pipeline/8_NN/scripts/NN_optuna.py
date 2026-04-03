import matplotlib
matplotlib.use('Agg')
import os
import time
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import torch
import torch.nn as nn
from torch.utils.data import TensorDataset, DataLoader
import optuna
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.metrics import roc_auc_score, RocCurveDisplay
import json
import pickle

# DIRECTORIES

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR   = os.path.join(SCRIPT_DIR, '..', '..', '2_Imputation', 'outputs')
OUTPUT_DIR = os.path.join(SCRIPT_DIR, '..', 'outputs')
PLOT_DIR   = os.path.join(OUTPUT_DIR, 'plots_optuna')
TABLE_DIR  = os.path.join(OUTPUT_DIR, 'tables_optuna')
MODEL_DIR  = os.path.join(OUTPUT_DIR, 'models_optuna')
LOG_DIR    = os.path.join(OUTPUT_DIR, 'logs_optuna')

for d in [PLOT_DIR, TABLE_DIR, MODEL_DIR, LOG_DIR]:
    os.makedirs(d, exist_ok=True)

print(f"Data dir:   {DATA_DIR}")
print(f"Output dir: {OUTPUT_DIR}")

# LOAD DATA

train = pd.read_csv(os.path.join(DATA_DIR, 'ukb_train_imputed.csv'))
val   = pd.read_csv(os.path.join(DATA_DIR, 'ukb_val_imputed.csv'))
test  = pd.read_csv(os.path.join(DATA_DIR, 'ukb_test_imputed.csv'))

print(f"Train: {train.shape}, Val: {val.shape}, Test: {test.shape}")

# FEATURES

CVH_FEATURES = [
    'DASH_score', 'MET_total', 'pack_year_index', 'bmi',
    'biochem_cholesterol', 'biochem_hdl',
    'biochem_hba1c', 'biochem_glucose',
    'systolic_bp', 'diastolic_bp'
]

BHS_FEATURES = [
    'biochem_hba1c', 'biochem_hdl', 'biochem_ldl_direct', 'biochem_triglycerides',
    'systolic_bp', 'diastolic_bp', 'cardiac_pulse_rate',
    'biochem_crp', 'igf1',
    'alanine_aminotransferase', 'aspartate_aminotransferase', 'gamma_glutamyltransferase',
    'creatinine'
]

ALL_FEATURES   = list(dict.fromkeys(CVH_FEATURES + BHS_FEATURES))
CONFOUNDER_NUM = ['age_at_recruitment']
CONFOUNDER_CAT = ['sex']

# PREPROCESSING

ohe_mlp    = OneHotEncoder(drop='first', sparse_output=False, handle_unknown='ignore')
scaler_mlp = StandardScaler()

ohe_mlp.fit(train[CONFOUNDER_CAT])
all_num_cols = ALL_FEATURES + CONFOUNDER_NUM

X_train_num = scaler_mlp.fit_transform(train[all_num_cols])
X_val_num   = scaler_mlp.transform(val[all_num_cols])
X_test_num  = scaler_mlp.transform(test[all_num_cols])

X_train_cat = ohe_mlp.transform(train[CONFOUNDER_CAT])
X_val_cat   = ohe_mlp.transform(val[CONFOUNDER_CAT])
X_test_cat  = ohe_mlp.transform(test[CONFOUNDER_CAT])

X_train_mlp = np.hstack([X_train_num, X_train_cat]).astype(np.float32)
X_val_mlp   = np.hstack([X_val_num,   X_val_cat]).astype(np.float32)
X_test_mlp  = np.hstack([X_test_num,  X_test_cat]).astype(np.float32)

y_train_mlp = train['cvd'].astype(np.float32).values
y_val_mlp   = val['cvd'].astype(np.float32).values
y_test_mlp  = test['cvd'].astype(np.float32).values

device  = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
X_tr_t  = torch.tensor(X_train_mlp)
y_tr_t  = torch.tensor(y_train_mlp).unsqueeze(1)
X_vl_t  = torch.tensor(X_val_mlp)
y_vl_t  = torch.tensor(y_val_mlp).unsqueeze(1)
X_te_t  = torch.tensor(X_test_mlp)

print(f"Input dim: {X_train_mlp.shape[1]}")
print(f"Device: {device}")

# MODEL

class MLP(nn.Module):
    def __init__(self, input_dim, hidden_dims, dropout, activation):
        super().__init__()
        act_fn = {'relu': nn.ReLU, 'tanh': nn.Tanh, 'elu': nn.ELU}[activation]
        layers = []
        in_dim = input_dim
        for h in hidden_dims:
            layers += [nn.Linear(in_dim, h), act_fn(), nn.Dropout(dropout)]
            in_dim = h
        layers += [nn.Linear(in_dim, 1), nn.Identity()]
        self.net = nn.Sequential(*layers)

    def forward(self, x):
        return self.net(x)

pos_weight = torch.tensor(
    [(y_train_mlp == 0).sum() / (y_train_mlp == 1).sum()],
    dtype=torch.float32
).to(device)
criterion  = nn.BCEWithLogitsLoss(pos_weight=pos_weight)
input_dim  = X_train_mlp.shape[1]

dataset_tr = TensorDataset(X_tr_t.to(device), y_tr_t.to(device))

# OPTUNA

def objective(trial):
    n_layers     = trial.suggest_int('n_layers', 1, 4)
    dropout      = trial.suggest_float('dropout', 0.0, 0.5)
    lr           = trial.suggest_float('lr', 1e-4, 1e-2, log=True)
    weight_decay = trial.suggest_float('weight_decay', 1e-5, 1e-2, log=True)
    batch_size   = trial.suggest_categorical('batch_size', [64, 128, 256, 512])
    activation   = trial.suggest_categorical('activation', ['relu', 'tanh', 'elu'])
    hidden_dims  = [trial.suggest_int(f'n_units_l{i}', 16, 256) for i in range(n_layers)]

    model      = MLP(input_dim, hidden_dims, dropout, activation).to(device)
    optimizer  = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=weight_decay)
    dataloader = DataLoader(dataset_tr, batch_size=batch_size, shuffle=True)

    best_auc   = 0
    no_improve = 0

    for epoch in range(100):
        model.train()
        for X_batch, y_batch in dataloader:
            optimizer.zero_grad()
            criterion(model(X_batch), y_batch).backward()
            optimizer.step()

        model.eval()
        with torch.no_grad():
            probs = torch.sigmoid(model(X_vl_t.to(device))).cpu().numpy().flatten()
            auc   = roc_auc_score(y_val_mlp, probs)

        if auc > best_auc:
            best_auc   = auc
            no_improve = 0
        else:
            no_improve += 1
            if no_improve >= 10:
                break

        trial.report(auc, epoch)
        if trial.should_prune():
            raise optuna.exceptions.TrialPruned()

    return best_auc

sampler = optuna.samplers.TPESampler(seed=42)
pruner  = optuna.pruners.MedianPruner(n_startup_trials=5, n_warmup_steps=10)
study   = optuna.create_study(direction='maximize', sampler=sampler, pruner=pruner)
optuna.logging.set_verbosity(optuna.logging.WARNING)

t0_optuna = time.time()
study.optimize(objective, n_trials=100, show_progress_bar=True)

# TRAINING WITH BEST PARAMS

best        = study.best_params
hidden_opt  = [best[f'n_units_l{i}'] for i in range(best['n_layers'])]
mlp_final   = MLP(input_dim, hidden_opt, best['dropout'], best['activation']).to(device)
optimizer   = torch.optim.Adam(mlp_final.parameters(), lr=best['lr'], weight_decay=best['weight_decay'])
dataloader  = DataLoader(dataset_tr, batch_size=best['batch_size'], shuffle=True)

best_auc_opt  = 0
best_state    = None
no_improve    = 0

for epoch in range(200):
    mlp_final.train()
    for X_batch, y_batch in dataloader:
        optimizer.zero_grad()
        criterion(mlp_final(X_batch), y_batch).backward()
        optimizer.step()

    mlp_final.eval()
    with torch.no_grad():
        probs_vl = torch.sigmoid(mlp_final(X_vl_t.to(device))).cpu().numpy().flatten()
        auc_vl   = roc_auc_score(y_val_mlp, probs_vl)

    if auc_vl > best_auc_opt:
        best_auc_opt = auc_vl
        best_state   = {k: v.clone() for k, v in mlp_final.state_dict().items()}
        no_improve   = 0
    else:
        no_improve += 1
        if no_improve >= 15:
            print(f'  Optuna final — early stopping epoch {epoch}')
            break

t1_optuna   = time.time()
time_optuna = t1_optuna - t0_optuna

mlp_final.load_state_dict(best_state)
mlp_final.eval()

# EVALUATION

with torch.no_grad():
    probs_tr_opt = torch.sigmoid(mlp_final(X_tr_t.to(device))).cpu().numpy().flatten()
    probs_vl_opt = torch.sigmoid(mlp_final(X_vl_t.to(device))).cpu().numpy().flatten()
    probs_te_opt = torch.sigmoid(mlp_final(X_te_t.to(device))).cpu().numpy().flatten()

auc_tr_opt = roc_auc_score(y_train_mlp, probs_tr_opt)
auc_vl_opt = roc_auc_score(y_val_mlp,   probs_vl_opt)
auc_te_opt = roc_auc_score(y_test_mlp,  probs_te_opt)

print(f'\nOptuna MLP — Train AUC: {auc_tr_opt:.4f} | Val AUC: {auc_vl_opt:.4f} | Test AUC: {auc_te_opt:.4f}')
print(f'Best architecture: {input_dim} → {" → ".join(str(h) for h in hidden_opt)} → 1')
print(f'Best params: activation={best["activation"]}, dropout={best["dropout"]:.2f}, lr={best["lr"]:.5f}')
print(f'Total time: {time_optuna:.1f}s')

# SAVE RESULTS

# test predictions
pd.DataFrame({
    'observed':              y_test_mlp,
    'predicted_probability': probs_te_opt
}).to_csv(os.path.join(TABLE_DIR, 'mlp_optuna_test_predictions.csv'), index=False)

# val predictions
pd.DataFrame({
    'observed':              y_val_mlp,
    'predicted_probability': probs_vl_opt
}).to_csv(os.path.join(TABLE_DIR, 'mlp_optuna_val_predictions.csv'), index=False)

# AUC results
pd.DataFrame([{
    'model':                 'MLP_Optuna',
    'auc_train':             round(auc_tr_opt, 4),
    'auc_val':               round(auc_vl_opt, 4),
    'auc_test':              round(auc_te_opt, 4),
    'training_time_seconds': round(time_optuna, 1),
    'n_layers':              best['n_layers'],
    'hidden_dims':           str(hidden_opt),
    'activation':            best['activation'],
    'dropout':               round(best['dropout'], 4),
    'lr':                    round(best['lr'], 6),
    'weight_decay':          round(best['weight_decay'], 6),
    'batch_size':            best['batch_size'],
}]).to_csv(os.path.join(TABLE_DIR, 'mlp_optuna_results.csv'), index=False)

# best hyperparameters
with open(os.path.join(TABLE_DIR, 'mlp_optuna_best_params.json'), 'w') as f:
    json.dump(best, f, indent=2)

# optuna trials
study.trials_dataframe().to_csv(os.path.join(TABLE_DIR, 'mlp_optuna_trials.csv'), index=False)

# model
torch.save(mlp_final.state_dict(), os.path.join(MODEL_DIR, 'mlp_optuna_state_dict.pt'))
with open(os.path.join(MODEL_DIR, 'mlp_optuna_architecture.json'), 'w') as f:
    json.dump({
        'input_dim':   input_dim,
        'hidden_dims': hidden_opt,
        'dropout':     best['dropout'],
        'activation':  best['activation']
    }, f, indent=2)

with open(os.path.join(MODEL_DIR, 'mlp_optuna_scaler.pkl'), 'wb') as f:
    pickle.dump(scaler_mlp, f)
with open(os.path.join(MODEL_DIR, 'mlp_optuna_ohe.pkl'), 'wb') as f:
    pickle.dump(ohe_mlp, f)

# ROC curve
fig, ax = plt.subplots(figsize=(7, 6))
for probs, y, label in [
    (probs_tr_opt, y_train_mlp, f'Train (AUC={auc_tr_opt:.3f})'),
    (probs_vl_opt, y_val_mlp,   f'Val   (AUC={auc_vl_opt:.3f})'),
    (probs_te_opt, y_test_mlp,  f'Test  (AUC={auc_te_opt:.3f})')
]:
    RocCurveDisplay.from_predictions(y, probs, name=label, ax=ax)
ax.plot([0, 1], [0, 1], 'k--', lw=0.8)
ax.set_title('ROC Curve — Optuna MLP')
plt.tight_layout()
fig.savefig(os.path.join(PLOT_DIR, 'mlp_optuna_roc_curve.png'), dpi=150, bbox_inches='tight')
fig.savefig(os.path.join(PLOT_DIR, 'mlp_optuna_roc_curve.pdf'),           bbox_inches='tight')
plt.close(fig)

# Optuna optimization history
fig, ax = plt.subplots(figsize=(8, 4))
trials_df = study.trials_dataframe()
trials_df = trials_df[trials_df['state'] == 'COMPLETE']
ax.plot(trials_df['number'], trials_df['value'], 'o-', alpha=0.5, markersize=3)
ax.axhline(study.best_value, color='red', linestyle='--', label=f'Best={study.best_value:.4f}')
ax.set(xlabel='Trial', ylabel='Val AUC', title='Optuna optimization history')
ax.legend()
plt.tight_layout()
fig.savefig(os.path.join(PLOT_DIR, 'mlp_optuna_optimization_history.png'), dpi=150, bbox_inches='tight')
fig.savefig(os.path.join(PLOT_DIR, 'mlp_optuna_optimization_history.pdf'),           bbox_inches='tight')
plt.close(fig)

print(f'\nAll outputs saved to: {OUTPUT_DIR}')
