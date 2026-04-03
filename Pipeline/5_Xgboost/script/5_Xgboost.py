import copy
import json
import time
import os
from datetime import datetime

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import shap
from sklearn.compose import ColumnTransformer
from sklearn.inspection import permutation_importance
from sklearn.metrics import (
    ConfusionMatrixDisplay,
    auc,
    confusion_matrix,
    roc_auc_score,
    roc_curve,
)
from sklearn.model_selection import ParameterGrid
from sklearn.preprocessing import OneHotEncoder, StandardScaler
import xgboost as xgb


print("CUDA_VISIBLE_DEVICES =", os.environ.get("CUDA_VISIBLE_DEVICES"))
print("XGBoost version =", xgb.__version__)
print(xgb.build_info())



# -------------------------------
# Load datasets
# -------------------------------
train = pd.read_csv("../../3_Correlation/outputs/ukb_train_drop_correlation_score.csv")
val   = pd.read_csv("../../3_Correlation/outputs/ukb_val_drop_correlation_score.csv")
test  = pd.read_csv("../../3_Correlation/outputs/ukb_test_drop_correlation_score.csv")

print(train.shape)
print(val.shape)
print(test.shape)

# -------------------------------
# Cast categorical columns
# -------------------------------
categorical_cols = [
    "lung_cancer",
    "liver_cancer",
    "kidney_cancer",
]

for df in [train, val, test]:
    for col in categorical_cols:
        if col in df.columns:
            df[col] = df[col].astype("category")


# -------------------------------
# Preview data (replacement for Jupyter display)
# -------------------------------
print(train.head())



# -------------------------------
# Descriptive statistics
# -------------------------------
print(train.describe(include="all"))

# -------------------------------
# Standardize column names
# -------------------------------
train.columns = train.columns.str.lower()
val.columns   = val.columns.str.lower()
test.columns  = test.columns.str.lower()

# -------------------------------
# Descriptive statistics (after renaming)
# -------------------------------
print(train.describe(include="all"))

# -------------------------------
# Separate target (y) and features (X)
# -------------------------------

# Target variable
train_y = train["cvd"]
val_y   = val["cvd"]
test_y  = test["cvd"]

# Drop identifier columns and target from feature sets
# "bmr", "biochem_cholesterol", "biochem_ldl_direct", "resp_fvc_best",
# "blood_hemoglobin_conc", "blood_reticulocyte_pct", "BHI series",
# and "CVH series" were already removed
cols_to_drop = ["cvd"]

train_X = train.drop(columns=cols_to_drop)
val_X   =val.drop(columns=cols_to_drop)
test_X  = test.drop(columns=cols_to_drop)

# Check shapes
print("Feature matrix shapes:")
print("Train X:", train_X.shape)
print("Val X:", val_X.shape)
print("Test X:", test_X.shape)

print("Target shapes:")
print("Train y:", train_y.shape)
print("Val y:", val_y.shape)
print("Test y:", test_y.shape)

# -------------------------------
# Feature info
# -------------------------------
train_X.info()


# -------------------------------
# Detect variable types
# -------------------------------

# Train
numeric_cols_train = train_X.select_dtypes(include=["int64", "float64"]).columns.tolist()
cat_cols_train     = train_X.select_dtypes(include=["object", "category", "string"]).columns.tolist()

print("Train numeric columns:")
print(numeric_cols_train)
print("Train categorical columns:")
print(cat_cols_train)

# Validation
numeric_cols_val = val_X.select_dtypes(include=["int64", "float64"]).columns.tolist()
cat_cols_val     = val_X.select_dtypes(include=["object", "category", "string"]).columns.tolist()

print("Validation numeric columns:")
print(numeric_cols_val)
print("Validation categorical columns:")
print(cat_cols_val)

# Test
numeric_cols_test = test_X.select_dtypes(include=["int64", "float64"]).columns.tolist()
cat_cols_test     = test_X.select_dtypes(include=["object", "category", "string"]).columns.tolist()

print("Test numeric columns:")
print(numeric_cols_test)
print("Test categorical columns:")
print(cat_cols_test)


