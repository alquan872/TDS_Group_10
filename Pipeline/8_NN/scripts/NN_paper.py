# Paper MLP — fixed architecture from NeuralCVD (256→128→100, SELU)
# Trains with early stopping, saves predictions and model for comparison script

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
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.metrics import roc_auc_score, RocCurveDisplay
import json
import pickle

# directories
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR   = os.path.join(SCRIPT_DIR, '..', '..', '2_Imputation', 'outputs')
OUTPUT_DIR = os.path.join(SCRIPT_DIR, '..', 'outputs')
PLOT_DIR   = os.path.join(OUTPUT_DIR, 'plots_paper')
TABLE_DIR  = os.path.join(OUTPUT_DIR, 'tables_paper')
MODEL_DIR  = os.path.join(OUTPUT_DIR, 'models_paper')

for d in [PLOT_DIR, TABLE_DIR, MODEL_DIR]:
    os.makedirs(d, exist_ok=True)

print(f"Data dir:   {DATA_DIR}")
print(f"Output dir: {OUTPUT_DIR}")

# load data
train = pd.read_csv(os.path.join(DATA_DIR, 'ukb_train_imputed.csv'))
val   = pd.read_csv(os.path.join(DATA_DIR, 'ukb_val_imputed.csv'))
test  = pd.read_csv(os.path.join(DATA_DIR, 'ukb_test_imputed.csv'))

print(f"Train: {train.shape}, Val: {val.shape}, Test: {test.shape}")

# features
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

# preprocessing
ohe_paper    = OneHotEncoder(drop='first', sparse_output=False, handle_unknown='ignore')
scaler_paper = StandardScaler()

ohe_paper.fit(train[CONFOUNDER_CAT])
all_num_cols = ALL_FEATURES + CONFOUNDER_NUM

X_train_num = scaler_paper.fit_transform(train[all_num_cols])
X_val_num   = scaler_paper.transform(val[all_num_cols])
X_test_num  = scaler_paper.transform(test[all_num_cols])

X_train_cat = ohe_paper.transform(train[CONFOUNDER_CAT])
X_val_cat   = ohe_paper.transform(val[CONFOUNDER_CAT])
X_test_cat  = ohe_paper.transform(test[CONFOUNDER_CAT])

X_train_mlp = np.hstack([X_train_num, X_train_cat]).astype(np.float32)
X_val_mlp   = np.hstack([X_val_num,   X_val_cat  ]).astype(np.float32)
X_test_mlp  = np.hstack([X_test_num,  X_test_cat ]).astype(np.float32)

y_train_mlp = train['cvd'].astype(np.float32).values
y_val_mlp   = val  ['cvd'].astype(np.float32).values
y_test_mlp  = test ['cvd'].astype(np.float32).values

device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
X_tr_t = torch.tensor(X_train_mlp)
y_tr_t = torch.tensor(y_train_mlp).unsqueeze(1)
X_vl_t = torch.tensor(X_val_mlp)
X_te_t = torch.tensor(X_test_mlp)

input_dim = X_train_mlp.shape[1]
print(f"Input dim: {input_dim} | Device: {device}")

# class imbalance — weight positive class
pos_weight = torch.tensor(
    [(y_train_mlp == 0).sum() / (y_train_mlp == 1).sum()],
    dtype=torch.float32
).to(device)
criterion = nn.BCEWithLogitsLoss(pos_weight=pos_weight)

dataset_tr = TensorDataset(X_tr_t.to(device), y_tr_t.to(device))


# paper model — NeuralCVD architecture

class MLPPaper(nn.Module):
    def __init__(self, input_dim):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(input_dim, 256), nn.SELU(),
            nn.Linear(256, 128),       nn.SELU(),
            nn.Linear(128, 100),       nn.SELU(),
            nn.Linear(100, 1)
        )

    def forward(self, x):
        return self.net(x)


paper_model = MLPPaper(input_dim).to(device)
optimizer   = torch.optim.Adam(paper_model.parameters(), lr=1e-3, weight_decay=1e-4)
dataloader  = DataLoader(dataset_tr, batch_size=256, shuffle=True)

best_auc_paper = 0
best_state     = None
no_improve     = 0

t0_paper = time.time()

