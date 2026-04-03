README.txt

Task: UKB XGBoost Modeling Pipeline

---

## Directory Structure

1. script/

   * Contains Python scripts for XGBoost modeling.
   * Main script performs:
     • data loading
     • preprocessing with scaling and one-hot encoding
     • class imbalance checking
     • XGBoost grid search
     • final model training
     • validation and test evaluation
     • ROC and confusion matrix plotting
     • feature importance analysis
     • SHAP interpretation
     • ranking comparison across feature selection methods

2. log/

   * Contains HPC execution logs.
   * Includes:
     • job submission and runtime records
     • memory and CPU/GPU usage
     • CUDA environment information
     • console outputs during grid search and model fitting
     • debugging or error messages when applicable

3. output/

   * Contains generated dataframes, model files, and figures.
   * Includes examples such as:
     • xgb_grid_search_results.csv
     • xgb_best_params.json
     • best_xgb_model.json
     • xgb_roc_curves.png
     • xgb_cm
     • cumulativefeature_importance.png
     • xgb_importance_nonzero_ranked.csv
     • xgb_feature_importance_nonzero_all.png
     • xgb_feature_importance_nonzero_top_minlen_vs_df.png
     • shap_importance_nonzero_ranked.csv
     • shap_importance_bar_topn.png
     • shap_summary_topn.png
     • shap_importance_nonzero_all.png
     • shap_beeswarm_nonzero_all.png
     • df_vs_xgb_rank_feature_importance_comparison.csv
     • df_vs_shap_rank_comparison.csv
     • xgb_vs_shap_rank_comparison_nonzero.csv

---

## Script Description

Input:

* Correlation-filtered training, validation, and test datasets:
  • ukb_train_drop_correlation_score.csv
  • ukb_val_drop_correlation_score.csv
  • ukb_test_drop_correlation_score.csv

* Stable predictor reference file from stability selection and LASSO:
  • stable_predictors_calibrated_threshold_onehot.csv

Output:

* Saved XGBoost model and best hyperparameters
* Grid search results table
* Evaluation plots
* Feature importance tables
* SHAP interpretation plots
* Rank comparison tables

Processing Steps:

1. Load Data

   * Read training, validation, and test datasets from the correlation-analysis output directory.
   * Read the stable predictor file for later feature ranking comparison.

2. Basic Data Preparation

   * Convert selected cancer variables to categorical type.
   * Standardize column names to lowercase.
   * Separate outcome variable (cvd) from predictors.

3. Preprocessing

   * Detect numeric and categorical predictors using the training set.
   * Apply:
     • StandardScaler to numeric variables
     • OneHotEncoder to categorical variables
   * Fit preprocessing on the training set only, then transform validation and test sets.

4. Class Imbalance Check

   * Summarize class counts and proportions for CVD outcome.
   * Compute scale_pos_weight based on the training set.

5. Hyperparameter Grid Search

   * Run XGBoost grid search over combinations of:
     • n_estimators
     • learning_rate
     • max_depth
     • min_child_weight
     • subsample
     • colsample_bytree
     • reg_lambda
   * Evaluate each model using validation ROC-AUC.
   * Track timing, best performance, and parameter combinations.

6. Save Best Results

   * Save all grid search results as CSV.
   * Save best parameters as JSON.
   * Save best XGBoost model file.

7. Final Model Training

   * Reload best parameters.
   * Refit the final XGBoost classifier on the training set.
   * Evaluate performance on validation and test sets.

8. Model Evaluation

   * Compute ROC-AUC for validation and test sets.
   * Generate and save:
     • ROC curve plot
     • confusion matrix plot

9. Native XGBoost Feature Importance

   * Extract native feature importances from the final model.
   * Compute cumulative importance.
   * Identify the rank at which 50%, 90%, and 99% cumulative importance are reached.
   * Save ranked importance table and related plots.

10. Comparison with Stable Predictors

* Compare XGBoost importance ranking with predictors from the stable predictor file.
* Save rank-by-rank comparison results.

11. SHAP Interpretation

* Compute SHAP values on the test set.
* Calculate mean absolute SHAP importance.
* Save SHAP-ranked tables and plots, including:
  • SHAP bar plot
  • SHAP summary plot
  • SHAP nonzero importance bar plot
  • SHAP beeswarm plot for nonzero features only

12. Rank Comparison Across Methods

* Compare:
  • stable predictors vs SHAP ranking
  • XGBoost native importance vs SHAP importance
* Save CSV summaries of ranking agreement and mismatch.

---

## Methods Used

* XGBoost Classification:
  Gradient-boosted tree model for binary CVD prediction.

* Train-Based Preprocessing:
  Scaling and one-hot encoding are fitted on the training set only and then applied to validation and test sets.

* Grid Search:
  Hyperparameter tuning is performed using validation ROC-AUC.

* ROC-AUC Evaluation:
  Used as the main discrimination metric for model selection and testing.

* Confusion Matrix:
  Used to summarize final test-set classification results.

* Native Feature Importance:
  Uses built-in XGBoost feature importance values.

* SHAP:
  Uses SHAP values to quantify feature contribution and improve interpretability.

* Rank Comparison:
  Compares feature importance rankings across XGBoost, SHAP, and external stable predictor lists.

---

## Notes

* Preprocessing is based on the training set to reduce data leakage.
* Validation data are used for hyperparameter selection, while test data are reserved for final performance assessment.
* GPU usage is attempted through device="cuda" and is recorded in the logs if available.
* Outputs include both model and interpretation plots for downstream reporting.

---

## End of README