# -------------------------------
# Column transformer for preprocessing
# -------------------------------

# Define column types (based on TRAIN only)
numeric_cols = train_X.select_dtypes(include=["number"]).columns.tolist()
cat_cols = train_X.select_dtypes(exclude=["number"]).columns.tolist()

print("Numeric cols:", len(numeric_cols))
print("Categorical cols:", len(cat_cols))

# Build column transformer
column_transformer = ColumnTransformer(
    transformers=[
        ("num", StandardScaler(), numeric_cols),
        (
            "cat",
            OneHotEncoder(sparse_output=False, handle_unknown="ignore"),
            cat_cols,
        ),
    ],
    remainder="drop",
    verbose_feature_names_out=False,
)

# Fit on training data and transform all splits
train_X_processed = column_transformer.fit_transform(train_X)
val_X_processed   = column_transformer.transform(val_X)
test_X_processed  = column_transformer.transform(test_X)

print("Processed feature shapes:")
print("Train:", train_X_processed.shape)
print("Validation:", val_X_processed.shape)
print("Test:", test_X_processed.shape)


# -------------------------------
# Check class imbalance in target (CVD)
# -------------------------------

def check_imbalance(y, name):
    print(f"===== {name} class distribution =====")
    counts = y.value_counts()
    props  = y.value_counts(normalize=True)

    print("Counts:")
    print(counts)

    print("Proportions:")
    print(props)

    if len(counts) == 2:
        ratio = counts.max() / counts.min()
        print("Imbalance ratio (majority/minority):", ratio)

    pos_rate = y.mean()
    print("Positive class rate (CVD=1):", pos_rate)


check_imbalance(train_y, "Train")



# -------------------------------
# Compute scale_pos_weight for XGBoost
# -------------------------------

# For imbalanced binary outcome:
# scale_pos_weight = number of negatives / number of positives
neg_count = (train_y == 0).sum()
pos_count = (train_y == 1).sum()
scale_pos_weight = neg_count / pos_count

print("scale_pos_weight:", scale_pos_weight)


# -------------------------------
# Gridsearch
# -------------------------------

xgb_param_grid = {
    "n_estimators": [200, 225, 250, 275, 300, 325, 350],
    "learning_rate": [0.015, 0.02, 0.03, 0.04, 0.05],
    "max_depth": [2, 3, 4],
    "min_child_weight": [1, 2, 3, 4],
    "subsample": [0.7, 0.75, 0.8, 0.85],
    "colsample_bytree": [0.8, 0.9, 1.0],
    "reg_lambda": [5, 10, 15, 20]
}


param_list = list(ParameterGrid(xgb_param_grid))
print(f"Total combinations: {len(param_list)}")

best_auc = -np.inf
best_model = None
best_params = None
results = []

start_time = time.time()

for i, params in enumerate(param_list, 1):

    iter_start = time.time()

    model = xgb.XGBClassifier(
        **params,
        random_state=42,
        eval_metric="logloss",
        tree_method="hist",
        device="cuda",
        n_jobs=1
    )

    model.fit(train_X_processed, train_y)

    val_pred = model.predict_proba(val_X_processed)[:, 1]
    val_auc = roc_auc_score(val_y, val_pred)

    # ---- save result ----
    results.append({
        "combination": i,
        **params,
        "val_auc": val_auc
    })

    # ---- check best ----
    is_best = False
    if val_auc > best_auc:
        best_auc = val_auc
        best_model = copy.deepcopy(model)
        best_params = params
        is_best = True

    # ---- timing ----
    iter_time = time.time() - iter_start
    elapsed_time = time.time() - start_time
    avg_time = elapsed_time / i
    remaining_time = avg_time * (len(param_list) - i)

    # ---- current system time ----
    current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # ---- print condition ----
    if is_best or i % 50 == 0:
        print(f"[{i}/{len(param_list)}]  |  Time: {current_time}")
        print(f"AUC: {val_auc:.5f} {'(BEST)' if is_best else ''}")
        print(f"Params: {params}")
        print(f"Iter time: {iter_time:.2f}s")
        print(f"Elapsed: {elapsed_time/60:.2f} min")
        print(f"ETA: {remaining_time/60:.2f} min")
        print("-" * 50)