for epoch in range(200):
    paper_model.train()
    for X_batch, y_batch in dataloader:
        optimizer.zero_grad()
        criterion(paper_model(X_batch), y_batch).backward()
        optimizer.step()

    paper_model.eval()
    with torch.no_grad():
        probs_vl = torch.sigmoid(paper_model(X_vl_t.to(device))).cpu().numpy().flatten()
        auc_vl   = roc_auc_score(y_val_mlp, probs_vl)

    if auc_vl > best_auc_paper:
        best_auc_paper = auc_vl
        best_state     = {k: v.clone() for k, v in paper_model.state_dict().items()}
        no_improve     = 0
    else:
        no_improve += 1
        if no_improve >= 15:
            print(f"  Early stopping at epoch {epoch}")
            break

t1_paper   = time.time()
time_paper = t1_paper - t0_paper

paper_model.load_state_dict(best_state)
paper_model.eval()

# evaluation
with torch.no_grad():
    probs_tr_paper = torch.sigmoid(paper_model(X_tr_t.to(device))).cpu().numpy().flatten()
    probs_vl_paper = torch.sigmoid(paper_model(X_vl_t.to(device))).cpu().numpy().flatten()
    probs_te_paper = torch.sigmoid(paper_model(X_te_t.to(device))).cpu().numpy().flatten()

auc_tr_paper = roc_auc_score(y_train_mlp, probs_tr_paper)
auc_vl_paper = roc_auc_score(y_val_mlp,   probs_vl_paper)
auc_te_paper = roc_auc_score(y_test_mlp,  probs_te_paper)

print(f"\nPaper MLP — Train AUC: {auc_tr_paper:.4f} | Val AUC: {auc_vl_paper:.4f} | "
      f"Test AUC: {auc_te_paper:.4f} | Time: {time_paper:.1f}s")

# save predictions
pd.DataFrame({
    'observed':              y_test_mlp,
    'predicted_probability': probs_te_paper,
}).to_csv(os.path.join(TABLE_DIR, 'mlp_paper_test_predictions.csv'), index=False)

pd.DataFrame({
    'observed':              y_val_mlp,
    'predicted_probability': probs_vl_paper,
}).to_csv(os.path.join(TABLE_DIR, 'mlp_paper_val_predictions.csv'), index=False)

# save summary results
pd.DataFrame([{
    'model':                 'MLP_Paper',
    'auc_train':             round(auc_tr_paper, 4),
    'auc_val':               round(auc_vl_paper, 4),
    'auc_test':              round(auc_te_paper, 4),
    'training_time_seconds': round(time_paper, 1),
    'architecture':          '256→128→100',
    'activation':            'SELU',
    'lr':                    1e-3,
    'weight_decay':          1e-4,
    'batch_size':            256,
}]).to_csv(os.path.join(TABLE_DIR, 'mlp_paper_results.csv'), index=False)

# save model
torch.save(paper_model.state_dict(), os.path.join(MODEL_DIR, 'mlp_paper_state_dict.pt'))
with open(os.path.join(MODEL_DIR, 'mlp_paper_architecture.json'), 'w') as f:
    json.dump({'input_dim': input_dim, 'hidden_dims': [256, 128, 100], 'activation': 'SELU'}, f, indent=2)

with open(os.path.join(MODEL_DIR, 'mlp_paper_scaler.pkl'), 'wb') as f:
    pickle.dump(scaler_paper, f)
with open(os.path.join(MODEL_DIR, 'mlp_paper_ohe.pkl'), 'wb') as f:
    pickle.dump(ohe_paper, f)

# ROC curve
fig, ax = plt.subplots(figsize=(7, 6))
for probs, y, label in [
    (probs_tr_paper, y_train_mlp, f'Train (AUC={auc_tr_paper:.3f})'),
    (probs_vl_paper, y_val_mlp,   f'Val   (AUC={auc_vl_paper:.3f})'),
    (probs_te_paper, y_test_mlp,  f'Test  (AUC={auc_te_paper:.3f})'),
]:
    RocCurveDisplay.from_predictions(y, probs, name=label, ax=ax)
ax.plot([0, 1], [0, 1], 'k--', lw=0.8)
ax.set_title('ROC Curve — Paper MLP')
plt.tight_layout()
fig.savefig(os.path.join(PLOT_DIR, 'mlp_paper_roc_curve.png'), dpi=150, bbox_inches='tight')
fig.savefig(os.path.join(PLOT_DIR, 'mlp_paper_roc_curve.pdf'),           bbox_inches='tight')
plt.close(fig)
print("Saved: mlp_paper_roc_curve")

print(f'\nAll outputs saved to: {OUTPUT_DIR}')