print("===== FINAL BEST =====")
print(f"Best AUC: {best_auc:.5f}")
print(f"Best Params: {best_params}")

# create directory if not exists
save_dir = "../outputs"
os.makedirs(save_dir, exist_ok=True)

# ---- save results ----
results_df = pd.DataFrame(results)
results_df.to_csv(os.path.join(save_dir, "xgb_grid_search_results.csv"), index=False)

# ---- save best params ----
with open(os.path.join(save_dir, "xgb_best_params.json"), "w") as f:
    json.dump(best_params, f, indent=4)

# ---- save best model ----
best_model.save_model(os.path.join(save_dir, "best_xgb_model.json"))


# ------------------------------
# Load and inspect grid search results
# ------------------------------

# ---- load results ----
results_df = pd.read_csv("../outputs/xgb_grid_search_results.csv")

# ---- sort by performance ----
results_df = results_df.sort_values("val_auc", ascending=False)

# ---- preview ----
print("===== Loaded Grid Search Results =====")
print("Total rows:", results_df.shape[0])

print("Top 10 parameter combinations:")
print(results_df.head(10))


# -------------------------------
# Load best parameters
# -------------------------------

with open("../outputs/xgb_best_params.json", "r") as f:
    loaded_params = json.load(f)

print("Loaded best parameters:")
print(loaded_params)


# -------------------------------
# Refit final model using saved parameters
# -------------------------------

# Refit one final model using saved parameters
# Train on train set and evaluate on validation/test sets
final_model = xgb.XGBClassifier(
    objective="binary:logistic",
    eval_metric="logloss",
    random_state=42,
    scale_pos_weight=scale_pos_weight,
    tree_method="hist",
    n_jobs=1,
    **loaded_params
)

final_model.fit(train_X_processed, train_y)
print("Final model retrained using saved parameters.")


# -------------------------------
# Validation performance
# -------------------------------

val_pred = final_model.predict_proba(val_X_processed)[:, 1]
val_auc = roc_auc_score(val_y, val_pred)
print("Validation ROC-AUC (reloaded best params):", val_auc)


# -------------------------------
# Test performance
# -------------------------------

# Test
test_pred = final_model.predict_proba(test_X_processed)[:, 1]
test_auc = roc_auc_score(test_y, test_pred)
print("Test ROC-AUC:", test_auc)


# -------------------------------
# ROC curve
# -------------------------------
fpr_val, tpr_val, _ = roc_curve(val_y, val_pred)
roc_auc_val_curve = auc(fpr_val, tpr_val)

fpr_test, tpr_test, _ = roc_curve(test_y, test_pred)
roc_auc_test_curve = auc(fpr_test, tpr_test)

plt.figure(figsize=(6, 6))
plt.plot(fpr_val, tpr_val, label=f"Validation ROC (AUC = {roc_auc_val_curve:.3f})")
plt.plot(fpr_test, tpr_test, label=f"Test ROC (AUC = {roc_auc_test_curve:.3f})")
plt.plot([0, 1], [0, 1], linestyle="--")
plt.xlabel("False Positive Rate")
plt.ylabel("True Positive Rate")
plt.title("XGBoost ROC Curves")
plt.legend(loc="lower right")
plt.tight_layout()

# Save (PDF)
plt.savefig("../outputs/xgb_roc_curves.pdf", bbox_inches="tight")


# -------------------------------
# Confusion matrix
# -------------------------------
test_pred_class = final_model.predict(test_X_processed)
cm = confusion_matrix(test_y, test_pred_class)

print("Confusion Matrix (Test):")
print(cm)

fig, ax = plt.subplots(figsize=(5, 5))

ConfusionMatrixDisplay(
    confusion_matrix=cm,
    display_labels=["No CVD", "CVD"]
).plot(cmap="Blues", colorbar=False, ax=ax)

ax.set_title("XGBoost - Confusion Matrix (Test)")
plt.tight_layout()

# -------------------------------
# Save figure (PDF)
# -------------------------------
plt.savefig(
    "../outputs/xgb_cm.pdf",
    bbox_inches="tight"
)

# -------------------------------
# Feature numbers
# -------------------------------

df_model1 = pd.read_csv('../../4_Stability_Selection_LASSO/outputs/tables/stable_predictors_model1_all_vars.csv')
df_model2 = pd.read_csv('../../4_Stability_Selection_LASSO/outputs/tables/stable_predictors_model2_no_age_sysbp.csv')

print(df_model1)
print(df_model1.shape)

print(df_model2)
print(df_model2.shape)

def run_analysis(df, model_name):
    os.makedirs("../outputs", exist_ok=True)

    print(f"\n========== Running for {model_name} ==========\n")

    top_n = len(df)
    df_predictors = df["predictor"].tolist()

    # -------------------------------
    # Feature names
    # -------------------------------
    feature_names = pd.Index(column_transformer.get_feature_names_out(), name="feature")
    feature_names_clean = [f.replace("_", " ") for f in feature_names]

    # -------------------------------
    # XGBoost feature importance
    # -------------------------------
    xgb_importance = pd.DataFrame({
        "feature": feature_names,
        "native_importance": final_model.feature_importances_
    })

    xgb_importance_sorted = xgb_importance.sort_values(
        "native_importance", ascending=False
    ).reset_index(drop=True)

    # normalize
    total_importance = xgb_importance_sorted["native_importance"].sum()
    if total_importance > 0:
        xgb_importance_sorted["importance_norm"] = (
            xgb_importance_sorted["native_importance"] / total_importance
        )
    else:
        xgb_importance_sorted["importance_norm"] = 0

    # cumulative
    xgb_importance_sorted["cumulative"] = (
        xgb_importance_sorted["importance_norm"].cumsum()
    )

    # thresholds
    thresholds = [0.5, 0.9, 0.99]
    threshold_ranks = {}

    for t in thresholds:
        if (xgb_importance_sorted["cumulative"] >= t).any():
            rank = (xgb_importance_sorted["cumulative"] >= t).idxmax() + 1
            threshold_ranks[t] = rank
        else:
            threshold_ranks[t] = None

    # -------------------------------
    # Plot cumulative feature importance
    # -------------------------------
    fig, ax = plt.subplots(figsize=(10, 6))
    ax.plot(
        np.arange(1, len(xgb_importance_sorted) + 1),
        xgb_importance_sorted["cumulative"].values
    )

    for t, r in threshold_ranks.items():
        ax.axhline(y=t, linestyle="--")
        if r is not None:
            ax.axvline(x=r, linestyle="--")
            ax.text(r, t, f"{int(t*100)}% (rank={r})")

    ax.set_xlabel("Feature rank")
    ax.set_ylabel("Cumulative importance")
    ax.set_title(f"Cumulative Feature Importance ({model_name})")
    fig.tight_layout()

    fig.savefig(
        f"../outputs/{model_name}_cumulative_importance.pdf",
        bbox_inches="tight"
    )
    plt.close(fig)

    print("Threshold summary:")
    for t, r in threshold_ranks.items():
        if r is not None:
            print(f"{int(t*100)}% importance reached at rank: {r}")
        else:
            print(f"{int(t*100)}% importance not reached")

    # -------------------------------
    # XGBoost importance > 0
    # -------------------------------
    xgb_importance_nonzero = xgb_importance[
        xgb_importance["native_importance"] > 0
    ].copy()

    num_nonzero = xgb_importance_nonzero.shape[0]
    total_features = xgb_importance.shape[0]

    print(f"Number of XGBoost features with importance > 0: {num_nonzero}")
    print(f"Total number of XGBoost features: {total_features}")
    print("XGBoost Native Feature Importances (> 0):")
    print(xgb_importance_nonzero)

    xgb_importance_nonzero_sorted = xgb_importance_nonzero.sort_values(
        "native_importance", ascending=False
    ).reset_index(drop=True)

    print("Ranked XGBoost feature list (importance > 0):")
    print(xgb_importance_nonzero_sorted)

    xgb_importance_nonzero_sorted.to_csv(
        f"../outputs/{model_name}_xgb_importance_nonzero_ranked.csv",
        index=False
    )
    print(f"Saved ranked importance table to: ../outputs/{model_name}_xgb_importance_nonzero_ranked.csv")

    # -------------------------------
    # Plot ALL XGBoost features with importance > 0
    # -------------------------------
    if num_nonzero > 0:
        xgb_importance_plot_all = xgb_importance_nonzero_sorted.copy()
        native_all = xgb_importance_plot_all.iloc[::-1].copy()
        native_all["feature_clean"] = native_all["feature"].str.replace("_", " ", regex=False)

        fig, ax = plt.subplots(figsize=(10, max(6, 0.35 * num_nonzero)))
        ax.barh(
            native_all["feature_clean"],
            native_all["native_importance"]
        )
        ax.set_title(f"XGBoost Feature Importance (> 0) for Train Set ({model_name})")
        ax.set_xlabel("Importance")
        ax.set_ylabel("Feature")
        fig.tight_layout()

        output_path_all = f"../outputs/{model_name}_xgb_feature_importance_nonzero_all.pdf"
        fig.savefig(output_path_all, bbox_inches="tight")
        plt.close(fig)

        print(f"Plot saved to: {output_path_all}")
    else:
        print("No XGBoost features with importance > 0 to plot.")

    # -------------------------------
    # Rank comparison between df and XGBoost importance
    # -------------------------------
    xgb_features_ranked = xgb_importance_nonzero_sorted["feature"].tolist()
    min_len_xgb = min(len(df_predictors), len(xgb_features_ranked))
    print(f"Comparison length for df vs XGBoost (min_len): {min_len_xgb}")

    comparison_rows = []
    for i in range(min_len_xgb):
        df_pred = df_predictors[i]
        xgb_feat = xgb_features_ranked[i]

        comparison_rows.append({
            "rank": i + 1,
            "df_predictor": df_pred,
            "xgb_feature": xgb_feat,
            "same": df_pred == xgb_feat
        })

    comparison_df_xgb = pd.DataFrame(comparison_rows)

    num_same_xgb = comparison_df_xgb["same"].sum() if not comparison_df_xgb.empty else 0
    total_xgb = len(comparison_df_xgb)

    print(comparison_df_xgb)
    print("Number of same predictors at the same rank:", num_same_xgb)
    print("Total compared ranks:", total_xgb)
    print("Match ratio:", round(num_same_xgb / total_xgb, 4) if total_xgb > 0 else np.nan)

    print("Matched at same rank:")
    print(comparison_df_xgb[comparison_df_xgb["same"]]) if total_xgb > 0 else print("None")

    print("Not matched at same rank:")
    print(comparison_df_xgb[~comparison_df_xgb["same"]]) if total_xgb > 0 else print("None")

    common_features_xgb = set(df_predictors).intersection(set(xgb_features_ranked))
    print("Number of common features regardless of rank:", len(common_features_xgb))
    print(sorted(common_features_xgb))

    comparison_df_xgb.to_csv(
        f"../outputs/{model_name}_df_vs_xgb_rank_feature_importance_comparison.csv",
        index=False
    )
    print(f"Saved to: ../outputs/{model_name}_df_vs_xgb_rank_feature_importance_comparison.csv")

    # -------------------------------
    # Plot XGBoost top min_len features
    # -------------------------------
    if min_len_xgb > 0:
        xgb_importance_plot_minlen = xgb_importance_nonzero_sorted.head(min_len_xgb).copy()
        native_minlen = xgb_importance_plot_minlen.iloc[::-1].copy()
        native_minlen["feature_clean"] = native_minlen["feature"].str.replace("_", " ", regex=False)

        fig, ax = plt.subplots(figsize=(10, max(6, 0.35 * min_len_xgb)))
        ax.barh(
            native_minlen["feature_clean"],
            native_minlen["native_importance"]
        )
        ax.set_title(
            f"XGBoost Feature Importance (> 0) - Top {min_len_xgb} Features Matched to df Length ({model_name})"
        )
        ax.set_xlabel("Importance")
        ax.set_ylabel("Feature")
        fig.tight_layout()

        output_path_minlen = f"../outputs/{model_name}_xgb_feature_importance_nonzero_top_minlen_vs_df.pdf"
        fig.savefig(output_path_minlen, bbox_inches="tight")
        plt.close(fig)

        print(f"Plot saved to: {output_path_minlen}")
    else:
        print("No XGBoost top-min_len plot generated because min_len_xgb = 0.")

    # -------------------------------
    # SHAP
    # -------------------------------
    print("Computing SHAP values on test set...")
    shap_explainer = shap.TreeExplainer(final_model)
    shap_values_raw = shap_explainer.shap_values(test_X_processed)

    if isinstance(shap_values_raw, list):
        shap_values = shap_values_raw[1] if len(shap_values_raw) > 1 else shap_values_raw[0]
    elif isinstance(shap_values_raw, np.ndarray) and shap_values_raw.ndim == 3:
        shap_values = shap_values_raw[:, :, 1]
    else:
        shap_values = shap_values_raw

    shap_importance = pd.DataFrame({
        "feature": feature_names,
        "feature_clean": feature_names_clean,
        "shap_mean_abs": np.abs(shap_values).mean(axis=0)
    }).sort_values("shap_mean_abs", ascending=False).reset_index(drop=True)

    shap_importance_nonzero = shap_importance[
        shap_importance["shap_mean_abs"] > 0
    ].copy()

    num_nonzero_shap = shap_importance_nonzero.shape[0]
    total_shap_features = shap_importance.shape[0]

    print(f"Total number of features in SHAP importance: {total_shap_features}")
    print(f"Number of features with SHAP importance > 0: {num_nonzero_shap}")
    print("SHAP importance table (> 0):")
    print(shap_importance_nonzero)

    shap_importance_nonzero_sorted = shap_importance_nonzero.sort_values(
        "shap_mean_abs", ascending=False
    ).reset_index(drop=True)

    print("Ranked SHAP feature list (importance > 0):")
    print(shap_importance_nonzero_sorted)

    shap_importance_nonzero_sorted.to_csv(
        f"../outputs/{model_name}_shap_importance_nonzero_ranked.csv",
        index=False
    )
    print(f"Saved to: ../outputs/{model_name}_shap_importance_nonzero_ranked.csv")

    # -------------------------------
    # SHAP zero-rank / top_n summary
    # -------------------------------
    n_plot = min(top_n, num_nonzero_shap)
    zero_mask = shap_importance["shap_mean_abs"] == 0

    if zero_mask.any():
        first_zero_idx = zero_mask.idxmax()
        zero_rank = first_zero_idx + 1
        print(f"First feature with SHAP importance = 0 is at rank: {zero_rank}")
        print("Feature name:", shap_importance.loc[first_zero_idx, "feature"])
    else:
        print("No SHAP importance exactly equal to 0")

    print(f"Total number of features in SHAP importance: {shap_importance.shape[0]}")
    print(f"Number of features with SHAP importance > 0: {num_nonzero_shap}")
    print(f"Number of features actually plotted: {n_plot}")
    print(f"Top {n_plot} SHAP Importances:")
    print(shap_importance.head(n_plot))

    # -----------------------------
    # Save SHAP bar plot
    # -----------------------------
    if n_plot > 0:
        plt.figure(figsize=(10, 8))
        shap.summary_plot(
            shap_values,
            test_X_processed,
            feature_names=feature_names_clean,
            plot_type="bar",
            max_display=n_plot,
            show=False
        )
        plt.gcf().set_size_inches(12, 10)
        plt.title(f"SHAP Feature Importance (Test set) - Top {n_plot} variables ({model_name})")
        plt.tight_layout()
        plt.savefig(
            f"../outputs/{model_name}_shap_importance_bar_topn.pdf",
            bbox_inches="tight"
        )
        plt.close()

        # -----------------------------
        # Save SHAP summary plot
        # -----------------------------
        plt.figure(figsize=(10, 8))
        shap.summary_plot(
            shap_values,
            test_X_processed,
            feature_names=feature_names_clean,
            max_display=n_plot,
            show=False
        )
        plt.gcf().set_size_inches(12, 10)
        plt.title(f"SHAP Summary Plot (Test set) - Top {n_plot} variables ({model_name})")
        plt.tight_layout()
        plt.savefig(
            f"../outputs/{model_name}_shap_summary_topn.pdf",
            bbox_inches="tight"
        )
        plt.close()
    else:
        print("No SHAP top-n plots generated because n_plot = 0.")

    # -------------------------------
    # Plot SHAP absolute importance > 0 only
    # -------------------------------
    n_plot_nonzero_shap = shap_importance_nonzero_sorted.shape[0]
    print(f"Number of SHAP features plotted (> 0): {n_plot_nonzero_shap}")

    if n_plot_nonzero_shap > 0:
        shap_plot_all = shap_importance_nonzero_sorted.copy()
        shap_plot_all_rev = shap_plot_all.iloc[::-1].copy()

        fig, ax = plt.subplots(figsize=(10, max(6, 0.35 * n_plot_nonzero_shap)))
        ax.barh(
            shap_plot_all_rev["feature_clean"],
            shap_plot_all_rev["shap_mean_abs"]
        )
        ax.set_title(f"SHAP Mean Absolute Importance (> 0) for Test Set ({model_name})")
        ax.set_xlabel("Mean |SHAP value|")
        ax.set_ylabel("Feature")
        fig.tight_layout()

        output_path_shap_nonzero = f"../outputs/{model_name}_shap_importance_nonzero_all.pdf"
        fig.savefig(output_path_shap_nonzero, bbox_inches="tight")
        plt.close(fig)

        print(f"Bar plot saved to: {output_path_shap_nonzero}")
    else:
        print("No SHAP features with importance > 0 to plot.")

    # -------------------------------
    # Save SHAP beeswarm plot (> 0 features only)
    # -------------------------------
    if n_plot_nonzero_shap > 0:
        nonzero_features = shap_importance_nonzero_sorted["feature"].tolist()
        nonzero_feature_clean = shap_importance_nonzero_sorted["feature_clean"].tolist()

        nonzero_idx = [feature_names.get_loc(f) for f in nonzero_features]

        shap_values_nonzero = shap_values[:, nonzero_idx]
        test_X_processed_nonzero = test_X_processed[:, nonzero_idx]

        plt.figure(figsize=(10, max(6, 0.35 * n_plot_nonzero_shap)))
        shap.summary_plot(
            shap_values_nonzero,
            test_X_processed_nonzero,
            feature_names=nonzero_feature_clean,
            max_display=n_plot_nonzero_shap,
            show=False
        )
        plt.gcf().set_size_inches(12, max(8, 0.35 * n_plot_nonzero_shap))
        plt.title(f"SHAP Beeswarm Plot (> 0 Features Only) for Test Set ({model_name})")
        plt.tight_layout()

        output_path_shap_beeswarm_nonzero = f"../outputs/{model_name}_shap_beeswarm_nonzero_all.pdf"
        plt.savefig(
            output_path_shap_beeswarm_nonzero,
            bbox_inches="tight"
        )
        plt.close()

        print(f"Beeswarm plot saved to: {output_path_shap_beeswarm_nonzero}")
    else:
        print("No SHAP beeswarm (>0 only) plot generated because n_plot_nonzero_shap = 0.")

    # -------------------------------
    # Rank comparison between df and SHAP importance
    # -------------------------------
    shap_features_ranked = shap_importance_nonzero_sorted["feature"].tolist()
    min_len_shap = min(len(df_predictors), len(shap_features_ranked))

    comparison_rows = []
    for i in range(min_len_shap):
        df_pred = df_predictors[i]
        shap_feat = shap_features_ranked[i]

        comparison_rows.append({
            "rank": i + 1,
            "df_predictor": df_pred,
            "shap_feature": shap_feat,
            "same": df_pred == shap_feat
        })

    comparison_df_shap = pd.DataFrame(comparison_rows)

    num_same_shap = comparison_df_shap["same"].sum() if not comparison_df_shap.empty else 0
    total_shap = len(comparison_df_shap)

    print(comparison_df_shap)
    print("Number of same predictors at the same rank:", num_same_shap)
    print("Total compared ranks:", total_shap)
    print("Match ratio:", round(num_same_shap / total_shap, 4) if total_shap > 0 else np.nan)

    print("Matched at same rank:")
    print(comparison_df_shap[comparison_df_shap["same"]]) if total_shap > 0 else print("None")

    print("Not matched at same rank:")
    print(comparison_df_shap[~comparison_df_shap["same"]]) if total_shap > 0 else print("None")

    common_features_shap = set(df_predictors).intersection(set(shap_features_ranked))
    print("Number of common features regardless of rank:", len(common_features_shap))
    print(sorted(common_features_shap))

    comparison_df_shap.to_csv(
        f"../outputs/{model_name}_df_vs_shap_rank_comparison.csv",
        index=False
    )
    print(f"Saved to: ../outputs/{model_name}_df_vs_shap_rank_comparison.csv")

    # -------------------------------
    # Compare XGBoost vs SHAP (nonzero) by rank
    # -------------------------------
    xgb_ranked_nonzero = (
        xgb_importance[xgb_importance["native_importance"] > 0]
        .sort_values("native_importance", ascending=False)
        .reset_index(drop=True)
    )

    shap_ranked_nonzero = (
        shap_importance[shap_importance["shap_mean_abs"] > 0]
        .sort_values("shap_mean_abs", ascending=False)
        .reset_index(drop=True)
    )

    xgb_features_ranked_nonzero = xgb_ranked_nonzero["feature"].tolist()
    shap_features_ranked_nonzero = shap_ranked_nonzero["feature"].tolist()

    max_len = max(len(xgb_features_ranked_nonzero), len(shap_features_ranked_nonzero))

    comparison_rows = []
    for i in range(max_len):
        xgb_feat = xgb_features_ranked_nonzero[i] if i < len(xgb_features_ranked_nonzero) else None
        shap_feat = shap_features_ranked_nonzero[i] if i < len(shap_features_ranked_nonzero) else None

        comparison_rows.append({
            "rank": i + 1,
            "xgb_feature": xgb_feat,
            "shap_feature": shap_feat,
            "same": xgb_feat == shap_feat
        })

    xgb_vs_shap_rank_df = pd.DataFrame(comparison_rows)

    print("=== XGBoost importance (>0) vs SHAP importance (>0): rank comparison ===")
    print(xgb_vs_shap_rank_df)

    print("Number of same features at the same rank:", xgb_vs_shap_rank_df["same"].sum())
    print("Total compared ranks:", len(xgb_vs_shap_rank_df))

    print("Matched at same rank:")
    print(xgb_vs_shap_rank_df[xgb_vs_shap_rank_df["same"]])

    print("Not matched at same rank:")
    print(xgb_vs_shap_rank_df[~xgb_vs_shap_rank_df["same"]])

    common_features_xgb_shap = set(xgb_features_ranked_nonzero).intersection(set(shap_features_ranked_nonzero))
    print("Number of common features regardless of rank:", len(common_features_xgb_shap))
    print(sorted(common_features_xgb_shap))

    only_in_xgb = set(xgb_features_ranked_nonzero) - set(shap_features_ranked_nonzero)
    only_in_shap = set(shap_features_ranked_nonzero) - set(xgb_features_ranked_nonzero)

    print("Features only in XGBoost importance (>0):", len(only_in_xgb))
    print(sorted(only_in_xgb))

    print("Features only in SHAP importance (>0):", len(only_in_shap))
    print(sorted(only_in_shap))

    xgb_vs_shap_rank_df.to_csv(
        f"../outputs/{model_name}_xgb_vs_shap_rank_comparison_nonzero.csv",
        index=False
    )
    print(f"Saved to: ../outputs/{model_name}_xgb_vs_shap_rank_comparison_nonzero.csv")


# -------------------------------
# Run analysis for both files
# -------------------------------
run_analysis(df_model1, "stable_predictors_model1_all_vars")
run_analysis(df_model2, "stable_predictors_model2_no_age_sysbp")
